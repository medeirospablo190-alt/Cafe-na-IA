--[[
===============================================================
 CAFEÍNA • MOBILE COMBAT / ESP / TP
 REBUILD V4

 Estrutura:
   ESP [ON/OFF] [▼]
      Box
      Distância
      Aura inimigos
      Players
      Bots

   IBOT [ON/OFF] [▼]
      Focar na cabeça

   TELEPORTE [▼]
      Player mais próximo
      Voltar à base
      Aliados

   IGNORE WALL [ON/OFF]

 MOBILE:
   • Menu compacto
   • Arrastável
   • Scroll automático
   • Minimizar
   • Ícone restaurador
   • Fechar = shutdown total

 IMPORTANTE:
   Ignore Wall aqui desativa somente o LOS LOCAL usado
   para seleção de alvo. Não altera validação de dano
   existente no servidor.
===============================================================
]]


--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local RunService =
    game:GetService("RunService")

local UserInputService =
    game:GetService("UserInputService")

local Workspace =
    game:GetService("Workspace")


--==============================================================
-- LOCAL
--==============================================================

local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")


--==============================================================
-- GLOBAL RUNTIME
-- Evita duas versões do script rodando simultaneamente.
--==============================================================

local GlobalEnvironment

if type(getgenv) == "function" then

    local Success,
        Environment =
        pcall(getgenv)

    if Success and Environment then
        GlobalEnvironment = Environment
    end
end

GlobalEnvironment =
    GlobalEnvironment or _G


if GlobalEnvironment.CafeinaMobileRuntime
and type(
    GlobalEnvironment.CafeinaMobileRuntime.Shutdown
) == "function" then

    pcall(
        GlobalEnvironment.CafeinaMobileRuntime.Shutdown
    )
end


local Runtime = {}

GlobalEnvironment.CafeinaMobileRuntime =
    Runtime


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    -- ESP

    ESPEnabled = false,

    ESPBox = true,

    ESPDistance = true,

    ESPEnemyAura = true,

    ESPPlayers = true,

    ESPBots = true,

    ESPMaxDistance = 5000,

    ESPInterval = 1 / 35,


    -- IBOT

    IBotEnabled = false,

    IBotHead = true,

    IBotMaxDistance = 1500,

    IBotSmoothness = 0.22,

    IBotInterval = 1 / 60,


    -- TELEPORT

    TeleportDistance = 35,

    TeleportBehindDistance = 5.5,

    AllyTeleportDistance = 5,

    TeleportInterval = 0.10,


    -- TESTE LOCAL

    IgnoreWalls = false
}


--==============================================================
-- UI STATE
--==============================================================

local STATE = {

    Closed = false,

    Minimized = false,

    ESPExpanded = false,

    IBotExpanded = false,

    TeleportExpanded = false,

    TPMode = false
}


--==============================================================
-- COLORS
--==============================================================

local COLORS = {

    Background =
        Color3.fromRGB(
            12,
            12,
            15
        ),

    Panel =
        Color3.fromRGB(
            21,
            21,
            25
        ),

    Panel2 =
        Color3.fromRGB(
            29,
            29,
            34
        ),

    Button =
        Color3.fromRGB(
            34,
            34,
            39
        ),

    Disabled =
        Color3.fromRGB(
            48,
            48,
            54
        ),

    Text =
        Color3.fromRGB(
            245,
            245,
            248
        ),

    Muted =
        Color3.fromRGB(
            142,
            142,
            153
        ),

    Stroke =
        Color3.fromRGB(
            59,
            59,
            67
        ),

    Red =
        Color3.fromRGB(
            255,
            48,
            58
        ),

    Green =
        Color3.fromRGB(
            48,
            220,
            88
        ),

    Ally =
        Color3.fromRGB(
            50,
            255,
            95
        ),

    Enemy =
        Color3.fromRGB(
            255,
            55,
            62
        ),

    White =
        Color3.fromRGB(
            255,
            255,
            255
        )
}


--==============================================================
-- RUNTIME TABLES
--==============================================================

local Connections = {}

local AllyConnections = {}

local ESPObjects = {}

local CurrentTPTarget = nil

local TeleportReady = false

local LastESP = 0

local LastTP = 0

local LastIBot = 0

local LastAllyRefresh = 0


--==============================================================
-- CONNECTION
--==============================================================

local function Connect(
    Signal,
    Callback,
    List
)

    local Connection =
        Signal:Connect(Callback)

    table.insert(
        List or Connections,
        Connection
    )

    return Connection
end


local function DisconnectList(
    List
)

    for Index =
        #List,
        1,
        -1 do

        local Connection =
            List[Index]

        pcall(function()
            Connection:Disconnect()
        end)

        List[Index] = nil
    end
end


--==============================================================
-- INSTANCE HELPERS
--==============================================================

local function Corner(
    Object,
    Radius
)

    local Item =
        Instance.new("UICorner")

    Item.CornerRadius =
        UDim.new(
            0,
            Radius or 8
        )

    Item.Parent =
        Object

    return Item
end


local function Stroke(
    Object
)

    local Item =
        Instance.new("UIStroke")

    Item.Color =
        COLORS.Stroke

    Item.Thickness =
        1

    Item.Transparency =
        0.2

    Item.Parent =
        Object

    return Item
end


--==============================================================
-- CHARACTER HELPERS
--==============================================================

local function GetRoot(
    Model
)

    if not Model then
        return nil
    end

    return

        Model:FindFirstChild(
            "HumanoidRootPart"
        )

        or

        Model:FindFirstChild(
            "UpperTorso"
        )

        or

        Model:FindFirstChild(
            "Torso"
        )

        or

        Model.PrimaryPart
end


local function GetHead(
    Model
)

    if not Model then
        return nil
    end

    return
        Model:FindFirstChild("Head")
end


local function GetHumanoid(
    Model
)

    if not Model then
        return nil
    end

    return
        Model:FindFirstChildOfClass(
            "Humanoid"
        )
end


local function IsAlive(
    Model
)

    if not Model
    or not Model.Parent then

        return false
    end


    local Humanoid =
        GetHumanoid(Model)


    if Humanoid then

        return Humanoid.Health > 0
    end


    local Health =
        Model:GetAttribute("Health")


    if typeof(Health) == "number" then

        return Health > 0
    end


    return GetRoot(Model) ~= nil
end


local function GetLocalRoot()

    return
        GetRoot(
            LocalPlayer.Character
        )
end


local function GetDistance(
    Root
)

    local LocalRoot =
        GetLocalRoot()


    if not LocalRoot
    or not Root then

        return math.huge
    end


    return (
        LocalRoot.Position -
        Root.Position
    ).Magnitude
end


--==============================================================
-- TEAM
--==============================================================

local function Normalize(
    Value
)

    if Value == nil then
        return nil
    end

    return string.lower(
        tostring(Value)
    )
end


local function GetLocalTeam()

    if LocalPlayer.Team then

        return Normalize(
            LocalPlayer.Team.Name
        )
    end


    local Character =
        LocalPlayer.Character


    if Character then

        local Team =
            Character:GetAttribute(
                "Team"
            )

        if Team ~= nil then

            return Normalize(Team)
        end
    end


    return nil
end


local function IsPlayerAlly(
    Player
)

    if Player == LocalPlayer then
        return true
    end


    if LocalPlayer.Team
    and Player.Team then

        return
            LocalPlayer.Team ==
            Player.Team
    end


    if not LocalPlayer.Neutral
    and not Player.Neutral
    and LocalPlayer.TeamColor ==
        Player.TeamColor then

        return true
    end


    local LocalTeam =
        GetLocalTeam()


    if LocalTeam
    and Player.Character then

        local Other =
            Player.Character:
            GetAttribute("Team")

        if Other ~= nil then

            return
                Normalize(Other) ==
                LocalTeam
        end
    end


    return false
