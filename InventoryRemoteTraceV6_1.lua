--==============================================================
-- CAFEINA • INVENTORY REMOTE TRACE V6.1 PASSIVE SAFE
-- Pickup/drop correlator • no touch spam • original remotes run first
-- Executor/mobile • passive observation
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local C = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V6_1_PASSIVE_SAFE",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    RADIUS = 48,
    SCAN_INTERVAL = 0.50,
    SESSION_TIMEOUT = 8,
    MAX_RECORDS = 2000,
    MAX_REMOTES = 400,
    MAX_TRACKED = 140,
    MAX_INCOMING = 60,
    MAX_ARGS = 14,
    MAX_STRING = 700,
    RETRIES = 3,
    FOCUS_SECONDS = 8,
}

local KEYWORDS = {
    "crystal", "gem", "pickup", "collect", "inventory", "backpack",
    "bagid", "dropcrystal", "placecrystal", "digrequest"
}

local function low(v) return string.lower(tostring(v or "")) end
local function hasKeyword(v)
    local text = low(v)
    for _, word in ipairs(KEYWORDS) do
        if string.find(text, word, 1, true) then return true, word end
    end
    return false, nil
end

local function pathOf(obj)
    if not obj then return "nil" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj)
end

local function safe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" then return v end
    if t == "string" then
        return #v > C.MAX_STRING and string.sub(v, 1, C.MAX_STRING) .. "...[truncated]" or v
    end
    if t == "Vector3" or t == "Vector2" or t == "EnumItem" then return tostring(v) end
    if t == "CFrame" then return tostring(v.Position) end
    if t == "Instance" then
        return { type = "Instance", class = v.ClassName, name = v.Name, path = pathOf(v) }
    end
    if t == "table" then
        if depth >= 2 then return "<table>" end
        local out, n = {}, 0
        for k, value in pairs(v) do
            n += 1
            if n > C.MAX_ARGS then break end
            out[tostring(k)] = safe(value, depth + 1)
        end
        return out
    end
    return tostring(v)
end

