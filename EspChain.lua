--==============================================================
-- CAFEÍNA • ESP MENU
--
-- FUNÇÕES
-- • ESP jogadores: aura branca + nome
-- • ESP CHAIN: aura vermelha + nome
-- • Linha vermelha até CHAIN
-- • Distância CHAIN no topo central
-- • Um único botão liga/desliga tudo
-- • Menu compacto expansível
-- • Fechar/recolher menu NÃO desliga o ESP
-- • Limpeza automática de personagens/CHAIN removidos
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local Camera = workspace.CurrentCamera

--==============================================================
-- STATE
--==============================================================

local State = {
    ESP = false,
    MenuOpen = false
}

local PlayerVisuals = {}

local CurrentChain = nil
local ChainHighlight = nil
local ChainBillboard = nil

--==============================================================
-- REMOVE MENU ANTIGO
--==============================================================

local oldGui = CoreGui:FindFirstChild("CafeinaESP")

if oldGui then
    oldGui:Destroy()
end

--==============================================================
-- GUI
--==============================================================

local GUI = Instance.new("ScreenGui")
GUI.Name = "CafeinaESP"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = true
GUI.DisplayOrder = 999999
GUI.Parent = CoreGui

--==============================================================
-- HELPERS
--==============================================================

local function getRoot(model)

    if not model then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model.PrimaryPart
end

local function isAlive(model)

    if not model or not model.Parent then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")

    if humanoid then
        return humanoid.Health > 0
    end

    return getRoot(model) ~= nil
end

--==============================================================
-- DISTÂNCIA CHAIN
--==============================================================

local DistanceLabel = Instance.new("TextLabel")

DistanceLabel.Name = "ChainDistance"

DistanceLabel.AnchorPoint =
    Vector2.new(0.5, 0)

DistanceLabel.Position =
    UDim2.new(0.5, 0, 0, 30)

DistanceLabel.Size =
    UDim2.fromOffset(140, 32)

DistanceLabel.BackgroundTransparency = 1

DistanceLabel.Text = ""

DistanceLabel.TextColor3 =
    Color3.fromRGB(255,255,255)

DistanceLabel.TextStrokeColor3 =
    Color3.fromRGB(0,0,0)

DistanceLabel.TextStrokeTransparency = 0

DistanceLabel.Font =
    Enum.Font.GothamBold

DistanceLabel.TextSize = 20

DistanceLabel.ZIndex = 999999

DistanceLabel.Visible = false

DistanceLabel.Parent = GUI

--==============================================================
-- LINHA CHAIN
--==============================================================

local ChainLine = Instance.new("Frame")

ChainLine.Name = "ChainLine"

ChainLine.AnchorPoint =
    Vector2.new(0.5,0.5)

ChainLine.BorderSizePixel = 0

ChainLine.BackgroundColor3 =
    Color3.fromRGB(255,20,20)

ChainLine.Size =
    UDim2.fromOffset(0,2)

ChainLine.Visible = false

-- abaixo do texto da distância
ChainLine.ZIndex = 999990

ChainLine.Parent = GUI

local function setLine(
    frame,
    x1,
    y1,
    x2,
    y2
)

    local dx = x2 - x1
    local dy = y2 - y1

    local length =
        math.sqrt(
            dx * dx +
            dy * dy
        )

    local angle =
        math.deg(
            math.atan2(
                dy,
                dx
            )
        )

    frame.Position =
        UDim2.fromOffset(
            (x1 + x2) / 2,
            (y1 + y2) / 2
        )

    frame.Size =
        UDim2.fromOffset(
            length,
            2
        )

    frame.Rotation = angle
end

--==============================================================
-- PLAYER ESP
--==============================================================

local function destroyPlayerESP(player)

    local data =
        PlayerVisuals[player]

    if not data then
        return
    end

    if data.Highlight then
        pcall(function()
            data.Highlight:Destroy()
        end)
    end

    if data.Billboard then
        pcall(function()
            data.Billboard:Destroy()
        end)
    end

    PlayerVisuals[player] = nil
end

