--[[
================================================================
 CAFEÍNA • WEAPON LAB V2
 MOBILE WEAPON TEST

 FUNÇÕES
 ----------------------------------------------------------------
 • SEM RECARGA
      - Remove animação de reload
      - Tenta zerar ReloadTime/ReloadDuration/etc
      - Mantém valores originais para restaurar no shutdown

 • SEM ANIMAÇÕES
      - Reload
      - Shoot / Fire
      - Recoil
      - Equip
      - Inspect
      - Pump / Bolt
      - outras animações identificadas como arma

 • RAJADA
      - Quantidade configurável
      - Intervalo configurável

 • FIRE CONTÍNUO
      - Segurar botão FIRE = dispara sem parar
      - Soltar = para
      - Funciona também com armas de disparo único
      - Evita criar vários loops simultâneos

 • MOBILE
      - Menu arrastável
      - Minimizar
      - Restaurar
      - Shutdown completo

 IMPORTANTE
 ----------------------------------------------------------------
 • O script utiliza Tool:Activate().
 • Não tenta adivinhar/remotear RemoteEvents de dano.
 • Não força o servidor a aceitar uma cadência que ele rejeite.
================================================================
]]


--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local UserInputService =
    game:GetService("UserInputService")

local RunService =
    game:GetService("RunService")


local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")


--==============================================================
-- RUNTIME
--==============================================================

local ENV = _G

if type(getgenv) == "function" then

    local OK,
        Result =
        pcall(getgenv)

    if OK and Result then
        ENV = Result
    end
end


if ENV.CAFEINA_WEAPON_LAB
and type(
    ENV.CAFEINA_WEAPON_LAB.Shutdown
) == "function" then

    pcall(
        ENV.CAFEINA_WEAPON_LAB.Shutdown
    )
end


local Runtime = {}

ENV.CAFEINA_WEAPON_LAB =
    Runtime


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    -- Recarga
    NoReload = true,

    -- Animações
    RemoveAnimations = true,

    -- Rajada
    BurstEnabled = true,

    ShotsPerBurst = 5,

    -- Tempo entre cada tiro da rajada.
    BurstInterval = 0.055,

    -- Tempo entre disparos/rajadas enquanto segura FIRE.
    HoldInterval = 0.015,

    -- Limites do menu
    MaxBurst = 50,

    MinBurstInterval = 0.01,

    MaxBurstInterval = 0.50
}


--==============================================================
-- STATE
--==============================================================

local STATE = {

    Closed = false,

    Minimized = false,

    Firing = false,

    BurstRunning = false,

    InternalActivation = false
}


--==============================================================
-- COLORS
--==============================================================

local COLORS = {

    BG =
        Color3.fromRGB(
            12,
            12,
            15
        ),

    PANEL =
        Color3.fromRGB(
            22,
            22,
            27
        ),

    BUTTON =
        Color3.fromRGB(
            34,
            34,
            40
        ),

    TEXT =
        Color3.fromRGB(
            245,
            245,
            248
        ),

    MUTED =
        Color3.fromRGB(
            145,
            145,
            155
        ),

    GREEN =
        Color3.fromRGB(
            48,
            220,
            88
        ),

    RED =
        Color3.fromRGB(
            255,
            48,
            58
        ),

    STROKE =
        Color3.fromRGB(
            64,
            64,
            72
        )
}


--==============================================================
-- CONNECTION MANAGEMENT
--==============================================================

local Connections = {}

local CharacterConnections = {}

local ToolConnections = {}


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

            Connection:
            Disconnect()
        end)

        List[Index] = nil
    end
end


--==============================================================
-- UI HELPERS
--==============================================================

local function AddCorner(
    Object,
    Radius
)

    local Corner =
        Instance.new("UICorner")

    Corner.CornerRadius =
        UDim.new(
            0,
            Radius or 8
        )

    Corner.Parent =
        Object

    return Corner
end


local function AddStroke(
    Object
)

    local Stroke =
        Instance.new("UIStroke")

    Stroke.Color =
        COLORS.STROKE

    Stroke.Thickness =
        1

    Stroke.Transparency =
        0.2

    Stroke.Parent =
        Object

    return Stroke
