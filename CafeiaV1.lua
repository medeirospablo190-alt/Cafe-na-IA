--==============================================================
-- CAFEÍNA • ESP + TP LITE V1
--
-- Foco:
--   ESP leve
--   Teleporte próximo
--   Players + Workspace.Soldiers
--
-- ESP:
--   Aliado:
--     Box verde
--     Distância verde
--
--   Inimigo:
--     Box vermelho
--     Distância vermelha
--     Aura branca
--
-- TELEPORTE:
--   Detecta player/bot inimigo próximo
--   Botão só fica disponível dentro da distância configurada
--   Slider ajustável em tempo real
--   Procura posição atrás do alvo
--   Checa chão
--   Tenta evitar parede/obstáculo
--   Orienta o personagem para o alvo
--==============================================================


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
-- LOCAL PLAYER
--==============================================================

local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    ESPEnabled = false,

    ESPBox = true,

    ESPDistance = true,

    EnemyAura = true,

    ESPPlayers = true,

    ESPBots = true,

    MaxESPDistance = 5000,

    ESPUpdateRate = 1 / 40,

    TeleportDistance = 35,

    TeleportMinDistance = 5,

    TeleportMaxDistance = 100,

    BehindDistance = 5,

    TeleportCheckRate = 0.08,

    TeleportConfirmDelay = 0.30
}


--==============================================================
-- COLORS
--==============================================================

local COLORS = {

    Ally =
        Color3.fromRGB(
            50,
            255,
            85
        ),

    Enemy =
        Color3.fromRGB(
            255,
            50,
            50
        ),

    Ready =
        Color3.fromRGB(
            55,
            220,
            90
        ),

    Disabled =
        Color3.fromRGB(
            60,
            60,
            68
        ),

    White =
        Color3.fromRGB(
            255,
            255,
            255
        ),

    Black =
        Color3.fromRGB(
            0,
            0,
            0
        ),

    Background =
        Color3.fromRGB(
            13,
            13,
            16
        ),

    Panel =
        Color3.fromRGB(
            21,
            21,
            25
        ),

    Panel2 =
        Color3.fromRGB(
            28,
            28,
            34
        ),

    Text =
        Color3.fromRGB(
            245,
            245,
            245
        ),

    SubText =
        Color3.fromRGB(
            145,
            145,
            155
        ),

    Accent =
        Color3.fromRGB(
            255,
            45,
            55
        ),

    Stroke =
        Color3.fromRGB(
            55,
            55,
            65
        )
}


--==============================================================
-- CLEAN OLD GUI
--==============================================================

for _, Name in ipairs({

    "CafeinaESPTPLite",
    "CafeinaESPOverlay"

}) do

    local Old =
        PlayerGui:FindFirstChild(Name)

    if Old then
        Old:Destroy()
    end
end


--==============================================================
-- RUNTIME
--==============================================================

local Connections = {}

local ESPObjects = {}

local Closed = false

local LastESPUpdate = 0

local LastTeleportCheck = 0

local CurrentTeleportTarget = nil

local CurrentTeleportTargetType = nil

local CurrentTeleportTargetDistance = nil

local TeleportReady = false


--==============================================================
-- CONNECTION HELPER
--==============================================================

local function Connect(
    Signal,
    Callback
)

    local Connection =
        Signal:Connect(Callback)

    table.insert(
        Connections,
        Connection
    )

    return Connection
end


--==============================================================
-- HELPERS
--==============================================================

local function SafeDestroy(Object)

    if not Object then
        return
    end

    pcall(function()
        Object:Destroy()
    end)
end


local function NormalizeTeam(Value)

    if Value == nil then
        return nil
    end

    return string.lower(
        tostring(Value)
    )
end


local function GetRoot(Model)

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


local function GetHead(Model)

    if not Model then
        return nil
    end

    return Model:FindFirstChild("Head")
end


local function IsAlive(Model)

    if not Model
    or not Model.Parent then

        return false
    end

    local Humanoid =
        Model:FindFirstChildOfClass(
            "Humanoid"
        )

    if Humanoid then

        return Humanoid.Health > 0
    end

    local Health =
        Model:GetAttribute(
            "Health"
        )

    if typeof(Health) == "number" then

        return Health > 0
    end

    return GetRoot(Model) ~= nil
end


local function GetLocalRoot()

    local Character =
        LocalPlayer.Character

    if not Character then
        return nil
    end

    return GetRoot(Character)
end


local function GetDistanceFromLocal(
    TargetRoot
)

    local LocalRoot =
        GetLocalRoot()

    if not LocalRoot
    or not TargetRoot then

        return nil
    end

    return (
        LocalRoot.Position -
        TargetRoot.Position
    ).Magnitude
end


--==============================================================
-- TEAM
--==============================================================

