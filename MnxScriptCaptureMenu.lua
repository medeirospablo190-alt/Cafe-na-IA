-- CAFEINA • UNIVERSAL SCRIPT CAPTURE V2.1 DIAGNOSTIC
-- executor/mobile • pass-through • auto Render/GitHub

local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local StarterGui=game:GetService("StarterGui")
local LogService=game:GetService("LogService")
local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV=(getgenv and getgenv()) or _G
local ORIG_LOADSTRING=loadstring
local ORIG_LOAD=rawget(ENV,"load") or rawget(_G,"load")
local C={
 V="CAFEINA_UNIVERSAL_CAPTURE_V2_1_DIAG",
 POST="https://cafe-na-ia.onrender.com/api/inventory-trace",
 HEALTH="https://cafe-na-ia.onrender.com/api/inventory-trace/health",
 CHUNK=80000,BATCH=18,RETRIES=3,DIR="CafeinaCaptures",RUNTIME_WINDOW=20,
}

local function firstfn(...)
 for i=1,select("#",...) do local v=select(i,...);if type(v)=="function" then return v end end
end
local synReq,httpReq,fluxReq
pcall(function() if syn and type(syn.request)=="function" then synReq=syn.request end end)
pcall(function() if http and type(http.request)=="function" then httpReq=http.request end end)
pcall(function() if fluxus and type(fluxus.request)=="function" then fluxReq=fluxus.request end end)
local REQUEST=firstfn(rawget(ENV,"request"),rawget(ENV,"http_request"),httpReq,synReq,fluxReq)
local WRITE=firstfn(rawget(ENV,"writefile"),writefile)
local MKDIR=firstfn(rawget(ENV,"makefolder"),makefolder)
local ISDIR=firstfn(rawget(ENV,"isfolder"),isfolder)

pcall(function()
 local old=rawget(ENV,"__CAFEINA_UNIVERSAL_CAPTURE")
 if old and type(old.Stop)=="function" then old.Stop() end
end)

local S={enabled=true,hookMode="none",loadHook=false,httpHook=false,requestHook=false,requestMode="none",runtime="none",
 captures=0,uploaded=0,duplicates=0,failed=0,diagnostics=0,diagUploaded=0,queue={},worker=false,seen={},items={},diag={},conns={},lastCompile=nil}

pcall(function() local g=rawget(ENV,"__CAFEINA_MNX_CAPTURE_GUI");if g then g:Destroy() end end)
pcall(function() local g=rawget(ENV,"__CAFEINA_UNIVERSAL_CAPTURE_GUI");if g then g:Destroy() end end)
local parent=CoreGui;pcall(function() if gethui then parent=gethui() end end)
local gui=Instance.new("ScreenGui");gui.Name="CafeinaUniversalCaptureV21";gui.ResetOnSpawn=false;gui.Parent=parent
ENV.__CAFEINA_MNX_CAPTURE_GUI=gui;ENV.__CAFEINA_UNIVERSAL_CAPTURE_GUI=gui
local f=Instance.new("Frame");f.Size=UDim2.fromOffset(302,142);f.Position=UDim2.fromOffset(10,72);f.BackgroundColor3=Color3.fromRGB(16,16,20);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,11)
local t=Instance.new("TextLabel");t.Size=UDim2.new(1,-70,0,26);t.Position=UDim2.fromOffset(10,5);t.BackgroundTransparency=1;t.Text="CAFEINA • UNIVERSAL CAPTURE 2.1";t.TextColor3=Color3.new(1,1,1);t.TextSize=11;t.Font=Enum.Font.GothamBold;t.TextXAlignment=Enum.TextXAlignment.Left;t.Parent=f
local stop=Instance.new("TextButton");stop.Size=UDim2.fromOffset(54,24);stop.Position=UDim2.new(1,-62,0,6);stop.BackgroundColor3=Color3.fromRGB(100,30,35);stop.BorderSizePixel=0;stop.Text="PARAR";stop.TextColor3=Color3.new(1,1,1);stop.TextSize=9;stop.Font=Enum.Font.GothamBold;stop.Parent=f;Instance.new("UICorner",stop).CornerRadius=UDim.new(0,7)
local st=Instance.new("TextLabel");st.Size=UDim2.new(1,-20,0,50);st.Position=UDim2.fromOffset(10,34);st.BackgroundTransparency=1;st.TextWrapped=true;st.Text="Inicializando...";st.TextColor3=Color3.fromRGB(225,225,230);st.TextSize=10;st.Font=Enum.Font.Gotham;st.TextXAlignment=Enum.TextXAlignment.Left;st.TextYAlignment=Enum.TextYAlignment.Top;st.Parent=f
local hooks=Instance.new("TextLabel");hooks.Size=UDim2.new(1,-20,0,20);hooks.Position=UDim2.fromOffset(10,86);hooks.BackgroundTransparency=1;hooks.TextColor3=Color3.fromRGB(150,165,185);hooks.TextSize=9;hooks.Font=Enum.Font.Code;hooks.TextXAlignment=Enum.TextXAlignment.Left;hooks.Parent=f
local cnt=Instance.new("TextLabel");cnt.Size=UDim2.new(1,-20,0,24);cnt.Position=UDim2.fromOffset(10,111);cnt.BackgroundTransparency=1;cnt.TextColor3=Color3.fromRGB(160,160,170);cnt.TextSize=9;cnt.Font=Enum.Font.Code;cnt.TextXAlignment=Enum.TextXAlignment.Left;cnt.Parent=f
local function refresh()
 pcall(function()
  hooks.Text=string.format("load=%s • HttpGet=%s • request=%s • runtime=%s",S.hookMode,S.httpHook and "ON" or "OFF",S.requestHook and S.requestMode or "OFF",S.runtime)
  cnt.Text=string.format("capt %d • env %d • diag %d/%d • falhas %d • dup %d",S.captures,S.uploaded,S.diagUploaded,S.diagnostics,S.failed,S.duplicates)
 end)
