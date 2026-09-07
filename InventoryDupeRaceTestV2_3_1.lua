--==============================================================
-- CAFEINA • CRYSTAL DUP RACE TEST V2.3.1
-- Manual legitimate drop -> TWO immediate ProximityPrompt activations
-- Focused/event-driven • no hook • no spatial scan • no DropCrystal automation
--==============================================================

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")

local LP=Players.LocalPlayer
local ENV=(getgenv and getgenv()) or _G

local CFG={
    VERSION="CAFEINA_CRYSTAL_DUP_RACE_TEST_V2_3_1",
    ENDPOINT="https://cafe-na-ia.onrender.com/api/inventory-trace",
    ARM_TIMEOUT=20,
    OBSERVE=1.50,
    REPLICATION_GRACE=0.18,
    MAX_RECORDS=220,
    MAX_ERRORS=12,
    MAX_SIGNALS=16,
    RETRIES=3,
}

local GemSignals=ReplicatedStorage:FindFirstChild("GemSignals")
local GemRemotes=ReplicatedStorage:FindFirstChild("GemRemotes")
local GemCollected=GemSignals and GemSignals:FindFirstChild("GemCollected")
local InventoryChanged=GemRemotes and GemRemotes:FindFirstChild("InventoryChanged")
local DroppedGems=Workspace:FindFirstChild("DroppedGems")

local function resolveRequest()
    local t={ENV and ENV.request,ENV and ENV.http_request,request,http_request,syn and syn.request,http and http.request}
    for _,fn in ipairs(t) do if type(fn)=="function" then return fn end end
end
local REQUEST=resolveRequest()

local function pathOf(obj)
    if not obj then return "nil" end
    local ok,v=pcall(function() return obj:GetFullName() end)
    return ok and v or tostring(obj)
end

local function safe(v,depth)
    depth=depth or 0
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="number" then return v end
    if t=="string" then return #v<=500 and v or string.sub(v,1,500).."...[truncated]" end
    if t=="Vector3" or t=="Vector2" or t=="Color3" or t=="EnumItem" then return tostring(v) end
    if t=="CFrame" then return tostring(v.Position) end
    if t=="Instance" then return {type="Instance",class=v.ClassName,name=v.Name,path=pathOf(v)} end
    if t=="table" then
        if depth>=2 then return "<table>" end
        local out,n={},0
        for k,val in pairs(v) do n+=1;if n>16 then break end;out[tostring(k)]=safe(val,depth+1) end
        return out
    end
    return tostring(v)
end

local function attrsOf(obj)
    local out={}
    if obj then pcall(function() for k,v in pairs(obj:GetAttributes()) do out[k]=safe(v) end end) end
    return out
end

local function toolSnap(tool) return tool and {name=tool.Name,path=pathOf(tool),attributes=attrsOf(tool)} or nil end
local function crystalSnap(c)
    if not c then return nil end
    local pos
    pcall(function() if c:IsA("Model") then pos=c:GetPivot().Position elseif c:IsA("BasePart") then pos=c.Position end end)
    return {name=c.Name,path=pathOf(c),class=c.ClassName,position=pos and tostring(pos) or nil,attributes=attrsOf(c)}
end

local S={
    active=false,sending=false,finalized=false,status="aguardando",phase="idle",seq=0,runId="",startedAt=0,finishedAt=0,
    records={},signals={},errors={},connections={},selected=nil,targetCrystal=nil,pendingWorld=nil,doubleFired=false,marks={},test={},
    baselineBagIds={},newBagIds={},
    counters={records=0,inventoryChanged=0,gemCollected=0,toolRemoved=0,toolAdded=0,worldAdded=0,worldRemoved=0,promptCalls=0,uploadAttempts=0,droppedRecords=0},
}

local function addError(phase,msg)
    if #S.errors<CFG.MAX_ERRORS then S.errors[#S.errors+1]={phase=tostring(phase),error=tostring(msg),clock=os.clock(),unix=os.time()} end
