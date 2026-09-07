-- CAFEINA • INVENTORY REMOTE TRACE V5 PICKUP CORRELATOR
-- PASSIVO / MOBILE: cristal no chao -> acao -> args/ID -> remove -> Backpack -> replicacao.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local PPS=game:GetService("ProximityPromptService")
local RS=game:GetService("ReplicatedStorage")
local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV=(getgenv and getgenv()) or _G
local C={
 V="CAFEINA_INVENTORY_REMOTE_TRACE_V5_PICKUP_CORRELATOR",
 ENDPOINT="https://cafe-na-ia.onrender.com/api/inventory-trace",
 HEALTH="https://cafe-na-ia.onrender.com/api/inventory-trace/health",
 MAXREC=1800,MAXREMOTE=240,BASE=3,FOCUS=24,FOCUSSEC=8,SESSIONSEC=10,PRESEC=3,
 RATE=140,RADIUS=38,SCAN=.35,MAXPARTS=120,MAXCRYSTALS=40,MAXVALUES=80,MAXINCOMING=80,MAXJSON=4600000,
 TERMS={"crystal","gem","pickup","pick_up","pick up","collect","claim","take","grab","getitem","get_item","item","inventory","backpack","storage","loot","reward","redeem","dropcrystal","placecrystal","digrequest","dig","plot","gemsignals"},
 PICK={"pickup","pick_up","pick up","collect","claim","take","grab","getitem","get_item","inventory","backpack"},
 CRYS={"crystal","gem"}, IDS={"id","crystalid","crystal_id","gemid","gem_id","itemid","item_id"}
}
local function pick(...)
 for i=1,select("#",...) do local v=select(i,...);if type(v)=="function" then return v end end
end
local sr,hr,fr
pcall(function()if syn and type(syn.request)=="function" then sr=syn.request end end)
pcall(function()if http and type(http.request)=="function" then hr=http.request end end)
pcall(function()if fluxus and type(fluxus.request)=="function" then fr=fluxus.request end end)
local REQUEST=pick(rawget(ENV,"request"),rawget(ENV,"http_request"),hr,sr,fr)
local WRITE=pick(rawget(ENV,"writefile"),writefile)
local CLIP=pick(rawget(ENV,"setclipboard"),setclipboard)
pcall(function()local o=rawget(ENV,"__CAFEINA_INVTRACE_V5") or rawget(ENV,"__CAFEINA_INVTRACE_V4");if type(o)=="table" and type(o.StopLocal)=="function" then o.StopLocal() end end)
pcall(function()local d=rawget(ENV,"__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V5") or rawget(ENV,"__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V3");if type(d)=="table" then d.handler=nil end end)
local S={running=false,uploading=false,records={},remotes=setmetatable({},{__mode="k"}),paths=setmetatable({},{__mode="k"}),conns={},tracked=setmetatable({},{__mode="k"}),near=setmetatable({},{__mode="k"}),watch=setmetatable({},{__mode="k"}),marker=setmetatable({},{__mode="k"}),sessions={},active=nil,seq=0,focusUntil=0,status="Verificando servidor...",rateSec=-1,rateCount=0}
local function low(x)return string.lower(tostring(x or ""))end
local function any(text,list)text=low(text);for _,v in ipairs(list)do if string.find(text,v,1,true)then return true,v end end;return false end
local function path(o)local v=S.paths[o];if v then return v end;local ok,r=pcall(function()return o:GetFullName()end);v=ok and r or tostring(o);S.paths[o]=v;return v end
local function isremote(o)if typeof(o)~="Instance" then return false end;local c=o.ClassName;return c=="RemoteEvent" or c=="RemoteFunction" or c=="UnreliableRemoteEvent" end
local function val(v)
 local t=typeof(v);if v==nil then return nil end
 if t=="string" then return #v<=240 and v or v:sub(1,240).."<truncated>" end
 if t=="number" or t=="boolean" then return v end
 if t=="Vector3" or t=="Vector2" or t=="CFrame" then return tostring(v) end
 if t=="Instance" then return{type="Instance",class=v.ClassName,name=v.Name,path=path(v)}end
 return tostring(v)
end
local function shallow(v,d)
 d=d or 0;if typeof(v)~="table" then return val(v) end;if d>1 then return"<nested>"end
 local o,n={},0;for k,x in pairs(v)do n+=1;if n>10 then o["<truncated>"]=true;break end;o[tostring(k)]=shallow(x,d+1)end;return o