end


--==============================================================
-- CHARACTER HELPERS
--==============================================================

local function GetCharacter()

    return
        LocalPlayer.Character
end


local function GetHumanoid()

    local Character =
        GetCharacter()

    if not Character then
        return nil
    end

    return
        Character:
        FindFirstChildOfClass(
            "Humanoid"
        )
end


local function GetAnimator()

    local Humanoid =
        GetHumanoid()

    if not Humanoid then
        return nil
    end

    return
        Humanoid:
        FindFirstChildOfClass(
            "Animator"
        )
end


local function GetEquippedTool()

    local Character =
        GetCharacter()

    if not Character then
        return nil
    end


    for _, Object in ipairs(
        Character:GetChildren()
    ) do

        if Object:IsA("Tool") then

            return Object
        end
    end


    return nil
end


--==============================================================
-- ANIMATION FILTER
--==============================================================

local AnimationKeywords = {

    "reload",
    "reloading",

    "shoot",
    "shot",
    "fire",
    "firing",

    "recoil",

    "pump",
    "bolt",

    "equip",
    "unequip",

    "draw",
    "holster",

    "inspect",

    "weapon",
    "gun"
}


local function TextHasWeaponKeyword(
    Text
)

    Text =
        string.lower(
            tostring(
                Text or ""
            )
        )


    for _, Keyword in ipairs(
        AnimationKeywords
    ) do

        if string.find(
            Text,
            Keyword,
            1,
            true
        ) then

            return true
        end
    end


    return false
end


local function IsWeaponAnimation(
    Track
)

    if not Track then
        return false
    end


    local Animation =
        Track.Animation


    if Animation then

        if TextHasWeaponKeyword(
            Animation.Name
        ) then

            return true
        end
    end


    return
        TextHasWeaponKeyword(
            Track.Name
        )
end


local function StopWeaponAnimations()

    if not CONFIG.RemoveAnimations
    and not CONFIG.NoReload then

        return
    end


    local Animator =
        GetAnimator()

    if not Animator then
        return
    end


    for _, Track in ipairs(
        Animator:
        GetPlayingAnimationTracks()
    ) do

        if IsWeaponAnimation(
            Track
        ) then

            pcall(function()

                Track:
                Stop(0)
            end)
        end
    end
end


--==============================================================
-- ANIMATION WATCHER
--==============================================================

local AnimationPlayedConnection =
    nil


local function DisconnectAnimationWatcher()

    if AnimationPlayedConnection then

        pcall(function()

            AnimationPlayedConnection:
            Disconnect()
        end)

        AnimationPlayedConnection =
            nil
    end
end


local function AttachAnimationWatcher()

    DisconnectAnimationWatcher()


    local Humanoid =
        GetHumanoid()

    if not Humanoid then
        return
    end


    local Animator =
        Humanoid:
        FindFirstChildOfClass(
            "Animator"
        )


    if not Animator then

        Animator =
            Humanoid:
            WaitForChild(
                "Animator",
                5
            )
    end


    if not Animator then
        return
    end


    AnimationPlayedConnection =
        Animator.AnimationPlayed:
        Connect(function(Track)

            if STATE.Closed then
                return
            end


            if not CONFIG.RemoveAnimations
            and not CONFIG.NoReload then

                return
            end


            if IsWeaponAnimation(
                Track
            ) then

                task.defer(function()

                    if STATE.Closed then
                        return
                    end

                    pcall(function()

                        Track:
                        Stop(0)
                    end)
                end)
            end
        end)
end


--==============================================================
-- NO RELOAD
--==============================================================

local ReloadNames = {

    reloadtime = true,

    reloadduration = true,

    reloadspeed = true,

    reloadcooldown = true,

    reloadwait = true,

    reload_delay = true,

    reload_time = true,

    reload_duration = true
}


-- Valores originais para restaurar.
local OriginalAttributes = {}

local OriginalValues = {}


