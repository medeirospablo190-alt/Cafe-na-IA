--============================================================--
-- GRUPO LUA • MOBILE MENU V2
-- EXECUTOR / CLIENT-SIDE
--
-- MOBILE FIRST
--
-- MOVIMENTO:
-- • Noclip
-- • Walk Speed + Slider
-- • Fly + Slider
-- • ESP Nome + Aura
--
-- PLAYERS:
-- • Lista de jogadores online
-- • Botão TP
--
-- FLY:
-- • Sem botão subir/descer
-- • Joystick controla movimento
-- • Câmera controla direção vertical
--============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer

--============================================================--
-- LIMPAR EXECUÇÃO ANTERIOR
--============================================================--

local ENV = _G

pcall(function()
    if getgenv then
        ENV = getgenv()
    end
end)

if ENV.__GRUPO_LUA_MOBILE_CLEANUP then
    pcall(ENV.__GRUPO_LUA_MOBILE_CLEANUP)
end

--============================================================--
-- CONNECTION MANAGER
--============================================================--

local Connections = {}

local function Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

local function DisconnectAll()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Connections)
end

--============================================================--
-- CONFIG
--============================================================--

local CFG = {
    Noclip = false,

    Walk = false,
    WalkSpeed = 35,
    WalkMin = 16,
    WalkMax = 150,

    Fly = false,
    FlySpeed = 55,
    FlyMin = 10,
    FlyMax = 200,

    ESP = false
}

--============================================================--
-- CHARACTER
--============================================================--

local Character
local Humanoid
local Root

local DefaultWalkSpeed = 16
local CollisionCache = {}

local function getCharacter(char)
    char = char or LP.Character or LP.CharacterAdded:Wait()

    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    Root = char:WaitForChild("HumanoidRootPart")

    DefaultWalkSpeed = Humanoid.WalkSpeed
    CollisionCache = {}

    return Character
end

getCharacter()

--============================================================--
-- GUI PARENT
--============================================================--

local guiParent

pcall(function()
    if gethui then
        guiParent = gethui()
    end
end)

if not guiParent then
    local success, result = pcall(function()
        return game:GetService("CoreGui")
    end)

    if success then
        guiParent = result
    else
        guiParent = LP:WaitForChild("PlayerGui")
    end
end

--============================================================--
-- LIMPA GUIS ANTIGAS
--============================================================--

local function destroyOldGUI(parent)
    if not parent then
        return
    end

    pcall(function()
        local old = parent:FindFirstChild("GrupoLuaMobile")
        if old then
            old:Destroy()
        end
    end)
end

destroyOldGUI(guiParent)
destroyOldGUI(LP:FindFirstChild("PlayerGui"))

pcall(function()
    destroyOldGUI(game:GetService("CoreGui"))
end)

for _, plr in ipairs(Players:GetPlayers()) do
    if plr.Character then
        for _, name in ipairs({
            "GrupoLuaAura",
            "GrupoLuaStudioHighlight"
        }) do
            local old = plr.Character:FindFirstChild(name)
            if old then
                pcall(function()
                    old:Destroy()
                end)
            end
        end
    end
end

--============================================================--
-- GUI
--============================================================--

local GUI = Instance.new("ScreenGui")
GUI.Name = "GrupoLuaMobile"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = false
GUI.DisplayOrder = 999999
GUI.Parent = guiParent

--============================================================--
-- COLORS
--============================================================--

local BLACK = Color3.fromRGB(14, 14, 14)
local ITEM = Color3.fromRGB(28, 28, 28)
local TRACK = Color3.fromRGB(60, 60, 60)
local WHITE = Color3.fromRGB(245, 245, 245)
local TEXT_OFF = Color3.fromRGB(235, 235, 235)
local TEXT_ON = Color3.fromRGB(10, 10, 10)

--============================================================--
-- MAIN
--============================================================--

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(270, 390)
Main.Position = UDim2.new(0, 15, 0.5, -195)
Main.BackgroundColor3 = BLACK
Main.BorderSizePixel = 0
Main.Parent = GUI

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(55, 55, 55)
MainStroke.Transparency = 0.25
MainStroke.Thickness = 1
MainStroke.Parent = Main