local function argsOf(packed)
    local out = {}
    local n = math.min(tonumber(packed and packed.n) or #packed, C.MAX_ARGS)
    for i = 1, n do out[i] = safe(packed[i]) end
    return out
end

local function resolveRequest()
    local candidates = {
        ENV and ENV.request,
        ENV and ENV.http_request,
        request,
        http_request,
        syn and syn.request,
        http and http.request,
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then return fn end
    end
end

local REQUEST = resolveRequest()

local S = {
    running = false,
    seq = 0,
    sessionSeq = 0,
    startedAt = 0,
    finishedAt = 0,
    runId = "",
    focusUntil = 0,
    status = "aguardando",
    records = {},
    remotes = {},
    sessions = {},
    sessionsByCrystal = setmetatable({}, { __mode = "k" }),
    tracked = setmetatable({}, { __mode = "k" }),
    bagMap = {},
    lastDrop = nil,
    connections = {},
    incomingConnections = {},
    diagnostics = {
        version = C.VERSION,
        errors = {},
        health = { checked = false },
        transport = { endpoint = C.ENDPOINT, retries = C.RETRIES, status = "not_started" },
        counters = {
            records = 0, scans = 0, scanErrors = 0,
            crystalSeen = 0, crystalRemoved = 0,
            prompts = 0, toolAdded = 0, toolRemoved = 0,
            remoteOutgoing = 0, remoteIncoming = 0,
            dropAttempts = 0, dropWorldSeen = 0,
            sessions = 0, sessionsHigh = 0, sessionsMedium = 0, sessionsLow = 0,
            uploadAttempts = 0, droppedRecords = 0,
        },
        capabilities = {},
    },
}

local function err(phase, message)
    if #S.diagnostics.errors < 20 then
        S.diagnostics.errors[#S.diagnostics.errors + 1] = {
            unix = os.time(), phase = tostring(phase), error = tostring(message)
        }
    end
end

local function rec(data)
    if #S.records >= C.MAX_RECORDS then
        S.diagnostics.counters.droppedRecords += 1
        return nil
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = os.clock()
    data.unix = os.time()
    S.records[#S.records + 1] = data
    S.diagnostics.counters.records += 1
    return data
end

local function crystalRoot(obj)
    local cur = obj
    for _ = 1, 7 do
        if not cur then break end
        local parent = cur.Parent
        if parent and (parent.Name == "SpawnedGems" or parent.Name == "DroppedGems") then
            return cur
        end
        cur = parent
    end
end

local function crystalSnapshot(crystal, part)
    if not crystal then return nil end
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local pos
    pcall(function()
        if crystal:IsA("Model") then pos = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos = crystal.Position
        elseif part and part:IsA("BasePart") then pos = part.Position end
    end)
    local attrs = {}
    pcall(function()
        for k, v in pairs(crystal:GetAttributes()) do attrs[k] = safe(v) end
    end)
    return {
        name = crystal.Name,
        class = crystal.ClassName,
        path = pathOf(crystal),
        position = pos and tostring(pos) or nil,
        distance = (pos and root) and (root.Position - pos).Magnitude or nil,
        attributes = attrs,
    }
end

local function latestPending(maxAge)
    local now = os.clock()
    for i = #S.sessions, 1, -1 do
        local session = S.sessions[i]
        if not session.finalized and now <= session.expiresAt then
            if not maxAge or now - session.startedClock <= maxAge then return session end
        end
    end
end

local function sessionForCrystal(crystal, create, kind, trigger)
    if crystal then
        local current = S.sessionsByCrystal[crystal]
        if current and not current.finalized and os.clock() <= current.expiresAt then return current end
    end
    if not create then return nil end
    S.sessionSeq += 1
    local session = {
        id = string.format("pickup-%03d", S.sessionSeq),
        crystalRef = crystal,
        crystalName = crystal and crystal.Name or nil,
        crystalBefore = crystalSnapshot(crystal),
        triggerKind = kind,
        trigger = safe(trigger),
        startedClock = os.clock(),
        startedUnix = os.time(),
        expiresAt = os.clock() + C.SESSION_TIMEOUT,
        prompt = nil,
        backpackAdded = {},
        worldRemoved = {},
        confirmations = {},
        incoming = {},
        outgoing = {},
        finalized = false,
    }
    S.sessions[#S.sessions + 1] = session
    if crystal then S.sessionsByCrystal[crystal] = session end
    S.diagnostics.counters.sessions += 1
    return session
end

local function finishSession(session, reason)
    if not session or session.finalized then return end
    session.finalized = true
    session.finishedClock = os.clock()
    session.finishedUnix = os.time()
    session.finishReason = reason or "completed"
    local p = session.prompt ~= nil
    local b = #session.backpackAdded > 0
    local w = #session.worldRemoved > 0
    local c = #session.confirmations > 0
    local score = (p and 1 or 0) + (b and 1 or 0) + (w and 1 or 0) + (c and 1 or 0)
    session.pickupCorrelated = p and b and w
    session.confidence = score >= 4 and "high" or score >= 3 and "medium" or "low"
    session.summary = {
        promptObserved = p,
        backpackAdditionObserved = b,
        worldRemovalObserved = w,
        serverConfirmationObserved = c,
        pickupCorrelated = session.pickupCorrelated,
        confidence = session.confidence,
        bagIds = {},
    }
    for _, event in ipairs(session.backpackAdded) do
        local id = event.tool and event.tool.attributes and event.tool.attributes.BagId
        if id ~= nil then session.summary.bagIds[#session.summary.bagIds + 1] = id end
    end
    if session.confidence == "high" then S.diagnostics.counters.sessionsHigh += 1
    elseif session.confidence == "medium" then S.diagnostics.counters.sessionsMedium += 1
    else S.diagnostics.counters.sessionsLow += 1 end
end

local function maybeFinish(session)
    if session and not session.finalized and session.prompt and #session.backpackAdded > 0 and #session.worldRemoved > 0 and #session.confirmations > 0 then
        finishSession(session, "full_chain")
    end
end

local function trackCrystal(crystal, part)
    if not crystal or S.tracked[crystal] then return end
    local count = 0
    for _ in pairs(S.tracked) do count += 1 end
    if count >= C.MAX_TRACKED then return end

    local snap = crystalSnapshot(crystal, part)
    S.tracked[crystal] = { snapshot = snap, removed = false }
    S.diagnostics.counters.crystalSeen += 1
    rec({ kind = "crystal_world_seen", crystal = snap })

    if crystal.Parent and crystal.Parent.Name == "DroppedGems" and S.lastDrop and os.clock() - S.lastDrop.clock <= 3.5 then
        S.diagnostics.counters.dropWorldSeen += 1
        rec({
            kind = "drop_world_seen",
            bagId = S.lastDrop.bagId,
            expectedGemName = S.lastDrop.gemName,
            crystal = snap,
            dropConfirmedByWorld = (not S.lastDrop.gemName) or S.lastDrop.gemName == crystal.Name,
        })
    end

    local conn = crystal.AncestryChanged:Connect(function()
        if not S.running then return end
        local inside = false
        pcall(function() inside = crystal:IsDescendantOf(Workspace) end)
        if inside then return end
        local tracked = S.tracked[crystal]
        if not tracked or tracked.removed then return end
        tracked.removed = true
        S.diagnostics.counters.crystalRemoved += 1
        local event = rec({ kind = "crystal_world_removed", crystal = tracked.snapshot, replication = true })
        local session = sessionForCrystal(crystal, true, "world_removed", tracked.snapshot)
        if event and session then
            event.sessionId = session.id
            session.worldRemoved[#session.worldRemoved + 1] = event
            session.expiresAt = os.clock() + 2
            maybeFinish(session)
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local function scanNearby()
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { char }
    overlap.MaxParts = 160
    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInRadius(root.Position, C.RADIUS, overlap)
    end)
    S.diagnostics.counters.scans += 1
    if not ok then
        S.diagnostics.counters.scanErrors += 1
        err("nearby_scan", parts)
        return
    end
    for _, part in ipairs(parts) do
        local crystal = crystalRoot(part)
        if crystal then trackCrystal(crystal, part) end
    end
end

local function toolSnapshot(tool)
    local attrs = {}
    pcall(function()
        for k, v in pairs(tool:GetAttributes()) do attrs[k] = safe(v) end
    end)
    return { name = tool.Name, path = pathOf(tool), attributes = attrs }
end

local function matchToolSession(tool)
    local gemName = tool.attributes and tool.attributes.GemName
    if gemName then
        for i = #S.sessions, 1, -1 do
            local session = S.sessions[i]
            if not session.finalized and session.crystalName == gemName and os.clock() <= session.expiresAt then return session end
        end
    end
    return latestPending(3)
end

local function watchContainer(container, label)
    if not container then return end
    local added = container.ChildAdded:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolAdded += 1
        local tool = toolSnapshot(obj)
        local bagId = tool.attributes and tool.attributes.BagId
        if bagId ~= nil then
            S.bagMap[tostring(bagId)] = {
                bagId = bagId,
                gemName = tool.attributes.GemName,
                kg = tool.attributes.Kg,
                value = tool.attributes.Value,
            }
        end
        local event = rec({ kind = "tool_added", container = label, tool = tool, replication = true })
        if label == "Backpack" and event then
            local session = matchToolSession(tool)
            if session then
                event.sessionId = session.id
                session.backpackAdded[#session.backpackAdded + 1] = event
                session.expiresAt = os.clock() + 3
                maybeFinish(session)
            end
        end
    end)
    local removed = container.ChildRemoved:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolRemoved += 1
        rec({ kind = "tool_removed", container = label, tool = { name = obj.Name, path = pathOf(obj) } })
    end)
    S.connections[#S.connections + 1] = added
    S.connections[#S.connections + 1] = removed
end

local function installTools()
    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")
    local conn = LP.CharacterAdded:Connect(function(char)
        if S.running then watchContainer(char, "Character") end
    end)
    S.connections[#S.connections + 1] = conn
end

local function installPrompts()
    local conn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not S.running or (player and player ~= LP) then return end
        local crystal = crystalRoot(prompt)
        if not crystal then return end
        S.diagnostics.counters.prompts += 1
        local event = rec({
            kind = "prompt_triggered",
            prompt = pathOf(prompt),
            actionText = prompt.ActionText,
            objectText = prompt.ObjectText,
            crystal = crystalSnapshot(crystal),
        })
        local session = sessionForCrystal(crystal, true, "prompt", event)
        if event and session then
            event.sessionId = session.id
            session.prompt = event
            session.expiresAt = os.clock() + C.SESSION_TIMEOUT
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local IMPORTANT_INCOMING = {
    GemCollected = true,
    InventoryChanged = true,
    MineHit = true,
    DigResult = true,
}

local function sessionForIncoming(remote, packed)
    if remote.Name == "GemCollected" or remote.Name == "MineHit" then
        local possiblePlayer = packed[2]
        if remote.Name == "GemCollected" and typeof(possiblePlayer) == "Instance" and possiblePlayer:IsA("Player") and possiblePlayer ~= LP then
            return nil
        end
        for i = 1, math.min(packed.n or #packed, C.MAX_ARGS) do
            local value = packed[i]
            if typeof(value) == "Instance" then
                local crystal = crystalRoot(value) or value
                local session = S.sessionsByCrystal[crystal]
                if session and not session.finalized then return session end
            end
        end
    end
    if remote.Name == "InventoryChanged" then return latestPending(3) end
    return latestPending(2)
end

local function installIncoming()
    local count = 0
    for _, rootName in ipairs({ "GemSignals", "GemRemotes", "DigRemotes", "PlotRemotes" }) do
        local root = ReplicatedStorage:FindFirstChild(rootName)
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if count >= C.MAX_INCOMING then break end
                if (obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent")) and IMPORTANT_INCOMING[obj.Name] then
                    count += 1
                    local remote = obj
                    local conn = remote.OnClientEvent:Connect(function(...)
                        if not S.running then return end
                        S.diagnostics.counters.remoteIncoming += 1
                        local packed = table.pack(...)
                        local event = rec({
                            kind = "remote_incoming",
                            remote = pathOf(remote),
                            class = remote.ClassName,
                            arguments = argsOf(packed),
                            replication = true,
                        })
                        local session = sessionForIncoming(remote, packed)
                        if event and session then
                            event.sessionId = session.id
                            session.incoming[#session.incoming + 1] = event
                            if remote.Name == "GemCollected" or remote.Name == "InventoryChanged" then
                                session.confirmations[#session.confirmations + 1] = event
                            end
                            session.expiresAt = math.max(session.expiresAt, os.clock() + 2)
                            maybeFinish(session)
                        end
                    end)
                    S.incomingConnections[#S.incomingConnections + 1] = conn
                end
            end
        end
    end
end

local function isRemote(obj)
    return typeof(obj) == "Instance" and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent"))
end

local function observeOutgoing(remote, method, packed, response)
    if not S.running then return end
    S.diagnostics.counters.remoteOutgoing += 1
    local remotePath = pathOf(remote)
    local relevant = hasKeyword(remotePath) or os.clock() <= S.focusUntil
    if not relevant then return end

    local info = S.remotes[remotePath]
    if not info then
        local n = 0
        for _ in pairs(S.remotes) do n += 1 end
        if n < C.MAX_REMOTES then
            info = { path = remotePath, class = remote.ClassName, outgoing = 0, samples = 0, firstSeen = os.clock() }
            S.remotes[remotePath] = info
        end
    end
    if info then info.outgoing += 1; info.samples += 1 end

    local data = {
        kind = "remote_outgoing",
        remote = remotePath,
        class = remote.ClassName,
        method = method,
        relevant = true,
        arguments = argsOf(packed),
        observedAfterForward = true,
    }
    if response then data.response = argsOf(response) end

    if remote.Name == "DropCrystal" then
        local bagId = packed[1]
        local known = S.bagMap[tostring(bagId)]
        S.diagnostics.counters.dropAttempts += 1
        data.kind = "drop_attempt"
        data.bagId = safe(bagId)
        data.knownItem = known and safe(known) or nil
        S.lastDrop = { clock = os.clock(), bagId = bagId, gemName = known and known.gemName or nil }
    end

    local event = rec(data)
    local session = latestPending(3)
    if event and session then
        event.sessionId = session.id
        session.outgoing[#session.outgoing + 1] = event
    end
end

-- Disable handlers left by older Cafeina trace versions in this same executor session.
for _, key in ipairs({ "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V5", "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V6" }) do
    local oldDispatch = rawget(ENV, key)
    if type(oldDispatch) == "table" then oldDispatch.handler = nil end
end

local DISPATCH_KEY = "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V61"
local dispatch = rawget(ENV, DISPATCH_KEY)

local function installSafeHook()
    if type(dispatch) ~= "table" and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
        dispatch = { handler = nil }
        local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
        local old
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            local handler = dispatch.handler
            if handler and isRemote(self) and (method == "FireServer" or method == "InvokeServer") then
                local packed = table.pack(...)
                -- Critical rule: the game's original remote call happens FIRST.
                local result = table.pack(old(self, ...))
                task.defer(function()
                    pcall(handler, self, method, packed, method == "InvokeServer" and result or nil)
                end)
                return table.unpack(result, 1, result.n)
            end
            return old(self, ...)
        end))
        ENV[DISPATCH_KEY] = dispatch
    end
    if type(dispatch) == "table" then
        dispatch.handler = observeOutgoing
        return true
    end
    err("capture", "hookmetamethod/getnamecallmethod indisponivel")
    return false
end

local function disconnectAll()
    for _, conn in ipairs(S.connections) do pcall(function() conn:Disconnect() end) end
    for _, conn in ipairs(S.incomingConnections) do pcall(function() conn:Disconnect() end) end
    S.connections = {}
    S.incomingConnections = {}
    if type(dispatch) == "table" then dispatch.handler = nil end
end

local function http(options)
    if not REQUEST then return false, nil, "request/http_request indisponivel" end
    local ok, response = pcall(REQUEST, options)
    if not ok or not response then return false, nil, tostring(response) end
    local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body = tostring(response.Body or response.body or "")
    return status >= 200 and status < 300, { status = status, body = body }, nil
end

local function health()
    S.diagnostics.health.checked = true
    local ok, response, message = http({
        Url = C.HEALTH,
        Method = "GET",
        Headers = { Accept = "application/json", ["Cache-Control"] = "no-cache" },
    })
    if not ok then
        S.diagnostics.health.ok = false
        S.diagnostics.health.error = message or "health_failed"
        return
    end
    S.diagnostics.health.ok = true
    S.diagnostics.health.httpStatus = response.status
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, response.body)
    if decodeOk and type(data) == "table" then
        S.diagnostics.health.githubMirrorConfigured = data.githubMirrorConfigured
        S.diagnostics.health.maxRecords = data.maxRecords
        S.diagnostics.health.maxRemotes = data.maxRemotes
    end
end

local function remotesList()
    local out = {}
    for _, value in pairs(S.remotes) do out[#out + 1] = value end
    table.sort(out, function(a, b) return (a.firstSeen or 0) < (b.firstSeen or 0) end)
    return out
end

local function buildPayload()
    S.diagnostics.transport.status = "pending_at_send"
    S.diagnostics.operation = {
        startedAt = S.startedAt,
        finishedAt = S.finishedAt,
        durationSeconds = math.max(0, S.finishedAt - S.startedAt),
        records = #S.records,
        sessions = #S.sessions,
        bagIdsKnown = (function() local n=0 for _ in pairs(S.bagMap) do n+=1 end return n end)(),
        passiveSafeHook = true,
        touchWatcher = false,
    }
    return {
        schemaVersion = 1,
        userId = tostring(LP.UserId),
        username = LP.Name,
        capturedAt = DateTime.now():ToIsoDate(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = S.runId,
        trace = {
            version = C.VERSION,
            purpose = "crystal_pickup_drop_correlation",
            runId = S.runId,
            startedAt = S.startedAt,
            finishedAt = S.finishedAt,
            records = S.records,
            remotes = remotesList(),
            pickupSessions = S.sessions,
            bagMap = S.bagMap,
            diagnostics = S.diagnostics,
        },
    }
end

local function saveLocal(name, text)
    if type(writefile) ~= "function" then return false end
    local ok, message = pcall(writefile, name, text)
    if not ok then err("writefile", message) end
    return ok
end

local function upload(payload)
    local encodeOk, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not encodeOk then return false, nil, "json_encode_failed" end
    local name = string.format("Cafeina_PickupDrop_%s_%d.json", tostring(game.PlaceId), os.time())
    saveLocal(name, body)

    for attempt = 1, C.RETRIES do
        S.diagnostics.counters.uploadAttempts += 1
        S.diagnostics.transport.status = "sending"
        local ok, response, message = http({
            Url = C.ENDPOINT,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
            Body = body,
        })
        if ok then
            local receipt
            pcall(function() receipt = HttpService:JSONDecode(response.body) end)
            S.diagnostics.transport.status = "accepted"
            S.diagnostics.transport.serverAccepted = true
            S.diagnostics.transport.httpStatus = response.status
            S.diagnostics.transport.githubConfigured = receipt and receipt.github and receipt.github.configured or false
            S.diagnostics.transport.githubMirrored = receipt and receipt.github and receipt.github.mirrored or false
            S.diagnostics.transport.latestUrl = receipt and receipt.latestUrl or nil
            local receiptText
            pcall(function() receiptText = HttpService:JSONEncode({ payload = payload, receipt = receipt }) end)
            if receiptText then saveLocal(string.gsub(name, "%.json$", "_receipt.json"), receiptText) end
            return true, receipt
        end
        S.diagnostics.transport.lastError = message or (response and ("HTTP " .. tostring(response.status))) or "upload_failed"
        S.diagnostics.transport.status = "retrying"
        task.wait(attempt * 1.5)
    end
    S.diagnostics.transport.status = "failed"
    S.diagnostics.transport.serverAccepted = false
    return false, nil, S.diagnostics.transport.lastError
end

local function start()
    if S.running then return end
    S.running = true
    S.startedAt = os.time()
    S.finishedAt = 0
    S.runId = HttpService:GenerateGUID(false)
    S.status = "capturando • passive-safe"
    S.diagnostics.capabilities = {
        request = REQUEST ~= nil,
        writefile = type(writefile) == "function",
        setclipboard = type(setclipboard) == "function",
        hookmetamethod = type(hookmetamethod) == "function",
        getnamecallmethod = type(getnamecallmethod) == "function",
        prompt = true,
        spatial = true,
        touchWatcher = false,
        originalRemoteFirst = true,
    }
    task.spawn(health)
    installTools()
    installPrompts()
    installIncoming()
    installSafeHook()
    task.spawn(function()
        while S.running do
            scanNearby()
            for _, session in ipairs(S.sessions) do
                if not session.finalized and os.clock() > session.expiresAt then finishSession(session, "timeout") end
            end
            task.wait(C.SCAN_INTERVAL)
        end
    end)
end

local function stopAndSend()
    if not S.running then return false, nil, "not_running" end
    S.running = false
    S.finishedAt = os.time()
    disconnectAll()
    for _, session in ipairs(S.sessions) do
        if not session.finalized then finishSession(session, "scan_stopped") end
    end
    S.status = "enviando"
    local ok, receipt, message = upload(buildPayload())
    if ok then
        S.status = (receipt and receipt.github and receipt.github.mirrored) and "ENVIADO + GITHUB ✓" or "RENDER RECEBEU • GITHUB PENDENTE"
    else
        S.status = "ENVIO FALHOU • backup preservado"
    end
    return ok, receipt, message
end

--============================== UI ==============================
local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceV61"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(292, 210)
frame.Position = UDim2.new(0.5, -146, 0.16, 0)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -18, 0, 30)
title.Position = UDim2.fromOffset(9, 7)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • TRACE V6.1 PASSIVE SAFE"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -18, 0, 52)
status.Position = UDim2.fromOffset(9, 38)
status.BackgroundColor3 = Color3.fromRGB(22,22,25)
status.TextColor3 = Color3.fromRGB(220,220,225)
status.TextSize = 10
status.Font = Enum.Font.Code
status.TextWrapped = true
status.Text = "Status: aguardando"
status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

local function button(text, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -18, 0, 32)
    b.Position = UDim2.fromOffset(9, y)
    b.BackgroundColor3 = Color3.fromRGB(38,38,43)
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local startBtn = button("INICIAR SCAN", 96)
local focusBtn = button("MARCAR JANELA • 8s", 133)
local stopBtn = button("PARAR + ENVIAR", 170)
stopBtn.BackgroundColor3 = Color3.fromRGB(108,25,31)

startBtn.MouseButton1Click:Connect(start)
focusBtn.MouseButton1Click:Connect(function()
    S.focusUntil = os.clock() + C.FOCUS_SECONDS
    S.status = "janela marcada por 8s"
end)
stopBtn.MouseButton1Click:Connect(function()
    if S.running then task.spawn(stopAndSend) end
end)

task.spawn(function()
    while gui.Parent do
        local c = S.diagnostics.counters
        status.Text = string.format(
            "Status: %s\nReg: %d • Sess: %d • High: %d\nDrop: %d • DropWorld: %d • IN: %d",
            S.status, c.records, c.sessions, c.sessionsHigh, c.dropAttempts, c.dropWorldSeen, c.remoteIncoming
        )
        task.wait(0.35)
    end
end)

return {
    Start = start,
    StopAndSend = stopAndSend,
    State = S,
    Version = C.VERSION,
}
