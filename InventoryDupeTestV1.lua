--==============================================================
-- CAFEINA • CRYSTAL DUP CONSISTENCY TEST V1
-- Controlled stale-BagId / state-consistency validator
-- No __namecall hook • no spatial polling • no touch watcher
-- One crystal per test • auto-report to Render/GitHub pipeline
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_CRYSTAL_DUP_CONSISTENCY_V1",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    MAX_RECORDS = 700,
    MAX_ERRORS = 20,
    MAX_ANOMALIES = 20,
    MAX_ARGS = 12,
    MAX_STRING = 600,
    DROP_TIMEOUT = 3.5,
    PICKUP_TIMEOUT = 4.0,
    REPLAY_OBSERVE = 1.15,
    POLL_STEP = 0.04,
    RETRIES = 3,
}

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
local DROP_REMOTE = ReplicatedStorage:FindFirstChild("GemSignals") and ReplicatedStorage.GemSignals:FindFirstChild("DropCrystal")
local INVENTORY_CHANGED = ReplicatedStorage:FindFirstChild("GemRemotes") and ReplicatedStorage.GemRemotes:FindFirstChild("InventoryChanged")
local DROPPED_GEMS = Workspace:FindFirstChild("DroppedGems")

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

local function attrsOf(obj)
    local attrs = {}
    if not obj then return attrs end
    pcall(function()
        for k, v in pairs(obj:GetAttributes()) do attrs[k] = safe(v) end
    end)
    return attrs
end

local function toolSnapshot(tool)
    if not tool then return nil end
    return {
        name = tool.Name,
        path = pathOf(tool),
        attributes = attrsOf(tool),
    }
end

local function crystalSnapshot(crystal)
    if not crystal then return nil end
    local pos
    pcall(function()
        if crystal:IsA("Model") then pos = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos = crystal.Position end
    end)
    return {
        name = crystal.Name,
        path = pathOf(crystal),
        class = crystal.ClassName,
        position = pos and tostring(pos) or nil,
        attributes = attrsOf(crystal),
    }
end

local function newCounters()
    return {
        records = 0,
        anomalies = 0,
        dropCalls = 0,
        worldAdded = 0,
        worldRemoved = 0,
        toolAdded = 0,
        toolRemoved = 0,
        inventoryChanged = 0,
        uploadAttempts = 0,
        droppedRecords = 0,
    }
end

local S = {
    running = false,
    sending = false,
    finalized = false,
    cancelRequested = false,
    status = "aguardando",
    phase = "idle",
    seq = 0,
    runId = "",
    startedAt = 0,
    finishedAt = 0,
    records = {},
    anomalies = {},
    worldAddedEvents = {},
    worldRemovedEvents = {},
    toolAddedEvents = {},
    toolRemovedEvents = {},
    inventoryEvents = {},
    connections = {},
    test = {},
    diagnostics = {
        version = CFG.VERSION,
        errors = {},
        counters = newCounters(),
        health = { checked = false },
        transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" },
        guards = {
            noNamecallHook = true,
            noSpatialPolling = true,
            noTouchWatcher = true,
            oneCrystalPerRun = true,
            boundedStaleIdReplays = 2,
            noRemoteFlood = true,
            autoStopOnCriticalAnomaly = true,
            maxRecords = CFG.MAX_RECORDS,
        },
    },
}

local function addError(phase, message)
    if #S.diagnostics.errors < CFG.MAX_ERRORS then
        S.diagnostics.errors[#S.diagnostics.errors + 1] = {
            unix = os.time(), phase = tostring(phase), error = tostring(message)
        }
    end
end