local function IsReloadName(
    Name
)

    Name =
        string.lower(
            tostring(
                Name or ""
            )
        )


    if ReloadNames[Name] then
        return true
    end


    if string.find(
        Name,
        "reload",
        1,
        true
    ) then

        if string.find(
            Name,
            "time",
            1,
            true
        )

        or string.find(
            Name,
            "duration",
            1,
            true
        )

        or string.find(
            Name,
            "delay",
            1,
            true
        )

        or string.find(
            Name,
            "cooldown",
            1,
            true
        ) then

            return true
        end
    end


    return false
end


local function PatchAttributes(
    Object
)

    if not Object
    or not Object.Parent then

        return
    end


    local Success,
        Attributes =
        pcall(function()

            return
                Object:
                GetAttributes()
        end)


    if not Success then
        return
    end


    for Name,
        Value in pairs(
            Attributes
        ) do

        if IsReloadName(Name)
        and typeof(Value) == "number" then

            OriginalAttributes[Object] =
                OriginalAttributes[Object]
                or {}


            if OriginalAttributes[Object][Name] ==
                nil then

                OriginalAttributes[Object][Name] =
                    Value
            end


            pcall(function()

                Object:
                SetAttribute(
                    Name,
                    0
                )
            end)
        end
    end
end


local function PatchValueObject(
    Object
)

    if not Object then
        return
    end


    if not (
        Object:IsA("NumberValue")
        or
        Object:IsA("IntValue")
    ) then

        return
    end


    if not IsReloadName(
        Object.Name
    ) then

        return
    end


    if OriginalValues[Object] ==
        nil then

        OriginalValues[Object] =
            Object.Value
    end


    pcall(function()

        Object.Value =
            0
    end)
end


local function PatchReloadOnTool(
    Tool
)

    if not CONFIG.NoReload
    or not Tool then

        return
    end


    PatchAttributes(Tool)

    PatchValueObject(Tool)


    for _, Object in ipairs(
        Tool:GetDescendants()
    ) do

        PatchAttributes(Object)

        PatchValueObject(Object)
    end


    StopWeaponAnimations()
end


local function RestoreReloadValues()

    for Object,
        Attributes in pairs(
            OriginalAttributes
        ) do

        if typeof(Object) ==
            "Instance"
        and Object.Parent then

            for Name,
                Value in pairs(
                    Attributes
                ) do

                pcall(function()

                    Object:
                    SetAttribute(
                        Name,
                        Value
                    )
                end)
            end
        end
    end


    table.clear(
        OriginalAttributes
    )


    for Object,
        Value in pairs(
            OriginalValues
        ) do

        if typeof(Object) ==
            "Instance"
        and Object.Parent then

            pcall(function()

                Object.Value =
                    Value
            end)
        end
    end


    table.clear(
        OriginalValues
    )
end


local function ApplyNoReload()

    if not CONFIG.NoReload then
        return
    end


    local Tool =
        GetEquippedTool()


    if Tool then

        PatchReloadOnTool(
            Tool
        )
    end
end


--==============================================================
-- TOOL ACTIVATION
--==============================================================

local function ActivateToolOnce(
    ExpectedTool
)

    if STATE.Closed then
        return false
    end


    local Tool =
        GetEquippedTool()


    if not Tool then
        return false
    end


    if ExpectedTool
    and Tool ~= ExpectedTool then

        return false
    end


    if CONFIG.NoReload then

        PatchReloadOnTool(
            Tool
        )
    end


    STATE.InternalActivation =
        true


    local Success =
        pcall(function()

            Tool:
            Activate()
        end)


    STATE.InternalActivation =
        false


    if CONFIG.RemoveAnimations
    or CONFIG.NoReload then

        task.defer(
            StopWeaponAnimations
        )
    end


    return Success
end


--==============================================================
-- BURST
--==============================================================

local BurstToken = 0


local function CancelBurst()

    BurstToken += 1

    STATE.BurstRunning =
        false
end


