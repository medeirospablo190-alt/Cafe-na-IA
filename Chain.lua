--==============================================================--
-- CAFEÍNA • CHAIN MENU MOBILE
-- Compacto • Preto • Touch
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    GUI_NAME = "CafeinaChainMobile",

    WIDTH = 260,
    HEIGHT = 245,

    MAX_CHAIN_DISTANCE = 35,

    DEFENSE_COOLDOWN = 0.12,

    DEFENSE_NAMES = {
        "defend",
        "defense",
        "defesa",
        "block",
        "bloquear",
        "parry",
        "guard",
    }
}

--==============================================================--
-- ESTADO
--==============================================================--

local AutoDefenseEnabled = false
local NoDamageEnabled = false
local Destroyed = false

local LastDefense = 0

local ChainConnections = {}
local CharacterConnections = {}

local SafetyConnection
local CharacterAddedConnection

--==============================================================--
-- HELPERS
--==============================================================--

local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function disconnectTable(tbl)
    for _, connection in ipairs(tbl) do
        disconnect(connection)
    end

    table.clear(tbl)
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid(character)
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
end

--==============================================================--
-- CHAIN
--==============================================================--

local function getChain()

    local misc = Workspace:FindFirstChild("Misc")
    if not misc then
        return nil
    end

    local ai = misc:FindFirstChild("AI")
    if not ai then
        return nil
    end

    return ai:FindFirstChild("CHAIN")

end

local function getChainRoot(chain)

    if not chain then
        return nil
    end

    return chain:FindFirstChild("HumanoidRootPart")
        or chain:FindFirstChild("Torso")
        or chain.PrimaryPart

end

local function chainNear()

    local chain = getChain()
    if not chain then
        return false
    end

    local playerRoot = getRoot(getCharacter())
    local chainRoot = getChainRoot(chain)

    if not playerRoot or not chainRoot then
        return true
    end

    return
        (playerRoot.Position - chainRoot.Position).Magnitude
        <= CONFIG.MAX_CHAIN_DISTANCE

end

--==============================================================--
-- LOCALIZAR BOTÃO MOBILE DE DEFESA
--==============================================================--

local function nameLooksDefensive(name)

    name = string.lower(name)

    for _, keyword in ipairs(CONFIG.DEFENSE_NAMES) do

        if string.find(name, keyword, 1, true) then
            return true
        end

    end

    return false

end

local function findDefenseButton()

    local playerGui =
        LocalPlayer:FindFirstChildOfClass("PlayerGui")

    if not playerGui then
        return nil
    end

    for _, obj in ipairs(playerGui:GetDescendants()) do

        if
            (obj:IsA("TextButton")
            or obj:IsA("ImageButton"))
            and obj.Visible
            and nameLooksDefensive(obj.Name)
        then

            return obj

        end

        if obj:IsA("TextButton") then

            if nameLooksDefensive(obj.Text) then
                return obj
            end

        end

    end

    return nil

end

--==============================================================--
-- DEFESA MOBILE
--==============================================================--

local function pressGuiButton(button)

    if not button then
        return false
    end

    -- Alguns executores expõem firesignal.
    if firesignal then

        local ok = pcall(function()
            firesignal(button.Activated)
        end)

        if ok then
            return true
        end

        ok = pcall(function()
            firesignal(button.MouseButton1Click)
        end)

        if ok then
            return true
        end

    end

    return false

end

local function defend()

    if not AutoDefenseEnabled then
        return
    end

    if not chainNear() then
        return
    end

    local now = os.clock()

    if now - LastDefense < CONFIG.DEFENSE_COOLDOWN then
        return
    end

    LastDefense = now

    local button = findDefenseButton()

    if button then
        pressGuiButton(button)
    end

end

--==============================================================--
-- DETECÇÃO DE ATAQUE
--==============================================================--

local function looksLikeAttack(obj)

    if not obj then
        return false
    end

    local n = string.lower(obj.Name)

    return
        string.find(n, "windup", 1, true)
        or string.find(n, "swing", 1, true)
        or string.find(n, "attack", 1, true)
        or string.find(n, "bladehit", 1, true)
        or string.find(n, "clash", 1, true)

end

local function stopChainMonitoring()
    disconnectTable(ChainConnections)
end

local function startChainMonitoring()

    stopChainMonitoring()

    local chain = getChain()

    if not chain then
        return
    end

    table.insert(
        ChainConnections,

        chain.DescendantAdded:Connect(function(obj)

            if AutoDefenseEnabled
            and looksLikeAttack(obj) then

                defend()

            end

        end)
    )

    for _, attribute in ipairs({
        "Charging",
        "CanSwing",
        "Clashing",
    }) do

        table.insert(
            ChainConnections,

            chain:GetAttributeChangedSignal(attribute):Connect(function()

                if not AutoDefenseEnabled then
                    return
                end

                if chain:GetAttribute(attribute) == true then
                    defend()
                end

            end)
        )

    end

