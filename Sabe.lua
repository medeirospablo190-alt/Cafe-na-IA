--[[
=====================================================================
 CAFEÍNA • WEAPON LAB V4
 EXECUTOR ONLY • GAME-SPECIFIC

 Estrutura observada no jogo:
 ReplicatedStorage.BlasterSystem.Blaster

 Funções:
 • SEM RECARGA
 • SEM ANIMAÇÕES
 • SEM RECOIL
 • AUTO FIRE
 • HEAD LOCK
 • HITBOX
 • ALVOS
 • Players + Workspace.Soldiers
 • TP atrás
 • Follow inteligente
 • Auto-fire no alvo
 • Head targeting via BlasterController.getMouseLocation
 • Restauração completa
 • Mobile
=====================================================================
]]

--===================================================================
-- SERVICES
--===================================================================

local Players =
    game:GetService("Players")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local RunService =
    game:GetService("RunService")

local UserInputService =
    game:GetService("UserInputService")

local Workspace =
    game:GetService("Workspace")

local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    warn("[CAFEÍNA] LocalPlayer não encontrado")
    return
end

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui",
        15
    )

if not PlayerGui then
    warn("[CAFEÍNA] PlayerGui não encontrado")
    return
end

--===================================================================
-- RUNTIME / REINJEÇÃO
--===================================================================

local ENV = _G

if type(getgenv) == "function" then
    local ok, result =
        pcall(getgenv)

    if ok and type(result) == "table" then
        ENV = result
    end
end

if
    ENV.CAFEINA_WEAPON_LAB_V4
    and
    type(
        ENV.CAFEINA_WEAPON_LAB_V4.Shutdown
    ) == "function"
then
    pcall(
        ENV.CAFEINA_WEAPON_LAB_V4.Shutdown
    )
end

local Runtime = {}

ENV.CAFEINA_WEAPON_LAB_V4 =
    Runtime

--===================================================================
-- CONFIG
--===================================================================

local CONFIG = {

    -- ARMAS
    NoReload = true,
    NoAnimations = true,
    NoRecoil = true,

    ContinuousFire = true,

    -- força tentativa de comportamento Auto
    ForceAuto = true,

    -- RPM cliente
    DesiredRPM = 1200,

    -- mantém munição cheia localmente
    InfiniteAmmo = true,

    -- HEAD LOCK
    HeadLock = true,

    -- gira câmera para Head como fallback
    CameraHeadLock = true,

    -- HITBOX
    HitboxEnabled = true,

    HitboxSize =
        Vector3.new(
            16,
            16,
            16
        ),

    -- TP
    BehindDistance = 6.5,

    BehindHeight = 0.5,

    RepositionDistance = 3.0,

    FollowInterval = 0.08,

    -- TARGET LIST
    TargetRefresh = 0.75,

    IncludePlayers = true,

    IncludeSoldiers = true,

    -- BURST
    BurstEnabled = false,

    BurstShots = 5,

    BurstInterval = 0.045,

    MaxBurst = 50
}

--===================================================================
-- STATE
--===================================================================

local STATE = {

    Closed = false,

    Minimized = false,

    TargetMenuOpen = false,

    Target = nil,

    TargetKind = nil,

    Attacking = false,

    AttackToken = 0,

    Firing = false,

    FireToken = 0,

    InternalActivation = false,

    CurrentTool = nil,

    BlasterHooked = false,

    HookStatus = "NÃO ENCONTRADO"
}

--===================================================================
-- CONNECTIONS
--===================================================================

local Connections = {}

local ToolConnections = {}

local CharacterConnections = {}

local TargetConnections = {}

local AttackConnections = {}

local function Connect(
    signal,
    callback,
    list
)

    local connection =
        signal:Connect(callback)

    table.insert(
        list or Connections,
        connection
    )

    return connection
end

local function DisconnectList(list)

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

--===================================================================
-- CHARACTER
--===================================================================

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

local function GetRoot()

    local character =
        GetCharacter()

    return
        character
        and character:
        FindFirstChild(
            "HumanoidRootPart"
        )
end

local function GetEquippedTool()

    local character =
        GetCharacter()

    if not character then
        return nil
    end

    for _, child in ipairs(
        character:GetChildren()
    ) do

        if child:IsA("Tool") then
            return child
        end
    end

    return nil
end

--===================================================================
-- TEAM
--===================================================================

local function GetLocalTeamName()

    if LocalPlayer.Team then
        return
            tostring(
                LocalPlayer.Team.Name
            )
    end

    local character =
        GetCharacter()

    if character then

        local attr =
            character:
            GetAttribute("Team")

        if attr ~= nil then
            return tostring(attr)
        end
    end

    return nil
end

local function SameStringTeam(
    a,
    b
)

    if a == nil
    or b == nil then
        return false
    end

    return
        string.lower(
            tostring(a)
        )
        ==
        string.lower(
            tostring(b)
        )
end

