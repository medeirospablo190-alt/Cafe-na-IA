--==============================================================
-- CAFEINA • CRYSTAL DUP RACE TEST V2
-- Manual legitimate drop -> first-possible pickup timing collector
-- Event-driven • no __namecall hook • no spatial scan • no remote flood
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_CRYSTAL_DUP_RACE_TEST_V2",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    ARM_TIMEOUT = 20,
    PICKUP_SETTLE_TIMEOUT = 4,
    FINAL_SETTLE = 0.30,
    MAX_RECORDS = 180,
    MAX_ERRORS = 12,
    MAX_ANOMALIES = 12,
    RETRIES = 3,
}

local GemSignals = ReplicatedStorage:FindFirstChild("GemSignals")
local GemRemotes = ReplicatedStorage:FindFirstChild("GemRemotes")
local GemCollected = GemSignals and GemSignals:FindFirstChild("GemCollected")
local InventoryChanged = GemRemotes and GemRemotes:FindFirstChild("InventoryChanged")
local DroppedGems = Workspace:FindFirstChild("DroppedGems")

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

local function pathOf(obj)
    if not obj then return "nil" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj)
end

local function safe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" then return v end
    if t == "string" then return #v <= 500 and v or string.sub(v, 1, 500) .. "...[truncated]" end
    if t == "Vector3" or t == "Vector2" or t == "Color3" or t == "EnumItem" then return tostring(v) end
    if t == "CFrame" then return tostring(v.Position) end
    if t == "Instance" then return { type="Instance", class=v.ClassName, name=v.Name, path=pathOf(v) } end
    if t == "table" then
        if depth >= 2 then return "<table>" end
        local out, n = {}, 0
        for k, value in pairs(v) do
            n += 1
            if n > 16 then break end
            out[tostring(k)] = safe(value, depth + 1)
        end
        return out
    end
    return tostring(v)
end

local function attrsOf(obj)
    local out = {}
    if not obj then return out end
    pcall(function()
        for k, v in pairs(obj:GetAttributes()) do out[k] = safe(v) end
    end)
    return out
end

local function toolSnapshot(tool)
    if not tool then return nil end
    return { name=tool.Name, path=pathOf(tool), attributes=attrsOf(tool) }
end

local function crystalSnapshot(crystal)
    if not crystal then return nil end
    local position
    pcall(function()
        if crystal:IsA("Model") then position = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then position = crystal.Position end
    end)
    return {
        name = crystal.Name,
        path = pathOf(crystal),
        class = crystal.ClassName,
        position = position and tostring(position) or nil,
        attributes = attrsOf(crystal),
    }
end

local S = {
    active = false,
    sending = false,
    finalized = false,
    status = "aguardando",
    phase = "idle",
    seq = 0,
    runId = "",
    startedAt = 0,
    finishedAt = 0,
    records = {},
    anomalies = {},
    errors = {},
    connections = {},
    selected = nil,
    selectedTool = nil,
    targetCrystal = nil,
    targetPrompt = nil,
    promptFired = false,
    finalizeScheduled = false,
    marks = {},
    test = {},
    counters = {
        records = 0,
        inventoryChanged = 0,
        gemCollected = 0,
        toolRemoved = 0,
        toolAdded = 0,
        worldAdded = 0,
        worldRemoved = 0,
        promptAttempts = 0,
        uploadAttempts = 0,
        droppedRecords = 0,
    },
}

