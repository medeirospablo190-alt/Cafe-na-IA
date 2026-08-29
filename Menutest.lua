--[[
=====================================================================
CAFEÍNA • WEAPON / HITSCAN RESEARCH SCANNER V6
=====================================================================

FOCO:
  • Estrutura completa visível ao cliente
  • Armas / Tools
  • Hitscan
  • castRays / canPierce / damage
  • BlasterSystem
  • Caster / FastCast
  • Remotes de combate
  • MuzzleAttachment
  • BulletTrail / BulletImpact
  • Alterações de munição / reload
  • Geometria / paredes / CanQuery / CollisionGroup
  • Eventos recebidos de remotes de combate
  • Objetos novos durante os tiros

BOTÕES:
  [ INICIAR / RETOMAR ]
  [ PAUSAR ]
  [ ENVIAR TUDO ]

UPLOAD:
  https://cafe-na-ia.onrender.com

  POST /upload/start
  POST /upload/chunk
  POST /upload/finish

IMPORTANTE:
  • Não FireServer()
  • Não InvokeServer()
  • Não altera armas
  • Não altera paredes
  • Não altera raycast do jogo
  • Somente observa o que está disponível ao cliente
=====================================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local HttpService =
    game:GetService("HttpService")

local UserInputService =
    game:GetService("UserInputService")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local ReplicatedFirst =
    game:GetService("ReplicatedFirst")

local Workspace =
    game:GetService("Workspace")

local Lighting =
    game:GetService("Lighting")

local StarterGui =
    game:GetService("StarterGui")

local StarterPack =
    game:GetService("StarterPack")

local CollectionService =
    game:GetService("CollectionService")

local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    SCANNER =
        "CAFEINA_WEAPON_WALL_RESEARCH_V6",

    VERSION =
        "6.0",

    API_BASE =
        "https://cafe-na-ia.onrender.com",

    -- deixe vazio enquanto o backend não exigir token
    UPLOAD_TOKEN =
        "",

    -- servidor suporta 300 MiB.
    -- scanner usa margem segura.
    MAX_TOTAL_BYTES =
        250 * 1024 * 1024,

    -- backend aceita aproximadamente 6 MiB/request
    CHUNK_TARGET_BYTES =
        3500000,

    CHUNK_HARD_BYTES =
        5400000,

    MEMORY_FALLBACK_LIMIT =
        64 * 1024 * 1024,

    UPLOAD_RETRIES =
        4,

    RETRY_DELAY =
        1.25,

    -- velocidade do scanner
    PASS_INTERVAL =
        0.70,

    YIELD_EVERY =
        150,

    MAX_OBJECTS_PER_PASS =
        350000,

    -- geometria
    GEOMETRY_INTERVAL =
        0.22,

    GEOMETRY_DISTANCE =
        1200,

    GEOMETRY_DEPTH =
        7,

    EFFECT_SHOT_WINDOW =
        0.35,

    -- eventos dinâmicos
    MAX_REMOTE_ARGS =
        16,

    MAX_STRING =
        1500
}

--==============================================================
-- EXECUTOR API
--==============================================================

local requestFn =
    (syn and syn.request)
    or http_request
    or request
    or (http and http.request)

local writefileFn =
    writefile

local readfileFn =
    readfile

local makefolderFn =
    makefolder

local isfolderFn =
    isfolder

local isfileFn =
    isfile

local delfileFn =
    delfile

local CAN_USE_FILES =
    type(writefileFn) == "function"
    and type(readfileFn) == "function"

--==============================================================
-- STATE
--==============================================================

local STATE = {

    running = false,
    paused = false,
    started = false,
    uploading = false,
    uploaded = false,

    generation = 0,

    passes = 0,
    records = 0,
    bytes = 0,

    shots = 0,
    geometry = 0,
    effects = 0,
    remoteEvents = 0,

    currentChunk = {},
    currentChunkBytes = 2,

    diskChunks = {},
    memoryChunks = {},

    seen = {},
    weapons = {},
    remotes = {},
    connections = {},

    lastShotTime = 0,
    lastGeometry = 0,

    sessionFolder = nil,
    lastLink = nil
}

--==============================================================
-- HELPERS
--==============================================================

local function readableSize(bytes)

    bytes =
        tonumber(bytes) or 0

    if bytes >= 1024 * 1024 then

        return string.format(
            "%.1f MB",
            bytes / 1024 / 1024
        )

    elseif bytes >= 1024 then

        return string.format(
            "%.1f KB",
            bytes / 1024
        )
    end

    return tostring(bytes) .. " B"
end


local function safeString(value, limit)

    limit =
        limit or CONFIG.MAX_STRING

    local text =
        tostring(value or "")

    if #text > limit then
        return text:sub(1, limit)
    end

    return text
end


local function safePath(obj)

    if not obj then
        return ""
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


local function vector3(v)

    if typeof(v) ~= "Vector3" then
        return nil
    end

    return {
        x = v.X,
        y = v.Y,
        z = v.Z
    }
end


local function vector2(v)

    if typeof(v) ~= "Vector2" then
        return nil
    end

    return {
        x = v.X,
        y = v.Y
    }
end


local function cframeInfo(cf)

    if typeof(cf) ~= "CFrame" then
        return nil
    end

    return {
        position =
            vector3(cf.Position),

        look =
            vector3(cf.LookVector),

        right =
            vector3(cf.RightVector),

        up =
            vector3(cf.UpVector)
    }
end


local function serializeValue(value, depth)

    depth =
        depth or 0

    if depth > 5 then
        return "[depth-limit]"
    end

    local valueType =
        typeof(value)

    if
        valueType == "nil"
    then

        return nil

    elseif
        valueType == "string"
        or valueType == "number"
        or valueType == "boolean"
    then

        return value

    elseif valueType == "Vector3" then

        return vector3(value)

    elseif valueType == "Vector2" then

        return vector2(value)

    elseif valueType == "CFrame" then

        return cframeInfo(value)

    elseif valueType == "Color3" then

        return {
            r = value.R,
            g = value.G,
            b = value.B
        }

    elseif valueType == "Instance" then

        return {
            instance = true,
            name = value.Name,
            class = value.ClassName,
            path = safePath(value)
        }

    elseif valueType == "EnumItem" then

        return tostring(value)

    elseif valueType == "table" then

        local output = {}
        local count = 0

        for key, item in pairs(value) do

            count += 1

            if count > 50 then
                break
            end

            output[
                safeString(key, 100)
            ] =
                serializeValue(
                    item,
                    depth + 1
                )
        end

        return output
    end

    return safeString(value, 800)
end


local function attributes(obj)

    local result = {}

    local ok, attrs =
        pcall(function()
            return obj:GetAttributes()
        end)

    if not ok then
        return result
    end

    local count = 0

    for name, value in pairs(attrs) do

        count += 1

        if count > 100 then
            break
        end

        result[
            safeString(name, 120)
        ] =
            serializeValue(value)
    end

    return result
end


local function tags(obj)

    local ok, list =
        pcall(function()
            return CollectionService:GetTags(obj)
        end)

    if ok then
        return list
    end

    return {}
end

--==============================================================
-- SESSION STORAGE
--==============================================================

local function createSessionFolder()

    STATE.sessionFolder =
        "CafeinaWeaponScan_"
        .. tostring(os.time())

    if not CAN_USE_FILES then
        return
    end

    if
        type(makefolderFn) == "function"
    then

        pcall(
            makefolderFn,
            STATE.sessionFolder
        )
    end
end


local function memoryBytes()

    local total = 0

    for _, item in ipairs(
        STATE.memoryChunks
    ) do

        total += item.bytes or 0
    end

    return total
end


local function flushChunk()

    if #STATE.currentChunk == 0 then
        return true
    end

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                STATE.currentChunk
            )

        end)

    if not ok then
        return false,
            "erro ao serializar bloco"
    end

    local index =
        #STATE.diskChunks
        + #STATE.memoryChunks
        + 1

    if CAN_USE_FILES then

        local path =
            STATE.sessionFolder
            .. "/chunk_"
            .. string.format(
                "%06d",
                index
            )
            .. ".json"

        local saved =
            pcall(
                writefileFn,
                path,
                encoded
            )

        if saved then

            table.insert(
                STATE.diskChunks,
                path
            )

        else

            table.insert(
                STATE.memoryChunks,
                {
                    objects =
                        STATE.currentChunk,

                    bytes =
                        #encoded
                }
            )
        end

    else

        if
            memoryBytes()
            + #encoded
            >
            CONFIG.MEMORY_FALLBACK_LIMIT
        then

            return false,
                "limite de memória do executor"
        end

        table.insert(
            STATE.memoryChunks,
            {
                objects =
                    STATE.currentChunk,

                bytes =
                    #encoded
            }
        )
    end

    STATE.currentChunk = {}
    STATE.currentChunkBytes = 2

    return true
