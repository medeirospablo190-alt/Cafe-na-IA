--==============================================================--
-- CAFEINA • INVENTORY REMOTE TRACE V1
-- EXECUTOR ONLY • MOBILE
-- Captures inventory/item-related remotes and uploads to CAFEINA server.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
if not LP then return end

local CONFIG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V1",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    CAPTURE_WINDOW = 4,
    MAX_RECORDS = 5000,
    POST_STATE_DELAY = 0.20,
    UPLOAD_CHUNK_BYTES = 600000,
    TERMS = {
        "laser grid", "item", "items", "inventory", "storage",
        "getitem", "get_item", "take", "withdraw", "claim",
        "pickup", "collect", "reward", "redeem", "search_option",
        "item_amount", "backpack", "loot"
    }
}

local ENV = (getgenv and getgenv()) or _G

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synRequest, httpRequest
pcall(function() if syn and type(syn.request)=="function" then synRequest=syn.request end end)
pcall(function() if http and type(http.request)=="function" then httpRequest=http.request end end)

local REQUEST = pick(rawget(ENV,"request"), rawget(ENV,"http_request"), httpRequest, synRequest)
local WRITEFILE = pick(rawget(ENV,"writefile"))
local SETCLIPBOARD = pick(rawget(ENV,"setclipboard"))

local old = rawget(ENV, "__CAFEINA_INVENTORY_TRACE")
if type(old)=="table" and type(old.Stop)=="function" then pcall(old.Stop) end

local State = {
    Running = true,
    Records = {},
    TargetRemotes = {},
    IncomingConnections = {},
    CaptureUntil = 0,
    Sequence = 0,
    Pending = 0,
    StartedAt = os.time(),
    RunId = HttpService:GenerateGUID(false),
    Uploading = false,
}

local function lower(v) return string.lower(tostring(v or "")) end

local function fullPath(obj)
    local ok, v = pcall(function() return obj:GetFullName() end)
    return ok and v or tostring(obj)
end

local function safeSerialize(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then return "<max_depth>" end
    local t = typeof(v)
    if v == nil then return nil end
    if t=="string" or t=="boolean" then return v end
    if t=="number" then
        if v~=v then return "<nan>" end
        if v==math.huge then return "<inf>" end
        if v==-math.huge then return "<-inf>" end
        return v
    end
    if t=="Instance" then return {type="Instance",name=v.Name,class=v.ClassName,path=fullPath(v)} end
    if t=="Vector3" then return {type="Vector3",x=v.X,y=v.Y,z=v.Z} end
    if t=="Vector2" then return {type="Vector2",x=v.X,y=v.Y} end
    if t=="CFrame" then local p=v.Position return {type="CFrame",x=p.X,y=p.Y,z=p.Z} end
    if t=="table" then
        if seen[v] then return "<cycle>" end
        seen[v]=true
        local out, count = {}, 0
        for k,val in pairs(v) do
            count += 1
            if count > 80 then out["<truncated>"]=true break end
            out[tostring(k)] = safeSerialize(val, depth+1, seen)
        end
        seen[v]=nil
        return out
    end
    return tostring(v)
end

local function flatten(v, out, depth)
    out = out or {}
    depth = depth or 0
    if depth > 4 then return out end
    local t = typeof(v)
    if t=="string" or t=="number" or t=="boolean" then
        table.insert(out, lower(v))
    elseif t=="Instance" then
        table.insert(out, lower(v.Name.." "..fullPath(v)))
    elseif t=="table" then
        for k,val in pairs(v) do flatten(k,out,depth+1); flatten(val,out,depth+1) end
    end
    return out
end

local function argsText(args)
    local out={}
    for i=1,args.n do flatten(args[i],out,0) end
    return table.concat(out," ")
end

local function toolList(container)
    local out={}
    if not container then return out end
    for _,obj in ipairs(container:GetChildren()) do
        if obj:IsA("Tool") then table.insert(out,obj.Name) end
    end
    table.sort(out)
    return out
end

local function relevantAttrs(inst)
    if not inst then return {} end
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if not ok then return {} end
    local out={}
    for k,v in pairs(attrs) do
        local s=lower(k)
        if s:find("item",1,true) or s:find("weapon",1,true) or s:find("inventory",1,true)
            or s:find("equip",1,true) or s:find("selected",1,true) or s:find("current",1,true) then
            out[k]=safeSerialize(v)
        end
    end
    return out
end

local function snapshot()
    local char=LP.Character
    local backpack=LP:FindFirstChildOfClass("Backpack")
    local equipped
    if char then
        local tool=char:FindFirstChildOfClass("Tool")
        if tool then equipped=tool.Name end
    end
    return {
        clock=os.clock(),
        equipped=equipped,
        backpackTools=toolList(backpack),
        characterTools=toolList(char),
        playerAttributes=relevantAttrs(LP),
        characterAttributes=relevantAttrs(char),
    }
end

local statusChanged
local function addRecord(r)
    if not State.Running or #State.Records>=CONFIG.MAX_RECORDS then return end
    State.Sequence += 1
    r.seq=State.Sequence
    r.clock=os.clock()
    r.unix=os.time()
    table.insert(State.Records,r)
    if statusChanged then statusChanged() end
end

local function attachIncoming(remote)
    if State.IncomingConnections[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
    local ok,conn=pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            if not State.Running then return end
            addRecord({
                kind="remote_incoming",
                remote=fullPath(remote),
                class=remote.ClassName,
                arguments=safeSerialize(table.pack(...)),
                state=snapshot(),
            })
        end)
    end)
    if ok and conn then State.IncomingConnections[remote]=conn end
