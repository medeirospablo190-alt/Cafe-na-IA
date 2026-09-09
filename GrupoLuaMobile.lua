--============================================================--
-- GRUPO LUA • LOGIN -> MOBILE MENU
-- Chave local: cafeina
-- O login é solicitado uma única vez quando o executor suporta
-- readfile/writefile. A chave não é salva; só um marcador local.
--============================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local LP = Players.LocalPlayer
if not LP then return end

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

local KEY = "cafeina"
local AUTH_FILE = "grupo_lua_cafeina_auth_v1.txt"
local AUTH_MARKER = "GRUPO_LUA_AUTHORIZED_V1"
local MENU_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaMobileMain.lua"

local function getParent()
    local parent

    pcall(function()
        if type(gethui) == "function" then
            parent = gethui()
        end
    end)

    if not parent then
        pcall(function()
            parent = game:GetService("CoreGui")
        end)
    end

    if not parent then
        parent = LP:WaitForChild("PlayerGui")
    end

    return parent
end

local PARENT = getParent()

local function alreadyAuthorized()
    if ENV.__GRUPO_LUA_CAFEINA_AUTH == true then
        return true
    end

    if type(readfile) == "function" then
        local ok, value = pcall(readfile, AUTH_FILE)
        if ok and tostring(value) == AUTH_MARKER then
            ENV.__GRUPO_LUA_CAFEINA_AUTH = true
            return true
        end
    end

    return false
end

local function rememberAuthorization()
    ENV.__GRUPO_LUA_CAFEINA_AUTH = true

    if type(writefile) == "function" then
        pcall(writefile, AUTH_FILE, AUTH_MARKER)
    end
end

local function loadMenu()
    local ok, source = pcall(function()
        return game:HttpGet(MENU_URL, true)
    end)

    if not ok or type(source) ~= "string" or source == "" then
        warn("[GRUPO LUA] Não foi possível baixar o menu.")
        return false
    end

    local compiled, compileError = loadstring(source)
    if not compiled then
        warn("[GRUPO LUA] Falha ao preparar o menu: " .. tostring(compileError))
        return false
    end

    local runtimeOK, runtimeError = pcall(compiled)
    if not runtimeOK then
        warn("[GRUPO LUA] Falha ao executar o menu: " .. tostring(runtimeError))
        return false
    end

    return true
end

if alreadyAuthorized() then
    loadMenu()
    return
end

pcall(function()
    local old = PARENT:FindFirstChild("GrupoLuaAccess")
    if old then old:Destroy() end
end)

local GUI = Instance.new("ScreenGui")
GUI.Name = "GrupoLuaAccess"
GUI.IgnoreGuiInset = true
GUI.ResetOnSpawn = false
GUI.DisplayOrder = 1000000
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = PARENT

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
Shell.Size = UDim2.fromOffset(522, 262)
Shell.BackgroundColor3 = Color3.fromRGB(100, 100, 106)
Shell.BackgroundTransparency = 0.35
Shell.BorderSizePixel = 0
Shell.Parent = Overlay

local ShellCorner = Instance.new("UICorner")
ShellCorner.CornerRadius = UDim.new(0, 18)
ShellCorner.Parent = Shell

local Scale = Instance.new("UIScale")
Scale.Parent = Shell

local Main = Instance.new("Frame")
Main.Position = UDim2.fromOffset(1, 1)
Main.Size = UDim2.new(1, -2, 1, -2)
Main.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.Parent = Shell

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 17)
MainCorner.Parent = Main

local Background = Instance.new("ImageLabel")
Background.Name = "Background"
Background.Size = UDim2.fromScale(1, 1)
Background.BackgroundTransparency = 1
Background.BorderSizePixel = 0
Background.Image = "rbxassetid://91124214069969"
Background.ScaleType = Enum.ScaleType.Fit
Background.ZIndex = 1
Background.Parent = Main

pcall(function()
    task.spawn(function()
        ContentProvider:PreloadAsync({Background})
    end)
end)

local Close = Instance.new("TextButton")
Close.AnchorPoint = Vector2.new(0.5, 0.5)
Close.Position = UDim2.new(1, -20, 0, 20)
Close.Size = UDim2.fromOffset(30, 30)
Close.BackgroundTransparency = 1
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.fromRGB(235, 42, 38)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 27
Close.AutoButtonColor = false
Close.ZIndex = 30
Close.Parent = Main

local InputBorder = Instance.new("Frame")
InputBorder.AnchorPoint = Vector2.new(0.5, 0.5)
InputBorder.Position = UDim2.new(0.5, 0, 0.60, 0)
InputBorder.Size = UDim2.fromOffset(260, 43)
InputBorder.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
InputBorder.BackgroundTransparency = 0.76
InputBorder.BorderSizePixel = 0
InputBorder.ZIndex = 5
InputBorder.Parent = Main

local BorderCorner = Instance.new("UICorner")
BorderCorner.CornerRadius = UDim.new(0, 10)
BorderCorner.Parent = InputBorder