end

--==============================================================
-- RECORDING
--==============================================================

local function recordSignature(record)

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                record
            )

        end)

    if ok then
        return encoded
    end

    return tostring(record.kind)
        .. "|"
        .. tostring(record.path)
end


local function addRecord(
    record,
    dedupeKey,
    force
)

    if
        STATE.bytes
        >= CONFIG.MAX_TOTAL_BYTES
    then

        return false,
            "LIMIT_REACHED"
    end

    record.time =
        record.time
        or os.clock()

    record.unix =
        record.unix
        or os.time()

    if
        dedupeKey
        and not force
    then

        local sig =
            recordSignature(record)

        if
            STATE.seen[dedupeKey]
            == sig
        then

            return true,
                false
        end

        STATE.seen[dedupeKey] =
            sig
    end

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                record
            )

        end)

    if not ok then
        return true,
            false
    end

    local size =
        #encoded + 1

    if size >
        CONFIG.CHUNK_HARD_BYTES
    then

        return true,
            false
    end

    if
        STATE.currentChunkBytes
        + size
        >
        CONFIG.CHUNK_TARGET_BYTES
    then

        local flushed, err =
            flushChunk()

        if not flushed then
            return false, err
        end
    end

    if
        STATE.bytes
        + size
        >
        CONFIG.MAX_TOTAL_BYTES
    then

        return false,
            "LIMIT_REACHED"
    end

    table.insert(
        STATE.currentChunk,
        record
    )

    STATE.currentChunkBytes +=
        size

    STATE.records += 1
    STATE.bytes += size

    return true, true
end

--==============================================================
-- PROPERTIES
--==============================================================

local function objectProperties(obj)

    local p = {}

    if obj:IsA("BasePart") then

        p.position =
            vector3(obj.Position)

        p.size =
            vector3(obj.Size)

        p.transparency =
            obj.Transparency

        p.canCollide =
            obj.CanCollide

        p.canQuery =
            obj.CanQuery

        p.canTouch =
            obj.CanTouch

        p.anchored =
            obj.Anchored

        p.material =
            tostring(obj.Material)

        p.collisionGroup =
            obj.CollisionGroup

        p.massless =
            obj.Massless

    elseif obj:IsA("Tool") then

        p.requiresHandle =
            obj.RequiresHandle

        p.canBeDropped =
            obj.CanBeDropped

    elseif obj:IsA("Attachment") then

        p.worldPosition =
            vector3(
                obj.WorldPosition
            )

        p.worldCFrame =
            cframeInfo(
                obj.WorldCFrame
            )

    elseif obj:IsA("Sound") then

        p.soundId =
            obj.SoundId

        p.volume =
            obj.Volume

        p.playbackSpeed =
            obj.PlaybackSpeed

        p.playing =
            obj.Playing

    elseif obj:IsA("Trail") then

        p.enabled =
            obj.Enabled

        p.lifetime =
            obj.Lifetime

        p.minLength =
            obj.MinLength

    elseif obj:IsA("Beam") then

        p.enabled =
            obj.Enabled

        p.width0 =
            obj.Width0

        p.width1 =
            obj.Width1

    elseif obj:IsA("RemoteEvent")
        or obj:IsA(
            "UnreliableRemoteEvent"
        )
        or obj:IsA(
            "RemoteFunction"
        )
    then

        p.remoteType =
            obj.ClassName

    elseif obj:IsA("ModuleScript") then

        p.module =
            true

    elseif obj:IsA("Player") then

        p.userId =
            obj.UserId

        p.displayName =
            obj.DisplayName
    end

    return p
