--============================================================--
-- GRUPO LUA • MOBILE MENU V3
-- EXECUTOR / CLIENT-SIDE • MOBILE FIRST
--
-- ABAS:
--   MENU       -> Noclip, Walk Speed, Fly, ESP
--   TELEPORTE  -> Players online + botão TP
--
-- FLY MOBILE:
--   Joystick = movimento
--   Camera = direção completa (inclusive subir/descer)
--============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
if not LP then return end

--============================================================--
-- CLEANUP DE EXECUÇÃO ANTERIOR
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

local Connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

local function disconnectAll()
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

    ESP = false,
}

--============================================================--
-- CHARACTER
--============================================================--

local Character
local Humanoid
local Root
local DefaultWalkSpeed = 16
local CollisionCache = {}

local function bindCharacter(char)
    char = char or LP.Character or LP.CharacterAdded:Wait()

    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    Root = char:WaitForChild("HumanoidRootPart")
    DefaultWalkSpeed = Humanoid.WalkSpeed
    CollisionCache = {}

    return true
end

bindCharacter()

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
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and coreGui then
        guiParent = coreGui
    else
        guiParent = LP:WaitForChild("PlayerGui")
    end
end

local function destroyOldGUI(parent)
    if not parent then return end

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

--============================================================--
-- CORES
--============================================================--

local BLACK = Color3.fromRGB(14, 14, 14)
local ITEM = Color3.fromRGB(28, 28, 28)
local TRACK = Color3.fromRGB(61, 61, 61)
local WHITE = Color3.fromRGB(245, 245, 245)
local TEXT_OFF = Color3.fromRGB(235, 235, 235)
local TEXT_DIM = Color3.fromRGB(145, 145, 145)
local TEXT_ON = Color3.fromRGB(10, 10, 10)

--============================================================--
-- GUI PRINCIPAL • TAMANHO ORIGINAL
--============================================================--

local GUI = Instance.new("ScreenGui")
GUI.Name = "GrupoLuaMobile"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = false
GUI.DisplayOrder = 999999
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = guiParent

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(275, 365)
Main.Position = UDim2.new(0, 15, 0.5, -182)
Main.BackgroundColor3 = BLACK
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = GUI

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 13)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(52, 52, 52)
MainStroke.Transparency = 0.25
MainStroke.Thickness = 1
MainStroke.Parent = Main

--============================================================--
-- HEADER / DRAG MOBILE
--============================================================--

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundTransparency = 1
Header.Active = true
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -24, 1, 0)
Title.Position = UDim2.fromOffset(12, 0)
Title.BackgroundTransparency = 1
Title.Text = "GRUPO LUA"
Title.TextColor3 = WHITE
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local dragging = false
local dragInput
local dragStart
local startPosition

connect(Header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragInput = input
        dragStart = input.Position
        startPosition = Main.Position
    end
end)