local function FireBurst(
    ExpectedTool
)

    if STATE.Closed
    or STATE.BurstRunning then

        return false
    end


    local Tool =
        ExpectedTool
        or GetEquippedTool()


    if not Tool then
        return false
    end


    STATE.BurstRunning =
        true


    BurstToken += 1


    local MyToken =
        BurstToken


    task.spawn(function()

        local Shots =
            math.clamp(

                math.floor(
                    CONFIG.ShotsPerBurst
                ),

                1,

                CONFIG.MaxBurst
            )


        for Index =
            1,
            Shots do

            if STATE.Closed
            or MyToken ~= BurstToken then

                break
            end


            local CurrentTool =
                GetEquippedTool()


            if CurrentTool ~= Tool then
                break
            end


            ActivateToolOnce(
                Tool
            )


            if Index < Shots then

                task.wait(

                    math.max(

                        CONFIG.BurstInterval,

                        CONFIG.MinBurstInterval
                    )
                )
            end
        end


        if MyToken ==
            BurstToken then

            STATE.BurstRunning =
                false
        end
    end)


    return true
end


--==============================================================
-- CONTINUOUS FIRE
--==============================================================

local FireLoopToken = 0


local function StopContinuousFire()

    STATE.Firing =
        false


    FireLoopToken += 1


    CancelBurst()


    local Tool =
        GetEquippedTool()


    if Tool then

        pcall(function()

            Tool:
            Deactivate()
        end)
    end
end


local function StartContinuousFire()

    if STATE.Closed
    or STATE.Firing then

        return
    end


    local InitialTool =
        GetEquippedTool()


    if not InitialTool then
        return
    end


    STATE.Firing =
        true


    FireLoopToken += 1


    local MyToken =
        FireLoopToken


    task.spawn(function()

        while
            not STATE.Closed

            and
            STATE.Firing

            and
            MyToken ==
            FireLoopToken
        do

            local Tool =
                GetEquippedTool()


            if Tool ~=
                InitialTool then

                break
            end


            if CONFIG.NoReload then

                PatchReloadOnTool(
                    Tool
                )
            end


            if CONFIG.BurstEnabled then

                FireBurst(
                    Tool
                )


                while
                    STATE.BurstRunning

                    and
                    STATE.Firing

                    and
                    not STATE.Closed

                    and
                    MyToken ==
                    FireLoopToken
                do

                    task.wait()
                end

            else

                ActivateToolOnce(
                    Tool
                )
            end


            if STATE.Closed
            or not STATE.Firing
            or MyToken ~=
                FireLoopToken then

                break
            end


            task.wait(

                math.max(
                    CONFIG.HoldInterval,
                    0.01
                )
            )
        end


        if MyToken ==
            FireLoopToken then

            STATE.Firing =
                false
        end
    end)
end


--==============================================================
-- OLD GUI CLEAN
--==============================================================

local OldGui =
    PlayerGui:
    FindFirstChild(
        "CafeinaWeaponLabV2"
    )


if OldGui then

    OldGui:
    Destroy()
end


--==============================================================
-- GUI
--==============================================================

local Gui =
    Instance.new("ScreenGui")


Gui.Name =
    "CafeinaWeaponLabV2"


Gui.ResetOnSpawn =
    false


Gui.DisplayOrder =
    999


Gui.IgnoreGuiInset =
    false


Gui.Parent =
    PlayerGui


--==============================================================
-- MAIN
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
        0.17,
        0
    )


Main.Size =
    UDim2.fromOffset(
        274,
        316
    )


Main.BackgroundColor3 =
    COLORS.BG


Main.BorderSizePixel =
    0


Main.Parent =
    Gui


AddCorner(
    Main,
    12
)

AddStroke(Main)


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
        43
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
        -85,
        1,
        0
    )


Title.BackgroundTransparency =
    1


Title.Text =
    "CAFEÍNA • WEAPON LAB"


Title.TextColor3 =
    COLORS.TEXT


Title.Font =
    Enum.Font.GothamBold


Title.TextSize =
    12


Title.TextXAlignment =
    Enum.TextXAlignment.Left


Title.Parent =
    Header


--==============================================================
-- HEADER BUTTONS
--==============================================================

local Minimize =
    Instance.new("TextButton")


Minimize.Size =
    UDim2.fromOffset(
        28,
        28
    )