local function IsPlayerEnemy(
    player
)

    if
        not player
        or player == LocalPlayer
    then
        return false
    end

    local character =
        player.Character

    if not character then
        return false
    end

    local humanoid =
        character:
        FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:
        FindFirstChild(
            "HumanoidRootPart"
        )

    local head =
        character:
        FindFirstChild(
            "Head"
        )

    if
        not humanoid
        or humanoid.Health <= 0
        or not root
        or not head
    then
        return false
    end

    -- Roblox Team
    if
        LocalPlayer.Team
        and player.Team
    then

        if LocalPlayer.Team ==
            player.Team
        then
            return false
        end

        if
            not LocalPlayer.Neutral
            and
            not player.Neutral
            and
            LocalPlayer.TeamColor ==
            player.TeamColor
        then
            return false
        end

        return true
    end

    -- Attribute fallback
    local myTeam =
        GetLocalTeamName()

    local targetTeam =
        character:
        GetAttribute("Team")

    if
        myTeam
        and targetTeam
        and SameStringTeam(
            myTeam,
            targetTeam
        )
    then
        return false
    end

    return true
end

local function IsSoldierEnemy(
    model
)

    if
        not model
        or not model:IsA("Model")
    then
        return false
    end

    local soldiers =
        Workspace:
        FindFirstChild(
            "Soldiers"
        )

    if
        not soldiers
        or model.Parent ~= soldiers
    then
        return false
    end

    local humanoid =
        model:
        FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        model:
        FindFirstChild(
            "HumanoidRootPart"
        )

    local head =
        model:
        FindFirstChild(
            "Head"
        )

    if
        not humanoid
        or humanoid.Health <= 0
        or not root
        or not head
    then
        return false
    end

    local soldierTeam =
        model:
        GetAttribute("Team")

    local myTeam =
        GetLocalTeamName()

    -- Se conseguimos identificar os dois,
    -- somente time diferente entra.
    if
        soldierTeam ~= nil
        and myTeam ~= nil
    then
        return
            not SameStringTeam(
                soldierTeam,
                myTeam
            )
    end

    -- Sem informação suficiente:
    -- não assume aliado.
    return true
end

--===================================================================
-- TARGET HELPERS
--===================================================================

local function GetTargetModel()

    return STATE.Target
end

local function GetTargetHumanoid()

    local target =
        GetTargetModel()

    return
        target
        and target:
        FindFirstChildOfClass(
            "Humanoid"
        )
end

local function GetTargetRoot()

    local target =
        GetTargetModel()

    return
        target
        and target:
        FindFirstChild(
            "HumanoidRootPart"
        )
end

local function GetTargetHead()

    local target =
        GetTargetModel()

    return
        target
        and target:
        FindFirstChild(
            "Head"
        )
end

local function TargetIsEnemy(
    target
)

    if not target then
        return false
    end

    local player =
        Players:
        GetPlayerFromCharacter(
            target
        )

    if player then
        return
            IsPlayerEnemy(
                player
            )
    end

    return
        IsSoldierEnemy(
            target
        )
end

local function TargetAlive()

    local humanoid =
        GetTargetHumanoid()

    return
        STATE.Target ~= nil
        and humanoid ~= nil
        and humanoid.Health > 0
        and GetTargetRoot() ~= nil
        and GetTargetHead() ~= nil
        and TargetIsEnemy(
            STATE.Target
        )
end

--===================================================================
-- ORIGINAL WEAPON VALUES
--===================================================================

local OriginalAttributes = {}

local function SaveAttribute(
    object,
    attribute
)

    if not object then
        return
    end

    local map =
        OriginalAttributes[object]

    if not map then
        map = {}
        OriginalAttributes[object] =
            map
    end

    if map[attribute] ~= nil then
        return
    end

    local value =
        object:
        GetAttribute(
            attribute
        )

    if value ~= nil then
        map[attribute] =
            value
    end
end

local function SetSavedAttribute(
    object,
    attribute,
    value
)

    if not object then
        return
    end

    SaveAttribute(
        object,
        attribute
    )

    pcall(function()

        object:
            SetAttribute(
                attribute,
                value
            )
    end)
end

--===================================================================
-- WEAPON PATCH
--===================================================================

local function PatchWeapon(
    tool
)

    if
        not tool
        or not tool:IsA("Tool")
    then
        return
    end

    -- reload
    if CONFIG.NoReload then

        SetSavedAttribute(
            tool,
            "reloadTime",
            0
        )

        SetSavedAttribute(
            tool,
            "reloadTimePerRound",
            0
        )

        SetSavedAttribute(
            tool,
            "_reloading",
            false
        )
    end

    -- recoil
    if CONFIG.NoRecoil then

        SetSavedAttribute(
            tool,
            "recoilMin",
            Vector2.zero
        )

        SetSavedAttribute(
            tool,
            "recoilMax",
            Vector2.zero
        )
    end

    -- auto
    if CONFIG.ForceAuto then

        SetSavedAttribute(
            tool,
            "fireMode",
            "Auto"
        )

        SetSavedAttribute(
            tool,
            "rateOfFire",
            CONFIG.DesiredRPM
        )
    end

    -- ammo
    if CONFIG.InfiniteAmmo then

        local magazine =
            tool:
            GetAttribute(
                "magazineSize"
            )

        if typeof(magazine) ==
            "number"
        then

            SetSavedAttribute(
                tool,
                "_ammo",
                magazine
            )
        end
    end
end