local function addError(phase, message)
    if #S.errors < CFG.MAX_ERRORS then
        S.errors[#S.errors + 1] = { phase=tostring(phase), error=tostring(message), clock=os.clock(), unix=os.time() }
    end
end

local function record(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.counters.droppedRecords += 1
        return nil
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = data.clock or os.clock()
    data.unix = data.unix or os.time()
    data.phase = data.phase or S.phase
    S.records[#S.records + 1] = data
    S.counters.records += 1
    return data
end

local function flag(code, details)
    if #S.anomalies >= CFG.MAX_ANOMALIES then return end
    local item = {
        code = tostring(code),
        clock = os.clock(),
        unix = os.time(),
        phase = S.phase,
        details = safe(details or {}),
    }
    S.anomalies[#S.anomalies + 1] = item
    record({ kind="consistency_signal", signal=item })
end

local function allContainers()
    return {
        LP:FindFirstChildOfClass("Backpack"),
        LP.Character,
    }
end

local function itemFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local bagId = tool:GetAttribute("BagId")
    local gemName = tool:GetAttribute("GemName")
    if bagId == nil or not gemName then return nil end
    return {
        bagId = bagId,
        gemName = gemName,
        kg = tool:GetAttribute("Kg"),
        value = tool:GetAttribute("Value"),
        rarity = tool:GetAttribute("Rarity"),
        sizeLetter = tool:GetAttribute("SizeLetter"),
        mutations = tool:GetAttribute("Mutations"),
        snapshot = toolSnapshot(tool),
    }
end

local function chooseCandidate()
    -- Prefer the equipped crystal. This lets the user choose the test item by equipping it.
    if LP.Character then
        for _, obj in ipairs(LP.Character:GetChildren()) do
            local item = itemFromTool(obj)
            if item then return item, obj, "Character" end
        end
    end
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            local item = itemFromTool(obj)
            if item then return item, obj, "Backpack" end
        end
    end
    return nil
end

local function findBagId(bagId)
    for _, container in ipairs(allContainers()) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and tostring(obj:GetAttribute("BagId")) == tostring(bagId) then
                    return obj
                end
            end
        end
    end
    return nil
end

local function sameItemInstance(obj, item)
    if not obj or not obj:IsA("Tool") then return false end
    if obj:GetAttribute("GemName") ~= item.gemName then return false end
    local kg = obj:GetAttribute("Kg")
    local value = obj:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(item.kg) ~= tonumber(kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(item.value) ~= tonumber(value) then return false end
    if item.rarity ~= nil and obj:GetAttribute("Rarity") ~= nil and tostring(item.rarity) ~= tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter ~= nil and obj:GetAttribute("SizeLetter") ~= nil and tostring(item.sizeLetter) ~= tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function sameWorldCrystal(obj, item)
    if not obj or not obj.Parent then return false end
    if obj.Name ~= item.gemName then return false end
    local kg = obj:GetAttribute("Kg")
    local value = obj:GetAttribute("Value")
    if item.kg ~= nil and kg ~= nil and tonumber(item.kg) ~= tonumber(kg) then return false end
    if item.value ~= nil and value ~= nil and tonumber(item.value) ~= tonumber(value) then return false end
    if item.rarity ~= nil and obj:GetAttribute("Rarity") ~= nil and tostring(item.rarity) ~= tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter ~= nil and obj:GetAttribute("SizeLetter") ~= nil and tostring(item.sizeLetter) ~= tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function countBagIdsForItem(item)
    local seen, count = {}, 0
    for _, container in ipairs(allContainers()) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if sameItemInstance(obj, item) then
                    local id = obj:GetAttribute("BagId")
                    if id ~= nil and not seen[tostring(id)] then
                        seen[tostring(id)] = true
                        count += 1
                    end
                end
            end
        end
    end
    return count, seen
end

local function uidWorldCount(uid)
    if not DroppedGems or uid == nil then return 0 end
    local count = 0
    for _, obj in ipairs(DroppedGems:GetChildren()) do
        if tostring(obj:GetAttribute("Uid")) == tostring(uid) then count += 1 end
    end
    return count
end

local function disconnectAll()
    for _, conn in ipairs(S.connections) do pcall(function() conn:Disconnect() end) end
    S.connections = {}
end

local function httpRequest(options)
    if not REQUEST then return false, nil, "request/http_request unavailable" end
    local ok, response = pcall(REQUEST, options)
    if not ok or not response then return false, nil, tostring(response) end
    local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body = tostring(response.Body or response.body or "")
    return status >= 200 and status < 300, { status=status, body=body }, nil
end

local function ms(a, b)
    if not a or not b then return nil end
    return (b - a) * 1000
end

local function buildSummary()
    local m = S.marks
    local item = S.selected
    local uid = S.test.uid
    local bagCount, bagSet = item and countBagIdsForItem(item) or 0, {}
    if item then bagCount, bagSet = countBagIdsForItem(item) end

    S.test.timelineMs = {
        toolRemoved_to_worldAdded = ms(m.toolRemoved, m.worldAdded),
        worldAdded_to_promptReady = ms(m.worldAdded, m.promptReady),
        worldAdded_to_promptFire = ms(m.worldAdded, m.promptFire),
        promptFire_to_toolAdded = ms(m.promptFire, m.newToolAdded),
        promptFire_to_inventoryChanged = ms(m.promptFire, m.pickupInventoryChanged),
        promptFire_to_gemCollected = ms(m.promptFire, m.gemCollected),
        promptFire_to_worldRemoved = ms(m.promptFire, m.worldRemoved),
        worldAdded_to_toolAdded = ms(m.worldAdded, m.newToolAdded),
    }

    S.test.finalState = {
        oldBagIdPresent = item and findBagId(item.bagId) ~= nil or false,
        newBagId = S.test.newBagId,
        bagIdChanged = item and S.test.newBagId ~= nil and tostring(S.test.newBagId) ~= tostring(item.bagId) or nil,
        matchingActiveBagIds = bagCount,
        activeBagIds = bagSet,
        uid = uid,
        sameUidWorldCount = uid and uidWorldCount(uid) or nil,
        targetStillInWorld = S.targetCrystal and S.targetCrystal.Parent ~= nil or false,
    }

    if S.test.finalState.oldBagIdPresent and S.test.newBagId and tostring(S.test.newBagId) ~= tostring(item.bagId) then
        flag("OLD_AND_NEW_BAGID_COEXIST", { oldBagId=item.bagId, newBagId=S.test.newBagId })
    end
    if uid and uidWorldCount(uid) > 1 then
        flag("SAME_UID_MULTIPLE_WORLD_OBJECTS", { uid=uid, count=uidWorldCount(uid) })
    end
end

local function buildPayload()
    buildSummary()
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
            purpose = "crystal_drop_immediate_pickup_race_timing",
            runId = S.runId,
            startedAt = S.startedAt,
            finishedAt = S.finishedAt,
            records = S.records,
            remotes = {
                { name="InventoryChanged", path=pathOf(InventoryChanged) },
                { name="GemCollected", path=pathOf(GemCollected) },
            },
            pickupSessions = {},
            bagMap = {},
            dupeRace = S.test,
            anomalies = S.anomalies,
            diagnostics = {
                errors = S.errors,
                counters = S.counters,
                transport = { endpoint=CFG.ENDPOINT, retries=CFG.RETRIES },
                guards = {
                    noHook = true,
                    noSpatialPolling = true,
                    noTouchWatcher = true,
                    noDropRemoteAutomation = true,
                    oneAutomaticPromptAttempt = true,
                    eventDrivenTargeting = true,
                    maxRecords = CFG.MAX_RECORDS,
                },
            },
        },
    }
end

local function upload()
    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, buildPayload())
    if not okEncode then return false, nil, "json_encode_failed" end

    if type(writefile) == "function" then
        pcall(writefile, "Cafeina_DupeRace_" .. tostring(game.PlaceId) .. "_" .. S.runId:gsub("-", "") .. ".json", body)
    end

    for attempt = 1, CFG.RETRIES do
        S.counters.uploadAttempts += 1
        local ok, response, err = httpRequest({
            Url = CFG.ENDPOINT,
            Method = "POST",
            Headers = { ["Content-Type"]="application/json", Accept="application/json" },
            Body = body,
        })
        if ok then
            local receipt
            pcall(function() receipt = HttpService:JSONDecode(response.body) end)
            return true, receipt, nil
        end
        if attempt < CFG.RETRIES then task.wait(attempt * 1.2) end
        if attempt == CFG.RETRIES then return false, nil, err or (response and response.status) or "upload_failed" end
    end
    return false, nil, "upload_failed"
end

local function finish(reason)
    if S.finalized then return end
    S.finalized = true
    S.active = false
    S.finishedAt = os.time()
    S.test.finishReason = reason
    disconnectAll()
    S.sending = true
    S.status = "enviando resultado"
    local ok, receipt, err = upload()
    S.sending = false
    if ok then
        local mirrored = receipt and receipt.github and receipt.github.mirrored
        S.status = "TESTE ENVIADO" .. (mirrored and " • GITHUB ✓" or " • RENDER ✓")
    else
        S.status = "TESTE SALVO • ENVIO FALHOU"
        addError("upload", err)
    end
end

local function scheduleFinish(reason)
    if S.finalizeScheduled or S.finalized then return end
    S.finalizeScheduled = true
    task.delay(CFG.FINAL_SETTLE, function()
        if not S.finalized then finish(reason) end
    end)
end

local function maybeComplete()
    if not S.active or S.finalized then return end
    if S.promptFired and S.marks.newToolAdded and (S.marks.worldRemoved or S.marks.gemCollected) then
        scheduleFinish("pickup_confirmed")
    end
end

local function attemptPrompt(prompt)
    if not S.active or S.promptFired or S.finalized then return end
    if not prompt or not prompt:IsA("ProximityPrompt") then return end

    S.targetPrompt = prompt
    S.marks.promptReady = S.marks.promptReady or os.clock()
    record({
        kind = "pickup_prompt_ready",
        prompt = pathOf(prompt),
        enabled = prompt.Enabled,
        actionText = prompt.ActionText,
        holdDuration = prompt.HoldDuration,
    })

    if not prompt.Enabled then
        local conn
        conn = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not S.active or S.promptFired then
                if conn then conn:Disconnect() end
                return
            end
            if prompt.Enabled then
                if conn then conn:Disconnect() end
                attemptPrompt(prompt)
            end
        end)
        S.connections[#S.connections + 1] = conn
        return
    end

    if type(fireproximityprompt) ~= "function" then
        addError("pickup", "fireproximityprompt unavailable")
        S.status = "executor sem fireproximityprompt"
        scheduleFinish("missing_prompt_api")
        return
    end

    S.promptFired = true
    S.counters.promptAttempts += 1
    S.phase = "pickup_fired"
    S.marks.promptFire = os.clock()
    local ok, err = pcall(fireproximityprompt, prompt)
    local returned = os.clock()
    S.marks.promptReturn = returned
    record({
        kind = "automatic_pickup_attempt",
        prompt = pathOf(prompt),
        success = ok,
        error = ok and nil or tostring(err),
        fireClock = S.marks.promptFire,
        returnClock = returned,
        fireDurationMs = (returned - S.marks.promptFire) * 1000,
    })

    if not ok then
        addError("fireproximityprompt", err)
        scheduleFinish("prompt_call_failed")
        return
    end

    S.status = "pickup disparado • aguardando servidor"
    task.delay(CFG.PICKUP_SETTLE_TIMEOUT, function()
        if S.active and not S.finalized then finish("pickup_settle_timeout") end
    end)
end

local function findExistingPrompt(crystal)
    if not crystal then return nil end
    for _, obj in ipairs(crystal:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then return obj end
    end
    return nil
end

local function acquireWorldCrystal(crystal)
    if not S.active or S.targetCrystal or not sameWorldCrystal(crystal, S.selected) then return end

    -- This must be the selected inventory item actually leaving the player.
    -- A simple Backpack -> Character transfer does not qualify because the BagId is still present.
    if findBagId(S.selected.bagId) then return end

    S.targetCrystal = crystal
    S.phase = "world_seen"
    S.marks.worldAdded = os.clock()
    S.counters.worldAdded += 1
    S.test.uid = crystal:GetAttribute("Uid")
    S.test.world = crystalSnapshot(crystal)
    record({ kind="target_world_added", crystal=S.test.world, oldBagId=S.selected.bagId })

    if S.test.uid and uidWorldCount(S.test.uid) > 1 then
        flag("SAME_UID_MULTIPLE_WORLD_OBJECTS", { uid=S.test.uid, count=uidWorldCount(S.test.uid) })
    end

    local prompt = findExistingPrompt(crystal)
    if prompt then
        attemptPrompt(prompt)
    else
        local conn
        conn = crystal.DescendantAdded:Connect(function(obj)
            if not S.active or S.promptFired then
                if conn then conn:Disconnect() end
                return
            end
            if obj:IsA("ProximityPrompt") then
                if conn then conn:Disconnect() end
                attemptPrompt(obj)
            end
        end)
        S.connections[#S.connections + 1] = conn
    end
end

local function installWatchers()
    local function watchContainer(container, label)
        if not container then return end

        local removed = container.ChildRemoved:Connect(function(obj)
            if not S.active or not obj:IsA("Tool") then return end
            local bagId = obj:GetAttribute("BagId")
            if tostring(bagId) ~= tostring(S.selected.bagId) then return end
            S.counters.toolRemoved += 1
            S.marks.toolRemoved = S.marks.toolRemoved or os.clock()
            record({ kind="selected_tool_removed", container=label, tool=toolSnapshot(obj) })
        end)

        local added = container.ChildAdded:Connect(function(obj)
            if not S.active or not obj:IsA("Tool") then return end
            if not sameItemInstance(obj, S.selected) then return end
            local bagId = obj:GetAttribute("BagId")

            -- Ignore equip/unequip transfers of the original entry before a world crystal exists.
            if not S.targetCrystal and tostring(bagId) == tostring(S.selected.bagId) then return end
            if not S.promptFired then return end

            if not S.marks.newToolAdded then
                S.counters.toolAdded += 1
                S.marks.newToolAdded = os.clock()
                S.test.newBagId = bagId
                S.test.newTool = toolSnapshot(obj)
                record({
                    kind = "pickup_tool_added",
                    container = label,
                    oldBagId = S.selected.bagId,
                    newBagId = bagId,
                    tool = S.test.newTool,
                })

                if findBagId(S.selected.bagId) and tostring(bagId) ~= tostring(S.selected.bagId) then
                    flag("OLD_AND_NEW_BAGID_COEXIST", { oldBagId=S.selected.bagId, newBagId=bagId })
                end
                maybeComplete()
            end
        end)

        S.connections[#S.connections + 1] = removed
        S.connections[#S.connections + 1] = added
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")

    local charConn = LP.CharacterAdded:Connect(function(char)
        if S.active then watchContainer(char, "Character") end
    end)
    S.connections[#S.connections + 1] = charConn

    if DroppedGems then
        local added = DroppedGems.ChildAdded:Connect(function(crystal)
            if S.active then acquireWorldCrystal(crystal) end
        end)
        local removed = DroppedGems.ChildRemoved:Connect(function(crystal)
            if not S.active or crystal ~= S.targetCrystal then return end
            S.counters.worldRemoved += 1
            S.marks.worldRemoved = S.marks.worldRemoved or os.clock()
            record({ kind="target_world_removed", crystal=crystalSnapshot(crystal) })
            maybeComplete()
        end)
        S.connections[#S.connections + 1] = added
        S.connections[#S.connections + 1] = removed
    end

    if InventoryChanged and InventoryChanged:IsA("RemoteEvent") then
        local conn = InventoryChanged.OnClientEvent:Connect(function(...)
            if not S.active then return end
            S.counters.inventoryChanged += 1
            local packed = table.pack(...)
            local args = {}
            for i = 1, math.min(packed.n or #packed, 8) do args[i] = safe(packed[i]) end
            local now = os.clock()
            local stage = S.promptFired and "after_pickup_attempt" or (S.targetCrystal and "after_world_add" or "before_world_add")
            if S.promptFired and not S.marks.pickupInventoryChanged then S.marks.pickupInventoryChanged = now end
            record({ kind="inventory_changed", stage=stage, arguments=args, clock=now })
            maybeComplete()
        end)
        S.connections[#S.connections + 1] = conn
    end

    if GemCollected and GemCollected:IsA("RemoteEvent") then
        local conn = GemCollected.OnClientEvent:Connect(function(crystal, player, ...)
            if not S.active then return end
            if typeof(player) == "Instance" and player:IsA("Player") and player ~= LP then return end
            if S.targetCrystal and crystal ~= S.targetCrystal then return end
            if not S.targetCrystal and typeof(crystal) == "Instance" and not sameWorldCrystal(crystal, S.selected) then return end
            S.counters.gemCollected += 1
            S.marks.gemCollected = S.marks.gemCollected or os.clock()
            record({ kind="gem_collected", crystal=safe(crystal), player=safe(player) })
            maybeComplete()
        end)
        S.connections[#S.connections + 1] = conn
    end
end

local function resetState()
    disconnectAll()
    S.active = false
    S.sending = false
    S.finalized = false
    S.status = "aguardando"
    S.phase = "idle"
    S.seq = 0
    S.runId = ""
    S.startedAt = 0
    S.finishedAt = 0
    S.records = {}
    S.anomalies = {}
    S.errors = {}
    S.connections = {}
    S.selected = nil
    S.selectedTool = nil
    S.targetCrystal = nil
    S.targetPrompt = nil
    S.promptFired = false
    S.finalizeScheduled = false
    S.marks = {}
    S.test = {}
    S.counters = {
        records=0, inventoryChanged=0, gemCollected=0, toolRemoved=0, toolAdded=0,
        worldAdded=0, worldRemoved=0, promptAttempts=0, uploadAttempts=0, droppedRecords=0,
    }
end

local function arm()
    if S.active or S.sending then return false end
    resetState()

    if not DroppedGems then
        S.status = "DroppedGems não encontrado"
        addError("prepare", "Workspace.DroppedGems missing")
        return false
    end
    if type(fireproximityprompt) ~= "function" then
        S.status = "executor sem fireproximityprompt"
        addError("prepare", "fireproximityprompt unavailable")
        return false
    end

    local item, tool, container = chooseCandidate()
    if not item then
        S.status = "nenhum cristal com BagId"
        return false
    end

    S.selected = item
    S.selectedTool = tool
    S.runId = HttpService:GenerateGUID(false)
    S.startedAt = os.time()
    S.active = true
    S.phase = "armed"
    S.status = "ARMADO • solte esse cristal normalmente"
    S.test.selected = {
        oldBagId = item.bagId,
        gemName = item.gemName,
        kg = item.kg,
        value = item.value,
        rarity = item.rarity,
        sizeLetter = item.sizeLetter,
        container = container,
        tool = item.snapshot,
    }
    S.marks.armed = os.clock()
    record({ kind="race_test_armed", selected=S.test.selected })
    installWatchers()

    task.delay(CFG.ARM_TIMEOUT, function()
        if S.active and not S.targetCrystal and not S.finalized then
            finish("arm_timeout_no_drop")
        end
    end)
    return true
end

-- Stop older CAFEINA collectors/tests so only this lightweight test is observing the run.
for _, key in ipairs({
    "__CAFEINA_INVTRACE_RUNTIME_V64",
    "__CAFEINA_INVTRACE_RUNTIME_NOHOOK",
    "__CAFEINA_DUP_TEST_RUNTIME_V11",
    "__CAFEINA_DUP_RACE_RUNTIME_V2",
}) do
    local rt = rawget(ENV, key)
    if type(rt) == "table" then
        local fn = rt.cleanup or rt.stop
        if type(fn) == "function" then pcall(fn) end
    end
end

local RUNTIME_KEY = "__CAFEINA_DUP_RACE_RUNTIME_V2"

for _, parent in ipairs({ CoreGui, LP:FindFirstChildOfClass("PlayerGui") }) do
    if parent then
        local old = parent:FindFirstChild("CafeinaDupeRaceV2")
        if old then pcall(function() old:Destroy() end) end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaDupeRaceV2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(306, 210)
frame.Position = UDim2.new(0.5, -153, 0.16, 0)
frame.BackgroundColor3 = Color3.fromRGB(12,12,14)
frame.BackgroundTransparency = 0.04
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-18,0,28)
title.Position = UDim2.fromOffset(9,7)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • RACE PICKUP V2"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1,-18,0,42)
selectedLabel.Position = UDim2.fromOffset(9,38)
selectedLabel.BackgroundColor3 = Color3.fromRGB(21,21,24)
selectedLabel.TextColor3 = Color3.fromRGB(225,225,230)
selectedLabel.TextSize = 11
selectedLabel.Font = Enum.Font.Code
selectedLabel.TextWrapped = true
selectedLabel.Parent = frame
Instance.new("UICorner", selectedLabel).CornerRadius = UDim.new(0,8)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1,-18,0,52)
statusLabel.Position = UDim2.fromOffset(9,86)
statusLabel.BackgroundColor3 = Color3.fromRGB(21,21,24)
statusLabel.TextColor3 = Color3.fromRGB(225,225,230)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Code
statusLabel.TextWrapped = true
statusLabel.Parent = frame
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0,8)

local armBtn = Instance.new("TextButton")
armBtn.Size = UDim2.new(1,-18,0,38)
armBtn.Position = UDim2.fromOffset(9,145)
armBtn.BackgroundColor3 = Color3.fromRGB(42,42,47)
armBtn.TextColor3 = Color3.new(1,1,1)
armBtn.TextSize = 12
armBtn.Font = Enum.Font.GothamBold
armBtn.Text = "ARMAR PICKUP RÁPIDO"
armBtn.Parent = frame
Instance.new("UICorner", armBtn).CornerRadius = UDim.new(0,8)

local function cleanup()
    disconnectAll()
    S.active = false
    pcall(function() gui:Destroy() end)
end
ENV[RUNTIME_KEY] = { cleanup=cleanup, state=S }

armBtn.MouseButton1Click:Connect(function()
    if not S.active and not S.sending then arm() end
end)

task.spawn(function()
    while gui.Parent do
        if S.selected then
            selectedLabel.Text = string.format(
                "%s • BagId %s\n%s kg • $%s",
                tostring(S.selected.gemName), tostring(S.selected.bagId),
                tostring(S.selected.kg or "?"), tostring(S.selected.value or "?")
            )
        else
            local candidate = chooseCandidate()
            if candidate then
                selectedLabel.Text = string.format(
                    "Próximo: %s • BagId %s\nEquipe outro cristal para escolher",
                    tostring(candidate.gemName), tostring(candidate.bagId)
                )
            else
                selectedLabel.Text = "Nenhum cristal com BagId no inventário"
            end
        end

        local promptMs = ms(S.marks.worldAdded, S.marks.promptFire)
        statusLabel.Text = string.format(
            "Status: %s\nFase: %s • World→Pickup: %s ms",
            tostring(S.status), tostring(S.phase), promptMs and string.format("%.3f", promptMs) or "..."
        )

        local busy = S.active or S.sending
        armBtn.Active = not busy
        armBtn.AutoButtonColor = not busy
        armBtn.Text = S.sending and "ENVIANDO..." or (S.active and "ARMADO • SOLTE O CRISTAL" or "ARMAR PICKUP RÁPIDO")
        task.wait(0.35)
    end
end)

return {
    Arm = arm,
    State = S,
    Cleanup = cleanup,
    Version = CFG.VERSION,
}