Minimize.Position =
    UDim2.new(
        1,
        -68,
        0,
        7
    )


Minimize.BackgroundColor3 =
    COLORS.BUTTON


Minimize.BorderSizePixel =
    0


Minimize.Text =
    "—"


Minimize.TextColor3 =
    COLORS.TEXT


Minimize.Font =
    Enum.Font.GothamBold


Minimize.TextSize =
    13


Minimize.Parent =
    Header


AddCorner(
    Minimize,
    6
)


local Close =
    Instance.new("TextButton")


Close.Size =
    UDim2.fromOffset(
        28,
        28
    )


Close.Position =
    UDim2.new(
        1,
        -34,
        0,
        7
    )


Close.BackgroundColor3 =
    COLORS.RED


Close.BorderSizePixel =
    0


Close.Text =
    "×"


Close.TextColor3 =
    COLORS.TEXT


Close.Font =
    Enum.Font.GothamBold


Close.TextSize =
    15


Close.Parent =
    Header


AddCorner(
    Close,
    6
)


--==============================================================
-- BODY
--==============================================================

local Body =
    Instance.new("Frame")


Body.Position =
    UDim2.fromOffset(
        7,
        46
    )


Body.Size =
    UDim2.new(
        1,
        -14,
        1,
        -53
    )


Body.BackgroundTransparency =
    1


Body.Parent =
    Main


local Layout =
    Instance.new("UIListLayout")


Layout.Padding =
    UDim.new(
        0,
        6
    )


Layout.SortOrder =
    Enum.SortOrder.LayoutOrder


Layout.Parent =
    Body


--==============================================================
-- TOGGLE CREATOR
--==============================================================

local function CreateToggle(
    Order,
    Text,
    Initial,
    Callback
)

    local Enabled =
        Initial == true


    local Row =
        Instance.new("TextButton")


    Row.LayoutOrder =
        Order


    Row.Size =
        UDim2.new(
            1,
            0,
            0,
            40
        )


    Row.BackgroundColor3 =
        COLORS.PANEL


    Row.BorderSizePixel =
        0


    Row.Text =
        ""


    Row.Parent =
        Body


    AddCorner(
        Row,
        8
    )


    local Label =
        Instance.new("TextLabel")


    Label.Position =
        UDim2.fromOffset(
            11,
            0
        )


    Label.Size =
        UDim2.new(
            1,
            -73,
            1,
            0
        )


    Label.BackgroundTransparency =
        1


    Label.Text =
        Text


    Label.TextColor3 =
        COLORS.TEXT


    Label.Font =
        Enum.Font.GothamMedium


    Label.TextSize =
        11


    Label.TextXAlignment =
        Enum.TextXAlignment.Left


    Label.Parent =
        Row


    local Status =
        Instance.new("TextLabel")


    Status.Position =
        UDim2.new(
            1,
            -57,
            0,
            0
        )


    Status.Size =
        UDim2.fromOffset(
            48,
            40
        )


    Status.BackgroundTransparency =
        1


    Status.Font =
        Enum.Font.GothamBold


    Status.TextSize =
        10


    Status.Parent =
        Row


    local function Refresh()

        Status.Text =
            Enabled
            and "ON"
            or "OFF"


        Status.TextColor3 =
            Enabled
            and COLORS.GREEN
            or COLORS.MUTED
    end


    Connect(
        Row.Activated,

        function()

            Enabled =
                not Enabled


            Refresh()


            if Callback then

                Callback(
                    Enabled
                )
            end
        end
    )


    Refresh()


    return {

        Set =
            function(Value)

                Enabled =
                    Value == true

                Refresh()
            end,

        Get =
            function()

                return Enabled
            end
    }
end


--==============================================================
-- ADJUSTER
--==============================================================