local function GetLocalTeam()

    if LocalPlayer.Team then

        return NormalizeTeam(
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

            return NormalizeTeam(
                Team
            )
        end
    end

    return nil
end


local function IsPlayerAlly(Player)

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
    and not Player.Neutral then

        if LocalPlayer.TeamColor ==
            Player.TeamColor then

            return true
        end
    end


    local LocalTeam =
        GetLocalTeam()

    if LocalTeam
    and Player.Character then

        local Team =
            Player.Character:
            GetAttribute(
                "Team"
            )

        if Team ~= nil then

            return
                NormalizeTeam(
                    Team
                )
                ==
                LocalTeam
        end
    end


    return false
end


local function GetBotTeam(Model)

    if not Model then
        return nil
    end


    local Team =
        Model:GetAttribute(
            "Team"
        )

    if Team ~= nil then

        return NormalizeTeam(
            Team
        )
    end


    for _, Name in ipairs({

        "HumanoidRootPart",
        "Humanoid",
        "Scripts",
        "SoldierAI"

    }) do

        local Object =
            Model:FindFirstChild(
                Name
            )

        if Object then

            local ObjectTeam =
                Object:GetAttribute(
                    "Team"
                )

            if ObjectTeam ~= nil then

                return NormalizeTeam(
                    ObjectTeam
                )
            end
        end
    end


    return nil
end


local function IsBotAlly(Model)

    local LocalTeam =
        GetLocalTeam()

    if not LocalTeam then

        return false
    end


    local BotTeam =
        GetBotTeam(
            Model
        )

    if not BotTeam then

        return false
    end


    return
        BotTeam ==
        LocalTeam
end


--==============================================================
-- BOT VALIDATION
--==============================================================

local function IsValidBot(Model)

    if not Model:IsA("Model") then
        return false
    end


    if Model:FindFirstChildOfClass(
        "Humanoid"
    ) then

        return true
    end


    if Model:FindFirstChild(
        "HumanoidRootPart"
    ) then

        return true
    end


    if Model:GetAttribute(
        "Team"
    ) ~= nil then

        return true
    end


    if typeof(
        Model:GetAttribute(
            "Health"
        )
    ) == "number" then

        return true
    end


    return false
end


--==============================================================
-- OVERLAY
--==============================================================

local Overlay =
    Instance.new(
        "ScreenGui"
    )

Overlay.Name =
    "CafeinaESPOverlay"

Overlay.ResetOnSpawn =
    false

Overlay.IgnoreGuiInset =
    true

Overlay.DisplayOrder =
    500

Overlay.ZIndexBehavior =
    Enum.ZIndexBehavior.Sibling

Overlay.Parent =
    PlayerGui


--==============================================================
-- CREATE ESP
--==============================================================

local function CreateESP(
    Key,
    TargetType,
    Target
)

    if ESPObjects[Key] then
        return ESPObjects[Key]
    end


    local Container =
        Instance.new("Frame")

    Container.BackgroundTransparency =
        1

    Container.BorderSizePixel =
        0

    Container.Visible =
        false

    Container.Parent =
        Overlay


    local Shadow =
        Instance.new("Frame")

    Shadow.Size =
        UDim2.fromScale(
            1,
            1
        )

    Shadow.BackgroundTransparency =
        1

    Shadow.BorderSizePixel =
        0

    Shadow.Parent =
        Container


    local ShadowStroke =
        Instance.new("UIStroke")

    ShadowStroke.Color =
        COLORS.Black

    ShadowStroke.Thickness =
        3.5

    ShadowStroke.Transparency =
        0.15

    ShadowStroke.Parent =
        Shadow


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
        Container


    local Stroke =
        Instance.new("UIStroke")

    Stroke.Thickness =
        1.6

    Stroke.Color =
        COLORS.Enemy

    Stroke.Parent =
        Box


    local DistanceLabel =
        Instance.new("TextLabel")

    DistanceLabel.Position =
        UDim2.new(
            0,
            0,
            0,
            -24
        )

    DistanceLabel.Size =
        UDim2.new(
            1,
            0,
            0,
            20
        )

    DistanceLabel.BackgroundColor3 =
        COLORS.Black

    DistanceLabel.BackgroundTransparency =
        0.20

    DistanceLabel.BorderSizePixel =
        0

    DistanceLabel.Font =
        Enum.Font.GothamBold

    DistanceLabel.TextSize =
        11

    DistanceLabel.TextColor3 =
        COLORS.Enemy

    DistanceLabel.TextStrokeColor3 =
        COLORS.Black

    DistanceLabel.TextStrokeTransparency =
        0

    DistanceLabel.Text =
        ""

    DistanceLabel.Parent =
        Container


    local LabelCorner =
        Instance.new("UICorner")

    LabelCorner.CornerRadius =
        UDim.new(
            0,
            4
        )

    LabelCorner.Parent =
        DistanceLabel


    local Highlight =
        Instance.new("Highlight")

    Highlight.Name =
        "CafeinaEnemyAura"

    Highlight.Enabled =
        false

    Highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    Highlight.FillColor =
        COLORS.White

    Highlight.FillTransparency =
        0.58

    Highlight.OutlineColor =
        COLORS.White

    Highlight.OutlineTransparency =
        0.05

    Highlight.Parent =
        Workspace


    local Data = {

        Key = Key,

        Type = TargetType,

        Target = Target,

        Container = Container,

        Shadow = Shadow,

        Box = Box,

        Stroke = Stroke,

        DistanceLabel =
            DistanceLabel,

        Highlight = Highlight
    }


    ESPObjects[Key] =
        Data

    return Data
end


--==============================================================
-- ESP CLEANUP
--==============================================================

local function HideESP(Data)

    if not Data then
        return
    end

    Data.Container.Visible =
        false

    if Data.Highlight then

        Data.Highlight.Enabled =
            false

        Data.Highlight.Adornee =
            nil
    end
end


local function RemoveESP(Key)

    local Data =
        ESPObjects[Key]

    if not Data then
        return
    end

    SafeDestroy(
        Data.Container
    )

    SafeDestroy(
        Data.Highlight
    )

    ESPObjects[Key] =
        nil
end


local function HideAllESP()

    for _, Data in pairs(
        ESPObjects
    ) do

        HideESP(Data)
    end
end


--==============================================================
-- SCREEN BOX
--==============================================================

local function GetScreenBox(Model)

    local Camera =
        Workspace.CurrentCamera

    if not Camera
    or not Model then

        return nil
    end


    local Root =
        GetRoot(Model)

    if not Root then
        return nil
    end


    local Head =
        GetHead(Model)


    --==========================================================
    -- STABLE HUMANOID BOX
    --==========================================================

    if Head then

        local RootScreen =
            Camera:
            WorldToViewportPoint(
                Root.Position
            )

        local HeadScreen =
            Camera:
            WorldToViewportPoint(
                Head.Position +
                Vector3.new(
                    0,
                    0.65,
                    0
                )
            )

        local FeetScreen =
            Camera:
            WorldToViewportPoint(
                Root.Position -
                Vector3.new(
                    0,
                    3,
                    0
                )
            )


        if RootScreen.Z > 0
        and HeadScreen.Z > 0
        and FeetScreen.Z > 0 then

            local Height =
                math.abs(
                    FeetScreen.Y -
                    HeadScreen.Y
                )

            if Height > 8 then

                local Width =
                    Height * 0.48

                local CenterX =
                    RootScreen.X

                return

                    CenterX -
                    Width / 2,

                    HeadScreen.Y,

                    CenterX +
                    Width / 2,

                    FeetScreen.Y
            end
        end
    end


    --==========================================================
    -- BOUNDING BOX FALLBACK
    --==========================================================

    local Success,
        CF,
        Size =
        pcall(function()

            return Model:GetBoundingBox()

        end)


    if not Success then
        return nil
    end


    local Half =
        Size / 2


    local Points = {

        Vector3.new(-Half.X, -Half.Y, -Half.Z),
        Vector3.new( Half.X, -Half.Y, -Half.Z),
        Vector3.new(-Half.X,  Half.Y, -Half.Z),
        Vector3.new( Half.X,  Half.Y, -Half.Z),

        Vector3.new(-Half.X, -Half.Y,  Half.Z),
        Vector3.new( Half.X, -Half.Y,  Half.Z),
        Vector3.new(-Half.X,  Half.Y,  Half.Z),
        Vector3.new( Half.X,  Half.Y,  Half.Z)
    }


    local MinX =
        math.huge

    local MinY =
        math.huge

    local MaxX =
        -math.huge

    local MaxY =
        -math.huge

    local Valid =
        0


    for _, Point in ipairs(
        Points
    ) do

        local World =
            CF:
            PointToWorldSpace(
                Point
            )

        local Screen =
            Camera:
            WorldToViewportPoint(
                World
            )


        if Screen.Z > 0 then

            Valid += 1

            MinX =
                math.min(
                    MinX,
                    Screen.X
                )

            MinY =
                math.min(
                    MinY,
                    Screen.Y
                )

            MaxX =
                math.max(
                    MaxX,
                    Screen.X
                )

            MaxY =
                math.max(
                    MaxY,
                    Screen.Y
                )
        end
    end


    if Valid == 0 then
        return nil
    end


    return
        MinX,
        MinY,
        MaxX,
        MaxY
end


--==============================================================
-- UPDATE TARGET ESP
--==============================================================

local function UpdateESPData(
    Data,
    Model,
    IsAlly
)

    if not CONFIG.ESPEnabled
    or not Model
    or not IsAlive(Model) then

        HideESP(Data)

        return
    end


    local Root =
        GetRoot(Model)

    if not Root then

        HideESP(Data)

        return
    end


    local Distance =
        GetDistanceFromLocal(
            Root
        )

    if not Distance
    or Distance >
        CONFIG.MaxESPDistance then

        HideESP(Data)

        return
    end


    local MinX,
        MinY,
        MaxX,
        MaxY =
        GetScreenBox(Model)


    if not MinX then

        HideESP(Data)

        return
    end


    local Width =
        math.clamp(
            MaxX - MinX,
            8,
            900
        )

    local Height =
        math.clamp(
            MaxY - MinY,
            12,
            1100
        )


    local Color =
        IsAlly
        and COLORS.Ally
        or COLORS.Enemy


    Data.Container.Position =
        UDim2.fromOffset(
            MinX,
            MinY
        )

    Data.Container.Size =
        UDim2.fromOffset(
            Width,
            Height
        )

    Data.Container.Visible =
        true


    Data.Box.Visible =
        CONFIG.ESPBox

    Data.Shadow.Visible =
        CONFIG.ESPBox


    Data.Stroke.Color =
        Color


    Data.DistanceLabel.Visible =
        CONFIG.ESPDistance

    Data.DistanceLabel.TextColor3 =
        Color


    if CONFIG.ESPDistance then

        Data.DistanceLabel.Text =
            tostring(
                math.floor(
                    Distance +
                    0.5
                )
            )
            ..
            " studs"
    end


    if CONFIG.EnemyAura
    and not IsAlly then

        Data.Highlight.Adornee =
            Model

        Data.Highlight.Enabled =
            true

    else

        Data.Highlight.Enabled =
            false

        Data.Highlight.Adornee =
            nil
    end
end


--==============================================================
-- UPDATE PLAYERS
--==============================================================

local function UpdatePlayersESP()

    local Existing = {}


    for _, Player in ipairs(
        Players:GetPlayers()
    ) do

        if Player ~= LocalPlayer then

            local Key =
                "PLAYER_"
                ..
                tostring(
                    Player.UserId
                )


            Existing[Key] =
                true


            if CONFIG.ESPPlayers then

                local Data =
                    ESPObjects[Key]


                if not Data then

                    Data =
                        CreateESP(
                            Key,
                            "Player",
                            Player
                        )
                end


                local Character =
                    Player.Character


                if Character then

                    UpdateESPData(

                        Data,

                        Character,

                        IsPlayerAlly(
                            Player
                        )
                    )

                else

                    HideESP(Data)
                end

            else

                local Data =
                    ESPObjects[Key]

                if Data then
                    HideESP(Data)
                end
            end
        end
    end


    local RemoveList = {}


    for Key, Data in pairs(
        ESPObjects
    ) do

        if Data.Type == "Player"
        and not Existing[Key] then

            table.insert(
                RemoveList,
                Key
            )
        end
    end


    for _, Key in ipairs(
        RemoveList
    ) do

        RemoveESP(Key)
    end
end


--==============================================================
-- UPDATE BOTS
--==============================================================

local function UpdateBotsESP()

    local Soldiers =
        Workspace:
        FindFirstChild(
            "Soldiers"
        )


    if not Soldiers then

        for _, Data in pairs(
            ESPObjects
        ) do

            if Data.Type == "Bot" then

                HideESP(Data)
            end
        end

        return
    end


    local Existing = {}


    for _, Model in ipairs(
        Soldiers:GetChildren()
    ) do

        if IsValidBot(Model) then

            local Key =
                Model


            Existing[Key] =
                true


            if CONFIG.ESPBots then

                local Data =
                    ESPObjects[Key]


                if not Data then

                    Data =
                        CreateESP(
                            Key,
                            "Bot",
                            Model
                        )
                end


                UpdateESPData(

                    Data,

                    Model,

                    IsBotAlly(
                        Model
                    )
                )

            else

                local Data =
                    ESPObjects[Key]

                if Data then
                    HideESP(Data)
                end
            end
        end
    end


    local RemoveList = {}


    for Key, Data in pairs(
        ESPObjects
    ) do

        if Data.Type == "Bot"
        and not Existing[Key] then

            table.insert(
                RemoveList,
                Key
            )
        end
    end


    for _, Key in ipairs(
        RemoveList
    ) do

        RemoveESP(Key)
    end
end


--==============================================================
-- TELEPORT TARGET SEARCH
--==============================================================

local function GetClosestEnemy()

    local BestTarget =
        nil

    local BestType =
        nil

    local BestDistance =
        math.huge


    --==========================================================
    -- PLAYERS
    --==========================================================

    for _, Player in ipairs(
        Players:GetPlayers()
    ) do

        if Player ~= LocalPlayer
        and not IsPlayerAlly(Player) then

            local Character =
                Player.Character


            if Character
            and IsAlive(Character) then

                local Root =
                    GetRoot(Character)


                if Root then

                    local Distance =
                        GetDistanceFromLocal(
                            Root
                        )


                    if Distance
                    and Distance <
                        BestDistance then

                        BestDistance =
                            Distance

                        BestTarget =
                            Character

                        BestType =
                            "Player"
                    end
                end
            end
        end
    end


    --==========================================================
    -- BOTS
    --==========================================================

    local Soldiers =
        Workspace:
        FindFirstChild(
            "Soldiers"
        )


    if Soldiers then

        for _, Model in ipairs(
            Soldiers:GetChildren()
        ) do

            if IsValidBot(Model)
            and IsAlive(Model)
            and not IsBotAlly(Model) then

                local Root =
                    GetRoot(Model)


                if Root then

                    local Distance =
                        GetDistanceFromLocal(
                            Root
                        )


                    if Distance
                    and Distance <
                        BestDistance then

                        BestDistance =
                            Distance

                        BestTarget =
                            Model

                        BestType =
                            "Bot"
                    end
                end
            end
        end
    end


    return
        BestTarget,
        BestType,
        BestDistance
end


--==============================================================
-- RAYCAST HELPERS
--==============================================================

local function BuildRaycastParams(
    ExtraIgnore
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


    if ExtraIgnore then

        table.insert(
            Ignore,
            ExtraIgnore
        )
    end


    Params.FilterDescendantsInstances =
        Ignore


    Params.IgnoreWater =
        false


    return Params
end


--==============================================================
-- FIND GROUND
--==============================================================

local function FindGroundPosition(
    DesiredPosition,
    TargetModel
)

    local Origin =
        DesiredPosition +
        Vector3.new(
            0,
            8,
            0
        )


    local Direction =
        Vector3.new(
            0,
            -30,
            0
        )


    local Result =
        Workspace:Raycast(

            Origin,

            Direction,

            BuildRaycastParams(
                TargetModel
            )
        )


    if not Result then
        return nil
    end


    return
        Result.Position +
        Vector3.new(
            0,
            3.2,
            0
        )
end


--==============================================================
-- CHECK SPACE
--==============================================================

local function IsPositionClear(
    Position,
    TargetModel
)

    local Character =
        LocalPlayer.Character

    if not Character then
        return false
    end


    local Params =
        OverlapParams.new()


    Params.FilterType =
        Enum.RaycastFilterType.Exclude


    local Ignore = {
        Character
    }


    if TargetModel then

        table.insert(
            Ignore,
            TargetModel
        )
    end


    Params.FilterDescendantsInstances =
        Ignore


    local Parts =
        Workspace:
        GetPartBoundsInBox(

            CFrame.new(
                Position
            ),

            Vector3.new(
                3.5,
                5.5,
                3.5
            ),

            Params
        )


    for _, Part in ipairs(
        Parts
    ) do

        if Part:IsA("BasePart")
        and Part.CanCollide
        and Part.Transparency < 1 then

            return false
        end
    end


    return true
end


--==============================================================
-- WALL CHECK
--==============================================================

local function HasDirectClearance(
    FromPosition,
    ToPosition,
    TargetModel
)

    local Direction =
        ToPosition -
        FromPosition


    if Direction.Magnitude <= 0.1 then
        return true
    end


    local Result =
        Workspace:Raycast(

            FromPosition,

            Direction,

            BuildRaycastParams(
                TargetModel
            )
        )


    return Result == nil
end


--==============================================================
-- SAFE TELEPORT POSITION
--==============================================================

local function FindSafeTeleportPosition(
    TargetModel
)

    local TargetRoot =
        GetRoot(TargetModel)


    if not TargetRoot then
        return nil
    end


    local Forward =
        TargetRoot.CFrame.LookVector


    local Right =
        TargetRoot.CFrame.RightVector


    local Behind =
        -Forward


    local Candidates = {

        Behind *
            CONFIG.BehindDistance,

        Behind *
            (
                CONFIG.BehindDistance +
                1.5
            ),

        Behind *
            (
                CONFIG.BehindDistance -
                1
            )
            +
        Right * 2,

        Behind *
            (
                CONFIG.BehindDistance -
                1
            )
            -
        Right * 2,

        Behind *
            (
                CONFIG.BehindDistance +
                2
            )
            +
        Right * 2.5,

        Behind *
            (
                CONFIG.BehindDistance +
                2
            )
            -
        Right * 2.5
    }


    for _, Offset in ipairs(
        Candidates
    ) do

        local Desired =
            TargetRoot.Position +
            Offset


        local Grounded =
            FindGroundPosition(

                Desired,

                TargetModel
            )


        if Grounded
        and IsPositionClear(
            Grounded,
            TargetModel
        )
        and HasDirectClearance(

            Grounded +
            Vector3.new(
                0,
                1.5,
                0
            ),

            TargetRoot.Position +
            Vector3.new(
                0,
                1,
                0
            ),

            TargetModel
        ) then

            return Grounded
        end
    end


    return nil
end


--==============================================================
-- EXECUTE TELEPORT
--==============================================================

local function ExecuteTeleport()

    if not TeleportReady then
        return false
    end


    local Target =
        CurrentTeleportTarget


    if not Target
    or not Target.Parent
    or not IsAlive(Target) then

        return false
    end


    local TargetRoot =
        GetRoot(Target)


    local LocalRoot =
        GetLocalRoot()


    if not TargetRoot
    or not LocalRoot then

        return false
    end


    local Distance =
        GetDistanceFromLocal(
            TargetRoot
        )


    if not Distance
    or Distance >
        CONFIG.TeleportDistance then

        return false
    end


    local SafePosition =
        FindSafeTeleportPosition(
            Target
        )


    if not SafePosition then

        return false
    end


    local OldPosition =
        LocalRoot.Position


    local NewCFrame =
        CFrame.lookAt(

            SafePosition,

            TargetRoot.Position
        )


    LocalRoot.CFrame =
        NewCFrame


    task.delay(

        CONFIG.TeleportConfirmDelay,

        function()

            local Root =
                GetLocalRoot()


            if not Root then
                return
            end


            local DistanceToNew =
                (
                    Root.Position -
                    SafePosition
                ).Magnitude


            local DistanceToOld =
                (
                    Root.Position -
                    OldPosition
                ).Magnitude


            if DistanceToNew < 8 then

                print(
                    "CAFEÍNA TP: posição mantida"
                )

            elseif DistanceToOld < 8 then

                print(
                    "CAFEÍNA TP: posição aparentemente corrigida"
                )
            end
        end
    )


    return true
end


--==============================================================
-- MAIN GUI
--==============================================================

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "CafeinaESPTPLite"

Gui.ResetOnSpawn =
    false

Gui.DisplayOrder =
    600

Gui.Parent =
    PlayerGui


--==============================================================
-- MAIN PANEL
--==============================================================

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        260,
        150
    )

Main.Position =
    UDim2.new(
        0.5,
        -130,
        0.5,
        -75
    )

Main.BackgroundColor3 =
    COLORS.Background

Main.BorderSizePixel =
    0

Main.Parent =
    Gui


Instance.new(
    "UICorner",
    Main
).CornerRadius =
    UDim.new(
        0,
        11
    )


local MainStroke =
    Instance.new("UIStroke")

MainStroke.Color =
    COLORS.Stroke

MainStroke.Parent =
    Main


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
        42
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
        -70,
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
    15

Title.TextColor3 =
    COLORS.Text

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Header


local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.fromOffset(
        30,
        30
    )

Close.Position =
    UDim2.new(
        1,
        -36,
        0,
        6
    )

Close.BackgroundColor3 =
    COLORS.Accent

Close.Text =
    "×"

Close.Font =
    Enum.Font.GothamBold

Close.TextSize =
    17

Close.TextColor3 =
    COLORS.Text

Close.BorderSizePixel =
    0

Close.Parent =
    Header


Instance.new(
    "UICorner",
    Close
).CornerRadius =
    UDim.new(
        0,
        7
    )


--==============================================================
-- MENU CONTENT
--==============================================================

local Content =
    Instance.new("Frame")

Content.Position =
    UDim2.fromOffset(
        8,
        44
    )

Content.Size =
    UDim2.new(
        1,
        -16,
        1,
        -52
    )

Content.BackgroundTransparency =
    1

Content.Parent =
    Main


local Layout =
    Instance.new("UIListLayout")

Layout.Padding =
    UDim.new(
        0,
        6
    )

Layout.Parent =
    Content


--==============================================================
-- EXPANDABLE ESP PANEL
--==============================================================

local ESPHolder =
    Instance.new("Frame")

ESPHolder.Size =
    UDim2.new(
        1,
        0,
        0,
        44
    )

ESPHolder.BackgroundColor3 =
    COLORS.Panel

ESPHolder.BorderSizePixel =
    0

ESPHolder.ClipsDescendants =
    true

ESPHolder.Parent =
    Content


Instance.new(
    "UICorner",
    ESPHolder
).CornerRadius =
    UDim.new(
        0,
        8
    )


local ESPMainButton =
    Instance.new("TextButton")

ESPMainButton.Size =
    UDim2.new(
        1,
        0,
        0,
        44
    )

ESPMainButton.BackgroundTransparency =
    1

ESPMainButton.Text =
    ""

ESPMainButton.Parent =
    ESPHolder


local ESPLabel =
    Instance.new("TextLabel")

ESPLabel.Position =
    UDim2.fromOffset(
        10,
        0
    )

ESPLabel.Size =
    UDim2.new(
        1,
        -65,
        0,
        44
    )

ESPLabel.BackgroundTransparency =
    1

ESPLabel.Text =
    "ESP"

ESPLabel.Font =
    Enum.Font.GothamBold

ESPLabel.TextSize =
    13

ESPLabel.TextColor3 =
    COLORS.Text

ESPLabel.TextXAlignment =
    Enum.TextXAlignment.Left

ESPLabel.Parent =
    ESPHolder


local ESPState =
    Instance.new("TextLabel")

ESPState.Position =
    UDim2.new(
        1,
        -55,
        0,
        0
    )

ESPState.Size =
    UDim2.fromOffset(
        45,
        44
    )

ESPState.BackgroundTransparency =
    1

ESPState.Text =
    "OFF"

ESPState.Font =
    Enum.Font.GothamBold

ESPState.TextSize =
    11

ESPState.TextColor3 =
    COLORS.SubText

ESPState.Parent =
    ESPHolder


local ESPOptions =
    Instance.new("Frame")

ESPOptions.Position =
    UDim2.fromOffset(
        0,
        44
    )

ESPOptions.Size =
    UDim2.new(
        1,
        0,
        0,
        175
    )

ESPOptions.BackgroundTransparency =
    1

ESPOptions.Parent =
    ESPHolder


local ESPOptionLayout =
    Instance.new("UIListLayout")

ESPOptionLayout.Padding =
    UDim.new(
        0,
        3
    )

ESPOptionLayout.Parent =
    ESPOptions


local ESPExpanded =
    false


--==============================================================
-- SMALL OPTION TOGGLE
--==============================================================

local function AddSmallToggle(
    Text,
    Default,
    Callback
)

    local State =
        Default


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
        ESPOptions


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
            -60,
            1,
            0
        )

    Label.BackgroundTransparency =
        1

    Label.Text =
        Text

    Label.Font =
        Enum.Font.GothamMedium

    Label.TextSize =
        11

    Label.TextColor3 =
        COLORS.Text

    Label.TextXAlignment =
        Enum.TextXAlignment.Left

    Label.Parent =
        Row


    local Value =
        Instance.new("TextLabel")

    Value.Position =
        UDim2.new(
            1,
            -48,
            0,
            0
        )

    Value.Size =
        UDim2.fromOffset(
            40,
            32
        )

    Value.BackgroundTransparency =
        1

    Value.Font =
        Enum.Font.GothamBold

    Value.TextSize =
        10

    Value.Parent =
        Row


    local function Refresh()

        Value.Text =
            State
            and "ON"
            or "OFF"

        Value.TextColor3 =
            State
            and COLORS.Ready
            or COLORS.SubText
    end


    Refresh()


    Row.MouseButton1Click:
        Connect(function()

            State =
                not State

            Refresh()

            Callback(State)

        end)