end

--==============================================================
-- COMBAT CLASSIFICATION
--==============================================================

local COMBAT_WORDS = {

    "weapon",
    "gun",
    "blaster",
    "bullet",
    "projectile",
    "hit",
    "damage",
    "shoot",
    "fire",
    "ray",
    "cast",
    "fastcast",
    "caster",
    "pierce",
    "penetr",
    "impact",
    "trail",
    "muzzle",
    "reload",
    "ammo"
}


local function combatReason(obj)

    local text =
        string.lower(
            obj.Name
            .. " "
            .. safePath(obj)
        )

    for _, word in ipairs(
        COMBAT_WORDS
    ) do

        if text:find(
            word,
            1,
            true
        ) then

            return word
        end
    end

    return nil
end


local function snapshot(obj)

    local reason =
        combatReason(obj)

    return {

        kind =
            reason
            and "combat_object"
            or "object",

        priority =
            reason ~= nil,

        combatMatch =
            reason,

        path =
            safePath(obj),

        parentPath =
            obj.Parent
            and safePath(obj.Parent)
            or "",

        name =
            obj.Name,

        class =
            obj.ClassName,

        childCount =
            #obj:GetChildren(),

        attributes =
            attributes(obj),

        tags =
            tags(obj),

        properties =
            objectProperties(obj),

        pass =
            STATE.passes
    }
end

--==============================================================
-- ROOTS
--==============================================================

local function roots()

    return {

        Workspace,
        ReplicatedStorage,
        ReplicatedFirst,
        Players,
        Lighting,
        StarterGui,
        StarterPack
    }
end


local function enumerate()

    local output = {}

    for _, root in ipairs(
        roots()
    ) do

        table.insert(
            output,
            root
        )

        local ok, descendants =
            pcall(function()

                return root:GetDescendants()

            end)

        if ok then

            for _, obj in ipairs(
                descendants
            ) do

                table.insert(
                    output,
                    obj
                )

                if
                    #output
                    >=
                    CONFIG.MAX_OBJECTS_PER_PASS
                then

                    return output
                end
            end
        end
    end

    return output
end

--==============================================================
-- WEAPON WATCHER
--==============================================================

local function looksLikeWeapon(tool)

    if not tool:IsA("Tool") then
        return false
    end

    local attrs =
        tool:GetAttributes()

    if
        attrs._ammo ~= nil
        or attrs.damage ~= nil
        or attrs.range ~= nil
        or attrs.rateOfFire ~= nil
        or attrs.magazineSize ~= nil
        or attrs.projectileType ~= nil
    then

        return true
    end

    return
        tool:FindFirstChild(
            "MuzzleAttachment",
            true
        ) ~= nil
end


local function findMuzzle(tool)

    for _, obj in ipairs(
        tool:GetDescendants()
    ) do

        if
            obj:IsA("Attachment")
            and
            string.lower(
                obj.Name
            ):find(
                "muzzle",
                1,
                true
            )
        then

            return obj
        end
    end

    return nil
end


local function cameraInfo()

    local camera =
        Workspace.CurrentCamera

    if not camera then
        return nil
    end

    return {

        cframe =
            cframeInfo(
                camera.CFrame
            ),

        fov =
            camera.FieldOfView,

        type =
            tostring(
                camera.CameraType
            )
    }
end


local function shotCandidate(
    tool,
    oldAmmo,
    newAmmo
)

    STATE.shots += 1
    STATE.lastShotTime =
        os.clock()

    local muzzle =
        findMuzzle(tool)

    addRecord({

        kind =
            "shot_candidate",

        shotId =
            STATE.shots,

        reason =
            "attribute_ammo_decrease",

        weapon =
            tool.Name,

        weaponPath =
            safePath(tool),

        oldAmmo =
            oldAmmo,

        newAmmo =
            newAmmo,

        attributes =
            attributes(tool),

        muzzle =
            muzzle and {

                path =
                    safePath(muzzle),

                worldPosition =
                    vector3(
                        muzzle.WorldPosition
                    ),

                worldCFrame =
                    cframeInfo(
                        muzzle.WorldCFrame
                    )
            }
            or nil,

        camera =
            cameraInfo()

    }, nil, true)
end


local WATCH_ATTRIBUTES = {

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

    "beamEffectName",
    "tracerEffectName",
    "impactEffectName",
    "impactSoundEffectName"
}