end

local function markRemote(remote,reason)
    if State.TargetRemotes[remote] then return end
    State.TargetRemotes[remote]={path=fullPath(remote),class=remote.ClassName,reason=reason,discoveredAt=os.clock()}
    attachIncoming(remote)
    addRecord({kind="remote_discovered",remote=fullPath(remote),class=remote.ClassName,reason=reason})
end

local function matches(remote,args)
    if State.TargetRemotes[remote] then return true,"known_remote" end
    if os.clock() <= State.CaptureUntil then return true,"capture_window" end
    local text=lower(fullPath(remote)).." "..argsText(args)
    for _,term in ipairs(CONFIG.TERMS) do
        if text:find(lower(term),1,true) then return true,"keyword:"..term end
    end
    return false
end

local function schedulePostState(callId,remote)
    State.Pending += 1
    task.delay(CONFIG.POST_STATE_DELAY,function()
        if State.Running then
            addRecord({kind="post_remote_state",callId=callId,remote=fullPath(remote),state=snapshot()})
        end
        State.Pending=math.max(0,State.Pending-1)
    end)
end

local hookAvailable = type(hookmetamethod)=="function" and type(getnamecallmethod)=="function"
if hookAvailable then
    local wrap = type(newcclosure)=="function" and newcclosure or function(f)return f end
    local oldNamecall
    oldNamecall=hookmetamethod(game,"__namecall",wrap(function(self,...)
        local method=getnamecallmethod()
        local remoteCall=(method=="FireServer" or method=="InvokeServer")
        local isRemote=typeof(self)=="Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent"))
        if State.Running and remoteCall and isRemote then
            local args=table.pack(...)
            local okMatch,reason=matches(self,args)
            if okMatch then
                markRemote(self,reason)
                local callId=State.RunId..":"..tostring(State.Sequence+1)
                local before=snapshot()
                if method=="InvokeServer" then
                    local started=os.clock()
                    local returned=table.pack(oldNamecall(self,...))
                    addRecord({
                        kind="remote_outgoing",callId=callId,remote=fullPath(self),class=self.ClassName,
                        method=method,reason=reason,arguments=safeSerialize(args),before=before,
                        response=safeSerialize(returned),elapsed=os.clock()-started,after=snapshot(),
                    })
                    return table.unpack(returned,1,returned.n)
                else
                    addRecord({kind="remote_outgoing",callId=callId,remote=fullPath(self),class=self.ClassName,method=method,reason=reason,arguments=safeSerialize(args),before=before})
                    local returned=table.pack(oldNamecall(self,...))
                    schedulePostState(callId,self)
                    return table.unpack(returned,1,returned.n)
                end
            end
        end
        return oldNamecall(self,...)
    end))
else
    warn("[CAFEINA TRACE] executor sem hookmetamethod/getnamecallmethod")
end

task.spawn(function()
    for _,obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent") then
            local path=lower(fullPath(obj))
            for _,term in ipairs(CONFIG.TERMS) do
                if path:find(lower(term),1,true) then markRemote(obj,"remote_name:"..term) break end
            end
        end
    end
end)

