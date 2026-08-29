--[[
=====================================================================
 CAFEÍNA • WEAPON LAB V5.1
 EXECUTOR ONLY • WEAPON CORE

 ATUALIZAÇÃO:
 • Remove restos visuais de versões antigas
 • Remove possíveis linhas/FOV/tracers antigos
 • Sem teleporte
 • Sem lista de inimigos
 • Sem hitbox
 • Sem head-lock
 • Munição virtual contínua
 • Nunca deixa _ammo chegar perto de zero
 • Sem recarga
 • Semi -> Auto
 • Segurar botão normal = tiro contínuo
 • Sem recoil
 • Sem animações de arma
 • Reinjeção segura
 • Mobile
=====================================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local RunService =
    game:GetService("RunService")

local UserInputService =
    game:GetService("UserInputService")

local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    warn("[CAFEÍNA] LocalPlayer indisponível")
    return
end

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui",
        15
    )

if not PlayerGui then
    warn("[CAFEÍNA] PlayerGui indisponível")
    return
end

--==============================================================
-- ENV
--==============================================================

local ENV = _G

if type(getgenv) == "function" then

    local ok, result =
        pcall(getgenv)

    if ok and type(result) == "table" then
        ENV = result
    end
end

--==============================================================
-- LIMPEZA DE RUNTIMES ANTIGOS
--==============================================================

local OLD_RUNTIME_NAMES = {

    "CAFEINA_WEAPON_LAB",
    "CAFEINA_WEAPON_LAB_V3",
    "CAFEINA_WEAPON_LAB_V4",
    "CAFEINA_WEAPON_LAB_V5",

    "CafeinaMobileRuntime",
    "CAFEINA_RUNTIME",
    "CAFEINA_AIMBOT",
    "CAFEINA_ESP"
}

for _, runtimeName in ipairs(
    OLD_RUNTIME_NAMES
) do

    local runtime =
        ENV[runtimeName]

    if runtime
    and type(runtime) == "table"
    and type(runtime.Shutdown) == "function" then

        pcall(
            runtime.Shutdown
        )
    end
end

--==============================================================
-- LIMPEZA VISUAL ANTIGA
--==============================================================

local OLD_GUI_NAMES = {

    "CafeinaWeaponLab",
    "CafeinaWeaponLabV3",
    "CafeinaWeaponLabV4",
    "CafeinaWeaponLabV5",
    "CafeinaWeaponLabV51",

    "CafeinaTargetMenu",
    "CafeinaTeleportMenu",

    "CafeinaESP",
    "CafeinaFOV",
    "CafeinaAimbot",
    "CafeinaAim",
    "CafeinaTracer",

    "CafeinaMobile",
    "CafeinaV1",
    "CafeinaMenu"
}

for _, guiName in ipairs(
    OLD_GUI_NAMES
) do

    local object =
        PlayerGui:
        FindFirstChild(guiName)

    if object then

        pcall(function()
            object:Destroy()
        end)
    end
end

--==============================================================
-- LIMPEZA POR PREFIXO CAFEINA
-- somente ScreenGui/GuiObject suspeitos
--==============================================================

for _, object in ipairs(
    PlayerGui:GetChildren()
) do

    local lower =
        string.lower(
            object.Name
        )

    if
        string.find(
            lower,
            "cafeina",
            1,
            true
        )
        and
        (
            object:IsA("ScreenGui")
            or
            object:IsA("Frame")
        )
    then

        pcall(function()
            object:Destroy()
        end)
    end
end

--==============================================================
-- REMOVE BINDINGS ANTIGOS
--==============================================================

local OLD_RENDER_BINDS = {

    "CafeinaFOV",
    "CafeinaESP",
    "CafeinaAimbot",

    "CafeinaTargetHead",
    "CAFEINA_WEAPON_HEAD_LOCK_V4",

    "CafeinaTracer",
    "CafeinaTeleport"
}

for _, bindName in ipairs(
    OLD_RENDER_BINDS
) do

    pcall(function()

        RunService:
            UnbindFromRenderStep(
                bindName
            )
    end)
end

--==============================================================
-- NOVO RUNTIME
--==============================================================

local RUNTIME_KEY =
    "CAFEINA_WEAPON_LAB_V51"

if ENV[RUNTIME_KEY]
and type(
    ENV[RUNTIME_KEY].Shutdown
) == "function" then

    pcall(
        ENV[RUNTIME_KEY].Shutdown
    )
end

local Runtime = {}

ENV[RUNTIME_KEY] =
    Runtime

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    InfiniteAmmo = true,

    VirtualAmmo = 999999,

    AmmoSafetyThreshold = 500000,

    NoReload = true,

    ContinuousFire = true,

    ForceAuto = true,

    DesiredRPM = 1200,

    MinimumLoopInterval = 0.025,

    MaximumLoopInterval = 0.20,

    BurstEnabled = false,

    BurstShots = 5,

    BurstInterval = 0.04,

    MaxBurst = 50,

    NoRecoil = true,

    NoAnimations = true,

    WeaponWatchInterval = 0.06
}

