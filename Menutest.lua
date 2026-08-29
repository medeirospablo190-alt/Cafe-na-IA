--[[
================================================================
 CAFEÍNA • TEST LAB V6.1
 Controlled Server Test + Runtime Evidence Collector

 OBJETIVO
   1. Mapear estruturas relevantes visíveis ao cliente.
   2. Observar eventos enviados pelo servidor.
   3. Executar testes SOMENTE no SecurityTestService dedicado.
   4. Correlacionar respostas/alterações com cada teste.
   5. Enviar scan + testes + evidências ao site CAFEÍNA.

 BOTÕES
   • INICIAR SCAN
   • TESTES
   • INTERROMPER
   • ENVIAR

 UPLOAD
   /upload/start
   /upload/chunk
   /upload/finish
   /upload/cancel
================================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local ReplicatedFirst =
    game:GetService("ReplicatedFirst")

local Workspace =
    game:GetService("Workspace")

local HttpService =
    game:GetService("HttpService")

local RunService =
    game:GetService("RunService")

local UserInputService =
    game:GetService("UserInputService")

local LocalPlayer =
    Players.LocalPlayer
    or Players.PlayerAdded:Wait()

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- REINJECTION
--==============================================================

local ENV = _G

if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)

    if ok and result then
        ENV = result
    end
end

if ENV.CAFEINA_TEST_LAB_V61
and
type(ENV.CAFEINA_TEST_LAB_V61.Shutdown) == "function"
then
    pcall(
        ENV.CAFEINA_TEST_LAB_V61.Shutdown
    )
end

local Runtime = {
    Closed = false,
    Connections = {},
    RemoteConnections = {},
    WatchConnections = {},
}

ENV.CAFEINA_TEST_LAB_V61 =
    Runtime

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    VERSION =
        "6.1",

    ScanInterval =
        0.55,

    InitialYieldEvery =
        300,

    MaxRecords =
        120000,

    MaxBytesApprox =
        150 * 1024 * 1024,

    RuntimeEventWindow =
        3.0,

    AttributeDebounce =
        0.08,

    --==========================================================
    -- TRACKING
    --==========================================================

    TrackRemotes =
        true,

    TrackSoldiers =
        true,

    TrackTools =
        true,

    TrackTycoon =
        true,

    TrackPlayerData =
        true,

    TrackBlaster =
        true,

    TrackInteractions =
        true,

    TrackInterestingAttributes =
        true,

    TrackHighValueStructure =
        true,

    TrackRelevantGui =
        true,

    ObserveServerEvents =
        true,

    ObserveRuntimeObjects =
        true,

    --==========================================================
    -- TEST SERVICE
    --==========================================================

    SafeTestServicePath =
        "ReplicatedStorage.__remotes.SecurityTestService",

    SafeTestDelay =
        0.35,

    TestResponseWindow =
        2.5,

    SafeTestNames = {
        Ping = true,
        Echo = true,
        ValidateNumber = true,
        ValidateString = true,
        ClientDiagnostic = true,
    },

    --==========================================================
    -- VISUAL JUNK FILTER
    --==========================================================

    IgnoreDecorative =
        true,

    IgnoreClasses = {

        ParticleEmitter = true,
        Trail = true,
        Beam = true,
        Texture = true,
        Decal = true,
        SurfaceAppearance = true,
        SpecialMesh = true,

        -- MeshPart pode carregar Touch/Tool/atributos.
        MeshPart = false,
    },

    --==========================================================
    -- INTERESTING NAMES
    --==========================================================

    InterestingNames = {

        "damage",
        "health",
        "maxhealth",

        "ammo",
        "mag",
        "magazine",
        "reload",

        "firerate",
        "fire",
        "spread",
        "recoil",
        "range",

        "speed",
        "walkspeed",

        "money",
        "cash",

        "kills",
        "rebirth",

        "team",

        "weapon",
        "gun",
        "tool",

        "soldier",
        "npc",
        "aggro",
        "target",

        "cooldown",
        "cost",
        "price",

        "purchase",
        "collect",
        "button",
        "tycoon",

        "blaster",
        "bullet",
        "projectile",

        "hit",
        "headshot",

        "armor",
        "armour",

        "loadout",
        "spawn",

        "admin",
        "give",
        "reset",
        "teleport",

        "gamepass",
        "setting",
        "flag",
        "leaderboard",

        "inventory",
        "equip",
        "auth",
        "permission",
    },

    --==========================================================
    -- UPLOAD
    --==========================================================

    BASE_URL =
        "https://cafe-na-ia.onrender.com",

    UPLOAD_BASE =
        "https://cafe-na-ia.onrender.com/upload",

    UPLOAD_TOKEN =
        "",

    UploadChunkBytes =
        2500000,

    UploadRetries =
        4,

    UploadRetryDelay =
        1.25,
}

--==============================================================
-- STATE
--==============================================================

local STATE = {

    Running =
        false,

    StopRequested =
        false,

    Sending =
        false,

    Testing =
        false,

    LimitReached =
        false,

    --==========================================================
    -- TESTS
    --==========================================================

    TestsRun =
        0,

    TestsPassed =
        0,

    TestsBlocked =
        0,

    TestsErrors =
        0,

    ActiveTestId =
        nil,

    ActiveTestRemote =
        nil,

    ActiveTestStarted =
        0,

    --==========================================================
    -- REMOTE EVENTS
    --==========================================================

    RemoteEventsObserved =
        0,

    ObservedRemotes =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        ),

    --==========================================================
    -- SCAN
    --==========================================================

    Pass =
        0,

    StartedAt =
        0,

    FinishedAt =
        0,

    Records =
        {},

    Seen =
        {},

    LastSnapshot =
        {},

    Added =
        0,

    Changed =
        0,

    Removed =
        0,

    NewUseful =
        0,

    NewThisPass =
        0,

    CategoryCount =
        {},

    ApproxBytes =
        0,

    CurrentArea =
        "Aguardando",

    --==========================================================
    -- UPLOAD
    --==========================================================

    UploadId =
        nil,

    BytesSent =
        0,

    ChunksSent =
        0,

    TotalChunks =
        0,

    LastURL =
        nil,

    UploadCancelled =
        false,

    --==========================================================
    -- STATUS
    --==========================================================

    LastStatus =
        "Pronto",

    LastDetail =
        "Aguardando início",

    --==========================================================
    -- WATCHERS
    --==========================================================

    WatchedObjects =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        ),

    AttributeLast =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        ),
}

--==============================================================
-- BASIC HELPERS
--==============================================================

local function now()
    return os.clock()
end

local function lower(value)

    return string.lower(
        tostring(
            value or ""
        )
    )
end

local function connect(
    signal,
    callback,
    bucket
)

    local connection =
        signal:Connect(
            callback
        )

    table.insert(
        bucket
        or Runtime.Connections,
        connection
    )

    return connection
end

local function safeFullName(
    obj
)

    local ok, value =
        pcall(function()

            return obj:
                GetFullName()
        end)

    if ok then
        return value
    end

    return tostring(obj)
end

local function safeAttributes(
    obj
)

    local ok, attrs =
        pcall(function()

            return obj:
                GetAttributes()
        end)

    if ok
    and
    type(attrs) == "table"
    then
        return attrs
    end

    return {}
end

local function containsInterestingName(
    name
)

    local n =
        lower(name)

    for _, token in ipairs(
        CONFIG.InterestingNames
    ) do

        if string.find(
            n,
            token,
            1,
            true
        ) then

            return true,
                token
        end
    end

    return false,
        nil
end

local function isDecorative(
    obj
)

    if not CONFIG.IgnoreDecorative then
        return false
    end

    if CONFIG.IgnoreClasses[
        obj.ClassName
    ]
    then
        return true
    end

    local n =
        lower(obj.Name)

    return
        n == "mesh"
        or
        n == "accessoryweld"
        or
        n == "originalposition"
        or
        n == "originalsize"
end

--==============================================================
-- DEEP SERIALIZATION
--==============================================================

local function serializeValue(
    value,
    depth,
    seen
)

    depth =
        depth or 0

    seen =
        seen or {}

    if depth >= 7 then
        return "[depth-limit]"
    end

    local valueType =
        typeof(value)

    if valueType == "nil"
    or valueType == "string"
    or valueType == "number"
    or valueType == "boolean"
    then
        return value
    end

    if valueType == "Instance" then

        return {
            type =
                "Instance",

            class =
                value.ClassName,

            name =
                value.Name,

            path =
                safeFullName(value),
        }
    end

    if valueType == "Vector3" then

        return {
            type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z,
        }
    end

    if valueType == "Vector2" then

        return {
            type = "Vector2",
            x = value.X,
            y = value.Y,
        }
    end

    if valueType == "Color3" then

        return {
            type = "Color3",
            r = value.R,
            g = value.G,
            b = value.B,
        }
    end

    if valueType == "CFrame" then

        local p =
            value.Position

        local look =
            value.LookVector

        return {
            type = "CFrame",

            position = {
                x = p.X,
                y = p.Y,
                z = p.Z,
            },

            look = {
                x = look.X,
                y = look.Y,
                z = look.Z,
            }
        }
    end

    if valueType == "EnumItem" then
        return tostring(value)
    end

    if valueType == "table" then

        if seen[value] then
            return "[circular]"
        end

        seen[value] =
            true

        local result =
            {}

        local count =
            0

        for key, child in pairs(
            value
        ) do

            count += 1

            if count > 120 then

                result.__truncated =
                    true

                break
            end

            result[
                tostring(key)
            ] =
                serializeValue(
                    child,
                    depth + 1,
                    seen
                )
        end

        seen[value] =
            nil

        return result
    end

    return tostring(value)