local function postJson(url,payload)
    if not REQUEST then return false,nil,"request/http_request indisponivel" end
    local okBody,body=pcall(function() return HttpService:JSONEncode(payload) end)
    if not okBody then return false,nil,tostring(body) end
    local ok,res=pcall(function()
        return REQUEST({Url=url,Method="POST",Headers={["Content-Type"]="application/json",["Accept"]="application/json"},Body=body})
    end)
    if not ok then return false,nil,tostring(res) end
    local status=tonumber(res.StatusCode or res.Status or res.status) or 0
    local rb=res.Body or res.body or ""
    local decoded
    if rb~="" then pcall(function() decoded=HttpService:JSONDecode(rb) end) end
    if status<200 or status>=300 then return false,decoded,"HTTP "..status..": "..rb end
    return true,decoded,nil
end

local function buildReport()
    local remotes={}
    for _,d in pairs(State.TargetRemotes) do
        table.insert(remotes,{path=d.path,class=d.class,reason=d.reason,discoveredAt=d.discoveredAt})
    end
    table.sort(remotes,function(a,b)return a.path<b.path end)
    return {
        kind="inventory_remote_trace",version=CONFIG.VERSION,runId=State.RunId,
        placeId=game.PlaceId,gameId=game.GameId,startedAt=State.StartedAt,finishedAt=os.time(),
        targetTerms=CONFIG.TERMS,remotes=remotes,records=State.Records,
    }
end

local function saveBackup(report)
    local json=HttpService:JSONEncode(report)
    local filename="Cafeina_InventoryRemoteTrace_"..game.PlaceId.."_"..os.time()..".json"
    if WRITEFILE then pcall(function() WRITEFILE(filename,json) end) end
    return filename,json
end

local function makeChunks(objects)
    local chunks,current,currentBytes={}, {}, 2
    for _,obj in ipairs(objects) do
        local enc=HttpService:JSONEncode(obj)
        local size=#enc+1
        if #current>0 and currentBytes+size>CONFIG.UPLOAD_CHUNK_BYTES then
            table.insert(chunks,current); current={}; currentBytes=2
        end
        table.insert(current,obj); currentBytes += size
    end
    if #current>0 then table.insert(chunks,current) end
    return chunks
end

local function uploadReport(report)
    if State.Uploading then return false,"upload em andamento" end
    State.Uploading=true
    local filename="Cafeina_InventoryRemoteTrace_"..game.PlaceId.."_"..os.time()..".json"
    local reportJson=HttpService:JSONEncode(report)
    local okStart,startData,startErr=postJson(CONFIG.UPLOAD_BASE.."/start",{
        filename=filename,source=CONFIG.VERSION,
        metadata={type="inventory_remote_trace",runId=State.RunId,placeId=game.PlaceId,gameId=game.GameId,records=#State.Records}
    })
    if not okStart then State.Uploading=false return false,"START: "..tostring(startErr) end
    local uploadId=type(startData)=="table" and (startData.uploadId or startData.id or startData.upload_id)
    if not uploadId then State.Uploading=false return false,"/start sem uploadId" end
    local objects={{kind="inventory_remote_trace_header",version=report.version,runId=report.runId,placeId=report.placeId,gameId=report.gameId,startedAt=report.startedAt,finishedAt=report.finishedAt,targetTerms=report.targetTerms,remotes=report.remotes}}
    for _,r in ipairs(report.records) do table.insert(objects,r) end
    local chunks=makeChunks(objects)
    for i,chunk in ipairs(chunks) do
        if statusChanged then statusChanged("UPLOAD "..i.."/"..#chunks) end
        local okChunk,_,chunkErr=postJson(CONFIG.UPLOAD_BASE.."/chunk",{uploadId=uploadId,index=i,objects=chunk})
        if not okChunk then
            pcall(function() postJson(CONFIG.UPLOAD_BASE.."/cancel",{uploadId=uploadId}) end)
            State.Uploading=false
            return false,"CHUNK "..i..": "..tostring(chunkErr)
        end
    end
    local okFinish,finishData,finishErr=postJson(CONFIG.UPLOAD_BASE.."/finish",{
        uploadId=uploadId,totalChunks=#chunks,totalBytes=#reportJson,records=#objects
    })
    State.Uploading=false
    if not okFinish then return false,"FINISH: "..tostring(finishErr) end
    return true,{uploadId=uploadId,finish=finishData,filename=filename}
end

-- GUI
local parent=CoreGui
pcall(function() if gethui then parent=gethui() end end)
pcall(function() local x=parent:FindFirstChild("CafeinaInventoryTraceGui") if x then x:Destroy() end end)

local gui=Instance.new("ScreenGui")
gui.Name="CafeinaInventoryTraceGui"
gui.ResetOnSpawn=false
gui.Parent=parent

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(285,175)
frame.Position=UDim2.new(0.5,-142,0.55,-87)
frame.BackgroundColor3=Color3.fromRGB(16,16,19)
frame.BorderSizePixel=0
frame.Active=true
frame.Draggable=true
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-16,0,27)
title.Position=UDim2.fromOffset(8,6)
title.BackgroundTransparency=1
title.Text="CAFEINA • INVENTORY TRACE"
title.TextColor3=Color3.new(1,1,1)
title.Font=Enum.Font.GothamBold
title.TextSize=14
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local status=Instance.new("TextLabel")
status.Size=UDim2.new(1,-16,0,42)
status.Position=UDim2.fromOffset(8,36)
status.BackgroundTransparency=1
status.Text="COLETANDO..."
status.TextWrapped=true
status.TextColor3=Color3.fromRGB(205,205,205)
status.Font=Enum.Font.Gotham
status.TextSize=12
status.TextXAlignment=Enum.TextXAlignment.Left
status.Parent=frame

local function makeButton(text,y,color)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-16,0,37)
    b.Position=UDim2.fromOffset(8,y)
    b.BackgroundColor3=color or Color3.fromRGB(42,42,47)
    b.BorderSizePixel=0
    b.Text=text
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=12
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    return b
end