--============================================================--
-- HEADER
--============================================================--

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 45)
Header.BackgroundTransparency = 1
Header.Active = true
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -24, 1, 0)
Title.Position = UDim2.fromOffset(13, 0)
Title.BackgroundTransparency = 1
Title.Text = "GRUPO LUA"
Title.TextColor3 = WHITE
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

--============================================================--
-- MOBILE DRAG
--============================================================--

local dragging = false
local dragStart
local startPosition

Connect(Header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
    end
end)

Connect(UserInputService.InputChanged, function(input)
    if not dragging then return end

    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart

        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

Connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

--============================================================--
-- TABS
--============================================================--

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 36)
TabBar.Position = UDim2.fromOffset(10, 44)
TabBar.BackgroundTransparency = 1
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabLayout.Padding = UDim.new(0, 6)
TabLayout.Parent = TabBar

local function createTab(text)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.5, -3, 1, 0)
    button.BackgroundColor3 = ITEM
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = text
    button.TextColor3 = TEXT_OFF
    button.TextSize = 10
    button.Font = Enum.Font.GothamBold
    button.Parent = TabBar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    return button
end

local MovementTab = createTab("MOVIMENTO")
local PlayersTab = createTab("PLAYERS")

--============================================================--
-- PAGE HOLDER
--============================================================--

local PageHolder = Instance.new("Frame")
PageHolder.Size = UDim2.new(1, -20, 1, -90)
PageHolder.Position = UDim2.fromOffset(10, 85)
PageHolder.BackgroundTransparency = 1
PageHolder.ClipsDescendants = true
PageHolder.Parent = Main

local function createScrollPage()
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110)
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
    page.Parent = PageHolder

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page

    return page, layout
end

local MovementPage = createScrollPage()
local PlayersPage = createScrollPage()
PlayersPage.Visible = false

local function tabStyle(button, enabled)
    TweenService:Create(
        button,
        TweenInfo.new(0.1),
        {
            BackgroundColor3 = enabled and WHITE or ITEM,
            TextColor3 = enabled and TEXT_ON or TEXT_OFF
        }
    ):Play()
end

local function showMovement()
    MovementPage.Visible = true
    PlayersPage.Visible = false
    tabStyle(MovementTab, true)
    tabStyle(PlayersTab, false)
end

local function showPlayers()
    MovementPage.Visible = false
    PlayersPage.Visible = true
    tabStyle(MovementTab, false)
    tabStyle(PlayersTab, true)
end

Connect(MovementTab.Activated, showMovement)
Connect(PlayersTab.Activated, showPlayers)
showMovement()

--============================================================--
-- COMPONENTS
--============================================================--

local function toggleStyle(button, state)
    TweenService:Create(
        button,
        TweenInfo.new(0.12),
        {
            BackgroundColor3 = state and WHITE or ITEM,
            TextColor3 = state and TEXT_ON or TEXT_OFF
        }
    ):Play()
end

local function createToggle(parent, text, default, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, -3, 0, 44)
    Button.BackgroundColor3 = ITEM
    Button.TextColor3 = TEXT_OFF
    Button.BorderSizePixel = 0
    Button.AutoButtonColor = false
    Button.Text = text
    Button.TextSize = 12
    Button.Font = Enum.Font.GothamSemibold
    Button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = Button

    local state = default
    toggleStyle(Button, state)

    Connect(Button.Activated, function()
        state = not state
        toggleStyle(Button, state)
        callback(state)
    end)

    return Button
end