connect(Header.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

connect(UserInputService.InputChanged, function(input)
    if not dragging or input ~= dragInput then
        return
    end

    local delta = input.Position - dragStart

    Main.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

connect(UserInputService.InputEnded, function(input)
    if input == dragInput
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        dragInput = nil
    end
end)

--============================================================--
-- ABAS
--============================================================--

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -16, 0, 32)
TabBar.Position = UDim2.fromOffset(8, 39)
TabBar.BackgroundTransparency = 1
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabLayout.Padding = UDim.new(0, 5)
TabLayout.Parent = TabBar

local function makeTab(text)
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

local MenuTab = makeTab("MENU")
local TeleportTab = makeTab("TELEPORTE")

--============================================================--
-- PÁGINAS / SCROLL
--============================================================--

local PageHolder = Instance.new("Frame")
PageHolder.Size = UDim2.new(1, -16, 1, -79)
PageHolder.Position = UDim2.fromOffset(8, 75)
PageHolder.BackgroundTransparency = 1
PageHolder.ClipsDescendants = true
PageHolder.Parent = Main

local function makeScrollPage()
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = Color3.fromRGB(115, 115, 115)
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
    page.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    page.Parent = PageHolder

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = page

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = page

    return page
end

local MenuPage = makeScrollPage()
local TeleportPage = makeScrollPage()
TeleportPage.Visible = false

local function setTabStyle(button, active)
    TweenService:Create(
        button,
        TweenInfo.new(0.1),
        {
            BackgroundColor3 = active and WHITE or ITEM,
            TextColor3 = active and TEXT_ON or TEXT_OFF,
        }
    ):Play()
end

local function showMenu()
    MenuPage.Visible = true
    TeleportPage.Visible = false
    setTabStyle(MenuTab, true)
    setTabStyle(TeleportTab, false)
end

local function showTeleports()
    MenuPage.Visible = false
    TeleportPage.Visible = true
    setTabStyle(MenuTab, false)
    setTabStyle(TeleportTab, true)
end

connect(MenuTab.Activated, showMenu)
connect(TeleportTab.Activated, showTeleports)
showMenu()

--============================================================--
-- COMPONENTES
--============================================================--

local function setToggleStyle(button, enabled)
    TweenService:Create(
        button,
        TweenInfo.new(0.11),
        {
            BackgroundColor3 = enabled and WHITE or ITEM,
            TextColor3 = enabled and TEXT_ON or TEXT_OFF,
        }
    ):Play()
end

local function makeToggle(text, initial, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -3, 0, 38)
    button.BackgroundColor3 = ITEM
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = text
    button.TextColor3 = TEXT_OFF
    button.TextSize = 11
    button.Font = Enum.Font.GothamSemibold
    button.Parent = MenuPage

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local state = initial
    setToggleStyle(button, state)

    connect(button.Activated, function()
        state = not state
        setToggleStyle(button, state)
        callback(state)
    end)

    return button
end

local function makeSlider(title, minValue, maxValue, initialValue, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -3, 0, 52)
    holder.BackgroundColor3 = ITEM
    holder.BorderSizePixel = 0
    holder.Parent = MenuPage

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = holder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.72, 0, 0, 23)
    label.Position = UDim2.fromOffset(10, 2)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = TEXT_OFF
    label.TextSize = 10
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = holder

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.28, -10, 0, 23)
    valueLabel.Position = UDim2.new(0.72, 0, 0, 2)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(initialValue)
    valueLabel.TextColor3 = TEXT_DIM
    valueLabel.TextSize = 10
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = holder

    local hitbox = Instance.new("Frame")
    hitbox.Size = UDim2.new(1, -20, 0, 22)
    hitbox.Position = UDim2.new(0, 10, 1, -26)
    hitbox.BackgroundTransparency = 1
    hitbox.Active = true
    hitbox.Parent = holder

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Size = UDim2.new(1, 0, 0, 5)
    track.Position = UDim2.new(0, 0, 0.5, 0)
    track.BackgroundColor3 = TRACK
    track.BorderSizePixel = 0
    track.Parent = hitbox

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = WHITE
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = WHITE
    knob.BorderSizePixel = 0
    knob.Parent = track

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local percent = math.clamp(
        (initialValue - minValue) / (maxValue - minValue),
        0,
        1
    )

    fill.Size = UDim2.new(percent, 0, 1, 0)
    knob.Position = UDim2.new(percent, 0, 0.5, 0)

    local sliding = false
    local slideInput

    local function updateFromX(x)
        if not hitbox.Parent or hitbox.AbsoluteSize.X <= 0 then
            return
        end

        local p = math.clamp(
            (x - hitbox.AbsolutePosition.X) / hitbox.AbsoluteSize.X,
            0,
            1
        )

        local value = math.floor(minValue + ((maxValue - minValue) * p) + 0.5)

        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, 0, 0.5, 0)
        valueLabel.Text = tostring(value)
        callback(value)
    end

    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            slideInput = input
            MenuPage.ScrollingEnabled = false
            updateFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not sliding then return end

        if input == slideInput
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromX(input.Position.X)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input == slideInput
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
            slideInput = nil
            MenuPage.ScrollingEnabled = true
        end
    end)

    return holder
