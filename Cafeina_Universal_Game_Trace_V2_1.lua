--==============================================================--
-- CAFEINA • UNIVERSAL GAME TRACE V2.1
-- Universal passive mapper. No game-specific keyword filters.
-- Catalogs client-visible remotes, inbound events, prompts, values,
-- tags, inventory, GUI, nearby world structure and movement.
-- Upload only succeeds after Render AND GitHub mirror confirmation.
--==============================================================--

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local UserInputService=game:GetService("UserInputService")
local CoreGui=game:GetService("CoreGui")

local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV=(getgenv and getgenv()) or _G

local C={
 VERSION="CAFEINA_UNIVERSAL_GAME_TRACE_V2_1",
 PURPOSE="universal_game_mapping",
 ENDPOINT="https://cafe-na-ia.onrender.com/api/inventory-trace",
 HEALTH="https://cafe-na-ia.onrender.com/api/inventory-trace/health",
 MAX_RECORDS=12000, MAX_REMOTES=1200, MAX_INBOUND=1000, MAX_VALUES=650,
 MAX_STRING=1000, MAX_TABLE=45, MAX_DEPTH=4,
 STRUCTURE_MAX=3600, NEARBY_RADIUS=150, NEARBY_MAX=1000, GUI_MAX=700,
 TRAJECTORY_INTERVAL=.5, RECORDS_PER_BATCH=800, REMOTES_PER_BATCH=500,
 MAX_BATCHES=22, RETRIES=4, RETRY_BASE=.8,
 CACHE_SUFFIX="CafeinaUniversalTraceV21_pending.json",
}

local function pick(...)
 for i=1,select("#",...) do local v=select(i,...); if type(v)=="function" then return v end end
end

local synReq,httpReq
pcall(function() if syn and type(syn.request)=="function" then synReq=syn.request end end)
pcall(function() if http and type(http.request)=="function" then httpReq=http.request end end)
local REQUEST=pick(rawget(ENV,"request"),rawget(ENV,"http_request"),request,http_request,httpReq,synReq)
local WRITEFILE=pick(rawget(ENV,"writefile"),writefile)
local READFILE=pick(rawget(ENV,"readfile"),readfile)
local ISFILE=pick(rawget(ENV,"isfile"),isfile)
local DELFILE=pick(rawget(ENV,"delfile"),delfile)

local function pathOf(x)
 if typeof(x)~="Instance" then return tostring(x) end
 local ok,v=pcall(function() return x:GetFullName() end)
 return ok and v or (x.ClassName..":"..x.Name)
end

local function ser(v,d,seen)
 d=d or 0; seen=seen or {}
 if d>C.MAX_DEPTH then return "<max_depth>" end
 local t=typeof(v)
 if v==nil or t=="boolean" then return v end
 if t=="number" then
  if v~=v then return "<nan>" elseif v==math.huge then return "<inf>" elseif v==-math.huge then return "<-inf>" end
  return v
 end
 if t=="string" then return #v>C.MAX_STRING and (string.sub(v,1,C.MAX_STRING).."...[truncated]") or v end
 if t=="Vector2" then return {type="Vector2",x=v.X,y=v.Y} end
 if t=="Vector3" then return {type="Vector3",x=v.X,y=v.Y,z=v.Z} end
 if t=="CFrame" then local p=v.Position; local rx,ry,rz=v:ToOrientation(); return {type="CFrame",x=p.X,y=p.Y,z=p.Z,rx=rx,ry=ry,rz=rz} end
 if t=="Color3" then return {type="Color3",r=v.R,g=v.G,b=v.B} end
 if t=="UDim2" then return {type="UDim2",xs=v.X.Scale,xo=v.X.Offset,ys=v.Y.Scale,yo=v.Y.Offset} end
 if t=="EnumItem" then return tostring(v) end
 if t=="Instance" then return {type="Instance",name=v.Name,className=v.ClassName,path=pathOf(v)} end
 if t=="table" then
  if seen[v] then return "<cycle>" end
  seen[v]=true; local out,n={},0
  for k,item in pairs(v) do n=n+1; if n>C.MAX_TABLE then out["<truncated>"]=true; break end; out[tostring(k)]=ser(item,d+1,seen) end
  seen[v]=nil; return out
 end
 return tostring(v)