local function createSlider(parent, title, min, max, value, callback)
    local Holder = Instance.new("Frame")
    Holder.Size = UDim2.new(1, -3, 0, 64)
    Holder.BackgroundColor3 = ITEM
    Holder.BorderSizePixel = 0
    Holder.Parent = parent

    local holderCorner = Instance.new("UICorner")
    holderCorner.CornerRadius = UDim.new(0, 9)
    holderCorner.Parent = Holder

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.7, 0, 0, 28)
    Label.Position = UDim2.fromOffset(12, 3)
    Label.BackgroundTransparency = 1
    Label.Text = title
    Label.TextColor3 = TEXT_OFF
    Label.TextSize = 11
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Holder

    local Value = Instance.new("TextLabel")
    Value.Size = UDim2.new(0.3, -12, 0, 28)
    Value.Position = UDim2.new(0.7, 0, 0, 3)
    Value.BackgroundTransparency = 1
    Value.Text = tostring(value)
    Value.TextColor3 = Color3.fromRGB(165, 165, 165)
    Value.TextSize = 11
    Value.Font = Enum.Font.GothamBold
    Value.TextXAlignment = Enum.TextXAlignment.Right
    Value.Parent = Holder

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -24, 0, 6)
    Track.Position = UDim2.new(0, 12, 1, -19)
    Track.BackgroundColor3 = TRACK
    Track.BorderSizePixel = 0
    Track.Active = true
    Track.Parent = Holder

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = Track

    local Fill = Instance.new("Frame")
    Fill.BackgroundColor3 = WHITE
    Fill.BorderSizePixel = 0
    Fill.Parent = Track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = Fill

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.fromOffset(18, 18)
    Knob.AnchorPoint = Vector2.new(0.5, 0.5)
    Knob.BackgroundColor3 = WHITE
    Knob.BorderSizePixel = 0
    Knob.Active = true
    Knob.Parent = Track

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = Knob

    local pct = math.clamp((value - min) / (max - min), 0, 1)
    Fill.Size = UDim2.new(pct, 0, 1, 0)
    Knob.Position = UDim2.new(pct, 0, 0.5, 0)

    local sliding = false

    local function update(x)
        if not Track or not Track.Parent or Track.AbsoluteSize.X <= 0 then
            return
        end

        local percent = math.clamp(
            (x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X,
            0,
            1
        )

        local newValue = math.floor(min + ((max - min) * percent))

        Fill.Size = UDim2.new(percent, 0, 1, 0)
        Knob.Position = UDim2.new(percent, 0, 0.5, 0)
        Value.Text = tostring(newValue)

        callback(newValue)
    end

    local function beginSlide(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            update(input.Position.X)
        end
    end

    Connect(Track.InputBegan, beginSlide)
    Connect(Knob.InputBegan, beginSlide)

    Connect(UserInputService.InputChanged, function(input)
        if not sliding then return end

        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input.Position.X)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
        end
    end)

    return Holder
end

--============================================================--
-- NOCLIP
--============================================================--

local function restoreCollisions()
    for part, data in pairs(CollisionCache) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = data.CanCollide
            end)
        end
    end

    CollisionCache = {}
end

createToggle(MovementPage, "NOCLIP", CFG.Noclip, function(enabled)
    CFG.Noclip = enabled

    if not enabled then
        restoreCollisions()
    end
end)

Connect(RunService.Stepped, function()
    if not CFG.Noclip or not Character then
        return
    end

    for _, object in ipairs(Character:GetDescendants()) do
        if object:IsA("BasePart") then
            if not CollisionCache[object] then
                CollisionCache[object] = {
                    CanCollide = object.CanCollide
                }
            end

            if object.CanCollide then
                object.CanCollide = false
            end
        end
    end
end)

--============================================================--
-- WALK SPEED
--============================================================--

createToggle(MovementPage, "WALK SPEED", CFG.Walk, function(enabled)
    CFG.Walk = enabled

    if Humanoid then
        if enabled then
            Humanoid.WalkSpeed = CFG.WalkSpeed
        else
            Humanoid.WalkSpeed = DefaultWalkSpeed
        end
    end
end)

createSlider(
    MovementPage,
    "Velocidade",
    CFG.WalkMin,
    CFG.WalkMax,
    CFG.WalkSpeed,
    function(value)
        CFG.WalkSpeed = value

        if CFG.Walk and Humanoid then
            Humanoid.WalkSpeed = value
        end
    end
)