local function CreateAdjuster(
    Order,
    Text,
    Getter,
    MinusCallback,
    PlusCallback
)

    local Row =
        Instance.new("Frame")


    Row.LayoutOrder =
        Order


    Row.Size =
        UDim2.new(
            1,
            0,
            0,
            42
        )


    Row.BackgroundColor3 =
        COLORS.PANEL


    Row.BorderSizePixel =
        0


    Row.Parent =
        Body


    AddCorner(
        Row,
        8
    )


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
            -125,
            1,
            0
        )


    Label.BackgroundTransparency =
        1


    Label.Text =
        Text


    Label.TextColor3 =
        COLORS.TEXT


    Label.Font =
        Enum.Font.GothamMedium


    Label.TextSize =
        10


    Label.TextXAlignment =
        Enum.TextXAlignment.Left


    Label.Parent =
        Row


    local Minus =
        Instance.new("TextButton")


    Minus.Size =
        UDim2.fromOffset(
            31,
            30
        )


    Minus.Position =
        UDim2.new(
            1,
            -108,
            0,
            6
        )


    Minus.BackgroundColor3 =
        COLORS.BUTTON


    Minus.BorderSizePixel =
        0


    Minus.Text =
        "−"


    Minus.TextColor3 =
        COLORS.TEXT


    Minus.Font =
        Enum.Font.GothamBold


    Minus.TextSize =
        14


    Minus.Parent =
        Row


    AddCorner(
        Minus,
        6
    )


    local Value =
        Instance.new("TextLabel")


    Value.Position =
        UDim2.new(
            1,
            -74,
            0,
            0
        )


    Value.Size =
        UDim2.fromOffset(
            40,
            42
        )


    Value.BackgroundTransparency =
        1


    Value.TextColor3 =
        COLORS.GREEN


    Value.Font =
        Enum.Font.GothamBold


    Value.TextSize =
        10


    Value.Parent =
        Row


    local Plus =
        Instance.new("TextButton")


    Plus.Size =
        UDim2.fromOffset(
            31,
            30
        )


    Plus.Position =
        UDim2.new(
            1,
            -33,
            0,
            6
        )


    Plus.BackgroundColor3 =
        COLORS.BUTTON


    Plus.BorderSizePixel =
        0


    Plus.Text =
        "+"


    Plus.TextColor3 =
        COLORS.TEXT


    Plus.Font =
        Enum.Font.GothamBold


    Plus.TextSize =
        14


    Plus.Parent =
        Row


    AddCorner(
        Plus,
        6
    )


    local function Refresh()

        Value.Text =
            tostring(
                Getter()
            )
    end


    Connect(
        Minus.Activated,

        function()

            MinusCallback()

            Refresh()
        end
    )


    Connect(
        Plus.Activated,

        function()

            PlusCallback()

            Refresh()
        end
    )


    Refresh()
end


--==============================================================
-- OPTIONS
--==============================================================

CreateToggle(

    1,

    "SEM RECARGA",

    CONFIG.NoReload,

    function(Value)

        CONFIG.NoReload =
            Value


        if Value then

            ApplyNoReload()

            StopWeaponAnimations()

        else

            RestoreReloadValues()
        end
    end
)


CreateToggle(

    2,

    "SEM ANIMAÇÕES",

    CONFIG.RemoveAnimations,

    function(Value)

        CONFIG.RemoveAnimations =
            Value


        if Value then

            StopWeaponAnimations()
        end
    end
)


CreateToggle(

    3,

    "RAJADA",

    CONFIG.BurstEnabled,

    function(Value)

        CONFIG.BurstEnabled =
            Value


        if not Value then

            CancelBurst()
        end
    end
)


CreateAdjuster(

    4,

    "TIROS / RAJADA",

    function()

        return
            CONFIG.ShotsPerBurst
    end,

    function()

        CONFIG.ShotsPerBurst =
            math.max(

                1,

                CONFIG.ShotsPerBurst -
                1
            )
    end,

    function()

        CONFIG.ShotsPerBurst =
            math.min(

                CONFIG.MaxBurst,

                CONFIG.ShotsPerBurst +
                1
            )
    end
)


CreateAdjuster(

    5,

    "INTERVALO ms",

    function()

        return
            math.floor(
                CONFIG.BurstInterval *
                1000
            )
    end,

    function()

        CONFIG.BurstInterval =
            math.max(

                CONFIG.MinBurstInterval,

                CONFIG.BurstInterval -
                0.01
            )
    end,

    function()

        CONFIG.BurstInterval =
            math.min(

                CONFIG.MaxBurstInterval,

                CONFIG.BurstInterval +
                0.01
            )
    end
)