end
local function args(a)local o={};local n=math.min(tonumber(a.n)or#a,8);for i=1,n do o[i]=shallow(a[i],0)end;return o end
local function argtext(a)local o={};local n=math.min(tonumber(a.n)or#a,8);for i=1,n do local v=a[i];local t=typeof(v);if t=="string" or t=="number" or t=="boolean" then o[#o+1]=tostring(v)elseif t=="Instance" then o[#o+1]=v.Name end end;return table.concat(o," ")end
local function diag()
 return{version=C.V,capabilities={request=REQUEST~=nil,writefile=WRITE~=nil,setclipboard=CLIP~=nil,hookmetamethod=type(hookmetamethod)=="function",getnamecallmethod=type(getnamecallmethod)=="function",spatial=true,prompt=true},health={checked=false,ok=false,githubMirrorConfigured=false},counters={records=0,dropRate=0,dropLimit=0,remoteSeen=0,remoteSamples=0,remoteIncoming=0,toolAdded=0,toolRemoved=0,prompt=0,touch=0,click=0,crystalSeen=0,crystalRemoved=0,valueChanges=0,scans=0,scanErrors=0,maxNearby=0,sessions=0,high=0,medium=0,uploadAttempts=0},errors={},operation={capture=false,tools=false,crystals=false,prompts=false,replication=false,incoming=false,backupSupported=WRITE~=nil,backupSaved=false,payloadBytes=0},transport={endpoint=C.ENDPOINT,health=C.HEALTH,retries=3,serverAccepted=false,githubMirrored=false}}
end
S.diag=diag()
local function derr(where,e)local a=S.diag.errors;if#a<24 then a[#a+1]={where=tostring(where),error=tostring(e),clock=os.clock(),unix=os.time()}end end
local function allow()local sec=math.floor(os.clock());if sec~=S.rateSec then S.rateSec=sec;S.rateCount=0 end;if S.rateCount>=C.RATE then S.diag.counters.dropRate+=1;return false end;S.rateCount+=1;return true end
local function rec(r,bypass)
 if not S.running then return nil end;if#S.records>=C.MAXREC then S.diag.counters.dropLimit+=1;S.status="Limite atingido • PARAR + ENVIAR";return nil end
 if not bypass and not allow()then return nil end;r.seq=#S.records+1;r.clock=os.clock();r.unix=os.time();S.records[#S.records+1]=r;S.diag.counters.records+=1;return r
end
local function rcount()local n=0;for _ in pairs(S.remotes)do n+=1 end;return n end
local function marker(o)
 if not o or typeof(o)~="Instance" then return false end;local c=S.marker[o];if c~=nil then return c end
 if any(o.Name,C.CRYS)then S.marker[o]=true;return true end
 local ok,at=pcall(function()return o:GetAttributes()end);if ok then for k in pairs(at)do local q=low(k);if q=="crystalid" or q=="crystal_id" or q=="gemid" or q=="gem_id" then S.marker[o]=true;return true end end end
 local ok2,ch=pcall(function()return o:GetChildren()end);if ok2 then local n=0;for _,x in ipairs(ch)do n+=1;if n>16 then break end;if x:IsA("ValueBase")then local q=low(x.Name);for _,id in ipairs(C.IDS)do if q==id then S.marker[o]=true;return true end end end end end
 S.marker[o]=false;return false
end
local function crystalRoot(o)
 local cur,below=o,nil;for _=1,6 do if not cur or cur==Workspace then break end;if marker(cur)then if cur:IsA("Folder")and below then return below end;return cur end;below=cur;cur=cur.Parent end;return nil
end
local function ids(o)
 local out,seen={},{};local function put(k,v)if v==nil then return end;local z=tostring(k).."="..tostring(v);if seen[z]then return end;seen[z]=true;out[#out+1]={key=tostring(k),value=val(v)}end
 local nodes={o};if o and o.Parent and o.Parent~=Workspace then nodes[#nodes+1]=o.Parent end
 for _,n in ipairs(nodes)do local ok,a=pcall(function()return n:GetAttributes()end);if ok then for k,v in pairs(a)do local q=low(k);for _,w in ipairs(C.IDS)do if q==w then put(n.Name..".attr."..k,v)end end end end;local ok2,ch=pcall(function()return n:GetChildren()end);if ok2 then local z=0;for _,x in ipairs(ch)do z+=1;if z>24 then break end;if x:IsA("ValueBase")then local q=low(x.Name);for _,w in ipairs(C.IDS)do if q==w then local y,v=pcall(function()return x.Value end);if y then put(n.Name..".value."..x.Name,v)end end end end end end end;return out
end
local function snap(o,part,rootpos)
 if not o then return nil end;local p;if part and part:IsA("BasePart")then p=part.Position end;if not p then pcall(function()if o:IsA("Model")then p=o:GetPivot().Position elseif o:IsA("BasePart")then p=o.Position end end)end
 local list=ids(o);if part and part~=o then for _,e in ipairs(ids(part))do list[#list+1]=e end end;local num=tonumber(o.Name);if num then list[#list+1]={key="instance_name_numeric",value=num}end
 return{name=o.Name,class=o.ClassName,path=path(o),position=p and tostring(p)or nil,distance=(p and rootpos)and(p-rootpos).Magnitude or nil,ids=list}
end
local function nearest()
 local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart");local rp=root and root.Position;local best,bd
 for o,i in pairs(S.near)do if o and o.Parent then local x=snap(o,i.part,rp);local d=x and x.distance or math.huge;if not best or d<bd then best,bd=x,d end end end;return best
end
local function actionSummary(r)return r and{seq=r.seq,kind=r.kind,remote=r.remote,method=r.method,role=r.role,arguments=r.arguments,response=r.response,prompt=r.prompt,detector=r.detector,touched=r.touched,clock=r.clock}or nil end
local function finishSession(s)
 if not s or s.finalized then return end;s.finalized=true;s.finishedClock=os.clock();s.finishedUnix=os.time();local a=#s.actions>0;local w=#s.worldRemoved>0;local b=#s.backpackAdded>0;local n=(a and 1 or 0)+(w and 1 or 0)+(b and 1 or 0)
 s.confidence=n==3 and"high"or n==2 and"medium"or"low";s.pickupCorrelated=n==3;s.summary={actionObserved=a,worldRemovalObserved=w,backpackAdditionObserved=b,replicationObserved=w or b or#s.replication>0,pickupCorrelated=s.pickupCorrelated,confidence=s.confidence};if n==3 then S.diag.counters.high+=1 elseif n==2 then S.diag.counters.medium+=1 end
end
local function prebuffer(s)
 local cut=os.clock()-C.PRESEC;for i=#S.records,1,-1 do local r=S.records[i];if(r.clock or 0)<cut then break end;if not r.sessionId and(r.kind=="remote_outgoing"or r.kind=="prompt_triggered"or r.kind=="crystal_touch"or r.kind=="click_detector")then r.sessionId=s.id;s.actions[#s.actions+1]=actionSummary(r)end end
end
local function newSession(kind,data)
 S.seq+=1;local s={id=string.format("pickup-%03d",S.seq),startedClock=os.clock(),startedUnix=os.time(),expiresAt=os.clock()+C.SESSIONSEC,triggerKind=kind,trigger=data,crystalBefore=nearest() or(kind=="crystal_world_removed"and data or nil),actions={},worldRemoved={},backpackAdded={},replication={},finalized=false};S.sessions[#S.sessions+1]=s;S.active=s;S.diag.counters.sessions+=1;prebuffer(s);return s
end
local function session(create,kind,data)local s=S.active;if s and not s.finalized and os.clock()<=s.expiresAt then return s end;if s and not s.finalized then finishSession(s)end;S.active=nil;if create then return newSession(kind or"auto",data)end end
local function attach(r,create)local s=session(create,r and r.kind,actionSummary(r));if not r or not s then return s end;r.sessionId=s.id;s.actions[#s.actions+1]=actionSummary(r);s.expiresAt=math.max(s.expiresAt,os.clock()+C.SESSIONSEC);return s end
local function track(o,part)
 if not o or S.tracked[o]then return end;local n=0;for _ in pairs(S.tracked)do n+=1 end;if n>=C.MAXCRYSTALS then return end
 local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart");local ss=snap(o,part,root and root.Position);S.tracked[o]={part=part,snapshot=ss,seen=os.clock()};S.diag.counters.crystalSeen+=1;rec({kind="crystal_world_seen",crystal=ss},true)
 local ac=o.AncestryChanged:Connect(function()if not S.running then return end;local inside=false;pcall(function()inside=o:IsDescendantOf(Workspace)end);if inside then return end;local t=S.tracked[o];if not t or t.removed then return end;t.removed=true;S.near[o]=nil;S.diag.counters.crystalRemoved+=1;local r=rec({kind="crystal_world_removed",crystal=t.snapshot,replication=true},true);local se=session(true,"crystal_world_removed",t.snapshot);if r and se then r.sessionId=se.id;se.worldRemoved[#se.worldRemoved+1]={seq=r.seq,crystal=r.crystal,clock=r.clock};se.replication[#se.replication+1]={seq=r.seq,type="world_removed",clock=r.clock};se.expiresAt=os.clock()+C.SESSIONSEC end end);S.conns[#S.conns+1]=ac
 if part and part:IsA("BasePart")then local tc=part.Touched:Connect(function(hit)if not S.running then return end;local char=LP.Character;if not char or not hit or not hit:IsDescendantOf(char)then return end;local t=S.tracked[o];if t and t.lastTouch and os.clock()-t.lastTouch<.5 then return end;if t then t.lastTouch=os.clock()end;S.diag.counters.touch+=1;local r=rec({kind="crystal_touch",touched=path(part),characterPart=hit.Name,crystal=t and t.snapshot or ss},true);attach(r,true)end);S.conns[#S.conns+1]=tc end
 local q={{obj=o,depth=0}};local qi,done=1,0;while qi<=#q and done<40 do local e=q[qi];qi+=1;done+=1;local x,d=e.obj,e.depth;if x:IsA("ClickDetector")and not S.watch[x]then S.watch[x]=true;local cc=x.MouseClick:Connect(function(pl)if not S.running or(pl and pl~=LP)then return end;S.diag.counters.click+=1;local r=rec({kind="click_detector",detector=path(x),crystal=S.tracked[o]and S.tracked[o].snapshot or ss},true);attach(r,true)end);S.conns[#S.conns+1]=cc elseif d<3 then local ok,ch=pcall(function()return x:GetChildren()end);if ok then for _,k in ipairs(ch)do q[#q+1]={obj=k,depth=d+1}end end end end
end
local function scan()
 local char=LP.Character;local root=char and char:FindFirstChild("HumanoidRootPart");if not root then return end;local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Exclude;op.FilterDescendantsInstances={char};op.MaxParts=C.MAXPARTS
 local ok,parts=pcall(function()return Workspace:GetPartBoundsInRadius(root.Position,C.RADIUS,op)end);S.diag.counters.scans+=1;if not ok then S.diag.counters.scanErrors+=1;derr("nearby_scan",parts);return end
 local now=setmetatable({},{__mode="k"});local count=0;for _,p in ipairs(parts)do local o=crystalRoot(p);if o and not now[o]then now[o]={part=p};count+=1;track(o,p)end end;if count>S.diag.counters.maxNearby then S.diag.counters.maxNearby=count end;S.near=now
end
local function rinfo(remote)local i=S.remotes[remote];if i then return i end;if rcount()>=C.MAXREMOTE then return nil end;i={path=path(remote),class=remote.ClassName,outgoing=0,samples=0,firstSeen=os.clock()};S.remotes[remote]=i;return i end
local function role(p)p=low(p);if p:find("dropcrystal",1,true)then return"known_drop"end;if p:find("placecrystal",1,true)then return"known_place"end;if any(p,C.PICK)then return"pickup_candidate"end;if p:find("crystal",1,true)or p:find("gem",1,true)then return"crystal_related"end;return"other"end
local function outgoing(remote,method,a,results,phase)
 if not S.running then return end;
 if phase=="response" then local r=rec({kind="remote_invoke_response",remote=path(remote),class=remote.ClassName,method=method,response=args(results or table.pack()),replication=true},true);local se=session(false);if r and se then r.sessionId=se.id;se.replication[#se.replication+1]={seq=r.seq,type="invoke_response",remote=r.remote,response=r.response,clock=r.clock}end;return end;S.diag.counters.remoteSeen+=1;local i=rinfo(remote);if not i then return end;i.outgoing+=1;local focus=os.clock()<=S.focusUntil;local ph,pt=any(i.path,C.TERMS);local ah,at=any(argtext(a),C.TERMS);local ro=role(i.path);local relevant=focus or ph or ah or ro~="other";local limit=focus and C.FOCUS or C.BASE;if not relevant and i.samples>=1 then return end;if i.samples>=limit or not allow()then return end;i.samples+=1;S.diag.counters.remoteSamples+=1;if ph then i.keyword=pt end;if ah then i.keyword=at end;if focus then i.focus=true end
 local r=rec({kind="remote_outgoing",remote=i.path,class=i.class,method=method,relevant=relevant,role=ro,reason=focus and"focus_window"or ph and("path:"..pt)or ah and("arg:"..at)or"first_seen",arguments=relevant and args(a)or nil,response=(method=="InvokeServer"and results)and args(results)or nil},true);local create=focus or ro=="pickup_candidate";if ro=="known_drop"or ro=="known_place"then create=focus end;if relevant then attach(r,create)end
end
local function disconnect()for _,c in ipairs(S.conns)do pcall(function()c:Disconnect()end)end;S.conns={}end
local function tools()
 local function watchCont(c,label)if not c then return end;S.conns[#S.conns+1]=c.ChildAdded:Connect(function(x)if not S.running or not x:IsA("Tool")then return end;S.diag.counters.toolAdded+=1;local at={};pcall(function()for k,v in pairs(x:GetAttributes())do at[k]=val(v)end end);local t={name=x.Name,path=path(x),attributes=at};local r=rec({kind="tool_added",container=label,tool=t,replication=true},true);if label=="Backpack"then local se=session(false);if not se and(os.clock()<=S.focusUntil or nearest())then se=session(true,"backpack_tool_added",t)end;if r and se then r.sessionId=se.id;se.backpackAdded[#se.backpackAdded+1]={seq=r.seq,tool=t,clock=r.clock};se.replication[#se.replication+1]={seq=r.seq,type="backpack_added",clock=r.clock};se.expiresAt=os.clock()+C.SESSIONSEC end end end);S.conns[#S.conns+1]=c.ChildRemoved:Connect(function(x)if not S.running or not x:IsA("Tool")then return end;S.diag.counters.toolRemoved+=1;local r=rec({kind="tool_removed",container=label,tool={name=x.Name,path=path(x)}},true);local se=session(false);if r and se then r.sessionId=se.id end end)end
 watchCont(LP:FindFirstChildOfClass("Backpack"),"Backpack");watchCont(LP.Character,"Character");S.conns[#S.conns+1]=LP.CharacterAdded:Connect(function(ch)if S.running then watchCont(ch,"Character")end end);S.diag.operation.tools=true
end
local function prompts()
 local ok,c=pcall(function()return PPS.PromptTriggered:Connect(function(p,pl)if not S.running or(pl and pl~=LP)then return end;S.diag.counters.prompt+=1;local o=crystalRoot(p);local r=rec({kind="prompt_triggered",prompt=path(p),actionText=p.ActionText,objectText=p.ObjectText,crystal=o and(S.tracked[o]and S.tracked[o].snapshot or snap(o,p.Parent and p.Parent:IsA("BasePart")and p.Parent,nil))or nil},true);attach(r,true)end)end);if ok and c then S.conns[#S.conns+1]=c;S.diag.operation.prompts=true else derr("prompt",c)end
end
local function valueWatch(o)
 if not o or S.watch[o]or not o:IsA("ValueBase")or not any(path(o),C.TERMS)then return end;local n=0;for _ in pairs(S.watch)do n+=1 end;if n>=C.MAXVALUES then return end;S.watch[o]=true;local last;pcall(function()last=val(o.Value)end);local c=o.Changed:Connect(function(v)if not S.running then return end;local nv=val(v);S.diag.counters.valueChanges+=1;local r=rec({kind="replicated_value_changed",path=path(o),old=last,new=nv,replication=true},true);last=nv;local se=session(false);if r and se then r.sessionId=se.id;se.replication[#se.replication+1]={seq=r.seq,type="value_changed",path=r.path,old=r.old,new=r.new,clock=r.clock}end end);S.conns[#S.conns+1]=c
end
local function replication()
 local ok,d=pcall(function()return LP:GetDescendants()end);if ok then for _,o in ipairs(d)do valueWatch(o)end else derr("player_descendants",d)end;S.conns[#S.conns+1]=LP.DescendantAdded:Connect(function(o)if not S.running then return end;valueWatch(o);if any(path(o),C.TERMS)and(o:IsA("Folder")or o:IsA("Configuration"))then local r=rec({kind="replicated_object_added",path=path(o),class=o.ClassName,replication=true},true);local se=session(false);if r and se then r.sessionId=se.id;se.replication[#se.replication+1]={seq=r.seq,type="object_added",path=r.path,clock=r.clock}end end end);S.diag.operation.replication=true
end
local function incoming()
 local roots={};local ok,ch=pcall(function()return RS:GetChildren()end);if not ok then derr("incoming_roots",ch);return end;for _,x in ipairs(ch)do local n=low(x.Name);if any(n,C.TERMS)or n=="gemsignals"or n=="plotremotes"or n=="digremotes"then roots[#roots+1]=x end end
 local q={};for _,x in ipairs(roots)do q[#q+1]={o=x,d=0}end;local qi,processed,count=1,0,0;while qi<=#q and processed<360 and count<C.MAXINCOMING do local e=q[qi];qi+=1;processed+=1;local o,d=e.o,e.d;if o:IsA("RemoteEvent")or o:IsA("UnreliableRemoteEvent")then count+=1;local remote=o;local c=remote.OnClientEvent:Connect(function(...)if not S.running then return end;S.diag.counters.remoteIncoming+=1;local r=rec({kind="remote_incoming",remote=path(remote),class=remote.ClassName,arguments=args(table.pack(...)),replication=true},true);local se=session(false);if r and se then r.sessionId=se.id;se.replication[#se.replication+1]={seq=r.seq,type="remote_incoming",remote=r.remote,arguments=r.arguments,clock=r.clock};se.expiresAt=os.clock()+C.SESSIONSEC end end);S.conns[#S.conns+1]=c elseif d<4 then local yes,kids=pcall(function()return o:GetChildren()end);if yes then for _,k in ipairs(kids)do q[#q+1]={o=k,d=d+1}end end end end;S.diag.operation.incoming=count>0;S.diag.operation.incomingCount=count
end
local KEY="__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V5";local D=rawget(ENV,KEY)
if type(D)~="table"and type(hookmetamethod)=="function"and type(getnamecallmethod)=="function"then
 D={handler=nil};local wrap=type(newcclosure)=="function"and newcclosure or function(f)return f end;local old
 old=hookmetamethod(game,"__namecall",wrap(function(self,...)
  local m=getnamecallmethod();local h=D.handler
  if h and m=="InvokeServer"and isremote(self)then local a=table.pack(...);pcall(h,self,m,a,nil,"request");local r=table.pack(old(self,...));pcall(h,self,m,a,r,"response");return table.unpack(r,1,r.n)
  elseif h and m=="FireServer"and isremote(self)then pcall(h,self,m,table.pack(...),nil,"request")end
  return old(self,...)
 end));ENV[KEY]=D
end
local function enable()if type(D)~="table"then derr("capture","hookmetamethod/getnamecallmethod indisponivel");return false end;D.handler=outgoing;S.diag.operation.capture=true;return true end
local function disable()if type(D)=="table"then D.handler=nil end end
local function iso()local ok,v=pcall(function()return DateTime.now():ToIsoDate()end);return ok and v or os.date("!%Y-%m-%dT%H:%M:%SZ")end
local function http(o)if not REQUEST then return false,nil,"request/http_request indisponivel"end;local ok,r=pcall(REQUEST,o);if not ok or not r then return false,nil,tostring(r)end;local code=tonumber(r.StatusCode or r.Status or r.status_code or r.status)or 0;local body=tostring(r.Body or r.body or"");return code>=200 and code<300,{status=code,body=body},nil end
local function health()
 S.diag.health.checked=true;if not REQUEST then S.diag.health.error="executor_sem_http";S.status="Executor sem HTTP • backup local";return false end;local ok,r,e=http({Url=C.HEALTH,Method="GET",Headers={Accept="application/json",["Cache-Control"]="no-cache"}});if not ok then S.diag.health.error=e or(r and"HTTP "..r.status)or"health_failed";S.status="Servidor indisponivel • backup local";return false end;local d;pcall(function()d=HttpService:JSONDecode(r.body)end);if type(d)=="table"and d.ok==true then S.diag.health.ok=true;S.diag.health.httpStatus=r.status;S.diag.health.githubMirrorConfigured=d.githubMirrorConfigured==true;S.diag.health.maxRecords=d.maxRecords;S.diag.health.maxRemotes=d.maxRemotes;S.status=d.githubMirrorConfigured and"Servidor OK • GitHub mirror OK"or"Servidor OK • GitHub mirror OFF";return true end;S.diag.health.error="health_invalid";return false
end
local function report()
 if S.active and not S.active.finalized then finishSession(S.active)end;for _,x in ipairs(S.sessions)do if not x.finalized then finishSession(x)end end;local rem={};for _,i in pairs(S.remotes)do rem[#rem+1]={path=i.path,class=i.class,outgoing=i.outgoing,samples=i.samples,keyword=i.keyword,focus=i.focus,firstSeen=i.firstSeen}end;table.sort(rem,function(a,b)return a.path<b.path end);S.diag.operation.records=#S.records;S.diag.operation.remotes=#rem;S.diag.operation.sessions=#S.sessions;S.diag.operation.finishedAt=os.time();S.diag.operation.durationSeconds=S.startedClock and(os.clock()-S.startedClock)or nil;return{version=C.V,runId=S.runId,startedAt=S.startedAt,finishedAt=os.time(),purpose="crystal_pickup_correlation",remotes=rem,records=S.records,pickupSessions=S.sessions,diagnostics=S.diag}
end
local function payload(r)return{schemaVersion=1,userId=tostring(LP.UserId),username=tostring(LP.Name),capturedAt=iso(),placeId=game.PlaceId,gameId=game.GameId,runId=S.runId,trace=r}end
local function backup(p)
 local name="Cafeina_PickupTrace_"..game.PlaceId.."_"..os.time()..".json";local ok,j=pcall(function()return HttpService:JSONEncode(p)end);if not ok then derr("json",j);return nil,nil end;S.diag.operation.payloadBytes=#j;if WRITE then local yes,e=pcall(WRITE,name,j);S.diag.operation.backupSaved=yes;if not yes then derr("writefile",e)end;local y,j2=pcall(function()return HttpService:JSONEncode(p)end);if y then j=j2;S.diag.operation.payloadBytes=#j;if yes then pcall(WRITE,name,j)end end end;if#j>C.MAXJSON then derr("payload_size","JSON excedeu limite de upload");S.diag.operation.payloadTooLarge=true;return name,nil end;return name,j
end
local function send(p,j)
 if not REQUEST then return false,"executor sem HTTP"end;S.uploading=true;local last;for n=1,3 do S.diag.counters.uploadAttempts+=1;S.status="Enviando... "..n.."/3";local ok,r,e=http({Url=C.ENDPOINT,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json",["User-Agent"]="Cafeina-PickupTrace/5"},Body=j});if ok then local d;pcall(function()d=HttpService:JSONDecode(r.body)end);if type(d)=="table"and d.ok==true then S.diag.transport.serverAccepted=true;S.diag.transport.githubMirrored=type(d.github)=="table"and d.github.mirrored==true;S.diag.transport.httpStatus=r.status;S.diag.transport.latestUrl=d.latestUrl;S.uploading=false;return true,d end;last="HTTP OK sem confirmacao JSON"else last=e or(r and"HTTP "..r.status)or"falha HTTP"end;S.diag.transport.lastError=last;if n<3 then task.wait(n)end end;S.uploading=false;return false,last
end
local function loops()
 task.spawn(function()while S.running do local ok,e=pcall(scan);if not ok then S.diag.counters.scanErrors+=1;derr("scan_loop",e)end;task.wait(C.SCAN)end end)
 task.spawn(function()while S.running do local x=S.active;if x and not x.finalized and os.clock()>x.expiresAt then finishSession(x);S.active=nil end;task.wait(.4)end end)
end
local function start()
 if S.running or S.uploading then return end;disconnect();S.records={};S.remotes=setmetatable({},{__mode="k"});S.paths=setmetatable({},{__mode="k"});S.tracked=setmetatable({},{__mode="k"});S.near=setmetatable({},{__mode="k"});S.watch=setmetatable({},{__mode="k"});S.marker=setmetatable({},{__mode="k"});S.sessions={};S.active=nil;S.seq=0;S.startedAt=os.time();S.startedClock=os.clock();S.runId=HttpService:GenerateGUID(false);S.focusUntil=0;S.rateSec=-1;S.rateCount=0;S.lastPayload=nil;S.lastJson=nil;S.lastBackup=nil;S.diag=diag();S.running=true;tools();prompts();replication();incoming();S.diag.operation.crystals=true;local ok=enable();loops();task.spawn(health);S.status=ok and"SCAN ATIVO • pegue cristais normalmente"or"SCAN PARCIAL • sem hook de remotes"
end
local function mark()
 if not S.running then S.status="Inicie o scan primeiro";return end;S.focusUntil=os.clock()+C.FOCUSSEC;local se=session(true,"manual_pickup_window",{seconds=C.FOCUSSEC,crystal=nearest()});se.expiresAt=os.clock()+C.SESSIONSEC;rec({kind="pickup_window_marked",sessionId=se.id,seconds=C.FOCUSSEC,crystal=se.crystalBefore},true);S.status="PICKUP MARCADO 8s • pegue o cristal agora";task.delay(C.FOCUSSEC,function()if S.running and os.clock()>=S.focusUntil then S.status="SCAN ATIVO • pegue cristais normalmente"end end)
end
local function stoplocal()S.running=false;S.focusUntil=0;if S.active and not S.active.finalized then finishSession(S.active)end;disable();disconnect()end
local function deliver(p,name,j)
 S.lastPayload=p;S.lastJson=j;S.lastBackup=name;local ok,d=send(p,j);if not ok then S.status="ENVIO FALHOU • backup preservado • ENVIAR NOVAMENTE";warn("[PICKUP TRACE]",d);return end;local g=type(d.github)=="table"and d.github or{};if g.mirrored==true then S.status="ENVIADO + GITHUB ✓ • "..tostring(d.traceId or"OK")elseif g.configured==true then S.status="SERVIDOR RECEBEU • GITHUB FALHOU"else S.status="SERVIDOR RECEBEU • GITHUB MIRROR OFF"end;if d.latestUrl then local u="https://cafe-na-ia.onrender.com"..d.latestUrl;print("[PICKUP TRACE] latest:",u);if CLIP then pcall(CLIP,u)end end;print("[PICKUP TRACE] registros",#S.records,"pickups",#S.sessions,"erros",#S.diag.errors,"github",g.mirrored==true)
end
local function finish()
 if S.uploading then return end;if not S.running then if S.lastPayload and S.lastJson then task.spawn(deliver,S.lastPayload,S.lastBackup,S.lastJson)else S.status="Nenhuma coleta pronta"end;return end;stoplocal();S.status="Gerando diagnostico + arquivo...";local p=payload(report());local name,j=backup(p);if not j then S.status="JSON grande/erro • backup local preservado";return end;S.lastPayload=p;S.lastJson=j;S.lastBackup=name;task.spawn(deliver,p,name,j)
end
-- GUI compacta
pcall(function()local g=rawget(ENV,"__CAFEINA_INVTRACE_GUI");if g then g:Destroy()end end)
local parent=CoreGui;pcall(function()if gethui then parent=gethui()end end)
local gui=Instance.new("ScreenGui");gui.Name="CafeinaPickupTraceV5";gui.ResetOnSpawn=false;gui.Parent=parent;ENV.__CAFEINA_INVTRACE_GUI=gui
local f=Instance.new("Frame");f.Size=UDim2.fromOffset(264,224);f.Position=UDim2.fromOffset(8,72);f.BackgroundColor3=Color3.fromRGB(16,16,19);f.BorderSizePixel=0;f.Active=true;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,12)
local title=Instance.new("TextLabel");title.Size=UDim2.new(1,-72,0,30);title.Position=UDim2.fromOffset(10,5);title.BackgroundTransparency=1;title.Text="CAFEINA • PICKUP TRACE V5";title.TextColor3=Color3.new(1,1,1);title.TextSize=11;title.Font=Enum.Font.GothamBold;title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=f
local min=Instance.new("TextButton");min.Size=UDim2.fromOffset(52,26);min.Position=UDim2.new(1,-60,0,6);min.BackgroundColor3=Color3.fromRGB(38,38,44);min.BorderSizePixel=0;min.Text="MIN";min.TextColor3=Color3.new(1,1,1);min.TextSize=11;min.Font=Enum.Font.GothamBold;min.Parent=f;Instance.new("UICorner",min).CornerRadius=UDim.new(0,7)
local st=Instance.new("TextLabel");st.Size=UDim2.new(1,-20,0,74);st.Position=UDim2.fromOffset(10,38);st.BackgroundTransparency=1;st.TextWrapped=true;st.TextColor3=Color3.fromRGB(210,210,210);st.TextSize=10;st.Font=Enum.Font.Gotham;st.TextXAlignment=Enum.TextXAlignment.Left;st.TextYAlignment=Enum.TextYAlignment.Top;st.Parent=f
local function button(text,y,bg)local b=Instance.new("TextButton");b.Size=UDim2.new(1,-20,0,31);b.Position=UDim2.fromOffset(10,y);b.BackgroundColor3=bg;b.BorderSizePixel=0;b.Text=text;b.TextColor3=Color3.new(1,1,1);b.TextSize=11;b.Font=Enum.Font.GothamBold;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,8);return b end
local bs=button("INICIAR SCAN",116,Color3.fromRGB(35,80,45));local bm=button("MARCAR PICKUP • 8s",152,Color3.fromRGB(45,45,52));local bf=button("PARAR + ENVIAR",188,Color3.fromRGB(115,28,28))
local mini=Instance.new("TextButton");mini.Size=UDim2.fromOffset(84,42);mini.Position=f.Position;mini.BackgroundColor3=Color3.fromRGB(18,18,22);mini.BorderSizePixel=0;mini.Text="PICKUP TRACE";mini.TextColor3=Color3.new(1,1,1);mini.TextSize=9;mini.Font=Enum.Font.GothamBold;mini.Visible=false;mini.Parent=gui;Instance.new("UICorner",mini).CornerRadius=UDim.new(0,10)
local function minimize(v)f.Visible=not v;mini.Visible=v;if v then mini.Text=S.running and"TRACE ON"or"PICKUP TRACE"end end;min.MouseButton1Click:Connect(function()minimize(true)end);mini.MouseButton1Click:Connect(function()minimize(false)end)
do local drag=false;local ds,sp;title.Active=true;title.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true;ds=i.Position;sp=f.Position end end);title.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end);UIS.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y);mini.Position=f.Position end end)end
bs.MouseButton1Click:Connect(function()start();if S.running then task.delay(.3,function()if S.running then minimize(true)end end)end end);bm.MouseButton1Click:Connect(function()mark();if S.running then task.delay(.2,function()if S.running then minimize(true)end end)end end);bf.MouseButton1Click:Connect(finish)
task.spawn(function()while gui.Parent do local d=S.diag;st.Text=S.status.."\n"..#S.records.." registros • "..rcount().." remotes\n"..#S.sessions.." pickups • alta: "..(d and d.counters.high or 0).." • erros: "..(d and#d.errors or 0);bs.Text=S.running and"SCAN ATIVO"or"INICIAR SCAN";bf.Text=S.uploading and"ENVIANDO..."or(not S.running and S.lastPayload and"ENVIAR NOVAMENTE"or"PARAR + ENVIAR");if mini.Visible then mini.Text=S.running and"TRACE ON"or(S.uploading and"UPLOAD"or"PICKUP TRACE")end;task.wait(.5)end end)
task.spawn(health)
ENV.__CAFEINA_INVTRACE_V5={Start=start,MarkPickup=mark,Finish=finish,StopLocal=stoplocal,Preflight=health,State=S}
print("[CAFEINA PICKUP TRACE] V5 carregado")