end
local function rec(d)
    if #S.records>=CFG.MAX_RECORDS then S.counters.droppedRecords+=1;return end
    S.seq+=1;d.seq=S.seq;d.clock=d.clock or os.clock();d.unix=d.unix or os.time();d.phase=d.phase or S.phase
    S.records[#S.records+1]=d;S.counters.records+=1;return d
end
local function signal(code,severity,details)
    if #S.signals>=CFG.MAX_SIGNALS then return end
    local x={code=tostring(code),severity=tostring(severity or "info"),phase=S.phase,clock=os.clock(),unix=os.time(),details=safe(details or {})}
    S.signals[#S.signals+1]=x;rec({kind="consistency_signal",signal=x})
end

local function containers() return {LP:FindFirstChildOfClass("Backpack"),LP.Character} end
local function itemFromTool(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local id,name=tool:GetAttribute("BagId"),tool:GetAttribute("GemName")
    if id==nil or not name then return nil end
    return {bagId=id,gemName=name,kg=tool:GetAttribute("Kg"),value=tool:GetAttribute("Value"),rarity=tool:GetAttribute("Rarity"),sizeLetter=tool:GetAttribute("SizeLetter"),snapshot=toolSnap(tool)}
end
local function chooseItem()
    if LP.Character then for _,o in ipairs(LP.Character:GetChildren()) do local i=itemFromTool(o);if i then return i,"Character" end end end
    local b=LP:FindFirstChildOfClass("Backpack")
    if b then for _,o in ipairs(b:GetChildren()) do local i=itemFromTool(o);if i then return i,"Backpack" end end end
end
local function sameTool(o,i)
    if not o or not o:IsA("Tool") or o:GetAttribute("GemName")~=i.gemName then return false end
    local kg,val=o:GetAttribute("Kg"),o:GetAttribute("Value")
    if i.kg~=nil and kg~=nil and tonumber(i.kg)~=tonumber(kg) then return false end
    if i.value~=nil and val~=nil and tonumber(i.value)~=tonumber(val) then return false end
    if i.rarity~=nil and o:GetAttribute("Rarity")~=nil and tostring(i.rarity)~=tostring(o:GetAttribute("Rarity")) then return false end
    if i.sizeLetter~=nil and o:GetAttribute("SizeLetter")~=nil and tostring(i.sizeLetter)~=tostring(o:GetAttribute("SizeLetter")) then return false end
    return true
end
local function sameWorld(o,i)
    if not o or not o.Parent or o.Name~=i.gemName then return false end
    local kg,val=o:GetAttribute("Kg"),o:GetAttribute("Value")
    if i.kg~=nil and kg~=nil and tonumber(i.kg)~=tonumber(kg) then return false end
    if i.value~=nil and val~=nil and tonumber(i.value)~=tonumber(val) then return false end
    if i.rarity~=nil and o:GetAttribute("Rarity")~=nil and tostring(i.rarity)~=tostring(o:GetAttribute("Rarity")) then return false end
    if i.sizeLetter~=nil and o:GetAttribute("SizeLetter")~=nil and tostring(i.sizeLetter)~=tostring(o:GetAttribute("SizeLetter")) then return false end
    return true
end
local function findBagId(id)
    for _,c in ipairs(containers()) do if c then for _,o in ipairs(c:GetChildren()) do if o:IsA("Tool") and tostring(o:GetAttribute("BagId"))==tostring(id) then return o end end end end
end
local function matchingBagIds(item)
    local set={}
    for _,c in ipairs(containers()) do if c then for _,o in ipairs(c:GetChildren()) do if sameTool(o,item) then local id=o:GetAttribute("BagId");if id~=nil then set[tostring(id)]=true end end end end end
    return set
end
local function captureBaseline(item)
    S.baselineBagIds=matchingBagIds(item)
end
local function activeNewBagIds()
    local active=matchingBagIds(S.selected);local out,n={},0
    for id in pairs(active) do if not S.baselineBagIds[id] or id==tostring(S.selected.bagId) then
        if id~=tostring(S.selected.bagId) then out[id]=true;n+=1 end
    end end
    return n,out
end
local function uidWorldCount(uid)
    if not DroppedGems or uid==nil then return 0 end
    local n=0;for _,o in ipairs(DroppedGems:GetChildren()) do if tostring(o:GetAttribute("Uid"))==tostring(uid) then n+=1 end end;return n
end
local function disconnectAll() for _,c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end;S.connections={} end

local function httpRequest(opts)
    if not REQUEST then return false,nil,"request unavailable" end
    local ok,r=pcall(REQUEST,opts);if not ok or not r then return false,nil,tostring(r) end
    local status=tonumber(r.StatusCode or r.Status or r.status_code or r.status) or 0
    return status>=200 and status<300,{status=status,body=tostring(r.Body or r.body or "")},nil
end

local function buildSummary()
    local newCount,newSet=0,{}
    if S.selected then newCount,newSet=activeNewBagIds() end
    S.test.finalState={
        oldBagIdPresent=S.selected and findBagId(S.selected.bagId)~=nil or false,
        uid=S.test.uid,targetStillInWorld=S.targetCrystal and S.targetCrystal.Parent~=nil or false,
        sameUidWorldCount=S.test.uid and uidWorldCount(S.test.uid) or nil,
        distinctNewBagIdsObserved=S.test.distinctNewBagIdsObserved or 0,
        activeNewBagIds=newCount,activeNewBagIdSet=newSet,
        inventoryEventsAfterDouble=S.test.inventoryEventsAfterDouble or 0,
        gemCollectedAfterDouble=S.test.gemCollectedAfterDouble or 0,
    }
    if newCount>1 then signal("MULTIPLE_NEW_BAGIDS_ACTIVE","critical",{count=newCount,bagIds=newSet}) end
    if (S.test.distinctNewBagIdsObserved or 0)>1 then signal("MULTIPLE_NEW_BAGIDS_OBSERVED","critical",{count=S.test.distinctNewBagIdsObserved,bagIds=S.newBagIds}) end
    if (S.test.inventoryEventsAfterDouble or 0)>1 then signal("MULTIPLE_INVENTORY_EVENTS_AFTER_DOUBLE","warning",{count=S.test.inventoryEventsAfterDouble}) end
    if (S.test.gemCollectedAfterDouble or 0)>1 then signal("MULTIPLE_GEMCOLLECTED_AFTER_DOUBLE","warning",{count=S.test.gemCollectedAfterDouble}) end
    if S.test.uid and uidWorldCount(S.test.uid)>1 then signal("SAME_UID_MULTIPLE_WORLD_OBJECTS","critical",{uid=S.test.uid,count=uidWorldCount(S.test.uid)}) end
end
local function payload()
    buildSummary()
    return {schemaVersion=1,userId=tostring(LP.UserId),username=LP.Name,capturedAt=DateTime.now():ToIsoDate(),placeId=game.PlaceId,gameId=game.GameId,runId=S.runId,trace={version=CFG.VERSION,purpose="crystal_double_proximity_prompt_race",runId=S.runId,startedAt=S.startedAt,finishedAt=S.finishedAt,records=S.records,remotes={{name="InventoryChanged",path=pathOf(InventoryChanged)},{name="GemCollected",path=pathOf(GemCollected)}},pickupSessions={},bagMap={},dupeRace=S.test,anomalies=S.signals,diagnostics={errors=S.errors,counters=S.counters,transport={endpoint=CFG.ENDPOINT,retries=CFG.RETRIES},guards={noHook=true,noSpatialPolling=true,noTouchWatcher=true,noDropRemoteAutomation=true,maxPromptCalls=2,eventDrivenTargeting=true,baselineBagIdsIgnored=true,maxRecords=CFG.MAX_RECORDS}}}}
end
local function upload()
    local ok,body=pcall(HttpService.JSONEncode,HttpService,payload());if not ok then return false,nil,"json_encode_failed" end
    if type(writefile)=="function" then pcall(writefile,"Cafeina_DupeRace_"..tostring(game.PlaceId).."_"..S.runId:gsub("-","")..".json",body) end
    for a=1,CFG.RETRIES do S.counters.uploadAttempts+=1;local good,r,e=httpRequest({Url=CFG.ENDPOINT,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json"},Body=body});if good then local receipt;pcall(function() receipt=HttpService:JSONDecode(r.body) end);return true,receipt,nil end;if a<CFG.RETRIES then task.wait(a*1.2) else return false,nil,e or "upload_failed" end end
end
local function finish(reason)
    if S.finalized then return end
    S.finalized=true;S.active=false;S.finishedAt=os.time();S.test.finishReason=reason;disconnectAll();S.sending=true;S.status="enviando resultado"
    local ok,receipt,err=upload();S.sending=false
    if ok then local mirrored=receipt and receipt.github and receipt.github.mirrored;S.status="TESTE ENVIADO"..(mirrored and " • GITHUB ✓" or " • RENDER ✓") else S.status="TESTE SALVO • ENVIO FALHOU";addError("upload",err) end
end

local function findPrompt(c) if c then for _,o in ipairs(c:GetDescendants()) do if o:IsA("ProximityPrompt") then return o end end end end
local function doubleFire(prompt)
    if not S.active or S.finalized or S.doubleFired or not prompt or not prompt:IsA("ProximityPrompt") then return end
    if type(fireproximityprompt)~="function" then addError("double_fire","fireproximityprompt unavailable");finish("missing_prompt_api");return end
    S.doubleFired=true;S.phase="double_prompt_fire"
    local t1=os.clock();local ok1,e1=pcall(fireproximityprompt,prompt);local r1=os.clock();S.counters.promptCalls+=1
    local still=prompt.Parent~=nil;local enabled=still and prompt.Enabled or nil
    local t2=os.clock();local ok2,e2=pcall(fireproximityprompt,prompt);local r2=os.clock();S.counters.promptCalls+=1
    S.test.doublePrompt={first={fireClock=t1,returnClock=r1,durationMs=(r1-t1)*1000,success=ok1,error=ok1 and nil or tostring(e1)},second={fireClock=t2,returnClock=r2,durationMs=(r2-t2)*1000,success=ok2,error=ok2 and nil or tostring(e2)},gapFirstStartToSecondStartMs=(t2-t1)*1000,gapFirstReturnToSecondStartMs=(t2-r1)*1000,promptStillPresentAfterFirst=still,promptEnabledAfterFirst=enabled}
    rec({kind="double_proximity_prompt_fire",prompt=pathOf(prompt),double=S.test.doublePrompt})
    if not ok1 then addError("first_prompt",e1) end;if not ok2 then addError("second_prompt",e2) end
    S.status="2 prompts enviados • observando servidor"
    task.delay(CFG.OBSERVE,function() if S.active and not S.finalized then finish("double_prompt_observed") end end)
end

local function confirmWorld(c)
    if not S.active or S.targetCrystal or not sameWorld(c,S.selected) then return end
    if findBagId(S.selected.bagId) then
        S.pendingWorld=c;local candidate=c
        task.delay(CFG.REPLICATION_GRACE,function() if S.active and not S.targetCrystal and S.pendingWorld==candidate and candidate.Parent and not findBagId(S.selected.bagId) then confirmWorld(candidate) end end)
        return
    end
    S.pendingWorld=nil;S.targetCrystal=c;S.phase="world_seen";S.counters.worldAdded+=1;S.test.uid=c:GetAttribute("Uid");S.test.world=crystalSnap(c);rec({kind="target_world_added",crystal=S.test.world,oldBagId=S.selected.bagId})
    local p=findPrompt(c)
    if p then
        if p.Enabled then doubleFire(p) else local en;en=p:GetPropertyChangedSignal("Enabled"):Connect(function() if not S.active or S.doubleFired then if en then en:Disconnect() end;return end;if p.Enabled then if en then en:Disconnect() end;doubleFire(p) end end);S.connections[#S.connections+1]=en end
    else
        local d;d=c.DescendantAdded:Connect(function(o) if not S.active or S.doubleFired then if d then d:Disconnect() end;return end;if o:IsA("ProximityPrompt") then if d then d:Disconnect() end;if o.Enabled then doubleFire(o) else local en;en=o:GetPropertyChangedSignal("Enabled"):Connect(function() if not S.active or S.doubleFired then if en then en:Disconnect() end;return end;if o.Enabled then if en then en:Disconnect() end;doubleFire(o) end end);S.connections[#S.connections+1]=en end end end);S.connections[#S.connections+1]=d
    end
end

local function installWatchers()
    local function watchContainer(c,label)
        if not c then return end
        local rem=c.ChildRemoved:Connect(function(o)
            if not S.active or not o:IsA("Tool") or tostring(o:GetAttribute("BagId"))~=tostring(S.selected.bagId) then return end
            local tc=os.clock();task.delay(CFG.REPLICATION_GRACE,function() if S.active and not S.marks.toolRemoved and not findBagId(S.selected.bagId) then S.marks.toolRemoved=tc;S.counters.toolRemoved+=1;rec({kind="selected_tool_removed_confirmed",container=label,oldBagId=S.selected.bagId,clock=tc});if S.pendingWorld and S.pendingWorld.Parent then confirmWorld(S.pendingWorld) end end end)
        end)
        local add=c.ChildAdded:Connect(function(o)
            if not S.active or not S.doubleFired or not o:IsA("Tool") or not sameTool(o,S.selected) then return end
            local id=o:GetAttribute("BagId");if id==nil then return end
            S.counters.toolAdded+=1;rec({kind="matching_tool_added_after_double",container=label,bagId=id,tool=toolSnap(o)})
            local key=tostring(id)
            if key~=tostring(S.selected.bagId) and not S.baselineBagIds[key] and not S.newBagIds[key] then
                S.newBagIds[key]=true;S.test.distinctNewBagIdsObserved=(S.test.distinctNewBagIdsObserved or 0)+1
                rec({kind="new_bagid_observed_after_double",bagId=id,distinctCount=S.test.distinctNewBagIdsObserved})
                if S.test.distinctNewBagIdsObserved>1 then signal("SECOND_DISTINCT_NEW_BAGID","critical",{bagId=id,all=S.newBagIds}) end
            end
        end)
        S.connections[#S.connections+1]=rem;S.connections[#S.connections+1]=add
    end
    watchContainer(LP:FindFirstChildOfClass("Backpack"),"Backpack");watchContainer(LP.Character,"Character")
    local cc=LP.CharacterAdded:Connect(function(ch) if S.active then watchContainer(ch,"Character") end end);S.connections[#S.connections+1]=cc
    if DroppedGems then
        local a=DroppedGems.ChildAdded:Connect(function(c) if S.active then confirmWorld(c) end end)
        local r=DroppedGems.ChildRemoved:Connect(function(c) if S.active and c==S.targetCrystal then S.counters.worldRemoved+=1;rec({kind="target_world_removed",crystal=crystalSnap(c)}) end end)
        S.connections[#S.connections+1]=a;S.connections[#S.connections+1]=r
    end
    if InventoryChanged and InventoryChanged:IsA("RemoteEvent") then
        local x=InventoryChanged.OnClientEvent:Connect(function(...)
            if not S.active then return end;S.counters.inventoryChanged+=1;local p=table.pack(...);local args={};for i=1,math.min(p.n or #p,8) do args[i]=safe(p[i]) end
            local stage=S.doubleFired and "after_double_prompt" or "drop_transition";if S.doubleFired then S.test.inventoryEventsAfterDouble=(S.test.inventoryEventsAfterDouble or 0)+1 end;rec({kind="inventory_changed",stage=stage,arguments=args})
        end);S.connections[#S.connections+1]=x
    end
    if GemCollected and GemCollected:IsA("RemoteEvent") then
        local x=GemCollected.OnClientEvent:Connect(function(c,p,...)
            if not S.active then return end;if typeof(p)=="Instance" and p:IsA("Player") and p~=LP then return end;if S.targetCrystal and c~=S.targetCrystal then return end;if not S.targetCrystal and typeof(c)=="Instance" and not sameWorld(c,S.selected) then return end
            S.counters.gemCollected+=1;local stage=S.doubleFired and "after_double_prompt" or "before_double_prompt";if S.doubleFired then S.test.gemCollectedAfterDouble=(S.test.gemCollectedAfterDouble or 0)+1 end;rec({kind="gem_collected",stage=stage,crystal=safe(c),player=safe(p)})
        end);S.connections[#S.connections+1]=x
    end
end

local function reset()
    disconnectAll();S.active=false;S.sending=false;S.finalized=false;S.status="aguardando";S.phase="idle";S.seq=0;S.runId="";S.startedAt=0;S.finishedAt=0;S.records={};S.signals={};S.errors={};S.connections={};S.selected=nil;S.targetCrystal=nil;S.pendingWorld=nil;S.doubleFired=false;S.marks={};S.test={};S.baselineBagIds={};S.newBagIds={};S.counters={records=0,inventoryChanged=0,gemCollected=0,toolRemoved=0,toolAdded=0,worldAdded=0,worldRemoved=0,promptCalls=0,uploadAttempts=0,droppedRecords=0}
end
local function arm()
    if S.active or S.sending then return false end;reset()
    if not DroppedGems then S.status="DroppedGems não encontrado";return false end
    if type(fireproximityprompt)~="function" then S.status="executor sem fireproximityprompt";return false end
    local item,container=chooseItem();if not item then S.status="nenhum cristal com BagId";return false end
    S.selected=item;captureBaseline(item);S.runId=HttpService:GenerateGUID(false);S.startedAt=os.time();S.active=true;S.phase="armed";S.status="ARMADO • solte esse cristal normalmente"
    S.test.selected={oldBagId=item.bagId,gemName=item.gemName,kg=item.kg,value=item.value,rarity=item.rarity,sizeLetter=item.sizeLetter,container=container,tool=item.snapshot};S.test.baselineBagIds=safe(S.baselineBagIds);rec({kind="double_prompt_test_armed",selected=S.test.selected,baselineBagIds=S.test.baselineBagIds});installWatchers()
    task.delay(CFG.ARM_TIMEOUT,function() if S.active and not S.targetCrystal and not S.finalized then finish("arm_timeout_no_drop") end end);return true
end

for _,key in ipairs({"__CAFEINA_INVTRACE_RUNTIME_V64","__CAFEINA_INVTRACE_RUNTIME_NOHOOK","__CAFEINA_DUP_TEST_RUNTIME_V11","__CAFEINA_DUP_RACE_RUNTIME_V2","__CAFEINA_DUP_RACE_RUNTIME_V21","__CAFEINA_DUP_RACE_RUNTIME_V22","__CAFEINA_DUP_RACE_RUNTIME_V23","__CAFEINA_DUP_RACE_RUNTIME_V231"}) do local rt=rawget(ENV,key);if type(rt)=="table" then local fn=rt.cleanup or rt.stop;if type(fn)=="function" then pcall(fn) end end end
local RUNTIME_KEY="__CAFEINA_DUP_RACE_RUNTIME_V231"

for _,parent in ipairs({CoreGui,LP:FindFirstChildOfClass("PlayerGui")}) do if parent then for _,name in ipairs({"CafeinaDupeRaceV23","CafeinaDupeRaceV231"}) do local old=parent:FindFirstChild(name);if old then pcall(function() old:Destroy() end) end end end end
local gui=Instance.new("ScreenGui");gui.Name="CafeinaDupeRaceV231";gui.ResetOnSpawn=false;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;pcall(function() gui.Parent=CoreGui end);if not gui.Parent then gui.Parent=LP:WaitForChild("PlayerGui") end
local frame=Instance.new("Frame");frame.Size=UDim2.fromOffset(306,210);frame.Position=UDim2.new(0.5,-153,0.16,0);frame.BackgroundColor3=Color3.fromRGB(12,12,14);frame.BackgroundTransparency=0.04;frame.BorderSizePixel=0;frame.Active=true;frame.Draggable=true;frame.Parent=gui;Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local title=Instance.new("TextLabel");title.Size=UDim2.new(1,-18,0,28);title.Position=UDim2.fromOffset(9,7);title.BackgroundTransparency=1;title.Text="CAFEINA • DOUBLE PROMPT V2.3";title.TextColor3=Color3.new(1,1,1);title.TextSize=14;title.Font=Enum.Font.GothamBold;title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=frame
local selectedLabel=Instance.new("TextLabel");selectedLabel.Size=UDim2.new(1,-18,0,42);selectedLabel.Position=UDim2.fromOffset(9,38);selectedLabel.BackgroundColor3=Color3.fromRGB(21,21,24);selectedLabel.TextColor3=Color3.fromRGB(225,225,230);selectedLabel.TextSize=11;selectedLabel.Font=Enum.Font.Code;selectedLabel.TextWrapped=true;selectedLabel.Parent=frame;Instance.new("UICorner",selectedLabel).CornerRadius=UDim.new(0,8)
local statusLabel=Instance.new("TextLabel");statusLabel.Size=UDim2.new(1,-18,0,52);statusLabel.Position=UDim2.fromOffset(9,86);statusLabel.BackgroundColor3=Color3.fromRGB(21,21,24);statusLabel.TextColor3=Color3.fromRGB(225,225,230);statusLabel.TextSize=11;statusLabel.Font=Enum.Font.Code;statusLabel.TextWrapped=true;statusLabel.Parent=frame;Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,8)
local armBtn=Instance.new("TextButton");armBtn.Size=UDim2.new(1,-18,0,38);armBtn.Position=UDim2.fromOffset(9,145);armBtn.BackgroundColor3=Color3.fromRGB(42,42,47);armBtn.TextColor3=Color3.new(1,1,1);armBtn.TextSize=12;armBtn.Font=Enum.Font.GothamBold;armBtn.Text="ARMAR DUPLO PROMPT";armBtn.Parent=frame;Instance.new("UICorner",armBtn).CornerRadius=UDim.new(0,8)
local function refresh()
    selectedLabel.Text=S.selected and (tostring(S.selected.gemName).." • BagId "..tostring(S.selected.bagId)) or "Equipe o cristal que deseja testar"
    statusLabel.Text="Status: "..tostring(S.status).."\nPrompt: "..tostring(S.counters.promptCalls).."/2 • BagIds novos: "..tostring(S.test.distinctNewBagIdsObserved or 0).." • Inv: "..tostring(S.counters.inventoryChanged).." • Gem: "..tostring(S.counters.gemCollected)
    armBtn.Text=S.active and "TESTE EM ANDAMENTO" or (S.sending and "ENVIANDO..." or "ARMAR DUPLO PROMPT");armBtn.AutoButtonColor=not(S.active or S.sending)
end
armBtn.MouseButton1Click:Connect(function() if not S.active and not S.sending then arm();refresh() end end)
task.spawn(function() while gui.Parent do refresh();task.wait(0.20) end end)
ENV[RUNTIME_KEY]={cleanup=function() disconnectAll();S.active=false;if gui then pcall(function() gui:Destroy() end) end end,stop=function() disconnectAll();S.active=false end}
refresh()
