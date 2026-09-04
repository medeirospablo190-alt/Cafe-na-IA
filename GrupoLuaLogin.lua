--[[
    GRUPO LUA — LOGIN V12 / BASE ESTÁVEL

    Visual mobile:
      • imagem Roblox: rbxassetid://91124214069969
      • painel 520 x 260
      • campo da chave muito transparente, inclusive ao tocar
      • botão VERIFICAR transparente, sem preenchimento vermelho
      • X vermelho no canto superior direito
      • painel arrastável e com escala automática

    Acesso:
      • FREE/VIP são validadas pela Control API
      • a chave fica vinculada ao primeiro aparelho no servidor
      • a chave digitada nunca é salva em arquivo
      • somente o token da sessão é persistido por menu
      • enquanto a sessão for válida, o menu abre sem pedir a chave novamente

    Loader de um menu:
      getgenv().GRUPO_LUA_MENU_ID = "menu_xxxxx"
      loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaLogin.lua"))()
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    API_BASE = "https://grupo-lua-control-api.onrender.com",
    IMAGE_ASSET = "rbxassetid://91124214069969",
    WIDTH = 520,
    HEIGHT = 260,
}

local COLORS = {
    WHITE = Color3.fromRGB(245, 245, 247),
    MUTED = Color3.fromRGB(225, 225, 230),
    RED = Color3.fromRGB(235, 42, 38),
    GREEN = Color3.fromRGB(92, 220, 125),
    DARK = Color3.fromRGB(6, 6, 8),
}

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

local MENU_ID = tostring(ENV.GRUPO_LUA_MENU_ID or "__MENU_ID__")
local SAFE_MENU_ID = MENU_ID:gsub("[^%w_%-]", "_")
local DEVICE_FILE = "grupo_lua_device_id_v1.txt"
local SESSION_FILE = "grupo_lua_session_" .. SAFE_MENU_ID .. ".json"

local function findRequest()
    if type(request) == "function" then
        return request
    end
    if type(http_request) == "function" then
        return http_request
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        return syn.request
    end
    if type(fluxus) == "table" and type(fluxus.request) == "function" then
        return fluxus.request
    end
    return nil
end

local Request = findRequest()

local function rawRequest(options)
    if Request then
        local ok, response = pcall(Request, options)
        if not ok then
            return false, nil, tostring(response)
        end
        if not response then
            return false, nil, "Resposta HTTP vazia."
        end

        local status = tonumber(response.StatusCode or response.Status or 0) or 0
        return status >= 200 and status < 300, response, nil
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync(options)
    end)
    if not ok then
        return false, nil, tostring(response)
    end

    return response.Success == true, response, nil
end

local function jsonRequest(method, url, body, headers)
    local finalHeaders = {
        ["Accept"] = "application/json",
    }

    if body ~= nil then
        finalHeaders["Content-Type"] = "application/json"
    end

    for key, value in pairs(headers or {}) do
        finalHeaders[key] = value
    end

    local options = {
        Url = url,
        Method = method,
        Headers = finalHeaders,
    }

    if body ~= nil then
        local encodeOK, encoded = pcall(function()
            return HttpService:JSONEncode(body)
        end)
        if not encodeOK then
            return false, nil, 0, "Falha ao preparar requisição."
        end
        options.Body = encoded
    end

    local requestOK, response, requestError = rawRequest(options)
    if not response then
        return false, nil, 0, requestError or "Sem resposta do servidor."
    end

    local status = tonumber(response.StatusCode or response.Status or 0) or 0
    local responseBody = response.Body or ""
    local decoded

    if responseBody ~= "" then
        pcall(function()
            decoded = HttpService:JSONDecode(responseBody)
        end)
    end

    return requestOK, decoded, status, requestError
end

local function downloadText(url)
    if Request then
        local ok, response = rawRequest({
            Url = url,
            Method = "GET",
            Headers = {
                ["Accept"] = "text/plain,*/*",
            },
        })
        if ok and response and type(response.Body) == "string" and response.Body ~= "" then
            return true, response.Body
        end
    end

    local ok, result = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and type(result) == "string" and result ~= "" then
        return true, result
    end

    return false, "Não foi possível baixar o menu."
end

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and name then
            return tostring(name)
        end
    end
    return "Executor"
end