local function watchWeapon(tool)

    if STATE.weapons[tool] then
        return
    end

    if not looksLikeWeapon(tool) then
        return
    end

    STATE.weapons[tool] =
        true

    local previous = {}

    for name, value in pairs(
        tool:GetAttributes()
    ) do

        previous[name] =
            value
    end

    addRecord({

        kind =
            "weapon_detected",

        path =
            safePath(tool),

        name =
            tool.Name,

        attributes =
            attributes(tool),

        properties =
            objectProperties(tool)

    }, nil, true)

    for _, attributeName in ipairs(
        WATCH_ATTRIBUTES
    ) do

        local connection =
            tool:GetAttributeChangedSignal(
                attributeName
            ):Connect(function()

                if not STATE.started then
                    return
                end

                local old =
                    previous[
                        attributeName
                    ]

                local new =
                    tool:GetAttribute(
                        attributeName
                    )

                previous[
                    attributeName
                ] =
                    new

                addRecord({

                    kind =
                        "weapon_attribute_change",

                    weapon =
                        tool.Name,

                    path =
                        safePath(tool),

                    attribute =
                        attributeName,

                    old =
                        serializeValue(old),

                    new =
                        serializeValue(new)

                }, nil, true)

                if
                    attributeName
                    == "_ammo"
                    and
                    typeof(old)
                    == "number"
                    and
                    typeof(new)
                    == "number"
                    and
                    new < old
                then

                    shotCandidate(
                        tool,
                        old,
                        new
                    )
                end
            end)

        table.insert(
            STATE.connections,
            connection
        )
    end
end


local function scanWeapons()

    local backpack =
        LocalPlayer:FindFirstChild(
            "Backpack"
        )

    local character =
        LocalPlayer.Character

    if backpack then

        for _, obj in ipairs(
            backpack:GetChildren()
        ) do

            if obj:IsA("Tool") then
                watchWeapon(obj)
            end
        end
    end

    if character then

        for _, obj in ipairs(
            character:GetChildren()
        ) do

            if obj:IsA("Tool") then
                watchWeapon(obj)
            end
        end
    end
end

--==============================================================
-- REMOTES
--==============================================================

local function isCombatRemote(obj)

    if
        not obj:IsA("RemoteEvent")
        and
        not obj:IsA(
            "UnreliableRemoteEvent"
        )
        and
        not obj:IsA(
            "RemoteFunction"
        )
    then

        return false
    end

    return combatReason(obj) ~= nil
end


local function watchRemote(remote)

    if STATE.remotes[remote] then
        return
    end

    STATE.remotes[remote] =
        true

    addRecord({

        kind =
            "remote_structure",

        path =
            safePath(remote),

        name =
            remote.Name,

        class =
            remote.ClassName,

        attributes =
            attributes(remote)

    }, nil, true)

    -- Apenas eventos servidor -> cliente.
    -- Não dispara nada no servidor.
    if
        remote:IsA("RemoteEvent")
        or remote:IsA(
            "UnreliableRemoteEvent"
        )
    then

        local connection =
            remote.OnClientEvent:
            Connect(function(...)

                if not STATE.started then
                    return
                end

                local raw =
                    {...}

                local args = {}

                for i = 1,
                    math.min(
                        #raw,
                        CONFIG.MAX_REMOTE_ARGS
                    )
                do

                    args[i] =
                        serializeValue(
                            raw[i]
                        )
                end

                STATE.remoteEvents += 1

                addRecord({

                    kind =
                        "remote_client_event",

                    eventId =
                        STATE.remoteEvents,

                    path =
                        safePath(remote),

                    remote =
                        remote.Name,

                    class =
                        remote.ClassName,

                    args =
                        args,

                    nearShot =
                        (
                            os.clock()
                            -
                            STATE.lastShotTime
                        )
                        <=
                        CONFIG.EFFECT_SHOT_WINDOW

                }, nil, true)
            end)

        table.insert(
            STATE.connections,
            connection
        )
    end
end


local function scanRemotes()

    for _, obj in ipairs(
        ReplicatedStorage:GetDescendants()
    ) do

        if isCombatRemote(obj) then
            watchRemote(obj)
        end
    end
end

--==============================================================
-- GEOMETRY RESEARCH
--==============================================================

local function describeHit(
    rayResult,
    index
)

    local obj =
        rayResult.Instance

    local result = {

        index =
            index,

        position =
            vector3(
                rayResult.Position
            ),

        normal =
            vector3(
                rayResult.Normal
            ),

        distance =
            rayResult.Distance,

        material =
            tostring(
                rayResult.Material
            )
    }

    if obj then

        result.object = {

            name =
                obj.Name,

            class =
                obj.ClassName,

            path =
                safePath(obj),

            attributes =
                attributes(obj),

            tags =
                tags(obj),

            properties =
                objectProperties(obj)
        }
    end

    return result
end


local function geometryProbe()

    if not STATE.running then
        return
    end

    local camera =
        Workspace.CurrentCamera

    if not camera then
        return
    end

    local origin =
        camera.CFrame.Position

    local direction =
        camera.CFrame.LookVector

    local ignore = {}

    if LocalPlayer.Character then

        table.insert(
            ignore,
            LocalPlayer.Character
        )
    end

    local hits = {}
    local remaining =
        CONFIG.GEOMETRY_DISTANCE

    for depth = 1,
        CONFIG.GEOMETRY_DEPTH
    do

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
                depth
            )
        )

        if result.Instance then

            table.insert(
                ignore,
                result.Instance
            )
        end

        local traveled =
            (
                result.Position
                - origin
            ).Magnitude

        remaining -=
            traveled + 0.05

        if remaining <= 0 then
            break
        end

        origin =
            result.Position
            +
            direction * 0.05
    end

    STATE.geometry += 1

    addRecord({

        kind =
            "wall_geometry_probe",

        probeId =
            STATE.geometry,

        camera =
            cameraInfo(),

        hitCount =
            #hits,

        hits =
            hits,

        nearShot =
            (
                os.clock()
                -
                STATE.lastShotTime
            )
            <=
            CONFIG.EFFECT_SHOT_WINDOW

    }, nil, true)
end

--==============================================================
-- NEW OBJECT / EFFECT WATCHER
--==============================================================

