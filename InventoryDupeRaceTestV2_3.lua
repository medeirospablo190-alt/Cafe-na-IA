--==============================================================
-- CAFEINA • CRYSTAL DUP RACE TEST V2.3
-- Manual legitimate drop -> TWO immediate prompt activations -> observe server
-- Focused/event-driven • no hook • no spatial scan • no DropCrystal automation
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

local CFG = {
    VERSION = "CAFEINA_CRYSTAL_DUP_RACE_TEST_V2_3",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    ARM_TIMEOUT = 20,
    OBSERVE_AFTER_DOUBLE = 1.50,
    REPLICATION_GRACE = 0.18,
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
        ENV and ENV.request,
        ENV and ENV.http_request,
        request,
        http_request,
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
        for k,val in pairs(v) do
            n += 1
            if n > 16 then break end
            out[tostring(k)] = safe(val, depth+1)
        end
        return out
    end
    return tostring(v)
end

local function attrsOf(obj)
    local out = {}
    if not obj then return out end
    pcall(function()
        for k,v in pairs(obj:GetAttributes()) do out[k] = safe(v) end
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
        if crystal:IsA("Model") then pos = crystal:GetPivot().Position
        elseif crystal:IsA("BasePart") then pos = crystal.Position end
    end)
    return {name=crystal.Name,path=pathOf(crystal),class=crystal.ClassName,position=pos and tostring(pos) or nil,attributes=attrsOf(crystal)}
end

local S = {
    active=false,sending=false,finalized=false,status="aguardando",phase="idle",
    seq=0,runId="",startedAt=0,finishedAt=0,
    records={},signals={},errors={},connections={},
    selected=nil,targetCrystal=nil,targetPrompt=nil,pendingWorld=nil,
    doubleFired=false,marks={},test={},
    counters={
        records=0,inventoryChanged=0,gemCollected=0,toolRemoved=0,
        toolAdded=0,worldAdded=0,worldRemoved=0,
        promptCalls=0,uploadAttempts=0,droppedRecords=0,
    },
}

local function addError(phase,msg)
    if #S.errors < CFG.MAX_ERRORS then
        S.errors[#S.errors+1] = {phase=tostring(phase),error=tostring(msg),clock=os.clock(),unix=os.time()}
    end
end

local function rec(data)
    if #S.records >= CFG.MAX_RECORDS then
        S.counters.droppedRecords += 1
        return
    end
    S.seq += 1
    data.seq = S.seq
    data.clock = data.clock or os.clock()
    data.unix = data.unix or os.time()
    data.phase = data.phase or S.phase
    S.records[#S.records+1] = data
    S.counters.records += 1
    return data
end

local function signal(code,severity,details)
    if #S.signals >= CFG.MAX_SIGNALS then return end
    local item = {code=tostring(code),severity=tostring(severity or "info"),phase=S.phase,clock=os.clock(),unix=os.time(),details=safe(details or {})}
    S.signals[#S.signals+1] = item
    rec({kind="consistency_signal",signal=item})
end

local function containers()
    return {LP:FindFirstChildOfClass("Backpack"),LP.Character}
end

local function itemFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local bagId = tool:GetAttribute("BagId")
    local gemName = tool:GetAttribute("GemName")
    if bagId == nil or not gemName then return nil end
    return {
        bagId=bagId,gemName=gemName,kg=tool:GetAttribute("Kg"),value=tool:GetAttribute("Value"),
        rarity=tool:GetAttribute("Rarity"),sizeLetter=tool:GetAttribute("SizeLetter"),snapshot=toolSnap(tool),
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
                if obj:IsA("Tool") and tostring(obj:GetAttribute("BagId")) == tostring(id) then return obj end
            end
        end
    end
end

local function sameTool(obj,item)
    if not obj or not obj:IsA("Tool") or obj:GetAttribute("GemName") ~= item.gemName then return false end
    local kg,value=obj:GetAttribute("Kg"),obj:GetAttribute("Value")
    if item.kg~=nil and kg~=nil and tonumber(item.kg)~=tonumber(kg) then return false end
    if item.value~=nil and value~=nil and tonumber(item.value)~=tonumber(value) then return false end
    if item.rarity~=nil and obj:GetAttribute("Rarity")~=nil and tostring(item.rarity)~=tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter~=nil and obj:GetAttribute("SizeLetter")~=nil and tostring(item.sizeLetter)~=tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function sameWorld(obj,item)
    if not obj or not obj.Parent or obj.Name ~= item.gemName then return false end
    local kg,value=obj:GetAttribute("Kg"),obj:GetAttribute("Value")
    if item.kg~=nil and kg~=nil and tonumber(item.kg)~=tonumber(kg) then return false end
    if item.value~=nil and value~=nil and tonumber(item.value)~=tonumber(value) then return false end
    if item.rarity~=nil and obj:GetAttribute("Rarity")~=nil and tostring(item.rarity)~=tostring(obj:GetAttribute("Rarity")) then return false end
    if item.sizeLetter~=nil and obj:GetAttribute("SizeLetter")~=nil and tostring(item.sizeLetter)~=tostring(obj:GetAttribute("SizeLetter")) then return false end
    return true
end

local function activeToolState(item)
    local tools,bagSet,bagCount = 0,{},0
    for _,container in ipairs(containers()) do
        if container then
            for _,obj in ipairs(container:GetChildren()) do
                if sameTool(obj,item) then
                    tools += 1
                    local id=obj:GetAttribute("BagId")
                    if id~=nil and not bagSet[tostring(id)] then bagSet[tostring(id)]=true; bagCount+=1 end
                end
            end
        end
    end
    return tools,bagCount,bagSet
end

local function uidWorldCount(uid)
    if not DroppedGems or uid==nil then return 0 end
    local n=0
    for _,obj in ipairs(DroppedGems:GetChildren()) do
        if tostring(obj:GetAttribute("Uid")) == tostring(uid) then n += 1 end
    end
    return n
end

local function disconnectAll()
    for _,c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    S.connections={}
end

local function httpRequest(options)
    if not REQUEST then return false,nil,"request unavailable" end
    local ok,response=pcall(REQUEST,options)
    if not ok or not response then return false,nil,tostring(response) end
    local status=tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body=tostring(response.Body or response.body or "")
    return status>=200 and status<300,{status=status,body=body},nil
end

local function findPrompt(crystal)
    if not crystal then return nil end
    for _,obj in ipairs(crystal:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then return obj end
    end
end

local function buildSummary()
    local tools,bags,bagSet=0,0,{}
    if S.selected then tools,bags,bagSet=activeToolState(S.selected) end
    S.test.finalState={
        oldBagIdPresent=S.selected and findBagId(S.selected.bagId)~=nil or false,
        activeMatchingTools=tools,
        activeMatchingBagIds=bags,
        activeBagIds=bagSet,
        uid=S.test.uid,
        sameUidWorldCount=S.test.uid and uidWorldCount(S.test.uid) or nil,
        targetStillInWorld=S.targetCrystal and S.targetCrystal.Parent~=nil or false,
        toolAdditions=#(S.test.toolAdditions or {}),
        inventoryEventsAfterDouble=S.test.inventoryEventsAfterDouble or 0,
        gemCollectedAfterDouble=S.test.gemCollectedAfterDouble or 0,
    }
    if tools>1 then signal("MULTIPLE_MATCHING_TOOLS_ACTIVE","critical",{tools=tools,bagIds=bagSet}) end
    if bags>1 then signal("MULTIPLE_MATCHING_BAGIDS_ACTIVE","critical",{bags=bags,bagIds=bagSet}) end
    if (S.test.inventoryEventsAfterDouble or 0)>1 then signal("MULTIPLE_INVENTORY_EVENTS_AFTER_DOUBLE","warning",{count=S.test.inventoryEventsAfterDouble}) end
    if (S.test.gemCollectedAfterDouble or 0)>1 then signal("MULTIPLE_GEMCOLLECTED_AFTER_DOUBLE","warning",{count=S.test.gemCollectedAfterDouble}) end
    if S.test.uid and uidWorldCount(S.test.uid)>1 then signal("SAME_UID_MULTIPLE_WORLD_OBJECTS","critical",{uid=S.test.uid,count=uidWorldCount(S.test.uid)}) end
end

local function payload()
    buildSummary()
    return {
        schemaVersion=1,userId=tostring(LP.UserId),username=LP.Name,capturedAt=DateTime.now():ToIsoDate(),placeId=game.PlaceId,gameId=game.GameId,runId=S.runId,
        trace={
            version=CFG.VERSION,purpose="crystal_double_proximity_prompt_race",runId=S.runId,startedAt=S.startedAt,finishedAt=S.finishedAt,
            records=S.records,remotes={{name="InventoryChanged",path=pathOf(InventoryChanged)},{name="GemCollected",path=pathOf(GemCollected)}},
            pickupSessions={},bagMap={},dupeRace=S.test,anomalies=S.signals,
            diagnostics={errors=S.errors,counters=S.counters,transport={endpoint=CFG.ENDPOINT,retries=CFG.RETRIES},guards={noHook=true,noSpatialPolling=true,noTouchWatcher=true,noDropRemoteAutomation=true,exactPromptCalls=2,eventDrivenTargeting=true,maxRecords=CFG.MAX_RECORDS}}
        }
    }
end

local function upload()
    local okEncode,body=pcall(HttpService.JSONEncode,HttpService,payload())
    if not okEncode then return false,nil,"json_encode_failed" end
    if type(writefile)=="function" then pcall(writefile,"Cafeina_DupeRace_"..tostring(game.PlaceId).."_"..S.runId:gsub("-","")..".json",body) end
    for attempt=1,CFG.RETRIES do
        S.counters.uploadAttempts+=1
        local ok,response,err=httpRequest({Url=CFG.ENDPOINT,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json"},Body=body})
        if ok then local receipt; pcall(function() receipt=HttpService:JSONDecode(response.body) end); return true,receipt,nil end
        if attempt<CFG.RETRIES then task.wait(attempt*1.2) else return false,nil,err or "upload_failed" end
    end
end

local function finish(reason)
    if S.finalized then return end
    S.finalized=true; S.active=false; S.finishedAt=os.time(); S.test.finishReason=reason; disconnectAll(); S.sending=true; S.status="enviando resultado"
    local ok,receipt,err=upload(); S.sending=false
    if ok then
        local mirrored=receipt and receipt.github and receipt.github.mirrored
        S.status="TESTE ENVIADO"..(mirrored and " • GITHUB ✓" or " • RENDER ✓")
    else
        S.status="TESTE SALVO • ENVIO FALHOU"; addError("upload",err)
    end
end

local function doubleFire(prompt)
    if not S.active or S.finalized or S.doubleFired or not prompt or not prompt:IsA("ProximityPrompt") then return end
    if type(fireproximityprompt)~="function" then addError("double_fire","fireproximityprompt unavailable"); finish("missing_prompt_api"); return end

    S.doubleFired=true
    S.targetPrompt=prompt
    S.phase="double_prompt_fire"
    S.marks.doubleStart=os.clock()

    local t1=os.clock()
    local ok1,err1=pcall(fireproximityprompt,prompt)
    local r1=os.clock()
    S.counters.promptCalls+=1

    local stillPresentAfterFirst = prompt.Parent~=nil
    local enabledAfterFirst = stillPresentAfterFirst and prompt.Enabled or nil

    local t2=os.clock()
    local ok2,err2=pcall(fireproximityprompt,prompt)
    local r2=os.clock()
    S.counters.promptCalls+=1
    S.marks.secondPromptFire=t2

    S.test.doublePrompt={
        first={fireClock=t1,returnClock=r1,durationMs=(r1-t1)*1000,success=ok1,error=ok1 and nil or tostring(err1)},
        second={fireClock=t2,returnClock=r2,durationMs=(r2-t2)*1000,success=ok2,error=ok2 and nil or tostring(err2)},
        gapFirstStartToSecondStartMs=(t2-t1)*1000,
        gapFirstReturnToSecondStartMs=(t2-r1)*1000,
        promptStillPresentAfterFirst=stillPresentAfterFirst,
        promptEnabledAfterFirst=enabledAfterFirst,
    }
    rec({kind="double_proximity_prompt_fire",prompt=pathOf(prompt),double=S.test.doublePrompt})

    if not ok1 then addError("first_prompt",err1) end
    if not ok2 then addError("second_prompt",err2) end
    S.status="2 prompts enviados • observando servidor"

    task.delay(CFG.OBSERVE_AFTER_DOUBLE,function()
        if S.active and not S.finalized then finish("double_prompt_observed") end
    end)
end

local function confirmWorldCrystal(crystal)
    if not S.active or S.targetCrystal or not sameWorld(crystal,S.selected) then return end
    if findBagId(S.selected.bagId) then
        S.pendingWorld=crystal
        local candidate=crystal
        task.delay(CFG.REPLICATION_GRACE,function()
            if not S.active or S.targetCrystal or S.pendingWorld~=candidate then return end
            if candidate.Parent and not findBagId(S.selected.bagId) then confirmWorldCrystal(candidate) end
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

    local prompt=findPrompt(crystal)
    if prompt then
        if prompt.Enabled then doubleFire(prompt) else
            local conn
            conn=prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
                if not S.active or S.doubleFired then if conn then conn:Disconnect() end; return end
                if prompt.Enabled then if conn then conn:Disconnect() end; doubleFire(prompt) end
            end)
            S.connections[#S.connections+1]=conn
        end
    else
        local conn
        conn=crystal.DescendantAdded:Connect(function(obj)
            if not S.active or S.doubleFired then if conn then conn:Disconnect() end; return end
            if obj:IsA("ProximityPrompt") then
                if conn then conn:Disconnect() end
                if obj.Enabled then doubleFire(obj) else
                    local en
                    en=obj:GetPropertyChangedSignal("Enabled"):Connect(function()
                        if not S.active or S.doubleFired then if en then en:Disconnect() end; return end
                        if obj.Enabled then if en then en:Disconnect() end; doubleFire(obj) end
                    end)
                    S.connections[#S.connections+1]=en
                end
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
            if tostring(obj:GetAttribute("BagId"))~=tostring(S.selected.bagId) then return end
            local candidateClock=os.clock()
            task.delay(CFG.REPLICATION_GRACE,function()
                if not S.active or S.marks.toolRemoved then return end
                if not findBagId(S.selected.bagId) then
                    S.marks.toolRemoved=candidateClock; S.counters.toolRemoved+=1
                    rec({kind="selected_tool_removed_confirmed",container=label,oldBagId=S.selected.bagId,clock=candidateClock})
                    if S.pendingWorld and S.pendingWorld.Parent then confirmWorldCrystal(S.pendingWorld) end
                end
            end)
        end)
        local added=container.ChildAdded:Connect(function(obj)
            if not S.active or not obj:IsA("Tool") or not sameTool(obj,S.selected) then return end
            local bagId=obj:GetAttribute("BagId")
            if not S.targetCrystal and tostring(bagId)==tostring(S.selected.bagId) then return end
            if not S.doubleFired then return end
            S.counters.toolAdded+=1
            S.test.toolAdditions=S.test.toolAdditions or {}
            local entry={clock=os.clock(),container=label,bagId=bagId,tool=toolSnap(obj)}
            S.test.toolAdditions[#S.test.toolAdditions+1]=entry
            rec({kind="pickup_tool_added_after_double",entry=entry})
            if #S.test.toolAdditions>1 then signal("SECOND_TOOL_ADDITION_AFTER_DOUBLE","critical",{count=#S.test.toolAdditions,latestBagId=bagId}) end
        end)
        S.connections[#S.connections+1]=removed
        S.connections[#S.connections+1]=added
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"),"Backpack")
    watchContainer(LP.Character,"Character")
    local charConn=LP.CharacterAdded:Connect(function(char) if S.active then watchContainer(char,"Character") end end)
    S.connections[#S.connections+1]=charConn

    if DroppedGems then
        local added=DroppedGems.ChildAdded:Connect(function(crystal) if S.active then confirmWorldCrystal(crystal) end end)
        local removed=DroppedGems.ChildRemoved:Connect(function(crystal)
            if not S.active or crystal~=S.targetCrystal then return end
            S.counters.worldRemoved+=1; S.marks.worldRemoved=S.marks.worldRemoved or os.clock()
            rec({kind="target_world_removed",crystal=crystalSnap(crystal)})
        end)
        S.connections[#S.connections+1]=added
        S.connections[#S.connections+1]=removed
    end

    if InventoryChanged and InventoryChanged:IsA("RemoteEvent") then
        local conn=InventoryChanged.OnClientEvent:Connect(function(...)
            if not S.active then return end
            S.counters.inventoryChanged+=1
            local packed=table.pack(...); local args={}
            for i=1,math.min(packed.n or #packed,8) do args[i]=safe(packed[i]) end
            local stage=S.doubleFired and "after_double_prompt" or "drop_transition"
            if S.doubleFired then S.test.inventoryEventsAfterDouble=(S.test.inventoryEventsAfterDouble or 0)+1 end
            rec({kind="inventory_changed",stage=stage,arguments=args})
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
            local stage=S.doubleFired and "after_double_prompt" or "before_double_prompt"
            if S.doubleFired then S.test.gemCollectedAfterDouble=(S.test.gemCollectedAfterDouble or 0)+1 end
            rec({kind="gem_collected",stage=stage,crystal=safe(crystal),player=safe(player)})
        end)
        S.connections[#S.connections+1]=conn
    end
end

local function resetState()
    disconnectAll()
    S.active=false;S.sending=false;S.finalized=false;S.status="aguardando";S.phase="idle";S.seq=0;S.runId="";S.startedAt=0;S.finishedAt=0
    S.records={};S.signals={};S.errors={};S.connections={};S.selected=nil;S.targetCrystal=nil;S.targetPrompt=nil;S.pendingWorld=nil;S.doubleFired=false;S.marks={};S.test={}
    S.counters={records=0,inventoryChanged=0,gemCollected=0,toolRemoved=0,toolAdded=0,worldAdded=0,worldRemoved=0,promptCalls=0,uploadAttempts=0,droppedRecords=0}
end

local function arm()
    if S.active or S.sending then return false end
    resetState()
    if not DroppedGems then S.status="DroppedGems não encontrado"; return false end
    if type(fireproximityprompt)~="function" then S.status="executor sem fireproximityprompt"; return false end
    local item,container=chooseItem()
    if not item then S.status="nenhum cristal com BagId"; return false end
    S.selected=item;S.runId=HttpService:GenerateGUID(false);S.startedAt=os.time();S.active=true;S.phase="armed";S.status="ARMADO • solte esse cristal normalmente"
    S.test.selected={oldBagId=item.bagId,gemName=item.gemName,kg=item.kg,value=item.value,rarity=item.rarity,sizeLetter=item.sizeLetter,container=container,tool=item.snapshot}
    rec({kind="double_prompt_test_armed",selected=S.test.selected})
    installWatchers()
    task.delay(CFG.ARM_TIMEOUT,function() if S.active and not S.targetCrystal and not S.finalized then finish("arm_timeout_no_drop") end end)
    return true
end

for _,key in ipairs({"__CAFEINA_INVTRACE_RUNTIME_V64","__CAFEINA_INVTRACE_RUNTIME_NOHOOK","__CAFEINA_DUP_TEST_RUNTIME_V11","__CAFEINA_DUP_RACE_RUNTIME_V2","__CAFEINA_DUP_RACE_RUNTIME_V21","__CAFEINA_DUP_RACE_RUNTIME_V22","__CAFEINA_DUP_RACE_RUNTIME_V23"}) do
    local rt=rawget(ENV,key)
    if type(rt)=="table" then local fn=rt.cleanup or rt.stop; if type(fn)=="function" then pcall(fn) end end
end

local RUNTIME_KEY="__CAFEINA_DUP_RACE_RUNTIME_V23"

for _,parent in ipairs({CoreGui,LP:FindFirstChildOfClass("PlayerGui")}) do
    if parent then local old=parent:FindFirstChild("CafeinaDupeRaceV23"); if old then pcall(function() old:Destroy() end) end end
end

local gui=Instance.new("ScreenGui")
gui.Name="CafeinaDupeRaceV23";gui.ResetOnSpawn=false;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent=CoreGui end)
if not gui.Parent then gui.Parent=LP:WaitForChild("PlayerGui") end

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(306,210);frame.Position=UDim2.new(0.5,-153,0.16,0);frame.BackgroundColor3=Color3.fromRGB(12,12,14);frame.BackgroundTransparency=0.04;frame.BorderSizePixel=0;frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-18,0,28);title.Position=UDim2.fromOffset(9,7);title.BackgroundTransparency=1;title.Text="CAFEINA • DOUBLE PROMPT V2.3";title.TextColor3=Color3.new(1,1,1);title.TextSize=14;title.Font=Enum.Font.GothamBold;title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=frame

local selectedLabel=Instance.new("TextLabel")
selectedLabel.Size=UDim2.new(1,-18,0,42);selectedLabel.Position=UDim2.fromOffset(9,38);selectedLabel.BackgroundColor3=Color3.fromRGB(21,21,24);selectedLabel.TextColor3=Color3.fromRGB(225,225,230);selectedLabel.TextSize=11;selectedLabel.Font=Enum.Font.Code;selectedLabel.TextWrapped=true;selectedLabel.Parent=frame
Instance.new("UICorner",selectedLabel).CornerRadius=UDim.new(0,8)

local statusLabel=Instance.new("TextLabel")
statusLabel.Size=UDim2.new(1,-18,0,52);statusLabel.Position=UDim2.fromOffset(9,86);statusLabel.BackgroundColor3=Color3.fromRGB(21,21,24);statusLabel.TextColor3=Color3.fromRGB(225,225,230);statusLabel.TextSize=11;statusLabel.Font=Enum.Font.Code;statusLabel.TextWrapped=true;statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,8)

local armBtn=Instance.new("TextButton")
armBtn.Size=UDim2.new(1,-18,0,38);armBtn.Position=UDim2.fromOffset(9,145);armBtn.BackgroundColor3=Color3.fromRGB(42,42,47);armBtn.TextColor3=Color3.new(1,1,1);armBtn.TextSize=12;armBtn.Font=Enum.Font.GothamBold;armBtn.Text="ARMAR DUPLO PROMPT";armBtn.Parent=frame
Instance.new("UICorner",armBtn).CornerRadius=UDim.new(0,8)

local function refresh()
    if S.selected then selectedLabel.Text=tostring(S.selected.gemName).." • BagId "..tostring(S.selected.bagId) else selectedLabel.Text="Equipe o cristal que deseja testar" end
    statusLabel.Text="Status: "..tostring(S.status).."\nPrompt calls: "..tostring(S.counters.promptCalls).."/2 • Tools+: "..tostring(S.counters.toolAdded).." • Inv: "..tostring(S.counters.inventoryChanged).." • Gem: "..tostring(S.counters.gemCollected)
    armBtn.Text=S.active and "TESTE EM ANDAMENTO" or (S.sending and "ENVIANDO..." or "ARMAR DUPLO PROMPT")
    armBtn.AutoButtonColor=not (S.active or S.sending)
end

armBtn.MouseButton1Click:Connect(function()
    if not S.active and not S.sending then arm(); refresh() end
end)

task.spawn(function()
    while gui.Parent do refresh(); task.wait(0.20) end
end)

ENV[RUNTIME_KEY]={
    cleanup=function()
        disconnectAll();S.active=false
        if gui then pcall(function() gui:Destroy() end) end
    end,
    stop=function() disconnectAll();S.active=false end,
}

refresh()
