--==============================================================
-- CAFEINA • INVENTORY REMOTE TRACE V6
-- PICKUP SESSION CORRELATOR + TRANSPORT DIAGNOSTICS
-- Executor/mobile • passive observation • PlaceId agnostic
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CONFIG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V6_PICKUP_SESSIONS",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    RADIUS = 55,
    SCAN_INTERVAL = 0.35,
    SESSION_TIMEOUT = 10,
    PREBUFFER_SECONDS = 2.5,
    MAX_RECORDS = 2200,
    MAX_REMOTES = 500,
    MAX_TRACKED_CRYSTALS = 180,
    MAX_INCOMING_REMOTES = 80,
    MAX_ARGS = 16,
    MAX_STRING = 800,
    RETRIES = 3,
    FOCUS_SECONDS = 8,
}

local KEYWORDS = {
    "crystal", "gem", "pickup", "pick up", "collect", "claim", "take", "grab",
    "inventory", "backpack", "bagid", "drop", "place", "mine"
}

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function containsKeyword(text)
    text = lower(text)
    for _, word in ipairs(KEYWORDS) do
        if string.find(text, word, 1, true) then
            return true, word
        end
    end
    return false, nil
end

local function pathOf(obj)
    if not obj then return "nil" end
    local ok, full = pcall(function() return obj:GetFullName() end)
    return ok and full or tostring(obj)
end

local function safeValue(v, depth)
    depth = depth or 0
    local tv = typeof(v)
    if tv == "nil" or tv == "boolean" or tv == "number" then return v end
    if tv == "string" then
        if #v > CONFIG.MAX_STRING then return string.sub(v, 1, CONFIG.MAX_STRING) .. "...[truncated]" end
        return v
    end
    if tv == "Vector3" then return tostring(v) end
    if tv == "Vector2" then return tostring(v) end
    if tv == "CFrame" then return tostring(v.Position) end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "Instance" then
        return { type = "Instance", class = v.ClassName, name = v.Name, path = pathOf(v) }
    end
    if tv == "table" then
        if depth >= 2 then return "<table>" end
        local out, count = {}, 0
        for k, value in pairs(v) do
            count += 1
            if count > CONFIG.MAX_ARGS then break end
            out[tostring(k)] = safeValue(value, depth + 1)
        end
        return out
    end
    return tostring(v)
end

