--[[
==============================================================
CAFEÍNA • WALL / HITSCAN RESEARCH SCANNER V5
==============================================================

FOCO:
  castRays
  canPierce
  canDamageTarget
  canPlayerDamageTarget
  Caster
  FastCastRedux
  Raycast
  Hitscan
  Weapon attributes
  MuzzleAttachment
  BulletTrail
  BulletImpact
  Remotes relacionados a tiro/dano

SEGURANÇA:
  - NÃO FireServer()
  - NÃO InvokeServer()
  - NÃO altera armas
  - NÃO altera partes
  - NÃO altera raycast do jogo
  - somente observa informações visíveis ao cliente
==============================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local Workspace =
    game:GetService("Workspace")

local RunService =
    game:GetService("RunService")

local HttpService =
    game:GetService("HttpService")

local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    Scanner =
        "CAFEINA_WALL_HITSCAN_RESEARCH_V5",

    Version =
        "5.0",

    -- limite aproximado do JSON
    MaxBytes =
        35 * 1024 * 1024,

    -- máximo de registros
    MaxRecords =
        80000,

    -- frequência de atualização
    PassInterval =
        0.20,

    -- análise de parede
    GeometryInterval =
        0.25,

    -- máximo de objetos encontrados
    -- na mesma direção
    GeometryDepth =
        6,

    GeometryDistance =
        1200,

    EffectWindow =
        0.20,

    -- atributos importantes
    WeaponAttributes = {

        "_ammo",

        "_reloading",

        "damage",

        "range",

        "spread",

        "rayRadius",

        "raysPerShot",

        "rateOfFire",

        "fireMode",

        "projectileType",

        "magazineSize",

        "reloadTime",

        "reloadType",

        "explosionRadius",

        "tracerEffectName",

        "beamEffectName",

        "impactEffectName",

        "impactSoundEffectName"
    }
}

--==============================================================
-- STATE
--==============================================================

local STATE = {

    Running = false,

    Started = false,

    Pass = 0,

    Shots = 0,

    GeometryScans = 0,

    Records = {},

    Connections = {},

    Weapons = {},

    Remotes = {},

    Modules = {},

    Effects = 0,

    ApproxBytes = 0,

    LastShotTime = 0
}

--==============================================================
-- HELPERS
--==============================================================

local function now()

    return os.clock()

end


local function safePath(obj)

    if not obj then
        return nil
    end

    local ok, result =
        pcall(function()

            return obj:GetFullName()

        end)

    if ok then
        return result
    end

    return obj.Name

end


local function safeAttributes(obj)

    local result = {}

    local ok, attributes =
        pcall(function()

            return obj:GetAttributes()

        end)

    if not ok then
        return result
    end

    for name, value in pairs(attributes) do

        local valueType =
            typeof(value)

        if
            valueType == "string"
            or valueType == "number"
            or valueType == "boolean"
        then

            result[name] = value

        else

            result[name] =
                tostring(value)

        end
    end

    return result

end


local function serializeVector(v)

    if typeof(v) ~= "Vector3" then
        return nil
    end

    return {

        x = v.X,
        y = v.Y,
        z = v.Z
    }

end


local function serializeCFrame(cf)

    if typeof(cf) ~= "CFrame" then
        return nil
    end

    return {

        position =
            serializeVector(cf.Position),

        look =
            serializeVector(cf.LookVector)
    }

end


local function addRecord(record)

    if not STATE.Running then
        return
    end

    if #STATE.Records >= CONFIG.MaxRecords then

        STATE.Running = false

        return
    end

    record.time =
        record.time or now()

    table.insert(
        STATE.Records,
        record
    )

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(record)

        end)

    if ok then

        STATE.ApproxBytes +=
            #encoded

    end

    if
        STATE.ApproxBytes
        >= CONFIG.MaxBytes
    then

        STATE.Running = false

    end
end

--==============================================================
-- CAMERA
--==============================================================