local function watchWorkspace()

    local connection =
        Workspace.DescendantAdded:
        Connect(function(obj)

            if not STATE.started then
                return
            end

            local match =
                combatReason(obj)

            if not match then
                return
            end

            STATE.effects += 1

            task.defer(function()

                if not obj.Parent then
                    return
                end

                addRecord({

                    kind =
                        "combat_effect",

                    effectId =
                        STATE.effects,

                    match =
                        match,

                    path =
                        safePath(obj),

                    name =
                        obj.Name,

                    class =
                        obj.ClassName,

                    attributes =
                        attributes(obj),

                    properties =
                        objectProperties(obj),

                    nearShot =
                        (
                            os.clock()
                            -
                            STATE.lastShotTime
                        )
                        <=
                        CONFIG.EFFECT_SHOT_WINDOW

                }, nil, true)
            end)
        end)

    table.insert(
        STATE.connections,
        connection
    )
end

--==============================================================
-- TOOL CONTAINERS
--==============================================================

local function watchToolContainer(container)

    if not container then
        return
    end

    local connection =
        container.ChildAdded:
        Connect(function(obj)

            if obj:IsA("Tool") then

                task.defer(function()
                    watchWeapon(obj)
                end)
            end
        end)

    table.insert(
        STATE.connections,
        connection
    )
end


local function setupPlayerWatch()

    watchToolContainer(
        LocalPlayer:FindFirstChild(
            "Backpack"
        )
    )

    watchToolContainer(
        LocalPlayer.Character
    )

    local connection =
        LocalPlayer.CharacterAdded:
        Connect(function(character)

            watchToolContainer(character)

            task.wait(0.5)

            scanWeapons()
        end)

    table.insert(
        STATE.connections,
        connection
    )
end

--==============================================================
-- UI
--==============================================================

local oldGui =
    PlayerGui:FindFirstChild(
        "CafeinaWeaponScannerV6"
    )

if oldGui then
    oldGui:Destroy()
end


local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "CafeinaWeaponScannerV6"

Gui.ResetOnSpawn =
    false

Gui.Parent =
    PlayerGui


local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        342,
        132
    )

Main.Position =
    UDim2.new(
        0.5,
        -171,
        0.13,
        0
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        13,
        13,
        15
    )

Main.BorderSizePixel =
    0

Main.Parent =
    Gui


local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(
        0,
        11
    )

corner.Parent =
    Main


local stroke =
    Instance.new("UIStroke")

stroke.Color =
    Color3.fromRGB(
        55,
        55,
        60
    )

stroke.Parent =
    Main


local function makeButton(
    text,
    x,
    width
)

    local button =
        Instance.new("TextButton")

    button.Size =
        UDim2.fromOffset(
            width,
            34
        )

    button.Position =
        UDim2.fromOffset(
            x,
            8
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            31,
            31,
            35
        )

    button.TextColor3 =
        Color3.fromRGB(
            245,
            245,
            245
        )

    button.Text =
        text

    button.TextSize =
        10

    button.Font =
        Enum.Font.GothamBold

    button.BorderSizePixel =
        0

    button.Parent =
        Main

    local c =
        Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(
            0,
            8
        )

    c.Parent =
        button

    return button
end


local StartButton =
    makeButton(
        "INICIAR",
        8,
        104
    )


local PauseButton =
    makeButton(
        "PAUSAR",
        119,
        100
    )


local SendButton =
    makeButton(
        "ENVIAR TUDO",
        226,
        108
    )


local ScanStatus =
    Instance.new("TextLabel")

ScanStatus.Size =
    UDim2.new(
        1,
        -16,
        0,
        20
    )

ScanStatus.Position =
    UDim2.fromOffset(
        8,
        47
    )

ScanStatus.BackgroundTransparency =
    1

ScanStatus.Text =
    "Pronto para iniciar"

ScanStatus.TextColor3 =
    Color3.fromRGB(
        190,
        190,
        200
    )

ScanStatus.TextSize =
    9

ScanStatus.Font =
    Enum.Font.Gotham

ScanStatus.TextXAlignment =
    Enum.TextXAlignment.Left

ScanStatus.TextTruncate =
    Enum.TextTruncate.AtEnd

ScanStatus.Parent =
    Main


local ProgressBG =
    Instance.new("Frame")

ProgressBG.Size =
    UDim2.new(
        1,
        -16,
        0,
        12
    )

ProgressBG.Position =
    UDim2.fromOffset(
        8,
        76
    )

ProgressBG.BackgroundColor3 =
    Color3.fromRGB(
        35,
        35,
        40
    )

ProgressBG.BorderSizePixel =
    0

ProgressBG.Parent =
    Main


local progressCorner =
    Instance.new("UICorner")

progressCorner.CornerRadius =
    UDim.new(1, 0)

progressCorner.Parent =
    ProgressBG


local Progress =
    Instance.new("Frame")

Progress.Size =
    UDim2.new(
        0,
        0,
        1,
        0
    )

Progress.BackgroundColor3 =
    Color3.fromRGB(
        235,
        235,
        235
    )

Progress.BorderSizePixel =
    0

Progress.Parent =
    ProgressBG


local progressFillCorner =
    Instance.new("UICorner")

progressFillCorner.CornerRadius =
    UDim.new(1, 0)

progressFillCorner.Parent =
    Progress


local UploadText =
    Instance.new("TextLabel")

UploadText.Size =
    UDim2.new(
        1,
        -16,
        0,
        16
    )

UploadText.Position =
    UDim2.fromOffset(
        8,
        93
    )

UploadText.BackgroundTransparency =
    1

UploadText.Text =
    "Upload: aguardando"

UploadText.TextColor3 =
    Color3.fromRGB(
        125,
        125,
        135
    )

UploadText.TextSize =
    8

UploadText.Font =
    Enum.Font.Gotham

