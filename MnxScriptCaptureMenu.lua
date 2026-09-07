-- CAFEINA • MNX CAPTURE V1 • mobile/executor • PlaceId 138686218420016
-- Captura original -> envia ao Render/GitHub -> altera SOMENTE o final MNX ->
-- envia patched -> executa o decodificador -> captura gnJOnhd0f -> envia deobf.

local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV=(getgenv and getgenv()) or _G

local C={
 V="CAFEINA_MNX_CAPTURE_V1", PLACE=138686218420016,
 POST="https://cafe-na-ia.onrender.com/api/inventory-trace",
 HEALTH="https://cafe-na-ia.onrender.com/api/inventory-trace/health",
 JSON_MAX=4700000, CHUNK=120000, RETRIES=3,
}
if game.PlaceId~=C.PLACE then warn("[MNX] PlaceId bloqueado",game.PlaceId) return end

local function firstfn(...)
 for i=1,select("#",...) do local v=select(i,...); if type(v)=="function" then return v end end
end
local synReq,httpReq,fluxReq
pcall(function() if syn and type(syn.request)=="function" then synReq=syn.request end end)
pcall(function() if http and type(http.request)=="function" then httpReq=http.request end end)
pcall(function() if fluxus and type(fluxus.request)=="function" then fluxReq=fluxus.request end end)
local REQUEST=firstfn(rawget(ENV,"request"),rawget(ENV,"http_request"),httpReq,synReq,fluxReq)
local WRITE=firstfn(rawget(ENV,"writefile"),writefile)
local GETCLIP=firstfn(rawget(ENV,"getclipboard"),getclipboard)
local SETCLIP=firstfn(rawget(ENV,"setclipboard"),setclipboard)

local S={busy=false,render=false,github=false,original=nil,patched=nil,deobf=nil,status="Aguardando script.",err=nil,lastFile=nil}
local MARK="local yjPoJ8HYWs,art2yjeMs=loadstring(gnJOnhd0f)"
local SIG="Mnx | Public Enemy"
local REPL=[=[print("========== MNX PAYLOAD ==========")
print(gnJOnhd0f)
print("=================================")

if writefile then
    writefile(
        "MNX_DUPE_DEOBF.lua",
        gnJOnhd0f
    )

    print(
        "Payload salvo em MNX_DUPE_DEOBF.lua"
    )
end

if setclipboard then
    setclipboard(gnJOnhd0f)

    print(
        "Payload também foi copiado."
    )
end

return gnJOnhd0f
]=]

local function iso()
 local ok,v=pcall(function() return DateTime.now():ToIsoDate() end)
 return ok and v or os.date("!%Y-%m-%dT%H:%M:%SZ")
end
local function req(o)
 if not REQUEST then return false,nil,"request/http_request indisponível" end
 local ok,r=pcall(REQUEST,o); if not ok or not r then return false,nil,tostring(r) end
 local code=tonumber(r.StatusCode or r.Status or r.status_code or r.status) or 0
 local body=tostring(r.Body or r.body or "")
 return code>=200 and code<300,{status=code,body=body},nil
end
local function health()
 S.status="Verificando Render/GitHub..."
 local ok,r,e=req({Url=C.HEALTH,Method="GET",Headers={Accept="application/json",["Cache-Control"]="no-cache"}})
 if not ok then S.render=false;S.github=false;S.err=e or (r and "HTTP "..r.status) or "health falhou";return false end
 local d;pcall(function() d=HttpService:JSONDecode(r.body) end)
 S.render=type(d)=="table" and d.ok==true
 S.github=S.render and d.githubMirrorConfigured==true
 if not S.render then S.err="Health inválido" return false end
 if not S.github then S.err="GitHub mirror não configurado no Render" return false end
 S.err=nil;S.status="Render OK • GitHub mirror OK";return true
end
local function save(kind,src)
 if not WRITE then return end
 local n=kind=="original" and "MNX_DUPE_ORIGINAL.lua" or kind=="patched" and "MNX_DUPE_PATCHED.lua" or "MNX_DUPE_DEOBF.lua"
 pcall(WRITE,n,src)
