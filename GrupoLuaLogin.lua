--[[
    GRUPO LUA — LOGIN / MENU ACCESS
    Mobile / Executor

    Fundo: assets/grupo-lua-login.jpg
    API: Grupo Lua Control API

    O loader de cada menu deve definir:
        getgenv().GRUPO_LUA_MENU_ID = "menu_xxxxx"
    antes de executar este arquivo.
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
    IMAGE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/assets/grupo-lua-login.jpg",
    IMAGE_FILE = "grupo_lua_login_v1.jpg",
    WIDTH = 430,
    HEIGHT = 215,
}

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

local MENU_ID = tostring(ENV.GRUPO_LUA_MENU_ID or "__MENU_ID__")

local COLORS = {
    WHITE = Color3.fromRGB(245, 245, 247),
    INPUT = Color3.fromRGB(8, 8, 9),
    RED = Color3.fromRGB(143, 24, 22),
    RED_HOVER = Color3.fromRGB(177, 31, 28),
    RED_BRIGHT = Color3.fromRGB(216, 45, 39),
    GREEN = Color3.fromRGB(48, 175, 92),
}

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

local function getAssetFunction()
    if type(getcustomasset) == "function" then
        return getcustomasset
    end
    if type(getsynasset) == "function" then
        return getsynasset
    end
    return nil
end

local function loadBackgroundAsset()
    local assetFunction = getAssetFunction()

    if not assetFunction or type(writefile) ~= "function" then
        return nil
    end

    if type(isfile) == "function" then
        local exists = false
        pcall(function()
            exists = isfile(CONFIG.IMAGE_FILE)
        end)

        if exists then
            local ok, asset = pcall(assetFunction, CONFIG.IMAGE_FILE)
            if ok and asset then
                return asset
            end
        end
    end

    local imageData

    if Request then
        local ok, response = rawRequest({
            Url = CONFIG.IMAGE_URL,
            Method = "GET",
            Headers = {
                ["Accept"] = "image/jpeg,image/*,*/*",
            },
        })

        if ok and response and type(response.Body) == "string" and #response.Body > 100 then
            imageData = response.Body
        end
    end

    if not imageData then
        local ok, body = pcall(function()
            return game:HttpGet(CONFIG.IMAGE_URL, true)
        end)

        if ok and type(body) == "string" and #body > 100 then
            imageData = body
        end
    end

    if not imageData then
        return nil
    end

    local writeOK = pcall(writefile, CONFIG.IMAGE_FILE, imageData)
    imageData = nil

    if not writeOK then
        return nil
    end

    local assetOK, asset = pcall(assetFunction, CONFIG.IMAGE_FILE)
    if assetOK and asset then
        return asset
    end

    return nil
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
    TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.15,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out
        ),
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

-- Casca fina para uma borda uniforme, sem UIStroke externo.
local Shell = Instance.new("Frame")
Shell.Name = "Shell"
Shell.AnchorPoint = Vector2.new(0.5, 0.5)
Shell.Position = UDim2.fromScale(0.5, 0.5)
Shell.Size = UDim2.fromOffset(CONFIG.WIDTH + 2, CONFIG.HEIGHT + 2)
Shell.BackgroundColor3 = Color3.fromRGB(90, 90, 94)
Shell.BorderSizePixel = 0
Shell.Parent = Overlay
corner(Shell, 18)

local Main = Instance.new("Frame")
Main.Position = UDim2.fromOffset(1, 1)
Main.Size = UDim2.new(1, -2, 1, -2)
Main.BackgroundColor3 = Color3.fromRGB(5, 5, 6)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = Shell
corner(Main, 17)

local Background = Instance.new("ImageLabel")
Background.Name = "Background"
Background.Size = UDim2.fromScale(1, 1)
Background.Position = UDim2.fromScale(0, 0)
Background.BackgroundTransparency = 1
Background.BorderSizePixel = 0
Background.Image = ""
Background.ScaleType = Enum.ScaleType.Fit
Background.ZIndex = 1
Background.Parent = Main

local InputBorder = Instance.new("Frame")
InputBorder.AnchorPoint = Vector2.new(0.5, 0.5)
InputBorder.Position = UDim2.new(0.5, 0, 0.60, 0)
InputBorder.Size = UDim2.fromOffset(220, 40)
InputBorder.BackgroundColor3 = Color3.fromRGB(125, 125, 128)
InputBorder.BorderSizePixel = 0
InputBorder.ZIndex = 5
InputBorder.Parent = Main
corner(InputBorder, 10)

local InputHolder = Instance.new("Frame")
InputHolder.Position = UDim2.fromOffset(1, 1)
InputHolder.Size = UDim2.new(1, -2, 1, -2)
InputHolder.BackgroundColor3 = COLORS.INPUT
InputHolder.BackgroundTransparency = 0.08
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
KeyBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 125)
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
Verify.Size = UDim2.fromOffset(220, 36)
Verify.BackgroundColor3 = COLORS.RED
Verify.BorderSizePixel = 0
Verify.Text = "VERIFICAR"
Verify.TextColor3 = COLORS.WHITE
Verify.Font = Enum.Font.GothamBold
Verify.TextSize = 11
Verify.AutoButtonColor = false
Verify.ZIndex = 5
Verify.Parent = Main
corner(Verify, 9)

task.spawn(function()
    local asset = loadBackgroundAsset()
    if not asset or not Background or not Background.Parent then
        return
    end

    Background.Image = asset
    pcall(function()
        ContentProvider:PreloadAsync({ Background })
    end)
end)