--==============================================================
-- FIRE BUTTON
--==============================================================

local Fire =
    Instance.new("TextButton")


Fire.AnchorPoint =
    Vector2.new(
        1,
        1
    )


Fire.Position =
    UDim2.new(
        1,
        -20,
        1,
        -85
    )


Fire.Size =
    UDim2.fromOffset(
        76,
        76
    )


Fire.BackgroundColor3 =
    COLORS.RED


Fire.BackgroundTransparency =
    0.10


Fire.BorderSizePixel =
    0


Fire.Text =
    "FIRE"


Fire.TextColor3 =
    COLORS.TEXT


Fire.Font =
    Enum.Font.GothamBlack


Fire.TextSize =
    13


Fire.Parent =
    Gui


AddCorner(
    Fire,
    38
)

AddStroke(Fire)


--==============================================================
-- FIRE TOUCH TRACKING
--==============================================================

local ActiveFireInput =
    nil


Connect(
    Fire.InputBegan,

    function(Input)

        if STATE.Closed then
            return
        end


        if Input.UserInputType ~=
            Enum.UserInputType.Touch

        and Input.UserInputType ~=
            Enum.UserInputType.MouseButton1 then

            return
        end


        if ActiveFireInput then
            return
        end


        ActiveFireInput =
            Input


        Fire.BackgroundTransparency =
            0


        StartContinuousFire()
    end
)


local function ReleaseFire(
    Input
)

    if not ActiveFireInput then
        return
    end


    if Input
    and Input ~= ActiveFireInput then

        return
    end


    ActiveFireInput =
        nil


    Fire.BackgroundTransparency =
        0.10


    StopContinuousFire()
end


Connect(
    Fire.InputEnded,

    function(Input)

        ReleaseFire(Input)
    end
)


-- Fallback importante para mobile:
-- se o dedo terminar fora do botão.
Connect(
    UserInputService.InputEnded,

    function(Input)

        if ActiveFireInput
        and Input ==
            ActiveFireInput then

            ReleaseFire(Input)
        end
    end
)


--==============================================================
-- TOOL WATCHER
--==============================================================

local CurrentTool =
    nil


local function DisconnectToolWatcher()

    DisconnectList(
        ToolConnections
    )


    CurrentTool =
        nil
end


local function AttachTool(
    Tool
)

    if STATE.Closed then
        return
    end


    if Tool ==
        CurrentTool then

        return
    end


    DisconnectToolWatcher()


    if not Tool
    or not Tool:IsA("Tool") then

        return
    end


    CurrentTool =
        Tool


    if CONFIG.NoReload then

        PatchReloadOnTool(
            Tool
        )
    end


    -- Se a arma criar valores de reload depois do equip,
    -- aplica o patch também.
    Connect(

        Tool.DescendantAdded,

        function(Object)

            if STATE.Closed
            or not CONFIG.NoReload then

                return
            end


            task.defer(function()

                if STATE.Closed
                or not CONFIG.NoReload then

                    return
                end


                PatchAttributes(
                    Object
                )


                PatchValueObject(
                    Object
                )
            end)
        end,

        ToolConnections
    )


    Connect(

        Tool.Activated,

        function()

            if STATE.Closed
            or STATE.InternalActivation then

                return
            end


            if CONFIG.NoReload then

                PatchReloadOnTool(
                    Tool
                )
            end


            if CONFIG.RemoveAnimations
            or CONFIG.NoReload then

                task.defer(
                    StopWeaponAnimations
                )
            end


            -- Quando a ativação veio do botão original da arma,
            -- acrescenta a rajada.
            if CONFIG.BurstEnabled
            and not STATE.BurstRunning
            and not STATE.Firing then

                FireBurst(
                    Tool
                )
            end
        end,

        ToolConnections
    )
end


local function RefreshTool()

    local Tool =
        GetEquippedTool()


    if Tool then

        AttachTool(
            Tool
        )

    else

        DisconnectToolWatcher()
    end