local function packArgs(packed)
    local out = {}
    local n = math.min(tonumber(packed and packed.n) or #packed, CONFIG.MAX_ARGS)
    for i = 1, n do out[i] = safeValue(packed[i]) end
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
    return nil
end

local REQUEST = resolveRequest()

local STATE = {
    running = false,
    seq = 0,
    sessionSeq = 0,
    startedAt = 0,
    finishedAt = 0,
    focusUntil = 0,
    records = {},
    remotes = {},
    connections = {},
    incomingConnections = {},
    tracked = setmetatable({}, { __mode = "k" }),
    sessionsByCrystal = setmetatable({}, { __mode = "k" }),
    sessions = {},
    recent = {},
    status = "aguardando",
    diagnostics = {
        version = CONFIG.VERSION,
        errors = {},
        capabilities = {},
        counters = {
            records = 0,
            scans = 0,
            scanErrors = 0,
            crystalSeen = 0,
            crystalRemoved = 0,
            prompts = 0,
            touch = 0,
            toolAdded = 0,
            toolRemoved = 0,
            remoteOutgoing = 0,
            remoteIncoming = 0,
            sessions = 0,
            sessionsHigh = 0,
            sessionsMedium = 0,
            sessionsLow = 0,
            uploadAttempts = 0,
            droppedRecords = 0,
        },
        health = { checked = false },
        transport = {
            endpoint = CONFIG.ENDPOINT,
            status = "not_started",
            retries = CONFIG.RETRIES,
        },
    }
}

local function addError(phase, err)
    STATE.diagnostics.errors[#STATE.diagnostics.errors + 1] = {
        unix = os.time(), phase = tostring(phase), error = tostring(err)
    }
end

local function record(data)
    if #STATE.records >= CONFIG.MAX_RECORDS then
        STATE.diagnostics.counters.droppedRecords += 1
        return nil
    end
    STATE.seq += 1
    data.seq = STATE.seq
    data.clock = os.clock()
    data.unix = os.time()
    STATE.records[#STATE.records + 1] = data
    STATE.recent[#STATE.recent + 1] = data
    while #STATE.recent > 80 do table.remove(STATE.recent, 1) end
    STATE.diagnostics.counters.records += 1
    return data
end

local function snapshotCrystal(crystal, part)
    if not crystal then return nil end
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local pos
    pcall(function()
        if crystal:IsA("Model") then pos = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos = crystal.Position
        elseif part and part:IsA("BasePart") then pos = part.Position end
    end)
    local distance
    if pos and root then distance = (root.Position - pos).Magnitude end
    local attributes = {}
    pcall(function()
        for k, v in pairs(crystal:GetAttributes()) do
            if containsKeyword(k) or k == "Id" or k == "ID" then attributes[k] = safeValue(v) end
        end
    end)
    return {
        name = crystal.Name,
        class = crystal.ClassName,
        path = pathOf(crystal),
        position = pos and tostring(pos) or nil,
        distance = distance,
        attributes = attributes,
    }
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
    return nil
end

local function sessionForCrystal(crystal, create, triggerKind, triggerData)
    if crystal then
        local existing = STATE.sessionsByCrystal[crystal]
        if existing and not existing.finalized and os.clock() <= existing.expiresAt then
            return existing
        end
    end
    if not create then return nil end

    STATE.sessionSeq += 1
    local session = {
        id = string.format("pickup-%03d", STATE.sessionSeq),
        crystalRef = crystal,
        crystalBefore = snapshotCrystal(crystal),
        crystalName = crystal and crystal.Name or nil,
        triggerKind = triggerKind,
        trigger = safeValue(triggerData),
        startedClock = os.clock(),
        startedUnix = os.time(),
        expiresAt = os.clock() + CONFIG.SESSION_TIMEOUT,
        prompt = nil,
        outgoing = {},
        incoming = {},
        backpackAdded = {},
        worldRemoved = {},
        confirmations = {},
        finalized = false,
    }
    STATE.sessions[#STATE.sessions + 1] = session
    if crystal then STATE.sessionsByCrystal[crystal] = session end
    STATE.diagnostics.counters.sessions += 1

    local cutoff = os.clock() - CONFIG.PREBUFFER_SECONDS
    for i = #STATE.recent, 1, -1 do
        local r = STATE.recent[i]
        if (r.clock or 0) < cutoff then break end
        if r.kind == "remote_outgoing" then
            session.outgoing[#session.outgoing + 1] = r
        end
    end
    return session
end

local function latestSessionByName(name)
    name = tostring(name or "")
    for i = #STATE.sessions, 1, -1 do
        local s = STATE.sessions[i]
        if not s.finalized and os.clock() <= s.expiresAt then
            if name == "" or s.crystalName == name then return s end
        end
    end
    return nil
end

local function finalizeSession(s, reason)
    if not s or s.finalized then return end
    s.finalized = true
    s.finishedClock = os.clock()
    s.finishedUnix = os.time()
    s.finishReason = reason or "completed"
    local hasPrompt = s.prompt ~= nil
    local hasTool = #s.backpackAdded > 0
    local hasRemoval = #s.worldRemoved > 0
    local hasConfirmation = #s.confirmations > 0
    local score = (hasPrompt and 1 or 0) + (hasTool and 1 or 0) + (hasRemoval and 1 or 0) + (hasConfirmation and 1 or 0)
    s.pickupCorrelated = hasPrompt and hasTool and hasRemoval
    s.confidence = score >= 4 and "high" or score >= 3 and "medium" or "low"
    s.summary = {
        promptObserved = hasPrompt,
        backpackAdditionObserved = hasTool,
        worldRemovalObserved = hasRemoval,
        serverConfirmationObserved = hasConfirmation,
        pickupCorrelated = s.pickupCorrelated,
        confidence = s.confidence,
        bagIds = {},
    }
    for _, item in ipairs(s.backpackAdded) do
        local id = item.tool and item.tool.attributes and item.tool.attributes.BagId
        if id ~= nil then s.summary.bagIds[#s.summary.bagIds + 1] = id end
    end
    if s.confidence == "high" then STATE.diagnostics.counters.sessionsHigh += 1
    elseif s.confidence == "medium" then STATE.diagnostics.counters.sessionsMedium += 1
    else STATE.diagnostics.counters.sessionsLow += 1 end
end

local function maybeFinalize(s)
    if not s or s.finalized then return end
    if s.prompt and #s.backpackAdded > 0 and #s.worldRemoved > 0 and #s.confirmations > 0 then
        finalizeSession(s, "full_chain")
    end
end

local function trackCrystal(crystal, part)
    if not crystal or STATE.tracked[crystal] then return end
    local trackedCount = 0
    for _ in pairs(STATE.tracked) do trackedCount += 1 end
    if trackedCount >= CONFIG.MAX_TRACKED_CRYSTALS then return end

    local snap = snapshotCrystal(crystal, part)
    STATE.tracked[crystal] = { snapshot = snap, removed = false }
    STATE.diagnostics.counters.crystalSeen += 1
    record({ kind = "crystal_world_seen", crystal = snap })

    local ancestry = crystal.AncestryChanged:Connect(function()
        if not STATE.running then return end
        local inside = false
        pcall(function() inside = crystal:IsDescendantOf(Workspace) end)
        if inside then return end
        local t = STATE.tracked[crystal]
        if not t or t.removed then return end
        t.removed = true
        STATE.diagnostics.counters.crystalRemoved += 1
        local r = record({ kind = "crystal_world_removed", crystal = t.snapshot, replication = true })
        local s = sessionForCrystal(crystal, true, "world_removed", t.snapshot)
        if r and s then
            r.sessionId = s.id
            s.worldRemoved[#s.worldRemoved + 1] = r
            s.expiresAt = os.clock() + 2
            maybeFinalize(s)
        end
    end)
    STATE.connections[#STATE.connections + 1] = ancestry

    if part and part:IsA("BasePart") then
        local touch = part.Touched:Connect(function(hit)
            if not STATE.running then return end
            local char = LP.Character
            if not char or not hit or not hit:IsDescendantOf(char) then return end
            STATE.diagnostics.counters.touch += 1
            local r = record({ kind = "crystal_touch", crystal = snap, touched = pathOf(part), characterPart = hit.Name })
            local s = sessionForCrystal(crystal, false)
            if r and s then r.sessionId = s.id end
        end)
        STATE.connections[#STATE.connections + 1] = touch
    end
end

local function scanNearby()
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { char }
    overlap.MaxParts = 180
    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInRadius(root.Position, CONFIG.RADIUS, overlap)
    end)
    STATE.diagnostics.counters.scans += 1
    if not ok then
        STATE.diagnostics.counters.scanErrors += 1
        addError("nearby_scan", parts)
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
        for k, v in pairs(tool:GetAttributes()) do attrs[k] = safeValue(v) end
    end)
    return { name = tool.Name, path = pathOf(tool), attributes = attrs }
end

local function matchSessionForTool(toolData)
    local gemName = toolData.attributes and toolData.attributes.GemName
    if gemName then
        local s = latestSessionByName(gemName)
        if s then return s end
    end
    return latestSessionByName("")
end

local function watchContainer(container, label)
    if not container then return end
    local added = container.ChildAdded:Connect(function(obj)
        if not STATE.running or not obj:IsA("Tool") then return end
        STATE.diagnostics.counters.toolAdded += 1
        local tool = toolSnapshot(obj)
        local r = record({ kind = "tool_added", container = label, tool = tool, replication = true })
        if label == "Backpack" then
            local s = matchSessionForTool(tool)
            if s and r then
                r.sessionId = s.id
                s.backpackAdded[#s.backpackAdded + 1] = r
                s.expiresAt = os.clock() + 3
                maybeFinalize(s)
            end
        end
    end)
    local removed = container.ChildRemoved:Connect(function(obj)
        if not STATE.running or not obj:IsA("Tool") then return end
        STATE.diagnostics.counters.toolRemoved += 1
        record({ kind = "tool_removed", container = label, tool = { name = obj.Name, path = pathOf(obj) } })
    end)
    STATE.connections[#STATE.connections + 1] = added
    STATE.connections[#STATE.connections + 1] = removed
end

local function installToolWatchers()
    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")
    local charConn = LP.CharacterAdded:Connect(function(char)
        if STATE.running then watchContainer(char, "Character") end
    end)
    STATE.connections[#STATE.connections + 1] = charConn
end

local function installPromptWatcher()
    local conn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not STATE.running or (player and player ~= LP) then return end
        STATE.diagnostics.counters.prompts += 1
        local crystal = crystalRoot(prompt)
        local r = record({
            kind = "prompt_triggered",
            prompt = pathOf(prompt),
            actionText = prompt.ActionText,
            objectText = prompt.ObjectText,
            crystal = crystal and snapshotCrystal(crystal) or nil,
        })
        if crystal then
            local s = sessionForCrystal(crystal, true, "prompt", r)
            if r and s then
                r.sessionId = s.id
                s.prompt = r
                s.expiresAt = os.clock() + CONFIG.SESSION_TIMEOUT
            end
        end
    end)
    STATE.connections[#STATE.connections + 1] = conn
end

local function incomingSession(remote, packed)
    local name = remote.Name
    if name == "GemCollected" or name == "MineHit" then
        for i = 1, math.min(packed.n or #packed, CONFIG.MAX_ARGS) do
            if typeof(packed[i]) == "Instance" then
                local crystal = crystalRoot(packed[i]) or packed[i]
                local s = STATE.sessionsByCrystal[crystal]
                if s and not s.finalized then return s end
            end
        end
    end
    return latestSessionByName("")
end

local function installIncomingWatchers()
    local roots = {}
    for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
        local n = lower(obj.Name)
        if n == "gemsignals" or n == "gemremotes" or n == "digremotes" or n == "plotremotes" or containsKeyword(n) then
            roots[#roots + 1] = obj
        end
    end
    local queue = {}
    for _, root in ipairs(roots) do queue[#queue + 1] = { obj = root, depth = 0 } end
    local index, count = 1, 0
    while index <= #queue and count < CONFIG.MAX_INCOMING_REMOTES do
        local entry = queue[index]
        index += 1
        local obj, depth = entry.obj, entry.depth
        if obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") then
            count += 1
            local remote = obj
            local conn = remote.OnClientEvent:Connect(function(...)
                if not STATE.running then return end
                STATE.diagnostics.counters.remoteIncoming += 1
                local packed = table.pack(...)
                local r = record({ kind = "remote_incoming", remote = pathOf(remote), class = remote.ClassName, arguments = packArgs(packed), replication = true })
                local s = incomingSession(remote, packed)
                if r and s then
                    r.sessionId = s.id
                    s.incoming[#s.incoming + 1] = r
                    if remote.Name == "GemCollected" or remote.Name == "InventoryChanged" then
                        s.confirmations[#s.confirmations + 1] = r
                    end
                    s.expiresAt = math.max(s.expiresAt, os.clock() + 2)
                    maybeFinalize(s)
                end
            end)
            STATE.incomingConnections[#STATE.incomingConnections + 1] = conn
        elseif depth < 4 then
            local ok, children = pcall(function() return obj:GetChildren() end)
            if ok then
                for _, child in ipairs(children) do queue[#queue + 1] = { obj = child, depth = depth + 1 } end
            end
        end
    end
end

local DISPATCH_KEY = "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V6"
local dispatch = rawget(ENV, DISPATCH_KEY)

local function isRemote(obj)
    return typeof(obj) == "Instance" and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent"))
end

local function onOutgoing(remote, method, packed, response, phase)
    if not STATE.running then return end
    if phase == "response" then
        local s = latestSessionByName("")
        local r = record({ kind = "remote_invoke_response", remote = pathOf(remote), method = method, response = packArgs(response or table.pack()), replication = true })
        if r and s then r.sessionId = s.id; s.incoming[#s.incoming + 1] = r end
        return
    end

    STATE.diagnostics.counters.remoteOutgoing += 1
    local remotePath = pathOf(remote)
    local relevant = containsKeyword(remotePath) or os.clock() <= STATE.focusUntil
    local argsText = ""
    for i = 1, math.min(packed.n or #packed, 6) do argsText ..= " " .. tostring(safeValue(packed[i])) end
    if containsKeyword(argsText) then relevant = true end

    local info = STATE.remotes[remotePath]
    if not info then
        local count = 0
        for _ in pairs(STATE.remotes) do count += 1 end
        if count < CONFIG.MAX_REMOTES then
            info = { path = remotePath, class = remote.ClassName, outgoing = 0, samples = 0, firstSeen = os.clock() }
            STATE.remotes[remotePath] = info
        end
    end
    if info then info.outgoing += 1 end
    if not relevant and info and info.samples >= 1 then return end
    if info then info.samples += 1 end

    local r = record({ kind = "remote_outgoing", remote = remotePath, class = remote.ClassName, method = method, relevant = relevant, arguments = relevant and packArgs(packed) or nil })
    if relevant and r then
        local s = latestSessionByName("")
        if s then r.sessionId = s.id; s.outgoing[#s.outgoing + 1] = r end
    end
end

local function installNamecallHook()
    if type(dispatch) ~= "table" and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
        dispatch = { handler = nil }
        local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
        local old
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            local handler = dispatch.handler
            if handler and method == "InvokeServer" and isRemote(self) then
                local packed = table.pack(...)
                pcall(handler, self, method, packed, nil, "request")
                local result = table.pack(old(self, ...))
                pcall(handler, self, method, packed, result, "response")
                return table.unpack(result, 1, result.n)
            elseif handler and method == "FireServer" and isRemote(self) then
                pcall(handler, self, method, table.pack(...), nil, "request")
            end
            return old(self, ...)
        end))
        ENV[DISPATCH_KEY] = dispatch
    end
    if type(dispatch) == "table" then dispatch.handler = onOutgoing return true end
    addError("capture", "hookmetamethod/getnamecallmethod indisponivel")
    return false
end

local function disconnectAll()
    for _, conn in ipairs(STATE.connections) do pcall(function() conn:Disconnect() end) end
    for _, conn in ipairs(STATE.incomingConnections) do pcall(function() conn:Disconnect() end) end
    STATE.connections = {}
    STATE.incomingConnections = {}
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

local function checkHealth()
    STATE.diagnostics.health.checked = true
    if not REQUEST then
        STATE.diagnostics.health.ok = false
        STATE.diagnostics.health.error = "executor_without_http"
        return false
    end
    local ok, response, err = http({ Url = CONFIG.HEALTH, Method = "GET", Headers = { Accept = "application/json", ["Cache-Control"] = "no-cache" } })
    if not ok then
        STATE.diagnostics.health.ok = false
        STATE.diagnostics.health.error = err or (response and ("HTTP " .. tostring(response.status))) or "health_failed"
        return false
    end
    STATE.diagnostics.health.ok = true
    STATE.diagnostics.health.httpStatus = response.status
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, response.body)
    if decodeOk and type(data) == "table" then
        STATE.diagnostics.health.githubMirrorConfigured = data.githubMirrorConfigured
        STATE.diagnostics.health.maxRecords = data.maxRecords
        STATE.diagnostics.health.maxRemotes = data.maxRemotes
    end
    return true
end

local function remotesList()
    local out = {}
    for _, info in pairs(STATE.remotes) do out[#out + 1] = info end
    table.sort(out, function(a, b) return (a.firstSeen or 0) < (b.firstSeen or 0) end)
    return out
end

local function buildPayload()
    local diag = STATE.diagnostics
    diag.operation = {
        startedAt = STATE.startedAt,
        finishedAt = STATE.finishedAt,
        durationSeconds = math.max(0, STATE.finishedAt - STATE.startedAt),
        records = #STATE.records,
        sessions = #STATE.sessions,
        backupSupported = type(writefile) == "function",
        requestSupported = REQUEST ~= nil,
    }
    diag.transport.status = "pending_at_send"
    diag.transport.serverAccepted = nil
    diag.transport.githubMirrored = nil

    return {
        schemaVersion = 1,
        userId = tostring(LP.UserId),
        username = LP.Name,
        capturedAt = DateTime.now():ToIsoDate(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = STATE.runId,
        trace = {
            version = CONFIG.VERSION,
            purpose = "crystal_pickup_correlation",
            runId = STATE.runId,
            startedAt = STATE.startedAt,
            finishedAt = STATE.finishedAt,
            records = STATE.records,
            remotes = remotesList(),
            pickupSessions = STATE.sessions,
            diagnostics = diag,
        }
    }
end

local function safeFileName()
    return string.format("Cafeina_PickupTrace_%s_%d.json", tostring(game.PlaceId), os.time())
end

local function saveLocal(name, text)
    if type(writefile) ~= "function" then return false end
    local ok, err = pcall(writefile, name, text)
    if not ok then addError("writefile", err) end
    return ok
end

local function uploadPayload(payload)
    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then return false, nil, "json_encode_failed" end

    local backupName = safeFileName()
    saveLocal(backupName, body)

    STATE.diagnostics.transport.status = "sending"
    for attempt = 1, CONFIG.RETRIES do
        STATE.diagnostics.counters.uploadAttempts += 1
        local ok, response, err = http({
            Url = CONFIG.ENDPOINT,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
            Body = body,
        })
        if ok then
            local receipt
            pcall(function() receipt = HttpService:JSONDecode(response.body) end)
            STATE.diagnostics.transport.status = "accepted"
            STATE.diagnostics.transport.serverAccepted = true
            STATE.diagnostics.transport.httpStatus = response.status
            STATE.diagnostics.transport.receipt = safeValue(receipt)
            STATE.diagnostics.transport.githubMirrored = receipt and receipt.github and receipt.github.mirrored or false
            STATE.diagnostics.transport.githubConfigured = receipt and receipt.github and receipt.github.configured or false
            STATE.diagnostics.transport.latestUrl = receipt and receipt.latestUrl or nil
            local finalText
            pcall(function() finalText = HttpService:JSONEncode(payload) end)
            if finalText then saveLocal(string.gsub(backupName, "%.json$", "_receipt.json"), finalText) end
            return true, receipt, nil
        end
        STATE.diagnostics.transport.status = "retrying"
        STATE.diagnostics.transport.lastError = err or (response and ("HTTP " .. tostring(response.status))) or "upload_failed"
        task.wait(attempt * 1.5)
    end
    STATE.diagnostics.transport.status = "failed"
    STATE.diagnostics.transport.serverAccepted = false
    return false, nil, STATE.diagnostics.transport.lastError
end

local function startCapture()
    if STATE.running then return end
    STATE.running = true
    STATE.startedAt = os.time()
    STATE.finishedAt = 0
    STATE.runId = HttpService:GenerateGUID(false)
    STATE.status = "capturando"

    STATE.diagnostics.capabilities = {
        request = REQUEST ~= nil,
        writefile = type(writefile) == "function",
        setclipboard = type(setclipboard) == "function",
        hookmetamethod = type(hookmetamethod) == "function",
        getnamecallmethod = type(getnamecallmethod) == "function",
        prompt = true,
        spatial = true,
    }

    task.spawn(checkHealth)
    installToolWatchers()
    installPromptWatcher()
    installIncomingWatchers()
    installNamecallHook()

    task.spawn(function()
        while STATE.running do
            scanNearby()
            for _, s in ipairs(STATE.sessions) do
                if not s.finalized and os.clock() > s.expiresAt then finalizeSession(s, "timeout") end
            end
            task.wait(CONFIG.SCAN_INTERVAL)
        end
    end)
end

local function stopCaptureAndSend()
    if not STATE.running then return false, nil, "not_running" end
    STATE.running = false
    STATE.finishedAt = os.time()
    disconnectAll()
    for _, s in ipairs(STATE.sessions) do
        if not s.finalized then finalizeSession(s, "scan_stopped") end
    end
    STATE.status = "enviando"
    local payload = buildPayload()
    local ok, receipt, err = uploadPayload(payload)
    if ok then
        STATE.status = (receipt and receipt.github and receipt.github.mirrored) and "ENVIADO + GITHUB ✓" or "RENDER RECEBEU • GITHUB PENDENTE"
    else
        STATE.status = "ENVIO FALHOU • backup preservado"
    end
    return ok, receipt, err
end

--============================== UI ==============================
local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceV6"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(286, 206)
frame.Position = UDim2.new(0.5, -143, 0.16, 0)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -18, 0, 30)
title.Position = UDim2.fromOffset(9, 7)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • PICKUP TRACE V6"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -18, 0, 48)
status.Position = UDim2.fromOffset(9, 38)
status.BackgroundColor3 = Color3.fromRGB(22,22,25)
status.TextColor3 = Color3.fromRGB(220,220,225)
status.TextSize = 11
status.Font = Enum.Font.Code
status.TextWrapped = true
status.Text = "Status: aguardando"
status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

local function button(text, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -18, 0, 34)
    b.Position = UDim2.fromOffset(9, y)
    b.BackgroundColor3 = Color3.fromRGB(38, 38, 43)
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local startBtn = button("INICIAR SCAN", 94)
local focusBtn = button("MARCAR PICKUP • 8s", 132)
local stopBtn = button("PARAR + ENVIAR", 170)
stopBtn.BackgroundColor3 = Color3.fromRGB(108, 25, 31)

startBtn.MouseButton1Click:Connect(function()
    startCapture()
end)

focusBtn.MouseButton1Click:Connect(function()
    STATE.focusUntil = os.clock() + CONFIG.FOCUS_SECONDS
    STATE.status = "janela de pickup marcada por 8s"
end)

stopBtn.MouseButton1Click:Connect(function()
    if STATE.running then
        task.spawn(stopCaptureAndSend)
    end
end)

task.spawn(function()
    while gui.Parent do
        local c = STATE.diagnostics.counters
        status.Text = string.format(
            "Status: %s\nRegistros: %d • Sessões: %d • High: %d\nPrompts: %d • Tools: %d • Remotes IN: %d",
            STATE.status, c.records, c.sessions, c.sessionsHigh, c.prompts, c.toolAdded, c.remoteIncoming
        )
        task.wait(0.3)
    end
end)

return {
    Start = startCapture,
    StopAndSend = stopCaptureAndSend,
    State = STATE,
    Version = CONFIG.VERSION,
}