end


local function GetBotTeam(
    Model
)

    if not Model then
        return nil
    end

    local Team =
        Model:GetAttribute("Team")

    if Team == nil then
        return nil
    end

    return Normalize(Team)
end


local function IsBotAlly(
    Model
)

    local LocalTeam =
        GetLocalTeam()

    local BotTeam =
        GetBotTeam(Model)


    if not LocalTeam
    or not BotTeam then

        return false
    end


    return
        LocalTeam ==
        BotTeam
end


local function IsKnownEnemyBot(
    Model
)

    local LocalTeam =
        GetLocalTeam()

    local BotTeam =
        GetBotTeam(Model)


    -- Para TP / IBOT:
    -- time desconhecido não é tratado como inimigo.

    if not LocalTeam
    or not BotTeam then

        return false
    end


    return
        LocalTeam ~= BotTeam
end


local function IsValidBot(
    Model
)

    if not Model
    or not Model:IsA("Model") then

        return false
    end


    return
        GetRoot(Model) ~= nil
        and
        IsAlive(Model)
end


--==============================================================
-- SOLDIERS
--==============================================================

local function GetSoldiersFolder()

    return
        Workspace:
        FindFirstChild("Soldiers")
end


--==============================================================
-- LOS
--==============================================================

local function HasLineOfSight(
    TargetModel,
    TargetPart
)

    if CONFIG.IgnoreWalls then
        return true
    end


    local Camera =
        Workspace.CurrentCamera


    TargetPart =
        TargetPart
        or GetRoot(TargetModel)


    if not Camera
    or not TargetPart then

        return false
    end


    local Params =
        RaycastParams.new()


    Params.FilterType =
        Enum.RaycastFilterType.Exclude


    local Ignore = {}


    if LocalPlayer.Character then

        table.insert(
            Ignore,
            LocalPlayer.Character
        )
    end


    Params.FilterDescendantsInstances =
        Ignore


    local Origin =
        Camera.CFrame.Position


    local Direction =
        TargetPart.Position -
        Origin


    local Result =
        Workspace:Raycast(
            Origin,
            Direction,
            Params
        )


    if not Result then
        return true
    end


    return
        Result.Instance:
        IsDescendantOf(
            TargetModel
        )
end


--==============================================================
-- CLEAN OLD GUI
--==============================================================

for _, Name in ipairs({

    "CafeinaMobileV4",
    "CafeinaMobileESP"

}) do

    local Existing =
        PlayerGui:
        FindFirstChild(Name)

    if Existing then
        Existing:Destroy()
    end
end


--==============================================================
-- GUI
--==============================================================

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "CafeinaMobileV4"

Gui.ResetOnSpawn =
    false

Gui.DisplayOrder =
    900

Gui.IgnoreGuiInset =
    false

Gui.Parent =
    PlayerGui


local Overlay =
    Instance.new("ScreenGui")

Overlay.Name =
    "CafeinaMobileESP"

Overlay.ResetOnSpawn =
    false

Overlay.IgnoreGuiInset =
    true

Overlay.DisplayOrder =
    800

Overlay.Parent =
    PlayerGui


--==============================================================
-- MAIN PANEL
--==============================================================

local Main =
    Instance.new("Frame")

Main.AnchorPoint =
    Vector2.new(
        0.5,
        0
    )

Main.Position =
    UDim2.new(
        0.5,
        0,
        0.18,
        0
    )

Main.Size =
    UDim2.fromOffset(
        260,
        210
    )

Main.BackgroundColor3 =
    COLORS.Background

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

Corner(Main, 12)
Stroke(Main)


--==============================================================
-- HEADER
--==============================================================

local Header =
    Instance.new("Frame")

Header.Size =
    UDim2.new(
        1,
        0,
        0,
        41
    )

Header.BackgroundTransparency =
    1

Header.Parent =
    Main


local Title =
    Instance.new("TextLabel")

Title.Position =
    UDim2.fromOffset(
        12,
        0
    )