end


--==============================================================
-- CHARACTER WATCHER
--==============================================================

local function AttachCharacter(
    Character
)

    DisconnectList(
        CharacterConnections
    )


    StopContinuousFire()

    DisconnectToolWatcher()

    AttachAnimationWatcher()


    Connect(

        Character.ChildAdded,

        function(Object)

            if Object:IsA("Tool") then

                task.defer(function()

                    if STATE.Closed then
                        return
                    end


                    AttachTool(
                        Object
                    )
                end)
            end
        end,

        CharacterConnections
    )


    Connect(

        Character.ChildRemoved,

        function(Object)

            if Object ==
                CurrentTool then

                StopContinuousFire()

                task.defer(
                    RefreshTool
                )
            end
        end,

        CharacterConnections
    )


    task.defer(
        RefreshTool
    )
end


if LocalPlayer.Character then

    AttachCharacter(
        LocalPlayer.Character
    )
end


Connect(
    LocalPlayer.CharacterAdded,

    function(Character)

        StopContinuousFire()

        DisconnectAnimationWatcher()

        task.wait(0.15)


        if STATE.Closed then
            return
        end


        AttachCharacter(
            Character
        )
    end
)


--==============================================================
-- PERIODIC RELOAD PATCH
-- Mantém atributos locais em zero caso o controlador tente
-- restaurá-los durante a partida.
--==============================================================

local ReloadPatchAccumulator = 0


Connect(
    RunService.Heartbeat,

    function(Delta)

        if STATE.Closed
        or not CONFIG.NoReload then

            return
        end


        ReloadPatchAccumulator +=
            Delta


        if ReloadPatchAccumulator <
            0.15 then

            return
        end


        ReloadPatchAccumulator =
            0


        ApplyNoReload()
    end
)


--==============================================================
-- DRAG
--==============================================================

local function MakeDraggable(
    Handle,
    Object
)

    local Dragging =
        false

    local DragInput =
        nil

    local StartPointer =
        nil

    local StartPosition =
        nil


    Connect(
        Handle.InputBegan,

        function(Input)

            if Input.UserInputType ==
                Enum.UserInputType.Touch

            or Input.UserInputType ==
                Enum.UserInputType.MouseButton1 then

                Dragging =
                    true


                StartPointer =
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
            or not StartPointer
            or not StartPosition then

                return
            end


            local Delta =
                Input.Position -
                StartPointer


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


--==============================================================
-- RESTORE
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
    COLORS.BG


Restore.BorderSizePixel =
    0


Restore.Text =
    "W"


Restore.TextColor3 =
    COLORS.RED


Restore.Font =
    Enum.Font.GothamBlack


Restore.TextSize =
    17


Restore.Visible =
    false


Restore.Parent =
    Gui


AddCorner(
    Restore,
    12
)

AddStroke(Restore)


MakeDraggable(
    Restore,
    Restore
)


local function MinimizeMenu()

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


local function RestoreMenu()

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
    MinimizeMenu
)


Connect(
    Restore.Activated,
    RestoreMenu
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


    CONFIG.NoReload =
        false


    CONFIG.RemoveAnimations =
        false


    CONFIG.BurstEnabled =
        false


    ReleaseFire()


    StopContinuousFire()

    CancelBurst()


    DisconnectAnimationWatcher()

    DisconnectToolWatcher()


    DisconnectList(
        CharacterConnections
    )


    RestoreReloadValues()


    DisconnectList(
        Connections
    )


    if Gui then

        pcall(function()

            Gui:
            Destroy()
        end)
    end


    if ENV.CAFEINA_WEAPON_LAB ==
        Runtime then

        ENV.CAFEINA_WEAPON_LAB =
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
-- INITIAL PATCH
--==============================================================

task.defer(function()

    if STATE.Closed then
        return
    end


    RefreshTool()


    if CONFIG.NoReload then

        ApplyNoReload()
    end


    if CONFIG.RemoveAnimations then

        StopWeaponAnimations()
    end
end)


print(
    "CAFEÍNA • WEAPON LAB V2 • carregado"
)