end

--============================================================--
-- NOCLIP
--============================================================--

local function restoreCollisions()
    for part, canCollide in pairs(CollisionCache) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = canCollide
            end)
        end
    end

    CollisionCache = {}
end

makeToggle("NOCLIP", CFG.Noclip, function(enabled)
    CFG.Noclip = enabled

    if not enabled then
        restoreCollisions()
    end
end)

connect(RunService.Stepped, function()
    if not CFG.Noclip or not Character or not Character.Parent then
        return
    end

    for _, object in ipairs(Character:GetDescendants()) do
        if object:IsA("BasePart") then
            if CollisionCache[object] == nil then
                CollisionCache[object] = object.CanCollide
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

makeToggle("WALK SPEED", CFG.Walk, function(enabled)
    CFG.Walk = enabled

    if Humanoid and Humanoid.Parent then
        Humanoid.WalkSpeed = enabled and CFG.WalkSpeed or DefaultWalkSpeed
    end
end)

makeSlider(
    "Velocidade",
    CFG.WalkMin,
    CFG.WalkMax,
    CFG.WalkSpeed,
    function(value)
        CFG.WalkSpeed = value

        if CFG.Walk and Humanoid and Humanoid.Parent then
            Humanoid.WalkSpeed = value
        end
    end
)

connect(RunService.Heartbeat, function()
    if CFG.Walk
    and Humanoid
    and Humanoid.Parent
    and Humanoid.Health > 0
    and Humanoid.WalkSpeed ~= CFG.WalkSpeed then
        Humanoid.WalkSpeed = CFG.WalkSpeed
    end
end)

--============================================================--
-- FLY MOBILE
--============================================================--

local FlyAttachment
local FlyVelocity
local FlyOrientation
local FlyRenderConnection

local function destroyFly()
    if FlyRenderConnection then
        pcall(function()
            FlyRenderConnection:Disconnect()
        end)
        FlyRenderConnection = nil
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

local function flatCameraBasis(camera)
    local look = camera.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)

    if flatLook.Magnitude < 0.001 and Root then
        local rootLook = Root.CFrame.LookVector
        flatLook = Vector3.new(rootLook.X, 0, rootLook.Z)
    end

    if flatLook.Magnitude < 0.001 then
        flatLook = Vector3.new(0, 0, -1)
    end

    flatLook = flatLook.Unit

    local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)

    return flatLook, flatRight
end