end

task.spawn(function()

    local lastChain

    while not Destroyed do

        task.wait(0.5)

        if AutoDefenseEnabled then

            local chain = getChain()

            if chain ~= lastChain then

                lastChain = chain

                if chain then
                    startChainMonitoring()
                else
                    stopChainMonitoring()
                end

            end

        else
            lastChain = nil
        end

    end

end)

--==============================================================--
-- SEM DANO / ANTI RESET LOCAL
--==============================================================--

local function disableReset()

    task.spawn(function()

        for _ = 1, 6 do

            if not NoDamageEnabled then
                return
            end

            local ok = pcall(function()

                StarterGui:SetCore(
                    "ResetButtonCallback",
                    false
                )

            end)

            if ok then
                break
            end

            task.wait(0.4)

        end

    end)

end

local function restoreReset()

    pcall(function()

        StarterGui:SetCore(
            "ResetButtonCallback",
            true
        )

    end)

end

local function protectCharacter(character)

    disconnectTable(CharacterConnections)

    local humanoid =
        getHumanoid(character)
        or character:WaitForChild("Humanoid", 8)

    if not humanoid then
        return
    end

    disableReset()

    pcall(function()
        humanoid.BreakJointsOnDeath = false
    end)

    pcall(function()

        humanoid:SetStateEnabled(
            Enum.HumanoidStateType.Dead,
            false
        )

    end)

    pcall(function()

        humanoid:SetStateEnabled(
            Enum.HumanoidStateType.Ragdoll,
            false
        )

    end)

    pcall(function()

        humanoid:SetStateEnabled(
            Enum.HumanoidStateType.FallingDown,
            false
        )

    end)

    table.insert(
        CharacterConnections,

        humanoid.HealthChanged:Connect(function(health)

            if not NoDamageEnabled then
                return
            end

            if health < humanoid.MaxHealth then

                pcall(function()
                    humanoid.Health = humanoid.MaxHealth
                end)

            end

        end)
    )

    table.insert(
        CharacterConnections,

        humanoid.StateChanged:Connect(function(_, state)

            if not NoDamageEnabled then
                return
            end

            if
                state == Enum.HumanoidStateType.Dead
                or state == Enum.HumanoidStateType.Ragdoll
                or state == Enum.HumanoidStateType.FallingDown
            then

                pcall(function()
                    humanoid.Health = humanoid.MaxHealth
                end)

                pcall(function()

                    humanoid:ChangeState(
                        Enum.HumanoidStateType.GettingUp
                    )

                end)

            end

        end)
    )

end

local function startSafetyLoop()

    disconnect(SafetyConnection)

    SafetyConnection =
        RunService.Heartbeat:Connect(function()

            if not NoDamageEnabled then
                return
            end

            local character = getCharacter()
            local humanoid = getHumanoid(character)

            if not humanoid then
                return
            end

            if humanoid.Health < humanoid.MaxHealth then

                pcall(function()
                    humanoid.Health = humanoid.MaxHealth
                end)

            end

            pcall(function()
                humanoid.BreakJointsOnDeath = false
            end)

        end)

end

local function enableNoDamage()

    if NoDamageEnabled then
        return
    end

    NoDamageEnabled = true

    disableReset()

    local character = getCharacter()

    if character then
        protectCharacter(character)
    end

    startSafetyLoop()

end

local function disableNoDamage()

    NoDamageEnabled = false

    disconnectTable(CharacterConnections)
    disconnect(SafetyConnection)

    SafetyConnection = nil

    restoreReset()

end

CharacterAddedConnection =
    LocalPlayer.CharacterAdded:Connect(function(character)

        if NoDamageEnabled then

            task.wait(0.1)
            protectCharacter(character)

        end

    end)

--==============================================================--
-- GUI CLEANUP
--==============================================================--

pcall(function()

    local old = CoreGui:FindFirstChild(CONFIG.GUI_NAME)

    if old then
        old:Destroy()
    end

end)

--==============================================================--
-- GUI
--==============================================================--

local gui = Instance.new("ScreenGui")

gui.Name = CONFIG.GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local parent

pcall(function()

    if gethui then
        parent = gethui()
    end

end)

if not parent then
    parent = CoreGui
end

gui.Parent = parent

--==============================================================--
-- CORES
--==============================================================--

local BLACK = Color3.fromRGB(8,8,9)
local BLACK2 = Color3.fromRGB(14,14,15)
local BLACK3 = Color3.fromRGB(22,22,24)

