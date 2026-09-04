-- GRUPO LUA — DELTA IMAGE DIAGNOSTIC
-- Mostra na própria tela onde o carregamento da imagem está falhando.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local IMAGE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/assets/grupo-lua-login.jpg"
local FILE_NAME = "grupo_lua_diag.jpg"

local function parentGui()
    local p
    pcall(function() if type(gethui) == "function" then p = gethui() end end)
    if not p then p = game:GetService("CoreGui") end
    if not p and LocalPlayer then p = LocalPlayer:WaitForChild("PlayerGui") end
    return p
end

local gui = Instance.new("ScreenGui")
gui.Name = "GrupoLuaImageDiag"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = parentGui()

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(520,330)
frame.BackgroundColor3 = Color3.fromRGB(10,10,12)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner",frame).CornerRadius = UDim.new(0,14)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,34)
title.Position = UDim2.fromOffset(10,8)
title.BackgroundTransparency = 1
title.Text = "GRUPO LUA • TESTE DE IMAGEM DELTA"
title.TextColor3 = Color3.fromRGB(245,245,245)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local log = Instance.new("TextLabel")
log.Size = UDim2.new(1,-20,0,180)
log.Position = UDim2.fromOffset(10,48)
log.BackgroundColor3 = Color3.fromRGB(18,18,20)
log.BorderSizePixel = 0
log.Text = "Iniciando..."
log.TextColor3 = Color3.fromRGB(225,225,225)
log.Font = Enum.Font.Code
log.TextSize = 12
log.TextWrapped = true
log.TextXAlignment = Enum.TextXAlignment.Left
log.TextYAlignment = Enum.TextYAlignment.Top
log.Parent = frame
Instance.new("UICorner",log).CornerRadius = UDim.new(0,10)

local preview = Instance.new("ImageLabel")
preview.Size = UDim2.fromOffset(180,80)
preview.Position = UDim2.new(.5,-90,1,-92)
preview.BackgroundColor3 = Color3.fromRGB(30,30,32)
preview.BorderSizePixel = 0
preview.ScaleType = Enum.ScaleType.Fit
preview.Parent = frame
Instance.new("UICorner",preview).CornerRadius = UDim.new(0,8)

local lines = {}
local function add(k,v)
    lines[#lines+1] = tostring(k)..": "..tostring(v)
    log.Text = table.concat(lines,"\n")
end

local req
if type(request)=="function" then req=request
elseif type(http_request)=="function" then req=http_request
elseif type(syn)=="table" and type(syn.request)=="function" then req=syn.request
elseif type(fluxus)=="table" and type(fluxus.request)=="function" then req=fluxus.request end

add("executor", (type(identifyexecutor)=="function" and tostring(select(1,identifyexecutor()))) or "desconhecido")
add("request", type(req))
add("writefile", type(writefile))
add("readfile", type(readfile))
add("isfile", type(isfile))
add("getcustomasset", type(getcustomasset))
add("getsynasset", type(getsynasset))
add("getasset", type(getasset))

local body
local status
if req then
    local ok,res = pcall(req,{Url=IMAGE_URL,Method="GET",Headers={Accept="image/jpeg,image/*,*/*"}})
    add("request call", ok)
    if ok and type(res)=="table" then
        status = res.StatusCode or res.status_code or res.status or res.Status
        body = res.Body or res.body or res.ResponseBody or res.responseBody or res.data
        add("HTTP status", status or "nil")
        add("body type", type(body))
        add("body bytes", type(body)=="string" and #body or 0)
    else
        add("request error", tostring(res))
    end
else
    local ok,res = pcall(function() return game:HttpGet(IMAGE_URL,true) end)
    add("HttpGet call", ok)
    if ok then body=res; add("body bytes", type(body)=="string" and #body or 0) end
end

if type(body)=="string" and #body>100 and type(writefile)=="function" then
    local ok,err = pcall(writefile,FILE_NAME,body)
    add("writefile call", ok)
    if not ok then add("write error", err) end
else
    add("writefile call", "não executado")
end

if type(isfile)=="function" then
    local ok,res = pcall(isfile,FILE_NAME)
    add("isfile result", ok and res or "erro")
end

if type(readfile)=="function" then
    local ok,res = pcall(readfile,FILE_NAME)
    add("readfile bytes", ok and type(res)=="string" and #res or 0)
end

local assetFn
if type(getcustomasset)=="function" then assetFn=getcustomasset
elseif type(getsynasset)=="function" then assetFn=getsynasset
elseif type(getasset)=="function" then assetFn=getasset
elseif type(customasset)=="function" then assetFn=customasset end

if assetFn then
    local ok,res = pcall(assetFn,FILE_NAME)
    add("asset call", ok)
    add("asset result", ok and tostring(res) or tostring(res))
    if ok and res then
        preview.Image = res
        task.wait(4)
        add("ImageLabel.IsLoaded", preview.IsLoaded)
        add("ImageRect", tostring(preview.AbsoluteSize))
    end
else
    add("asset call", "SEM FUNÇÃO")
end

add("fim", "mande print desta tela")