local captureButton=makeButton("CAPTURAR PROXIMA ACAO • 4s",85)
local stopButton=makeButton("ENCERRAR + ENVIAR",129,Color3.fromRGB(110,25,25))

statusChanged=function(custom)
    if custom then
        status.Text=tostring(custom).."\n"..#State.Records.." registros"
        return
    end
    local targets=0
    for _ in pairs(State.TargetRemotes) do targets += 1 end
    status.Text="COLETANDO • "..#State.Records.." registros\n"..targets.." remotes identificados"
end
statusChanged()

captureButton.MouseButton1Click:Connect(function()
    State.CaptureUntil=os.clock()+CONFIG.CAPTURE_WINDOW
    captureButton.Text="FACA A ACAO AGORA..."
    task.delay(CONFIG.CAPTURE_WINDOW,function()
        if State.Running then captureButton.Text="CAPTURAR PROXIMA ACAO • 4s" statusChanged() end
    end)
end)

local function stopAndUpload()
    if not State.Running then return end
    stopButton.Text="FINALIZANDO..."
    status.Text="Aguardando eventos pendentes..."
    local deadline=os.clock()+2
    while State.Pending>0 and os.clock()<deadline do task.wait(0.05) end
    State.Running=false
    for _,conn in pairs(State.IncomingConnections) do pcall(function() conn:Disconnect() end) end
    local report=buildReport()
    local backup=saveBackup(report)
    status.Text="Backup salvo.\nEnviando..."
    local ok,result=uploadReport(report)
    if ok then
        local uploadId=result.uploadId
        status.Text="ENVIADO ✓\nID: "..tostring(uploadId)
        stopButton.Text="UPLOAD CONCLUIDO"
        print("[CAFEINA TRACE] uploadId:",uploadId)
        print("[CAFEINA TRACE] backup:",backup)
        local finish=result.finish
        local publicLink=type(finish)=="table" and (finish.url or finish.link or finish.downloadUrl or finish.publicUrl)
        if publicLink then
            print("[CAFEINA TRACE] link:",publicLink)
            if SETCLIPBOARD then pcall(SETCLIPBOARD,publicLink) end
        elseif SETCLIPBOARD then
            pcall(SETCLIPBOARD,tostring(uploadId))
        end
    else
        status.Text="FALHA NO UPLOAD\n"..tostring(result)
        stopButton.Text="ARQUIVO PRESERVADO"
        warn("[CAFEINA TRACE]",result)
        warn("[CAFEINA TRACE] backup:",backup)
    end
end

stopButton.MouseButton1Click:Connect(function() task.spawn(stopAndUpload) end)

ENV.__CAFEINA_INVENTORY_TRACE={
    State=State,
    CaptureNext=function(seconds) State.CaptureUntil=os.clock()+(tonumber(seconds) or CONFIG.CAPTURE_WINDOW) end,
    Stop=function() State.Running=false end,
    Finish=stopAndUpload,
    GetRecords=function() return State.Records end,
    GetRemotes=function() return State.TargetRemotes end,
}

print("==============================================")
print("CAFEINA INVENTORY REMOTE TRACE")
print("PlaceId:",game.PlaceId)
print("RunId:",State.RunId)
print("Coleta iniciada automaticamente.")
print("==============================================")