Connect(RunService.Heartbeat, function()
    if CFG.Walk and Humanoid and Humanoid.Parent and Humanoid.Health > 0 then
        if Humanoid.WalkSpeed ~= CFG.WalkSpeed then
            Humanoid.WalkSpeed = CFG.WalkSpeed
        end
    end
end)

--============================================================--
-- MOBILE FLY
--============================================================--

local FlyAttachment
local FlyVelocity
local FlyOrientation
local FlyConnection

local function destroyFlyObjects()
    if FlyConnection then
        pcall(function()
            FlyConnection:Disconnect()
        end)
        FlyConnection = nil
    end

    if FlyVelocity then
        pcall(function()
            FlyVelocity:Destroy()
        end)
        FlyVelocity = nil
    end

    if FlyOrientation then
        pcall(function()
            FlyOrientation:Destroy()
        end)
        FlyOrientation = nil
    end

    if FlyAttachment then
        pcall(function()
            FlyAttachment:Destroy()
        end)
        FlyAttachment = nil
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.AutoRotate = true
        end)
    end
end

local function getFlatCameraBasis(camera)
    local cameraLook = camera.CFrame.LookVector
    local flatLook = Vector3.new(cameraLook.X, 0, cameraLook.Z)

    if flatLook.Magnitude < 0.01 then
        local rootLook = Root and Root.CFrame.LookVector or Vector3.new(0, 0, -1)
        flatLook = Vector3.new(rootLook.X, 0, rootLook.Z)
    end

    if flatLook.Magnitude < 0.01 then
        flatLook = Vector3.new(0, 0, -1)
    end

    flatLook = flatLook.Unit

    local flatRight = Vector3.new(
        -flatLook.Z,
        0,
        flatLook.X
    )

    return flatLook, flatRight
end

local function startFly()
    destroyFlyObjects()

    if not Character or not Character.Parent then
        getCharacter()
    end

    if not Humanoid or not Root or Humanoid.Health <= 0 then
        return
    end

    Humanoid.Sit = false

    pcall(function()
        Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end)

    Root.AssemblyLinearVelocity = Vector3.new(
        Root.AssemblyLinearVelocity.X,
        math.max(Root.AssemblyLinearVelocity.Y, 7),
        Root.AssemblyLinearVelocity.Z
    )

    FlyAttachment = Instance.new("Attachment")
    FlyAttachment.Name = "GrupoLuaFlyAttachment"
    FlyAttachment.Parent = Root

    FlyVelocity = Instance.new("LinearVelocity")
    FlyVelocity.Name = "GrupoLuaFlyVelocity"
    FlyVelocity.Attachment0 = FlyAttachment
    FlyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    FlyVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    FlyVelocity.MaxForce = math.huge
    FlyVelocity.VectorVelocity = Vector3.zero
    FlyVelocity.Parent = Root

    FlyOrientation = Instance.new("AlignOrientation")
    FlyOrientation.Name = "GrupoLuaFlyOrientation"
    FlyOrientation.Attachment0 = FlyAttachment
    FlyOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    FlyOrientation.RigidityEnabled = false
    FlyOrientation.Responsiveness = 25
    FlyOrientation.MaxTorque = math.huge
    FlyOrientation.Parent = Root

    Humanoid.AutoRotate = false

    FlyConnection = RunService.RenderStepped:Connect(function()
        if not CFG.Fly then
            return
        end

        if not Root or not Root.Parent
        or not Humanoid or not Humanoid.Parent
        or Humanoid.Health <= 0 then
            return
        end

        local camera = workspace.CurrentCamera

        if not camera then
            return
        end

        local move = Humanoid.MoveDirection
        local desired = Vector3.zero

        if move.Magnitude > 0.001 then
            local flatLook, flatRight = getFlatCameraBasis(camera)

            local forwardInput = move:Dot(flatLook)
            local rightInput = move:Dot(flatRight)

            local cameraLook = camera.CFrame.LookVector
            local cameraRight = camera.CFrame.RightVector

            desired =
                (cameraLook * forwardInput)
                +
                (cameraRight * rightInput)

            if desired.Magnitude > 1 then
                desired = desired.Unit
            end
        end

        FlyVelocity.VectorVelocity = desired * CFG.FlySpeed

        local look = camera.CFrame.LookVector
        local facing = Vector3.new(look.X, 0, look.Z)

        if facing.Magnitude > 0.01 then
            FlyOrientation.CFrame = CFrame.lookAt(
                Root.Position,
                Root.Position + facing.Unit
            )
        end
    end)