local WHITE = Color3.fromRGB(240,240,240)
local GRAY = Color3.fromRGB(135,135,140)

--==============================================================--
-- MAIN
--==============================================================--

local main = Instance.new("Frame")

main.Size = UDim2.fromOffset(
    CONFIG.WIDTH,
    CONFIG.HEIGHT
)

main.Position = UDim2.new(
    0.5,
    -(CONFIG.WIDTH / 2),
    0.5,
    -(CONFIG.HEIGHT / 2)
)

main.BackgroundColor3 = BLACK
main.BorderSizePixel = 0
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0,10)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(40,40,42)
mainStroke.Thickness = 1
mainStroke.Parent = main

--==============================================================--
-- HEADER
--==============================================================--

local header = Instance.new("Frame")

header.Size = UDim2.new(1,0,0,42)
header.BackgroundTransparency = 1
header.Parent = main

local title = Instance.new("TextLabel")

title.Size = UDim2.new(1,-82,1,0)
title.Position = UDim2.fromOffset(14,0)

title.BackgroundTransparency = 1

title.Text = "CAFEÍNA  |  CHAIN"
title.TextColor3 = WHITE

title.Font = Enum.Font.GothamBold
title.TextSize = 14

title.TextXAlignment =
    Enum.TextXAlignment.Left

title.Parent = header

local minimize = Instance.new("TextButton")

minimize.Size = UDim2.fromOffset(36,36)
minimize.Position = UDim2.new(1,-76,0,3)

minimize.BackgroundTransparency = 1
minimize.Text = "−"

minimize.TextColor3 = WHITE
minimize.TextSize = 22

minimize.Font = Enum.Font.GothamBold

minimize.Parent = header

local close = Instance.new("TextButton")

close.Size = UDim2.fromOffset(36,36)
close.Position = UDim2.new(1,-39,0,3)

close.BackgroundTransparency = 1
close.Text = "×"

close.TextColor3 = WHITE
close.TextSize = 23

close.Font = Enum.Font.GothamBold

close.Parent = header

local line = Instance.new("Frame")

line.Size = UDim2.new(1,0,0,1)
line.Position = UDim2.fromOffset(0,41)

line.BackgroundColor3 =
    Color3.fromRGB(35,35,37)

line.BorderSizePixel = 0
line.Parent = main

--==============================================================--
-- CARD CREATOR
--==============================================================--

local function createRow(y, titleText, descText)

    local row = Instance.new("Frame")

    row.Size =
        UDim2.new(1,-20,0,70)

    row.Position =
        UDim2.fromOffset(10,y)

    row.BackgroundColor3 = BLACK2
    row.BorderSizePixel = 0

    row.Parent = main

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,8)
    c.Parent = row

    local titleLabel =
        Instance.new("TextLabel")

    titleLabel.Size =
        UDim2.new(1,-92,0,25)

    titleLabel.Position =
        UDim2.fromOffset(12,9)

    titleLabel.BackgroundTransparency = 1

    titleLabel.Text = titleText
    titleLabel.TextColor3 = WHITE

    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamBold

    titleLabel.TextXAlignment =
        Enum.TextXAlignment.Left

    titleLabel.Parent = row

    local desc =
        Instance.new("TextLabel")

    desc.Size =
        UDim2.new(1,-92,0,28)

    desc.Position =
        UDim2.fromOffset(12,33)

    desc.BackgroundTransparency = 1

    desc.Text = descText
    desc.TextColor3 = GRAY

    desc.TextSize = 10
    desc.TextWrapped = true

    desc.Font = Enum.Font.Gotham

    desc.TextXAlignment =
        Enum.TextXAlignment.Left

    desc.TextYAlignment =
        Enum.TextYAlignment.Top

    desc.Parent = row

    local button =
        Instance.new("TextButton")

    button.Size =
        UDim2.fromOffset(58,38)

    button.Position =
        UDim2.new(1,-70,0.5,-19)

    button.BackgroundColor3 = BLACK3

    button.Text = "OFF"
    button.TextColor3 = GRAY

    button.TextSize = 13
    button.Font = Enum.Font.GothamBold

    button.AutoButtonColor = false

    button.Parent = row

    local bc =
        Instance.new("UICorner")

    bc.CornerRadius =
        UDim.new(0,8)

    bc.Parent = button

    return button

end

--==============================================================--
-- ROWS
--==============================================================--

local defenseButton =
    createRow(
        52,
        "CHAIN DEFESA",
        "Defesa automática mobile."
    )

local damageButton =
    createRow(
        130,
        "SEM DANO",
        "Proteção local contra dano/reset."
    )