local function createPlayerESP(player)

    if player == LocalPlayer then
        return
    end

    destroyPlayerESP(player)

    local character =
        player.Character

    if not character
    or not character.Parent
    or not isAlive(character) then
        return
    end

    local root =
        getRoot(character)

    if not root then
        return
    end

    --==========================================================
    -- WHITE AURA
    --==========================================================

    local highlight =
        Instance.new("Highlight")

    highlight.Name =
        "CafeinaPlayerESP"

    highlight.Adornee =
        character

    highlight.FillColor =
        Color3.fromRGB(
            255,
            255,
            255
        )

    highlight.FillTransparency =
        0.78

    highlight.OutlineColor =
        Color3.fromRGB(
            255,
            255,
            255
        )

    highlight.OutlineTransparency =
        0

    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    highlight.Enabled =
        State.ESP

    highlight.Parent =
        character

    --==========================================================
    -- PLAYER NAME
    --==========================================================

    local billboard =
        Instance.new("BillboardGui")

    billboard.Name =
        "CafeinaPlayerName"

    billboard.Adornee =
        root

    billboard.Size =
        UDim2.fromOffset(
            180,
            30
        )

    billboard.StudsOffset =
        Vector3.new(
            0,
            3.1,
            0
        )

    billboard.AlwaysOnTop =
        true

    billboard.Enabled =
        State.ESP

    billboard.Parent =
        GUI

    local text =
        Instance.new("TextLabel")

    text.Size =
        UDim2.fromScale(
            1,
            1
        )

    text.BackgroundTransparency =
        1

    text.Text =
        player.DisplayName

    text.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )

    text.TextStrokeColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )

    text.TextStrokeTransparency =
        0

    text.Font =
        Enum.Font.GothamBold

    text.TextSize =
        15

    text.Parent =
        billboard

    PlayerVisuals[player] = {
        Character = character,
        Highlight = highlight,
        Billboard = billboard
    }
end

local function refreshPlayers()

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player ~= LocalPlayer then

            if State.ESP then

                local character =
                    player.Character

                local data =
                    PlayerVisuals[player]

                if character
                and isAlive(character) then

                    if not data
                    or data.Character ~= character
                    or not data.Highlight
                    or not data.Highlight.Parent
                    or not data.Billboard
                    or not data.Billboard.Parent then

                        createPlayerESP(player)

                    else

                        data.Highlight.Enabled =
                            true

                        data.Billboard.Enabled =
                            true
                    end

                else

                    destroyPlayerESP(player)
                end

            else

                destroyPlayerESP(player)
            end
        end
    end
end

--==============================================================
-- PLAYER CONNECTIONS
--==============================================================

local function setupPlayer(player)

    if player == LocalPlayer then
        return
    end

    player.CharacterAdded:Connect(
        function(character)

            task.spawn(function()

                local root =
                    character:WaitForChild(
                        "HumanoidRootPart",
                        5
                    )

                if State.ESP
                and root
                and character.Parent then

                    createPlayerESP(player)
                end
            end)
        end
    )

    player.CharacterRemoving:Connect(
        function()

            destroyPlayerESP(player)
        end
    )

    if player.Character
    and State.ESP then

        createPlayerESP(player)
    end
end

for _, player in ipairs(
    Players:GetPlayers()
) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(
    setupPlayer
)

Players.PlayerRemoving:Connect(
    function(player)

        destroyPlayerESP(player)
    end
)

--==============================================================
-- FIND CHAIN
--==============================================================

local function findChain()

    local misc =
        workspace:FindFirstChild(
            "Misc"
        )

    if not misc then
        return nil
    end

    local ai =
        misc:FindFirstChild(
            "AI"
        )

    if not ai then
        return nil
    end

    return ai:FindFirstChild(
        "CHAIN"
    )
end

--==============================================================
-- CHAIN CLEANUP
--==============================================================

local function clearChainVisuals()

    if ChainHighlight then

        pcall(function()
            ChainHighlight:Destroy()
        end)

        ChainHighlight = nil
    end

    if ChainBillboard then

        pcall(function()
            ChainBillboard:Destroy()
        end)

        ChainBillboard = nil
    end

    ChainLine.Visible = false

    DistanceLabel.Visible = false
    DistanceLabel.Text = ""
end

--==============================================================
-- CREATE CHAIN ESP
--==============================================================