--==============================================================
-- STATE
--==============================================================

local STATE = {

    Closed = false,

    Minimized = false,

    Firing = false,

    FireToken = 0,

    InternalActivation = false,

    CurrentTool = nil,

    BlasterController = nil,

    BlasterHooked = false,

    HookStatus = "INICIANDO"
}

--==============================================================
-- CONNECTIONS
--==============================================================

local Connections = {}

local ToolConnections = {}

local CharacterConnections = {}

local function Connect(
    signal,
    callback,
    list
)

    local connection =
        signal:Connect(
            callback
        )

    table.insert(
        list or Connections,
        connection
    )

    return connection
end

local function DisconnectList(
    list
)

    for i = #list, 1, -1 do

        local connection =
            list[i]

        if connection then

            pcall(function()
                connection:Disconnect()
            end)
        end

        list[i] = nil
    end
end

--==============================================================
-- CHARACTER
--==============================================================

local function GetCharacter()

    return
        LocalPlayer.Character
end

local function GetHumanoid()

    local character =
        GetCharacter()

    return
        character
        and character:
        FindFirstChildOfClass(
            "Humanoid"
        )
end

local function GetAnimator()

    local humanoid =
        GetHumanoid()

    return
        humanoid
        and humanoid:
        FindFirstChildOfClass(
            "Animator"
        )
end

local function GetEquippedTool()

    local character =
        GetCharacter()

    if not character then
        return nil
    end

    for _, object in ipairs(
        character:GetChildren()
    ) do

        if object:IsA("Tool") then
            return object
        end
    end

    return nil
end

--==============================================================
-- DETECTA ARMA BLASTER
--==============================================================

local function IsBlasterTool(
    tool
)

    if not tool
    or not tool:IsA("Tool") then
        return false
    end

    if tool:GetAttribute(
        "projectileType"
    ) ~= nil then
        return true
    end

    if tool:GetAttribute(
        "magazineSize"
    ) ~= nil then
        return true
    end

    if tool:GetAttribute(
        "rateOfFire"
    ) ~= nil then
        return true
    end

    local scripts =
        tool:
        FindFirstChild(
            "Scripts"
        )

    if scripts
    and scripts:
        FindFirstChild(
            "Blaster"
        ) then

        return true
    end

    return false
end

--==============================================================
-- ORIGINAL VALUES
--==============================================================

local OriginalAttributes = {}

local function SaveAttribute(
    object,
    name
)

    if not object then
        return
    end

    local current =
        object:
        GetAttribute(name)

    if current == nil then
        return
    end

    local map =
        OriginalAttributes[object]

    if not map then

        map = {}

        OriginalAttributes[object] =
            map
    end

    if map[name] == nil then
        map[name] =
            current
    end
end

local function SetAttributeSafe(
    object,
    name,
    value
)

    if not object
    or not object.Parent then
        return false
    end

    SaveAttribute(
        object,
        name
    )

    return pcall(function()

        object:
            SetAttribute(
                name,
                value
            )
    end)
end

local function RestoreAttributes()

    for object, values in pairs(
        OriginalAttributes
    ) do

        if typeof(object) ==
            "Instance"
        and object.Parent then

            for name, value in pairs(
                values
            ) do

                pcall(function()

                    object:
                        SetAttribute(
                            name,
                            value
                        )
                end)
            end
        end
    end

    table.clear(
        OriginalAttributes
    )
end

--==============================================================
-- AMMO
--==============================================================

local function ForceAmmo(
    tool
)

    if not CONFIG.InfiniteAmmo
    or not IsBlasterTool(tool) then
        return
    end

    local ammo =
        tool:
        GetAttribute(
            "_ammo"
        )

    if typeof(ammo) ==
        "number" then

        if ammo <
            CONFIG.AmmoSafetyThreshold then

            SetAttributeSafe(
                tool,
                "_ammo",
                CONFIG.VirtualAmmo
            )
        end
    end

    if tool:GetAttribute(
        "_reloading"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "_reloading",
            false
        )
    end
