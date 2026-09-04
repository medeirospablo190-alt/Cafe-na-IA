-- GRUPO LUA — DELTA IMAGE DIAGNOSTIC V2
-- Testa duas rotas sem travar a interface:
-- 1) Drawing.new("Image") com bytes HTTP diretos
-- 2) getcustomasset usando nome de arquivo sem extensão, como o próprio Delta faz

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local IMAGE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/assets/grupo-lua-login.jpg"
local FILE_NAME = "delta_theme_image"

local function parentGui()
    local p
    pcall(function() if type(gethui) == "function" then p = gethui() end end)
    if not p then p = game:GetService("CoreGui") end
    if not p and LocalPlayer then p = LocalPlayer:WaitForChild("PlayerGui") end
    return p
end

local gui = Instance.new("ScreenGui")
gui.Name = "GrupoLuaImageDiag2"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = parentGui()

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(560,360)
frame.BackgroundColor3 = Color3.fromRGB(10,10,12)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner",frame).CornerRadius = UDim.new(0,14)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,34)
title.Position = UDim2.fromOffset(10,8)
title.BackgroundTransparency = 1
title.Text = "GRUPO LUA • TESTE DELTA V2"
title.TextColor3 = Color3.fromRGB(245,245,245)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local log = Instance.new("TextLabel")
log.Size = UDim2.new(1,-20,0,230)
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

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-20,0,56)
status.Position = UDim2.fromOffset(10,292)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(235,235,235)
status.Font = Enum.Font.GothamBold
status.TextSize = 13
status.TextWrapped = true
status.Text = ""
status.Parent = frame

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
add("Drawing", type(Drawing))
add("Drawing.new", type(Drawing)=="table" and type(Drawing.new) or "nil")
add("request", type(req))
add("writefile", type(writefile))
add("getcustomasset", type(getcustomasset))

local body
if req then
    local ok,res = pcall(req,{Url=IMAGE_URL,Method="GET",Headers={Accept="image/jpeg,image/*,*/*"}})
    add("request call", ok)
    if ok and type(res)=="table" then
        local statusCode = res.StatusCode or res.status_code or res.status or res.Status
        body = res.Body or res.body or res.ResponseBody or res.responseBody or res.data
        add("HTTP status", statusCode or "nil")
        add("body bytes", type(body)=="string" and #body or 0)
    else
        add("request error", tostring(res))
    end
end

-- Teste 1: Drawing.Image com bytes diretos
local drawingDone = false
local drawingSuccess = false
local drawingError = nil
local drawingImage

task.spawn(function()
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
        drawingError = "Drawing indisponível"
        drawingDone = true
        return
    end
    if type(body) ~= "string" or #body < 100 then
        drawingError = "bytes da imagem indisponíveis"
        drawingDone = true
        return
    end

    local ok,err = pcall(function()
        drawingImage = Drawing.new("Image")
        drawingImage.Data = body
        drawingImage.Position = Vector2.new(50, 80)
        drawingImage.Size = Vector2.new(300, 150)
        drawingImage.Transparency = 1
        drawingImage.Visible = true
    end)
    drawingSuccess = ok
    drawingError = ok and nil or tostring(err)
    drawingDone = true
end)

-- Teste 2: exatamente o padrão usado pelo próprio Delta: arquivo sem extensão
local assetDone = false
local assetSuccess = false
local assetResult = nil
local assetError = nil

task.spawn(function()
    if type(body) ~= "string" or #body < 100 then
        assetError = "bytes da imagem indisponíveis"
        assetDone = true
        return
    end
    if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then
        assetError = "funções indisponíveis"
        assetDone = true
        return
    end

    pcall(function()
        if type(isfile)=="function" and type(delfile)=="function" and isfile(FILE_NAME) then
            delfile(FILE_NAME)
        end
    end)

    local wok,werr = pcall(writefile, FILE_NAME, body)
    add("write extensionless", wok)
    if not wok then
        assetError = tostring(werr)
        assetDone = true
        return
    end

    local ok,res = pcall(getcustomasset, FILE_NAME)
    assetSuccess = ok and type(res)=="string" and res~=""
    assetResult = res
    assetError = ok and nil or tostring(res)
    assetDone = true
end)

for i=1,8 do
    task.wait(1)
    status.Text = string.format(
        "Drawing: %s  |  getcustomasset sem extensão: %s  |  %ds",
        drawingDone and (drawingSuccess and "OK" or "FALHOU") or "TESTANDO",
        assetDone and (assetSuccess and "OK" or "FALHOU") or "TESTANDO",
        i
    )
end

add("Drawing final", drawingDone and (drawingSuccess and "OK" or ("FALHOU - "..tostring(drawingError))) or "TRAVOU")
add("asset final", assetDone and (assetSuccess and ("OK - "..tostring(assetResult)) or ("FALHOU - "..tostring(assetError))) or "TRAVOU")

if drawingSuccess then
    status.Text = "Se a foto apareceu no canto superior esquerdo, podemos usar Drawing no login."
elseif assetSuccess then
    status.Text = "getcustomasset funcionou sem extensão. Posso adaptar o login para esse formato."
else
    status.Text = "As duas rotas falharam/travaram. Nesse build do Delta, use rbxassetid para imagem garantida."
end