end


AddSmallToggle(
    "Box",
    true,
    function(Value)
        CONFIG.ESPBox = Value
    end
)


AddSmallToggle(
    "Distância",
    true,
    function(Value)
        CONFIG.ESPDistance = Value
    end
)


AddSmallToggle(
    "Aura inimigos",
    true,
    function(Value)

        CONFIG.EnemyAura =
            Value

        if not Value then

            for _, Data in pairs(
                ESPObjects
            ) do

                if Data.Highlight then

                    Data.Highlight.Enabled =
                        false

                    Data.Highlight.Adornee =
                        nil
                end
            end
        end
    end
)


AddSmallToggle(
    "Players",
    true,
    function(Value)
        CONFIG.ESPPlayers = Value
    end
)


AddSmallToggle(
    "Bots",
    true,
    function(Value)
        CONFIG.ESPBots = Value
    end
)


--==============================================================
-- ESP MAIN BUTTON
--==============================================================

ESPMainButton.MouseButton1Click:
    Connect(function()

        CONFIG.ESPEnabled =
            not CONFIG.ESPEnabled


        ESPExpanded =
            CONFIG.ESPEnabled


        ESPState.Text =
            CONFIG.ESPEnabled
            and "ON"
            or "OFF"


        ESPState.TextColor3 =
            CONFIG.ESPEnabled
            and COLORS.Ready
            or COLORS.SubText


        ESPHolder.Size =
            UDim2.new(
                1,
                0,
                0,
                ESPExpanded
                and 222
                or 44
            )


        Main.Size =
            UDim2.fromOffset(
                260,
                ESPExpanded
                and 328
                or 150
            )


        if not CONFIG.ESPEnabled then

            HideAllESP()
        end
    end)


