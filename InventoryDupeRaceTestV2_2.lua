--==============================================================
-- CAFEINA • CRYSTAL DUP RACE TEST V2.2
-- Legitimate manual drop -> immediate pickup -> one same-instance retry
-- Focused timing only • event-driven • no hook • no spatial scan
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_CRYSTAL_DUP_RACE_TEST_V2_2",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    ARM_TIMEOUT = 20,
    FIRST_PICKUP_TIMEOUT = 4,
    SECOND_OBSERVE = 1.0,
    REPLICATION_REORDER_GRACE = 0.18,
    MAX_RECORDS = 220,
    MAX_ERRORS = 12,
    MAX_SIGNALS = 16,
    RETRIES = 3,
}

local GemSignals = ReplicatedStorage:FindFirstChild("GemSignals")
local GemRemotes = ReplicatedStorage:FindFirstChild("GemRemotes")
local GemCollected = GemSignals and GemSignals:FindFirstChild("GemCollected")
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

local function safe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" then return v end
    if t == "string" then return #v <= 500 and v or string.sub(v,1,500).."...[truncated]" end
    if t == "Vector3" or t == "Vector2" or t == "Color3" or t == "EnumItem" then return tostring(v) end
    if t == "CFrame" then return tostring(v.Position) end
    if t == "Instance" then return {type="Instance",class=v.ClassName,name=v.Name,path=pathOf(v)} end
    if t == "table" then
        if depth >= 2 then return "<table>" end
        local out,n = {},0
        for k,value in pairs(v) do
            n += 1
            if n > 16 then break end
            out[tostring(k)] = safe(value, depth+1)
        end
        return out
    end
    return tostring(v)
end

local function attrsOf(obj)
    local out = {}
    if not obj then return out end
    pcall(function()
        for k,v in pairs(obj:GetAttributes()) do out[k]=safe(v) end
    end)
    return out
end

local function toolSnap(tool)
    return tool and {name=tool.Name,path=pathOf(tool),attributes=attrsOf(tool)} or nil
end

local function crystalSnap(crystal)
    if not crystal then return nil end
    local pos
    pcall(function()
        if crystal:IsA("Model") then pos=crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos=crystal.Position end
    end)
    return {
        name=crystal.Name,
        path=pathOf(crystal),
        class=crystal.ClassName,
        position=pos and tostring(pos) or nil,
        attributes=attrsOf(crystal),
    }
end

local S = {
    active=false,
    sending=false,
    finalized=false,
    status="aguardando",
    phase="idle",
    seq=0,
    runId="",
    startedAt=0,
    finishedAt=0,
    records={},
    signals={},
    errors={},
    connections={},
    selected=nil,
    targetCrystal=nil,
    targetPrompt=nil,
    pendingWorld=nil,
    firstPromptFired=false,
    firstPickupConfirmed=false,
    secondAttempted=false,
    secondObserveScheduled=false,
    marks={},
    test={},
    counters={
        records=0,
        inventoryChanged=0,
        gemCollected=0,
        toolRemoved=0,
        firstToolAdded=0,
        secondToolAdded=0,
        worldAdded=0,
        worldRemoved=0,
        firstPromptAttempts=0,
        secondPromptAttempts=0,
        uploadAttempts=0,
        droppedRecords=0,
    },
}