local function clientLabel()
    local pieces = { executorName() }
    if LocalPlayer then
        pieces[#pieces + 1] = "UID:" .. tostring(LocalPlayer.UserId)
    end
    return table.concat(pieces, " | ")
end

local function safeReadFile(path)
    if type(readfile) ~= "function" then
        return nil
    end
    local ok, value = pcall(readfile, path)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function safeWriteFile(path, value)
    if type(writefile) ~= "function" then
        return false
    end
    return pcall(writefile, path, tostring(value or ""))
end

local function safeDeleteFile(path)
    if type(delfile) == "function" then
        pcall(delfile, path)
    end
end

local function resolveDeviceId()
    local forced = tostring(ENV.GRUPO_LUA_DEVICE_ID or "")
    if forced ~= "" then
        return forced
    end

    if type(gethwid) == "function" then
        local ok, value = pcall(gethwid)
        if ok and type(value) == "string" and value ~= "" then
            ENV.GRUPO_LUA_DEVICE_ID = value
            return value
        end
    end

    local okAnalytics, analyticsId = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    if okAnalytics and type(analyticsId) == "string" and analyticsId ~= "" then
        ENV.GRUPO_LUA_DEVICE_ID = analyticsId
        return analyticsId
    end

    local saved = safeReadFile(DEVICE_FILE)
    if saved then
        ENV.GRUPO_LUA_DEVICE_ID = saved
        return saved
    end

    local generated = HttpService:GenerateGUID(false)
    ENV.GRUPO_LUA_DEVICE_ID = generated
    safeWriteFile(DEVICE_FILE, generated)
    return generated
end

local DEVICE_ID = resolveDeviceId()

local function saveMenuSession(token, expiresAt, keyType)
    if type(token) ~= "string" or token == "" then
        return
    end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            menuId = MENU_ID,
            token = token,
            expiresAt = expiresAt,
            keyType = keyType,
        })
    end)

    if ok and encoded then
        safeWriteFile(SESSION_FILE, encoded)
    end
end

local function readMenuSession()
    local raw = safeReadFile(SESSION_FILE)
    if not raw then
        return nil
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not ok or type(data) ~= "table" then
        return nil
    end
    if tostring(data.menuId or "") ~= MENU_ID then
        return nil
    end
    if type(data.token) ~= "string" or data.token == "" then
        return nil
    end

    return data
end

local function clearMenuSession()
    safeDeleteFile(SESSION_FILE)
end

local Parent
pcall(function()
    if type(gethui) == "function" then
        Parent = gethui()
    end
end)

if not Parent then
    local ok, core = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok then
        Parent = core
    end
end

if not Parent and LocalPlayer then
    Parent = LocalPlayer:WaitForChild("PlayerGui")
end

assert(Parent, "[GRUPO LUA] Não foi possível criar a interface.")

local old = Parent:FindFirstChild("GrupoLuaAccess")
if old then
    old:Destroy()
end

local function corner(object, radius)
    local ui = Instance.new("UICorner")
    ui.CornerRadius = UDim.new(0, radius)
    ui.Parent = object
    return ui
end

local function tween(object, properties, duration)
    if not object or not object.Parent then
        return
    end
    TweenService:Create(
        object,
        TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        properties
    ):Play()
end

local GUI = Instance.new("ScreenGui")
GUI.Name = "GrupoLuaAccess"
GUI.IgnoreGuiInset = true
GUI.ResetOnSpawn = false
GUI.DisplayOrder = 999999
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = Parent

local Overlay = Instance.new("Frame")
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.BackgroundColor3 = Color3.new(0, 0, 0)
Overlay.BackgroundTransparency = 0.52
Overlay.BorderSizePixel = 0
Overlay.Parent = GUI

local Shell = Instance.new("Frame")
Shell.Name = "Shell"
Shell.AnchorPoint = Vector2.new(0.5, 0.5)
Shell.Position = UDim2.fromScale(0.5, 0.5)
Shell.Size = UDim2.fromOffset(CONFIG.WIDTH + 2, CONFIG.HEIGHT + 2)
Shell.BackgroundColor3 = Color3.fromRGB(100, 100, 106)
Shell.BackgroundTransparency = 0.35
Shell.BorderSizePixel = 0
Shell.Parent = Overlay
corner(Shell, 18)

local Main = Instance.new("Frame")
Main.Position = UDim2.fromOffset(1, 1)
Main.Size = UDim2.new(1, -2, 1, -2)
Main.BackgroundColor3 = COLORS.DARK
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = Shell
corner(Main, 17)