--==============================================================
-- TELEPORT OPEN BUTTON
--==============================================================

local TeleportOpen =
    Instance.new("TextButton")

TeleportOpen.Size =
    UDim2.new(
        1,
        0,
        0,
        44
    )

TeleportOpen.BackgroundColor3 =
    COLORS.Panel

TeleportOpen.BorderSizePixel =
    0

TeleportOpen.Text =
    "TELEPORTE   >"

TeleportOpen.Font =
    Enum.Font.GothamBold

TeleportOpen.TextSize =
    12

TeleportOpen.TextColor3 =
    COLORS.Text

TeleportOpen.Parent =
    Content


Instance.new(
    "UICorner",
    TeleportOpen
).CornerRadius =
    UDim.new(
        0,
        8
    )


--==============================================================
-- TELEPORT MINI PANEL
--==============================================================

local TPPanel =
    Instance.new("Frame")

TPPanel.Size =
    UDim2.fromOffset(
        190,
        138
    )

TPPanel.Position =
    UDim2.new(
        0.5,
        -95,
        0.5,
        -69
    )

TPPanel.BackgroundColor3 =
    COLORS.Background

TPPanel.BorderSizePixel =
    0

TPPanel.Visible =
    false

TPPanel.Parent =
    Gui


Instance.new(
    "UICorner",
    TPPanel
).CornerRadius =
    UDim.new(
        0,
        10
    )