end
local function status(x,notify)
 pcall(function() st.Text=tostring(x) end);refresh();print("[UNIVERSAL CAPTURE] "..tostring(x))
 if notify then task.spawn(function() pcall(function() StarterGui:SetCore("SendNotification",{Title="UNIVERSAL CAPTURE",Text=tostring(x),Duration=5}) end) end) end
end
local function iso() local ok,v=pcall(function() return DateTime.now():ToIsoDate() end);return ok and v or os.date("!%Y-%m-%dT%H:%M:%SZ") end
local function clip(v,n) local s=tostring(v or "");n=n or 500;if #s>n then s=s:sub(1,n).."..." end;return s end
local function req(o)
 if not REQUEST then return false,nil,"request/http_request indisponivel" end
 local ok,r=pcall(REQUEST,o);if not ok or not r then return false,nil,tostring(r) end
 local code=tonumber(r.StatusCode or r.Status or r.status_code or r.status) or 0
 local body=tostring(r.Body or r.body or r.Data or "")
 return code>=200 and code<300,{status=code,body=body},nil
end
local function health()
 local ok,r,e=req({Url=C.HEALTH,Method="GET",Headers={Accept="application/json",["Cache-Control"]="no-cache"}})
 if not ok then return false,e or (r and "HTTP "..r.status) or "health falhou" end
 local d;pcall(function() d=HttpService:JSONDecode(r.body) end)
 if type(d)~="table" or d.ok~=true then return false,"health invalido" end
 if d.githubMirrorConfigured~=true then return false,"Render OK, mirror GitHub nao configurado" end
 return true