local function record(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.diagnostics.counters.droppedRecords += 1
        return nil
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = data.clock or os.clock()
    data.unix = data.unix or os.time()
    data.phase = data.phase or S.phase
    S.records[#S.records + 1] = data
    S.diagnostics.counters.records += 1
    return data
end

local function anomaly(code, severity, details)
    if #S.anomalies >= CFG.MAX_ANOMALIES then return end
    local item = {
        code = tostring(code),
        severity = tostring(severity or "warning"),
        phase = S.phase,
        clock = os.clock(),
        unix = os.time(),
        details = safe(details or {}),
    }
    S.anomalies[#S.anomalies + 1] = item
    S.diagnostics.counters.anomalies += 1
    record({ kind = "dupe_anomaly", anomaly = item })
end

local function listToolContainers()
    return {
        { obj = LP:FindFirstChildOfClass("Backpack"), label = "Backpack" },
        { obj = LP.Character, label = "Character" },
    }
end

local function candidateFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local attrs = attrsOf(tool)
    if attrs.BagId == nil or not attrs.GemName then return nil end
    return {
        instance = tool,
        bagId = attrs.BagId,
        gemName = attrs.GemName,
        kg = attrs.Kg,
        value = attrs.Value,
        rarity = attrs.Rarity,
        snapshot = toolSnapshot(tool),
    }
end

local function findCandidate()
    -- Prefer Backpack so the test does not need to manipulate equip state.
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            local item = candidateFromTool(child)
            if item then return item end
        end
    end
    if LP.Character then
        for _, child in ipairs(LP.Character:GetChildren()) do
            local item = candidateFromTool(child)
            if item then return item end
        end
    end
    return nil
end

local function findToolByBagId(bagId)
    for _, container in ipairs(listToolContainers()) do
        if container.obj then
            for _, child in ipairs(container.obj:GetChildren()) do
                if child:IsA("Tool") and tostring(child:GetAttribute("BagId")) == tostring(bagId) then
                    return child, container.label
                end
            end
        end
    end
    return nil
end

local function toolMatchesItem(tool, item, requireDifferentBag)
    if not tool or not tool:IsA("Tool") then return false end
    local gemName = tool:GetAttribute("GemName")
    if gemName ~= item.gemName then return false end
    local bagId = tool:GetAttribute("BagId")
    if bagId == nil then return false end
    if requireDifferentBag and tostring(bagId) == tostring(item.bagId) then return false end
    local kg = tool:GetAttribute("Kg")
    local value = tool:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(kg) ~= tonumber(item.kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(value) ~= tonumber(item.value) then return false end
    return true
end

local function findMatchingTool(item, requireDifferentBag)
    for _, container in ipairs(listToolContainers()) do
        if container.obj then
            for _, child in ipairs(container.obj:GetChildren()) do
                if toolMatchesItem(child, item, requireDifferentBag) then
                    return child, container.label
                end
            end
        end
    end
    return nil
end

local function crystalMatchesItem(crystal, item)
    if not crystal or not crystal.Parent then return false end
    if crystal.Name ~= item.gemName then return false end
    local kg = crystal:GetAttribute("Kg")
    local value = crystal:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(kg) ~= tonumber(item.kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(value) ~= tonumber(item.value) then return false end
    return true
end

local function countWorldUid(uid)
    if not DROPPED_GEMS or not uid then return 0, {} end
    local count, objects = 0, {}
    for _, child in ipairs(DROPPED_GEMS:GetChildren()) do
        if tostring(child:GetAttribute("Uid")) == tostring(uid) then
            count += 1
            objects[#objects + 1] = child
        end
    end
    return count, objects
end

local function countMatchingWorld(item)
    if not DROPPED_GEMS then return 0, {} end
    local count, objects = 0, {}
    for _, child in ipairs(DROPPED_GEMS:GetChildren()) do
        if crystalMatchesItem(child, item) then
            count += 1
            objects[#objects + 1] = child
        end
    end
    return count, objects
end

local function waitUntil(predicate, timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if S.cancelRequested then return nil, "cancelled" end
        local ok, a, b, c = pcall(predicate)
        if ok and a then return a, b, c end
        task.wait(CFG.POLL_STEP)
    end
    return nil, "timeout"
end

local function waitForMatchingWorld(item, afterClock, timeout)
    return waitUntil(function()
        for i = #S.worldAddedEvents, 1, -1 do
            local event = S.worldAddedEvents[i]
            if event.clock >= afterClock and event.instance and event.instance.Parent and crystalMatchesItem(event.instance, item) then
                return event.instance, event
            end
        end
        return false
    end, timeout)
end

local function waitForNewMatchingTool(item, afterClock)
    return waitUntil(function()
        for i = #S.toolAddedEvents, 1, -1 do
            local event = S.toolAddedEvents[i]
            if event.clock >= afterClock and event.instance and event.instance.Parent and toolMatchesItem(event.instance, item, true) then
                return event.instance, event
            end
        end
        local tool, label = findMatchingTool(item, true)
        if tool then return tool, { container = label, clock = os.clock(), inferred = true } end
        return false
    end, CFG.PICKUP_TIMEOUT)
end

local function findPrompt(crystal)
    if not crystal then return nil end
    for _, desc in ipairs(crystal:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then return desc end
    end
    return nil
end

local function callDrop(bagId, label)
    if not DROP_REMOTE or not DROP_REMOTE:IsA("RemoteEvent") then
        return false, "DropCrystal RemoteEvent unavailable"
    end
    local before = os.clock()
    local ok, message = pcall(function()
        DROP_REMOTE:FireServer(bagId)
    end)
    local after = os.clock()
    S.diagnostics.counters.dropCalls += 1
    record({
        kind = "controlled_drop_call",
        label = label,
        bagId = safe(bagId),
        remote = pathOf(DROP_REMOTE),
        callClock = before,
        returnClock = after,
        callDuration = math.max(0, after - before),
        success = ok,
        error = ok and nil or tostring(message),
    })
    if not ok then addError("drop_call", message) end
    return ok, message, before, after
end

local function disconnectAll()
    for _, conn in ipairs(S.connections) do
        pcall(function() conn:Disconnect() end)
    end
    S.connections = {}
end

local function watchTools(container, label)
    if not container then return end
    local added = container.ChildAdded:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolAdded += 1
        local event = {
            instance = obj,
            clock = os.clock(),
            container = label,
            snapshot = toolSnapshot(obj),
        }
        S.toolAddedEvents[#S.toolAddedEvents + 1] = event
        record({ kind = "tool_added", container = label, tool = event.snapshot, replication = true })
    end)
    local removed = container.ChildRemoved:Connect(function(obj)
        if not S.running or not obj:IsA("Tool") then return end
        S.diagnostics.counters.toolRemoved += 1
        local event = {
            instance = obj,
            clock = os.clock(),
            container = label,
            snapshot = toolSnapshot(obj),
        }
        S.toolRemovedEvents[#S.toolRemovedEvents + 1] = event
        record({ kind = "tool_removed", container = label, tool = event.snapshot, replication = true })
    end)
    S.connections[#S.connections + 1] = added
    S.connections[#S.connections + 1] = removed
end

local function installWatchers()
    watchTools(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchTools(LP.Character, "Character")

    local charConn = LP.CharacterAdded:Connect(function(char)
        if S.running then watchTools(char, "Character") end
    end)
    S.connections[#S.connections + 1] = charConn

    if INVENTORY_CHANGED and INVENTORY_CHANGED:IsA("RemoteEvent") then
        local conn = INVENTORY_CHANGED.OnClientEvent:Connect(function(...)
            if not S.running then return end
            S.diagnostics.counters.inventoryChanged += 1
            local packed = table.pack(...)
            local args = {}
            for i = 1, math.min(packed.n or #packed, CFG.MAX_ARGS) do args[i] = safe(packed[i]) end
            local event = { clock = os.clock(), args = args }
            S.inventoryEvents[#S.inventoryEvents + 1] = event
            record({ kind = "inventory_changed", arguments = args, replication = true })
        end)
        S.connections[#S.connections + 1] = conn
    end

    if DROPPED_GEMS then
        local addConn = DROPPED_GEMS.ChildAdded:Connect(function(crystal)
            if not S.running then return end
            S.diagnostics.counters.worldAdded += 1
            local event = {
                instance = crystal,
                clock = os.clock(),
                snapshot = crystalSnapshot(crystal),
            }
            S.worldAddedEvents[#S.worldAddedEvents + 1] = event
            record({ kind = "world_crystal_added", crystal = event.snapshot, replication = true })

            local uid = crystal:GetAttribute("Uid")
            if uid then
                local count = countWorldUid(uid)
                if count > 1 then
                    anomaly("DUPLICATE_UID_IN_WORLD", "critical", { uid = uid, count = count, crystal = event.snapshot })
                end
            end
        end)
        local removeConn = DROPPED_GEMS.ChildRemoved:Connect(function(crystal)
            if not S.running then return end
            S.diagnostics.counters.worldRemoved += 1
            local event = {
                instance = crystal,
                clock = os.clock(),
                snapshot = crystalSnapshot(crystal),
            }
            S.worldRemovedEvents[#S.worldRemovedEvents + 1] = event
            record({ kind = "world_crystal_removed", crystal = event.snapshot, replication = true })
        end)
        S.connections[#S.connections + 1] = addConn
        S.connections[#S.connections + 1] = removeConn
    end
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
        anomalies = #S.anomalies,
        noNamecallHook = true,
        spatialPolling = false,
        touchWatcher = false,
        controlledDropCalls = S.diagnostics.counters.dropCalls,
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
            purpose = "crystal_dupe_consistency_test",
            runId = S.runId,
            startedAt = S.startedAt,
            finishedAt = S.finishedAt,
            records = S.records,
            remotes = {
                { name = "DropCrystal", path = pathOf(DROP_REMOTE) },
                { name = "InventoryChanged", path = pathOf(INVENTORY_CHANGED) },
            },
            pickupSessions = {},
            bagMap = {},
            dupeTest = S.test,
            anomalies = S.anomalies,
            diagnostics = S.diagnostics,
        },
    }
end

local function upload()
    local payload = buildPayload()
    local encodeOk, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not encodeOk then return false, nil, "json_encode_failed" end

    local name = string.format("Cafeina_DupeTest_%s_%s.json", tostring(game.PlaceId), tostring(S.runId):gsub("-", ""))
    saveLocal(name, body)

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
            return true, receipt, nil
        end
        S.diagnostics.transport.lastError = message or (response and ("HTTP " .. tostring(response.status))) or "upload_failed"
        S.diagnostics.transport.status = "retrying"
        task.wait(attempt * 1.25)
    end

    S.diagnostics.transport.status = "failed"
    S.diagnostics.transport.serverAccepted = false
    return false, nil, S.diagnostics.transport.lastError
end

local function resetRun()
    disconnectAll()
    S.running = false
    S.sending = false
    S.finalized = false
    S.cancelRequested = false
    S.status = "preparando"
    S.phase = "prepare"
    S.seq = 0
    S.runId = HttpService:GenerateGUID(false)
    S.startedAt = os.time()
    S.finishedAt = 0
    S.records = {}
    S.anomalies = {}
    S.worldAddedEvents = {}
    S.worldRemovedEvents = {}
    S.toolAddedEvents = {}
    S.toolRemovedEvents = {}
    S.inventoryEvents = {}
    S.test = {}
    S.diagnostics.errors = {}
    S.diagnostics.counters = newCounters()
    S.diagnostics.health = { checked = false }
    S.diagnostics.transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" }
end

local function finalizeAndSend(reason)
    if S.finalized then return end
    S.finalized = true
    S.running = false
    S.finishedAt = os.time()
    S.test.finishReason = reason or "completed"
    S.test.result = (#S.anomalies > 0) and "POSSIBLE_INCONSISTENCY" or "NO_DUP_OBSERVED"
    disconnectAll()

    S.sending = true
    S.status = "enviando resultado"
    local ok, receipt, message = upload()
    S.sending = false
    if ok then
        if #S.anomalies > 0 then
            S.status = string.format("POSSÍVEL DUP: %d • ENVIADO ✓", #S.anomalies)
        else
            S.status = "SEM DUP DETECTADO • ENVIADO ✓"
        end
        S.test.githubMirrored = receipt and receipt.github and receipt.github.mirrored or false
    else
        S.status = (#S.anomalies > 0 and "POSSÍVEL DUP" or "TESTE CONCLUÍDO") .. " • ENVIO FALHOU"
        addError("upload", message or "failed")
    end
end

local function runControlledTest()
    resetRun()
    S.running = true
    installWatchers()
    task.spawn(checkHealth)

    local item = findCandidate()
    if not item then
        S.status = "ERRO: nenhum cristal no inventário"
        addError("prepare", "no Tool with BagId/GemName found")
        finalizeAndSend("no_candidate")
        return
    end

    if not DROP_REMOTE or not DROP_REMOTE:IsA("RemoteEvent") then
        S.status = "ERRO: DropCrystal não encontrado"
        addError("prepare", "ReplicatedStorage.GemSignals.DropCrystal unavailable")
        finalizeAndSend("missing_drop_remote")
        return
    end

    if not DROPPED_GEMS then
        S.status = "ERRO: DroppedGems não encontrado"
        addError("prepare", "Workspace.DroppedGems unavailable")
        finalizeAndSend("missing_dropped_gems")
        return
    end

    if type(fireproximityprompt) ~= "function" then
        S.status = "ERRO: executor sem fireproximityprompt"
        addError("prepare", "fireproximityprompt unavailable")
        finalizeAndSend("missing_fireproximityprompt")
        return
    end

    S.test = {
        selected = {
            oldBagId = safe(item.bagId),
            gemName = item.gemName,
            kg = item.kg,
            value = item.value,
            rarity = item.rarity,
            tool = item.snapshot,
        },
        phases = {},
    }
    record({ kind = "test_begin", selected = S.test.selected })

    -- Phase 1: one legitimate baseline drop.
    S.phase = "baseline_drop"
    S.status = "1/4 • drop normal"
    local ok, _, callClock = callDrop(item.bagId, "baseline")
    if not ok then
        finalizeAndSend("baseline_call_failed")
        return
    end

    local worldCrystal, worldEvent = waitForMatchingWorld(item, callClock, CFG.DROP_TIMEOUT)
    if not worldCrystal then
        anomaly("BASELINE_DROP_NO_WORLD", "critical", { bagId = item.bagId, gemName = item.gemName })
        finalizeAndSend("baseline_no_world")
        return
    end

    local uid = worldCrystal:GetAttribute("Uid")
    S.test.uid = safe(uid)
    S.test.baselineWorld = crystalSnapshot(worldCrystal)
    local oldGone = findToolByBagId(item.bagId) == nil
    local uidCount = uid and countWorldUid(uid) or 0
    S.test.phases.baseline = {
        worldSeenClock = worldEvent and worldEvent.clock or os.clock(),
        uid = safe(uid),
        oldBagIdRemoved = oldGone,
        sameUidWorldCount = uidCount,
    }
    if not oldGone then
        anomaly("WORLD_AND_OLD_BAGID_ACTIVE_AFTER_DROP", "critical", { bagId = item.bagId, uid = uid })
    end
    if uid and uidCount > 1 then
        anomaly("MULTIPLE_WORLD_OBJECTS_SAME_UID_AFTER_SINGLE_DROP", "critical", { uid = uid, count = uidCount })
    end

    -- Phase 2: replay the now-stale old BagId once while crystal is in world.
    S.phase = "stale_replay_world"
    S.status = "2/4 • replay ID antigo"
    local beforeUidCount = uid and countWorldUid(uid) or 0
    local beforeMatchingCount = countMatchingWorld(item)
    local replayMark = os.clock()
    callDrop(item.bagId, "stale_while_world")
    task.wait(CFG.REPLAY_OBSERVE)
    if S.cancelRequested then finalizeAndSend("cancelled") return end

    local afterUidCount = uid and countWorldUid(uid) or 0
    local afterMatchingCount = countMatchingWorld(item)
    local extraWorldAfterReplay = false
    for _, event in ipairs(S.worldAddedEvents) do
        if event.clock >= replayMark and event.instance and crystalMatchesItem(event.instance, item) then
            extraWorldAfterReplay = true
            break
        end
    end
    S.test.phases.staleWhileWorld = {
        beforeUidCount = beforeUidCount,
        afterUidCount = afterUidCount,
        beforeMatchingWorld = beforeMatchingCount,
        afterMatchingWorld = afterMatchingCount,
        extraMatchingWorldEvent = extraWorldAfterReplay,
    }
    if afterUidCount > beforeUidCount or afterMatchingCount > beforeMatchingCount or extraWorldAfterReplay then
        anomaly("STALE_BAGID_ACCEPTED_WHILE_WORLD", "critical", {
            oldBagId = item.bagId,
            uid = uid,
            beforeUidCount = beforeUidCount,
            afterUidCount = afterUidCount,
            beforeMatching = beforeMatchingCount,
            afterMatching = afterMatchingCount,
        })
        finalizeAndSend("critical_stale_world")
        return
    end

    -- Phase 3: pick the exact world crystal back up once and learn the new BagId.
    S.phase = "pickup_reissue"
    S.status = "3/4 • pickup + novo BagId"
    if not worldCrystal.Parent then
        anomaly("BASELINE_WORLD_DISAPPEARED_BEFORE_PICKUP", "critical", { uid = uid })
        finalizeAndSend("world_missing_before_pickup")
        return
    end

    local prompt = findPrompt(worldCrystal)
    if not prompt then
        anomaly("PICKUP_PROMPT_NOT_FOUND", "critical", { crystal = crystalSnapshot(worldCrystal) })
        finalizeAndSend("prompt_missing")
        return
    end

    local pickupClock = os.clock()
    local promptOk, promptErr = pcall(fireproximityprompt, prompt)
    record({ kind = "controlled_pickup_prompt", prompt = pathOf(prompt), success = promptOk, error = promptOk and nil or tostring(promptErr) })
    if not promptOk then
        addError("pickup", promptErr)
        finalizeAndSend("prompt_fire_failed")
        return
    end

    local newTool = waitForNewMatchingTool(item, pickupClock)
    if not newTool then
        anomaly("PICKUP_DID_NOT_CREATE_NEW_INVENTORY_ENTRY", "critical", { oldBagId = item.bagId, uid = uid })
        finalizeAndSend("pickup_no_new_tool")
        return
    end

    local newBagId = newTool:GetAttribute("BagId")
    S.test.newBagId = safe(newBagId)
    local worldRemoved = waitUntil(function()
        return not worldCrystal.Parent
    end, CFG.PICKUP_TIMEOUT)
    local remainingUidCount = uid and countWorldUid(uid) or 0
    S.test.phases.pickup = {
        newBagId = safe(newBagId),
        oldBagId = safe(item.bagId),
        bagIdChanged = tostring(newBagId) ~= tostring(item.bagId),
        originalWorldRemoved = worldRemoved == true,
        remainingSameUidWorld = remainingUidCount,
        newTool = toolSnapshot(newTool),
    }
    if tostring(newBagId) == tostring(item.bagId) then
        anomaly("BAGID_REUSED_AFTER_PICKUP", "warning", { bagId = newBagId, uid = uid })
    end
    if remainingUidCount > 0 and newTool.Parent then
        anomaly("SAME_UID_WORLD_AND_INVENTORY_SIMULTANEOUS", "critical", {
            uid = uid,
            newBagId = newBagId,
            worldCount = remainingUidCount,
        })
        finalizeAndSend("world_inventory_overlap")
        return
    end

    -- Phase 4: replay the old BagId once after the same crystal has a new BagId.
    S.phase = "stale_replay_after_reissue"
    S.status = "4/4 • validar ID invalidado"
    local oldReplayMark = os.clock()
    local beforeWorld = countMatchingWorld(item)
    local newToolWasPresent = findToolByBagId(newBagId) ~= nil
    callDrop(item.bagId, "stale_after_reissue")
    task.wait(CFG.REPLAY_OBSERVE)
    if S.cancelRequested then finalizeAndSend("cancelled") return end

    local afterWorld = countMatchingWorld(item)
    local newToolStillPresent = findToolByBagId(newBagId) ~= nil
    local replayCreatedWorld = false
    for _, event in ipairs(S.worldAddedEvents) do
        if event.clock >= oldReplayMark and event.instance and crystalMatchesItem(event.instance, item) then
            replayCreatedWorld = true
            break
        end
    end

    S.test.phases.staleAfterReissue = {
        oldBagId = safe(item.bagId),
        currentBagId = safe(newBagId),
        newToolWasPresent = newToolWasPresent,
        newToolStillPresent = newToolStillPresent,
        beforeMatchingWorld = beforeWorld,
        afterMatchingWorld = afterWorld,
        replayCreatedWorld = replayCreatedWorld,
    }

    if (newToolWasPresent and not newToolStillPresent) or afterWorld > beforeWorld or replayCreatedWorld then
        anomaly("STALE_BAGID_ACCEPTED_AFTER_REISSUE", "critical", {
            oldBagId = item.bagId,
            currentBagId = newBagId,
            newToolStillPresent = newToolStillPresent,
            beforeWorld = beforeWorld,
            afterWorld = afterWorld,
            replayCreatedWorld = replayCreatedWorld,
        })
        finalizeAndSend("critical_stale_reissue")
        return
    end

    S.phase = "complete"
    S.status = "teste concluído • enviando"
    record({
        kind = "test_complete",
        oldBagId = safe(item.bagId),
        newBagId = safe(newBagId),
        uid = safe(uid),
        anomalyCount = #S.anomalies,
    })
    finalizeAndSend("completed")
end

-- Stop older scanner runtimes so no previous collector handler competes with this test.
for _, key in ipairs({
    "__CAFEINA_INVTRACE_RUNTIME_V64",
    "__CAFEINA_INVTRACE_RUNTIME_NOHOOK",
}) do
    local runtime = rawget(ENV, key)
    if type(runtime) == "table" then
        local fn = runtime.cleanup or runtime.stop
        if type(fn) == "function" then pcall(fn) end
    end
end

local RUNTIME_KEY = "__CAFEINA_DUP_TEST_RUNTIME_V1"
local previous = rawget(ENV, RUNTIME_KEY)
if type(previous) == "table" and type(previous.cleanup) == "function" then pcall(previous.cleanup) end

--============================== UI ==============================
for _, parent in ipairs({ CoreGui, LP:FindFirstChildOfClass("PlayerGui") }) do
    if parent then
        local old = parent:FindFirstChild("CafeinaDupeTestV1")
        if old then pcall(function() old:Destroy() end) end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaDupeTestV1"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(304, 226)
frame.Position = UDim2.new(0.5, -152, 0.16, 0)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
frame.BackgroundTransparency = 0.04
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -18, 0, 30)
title.Position = UDim2.fromOffset(9, 7)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • DUP TEST V1"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1, -18, 0, 36)
selectedLabel.Position = UDim2.fromOffset(9, 38)
selectedLabel.BackgroundColor3 = Color3.fromRGB(21, 21, 24)
selectedLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
selectedLabel.TextSize = 11
selectedLabel.Font = Enum.Font.Code
selectedLabel.TextWrapped = true
selectedLabel.Parent = frame
Instance.new("UICorner", selectedLabel).CornerRadius = UDim.new(0, 8)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -18, 0, 54)
statusLabel.Position = UDim2.fromOffset(9, 79)
statusLabel.BackgroundColor3 = Color3.fromRGB(21, 21, 24)
statusLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Code
statusLabel.TextWrapped = true
statusLabel.Parent = frame
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

local testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(1, -18, 0, 38)
testBtn.Position = UDim2.fromOffset(9, 141)
testBtn.BackgroundColor3 = Color3.fromRGB(42, 42, 47)
testBtn.TextColor3 = Color3.new(1, 1, 1)
testBtn.TextSize = 12
testBtn.Font = Enum.Font.GothamBold
testBtn.Text = "TESTAR DUP"
testBtn.Parent = frame
Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0, 8)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -18, 0, 32)
stopBtn.Position = UDim2.fromOffset(9, 186)
stopBtn.BackgroundColor3 = Color3.fromRGB(105, 25, 31)
stopBtn.TextColor3 = Color3.new(1, 1, 1)
stopBtn.TextSize = 11
stopBtn.Font = Enum.Font.GothamBold
stopBtn.Text = "PARAR + ENVIAR PARCIAL"
stopBtn.Parent = frame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 8)

local function cleanup()
    S.cancelRequested = true
    disconnectAll()
    S.running = false
    pcall(function() gui:Destroy() end)
end

ENV[RUNTIME_KEY] = { cleanup = cleanup, state = S }

testBtn.MouseButton1Click:Connect(function()
    if S.running or S.sending then return end
    task.spawn(runControlledTest)
end)

stopBtn.MouseButton1Click:Connect(function()
    if S.running and not S.sending and not S.finalized then
        S.cancelRequested = true
        S.phase = "cancelled"
        S.status = "parando • enviando parcial"
        task.spawn(function()
            task.wait(0.08)
            finalizeAndSend("user_cancelled")
        end)
    end
end)

task.spawn(function()
    while gui.Parent do
        local candidate = (not S.running and not S.sending) and findCandidate() or nil
        if candidate then
            selectedLabel.Text = string.format("Cristal: %s • BagId %s\n%s kg • $%s", tostring(candidate.gemName), tostring(candidate.bagId), tostring(candidate.kg or "?"), tostring(candidate.value or "?"))
        elseif S.test.selected then
            selectedLabel.Text = string.format("Teste: %s • antigo %s • novo %s", tostring(S.test.selected.gemName), tostring(S.test.selected.oldBagId), tostring(S.test.newBagId or "..."))
        else
            selectedLabel.Text = "Cristal: nenhum Tool com BagId encontrado"
        end

        statusLabel.Text = string.format(
            "Status: %s\nFase: %s • Anomalias: %d • Reg: %d",
            tostring(S.status), tostring(S.phase), #S.anomalies, S.diagnostics.counters.records
        )

        local busy = S.running or S.sending
        testBtn.Active = not busy
        testBtn.AutoButtonColor = not busy
        testBtn.Text = S.sending and "ENVIANDO..." or (S.running and "TESTE EM ANDAMENTO" or "TESTAR DUP")
        stopBtn.Active = S.running and not S.sending
        stopBtn.AutoButtonColor = S.running and not S.sending
        task.wait(0.35)
    end
end)

return {
    Run = runControlledTest,
    StopAndSend = function()
        if S.running and not S.finalized then
            S.cancelRequested = true
            finalizeAndSend("external_stop")
        end
    end,
    Cleanup = cleanup,
    State = S,
    Version = CFG.VERSION,
}