local TPStroke =
    Instance.new("UIStroke")

TPStroke.Color =
    COLORS.Stroke

TPStroke.Parent =
    TPPanel


--==============================================================
-- TP BUTTON
--==============================================================

local TPButton =
    Instance.new("TextButton")

TPButton.Size =
    UDim2.fromOffset(
        52,
        52
    )

TPButton.Position =
    UDim2.new(
        0.5,
        -26,
        0,
        8
    )

TPButton.BackgroundColor3 =
    COLORS.Disabled

TPButton.BorderSizePixel =
    0

TPButton.Text =
    "TP"

TPButton.Font =
    Enum.Font.GothamBold

TPButton.TextSize =
    16

TPButton.TextColor3 =
    COLORS.Text

TPButton.Parent =
    TPPanel


Instance.new(
    "UICorner",
    TPButton
).CornerRadius =
    UDim.new(
        1,
        0
    )


--==============================================================
-- DISTANCE VALUE
--==============================================================

local TPDistanceLabel =
    Instance.new("TextLabel")

TPDistanceLabel.Position =
    UDim2.fromOffset(
        8,
        61
    )

TPDistanceLabel.Size =
    UDim2.new(
        1,
        -16,
        0,
        20
    )

TPDistanceLabel.BackgroundTransparency =
    1