end

local function attrs(inst)
 local ok,t=pcall(function() return inst:GetAttributes() end)
 return ok and ser(t) or {}
end

local function packed(args)
 local n=tonumber(args and args.n) or 0; local out={count=n,values={}}; local lim=math.min(n,24)
 for i=1,lim do out.values[i]=ser(args[i]) end
 if n>lim then out.truncated=n-lim end
 return out
end

local S={running=false,stopping=false,uploading=false,runId=nil,startClock=0,startIso=nil,
 records={},remotes={},remoteSeen={},conns={},inbound=setmetatable({},{__mode="k"}),values=setmetatable({},{__mode="k"}),
 inboundCount=0,valueCount=0,dropped=0,staticDone=false,lastTrajectory=0,pending=nil}

local function iso() local ok,v=pcall(function() return DateTime.now():ToIsoDate() end); return ok and v or tostring(os.time()) end
local function rec(kind,data)
 if not S.running or S.stopping then return end
 if #S.records>=C.MAX_RECORDS then S.dropped=S.dropped+1; return end
 data=data or {}; data.seq=#S.records+1; data.kind=kind; data.clock=os.clock()-S.startClock; data.unix=os.time(); data.runId=S.runId
 S.records[#S.records+1]=data
end

local function playerSnap()
 local ch=LP.Character; local o={userId=LP.UserId,username=LP.Name,displayName=LP.DisplayName,character=ch~=nil}
 if not ch then return o end
 local root=ch:FindFirstChild("HumanoidRootPart"); local hum=ch:FindFirstChildOfClass("Humanoid")
 if root then o.position=ser(root.Position); o.cframe=ser(root.CFrame); o.velocity=ser(root.AssemblyLinearVelocity); o.angularVelocity=ser(root.AssemblyAngularVelocity) end
 if hum then o.health=hum.Health; o.maxHealth=hum.MaxHealth; o.walkSpeed=hum.WalkSpeed; o.jumpPower=hum.JumpPower; o.state=tostring(hum:GetState()); o.floor=tostring(hum.FloorMaterial); o.moveDirection=ser(hum.MoveDirection) end
 return o
end

local function isRemote(x) return x:IsA("RemoteEvent") or x:IsA("RemoteFunction") or x:IsA("UnreliableRemoteEvent") end
local function remoteDesc(r) return {path=pathOf(r),name=r.Name,className=r.ClassName,parent=r.Parent and pathOf(r.Parent) or nil,attributes=attrs(r)} end
local function registerRemote(r,source)
 if not isRemote(r) then return end
 local p=pathOf(r); if S.remoteSeen[p] then return end; S.remoteSeen[p]=true
 if #S.remotes<C.MAX_REMOTES then local d=remoteDesc(r); d.source=source; S.remotes[#S.remotes+1]=d end
end

local function attachInbound(r)
 if S.inbound[r] or S.inboundCount>=C.MAX_INBOUND then return end
 if not (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then return end
 S.inbound[r]=true; S.inboundCount=S.inboundCount+1; registerRemote(r,"inbound")
 local c=r.OnClientEvent:Connect(function(...)
  if not S.running or S.stopping then return end
  local a=table.pack(...)
  task.defer(function() pcall(function() if S.running and not S.stopping then rec("remote_inbound",{remote=remoteDesc(r),payload=packed(a),player=playerSnap()}) end end) end)
 end)
 S.conns[#S.conns+1]=c
end

local function valueSnap(v)
 local o={path=pathOf(v),name=v.Name,className=v.ClassName,attributes=attrs(v)}; pcall(function() o.value=ser(v.Value) end); return o
end
local function attachValue(v)
 if S.values[v] or S.valueCount>=C.MAX_VALUES or not v:IsA("ValueBase") then return end
 S.values[v]=true; S.valueCount=S.valueCount+1
 local c=v.Changed:Connect(function(x) if S.running and not S.stopping then rec("value_changed",{object=valueSnap(v),value=ser(x)}) end end)
 S.conns[#S.conns+1]=c
end

local function obj(inst,source)
 local o={source=source,path=pathOf(inst),name=inst.Name,className=inst.ClassName,parent=inst.Parent and pathOf(inst.Parent) or nil,attributes=attrs(inst)}
 if inst:IsA("ValueBase") then pcall(function() o.value=ser(inst.Value) end)
 elseif inst:IsA("ProximityPrompt") then o.prompt={actionText=inst.ActionText,objectText=inst.ObjectText,enabled=inst.Enabled,hold=inst.HoldDuration,distance=inst.MaxActivationDistance,lineOfSight=inst.RequiresLineOfSight}
 elseif inst:IsA("ClickDetector") then o.click={distance=inst.MaxActivationDistance}
 elseif inst:IsA("Tool") then o.tool={requiresHandle=inst.RequiresHandle,canBeDropped=inst.CanBeDropped}
 elseif inst:IsA("BasePart") then o.part={position=ser(inst.Position),size=ser(inst.Size),material=tostring(inst.Material),anchored=inst.Anchored,canCollide=inst.CanCollide,canTouch=inst.CanTouch,canQuery=inst.CanQuery,transparency=inst.Transparency}
 elseif inst:IsA("GuiObject") then o.gui={visible=inst.Visible,position=ser(inst.Position),size=ser(inst.Size)}; if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then o.gui.text=ser(inst.Text) end end
 return o
end

local function histogram(list) local h={}; for _,x in ipairs(list) do h[x.ClassName]=(h[x.ClassName] or 0)+1 end; return h end
local function scanContainer(root,label)
 local list=root:GetDescendants(); rec("container_summary",{container=label,descendants=#list,classHistogram=histogram(list)})
 local structures=0
 for i,x in ipairs(list) do
  if not S.running or S.stopping then return end
  if isRemote(x) then registerRemote(x,label); if x:IsA("RemoteEvent") or x:IsA("UnreliableRemoteEvent") then attachInbound(x) end; rec("remote_catalog_entry",remoteDesc(x))
  elseif x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") or x:IsA("ModuleScript") or x:IsA("LocalScript") or x:IsA("Script") or x:IsA("BindableEvent") or x:IsA("BindableFunction") or x:IsA("Configuration") then rec("important_instance",obj(x,label)); if x:IsA("ValueBase") then attachValue(x) end
  elseif structures<C.STRUCTURE_MAX and (x:IsA("Folder") or x:IsA("Model") or x:IsA("Accessory")) then structures=structures+1; rec("structure_path",{source=label,path=pathOf(x),className=x.ClassName,children=#x:GetChildren(),attributes=attrs(x)}) end
  if i%130==0 then task.wait() end
 end
end

local function scanNearby()
 local ch=LP.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart"); if not root then rec("nearby_scan",{ok=false,reason="no_root"}); return end
 local p=OverlapParams.new(); p.FilterType=Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances={ch}; p.MaxParts=C.NEARBY_MAX
 local ok,list=pcall(function() return Workspace:GetPartBoundsInRadius(root.Position,C.NEARBY_RADIUS,p) end)
 if not ok then rec("nearby_scan",{ok=false,error=tostring(list)}); return end
 rec("nearby_scan",{ok=true,radius=C.NEARBY_RADIUS,count=#list,origin=ser(root.Position)})
 for i,x in ipairs(list) do if not S.running or S.stopping then return end; rec("nearby_part",obj(x,"nearby")); if i%100==0 then task.wait() end end
end

local function scanTags()
 local ok,tags=pcall(function() return CollectionService:GetAllTags() end); if not ok then rec("tag_scan",{ok=false,error=tostring(tags)}); return end
 table.sort(tags); rec("tag_scan",{ok=true,count=#tags,tags=ser(tags)})
 for _,tag in ipairs(tags) do if not S.running or S.stopping then return end; local list=CollectionService:GetTagged(tag); local samples={}; for i=1,math.min(#list,20) do samples[i]=pathOf(list[i]) end; rec("tag_entry",{tag=tag,count=#list,samples=samples}) end
end

local function scanPlayer()
 rec("player_snapshot",{player=playerSnap(),attributes=attrs(LP)})
 local b=LP:FindFirstChildOfClass("Backpack"); if b then for _,x in ipairs(b:GetChildren()) do if x:IsA("Tool") then rec("inventory_tool",obj(x,"Backpack")) end end end
 local ls=LP:FindFirstChild("leaderstats"); if ls then for _,x in ipairs(ls:GetChildren()) do if x:IsA("ValueBase") then rec("leaderstat",valueSnap(x)); attachValue(x) end end end
end

local function scanGui()
 local pg=LP:FindFirstChildOfClass("PlayerGui"); if not pg then return end
 local n=0
 for _,x in ipairs(pg:GetDescendants()) do if not S.running or S.stopping then return end; if x:IsA("ScreenGui") then rec("gui_screen",{path=pathOf(x),name=x.Name,enabled=x.Enabled,displayOrder=x.DisplayOrder,attributes=attrs(x)}) elseif x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then n=n+1; if n>C.GUI_MAX then break end; rec("gui_text",obj(x,"PlayerGui")) end; if n>0 and n%80==0 then task.wait() end end
end

local function watchContainer(container,label)
 if not container then return end
 local a=container.ChildAdded:Connect(function(x) if S.running and not S.stopping and x:IsA("Tool") then rec("tool_added",{container=label,tool=obj(x,label),player=playerSnap()}) end end)
 local r=container.ChildRemoved:Connect(function(x) if S.running and not S.stopping and x:IsA("Tool") then rec("tool_removed",{container=label,tool={name=x.Name,path=pathOf(x)},player=playerSnap()}) end end)
 S.conns[#S.conns+1]=a; S.conns[#S.conns+1]=r
end

local function runtimeWatchers()
 local ra=ReplicatedStorage.DescendantAdded:Connect(function(x) if not S.running or S.stopping then return end; if isRemote(x) then registerRemote(x,"runtime_added"); if x:IsA("RemoteEvent") or x:IsA("UnreliableRemoteEvent") then attachInbound(x) end; rec("replicated_added",obj(x,"runtime_added")) elseif x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") then rec("replicated_added",obj(x,"runtime_added")); if x:IsA("ValueBase") then attachValue(x) end end end); S.conns[#S.conns+1]=ra
 local wa=Workspace.DescendantAdded:Connect(function(x) if S.running and not S.stopping and (x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector")) then rec("workspace_added",obj(x,"runtime_added")); if x:IsA("ValueBase") then attachValue(x) end end end); S.conns[#S.conns+1]=wa
 local wr=Workspace.DescendantRemoving:Connect(function(x) if S.running and not S.stopping and (x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector")) then rec("workspace_removing",{path=pathOf(x),name=x.Name,className=x.ClassName,attributes=attrs(x)}) end end); S.conns[#S.conns+1]=wr
 local pp=ProximityPromptService.PromptTriggered:Connect(function(prompt,player) if S.running and not S.stopping and (not player or player==LP) then rec("prompt_triggered",{prompt=obj(prompt,"triggered"),player=playerSnap()}) end end); S.conns[#S.conns+1]=pp
 local ac=LP.AttributeChanged:Connect(function(name) if S.running and not S.stopping then rec("player_attribute_changed",{name=tostring(name),value=ser(LP:GetAttribute(name))}) end end); S.conns[#S.conns+1]=ac
 watchContainer(LP:FindFirstChildOfClass("Backpack"),"Backpack"); watchContainer(LP.Character,"Character")
 local ca=LP.CharacterAdded:Connect(function(ch) if S.running and not S.stopping then rec("character_added",{path=pathOf(ch)}); watchContainer(ch,"Character") end end); S.conns[#S.conns+1]=ca
end

local function disconnect() for _,c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end; table.clear(S.conns); S.inbound=setmetatable({},{__mode="k"}); S.values=setmetatable({},{__mode="k"}) end

local function rawRequest(options)
 if not REQUEST then return false,nil,"executor_request_unavailable" end
 local err="unknown"
 for attempt=1,C.RETRIES do local ok,res=pcall(REQUEST,options); if ok and type(res)=="table" then local code=tonumber(res.StatusCode or res.Status or res.status) or 0; if code>=200 and code<300 then return true,res,nil end; err="HTTP "..tostring(code).." "..tostring(res.Body or res.body or "") else err=tostring(res) end; task.wait(C.RETRY_BASE*attempt) end
 return false,nil,err
end

local function getJson(url)
 local ok,res,err=rawRequest({Url=url,Method="GET",Headers={Accept="application/json"}}); if not ok then return false,nil,err end
 local good,data=pcall(HttpService.JSONDecode,HttpService,res.Body or res.body or "{}"); return good and true or false,good and data or nil,good and nil or tostring(data)
end
local function post(body)
 local good,text=pcall(HttpService.JSONEncode,HttpService,body); if not good then return false,nil,"json_encode_failed" end
 local ok,res,err=rawRequest({Url=C.ENDPOINT,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json"},Body=text}); if not ok then return false,nil,err end
 local decode,data=pcall(HttpService.JSONDecode,HttpService,res.Body or res.body or "{}"); if not decode or type(data)~="table" then return false,nil,"invalid_api_response" end
 if data.ok~=true then return false,data,tostring(data.message or "api_not_ok") end
 if type(data.github)~="table" then return false,data,"github_status_missing" end
 if data.github.configured~=true then return false,data,"github_mirror_not_configured" end
 if data.github.mirrored~=true then return false,data,tostring(data.github.error or "github_mirror_failed") end
 return true,data,nil
end

local function cacheFile() return tostring(game.PlaceId).."_"..C.CACHE_SUFFIX end
local function saveCache(snap) if not WRITEFILE then return false,"writefile_unavailable" end; local ok,text=pcall(HttpService.JSONEncode,HttpService,snap); if not ok then return false,"cache_encode_failed" end; local w,e=pcall(WRITEFILE,cacheFile(),text); return w,w and nil or tostring(e) end
local function loadCache() if not READFILE or not ISFILE then return nil end; local ok,exists=pcall(ISFILE,cacheFile()); if not ok or not exists then return nil end; local r,text=pcall(READFILE,cacheFile()); if not r then return nil end; local d,data=pcall(HttpService.JSONDecode,HttpService,text); return d and data or nil end
local function clearCache() if DELFILE and ISFILE then local ok,e=pcall(ISFILE,cacheFile()); if ok and e then pcall(DELFILE,cacheFile()) end end end

local function snapshot() return {schemaVersion=2,version=C.VERSION,purpose=C.PURPOSE,runId=S.runId,capturedAt=iso(),placeId=game.PlaceId,gameId=game.GameId,placeVersion=game.PlaceVersion,userId=LP.UserId,username=LP.Name,startedAt=S.startIso,finishedAt=iso(),records=S.records,remotes=S.remotes,stats={records=#S.records,remotes=#S.remotes,dropped=S.dropped,inboundListeners=S.inboundCount,valueWatchers=S.valueCount,outboundObserver=false,staticDone=S.staticDone}} end
local function split(list,size) local out,i={},1; while i<=#list do local b={}; local stop=math.min(#list,i+size-1); for j=i,stop do b[#b+1]=list[j] end; out[#out+1]=b; i=stop+1 end; return out end

local function upload(snap,status)
 if S.uploading then return false,"upload_already_running" end; S.uploading=true
 local hk,h,he=getJson(C.HEALTH); if not hk or type(h)~="table" or h.ok~=true then S.uploading=false; return false,"health_failed: "..tostring(he) end
 if h.githubMirrorConfigured~=true then S.uploading=false; return false,"github_mirror_not_configured" end
 local rb=split(snap.records or {},C.RECORDS_PER_BATCH); local mb=split(snap.remotes or {},C.REMOTES_PER_BATCH); local total=#rb+#mb+1
 if total>C.MAX_BATCHES then S.uploading=false; return false,"too_many_batches: "..total end
 local bi=0
 local function send(kind,records,remotes)
  bi=bi+1; if status then status(string.format("Enviando %d/%d • %s",bi,total,kind)) end
  local payload={schemaVersion=2,userId=tostring(snap.userId),username=tostring(snap.username),capturedAt=snap.capturedAt,placeId=snap.placeId,gameId=snap.gameId,runId=snap.runId,trace={version=C.VERSION,purpose=C.PURPOSE,runId=snap.runId,batchIndex=bi,batchTotal=total,batchKind=kind,placeVersion=snap.placeVersion,startedAt=snap.startedAt,finishedAt=snap.finishedAt,stats=snap.stats,records=records or {},remotes=remotes or {}}}
  local ok,data,err=post(payload); return ok,ok and data or err
 end
 for _,b in ipairs(mb) do local ok,e=send("remote_catalog",{},b); if not ok then S.uploading=false; return false,e end; task.wait(.15) end
 for _,b in ipairs(rb) do local ok,e=send("records",b,{}); if not ok then S.uploading=false; return false,e end; task.wait(.15) end
 local manifest={{kind="upload_manifest",version=C.VERSION,purpose=C.PURPOSE,runId=snap.runId,placeId=snap.placeId,gameId=snap.gameId,placeVersion=snap.placeVersion,recordsTotal=#(snap.records or {}),remotesTotal=#(snap.remotes or {}),dropped=snap.stats and snap.stats.dropped or 0,recordBatches=#rb,remoteBatches=#mb,finishedAt=snap.finishedAt,githubMirrorRequired=true}}
 local ok,data=send("manifest",manifest,{}); if not ok then S.uploading=false; return false,data end
 S.uploading=false; clearCache(); return true,(type(data)=="table" and data.latestUrl) or "confirmed"
end

local function startScans()
 task.spawn(function()
  local services={}; for _,x in ipairs(game:GetChildren()) do services[#services+1]={name=x.Name,className=x.ClassName} end; rec("game_services",{services=services})
  scanContainer(ReplicatedStorage,"ReplicatedStorage"); if S.running and not S.stopping then scanContainer(Workspace,"Workspace") end; if S.running and not S.stopping then scanNearby() end; if S.running and not S.stopping then scanTags() end; if S.running and not S.stopping then scanPlayer() end; if S.running and not S.stopping then scanGui() end
  S.staticDone=true; rec("scan_completed",{records=#S.records,remotes=#S.remotes,inboundListeners=S.inboundCount,valueWatchers=S.valueCount})
 end)
end

local heartbeat=RunService.Heartbeat:Connect(function() if S.running and not S.stopping and os.clock()-S.lastTrajectory>=C.TRAJECTORY_INTERVAL then S.lastTrajectory=os.clock(); rec("trajectory",{player=playerSnap()}) end end)

local name="CafeinaUniversalGameTraceV21"; local parent=CoreGui; pcall(function() if type(gethui)=="function" then parent=gethui() end end); pcall(function() local old=parent:FindFirstChild(name); if old then old:Destroy() end end)
local gui=Instance.new("ScreenGui"); gui.Name=name; gui.ResetOnSpawn=false; if not pcall(function() gui.Parent=parent end) then gui.Parent=LP:WaitForChild("PlayerGui") end
local f=Instance.new("Frame"); f.Size=UDim2.fromOffset(292,218); f.Position=UDim2.new(.5,-146,.34,-109); f.BackgroundColor3=Color3.fromRGB(8,8,10); f.BorderSizePixel=0; f.Parent=gui; local fc=Instance.new("UICorner"); fc.CornerRadius=UDim.new(0,10); fc.Parent=f; local fs=Instance.new("UIStroke"); fs.Color=Color3.fromRGB(54,54,62); fs.Parent=f
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(10,8); title.Size=UDim2.new(1,-20,0,22); title.Font=Enum.Font.GothamBold; title.TextSize=12; title.TextColor3=Color3.new(1,1,1); title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="CAFEINA • UNIVERSAL TRACE V2.1"; title.Parent=f
local st=Instance.new("TextLabel"); st.BackgroundTransparency=1; st.Position=UDim2.fromOffset(10,34); st.Size=UDim2.new(1,-20,0,66); st.Font=Enum.Font.Gotham; st.TextSize=10; st.TextWrapped=true; st.TextColor3=Color3.fromRGB(195,195,204); st.TextXAlignment=Enum.TextXAlignment.Left; st.TextYAlignment=Enum.TextYAlignment.Top; st.Text=REQUEST and "Pronto • verificando servidor..." or "Executor sem request/http_request"; st.Parent=f
local ct=Instance.new("TextLabel"); ct.BackgroundTransparency=1; ct.Position=UDim2.fromOffset(10,101); ct.Size=UDim2.new(1,-20,0,18); ct.Font=Enum.Font.Code; ct.TextSize=10; ct.TextColor3=Color3.fromRGB(145,145,158); ct.TextXAlignment=Enum.TextXAlignment.Left; ct.Parent=f
local main=Instance.new("TextButton"); main.Position=UDim2.fromOffset(10,126); main.Size=UDim2.new(1,-20,0,37); main.BackgroundColor3=Color3.fromRGB(31,31,36); main.BorderSizePixel=0; main.Font=Enum.Font.GothamBold; main.TextSize=11; main.TextColor3=Color3.new(1,1,1); main.Text="INICIAR COLETA UNIVERSAL"; main.Parent=f; local mc=Instance.new("UICorner"); mc.CornerRadius=UDim.new(0,7); mc.Parent=main
local mark=Instance.new("TextButton"); mark.Position=UDim2.fromOffset(10,170); mark.Size=UDim2.new(1,-20,0,32); mark.BackgroundColor3=Color3.fromRGB(22,22,27); mark.BorderSizePixel=0; mark.Font=Enum.Font.GothamBold; mark.TextSize=10; mark.TextColor3=Color3.fromRGB(210,210,218); mark.Text="MARCAR AÇÃO AGORA"; mark.Parent=f; local mk=Instance.new("UICorner"); mk.CornerRadius=UDim.new(0,7); mk.Parent=mark
local dragging,di,ds,sp=false,nil,nil,nil; f.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; ds=i.Position; sp=f.Position; i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end end); f.InputChanged:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then di=i end end); UserInputService.InputChanged:Connect(function(i) if dragging and i==di then local d=i.Position-ds; f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
local function status(x) st.Text=tostring(x or "") end
task.spawn(function() while gui.Parent do ct.Text=string.format("R:%d  REM:%d  DROP:%d",#S.records,#S.remotes,S.dropped); task.wait(.25) end end)

local function begin()
 if S.running or S.uploading then return end; if not REQUEST then status("Falha: executor sem request/http_request"); return end
 S.running=true; S.stopping=false; S.uploading=false; S.runId=HttpService:GenerateGUID(false); S.startClock=os.clock(); S.startIso=iso(); S.records={}; S.remotes={}; S.remoteSeen={}; S.inboundCount=0; S.valueCount=0; S.dropped=0; S.staticDone=false; S.lastTrajectory=0
 runtimeWatchers(); rec("session_started",{version=C.VERSION,purpose=C.PURPOSE,placeId=game.PlaceId,gameId=game.GameId,placeVersion=game.PlaceVersion,capabilities={request=REQUEST~=nil,writefile=WRITEFILE~=nil,outboundObserver=false},player=playerSnap()}); startScans(); main.Text="ENCERRAR + ENVIAR"; main.BackgroundColor3=Color3.fromRGB(157,42,48); status("Coletando universalmente • use as funções do jogo normalmente")
end

local function finish()
 if not S.running or S.uploading then return end
 rec("session_finalized",{records=#S.records,remotes=#S.remotes,dropped=S.dropped,staticDone=S.staticDone,inboundListeners=S.inboundCount,valueWatchers=S.valueCount,player=playerSnap()})
 S.stopping=true; S.running=false; local snap=snapshot(); disconnect(); local cacheOk,cacheErr=saveCache(snap); S.pending=snap
 main.Text="ENVIANDO..."; main.BackgroundColor3=Color3.fromRGB(31,31,36); status(cacheOk and "Cópia local salva • verificando Render + GitHub..." or ("Mantido na memória • cache local indisponível\n"..tostring(cacheErr)))
 task.spawn(function() local ok,res=upload(snap,status); if ok then S.pending=nil; status("GitHub confirmado ✓\nrunId: "..tostring(snap.runId)); main.Text="INICIAR NOVA COLETA"; S.records={}; S.remotes={} else status("Falha no envio • dados NÃO apagados\n"..tostring(res)); main.Text="REENVIAR DADOS" end end)
end

local function retry()
 if S.uploading then return end; local snap=S.pending or loadCache(); if not snap then status("Nenhuma coleta pendente encontrada"); main.Text="INICIAR COLETA UNIVERSAL"; return end
 main.Text="REENVIANDO..."; status("Reenviando sem apagar a coleta..."); task.spawn(function() local ok,res=upload(snap,status); if ok then S.pending=nil; status("GitHub confirmado ✓\nrunId: "..tostring(snap.runId)); main.Text="INICIAR NOVA COLETA" else S.pending=snap; status("Falha no reenvio • dados preservados\n"..tostring(res)); main.Text="REENVIAR DADOS" end end)
end

mark.Activated:Connect(function() if not S.running or S.stopping then status("Inicie a coleta antes de marcar"); return end; rec("manual_action_marker",{player=playerSnap(),recordsBefore=#S.records}); status("Ação marcada ✓ • faça a ação no jogo agora") end)
main.Activated:Connect(function() if S.uploading then return end; if main.Text=="REENVIAR DADOS" then retry() elseif S.running then finish() else begin() end end)

local pending=loadCache(); if pending then S.pending=pending; main.Text="REENVIAR DADOS"; status("Coleta pendente encontrada • toque para reenviar") else task.spawn(function() if not REQUEST then return end; local ok,h,e=getJson(C.HEALTH); if ok and type(h)=="table" and h.ok then status(h.githubMirrorConfigured and "Render + GitHub prontos ✓\nPode iniciar a coleta" or "Render online • GitHub mirror não configurado") else status("Falha no teste do servidor\n"..tostring(e)) end end) end

ENV.__CAFEINA_UNIVERSAL_TRACE_V21={Gui=gui,State=S,Config=C,Mark=function(label) if S.running and not S.stopping then rec("external_marker",{label=tostring(label or "marker"),player=playerSnap()}) end end,Stop=function() S.stopping=true; S.running=false; disconnect(); pcall(function() heartbeat:Disconnect() end); pcall(function() gui:Destroy() end) end}
gui.Destroying:Connect(function() S.stopping=true; S.running=false; disconnect(); pcall(function() heartbeat:Disconnect() end) end)
print("[CAFEINA] UNIVERSAL GAME TRACE V2.1 carregado • sem filtros por palavra-chave")
