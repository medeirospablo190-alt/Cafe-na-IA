--==============================================================
-- CAFEINA • CRYSTAL DUP CONSISTENCY TEST V1.1
-- Controlled stale-BagId/state validator for an authorized game
-- No hook • no touch watcher • no spatial scanner • max 3 DropCrystal calls
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_CRYSTAL_DUP_CONSISTENCY_V1_1",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    DROP_TIMEOUT = 3.5,
    PICKUP_TIMEOUT = 4.0,
    REPLAY_WINDOW = 1.15,
    WAIT_STEP = 0.04,
    MAX_RECORDS = 500,
    MAX_ANOMALIES = 16,
    RETRIES = 3,
}

local GemSignals = ReplicatedStorage:FindFirstChild("GemSignals")
local GemRemotes = ReplicatedStorage:FindFirstChild("GemRemotes")
local DropCrystal = GemSignals and GemSignals:FindFirstChild("DropCrystal")
local InventoryChanged = GemRemotes and GemRemotes:FindFirstChild("InventoryChanged")
local DroppedGems = Workspace:FindFirstChild("DroppedGems")

local function resolveRequest()
    local list = {
        ENV and ENV.request, ENV and ENV.http_request,
        request, http_request,
        syn and syn.request,
        http and http.request,
    }
    for _, fn in ipairs(list) do
        if type(fn) == "function" then return fn end
    end
end
local REQUEST = resolveRequest()

local function pathOf(obj)
    if not obj then return "nil" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj)
end

local function attrs(obj)
    local out = {}
    if not obj then return out end
    pcall(function()
        for k, v in pairs(obj:GetAttributes()) do
            local t = typeof(v)
            out[k] = (t == "string" or t == "number" or t == "boolean" or t == "nil") and v or tostring(v)
        end
    end)
    return out
end

local function toolSnap(tool)
    return tool and { name = tool.Name, path = pathOf(tool), attributes = attrs(tool) } or nil
end

local function crystalSnap(crystal)
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
        attributes = attrs(crystal),
    }
end

local S = {
    running = false,
    sending = false,
    finalized = false,
    cancel = false,
    phase = "idle",
    status = "aguardando",
    runId = "",
    startedAt = 0,
    finishedAt = 0,
    seq = 0,
    records = {},
    anomalies = {},
    connections = {},
    worldAdded = {},
    toolAdded = {},
    inventoryChanged = {},
    test = {},
    diagnostics = {
        version = CFG.VERSION,
        errors = {},
        counters = {
            records = 0, anomalies = 0, dropCalls = 0,
            worldAdded = 0, worldRemoved = 0,
            toolAdded = 0, toolRemoved = 0,
            inventoryChanged = 0, uploadAttempts = 0,
            droppedRecords = 0,
        },
        health = { checked = false },
        transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" },
        guards = {
            noHook = true,
            noTouchWatcher = true,
            noSpatialPolling = true,
            maxControlledDropCalls = 3,
            staleBagIdReplays = 2,
            oneCrystalPerRun = true,
            noFlood = true,
        },
    },
}