local Background = Instance.new("ImageLabel")
Background.Name = "Background"
Background.Size = UDim2.fromScale(1, 1)
Background.BackgroundTransparency = 1
Background.BorderSizePixel = 0
Background.Image = CONFIG.IMAGE_ASSET
Background.ScaleType = Enum.ScaleType.Fit
Background.ZIndex = 1
Background.Parent = Main

task.spawn(function()
    pcall(function()
        ContentProvider:PreloadAsync({ Background })
    end)
end)

local CloseButton = Instance.new("TextButton")
CloseButton.Name = "CloseButton"
CloseButton.AnchorPoint = Vector2.new(0.5, 0.5)
CloseButton.Position = UDim2.new(1, -20, 0, 20)
CloseButton.Size = UDim2.fromOffset(30, 30)
CloseButton.BackgroundTransparency = 1
CloseButton.BorderSizePixel = 0
CloseButton.Text = "×"
CloseButton.TextColor3 = COLORS.RED
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 27
CloseButton.AutoButtonColor = false
CloseButton.ZIndex = 30
CloseButton.Parent = Main

CloseButton.MouseButton1Click:Connect(function()
    if GUI and GUI.Parent then
        GUI:Destroy()
    end
end)

local InputBorder = Instance.new("Frame")
InputBorder.AnchorPoint = Vector2.new(0.5, 0.5)
InputBorder.Position = UDim2.new(0.5, 0, 0.60, 0)
InputBorder.Size = UDim2.fromOffset(260, 43)
InputBorder.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
InputBorder.BackgroundTransparency = 0.76
InputBorder.BorderSizePixel = 0
InputBorder.ZIndex = 5
InputBorder.Parent = Main
corner(InputBorder, 10)

local InputHolder = Instance.new("Frame")
InputHolder.Position = UDim2.fromOffset(1, 1)
InputHolder.Size = UDim2.new(1, -2, 1, -2)
InputHolder.BackgroundColor3 = COLORS.DARK
InputHolder.BackgroundTransparency = 0.93
InputHolder.BorderSizePixel = 0
InputHolder.ZIndex = 6
InputHolder.Parent = InputBorder
corner(InputHolder, 9)

local KeyBox = Instance.new("TextBox")
KeyBox.Position = UDim2.fromOffset(12, 0)
KeyBox.Size = UDim2.new(1, -24, 1, 0)
KeyBox.BackgroundTransparency = 1
KeyBox.Text = ""
KeyBox.PlaceholderText = "Digite sua chave"
KeyBox.PlaceholderColor3 = Color3.fromRGB(230, 230, 235)
KeyBox.TextColor3 = COLORS.WHITE
KeyBox.TextXAlignment = Enum.TextXAlignment.Center
KeyBox.Font = Enum.Font.GothamMedium
KeyBox.TextSize = 12
KeyBox.ClearTextOnFocus = false
KeyBox.ZIndex = 7
KeyBox.Parent = InputHolder

local Verify = Instance.new("TextButton")
Verify.AnchorPoint = Vector2.new(0.5, 0.5)
Verify.Position = UDim2.new(0.5, 0, 0.80, 0)
Verify.Size = UDim2.fromOffset(260, 39)
Verify.BackgroundColor3 = COLORS.DARK
Verify.BackgroundTransparency = 0.90
Verify.BorderSizePixel = 0
Verify.Text = "VERIFICAR"
Verify.TextColor3 = COLORS.WHITE
Verify.Font = Enum.Font.GothamBold
Verify.TextSize = 11
Verify.AutoButtonColor = false
Verify.ZIndex = 5
Verify.Parent = Main
corner(Verify, 9)

local VerifyStroke = Instance.new("UIStroke")
VerifyStroke.Color = Color3.fromRGB(235, 235, 240)
VerifyStroke.Transparency = 0.45
VerifyStroke.Thickness = 1
VerifyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
VerifyStroke.Parent = Verify

local DEFAULT_BUTTON_TEXT = "VERIFICAR"
local Busy = false

local function setButton(text, color)
    if not Verify or not Verify.Parent then
        return
    end
    Verify.Text = tostring(text or DEFAULT_BUTTON_TEXT)
    Verify.TextColor3 = color or COLORS.WHITE
end

local function temporaryButton(text, color, seconds)
    setButton(text, color)
    task.delay(seconds or 1.4, function()
        if Verify and Verify.Parent and not Busy then
            setButton(DEFAULT_BUTTON_TEXT, COLORS.WHITE)
        end
    end)
end