end

createToggle(MovementPage, "FLY", CFG.Fly, function(enabled)
    CFG.Fly = enabled

    if enabled then
        startFly()
    else
        destroyFlyObjects()
    end
end)

createSlider(
    MovementPage,
    "Fly Speed",
    CFG.FlyMin,
    CFG.FlyMax,
    CFG.FlySpeed,
    function(value)
        CFG.FlySpeed = value
    end
)

--============================================================--
-- ESP
--============================================================--

local ESPObjects = {}

local function removeESP(plr)
    local data = ESPObjects[plr]

    if data then
        for _, object in pairs(data) do
            pcall(function()
                if object then
                    object:Destroy()
                end
            end)
        end

        ESPObjects[plr] = nil
    end

    if plr.Character then
        local old = plr.Character:FindFirstChild("GrupoLuaAura")
        if old then
            pcall(function()
                old:Destroy()
            end)
        end
    end
end

local function createESP(plr)
    if plr == LP then
        return
    end

    removeESP(plr)

    if not CFG.ESP then
        return
    end

    local char = plr.Character
    if not char then
        return
    end

    local head = char:FindFirstChild("Head")
    if not head then
        return
    end

    local Highlight = Instance.new("Highlight")
    Highlight.Name = "GrupoLuaAura"
    Highlight.Adornee = char
    Highlight.FillColor = Color3.fromRGB(255, 255, 255)
    Highlight.FillTransparency = 0.78
    Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    Highlight.OutlineTransparency = 0
    Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    Highlight.Parent = char

    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "GrupoLuaName_" .. tostring(plr.UserId)
    Billboard.Adornee = head
    Billboard.Size = UDim2.fromOffset(180, 32)
    Billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    Billboard.AlwaysOnTop = true
    Billboard.Parent = GUI

    local Name = Instance.new("TextLabel")
    Name.Size = UDim2.fromScale(1, 1)
    Name.BackgroundTransparency = 1
    Name.Text = plr.DisplayName
    Name.TextColor3 = Color3.fromRGB(255, 255, 255)
    Name.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    Name.TextStrokeTransparency = 0.2
    Name.TextSize = 13
    Name.Font = Enum.Font.GothamBold
    Name.Parent = Billboard

    ESPObjects[plr] = {
        Highlight,
        Billboard
    }
end

local function refreshESP()
    local current = {}

    for plr in pairs(ESPObjects) do
        table.insert(current, plr)
    end

    for _, plr in ipairs(current) do
        removeESP(plr)
    end

    if not CFG.ESP then
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            createESP(plr)
        end
    end
end

createToggle(
    MovementPage,
    "ESP • NOME + AURA",
    CFG.ESP,
    function(enabled)
        CFG.ESP = enabled
        refreshESP()
    end
)

--============================================================--
-- PLAYERS PAGE
--============================================================--

local PlayerRows = {}

local function clearPlayerRows()
    for _, row in pairs(PlayerRows) do
        pcall(function()
            row:Destroy()
        end)
    end

    PlayerRows = {}
end

local function teleportToPlayer(plr)
    if not plr or plr == LP then
        return false
    end

    local targetCharacter = plr.Character
    if not targetCharacter then
        return false
    end

    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return false
    end

    if not Character or not Character.Parent or not Root or not Root.Parent then
        getCharacter()
    end

    if not Root then
        return false
    end

    local destination = targetRoot.CFrame * CFrame.new(0, 1, 3)

    Root.CFrame = destination
    Root.AssemblyLinearVelocity = Vector3.zero
    Root.AssemblyAngularVelocity = Vector3.zero

    return true
end