end

--==============================================================
-- NO RELOAD
--==============================================================

local function ForceNoReload(
    tool
)

    if not CONFIG.NoReload
    or not IsBlasterTool(tool) then
        return
    end

    if tool:GetAttribute(
        "reloadTime"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "reloadTime",
            0
        )
    end

    if tool:GetAttribute(
        "reloadTimePerRound"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "reloadTimePerRound",
            0
        )
    end

    if tool:GetAttribute(
        "_reloading"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "_reloading",
            false
        )
    end
end

--==============================================================
-- AUTO
--==============================================================

local function ForceAuto(
    tool
)

    if not CONFIG.ForceAuto
    or not IsBlasterTool(tool) then
        return
    end

    if tool:GetAttribute(
        "fireMode"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "fireMode",
            "Auto"
        )
    end

    if tool:GetAttribute(
        "rateOfFire"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "rateOfFire",
            CONFIG.DesiredRPM
        )
    end
end

--==============================================================
-- RECOIL
--==============================================================

local function ForceNoRecoil(
    tool
)

    if not CONFIG.NoRecoil
    or not IsBlasterTool(tool) then
        return
    end

    if tool:GetAttribute(
        "recoilMin"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "recoilMin",
            Vector2.zero
        )
    end

    if tool:GetAttribute(
        "recoilMax"
    ) ~= nil then

        SetAttributeSafe(
            tool,
            "recoilMax",
            Vector2.zero
        )
    end
end

--==============================================================
-- PATCH MASTER
--==============================================================

local function PatchWeapon(
    tool
)

    if not IsBlasterTool(tool) then
        return false
    end

    ForceAmmo(tool)

    ForceNoReload(tool)

    ForceAuto(tool)

    ForceNoRecoil(tool)

    ForceAmmo(tool)

    return true
end

--==============================================================
-- ANIMAÇÕES
--==============================================================

local AnimationKeywords = {

    "reload",
    "reloading",

    "fire",
    "firing",

    "shoot",
    "shot",

    "recoil",

    "pump",
    "bolt",

    "equip",
    "unequip",

    "inspect",
    "holster"
}