local function createChainESP(chain)

    clearChainVisuals()

    if not chain
    or not chain.Parent then
        return
    end

    local root =
        getRoot(chain)

    if not root then
        return
    end

    --==========================================================
    -- RED AURA
    --==========================================================

    ChainHighlight =
        Instance.new("Highlight")

    ChainHighlight.Name =
        "CafeinaChainESP"

    ChainHighlight.Adornee =
        chain

    ChainHighlight.FillColor =
        Color3.fromRGB(
            255,
            20,
            20
        )

    ChainHighlight.FillTransparency =
        0.72

    ChainHighlight.OutlineColor =
        Color3.fromRGB(
            255,
            0,
            0
        )

    ChainHighlight.OutlineTransparency =
        0

    ChainHighlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    ChainHighlight.Parent =
        chain

    --==========================================================
    -- CHAIN NAME
    --==========================================================

    ChainBillboard =
        Instance.new("BillboardGui")

    ChainBillboard.Name =
        "CafeinaChainName"

    ChainBillboard.Adornee =
        root

    ChainBillboard.Size =
        UDim2.fromOffset(
            140,
            30
        )

    ChainBillboard.StudsOffset =
        Vector3.new(
            0,
            3.4,
            0
        )

    ChainBillboard.AlwaysOnTop =
        true

    ChainBillboard.Parent =
        GUI

    local text =
        Instance.new("TextLabel")

    text.Size =
        UDim2.fromScale(
            1,
            1
        )

    text.BackgroundTransparency =
        1

    text.Text =
        "CHAIN"

    text.TextColor3 =
        Color3.fromRGB(
            255,
            35,
            35
        )

    text.TextStrokeColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )

    text.TextStrokeTransparency =
        0

    text.Font =
        Enum.Font.GothamBold

    text.TextSize =
        16

    text.Parent =
        ChainBillboard
end

--==============================================================
-- UPDATE CHAIN LINE
--
-- A linha começa ABAIXO da distância.
-- Ela nunca atravessa o texto.
--==============================================================

local function updateChainLine(
    chainRoot
)

    if not State.ESP
    or not chainRoot
    or not Camera then

        ChainLine.Visible =
            false

        return
    end

    local screenPos,
        onScreen =
        Camera:WorldToViewportPoint(
            chainRoot.Position
        )

    if not onScreen
    or screenPos.Z <= 0 then

        ChainLine.Visible =
            false

        return
    end

    local viewport =
        Camera.ViewportSize

    ------------------------------------------------------------
    -- DistanceLabel:
    -- Y inicial = 30
    -- altura = 32
    --
    -- bottom = 62
    --
    -- margem extra = 8px
    ------------------------------------------------------------

    local startX =
        viewport.X / 2

    local startY =
        70

    setLine(
        ChainLine,
        startX,
        startY,
        screenPos.X,
        screenPos.Y
    )

    ChainLine.Visible =
        true
end

--==============================================================
-- MENU PRINCIPAL
--==============================================================

local MainButton =
    Instance.new("TextButton")

MainButton.Name =
    "MainButton"

MainButton.Position =
    UDim2.new(
        0,
        14,
        0.42,
        0
    )

MainButton.Size =
    UDim2.fromOffset(
        108,
        34
    )

MainButton.BackgroundColor3 =
    Color3.fromRGB(
        22,
        22,
        26
    )

MainButton.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

MainButton.Font =
    Enum.Font.GothamBold

MainButton.TextSize =
    12

MainButton.Text =
    "CAFEÍNA ESP"

MainButton.AutoButtonColor =
    true

MainButton.ZIndex =
    100

MainButton.Parent =
    GUI

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

MainCorner.Parent =
    MainButton

--==============================================================
-- PANEL
--==============================================================

local Panel =
    Instance.new("Frame")

Panel.Name =
    "Panel"

Panel.Position =
    UDim2.new(
        0,
        14,
        0.42,
        38
    )

Panel.Size =
    UDim2.fromOffset(
        108,
        0
    )

Panel.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        22
    )

Panel.ClipsDescendants =
    true

Panel.Visible =
    false

Panel.ZIndex =
    90

Panel.Parent =
    GUI

local PanelCorner =
    Instance.new("UICorner")

PanelCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

PanelCorner.Parent =
    Panel

--==============================================================
-- ESP TOGGLE
--==============================================================

local ESPButton =
    Instance.new("TextButton")

ESPButton.Name =
    "ESPButton"

ESPButton.Position =
    UDim2.fromOffset(
        5,
        5
    )

ESPButton.Size =
    UDim2.new(
        1,
        -10,
        0,
        31
    )

ESPButton.BackgroundColor3 =
    Color3.fromRGB(
        32,
        32,
        38
    )

ESPButton.TextColor3 =
    Color3.fromRGB(
        190,
        190,
        190
    )