TPDistanceLabel.Text =
    tostring(
        CONFIG.TeleportDistance
    )
    ..
    " studs"

TPDistanceLabel.Font =
    Enum.Font.GothamBold

TPDistanceLabel.TextSize =
    11

TPDistanceLabel.TextColor3 =
    COLORS.Text

TPDistanceLabel.Parent =
    TPPanel


--==============================================================
-- SLIDER
--==============================================================

local Slider =
    Instance.new("Frame")

Slider.Position =
    UDim2.fromOffset(
        14,
        85
    )

Slider.Size =
    UDim2.new(
        1,
        -28,
        0,
        6
    )

Slider.BackgroundColor3 =
    COLORS.Disabled

Slider.BorderSizePixel =
    0

Slider.Parent =
    TPPanel


Instance.new(
    "UICorner",
    Slider
).CornerRadius =
    UDim.new(
        1,
        0
    )


local SliderFill =
    Instance.new("Frame")

SliderFill.Size =
    UDim2.fromScale(
        0.315,
        1
    )

SliderFill.BackgroundColor3 =
    COLORS.Accent

SliderFill.BorderSizePixel =
    0

SliderFill.Parent =
    Slider


Instance.new(
    "UICorner",
    SliderFill
).CornerRadius =
    UDim.new(
        1,
        0
    )