UploadText.TextXAlignment =
    Enum.TextXAlignment.Left

UploadText.TextTruncate =
    Enum.TextTruncate.AtEnd

UploadText.Parent =
    Main


local Stats =
    Instance.new("TextLabel")

Stats.Size =
    UDim2.new(
        1,
        -16,
        0,
        14
    )

Stats.Position =
    UDim2.fromOffset(
        8,
        112
    )

Stats.BackgroundTransparency =
    1

Stats.Text =
    "0 MB • 0 registros"

Stats.TextColor3 =
    Color3.fromRGB(
        105,
        105,
        115
    )

Stats.TextSize =
    8

Stats.Font =
    Enum.Font.Code

Stats.TextXAlignment =
    Enum.TextXAlignment.Left

Stats.Parent =
    Main


local function uploadProgress(
    text,
    fraction
)

    fraction =
        math.clamp(
            tonumber(fraction) or 0,
            0,
            1
        )

    UploadText.Text =
        tostring(text or "")

    Progress.Size =
        UDim2.new(
            fraction,
            0,
            1,
            0
        )
end


local function refreshButtons()

    if STATE.uploading then

        StartButton.Text =
            "AGUARDE"

        PauseButton.Text =
            "AGUARDE"

        return
    end

    if STATE.running then

        StartButton.Text =
            "COLETANDO"

    elseif STATE.paused then

        StartButton.Text =
            "RETOMAR"

    else

        StartButton.Text =
            "INICIAR"
    end
end

--==============================================================
-- DRAG MOBILE
--==============================================================

local dragging = false
local dragStart
local startPosition


Main.InputBegan:
Connect(function(input)

    if
        input.UserInputType
        == Enum.UserInputType.Touch
        or
        input.UserInputType
        == Enum.UserInputType.MouseButton1
    then

        dragging = true

        dragStart =
            input.Position

        startPosition =
            Main.Position
    end
end)


UserInputService.InputChanged:
Connect(function(input)

    if not dragging then
        return
    end

    if
        input.UserInputType
        ~= Enum.UserInputType.Touch
        and
        input.UserInputType
        ~= Enum.UserInputType.MouseMovement
    then

        return
    end

    local delta =
        input.Position
        - dragStart

    Main.Position =
        UDim2.new(

            startPosition.X.Scale,
            startPosition.X.Offset
                + delta.X,

            startPosition.Y.Scale,
            startPosition.Y.Offset
                + delta.Y
        )
end)


UserInputService.InputEnded:
Connect(function(input)

    if
        input.UserInputType
        == Enum.UserInputType.Touch
        or
        input.UserInputType
        == Enum.UserInputType.MouseButton1
    then

        dragging =
            false
    end
end)

--==============================================================
-- SCANNER RESET
--==============================================================

local function resetScanner()

    STATE.generation += 1

    STATE.running = false
    STATE.paused = false
    STATE.started = false
    STATE.uploading = false
    STATE.uploaded = false

    STATE.passes = 0
    STATE.records = 0
    STATE.bytes = 0

    STATE.shots = 0
    STATE.geometry = 0
    STATE.effects = 0
    STATE.remoteEvents = 0

    STATE.currentChunk = {}
    STATE.currentChunkBytes = 2

    STATE.diskChunks = {}
    STATE.memoryChunks = {}

    STATE.seen = {}
    STATE.weapons = {}
    STATE.remotes = {}

    STATE.lastShotTime = 0
    STATE.lastGeometry = 0
    STATE.lastLink = nil

    createSessionFolder()
end

--==============================================================
-- PASS
--==============================================================