end

--==============================================================
-- SIZE
--==============================================================

local function approxLen(
    value
)

    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            value
        )

    if ok then
        return #encoded
    end

    return 64
end

local function readableSize(
    bytes
)

    bytes =
        tonumber(bytes)
        or 0

    if bytes >= 1024 * 1024 then

        return string.format(
            "%.2f MB",
            bytes
                /
            (1024 * 1024)
        )
    end

    if bytes >= 1024 then

        return string.format(
            "%.1f KB",
            bytes / 1024
        )
    end

    return
        tostring(bytes)
        ..
        " B"
end

--==============================================================
-- RECORDS
--==============================================================

local function recordKey(
    category,
    obj,
    suffix
)

    return
        tostring(category)
        ..
        "|"
        ..
        safeFullName(obj)
        ..
        "|"
        ..
        tostring(
            suffix or ""
        )
end

local function addRecord(
    category,
    kind,
    key,
    data,
    force
)

    if Runtime.Closed then
        return false
    end

    if #STATE.Records >=
        CONFIG.MaxRecords
    then

        STATE.LimitReached =
            true

        STATE.StopRequested =
            true

        STATE.LastStatus =
            "Limite de registros"

        return false
    end

    local rec = {

        timestamp =
            os.time(),

        clock =
            now(),

        pass =
            STATE.Pass,

        category =
            category,

        kind =
            kind,

        key =
            key,

        testId =
            STATE.ActiveTestId,

        data =
            data,
    }

    local bytes =
        approxLen(rec)

    if STATE.ApproxBytes + bytes >
        CONFIG.MaxBytesApprox
    then

        STATE.LimitReached =
            true

        STATE.StopRequested =
            true

        STATE.LastStatus =
            "Limite de 150 MB"

        return false
    end

    table.insert(
        STATE.Records,
        rec
    )

    STATE.ApproxBytes +=
        bytes

    STATE.CategoryCount[
        category
    ] =
        (
            STATE.CategoryCount[
                category
            ]
            or 0
        )
        +
        1

    if kind == "baseline" then

        STATE.Added +=
            1

    elseif kind == "changed" then

        STATE.Changed +=
            1

    elseif kind == "removed" then

        STATE.Removed +=
            1
    end

    STATE.NewUseful +=
        1

    STATE.NewThisPass +=
        1

    return true
end

--==============================================================
-- SNAPSHOT
--==============================================================

local function snapshotValue(
    obj
)

    local data = {

        class =
            obj.ClassName,

        name =
            obj.Name,

        path =
            safeFullName(obj),

        childCount =
            #obj:GetChildren(),

        archivable =
            obj.Archivable,
    }

    if obj:IsA(
        "ValueBase"
    )
    then

        local ok, value =
            pcall(function()

                return obj.Value
            end)

        if ok then

            data.value =
                serializeValue(
                    value
                )
        end
    end

    if obj:IsA(
        "Humanoid"
    )
    then

        data.health =
            obj.Health

        data.maxHealth =
            obj.MaxHealth

        data.walkSpeed =
            obj.WalkSpeed

        data.jumpPower =
            obj.JumpPower
    end

    if obj:IsA(
        "Tool"
    )
    then

        data.toolTip =
            obj.ToolTip

        data.canBeDropped =
            obj.CanBeDropped

        data.hasHandle =
            obj:
            FindFirstChild(
                "Handle"
            ) ~= nil
    end

    if obj:IsA(
        "BasePart"
    )
    then

        data.canTouch =
            obj.CanTouch

        data.canQuery =
            obj.CanQuery

        data.canCollide =
            obj.CanCollide

        data.anchored =
            obj.Anchored
    end

    if obj:IsA(
        "ProximityPrompt"
    )
    then

        data.actionText =
            obj.ActionText

        data.objectText =
            obj.ObjectText

        data.holdDuration =
            obj.HoldDuration

        data.maxActivationDistance =
            obj.MaxActivationDistance

        data.requiresLineOfSight =
            obj.RequiresLineOfSight
    end

    if obj:IsA(
        "ClickDetector"
    )
    then

        data.maxActivationDistance =
            obj.MaxActivationDistance
    end

    if obj:IsA(
        "TextLabel"
    )
    or
    obj:IsA(
        "TextButton"
    )
    then

        data.text =
            string.sub(
                obj.Text,
                1,
                500
            )

        data.visible =
            obj.Visible
    end

    local attrs =
        safeAttributes(obj)

    if next(attrs) then

        data.attributes =
            {}

        for name, value in pairs(
            attrs
        ) do

            if
                containsInterestingName(
                    name
                )
                or
                not CONFIG.TrackInterestingAttributes
            then

                data.attributes[
                    name
                ] =
                    serializeValue(
                        value
                    )
            end
        end

        if not next(
            data.attributes
        )
        then

            data.attributes =
                nil
        end
    end

    return data
end

local function fingerprint(
    data
)

    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            data
        )

    if ok then
        return encoded
    end

    return tostring(data)
end

--==============================================================
-- CONSIDER
--==============================================================

local function consider(
    category,
    obj,
    forceUseful
)

    if not obj
    or not obj.Parent
    then
        return
    end

    if isDecorative(obj)
    and
    not forceUseful
    then
        return
    end

    local key =
        recordKey(
            category,
            obj
        )

    local data =
        snapshotValue(obj)

    local fp =
        fingerprint(data)

    STATE.Seen[
        key
    ] =
        true

    local old =
        STATE.LastSnapshot[
            key
        ]

    if old == nil then

        if addRecord(
            category,
            "baseline",
            key,
            data
        )
        then

            STATE.LastSnapshot[
                key
            ] =
                fp
        end

    elseif old ~= fp then

        if addRecord(
            category,
            "changed",
            key,
            data
        )
        then

            STATE.LastSnapshot[
                key
            ] =
                fp
        end
    end
end

--==============================================================
-- SCAN DESCENDANTS WITH YIELD
--==============================================================

local function scanDescendants(
    root,
    category,
    predicate
)

    if not root then
        return
    end

    local descendants =
        root:GetDescendants()

    for index, obj in ipairs(
        descendants
    ) do

        if STATE.StopRequested
        or
        Runtime.Closed
        then
            break
        end

        local accepted =
            true

        if predicate then

            local ok, result =
                pcall(
                    predicate,
                    obj
                )

            accepted =
                ok
                and
                result == true
        end

        if accepted then

            consider(
                category,
                obj,
                false
            )
        end

        if index %
            CONFIG.InitialYieldEvery
            ==
            0
        then

            RunService.Heartbeat:
                Wait()
        end
    end
end

--==============================================================
-- HIGH VALUE
--==============================================================

local HIGH_VALUE_TOKENS = {

    "__remotes",

    "tycoon",
    "purchase",
    "money",
    "cash",

    "weapon",
    "gun",
    "blaster",

    "projectile",
    "damage",

    "playerdata",
    "loadout",

    "leaderboard",
    "setting",
    "flag",

    "admin",

    "rebirth",
    "collector",
    "button",

    "soldier",
    "npc",

    "gamepass",
}

local function pathIsHighValue(
    obj
)

    local path =
        lower(
            safeFullName(obj)
        )

    for _, token in ipairs(
        HIGH_VALUE_TOKENS
    ) do

        if string.find(
            path,
            token,
            1,
            true
        ) then

            return true
        end
    end

    return false
end

--==============================================================
-- TEST CORRELATION
--==============================================================

local function currentTestContext()

    if not STATE.ActiveTestId then
        return nil
    end

    return {

        testId =
            STATE.ActiveTestId,

        remote =
            STATE.ActiveTestRemote,

        elapsed =
            now()
            -
            STATE.ActiveTestStarted,
    }
end

--==============================================================
-- REMOTE EVENT OBSERVATION
--==============================================================