KeyBox.Focused:Connect(function()
    tween(InputBorder, {
        BackgroundColor3 = COLORS.RED_BRIGHT,
    })
end)

KeyBox.FocusLost:Connect(function()
    tween(InputBorder, {
        BackgroundColor3 = Color3.fromRGB(125, 125, 128),
    })
end)

Verify.MouseEnter:Connect(function()
    tween(Verify, {
        BackgroundColor3 = COLORS.RED_HOVER,
    })
end)

Verify.MouseLeave:Connect(function()
    tween(Verify, {
        BackgroundColor3 = COLORS.RED,
    })
end)

local DEFAULT_BUTTON_TEXT = "VERIFICAR"

local function temporaryButton(text, color, seconds)
    Verify.Text = tostring(text)

    if color then
        tween(Verify, {
            BackgroundColor3 = color,
        })
    end

    task.delay(seconds or 1.3, function()
        if Verify and Verify.Parent then
            Verify.Text = DEFAULT_BUTTON_TEXT
            tween(Verify, {
                BackgroundColor3 = COLORS.RED,
            })
        end
    end)
end

local function apiErrorText(data, status)
    local code = type(data) == "table" and tostring(data.code or "") or ""

    if code == "INVALID_MENU_KEY" then
        return "CHAVE INVÁLIDA"
    elseif code == "MENU_KEY_EXPIRED" then
        return "CHAVE EXPIRADA"
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

local Busy = false

local function validate()
    if Busy then
        return
    end

    if MENU_ID == "" or MENU_ID == "__MENU_ID__" or not MENU_ID:match("^menu_") then
        temporaryButton("MENU NÃO CONFIGURADO", COLORS.RED_BRIGHT, 1.5)
        return
    end

    local key = tostring(KeyBox.Text or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if key == "" then
        temporaryButton("DIGITE SUA CHAVE", COLORS.RED_BRIGHT, 1.2)
        tween(InputBorder, {
            BackgroundColor3 = COLORS.RED_BRIGHT,
        })
        return
    end

    Busy = true
    KeyBox.TextEditable = false
    Verify.Text = "VERIFICANDO..."
    tween(Verify, {
        BackgroundColor3 = Color3.fromRGB(80, 22, 22),
    })

    local validateOK, validateData, validateStatus = jsonRequest(
        "POST",
        CONFIG.API_BASE .. "/v1/menu-access/validate",
        {
            menuId = MENU_ID,
            key = key,
            clientLabel = clientLabel(),
        }
    )

    key = nil

    if
        not validateOK
        or type(validateData) ~= "table"
        or validateData.ok ~= true
        or type(validateData.token) ~= "string"
    then
        KeyBox.TextEditable = true
        Busy = false
        temporaryButton(
            apiErrorText(validateData, validateStatus),
            COLORS.RED_BRIGHT,
            1.5
        )
        return
    end

    local accessToken = validateData.token
    local keyType = tostring(validateData.keyType or "")

    Verify.Text = "CARREGANDO..."

    local manifestOK, manifest, manifestStatus = jsonRequest(
        "GET",
        CONFIG.API_BASE .. "/v1/menu-access/" .. MENU_ID .. "/manifest",
        nil,
        {
            ["Authorization"] = "Bearer " .. accessToken,
        }
    )

    accessToken = nil

    if
        not manifestOK
        or type(manifest) ~= "table"
        or manifest.ok ~= true
        or type(manifest.menu) ~= "table"
        or type(manifest.menu.sourceUrl) ~= "string"
    then
        KeyBox.TextEditable = true
        Busy = false
        temporaryButton(
            manifestStatus == 401 and "SESSÃO EXPIRADA" or "ERRO AO CARREGAR",
            COLORS.RED_BRIGHT,
            1.5
        )
        return
    end

    local downloadOK, source = downloadText(manifest.menu.sourceUrl)

    if not downloadOK or type(source) ~= "string" or source == "" then
        KeyBox.TextEditable = true
        Busy = false
        temporaryButton("ERRO AO BAIXAR", COLORS.RED_BRIGHT, 1.5)
        return
    end

    if type(loadstring) ~= "function" then
        source = nil
        KeyBox.TextEditable = true
        Busy = false
        temporaryButton("LOADSTRING INDISPONÍVEL", COLORS.RED_BRIGHT, 1.7)
        return
    end

    local fn, compileError = loadstring(source)
    source = nil

    if not fn then
        warn("[GRUPO LUA] Falha de compilação:", compileError)
        KeyBox.TextEditable = true
        Busy = false
        temporaryButton("ERRO NO MENU", COLORS.RED_BRIGHT, 1.5)
        return
    end

    KeyBox.Text = ""
    Verify.Text = keyType ~= "" and ("LIBERADO • " .. keyType) or "LIBERADO"
    tween(Verify, {
        BackgroundColor3 = COLORS.GREEN,
    }, 0.18)

    task.wait(0.35)
    GUI:Destroy()

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
    local widthScale = (viewport.X * 0.88) / (CONFIG.WIDTH + 2)
    local heightScale = (viewport.Y * 0.76) / (CONFIG.HEIGHT + 2)

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

-- Área invisível de arraste para não cobrir a imagem.
local DragArea = Instance.new("Frame")
DragArea.Size = UDim2.new(1, 0, 0, 74)
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