local function scanPass(
    generation
)

    STATE.passes += 1

    local pass =
        STATE.passes

    local objects =
        enumerate()

    local changed =
        0

    for index, obj in ipairs(
        objects
    ) do

        if
            generation
            ~= STATE.generation
            or
            not STATE.running
        then

            return true
        end

        local ok, record =
            pcall(
                snapshot,
                obj
            )

        if ok and record then

            local addedOk, result =
                addRecord(
                    record,
                    safePath(obj)
                )

            if not addedOk then

                return false,
                    result
            end

            if result then
                changed += 1
            end
        end

        if
            index
            % CONFIG.YIELD_EVERY
            == 0
        then

            ScanStatus.Text =
                "Pass "
                .. tostring(pass)
                .. " • "
                .. tostring(index)
                .. "/"
                .. tostring(#objects)
                .. " • "
                .. readableSize(
                    STATE.bytes
                )

            task.wait()
        end
    end

    scanWeapons()
    scanRemotes()

    addRecord({

        kind =
            "pass_summary",

        pass =
            pass,

        inspected =
            #objects,

        changed =
            changed,

        records =
            STATE.records,

        bytes =
            STATE.bytes,

        shots =
            STATE.shots,

        geometry =
            STATE.geometry,

        effects =
            STATE.effects,

        remoteEvents =
            STATE.remoteEvents

    }, nil, true)

    return true
end

--==============================================================
-- START / RESUME
--==============================================================

local function startScanner()

    if
        STATE.uploading
        or STATE.running
    then

        return
    end

    if not STATE.started then

        resetScanner()

        STATE.started = true

        setupPlayerWatch()
        watchWorkspace()

        addRecord({

            kind =
                "session_start",

            scanner =
                CONFIG.SCANNER,

            version =
                CONFIG.VERSION,

            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId,

            clientVisibleOnly =
                true,

            focus = {

                "weapons",
                "hitscan",
                "castRays",
                "canPierce",
                "damage",
                "FastCast",
                "Caster",
                "walls",
                "collision",
                "remotes",
                "effects"
            },

            safety = {

                fireServer =
                    false,

                invokeServer =
                    false,

                modifiesGame =
                    false
            }

        }, nil, true)
    end

    STATE.running = true
    STATE.paused = false

    STATE.generation += 1

    local generation =
        STATE.generation

    refreshButtons()

    task.spawn(function()

        while
            STATE.running
            and generation
            == STATE.generation
        do

            local ok, result =
                scanPass(
                    generation
                )

            if not ok then

                STATE.running =
                    false

                STATE.paused =
                    true

                flushChunk()

                ScanStatus.Text =
                    result
                    == "LIMIT_REACHED"
                    and
                    "Limite de coleta atingido"
                    or
                    "Erro: "
                    .. tostring(result)

                refreshButtons()

                break
            end

            ScanStatus.Text =
                "Pass "
                .. tostring(
                    STATE.passes
                )
                .. " completo • "
                .. readableSize(
                    STATE.bytes
                )

            task.wait(
                CONFIG.PASS_INTERVAL
            )
        end
    end)

    -- probes independentes
    task.spawn(function()

        while
            STATE.running
            and generation
            == STATE.generation
        do

            local now =
                os.clock()

            if
                now
                -
                STATE.lastGeometry
                >=
                CONFIG.GEOMETRY_INTERVAL
            then

                STATE.lastGeometry =
                    now

                pcall(
                    geometryProbe
                )
            end

            task.wait(0.05)
        end
    end)
end

--==============================================================
-- PAUSE
--==============================================================

local function pauseScanner(
    reason
)

    if not STATE.started then
        return
    end

    if not STATE.running then

        STATE.paused =
            true

        refreshButtons()

        return
    end

    STATE.running = false
    STATE.paused = true

    STATE.generation += 1

    local ok, err =
        flushChunk()

    if not ok then

        ScanStatus.Text =
            "Erro ao fechar bloco: "
            .. tostring(err)

    else

        addRecord({

            kind =
                "scan_paused",

            reason =
                reason
                or "USER",

            passes =
                STATE.passes,

            records =
                STATE.records,

            bytes =
                STATE.bytes,

            shots =
                STATE.shots

        }, nil, true)

        flushChunk()

        ScanStatus.Text =
            "Pausado • "
            .. tostring(
                STATE.records
            )
            .. " registros • "
            .. readableSize(
                STATE.bytes
            )
    end

    refreshButtons()
end

--==============================================================
-- REQUEST
--==============================================================

local function doRequest(
    method,
    path,
    body
)

    if type(requestFn)
        ~= "function"
    then

        return false,
            "request/http_request não disponível"
    end

    local payload =
        HttpService:JSONEncode(
            body or {}
        )

    local lastError =
        "falha desconhecida"

    for attempt = 1,
        CONFIG.UPLOAD_RETRIES
    do

        local ok, response =
            pcall(
                requestFn,
                {

                    Url =
                        CONFIG.API_BASE
                        .. path,

                    Method =
                        method,

                    Headers = {

                        ["Content-Type"] =
                            "application/json"
                    },

                    Body =
                        payload
                }
            )

        if ok and response then

            local status =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or 0
                )
                or 0

            local responseText =
                tostring(
                    response.Body
                    or ""
                )

            local decoded = nil

            pcall(function()

                decoded =
                    HttpService:JSONDecode(
                        responseText
                    )
            end)

            if
                status >= 200
                and status < 300
            then

                return true,
                    decoded
                    or responseText
            end

            if type(decoded)
                == "table"
            then

                lastError =
                    decoded.message
                    or decoded.error
                    or
                    ("HTTP "
                    .. status)

            else

                lastError =
                    "HTTP "
                    .. tostring(status)
                    .. " • "
                    .. responseText:sub(
                        1,
                        250
                    )
            end

        else

            lastError =
                tostring(response)
        end

        if attempt <
            CONFIG.UPLOAD_RETRIES
        then

            task.wait(
                CONFIG.RETRY_DELAY
                * attempt
            )
        end
    end

    return false,
        lastError
end

--==============================================================
-- LOAD CHUNK
--==============================================================

local function totalChunks()

    return
        #STATE.diskChunks
        +
        #STATE.memoryChunks
end


local function loadChunk(index)

    local path =
        STATE.diskChunks[index]

    if path then

        local ok, text =
            pcall(
                readfileFn,
                path
            )

        if not ok then

            return nil,
                "erro lendo "
                .. path
        end

        local decodeOk, objects =
            pcall(function()

                return HttpService:
                    JSONDecode(text)
            end)

        if
            not decodeOk
            or type(objects)
            ~= "table"
        then

            return nil,
                "chunk local inválido"
        end

        return objects
    end

    local memoryIndex =
        index
        -
        #STATE.diskChunks

    local item =
        STATE.memoryChunks[
            memoryIndex
        ]

    if item then
        return item.objects
    end

    return nil,
        "chunk não encontrado"
end

--==============================================================
-- CLEANUP
--==============================================================

local function cleanupUploaded()

    if
        type(delfileFn)
        == "function"
    then

        for _, path in ipairs(
            STATE.diskChunks
        ) do

            pcall(function()

                if
                    type(isfileFn)
                    ~= "function"
                    or isfileFn(path)
                then

                    delfileFn(path)
                end
            end)
        end
    end

    STATE.memoryChunks = {}
end

--==============================================================
-- UPLOAD ALL
--==============================================================