local function observeRemote(
    remote
)

    if not CONFIG.ObserveServerEvents then
        return
    end

    if STATE.ObservedRemotes[
        remote
    ]
    then
        return
    end

    if not (
        remote:IsA(
            "RemoteEvent"
        )
        or
        remote.ClassName ==
            "UnreliableRemoteEvent"
    )
    then
        return
    end

    STATE.ObservedRemotes[
        remote
    ] =
        true

    local ok, connection =
        pcall(function()

            return remote.OnClientEvent:
                Connect(function(...)

                    if Runtime.Closed then
                        return
                    end

                    if not STATE.Running
                    and
                    not STATE.Testing
                    then
                        return
                    end

                    STATE.RemoteEventsObserved +=
                        1

                    local args =
                        table.pack(...)

                    local safeArgs =
                        {}

                    for i = 1,
                        math.min(
                            args.n,
                            30
                        )
                    do

                        safeArgs[i] =
                            serializeValue(
                                args[i]
                            )
                    end

                    addRecord(
                        "RemoteTraffic",

                        "server_event",

                        "evt|"
                        ..
                        safeFullName(remote)
                        ..
                        "|"
                        ..
                        tostring(
                            STATE.RemoteEventsObserved
                        ),

                        {
                            path =
                                safeFullName(remote),

                            class =
                                remote.ClassName,

                            argumentCount =
                                args.n,

                            args =
                                safeArgs,

                            testContext =
                                currentTestContext(),
                        },

                        true
                    )
                end)
        end)

    if ok
    and
    connection
    then

        table.insert(
            Runtime.RemoteConnections,
            connection
        )
    end
end

--==============================================================
-- OBJECT WATCHER
--==============================================================

local function watchObject(
    obj
)

    if STATE.WatchedObjects[
        obj
    ]
    then
        return
    end

    STATE.WatchedObjects[
        obj
    ] =
        true

    local interesting =
        pathIsHighValue(obj)
        or
        containsInterestingName(
            obj.Name
        )

    if not interesting then
        return
    end

    local ok, connection =
        pcall(function()

            return obj.AttributeChanged:
                Connect(function(
                    attribute
                )

                    if Runtime.Closed then
                        return
                    end

                    if not STATE.Running
                    and
                    not STATE.Testing
                    then
                        return
                    end

                    if not
                        containsInterestingName(
                            attribute
                        )
                    then
                        return
                    end

                    local current =
                        now()

                    local map =
                        STATE.AttributeLast[
                            obj
                        ]

                    if not map then

                        map =
                            {}

                        STATE.AttributeLast[
                            obj
                        ] =
                            map
                    end

                    local previous =
                        map[
                            attribute
                        ]
                        or 0

                    if current - previous <
                        CONFIG.AttributeDebounce
                    then
                        return
                    end

                    map[
                        attribute
                    ] =
                        current

                    local success,
                          value =
                        pcall(
                            obj.GetAttribute,
                            obj,
                            attribute
                        )

                    if not success then
                        return
                    end

                    addRecord(
                        "Runtime",

                        "attribute_change",

                        "attr|"
                        ..
                        safeFullName(obj)
                        ..
                        "|"
                        ..
                        attribute
                        ..
                        "|"
                        ..
                        tostring(current),

                        {
                            path =
                                safeFullName(obj),

                            class =
                                obj.ClassName,

                            attribute =
                                attribute,

                            value =
                                serializeValue(
                                    value
                                ),

                            testContext =
                                currentTestContext(),
                        },

                        true
                    )
                end)
        end)

    if ok
    and
    connection
    then

        table.insert(
            Runtime.WatchConnections,
            connection
        )
    end
end

--==============================================================
-- RUNTIME ROOT OBSERVATION
--==============================================================

local function observeRoot(
    root,
    label
)

    if not root then
        return
    end

    connect(
        root.DescendantAdded,

        function(obj)

            if Runtime.Closed then
                return
            end

            if not STATE.Running
            and
            not STATE.Testing
            then
                return
            end

            task.defer(function()

                if Runtime.Closed
                or
                not obj.Parent
                then
                    return
                end

                if
                    pathIsHighValue(obj)
                    or
                    containsInterestingName(
                        obj.Name
                    )
                    or
                    obj:IsA(
                        "RemoteEvent"
                    )
                    or
                    obj:IsA(
                        "RemoteFunction"
                    )
                    or
                    obj.ClassName ==
                        "UnreliableRemoteEvent"
                    or
                    obj:IsA(
                        "Tool"
                    )
                    or
                    obj:IsA(
                        "ValueBase"
                    )
                    or
                    obj:IsA(
                        "ProximityPrompt"
                    )
                    or
                    obj:IsA(
                        "ClickDetector"
                    )
                    or
                    obj:IsA(
                        "TouchTransmitter"
                    )
                then

                    addRecord(
                        "Runtime",

                        "object_added",

                        "add|"
                        ..
                        safeFullName(obj)
                        ..
                        "|"
                        ..
                        tostring(
                            now()
                        ),

                        {
                            area =
                                label,

                            snapshot =
                                snapshotValue(
                                    obj
                                ),

                            testContext =
                                currentTestContext(),
                        },

                        true
                    )
                end

                if obj:IsA(
                    "RemoteEvent"
                )
                or
                obj.ClassName ==
                    "UnreliableRemoteEvent"
                then

                    observeRemote(
                        obj
                    )
                end

                watchObject(
                    obj
                )
            end)
        end
    )

    connect(
        root.DescendantRemoving,

        function(obj)

            if Runtime.Closed then
                return
            end

            if not STATE.Running
            and
            not STATE.Testing
            then
                return
            end

            if
                pathIsHighValue(obj)
                or
                containsInterestingName(
                    obj.Name
                )
                or
                obj:IsA(
                    "Tool"
                )
                or
                obj:IsA(
                    "ValueBase"
                )
            then

                addRecord(
                    "Runtime",

                    "object_removed",

                    "remove|"
                    ..
                    safeFullName(obj)
                    ..
                    "|"
                    ..
                    tostring(
                        now()
                    ),

                    {
                        area =
                            label,

                        path =
                            safeFullName(obj),

                        class =
                            obj.ClassName,

                        name =
                            obj.Name,

                        testContext =
                            currentTestContext(),
                    },

                    true
                )
            end
        end
    )
end

--==============================================================
-- SMART SCANNERS
--==============================================================

local function scanRemotes()

    if not CONFIG.TrackRemotes then
        return
    end

    STATE.CurrentArea =
        "Remotes"

    local roots = {
        ReplicatedStorage,
        ReplicatedFirst
    }

    for _, root in ipairs(
        roots
    ) do

        scanDescendants(
            root,
            "Remotes",

            function(obj)

                local remote =
                    obj:IsA(
                        "RemoteEvent"
                    )
                    or
                    obj:IsA(
                        "RemoteFunction"
                    )
                    or
                    obj.ClassName ==
                        "UnreliableRemoteEvent"

                if remote then

                    observeRemote(
                        obj
                    )

                    watchObject(
                        obj
                    )
                end

                return
                    remote
                    or
                    obj:IsA(
                        "BindableEvent"
                    )
                    or
                    obj:IsA(
                        "BindableFunction"
                    )
            end
        )
    end
end

local function scanHighValueStructure()

    if not CONFIG.TrackHighValueStructure then
        return
    end

    STATE.CurrentArea =
        "Estrutura"

    local roots = {
        ReplicatedStorage,
        ReplicatedFirst,
        Workspace
    }

    for _, root in ipairs(
        roots
    ) do

        scanDescendants(
            root,
            "Structure",

            function(obj)

                if not pathIsHighValue(
                    obj
                )
                then
                    return false
                end

                watchObject(
                    obj
                )

                return
                    obj:IsA("Folder")
                    or
                    obj:IsA("Configuration")
                    or
                    obj:IsA("ModuleScript")
                    or
                    obj:IsA("LocalScript")
                    or
                    obj:IsA("ValueBase")
                    or
                    obj:IsA("Tool")
                    or
                    obj:IsA("ProximityPrompt")
                    or
                    obj:IsA("ClickDetector")
                    or
                    obj:IsA("RemoteEvent")
                    or
                    obj:IsA("RemoteFunction")
                    or
                    obj.ClassName ==
                        "UnreliableRemoteEvent"
            end
        )
    end
end

local function scanRelevantGui()

    if not CONFIG.TrackRelevantGui then
        return
    end

    STATE.CurrentArea =
        "GUI"

    scanDescendants(
        PlayerGui,
        "Gui",

        function(obj)

            if not obj:IsA(
                "GuiObject"
            )
            then
                return false
            end

            return
                containsInterestingName(
                    obj.Name
                )
                or
                pathIsHighValue(
                    obj
                )
                or
                (
                    (
                        obj:IsA("TextLabel")
                        or
                        obj:IsA("TextButton")
                    )
                    and
                    containsInterestingName(
                        obj.Text
                    )
                )
        end
    )
end