local InputHolder = Instance.new("Frame")
InputHolder.Position = UDim2.fromOffset(1, 1)
InputHolder.Size = UDim2.new(1, -2, 1, -2)
InputHolder.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
InputHolder.BackgroundTransparency = 0.93
InputHolder.BorderSizePixel = 0
InputHolder.ClipsDescendants = true
InputHolder.ZIndex = 6
InputHolder.Parent = InputBorder

local HolderCorner = Instance.new("UICorner")
HolderCorner.CornerRadius = UDim.new(0, 9)
HolderCorner.Parent = InputHolder

local KeyBox = Instance.new("TextBox")
KeyBox.Position = UDim2.fromOffset(12, 0)
KeyBox.Size = UDim2.new(1, -24, 1, 0)
KeyBox.BackgroundTransparency = 1
KeyBox.Text = ""
KeyBox.PlaceholderText = "Digite sua chave"
KeyBox.PlaceholderColor3 = Color3.fromRGB(230, 230, 235)
KeyBox.TextColor3 = Color3.fromRGB(245, 245, 247)
KeyBox.TextXAlignment = Enum.TextXAlignment.Center
KeyBox.Font = Enum.Font.GothamMedium
KeyBox.TextSize = 12
KeyBox.ClearTextOnFocus = false
KeyBox.MultiLine = false
KeyBox.TextWrapped = false
KeyBox.TextTruncate = Enum.TextTruncate.AtEnd
KeyBox.ZIndex = 7
KeyBox.Parent = InputHolder

local Verify = Instance.new("TextButton")
Verify.AnchorPoint = Vector2.new(0.5, 0.5)
Verify.Position = UDim2.new(0.5, 0, 0.80, 0)
Verify.Size = UDim2.fromOffset(260, 39)
Verify.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
Verify.BackgroundTransparency = 0.90
Verify.BorderSizePixel = 0
Verify.Text = "VERIFICAR"
Verify.TextColor3 = Color3.fromRGB(245, 245, 247)
Verify.Font = Enum.Font.GothamBold
Verify.TextSize = 11
Verify.AutoButtonColor = false
Verify.ZIndex = 5
Verify.Parent = Main

local VerifyCorner = Instance.new("UICorner")
VerifyCorner.CornerRadius = UDim.new(0, 9)
VerifyCorner.Parent = Verify

local VerifyStroke = Instance.new("UIStroke")
VerifyStroke.Color = Color3.fromRGB(235, 235, 240)
VerifyStroke.Transparency = 0.45
VerifyStroke.Thickness = 1
VerifyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
VerifyStroke.Parent = Verify

local Connections = {}
local finished = false
local busy = false
local dragInput
local dragStart
local startPos

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

local function cleanup()
    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)

    if GUI and GUI.Parent then
        GUI:Destroy()
    end
end

local function updateScale()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(520, 600)
    local sx = (viewport.X * 0.92) / 522
    local sy = (viewport.Y * 0.70) / 262
    Scale.Scale = math.clamp(math.min(sx, sy, 1), 0.50, 1)
end

updateScale()
pcall(function()
    connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateScale)
end)

connect(Main.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if input.Position.Y <= Main.AbsolutePosition.Y + (52 * Scale.Scale) then
            dragInput = input
            dragStart = input.Position
            startPos = Shell.Position
        end
    end
end)

connect(UserInputService.InputChanged, function(input)
    if not dragInput then return end

    local valid =
        (dragInput.UserInputType == Enum.UserInputType.Touch and input == dragInput)
        or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement)

    if not valid then return end

    local delta = input.Position - dragStart
    Shell.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

connect(UserInputService.InputEnded, function(input)
    if input == dragInput
    or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragInput = nil
    end
end)

local function normalized(text)
    text = tostring(text or "")
    text = text:match("^%s*(.-)%s*$") or text
    return string.lower(text)
end

local function verify()
    if busy or finished then return end
    busy = true

    if normalized(KeyBox.Text) ~= KEY then
        Verify.Text = "CHAVE INVÁLIDA"
        Verify.TextColor3 = Color3.fromRGB(235, 42, 38)

        task.delay(0.9, function()
            if Verify and Verify.Parent and not finished then
                Verify.Text = "VERIFICAR"
                Verify.TextColor3 = Color3.fromRGB(245, 245, 247)
                busy = false
            end
        end)
        return
    end

    Verify.Text = "LIBERADO"
    Verify.TextColor3 = Color3.fromRGB(92, 220, 125)

    rememberAuthorization()
    finished = true
    task.wait(0.15)
    cleanup()
    loadMenu()
end

connect(Verify.Activated, verify)
connect(KeyBox.FocusLost, function(enterPressed)
    KeyBox.TextTruncate = Enum.TextTruncate.AtEnd
    if enterPressed then verify() end
end)
connect(KeyBox.Focused, function()
    KeyBox.TextTruncate = Enum.TextTruncate.None
end)
connect(Close.Activated, function()
    if finished then return end
    finished = true
    cleanup()
end)