local function addError(phase,msg)
    if #S.errors < CFG.MAX_ERRORS then
        S.errors[#S.errors+1]={phase=tostring(phase),error=tostring(msg),clock=os.clock(),unix=os.time()}
    end
end

local function rec(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.counters.droppedRecords += 1
        return nil
    end
    S.seq += 1
    data.seq=S.seq
    data.clock=data.clock or os.clock()
    data.unix=data.unix or os.time()
    data.phase=data.phase or S.phase
    S.records[#S.records+1]=data
    S.counters.records += 1
    return data
end

local function signal(code,details,severity)
    if #S.signals >= CFG.MAX_SIGNALS then return end
    local item={
        code=tostring(code),
        severity=tostring(severity or "info"),
        phase=S.phase,
        clock=os.clock(),
        unix=os.time(),
        details=safe(details or {}),
    }
    S.signals[#S.signals+1]=item
    rec({kind="consistency_signal",signal=item})
end

local function containers()
    return {LP:FindFirstChildOfClass("Backpack"), LP.Character}
end

local function itemFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local bagId,gemName=tool:GetAttribute("BagId"),tool:GetAttribute("GemName")
    if bagId==nil or not gemName then return nil end
    return {
        bagId=bagId,
        gemName=gemName,
        kg=tool:GetAttribute("Kg"),
        value=tool:GetAttribute("Value"),
        rarity=tool:GetAttribute("Rarity"),
        sizeLetter=tool:GetAttribute("SizeLetter"),
        mutations=tool:GetAttribute("Mutations"),
        snapshot=toolSnap(tool),
    }
end

local function chooseItem()
    if LP.Character then
        for _,obj in ipairs(LP.Character:GetChildren()) do
            local item=itemFromTool(obj)
            if item then return item,"Character" end
        end
    end
    local backpack=LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _,obj in ipairs(backpack:GetChildren()) do
            local item=itemFromTool(obj)
            if item then return item,"Backpack" end
        end
    end
end

local function findBagId(id)
    for _,container in ipairs(containers()) do
        if container then
            for _,obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and tostring(obj:GetAttribute("BagId"))==tostring(id) then return obj end
            end
        end
    end
end

local function sameTool(obj,item)
    if not obj or not obj:IsA("Tool") or obj:GetAttribute("GemName")~=item.gemName then return false end
    local kg,value=obj:GetAttribute("Kg"),obj:GetAttribute("Value")
    if item.kg~=nil and kg~=nil and tonumber(item.kg)~=tonumber(kg) then return false end
    if item.value~=nil and value~=nil and tonumber(item.value)~=tonumber(value) then return false end
    if item.rarity~=nil and obj:GetAttribute("Rarity")~=nil and tostring(item.rarity)~=tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter~=nil and obj:GetAttribute("SizeLetter")~=nil and tostring(item.sizeLetter)~=tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function sameWorld(obj,item)
    if not obj or not obj.Parent or obj.Name~=item.gemName then return false end
    local kg,value=obj:GetAttribute("Kg"),obj:GetAttribute("Value")
    if item.kg~=nil and kg~=nil and tonumber(item.kg)~=tonumber(kg) then return false end
    if item.value~=nil and value~=nil and tonumber(item.value)~=tonumber(value) then return false end
    if item.rarity~=nil and obj:GetAttribute("Rarity")~=nil and tostring(item.rarity)~=tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter~=nil and obj:GetAttribute("SizeLetter")~=nil and tostring(item.sizeLetter)~=tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function uidWorldCount(uid)
    if not DroppedGems or uid==nil then return 0 end
    local n=0
    for _,obj in ipairs(DroppedGems:GetChildren()) do
        if tostring(obj:GetAttribute("Uid"))==tostring(uid) then n+=1 end
    end
    return n
end

local function activeBagIds(item)
    local set,count={},0
    for _,container in ipairs(containers()) do
        if container then
            for _,obj in ipairs(container:GetChildren()) do
                if sameTool(obj,item) then
                    local id=obj:GetAttribute("BagId")
                    if id~=nil and not set[tostring(id)] then
                        set[tostring(id)]=true
                        count+=1
                    end
                end
            end
        end
    end
    return count,set
end

local function disconnectAll()
    for _,c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    S.connections={}
end

local function request(options)
    if not REQUEST then return false,nil,"request unavailable" end
    local ok,response=pcall(REQUEST,options)
    if not ok or not response then return false,nil,tostring(response) end
    local status=tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body=tostring(response.Body or response.body or "")
    return status>=200 and status<300,{status=status,body=body},nil
end

local function ms(a,b)
    if not a or not b then return nil end
    return (b-a)*1000
end

local function findPrompt(crystal)
    if not crystal then return nil end
    for _,obj in ipairs(crystal:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then return obj end
    end
end

local function buildSummary()
    local m,item=S.marks,S.selected
    local count,set=item and activeBagIds(item) or 0,{}
    if item then count,set=activeBagIds(item) end

    S.test.timelineMs={
        toolRemoved_to_dropInventoryChanged=ms(m.toolRemoved,m.dropInventoryChanged),
        toolRemoved_to_worldAdded=ms(m.toolRemoved,m.worldAdded),
        dropInventoryChanged_to_worldAdded=ms(m.dropInventoryChanged,m.worldAdded),
        worldAdded_to_firstPromptReady=ms(m.worldAdded,m.firstPromptReady),
        worldAdded_to_firstPromptFire=ms(m.worldAdded,m.firstPromptFire),
        firstPromptFire_to_firstToolAdded=ms(m.firstPromptFire,m.firstToolAdded),
        firstPromptFire_to_firstInventoryChanged=ms(m.firstPromptFire,m.firstPickupInventoryChanged),
        firstPromptFire_to_firstGemCollected=ms(m.firstPromptFire,m.firstGemCollected),
        firstConfirmed_to_secondPromptFire=ms(m.firstPickupConfirmed,m.secondPromptFire),
        secondPromptFire_to_secondToolAdded=ms(m.secondPromptFire,m.secondToolAdded),
        secondPromptFire_to_secondInventoryChanged=ms(m.secondPromptFire,m.secondInventoryChanged),
        secondPromptFire_to_secondGemCollected=ms(m.secondPromptFire,m.secondGemCollected),
        secondPromptFire_to_worldRemoved=ms(m.secondPromptFire,m.worldRemoved),
    }

    S.test.finalState={
        oldBagIdPresent=item and findBagId(item.bagId)~=nil or false,
        firstNewBagId=S.test.firstNewBagId,
        secondNewBagId=S.test.secondNewBagId,
        activeMatchingBagIds=count,
        activeBagIds=set,
        uid=S.test.uid,
        sameUidWorldCount=S.test.uid and uidWorldCount(S.test.uid) or nil,
        targetStillInWorld=S.targetCrystal and S.targetCrystal.Parent~=nil or false,
        firstPickupConfirmed=S.firstPickupConfirmed,
        secondAttempted=S.secondAttempted,
        secondInventoryChangedObserved=m.secondInventoryChanged~=nil,
        secondGemCollectedObserved=m.secondGemCollected~=nil,
        secondToolAddedObserved=m.secondToolAdded~=nil,
    }

    if item and S.test.firstNewBagId and tostring(S.test.firstNewBagId)~=tostring(item.bagId) and findBagId(item.bagId) then
        signal("OLD_AND_FIRST_NEW_BAGID_COEXIST",{oldBagId=item.bagId,newBagId=S.test.firstNewBagId},"warning")
    end
    if S.test.uid and uidWorldCount(S.test.uid)>1 then
        signal("SAME_UID_MULTIPLE_WORLD_OBJECTS",{uid=S.test.uid,count=uidWorldCount(S.test.uid)},"critical")
    end
end

local function payload()
    buildSummary()
    return {
        schemaVersion=1,
        userId=tostring(LP.UserId),
        username=LP.Name,
        capturedAt=DateTime.now():ToIsoDate(),
        placeId=game.PlaceId,
        gameId=game.GameId,
        runId=S.runId,
        trace={
            version=CFG.VERSION,
            purpose="crystal_drop_immediate_pickup_then_same_instance_retry",
            runId=S.runId,
            startedAt=S.startedAt,
            finishedAt=S.finishedAt,
            records=S.records,
            remotes={
                {name="InventoryChanged",path=pathOf(InventoryChanged)},
                {name="GemCollected",path=pathOf(GemCollected)},
            },
            pickupSessions={},
            bagMap={},
            dupeRace=S.test,
            anomalies=S.signals,
            diagnostics={
                errors=S.errors,
                counters=S.counters,
                transport={endpoint=CFG.ENDPOINT,retries=CFG.RETRIES},
                guards={
                    noHook=true,
                    noSpatialPolling=true,
                    noTouchWatcher=true,
                    noDropRemoteAutomation=true,
                    firstAutomaticPromptAttempts=1,
                    secondAutomaticPromptAttempts=1,
                    maxAutomaticPromptAttempts=2,
                    eventDrivenTargeting=true,
                    maxRecords=CFG.MAX_RECORDS,
                },
            },
        },
    }
end

local function upload()
    local okEncode,body=pcall(HttpService.JSONEncode,HttpService,payload())
    if not okEncode then return false,nil,"json_encode_failed" end

    if type(writefile)=="function" then
        pcall(writefile,"Cafeina_DupeRace_"..tostring(game.PlaceId).."_"..S.runId:gsub("-","")..".json",body)
    end

    for attempt=1,CFG.RETRIES do
        S.counters.uploadAttempts+=1
        local ok,response,err=request({
            Url=CFG.ENDPOINT,
            Method="POST",
            Headers={["Content-Type"]="application/json",Accept="application/json"},
            Body=body,
        })
        if ok then
            local receipt
            pcall(function() receipt=HttpService:JSONDecode(response.body) end)
            return true,receipt,nil
        end
        if attempt<CFG.RETRIES then
            task.wait(attempt*1.2)
        else
            return false,nil,err or "upload_failed"
        end
    end
end

local function finish(reason)
    if S.finalized then return end
    S.finalized=true
    S.active=false
    S.finishedAt=os.time()
    S.test.finishReason=reason
    disconnectAll()
    S.sending=true
    S.status="enviando resultado"
    local ok,receipt,err=upload()
    S.sending=false
    if ok then
        local mirrored=receipt and receipt.github and receipt.github.mirrored
        S.status="TESTE ENVIADO"..(mirrored and " • GITHUB ✓" or " • RENDER ✓")
    else
        S.status="TESTE SALVO • ENVIO FALHOU"
        addError("upload",err)
    end
end

local function scheduleSecondObserveFinish()
    if S.secondObserveScheduled or S.finalized then return end
    S.secondObserveScheduled=true
    task.delay(CFG.SECOND_OBSERVE,function()
        if S.active and not S.finalized then finish("second_attempt_observed") end
    end)
end

local function doSecondAttempt()
    if not S.active or S.finalized or S.secondAttempted or not S.firstPickupConfirmed then return end
    S.secondAttempted=true
    S.phase="second_pickup_attempt"
    S.marks.secondPromptFire=os.clock()

    local crystal=S.targetCrystal
    local prompt=S.targetPrompt
    if not prompt or not prompt.Parent then prompt=findPrompt(crystal) end

    S.test.secondAttempt={
        crystalStillPresent=crystal and crystal.Parent~=nil or false,
        promptStillPresent=prompt and prompt.Parent~=nil or false,
        promptEnabled=prompt and prompt.Enabled or nil,
        uid=S.test.uid,
        activeFirstBagId=S.test.firstNewBagId and findBagId(S.test.firstNewBagId)~=nil or false,
    }

    if not crystal or not crystal.Parent then
        rec({kind="second_pickup_skipped",reason="world_instance_removed",state=S.test.secondAttempt})
        finish("world_removed_before_second_attempt")
        return
    end
    if not prompt or not prompt.Parent then
        rec({kind="second_pickup_skipped",reason="prompt_removed",state=S.test.secondAttempt})
        finish("prompt_removed_before_second_attempt")
        return
    end
    if type(fireproximityprompt)~="function" then
        addError("second_pickup","fireproximityprompt unavailable")
        finish("missing_prompt_api")
        return
    end

    S.counters.secondPromptAttempts+=1
    local t0=os.clock()
    S.marks.secondPromptFire=t0
    local ok,err=pcall(fireproximityprompt,prompt)
    local t1=os.clock()
    rec({
        kind="second_same_instance_pickup_attempt",
        uid=S.test.uid,
        prompt=pathOf(prompt),
        promptEnabled=prompt.Enabled,
        success=ok,
        error=ok and nil or tostring(err),
        fireClock=t0,
        returnClock=t1,
        fireDurationMs=(t1-t0)*1000,
        firstNewBagId=S.test.firstNewBagId,
    })
    if not ok then addError("second_fireproximityprompt",err) end
    S.status="2º pickup disparado • observando"
    scheduleSecondObserveFinish()
end

local function maybeConfirmFirstPickup()
    if not S.active or S.finalized or S.firstPickupConfirmed then return end
    if S.marks.firstToolAdded and (S.marks.firstPickupInventoryChanged or S.marks.firstGemCollected) then
        S.firstPickupConfirmed=true
        S.marks.firstPickupConfirmed=os.clock()
        S.test.firstPickupConfirmed={
            clock=S.marks.firstPickupConfirmed,
            newBagId=S.test.firstNewBagId,
            inventoryChanged=S.marks.firstPickupInventoryChanged~=nil,
            gemCollected=S.marks.firstGemCollected~=nil,
            targetStillInWorld=S.targetCrystal and S.targetCrystal.Parent~=nil or false,
            uid=S.test.uid,
        }
        rec({kind="first_pickup_confirmed",confirmation=S.test.firstPickupConfirmed})
        task.spawn(doSecondAttempt)
    end
end

local function attemptFirstPrompt(prompt)
    if not S.active or S.finalized or S.firstPromptFired or not prompt or not prompt:IsA("ProximityPrompt") then return end
    S.targetPrompt=prompt
    S.marks.firstPromptReady=S.marks.firstPromptReady or os.clock()
    rec({kind="first_pickup_prompt_ready",prompt=pathOf(prompt),enabled=prompt.Enabled,actionText=prompt.ActionText,holdDuration=prompt.HoldDuration})

    if not prompt.Enabled then
        local conn
        conn=prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not S.active or S.firstPromptFired then
                if conn then conn:Disconnect() end
                return
            end
            if prompt.Enabled then
                if conn then conn:Disconnect() end
                attemptFirstPrompt(prompt)
            end
        end)
        S.connections[#S.connections+1]=conn
        return
    end

    if type(fireproximityprompt)~="function" then
        addError("first_pickup","fireproximityprompt unavailable")
        finish("missing_prompt_api")
        return
    end

    S.firstPromptFired=true
    S.counters.firstPromptAttempts+=1
    S.phase="first_pickup_attempt"
    local t0=os.clock()
    S.marks.firstPromptFire=t0
    local ok,err=pcall(fireproximityprompt,prompt)
    local t1=os.clock()
    rec({
        kind="first_automatic_pickup_attempt",
        prompt=pathOf(prompt),
        success=ok,
        error=ok and nil or tostring(err),
        fireClock=t0,
        returnClock=t1,
        fireDurationMs=(t1-t0)*1000,
    })
    if not ok then
        addError("first_fireproximityprompt",err)
        finish("first_prompt_call_failed")
        return
    end

    S.status="1º pickup disparado • aguardando servidor"
    task.delay(CFG.FIRST_PICKUP_TIMEOUT,function()
        if S.active and not S.finalized and not S.firstPickupConfirmed then
            finish("first_pickup_timeout")
        end
    end)
end

local function confirmWorldCrystal(crystal)
    if not S.active or S.targetCrystal or not crystal or not sameWorld(crystal,S.selected) then return end

    if findBagId(S.selected.bagId) then
        S.pendingWorld=crystal
        local candidate=crystal
        task.delay(CFG.REPLICATION_REORDER_GRACE,function()
            if not S.active or S.targetCrystal or S.pendingWorld~=candidate then return end
            if candidate.Parent and not findBagId(S.selected.bagId) then
                confirmWorldCrystal(candidate)
            end
        end)
        return
    end

    S.pendingWorld=nil
    S.targetCrystal=crystal
    S.phase="world_seen"
    S.marks.worldAdded=os.clock()
    S.counters.worldAdded+=1
    S.test.uid=crystal:GetAttribute("Uid")
    S.test.world=crystalSnap(crystal)
    rec({kind="target_world_added",crystal=S.test.world,oldBagId=S.selected.bagId})

    if S.test.uid and uidWorldCount(S.test.uid)>1 then
        signal("SAME_UID_MULTIPLE_WORLD_OBJECTS",{uid=S.test.uid,count=uidWorldCount(S.test.uid)},"critical")
    end

    local prompt=findPrompt(crystal)
    if prompt then
        attemptFirstPrompt(prompt)
    else
        local conn
        conn=crystal.DescendantAdded:Connect(function(obj)
            if not S.active or S.firstPromptFired then
                if conn then conn:Disconnect() end
                return
            end
            if obj:IsA("ProximityPrompt") then
                if conn then conn:Disconnect() end
                attemptFirstPrompt(obj)
            end
        end)
        S.connections[#S.connections+1]=conn
    end
end

local function installWatchers()
    local function watchContainer(container,label)
        if not container then return end

        local removed=container.ChildRemoved:Connect(function(obj)
            if not S.active or not obj:IsA("Tool") then return end
            local bagId=obj:GetAttribute("BagId")
            if tostring(bagId)~=tostring(S.selected.bagId) then return end
            S.marks.toolRemovedCandidate=os.clock()
            S.test.departedContainer=label
            task.delay(CFG.REPLICATION_REORDER_GRACE,function()
                if not S.active or S.marks.toolRemoved or not S.marks.toolRemovedCandidate then return end
                if not findBagId(S.selected.bagId) then
                    S.marks.toolRemoved=S.marks.toolRemovedCandidate
                    S.counters.toolRemoved+=1
                    rec({kind="selected_tool_removed_confirmed",container=label,oldBagId=S.selected.bagId,clock=S.marks.toolRemoved})
                    if S.pendingWorld and S.pendingWorld.Parent then confirmWorldCrystal(S.pendingWorld) end
                end
            end)
        end)

        local added=container.ChildAdded:Connect(function(obj)
            if not S.active or not obj:IsA("Tool") or not sameTool(obj,S.selected) then return end
            local bagId=obj:GetAttribute("BagId")

            -- Equip/unequip transfer of the original Tool is not a drop.
            if not S.targetCrystal and tostring(bagId)==tostring(S.selected.bagId) then
                S.marks.toolRemovedCandidate=nil
                S.test.departedContainer=nil
                return
            end

            if S.secondAttempted then
                if not S.marks.secondToolAdded then
                    S.marks.secondToolAdded=os.clock()
                    S.counters.secondToolAdded+=1
                    S.test.secondNewBagId=bagId
                    S.test.secondNewTool=toolSnap(obj)
                    rec({kind="second_pickup_tool_added",container=label,bagId=bagId,tool=S.test.secondNewTool})
                    signal("SECOND_ATTEMPT_CREATED_TOOL",{firstBagId=S.test.firstNewBagId,secondBagId=bagId},"critical")
                end
                return
            end

            if S.firstPromptFired and not S.marks.firstToolAdded then
                S.marks.firstToolAdded=os.clock()
                S.counters.firstToolAdded+=1
                S.test.firstNewBagId=bagId
                S.test.firstNewTool=toolSnap(obj)
                rec({kind="first_pickup_tool_added",container=label,oldBagId=S.selected.bagId,newBagId=bagId,tool=S.test.firstNewTool})
                maybeConfirmFirstPickup()
            end
        end)

        S.connections[#S.connections+1]=removed
        S.connections[#S.connections+1]=added
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"),"Backpack")
    watchContainer(LP.Character,"Character")

    local charConn=LP.CharacterAdded:Connect(function(char)
        if S.active then watchContainer(char,"Character") end
    end)
    S.connections[#S.connections+1]=charConn

    if DroppedGems then
        local added=DroppedGems.ChildAdded:Connect(function(crystal)
            if S.active then confirmWorldCrystal(crystal) end
        end)
        local removed=DroppedGems.ChildRemoved:Connect(function(crystal)
            if not S.active or crystal~=S.targetCrystal then return end
            S.counters.worldRemoved+=1
            S.marks.worldRemoved=S.marks.worldRemoved or os.clock()
            rec({kind="target_world_removed",crystal=crystalSnap(crystal)})
            if S.firstPickupConfirmed and not S.secondAttempted then
                -- If removal beats the retry, that itself is the result.
                doSecondAttempt()
            end
        end)
        S.connections[#S.connections+1]=added
        S.connections[#S.connections+1]=removed
    end

    if InventoryChanged and InventoryChanged:IsA("RemoteEvent") then
        local conn=InventoryChanged.OnClientEvent:Connect(function(...)
            if not S.active then return end
            S.counters.inventoryChanged+=1
            local packed=table.pack(...)
            local args={}
            for i=1,math.min(packed.n or #packed,8) do args[i]=safe(packed[i]) end
            local now=os.clock()
            local stage
            if S.secondAttempted then
                stage="after_second_attempt"
                if not S.marks.secondInventoryChanged then
                    S.marks.secondInventoryChanged=now
                    signal("SECOND_ATTEMPT_TRIGGERED_INVENTORY_CHANGED",{arguments=args},"warning")
                end
            elseif S.firstPromptFired then
                stage="after_first_attempt"
                S.marks.firstPickupInventoryChanged=S.marks.firstPickupInventoryChanged or now
            else
                stage="drop_transition"
                S.marks.dropInventoryChanged=S.marks.dropInventoryChanged or now
            end
            rec({kind="inventory_changed",stage=stage,arguments=args,clock=now})
            maybeConfirmFirstPickup()
        end)
        S.connections[#S.connections+1]=conn
    end

    if GemCollected and GemCollected:IsA("RemoteEvent") then
        local conn=GemCollected.OnClientEvent:Connect(function(crystal,player,...)
            if not S.active then return end
            if typeof(player)=="Instance" and player:IsA("Player") and player~=LP then return end
            if S.targetCrystal and crystal~=S.targetCrystal then return end
            if not S.targetCrystal and typeof(crystal)=="Instance" and not sameWorld(crystal,S.selected) then return end

            S.counters.gemCollected+=1
            local now=os.clock()
            local stage
            if S.secondAttempted then
                stage="after_second_attempt"
                if not S.marks.secondGemCollected then
                    S.marks.secondGemCollected=now
                    signal("SECOND_ATTEMPT_TRIGGERED_GEM_COLLECTED",{uid=S.test.uid},"warning")
                end
            else
                stage="after_first_attempt"
                S.marks.firstGemCollected=S.marks.firstGemCollected or now
            end
            rec({kind="gem_collected",stage=stage,crystal=safe(crystal),player=safe(player),clock=now})
            maybeConfirmFirstPickup()
        end)
        S.connections[#S.connections+1]=conn
    end
end

local function resetState()
    disconnectAll()
    S.active=false
    S.sending=false
    S.finalized=false
    S.status="aguardando"
    S.phase="idle"
    S.seq=0
    S.runId=""
    S.startedAt=0
    S.finishedAt=0
    S.records={}
    S.signals={}
    S.errors={}
    S.connections={}
    S.selected=nil
    S.targetCrystal=nil
    S.targetPrompt=nil
    S.pendingWorld=nil
    S.firstPromptFired=false
    S.firstPickupConfirmed=false
    S.secondAttempted=false
    S.secondObserveScheduled=false
    S.marks={}
    S.test={}
    S.counters={records=0,inventoryChanged=0,gemCollected=0,toolRemoved=0,firstToolAdded=0,secondToolAdded=0,worldAdded=0,worldRemoved=0,firstPromptAttempts=0,secondPromptAttempts=0,uploadAttempts=0,droppedRecords=0}
end

local function arm()
    if S.active or S.sending then return false end
    resetState()

    if not DroppedGems then
        S.status="DroppedGems não encontrado"
        addError("prepare","Workspace.DroppedGems missing")
        return false
    end
    if type(fireproximityprompt)~="function" then
        S.status="executor sem fireproximityprompt"
        addError("prepare","fireproximityprompt unavailable")
        return false
    end

    local item,container=chooseItem()
    if not item then
        S.status="nenhum cristal com BagId"
        return false
    end

    S.selected=item
    S.runId=HttpService:GenerateGUID(false)
    S.startedAt=os.time()
    S.active=true
    S.phase="armed"
    S.status="ARMADO • solte esse cristal normalmente"
    S.test.selected={
        oldBagId=item.bagId,
        gemName=item.gemName,
        kg=item.kg,
        value=item.value,
        rarity=item.rarity,
        sizeLetter=item.sizeLetter,
        container=container,
        tool=item.snapshot,
    }
    S.marks.armed=os.clock()
    rec({kind="race_test_armed",selected=S.test.selected})
    installWatchers()

    task.delay(CFG.ARM_TIMEOUT,function()
        if S.active and not S.targetCrystal and not S.finalized then
            finish("arm_timeout_no_drop")
        end
    end)
    return true
end

-- Stop older CAFEINA collectors/tests so this lightweight run is isolated.
for _,key in ipairs({
    "__CAFEINA_INVTRACE_RUNTIME_V64",
    "__CAFEINA_INVTRACE_RUNTIME_NOHOOK",
    "__CAFEINA_DUP_TEST_RUNTIME_V11",
    "__CAFEINA_DUP_RACE_RUNTIME_V2",
    "__CAFEINA_DUP_RACE_RUNTIME_V21",
    "__CAFEINA_DUP_RACE_RUNTIME_V22",
}) do
    local rt=rawget(ENV,key)
    if type(rt)=="table" then
        local fn=rt.cleanup or rt.stop
        if type(fn)=="function" then pcall(fn) end
    end
end

local RUNTIME_KEY="__CAFEINA_DUP_RACE_RUNTIME_V22"

for _,parent in ipairs({CoreGui,LP:FindFirstChildOfClass("PlayerGui")}) do
    if parent then
        for _,name in ipairs({"CafeinaDupeRaceV2","CafeinaDupeRaceV21","CafeinaDupeRaceV22"}) do
            local old=parent:FindFirstChild(name)
            if old then pcall(function() old:Destroy() end) end
        end
    end
end

local gui=Instance.new("ScreenGui")
gui.Name="CafeinaDupeRaceV22"
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent=CoreGui end)
if not gui.Parent then gui.Parent=LP:WaitForChild("PlayerGui") end

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(306,220)
frame.Position=UDim2.new(0.5,-153,0.16,0)
frame.BackgroundColor3=Color3.fromRGB(12,12,14)
frame.BackgroundTransparency=0.04
frame.BorderSizePixel=0
frame.Active=true
frame.Draggable=true
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-18,0,28)
title.Position=UDim2.fromOffset(9,7)
title.BackgroundTransparency=1
title.Text="CAFEINA • RACE PICKUP V2.2"
title.TextColor3=Color3.new(1,1,1)
title.TextSize=14
title.Font=Enum.Font.GothamBold
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local selectedLabel=Instance.new("TextLabel")
selectedLabel.Size=UDim2.new(1,-18,0,42)
selectedLabel.Position=UDim2.fromOffset(9,38)
selectedLabel.BackgroundColor3=Color3.fromRGB(21,21,24)
selectedLabel.TextColor3=Color3.fromRGB(225,225,230)
selectedLabel.TextSize=11
selectedLabel.Font=Enum.Font.Code
selectedLabel.TextWrapped=true
selectedLabel.Parent=frame
Instance.new("UICorner",selectedLabel).CornerRadius=UDim.new(0,8)

local statusLabel=Instance.new("TextLabel")
statusLabel.Size=UDim2.new(1,-18,0,62)
statusLabel.Position=UDim2.fromOffset(9,86)
statusLabel.BackgroundColor3=Color3.fromRGB(21,21,24)
statusLabel.TextColor3=Color3.fromRGB(225,225,230)
statusLabel.TextSize=11
statusLabel.Font=Enum.Font.Code
statusLabel.TextWrapped=true
statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,8)

local armBtn=Instance.new("TextButton")
armBtn.Size=UDim2.new(1,-18,0,38)
armBtn.Position=UDim2.fromOffset(9,155)
armBtn.BackgroundColor3=Color3.fromRGB(42,42,47)
armBtn.TextColor3=Color3.new(1,1,1)
armBtn.TextSize=12
armBtn.Font=Enum.Font.GothamBold
armBtn.Text="ARMAR PICKUP RÁPIDO"
armBtn.Parent=frame
Instance.new("UICorner",armBtn).CornerRadius=UDim.new(0,8)

local note=Instance.new("TextLabel")
note.Size=UDim2.new(1,-18,0,18)
note.Position=UDim2.fromOffset(9,197)
note.BackgroundTransparency=1
note.Text="1º pickup imediato + 1 retry na mesma instância"
note.TextColor3=Color3.fromRGB(150,150,158)
note.TextSize=9
note.Font=Enum.Font.Code
note.Parent=frame

local function cleanup()
    disconnectAll()
    S.active=false
    pcall(function() gui:Destroy() end)
end
ENV[RUNTIME_KEY]={cleanup=cleanup,state=S}

armBtn.MouseButton1Click:Connect(function()
    if not S.active and not S.sending then arm() end
end)

task.spawn(function()
    while gui.Parent do
        local candidate,container=(not S.active and not S.sending) and chooseItem() or nil,nil
        if not S.active and not S.sending then candidate,container=chooseItem() end
        if candidate then
            selectedLabel.Text=string.format("Cristal: %s • BagId %s\n%s kg • $%s",tostring(candidate.gemName),tostring(candidate.bagId),tostring(candidate.kg or "?"),tostring(candidate.value or "?"))
        elseif S.test.selected then
            selectedLabel.Text=string.format("Teste: %s • antigo %s • novo %s",tostring(S.test.selected.gemName),tostring(S.test.selected.oldBagId),tostring(S.test.firstNewBagId or "..."))
        else
            selectedLabel.Text="Cristal: nenhum Tool com BagId encontrado"
        end

        statusLabel.Text=string.format(
            "Status: %s\nFase: %s • 1º:%s • 2º:%s\nSinais:%d • Reg:%d",
            tostring(S.status),
            tostring(S.phase),
            S.firstPickupConfirmed and "OK" or (S.firstPromptFired and "..." or "-"),
            S.secondAttempted and "FEITO" or "-",
            #S.signals,
            S.counters.records
        )

        local busy=S.active or S.sending
        armBtn.Active=not busy
        armBtn.AutoButtonColor=not busy
        armBtn.Text=S.sending and "ENVIANDO..." or (S.active and "TESTE EM ANDAMENTO" or "ARMAR PICKUP RÁPIDO")
        task.wait(0.35)
    end
end)

return {Arm=arm,State=S,Cleanup=cleanup,Version=CFG.VERSION}