local function scanBlaster()

    if not CONFIG.TrackBlaster then
        return
    end

    STATE.CurrentArea =
        "Blaster"

    local blasterRoot =
        ReplicatedStorage:
        FindFirstChild(
            "BlasterSystem"
        )

    if blasterRoot then

        scanDescendants(
            blasterRoot,
            "BlasterSystem",

            function(obj)

                local path =
                    lower(
                        safeFullName(obj)
                    )

                return
                    string.find(
                        path,
                        "blaster",
                        1,
                        true
                    )
                    or
                    string.find(
                        path,
                        "bullet",
                        1,
                        true
                    )
                    or
                    string.find(
                        path,
                        "projectile",
                        1,
                        true
                    )
                    or
                    containsInterestingName(
                        obj.Name
                    )
            end
        )
    end
end

local function scanTools()

    if not CONFIG.TrackTools then
        return
    end

    STATE.CurrentArea =
        "Tools"

    local roots = {
        Workspace,
        ReplicatedStorage
    }

    local backpack =
        LocalPlayer:
        FindFirstChild(
            "Backpack"
        )

    if backpack then

        table.insert(
            roots,
            backpack
        )
    end

    if LocalPlayer.Character then

        table.insert(
            roots,
            LocalPlayer.Character
        )
    end

    for _, root in ipairs(
        roots
    ) do

        scanDescendants(
            root,
            "Tools",

            function(obj)

                if obj:IsA(
                    "Tool"
                )
                then

                    watchObject(
                        obj
                    )

                    return true
                end

                local parent =
                    obj.Parent

                if parent
                and
                parent:IsA(
                    "Tool"
                )
                then

                    watchObject(
                        obj
                    )

                    return
                        containsInterestingName(
                            obj.Name
                        )
                        or
                        obj:IsA(
                            "ValueBase"
                        )
                        or
                        obj:IsA(
                            "ModuleScript"
                        )
                        or
                        obj:IsA(
                            "LocalScript"
                        )
                end

                return false
            end
        )
    end
end

local function scanSoldiers()

    if not CONFIG.TrackSoldiers then
        return
    end

    STATE.CurrentArea =
        "Soldiers"

    local soldiers =
        Workspace:
        FindFirstChild(
            "Soldiers"
        )

    if not soldiers then
        return
    end

    for index, model in ipairs(
        soldiers:GetChildren()
    ) do

        if STATE.StopRequested then
            break
        end

        if model:IsA(
            "Model"
        )
        then

            consider(
                "Soldiers",
                model,
                true
            )

            for _, obj in ipairs(
                model:GetDescendants()
            ) do

                if
                    obj:IsA(
                        "Humanoid"
                    )
                    or
                    obj:IsA(
                        "Tool"
                    )
                    or
                    obj:IsA(
                        "ValueBase"
                    )
                    or
                    obj.Name ==
                        "HumanoidRootPart"
                    or
                    containsInterestingName(
                        obj.Name
                    )
                then

                    consider(
                        "Soldiers",
                        obj,
                        true
                    )

                    watchObject(
                        obj
                    )
                end
            end
        end

        if index % 20 == 0 then
            RunService.Heartbeat:Wait()
        end
    end
end

local function scanPlayerData()

    if not CONFIG.TrackPlayerData then
        return
    end

    STATE.CurrentArea =
        "PlayerData"

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if STATE.StopRequested then
            break
        end

        local leaderstats =
            player:
            FindFirstChild(
                "leaderstats"
            )

        if leaderstats then

            for _, obj in ipairs(
                leaderstats:
                GetDescendants()
            ) do

                if obj:IsA(
                    "ValueBase"
                )
                then

                    consider(
                        "PlayerData",
                        obj,
                        true
                    )

                    watchObject(
                        obj
                    )
                end
            end
        end

        for _, child in ipairs(
            player:GetChildren()
        ) do

            if child ~=
                player.Character
            and
            (
                child:IsA("Folder")
                or
                child:IsA("Configuration")
                or
                child:IsA("ValueBase")
            )
            and
            containsInterestingName(
                child.Name
            )
            then

                consider(
                    "PlayerData",
                    child,
                    true
                )

                for _, obj in ipairs(
                    child:GetDescendants()
                ) do

                    if
                        obj:IsA(
                            "ValueBase"
                        )
                        or
                        containsInterestingName(
                            obj.Name
                        )
                    then

                        consider(
                            "PlayerData",
                            obj,
                            true
                        )

                        watchObject(
                            obj
                        )
                    end
                end
            end
        end
    end
end

local function scanTycoon()

    if not CONFIG.TrackTycoon then
        return
    end

    STATE.CurrentArea =
        "Tycoon"

    local tycoons =
        Workspace:
        FindFirstChild(
            "Tycoons"
        )

    if not tycoons then
        return
    end

    scanDescendants(
        tycoons,
        "Tycoon",

        function(obj)

            local path =
                lower(
                    safeFullName(obj)
                )

            local relevant =
                string.find(
                    path,
                    "button",
                    1,
                    true
                )
                or
                string.find(
                    path,
                    "collector",
                    1,
                    true
                )
                or
                string.find(
                    path,
                    "purchase",
                    1,
                    true
                )
                or
                containsInterestingName(
                    obj.Name
                )

            if not relevant then
                return false
            end

            watchObject(
                obj
            )

            return
                obj:IsA("ValueBase")
                or
                obj:IsA("ProximityPrompt")
                or
                obj:IsA("ClickDetector")
                or
                obj:IsA("TouchTransmitter")
                or
                obj:IsA("Tool")
                or
                obj:IsA("Model")
                or
                containsInterestingName(
                    obj.Name
                )
        end
    )
end

local function scanInteractions()

    if not CONFIG.TrackInteractions then
        return
    end

    STATE.CurrentArea =
        "Interactions"

    scanDescendants(
        Workspace,
        "Interactions",

        function(obj)

            return
                obj:IsA(
                    "ProximityPrompt"
                )
                or
                obj:IsA(
                    "ClickDetector"
                )
                or
                obj:IsA(
                    "TouchTransmitter"
                )
        end
    )
end

--==============================================================
-- REMOVED DETECTION
--==============================================================

local function detectRemoved()

    for key in pairs(
        STATE.LastSnapshot
    ) do

        if not STATE.Seen[
            key
        ]
        then

            addRecord(
                "Lifecycle",

                "removed",

                key,

                {
                    path =
                        key,

                    testContext =
                        currentTestContext(),
                },

                true
            )

            STATE.LastSnapshot[
                key
            ] =
                nil
        end
    end
end

--==============================================================
-- RESET
--==============================================================

local function resetState()

    STATE.StopRequested =
        false

    STATE.LimitReached =
        false

    STATE.Pass =
        0

    STATE.StartedAt =
        now()

    STATE.FinishedAt =
        0

    STATE.Records =
        {}

    STATE.Seen =
        {}

    STATE.LastSnapshot =
        {}

    STATE.Added =
        0

    STATE.Changed =
        0

    STATE.Removed =
        0

    STATE.NewUseful =
        0

    STATE.NewThisPass =
        0

    STATE.CategoryCount =
        {}

    STATE.ApproxBytes =
        0

    STATE.TestsRun =
        0

    STATE.TestsPassed =
        0

    STATE.TestsBlocked =
        0

    STATE.TestsErrors =
        0

    STATE.RemoteEventsObserved =
        0

    STATE.ActiveTestId =
        nil

    STATE.ActiveTestRemote =
        nil

    STATE.ActiveTestStarted =
        0

    STATE.LastURL =
        nil
end

--==============================================================
-- PASS
--==============================================================

local function runPass()

    STATE.Pass +=
        1

    STATE.NewThisPass =
        0

    STATE.Seen =
        {}

    scanRemotes()

    if STATE.StopRequested then
        return
    end

    scanHighValueStructure()

    if STATE.StopRequested then
        return
    end

    scanRelevantGui()

    if STATE.StopRequested then
        return
    end

    scanBlaster()

    if STATE.StopRequested then
        return
    end

    scanSoldiers()

    if STATE.StopRequested then
        return
    end

    scanPlayerData()

    if STATE.StopRequested then
        return
    end

    scanTycoon()

    if STATE.StopRequested then
        return
    end

    scanTools()

    if STATE.StopRequested then
        return
    end

    scanInteractions()

    detectRemoved()

    STATE.CurrentArea =
        "Runtime"
end

--==============================================================
-- GUI
--==============================================================

local oldGui =
    PlayerGui:
    FindFirstChild(
        "CafeinaTestLabV61"
    )

if oldGui then
    oldGui:Destroy()
end

local gui =
    Instance.new(
        "ScreenGui"
    )

gui.Name =
    "CafeinaTestLabV61"

gui.ResetOnSpawn =
    false

gui.IgnoreGuiInset =
    false

gui.Parent =
    PlayerGui

Runtime.Gui =
    gui

local main =
    Instance.new(
        "Frame"
    )

main.Size =
    UDim2.fromOffset(
        330,
        242
    )

main.Position =
    UDim2.new(
        0.5,
        -165,
        0.08,
        0
    )

main.BackgroundColor3 =
    Color3.fromRGB(
        15,
        15,
        18
    )

main.BorderSizePixel =
    0