local function IsWeaponAnimation(
    track
)

    if not track then
        return false
    end

    local text =
        string.lower(
            tostring(
                track.Name or ""
            )
        )

    if track.Animation then

        text =
            text
            ..
            " "
            ..
            string.lower(
                tostring(
                    track.Animation.Name or ""
                )
            )
    end

    for _, keyword in ipairs(
        AnimationKeywords
    ) do

        if string.find(
            text,
            keyword,
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function StopWeaponAnimations()

    if not CONFIG.NoAnimations then
        return
    end

    local animator =
        GetAnimator()

    if not animator then
        return
    end

    for _, track in ipairs(
        animator:
        GetPlayingAnimationTracks()
    ) do

        if IsWeaponAnimation(
            track
        ) then

            pcall(function()
                track:Stop(0)
            end)
        end
    end
end

--==============================================================
-- BLASTER CONTROLLER
--==============================================================

local OriginalControllerFunctions = {}

local function InstallBlasterController()

    local ok, controller =
        pcall(function()

            return require(
                ReplicatedStorage
                :WaitForChild(
                    "BlasterSystem",
                    5
                )
                :WaitForChild(
                    "Blaster",
                    5
                )
                :WaitForChild(
                    "Scripts",
                    5
                )
                :WaitForChild(
                    "BlasterController",
                    5
                )
            )
        end)

    if not ok
    or type(controller) ~= "table" then

        STATE.HookStatus =
            "TOOL MODE"

        return false
    end

    STATE.BlasterController =
        controller

    --==========================================================
    -- SHOOT
    --==========================================================

    if type(
        controller.shoot
    ) == "function" then

        OriginalControllerFunctions.shoot =
            controller.shoot

        controller.shoot =
            function(self, ...)

                local tool =
                    GetEquippedTool()

                if tool then
                    PatchWeapon(tool)
                end

                local results = {
                    OriginalControllerFunctions.shoot(
                        self,
                        ...
                    )
                }

                if tool then

                    ForceAmmo(tool)

                    ForceNoReload(tool)
                end

                return
                    table.unpack(
                        results
                    )
            end
    end

    --==========================================================
    -- START SHOOTING
    --==========================================================

    if type(
        controller.startShooting
    ) == "function" then

        OriginalControllerFunctions.startShooting =
            controller.startShooting

        controller.startShooting =
            function(self, ...)

                local tool =
                    GetEquippedTool()

                if tool then
                    PatchWeapon(tool)
                end

                return
                    OriginalControllerFunctions.startShooting(
                        self,
                        ...
                    )
            end
    end

    --==========================================================
    -- RELOAD
    --==========================================================

    if type(
        controller.reload
    ) == "function" then

        OriginalControllerFunctions.reload =
            controller.reload

        controller.reload =
            function(self, ...)

                if CONFIG.NoReload then

                    local tool =
                        GetEquippedTool()

                    if tool then

                        ForceAmmo(tool)

                        ForceNoReload(tool)
                    end

                    return
                end

                return
                    OriginalControllerFunctions.reload(
                        self,
                        ...
                    )
            end
    end

    --==========================================================
    -- STOP RELOAD
    --==========================================================

    if type(
        controller.stopReload
    ) == "function" then

        OriginalControllerFunctions.stopReload =
            controller.stopReload
    end

    --==========================================================
    -- RECOIL
    --==========================================================

    if type(
        controller.recoil
    ) == "function" then

        OriginalControllerFunctions.recoil =
            controller.recoil

        controller.recoil =
            function(self, ...)

                if CONFIG.NoRecoil then
                    return
                end

                return
                    OriginalControllerFunctions.recoil(
                        self,
                        ...
                    )
            end
    end

    STATE.BlasterHooked =
        true

    STATE.HookStatus =
        "BLASTER OK"

    return true
end

local function RestoreController()

    local controller =
        STATE.BlasterController

    if not controller then
        return
    end

    for name, original in pairs(
        OriginalControllerFunctions
    ) do

        pcall(function()
            controller[name] =
                original
        end)
    end

    table.clear(
        OriginalControllerFunctions
    )

    STATE.BlasterController =
        nil

    STATE.BlasterHooked =
        false
end

--==============================================================
-- FIRE INTERVAL
--==============================================================

local function GetFireInterval()

    local rpm =
        math.clamp(
            tonumber(
                CONFIG.DesiredRPM
            ) or 600,
            60,
            4000
        )

    return math.clamp(

        60 / rpm,

        CONFIG.MinimumLoopInterval,

        CONFIG.MaximumLoopInterval
    )
end

--==============================================================
-- FIRE ONCE
--==============================================================

local function FireOnce(
    expectedTool
)

    if STATE.Closed then
        return false
    end

    local tool =
        GetEquippedTool()

    if not tool
    or not IsBlasterTool(tool) then
        return false
    end

    if expectedTool
    and tool ~= expectedTool then
        return false
    end

    -- evita entrar em empty state
    PatchWeapon(tool)

    STATE.InternalActivation =
        true

    local ok =
        pcall(function()
            tool:Activate()
        end)

    STATE.InternalActivation =
        false

    ForceAmmo(tool)

    ForceNoReload(tool)

    if CONFIG.NoAnimations then

        task.defer(
            StopWeaponAnimations
        )
    end

    return ok
end

--==============================================================
-- FIRE LOOP
--==============================================================

local function StopContinuousFire()

    STATE.Firing =
        false

    STATE.FireToken += 1
end

local function StartContinuousFire(
    tool
)

    if STATE.Closed
    or STATE.Firing
    or not CONFIG.ContinuousFire
    or not tool
    or tool ~= GetEquippedTool()
    or not IsBlasterTool(tool) then

        return
    end

    STATE.Firing =
        true

    STATE.FireToken += 1

    local token =
        STATE.FireToken

    task.spawn(function()

        while
            not STATE.Closed
            and
            STATE.Firing
            and
            STATE.FireToken ==
            token
        do

            if
                GetEquippedTool()
                ~= tool
            then
                break
            end

            PatchWeapon(tool)

            if CONFIG.BurstEnabled then

                local shots =
                    math.clamp(
                        math.floor(
                            CONFIG.BurstShots
                        ),
                        1,
                        CONFIG.MaxBurst
                    )

                for shot = 1, shots do

                    if
                        STATE.Closed
                        or
                        not STATE.Firing
                        or
                        STATE.FireToken ~= token
                        or
                        GetEquippedTool() ~= tool
                    then
                        break
                    end

                    FireOnce(tool)

                    if shot < shots then

                        task.wait(
                            math.max(
                                CONFIG.BurstInterval,
                                0.01
                            )
                        )
                    end
                end

            else

                FireOnce(tool)
            end

            if
                STATE.Closed
                or
                not STATE.Firing
                or
                STATE.FireToken ~= token
            then
                break
            end

            task.wait(
                GetFireInterval()
            )
        end

        if STATE.FireToken ==
            token then

            STATE.Firing =
                false
        end
    end)
end

--==============================================================
-- TOOL WATCH
--==============================================================

local function AttachTool(
    tool
)

    if STATE.CurrentTool ==
        tool then
        return
    end

    DisconnectList(
        ToolConnections
    )

    StopContinuousFire()

    STATE.CurrentTool =
        tool

    if not tool
    or not IsBlasterTool(tool) then
        return
    end

    PatchWeapon(tool)

    --==========================================================
    -- BOTÃO ORIGINAL
    --==========================================================

    Connect(

        tool.Activated,

        function()

            if STATE.Closed
            or STATE.InternalActivation then
                return
            end

            PatchWeapon(tool)

            StopWeaponAnimations()

            if CONFIG.ContinuousFire then

                StartContinuousFire(
                    tool
                )
            end
        end,

        ToolConnections
    )

    --==========================================================
    -- SOLTOU BOTÃO
    --==========================================================

    Connect(

        tool.Deactivated,

        function()

            if STATE.InternalActivation then
                return
            end

            StopContinuousFire()
        end,

        ToolConnections
    )

    --==========================================================
    -- AMMO
    --==========================================================

    Connect(

        tool:
        GetAttributeChangedSignal(
            "_ammo"
        ),

        function()

            if STATE.Closed
            or not CONFIG.InfiniteAmmo then
                return
            end

            local ammo =
                tool:
                GetAttribute(
                    "_ammo"
                )

            if typeof(ammo) ==
                "number"
            and ammo <
                CONFIG.AmmoSafetyThreshold
            then

                ForceAmmo(tool)
            end
        end,

        ToolConnections
    )

    --==========================================================
    -- RELOADING
    --==========================================================

    Connect(

        tool:
        GetAttributeChangedSignal(
            "_reloading"
        ),

        function()

            if STATE.Closed
            or not CONFIG.NoReload then
                return
            end

            if tool:GetAttribute(
                "_reloading"
            ) == true then

                SetAttributeSafe(
                    tool,
                    "_reloading",
                    false
                )

                ForceAmmo(tool)

                local controller =
                    STATE.BlasterController

                local stopReload =
                    OriginalControllerFunctions.stopReload

                if controller
                and type(stopReload) ==
                    "function" then

                    pcall(function()

                        stopReload(
                            controller
                        )
                    end)
                end
            end
        end,

        ToolConnections
    )
end

local function RefreshTool()

    AttachTool(
        GetEquippedTool()
    )
end

--==============================================================
-- CHARACTER WATCH
--==============================================================

local function AttachCharacter(
    character
)

    DisconnectList(
        CharacterConnections
    )

    DisconnectList(
        ToolConnections
    )

    StopContinuousFire()

    STATE.CurrentTool =
        nil

    Connect(

        character.ChildAdded,

        function(child)

            if child:IsA("Tool") then

                task.defer(function()

                    if not STATE.Closed then
                        AttachTool(child)
                    end
                end)
            end
        end,

        CharacterConnections
    )

    Connect(

        character.ChildRemoved,

        function(child)

            if child ==
                STATE.CurrentTool then

                StopContinuousFire()

                STATE.CurrentTool =
                    nil

                task.defer(
                    RefreshTool
                )
            end
        end,

        CharacterConnections
    )

    local humanoid =
        character:
        FindFirstChildOfClass(
            "Humanoid"
        )

    local animator =
        humanoid
        and humanoid:
        FindFirstChildOfClass(
            "Animator"
        )

    if animator then

        Connect(

            animator.AnimationPlayed,

            function(track)

                if
                    not STATE.Closed
                    and
                    CONFIG.NoAnimations
                    and
                    IsWeaponAnimation(
                        track
                    )
                then

                    task.defer(function()

                        pcall(function()
                            track:Stop(0)
                        end)
                    end)
                end
            end,

            CharacterConnections
        )
    end

    task.defer(
        RefreshTool
    )
end

--==============================================================
-- WATCHDOG
--==============================================================

local WatchAccumulator =
    0

Connect(

    RunService.Heartbeat,

    function(dt)

        if STATE.Closed then
            return
        end

        WatchAccumulator +=
            dt

        if WatchAccumulator <
            CONFIG.WeaponWatchInterval then
            return
        end

        WatchAccumulator =
            0

        local tool =
            GetEquippedTool()

        if tool ~=
            STATE.CurrentTool then

            AttachTool(tool)
        end

        if tool
        and IsBlasterTool(tool) then

            PatchWeapon(tool)
        end

        if CONFIG.NoAnimations then

            StopWeaponAnimations()
        end
    end
)

--==============================================================
-- RESPAWN
--==============================================================

Connect(

    LocalPlayer.CharacterAdded,

    function(character)

        StopContinuousFire()

        task.wait(0.20)

        if not STATE.Closed then

            AttachCharacter(
                character
            )
        end
    end
)

--==============================================================
-- COLORS
--==============================================================

local COLORS = {

    BG =
        Color3.fromRGB(
            10,
            10,
            12
        ),

    PANEL =
        Color3.fromRGB(
            21,
            21,
            25
        ),

    PANEL2 =
        Color3.fromRGB(
            31,
            31,
            36
        ),

    TEXT =
        Color3.fromRGB(
            246,
            246,
            248
        ),

    MUTED =
        Color3.fromRGB(
            145,
            145,
            153
        ),

    RED =
        Color3.fromRGB(
            255,
            43,
            55
        ),

    GREEN =
        Color3.fromRGB(
            47,
            220,
            92
        ),

    STROKE =
        Color3.fromRGB(
            61,
            61,
            68
        )
}

local function AddCorner(
    object,
    radius
)

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(
            0,
            radius or 8
        )

    corner.Parent =
        object
end

local function AddStroke(
    object
)

    local stroke =
        Instance.new("UIStroke")

    stroke.Color =
        COLORS.STROKE

    stroke.Thickness =
        1

    stroke.Transparency =
        0.2

    stroke.Parent =
        object
end

--==============================================================
-- GUI
--==============================================================

local Gui =
    Instance.new(
        "ScreenGui"
    )

Gui.Name =
    "CafeinaWeaponLabV51"

Gui.ResetOnSpawn =
    false

Gui.DisplayOrder =
    999999

Gui.Parent =
    PlayerGui

local Main =
    Instance.new(
        "Frame"
    )

Main.AnchorPoint =
    Vector2.new(
        0.5,
        0
    )

Main.Position =
    UDim2.new(
        0.5,
        0,
        0.15,
        0
    )

Main.Size =
    UDim2.fromOffset(
        280,
        365
    )

Main.BackgroundColor3 =
    COLORS.BG

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

AddCorner(Main, 13)
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
        47
    )