local function cameraSnapshot()

    local camera =
        Workspace.CurrentCamera

    if not camera then
        return nil
    end

    return {

        cframe =
            serializeCFrame(
                camera.CFrame
            ),

        fov =
            camera.FieldOfView,

        cameraType =
            tostring(
                camera.CameraType
            )
    }

end

--==============================================================
-- WEAPON DETECTION
--==============================================================

local IMPORTANT = {}

for _, name in ipairs(
    CONFIG.WeaponAttributes
) do

    IMPORTANT[name] = true

end


local function looksLikeWeapon(tool)

    if not tool:IsA("Tool") then
        return false
    end

    local attrs =
        tool:GetAttributes()

    if
        attrs.damage
        or attrs.range
        or attrs._ammo
        or attrs.magazineSize
        or attrs.rateOfFire
        or attrs.projectileType
    then

        return true
    end

    if
        tool:FindFirstChild(
            "Model",
            true
        )
    then

        if
            tool:FindFirstChild(
                "MuzzleAttachment",
                true
            )
        then

            return true
        end
    end

    return false

end


local function weaponSnapshot(tool)

    return {

        name =
            tool.Name,

        path =
            safePath(tool),

        attributes =
            safeAttributes(tool)
    }

end

--==============================================================
-- SHOT DETECTION
--==============================================================

local function findMuzzle(tool)

    if not tool then
        return nil
    end

    for _, obj in ipairs(
        tool:GetDescendants()
    ) do

        if
            obj:IsA("Attachment")
            and string.lower(obj.Name)
                :find("muzzle")
        then

            return obj
        end
    end

    return nil

end


local function recordShot(
    tool,
    oldAmmo,
    newAmmo
)

    STATE.Shots += 1

    STATE.LastShotTime =
        now()

    local muzzle =
        findMuzzle(tool)

    local muzzleData = nil

    if muzzle then

        muzzleData = {

            name =
                muzzle.Name,

            path =
                safePath(muzzle),

            cframe =
                serializeCFrame(
                    muzzle.WorldCFrame
                )
        }
    end

    addRecord({

        kind =
            "shot_candidate",

        shotId =
            STATE.Shots,

        reason =
            "ammo_decrease",

        weapon =
            tool.Name,

        oldAmmo =
            oldAmmo,

        newAmmo =
            newAmmo,

        muzzle =
            muzzleData,

        camera =
            cameraSnapshot(),

        weaponAttributes =
            safeAttributes(tool)
    })
end

--==============================================================
-- WEAPON WATCHER
--==============================================================

local function watchWeapon(tool)

    if STATE.Weapons[tool] then
        return
    end

    if not looksLikeWeapon(tool) then
        return
    end

    STATE.Weapons[tool] = true

    addRecord({

        kind =
            "weapon_detected",

        weapon =
            weaponSnapshot(tool)
    })

    local previous = {}

    for name, value in pairs(
        tool:GetAttributes()
    ) do

        previous[name] = value

    end

    for _, attributeName in ipairs(
        CONFIG.WeaponAttributes
    ) do

        local connection =
            tool:GetAttributeChangedSignal(
                attributeName
            ):Connect(function()

                if not STATE.Running then
                    return
                end

                local oldValue =
                    previous[
                        attributeName
                    ]

                local newValue =
                    tool:GetAttribute(
                        attributeName
                    )

                previous[
                    attributeName
                ] =
                    newValue

                addRecord({

                    kind =
                        "weapon_attribute_change",

                    weapon =
                        tool.Name,

                    attribute =
                        attributeName,

                    oldValue =
                        oldValue,

                    value =
                        newValue
                })

                if
                    attributeName
                    == "_ammo"
                    and
                    typeof(oldValue)
                    == "number"
                    and
                    typeof(newValue)
                    == "number"
                    and
                    newValue < oldValue
                then

                    recordShot(
                        tool,
                        oldValue,
                        newValue
                    )
                end
            end)

        table.insert(
            STATE.Connections,
            connection
        )
    end
end