local function startFly()
    destroyFly()

    if not Character or not Character.Parent then
        bindCharacter()
    end

    if not Humanoid or not Root or Humanoid.Health <= 0 then
        return
    end

    Humanoid.Sit = false
    Humanoid.AutoRotate = false

    pcall(function()
        Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end)

    Root.AssemblyLinearVelocity = Vector3.new(
        Root.AssemblyLinearVelocity.X,
        math.max(Root.AssemblyLinearVelocity.Y, 8),
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
    FlyVelocity.VectorVelocity = Vector3.zero

    pcall(function()
        FlyVelocity.MaxForce = math.huge
    end)

    pcall(function()
        FlyVelocity.ForceLimitsEnabled = false
    end)

    FlyVelocity.Parent = Root

    FlyOrientation = Instance.new("AlignOrientation")
    FlyOrientation.Name = "GrupoLuaFlyOrientation"
    FlyOrientation.Attachment0 = FlyAttachment
    FlyOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    FlyOrientation.RigidityEnabled = false
    FlyOrientation.Responsiveness = 28

    pcall(function()
        FlyOrientation.MaxTorque = math.huge
    end)

    pcall(function()
        FlyOrientation.MaxAngularVelocity = math.huge
    end)

    FlyOrientation.Parent = Root

    FlyRenderConnection = RunService.RenderStepped:Connect(function()
        if not CFG.Fly then
            return
        end

        if not Root
        or not Root.Parent
        or not Humanoid
        or not Humanoid.Parent
        or Humanoid.Health <= 0
        or not FlyVelocity
        or not FlyVelocity.Parent then
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then
            FlyVelocity.VectorVelocity = Vector3.zero
            return
        end

        local move = Humanoid.MoveDirection
        local desired = Vector3.zero

        if move.Magnitude > 0.001 then
            local flatLook, flatRight = flatCameraBasis(camera)
            local forwardInput = move:Dot(flatLook)
            local rightInput = move:Dot(flatRight)

            desired =
                (camera.CFrame.LookVector * forwardInput)
                +
                (camera.CFrame.RightVector * rightInput)

            if desired.Magnitude > 1 then
                desired = desired.Unit
            end
        end

        FlyVelocity.VectorVelocity = desired * CFG.FlySpeed

        local look = camera.CFrame.LookVector
        local facing = Vector3.new(look.X, 0, look.Z)

        if facing.Magnitude > 0.001 and FlyOrientation and FlyOrientation.Parent then
            FlyOrientation.CFrame = CFrame.lookAt(
                Root.Position,
                Root.Position + facing.Unit
            )
        end
    end)
end

makeToggle("FLY", CFG.Fly, function(enabled)
    CFG.Fly = enabled

    if enabled then
        startFly()
    else
        destroyFly()
    end
end)

makeSlider(
    "Fly Speed",
    CFG.FlyMin,
    CFG.FlyMax,
    CFG.FlySpeed,
    function(value)
        CFG.FlySpeed = value
    end
)

--============================================================--
-- ESP • NOME + AURA BRANCA
--============================================================--

local ESPObjects = {}

local function removeESP(plr)
    local data = ESPObjects[plr]

    if data then
        for _, object in pairs(data) do
            pcall(function()
                object:Destroy()
            end)
        end

        ESPObjects[plr] = nil
    end

    if plr and plr.Character then
        local old = plr.Character:FindFirstChild("GrupoLuaAura")
        if old then
            pcall(function()
                old:Destroy()
            end)
        end
    end
end

local function createESP(plr)
    if plr == LP or not CFG.ESP then
        return
    end

    removeESP(plr)

    local char = plr.Character
    if not char then return end

    local head = char:FindFirstChild("Head")
    if not head then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "GrupoLuaAura"
    highlight.Adornee = char
    highlight.FillColor = WHITE
    highlight.FillTransparency = 0.80
    highlight.OutlineColor = WHITE
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = char

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "GrupoLuaName_" .. tostring(plr.UserId)
    billboard.Adornee = head
    billboard.Size = UDim2.fromOffset(160, 28)
    billboard.StudsOffset = Vector3.new(0, 2.35, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = GUI

    local name = Instance.new("TextLabel")
    name.Size = UDim2.fromScale(1, 1)
    name.BackgroundTransparency = 1
    name.Text = plr.DisplayName
    name.TextColor3 = WHITE
    name.TextStrokeColor3 = Color3.new(0, 0, 0)
    name.TextStrokeTransparency = 0.2
    name.TextSize = 12
    name.Font = Enum.Font.GothamBold
    name.Parent = billboard

    ESPObjects[plr] = {
        highlight,
        billboard,
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

makeToggle("ESP • NOME + AURA", CFG.ESP, function(enabled)
    CFG.ESP = enabled
    refreshESP()
end)

--============================================================--
-- TELEPORTE • LISTA DE PLAYERS
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

local function teleportTo(plr)
    if not plr or plr == LP or not plr.Parent then
        return false
    end

    local targetCharacter = plr.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

    if not targetRoot then
        return false
    end

    if not Character or not Character.Parent or not Root or not Root.Parent then
        bindCharacter()
    end

    if not Character or not Character.Parent or not Root then
        return false
    end

    local destination = targetRoot.CFrame * CFrame.new(0, 1, 3)

    local ok = pcall(function()
        Character:PivotTo(destination)
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
    end)

    return ok
end

local function makePlayerRow(plr)
    if plr == LP then return end

    local row = Instance.new("Frame")
    row.Name = "Player_" .. tostring(plr.UserId)
    row.Size = UDim2.new(1, -3, 0, 38)
    row.BackgroundColor3 = ITEM
    row.BorderSizePixel = 0
    row.Parent = TeleportPage

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = row

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -66, 1, 0)
    name.Position = UDim2.fromOffset(10, 0)
    name.BackgroundTransparency = 1
    name.Text = plr.DisplayName
    name.TextColor3 = TEXT_OFF
    name.TextSize = 10
    name.Font = Enum.Font.GothamMedium
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Parent = row

    local tp = Instance.new("TextButton")
    tp.Size = UDim2.fromOffset(46, 26)
    tp.AnchorPoint = Vector2.new(1, 0.5)
    tp.Position = UDim2.new(1, -7, 0.5, 0)
    tp.BackgroundColor3 = WHITE
    tp.BorderSizePixel = 0
    tp.AutoButtonColor = false
    tp.Text = "TP"
    tp.TextColor3 = TEXT_ON
    tp.TextSize = 10
    tp.Font = Enum.Font.GothamBold
    tp.Parent = row

    local tpCorner = Instance.new("UICorner")
    tpCorner.CornerRadius = UDim.new(0, 7)
    tpCorner.Parent = tp

    tp.Activated:Connect(function()
        if not tp.Parent or not plr.Parent then
            return
        end

        local success = teleportTo(plr)
        tp.Text = success and "OK" or "..."

        task.delay(0.45, function()
            if tp and tp.Parent then
                tp.Text = "TP"
            end
        end)
    end)

    PlayerRows[plr] = row
end

local function refreshPlayerList()
    clearPlayerRows()

    local list = Players:GetPlayers()

    table.sort(list, function(a, b)
        return string.lower(a.DisplayName) < string.lower(b.DisplayName)
    end)

    for _, plr in ipairs(list) do
        if plr ~= LP then
            makePlayerRow(plr)
        end
    end
end

local function setupPlayer(plr)
    if plr == LP then return end

    connect(plr.CharacterAdded, function()
        task.wait(0.35)

        if CFG.ESP then
            createESP(plr)
        end
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do
    setupPlayer(plr)
end

connect(Players.PlayerAdded, function(plr)
    setupPlayer(plr)
    refreshPlayerList()
end)

connect(Players.PlayerRemoving, function(plr)
    removeESP(plr)
    task.defer(refreshPlayerList)
end)

refreshPlayerList()

--============================================================--
-- RESPAWN LOCAL
--============================================================--

connect(LP.CharacterAdded, function(char)
    destroyFly()
    restoreCollisions()

    task.wait(0.30)
    bindCharacter(char)

    if CFG.Walk and Humanoid then
        Humanoid.WalkSpeed = CFG.WalkSpeed
    end

    if CFG.Fly then
        task.wait(0.12)
        startFly()
    end
end)

--============================================================--
-- CLEANUP GLOBAL
--============================================================--

ENV.__GRUPO_LUA_MOBILE_CLEANUP = function()
    CFG.Noclip = false
    CFG.Walk = false
    CFG.Fly = false
    CFG.ESP = false

    destroyFly()
    restoreCollisions()

    local espPlayers = {}
    for plr in pairs(ESPObjects) do
        table.insert(espPlayers, plr)
    end

    for _, plr in ipairs(espPlayers) do
        removeESP(plr)
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.WalkSpeed = DefaultWalkSpeed
            Humanoid.AutoRotate = true
        end)
    end

    disconnectAll()

    pcall(function()
        GUI:Destroy()
    end)
end

print("GRUPO LUA MOBILE V3 carregado.")