KeyBox.Focused:Connect(function()
    tween(InputBorder, {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.66,
    })
end)

KeyBox.FocusLost:Connect(function()
    tween(InputBorder, {
        BackgroundColor3 = Color3.fromRGB(235, 235, 240),
        BackgroundTransparency = 0.76,
    })
end)

local function apiErrorText(data, status)
    local code = type(data) == "table" and tostring(data.code or "") or ""

    if code == "INVALID_MENU_KEY" then
        return "CHAVE INVÁLIDA"
    elseif code == "VIP_EXPIRED" or code == "MENU_KEY_EXPIRED" then
        return "CHAVE EXPIRADA"
    elseif code == "FREE_REQUIRES_ADMIN" then
        return "AGUARDA LIBERAÇÃO ADM"
    elseif code == "DEVICE_NOT_AUTHORIZED" then
        return "CHAVE EM OUTRO CELULAR"
    elseif code == "DEVICE_ID_REQUIRED" then
        return "APARELHO NÃO IDENTIFICADO"
    elseif code == "MENU_SUSPENDED" then
        return "MENU SUSPENSO"
    elseif code == "MENU_NOT_FOUND" then
        return "MENU NÃO ENCONTRADO"
    elseif code == "TOO_MANY_ATTEMPTS" or status == 429 then
        return "AGUARDE 1 MIN"
    elseif status >= 500 then
        return "SERVIDOR INDISPONÍVEL"
    end

    return "ACESSO NEGADO"
end

local function compileMenu(source)
    if type(source) ~= "string" or source == "" then
        return nil, "Fonte vazia"
    end
    if type(loadstring) ~= "function" then
        return nil, "loadstring indisponível"
    end
    return loadstring(source)
end

local function runMenuFunction(fn)
    if GUI and GUI.Parent then
        GUI:Destroy()
    end

    local runtimeOK, runtimeError = xpcall(fn, function(errorMessage)
        local trace = tostring(errorMessage)
        pcall(function()
            if debug and type(debug.traceback) == "function" then
                trace = debug.traceback(tostring(errorMessage), 2)
            end
        end)
        return trace
    end)

    if not runtimeOK then
        warn("[GRUPO LUA] Erro ao executar menu:", runtimeError)
    end
end

local function fetchManifest(token)
    return jsonRequest(
        "GET",
        CONFIG.API_BASE .. "/v1/menu-access/" .. MENU_ID .. "/manifest",
        nil,
        {
            ["Authorization"] = "Bearer " .. tostring(token),
            ["X-Menu-Device-Id"] = DEVICE_ID,
        }
    )
end

local function loadFromManifest(manifest)
    if
        type(manifest) ~= "table"
        or manifest.ok ~= true
        or type(manifest.menu) ~= "table"
        or type(manifest.menu.sourceUrl) ~= "string"
    then
        return false, "Manifest inválido"
    end

    local downloadOK, menuSource = downloadText(manifest.menu.sourceUrl)
    if not downloadOK or type(menuSource) ~= "string" or menuSource == "" then
        return false, "Falha ao baixar"
    end

    local fn, compileError = compileMenu(menuSource)
    menuSource = nil
    if not fn then
        warn("[GRUPO LUA] Falha de compilação:", compileError)
        return false, "Falha de compilação"
    end

    runMenuFunction(fn)
    return true
end