local function uploadEverything()

    if
        not STATE.started
        or STATE.uploading
    then

        return
    end

    if STATE.running then

        pauseScanner(
            "UPLOAD_REQUESTED"
        )

        task.wait(0.15)
    end

    local okFlush, flushErr =
        flushChunk()

    if not okFlush then

        UploadText.Text =
            "Erro: "
            .. tostring(
                flushErr
            )

        return
    end

    local chunks =
        totalChunks()

    if chunks < 1 then

        UploadText.Text =
            "Nada para enviar"

        return
    end

    STATE.uploading =
        true

    refreshButtons()

    uploadProgress(
        "Iniciando upload...",
        0
    )

    task.spawn(function()

        -- START
        local okStart, start =
            doRequest(
                "POST",
                "/upload/start",
                {

                    token =
                        CONFIG.UPLOAD_TOKEN,

                    filename =
                        "Cafeina_WeaponResearch_"
                        .. tostring(
                            game.PlaceId
                        )
                        .. "_"
                        .. os.date(
                            "!%Y%m%d_%H%M%S"
                        )
                        .. ".json",

                    source =
                        CONFIG.SCANNER,

                    metadata = {

                        area =
                            "WeaponResearch",

                        scanner =
                            CONFIG.SCANNER,

                        version =
                            CONFIG.VERSION,

                        placeId =
                            game.PlaceId,

                        gameId =
                            game.GameId,

                        jobId =
                            game.JobId,

                        passes =
                            STATE.passes,

                        records =
                            STATE.records,

                        approximateBytes =
                            STATE.bytes,

                        shots =
                            STATE.shots,

                        geometry =
                            STATE.geometry,

                        effects =
                            STATE.effects,

                        remoteEvents =
                            STATE.remoteEvents
                    }
                }
            )

        if
            not okStart
            or type(start)
            ~= "table"
            or not start.uploadId
        then

            STATE.uploading =
                false

            UploadText.Text =
                "Falha ao iniciar: "
                .. tostring(start)

            refreshButtons()

            return
        end

        local uploadId =
            tostring(
                start.uploadId
            )

        -- CHUNKS
        for index = 1,
            chunks
        do

            local objects, loadErr =
                loadChunk(index)

            if not objects then

                STATE.uploading =
                    false

                uploadProgress(

                    "Erro lendo parte "
                    .. tostring(index)
                    .. ": "
                    .. tostring(loadErr),

                    (index - 1)
                    / chunks
                )

                refreshButtons()

                return
            end

            uploadProgress(

                "Enviando parte "
                .. tostring(index)
                .. "/"
                .. tostring(chunks),

                (index - 1)
                / chunks
            )

            local okChunk, chunkResult =
                doRequest(
                    "POST",
                    "/upload/chunk",
                    {

                        token =
                            CONFIG.UPLOAD_TOKEN,

                        uploadId =
                            uploadId,

                        index =
                            index,

                        objects =
                            objects
                    }
                )

            if not okChunk then

                STATE.uploading =
                    false

                uploadProgress(

                    "Falha parte "
                    .. tostring(index)
                    .. ": "
                    .. tostring(
                        chunkResult
                    ),

                    (index - 1)
                    / chunks
                )

                refreshButtons()

                return
            end

            uploadProgress(

                "Parte "
                .. tostring(index)
                .. "/"
                .. tostring(chunks)
                .. " enviada",

                index / chunks
            )

            task.wait()
        end

        -- FINISH
        uploadProgress(
            "Finalizando arquivo...",
            0.98
        )

        local okFinish, finish =
            doRequest(
                "POST",
                "/upload/finish",
                {

                    token =
                        CONFIG.UPLOAD_TOKEN,

                    uploadId =
                        uploadId,

                    totalChunks =
                        chunks,

                    summary = {

                        area =
                            "WeaponResearch",

                        scanner =
                            CONFIG.SCANNER,

                        passes =
                            STATE.passes,

                        records =
                            STATE.records,

                        approximateBytes =
                            STATE.bytes,

                        shots =
                            STATE.shots,

                        geometryProbes =
                            STATE.geometry,

                        effects =
                            STATE.effects,

                        remoteEvents =
                            STATE.remoteEvents,

                        scanPaused =
                            STATE.paused
                    }
                }
            )

        STATE.uploading =
            false

        if not okFinish then

            uploadProgress(

                "Falha finalizando: "
                .. tostring(finish),

                0.98
            )

            refreshButtons()

            return
        end

        local link = ""

        if type(finish)
            == "table"
        then

            link =
                tostring(

                    finish.url
                    or finish.downloadUrl
                    or finish.download_url
                    or finish.link
                    or ""
                )
        end

        STATE.uploaded =
            true

        STATE.lastLink =
            link

        if
            link ~= ""
            and
            type(setclipboard)
            == "function"
        then

            pcall(
                setclipboard,
                link
            )
        end

        cleanupUploaded()

        uploadProgress(

            link ~= ""
            and
            "Concluído • link copiado"
            or
            "Upload concluído",

            1
        )

        ScanStatus.Text =
            "Arquivo salvo no site • "
            .. readableSize(
                STATE.bytes
            )

        refreshButtons()
    end)
end

--==============================================================
-- BUTTON EVENTS
--==============================================================

StartButton.Activated:
Connect(function()

    if STATE.uploading then
        return
    end

    if STATE.uploaded then

        resetScanner()

        STATE.started =
            false
    end

    startScanner()
end)


PauseButton.Activated:
Connect(function()

    if STATE.uploading then
        return
    end

    pauseScanner("USER")
end)


SendButton.Activated:
Connect(function()

    uploadEverything()
end)

--==============================================================
-- LIVE UI STATUS
--==============================================================

task.spawn(function()

    while Gui.Parent do

        Stats.Text =
            readableSize(
                STATE.bytes
            )
            .. " / "
            .. readableSize(
                CONFIG.MAX_TOTAL_BYTES
            )
            .. " • "
            .. tostring(
                STATE.records
            )
            .. " reg"
            .. " • "
            .. tostring(
                STATE.shots
            )
            .. " tiros"
            .. " • P"
            .. tostring(
                STATE.passes
            )

        task.wait(0.25)
    end
end)

--==============================================================
-- READY
--==============================================================

refreshButtons()

print(
    "[CAFEÍNA] Weapon / Hitscan Research Scanner V6 pronto"
)