local function RestoreWeaponAttributes()

    for object, values in pairs(
        OriginalAttributes
    ) do

        if
            typeof(object) ==
            "Instance"
            and object.Parent
        then

            for attribute,
                value in pairs(values)
            do

                pcall(function()

                    object:
                        SetAttribute(
                            attribute,
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

--===================================================================
-- ANIMATION CONTROL
--===================================================================

local WeaponAnimationNames = {

    "reload",
    "fire",
    "shoot",
    "shot",
    "recoil",

    "equip",
    "unequip",

    "pump",
    "bolt",

    "inspect",

    "weapon",
    "gun"
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

    local animation =
        track.Animation

    if animation then

        text =
            text
            .. " "
            ..
            string.lower(
                tostring(
                    animation.Name or ""
                )
            )
    end

    for _, word in ipairs(
        WeaponAnimationNames
    ) do

        if string.find(
            text,
            word,
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

    local humanoid =
        GetHumanoid()

    local animator =
        humanoid
        and humanoid:
        FindFirstChildOfClass(
            "Animator"
        )

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

--===================================================================
-- BLASTER CONTROLLER HOOK
--===================================================================

local BlasterController =
    nil

local OriginalBlaster = {}

local function GetSilentMousePosition()

    if
        not CONFIG.HeadLock
        or not STATE.Attacking
        or not TargetAlive()
    then
        return nil
    end

    local head =
        GetTargetHead()

    local camera =
        Workspace.CurrentCamera

    if not head
    or not camera then
        return nil
    end

    local position,
        onScreen =
        camera:
        WorldToViewportPoint(
            head.Position
        )

    -- Mesmo se estiver próximo da borda,
    -- ainda pode retornar o ponto projetado.
    return Vector2.new(
        position.X,
        position.Y
    ),
    onScreen
end

local function InstallBlasterHooks()

    local ok, result =
        pcall(function()

            local system =
                ReplicatedStorage:
                WaitForChild(
                    "BlasterSystem",
                    5
                )

            local blaster =
                system:
                WaitForChild(
                    "Blaster",
                    5
                )

            local scripts =
                blaster:
                WaitForChild(
                    "Scripts",
                    5
                )

            local module =
                scripts:
                WaitForChild(
                    "BlasterController",
                    5
                )

            return require(module)
        end)

    if
        not ok
        or type(result) ~= "table"
    then

        STATE.HookStatus =
            "FALLBACK CÂMERA"

        return false
    end

    BlasterController =
        result

    --===============================================================
    -- GET MOUSE LOCATION
    --===============================================================

    if
        type(
            BlasterController.getMouseLocation
        ) == "function"
    then

        OriginalBlaster.getMouseLocation =
            BlasterController.getMouseLocation

        BlasterController.getMouseLocation =
            function(self, ...)

                local silent =
                    GetSilentMousePosition()

                if silent then
                    return silent
                end

                return
                    OriginalBlaster.getMouseLocation(
                        self,
                        ...
                    )
            end
    end

    --===============================================================
    -- RECOIL
    --===============================================================

    if
        type(
            BlasterController.recoil
        ) == "function"
    then

        OriginalBlaster.recoil =
            BlasterController.recoil

        BlasterController.recoil =
            function(self, ...)

                if CONFIG.NoRecoil then
                    return
                end

                return
                    OriginalBlaster.recoil(
                        self,
                        ...
                    )
            end
    end

    --===============================================================
    -- RELOAD
    --===============================================================

    if
        type(
            BlasterController.reload
        ) == "function"
    then

        OriginalBlaster.reload =
            BlasterController.reload

        BlasterController.reload =
            function(self, ...)

                if CONFIG.NoReload then

                    local tool =
                        GetEquippedTool()

                    PatchWeapon(tool)

                    return
                end

                return
                    OriginalBlaster.reload(
                        self,
                        ...
                    )
            end
    end

    STATE.BlasterHooked =
        true

    STATE.HookStatus =
        "BLASTER HOOK OK"

    return true
end

local function RestoreBlasterHooks()

    if not BlasterController then
        return
    end

    for name, original in pairs(
        OriginalBlaster
    ) do

        pcall(function()

            BlasterController[name] =
                original
        end)
    end

    table.clear(
        OriginalBlaster
    )

    STATE.BlasterHooked =
        false
end

--===================================================================
-- HITBOX
--===================================================================

local HitboxState = {

    Part = nil,

    Size = nil,

    Transparency = nil,

    CanCollide = nil,

    Massless = nil
}

local function RestoreHitbox()

    local part =
        HitboxState.Part

    if part and part.Parent then

        pcall(function()

            if HitboxState.Size then
                part.Size =
                    HitboxState.Size
            end

            if
                HitboxState.Transparency
                ~= nil
            then
                part.Transparency =
                    HitboxState.Transparency
            end

            if
                HitboxState.CanCollide
                ~= nil
            then
                part.CanCollide =
                    HitboxState.CanCollide
            end

            if
                HitboxState.Massless
                ~= nil
            then
                part.Massless =
                    HitboxState.Massless
            end
        end)
    end

    HitboxState.Part = nil
    HitboxState.Size = nil
    HitboxState.Transparency = nil
    HitboxState.CanCollide = nil
    HitboxState.Massless = nil
end

local function ExpandHitbox()

    RestoreHitbox()

    if
        not CONFIG.HitboxEnabled
        or not TargetAlive()
    then
        return
    end

    local root =
        GetTargetRoot()

    if not root then
        return
    end

    HitboxState.Part =
        root

    HitboxState.Size =
        root.Size

    HitboxState.Transparency =
        root.Transparency

    HitboxState.CanCollide =
        root.CanCollide

    HitboxState.Massless =
        root.Massless

    pcall(function()

        root.Size =
            CONFIG.HitboxSize

        root.Transparency =
            1

        root.CanCollide =
            false

        root.Massless =
            true
    end)
end

--===================================================================
-- SAFE TELEPORT
--===================================================================

local function GroundPosition(
    position
)

    local character =
        GetCharacter()

    local target =
        GetTargetModel()

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character,
        target
    }

    local origin =
        position
        + Vector3.new(
            0,
            12,
            0
        )

    local result =
        Workspace:
        Raycast(
            origin,
            Vector3.new(
                0,
                -50,
                0
            ),
            params
        )

    if result then

        return
            Vector3.new(
                position.X,
                result.Position.Y + 3,
                position.Z
            )
    end

    return position
end

local function PositionIsFree(
    position
)

    local character =
        GetCharacter()

    local target =
        GetTargetModel()

    local params =
        OverlapParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character,
        target
    }

    local parts =
        Workspace:
        GetPartBoundsInBox(
            CFrame.new(position),
            Vector3.new(
                3.5,
                5.5,
                3.5
            ),
            params
        )

    for _, part in ipairs(parts) do

        if
            part.CanCollide
            and
            part.Transparency < 0.95
        then
            return false
        end
    end

    return true
end

local function FindBehindPosition()

    local targetRoot =
        GetTargetRoot()

    if not targetRoot then
        return nil
    end

    local backward =
        -targetRoot.CFrame.LookVector

    local right =
        targetRoot.CFrame.RightVector

    local base =
        targetRoot.Position
        +
        backward
        *
        CONFIG.BehindDistance

    base +=
        Vector3.new(
            0,
            CONFIG.BehindHeight,
            0
        )

    local candidates = {

        base,

        base + right * 3,

        base - right * 3,

        base + right * 5,

        base - right * 5,

        targetRoot.Position
        +
        backward
        *
        (
            CONFIG.BehindDistance
            + 3
        )
    }

    for _, candidate in ipairs(
        candidates
    ) do

        local grounded =
            GroundPosition(
                candidate
            )

        if PositionIsFree(
            grounded
        ) then
            return grounded
        end
    end

    return
        GroundPosition(
            base
        )
end

local function TeleportBehind(
    force
)

    if not TargetAlive() then
        return false
    end

    local myRoot =
        GetRoot()

    local targetRoot =
        GetTargetRoot()

    if
        not myRoot
        or not targetRoot
    then
        return false
    end

    local desired =
        FindBehindPosition()

    if not desired then
        return false
    end

    if
        not force
        and
        (
            myRoot.Position
            - desired
        ).Magnitude
        <=
        CONFIG.RepositionDistance
    then

        return true
    end

    pcall(function()

        myRoot.CFrame =
            CFrame.lookAt(
                desired,
                targetRoot.Position
            )
    end)

    return true
end

--===================================================================
-- CAMERA HEAD LOCK
--===================================================================

local AIM_BIND =
    "CAFEINA_WEAPON_HEAD_LOCK_V4"

local function InstallCameraLock()

    pcall(function()
        RunService:
            UnbindFromRenderStep(
                AIM_BIND
            )
    end)

    RunService:
        BindToRenderStep(

            AIM_BIND,

            Enum.RenderPriority.Camera.Value
            + 1,

            function()

                if
                    STATE.Closed
                    or
                    not STATE.Attacking
                    or
                    not CONFIG.CameraHeadLock
                    or
                    not TargetAlive()
                then
                    return
                end

                local camera =
                    Workspace.CurrentCamera

                local head =
                    GetTargetHead()

                if
                    not camera
                    or not head
                then
                    return
                end

                -- Não altera CameraType.
                -- O controlador normal continua existindo.
                camera.CFrame =
                    CFrame.lookAt(
                        camera.CFrame.Position,
                        head.Position
                    )
            end
        )
end

--===================================================================
-- AUTO FIRE
--===================================================================

local function FireInterval()

    local rpm =
        math.max(
            tonumber(
                CONFIG.DesiredRPM
            ) or 600,
            60
        )

    return
        math.max(
            60 / rpm,
            0.015
        )
end

local function FirePulse(
    expectedTool
)

    if STATE.Closed then
        return false
    end

    local tool =
        GetEquippedTool()

    if not tool then
        return false
    end

    if
        expectedTool
        and expectedTool ~= tool
    then
        return false
    end

    PatchWeapon(tool)

    STATE.InternalActivation =
        true

    local ok =
        pcall(function()

            tool:
                Activate()
        end)

    STATE.InternalActivation =
        false

    if CONFIG.NoAnimations then
        task.defer(
            StopWeaponAnimations
        )
    end

    return ok
end

local function StopContinuousFire()

    STATE.Firing =
        false

    STATE.FireToken += 1
end

local function StartContinuousFire(
    tool
)

    if
        STATE.Closed
        or STATE.Firing
        or not CONFIG.ContinuousFire
        or not tool
    then
        return
    end

    if
        tool ~=
        GetEquippedTool()
    then
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

                for index = 1,
                    shots
                do

                    if
                        STATE.Closed
                        or
                        not STATE.Firing
                        or
                        STATE.FireToken
                        ~= token
                    then
                        break
                    end

                    FirePulse(tool)

                    if index < shots then

                        task.wait(
                            math.max(
                                CONFIG.BurstInterval,
                                0.01
                            )
                        )
                    end
                end

            else

                FirePulse(tool)
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
                FireInterval()
            )
        end

        if
            STATE.FireToken ==
            token
        then

            STATE.Firing =
                false
        end
    end)