local function errorLog(phase, message)
    if #S.diagnostics.errors < 16 then
        S.diagnostics.errors[#S.diagnostics.errors + 1] = { phase = phase, error = tostring(message), unix = os.time() }
    end
end

local function rec(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.diagnostics.counters.droppedRecords += 1
        return
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = data.clock or os.clock()
    data.unix = data.unix or os.time()
    data.phase = data.phase or S.phase
    S.records[#S.records + 1] = data
    S.diagnostics.counters.records += 1
end

local function flag(code, severity, details)
    if #S.anomalies >= CFG.MAX_ANOMALIES then return end
    local item = { code = code, severity = severity or "warning", phase = S.phase, clock = os.clock(), details = details or {} }
    S.anomalies[#S.anomalies + 1] = item
    S.diagnostics.counters.anomalies += 1
    rec({ kind = "dupe_anomaly", anomaly = item })
end

local function containers()
    return { LP:FindFirstChildOfClass("Backpack"), LP.Character }
end

local function itemFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local a = attrs(tool)
    if a.BagId == nil or not a.GemName then return nil end
    return {
        tool = tool,
        bagId = a.BagId,
        gemName = a.GemName,
        kg = a.Kg,
        value = a.Value,
        rarity = a.Rarity,
        snapshot = toolSnap(tool),
    }
end

local function chooseItem()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            local item = itemFromTool(obj)
            if item then return item end
        end
    end
    if LP.Character then
        for _, obj in ipairs(LP.Character:GetChildren()) do
            local item = itemFromTool(obj)
            if item then return item end
        end
    end
end

local function findBag(bagId)
    for _, container in ipairs(containers()) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and tostring(obj:GetAttribute("BagId")) == tostring(bagId) then return obj end
            end
        end
    end
end

local function toolMatches(obj, item)
    if not obj or not obj:IsA("Tool") then return false end
    if obj:GetAttribute("GemName") ~= item.gemName or obj:GetAttribute("BagId") == nil then return false end
    local kg, value = obj:GetAttribute("Kg"), obj:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(item.kg) ~= tonumber(kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(item.value) ~= tonumber(value) then return false end
    return true
end

local function crystalMatches(obj, item)
    if not obj or not obj.Parent or obj.Name ~= item.gemName then return false end
    local kg, value = obj:GetAttribute("Kg"), obj:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(item.kg) ~= tonumber(kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(item.value) ~= tonumber(value) then return false end
    return true
end

local function matchingWorldCount(item)
    if not DroppedGems then return 0 end
    local n = 0
    for _, obj in ipairs(DroppedGems:GetChildren()) do if crystalMatches(obj, item) then n += 1 end end
    return n
end

local function uidWorldCount(uid)
    if not DroppedGems or uid == nil then return 0 end
    local n = 0
    for _, obj in ipairs(DroppedGems:GetChildren()) do
        if tostring(obj:GetAttribute("Uid")) == tostring(uid) then n += 1 end
    end
    return n
end

local function waitFor(predicate, timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if S.cancel then return nil, "cancelled" end
        local ok, a, b = pcall(predicate)
        if ok and a then return a, b end
        task.wait(CFG.WAIT_STEP)
    end
    return nil, "timeout"
end

local function disconnect()
    for _, c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    S.connections = {}
end

local function installWatchers()
    local function watchContainer(container, label)
        if not container then return end
        local a = container.ChildAdded:Connect(function(obj)
            if not S.running or not obj:IsA("Tool") then return end
            local event = { instance = obj, clock = os.clock(), label = label, snapshot = toolSnap(obj) }
            S.toolAdded[#S.toolAdded + 1] = event
            S.diagnostics.counters.toolAdded += 1
            rec({ kind = "tool_added", container = label, tool = event.snapshot })
        end)
        local r = container.ChildRemoved:Connect(function(obj)
            if not S.running or not obj:IsA("Tool") then return end
            S.diagnostics.counters.toolRemoved += 1
            rec({ kind = "tool_removed", container = label, tool = toolSnap(obj) })
        end)
        S.connections[#S.connections + 1] = a
        S.connections[#S.connections + 1] = r
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")
    S.connections[#S.connections + 1] = LP.CharacterAdded:Connect(function(char)
        if S.running then watchContainer(char, "Character") end
    end)

    if InventoryChanged and InventoryChanged:IsA("RemoteEvent") then
        S.connections[#S.connections + 1] = InventoryChanged.OnClientEvent:Connect(function(...)
            if not S.running then return end
            local args = table.pack(...)
            local clean = {}
            for i = 1, math.min(args.n or #args, 8) do clean[i] = tostring(args[i]) end
            local event = { clock = os.clock(), arguments = clean }
            S.inventoryChanged[#S.inventoryChanged + 1] = event
            S.diagnostics.counters.inventoryChanged += 1
            rec({ kind = "inventory_changed", arguments = clean })
        end)
    end

    if DroppedGems then
        S.connections[#S.connections + 1] = DroppedGems.ChildAdded:Connect(function(obj)
            if not S.running then return end
            local event = { instance = obj, clock = os.clock(), snapshot = crystalSnap(obj) }
            S.worldAdded[#S.worldAdded + 1] = event
            S.diagnostics.counters.worldAdded += 1
            rec({ kind = "world_added", crystal = event.snapshot })
            local uid = obj:GetAttribute("Uid")
            if uid and uidWorldCount(uid) > 1 then
                flag("DUPLICATE_UID_IN_WORLD", "critical", { uid = uid, count = uidWorldCount(uid) })
            end
        end)
        S.connections[#S.connections + 1] = DroppedGems.ChildRemoved:Connect(function(obj)
            if not S.running then return end
            S.diagnostics.counters.worldRemoved += 1
            rec({ kind = "world_removed", crystal = crystalSnap(obj) })
        end)
    end
end

local function latestWorld(item, afterClock)
    for i = #S.worldAdded, 1, -1 do
        local e = S.worldAdded[i]
        if e.clock >= afterClock and e.instance and e.instance.Parent and crystalMatches(e.instance, item) then return e.instance, e end
    end
end

local function waitWorld(item, afterClock)
    return waitFor(function() return latestWorld(item, afterClock) end, CFG.DROP_TIMEOUT)
end

local function waitMatchingTool(item, afterClock)
    return waitFor(function()
        for i = #S.toolAdded, 1, -1 do
            local e = S.toolAdded[i]
            if e.clock >= afterClock and e.instance and e.instance.Parent and toolMatches(e.instance, item) then return e.instance, e end
        end
        return false
    end, CFG.PICKUP_TIMEOUT)
end

local function findPrompt(crystal)
    if not crystal then return nil end
    for _, d in ipairs(crystal:GetDescendants()) do if d:IsA("ProximityPrompt") then return d end end
end

local function controlledDrop(bagId, label)
    if not DropCrystal or not DropCrystal:IsA("RemoteEvent") then return false, "DropCrystal unavailable" end
    if S.diagnostics.counters.dropCalls >= 3 then return false, "drop call guard reached" end
    local t0 = os.clock()
    local ok, err = pcall(function() DropCrystal:FireServer(bagId) end)
    local t1 = os.clock()
    S.diagnostics.counters.dropCalls += 1
    rec({ kind = "controlled_drop_call", label = label, bagId = bagId, callClock = t0, returnClock = t1, success = ok, error = ok and nil or tostring(err) })
    if not ok then errorLog("DropCrystal", err) end
    return ok, err, t0
end

local function httpRequest(options)
    if not REQUEST then return false, nil, "request unavailable" end
    local ok, response = pcall(REQUEST, options)
    if not ok or not response then return false, nil, tostring(response) end
    local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body = tostring(response.Body or response.body or "")
    return status >= 200 and status < 300, { status = status, body = body }, nil
end

local function checkHealth()
    S.diagnostics.health.checked = true
    local ok, response, err = httpRequest({ Url = CFG.HEALTH, Method = "GET", Headers = { Accept = "application/json" } })
    S.diagnostics.health.ok = ok
    if ok then
        S.diagnostics.health.httpStatus = response.status
        local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, response.body)
        if decodeOk and type(data) == "table" then S.diagnostics.health.githubMirrorConfigured = data.githubMirrorConfigured end
    else
        S.diagnostics.health.error = err
    end
end

local function payload()
    S.diagnostics.operation = {
        startedAt = S.startedAt, finishedAt = S.finishedAt,
        durationSeconds = math.max(0, S.finishedAt - S.startedAt),
        controlledDropCalls = S.diagnostics.counters.dropCalls,
        noHook = true, noTouchWatcher = true, spatialPolling = false,
    }
    S.diagnostics.transport.status = "pending_at_send"
    return {
        schemaVersion = 1,
        userId = tostring(LP.UserId), username = LP.Name,
        capturedAt = DateTime.now():ToIsoDate(),
        placeId = game.PlaceId, gameId = game.GameId, runId = S.runId,
        trace = {
            version = CFG.VERSION,
            purpose = "crystal_dupe_consistency_test",
            runId = S.runId, startedAt = S.startedAt, finishedAt = S.finishedAt,
            records = S.records,
            remotes = { { name = "DropCrystal", path = pathOf(DropCrystal) }, { name = "InventoryChanged", path = pathOf(InventoryChanged) } },
            pickupSessions = {}, bagMap = {},
            dupeTest = S.test, anomalies = S.anomalies,
            diagnostics = S.diagnostics,
        },
    }
end

local function upload()
    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload())
    if not okEncode then return false, nil, "json encode failed" end
    if type(writefile) == "function" then
        pcall(writefile, "Cafeina_DupeTest_" .. tostring(game.PlaceId) .. "_" .. S.runId:gsub("-", "") .. ".json", body)
    end
    for attempt = 1, CFG.RETRIES do
        S.diagnostics.counters.uploadAttempts += 1
        S.diagnostics.transport.status = "sending"
        local ok, response, err = httpRequest({
            Url = CFG.ENDPOINT, Method = "POST",
            Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
            Body = body,
        })
        if ok then
            local receipt
            pcall(function() receipt = HttpService:JSONDecode(response.body) end)
            S.diagnostics.transport.status = "accepted"
            S.diagnostics.transport.serverAccepted = true
            S.diagnostics.transport.httpStatus = response.status
            S.diagnostics.transport.githubMirrored = receipt and receipt.github and receipt.github.mirrored or false
            return true, receipt
        end
        S.diagnostics.transport.lastError = err or (response and response.status) or "failed"
        task.wait(attempt * 1.2)
    end
    S.diagnostics.transport.status = "failed"
    return false
end

local function resetRun()
    disconnect()
    S.running, S.sending, S.finalized, S.cancel = false, false, false, false
    S.phase, S.status = "prepare", "preparando"
    S.runId = HttpService:GenerateGUID(false)
    S.startedAt, S.finishedAt, S.seq = os.time(), 0, 0
    S.records, S.anomalies, S.worldAdded, S.toolAdded, S.inventoryChanged = {}, {}, {}, {}, {}
    S.test = {}
    S.diagnostics.errors = {}
    S.diagnostics.counters = { records=0, anomalies=0, dropCalls=0, worldAdded=0, worldRemoved=0, toolAdded=0, toolRemoved=0, inventoryChanged=0, uploadAttempts=0, droppedRecords=0 }
    S.diagnostics.health = { checked = false }
    S.diagnostics.transport = { endpoint = CFG.ENDPOINT, retries = CFG.RETRIES, status = "not_started" }
end

local function finish(reason)
    if S.finalized then return end
    S.finalized = true
    S.running = false
    S.finishedAt = os.time()
    S.test.finishReason = reason
    S.test.result = (#S.anomalies > 0) and "POSSIBLE_INCONSISTENCY" or "NO_DUP_OBSERVED"
    disconnect()
    S.sending = true
    S.status = "enviando resultado"
    local ok, receipt = upload()
    S.sending = false
    local mirrored = receipt and receipt.github and receipt.github.mirrored
    if ok then
        S.status = (#S.anomalies > 0 and ("POSSÍVEL DUP: " .. #S.anomalies) or "SEM DUP DETECTADO") .. (mirrored and " • GITHUB ✓" or " • RENDER ✓")
    else
        S.status = (#S.anomalies > 0 and "POSSÍVEL DUP" or "TESTE CONCLUÍDO") .. " • ENVIO FALHOU"
    end
end

local function runTest()
    resetRun()
    S.running = true
    installWatchers()
    task.spawn(checkHealth)

    local item = chooseItem()
    if not item then errorLog("prepare", "no crystal Tool with BagId/GemName"); S.status = "sem cristal no inventário"; finish("no_candidate"); return end
    if not DropCrystal or not DropCrystal:IsA("RemoteEvent") then errorLog("prepare", "DropCrystal missing"); S.status = "DropCrystal ausente"; finish("missing_remote"); return end
    if not DroppedGems then errorLog("prepare", "DroppedGems missing"); S.status = "DroppedGems ausente"; finish("missing_folder"); return end
    if type(fireproximityprompt) ~= "function" then errorLog("prepare", "fireproximityprompt unavailable"); S.status = "executor sem fireproximityprompt"; finish("missing_prompt_api"); return end

    S.test.selected = { oldBagId=item.bagId, gemName=item.gemName, kg=item.kg, value=item.value, rarity=item.rarity, tool=item.snapshot }
    S.test.phases = {}
    rec({ kind = "test_begin", selected = S.test.selected })

    -- 1. Normal drop establishes the world Uid for this exact inventory item.
    S.phase, S.status = "baseline_drop", "1/4 • drop normal"
    local ok, _, baseClock = controlledDrop(item.bagId, "baseline")
    if not ok then finish("baseline_call_failed"); return end
    local world, worldEvent = waitWorld(item, baseClock)
    if not world then flag("BASELINE_DROP_NO_WORLD", "critical", { bagId=item.bagId }); finish("baseline_no_world"); return end

    local uid = world:GetAttribute("Uid")
    S.test.uid = uid
    local oldGone = findBag(item.bagId) == nil
    local uidCount = uidWorldCount(uid)
    S.test.phases.baseline = { uid=uid, world=crystalSnap(world), oldBagIdRemoved=oldGone, uidWorldCount=uidCount, worldClock=worldEvent and worldEvent.clock }
    if not oldGone then flag("WORLD_AND_OLD_BAGID_ACTIVE_AFTER_DROP", "critical", { bagId=item.bagId, uid=uid }); finish("baseline_overlap"); return end
    if uid and uidCount > 1 then flag("MULTIPLE_WORLD_OBJECTS_SAME_UID_AFTER_SINGLE_DROP", "critical", { uid=uid, count=uidCount }); finish("baseline_duplicate_uid"); return end

    -- 2. Replay the invalidated old BagId once while the crystal is already in world.
    S.phase, S.status = "stale_replay_world", "2/4 • replay ID antigo"
    local beforeWorld, beforeUid, beforeInv = matchingWorldCount(item), uidWorldCount(uid), #S.inventoryChanged
    local _, _, replayClock = controlledDrop(item.bagId, "stale_while_world")
    task.wait(CFG.REPLAY_WINDOW)
    if S.cancel then finish("cancelled"); return end
    local afterWorld, afterUid, afterInv = matchingWorldCount(item), uidWorldCount(uid), #S.inventoryChanged
    local extraWorld = false
    for _, e in ipairs(S.worldAdded) do if e.clock >= replayClock and e.instance and crystalMatches(e.instance, item) then extraWorld = true break end end
    S.test.phases.staleWhileWorld = { beforeWorld=beforeWorld, afterWorld=afterWorld, beforeUid=beforeUid, afterUid=afterUid, inventoryEvents=afterInv-beforeInv, extraWorld=extraWorld }
    if afterWorld > beforeWorld or afterUid > beforeUid or extraWorld then
        flag("STALE_BAGID_ACCEPTED_WHILE_WORLD", "critical", S.test.phases.staleWhileWorld); finish("stale_world_mutation"); return
    elseif afterInv > beforeInv then
        flag("STALE_REPLAY_TRIGGERED_INVENTORY_CHANGED", "warning", { stage="while_world", count=afterInv-beforeInv })
    end

    -- 3. Pick the same world object up exactly once and learn the server-issued BagId.
    S.phase, S.status = "pickup_reissue", "3/4 • pickup + novo BagId"
    if not world.Parent then flag("WORLD_DISAPPEARED_BEFORE_CONTROLLED_PICKUP", "critical", { uid=uid }); finish("world_missing"); return end
    local prompt = findPrompt(world)
    if not prompt then flag("PICKUP_PROMPT_NOT_FOUND", "critical", { uid=uid }); finish("prompt_missing"); return end
    local pickupClock = os.clock()
    local promptOk, promptErr = pcall(fireproximityprompt, prompt)
    rec({ kind="controlled_pickup", prompt=pathOf(prompt), success=promptOk, error=promptOk and nil or tostring(promptErr) })
    if not promptOk then errorLog("pickup", promptErr); finish("pickup_call_failed"); return end
    local newTool = waitMatchingTool(item, pickupClock)
    if not newTool then flag("PICKUP_NO_INVENTORY_ENTRY", "critical", { uid=uid }); finish("pickup_no_tool"); return end
    local newBagId = newTool:GetAttribute("BagId")
    S.test.newBagId = newBagId
    local removed = waitFor(function() return not world.Parent end, CFG.PICKUP_TIMEOUT)
    local remainingUid = uidWorldCount(uid)
    S.test.phases.pickup = { oldBagId=item.bagId, newBagId=newBagId, bagIdChanged=tostring(newBagId)~=tostring(item.bagId), worldRemoved=removed==true, remainingUidWorld=remainingUid, tool=toolSnap(newTool) }
    if tostring(newBagId) == tostring(item.bagId) then flag("BAGID_REUSED_AFTER_PICKUP", "warning", { bagId=newBagId, uid=uid }) end
    if remainingUid > 0 and newTool.Parent then flag("SAME_UID_WORLD_AND_INVENTORY_SIMULTANEOUS", "critical", { uid=uid, newBagId=newBagId, worldCount=remainingUid }); finish("world_inventory_overlap"); return end

    -- 4. Replay the first BagId once more after the same crystal has a current BagId.
    S.phase, S.status = "stale_replay_after_reissue", "4/4 • validar ID invalidado"
    local beforeWorld2, beforeInv2 = matchingWorldCount(item), #S.inventoryChanged
    local newWasPresent = findBag(newBagId) ~= nil
    local _, _, replayClock2 = controlledDrop(item.bagId, "stale_after_reissue")
    task.wait(CFG.REPLAY_WINDOW)
    if S.cancel then finish("cancelled"); return end
    local afterWorld2, afterInv2 = matchingWorldCount(item), #S.inventoryChanged
    local newStillPresent = findBag(newBagId) ~= nil
    local replayWorld = false
    for _, e in ipairs(S.worldAdded) do if e.clock >= replayClock2 and e.instance and crystalMatches(e.instance, item) then replayWorld = true break end end
    S.test.phases.staleAfterReissue = { oldBagId=item.bagId, currentBagId=newBagId, newWasPresent=newWasPresent, newStillPresent=newStillPresent, beforeWorld=beforeWorld2, afterWorld=afterWorld2, inventoryEvents=afterInv2-beforeInv2, extraWorld=replayWorld }
    if (newWasPresent and not newStillPresent) or afterWorld2 > beforeWorld2 or replayWorld then
        flag("STALE_BAGID_ACCEPTED_AFTER_REISSUE", "critical", S.test.phases.staleAfterReissue); finish("stale_reissue_mutation"); return
    elseif afterInv2 > beforeInv2 then
        flag("STALE_REPLAY_TRIGGERED_INVENTORY_CHANGED", "warning", { stage="after_reissue", count=afterInv2-beforeInv2 })
    end

    S.phase, S.status = "complete", "teste concluído • enviando"
    rec({ kind="test_complete", oldBagId=item.bagId, newBagId=newBagId, uid=uid, anomalies=#S.anomalies })
    finish("completed")
end

-- Shut down older CAFEINA collectors so their handlers/connections do not compete.
for _, key in ipairs({ "__CAFEINA_INVTRACE_RUNTIME_V64", "__CAFEINA_INVTRACE_RUNTIME_NOHOOK" }) do
    local rt = rawget(ENV, key)
    if type(rt) == "table" then
        local fn = rt.cleanup or rt.stop
        if type(fn) == "function" then pcall(fn) end
    end
end

local RUNTIME_KEY = "__CAFEINA_DUP_TEST_RUNTIME_V11"
local previous = rawget(ENV, RUNTIME_KEY)
if type(previous) == "table" and type(previous.cleanup) == "function" then pcall(previous.cleanup) end

for _, parent in ipairs({ CoreGui, LP:FindFirstChildOfClass("PlayerGui") }) do
    if parent then
        local old = parent:FindFirstChild("CafeinaDupeTestV11")
        if old then pcall(function() old:Destroy() end) end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaDupeTestV11"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(304, 224)
frame.Position = UDim2.new(0.5, -152, 0.16, 0)
frame.BackgroundColor3 = Color3.fromRGB(12,12,14)
frame.BackgroundTransparency = 0.04
frame.BorderSizePixel = 0
frame.Active, frame.Draggable = true, true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-18,0,28); title.Position = UDim2.fromOffset(9,7)
title.BackgroundTransparency = 1; title.Text = "CAFEINA • DUP TEST V1.1"
title.TextColor3 = Color3.new(1,1,1); title.TextSize = 14; title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = frame

local selected = Instance.new("TextLabel")
selected.Size = UDim2.new(1,-18,0,38); selected.Position = UDim2.fromOffset(9,38)
selected.BackgroundColor3 = Color3.fromRGB(21,21,24); selected.TextColor3 = Color3.fromRGB(225,225,230)
selected.TextSize = 11; selected.Font = Enum.Font.Code; selected.TextWrapped = true; selected.Parent = frame
Instance.new("UICorner", selected).CornerRadius = UDim.new(0,8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-18,0,54); status.Position = UDim2.fromOffset(9,82)
status.BackgroundColor3 = Color3.fromRGB(21,21,24); status.TextColor3 = Color3.fromRGB(225,225,230)
status.TextSize = 11; status.Font = Enum.Font.Code; status.TextWrapped = true; status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0,8)

local testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(1,-18,0,38); testBtn.Position = UDim2.fromOffset(9,143)
testBtn.BackgroundColor3 = Color3.fromRGB(42,42,47); testBtn.TextColor3 = Color3.new(1,1,1)
testBtn.TextSize = 12; testBtn.Font = Enum.Font.GothamBold; testBtn.Text = "TESTAR DUP"; testBtn.Parent = frame
Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0,8)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1,-18,0,30); stopBtn.Position = UDim2.fromOffset(9,188)
stopBtn.BackgroundColor3 = Color3.fromRGB(105,25,31); stopBtn.TextColor3 = Color3.new(1,1,1)
stopBtn.TextSize = 11; stopBtn.Font = Enum.Font.GothamBold; stopBtn.Text = "PARAR + ENVIAR PARCIAL"; stopBtn.Parent = frame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0,8)

local function cleanup()
    S.cancel = true
    disconnect()
    S.running = false
    pcall(function() gui:Destroy() end)
end
ENV[RUNTIME_KEY] = { cleanup=cleanup, state=S }

testBtn.MouseButton1Click:Connect(function()
    if not S.running and not S.sending then task.spawn(runTest) end
end)
stopBtn.MouseButton1Click:Connect(function()
    if S.running and not S.sending and not S.finalized then
        S.cancel = true; S.phase = "cancelled"; S.status = "parando • enviando parcial"
        task.spawn(function() task.wait(0.08); finish("user_cancelled") end)
    end
end)

task.spawn(function()
    while gui.Parent do
        local candidate = (not S.running and not S.sending) and chooseItem() or nil
        if candidate then
            selected.Text = string.format("Cristal: %s • BagId %s\n%s kg • $%s", tostring(candidate.gemName), tostring(candidate.bagId), tostring(candidate.kg or "?"), tostring(candidate.value or "?"))
        elseif S.test.selected then
            selected.Text = string.format("Teste: %s • antigo %s • novo %s", tostring(S.test.selected.gemName), tostring(S.test.selected.oldBagId), tostring(S.test.newBagId or "..."))
        else
            selected.Text = "Cristal: nenhum Tool com BagId encontrado"
        end
        status.Text = string.format("Status: %s\nFase: %s • Alertas: %d • Reg: %d", tostring(S.status), tostring(S.phase), #S.anomalies, S.diagnostics.counters.records)
        local busy = S.running or S.sending
        testBtn.Active, testBtn.AutoButtonColor = not busy, not busy
        testBtn.Text = S.sending and "ENVIANDO..." or (S.running and "TESTE EM ANDAMENTO" or "TESTAR DUP")
        stopBtn.Active, stopBtn.AutoButtonColor = S.running and not S.sending, S.running and not S.sending
        task.wait(0.35)
    end
end)

return { Run=runTest, State=S, Cleanup=cleanup, Version=CFG.VERSION }