Title.Size =
    UDim2.new(
        1,
        -80,
        1,
        0
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "CAFEÍNA"

Title.Font =
    Enum.Font.GothamBold

Title.TextSize =
    14

Title.TextColor3 =
    COLORS.Text

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Header


--==============================================================
-- MINIMIZE
--==============================================================

local Minimize =
    Instance.new("TextButton")

Minimize.Size =
    UDim2.fromOffset(
        27,
        27
    )

Minimize.Position =
    UDim2.new(
        1,
        -65,
        0,
        7
    )

Minimize.BackgroundColor3 =
    COLORS.Panel2

Minimize.BorderSizePixel =
    0

Minimize.Text =
    "—"

Minimize.TextColor3 =
    COLORS.Text

Minimize.Font =
    Enum.Font.GothamBold

Minimize.TextSize =
    13

Minimize.Parent =
    Header

Corner(Minimize, 6)


--==============================================================
-- CLOSE
--==============================================================

local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.fromOffset(
        27,
        27
    )

Close.Position =
    UDim2.new(
        1,
        -33,
        0,
        7
    )

Close.BackgroundColor3 =
    COLORS.Red

Close.BorderSizePixel =
    0

Close.Text =
    "×"

Close.TextColor3 =
    COLORS.White

Close.Font =
    Enum.Font.GothamBold

Close.TextSize =
    15

Close.Parent =
    Header

Corner(Close, 6)


--==============================================================
-- MAIN SCROLL
--==============================================================

local Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(
        7,
        42
    )

Scroll.Size =
    UDim2.new(
        1,
        -14,
        1,
        -49
    )

Scroll.BackgroundTransparency =
    1

Scroll.BorderSizePixel =
    0

Scroll.ScrollBarThickness =
    3

Scroll.ScrollBarImageColor3 =
    COLORS.Red

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.CanvasSize =
    UDim2.new()

Scroll.ScrollingDirection =
    Enum.ScrollingDirection.Y

Scroll.Parent =
    Main


local MainLayout =
    Instance.new("UIListLayout")

MainLayout.Padding =
    UDim.new(
        0,
        5
    )

MainLayout.SortOrder =
    Enum.SortOrder.LayoutOrder

MainLayout.Parent =
    Scroll


--==============================================================
-- MAIN SIZE
--==============================================================

local function RefreshMainSize()

    task.defer(function()

        if STATE.Closed then
            return
        end


        local Camera =
            Workspace.CurrentCamera


        local ScreenHeight =
            Camera
            and Camera.ViewportSize.Y
            or 600


        local Wanted =
            MainLayout.AbsoluteContentSize.Y
            + 52


        local MaxHeight =
            math.min(
                410,
                ScreenHeight - 80
            )


        Main.Size =
            UDim2.fromOffset(
                260,
                math.clamp(
                    Wanted,
                    205,
                    MaxHeight
                )
            )
    end)
end


Connect(
    MainLayout:
    GetPropertyChangedSignal(
        "AbsoluteContentSize"
    ),

    RefreshMainSize
)


--==============================================================
-- DRAGGING
--==============================================================

local function MakeDraggable(
    Handle,
    Object
)

    local Dragging = false

    local DragInput = nil

    local StartInput = nil

    local StartPosition = nil


    Connect(
        Handle.InputBegan,

        function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.Touch

            or Input.UserInputType ==
                Enum.UserInputType.MouseButton1 then


                Dragging = true

                StartInput =
                    Input.Position

                StartPosition =
                    Object.Position
            end
        end
    )


    Connect(
        Handle.InputChanged,

        function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.Touch

            or Input.UserInputType ==
                Enum.UserInputType.MouseMovement then

                DragInput =
                    Input
            end
        end
    )


    Connect(
        UserInputService.InputChanged,

        function(Input)

            if not Dragging
            or Input ~= DragInput
            or not StartInput
            or not StartPosition then

                return
            end


            local Delta =
                Input.Position -
                StartInput


            Object.Position =
                UDim2.new(

                    StartPosition.X.Scale,

                    StartPosition.X.Offset +
                    Delta.X,

                    StartPosition.Y.Scale,

                    StartPosition.Y.Offset +
                    Delta.Y
                )
        end
    )


    Connect(
        UserInputService.InputEnded,

        function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.Touch

            or Input.UserInputType ==
                Enum.UserInputType.MouseButton1 then

                Dragging = false
            end
        end
    )
end


MakeDraggable(
    Header,
    Main
)


--==============================================================
-- RESTORE ICON
--==============================================================

local Restore =
    Instance.new("TextButton")

Restore.Size =
    UDim2.fromOffset(
        48,
        48
    )

Restore.Position =
    UDim2.new(
        0,
        16,
        0.5,
        -24
    )

Restore.BackgroundColor3 =
    COLORS.Background

Restore.BorderSizePixel =
    0

Restore.Text =
    "C"

Restore.TextColor3 =
    COLORS.Red

Restore.Font =
    Enum.Font.GothamBlack

Restore.TextSize =
    18

Restore.Visible =
    false

Restore.Parent =
    Gui

Corner(Restore, 12)
Stroke(Restore)

MakeDraggable(
    Restore,
    Restore
)


--==============================================================
-- MINIMIZATION
--==============================================================

local function MinimizeMain()

    if STATE.Closed then
        return
    end


    STATE.Minimized =
        true


    Main.Visible =
        false


    Restore.Visible =
        true
end


local function RestoreMain()

    if STATE.Closed then
        return
    end


    STATE.Minimized =
        false


    Restore.Visible =
        false


    Main.Visible =
        true
end


Connect(
    Minimize.Activated,
    MinimizeMain
)


Connect(
    Restore.Activated,

    function()

        RestoreMain()
    end
)


--==============================================================
-- TOGGLE VISUAL
--==============================================================

local function SetToggleVisual(
    Button,
    State
)

    Button.Text =
        State
        and "ON"
        or "OFF"


    Button.TextColor3 =
        State
        and COLORS.Green
        or COLORS.Muted


    Button.BackgroundColor3 =
        State
        and Color3.fromRGB(
            31,
            55,
            39
        )
        or COLORS.Button
end


--==============================================================
-- EXPANDABLE SECTION FACTORY
--==============================================================

local function CreateSection(
    Order,
    Name,
    HasMaster
)

    local Holder =
        Instance.new("Frame")

    Holder.LayoutOrder =
        Order

    Holder.Size =
        UDim2.new(
            1,
            -3,
            0,
            40
        )

    Holder.BackgroundColor3 =
        COLORS.Panel

    Holder.BorderSizePixel =
        0

    Holder.ClipsDescendants =
        true

    Holder.Parent =
        Scroll

    Corner(Holder, 8)


    local HeaderButton =
        Instance.new("Frame")

    HeaderButton.Size =
        UDim2.new(
            1,
            0,
            0,
            40
        )

    HeaderButton.BackgroundTransparency =
        1

    HeaderButton.Parent =
        Holder


    local Label =
        Instance.new("TextLabel")

    Label.Position =
        UDim2.fromOffset(
            10,
            0
        )

    Label.Size =
        UDim2.new(
            1,
            HasMaster
                and -103
                or -48,
            0,
            40
        )

    Label.BackgroundTransparency =
        1

    Label.Text =
        Name

    Label.TextColor3 =
        COLORS.Text

    Label.Font =
        Enum.Font.GothamBold

    Label.TextSize =
        11

    Label.TextXAlignment =
        Enum.TextXAlignment.Left

    Label.Parent =
        HeaderButton


    local Master = nil


    if HasMaster then

        Master =
            Instance.new("TextButton")

        Master.Size =
            UDim2.fromOffset(
                48,
                28
            )

        Master.Position =
            UDim2.new(
                1,
                -84,
                0,
                6
            )

        Master.BorderSizePixel =
            0

        Master.Font =
            Enum.Font.GothamBold

        Master.TextSize =
            9

        Master.Parent =
            HeaderButton

        Corner(Master, 6)
    end


    local Arrow =
        Instance.new("TextButton")

    Arrow.Size =
        UDim2.fromOffset(
            28,
            28
        )

    Arrow.Position =
        UDim2.new(
            1,
            -33,
            0,
            6
        )

    Arrow.BackgroundColor3 =
        COLORS.Button

    Arrow.BorderSizePixel =
        0

    Arrow.Text =
        "▼"

    Arrow.TextColor3 =
        COLORS.Muted

    Arrow.Font =
        Enum.Font.GothamBold

    Arrow.TextSize =
        9

    Arrow.Parent =
        HeaderButton

    Corner(Arrow, 6)


    local Body =
        Instance.new("Frame")

    Body.Position =
        UDim2.fromOffset(
            4,
            43
        )

    Body.Size =
        UDim2.new(
            1,
            -8,
            0,
            0
        )

    Body.BackgroundTransparency =
        1

    Body.Parent =
        Holder


    local Layout =
        Instance.new("UIListLayout")

    Layout.Padding =
        UDim.new(
            0,
            4
        )

    Layout.Parent =
        Body


    return {

        Holder = Holder,

        Label = Label,

        Master = Master,

        Arrow = Arrow,

        Body = Body,

        Layout = Layout
    }
end


--==============================================================
-- SMALL OPTION
--==============================================================

local function CreateOption(
    Parent,
    Text,
    Initial,
    Callback
)

    local State =
        Initial == true


    local Row =
        Instance.new("TextButton")

    Row.Size =
        UDim2.new(
            1,
            0,
            0,
            32
        )

    Row.BackgroundColor3 =
        COLORS.Panel2

    Row.BorderSizePixel =
        0

    Row.Text =
        ""

    Row.Parent =
        Parent

    Corner(Row, 6)


    local Label =
        Instance.new("TextLabel")

    Label.Position =
        UDim2.fromOffset(
            10,
            0
        )

    Label.Size =
        UDim2.new(
            1,
            -57,
            1,
            0
        )

    Label.BackgroundTransparency =
        1

    Label.Text =
        Text

    Label.TextColor3 =
        COLORS.Text

    Label.TextSize =
        10

    Label.Font =
        Enum.Font.GothamMedium

    Label.TextXAlignment =
        Enum.TextXAlignment.Left

    Label.Parent =
        Row


    local Status =
        Instance.new("TextLabel")

    Status.Position =
        UDim2.new(
            1,
            -47,
            0,
            0
        )

    Status.Size =
        UDim2.fromOffset(
            39,
            32
        )

    Status.BackgroundTransparency =
        1

    Status.Font =
        Enum.Font.GothamBold

    Status.TextSize =
        9

    Status.Parent =
        Row


    local API = {}


    local function Refresh()

        Status.Text =
            State
            and "ON"
            or "OFF"

        Status.TextColor3 =
            State
            and COLORS.Green
            or COLORS.Muted
    end


    function API:Set(
        Value,
        Silent
    )

        State =
            Value == true

        Refresh()

        if not Silent
        and Callback then

            Callback(State)
        end
    end


    function API:Get()

        return State
    end


    Connect(
        Row.Activated,

        function()

            API:Set(
                not State
            )
        end
    )


    Refresh()

    return API
end


--==============================================================
-- ACTION BUTTON
--==============================================================

local function CreateAction(
    Parent,
    Text
)

    local Button =
        Instance.new("TextButton")

    Button.Size =
        UDim2.new(
            1,
            0,
            0,
            36
        )

    Button.BackgroundColor3 =
        COLORS.Panel2

    Button.BorderSizePixel =
        0

    Button.Text =
        Text

    Button.TextColor3 =
        COLORS.Text

    Button.Font =
        Enum.Font.GothamMedium

    Button.TextSize =
        10

    Button.Parent =
        Parent

    Corner(Button, 6)

    return Button
end


--==============================================================
-- ESP SECTION
--==============================================================

local ESPSection =
    CreateSection(
        1,
        "ESP",
        true
    )


SetToggleVisual(
    ESPSection.Master,
    false
)


local ESPBoxOption =
    CreateOption(

        ESPSection.Body,

        "Box",

        true,

        function(Value)

            CONFIG.ESPBox =
                Value
        end
    )


local ESPDistanceOption =
    CreateOption(

        ESPSection.Body,

        "Distância",

        true,

        function(Value)

            CONFIG.ESPDistance =
                Value
        end
    )


local ESPAuraOption =
    CreateOption(

        ESPSection.Body,

        "Aura inimigos",

        true,

        function(Value)

            CONFIG.ESPEnemyAura =
                Value

            if not Value then

                for _, Data in pairs(
                    ESPObjects
                ) do

                    if Data.Highlight then

                        Data.Highlight.Enabled =
                            false
                    end
                end
            end
        end
    )


local ESPPlayersOption =
    CreateOption(

        ESPSection.Body,

        "Players",

        true,

        function(Value)

            CONFIG.ESPPlayers =
                Value
        end
    )


local ESPBotsOption =
    CreateOption(

        ESPSection.Body,

        "Bots",

        true,

        function(Value)

            CONFIG.ESPBots =
                Value
        end
    )


local ESPBodyHeight =
    5 * 32 +
    4 * 4


local function SetESPExpanded(
    Value
)

    STATE.ESPExpanded =
        Value == true


    ESPSection.Arrow.Text =
        STATE.ESPExpanded
        and "▲"
        or "▼"


    ESPSection.Holder.Size =
        UDim2.new(
            1,
            -3,
            0,

            STATE.ESPExpanded
            and 47 + ESPBodyHeight
            or 40
        )


    RefreshMainSize()
end


Connect(
    ESPSection.Arrow.Activated,

    function()

        SetESPExpanded(
            not STATE.ESPExpanded
        )
    end
)


--==============================================================
-- ESP MASTER
--==============================================================

local function HideAllESP()

    for _, Data in pairs(
        ESPObjects
    ) do

        if Data.Root then

            Data.Root.Visible =
                false
        end


        if Data.Highlight then

            Data.Highlight.Enabled =
                false
        end
    end
end


local function SetESPEnabled(
    Value
)

    CONFIG.ESPEnabled =
        Value == true


    SetToggleVisual(
        ESPSection.Master,
        CONFIG.ESPEnabled
    )


    if not CONFIG.ESPEnabled then

        HideAllESP()
    end
end


Connect(
    ESPSection.Master.Activated,

    function()

        SetESPEnabled(
            not CONFIG.ESPEnabled
        )
    end
)


--==============================================================
-- IBOT SECTION
--==============================================================

local IBotSection =
    CreateSection(
        2,
        "IBOT",
        true
    )


SetToggleVisual(
    IBotSection.Master,
    false
)


local IBotHeadOption =
    CreateOption(

        IBotSection.Body,

        "Focar na cabeça",

        true,

        function(Value)

            CONFIG.IBotHead =
                Value
        end
    )


local function SetIBotExpanded(
    Value
)

    STATE.IBotExpanded =
        Value == true


    IBotSection.Arrow.Text =
        STATE.IBotExpanded
        and "▲"
        or "▼"


    IBotSection.Holder.Size =
        UDim2.new(
            1,
            -3,
            0,

            STATE.IBotExpanded
            and 79
            or 40
        )


    RefreshMainSize()
end


Connect(
    IBotSection.Arrow.Activated,

    function()

        SetIBotExpanded(
            not STATE.IBotExpanded
        )
    end
)


local function SetIBotEnabled(
    Value
)

    CONFIG.IBotEnabled =
        Value == true


    SetToggleVisual(
        IBotSection.Master,
        CONFIG.IBotEnabled
    )
end


Connect(
    IBotSection.Master.Activated,

    function()

        SetIBotEnabled(
            not CONFIG.IBotEnabled
        )
    end
)


--==============================================================
-- TELEPORT SECTION
--==============================================================

local TPSection =
    CreateSection(
        3,
        "TELEPORTE",
        false
    )


local TPNearest =
    CreateAction(
        TPSection.Body,
        "PLAYER MAIS PRÓXIMO"
    )


local TPBase =
    CreateAction(
        TPSection.Body,
        "VOLTAR À BASE"
    )


local TPAllies =
    CreateAction(
        TPSection.Body,
        "ALIADOS"
    )


local TeleportBodyHeight =
    3 * 36 +
    2 * 4


local function SetTeleportExpanded(
    Value
)

    STATE.TeleportExpanded =
        Value == true


    TPSection.Arrow.Text =
        STATE.TeleportExpanded
        and "▲"
        or "▼"


    TPSection.Holder.Size =
        UDim2.new(
            1,
            -3,
            0,

            STATE.TeleportExpanded
            and 47 + TeleportBodyHeight
            or 40
        )


    RefreshMainSize()
end


Connect(
    TPSection.Arrow.Activated,

    function()

        SetTeleportExpanded(
            not STATE.TeleportExpanded
        )
    end
)


--==============================================================
-- IGNORE WALL
--==============================================================

local IgnoreRow =
    Instance.new("Frame")

IgnoreRow.LayoutOrder =
    4

IgnoreRow.Size =
    UDim2.new(
        1,
        -3,
        0,
        40
    )

IgnoreRow.BackgroundColor3 =
    COLORS.Panel

IgnoreRow.BorderSizePixel =
    0

IgnoreRow.Parent =
    Scroll

Corner(IgnoreRow, 8)


local IgnoreLabel =
    Instance.new("TextLabel")

IgnoreLabel.Position =
    UDim2.fromOffset(
        10,
        0
    )

IgnoreLabel.Size =
    UDim2.new(
        1,
        -70,
        1,
        0
    )

IgnoreLabel.BackgroundTransparency =
    1

IgnoreLabel.Text =
    "IGNORE WALL"

IgnoreLabel.TextColor3 =
    COLORS.Text

IgnoreLabel.Font =
    Enum.Font.GothamBold

IgnoreLabel.TextSize =
    11

IgnoreLabel.TextXAlignment =
    Enum.TextXAlignment.Left

IgnoreLabel.Parent =
    IgnoreRow


local IgnoreToggle =
    Instance.new("TextButton")

IgnoreToggle.Size =
    UDim2.fromOffset(
        48,
        28
    )

IgnoreToggle.Position =
    UDim2.new(
        1,
        -56,
        0,
        6
    )

IgnoreToggle.BorderSizePixel =
    0

IgnoreToggle.Font =
    Enum.Font.GothamBold

IgnoreToggle.TextSize =
    9

IgnoreToggle.Parent =
    IgnoreRow

Corner(IgnoreToggle, 6)


SetToggleVisual(
    IgnoreToggle,
    false
)


Connect(
    IgnoreToggle.Activated,

    function()

        CONFIG.IgnoreWalls =
            not CONFIG.IgnoreWalls


        SetToggleVisual(
            IgnoreToggle,
            CONFIG.IgnoreWalls
        )
    end
)


--==============================================================
-- ESP OBJECT
-- Importante:
-- distância não fica dentro do Box.
-- Assim Box pode ser OFF e distância continuar aparecendo.
--==============================================================

local function CreateESPObject(
    Key
)

    if ESPObjects[Key] then

        return ESPObjects[Key]
    end


    local RootFrame =
        Instance.new("Frame")

    RootFrame.BackgroundTransparency =
        1

    RootFrame.BorderSizePixel =
        0

    RootFrame.Visible =
        false

    RootFrame.Parent =
        Overlay


    local Box =
        Instance.new("Frame")

    Box.Size =
        UDim2.fromScale(
            1,
            1
        )

    Box.BackgroundTransparency =
        1

    Box.BorderSizePixel =
        0

    Box.Parent =
        RootFrame


    local BoxStroke =
        Instance.new("UIStroke")

    BoxStroke.Thickness =
        1.5

    BoxStroke.Parent =
        Box


    local Distance =
        Instance.new("TextLabel")

    Distance.AnchorPoint =
        Vector2.new(
            0.5,
            1
        )

    Distance.Position =
        UDim2.new(
            0.5,
            0,
            0,
            -3
        )

    Distance.Size =
        UDim2.fromOffset(
            80,
            18
        )

    Distance.BackgroundColor3 =
        Color3.new(
            0,
            0,
            0
        )

    Distance.BackgroundTransparency =
        0.30

    Distance.BorderSizePixel =
        0

    Distance.Font =
        Enum.Font.GothamBold

    Distance.TextSize =
        10

    Distance.TextStrokeTransparency =
        0.45

    Distance.Parent =
        RootFrame

    Corner(Distance, 4)


    local Highlight =
        Instance.new("Highlight")

    Highlight.Enabled =
        false

    Highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    Highlight.FillColor =
        COLORS.White

    Highlight.FillTransparency =
        0.62

    Highlight.OutlineColor =
        COLORS.White

    Highlight.OutlineTransparency =
        0.08

    Highlight.Parent =
        Workspace


    local Data = {

        Root =
            RootFrame,

        Box =
            Box,

        Stroke =
            BoxStroke,

        Distance =
            Distance,

        Highlight =
            Highlight
    }


    ESPObjects[Key] =
        Data


    return Data
end


local function RemoveESPObject(
    Key
)

    local Data =
        ESPObjects[Key]

    if not Data then
        return
    end


    if Data.Root then

        pcall(function()
            Data.Root:Destroy()
        end)
    end


    if Data.Highlight then

        pcall(function()
            Data.Highlight:Destroy()
        end)
    end


    ESPObjects[Key] =
        nil
end


--==============================================================
-- ESP BOX CALCULATION
--==============================================================

local function GetScreenBox(
    Model
)

    local Camera =
        Workspace.CurrentCamera


    local Root =
        GetRoot(Model)


    if not Camera
    or not Root then

        return nil
    end


    local Head =
        GetHead(Model)


    if Head then

        local Center,
            CenterVisible =
            Camera:
            WorldToViewportPoint(
                Root.Position
            )


        local Top =
            Camera:
            WorldToViewportPoint(

                Head.Position +
                Vector3.new(
                    0,
                    0.65,
                    0
                )
            )


        local Bottom =
            Camera:
            WorldToViewportPoint(

                Root.Position -
                Vector3.new(
                    0,
                    3,
                    0
                )
            )


        if Center.Z > 0
        and Top.Z > 0
        and Bottom.Z > 0 then

            local Height =
                math.abs(
                    Bottom.Y -
                    Top.Y
                )


            if Height >= 8 then

                local Width =
                    Height * 0.48


                return

                    Center.X -
                    Width / 2,

                    Top.Y,

                    Width,

                    Height
            end
        end
    end


    local Success,
        BoundingCF,
        BoundingSize =
        pcall(function()

            return
                Model:GetBoundingBox()
        end)


    if not Success then
        return nil
    end


    local Center =
        BoundingCF.Position


    local ScreenCenter =
        Camera:
        WorldToViewportPoint(
            Center
        )


    if ScreenCenter.Z <= 0 then
        return nil
    end


    local Top =
        Camera:
        WorldToViewportPoint(

            Center +
            Vector3.new(
                0,
                BoundingSize.Y / 2,
                0
            )
        )


    local Bottom =
        Camera:
        WorldToViewportPoint(

            Center -
            Vector3.new(
                0,
                BoundingSize.Y / 2,
                0
            )
        )


    local Height =
        math.abs(
            Bottom.Y -
            Top.Y
        )


    if Height < 8 then
        return nil
    end


    local Width =
        Height * 0.48


    return

        ScreenCenter.X -
        Width / 2,

        Top.Y,

        Width,

        Height
end


--==============================================================
-- UPDATE ESP OBJECT
--==============================================================

local function UpdateESPObject(
    Key,
    Model,
    Ally
)

    local Data =
        CreateESPObject(Key)


    if not Model
    or not Model.Parent
    or not IsAlive(Model) then

        Data.Root.Visible =
            false

        Data.Highlight.Enabled =
            false

        return
    end


    local Root =
        GetRoot(Model)


    if not Root then

        Data.Root.Visible =
            false

        Data.Highlight.Enabled =
            false

        return
    end


    local Studs =
        GetDistance(Root)


    if Studs >
        CONFIG.ESPMaxDistance then

        Data.Root.Visible =
            false

        Data.Highlight.Enabled =
            false

        return
    end


    local X,
        Y,
        Width,
        Height =
        GetScreenBox(Model)


    local Color =
        Ally
        and COLORS.Ally
        or COLORS.Enemy


    Data.Highlight.Adornee =
        Model


    Data.Highlight.Enabled =
        CONFIG.ESPEnabled
        and CONFIG.ESPEnemyAura
        and not Ally


    if not X then

        Data.Root.Visible =
            false

        return
    end


    Data.Root.Position =
        UDim2.fromOffset(
            X,
            Y
        )


    Data.Root.Size =
        UDim2.fromOffset(
            Width,
            Height
        )


    Data.Root.Visible =
        CONFIG.ESPEnabled


    Data.Box.Visible =
        CONFIG.ESPBox


    Data.Distance.Visible =
        CONFIG.ESPDistance


    Data.Stroke.Color =
        Color


    Data.Distance.TextColor3 =
        Color


    Data.Distance.Text =
        tostring(
            math.floor(
                Studs +
                0.5
            )
        )
        ..
        " st"
end


--==============================================================
-- UPDATE ESP
--==============================================================

local function UpdateESP()

    if not CONFIG.ESPEnabled then
        return
    end


    local Seen = {}


    if CONFIG.ESPPlayers then

        for _, Player in ipairs(
            Players:GetPlayers()
        ) do

            if Player ~= LocalPlayer
            and Player.Character then

                Seen[Player] =
                    true


                UpdateESPObject(

                    Player,

                    Player.Character,

                    IsPlayerAlly(
                        Player
                    )
                )
            end
        end
    end


    if CONFIG.ESPBots then

        local Soldiers =
            GetSoldiersFolder()


        if Soldiers then

            for _, Bot in ipairs(
                Soldiers:GetChildren()
            ) do

                if IsValidBot(Bot) then

                    Seen[Bot] =
                        true


                    UpdateESPObject(

                        Bot,

                        Bot,

                        IsBotAlly(
                            Bot
                        )
                    )
                end
            end
        end
    end


    local Remove = {}


    for Key,
        Data in pairs(
            ESPObjects
        ) do

        if not Seen[Key] then

            Data.Root.Visible =
                false

            Data.Highlight.Enabled =
                false


            local Exists =
                false


            if typeof(Key) ==
                "Instance" then

                Exists =
                    Key.Parent ~= nil
            end


            if not Exists then

                table.insert(
                    Remove,
                    Key
                )
            end
        end
    end


    for _, Key in ipairs(
        Remove
    ) do

        RemoveESPObject(Key)
    end
end


--==============================================================
-- ENEMY ENUMERATION
--==============================================================

local function ForEachEnemy(
    Callback
)

    for _, Player in ipairs(
        Players:GetPlayers()
    ) do

        if Player ~= LocalPlayer
        and Player.Character
        and IsAlive(
            Player.Character
        )
        and not IsPlayerAlly(
            Player
        ) then

            Callback(
                Player.Character,
                "Player"
            )
        end
    end


    local Soldiers =
        GetSoldiersFolder()


    if Soldiers then

        for _, Bot in ipairs(
            Soldiers:GetChildren()
        ) do

            if IsValidBot(Bot)
            and IsKnownEnemyBot(Bot) then

                Callback(
                    Bot,
                    "Bot"
                )
            end
        end
    end
end


--==============================================================
-- IBOT TARGET
--==============================================================

local function GetIBotTarget()

    local Camera =
        Workspace.CurrentCamera


    if not Camera then
        return nil
    end


    local ScreenCenter =
        Camera.ViewportSize / 2


    local BestPart =
        nil

    local BestScreenDistance =
        math.huge


    ForEachEnemy(

        function(Model)

            local Root =
                GetRoot(Model)


            if not Root then
                return
            end


            local WorldDistance =
                GetDistance(Root)


            if WorldDistance >
                CONFIG.IBotMaxDistance then

                return
            end


            local TargetPart


            if CONFIG.IBotHead then

                TargetPart =
                    GetHead(Model)

                if not TargetPart then
                    return
                end

            else

                TargetPart =
                    Root
            end


            if not HasLineOfSight(
                Model,
                TargetPart
            ) then

                return
            end


            local Screen,
                Visible =
                Camera:
                WorldToViewportPoint(
                    TargetPart.Position
                )


            if Screen.Z <= 0 then
                return
            end


            local Delta =
                Vector2.new(
                    Screen.X,
                    Screen.Y
                )
                -
                ScreenCenter


            local Distance =
                Delta.Magnitude


            if Distance <
                BestScreenDistance then

                BestScreenDistance =
                    Distance

                BestPart =
                    TargetPart
            end
        end
    )


    return BestPart
end


--==============================================================
-- UPDATE IBOT
--==============================================================

local function UpdateIBot()

    if not CONFIG.IBotEnabled then
        return
    end


    local Camera =
        Workspace.CurrentCamera


    if not Camera then
        return
    end


    local Target =
        GetIBotTarget()


    if not Target
    or not Target.Parent then

        return
    end


    local Desired =
        CFrame.lookAt(

            Camera.CFrame.Position,

            Target.Position
        )


    Camera.CFrame =
        Camera.CFrame:Lerp(

            Desired,

            math.clamp(
                CONFIG.IBotSmoothness,
                0.01,
                1
            )
        )
end


--==============================================================
-- TP TARGET
--==============================================================

local function GetClosestTeleportEnemy()

    local Best =
        nil

    local BestDistance =
        math.huge


    ForEachEnemy(

        function(Model)

            local Root =
                GetRoot(Model)


            if not Root then
                return
            end


            local Studs =
                GetDistance(Root)


            if Studs >=
                BestDistance then

                return
            end


            if not HasLineOfSight(
                Model,
                Root
            ) then

                return
            end


            Best =
                Model

            BestDistance =
                Studs
        end
    )


    return
        Best,
        BestDistance
end


--==============================================================
-- SAFE TELEPORT
--==============================================================

local function FindGround(
    Position,
    TargetModel
)

    local Params =
        RaycastParams.new()


    Params.FilterType =
        Enum.RaycastFilterType.Exclude


    local Ignore = {}


    if LocalPlayer.Character then

        table.insert(
            Ignore,
            LocalPlayer.Character
        )
    end


    if TargetModel then

        table.insert(
            Ignore,
            TargetModel
        )
    end


    Params.FilterDescendantsInstances =
        Ignore


    local Result =
        Workspace:Raycast(

            Position +
            Vector3.new(
                0,
                10,
                0
            ),

            Vector3.new(
                0,
                -40,
                0
            ),

            Params
        )


    if not Result then
        return nil
    end


    return
        Result.Position +
        Vector3.new(
            0,
            3.1,
            0
        )
end


local function IsPositionFree(
    Position,
    Target
)

    local Params =
        OverlapParams.new()


    Params.FilterType =
        Enum.RaycastFilterType.Exclude


    local Ignore = {}


    if LocalPlayer.Character then

        table.insert(
            Ignore,
            LocalPlayer.Character
        )
    end


    if Target then

        table.insert(
            Ignore,
            Target
        )
    end


    Params.FilterDescendantsInstances =
        Ignore


    local Parts =
        Workspace:
        GetPartBoundsInBox(

            CFrame.new(Position),

            Vector3.new(
                3.5,
                5.3,
                3.5
            ),

            Params
        )


    for _, Part in ipairs(
        Parts
    ) do

        if Part:IsA("BasePart")
        and Part.CanCollide then

            return false
        end
    end


    return true
end


local function FindSafePosition(
    Target,
    BehindDistance
)

    local TargetRoot =
        GetRoot(Target)


    if not TargetRoot then
        return nil
    end


    local Back =
        -TargetRoot.CFrame.LookVector


    local Right =
        TargetRoot.CFrame.RightVector


    local Offsets = {

        Back *
            BehindDistance,

        Back *
            BehindDistance
            +
            Right * 2.5,

        Back *
            BehindDistance
            -
            Right * 2.5,

        Back *
            (
                BehindDistance +
                2
            ),

        Back *
            (
                BehindDistance +
                3.5
            )
            +
            Right * 2,

        Back *
            (
                BehindDistance +
                3.5
            )
            -
            Right * 2,

        Right * 5,

        -Right * 5
    }


    for _, Offset in ipairs(
        Offsets
    ) do

        local Position =
            FindGround(

                TargetRoot.Position +
                Offset,

                Target
            )


        if Position
        and IsPositionFree(
            Position,
            Target
        ) then

            return Position
        end
    end


    return nil
end


local function TeleportToModel(
    Target,
    BehindDistance
)

    if STATE.Closed
    or not Target
    or not IsAlive(Target) then

        return false
    end


    local LocalRoot =
        GetLocalRoot()


    local TargetRoot =
        GetRoot(Target)


    if not LocalRoot
    or not TargetRoot then

        return false
    end


    local Position =
        FindSafePosition(

            Target,

            BehindDistance
        )


    if not Position then
        return false
    end


    local Look =
        Vector3.new(

            TargetRoot.Position.X,

            Position.Y,

            TargetRoot.Position.Z
        )


    LocalRoot.CFrame =
        CFrame.lookAt(
            Position,
            Look
        )


    return true
end


--==============================================================
-- FLOATING TP BUTTON
--==============================================================

local TPFloat =
    Instance.new("Frame")

TPFloat.Size =
    UDim2.fromOffset(
        50,
        50
    )

TPFloat.Position =
    UDim2.new(
        1,
        -70,
        1,
        -105
    )

TPFloat.BackgroundTransparency =
    1

TPFloat.Visible =
    false

TPFloat.Parent =
    Gui


local TPButton =
    Instance.new("TextButton")

TPButton.Size =
    UDim2.fromScale(
        1,
        1
    )

TPButton.BackgroundColor3 =
    COLORS.Disabled

TPButton.BorderSizePixel =
    0

TPButton.Text =
    "TP"

TPButton.TextColor3 =
    COLORS.Text

TPButton.Font =
    Enum.Font.GothamBold

TPButton.TextSize =
    13

TPButton.Parent =
    TPFloat

Corner(TPButton, 10)


local TPClose =
    Instance.new("TextButton")

TPClose.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

TPClose.Size =
    UDim2.fromOffset(
        18,
        18
    )

TPClose.Position =
    UDim2.new(
        1,
        -1,
        0,
        1
    )

TPClose.BackgroundColor3 =
    COLORS.Red

TPClose.BorderSizePixel =
    0

TPClose.Text =
    "×"

TPClose.TextColor3 =
    COLORS.White

TPClose.Font =
    Enum.Font.GothamBold

TPClose.TextSize =
    10

TPClose.ZIndex =
    20

TPClose.Parent =
    TPFloat

Corner(TPClose, 9)


MakeDraggable(
    TPButton,
    TPFloat
)


local function ExitTPMode()

    STATE.TPMode =
        false


    CurrentTPTarget =
        nil


    TeleportReady =
        false


    TPButton.BackgroundColor3 =
        COLORS.Disabled


    TPFloat.Visible =
        false


    RestoreMain()
end


Connect(
    TPClose.Activated,
    ExitTPMode
)


Connect(
    TPButton.Activated,

    function()

        if not STATE.TPMode
        or not TeleportReady
        or not CurrentTPTarget then

            return
        end


        if not CurrentTPTarget.Parent
        or not IsAlive(
            CurrentTPTarget
        ) then

            CurrentTPTarget =
                nil

            TeleportReady =
                false

            return
        end


        local Root =
            GetRoot(
                CurrentTPTarget
            )


        if not Root then
            return
        end


        -- Revalidação final.

        if GetDistance(Root) >
            CONFIG.TeleportDistance then

            TeleportReady =
                false

            TPButton.BackgroundColor3 =
                COLORS.Disabled

            return
        end


        TeleportToModel(

            CurrentTPTarget,

            CONFIG.TeleportBehindDistance
        )
    end
)


Connect(
    TPNearest.Activated,

    function()

        STATE.TPMode =
            true


        MinimizeMain()


        TPFloat.Visible =
            true
    end
)


--==============================================================
-- OWNED TYCOON
--==============================================================

local function FindOwnedTycoon()

    local Tycoons =
        Workspace:
        FindFirstChild("Tycoons")


    if not Tycoons then
        return nil
    end


    local PlayerName =
        LocalPlayer.Name


    -- Principal:
    -- CoreBuild.Collector.Owner

    for _, Tycoon in ipairs(
        Tycoons:GetChildren()
    ) do

        local Core =
            Tycoon:
            FindFirstChild("CoreBuild")


        local Collector =
            Core
            and Core:
            FindFirstChild("Collector")


        if Collector
        and tostring(
            Collector:
            GetAttribute("Owner")
            or ""
        ) == PlayerName then

            return Tycoon
        end
    end


    -- Fallback:
    -- Buttons.<Button>.Owner

    for _, Tycoon in ipairs(
        Tycoons:GetChildren()
    ) do

        local Buttons =
            Tycoon:
            FindFirstChild("Buttons")


        if Buttons then

            for _, Button in ipairs(
                Buttons:GetChildren()
            ) do

                if tostring(
                    Button:
                    GetAttribute("Owner")
                    or ""
                ) == PlayerName then

                    return Tycoon
                end
            end
        end
    end


    return nil
end


local function GetTycoonReturnPoint(
    Tycoon
)

    if not Tycoon then
        return nil
    end


    local Core =
        Tycoon:
        FindFirstChild("CoreBuild")


    local Collector =
        Core
        and Core:
        FindFirstChild("Collector")


    if Collector then

        local Collect =
            Collector:
            FindFirstChild("Collect")


        if Collect
        and Collect:IsA("BasePart") then

            return
                Collect.Position +
                Vector3.new(
                    0,
                    4,
                    5
                )
        end


        if Collector:IsA("BasePart") then

            return
                Collector.Position +
                Vector3.new(
                    0,
                    4,
                    5
                )
        end


        local Part =
            Collector:
            FindFirstChildWhichIsA(
                "BasePart",
                true
            )


        if Part then

            return
                Part.Position +
                Vector3.new(
                    0,
                    4,
                    5
                )
        end
    end


    local Success,
        CF =
        pcall(function()

            return
                Tycoon:GetBoundingBox()
        end)


    if Success and CF then

        return
            CF.Position +
            Vector3.new(
                0,
                6,
                0
            )
    end


    return nil
end


local function TeleportToBase()

    local Root =
        GetLocalRoot()


    if not Root then
        return false
    end


    local Tycoon =
        FindOwnedTycoon()


    if not Tycoon then

        warn(
            "CAFEÍNA: Tycoon do jogador não encontrado."
        )

        return false
    end


    local Position =
        GetTycoonReturnPoint(
            Tycoon
        )


    if not Position then

        warn(
            "CAFEÍNA: ponto da base não encontrado."
        )

        return false
    end


    Root.CFrame =
        CFrame.new(Position)


    return true
end


Connect(
    TPBase.Activated,
    TeleportToBase
)


--==============================================================
-- ALLY MENU
--==============================================================

local AllyPanel =
    Instance.new("Frame")

AllyPanel.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

AllyPanel.Position =
    UDim2.new(
        0.5,
        0,
        0.5,
        0
    )

AllyPanel.Size =
    UDim2.fromOffset(
        260,
        330
    )

AllyPanel.BackgroundColor3 =
    COLORS.Background

AllyPanel.BorderSizePixel =
    0

AllyPanel.Visible =
    false

AllyPanel.Parent =
    Gui

Corner(AllyPanel, 12)
Stroke(AllyPanel)


local AllyHeader =
    Instance.new("Frame")

AllyHeader.Size =
    UDim2.new(
        1,
        0,
        0,
        42
    )

AllyHeader.BackgroundTransparency =
    1

AllyHeader.Parent =
    AllyPanel


local AllyTitle =
    Instance.new("TextLabel")

AllyTitle.Position =
    UDim2.fromOffset(
        11,
        0
    )

AllyTitle.Size =
    UDim2.new(
        1,
        -55,
        1,
        0
    )

AllyTitle.BackgroundTransparency =
    1

AllyTitle.Text =
    "TELEPORTE • ALIADOS"

AllyTitle.TextColor3 =
    COLORS.Text

AllyTitle.Font =
    Enum.Font.GothamBold

AllyTitle.TextSize =
    12

AllyTitle.TextXAlignment =
    Enum.TextXAlignment.Left

AllyTitle.Parent =
    AllyHeader


local AllyClose =
    Instance.new("TextButton")

AllyClose.Size =
    UDim2.fromOffset(
        28,
        28
    )

AllyClose.Position =
    UDim2.new(
        1,
        -34,
        0,
        7
    )

AllyClose.BackgroundColor3 =
    COLORS.Red

AllyClose.BorderSizePixel =
    0

AllyClose.Text =
    "×"

AllyClose.TextColor3 =
    COLORS.White

AllyClose.Font =
    Enum.Font.GothamBold

AllyClose.TextSize =
    14

AllyClose.Parent =
    AllyHeader

Corner(AllyClose, 6)


local AllyScroll =
    Instance.new("ScrollingFrame")

AllyScroll.Position =
    UDim2.fromOffset(
        7,
        43
    )

AllyScroll.Size =
    UDim2.new(
        1,
        -14,
        1,
        -50
    )

AllyScroll.BackgroundTransparency =
    1

AllyScroll.BorderSizePixel =
    0

AllyScroll.ScrollBarThickness =
    3

AllyScroll.ScrollBarImageColor3 =
    COLORS.Red

AllyScroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

AllyScroll.CanvasSize =
    UDim2.new()

AllyScroll.Parent =
    AllyPanel


local AllyLayout =
    Instance.new("UIListLayout")

AllyLayout.Padding =
    UDim.new(
        0,
        5
    )

AllyLayout.Parent =
    AllyScroll


MakeDraggable(
    AllyHeader,
    AllyPanel
)


local function GetAllies()

    local Results = {}


    for _, Player in ipairs(
        Players:GetPlayers()
    ) do

        if Player ~= LocalPlayer
        and Player.Character
        and IsAlive(
            Player.Character
        )
        and IsPlayerAlly(
            Player
        ) then

            local Root =
                GetRoot(
                    Player.Character
                )


            if Root then

                table.insert(
                    Results,
                    {

                        Name =
                            Player.DisplayName,

                        Model =
                            Player.Character,

                        Type =
                            "Player",

                        Distance =
                            GetDistance(Root)
                    }
                )
            end
        end
    end


    local Soldiers =
        GetSoldiersFolder()


    if Soldiers then

        for _, Bot in ipairs(
            Soldiers:GetChildren()
        ) do

            if IsValidBot(Bot)
            and IsBotAlly(Bot) then

                local Root =
                    GetRoot(Bot)


                if Root then

                    table.insert(
                        Results,
                        {

                            Name =
                                Bot.Name,

                            Model =
                                Bot,

                            Type =
                                "Bot",

                            Distance =
                                GetDistance(Root)
                        }
                    )
                end
            end
        end
    end


    table.sort(

        Results,

        function(A, B)

            return
                A.Distance <
                B.Distance
        end
    )


    return Results
end


local function ClearAllyButtons()

    DisconnectList(
        AllyConnections
    )


    for _, Child in ipairs(
        AllyScroll:GetChildren()
    ) do

        if Child:IsA("TextButton") then

            Child:Destroy()
        end
    end
end


local function RefreshAllies()

    if not AllyPanel.Visible then
        return
    end


    ClearAllyButtons()


    local Allies =
        GetAllies()


    if #Allies == 0 then

        local Empty =
            Instance.new("TextButton")

        Empty.Size =
            UDim2.new(
                1,
                -3,
                0,
                42
            )

        Empty.BackgroundColor3 =
            COLORS.Panel

        Empty.BorderSizePixel =
            0

        Empty.Text =
            "Nenhum aliado disponível"

        Empty.TextColor3 =
            COLORS.Muted

        Empty.TextSize =
            10

        Empty.Font =
            Enum.Font.GothamMedium

        Empty.AutoButtonColor =
            false

        Empty.Parent =
            AllyScroll

        Corner(Empty, 7)

        return
    end


    for _, Ally in ipairs(
        Allies
    ) do

        local Button =
            Instance.new("TextButton")


        Button.Size =
            UDim2.new(
                1,
                -3,
                0,
                42
            )


        Button.BackgroundColor3 =
            COLORS.Panel


        Button.BorderSizePixel =
            0


        Button.TextColor3 =
            COLORS.Text


        Button.TextSize =
            10


        Button.Font =
            Enum.Font.GothamMedium


        Button.Text =
            (
                Ally.Type == "Bot"
                and "BOT • "
                or ""
            )
            ..
            Ally.Name
            ..
            "  •  "
            ..
            tostring(
                math.floor(
                    Ally.Distance +
                    0.5
                )
            )
            ..
            " st"


        Button.Parent =
            AllyScroll


        Corner(Button, 7)


        Connect(

            Button.Activated,

            function()

                local Model =
                    Ally.Model


                if not Model
                or not Model.Parent
                or not IsAlive(Model) then

                    RefreshAllies()

                    return
                end


                -- Revalida equipe.

                if Ally.Type ==
                    "Player" then

                    local Player =
                        Players:
                        GetPlayerFromCharacter(
                            Model
                        )


                    if not Player
                    or not IsPlayerAlly(
                        Player
                    ) then

                        RefreshAllies()

                        return
                    end

                else

                    if not IsBotAlly(
                        Model
                    ) then

                        RefreshAllies()

                        return
                    end
                end


                TeleportToModel(

                    Model,

                    CONFIG.AllyTeleportDistance
                )
            end,

            AllyConnections
        )
    end
end


local function OpenAllies()

    MinimizeMain()


    AllyPanel.Visible =
        true


    LastAllyRefresh =
        0


    RefreshAllies()
end


local function CloseAllies()

    AllyPanel.Visible =
        false


    ClearAllyButtons()


    RestoreMain()
end


Connect(
    TPAllies.Activated,
    OpenAllies
)


Connect(
    AllyClose.Activated,
    CloseAllies
)


--==============================================================
-- MAIN LOOP
--==============================================================

Connect(
    RunService.RenderStepped,

    function()

        if STATE.Closed then
            return
        end


        local Now =
            os.clock()


        --======================================================
        -- ESP
        --======================================================

        if CONFIG.ESPEnabled
        and Now - LastESP >=
            CONFIG.ESPInterval then

            LastESP =
                Now

            UpdateESP()
        end


        --======================================================
        -- IBOT
        --======================================================

        if CONFIG.IBotEnabled
        and Now - LastIBot >=
            CONFIG.IBotInterval then

            LastIBot =
                Now

            UpdateIBot()
        end


        --======================================================
        -- TELEPORT TARGET
        --======================================================

        if STATE.TPMode
        and TPFloat.Visible
        and Now - LastTP >=
            CONFIG.TeleportInterval then

            LastTP =
                Now


            local Target,
                Studs =
                GetClosestTeleportEnemy()


            CurrentTPTarget =
                Target


            TeleportReady =
                Target ~= nil
                and
                Studs <=
                CONFIG.TeleportDistance


            TPButton.BackgroundColor3 =
                TeleportReady
                and COLORS.Green
                or COLORS.Disabled
        end


        --======================================================
        -- ALLY LIST
        --======================================================

        if AllyPanel.Visible
        and Now - LastAllyRefresh >=
            0.75 then

            LastAllyRefresh =
                Now

            RefreshAllies()
        end
    end
)


--==============================================================
-- RESPAWN
--==============================================================

Connect(
    LocalPlayer.CharacterAdded,

    function()

        CurrentTPTarget =
            nil


        TeleportReady =
            false


        TPButton.BackgroundColor3 =
            COLORS.Disabled
    end
)


--==============================================================
-- SHUTDOWN
--==============================================================

local function Shutdown()

    if STATE.Closed then
        return
    end


    STATE.Closed =
        true


    CONFIG.ESPEnabled =
        false


    CONFIG.IBotEnabled =
        false


    CONFIG.IgnoreWalls =
        false


    STATE.TPMode =
        false


    CurrentTPTarget =
        nil


    TeleportReady =
        false


    HideAllESP()


    DisconnectList(
        AllyConnections
    )


    -- Destroy ESP elements.

    local Keys = {}


    for Key in pairs(
        ESPObjects
    ) do

        table.insert(
            Keys,
            Key
        )
    end


    for _, Key in ipairs(
        Keys
    ) do

        RemoveESPObject(
            Key
        )
    end


    DisconnectList(
        Connections
    )


    if Overlay then

        pcall(function()
            Overlay:Destroy()
        end)
    end


    if Gui then

        pcall(function()
            Gui:Destroy()
        end)
    end


    if GlobalEnvironment.CafeinaMobileRuntime ==
        Runtime then

        GlobalEnvironment.CafeinaMobileRuntime =
            nil
    end
end


Runtime.Shutdown =
    Shutdown


Connect(
    Close.Activated,
    Shutdown
)


--==============================================================
-- INITIAL
--==============================================================

SetESPExpanded(false)

SetIBotExpanded(false)

SetTeleportExpanded(false)

RefreshMainSize()


print(
    "CAFEÍNA MOBILE V4 • carregado"
)
