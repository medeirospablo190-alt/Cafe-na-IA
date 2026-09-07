--==============================================================
-- CAFEINA • INVENTORY REMOTE TRACE V6.4 FOCUSED STABLE
-- 3 outgoing remotes only + passive pickup/drop correlation
-- Mobile/executor • bounded • restart-safe • no touch/spatial polling
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V6_4_FOCUSED_STABLE",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    SESSION_TIMEOUT = 8,
    DROP_WINDOW = 4,
    MAX_RECORDS = 1600,
    MAX_SESSIONS = 120,
    MAX_DROPS = 80,
    MAX_ARGS = 12,
    MAX_STRING = 700,
    RETRIES = 3,
}

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
        if #v > CFG.MAX_STRING then return string.sub(v, 1, CFG.MAX_STRING) .. "...[truncated]" end
        return v
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
            if n > CFG.MAX_ARGS then break end
            out[tostring(k)] = safe(value, depth + 1)
        end
        return out
    end
    return tostring(v)
end

local function argsOf(packed)
    local out = {}
    local n = math.min(tonumber(packed and packed.n) or #packed, CFG.MAX_ARGS)
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
    return nil
end

local REQUEST = resolveRequest()

local function newCounters()
    return {
        records = 0,
        prompts = 0,
        toolAdded = 0,
        toolRemoved = 0,
        crystalRemoved = 0,
        incoming = 0,
        targetedOutgoing = 0,
        dropAttempts = 0,
        dropConfirmed = 0,
        dropWorldSeen = 0,
        placeCrystal = 0,
        digRequest = 0,
        sessions = 0,
        sessionsHigh = 0,
        sessionsMedium = 0,
        sessionsLow = 0,
        uploadAttempts = 0,
        droppedRecords = 0,
    }
end

local S = {
    running = false,
    sending = false,
    status = "aguardando",
    seq = 0,
    sessionSeq = 0,
    dropSeq = 0,
    runId = "",
    startedAt = 0,
    finishedAt = 0,
    records = {},
    sessions = {},
    sessionsByCrystal = setmetatable({}, { __mode = "k" }),
    tracked = setmetatable({}, { __mode = "k" }),
    bagMap = {},
    drops = {},
    connections = {},
    targetList = {},
    diagnostics = {
        version = CFG.VERSION,
        errors = {},
        counters = newCounters(),
        health = { checked = false },
        transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" },
        capabilities = {},
        guards = {
            noTouchWatcher = true,
            noSpatialPolling = true,
            noPerRemoteTaskDefer = true,
            exactTargetInstances = true,
            targetFilterBeforeGetNamecallMethod = true,
            originalCallBeforeObserver = true,
            singletonDispatcher = true,
            refuseStackOnLegacyHooks = true,
            protectedHookInstall = true,
            duplicateRuntimeCleanup = true,
            maxRecords = CFG.MAX_RECORDS,
            maxSessions = CFG.MAX_SESSIONS,
            maxDropAttempts = CFG.MAX_DROPS,
        },
    },
}

local function addError(phase, message)
    if #S.diagnostics.errors < 24 then
        S.diagnostics.errors[#S.diagnostics.errors + 1] = {
            unix = os.time(), phase = tostring(phase), error = tostring(message)
        }
    end
end

local function rec(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.diagnostics.counters.droppedRecords += 1
        return nil
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = data.clock or os.clock()
    data.unix = data.unix or os.time()
    S.records[#S.records + 1] = data
    S.diagnostics.counters.records += 1
    return data
end

local function crystalRoot(obj)
    local cur = obj
    for _ = 1, 7 do
        if not cur then break end
        local parent = cur.Parent
        if parent and (parent.Name == "SpawnedGems" or parent.Name == "DroppedGems") then return cur end
        cur = parent
    end
    return nil
end

local function crystalSnapshot(crystal)
    if not crystal then return nil end
    local pos
    pcall(function()
        if crystal:IsA("Model") then pos = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos = crystal.Position end
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
        attributes = attrs,
    }
end

local function pendingSessionForName(name, maxAge)
    local now = os.clock()
    for i = #S.sessions, 1, -1 do
        local session = S.sessions[i]
        if not session.finalized and now <= session.expiresAt then
            if (not maxAge or now - session.startedClock <= maxAge) and (not name or session.crystalName == name) then
                return session
            end
        end
    end
    return nil
end

local function sessionForCrystal(crystal, create, triggerKind, trigger)
    if crystal then
        local existing = S.sessionsByCrystal[crystal]
        if existing and not existing.finalized and os.clock() <= existing.expiresAt then return existing end
    end
    if not create or #S.sessions >= CFG.MAX_SESSIONS then return nil end

    S.sessionSeq += 1
    local session = {
        id = string.format("pickup-%03d", S.sessionSeq),
        crystalRef = crystal,
        crystalName = crystal and crystal.Name or nil,
        crystalBefore = crystalSnapshot(crystal),
        triggerKind = triggerKind,
        trigger = safe(trigger),
        startedClock = os.clock(),
        startedUnix = os.time(),
        expiresAt = os.clock() + CFG.SESSION_TIMEOUT,
        prompt = nil,
        backpackAdded = {},
        worldRemoved = {},
        confirmations = {},
        incoming = {},
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

local function trackCrystal(crystal)
    if not crystal or S.tracked[crystal] then return end
    S.tracked[crystal] = { snapshot = crystalSnapshot(crystal), removed = false }
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
        local session = sessionForCrystal(crystal, false)
        if event and session then
            event.sessionId = session.id
            session.worldRemoved[#session.worldRemoved + 1] = event
            maybeFinish(session)
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local function toolSnapshot(tool)
    local attrs = {}
    pcall(function()
        for k, v in pairs(tool:GetAttributes()) do attrs[k] = safe(v) end
    end)
    return { name = tool.Name, path = pathOf(tool), attributes = attrs }
end

local function rememberTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    local snap = toolSnapshot(tool)
    local id = snap.attributes and snap.attributes.BagId
    if id ~= nil then
        S.bagMap[tostring(id)] = {
            bagId = id,
            gemName = snap.attributes.GemName,
            kg = snap.attributes.Kg,
            value = snap.attributes.Value,
            rarity = snap.attributes.Rarity,
        }
    end
end

local function recentDropByBagId(bagId, age)
    if bagId == nil then return nil end
    local now = os.clock()
    for i = #S.drops, 1, -1 do
        local drop = S.drops[i]
        if tostring(drop.bagId) == tostring(bagId) and now - drop.callClock <= (age or CFG.DROP_WINDOW) then
            return drop
        end
    end
    return nil
end

local function recentDropByGemName(name, age)
    if not name then return nil end
    local now = os.clock()
    for i = #S.drops, 1, -1 do
        local drop = S.drops[i]
        if not drop.worldSeen and drop.gemName == name and now - drop.callClock <= (age or CFG.DROP_WINDOW) then
            return drop
        end
    end
    return nil
end

local function watchContainer(container, label)
    if not container then return end
    for _, child in ipairs(container:GetChildren()) do rememberTool(child) end

    local added = container.ChildAdded:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolAdded += 1
        local snap = toolSnapshot(obj)
        rememberTool(obj)
        local event = rec({ kind = "tool_added", container = label, tool = snap, replication = true })
        if label == "Backpack" and event then
            local gemName = snap.attributes and snap.attributes.GemName
            local session = gemName and pendingSessionForName(gemName, 3) or nil
            if session then
                event.sessionId = session.id
                session.backpackAdded[#session.backpackAdded + 1] = event
                maybeFinish(session)
            end
        end
    end)

    local removed = container.ChildRemoved:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolRemoved += 1
        local snap = toolSnapshot(obj)
        local bagId = snap.attributes and snap.attributes.BagId
        local drop = recentDropByBagId(bagId, 2.5)
        local event = rec({
            kind = "tool_removed",
            container = label,
            tool = snap,
            dropId = drop and drop.id or nil,
            correlatedToDrop = drop ~= nil,
        })
        if drop and event then drop.toolRemovedSeq = event.seq end
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

local function installPromptWatcher()
    local conn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not S.running or (player and player ~= LP) then return end
        local crystal = crystalRoot(prompt)
        if not crystal then return end
        trackCrystal(crystal)
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
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local incomingAttached = setmetatable({}, { __mode = "k" })

local function attachIncoming(remote)
    if not remote or incomingAttached[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
    incomingAttached[remote] = true

    local conn = remote.OnClientEvent:Connect(function(...)
        if not S.running then return end
        local packed = table.pack(...)
        if remote.Name == "GemCollected" then
            local player = packed[2]
            if typeof(player) == "Instance" and player:IsA("Player") and player ~= LP then return end
        end

        S.diagnostics.counters.incoming += 1
        local event = rec({
            kind = "remote_incoming",
            remote = pathOf(remote),
            class = remote.ClassName,
            arguments = argsOf(packed),
            replication = true,
        })

        local session
        if remote.Name == "GemCollected" or remote.Name == "MineHit" then
            for i = 1, math.min(packed.n or #packed, CFG.MAX_ARGS) do
                local value = packed[i]
                if typeof(value) == "Instance" then
                    local crystal = crystalRoot(value)
                    if crystal then
                        trackCrystal(crystal)
                        session = sessionForCrystal(crystal, remote.Name == "GemCollected", "server_" .. remote.Name, event)
                        if session then break end
                    end
                end
            end
        elseif remote.Name == "InventoryChanged" then
            session = pendingSessionForName(nil, 2.5)
            local drop = S.drops[#S.drops]
            if drop and os.clock() - drop.callClock <= 2.5 and event then
                event.dropId = drop.id
                drop.inventoryChangedSeq = event.seq
            end
        else
            session = pendingSessionForName(nil, 2)
        end

        if event and session and not session.finalized then
            event.sessionId = session.id
            session.incoming[#session.incoming + 1] = event
            if remote.Name == "GemCollected" or remote.Name == "InventoryChanged" then
                session.confirmations[#session.confirmations + 1] = event
            end
            maybeFinish(session)
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local function installIncoming()
    local gemSignals = ReplicatedStorage:FindFirstChild("GemSignals")
    local gemRemotes = ReplicatedStorage:FindFirstChild("GemRemotes")
    local digRemotes = ReplicatedStorage:FindFirstChild("DigRemotes")
    if gemSignals then
        attachIncoming(gemSignals:FindFirstChild("GemCollected"))
        attachIncoming(gemSignals:FindFirstChild("MineHit"))
    end
    if gemRemotes then attachIncoming(gemRemotes:FindFirstChild("InventoryChanged")) end
    if digRemotes then attachIncoming(digRemotes:FindFirstChild("DigResult")) end
end

local function watchDroppedFolder(folder)
    if not folder then return end
    local conn = folder.ChildAdded:Connect(function(crystal)
        if not S.running then return end
        S.diagnostics.counters.dropWorldSeen += 1
        local drop = recentDropByGemName(crystal.Name, CFG.DROP_WINDOW)
        local event = rec({
            kind = "drop_world_seen",
            crystal = crystalSnapshot(crystal),
            dropId = drop and drop.id or nil,
            bagId = drop and drop.bagId or nil,
            expectedGemName = drop and drop.gemName or nil,
            correlatedToOwnDrop = drop ~= nil,
        })
        if drop and event then
            drop.worldSeen = true
            drop.worldSeenSeq = event.seq
            drop.latencySeconds = math.max(0, event.clock - drop.callClock)
            S.diagnostics.counters.dropConfirmed += 1
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local function installDropWatcher()
    local folder = Workspace:FindFirstChild("DroppedGems")
    if folder then
        watchDroppedFolder(folder)
        return
    end
    local conn
    conn = Workspace.ChildAdded:Connect(function(obj)
        if not S.running then return end
        if obj.Name == "DroppedGems" then
            if conn then conn:Disconnect() end
            watchDroppedFolder(obj)
        end
    end)
    S.connections[#S.connections + 1] = conn
end

local TARGET_SPECS = {
    { root = "GemSignals", name = "DropCrystal", label = "DropCrystal" },
    { root = "PlotRemotes", name = "PlaceCrystal", label = "PlaceCrystal" },
    { root = "DigRemotes", name = "DigRequest", label = "DigRequest" },
}

local function resolveTargets()
    local targets, list = {}, {}
    for _, spec in ipairs(TARGET_SPECS) do
        local root = ReplicatedStorage:FindFirstChild(spec.root)
        local remote = root and root:FindFirstChild(spec.name)
        local valid = remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent"))
        if valid then
            targets[remote] = spec.label
            list[#list + 1] = { label = spec.label, path = pathOf(remote), class = remote.ClassName, found = true }
        else
            list[#list + 1] = { label = spec.label, expectedPath = "ReplicatedStorage." .. spec.root .. "." .. spec.name, found = false }
        end
    end
    S.targetList = list
    return targets
end

-- Make old CAFEINA handlers inert. Their wrappers cannot be uninstalled from this Lua state.
local legacyHookCount = 0
for _, key in ipairs({
    "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V5",
    "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V6",
    "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V61",
}) do
    local oldDispatch = rawget(ENV, key)
    if type(oldDispatch) == "table" then
        legacyHookCount += 1
        oldDispatch.handler = nil
    end
end
S.diagnostics.legacyHookWrappersDetected = legacyHookCount

local DISPATCH_KEY = "__CAFEINA_INVTRACE_NAMECALL_SINGLETON_V1"
local dispatch = rawget(ENV, DISPATCH_KEY)

local function ensureDispatcher()
    if type(dispatch) == "table" and dispatch.signature == "CAFEINA_INVTRACE_SINGLETON_V1" then
        return true
    end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        addError("hook", "hookmetamethod/getnamecallmethod unavailable")
        return false
    end

    local candidate = {
        signature = "CAFEINA_INVTRACE_SINGLETON_V1",
        handler = nil,
        targets = {},
    }
    local old
    local function body(self, ...)
        local handler = candidate.handler
        local target = handler and candidate.targets and candidate.targets[self]
        if target then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                local packed = table.pack(...)
                local callClock = os.clock()
                local result = table.pack(old(self, ...))
                local returnClock = os.clock()
                pcall(handler, self, target, method, packed, result, callClock, returnClock)
                return table.unpack(result, 1, result.n)
            end
        end
        return old(self, ...)
    end

    local wrapped = body
    if type(newcclosure) == "function" then
        local okWrap, value = pcall(newcclosure, body)
        if okWrap and type(value) == "function" then wrapped = value end
    end

    local okHook, oldOrError = pcall(function()
        return hookmetamethod(game, "__namecall", wrapped)
    end)
    if not okHook or type(oldOrError) ~= "function" then
        addError("hook_install", okHook and "hookmetamethod returned non-function" or oldOrError)
        return false
    end

    old = oldOrError
    dispatch = candidate
    ENV[DISPATCH_KEY] = dispatch
    return true
end

local function disableHook()
    if type(dispatch) == "table" then
        dispatch.handler = nil
        dispatch.targets = {}
    end
end

local function observeTarget(remote, label, method, packed, result, callClock, returnClock)
    if not S.running then return end
    S.diagnostics.counters.targetedOutgoing += 1
    local data = {
        kind = "target_remote_outgoing",
        target = label,
        remote = pathOf(remote),
        class = remote.ClassName,
        method = method,
        arguments = argsOf(packed),
        clock = callClock,
        forwardReturnClock = returnClock,
        observedAfterForward = true,
    }
    if method == "InvokeServer" then data.response = argsOf(result) end

    if label == "DropCrystal" then
        S.dropSeq += 1
        local bagId = packed[1]
        local known = S.bagMap[tostring(bagId)]
        local drop = {
            id = string.format("drop-%03d", S.dropSeq),
            callClock = callClock,
            returnClock = returnClock,
            unix = os.time(),
            bagId = safe(bagId),
            gemName = known and known.gemName or nil,
            knownItem = known and safe(known) or nil,
            worldSeen = false,
        }
        S.drops[#S.drops + 1] = drop
        while #S.drops > CFG.MAX_DROPS do table.remove(S.drops, 1) end
        S.diagnostics.counters.dropAttempts += 1
        data.kind = "drop_attempt"
        data.dropId = drop.id
        data.bagId = drop.bagId
        data.knownItem = drop.knownItem
    elseif label == "PlaceCrystal" then
        S.diagnostics.counters.placeCrystal += 1
    elseif label == "DigRequest" then
        S.diagnostics.counters.digRequest += 1
    end

    rec(data)
end

local function enableFocusedHook()
    local targets = resolveTargets()
    local found = 0
    for _ in pairs(targets) do found += 1 end
    S.diagnostics.targetCount = found

    if legacyHookCount > 0 then
        addError("hook_guard", "legacy CAFEINA hook wrapper detected; restart Roblox for focused hook")
        disableHook()
        return false, "legacy"
    end
    if found == 0 then
        addError("hook_targets", "none of the 3 target remotes were found")
        disableHook()
        return false, "targets"
    end
    if not ensureDispatcher() then
        disableHook()
        return false, "unsupported"
    end

    dispatch.targets = targets
    dispatch.handler = observeTarget
    return true, "ok"
end

local function disconnectAll()
    for _, conn in ipairs(S.connections) do pcall(function() conn:Disconnect() end) end
    S.connections = {}
    disableHook()
end

local function httpRequest(options)
    if not REQUEST then return false, nil, "request/http_request unavailable" end
    local ok, response = pcall(REQUEST, options)
    if not ok or not response then return false, nil, tostring(response) end
    local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body = tostring(response.Body or response.body or "")
    return status >= 200 and status < 300, { status = status, body = body }, nil
end

local function checkHealth()
    S.diagnostics.health.checked = true
    local ok, response, message = httpRequest({
        Url = CFG.HEALTH,
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

local function saveLocal(name, text)
    if type(writefile) ~= "function" then return false end
    local ok, message = pcall(writefile, name, text)
    if not ok then addError("writefile", message) end
    return ok
end

local function buildPayload()
    S.diagnostics.transport.status = "pending_at_send"
    S.diagnostics.operation = {
        startedAt = S.startedAt,
        finishedAt = S.finishedAt,
        durationSeconds = math.max(0, S.finishedAt - S.startedAt),
        records = #S.records,
        sessions = #S.sessions,
        eventDriven = true,
        hookScope = { "DropCrystal", "PlaceCrystal", "DigRequest" },
        focusedHook = S.diagnostics.capabilities.focusedHook == true,
        targetCount = S.diagnostics.targetCount or 0,
        legacyHookWrappersDetected = legacyHookCount,
        spatialPolling = false,
        touchWatcher = false,
        taskDeferPerRemote = false,
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
            version = CFG.VERSION,
            purpose = "crystal_pickup_drop_targeted_remote_correlation",
            runId = S.runId,
            startedAt = S.startedAt,
            finishedAt = S.finishedAt,
            records = S.records,
            remotes = S.targetList,
            pickupSessions = S.sessions,
            dropAttempts = S.drops,
            bagMap = S.bagMap,
            diagnostics = S.diagnostics,
        },
    }
end

local function upload(payload)
    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then return false, nil, "json_encode_failed" end

    local fileName = string.format("Cafeina_FocusedTrace_%s_%s.json", tostring(game.PlaceId), tostring(S.runId):gsub("-", ""))
    saveLocal(fileName, body)

    for attempt = 1, CFG.RETRIES do
        S.diagnostics.counters.uploadAttempts += 1
        S.diagnostics.transport.status = "sending"
        local ok, response, message = httpRequest({
            Url = CFG.ENDPOINT,
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
            pcall(function()
                receiptText = HttpService:JSONEncode({ runId = S.runId, receipt = receipt, transport = S.diagnostics.transport })
            end)
            if receiptText then saveLocal(fileName:gsub("%.json$", "_receipt.json"), receiptText) end
            return true, receipt, nil
        end
        S.diagnostics.transport.lastError = message or (response and ("HTTP " .. tostring(response.status))) or "upload_failed"
        S.diagnostics.transport.status = "retrying"
        task.wait(attempt * 1.5)
    end

    S.diagnostics.transport.status = "failed"
    S.diagnostics.transport.serverAccepted = false
    return false, nil, S.diagnostics.transport.lastError
end

local function resetRun()
    disconnectAll()
    S.seq = 0
    S.sessionSeq = 0
    S.dropSeq = 0
    S.runId = ""
    S.records = {}
    S.sessions = {}
    S.sessionsByCrystal = setmetatable({}, { __mode = "k" })
    S.tracked = setmetatable({}, { __mode = "k" })
    S.bagMap = {}
    S.drops = {}
    S.connections = {}
    S.targetList = {}
    incomingAttached = setmetatable({}, { __mode = "k" })
    S.diagnostics.errors = {}
    S.diagnostics.counters = newCounters()
    S.diagnostics.health = { checked = false }
    S.diagnostics.transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" }
    S.diagnostics.targetCount = 0
    S.diagnostics.legacyHookWrappersDetected = legacyHookCount
end

local function start()
    if S.running or S.sending then return false end
    resetRun()
    S.running = true
    S.startedAt = os.time()
    S.finishedAt = 0
    S.runId = HttpService:GenerateGUID(false)

    local hookOk, hookReason = enableFocusedHook()
    S.diagnostics.capabilities = {
        request = REQUEST ~= nil,
        writefile = type(writefile) == "function",
        eventDriven = true,
        hookmetamethod = type(hookmetamethod) == "function",
        getnamecallmethod = type(getnamecallmethod) == "function",
        focusedHook = hookOk,
        hookReason = hookReason,
        targetCount = S.diagnostics.targetCount or 0,
        spatialPolling = false,
        touchWatcher = false,
    }

    if hookOk then
        S.status = string.format("capturando • hook %d/3", S.diagnostics.targetCount or 0)
    elseif hookReason == "legacy" then
        S.status = "capturando • passivo • reinicie p/ hook"
    else
        S.status = "capturando • passivo"
    end

    task.spawn(checkHealth)
    installTools()
    installPromptWatcher()
    installIncoming()
    installDropWatcher()

    task.spawn(function()
        while S.running do
            local now = os.clock()
            for _, session in ipairs(S.sessions) do
                if not session.finalized and now > session.expiresAt then finishSession(session, "timeout") end
            end
            task.wait(0.75)
        end
    end)
    return true
end

local function stopOnly()
    if not S.running then
        disableHook()
        return false
    end
    S.running = false
    S.finishedAt = os.time()
    disconnectAll()
    for _, session in ipairs(S.sessions) do
        if not session.finalized then finishSession(session, "scan_stopped") end
    end
    return true
end

local function stopAndSend()
    if not S.running or S.sending then return false, nil, "not_running_or_busy" end
    stopOnly()
    S.sending = true
    S.status = "enviando"
    local ok, receipt, message = upload(buildPayload())
    S.sending = false
    if ok then
        S.status = (receipt and receipt.github and receipt.github.mirrored) and "ENVIADO + GITHUB ✓" or "RENDER RECEBEU • GITHUB PENDENTE"
    else
        S.status = "ENVIO FALHOU • backup preservado"
    end
    return ok, receipt, message
end

-- Stop old event-only runtime if present.
local oldV62 = rawget(ENV, "__CAFEINA_INVTRACE_RUNTIME_NOHOOK")
if type(oldV62) == "table" and type(oldV62.stop) == "function" then pcall(oldV62.stop) end

local RUNTIME_KEY = "__CAFEINA_INVTRACE_RUNTIME_V64"
local previousRuntime = rawget(ENV, RUNTIME_KEY)
if type(previousRuntime) == "table" and type(previousRuntime.cleanup) == "function" then pcall(previousRuntime.cleanup) end

local function destroyOldGui(name)
    pcall(function()
        local old = CoreGui:FindFirstChild(name)
        if old then old:Destroy() end
    end)
    pcall(function()
        local playerGui = LP:FindFirstChildOfClass("PlayerGui")
        local old = playerGui and playerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end)
end

for _, name in ipairs({
    "CafeinaInventoryTraceV6",
    "CafeinaInventoryTraceV61",
    "CafeinaInventoryTraceV62",
    "CafeinaInventoryTraceV63",
    "CafeinaInventoryTraceV64",
}) do
    destroyOldGui(name)
end

--============================== UI ==============================
local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceV64"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(292, 208)
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
title.Text = "CAFEINA • FOCUSED TRACE V6.4"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -18, 0, 66)
status.Position = UDim2.fromOffset(9, 38)
status.BackgroundColor3 = Color3.fromRGB(22, 22, 25)
status.TextColor3 = Color3.fromRGB(220, 220, 225)
status.TextSize = 11
status.Font = Enum.Font.Code
status.TextWrapped = true
status.Text = "Status: aguardando"
status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 8)

local function makeButton(text, y, danger)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -18, 0, 36)
    b.Position = UDim2.fromOffset(9, y)
    b.BackgroundColor3 = danger and Color3.fromRGB(108, 25, 31) or Color3.fromRGB(38, 38, 43)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local startBtn = makeButton("INICIAR SCAN", 113, false)
local stopBtn = makeButton("PARAR + ENVIAR", 158, true)

local function refreshButtons()
    local busy = S.running or S.sending
    startBtn.Active = not busy
    startBtn.AutoButtonColor = not busy
    startBtn.Text = S.running and "SCAN EM ANDAMENTO" or (S.sending and "ENVIANDO..." or "INICIAR SCAN")
    stopBtn.Active = S.running and not S.sending
    stopBtn.AutoButtonColor = S.running and not S.sending
    stopBtn.Text = S.sending and "ENVIANDO..." or "PARAR + ENVIAR"
end

startBtn.MouseButton1Click:Connect(function()
    start()
    refreshButtons()
end)

stopBtn.MouseButton1Click:Connect(function()
    if S.running and not S.sending then
        task.spawn(function()
            stopAndSend()
            refreshButtons()
        end)
    end
end)

local function cleanup()
    if S.running then stopOnly() else disableHook() end
    S.sending = false
    pcall(function() gui:Destroy() end)
end

ENV[RUNTIME_KEY] = { cleanup = cleanup, stop = stopOnly, state = S }

task.spawn(function()
    while gui.Parent do
        local c = S.diagnostics.counters
        local hookText = S.diagnostics.capabilities.focusedHook and tostring(S.diagnostics.targetCount or 0) .. "/3" or "OFF"
        status.Text = string.format(
            "Status: %s\nHook: %s • Reg: %d • Pickups: %d\nDrop: %d/%d • Place: %d • Dig: %d",
            S.status,
            hookText,
            c.records,
            c.sessions,
            c.dropConfirmed,
            c.dropAttempts,
            c.placeCrystal,
            c.digRequest
        )
        refreshButtons()
        task.wait(0.5)
    end
end)

return {
    Start = start,
    Stop = stopOnly,
    StopAndSend = stopAndSend,
    Cleanup = cleanup,
    State = S,
    Version = CFG.VERSION,
}