main.Active =
    true

main.Parent =
    gui

Instance.new(
    "UICorner",
    main
).CornerRadius =
    UDim.new(
        0,
        12
    )

local stroke =
    Instance.new(
        "UIStroke"
    )

stroke.Color =
    Color3.fromRGB(
        55,
        55,
        62
    )

stroke.Thickness =
    1

stroke.Parent =
    main

local title =
    Instance.new(
        "TextLabel"
    )

title.Size =
    UDim2.new(
        1,
        -20,
        0,
        28
    )

title.Position =
    UDim2.fromOffset(
        10,
        7
    )

title.BackgroundTransparency =
    1

title.Text =
    "CAFEÍNA • TEST LAB V6.1"

title.Font =
    Enum.Font.GothamBold

title.TextSize =
    14

title.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

title.TextXAlignment =
    Enum.TextXAlignment.Left

title.Parent =
    main

local scanSizeLabel =
    Instance.new(
        "TextLabel"
    )

scanSizeLabel.Size =
    UDim2.new(
        1,
        -20,
        0,
        34
    )

scanSizeLabel.Position =
    UDim2.fromOffset(
        10,
        38
    )

scanSizeLabel.BackgroundTransparency =
    1

scanSizeLabel.Text =
    "SCAN • 0.0 MB / 150 MB"

scanSizeLabel.Font =
    Enum.Font.GothamBold

scanSizeLabel.TextSize =
    15

scanSizeLabel.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

scanSizeLabel.TextXAlignment =
    Enum.TextXAlignment.Left

scanSizeLabel.Parent =
    main

local detailLabel =
    Instance.new(
        "TextLabel"
    )

detailLabel.Size =
    UDim2.new(
        1,
        -20,
        0,
        18
    )

detailLabel.Position =
    UDim2.fromOffset(
        10,
        68
    )

detailLabel.BackgroundTransparency =
    1

detailLabel.Text =
    "0 registros • pass 0 • novos 0"

detailLabel.Font =
    Enum.Font.Gotham

detailLabel.TextSize =
    10

detailLabel.TextColor3 =
    Color3.fromRGB(
        165,
        165,
        172
    )

detailLabel.TextXAlignment =
    Enum.TextXAlignment.Left

detailLabel.Parent =
    main

local uploadStatus =
    Instance.new(
        "TextLabel"
    )

uploadStatus.Size =
    UDim2.new(
        1,
        -20,
        0,
        22
    )

uploadStatus.Position =
    UDim2.fromOffset(
        10,
        86
    )

uploadStatus.BackgroundTransparency =
    1

uploadStatus.Text =
    "STATUS • aguardando"

uploadStatus.Font =
    Enum.Font.Gotham

uploadStatus.TextSize =
    11

uploadStatus.TextColor3 =
    Color3.fromRGB(
        180,
        180,
        185
    )

uploadStatus.TextXAlignment =
    Enum.TextXAlignment.Left

uploadStatus.Parent =
    main

local barBg =
    Instance.new(
        "Frame"
    )

barBg.Size =
    UDim2.new(
        1,
        -20,
        0,
        8
    )

barBg.Position =
    UDim2.fromOffset(
        10,
        112
    )

barBg.BackgroundColor3 =
    Color3.fromRGB(
        40,
        40,
        46
    )

barBg.BorderSizePixel =
    0

barBg.Parent =
    main

Instance.new(
    "UICorner",
    barBg
).CornerRadius =
    UDim.new(
        1,
        0
    )

local bar =
    Instance.new(
        "Frame"
    )

bar.Size =
    UDim2.fromScale(
        0,
        1
    )

bar.BackgroundColor3 =
    Color3.fromRGB(
        235,
        235,
        235
    )

bar.BorderSizePixel =
    0

bar.Parent =
    barBg

Instance.new(
    "UICorner",
    bar
).CornerRadius =
    UDim.new(
        1,
        0
    )

local linkLabel =
    Instance.new(
        "TextLabel"
    )

linkLabel.Size =
    UDim2.new(
        1,
        -20,
        0,
        18
    )

linkLabel.Position =
    UDim2.fromOffset(
        10,
        123
    )

linkLabel.BackgroundTransparency =
    1

linkLabel.Text =
    ""

linkLabel.Font =
    Enum.Font.Gotham

linkLabel.TextSize =
    10

linkLabel.TextColor3 =
    Color3.fromRGB(
        150,
        150,
        155
    )

linkLabel.TextXAlignment =
    Enum.TextXAlignment.Left

linkLabel.TextTruncate =
    Enum.TextTruncate.AtEnd

linkLabel.Parent =
    main