--==============================================================
-- SCAN PLAYER TOOLS
--==============================================================

local function scanTools()

    local character =
        LocalPlayer.Character

    if character then

        for _, child in ipairs(
            character:GetChildren()
        ) do

            if child:IsA("Tool") then

                watchWeapon(child)

            end
        end
    end

    local backpack =
        LocalPlayer:FindFirstChild(
            "Backpack"
        )

    if backpack then

        for _, child in ipairs(
            backpack:GetChildren()
        ) do

            if child:IsA("Tool") then

                watchWeapon(child)

            end
        end
    end
end

--==============================================================
-- MODULE RESEARCH
--==============================================================

local MODULE_WORDS = {

    "cast",

    "ray",

    "pierce",

    "damage",

    "blaster",

    "bullet",

    "projectile",

    "fastcast",

    "caster",

    "weapon",

    "hit"
}


local function moduleRelevant(obj)

    if not obj:IsA("ModuleScript") then
        return false
    end

    local text =
        string.lower(
            obj.Name
            .. " "
            .. safePath(obj)
        )

    for _, word in ipairs(
        MODULE_WORDS
    ) do

        if text:find(
            word,
            1,
            true
        ) then

            return true
        end
    end

    return false

end


local function scanModules()

    for _, obj in ipairs(
        ReplicatedStorage:GetDescendants()
    ) do

        if
            moduleRelevant(obj)
            and
            not STATE.Modules[obj]
        then

            STATE.Modules[obj] = true

            addRecord({

                kind =
                    "combat_module",

                name =
                    obj.Name,

                class =
                    obj.ClassName,

                path =
                    safePath(obj),

                attributes =
                    safeAttributes(obj)
            })
        end
    end
end

--==============================================================
-- REMOTE RESEARCH
--==============================================================

local REMOTE_WORDS = {

    "damage",

    "hit",

    "shoot",

    "fire",

    "weapon",

    "bullet",

    "projectile",

    "ray",

    "cast",

    "blaster",

    "combat",

    "impact"
}


local function remoteRelevant(obj)

    if
        not obj:IsA("RemoteEvent")
        and
        not obj:IsA(
            "RemoteFunction"
        )
        and
        not obj:IsA(
            "UnreliableRemoteEvent"
        )
    then

        return false
    end

    local text =
        string.lower(
            obj.Name
            .. " "
            .. safePath(obj)
        )

    for _, word in ipairs(
        REMOTE_WORDS
    ) do

        if text:find(
            word,
            1,
            true
        ) then

            return true
        end
    end

    return false

end


local function scanRemotes()

    for _, obj in ipairs(
        ReplicatedStorage:GetDescendants()
    ) do

        if
            remoteRelevant(obj)
            and
            not STATE.Remotes[obj]
        then

            STATE.Remotes[obj] = true

            addRecord({

                kind =
                    "combat_remote",

                name =
                    obj.Name,

                class =
                    obj.ClassName,

                path =
                    safePath(obj),

                attributes =
                    safeAttributes(obj)
            })
        end
    end
end

--==============================================================
-- EFFECT RESEARCH
--==============================================================

local EFFECT_WORDS = {

    "bullet",

    "impact",

    "trail",

    "beam",

    "shoot",

    "hit",

    "muzzle"
}


local function relevantEffect(obj)

    local lower =
        string.lower(
            obj.Name
        )

    for _, word in ipairs(
        EFFECT_WORDS
    ) do

        if lower:find(
            word,
            1,
            true
        ) then

            return word
        end
    end

    return nil

end


local function watchWorkspace()

    local connection =
        Workspace.DescendantAdded
        :Connect(function(obj)

            if not STATE.Running then
                return
            end

            local match =
                relevantEffect(obj)

            if not match then
                return
            end

            STATE.Effects += 1

            addRecord({

                kind =
                    "combat_effect",

                id =
                    STATE.Effects,

                name =
                    obj.Name,

                class =
                    obj.ClassName,

                path =
                    safePath(obj),

                match =
                    match,

                nearShot =
                    (
                        now()
                        -
                        STATE.LastShotTime
                    )
                    <=
                    CONFIG.EffectWindow,

                attributes =
                    safeAttributes(obj)
            })
        end)

    table.insert(
        STATE.Connections,
        connection
    )