ESPButton.Font =
    Enum.Font.GothamMedium

ESPButton.TextSize =
    12

ESPButton.Text =
    "ESP : OFF"

ESPButton.ZIndex =
    100

ESPButton.Parent =
    Panel

local ESPCorner =
    Instance.new("UICorner")

ESPCorner.CornerRadius =
    UDim.new(
        0,
        6
    )

ESPCorner.Parent =
    ESPButton

--==============================================================
-- ACTIVATE / DEACTIVATE EVERYTHING
--==============================================================

local function setESP(enabled)

    State.ESP = enabled

    if enabled then

        ESPButton.Text =
            "ESP : ON"

        ESPButton.TextColor3 =
            Color3.fromRGB(
                255,
                255,
                255
            )

        refreshPlayers()

        local chain =
            findChain()

        CurrentChain =
            chain

        if chain then
            createChainESP(chain)
        end

    else

        ESPButton.Text =
            "ESP : OFF"

        ESPButton.TextColor3 =
            Color3.fromRGB(
                190,
                190,
                190
            )

        for player in pairs(
            PlayerVisuals
        ) do

            destroyPlayerESP(
                player
            )
        end

        clearChainVisuals()
    end
end

ESPButton.MouseButton1Click:Connect(
    function()

        setESP(
            not State.ESP
        )
    end
)

--==============================================================
-- OPEN / CLOSE PANEL
--
-- Recolher o painel não altera State.ESP
--==============================================================

MainButton.MouseButton1Click:Connect(
    function()

        State.MenuOpen =
            not State.MenuOpen

        if State.MenuOpen then

            Panel.Visible = true

            Panel:TweenSize(
                UDim2.fromOffset(
                    108,
                    41
                ),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.14,
                true
            )

        else

            Panel:TweenSize(
                UDim2.fromOffset(
                    108,
                    0
                ),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.14,
                true,
                function()

                    if not State.MenuOpen then
                        Panel.Visible = false
                    end
                end
            )
        end
    end
)

--==============================================================
-- MAIN LOOP
--==============================================================

local refreshTimer = 0

RunService.RenderStepped:Connect(
    function(dt)

        Camera =
            workspace.CurrentCamera

        if not State.ESP then

            ChainLine.Visible =
                false

            DistanceLabel.Visible =
                false

            return
        end

        --======================================================
        -- REFRESH PLAYERS
        --
        -- Não precisa recriar ESP em todo frame.
        --======================================================

        refreshTimer += dt

        if refreshTimer >= 0.5 then

            refreshTimer = 0

            refreshPlayers()
        end

        --======================================================
        -- FIND / VALIDATE CHAIN
        --======================================================

        local foundChain =
            findChain()

        if foundChain ~= CurrentChain then

            clearChainVisuals()

            CurrentChain =
                foundChain

            if CurrentChain then

                createChainESP(
                    CurrentChain
                )
            end
        end

        if not CurrentChain
        or not CurrentChain.Parent
        or not isAlive(CurrentChain) then

            CurrentChain = nil

            clearChainVisuals()

            return
        end

        local chainRoot =
            getRoot(
                CurrentChain
            )

        if not chainRoot
        or not chainRoot.Parent then

            ChainLine.Visible =
                false

            DistanceLabel.Visible =
                false

            return
        end

        --======================================================
        -- RESTORE CHAIN VISUALS IF NECESSARY
        --======================================================

        if not ChainHighlight
        or not ChainHighlight.Parent
        or not ChainBillboard
        or not ChainBillboard.Parent then

            createChainESP(
                CurrentChain
            )
        end

        --======================================================
        -- DISTANCE
        --======================================================

        local myCharacter =
            LocalPlayer.Character

        local myRoot =
            getRoot(
                myCharacter
            )

        if myRoot
        and myRoot.Parent then

            local distance =
                (
                    myRoot.Position
                    -
                    chainRoot.Position
                ).Magnitude

            DistanceLabel.Text =
                tostring(
                    math.floor(
                        distance + 0.5
                    )
                )
                ..
                "m"

            DistanceLabel.Visible =
                true

        else

            DistanceLabel.Visible =
                false
        end

        --======================================================
        -- LINE
        --======================================================

        updateChainLine(
            chainRoot
        )
    end
)

--==============================================================
-- INITIAL CLEAN STATE
--==============================================================

setESP(false)