local function makeButton(
    text,
    x,
    y,
    width
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.fromOffset(
            width,
            34
        )

    button.Position =
        UDim2.fromOffset(
            x,
            y
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            30,
            30,
            35
        )

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        11

    button.TextColor3 =
        Color3.fromRGB(
            245,
            245,
            245
        )

    button.Parent =
        main

    Instance.new(
        "UICorner",
        button
    ).CornerRadius =
        UDim.new(
            0,
            8
        )

    return button
end

local startBtn =
    makeButton(
        "INICIAR SCAN",
        10,
        148,
        151
    )

local testBtn =
    makeButton(
        "TESTES",
        169,
        148,
        151
    )

local stopBtn =
    makeButton(
        "INTERROMPER",
        10,
        190,
        151
    )

local sendBtn =
    makeButton(
        "ENVIAR",
        169,
        190,
        151
    )

--==============================================================
-- UI FUNCTIONS
--==============================================================

local function setUploadStatus(
    textValue,
    color
)

    uploadStatus.Text =
        "STATUS • "
        ..
        tostring(
            textValue or ""
        )

    if color then

        uploadStatus.TextColor3 =
            color
    end
end

local function setUploadProgress(
    value
)

    bar.Size =
        UDim2.fromScale(
            math.clamp(
                tonumber(value)
                or 0,
                0,
                1
            ),
            1
        )
end

local function refreshInfo()

    local mb =
        STATE.ApproxBytes
        /
        1024
        /
        1024

    scanSizeLabel.Text =
        string.format(
            "SCAN • %.1f MB / 150 MB • T:%d • EVT:%d",
            mb,
            STATE.TestsRun,
            STATE.RemoteEventsObserved
        )

    detailLabel.Text =
        string.format(
            "%d registros • pass %d • novos %d • %s",
            #STATE.Records,
            STATE.Pass,
            STATE.NewThisPass,
            tostring(
                STATE.CurrentArea
            )
        )
end

--==============================================================
-- DRAG
--==============================================================

local dragging =
    false

local dragStart =
    nil

local startPosition =
    nil

connect(
    main.InputBegan,

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

            dragStart =
                input.Position

            startPosition =
                main.Position
        end
    end
)

connect(
    main.InputEnded,

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

connect(
    UserInputService.InputChanged,

    function(input)

        if not dragging
        or not dragStart
        or not startPosition
        then
            return
        end

        if
            input.UserInputType ~=
                Enum.UserInputType.Touch
            and
            input.UserInputType ~=
                Enum.UserInputType.MouseMovement
        then
            return
        end

        local delta =
            input.Position
            -
            dragStart

        main.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset
                    +
                    delta.X,

                startPosition.Y.Scale,
                startPosition.Y.Offset
                    +
                    delta.Y
            )
    end
)

--==============================================================
-- SCANNER
--==============================================================

local function scannerLoop()

    if STATE.Running then
        return
    end

    resetState()

    STATE.Running =
        true

    STATE.CurrentArea =
        "Iniciando"

    setUploadProgress(
        0
    )

    setUploadStatus(
        "coletando...",
        Color3.fromRGB(
            120,
            190,
            255
        )
    )

    linkLabel.Text =
        ""

    refreshInfo()

    task.spawn(function()

        while
            STATE.Running
            and
            not STATE.StopRequested
            and
            not Runtime.Closed
        do

            if STATE.ApproxBytes >=
                CONFIG.MaxBytesApprox
            then

                STATE.LimitReached =
                    true

                STATE.StopRequested =
                    true

                break
            end

            local ok, err =
                xpcall(
                    runPass,
                    debug.traceback
                )

            if not ok then

                STATE.Running =
                    false

                setUploadStatus(
                    "erro: "
                    ..
                    tostring(err),

                    Color3.fromRGB(
                        255,
                        100,
                        100
                    )
                )

                return
            end

            refreshInfo()

            if STATE.StopRequested then
                break
            end

            local elapsed =
                0

            while elapsed <
                CONFIG.ScanInterval
                and
                not STATE.StopRequested
                and
                not Runtime.Closed
            do

                task.wait(
                    0.1
                )

                elapsed +=
                    0.1
            end
        end

        STATE.Running =
            false

        STATE.FinishedAt =
            now()

        STATE.CurrentArea =
            "Pronto para envio"

        if STATE.LimitReached then

            setUploadStatus(
                "limite de coleta atingido",
                Color3.fromRGB(
                    140,
                    255,
                    170
                )
            )

        else

            setUploadStatus(
                "scan encerrado",
                Color3.fromRGB(
                    180,
                    180,
                    185
                )
            )
        end

        refreshInfo()
    end)
end

--==============================================================
-- PATH RESOLVER
--==============================================================

local function resolvePath(
    path
)

    local current =
        game

    for part in string.gmatch(
        tostring(
            path or ""
        ),
        "[^%.]+"
    ) do

        if part == "game" then

            current =
                game

        elseif current == game then

            local ok, service =
                pcall(function()

                    return game:
                        GetService(
                            part
                        )
                end)

            current =
                ok
                and
                service
                or
                game:
                FindFirstChild(
                    part
                )

        else

            current =
                current
                and
                current:
                FindFirstChild(
                    part
                )
                or
                nil
        end

        if not current then
            return nil
        end
    end

    return current
end

--==============================================================
-- RISK CATALOG
--==============================================================

local function classifyRemoteRisk(
    remote
)

    local name =
        lower(
            remote.Name
        )

    local path =
        lower(
            safeFullName(
                remote
            )
        )

    local tags =
        {}

    local function tag(
        word,
        label
    )

        if
            string.find(
                name,
                word,
                1,
                true
            )
            or
            string.find(
                path,
                word,
                1,
                true
            )
        then

            tags[
                #tags + 1
            ] =
                label
        end
    end

    tag(
        "admin",
        "authorization"
    )

    tag(
        "money",
        "economy"
    )

    tag(
        "cash",
        "economy"
    )

    tag(
        "purchase",
        "purchase"
    )

    tag(
        "gamepass",
        "entitlement"
    )

    tag(
        "give",
        "grant"
    )

    tag(
        "reset",
        "destructive"
    )

    tag(
        "damage",
        "combat"
    )

    tag(
        "shoot",
        "combat"
    )

    tag(
        "teleport",
        "movement"
    )

    tag(
        "rebirth",
        "progression"
    )

    return tags
end

local function catalogTestSurface()

    local count =
        0

    local processed =
        0

    for _, obj in ipairs(
        ReplicatedStorage:
        GetDescendants()
    ) do

        processed +=
            1

        if
            obj:IsA(
                "RemoteEvent"
            )
            or
            obj:IsA(
                "RemoteFunction"
            )
            or
            obj.ClassName ==
                "UnreliableRemoteEvent"
        then

            count +=
                1

            local path =
                safeFullName(obj)

            addRecord(
                "TestSurface",

                "remote_review",

                "review|"
                ..
                path,

                {
                    path =
                        path,

                    class =
                        obj.ClassName,

                    riskTags =
                        classifyRemoteRisk(
                            obj
                        ),

                    safeAutoCall =
                        string.find(
                            lower(path),
                            lower(
                                CONFIG.SafeTestServicePath
                            ),
                            1,
                            true
                        ) ~= nil
                        and
                        CONFIG.SafeTestNames[
                            obj.Name
                        ] == true,
                }
            )
        end

        if processed % 250 == 0 then
            RunService.Heartbeat:Wait()
        end
    end

    return count
end

--==============================================================
-- TEST SNAPSHOT
--==============================================================

local function captureFocusedSnapshot(
    label,
    testId
)

    local snapshot = {

        label =
            label,

        testId =
            testId,

        time =
            now(),

        leaderstats =
            {},

        backpack =
            {},

        character =
            {},

        tycoon =
            {},
    }

    local leaderstats =
        LocalPlayer:
        FindFirstChild(
            "leaderstats"
        )

    if leaderstats then

        for _, value in ipairs(
            leaderstats:
            GetDescendants()
        ) do

            if value:IsA(
                "ValueBase"
            )
            then

                snapshot.leaderstats[
                    safeFullName(value)
                ] =
                    snapshotValue(
                        value
                    )
            end
        end
    end

    local backpack =
        LocalPlayer:
        FindFirstChild(
            "Backpack"
        )

    if backpack then

        for _, tool in ipairs(
            backpack:
            GetChildren()
        ) do

            if tool:IsA(
                "Tool"
            )
            then

                snapshot.backpack[
                    tool.Name
                ] =
                    snapshotValue(
                        tool
                    )
            end
        end
    end

    local character =
        LocalPlayer.Character

    if character then

        for _, tool in ipairs(
            character:
            GetChildren()
        ) do

            if tool:IsA(
                "Tool"
            )
            then

                snapshot.character[
                    tool.Name
                ] =
                    snapshotValue(
                        tool
                    )
            end
        end
    end

    local tycoons =
        Workspace:
        FindFirstChild(
            "Tycoons"
        )

    if tycoons then

        for _, tycoon in ipairs(
            tycoons:
            GetChildren()
        ) do

            local core =
                tycoon:
                FindFirstChild(
                    "CoreBuild"
                )

            local collector =
                core
                and
                core:
                FindFirstChild(
                    "Collector"
                )

            if collector
            and
            tostring(
                collector:
                GetAttribute(
                    "Owner"
                )
                or ""
            ) ==
                LocalPlayer.Name
            then

                local buttons =
                    tycoon:
                    FindFirstChild(
                        "Buttons"
                    )

                local purchases =
                    tycoon:
                    FindFirstChild(
                        "Purchases"
                    )

                snapshot.tycoon = {

                    path =
                        safeFullName(
                            tycoon
                        ),

                    buttonCount =
                        buttons
                        and
                        #buttons:
                        GetChildren()
                        or
                        0,

                    purchaseCount =
                        purchases
                        and
                        #purchases:
                        GetChildren()
                        or
                        0,
                }

                break
            end
        end
    end

    addRecord(
        "Tests",

        "focused_snapshot",

        "snapshot|"
        ..
        tostring(testId)
        ..
        "|"
        ..
        tostring(label),

        snapshot,

        true
    )

    return snapshot
end

--==============================================================
-- SAFE TEST
--==============================================================

local function executeSafeRemoteTest(
    remote
)

    STATE.TestsRun +=
        1

    local testId =
        HttpService:
        GenerateGUID(
            false
        )

    local started =
        now()

    STATE.ActiveTestId =
        testId

    STATE.ActiveTestRemote =
        safeFullName(
            remote
        )

    STATE.ActiveTestStarted =
        started

    local args =
        {}

    if remote.Name ==
        "Echo"
    then

        args = {
            "CAFEINA_V61",
            testId,
        }

    elseif remote.Name ==
        "ValidateNumber"
    then

        args = {
            123.456
        }

    elseif remote.Name ==
        "ValidateString"
    then

        args = {
            "CAFEINA_TEST_V61"
        }

    elseif remote.Name ==
        "ClientDiagnostic"
    then

        args = {
            {
                scanner =
                    "CAFEINA_TEST_LAB_V61",

                test =
                    true,

                testId =
                    testId,

                placeId =
                    game.PlaceId,

                timestamp =
                    os.time(),
            }
        }
    end

    addRecord(
        "Tests",

        "test_start",

        "test-start|"
        ..
        testId,

        {
            testId =
                testId,

            path =
                safeFullName(
                    remote
                ),

            class =
                remote.ClassName,

            args =
                serializeValue(
                    args
                ),
        },

        true
    )

    captureFocusedSnapshot(
        "before",
        testId
    )

    if remote:IsA(
        "RemoteFunction"
    )
    then

        local ok, result =
            pcall(function()

                return remote:
                    InvokeServer(
                        table.unpack(
                            args
                        )
                    )
            end)

        local latency =
            now()
            -
            started

        if ok then

            STATE.TestsPassed +=
                1

        else

            STATE.TestsErrors +=
                1
        end

        addRecord(
            "Tests",

            ok
                and
                "passed"
                or
                "error",

            "test-result|"
            ..
            testId,

            {
                testId =
                    testId,

                path =
                    safeFullName(
                        remote
                    ),

                class =
                    remote.ClassName,

                latency =
                    latency,

                response =
                    ok
                    and
                    serializeValue(
                        result
                    )
                    or
                    nil,

                error =
                    ok
                    and
                    nil
                    or
                    tostring(result),
            },

            true
        )

    else

        local ok, err =
            pcall(function()

                remote:
                    FireServer(
                        table.unpack(
                            args
                        )
                    )
            end)

        local latency =
            now()
            -
            started

        if ok then

            STATE.TestsPassed +=
                1

        else

            STATE.TestsErrors +=
                1
        end

        addRecord(
            "Tests",

            ok
                and
                "sent"
                or
                "error",

            "test-result|"
            ..
            testId,

            {
                testId =
                    testId,

                path =
                    safeFullName(
                        remote
                    ),

                class =
                    remote.ClassName,

                latency =
                    latency,

                error =
                    ok
                    and
                    nil
                    or
                    tostring(err),
            },

            true
        )
    end

    -- janela para observar respostas/eventos posteriores
    local elapsed =
        0

    while
        elapsed <
        CONFIG.TestResponseWindow
        and
        not Runtime.Closed
    do

        task.wait(
            0.10
        )

        elapsed +=
            0.10
    end

    captureFocusedSnapshot(
        "after",
        testId
    )

    addRecord(
        "Tests",

        "test_end",

        "test-end|"
        ..
        testId,

        {
            testId =
                testId,

            duration =
                now()
                -
                started,

            observedServerEvents =
                STATE.RemoteEventsObserved,
        },

        true
    )

    STATE.ActiveTestId =
        nil

    STATE.ActiveTestRemote =
        nil

    STATE.ActiveTestStarted =
        0
end

--==============================================================
-- CONTROLLED TEST SUITE
--==============================================================

local function runControlledTests()

    if STATE.Testing then
        return
    end

    if STATE.Sending then

        setUploadStatus(
            "aguarde o envio terminar",
            Color3.fromRGB(
                255,
                220,
                120
            )
        )

        return
    end

    STATE.Testing =
        true

    testBtn.Text =
        "TESTANDO..."

    setUploadStatus(
        "mapeando superfície...",
        Color3.fromRGB(
            120,
            190,
            255
        )
    )

    task.spawn(function()

        local ok, err =
            xpcall(
                function()

                    local reviewed =
                        catalogTestSurface()

                    addRecord(
                        "Tests",

                        "suite_start",

                        "suite|"
                        ..
                        tostring(
                            os.time()
                        ),

                        {
                            reviewedRemotes =
                                reviewed,

                            safeService =
                                CONFIG.SafeTestServicePath,

                            responseWindow =
                                CONFIG.TestResponseWindow,
                        },

                        true
                    )

                    local service =
                        resolvePath(
                            CONFIG.SafeTestServicePath
                        )

                    if not service then

                        STATE.TestsBlocked +=
                            1

                        addRecord(
                            "Tests",

                            "blocked",

                            "safe-service-missing|"
                            ..
                            tostring(
                                os.time()
                            ),

                            {
                                reason =
                                    "SecurityTestService não encontrado.",

                                expectedPath =
                                    CONFIG.SafeTestServicePath,
                            },

                            true
                        )

                        return
                    end

                    local remotes =
                        {}

                    for _, remote in ipairs(
                        service:
                        GetDescendants()
                    ) do

                        if
                            remote:IsA(
                                "RemoteEvent"
                            )
                            or
                            remote:IsA(
                                "RemoteFunction"
                            )
                            or
                            remote.ClassName ==
                                "UnreliableRemoteEvent"
                        then

                            table.insert(
                                remotes,
                                remote
                            )
                        end
                    end

                    table.sort(
                        remotes,

                        function(a, b)

                            return
                                a.Name
                                <
                                b.Name
                        end
                    )

                    for _, remote in ipairs(
                        remotes
                    ) do

                        if Runtime.Closed then
                            break
                        end

                        if CONFIG.SafeTestNames[
                            remote.Name
                        ]
                        then

                            setUploadStatus(
                                "teste: "
                                ..
                                remote.Name,

                                Color3.fromRGB(
                                    120,
                                    190,
                                    255
                                )
                            )

                            executeSafeRemoteTest(
                                remote
                            )

                            refreshInfo()

                            task.wait(
                                CONFIG.SafeTestDelay
                            )

                        else

                            STATE.TestsBlocked +=
                                1

                            addRecord(
                                "Tests",

                                "blocked",

                                "blocked|"
                                ..
                                safeFullName(
                                    remote
                                ),

                                {
                                    path =
                                        safeFullName(
                                            remote
                                        ),

                                    reason =
                                        "Remote fora da allowlist de teste.",
                                }
                            )
                        end
                    end

                    -- passe adicional pós-testes
                    local previousStop =
                        STATE.StopRequested

                    STATE.StopRequested =
                        false

                    runPass()

                    STATE.StopRequested =
                        previousStop
                end,

                debug.traceback
            )

        if not ok then

            STATE.TestsErrors +=
                1

            addRecord(
                "Tests",

                "suite_error",

                "suite-error|"
                ..
                tostring(
                    os.time()
                ),

                {
                    error =
                        tostring(err)
                },

                true
            )

            setUploadStatus(
                "erro nos testes",
                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

        else

            setUploadStatus(
                string.format(
                    "testes %d • ok %d • bloqueados %d • eventos %d",
                    STATE.TestsRun,
                    STATE.TestsPassed,
                    STATE.TestsBlocked,
                    STATE.RemoteEventsObserved
                ),

                Color3.fromRGB(
                    140,
                    255,
                    170
                )
            )
        end

        STATE.Testing =
            false

        testBtn.Text =
            "TESTES"

        refreshInfo()
    end)
end

--==============================================================
-- HTTP
--==============================================================

local function getRequest()

    return
        (
            syn
            and
            syn.request
        )
        or
        http_request
        or
        request
        or
        (
            http
            and
            http.request
        )
end

local function getClipboard()

    if typeof(setclipboard) ==
        "function"
    then
        return setclipboard
    end

    if typeof(toclipboard) ==
        "function"
    then
        return toclipboard
    end

    return nil
end

local function withToken(
    body
)

    if CONFIG.UPLOAD_TOKEN ~=
        ""
    then

        body.token =
            CONFIG.UPLOAD_TOKEN
    end

    return body
end

local function postJson(
    url,
    body
)

    local req =
        getRequest()

    if not req then

        return false,
            "Executor sem HTTP."
    end

    local okEncode,
          encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            body
        )

    if not okEncode then

        return false,
            "Erro JSON: "
            ..
            tostring(encoded)
    end

    local lastError =
        "Falha desconhecida"

    for attempt = 1,
        CONFIG.UploadRetries
    do

        if STATE.UploadCancelled
        or
        Runtime.Closed
        then

            return false,
                "cancelado"
        end

        local ok, response =
            pcall(
                req,
                {
                    Url =
                        url,

                    Method =
                        "POST",

                    Headers = {
                        ["Content-Type"] =
                            "application/json",

                        ["Accept"] =
                            "application/json",
                    },

                    Body =
                        encoded,
                }
            )

        if ok
        and
        response
        then

            local code =
                tonumber(
                    response.StatusCode
                    or
                    response.Status
                    or
                    0
                )
                or
                0

            local raw =
                response.Body
                or
                response.body
                or
                ""

            if code >= 200
            and
            code < 300
            then

                if raw == "" then
                    return true, {}
                end

                local decodeOk,
                      decoded =
                    pcall(
                        HttpService.JSONDecode,
                        HttpService,
                        raw
                    )

                if decodeOk then
                    return true, decoded
                end

                return true,
                    {
                        raw = raw
                    }
            end

            lastError =
                "HTTP "
                ..
                tostring(code)

        else

            lastError =
                tostring(response)
        end

        if attempt <
            CONFIG.UploadRetries
        then

            task.wait(
                CONFIG.UploadRetryDelay
                *
                attempt
            )
        end
    end

    return false,
        lastError
end

--==============================================================
-- UPLOAD
--==============================================================

local function makeFilename()

    return string.format(
        "Cafeina_TestLabV61_%s_%s.json",

        tostring(
            game.PlaceId
        ),

        os.date(
            "!%Y%m%d_%H%M%S"
        )
    )
end

local function sendExport()

    if STATE.Sending then
        return
    end

    if STATE.Running then

        setUploadStatus(
            "interrompa o scan antes de enviar",
            Color3.fromRGB(
                255,
                220,
                120
            )
        )

        return
    end

    if STATE.Testing then

        setUploadStatus(
            "aguarde os testes terminarem",
            Color3.fromRGB(
                255,
                220,
                120
            )
        )

        return
    end

    if #STATE.Records == 0 then

        setUploadStatus(
            "nenhum dado",
            Color3.fromRGB(
                255,
                180,
                100
            )
        )

        return
    end

    STATE.Sending =
        true

    STATE.UploadCancelled =
        false

    STATE.UploadId =
        nil

    STATE.BytesSent =
        0

    STATE.ChunksSent =
        0

    STATE.TotalChunks =
        0

    setUploadProgress(
        0
    )

    linkLabel.Text =
        ""

    sendBtn.Text =
        "ENVIANDO..."

    task.spawn(function()

        local filename =
            makeFilename()

        setUploadStatus(
            "abrindo envio...",
            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local startOk,
              startResult =
            postJson(
                CONFIG.UPLOAD_BASE
                ..
                "/start",

                withToken(
                    {
                        filename =
                            filename,

                        source =
                            "cafeina-test-lab-v6.1",

                        metadata = {

                            placeId =
                                game.PlaceId,

                            gameId =
                                game.GameId,

                            jobId =
                                game.JobId,

                            clientVisibleOnly =
                                true,

                            scanner =
                                "CAFEINA TEST LAB V6.1",

                            version =
                                CONFIG.VERSION,

                            recordCount =
                                #STATE.Records,

                            bytesApprox =
                                STATE.ApproxBytes,

                            passes =
                                STATE.Pass,

                            testsRun =
                                STATE.TestsRun,

                            testsPassed =
                                STATE.TestsPassed,

                            testsBlocked =
                                STATE.TestsBlocked,

                            testsErrors =
                                STATE.TestsErrors,

                            remoteEventsObserved =
                                STATE.RemoteEventsObserved,
                        }
                    }
                )
            )

        if
            not startOk
            or
            type(startResult) ~= "table"
            or
            not startResult.uploadId
        then

            STATE.Sending =
                false

            sendBtn.Text =
                "ENVIAR"

            setUploadStatus(
                "erro ao abrir upload",
                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

            return
        end

        STATE.UploadId =
            tostring(
                startResult.uploadId
            )

        --======================================================
        -- BUILD CHUNKS
        --======================================================

        setUploadStatus(
            "gerando chunks...",
            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local chunks =
            {}

        local current =
            {}

        local currentBytes =
            2

        for index, record in ipairs(
            STATE.Records
        ) do

            local ok,
                  encoded =
                pcall(
                    HttpService.JSONEncode,
                    HttpService,
                    record
                )

            if ok then

                local recordBytes =
                    #encoded + 1

                if
                    #current > 0
                    and
                    currentBytes
                    +
                    recordBytes
                    >
                    CONFIG.UploadChunkBytes
                then

                    table.insert(
                        chunks,
                        current
                    )

                    current =
                        {}

                    currentBytes =
                        2
                end

                table.insert(
                    current,
                    record
                )

                currentBytes +=
                    recordBytes
            end

            if index % 1000 == 0 then
                RunService.Heartbeat:Wait()
            end
        end

        if #current > 0 then

            table.insert(
                chunks,
                current
            )
        end

        STATE.TotalChunks =
            #chunks

        if #chunks == 0 then

            STATE.Sending =
                false

            sendBtn.Text =
                "ENVIAR"

            setUploadStatus(
                "nenhum chunk",
                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

            return
        end

        --======================================================
        -- SEND CHUNKS
        --======================================================

        for index,
            objects
        in ipairs(
            chunks
        ) do

            if STATE.UploadCancelled
            or
            Runtime.Closed
            then
                break
            end

            local before =
                (
                    index - 1
                )
                /
                #chunks

            setUploadProgress(
                before
            )

            setUploadStatus(
                string.format(
                    "parte %d/%d • %d%%",
                    index,
                    #chunks,
                    math.floor(
                        before * 100
                    )
                ),

                Color3.fromRGB(
                    120,
                    190,
                    255
                )
            )

            local chunkOk,
                  chunkResult =
                postJson(
                    CONFIG.UPLOAD_BASE
                    ..
                    "/chunk",

                    withToken(
                        {
                            uploadId =
                                STATE.UploadId,

                            index =
                                index,

                            objects =
                                objects,
                        }
                    )
                )

            if not chunkOk then

                STATE.Sending =
                    false

                sendBtn.Text =
                    "ENVIAR"

                setUploadStatus(
                    "erro parte "
                    ..
                    tostring(index)
                    ..
                    ": "
                    ..
                    tostring(
                        chunkResult
                    ),

                    Color3.fromRGB(
                        255,
                        100,
                        100
                    )
                )

                return
            end

            STATE.ChunksSent =
                index

            local okBytes,
                  encodedObjects =
                pcall(
                    HttpService.JSONEncode,
                    HttpService,
                    objects
                )

            if okBytes then

                STATE.BytesSent +=
                    #encodedObjects
            end

            setUploadProgress(
                index
                /
                #chunks
            )
        end

        --======================================================
        -- FINISH
        --======================================================

        setUploadStatus(
            "finalizando...",
            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local finishOk,
              finishResult =
            postJson(
                CONFIG.UPLOAD_BASE
                ..
                "/finish",

                withToken(
                    {
                        uploadId =
                            STATE.UploadId,

                        totalChunks =
                            STATE.ChunksSent,

                        summary = {

                            records =
                                #STATE.Records,

                            chunks =
                                STATE.ChunksSent,

                            bytesApprox =
                                STATE.BytesSent,

                            scanBytesApprox =
                                STATE.ApproxBytes,

                            clientVisibleOnly =
                                true,

                            interrupted =
                                STATE.StopRequested,

                            limitReached =
                                STATE.LimitReached,

                            passes =
                                STATE.Pass,

                            testsRun =
                                STATE.TestsRun,

                            testsPassed =
                                STATE.TestsPassed,

                            testsBlocked =
                                STATE.TestsBlocked,

                            testsErrors =
                                STATE.TestsErrors,

                            remoteEventsObserved =
                                STATE.RemoteEventsObserved,

                            categories =
                                STATE.CategoryCount,
                        }
                    }
                )
            )

        STATE.Sending =
            false

        sendBtn.Text =
            "ENVIAR"

        if not finishOk then

            setUploadStatus(
                "erro ao finalizar",
                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

            return
        end

        local url =
            type(finishResult) ==
                "table"
            and
            (
                finishResult.downloadUrl
                or
                finishResult.url
            )
            or
            nil

        if not url
        or
        tostring(url) ==
            ""
        then

            setUploadStatus(
                "concluído sem link",
                Color3.fromRGB(
                    255,
                    180,
                    100
                )
            )

            return
        end

        url =
            tostring(url)

        if string.sub(
            url,
            1,
            1
        ) ==
            "/"
        then

            url =
                CONFIG.BASE_URL
                ..
                url
        end

        STATE.LastURL =
            url

        linkLabel.Text =
            url

        setUploadProgress(
            1
        )

        setUploadStatus(
            "100% • link copiado",
            Color3.fromRGB(
                140,
                255,
                170
            )
        )

        local clipboard =
            getClipboard()

        if clipboard then

            pcall(
                clipboard,
                url
            )
        end
    end)
end

--==============================================================
-- RUNTIME OBSERVERS
--==============================================================

if CONFIG.ObserveRuntimeObjects then

    observeRoot(
        ReplicatedStorage,
        "ReplicatedStorage"
    )

    observeRoot(
        ReplicatedFirst,
        "ReplicatedFirst"
    )

    observeRoot(
        Workspace,
        "Workspace"
    )

    observeRoot(
        PlayerGui,
        "PlayerGui"
    )

    local backpack =
        LocalPlayer:
        FindFirstChild(
            "Backpack"
        )

    if backpack then

        observeRoot(
            backpack,
            "Backpack"
        )
    end

    connect(
        LocalPlayer.CharacterAdded,

        function(character)

            observeRoot(
                character,
                "Character"
            )
        end
    )
end

--==============================================================
-- BUTTONS
--==============================================================

connect(
    startBtn.MouseButton1Click,

    function()

        if STATE.Running then
            return
        end

        if STATE.Sending
        or
        STATE.Testing
        then

            setUploadStatus(
                "aguarde a operação atual",
                Color3.fromRGB(
                    255,
                    220,
                    120
                )
            )

            return
        end

        scannerLoop()
    end
)

connect(
    testBtn.MouseButton1Click,

    function()

        runControlledTests()
    end
)

connect(
    stopBtn.MouseButton1Click,

    function()

        if STATE.Running then

            STATE.StopRequested =
                true

            setUploadStatus(
                "encerrando scan...",
                Color3.fromRGB(
                    255,
                    220,
                    120
                )
            )
        end
    end
)

connect(
    sendBtn.MouseButton1Click,

    function()

        sendExport()
    end
)

--==============================================================
-- INFO REFRESH
--==============================================================

connect(
    RunService.Heartbeat,

    function()

        if Runtime.Closed then
            return
        end

        refreshInfo()
    end
)

--==============================================================
-- SHUTDOWN
--==============================================================

function Runtime.Shutdown()

    if Runtime.Closed then
        return
    end

    Runtime.Closed =
        true

    STATE.StopRequested =
        true

    STATE.Running =
        false

    STATE.UploadCancelled =
        true

    local buckets = {

        Runtime.Connections,
        Runtime.RemoteConnections,
        Runtime.WatchConnections,
    }

    for _, bucket in ipairs(
        buckets
    ) do

        for _, connection in ipairs(
            bucket
        ) do

            pcall(function()

                connection:
                    Disconnect()
            end)
        end

        table.clear(
            bucket
        )
    end

    if Runtime.Gui then

        pcall(function()

            Runtime.Gui:
                Destroy()
        end)
    end

    if ENV.CAFEINA_TEST_LAB_V61 ==
        Runtime
    then

        ENV.CAFEINA_TEST_LAB_V61 =
            nil
    end
end

--==============================================================
-- START
--==============================================================

refreshInfo()

setUploadProgress(
    0
)

setUploadStatus(
    "aguardando",
    Color3.fromRGB(
        180,
        180,
        185
    )
)

print(
    "[CAFEÍNA] TEST LAB V6.1 carregado."
)