local Knob =
    Instance.new("Frame")

Knob.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

Knob.Size =
    UDim2.fromOffset(
        18,
        18
    )

Knob.Position =
    UDim2.new(
        0.315,
        0,
        0.5,
        0
    )

Knob.BackgroundColor3 =
    COLORS.White

Knob.BorderSizePixel =
    0

Knob.Parent =
    Slider


Instance.new(
    "UICorner",
    Knob
).CornerRadius =
    UDim.new(
        1,
        0
    )


--==============================================================
-- TP STATUS
--==============================================================

local TPStatus =
    Instance.new("TextLabel")

TPStatus.Position =
    UDim2.fromOffset(
        8,
        98
    )

TPStatus.Size =
    UDim2.new(
        1,
        -60,
        0,
        28
    )

TPStatus.BackgroundTransparency =
    1

TPStatus.Text =
    "SEM ALVO"

TPStatus.Font =
    Enum.Font.GothamBold

TPStatus.TextSize =
    10

TPStatus.TextColor3 =
    COLORS.SubText

TPStatus.TextXAlignment =
    Enum.TextXAlignment.Left

TPStatus.Parent =
    TPPanel


--==============================================================
-- BACK
--==============================================================

local Back =
    Instance.new("TextButton")

Back.Size =
    UDim2.fromOffset(
        46,
        26
    )

Back.Position =
    UDim2.new(
        1,
        -54,
        1,
        -34
    )

Back.BackgroundColor3 =
    COLORS.Panel2

Back.BorderSizePixel =
    0

Back.Text =
    "VOLTAR"

Back.Font =
    Enum.Font.GothamBold

Back.TextSize =
    8

Back.TextColor3 =
    COLORS.Text

Back.Parent =
    TPPanel


Instance.new(
    "UICorner",
    Back
).CornerRadius =
    UDim.new(
        0,
        6
    )


--==============================================================
-- OPEN / CLOSE TP PANEL
--==============================================================

TeleportOpen.MouseButton1Click:
    Connect(function()

        Main.Visible =
            false

        TPPanel.Visible =
            true
    end)


Back.MouseButton1Click:
    Connect(function()

        TPPanel.Visible =
            false

        Main.Visible =
            true
    end)


--==============================================================
-- SLIDER LOGIC
--==============================================================

local SliderDragging =
    false