end
local function records(kind,src)
 local out,total={},math.max(1,math.ceil(#src/C.CHUNK))
 for i=1,total do
  local a=(i-1)*C.CHUNK+1; local b=math.min(#src,i*C.CHUNK)
  out[#out+1]={kind="script_source_chunk",stage=kind,index=i,total=total,data=src:sub(a,b)}
 end
 return out
end
local function send(kind,src)
 local rid=string.format("MNX_CAPTURE_%s_%d_%d",kind:upper(),os.time(),math.random(100000,999999))
 local p={schemaVersion=1,userId=tostring(LP.UserId),username=tostring(LP.Name),capturedAt=iso(),placeId=game.PlaceId,gameId=game.GameId,runId=rid,
  trace={version=C.V,runId=rid,stage=kind,sourceChars=#src,startedAt=os.time(),finishedAt=os.time(),remotes={},records=records(kind,src)}}
 local ok,j=pcall(function() return HttpService:JSONEncode(p) end);if not ok then return false,"JSONEncode falhou" end
 if #j>C.JSON_MAX then return false,string.format("JSON %.2f MB excede limite seguro %.2f MB",#j/1e6,C.JSON_MAX/1e6) end
 local last="falha HTTP"
 for n=1,C.RETRIES do
  S.status=string.format("Enviando %s %d/%d...",kind,n,C.RETRIES)
  local yes,r,e=req({Url=C.POST,Method="POST",Headers={["Content-Type"]="application/json",Accept="application/json",["User-Agent"]="Cafeina-MNX-Capture/1.0"},Body=j})
  if yes and r then
   local d;pcall(function() d=HttpService:JSONDecode(r.body) end)
   if type(d)=="table" and d.ok==true then
    if type(d.github)=="table" and d.github.mirrored==true then S.lastFile=d.file;return true,d end
    last="Render recebeu, mas GitHub não confirmou mirror"
   else last="Resposta do Render sem confirmação" end
  else last=e or (r and "HTTP "..r.status) or last end
  if n<C.RETRIES then task.wait(1.25*n) end
 end
 return false,last
end

local function trim(x) return tostring(x or ""):match("^%s*(.-)%s*$") or "" end
local function sourceFrom(x)
 x=tostring(x or ""); if trim(x)=="" then return nil,"Entrada vazia" end
 local u=trim(x):match("^(https?://.+)$")
  or x:match('game%s*:%s*HttpGet%s*%(%s*"(https?://[^"]+)"')
  or x:match("game%s*:%s*HttpGet%s*%(%s*'(https?://[^']+)'")
 if u then
  S.status="Baixando script original...";local ok,v=pcall(function() return game:HttpGet(u) end)
  if not ok or type(v)~="string" or v=="" then return nil,"HttpGet falhou: "..tostring(v) end
  return v
 end
 return x
end
local function capture(x)
 if S.busy then return end
 local src,e=sourceFrom(x);if not src then S.err=e;S.status="Falha ao capturar";return end
 S.original=src;S.patched=nil;S.deobf=nil;S.err=nil;save("original",src)
 S.status=string.format("Original capturado • %d chars • final MNX: %s",#src,src:find(MARK,1,true) and "ACHADO" or "NÃO ACHADO")
end
local function patch(src)
 local a=src:find(MARK,1,true);if not a then return nil,"Bloco final MNX não encontrado" end
 if src:find(MARK,a+#MARK,true) then return nil,"Marcador final duplicado; cancelado" end
 local tail=src:sub(a);if not tail:find(SIG,1,true) then return nil,"Assinatura MNX ausente no bloco final" end
 local out=src:sub(1,a-1)..REPL
 if out:find("loadstring(gnJOnhd0f)",1,true) then return nil,"loadstring do payload ainda presente" end
 return out
end
local function decode(src)
 if type(loadstring)~="function" then return nil,"loadstring indisponível" end
 local f,e=loadstring(src);if not f then return nil,"Patched não compilou: "..tostring(e) end
 local ok,v=pcall(f);if not ok then return nil,"Decodificador falhou: "..tostring(v) end
 if type(v)~="string" or v=="" then return nil,"MNX não retornou gnJOnhd0f como string" end
 return v
end
local function process()
 if S.busy then return end;if not S.original then S.status="Capture o script primeiro" return end
 S.busy=true;S.err=nil
 local function fail(e) S.err=tostring(e);S.status="ERRO • "..S.err;S.busy=false end
 if not health() then return fail(S.err or S.status) end
 save("original",S.original)
 local ok,r=send("original",S.original);if not ok then return fail(r) end
 S.status="Original no GitHub ✓ • alterando final..."
 local p,e=patch(S.original);if not p then return fail(e) end;S.patched=p;save("patched",p)
 ok,r=send("patched",p);if not ok then return fail(r) end
 S.status="Patched no GitHub ✓ • executando só o decodificador..."
 local d;d,e=decode(p);if not d then return fail(e) end;S.deobf=d;save("deobfuscated",d)
 ok,r=send("deobfuscated",d);if not ok then return fail(r) end
 if SETCLIP then pcall(SETCLIP,d) end
 S.status=string.format("CONCLUÍDO ✓ • deobf %d chars • GitHub OK",#d);S.err=nil;S.busy=false
end

pcall(function() local old=rawget(ENV,"__CAFEINA_MNX_CAPTURE_GUI");if old then old:Destroy() end end)
local parent=CoreGui;pcall(function() if gethui then parent=gethui() end end)
local gui=Instance.new("ScreenGui");gui.Name="CafeinaMnxCaptureV1";gui.ResetOnSpawn=false;gui.Parent=parent;ENV.__CAFEINA_MNX_CAPTURE_GUI=gui
local f=Instance.new("Frame");f.Size=UDim2.fromOffset(310,330);f.Position=UDim2.fromOffset(10,72);f.BackgroundColor3=Color3.fromRGB(15,15,18);f.BorderSizePixel=0;f.Active=true;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,12)
local title=Instance.new("TextLabel");title.Size=UDim2.new(1,-72,0,30);title.Position=UDim2.fromOffset(10,6);title.BackgroundTransparency=1;title.Text="CAFEINA • MNX CAPTURE";title.TextColor3=Color3.new(1,1,1);title.TextSize=12;title.Font=Enum.Font.GothamBold;title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=f
local min=Instance.new("TextButton");min.Size=UDim2.fromOffset(52,26);min.Position=UDim2.new(1,-60,0,6);min.BackgroundColor3=Color3.fromRGB(42,42,48);min.BorderSizePixel=0;min.Text="MIN";min.TextColor3=Color3.new(1,1,1);min.TextSize=10;min.Font=Enum.Font.GothamBold;min.Parent=f;Instance.new("UICorner",min).CornerRadius=UDim.new(0,7)
local box=Instance.new("TextBox");box.Size=UDim2.new(1,-20,0,78);box.Position=UDim2.fromOffset(10,40);box.BackgroundColor3=Color3.fromRGB(25,25,30);box.BorderSizePixel=0;box.ClearTextOnFocus=false;box.MultiLine=true;box.TextXAlignment=Enum.TextXAlignment.Left;box.TextYAlignment=Enum.TextYAlignment.Top;box.PlaceholderText="Cole URL, loader HttpGet ou script completo";box.Text="";box.TextColor3=Color3.fromRGB(235,235,235);box.PlaceholderColor3=Color3.fromRGB(125,125,135);box.TextSize=10;box.Font=Enum.Font.Code;box.Parent=f;Instance.new("UICorner",box).CornerRadius=UDim.new(0,8)
local function btn(txt,x,y,w,bg)local b=Instance.new("TextButton");b.Size=UDim2.new(w,-15,0,34);b.Position=UDim2.new(x,10,0,y);b.BackgroundColor3=bg;b.BorderSizePixel=0;b.Text=txt;b.TextColor3=Color3.new(1,1,1);b.TextSize=10;b.Font=Enum.Font.GothamBold;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,8);return b end
local clip=btn("CLIPBOARD",0,126,.5,Color3.fromRGB(45,52,70));clip.Size=UDim2.new(.5,-15,0,34)
local cap=btn("CAPTURAR CAMPO",.5,126,.5,Color3.fromRGB(55,55,65));cap.Position=UDim2.new(.5,5,0,126);cap.Size=UDim2.new(.5,-15,0,34)
local go=btn("ENVIAR → PATCH → EXTRAIR",0,168,1,Color3.fromRGB(115,30,35));go.Size=UDim2.new(1,-20,0,34)
local st=Instance.new("TextLabel");st.Size=UDim2.new(1,-20,0,104);st.Position=UDim2.fromOffset(10,210);st.BackgroundTransparency=1;st.TextWrapped=true;st.TextColor3=Color3.fromRGB(215,215,220);st.TextSize=10;st.Font=Enum.Font.Gotham;st.TextXAlignment=Enum.TextXAlignment.Left;st.TextYAlignment=Enum.TextYAlignment.Top;st.Parent=f
local mini=Instance.new("TextButton");mini.Size=UDim2.fromOffset(88,40);mini.Position=f.Position;mini.BackgroundColor3=Color3.fromRGB(18,18,22);mini.BorderSizePixel=0;mini.Text="MNX CAPTURE";mini.TextColor3=Color3.new(1,1,1);mini.TextSize=9;mini.Font=Enum.Font.GothamBold;mini.Visible=false;mini.Parent=gui;Instance.new("UICorner",mini).CornerRadius=UDim.new(0,10)
min.MouseButton1Click:Connect(function() f.Visible=false;mini.Visible=true end);mini.MouseButton1Click:Connect(function() mini.Visible=false;f.Visible=true end)
clip.MouseButton1Click:Connect(function() if not GETCLIP then S.err="getclipboard indisponível" return end;local ok,v=pcall(GETCLIP);if ok then capture(v) else S.err=tostring(v) end end)
cap.MouseButton1Click:Connect(function() capture(box.Text) end);go.MouseButton1Click:Connect(function() task.spawn(process) end)
local dragging=false;local ds,sp;title.Active=true
title.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;ds=i.Position;sp=f.Position end end)
title.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
UIS.InputChanged:Connect(function(i)if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y);mini.Position=f.Position end end)
task.spawn(function()while gui.Parent do st.Text=string.format("Original: %d • Patched: %d • Deobf: %d\nRender: %s • GitHub: %s\n%s%s%s",S.original and #S.original or 0,S.patched and #S.patched or 0,S.deobf and #S.deobf or 0,S.render and "OK" or "?",S.github and "OK" or "?",S.status,S.lastFile and ("\nArquivo: "..S.lastFile) or "",S.err and ("\nErro: "..S.err) or "");go.Text=S.busy and "PROCESSANDO..." or "ENVIAR → PATCH → EXTRAIR";task.wait(.2) end end)
ENV.__CAFEINA_MNX_CAPTURE_V1={State=S,Capture=capture,Patch=patch,Process=process,Health=health}
task.spawn(health)
print("[MNX CAPTURE] V1 carregado")