end

--==============================================================
-- GEOMETRY / WALL RESEARCH
--==============================================================

local function describeHit(
    result,
    index
)

    local instance =
        result.Instance

    local data = {

        index =
            index,

        distance =
            result.Distance,

        position =
            serializeVector(
                result.Position
            ),

        normal =
            serializeVector(
                result.Normal
            ),

        material =
            tostring(
                result.Material
            )
    }

    if instance then

        data.instance = {

            name =
                instance.Name,

            class =
                instance.ClassName,

            path =
                safePath(instance),

            attributes =
                safeAttributes(instance)
        }

        if instance:IsA(
            "BasePart"
        ) then

            data.instance.part = {

                transparency =
                    instance.Transparency,

                canCollide =
                    instance.CanCollide,

                canQuery =
                    instance.CanQuery,

                canTouch =
                    instance.CanTouch,

                anchored =
                    instance.Anchored,

                material =
                    tostring(
                        instance.Material
                    ),

                size =
                    serializeVector(
                        instance.Size
                    ),

                position =
                    serializeVector(
                        instance.Position
                    ),

                collisionGroup =
                    instance.CollisionGroup
            }
        end
    end

    return data

end


local function geometryProbe()

    local camera =
        Workspace.CurrentCamera

    if not camera then
        return
    end

    STATE.GeometryScans += 1

    local origin =
        camera.CFrame.Position

    local direction =
        camera.CFrame.LookVector

    local remaining =
        CONFIG.GeometryDistance

    local ignore = {}

    if LocalPlayer.Character then

        table.insert(
            ignore,
            LocalPlayer.Character
        )

    end

    local hits = {}

    for index = 1,
        CONFIG.GeometryDepth
    do

        if remaining <= 0 then
            break
        end

        local params =
            RaycastParams.new()

        params.FilterType =
            Enum.RaycastFilterType.Exclude

        params.FilterDescendantsInstances =
            ignore

        params.IgnoreWater =
            false

        local result =
            Workspace:Raycast(

                origin,

                direction
                    * remaining,

                params
            )

        if not result then
            break
        end

        table.insert(
            hits,
            describeHit(
                result,
                index
            )
        )

        local hitInstance =
            result.Instance

        if hitInstance then

            table.insert(
                ignore,
                hitInstance
            )

        end

        local travelled =
            (
                result.Position
                -
                origin
            ).Magnitude

        remaining -=
            travelled + 0.05

        origin =
            result.Position
            +
            direction * 0.05
    end

    addRecord({

        kind =
            "wall_geometry_probe",

        scanId =
            STATE.GeometryScans,

        nearShot =
            (
                now()
                -
                STATE.LastShotTime
            )
            <=
            CONFIG.EffectWindow,

        camera =
            cameraSnapshot(),

        hitCount =
            #hits,

        hits =
            hits
    })
end

--==============================================================
-- CHARACTER / BACKPACK LISTENERS
--==============================================================

local function watchContainer(container)

    if not container then
        return
    end

    local connection =
        container.ChildAdded
        :Connect(function(child)

            if child:IsA("Tool") then

                task.defer(function()

                    watchWeapon(child)

                end)
            end
        end)

    table.insert(
        STATE.Connections,
        connection
    )
end


local function setupPlayerWatchers()

    watchContainer(
        LocalPlayer:FindFirstChild(
            "Backpack"
        )
    )

    if LocalPlayer.Character then

        watchContainer(
            LocalPlayer.Character
        )

    end

    local characterConnection =
        LocalPlayer.CharacterAdded
        :Connect(function(character)

            watchContainer(
                character
            )

            task.wait(1)

            scanTools()
        end)

    table.insert(
        STATE.Connections,
        characterConnection
    )