local function SetSliderFromX(X)

    local AbsoluteX =
        Slider.AbsolutePosition.X

    local Width =
        Slider.AbsoluteSize.X


    if Width <= 0 then
        return
    end


    local Alpha =
        math.clamp(

            (
                X -
                AbsoluteX
            )
            /
            Width,

            0,

            1
        )


    local Value =
        CONFIG.TeleportMinDistance
        +
        Alpha
        *
        (
            CONFIG.TeleportMaxDistance -
            CONFIG.TeleportMinDistance
        )


    Value =
        math.floor(
            Value +
            0.5
        )


    CONFIG.TeleportDistance =
        Value


    SliderFill.Size =
        UDim2.fromScale(
            Alpha,
            1
        )


    Knob.Position =
        UDim2.new(
            Alpha,
            0,
            0.5,
            0
        )


    TPDistanceLabel.Text =
        tostring(Value)
        ..
        " studs"
end


Slider.InputBegan:
    Connect(function(Input)

        if Input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or Input.UserInputType ==
            Enum.UserInputType.Touch then

            SliderDragging =
                true

            SetSliderFromX(
                Input.Position.X
            )
        end
    end)


Knob.InputBegan:
    Connect(function(Input)

        if Input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or Input.UserInputType ==
            Enum.UserInputType.Touch then

            SliderDragging =
                true

            SetSliderFromX(
                Input.Position.X
            )
        end
    end)


Connect(

    UserInputService.InputChanged,

    function(Input)

        if SliderDragging
        and (
            Input.UserInputType ==
            Enum.UserInputType.MouseMovement

            or

            Input.UserInputType ==
            Enum.UserInputType.Touch
        ) then

            SetSliderFromX(
                Input.Position.X
            )
        end
    end
)


Connect(

    UserInputService.InputEnded,

    function(Input)

        if Input.UserInputType ==
            Enum.UserInputType.MouseButton1

        or Input.UserInputType ==
            Enum.UserInputType.Touch then

            SliderDragging =
                false
        end
    end
)


--==============================================================
-- TP BUTTON
--==============================================================

TPButton.MouseButton1Click:
    Connect(function()

        if not TeleportReady then
            return
        end

        ExecuteTeleport()
    end)


--==============================================================
-- DRAG MAIN
--==============================================================

local function MakeDraggable(
    Handle,
    Object
)

    local Dragging =
        false

    local DragInput =
        nil

    local DragStart =
        nil

    local StartPosition =
        nil


    Handle.InputBegan:
        Connect(function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.MouseButton1

            or Input.UserInputType ==
                Enum.UserInputType.Touch then

                Dragging =
                    true

                DragStart =
                    Input.Position

                StartPosition =
                    Object.Position
            end
        end)


    Handle.InputChanged:
        Connect(function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.MouseMovement

            or Input.UserInputType ==
                Enum.UserInputType.Touch then

                DragInput =
                    Input
            end
        end)


    Connect(

        UserInputService.InputChanged,

        function(Input)

            if not Dragging
            or Input ~= DragInput
            or not DragStart
            or not StartPosition then

                return
            end


            local Delta =
                Input.Position -
                DragStart


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
                Enum.UserInputType.MouseButton1

            or Input.UserInputType ==
                Enum.UserInputType.Touch then

                Dragging =
                    false
            end
        end
    )
end


MakeDraggable(
    Header,
    Main
)

MakeDraggable(
    TPPanel,
    TPPanel
)


--==============================================================
-- MAIN LOOP
--==============================================================

Connect(

    RunService.RenderStepped,

    function()

        if Closed then
            return
        end


        local Now =
            os.clock()


        --======================================================
        -- ESP
        --======================================================

        if CONFIG.ESPEnabled
        and Now -
            LastESPUpdate >=
            CONFIG.ESPUpdateRate then

            LastESPUpdate =
                Now


            if CONFIG.ESPPlayers then

                UpdatePlayersESP()
            end


            if CONFIG.ESPBots then

                UpdateBotsESP()
            end
        end


        --======================================================
        -- TELEPORT TARGET
        --======================================================

        if Now -
            LastTeleportCheck >=
            CONFIG.TeleportCheckRate then

            LastTeleportCheck =
                Now


            local Target,
                TargetType,
                Distance =
                GetClosestEnemy()


            CurrentTeleportTarget =
                Target

            CurrentTeleportTargetType =
                TargetType

            CurrentTeleportTargetDistance =
                Distance


            TeleportReady =
                Target ~= nil
                and Distance ~= nil
                and Distance <=
                    CONFIG.TeleportDistance


            if TeleportReady then

                TPButton.BackgroundColor3 =
                    COLORS.Ready


                TPStatus.TextColor3 =
                    COLORS.Ready


                TPStatus.Text =
                    "PRONTO • "
                    ..
                    tostring(
                        math.floor(
                            Distance +
                            0.5
                        )
                    )
                    ..
                    " studs"

            elseif Target
            and Distance then

                TPButton.BackgroundColor3 =
                    COLORS.Disabled


                TPStatus.TextColor3 =
                    COLORS.SubText


                TPStatus.Text =
                    "ALVO • "
                    ..
                    tostring(
                        math.floor(
                            Distance +
                            0.5
                        )
                    )
                    ..
                    " studs"

            else

                TPButton.BackgroundColor3 =
                    COLORS.Disabled


                TPStatus.TextColor3 =
                    COLORS.SubText


                TPStatus.Text =
                    "SEM ALVO"
            end
        end
    end
)


--==============================================================
-- CLOSE
--==============================================================

Close.MouseButton1Click:
    Connect(function()

        Closed =
            true

        CONFIG.ESPEnabled =
            false


        HideAllESP()


        for _, Connection in ipairs(
            Connections
        ) do

            pcall(function()

                Connection:
                Disconnect()
            end)
        end


        table.clear(
            Connections
        )


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

            RemoveESP(Key)
        end


        SafeDestroy(
            Overlay
        )


        SafeDestroy(
            Gui
        )
    end)


--==============================================================
-- FINAL
--==============================================================

print(
    "CAFEÍNA • ESP + TP LITE V1 carregado"
)