Header.BackgroundTransparency =
    1

Header.Parent =
    Main

local Title =
    Instance.new("TextLabel")

Title.Position =
    UDim2.fromOffset(
        13,
        4
    )

Title.Size =
    UDim2.new(
        1,
        -90,
        0,
        22
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "CAFEÍNA • WEAPON LAB"

Title.TextColor3 =
    COLORS.TEXT

Title.Font =
    Enum.Font.GothamBlack

Title.TextSize =
    12

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Header

local Subtitle =
    Instance.new("TextLabel")

Subtitle.Position =
    UDim2.fromOffset(
        13,
        25
    )

Subtitle.Size =
    UDim2.new(
        1,
        -90,
        0,
        14
    )

Subtitle.BackgroundTransparency =
    1

Subtitle.Text =
    "V5.1 • CLEAN CORE"

Subtitle.TextColor3 =
    COLORS.MUTED

Subtitle.Font =
    Enum.Font.GothamBold

Subtitle.TextSize =
    8

Subtitle.TextXAlignment =
    Enum.TextXAlignment.Left

Subtitle.Parent =
    Header

local Minimize =
    Instance.new("TextButton")

Minimize.Size =
    UDim2.fromOffset(
        29,
        29
    )

Minimize.Position =
    UDim2.new(
        1,
        -70,
        0,
        8
    )

Minimize.BackgroundColor3 =
    COLORS.PANEL2

Minimize.BorderSizePixel =
    0

Minimize.Text =
    "—"

Minimize.TextColor3 =
    COLORS.TEXT

Minimize.Font =
    Enum.Font.GothamBold

Minimize.Parent =
    Header

AddCorner(Minimize, 7)

local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.fromOffset(
        29,
        29
    )

Close.Position =
    UDim2.new(
        1,
        -35,
        0,
        8
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

Close.Parent =
    Header

AddCorner(Close, 7)

--==============================================================
-- BODY
--==============================================================

local Body =
    Instance.new(
        "ScrollingFrame"
    )

Body.Position =
    UDim2.fromOffset(
        8,
        50
    )

Body.Size =
    UDim2.new(
        1,
        -16,
        1,
        -58
    )

Body.BackgroundTransparency =
    1

Body.BorderSizePixel =
    0

Body.ScrollBarThickness =
    3

Body.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Body.CanvasSize =
    UDim2.new()

Body.Parent =
    Main

local Layout =
    Instance.new(
        "UIListLayout"
    )

Layout.Padding =
    UDim.new(
        0,
        6
    )

Layout.Parent =
    Body

--==============================================================
-- STATUS
--==============================================================

local Status =
    Instance.new("TextLabel")

Status.Size =
    UDim2.new(
        1,
        0,
        0,
        38
    )

Status.BackgroundColor3 =
    COLORS.PANEL

Status.BorderSizePixel =
    0

Status.Text =
    "CARREGANDO..."

Status.TextColor3 =
    COLORS.MUTED

Status.Font =
    Enum.Font.GothamBold

Status.TextSize =
    9

Status.Parent =
    Body

AddCorner(Status, 8)

--==============================================================
-- TOGGLE
--==============================================================

local function CreateToggle(
    name,
    getter,
    setter
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.new(
            1,
            0,
            0,
            39
        )

    button.BackgroundColor3 =
        COLORS.PANEL

    button.BorderSizePixel =
        0

    button.Text =
        ""

    button.Parent =
        Body

    AddCorner(button, 8)

    local label =
        Instance.new(
            "TextLabel"
        )

    label.Position =
        UDim2.fromOffset(
            11,
            0
        )

    label.Size =
        UDim2.new(
            1,
            -65,
            1,
            0
        )

    label.BackgroundTransparency =
        1

    label.Text =
        name

    label.TextColor3 =
        COLORS.TEXT

    label.Font =
        Enum.Font.GothamMedium

    label.TextSize =
        10

    label.TextXAlignment =
        Enum.TextXAlignment.Left

    label.Parent =
        button

    local state =
        Instance.new(
            "TextLabel"
        )

    state.Position =
        UDim2.new(
            1,
            -55,
            0,
            0
        )

    state.Size =
        UDim2.fromOffset(
            45,
            39
        )

    state.BackgroundTransparency =
        1

    state.Font =
        Enum.Font.GothamBold

    state.TextSize =
        9

    state.Parent =
        button

    local function Refresh()

        local enabled =
            getter()

        state.Text =
            enabled
            and "ON"
            or "OFF"

        state.TextColor3 =
            enabled
            and COLORS.GREEN
            or COLORS.MUTED
    end

    Connect(

        button.Activated,

        function()

            setter(
                not getter()
            )

            Refresh()
        end
    )

    Refresh()
end

--==============================================================
-- OPTIONS
--==============================================================

CreateToggle(

    "MUNIÇÃO INFINITA",

    function()
        return CONFIG.InfiniteAmmo
    end,

    function(value)

        CONFIG.InfiniteAmmo =
            value

        if value then
            PatchWeapon(
                GetEquippedTool()
            )
        end
    end
)

CreateToggle(

    "SEM RECARGA",

    function()
        return CONFIG.NoReload
    end,

    function(value)

        CONFIG.NoReload =
            value

        if value then
            PatchWeapon(
                GetEquippedTool()
            )
        end
    end
)

CreateToggle(

    "DISPARO CONTÍNUO",

    function()
        return CONFIG.ContinuousFire
    end,

    function(value)

        CONFIG.ContinuousFire =
            value

        if not value then
            StopContinuousFire()
        end
    end
)

CreateToggle(

    "FORÇAR AUTO",

    function()
        return CONFIG.ForceAuto
    end,

    function(value)

        CONFIG.ForceAuto =
            value

        if value then
            PatchWeapon(
                GetEquippedTool()
            )
        end
    end
)

CreateToggle(

    "SEM RECOIL",

    function()
        return CONFIG.NoRecoil
    end,

    function(value)

        CONFIG.NoRecoil =
            value

        if value then
            PatchWeapon(
                GetEquippedTool()
            )
        end
    end
)

CreateToggle(

    "SEM ANIMAÇÕES",

    function()
        return CONFIG.NoAnimations
    end,

    function(value)

        CONFIG.NoAnimations =
            value

        if value then
            StopWeaponAnimations()
        end
    end
)

CreateToggle(

    "RAJADA",

    function()
        return CONFIG.BurstEnabled
    end,

    function(value)

        CONFIG.BurstEnabled =
            value
    end
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
    "C"

Restore.TextColor3 =
    COLORS.RED

Restore.Font =
    Enum.Font.GothamBlack

Restore.TextSize =
    18

Restore.Visible =
    false

Restore.Parent =
    Gui

AddCorner(Restore, 13)
AddStroke(Restore)

Connect(

    Minimize.Activated,

    function()

        STATE.Minimized =
            true

        Main.Visible =
            false

        Restore.Visible =
            true
    end
)

Connect(

    Restore.Activated,

    function()

        STATE.Minimized =
            false

        Main.Visible =
            true

        Restore.Visible =
            false
    end
)

--==============================================================
-- DRAG
--==============================================================

local function MakeDraggable(
    handle,
    frame
)

    local dragging =
        false

    local dragInput =
        nil

    local startPointer =
        nil

    local startPosition =
        nil

    Connect(

        handle.InputBegan,

        function(input)

            if
                input.UserInputType ==
                Enum.UserInputType.Touch

                or

                input.UserInputType ==
                Enum.UserInputType.MouseButton1
            then

                dragging =
                    true

                startPointer =
                    input.Position

                startPosition =
                    frame.Position
            end
        end
    )

    Connect(

        handle.InputChanged,

        function(input)

            if
                input.UserInputType ==
                Enum.UserInputType.Touch

                or

                input.UserInputType ==
                Enum.UserInputType.MouseMovement
            then

                dragInput =
                    input
            end
        end
    )

    Connect(

        UserInputService.InputChanged,

        function(input)

            if
                not dragging
                or
                input ~= dragInput
                or
                not startPointer
            then
                return
            end

            local delta =
                input.Position
                -
                startPointer

            frame.Position =
                UDim2.new(

                    startPosition.X.Scale,

                    startPosition.X.Offset
                    + delta.X,

                    startPosition.Y.Scale,

                    startPosition.Y.Offset
                    + delta.Y
                )
        end
    )

    Connect(

        UserInputService.InputEnded,

        function(input)

            if
                input.UserInputType ==
                Enum.UserInputType.Touch

                or

                input.UserInputType ==
                Enum.UserInputType.MouseButton1
            then

                dragging =
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
-- STATUS LOOP
--==============================================================

task.spawn(function()

    while not STATE.Closed do

        local tool =
            GetEquippedTool()

        if tool
        and IsBlasterTool(tool) then

            Status.Text =
                tostring(tool.Name)
                ..
                " • "
                ..
                tostring(
                    tool:GetAttribute(
                        "_ammo"
                    ) or "?"
                )
                ..
                " AMMO • "
                ..
                tostring(
                    tool:GetAttribute(
                        "fireMode"
                    ) or "?"
                )
                ..
                " • "
                ..
                STATE.HookStatus

            Status.TextColor3 =
                COLORS.GREEN

        elseif tool then

            Status.Text =
                tostring(tool.Name)
                ..
                " • TOOL"

            Status.TextColor3 =
                COLORS.MUTED

        else

            Status.Text =
                "EQUIPE UMA ARMA • "
                ..
                STATE.HookStatus

            Status.TextColor3 =
                COLORS.MUTED
        end

        task.wait(0.20)
    end
end)

--==============================================================
-- SHUTDOWN
--==============================================================

local function Shutdown()

    if STATE.Closed then
        return
    end

    STATE.Closed =
        true

    StopContinuousFire()

    CONFIG.InfiniteAmmo =
        false

    CONFIG.NoReload =
        false

    CONFIG.NoRecoil =
        false

    CONFIG.ForceAuto =
        false

    CONFIG.NoAnimations =
        false

    RestoreController()

    RestoreAttributes()

    DisconnectList(
        ToolConnections
    )

    DisconnectList(
        CharacterConnections
    )

    DisconnectList(
        Connections
    )

    if Gui then

        pcall(function()
            Gui:Destroy()
        end)
    end

    if ENV[RUNTIME_KEY] ==
        Runtime then

        ENV[RUNTIME_KEY] =
            nil
    end

    print(
        "[CAFEÍNA] Weapon Lab V5.1 encerrado"
    )
end

Runtime.Shutdown =
    Shutdown

Connect(
    Close.Activated,
    Shutdown
)

--==============================================================
-- INITIALIZE
--==============================================================

if InstallBlasterController() then

    STATE.HookStatus =
        "BLASTER OK"

else

    STATE.HookStatus =
        "TOOL MODE"
end

if LocalPlayer.Character then

    AttachCharacter(
        LocalPlayer.Character
    )
end

task.defer(function()

    RefreshTool()

    local tool =
        GetEquippedTool()

    if tool then
        PatchWeapon(tool)
    end

    StopWeaponAnimations()
end)

print(
    "[CAFEÍNA] Weapon Lab V5.1 iniciado"
)