end

--==============================================================
-- MAIN PASS
--==============================================================

local lastGeometry = 0

local function researchPass()

    STATE.Pass += 1

    scanTools()

    if
        STATE.Pass == 1
        or
        STATE.Pass % 20 == 0
    then

        scanModules()
        scanRemotes()

    end

    local t =
        now()

    if
        t - lastGeometry
        >=
        CONFIG.GeometryInterval
    then

        lastGeometry = t

        geometryProbe()
    end

    if
        STATE.Pass % 10
        == 0
    then

        local currentWeapon = nil

        for weapon in pairs(
            STATE.Weapons
        ) do

            if
                weapon.Parent
                and
                weapon:IsDescendantOf(
                    game
                )
            then

                currentWeapon =
                    weapon.Name

                break
            end
        end

        addRecord({

            kind =
                "pass_summary",

            pass =
                STATE.Pass,

            records =
                #STATE.Records,

            approxBytes =
                STATE.ApproxBytes,

            shots =
                STATE.Shots,

            geometryScans =
                STATE.GeometryScans,

            remotes =
                table.maxn
                and nil
                or nil,

            weapon =
                currentWeapon,

            camera =
                cameraSnapshot()
        })
    end
end

--==============================================================
-- START / STOP
--==============================================================

local function disconnectAll()

    for _, connection in ipairs(
        STATE.Connections
    ) do

        pcall(function()

            connection:Disconnect()

        end)
    end

    table.clear(
        STATE.Connections
    )
end


local function startScanner()

    if STATE.Running then
        return
    end

    STATE.Running = true
    STATE.Started = true

    addRecord({

        kind =
            "session_start",

        scanner =
            CONFIG.Scanner,

        version =
            CONFIG.Version,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        focus =
            "hitscan_wall_penetration_research",

        clientVisibleOnly =
            true,

        safety = {

            firesRemotes =
                false,

            invokesRemoteFunctions =
                false,

            mutatesGameObjects =
                false,

            observationalRaycastsOnly =
                true
        }
    })

    scanModules()
    scanRemotes()
    scanTools()

    setupPlayerWatchers()
    watchWorkspace()

    task.spawn(function()

        while STATE.Running do

            local ok, err =
                pcall(
                    researchPass
                )

            if not ok then

                addRecord({

                    kind =
                        "scanner_error",

                    message =
                        tostring(err)
                })
            end

            task.wait(
                CONFIG.PassInterval
            )
        end
    end)
end


local function stopScanner()

    if not STATE.Running then
        return
    end

    addRecord({

        kind =
            "session_stop",

        passes =
            STATE.Pass,

        shots =
            STATE.Shots,

        geometryScans =
            STATE.GeometryScans,

        records =
            #STATE.Records,

        approxBytes =
            STATE.ApproxBytes
    })

    STATE.Running = false

    disconnectAll()
end

--==============================================================
-- EXPORT
--==============================================================

local function buildExport()

    return {

        cafeina = {

            scanner =
                CONFIG.Scanner,

            version =
                CONFIG.Version,

            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            records =
                #STATE.Records,

            passes =
                STATE.Pass,

            shots =
                STATE.Shots,

            geometryScans =
                STATE.GeometryScans,

            approxBytes =
                STATE.ApproxBytes
        },

        records =
            STATE.Records
    }
end


local function exportJSON()

    local ok, json =
        pcall(function()

            return HttpService:JSONEncode(
                buildExport()
            )

        end)

    if not ok then

        return nil,
            tostring(json)

    end

    if setclipboard then

        pcall(function()

            setclipboard(json)

        end)
    end

    return json
end

--==============================================================
-- UI
--==============================================================

local old =
    PlayerGui:FindFirstChild(
        "CafeinaWallScannerV5"
    )

if old then
    old:Destroy()
end


local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "CafeinaWallScannerV5"

Gui.ResetOnSpawn =
    false