local function createPlayerRow(plr)
    if plr == LP then
        return
    end

    local Row = Instance.new("Frame")
    Row.Name = "Player_" .. tostring(plr.UserId)
    Row.Size = UDim2.new(1, -3, 0, 48)
    Row.BackgroundColor3 = ITEM
    Row.BorderSizePixel = 0
    Row.Parent = PlayersPage

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = Row

    local Name = Instance.new("TextLabel")
    Name.Size = UDim2.new(1, -75, 1, 0)
    Name.Position = UDim2.fromOffset(11, 0)
    Name.BackgroundTransparency = 1
    Name.Text = plr.DisplayName .. "\n@" .. plr.Name
    Name.TextColor3 = TEXT_OFF
    Name.Font = Enum.Font.GothamMedium
    Name.TextSize = 10
    Name.TextWrapped = false
    Name.TextTruncate = Enum.TextTruncate.AtEnd
    Name.TextXAlignment = Enum.TextXAlignment.Left
    Name.TextYAlignment = Enum.TextYAlignment.Center
    Name.Parent = Row

    local TP = Instance.new("TextButton")
    TP.Size = UDim2.fromOffset(51, 30)
    TP.AnchorPoint = Vector2.new(1, 0.5)
    TP.Position = UDim2.new(1, -9, 0.5, 0)
    TP.BackgroundColor3 = WHITE
    TP.BorderSizePixel = 0
    TP.AutoButtonColor = false
    TP.Text = "TP"
    TP.TextColor3 = TEXT_ON
    TP.TextSize = 11
    TP.Font = Enum.Font.GothamBold
    TP.Parent = Row

    local tpCorner = Instance.new("UICorner")
    tpCorner.CornerRadius = UDim.new(0, 8)
    tpCorner.Parent = TP

    Connect(TP.Activated, function()
        if not plr.Parent then
            return
        end

        local success = teleportToPlayer(plr)

        if success then
            TP.Text = "OK"
            task.delay(0.45, function()
                if TP and TP.Parent then
                    TP.Text = "TP"
                end
            end)
        else
            TP.Text = "..."
            task.delay(0.6, function()
                if TP and TP.Parent then
                    TP.Text = "TP"
                end
            end)
        end
    end)

    PlayerRows[plr] = Row
end

local function refreshPlayerList()
    clearPlayerRows()

    local list = Players:GetPlayers()

    table.sort(list, function(a, b)
        return string.lower(a.DisplayName) < string.lower(b.DisplayName)
    end)

    for _, plr in ipairs(list) do
        if plr ~= LP then
            createPlayerRow(plr)
        end
    end
end

local function setupPlayer(plr)
    if plr == LP then
        return
    end

    Connect(plr.CharacterAdded, function()
        task.wait(0.45)

        if CFG.ESP then
            createESP(plr)
        end
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do
    setupPlayer(plr)
end

Connect(Players.PlayerAdded, function(plr)
    setupPlayer(plr)
    refreshPlayerList()
end)

Connect(Players.PlayerRemoving, function(plr)
    removeESP(plr)
    PlayerRows[plr] = nil
    task.defer(refreshPlayerList)
end)

refreshPlayerList()

--============================================================--
-- LOCAL PLAYER RESPAWN
--============================================================--

Connect(LP.CharacterAdded, function(char)
    destroyFlyObjects()
    restoreCollisions()

    task.wait(0.35)
    getCharacter(char)

    if CFG.Walk then
        Humanoid.WalkSpeed = CFG.WalkSpeed
    end

    if CFG.Fly then
        task.wait(0.15)
        startFly()
    end
end)

--============================================================--
-- CLEANUP
--============================================================--

ENV.__GRUPO_LUA_MOBILE_CLEANUP = function()
    CFG.Fly = false
    CFG.Noclip = false
    CFG.Walk = false
    CFG.ESP = false

    destroyFlyObjects()
    restoreCollisions()

    for plr in pairs(ESPObjects) do
        pcall(function()
            removeESP(plr)
        end)
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.WalkSpeed = DefaultWalkSpeed
            Humanoid.AutoRotate = true
        end)
    end

    DisconnectAll()

    pcall(function()
        GUI:Destroy()
    end)
end

print("GRUPO LUA MOBILE V2 carregado.")
