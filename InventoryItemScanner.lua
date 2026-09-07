--==============================================================--
-- CAFEINA • INVENTORY ITEM SCANNER V1.1
-- Universal • executor/mobile • passivo
-- START -> coleta -> ENCERRAR -> upload automatico -> GitHub mirror
--==============================================================--

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local StarterPack = game:GetService("StarterPack")
local PPS = game:GetService("ProximityPromptService")
local Http = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

pcall(function()
    local old=rawget(ENV,"__CAFEINA_INVITEM_RUNTIME")
    if type(old)=="table" and type(old.Cleanup)=="function" then old.Cleanup() end
end)

local CFG = {
    VERSION = "CAFEINA_INVENTORY_ITEM_SCANNER_V1_1",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    MAX_RECORDS = 2200,
    MAX_REMOTES = 500,
    MAX_ITEMS = 850,
    MAX_JSON = 4200000,
    MAX_SCAN = 60000,
    RETRIES = 3,
}

local ITEM_WORDS = {
    "item","tool","weapon","gun","sword","gear","egg","pet","crystal","gem","ore",
    "food","potion","boost","key","card","loot","collectible","ammo","armor","pickaxe",
    "drill","seed","fruit","bag","backpack","inventory","hotbar"
}

local REMOTE_WORDS = {
    "inventory","item","bag","tool","pickup","collect","drop","equip","unequip","give",
    "take","buy","sell","reward","claim","egg","pet","crystal","gem","weapon","gear",
    "loot","slot","carry","place","hatch"
}

local CONTAINER_NAMES = {
    backpack=true,inventory=true,inventories=true,items=true,tools=true,weapons=true,gear=true,
    eggs=true,egginventory=true,pets=true,petinventory=true,crystals=true,gems=true,loot=true,
    hotbar=true,storage=true,bag=true,bags=true,equipment=true
}

local ATTRS = {
    "ItemId","ItemID","UID","Uid","BagId","BagID","GemName","EggId","EggID",
    "PetId","PetID","ToolId","ToolID","WeaponId","WeaponID","GearId","GearID","AssetCategory",
    "Rarity","Value","Price","Cost","Kg","Weight","Amount","Quantity","Stack","Count","Tier"
}

local function norm(v)
    return string.lower(tostring(v or "")):gsub("[^%w]", "")
end

local function pathOf(obj)
    if not obj then return "nil" end
    local ok,p=pcall(function() return obj:GetFullName() end)
    return ok and p or tostring(obj)
end

local function safe(v,depth,seen)
    depth=depth or 0; seen=seen or {}
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="number" then return v end
    if t=="string" then return #v>800 and (v:sub(1,800).."...[truncated]") or v end
    if t=="Vector2" or t=="Vector3" or t=="CFrame" or t=="Color3" or t=="EnumItem" then return tostring(v) end
    if t=="Instance" then return {type="Instance",class=v.ClassName,name=v.Name,path=pathOf(v)} end
    if t=="table" then
        if depth>=3 or seen[v] then return "<table>" end
        seen[v]=true
        local out,n={},0
        for k,x in pairs(v) do
            n+=1; if n>35 then out.__truncated=true break end
            out[tostring(k)]=safe(x,depth+1,seen)
        end
        seen[v]=nil; return out
    end
    return tostring(v)
end

local function argsSafe(...)
    local p=table.pack(...); local out={}
    for i=1,math.min(p.n,16) do out[i]=safe(p[i]) end
    if p.n>16 then out.__truncated=p.n-16 end
    return out
end

local function requestFn()
    local list={ENV and ENV.request,ENV and ENV.http_request,request,http_request,syn and syn.request,http and http.request,fluxus and fluxus.request}
    for _,fn in ipairs(list) do if type(fn)=="function" then return fn end end
end
local REQUEST=requestFn()

local function hasWord(text,words)
    local n=norm(text)
    for _,w in ipairs(words) do if n:find(w,1,true) then return true end end
    return false
end

local function attrsOf(obj)
    local out={}; local ok,a=pcall(function() return obj:GetAttributes() end)
    if ok then
        local n=0
        for k,v in pairs(a) do n+=1; if n>25 then out.__truncated=true break end; out[k]=safe(v) end
    end
    return out
end

local function importantAttr(obj)
    for _,k in ipairs(ATTRS) do
        local ok,v=pcall(function() return obj:GetAttribute(k) end)
        if ok and v~=nil then return true end
    end
    return false
end

local function inInventory(obj)
    local cur=obj and obj.Parent
    for _=1,5 do
        if not cur then break end
        if cur:IsA("Backpack") or CONTAINER_NAMES[norm(cur.Name)] then return true end
        cur=cur.Parent
    end
    return false