end
local function cafeUrl(url) return string.lower(tostring(url or "")):find("cafe%-na%-ia%.onrender%.com",1,false)~=nil end
local function hash(src)
 local h=5381;for i=1,#src do h=(h*33+string.byte(src,i))%4294967296;if i%250000==0 then task.wait() end end
 return string.format("%08x-%d",h,#src)
end
local function saveLocal(item)
 if not WRITE then return end
 if MKDIR then pcall(function() if not ISDIR or not ISDIR(C.DIR) then MKDIR(C.DIR) end end) end
 pcall(WRITE,string.format("%s/Capture_%04d_%s.lua",C.DIR,item.index,item.hash:sub(1,8)),item.source)
end
local function looksLua(src,url)
 if type(src)~="string" or #src<20 then return false end
 local u=string.lower(tostring(url or ""));if u:find("%.lua",1,false) or u:find("raw%.githubusercontent%.com",1,false) then return true end
 local n=0;for _,m in ipairs({"loadstring","function","local ","game:GetService","FireServer","InvokeServer","CreateWindow","getgenv"}) do if src:find(m,1,true) then n=n+1;if n>=2 then return true end end end
 return false
end

local function post(payload,ua)
 local ok,j=pcall(function() return HttpService:JSONEncode(payload) end);if not ok then return false,"JSONEncode falhou" end
 local last="falha HTTP"
 for n=1,C.RETRIES do
  local yes,r,e=req({Url=C.POST,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json",["User-Agent"]=ua},Body=j})
  if yes and r then local d;pcall(function() d=HttpService:JSONDecode(r.body) end);if type(d)=="table" and d.ok==true and type(d.github)=="table" and d.github.mirrored==true then return true end;last="Render recebeu sem mirror confirmado" else last=e or (r and "HTTP "..r.status) or last end
  if n<C.RETRIES then task.wait(1.1*n) end
 end
 return false,last
end
local function sendDiag(kind,data)
 if not S.enabled then return end
 S.diagnostics=S.diagnostics+1;local idx=S.diagnostics
 local rec={kind="capture_diagnostic",diagnostic=tostring(kind),index=idx,at=iso()}
 if type(data)=="table" then for k,v in pairs(data) do local lk=string.lower(tostring(k));if lk~="key" and lk~="hwid" and lk~="headers" and lk~="body" and lk~="requestbody" then if type(v)=="string" then rec[k]=clip(v,1200) elseif type(v)=="number" or type(v)=="boolean" then rec[k]=v elseif v~=nil then rec[k]=clip(v,500) end end end end
 S.diag[#S.diag+1]=rec;refresh()
 task.spawn(function()
  local rid=string.format("SCRIPT_DIAG_%d_%s_%d",idx,tostring(kind):upper():gsub("[^A-Z0-9_]","_"),os.time())
  local p={schemaVersion=1,userId=tostring(LP.UserId),username=tostring(LP.Name),capturedAt=iso(),placeId=game.PlaceId,gameId=game.GameId,runId=rid,trace={version=C.V,runId=rid,stage="capture_diagnostic",origin="diagnostic",remotes={},records={rec}}}
  local ok=post(p,"Cafeina-Universal-Diagnostic/2.1");if ok then S.diagUploaded=S.diagUploaded+1 else S.failed=S.failed+1 end;refresh()
 end)
end
local function sendSource(item)
 local total=math.max(1,math.ceil(#item.source/C.CHUNK));local batches=math.max(1,math.ceil(total/C.BATCH))
 for bi=1,batches do
  if not S.enabled then return false,"captura parada" end
  local records={};local a=(bi-1)*C.BATCH+1;local z=math.min(total,bi*C.BATCH)
  for i=a,z do local s=(i-1)*C.CHUNK+1;local e=math.min(#item.source,i*C.CHUNK);records[#records+1]={kind="script_source_chunk",stage="universal_pass_through",origin=item.origin,index=i,total=total,data=item.source:sub(s,e)} end
  local rid=string.format("SCRIPT_CAPTURE_%d_%s_B%d_%d",item.index,item.hash:sub(1,8),bi,os.time())
  local p={schemaVersion=1,userId=tostring(LP.UserId),username=tostring(LP.Name),capturedAt=iso(),placeId=game.PlaceId,gameId=game.GameId,runId=rid,trace={version=C.V,runId=rid,captureId=item.captureId,stage="universal_pass_through",origin=item.origin,detail=item.detail,sourceChars=#item.source,sourceHash=item.hash,sourceIndex=item.index,chunkCount=total,batchIndex=bi,batchTotal=batches,remotes={},records=records}}
  status(string.format("Enviando captura #%d • lote %d/%d...",item.index,bi,batches))
  local ok,err=post(p,"Cafeina-Universal-Capture/2.1");if not ok then return false,err end
 end
 return true
end
local function worker()
 if S.worker then return end;S.worker=true
 task.spawn(function()
  while S.enabled and #S.queue>0 do local item=table.remove(S.queue,1);local ok,err=sendSource(item);if ok then S.uploaded=S.uploaded+1;status(string.format("CAPTURA #%d NO GITHUB ✓ • %d bytes",item.index,#item.source),true) else S.failed=S.failed+1;status("CAPTURA PRESERVADA • "..tostring(err),true) end;refresh() end
  S.worker=false
 end)
end
local function process(src,origin,detail)
 if not S.enabled or type(src)~="string" or src=="" then return end
 local h=hash(src);if S.seen[h] then S.duplicates=S.duplicates+1;refresh();return end;S.seen[h]=true
 S.captures=S.captures+1;local i=S.captures;local item={index=i,source=src,hash=h,origin=tostring(origin or "unknown"),detail=clip(detail,500),captureId=string.format("CAP_%s_%d_%d_%d",game.PlaceId,LP.UserId,os.time(),i)}
 S.items[#S.items+1]=item;saveLocal(item);S.queue[#S.queue+1]=item;status(string.format("CAPTURADO #%d • %d bytes • %s",i,#src,item.origin),true);worker()
end
local function observe(src,origin,detail) if S.enabled and type(src)=="string" then task.defer(process,src,origin,detail) end end

local function installCompiler(original,name)
 if type(original)~="function" then return false,"none" end
 if type(hookfunction)=="function" then
  local old
  local wrap=function(src,chunk) observe(src,name,chunk);local fn,err=old(src,chunk);S.lastCompile={clock=os.clock(),chars=type(src)=="string" and #src or 0,chunk=clip(chunk,250),compiler=name};if type(fn)=="function" then sendDiag("loadstring_compile_ok",{sourceChars=S.lastCompile.chars,chunkName=S.lastCompile.chunk,compiler=name}) else status("ERRO DE COMPILACAO • "..clip(err,160),true);sendDiag("loadstring_compile_error",{sourceChars=S.lastCompile.chars,chunkName=S.lastCompile.chunk,compiler=name,error=err}) end;return fn,err end
  if type(newcclosure)=="function" then local ok,w=pcall(newcclosure,wrap);if ok and type(w)=="function" then wrap=w end end
  local ok,o=pcall(function() return hookfunction(original,wrap) end);if ok and type(o)=="function" then old=o;return true,"hookfunction" end
 end
 local repl=function(src,chunk) observe(src,name,chunk);local fn,err=original(src,chunk);S.lastCompile={clock=os.clock(),chars=type(src)=="string" and #src or 0,chunk=clip(chunk,250),compiler=name};if type(fn)=="function" then sendDiag("loadstring_compile_ok",{sourceChars=S.lastCompile.chars,chunkName=S.lastCompile.chunk,compiler=name}) else status("ERRO DE COMPILACAO • "..clip(err,160),true);sendDiag("loadstring_compile_error",{sourceChars=S.lastCompile.chars,chunkName=S.lastCompile.chunk,compiler=name,error=err}) end;return fn,err end
 local ok=pcall(function() ENV[name]=repl;_G[name]=repl end);return ok and ENV[name]==repl,ok and "environment" or "none"
end
local okLoad,mode=installCompiler(ORIG_LOADSTRING,"loadstring");S.loadHook=okLoad;S.hookMode=okLoad and mode or "none"
if type(ORIG_LOAD)=="function" and ORIG_LOAD~=ORIG_LOADSTRING then installCompiler(ORIG_LOAD,"load") end

if type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" then
 local old
 local wrap=function(self,...) local m=getnamecallmethod();if m=="HttpGet" or m=="HttpGetAsync" then local a={...};local r=old(self,...);if type(r)=="string" and looksLua(r,a[1]) then observe(r,"httpget",a[1]) end;return r end;return old(self,...) end
 if type(newcclosure)=="function" then local ok,w=pcall(newcclosure,wrap);if ok and type(w)=="function" then wrap=w end end
 local ok,o=pcall(function() return hookmetamethod(game,"__namecall",wrap) end);if ok and type(o)=="function" then old=o;S.httpHook=true end
end

local function inspect(options,response)
 if not S.enabled or type(options)~="table" then return end
 local url=tostring(options.Url or options.URL or options.url or "");if url=="" or cafeUrl(url) then return end
 local low=string.lower(url);local code=0;local body="";if type(response)=="table" then code=tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0;body=tostring(response.Body or response.body or response.Data or "") end
 if low:find("/api/v1/validate",1,true) then local d;pcall(function() d=HttpService:JSONDecode(body) end);status("ScriptVerse validate • HTTP "..code,true);sendDiag("scriptverse_validate_response",{url=url,status=code,ok=type(d)=="table" and d.ok==true or false,valid=type(d)=="table" and d.valid==true or false,keyType=type(d)=="table" and d.keyType or nil,code=type(d)=="table" and d.code or nil,error=type(d)=="table" and d.error or nil});return end
 if low:find("/api/v1/script",1,true) then
  local d;local decoded=pcall(function() d=HttpService:JSONDecode(body) end);local hs=decoded and type(d)=="table" and type(d.script)=="string" and #d.script>1;local hu=decoded and type(d)=="table" and type(d.svui)=="string" and #d.svui>1
  status(string.format("ScriptVerse /script • HTTP %d • script=%s (%d)",code,hs and "SIM" or "NAO",hs and #d.script or 0),true)
  sendDiag("scriptverse_script_response",{url=url,status=code,jsonDecoded=decoded,hasScript=hs,scriptChars=hs and #d.script or 0,hasSvui=hu,svuiChars=hu and #d.svui or 0,name=decoded and type(d)=="table" and d.name or nil,error=decoded and type(d)=="table" and d.error or nil})
  if hs then observe(d.script,"api_script",url) end;if hu then observe(d.svui,"api_svui",url) end
 end
end
local candidates={}
local function add(label,fn,setter) if type(fn)=="function" then candidates[#candidates+1]={label=label,fn=fn,setter=setter} end end
add("request",rawget(ENV,"request"),function(v) ENV.request=v;_G.request=v end);add("http_request",rawget(ENV,"http_request"),function(v) ENV.http_request=v;_G.http_request=v end)
pcall(function() add("syn.request",syn and syn.request,function(v) syn.request=v end) end);pcall(function() add("http.request",http and http.request,function(v) http.request=v end) end);pcall(function() add("fluxus.request",fluxus and fluxus.request,function(v) fluxus.request=v end) end)
local hooked,hookN,replaceN={},{},{}
hookN=0;replaceN=0
for _,c in ipairs(candidates) do
 local installed=false
 if type(hookfunction)=="function" and hooked[c.fn] then installed=true elseif type(hookfunction)=="function" then local old;local wrap=function(o) local r=old(o);pcall(inspect,o,r);return r end;local ok,x=pcall(function() return hookfunction(c.fn,wrap) end);if ok and type(x)=="function" then old=x;hooked[c.fn]=true;installed=true;hookN=hookN+1 end end
 if not installed and type(c.setter)=="function" then local orig=c.fn;local repl=function(o) local r=orig(o);pcall(inspect,o,r);return r end;local ok=pcall(c.setter,repl);if ok then installed=true;replaceN=replaceN+1 end end
end
S.requestHook=(hookN+replaceN)>0;if hookN>0 and replaceN>0 then S.requestMode="mixed" elseif hookN>0 then S.requestMode="hook" elseif replaceN>0 then S.requestMode="replace" end

local function runtimeErr(msg,stack,source)
 if not S.enabled or not S.lastCompile then return end;local age=os.clock()-(S.lastCompile.clock or 0);if age>C.RUNTIME_WINDOW then return end
 status("ERRO RUNTIME APOS LOADSTRING • "..clip(msg,160),true);sendDiag("runtime_error_after_loadstring",{message=msg,stack=stack,source=source,secondsAfterCompile=math.floor(age*1000)/1000,sourceChars=S.lastCompile.chars,chunkName=S.lastCompile.chunk,compiler=S.lastCompile.compiler})
end
local sc=false
pcall(function() local ScriptContext=game:GetService("ScriptContext");local c=ScriptContext.Error:Connect(function(m,s,inst) local src="ScriptContext";pcall(function() if inst then src=inst:GetFullName() end end);runtimeErr(m,s,src) end);S.conns[#S.conns+1]=c;sc=true end)
if sc then S.runtime="ScriptContext" else pcall(function() local c=LogService.MessageOut:Connect(function(m,typ) if typ==Enum.MessageType.MessageError then runtimeErr(m,"","LogService") end end);S.conns[#S.conns+1]=c;S.runtime="LogService" end) end

local function stopAll() S.enabled=false;for _,c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end;S.conns={};status("PARADO • hooks ficam em pass-through sem coletar",true);stop.Text="PARADO" end
stop.MouseButton1Click:Connect(function() if S.enabled then stopAll() end end)
ENV.__CAFEINA_UNIVERSAL_CAPTURE={State=S,Stop=stopAll,GetCaptures=function() return S.items end,GetDiagnostics=function() return S.diag end}
refresh()
if not S.loadHook and not S.httpHook and not S.requestHook then status("ERRO • executor nao permitiu instalar hooks principais",true) else
 status(string.format("ARMADO ✓ • load=%s • HttpGet=%s • request=%s • verificando servidor...",S.hookMode,S.httpHook and "ON" or "OFF",S.requestHook and "ON" or "OFF"),true)
 sendDiag("capture_started",{loadHook=S.loadHook,loadMode=S.hookMode,httpHook=S.httpHook,requestHook=S.requestHook,requestHookMode=S.requestMode,requestHookCount=hookN+replaceN,runtimeObserver=S.runtime})
 task.spawn(function() local ok,e=health();if ok then status(string.format("ARMADO ✓ • SERVIDOR OK • GITHUB OK • load=%s • request=%s",S.hookMode,S.requestHook and "ON" or "OFF"),true) else status("ARMADO LOCALMENTE • servidor: "..tostring(e),true) end end)
end