--==============================================================--
-- STATUS
--==============================================================--

local status =
    Instance.new("TextLabel")

status.Size =
    UDim2.new(1,-20,0,24)

status.Position =
    UDim2.fromOffset(10,208)

status.BackgroundTransparency = 1

status.Text =
    "STATUS: DESATIVADO"

status.TextColor3 = GRAY

status.TextSize = 10
status.Font = Enum.Font.GothamBold

status.TextXAlignment =
    Enum.TextXAlignment.Left

status.Parent = main

--==============================================================--
-- UI STATE
--==============================================================--

local function updateButton(button, enabled)

    if enabled then

        button.Text = "ON"

        button.BackgroundColor3 =
            Color3.fromRGB(230,230,230)

        button.TextColor3 =
            Color3.fromRGB(10,10,10)

    else

        button.Text = "OFF"

        button.BackgroundColor3 = BLACK3
        button.TextColor3 = GRAY

    end

end

local function updateStatus()

    if AutoDefenseEnabled and NoDamageEnabled then

        status.Text =
            "STATUS: DEFESA + SEM DANO"

        status.TextColor3 = WHITE

    elseif AutoDefenseEnabled then

        status.Text =
            "STATUS: DEFESA ATIVA"

        status.TextColor3 = WHITE

    elseif NoDamageEnabled then

        status.Text =
            "STATUS: SEM DANO ATIVO"

        status.TextColor3 = WHITE

    else

        status.Text =
            "STATUS: DESATIVADO"

        status.TextColor3 = GRAY

    end

end

--==============================================================--
-- TOGGLES
--==============================================================--

defenseButton.Activated:Connect(function()

    AutoDefenseEnabled =
        not AutoDefenseEnabled

    if AutoDefenseEnabled then
        startChainMonitoring()
    else
        stopChainMonitoring()
    end

    updateButton(
        defenseButton,
        AutoDefenseEnabled
    )

    updateStatus()

end)

damageButton.Activated:Connect(function()

    if NoDamageEnabled then
        disableNoDamage()
    else
        enableNoDamage()
    end

    updateButton(
        damageButton,
        NoDamageEnabled
    )

    updateStatus()

end)

--==============================================================--
-- DRAG MOBILE
--==============================================================--

local dragging = false
local dragStart
local startPosition
local dragInput

header.InputBegan:Connect(function(input)

    if
        input.UserInputType == Enum.UserInputType.Touch
        or
        input.UserInputType == Enum.UserInputType.MouseButton1
    then

        dragging = true

        dragStart = input.Position
        startPosition = main.Position

    end

end)

header.InputChanged:Connect(function(input)

    if
        input.UserInputType == Enum.UserInputType.Touch
        or
        input.UserInputType == Enum.UserInputType.MouseMovement
    then

        dragInput = input

    end

end)

UserInputService.InputChanged:Connect(function(input)

    if dragging and input == dragInput then

        local delta =
            input.Position - dragStart

        main.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )

    end

end)

UserInputService.InputEnded:Connect(function(input)

    if
        input.UserInputType == Enum.UserInputType.Touch
        or
        input.UserInputType == Enum.UserInputType.MouseButton1
    then

        dragging = false

    end

end)

--==============================================================--
-- MINIMIZE
--==============================================================--

local restore =
    Instance.new("TextButton")

restore.Size =
    UDim2.fromOffset(46,46)

restore.Position =
    UDim2.new(0.5,-23,0.5,-23)

restore.BackgroundColor3 = BLACK

restore.Text = "C"
restore.TextColor3 = WHITE

restore.TextSize = 17
restore.Font = Enum.Font.GothamBold

restore.Visible = false
restore.Parent = gui

local restoreCorner =
    Instance.new("UICorner")

restoreCorner.CornerRadius =
    UDim.new(1,0)

restoreCorner.Parent =
    restore

local restoreStroke =
    Instance.new("UIStroke")

restoreStroke.Color =
    Color3.fromRGB(45,45,47)

restoreStroke.Parent =
    restore

minimize.Activated:Connect(function()

    main.Visible = false
    restore.Visible = true

end)

restore.Activated:Connect(function()

    restore.Visible = false
    main.Visible = true

end)

--==============================================================--
-- CLOSE
--==============================================================--

close.Activated:Connect(function()

    Destroyed = true

    AutoDefenseEnabled = false

    disableNoDamage()
    stopChainMonitoring()

    disconnectTable(CharacterConnections)

    disconnect(CharacterAddedConnection)
    disconnect(SafetyConnection)

    gui:Destroy()

end)

--==============================================================--
-- INIT
--==============================================================--

updateButton(defenseButton,false)
updateButton(damageButton,false)
updateStatus()