end

local function pickupPrompt(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return false end
    local p=obj:FindFirstChildWhichIsA("ProximityPrompt",true); if not p then return false end
    local s=norm((p.ActionText or "").." "..(p.ObjectText or ""))
    return s:find("pick",1,true) or s:find("collect",1,true) or s:find("take",1,true)
        or s:find("grab",1,true) or s:find("steal",1,true) or s:find("loot",1,true) or hasWord(s,ITEM_WORDS)
end

local function itemLike(obj)
    if not obj then return false end
    return obj:IsA("Tool") or inInventory(obj) or importantAttr(obj) or hasWord(obj.Name,ITEM_WORDS) or pickupPrompt(obj)
end

local function remoteLike(obj)
    if not obj then return false end
    local c=obj.ClassName
    if c~="RemoteEvent" and c~="RemoteFunction" and c~="UnreliableRemoteEvent" then return false end
    local p=pathOf(obj)
    if p:find("ProfileMirror/ProfileDelta",1,true) then return true end
    return hasWord(obj.Name.." "..p,REMOTE_WORDS)
end

local function snap(obj,source)
    local s={source=source,class=obj.ClassName,name=obj.Name,path=pathOf(obj),attributes=attrsOf(obj)}
    if obj:IsA("Tool") then
        pcall(function() s.tool={canBeDropped=obj.CanBeDropped,requiresHandle=obj.RequiresHandle,textureId=obj.TextureId,tooltip=obj.ToolTip} end)
    elseif obj:IsA("StringValue") or obj:IsA("IntValue") or obj:IsA("NumberValue") or obj:IsA("BoolValue") then
        s.value=safe(obj.Value)
    end
    pcall(function()
        if obj:IsA("BasePart") then s.position=tostring(obj.Position)
        elseif obj:IsA("Model") then s.position=tostring(obj:GetPivot().Position) end
    end)
    return s
end

local S={
    running=false,sending=false,status="PRONTO",runId="",started=0,
    records={},items={},itemCount=0,remotes={},remoteSeen={},connections={},
    incomingSeen=setmetatable({},{__mode="k"}),
    counters={records=0,items=0,remotes=0,added=0,removed=0,prompts=0,incoming=0,outgoing=0,dropped=0},
    health={},upload={}
}

local function status(t) S.status=tostring(t or "") end
local function connect(sig,fn) local c=sig:Connect(fn); S.connections[#S.connections+1]=c; return c end
local function disconnectAll() for _,c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end; table.clear(S.connections) end

local function rec(kind,data)
    if not S.running then return end
    if #S.records>=CFG.MAX_RECORDS then S.counters.dropped+=1; return end
    data=data or {}; data.kind=kind; data.clock=os.clock(); data.unix=os.time()
    S.records[#S.records+1]=data; S.counters.records=#S.records
end

local function itemKey(s)
    local a=s.attributes or {}
    local id=a.ItemId or a.ItemID or a.UID or a.Uid or a.BagId or a.BagID or a.EggId or a.EggID
        or a.PetId or a.PetID or a.ToolId or a.ToolID or a.WeaponId or a.WeaponID or a.GearId or a.GearID
        or a.GemName or a.AssetCategory
    return table.concat({tostring(s.source),tostring(s.class),tostring(s.name),tostring(id or "")},"|")
end

local function addItem(obj,source)
    if not obj or not itemLike(obj) then return end
    local s=snap(obj,source); local key=itemKey(s); local old=S.items[key]
    if old then old.count=(old.count or 1)+1; old.lastPath=s.path; old.lastSeen=os.time(); return old end
    if S.itemCount>=CFG.MAX_ITEMS then return end
    S.itemCount+=1; S.counters.items=S.itemCount; s.count=1; s.firstSeen=os.time(); s.lastSeen=s.firstSeen; S.items[key]=s
    return s
end

local function addRemote(r)
    if not remoteLike(r) then return end
    local p=pathOf(r); if S.remoteSeen[p] or #S.remotes>=CFG.MAX_REMOTES then return end
    S.remoteSeen[p]=true; S.remotes[#S.remotes+1]={name=r.Name,class=r.ClassName,path=p}; S.counters.remotes=#S.remotes
end

local function attachRemote(r)
    if not remoteLike(r) or S.incomingSeen[r] then return end
    addRemote(r)
    if r.ClassName~="RemoteEvent" and r.ClassName~="UnreliableRemoteEvent" then return end
    S.incomingSeen[r]=true
    connect(r.OnClientEvent,function(...)
        if not S.running then return end
        S.counters.incoming+=1
        rec(pathOf(r):find("ProfileMirror/ProfileDelta",1,true) and "profile_delta" or "incoming_remote",{
            remote={name=r.Name,class=r.ClassName,path=pathOf(r)},args=argsSafe(...)
        })
    end)
end

local function scan(root,source)
    local list=root:GetDescendants(); local lim=math.min(#list,CFG.MAX_SCAN)
    for i=1,lim do
        if not S.running then return end
        local o=list[i]
        if remoteLike(o) then attachRemote(o) elseif itemLike(o) then addItem(o,source) end
        if i%300==0 then task.wait() end
    end
end

local function watchInventory(container,label)
    if not container then return end
    for _,o in ipairs(container:GetChildren()) do if o:IsA("Tool") or inInventory(o) then addItem(o,label..":initial") end end
    connect(container.ChildAdded,function(o)
        if not S.running or (label=="Character" and not o:IsA("Tool")) then return end
        S.counters.added+=1; local x=addItem(o,label..":added") or snap(o,label..":added")
        rec("inventory_added",{container=label,item=x})
    end)
    connect(container.ChildRemoved,function(o)
        if not S.running or (label=="Character" and not o:IsA("Tool")) then return end
        S.counters.removed+=1; rec("inventory_removed",{container=label,item=snap(o,label..":removed")})
    end)
end

local function installWatchers()
    local bp=LP:FindFirstChildOfClass("Backpack") or LP:WaitForChild("Backpack",5)
    watchInventory(bp,"Backpack"); watchInventory(LP.Character,"Character")
    connect(LP.CharacterAdded,function(c) task.wait(.15); if S.running then watchInventory(c,"Character") end end)
    connect(LP.DescendantAdded,function(o) if S.running and itemLike(o) then addItem(o,"Player:added") end end)
    connect(WS.DescendantAdded,function(o)
        if S.running and (o:IsA("Tool") or importantAttr(o) or hasWord(o.Name,ITEM_WORDS)) and itemLike(o) then
            addItem(o,"Workspace:added"); rec("world_item_added",{item=snap(o,"Workspace")})
        end
    end)
    connect(RS.DescendantAdded,function(o)
        if S.running then if remoteLike(o) then attachRemote(o) elseif itemLike(o) then addItem(o,"ReplicatedStorage:added") end end
    end)
    connect(PPS.PromptTriggered,function(p,player)
        if not S.running or (player and player~=LP) then return end
        local text=norm((p.ActionText or "").." "..(p.ObjectText or ""))
        if not (text:find("pick",1,true) or text:find("collect",1,true) or text:find("take",1,true) or text:find("grab",1,true) or text:find("steal",1,true) or text:find("loot",1,true) or hasWord(text,ITEM_WORDS)) then return end
        S.counters.prompts+=1; local root=p.Parent
        for _=1,4 do if not root or root==WS then break end; if itemLike(root) then break end; root=root.Parent end
        if root and root~=WS then addItem(root,"Prompt") end
        rec("pickup_prompt",{prompt={path=pathOf(p),action=p.ActionText,object=p.ObjectText,hold=p.HoldDuration},candidate=root and root~=WS and snap(root,"Prompt") or nil})
    end)
end

local function installOutgoingHook()
    local H=rawget(ENV,"__CAFEINA_INVITEM_HOOK")
    local function observe(r,method,args,result)
        if not S.running or not remoteLike(r) then return end
        S.counters.outgoing+=1; addRemote(r)
        rec("outgoing_remote",{method=method,remote={name=r.Name,class=r.ClassName,path=pathOf(r)},args=safe(args),result=result and safe(result) or nil})
    end
    if type(H)=="table" and H.installed then H.observer=observe; return true,"reused" end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return false,"hook unavailable" end
    H={observer=observe,installed=false}; local old
    local function handler(self,...)
        local method=getnamecallmethod(); local rel=typeof(self)=="Instance" and remoteLike(self)
        if method=="InvokeServer" and rel then
            local a=table.pack(...); local r=table.pack(old(self,...)); local cb=H.observer
            if cb then task.defer(cb,self,method,a,r) end
            return table.unpack(r,1,r.n)
        elseif method=="FireServer" and rel then
            local a=table.pack(...); local ret=old(self,...); local cb=H.observer
            if cb then task.defer(cb,self,method,a,nil) end
            return ret
        end
        return old(self,...)
    end
    local wrapped=type(newcclosure)=="function" and newcclosure(handler) or handler
    local ok,err=pcall(function() old=hookmetamethod(game,"__namecall",wrapped) end)
    if not ok or type(old)~="function" then return false,tostring(err) end
    H.installed=true; H.old=old; ENV.__CAFEINA_INVITEM_HOOK=H; return true,"installed"
end

local function health()
    S.health={checked=true,ok=false}
    if not REQUEST then S.health.error="no request"; return false end
    local ok,res=pcall(REQUEST,{Url=CFG.HEALTH,Method="GET",Headers={Accept="application/json"}})
    if not ok then S.health.error=tostring(res); return false end
    local body=res.Body or res.body or ""; local d; pcall(function() d=Http:JSONDecode(body) end)
    S.health.status=tonumber(res.StatusCode or res.Status or 0) or 0
    if type(d)=="table" then
        S.health.ok=d.ok==true; S.health.githubMirrorConfigured=d.githubMirrorConfigured==true
        S.health.maxRecords=d.maxRecords; S.health.maxRemotes=d.maxRemotes
    else S.health.ok=S.health.status>=200 and S.health.status<300 end
    return S.health.ok
end

local function itemArray()
    local out={}; for _,v in pairs(S.items) do out[#out+1]=v end
    table.sort(out,function(a,b) return tostring(a.name)<tostring(b.name) end); return out
end

local function payload()
    local trace={version=CFG.VERSION,captureType="inventory_item_catalog",runId=S.runId,startedUnix=S.started,finishedUnix=os.time(),records=S.records,remotes=S.remotes,catalog=itemArray(),counters=S.counters,health=S.health,passive=true}
    local body={schemaVersion=1,userId=tostring(LP.UserId),username=LP.Name,capturedAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),placeId=game.PlaceId,gameId=game.GameId,runId=S.runId,trace=trace}
    local text=Http:JSONEncode(body)
    while #text>CFG.MAX_JSON and #trace.records>100 do
        local n=math.max(1,math.floor(#trace.records*.15)); for _=1,n do table.remove(trace.records,1) end
        trace.counters.trimmedForUpload=(trace.counters.trimmedForUpload or 0)+n; text=Http:JSONEncode(body)
    end
    return text
end

local function upload()
    if S.sending then return end; S.sending=true; status("PREPARANDO UPLOAD...")
    local text=payload()
    if type(writefile)=="function" then pcall(writefile,string.format("Cafeina_InventoryItems_%s_%s.json",game.PlaceId,os.time()),text) end
    if not REQUEST then S.sending=false; status("SEM REQUEST • backup local preservado"); return end
    local last
    for i=1,CFG.RETRIES do
        status(string.format("ENVIANDO %d KB • %d/%d",math.floor(#text/1024),i,CFG.RETRIES))
        local ok,res=pcall(REQUEST,{Url=CFG.ENDPOINT,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json"},Body=text})
        if ok then
            local code=tonumber(res.StatusCode or res.Status or 0) or 0; local d; pcall(function() d=Http:JSONDecode(res.Body or res.body or "") end)
            if code>=200 and code<300 and type(d)=="table" and d.ok==true then
                local mirrored=type(d.github)=="table" and d.github.mirrored==true
                S.upload={ok=true,githubMirrored=mirrored,file=d.file,traceId=d.traceId,runId=d.runId}; S.sending=false
                status(mirrored and "ENVIADO + GITHUB MIRROR ✓" or "SERVIDOR OK • GitHub mirror nao confirmou")
                return
            end
            last="HTTP "..tostring(code)
        else last=tostring(res) end
        task.wait(i*1.2)
    end
    S.upload={ok=false,error=last}; S.sending=false; status("UPLOAD FALHOU • backup local preservado")
end

local function reset()
    disconnectAll(); S.records={}; S.items={}; S.itemCount=0; S.remotes={}; S.remoteSeen={}; S.incomingSeen=setmetatable({},{__mode="k"})
    for k in pairs(S.counters) do S.counters[k]=0 end
    S.runId=string.format("INVITEM_%s_%s_%s",game.PlaceId,LP.UserId,os.time()); S.started=os.time(); S.health={}; S.upload={}
end

local function start()
    if S.running or S.sending then return end; reset(); S.running=true; status("INICIANDO...")
    task.spawn(function()
        health(); installWatchers(); local hok,hinfo=installOutgoingHook()
        rec("scanner_started",{hook={ok=hok,info=hinfo},health=S.health,placeId=game.PlaceId,gameId=game.GameId})
        status("MAPEANDO PLAYER..."); scan(LP,"Player"); if not S.running then return end
        status("MAPEANDO STARTERPACK..."); scan(StarterPack,"StarterPack"); if not S.running then return end
        status("MAPEANDO REPLICATEDSTORAGE..."); scan(RS,"ReplicatedStorage"); if not S.running then return end
        status("MAPEANDO WORKSPACE..."); scan(WS,"Workspace"); if not S.running then return end
        status("COLETANDO • pegue/use/equipe itens normalmente")
    end)
end

local function stop()
    if not S.running or S.sending then return end
    rec("scanner_stopping",{counters=safe(S.counters)}); S.running=false; disconnectAll()
    local H=rawget(ENV,"__CAFEINA_INVITEM_HOOK"); if type(H)=="table" then H.observer=nil end
    task.spawn(upload)
end

pcall(function() local old=rawget(ENV,"__CAFEINA_INVITEM_GUI"); if typeof(old)=="Instance" then old:Destroy() end end)
local parent; pcall(function() if gethui then parent=gethui() end end); if not parent then parent=CoreGui end
local gui=Instance.new("ScreenGui"); gui.Name="CafeinaInventoryItemScanner"; gui.ResetOnSpawn=false
local parentOK=pcall(function() gui.Parent=parent end); if not parentOK then gui.Parent=LP:WaitForChild("PlayerGui") end
ENV.__CAFEINA_INVITEM_GUI=gui

local frame=Instance.new("Frame"); frame.Size=UDim2.fromOffset(310,176); frame.Position=UDim2.new(0,12,.5,-88); frame.BackgroundColor3=Color3.fromRGB(15,15,18); frame.BorderSizePixel=0; frame.Active=true; frame.Parent=gui; Instance.new("UICorner",frame).CornerRadius=UDim.new(0,11)
local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-20,0,26); title.Position=UDim2.fromOffset(10,7); title.BackgroundTransparency=1; title.Text="CAFEINA • INVENTORY SCANNER"; title.TextColor3=Color3.fromRGB(245,245,248); title.Font=Enum.Font.GothamBold; title.TextSize=12; title.TextXAlignment=Enum.TextXAlignment.Left; title.Active=true; title.Parent=frame
local st=Instance.new("TextLabel"); st.Size=UDim2.new(1,-20,0,42); st.Position=UDim2.fromOffset(10,35); st.BackgroundTransparency=1; st.TextWrapped=true; st.TextColor3=Color3.fromRGB(185,185,195); st.Font=Enum.Font.Gotham; st.TextSize=10; st.TextXAlignment=Enum.TextXAlignment.Left; st.TextYAlignment=Enum.TextYAlignment.Top; st.Parent=frame
local ct=Instance.new("TextLabel"); ct.Size=UDim2.new(1,-20,0,24); ct.Position=UDim2.fromOffset(10,80); ct.BackgroundTransparency=1; ct.TextColor3=Color3.fromRGB(160,160,170); ct.Font=Enum.Font.Code; ct.TextSize=10; ct.TextXAlignment=Enum.TextXAlignment.Left; ct.Parent=frame
local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,-20,0,52); btn.Position=UDim2.fromOffset(10,112); btn.BackgroundColor3=Color3.fromRGB(105,26,31); btn.BorderSizePixel=0; btn.TextColor3=Color3.new(1,1,1); btn.Font=Enum.Font.GothamBold; btn.TextSize=11; btn.Text="INICIAR COLETA"; btn.Parent=frame; Instance.new("UICorner",btn).CornerRadius=UDim.new(0,9)
btn.MouseButton1Click:Connect(function() if not S.sending then if S.running then stop() else start() end end end)

local dragging,dragStart,startPos=false,nil,nil
title.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end end)
title.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
UIS.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-dragStart; frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)

task.spawn(function()
    while gui.Parent do
        st.Text=S.status; ct.Text=string.format("itens:%d  eventos:%d  remotes:%d",S.counters.items or 0,S.counters.records or 0,S.counters.remotes or 0)
        btn.Text=S.sending and "ENVIANDO AUTOMATICAMENTE..." or (S.running and "ENCERRAR + ENVIAR AO GITHUB" or "INICIAR COLETA")
        task.wait(.1)
    end
end)

ENV.__CAFEINA_INVITEM_RUNTIME={
    Cleanup=function()
        S.running=false; disconnectAll()
        local H=rawget(ENV,"__CAFEINA_INVITEM_HOOK"); if type(H)=="table" then H.observer=nil end
        local g=rawget(ENV,"__CAFEINA_INVITEM_GUI"); if typeof(g)=="Instance" then pcall(function() g:Destroy() end) end
    end
}

print("[CAFEINA] Inventory Item Scanner V1.1 carregado")