local function validate()
    if Busy then
        return
    end

    if MENU_ID == "" or MENU_ID == "__MENU_ID__" or not MENU_ID:match("^menu_") then
        temporaryButton("MENU NÃO CONFIGURADO", COLORS.RED, 1.6)
        return
    end

    local key = tostring(KeyBox.Text or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if key == "" then
        temporaryButton("DIGITE SUA CHAVE", COLORS.RED, 1.3)
        return
    end

    Busy = true
    KeyBox.TextEditable = false
    setButton("VERIFICANDO...", COLORS.WHITE)

    local validateOK, validateData, validateStatus = jsonRequest(
        "POST",
        CONFIG.API_BASE .. "/v1/menu-access/validate",
        {
            menuId = MENU_ID,
            key = key,
            clientLabel = clientLabel(),
            deviceId = DEVICE_ID,
            deviceHint = executorName(),
        }
    )

    key = nil
    KeyBox.Text = ""

    if
        not validateOK
        or type(validateData) ~= "table"
        or validateData.ok ~= true
        or type(validateData.token) ~= "string"
    then
        Busy = false
        KeyBox.TextEditable = true
        temporaryButton(apiErrorText(validateData, validateStatus), COLORS.RED, 1.7)
        return
    end

    local accessToken = validateData.token
    local keyType = tostring(validateData.keyType or "")
    setButton("CARREGANDO...", COLORS.WHITE)

    local manifestOK, manifest, manifestStatus = fetchManifest(accessToken)
    if not manifestOK then
        Busy = false
        KeyBox.TextEditable = true
        if manifestStatus == 401 or manifestStatus == 403 then
            clearMenuSession()
        end
        temporaryButton(manifestStatus == 401 and "SESSÃO EXPIRADA" or "ERRO AO CARREGAR", COLORS.RED, 1.7)
        return
    end

    saveMenuSession(accessToken, validateData.expiresAt, keyType)
    accessToken = nil

    setButton(keyType ~= "" and ("LIBERADO • " .. keyType) or "LIBERADO", COLORS.GREEN)
    task.wait(0.20)

    local loaded = loadFromManifest(manifest)
    if not loaded and GUI and GUI.Parent then
        Busy = false
        KeyBox.TextEditable = true
        temporaryButton("ERRO NO MENU", COLORS.RED, 1.7)
    end
end

Verify.MouseButton1Click:Connect(validate)

KeyBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        validate()
    end
end)

-- Escala automática para celular.
local Scale = Instance.new("UIScale")
Scale.Scale = 1
Scale.Parent = Shell

local function updateScale()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local widthScale = (viewport.X * 0.90) / (CONFIG.WIDTH + 2)
    local heightScale = (viewport.Y * 0.80) / (CONFIG.HEIGHT + 2)
    Scale.Scale = math.min(1, widthScale, heightScale)
end

local CameraConnection
local function bindCamera()
    if CameraConnection then
        CameraConnection:Disconnect()
        CameraConnection = nil
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    CameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

bindCamera()
updateScale()

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCamera()
    updateScale()
end)

-- Área invisível para arrastar o painel sem cobrir a arte.
local DragArea = Instance.new("Frame")
DragArea.Size = UDim2.new(1, -48, 0, 72)
DragArea.Position = UDim2.fromOffset(0, 0)
DragArea.BackgroundTransparency = 1
DragArea.BorderSizePixel = 0
DragArea.Active = true
DragArea.ZIndex = 4
DragArea.Parent = Main

local Dragging = false
local DragInput
local DragStart
local StartPosition

DragArea.InputBegan:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        Dragging = true
        DragStart = input.Position
        StartPosition = Shell.Position
    end
end)

DragArea.InputChanged:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
    then
        DragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not Dragging or input ~= DragInput then
        return
    end

    local delta = input.Position - DragStart
    Shell.Position = UDim2.new(
        StartPosition.X.Scale,
        StartPosition.X.Offset + delta.X,
        StartPosition.Y.Scale,
        StartPosition.Y.Offset + delta.Y
    )
end)

UserInputService.InputEnded:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        Dragging = false
        DragInput = nil
    end
end)

local function tryResumeSession()
    if Busy or MENU_ID == "" or MENU_ID == "__MENU_ID__" or not MENU_ID:match("^menu_") then
        return
    end

    local saved = readMenuSession()
    if not saved then
        return
    end

    Busy = true
    KeyBox.TextEditable = false
    setButton("RESTAURANDO...", COLORS.WHITE)

    local manifestOK, manifest, manifestStatus = fetchManifest(saved.token)
    if not manifestOK then
        Busy = false
        KeyBox.TextEditable = true

        -- Só apaga o token quando o servidor confirmou que ele não é mais aceito.
        -- Falha de rede/5xx preserva a sessão para uma tentativa futura.
        if manifestStatus == 401 or manifestStatus == 403 then
            clearMenuSession()
            temporaryButton("SESSÃO EXPIRADA", COLORS.RED, 1.5)
        else
            temporaryButton("SERVIDOR INDISPONÍVEL", COLORS.RED, 1.5)
        end
        return
    end

    local keyType = tostring(saved.keyType or "")
    setButton(keyType ~= "" and ("LIBERADO • " .. keyType) or "LIBERADO", COLORS.GREEN)
    task.wait(0.15)

    local loaded = loadFromManifest(manifest)
    if not loaded and GUI and GUI.Parent then
        Busy = false
        KeyBox.TextEditable = true
        temporaryButton("ERRO NO MENU", COLORS.RED, 1.7)
    end
end

task.defer(tryResumeSession)