Gui.Parent =
    PlayerGui


local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        330,
        190
    )

Main.Position =
    UDim2.new(
        0.5,
        -165,
        0.16,
        0
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        16,
        16,
        18
    )

Main.BorderSizePixel =
    0

Main.Active =
    true

Main.Draggable =
    true

Main.Parent =
    Gui


local Corner =
    Instance.new(
        "UICorner"
    )

Corner.CornerRadius =
    UDim.new(
        0,
        10
    )

Corner.Parent =
    Main


local Title =
    Instance.new(
        "TextLabel"
    )

Title.Size =
    UDim2.new(
        1,
        -20,
        0,
        30
    )

Title.Position =
    UDim2.fromOffset(
        10,
        8
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "CAFEÍNA • HITSCAN RESEARCH V5"

Title.TextColor3 =
    Color3.new(
        1,
        1,
        1
    )

Title.TextSize =
    15

Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Main


local Status =
    Instance.new(
        "TextLabel"
    )

Status.Size =
    UDim2.new(
        1,
        -20,
        0,
        42
    )

Status.Position =
    UDim2.fromOffset(
        10,
        40
    )

Status.BackgroundTransparency =
    1

Status.Text =
    "Pronto"

Status.TextWrapped =
    true

Status.TextColor3 =
    Color3.fromRGB(
        200,
        200,
        200
    )

Status.TextSize =
    13

Status.Font =
    Enum.Font.Gotham

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.Parent =
    Main


local function createButton(
    text,
    x,
    width
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.fromOffset(
            width,
            40
        )

    button.Position =
        UDim2.fromOffset(
            x,
            92
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            35,
            35,
            39
        )

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        Color3.new(
            1,
            1,
            1
        )

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        12

    button.Parent =
        Main

    local c =
        Instance.new(
            "UICorner"
        )

    c.CornerRadius =
        UDim.new(
            0,
            7
        )

    c.Parent =
        button

    return button
end


local StartButton =
    createButton(
        "INICIAR",
        10,
        95
    )


local StopButton =
    createButton(
        "INTERROMPER",
        115,
        100
    )


local CopyButton =
    createButton(
        "COPIAR JSON",
        225,
        95
    )


local Stats =
    Instance.new(
        "TextLabel"
    )

Stats.Size =
    UDim2.new(
        1,
        -20,
        0,
        42
    )

Stats.Position =
    UDim2.fromOffset(
        10,
        140
    )

Stats.BackgroundTransparency =
    1

Stats.TextColor3 =
    Color3.fromRGB(
        170,
        170,
        170
    )

Stats.TextSize =
    12

Stats.Font =
    Enum.Font.Code

Stats.TextXAlignment =
    Enum.TextXAlignment.Left

Stats.Parent =
    Main

--==============================================================
-- BUTTONS
--==============================================================

StartButton.MouseButton1Click
:Connect(function()

    startScanner()

    Status.Text =
        "Analisando hitscan, paredes, armas e remotes..."

end)


StopButton.MouseButton1Click
:Connect(function()

    stopScanner()

    Status.Text =
        "Scanner interrompido • pronto para exportar"

end)


CopyButton.MouseButton1Click
:Connect(function()

    local json, err =
        exportJSON()

    if json then

        Status.Text =
            "JSON copiado • "
            ..
            tostring(
                #json
            )
            ..
            " bytes"

    else

        Status.Text =
            "Erro: "
            ..
            tostring(err)

    end
end)

--==============================================================
-- LIVE STATUS
--==============================================================

task.spawn(function()

    while Gui.Parent do

        Stats.Text =
            string.format(

                "Passes: %d  |  Tiros: %d\nGeometria: %d  |  Registros: %d",

                STATE.Pass,

                STATE.Shots,

                STATE.GeometryScans,

                #STATE.Records
            )

        task.wait(
            0.3
        )
    end
end)

print(
    "[CAFEÍNA] Wall / Hitscan Research Scanner V5 carregado"
)