end

--===================================================================
-- TOOL CONTROLLER
--===================================================================

local function AttachTool(
    tool
)

    if
        STATE.CurrentTool ==
        tool
    then
        return
    end

    DisconnectList(
        ToolConnections
    )

    StopContinuousFire()

    STATE.CurrentTool =
        tool

    if
        not tool
        or
        not tool:IsA("Tool")
    then
        return
    end

    PatchWeapon(tool)

    -- Botão ORIGINAL da arma
    Connect(

        tool.Activated,

        function()

            if
                STATE.Closed
                or
                STATE.InternalActivation
            then
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

    Connect(

        tool.Deactivated,

        function()

            if
                STATE.InternalActivation
                or STATE.Attacking
            then
                return
            end

            StopContinuousFire()
        end,

        ToolConnections
    )

    Connect(

        tool:GetAttributeChangedSignal(
            "_reloading"
        ),

        function()

            if
                CONFIG.NoReload
                and
                tool:
                GetAttribute(
                    "_reloading"
                ) == true
            then

                task.defer(function()
                    PatchWeapon(tool)
                end)
            end
        end,

        ToolConnections
    )

    Connect(

        tool:GetAttributeChangedSignal(
            "_ammo"
        ),

        function()

            if
                CONFIG.InfiniteAmmo
                and
                not STATE.Closed
            then

                task.defer(function()
                    PatchWeapon(tool)
                end)
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

--===================================================================
-- ATTACK
--===================================================================

local StopAttack

StopAttack =
    function()

        STATE.Attacking =
            false

        STATE.AttackToken += 1

        DisconnectList(
            AttackConnections
        )

        StopContinuousFire()

        RestoreHitbox()

        STATE.Target =
            nil

        STATE.TargetKind =
            nil
    end

local function StartAttack(
    target,
    kind
)

    StopAttack()

    STATE.Target =
        target

    STATE.TargetKind =
        kind

    if not TargetAlive() then

        STATE.Target = nil
        STATE.TargetKind = nil

        return false
    end

    local tool =
        GetEquippedTool()

    if not tool then
        return false
    end

    STATE.Attacking =
        true

    STATE.AttackToken += 1

    local token =
        STATE.AttackToken

    local humanoid =
        GetTargetHumanoid()

    if humanoid then

        Connect(

            humanoid.HealthChanged,

            function(health)

                if
                    health <= 0
                    and
                    STATE.AttackToken ==
                    token
                then

                    StopAttack()
                end
            end,

            AttackConnections
        )
    end

    ExpandHitbox()

    TeleportBehind(true)

    -- começa atirando automaticamente
    StartContinuousFire(
        tool
    )

    task.spawn(function()

        while
            not STATE.Closed
            and
            STATE.Attacking
            and
            STATE.AttackToken ==
            token
        do

            if not TargetAlive() then
                break
            end

            if
                GetEquippedTool()
                ~= tool
            then
                break
            end

            -- mantém patches
            PatchWeapon(tool)

            -- não CFrame-spamma;
            -- corrige somente quando necessário
            TeleportBehind(false)

            task.wait(
                CONFIG.FollowInterval
            )
        end

        if
            STATE.AttackToken ==
            token
        then

            StopAttack()
        end
    end)

    return true
end

--===================================================================
-- GUI
--===================================================================

local GUI_NAME =
    "CafeinaWeaponLabV4"

local previous =
    PlayerGui:
    FindFirstChild(
        GUI_NAME
    )

if previous then
    previous:Destroy()
end

local COLORS = {

    BG =
        Color3.fromRGB(
            10,
            10,
            12
        ),

    PANEL =
        Color3.fromRGB(
            20,
            20,
            24
        ),

    PANEL2 =
        Color3.fromRGB(
            29,
            29,
            34
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

local function Corner(
    object,
    radius
)

    local corner =
        Instance.new(
            "UICorner"
        )

    corner.CornerRadius =
        UDim.new(
            0,
            radius or 8
        )

    corner.Parent =
        object

    return corner
end

local function Stroke(
    object
)

    local stroke =
        Instance.new(
            "UIStroke"
        )

    stroke.Color =
        COLORS.STROKE

    stroke.Thickness =
        1

    stroke.Transparency =
        0.2

    stroke.Parent =
        object

    return stroke
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    GUI_NAME

Gui.ResetOnSpawn =
    false

Gui.IgnoreGuiInset =
    false

Gui.DisplayOrder =
    999999

Gui.ZIndexBehavior =
    Enum.ZIndexBehavior.Sibling

Gui.Parent =
    PlayerGui

--===================================================================
-- MAIN
--===================================================================

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
        0.12,
        0
    )

Main.Size =
    UDim2.fromOffset(
        286,
        392
    )

Main.BackgroundColor3 =
    COLORS.BG

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

Corner(Main, 13)
Stroke(Main)

local Header =
    Instance.new("Frame")

Header.Size =
    UDim2.new(
        1,
        0,
        0,
        46
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

Title.Font =
    Enum.Font.GothamBlack

Title.TextSize =
    12

Title.TextColor3 =
    COLORS.TEXT

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
        13
    )

Subtitle.BackgroundTransparency =
    1

Subtitle.Text =
    "BLASTER V4 • EXECUTOR"

Subtitle.Font =
    Enum.Font.GothamBold

Subtitle.TextSize =
    8

Subtitle.TextColor3 =
    COLORS.MUTED

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

Minimize.TextSize =
    14

Minimize.Parent =
    Header

Corner(Minimize, 7)

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

Close.TextSize =
    15

Close.Parent =
    Header

Corner(Close, 7)

--===================================================================
-- BODY
--===================================================================

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

--===================================================================
-- STATUS
--===================================================================

local Status =
    Instance.new("TextLabel")

Status.Size =
    UDim2.new(
        1,
        0,
        0,
        34
    )

Status.BackgroundColor3 =
    COLORS.PANEL

Status.BorderSizePixel =
    0

Status.Text =
    "INICIALIZANDO BLASTER..."

Status.TextColor3 =
    COLORS.MUTED

Status.Font =
    Enum.Font.GothamBold

Status.TextSize =
    9

Status.Parent =
    Body

Corner(Status, 8)

--===================================================================
-- UI HELPERS
--===================================================================

local function CreateToggle(
    text,
    getter,
    setter
)

    local row =
        Instance.new(
            "TextButton"
        )

    row.Size =
        UDim2.new(
            1,
            0,
            0,
            39
        )

    row.BackgroundColor3 =
        COLORS.PANEL

    row.BorderSizePixel =
        0

    row.Text =
        ""

    row.Parent =
        Body

    Corner(row, 8)

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
        text

    label.TextColor3 =
        COLORS.TEXT

    label.Font =
        Enum.Font.GothamMedium

    label.TextSize =
        10

    label.TextXAlignment =
        Enum.TextXAlignment.Left

    label.Parent =
        row

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
        row

    local function update()

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
        row.Activated,
        function()

            setter(
                not getter()
            )

            update()
        end
    )

    update()

    return row
end

local function CreateButton(
    text
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
            40
        )

    button.BackgroundColor3 =
        COLORS.PANEL

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        COLORS.TEXT

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        10

    button.Parent =
        Body

    Corner(button, 8)

    return button
end

--===================================================================
-- TOGGLES
--===================================================================

CreateToggle(
    "SEM RECARGA",
    function()
        return CONFIG.NoReload
    end,
    function(v)

        CONFIG.NoReload = v

        if v then
            PatchWeapon(
                GetEquippedTool()
            )
        end
    end
)

CreateToggle(
    "MUNIÇÃO INFINITA",
    function()
        return CONFIG.InfiniteAmmo
    end,
    function(v)

        CONFIG.InfiniteAmmo = v

        if v then
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
    function(v)

        CONFIG.ContinuousFire = v

        if not v then
            StopContinuousFire()
        end
    end
)

CreateToggle(
    "SEM RECOIL",
    function()
        return CONFIG.NoRecoil
    end,
    function(v)

        CONFIG.NoRecoil = v

        PatchWeapon(
            GetEquippedTool()
        )
    end
)

CreateToggle(
    "SEM ANIMAÇÕES",
    function()
        return CONFIG.NoAnimations
    end,
    function(v)

        CONFIG.NoAnimations = v

        if v then
            StopWeaponAnimations()
        end
    end
)

CreateToggle(
    "HEAD LOCK",
    function()
        return CONFIG.HeadLock
    end,
    function(v)
        CONFIG.HeadLock = v
    end
)

CreateToggle(
    "HITBOX GRANDE",
    function()
        return CONFIG.HitboxEnabled
    end,
    function(v)

        CONFIG.HitboxEnabled = v

        if not v then
            RestoreHitbox()

        elseif STATE.Attacking then
            ExpandHitbox()
        end
    end
)

local TargetButton =
    CreateButton(
        "ALVOS INIMIGOS  ›"
    )

local StopButton =
    CreateButton(
        "PARAR ALVO ATUAL"
    )

StopButton.TextColor3 =
    COLORS.RED

Connect(
    StopButton.Activated,
    StopAttack
)

--===================================================================
-- RESTORE
--===================================================================

local Restore =
    Instance.new(
        "TextButton"
    )

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

Corner(Restore, 13)
Stroke(Restore)

local function MinimizeMain()

    STATE.Minimized =
        true

    Main.Visible =
        false

    Restore.Visible =
        true
end

local function RestoreMain()

    STATE.Minimized =
        false

    Main.Visible =
        true

    Restore.Visible =
        false
end

Connect(
    Minimize.Activated,
    MinimizeMain
)

--===================================================================
-- TARGET PANEL
--===================================================================

local TargetPanel =
    Instance.new("Frame")

TargetPanel.AnchorPoint =
    Vector2.new(
        0.5,
        0
    )

TargetPanel.Position =
    UDim2.new(
        0.5,
        0,
        0.12,
        0
    )

TargetPanel.Size =
    UDim2.fromOffset(
        286,
        390
    )

TargetPanel.BackgroundColor3 =
    COLORS.BG

TargetPanel.BorderSizePixel =
    0

TargetPanel.Visible =
    false

TargetPanel.Parent =
    Gui

Corner(TargetPanel, 13)
Stroke(TargetPanel)

local TargetHeader =
    Instance.new("Frame")

TargetHeader.Size =
    UDim2.new(
        1,
        0,
        0,
        46
    )

TargetHeader.BackgroundTransparency =
    1

TargetHeader.Parent =
    TargetPanel

local TargetTitle =
    Instance.new("TextLabel")

TargetTitle.Position =
    UDim2.fromOffset(
        13,
        0
    )

TargetTitle.Size =
    UDim2.new(
        1,
        -55,
        1,
        0
    )

TargetTitle.BackgroundTransparency =
    1

TargetTitle.Text =
    "INIMIGOS"

TargetTitle.TextColor3 =
    COLORS.TEXT

TargetTitle.Font =
    Enum.Font.GothamBlack

TargetTitle.TextSize =
    12

TargetTitle.TextXAlignment =
    Enum.TextXAlignment.Left

TargetTitle.Parent =
    TargetHeader

local TargetClose =
    Instance.new(
        "TextButton"
    )

TargetClose.Size =
    UDim2.fromOffset(
        29,
        29
    )

TargetClose.Position =
    UDim2.new(
        1,
        -36,
        0,
        8
    )

TargetClose.BackgroundColor3 =
    COLORS.RED

TargetClose.BorderSizePixel =
    0

TargetClose.Text =
    "×"

TargetClose.TextColor3 =
    COLORS.TEXT

TargetClose.Font =
    Enum.Font.GothamBold

TargetClose.TextSize =
    15

TargetClose.Parent =
    TargetHeader

Corner(TargetClose, 7)

local TargetScroll =
    Instance.new(
        "ScrollingFrame"
    )

TargetScroll.Position =
    UDim2.fromOffset(
        8,
        50
    )

TargetScroll.Size =
    UDim2.new(
        1,
        -16,
        1,
        -58
    )

TargetScroll.BackgroundTransparency =
    1

TargetScroll.BorderSizePixel =
    0

TargetScroll.ScrollBarThickness =
    3

TargetScroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

TargetScroll.CanvasSize =
    UDim2.new()

TargetScroll.Parent =
    TargetPanel

local TargetLayout =
    Instance.new(
        "UIListLayout"
    )

TargetLayout.Padding =
    UDim.new(
        0,
        6
    )

TargetLayout.Parent =
    TargetScroll

--===================================================================
-- BUILD TARGET LIST
--===================================================================

local function GetTargetCandidates()

    local result = {}

    if CONFIG.IncludePlayers then

        for _, player in ipairs(
            Players:GetPlayers()
        ) do

            if IsPlayerEnemy(
                player
            ) then

                table.insert(
                    result,
                    {
                        Model =
                            player.Character,

                        Kind =
                            "PLAYER",

                        Name =
                            player.DisplayName
                    }
                )
            end
        end
    end

    if CONFIG.IncludeSoldiers then

        local soldiers =
            Workspace:
            FindFirstChild(
                "Soldiers"
            )

        if soldiers then

            for _, soldier in ipairs(
                soldiers:GetChildren()
            ) do

                if IsSoldierEnemy(
                    soldier
                ) then

                    table.insert(
                        result,
                        {
                            Model =
                                soldier,

                            Kind =
                                "SOLDIER",

                            Name =
                                soldier.Name
                        }
                    )
                end
            end
        end
    end

    local myRoot =
        GetRoot()

    table.sort(
        result,
        function(a, b)

            if not myRoot then
                return
                    a.Name < b.Name
            end

            local ar =
                a.Model
                and
                a.Model:
                FindFirstChild(
                    "HumanoidRootPart"
                )

            local br =
                b.Model
                and
                b.Model:
                FindFirstChild(
                    "HumanoidRootPart"
                )

            if not ar then
                return false
            end

            if not br then
                return true
            end

            return
                (
                    ar.Position
                    - myRoot.Position
                ).Magnitude
                <
                (
                    br.Position
                    - myRoot.Position
                ).Magnitude
        end
    )

    return result
end

local function RefreshTargetList()

    DisconnectList(
        TargetConnections
    )

    for _, child in ipairs(
        TargetScroll:GetChildren()
    ) do

        if child ~= TargetLayout then
            child:Destroy()
        end
    end

    local targets =
        GetTargetCandidates()

    for _, data in ipairs(
        targets
    ) do

        local root =
            data.Model
            and
            data.Model:
            FindFirstChild(
                "HumanoidRootPart"
            )

        local myRoot =
            GetRoot()

        local distance =
            0

        if root and myRoot then

            distance =
                math.floor(
                    (
                        root.Position
                        - myRoot.Position
                    ).Magnitude
                    + 0.5
                )
        end

        local row =
            Instance.new(
                "TextButton"
            )

        row.Size =
            UDim2.new(
                1,
                0,
                0,
                44
            )

        row.BackgroundColor3 =
            COLORS.PANEL

        row.BorderSizePixel =
            0

        row.Text =
            string.format(
                "%s  •  %s  •  %dst",
                data.Name,
                data.Kind,
                distance
            )

        row.TextColor3 =
            COLORS.TEXT

        row.Font =
            Enum.Font.GothamMedium

        row.TextSize =
            9

        row.Parent =
            TargetScroll

        Corner(row, 8)

        Connect(

            row.Activated,

            function()

                local target =
                    data.Model

                if
                    not target
                    or not target.Parent
                then
                    return
                end

                TargetPanel.Visible =
                    false

                STATE.TargetMenuOpen =
                    false

                StartAttack(
                    target,
                    data.Kind
                )
            end,

            TargetConnections
        )
    end
end

Connect(

    TargetButton.Activated,

    function()

        MinimizeMain()

        STATE.TargetMenuOpen =
            true

        TargetPanel.Visible =
            true

        RefreshTargetList()
    end
)

Connect(

    TargetClose.Activated,

    function()

        STATE.TargetMenuOpen =
            false

        TargetPanel.Visible =
            false
    end
)

Connect(

    Restore.Activated,

    function()

        STATE.TargetMenuOpen =
            false

        TargetPanel.Visible =
            false

        RestoreMain()
    end
)

--===================================================================
-- DRAG MOBILE
--===================================================================

local function MakeDraggable(
    handle,
    object
)

    local dragging = false

    local dragInput = nil

    local startInput = nil

    local startPosition = nil

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

                dragging = true

                startInput =
                    input.Position

                startPosition =
                    object.Position
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
                not startInput
                or
                not startPosition
            then
                return
            end

            local delta =
                input.Position
                - startInput

            object.Position =
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

MakeDraggable(
    TargetHeader,
    TargetPanel
)

--===================================================================
-- CHARACTER WATCH
--===================================================================

local function AttachCharacter(
    character
)

    DisconnectList(
        CharacterConnections
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

            if
                child ==
                STATE.CurrentTool
            then

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

    if humanoid then

        local animator =
            humanoid:
            FindFirstChildOfClass(
                "Animator"
            )

        if animator then

            Connect(

                animator.AnimationPlayed,

                function(track)

                    if
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
    end

    task.defer(
        RefreshTool
    )
end

--===================================================================
-- WATCHDOG
--===================================================================

local accumulator =
    0

Connect(

    RunService.Heartbeat,

    function(dt)

        if STATE.Closed then
            return
        end

        accumulator += dt

        if accumulator < 0.10 then
            return
        end

        accumulator = 0

        local tool =
            GetEquippedTool()

        if
            tool ~=
            STATE.CurrentTool
        then
            AttachTool(tool)
        end

        if tool then
            PatchWeapon(tool)
        end

        if CONFIG.NoAnimations then
            StopWeaponAnimations()
        end
    end
)

--===================================================================
-- TARGET LIST WATCHER
--===================================================================

task.spawn(function()

    while not STATE.Closed do

        if
            STATE.TargetMenuOpen
            and
            TargetPanel.Visible
        then

            RefreshTargetList()
        end

        task.wait(
            CONFIG.TargetRefresh
        )
    end
end)

--===================================================================
-- RESPAWN
--===================================================================

Connect(

    LocalPlayer.CharacterAdded,

    function(character)

        StopAttack()

        StopContinuousFire()

        task.wait(0.25)

        if not STATE.Closed then
            AttachCharacter(
                character
            )
        end
    end
)

--===================================================================
-- STATUS
--===================================================================

task.spawn(function()

    while not STATE.Closed do

        local tool =
            GetEquippedTool()

        local target =
            GetTargetModel()

        if STATE.Attacking
        and target then

            Status.Text =
                "ALVO: "
                ..
                target.Name
                ..
                " • "
                ..
                STATE.HookStatus

            Status.TextColor3 =
                COLORS.RED

        elseif tool then

            local ammo =
                tool:
                GetAttribute(
                    "_ammo"
                )

            Status.Text =
                tostring(
                    tool.Name
                )
                ..
                " • AMMO "
                ..
                tostring(
                    ammo or "?"
                )
                ..
                " • "
                ..
                STATE.HookStatus

            Status.TextColor3 =
                STATE.BlasterHooked
                and COLORS.GREEN
                or COLORS.MUTED

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

--===================================================================
-- SHUTDOWN
--===================================================================

local function Shutdown()

    if STATE.Closed then
        return
    end

    STATE.Closed =
        true

    StopAttack()

    StopContinuousFire()

    RestoreHitbox()

    RestoreWeaponAttributes()

    RestoreBlasterHooks()

    pcall(function()

        RunService:
            UnbindFromRenderStep(
                AIM_BIND
            )
    end)

    DisconnectList(
        TargetConnections
    )

    DisconnectList(
        AttackConnections
    )

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

    if
        ENV.CAFEINA_WEAPON_LAB_V4
        == Runtime
    then

        ENV.CAFEINA_WEAPON_LAB_V4 =
            nil
    end

    print(
        "[CAFEÍNA] Weapon Lab V4 encerrado"
    )
end

Runtime.Shutdown =
    Shutdown

Connect(
    Close.Activated,
    Shutdown
)

--===================================================================
-- INITIALIZE
--===================================================================

InstallCameraLock()

local hookOK =
    InstallBlasterHooks()

if hookOK then

    Status.Text =
        "BLASTER CONTROLLER CONECTADO"

    Status.TextColor3 =
        COLORS.GREEN

else

    Status.Text =
        "FALLBACK DE CÂMERA ATIVO"

    Status.TextColor3 =
        COLORS.MUTED
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
    "[CAFEÍNA] Weapon Lab V4 carregado"
)
