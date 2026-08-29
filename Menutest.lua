--[[
====================================================================
 CAFEÍNA • TEST LAB V6.2
 CORRELATION ENGINE • MOBILE / EXECUTOR

 OBJETIVO
   • Inventário inicial inteligente
   • Observação contínua de runtime
   • Server → Client RemoteEvents
   • Attributes / ValueBase / lifecycle
   • Correlação temporal
   • Combate / Blaster
   • PlayerData
   • Tycoon
   • Soldiers
   • Tools
   • Testes contínuos controlados
   • Upload completo ao site

 FLUXO
   INICIAR SCAN
       ↓
   coleta contínua

   TESTES
       ↓
   testes contínuos enquanto scan estiver ativo

   INTERROMPER
       ↓
   para scan + testes

   ENVIAR
       ↓
   envia todos os registros ao site

 IMPORTANTE
   Testes ativos SOMENTE:
   ReplicatedStorage.__remotes.SecurityTestService

   Allowlist:
       Ping
       Echo
       ValidateNumber
       ValidateString
       ClientDiagnostic
====================================================================
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

local CoreGui =
    game:GetService("CoreGui")

local LocalPlayer =
    Players.LocalPlayer
    or
    Players.PlayerAdded:Wait()

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- EXECUTOR ENVIRONMENT
--==============================================================

local ENV = _G

if type(getgenv) == "function" then
    local ok, result =
        pcall(getgenv)

    if ok and result then
        ENV = result
    end
end

--==============================================================
-- REINJECTION
--==============================================================

if ENV.CAFEINA_TEST_LAB_V62
and
type(
    ENV.CAFEINA_TEST_LAB_V62.Shutdown
) == "function"
then
    pcall(
        ENV.CAFEINA_TEST_LAB_V62.Shutdown
    )
end

local Runtime = {

    Closed = false,

    Connections = {},
    RemoteConnections = {},
    ObjectConnections = {},

    Gui = nil,
}

ENV.CAFEINA_TEST_LAB_V62 =
    Runtime

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    VERSION =
        "6.2",

    SCANNER_NAME =
        "CAFEINA TEST LAB V6.2",

    --==========================================================
    -- COLLECTION LIMITS
    --==========================================================

    MaxRecords =
        120000,

    MaxBytesApprox =
        150 * 1024 * 1024,

    FocusedPassInterval =
        1.25,

    YieldEvery =
        300,

    --==========================================================
    -- EVENT / CORRELATION
    --==========================================================

    CorrelationWindow =
        2.50,

    RecentEventLimit =
        500,

    AttributeDebounce =
        0.07,

    ValueDebounce =
        0.05,

    --==========================================================
    -- TESTS
    --==========================================================

    SafeTestServicePath =
        "ReplicatedStorage.__remotes.SecurityTestService",

    TestRemoteDelay =
        0.20,

    TestCycleDelay =
        0.70,

    TestResponseWindow =
        0.55,

    SafeTestNames = {

        Ping =
            true,

        Echo =
            true,

        ValidateNumber =
            true,

        ValidateString =
            true,

        ClientDiagnostic =
            true,
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

    --==========================================================
    -- INTERESTING WORDS
    --==========================================================

    InterestingNames = {

        "damage",
        "health",
        "kill",
        "death",

        "ammo",
        "reload",
        "shoot",
        "shot",
        "projectile",
        "bullet",
        "hit",
        "headshot",

        "weapon",
        "gun",
        "blaster",

        "money",
        "cash",
        "storedmoney",
        "collect",

        "purchase",
        "button",
        "tycoon",
        "rebirth",

        "playerdata",
        "leaderstats",

        "soldier",
        "npc",
        "aggro",
        "target",

        "team",

        "inventory",
        "loadout",
        "equip",

        "notification",
        "spectate",

        "flag",
        "setting",

        "admin",
        "permission",
        "auth",
    },

    --==========================================================
    -- ATTRIBUTES
    --==========================================================

    InterestingAttributes = {

        damage = true,
        criticalDamageMultiplier = true,

        projectileType = true,
        range = true,

        fireMode = true,
        rateOfFire = true,
        spread = true,

        magazineSize = true,

        _ammo = true,
        _reloading = true,

        reloadType = true,
        reloadTime = true,
        reloadTimePerRound = true,

        recoilMin = true,
        recoilMax = true,

        Purchase = true,
        importFromSetting = true,

        Price = true,
        Dependency = true,
        Owner = true,

        Gamepass = true,
        NonPurchase = true,
        Rebirths = true,

        HealthMult = true,
        FireRate = true,
        DamageMult = true,
        DamagePerSecond = true,

        Health = true,
        Team = true,
        Gun = true,

        SpeedMult = true,
        MagSize = true,

        StoredMoney = true,
    },
}

--==============================================================
-- STATE
--==============================================================

local STATE = {

    Running =
        false,

    AutoTesting =
        false,

    Testing =
        false,

    Sending =
        false,

    StopRequested =
        false,

    TestStopRequested =
        false,

    LimitReached =
        false,

    --==========================================================
    -- SCAN
    --==========================================================

    Pass =
        0,

    StartedAt =
        0,

    FinishedAt =
        0,

    CurrentArea =
        "Aguardando",

    Records =
        {},

    ApproxBytes =
        0,

    Added =
        0,

    Changed =
        0,

    Removed =
        0,

    NewThisPass =
        0,

    CategoryCount =
        {},

    --==========================================================
    -- DEDUP
    --==========================================================

    Snapshots =
        {},

    CataloguedRemotes =
        {},

    EventShapes =
        {},

    ObservedRemotes =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        ),

    WatchedObjects =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        ),

    --==========================================================
    -- RUNTIME
    --==========================================================

    RemoteEventsObserved =
        0,

    RecentEvents =
        {},

    --==========================================================
    -- TESTS
    --==========================================================

    SafeServiceChecked =
        false,

    SafeServiceAvailable =
        false,

    SafeTestRemotes =
        {},

    TestCycle =
        0,

    TestsRun =
        0,

    TestsInvoked =
        0,

    TestsSent =
        0,

    TestsPassed =
        0,

    TestsErrors =
        0,

    TestsBlocked =
        0,

    ActiveTestId =
        nil,

    ActiveTestRemote =
        nil,

    ActiveTestStarted =
        0,

    --==========================================================
    -- UPLOAD
    --==========================================================

    UploadId =
        nil,

    ChunksSent =
        0,

    TotalChunks =
        0,

    BytesSent =
        0,

    UploadCancelled =
        false,

    LastURL =
        nil,
}

--==============================================================
-- CONNECTION HELPER
--==============================================================

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

--==============================================================
-- BASIC HELPERS
--==============================================================

local function clock()
    return os.clock()
end

local function lower(
    value
)

    return string.lower(
        tostring(
            value or ""
        )
    )
end

local function safeFullName(
    object
)

    if not object then
        return "nil"
    end

    local ok, result =
        pcall(
            object.GetFullName,
            object
        )

    if ok then
        return result
    end

    return tostring(object)
end

local function containsInterestingName(
    value
)

    local text =
        lower(value)

    for _, token in ipairs(
        CONFIG.InterestingNames
    ) do

        if string.find(
            text,
            token,
            1,
            true
        )
        then
            return true,
                token
        end
    end

    return false
end

local function pathInteresting(
    object
)

    return containsInterestingName(
        safeFullName(
            object
        )
    )
end

--==============================================================
-- SERIALIZATION
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

    if
        valueType == "nil"
        or
        valueType == "string"
        or
        valueType == "number"
        or
        valueType == "boolean"
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
                safeFullName(
                    value
                ),
        }
    end

    if valueType == "Vector3" then

        return {

            type =
                "Vector3",

            x =
                value.X,

            y =
                value.Y,

            z =
                value.Z,
        }
    end

    if valueType == "Vector2" then

        return {

            type =
                "Vector2",

            x =
                value.X,

            y =
                value.Y,
        }
    end

    if valueType == "Color3" then

        return {

            type =
                "Color3",

            r =
                value.R,

            g =
                value.G,

            b =
                value.B,
        }
    end

    if valueType == "CFrame" then

        local position =
            value.Position

        return {

            type =
                "CFrame",

            position = {

                x =
                    position.X,

                y =
                    position.Y,

                z =
                    position.Z,
            }
        }
    end

    if valueType == "EnumItem" then

        return tostring(
            value
        )
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

            count +=
                1

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

    return tostring(
        value
    )
end

--==============================================================
-- JSON / SIZE
--==============================================================

local function encode(
    value
)

    local ok, result =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            value
        )

    if ok then
        return result
    end

    return nil
end

local function approxLen(
    value
)

    local encoded =
        encode(
            value
        )

    if encoded then
        return #encoded
    end

    return 64
end

--==============================================================
-- RECORDING
--==============================================================

local function addRecord(
    category,
    kind,
    key,
    data
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

        STATE.TestStopRequested =
            true

        STATE.AutoTesting =
            false

        return false
    end

    local record = {

        timestamp =
            os.time(),

        clock =
            clock(),

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

    local size =
        approxLen(
            record
        )

    if STATE.ApproxBytes + size >
        CONFIG.MaxBytesApprox
    then

        STATE.LimitReached =
            true

        STATE.StopRequested =
            true

        STATE.TestStopRequested =
            true

        STATE.AutoTesting =
            false

        return false
    end

    table.insert(
        STATE.Records,
        record
    )

    STATE.ApproxBytes +=
        size

    STATE.CategoryCount[
        category
    ] =
        (
            STATE.CategoryCount[
                category
            ]
            or
            0
        )
        +
        1

    STATE.NewThisPass +=
        1

    if kind == "baseline" then
        STATE.Added += 1
    elseif kind == "changed" then
        STATE.Changed += 1
    elseif kind == "removed" then
        STATE.Removed += 1
    end

    return true
end

--==============================================================
-- CORRELATION EVENT BUFFER
--==============================================================

local function addRecentEvent(
    eventType,
    source,
    data
)

    local event = {

        time =
            clock(),

        type =
            eventType,

        source =
            source,

        data =
            data,

        testId =
            STATE.ActiveTestId,
    }

    table.insert(
        STATE.RecentEvents,
        event
    )

    while #STATE.RecentEvents >
        CONFIG.RecentEventLimit
    do

        table.remove(
            STATE.RecentEvents,
            1
        )
    end

    return event
end

local function getRecentEvents(
    seconds
)

    local result =
        {}

    local threshold =
        clock()
        -
        (
            seconds
            or
            CONFIG.CorrelationWindow
        )

    for _, event in ipairs(
        STATE.RecentEvents
    ) do

        if event.time >=
            threshold
        then

            table.insert(
                result,
                event
            )
        end
    end

    return result
end

--==============================================================
-- SNAPSHOT
--==============================================================

local function getInterestingAttributes(
    object
)

    local result =
        {}

    local ok, attrs =
        pcall(
            object.GetAttributes,
            object
        )

    if not ok then
        return result
    end

    for name, value in pairs(
        attrs
    ) do

        if
            CONFIG.InterestingAttributes[
                name
            ]
            or
            containsInterestingName(
                name
            )
        then

            result[
                name
            ] =
                serializeValue(
                    value
                )
        end
    end

    return result
end

local function snapshotObject(
    object
)

    local data = {

        class =
            object.ClassName,

        name =
            object.Name,

        path =
            safeFullName(
                object
            ),

        attributes =
            getInterestingAttributes(
                object
            ),
    }

    if object:IsA(
        "ValueBase"
    )
    then

        local ok, value =
            pcall(function()

                return object.Value
            end)

        if ok then
            data.value =
                serializeValue(
                    value
                )
        end
    end

    if object:IsA(
        "Humanoid"
    )
    then

        data.health =
            object.Health

        data.maxHealth =
            object.MaxHealth

        data.walkSpeed =
            object.WalkSpeed
    end

    if object:IsA(
        "Tool"
    )
    then

        data.canBeDropped =
            object.CanBeDropped

        data.toolTip =
            object.ToolTip
    end

    if
        object:IsA("TextLabel")
        or
        object:IsA("TextButton")
    then

        data.text =
            string.sub(
                tostring(
                    object.Text
                ),
                1,
                500
            )

        data.visible =
            object.Visible
    end

    if object:IsA(
        "ProximityPrompt"
    )
    then

        data.actionText =
            object.ActionText

        data.objectText =
            object.ObjectText

        data.holdDuration =
            object.HoldDuration

        data.maxActivationDistance =
            object.MaxActivationDistance
    end

    return data
end

--==============================================================
-- DEDUP SNAPSHOT
--==============================================================

local function consider(
    category,
    object,
    force
)

    if
        not object
        or
        not object.Parent
    then
        return
    end

    if
        not force
        and
        not pathInteresting(
            object
        )
        and
        not object:IsA("RemoteEvent")
        and
        not object:IsA("RemoteFunction")
        and
        object.ClassName ~= "UnreliableRemoteEvent"
        and
        not object:IsA("Tool")
        and
        not object:IsA("ValueBase")
    then
        return
    end

    local data =
        snapshotObject(
            object
        )

    local fingerprint =
        encode(
            data
        )
        or
        tostring(data)

    local key =
        category
        ..
        "|"
        ..
        safeFullName(
            object
        )

    local previous =
        STATE.Snapshots[
            key
        ]

    if previous == nil then

        if addRecord(
            category,
            "baseline",
            key,
            data
        )
        then

            STATE.Snapshots[
                key
            ] =
                fingerprint
        end

    elseif previous ~=
        fingerprint
    then

        if addRecord(
            category,
            "changed",
            key,
            data
        )
        then

            STATE.Snapshots[
                key
            ] =
                fingerprint
        end
    end
end

--==============================================================
-- REMOTE CLASSIFICATION
--==============================================================

local function remoteCategory(
    remote
)

    local path =
        lower(
            safeFullName(
                remote
            )
        )

    if string.find(
        path,
        "blaster",
        1,
        true
    )
    then
        return "Blaster"
    end

    if string.find(
        path,
        "playerdata",
        1,
        true
    )
    then
        return "PlayerData"
    end

    if string.find(
        path,
        "tycoon",
        1,
        true
    )
    then
        return "Tycoon"
    end

    if string.find(
        path,
        "combat",
        1,
        true
    )
    then
        return "Combat"
    end

    if string.find(
        path,
        "death",
        1,
        true
    )
    or
    string.find(
        path,
        "spectate",
        1,
        true
    )
    then
        return "Death"
    end

    return "Other"
end

--==============================================================
-- ARGUMENT SHAPE
--==============================================================

local function shapeOf(
    value,
    depth
)

    depth =
        depth or 0

    if depth > 4 then
        return "..."
    end

    local t =
        typeof(value)

    if t == "Instance" then

        return
            "Instance<"
            ..
            value.ClassName
            ..
            ">"

    elseif t == "table" then

        local result =
            {}

        local count =
            0

        for key, child in pairs(
            value
        ) do

            count += 1

            if count > 20 then
                break
            end

            result[
                tostring(key)
            ] =
                shapeOf(
                    child,
                    depth + 1
                )
        end

        return result
    end

    return t
end

--==============================================================
-- SERVER → CLIENT REMOTE OBSERVATION
--==============================================================

local function observeRemote(
    remote
)

    if STATE.ObservedRemotes[
        remote
    ]
    then
        return
    end

    if
        not remote:IsA("RemoteEvent")
        and
        remote.ClassName ~=
            "UnreliableRemoteEvent"
    then
        return
    end

    STATE.ObservedRemotes[
        remote
    ] =
        true

    local connection =
        remote.OnClientEvent:
        Connect(function(...)

            if Runtime.Closed then
                return
            end

            if
                not STATE.Running
                and
                not STATE.AutoTesting
            then
                return
            end

            STATE.RemoteEventsObserved +=
                1

            local packed =
                table.pack(...)

            local args =
                {}

            local shapes =
                {}

            for i = 1,
                math.min(
                    packed.n,
                    40
                )
            do

                args[i] =
                    serializeValue(
                        packed[i]
                    )

                shapes[i] =
                    shapeOf(
                        packed[i]
                    )
            end

            local path =
                safeFullName(
                    remote
                )

            local shapeEncoded =
                encode(
                    shapes
                )
                or
                tostring(shapes)

            local shapeKey =
                path
                ..
                "|"
                ..
                shapeEncoded

            local firstShape =
                not STATE.EventShapes[
                    shapeKey
                ]

            if firstShape then

                STATE.EventShapes[
                    shapeKey
                ] =
                    true
            end

            local recent =
                getRecentEvents(
                    CONFIG.CorrelationWindow
                )

            local eventData = {

                path =
                    path,

                class =
                    remote.ClassName,

                remoteCategory =
                    remoteCategory(
                        remote
                    ),

                argumentCount =
                    packed.n,

                args =
                    args,

                shape =
                    shapes,

                firstObservedShape =
                    firstShape,

                recentContext =
                    recent,

                activeTest = {

                    id =
                        STATE.ActiveTestId,

                    remote =
                        STATE.ActiveTestRemote,

                    elapsed =
                        STATE.ActiveTestId
                        and
                        (
                            clock()
                            -
                            STATE.ActiveTestStarted
                        )
                        or
                        nil,
                },
            }

            addRecentEvent(
                "remote_server_client",
                path,
                {
                    shapes =
                        shapes,

                    args =
                        args,
                }
            )

            addRecord(
                "RemoteTraffic",

                firstShape
                    and
                    "server_event_new_shape"
                    or
                    "server_event",

                "evt|"
                ..
                tostring(
                    STATE.RemoteEventsObserved
                )
                ..
                "|"
                ..
                path,

                eventData
            )
        end)

    table.insert(
        Runtime.RemoteConnections,
        connection
    )
end

--==============================================================
-- WATCH OBJECT
--==============================================================

local function watchObject(
    object
)

    if STATE.WatchedObjects[
        object
    ]
    then
        return
    end

    STATE.WatchedObjects[
        object
    ] =
        true

    if
        object:IsA("RemoteEvent")
        or
        object.ClassName ==
            "UnreliableRemoteEvent"
    then

        observeRemote(
            object
        )
    end

    --==========================================================
    -- ATTRIBUTES
    --==========================================================

    local lastAttribute =
        {}

    local attrConnection =
        object.AttributeChanged:
        Connect(function(
            attribute
        )

            if Runtime.Closed
            or
            (
                not STATE.Running
                and
                not STATE.AutoTesting
            )
            then
                return
            end

            if
                not CONFIG.InterestingAttributes[
                    attribute
                ]
                and
                not containsInterestingName(
                    attribute
                )
            then
                return
            end

            local current =
                clock()

            if
                current
                -
                (
                    lastAttribute[
                        attribute
                    ]
                    or
                    0
                )
                <
                CONFIG.AttributeDebounce
            then
                return
            end

            lastAttribute[
                attribute
            ] =
                current

            local ok, value =
                pcall(
                    object.GetAttribute,
                    object,
                    attribute
                )

            if not ok then
                return
            end

            local path =
                safeFullName(
                    object
                )

            local data = {

                path =
                    path,

                class =
                    object.ClassName,

                attribute =
                    attribute,

                value =
                    serializeValue(
                        value
                    ),

                recentContext =
                    getRecentEvents(
                        CONFIG.CorrelationWindow
                    ),
            }

            addRecentEvent(
                "attribute",
                path
                ..
                "."
                ..
                attribute,
                data
            )

            addRecord(
                "Runtime",
                "attribute_changed",

                "attr|"
                ..
                path
                ..
                "|"
                ..
                attribute
                ..
                "|"
                ..
                tostring(current),

                data
            )
        end)

    table.insert(
        Runtime.ObjectConnections,
        attrConnection
    )

    --==========================================================
    -- VALUEBASE
    --==========================================================

    if object:IsA(
        "ValueBase"
    )
    then

        local lastValueChange =
            0

        local valueConnection =
            object.Changed:
            Connect(function(
                value
            )

                if Runtime.Closed
                or
                (
                    not STATE.Running
                    and
                    not STATE.AutoTesting
                )
                then
                    return
                end

                local current =
                    clock()

                if current -
                    lastValueChange
                    <
                    CONFIG.ValueDebounce
                then
                    return
                end

                lastValueChange =
                    current

                local path =
                    safeFullName(
                        object
                    )

                local data = {

                    path =
                        path,

                    class =
                        object.ClassName,

                    value =
                        serializeValue(
                            value
                        ),

                    recentContext =
                        getRecentEvents(
                            CONFIG.CorrelationWindow
                        ),
                }

                addRecentEvent(
                    "value",
                    path,
                    data
                )

                addRecord(
                    "Runtime",
                    "value_changed",

                    "value|"
                    ..
                    path
                    ..
                    "|"
                    ..
                    tostring(current),

                    data
                )
            end)

        table.insert(
            Runtime.ObjectConnections,
            valueConnection
        )
    end

    --==========================================================
    -- HUMANOID
    --==========================================================

    if object:IsA(
        "Humanoid"
    )
    then

        local healthConnection =
            object.HealthChanged:
            Connect(function(
                health
            )

                if Runtime.Closed
                or
                (
                    not STATE.Running
                    and
                    not STATE.AutoTesting
                )
                then
                    return
                end

                local path =
                    safeFullName(
                        object
                    )

                local data = {

                    path =
                        path,

                    health =
                        health,

                    maxHealth =
                        object.MaxHealth,

                    recentContext =
                        getRecentEvents(
                            CONFIG.CorrelationWindow
                        ),
                }

                addRecentEvent(
                    "humanoid_health",
                    path,
                    data
                )

                addRecord(
                    "CombatRuntime",
                    "health_changed",

                    "health|"
                    ..
                    path
                    ..
                    "|"
                    ..
                    tostring(clock()),

                    data
                )
            end)

        table.insert(
            Runtime.ObjectConnections,
            healthConnection
        )
    end
end

--==============================================================
-- SHOULD WATCH
--==============================================================

local function shouldWatch(
    object
)

    if
        object:IsA("RemoteEvent")
        or
        object:IsA("RemoteFunction")
        or
        object.ClassName ==
            "UnreliableRemoteEvent"
        or
        object:IsA("Tool")
        or
        object:IsA("ValueBase")
        or
        object:IsA("Humanoid")
        or
        object:IsA("ProximityPrompt")
        or
        object:IsA("ClickDetector")
        or
        object:IsA("TouchTransmitter")
    then
        return true
    end

    return pathInteresting(
        object
    )
end

--==============================================================
-- RUNTIME ROOT OBSERVER
--==============================================================

local function observeRoot(
    root,
    rootName
)

    if not root then
        return
    end

    connect(
        root.DescendantAdded,

        function(
            object
        )

            if Runtime.Closed then
                return
            end

            task.defer(function()

                if
                    Runtime.Closed
                    or
                    not object.Parent
                then
                    return
                end

                if shouldWatch(
                    object
                )
                then

                    watchObject(
                        object
                    )

                    if
                        STATE.Running
                        or
                        STATE.AutoTesting
                    then

                        local data =
                            snapshotObject(
                                object
                            )

                        addRecentEvent(
                            "object_added",
                            safeFullName(
                                object
                            ),
                            data
                        )

                        addRecord(
                            "Lifecycle",
                            "object_added",

                            "add|"
                            ..
                            safeFullName(
                                object
                            )
                            ..
                            "|"
                            ..
                            tostring(clock()),

                            {
                                root =
                                    rootName,

                                object =
                                    data,

                                recentContext =
                                    getRecentEvents(
                                        CONFIG.CorrelationWindow
                                    ),
                            }
                        )
                    end
                end
            end)
        end
    )

    connect(
        root.DescendantRemoving,

        function(
            object
        )

            if Runtime.Closed then
                return
            end

            if
                not STATE.Running
                and
                not STATE.AutoTesting
            then
                return
            end

            if shouldWatch(
                object
            )
            then

                local path =
                    safeFullName(
                        object
                    )

                local data = {

                    root =
                        rootName,

                    path =
                        path,

                    class =
                        object.ClassName,

                    name =
                        object.Name,

                    recentContext =
                        getRecentEvents(
                            CONFIG.CorrelationWindow
                        ),
                }

                addRecentEvent(
                    "object_removed",
                    path,
                    data
                )

                addRecord(
                    "Lifecycle",
                    "object_removed",

                    "remove|"
                    ..
                    path
                    ..
                    "|"
                    ..
                    tostring(clock()),

                    data
                )
            end
        end
    )
end

--==============================================================
-- REMOTE CATALOG
--==============================================================

local function catalogRemote(
    remote
)

    local path =
        safeFullName(
            remote
        )

    if STATE.CataloguedRemotes[
        path
    ]
    then
        return
    end

    STATE.CataloguedRemotes[
        path
    ] =
        true

    addRecord(
        "RemoteCatalog",
        "remote_discovered",

        "remote|"
        ..
        path,

        {
            path =
                path,

            name =
                remote.Name,

            class =
                remote.ClassName,

            category =
                remoteCategory(
                    remote
                ),
        }
    )

    observeRemote(
        remote
    )
end

--==============================================================
-- INITIAL SCAN ROOT
--==============================================================

local function scanRoot(
    root,
    category,
    predicate
)

    if not root then
        return
    end

    local descendants =
        root:GetDescendants()

    for index, object in ipairs(
        descendants
    ) do

        if
            STATE.StopRequested
            or
            Runtime.Closed
        then
            return
        end

        if
            object:IsA("RemoteEvent")
            or
            object:IsA("RemoteFunction")
            or
            object.ClassName ==
                "UnreliableRemoteEvent"
        then

            catalogRemote(
                object
            )
        end

        if shouldWatch(
            object
        )
        then
            watchObject(
                object
            )
        end

        local accepted =
            predicate == nil

        if predicate then

            local ok, result =
                pcall(
                    predicate,
                    object
                )

            accepted =
                ok
                and
                result == true
        end

        if accepted then

            consider(
                category,
                object,
                true
            )
        end

        if index %
            CONFIG.YieldEvery
            ==
            0
        then

            RunService.Heartbeat:
                Wait()
        end
    end
end

--==============================================================
-- PRIORITY ROOTS
--==============================================================

local function findPath(
    root,
    ...
)

    local current =
        root

    for _, name in ipairs({
        ...
    })
    do

        if not current then
            return nil
        end

        current =
            current:
            FindFirstChild(
                name
            )
    end

    return current
end

--==============================================================
-- INITIAL INVENTORY
--==============================================================

local function initialInventory()

    STATE.CurrentArea =
        "Remotes"

    scanRoot(
        ReplicatedStorage,
        "Remotes",

        function(
            object
        )

            return
                object:IsA("RemoteEvent")
                or
                object:IsA("RemoteFunction")
                or
                object.ClassName ==
                    "UnreliableRemoteEvent"
        end
    )

    if STATE.StopRequested then
        return
    end

    --==========================================================
    -- BLASTER
    --==========================================================

    STATE.CurrentArea =
        "Blaster"

    local blaster =
        ReplicatedStorage:
        FindFirstChild(
            "BlasterSystem"
        )

    if blaster then

        scanRoot(
            blaster,
            "Blaster",

            function(
                object
            )

                return
                    object:IsA("Tool")
                    or
                    object:IsA("ValueBase")
                    or
                    object:IsA("ModuleScript")
                    or
                    object:IsA("RemoteEvent")
                    or
                    object:IsA("RemoteFunction")
                    or
                    object.ClassName ==
                        "UnreliableRemoteEvent"
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    if STATE.StopRequested then
        return
    end

    --==========================================================
    -- TYCOON
    --==========================================================

    STATE.CurrentArea =
        "Tycoon"

    local tycoons =
        Workspace:
        FindFirstChild(
            "Tycoons"
        )

    if tycoons then

        scanRoot(
            tycoons,
            "Tycoon",

            function(
                object
            )

                return
                    object:IsA("ValueBase")
                    or
                    object:IsA("TouchTransmitter")
                    or
                    object:IsA("ProximityPrompt")
                    or
                    object:IsA("ClickDetector")
                    or
                    object:IsA("Tool")
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    if STATE.StopRequested then
        return
    end

    --==========================================================
    -- SOLDIERS
    --==========================================================

    STATE.CurrentArea =
        "Soldiers"

    local soldiers =
        Workspace:
        FindFirstChild(
            "Soldiers"
        )

    if soldiers then

        scanRoot(
            soldiers,
            "Soldiers",

            function(
                object
            )

                return
                    object:IsA("Model")
                    or
                    object:IsA("Humanoid")
                    or
                    object:IsA("Tool")
                    or
                    object:IsA("ValueBase")
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    if STATE.StopRequested then
        return
    end

    --==========================================================
    -- PLAYER DATA
    --==========================================================

    STATE.CurrentArea =
        "PlayerData"

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        local leaderstats =
            player:
            FindFirstChild(
                "leaderstats"
            )

        if leaderstats then

            scanRoot(
                leaderstats,
                "PlayerData",

                function(
                    object
                )

                    return
                        object:IsA(
                            "ValueBase"
                        )
                end
            )
        end
    end

    --==========================================================
    -- TOOLS
    --==========================================================

    STATE.CurrentArea =
        "Tools"

    local backpack =
        LocalPlayer:
        FindFirstChild(
            "Backpack"
        )

    if backpack then

        scanRoot(
            backpack,
            "Tools",

            function(
                object
            )

                return
                    object:IsA("Tool")
                    or
                    object:IsA("ValueBase")
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    if LocalPlayer.Character then

        scanRoot(
            LocalPlayer.Character,
            "Tools",

            function(
                object
            )

                return
                    object:IsA("Tool")
                    or
                    object:IsA("Humanoid")
                    or
                    object:IsA("ValueBase")
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    --==========================================================
    -- RELEVANT GUI
    --==========================================================

    STATE.CurrentArea =
        "GUI"

    scanRoot(
        PlayerGui,
        "GUI",

        function(
            object
        )

            if
                object:IsA("TextLabel")
                or
                object:IsA("TextButton")
            then

                return
                    pathInteresting(
                        object
                    )
                    or
                    containsInterestingName(
                        object.Text
                    )
            end

            return
                pathInteresting(
                    object
                )
        end
    )

    STATE.CurrentArea =
        "Runtime"
end

--==============================================================
-- FOCUSED PASS
--==============================================================

local function focusedPass()

    STATE.Pass +=
        1

    STATE.NewThisPass =
        0

    STATE.CurrentArea =
        "Blaster"

    local blaster =
        ReplicatedStorage:
        FindFirstChild(
            "BlasterSystem"
        )

    if blaster then

        scanRoot(
            blaster,
            "BlasterRuntime",

            function(
                object
            )

                return
                    object:IsA("Tool")
                    or
                    object:IsA("ValueBase")
                    or
                    pathInteresting(
                        object
                    )
            end
        )
    end

    if STATE.StopRequested then
        return
    end

    STATE.CurrentArea =
        "PlayerData"

    local leaderstats =
        LocalPlayer:
        FindFirstChild(
            "leaderstats"
        )

    if leaderstats then

        for _, object in ipairs(
            leaderstats:
            GetDescendants()
        ) do

            if object:IsA(
                "ValueBase"
            )
            then

                consider(
                    "PlayerDataRuntime",
                    object,
                    true
                )
            end
        end
    end

    if STATE.StopRequested then
        return
    end

    STATE.CurrentArea =
        "Tycoon"

    local tycoons =
        Workspace:
        FindFirstChild(
            "Tycoons"
        )

    if tycoons then

        for _, object in ipairs(
            tycoons:
            GetDescendants()
        ) do

            if
                object:IsA("ValueBase")
                or
                pathInteresting(
                    object
                )
            then

                consider(
                    "TycoonRuntime",
                    object,
                    true
                )
            end
        end
    end

    STATE.CurrentArea =
        "Runtime"
end

--==============================================================
-- SAFE PATH RESOLVER
--==============================================================

local function resolvePath(
    path
)

    local current =
        game

    for part in string.gmatch(
        tostring(path),
        "[^%.]+"
    )
    do

        if part == "game" then

            current =
                game

        elseif current == game then

            local ok, service =
                pcall(
                    game.GetService,
                    game,
                    part
                )

            if ok then
                current =
                    service
            else
                current =
                    game:
                    FindFirstChild(
                        part
                    )
            end

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
-- SECURITY TEST SERVICE DISCOVERY
--==============================================================

local function discoverSafeTestService()

    if STATE.SafeServiceChecked then
        return STATE.SafeServiceAvailable
    end

    STATE.SafeServiceChecked =
        true

    local service =
        resolvePath(
            CONFIG.SafeTestServicePath
        )

    if not service then

        STATE.SafeServiceAvailable =
            false

        STATE.TestsBlocked +=
            1

        addRecord(
            "Tests",
            "safe_service_missing",
            "safe-service-status",

            {
                available =
                    false,

                path =
                    CONFIG.SafeTestServicePath,
            }
        )

        return false
    end

    STATE.SafeServiceAvailable =
        true

    table.clear(
        STATE.SafeTestRemotes
    )

    for _, remote in ipairs(
        service:GetDescendants()
    ) do

        if
            (
                remote:IsA("RemoteEvent")
                or
                remote:IsA("RemoteFunction")
                or
                remote.ClassName ==
                    "UnreliableRemoteEvent"
            )
            and
            CONFIG.SafeTestNames[
                remote.Name
            ]
        then

            table.insert(
                STATE.SafeTestRemotes,
                remote
            )

            catalogRemote(
                remote
            )
        end
    end

    table.sort(
        STATE.SafeTestRemotes,

        function(a, b)
            return a.Name < b.Name
        end
    )

    addRecord(
        "Tests",
        "safe_service_ready",
        "safe-service-status",

        {
            available =
                true,

            path =
                CONFIG.SafeTestServicePath,

            remotes =
                #STATE.SafeTestRemotes,
        }
    )

    return true
end

--==============================================================
-- TEST ARGUMENTS
--==============================================================

local function getSafeTestArgs(
    remote,
    testId
)

    if remote.Name ==
        "Ping"
    then

        return {}

    elseif remote.Name ==
        "Echo"
    then

        return {
            "CAFEINA_V62",
            testId
        }

    elseif remote.Name ==
        "ValidateNumber"
    then

        return {
            123.456
        }

    elseif remote.Name ==
        "ValidateString"
    then

        return {
            "CAFEINA_TEST_V62"
        }

    elseif remote.Name ==
        "ClientDiagnostic"
    then

        return {

            {
                scanner =
                    CONFIG.SCANNER_NAME,

                version =
                    CONFIG.VERSION,

                testId =
                    testId,

                placeId =
                    game.PlaceId,

                timestamp =
                    os.time(),
            }
        }
    end

    return {}
end

--==============================================================
-- ONE SAFE TEST
--==============================================================

local function executeSafeTest(
    remote
)

    if
        not remote
        or
        not remote.Parent
        or
        not CONFIG.SafeTestNames[
            remote.Name
        ]
    then
        return
    end

    STATE.TestsRun +=
        1

    local testId =
        HttpService:
        GenerateGUID(
            false
        )

    local started =
        clock()

    STATE.ActiveTestId =
        testId

    STATE.ActiveTestRemote =
        safeFullName(
            remote
        )

    STATE.ActiveTestStarted =
        started

    local args =
        getSafeTestArgs(
            remote,
            testId
        )

    addRecord(
        "Tests",
        "test_start",

        "test-start|"
        ..
        testId,

        {
            id =
                testId,

            remote =
                safeFullName(
                    remote
                ),

            class =
                remote.ClassName,

            args =
                serializeValue(
                    args
                ),

            recentBefore =
                getRecentEvents(
                    CONFIG.CorrelationWindow
                ),
        }
    )

    if remote:IsA(
        "RemoteFunction"
    )
    then

        STATE.TestsInvoked +=
            1

        local ok, result =
            pcall(function()

                return remote:
                    InvokeServer(
                        table.unpack(
                            args
                        )
                    )
            end)

        if ok then
            STATE.TestsPassed += 1
        else
            STATE.TestsErrors += 1
        end

        addRecord(
            "Tests",

            ok
                and
                "invoke_result"
                or
                "invoke_error",

            "test-result|"
            ..
            testId,

            {
                id =
                    testId,

                remote =
                    safeFullName(
                        remote
                    ),

                latency =
                    clock()
                    -
                    started,

                response =
                    ok
                    and
                    serializeValue(
                        result
                    )
                    or
                    nil,

                error =
                    not ok
                    and
                    tostring(result)
                    or
                    nil,
            }
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

        if ok then
            STATE.TestsSent += 1
        else
            STATE.TestsErrors += 1
        end

        addRecord(
            "Tests",

            ok
                and
                "event_sent"
                or
                "event_error",

            "test-result|"
            ..
            testId,

            {
                id =
                    testId,

                remote =
                    safeFullName(
                        remote
                    ),

                latency =
                    clock()
                    -
                    started,

                error =
                    not ok
                    and
                    tostring(err)
                    or
                    nil,
            }
        )
    end

    local elapsed =
        0

    while elapsed <
        CONFIG.TestResponseWindow
    do

        if
            STATE.StopRequested
            or
            STATE.TestStopRequested
            or
            not STATE.AutoTesting
            or
            Runtime.Closed
        then
            break
        end

        task.wait(
            0.05
        )

        elapsed +=
            0.05
    end

    addRecord(
        "Tests",
        "test_end",

        "test-end|"
        ..
        testId,

        {
            id =
                testId,

            duration =
                clock()
                -
                started,

            recentAfter =
                getRecentEvents(
                    CONFIG.CorrelationWindow
                ),
        }
    )

    STATE.ActiveTestId =
        nil

    STATE.ActiveTestRemote =
        nil

    STATE.ActiveTestStarted =
        0
end

--==============================================================
-- GUI CREATION
--==============================================================

local GUI_NAME =
    "CafeinaTestLabV62"

local parent =
    PlayerGui

if type(gethui) ==
    "function"
then

    local ok, result =
        pcall(gethui)

    if ok
    and
    result
    then
        parent =
            result
    end
end

local old =
    parent:
    FindFirstChild(
        GUI_NAME
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new(
        "ScreenGui"
    )

Gui.Name =
    GUI_NAME

Gui.ResetOnSpawn =
    false

Gui.IgnoreGuiInset =
    false

Gui.Parent =
    parent

Runtime.Gui =
    Gui

--==============================================================
-- MAIN
--==============================================================

local Main =
    Instance.new(
        "Frame"
    )

Main.Size =
    UDim2.fromOffset(
        350,
        285
    )

Main.Position =
    UDim2.new(
        0.5,
        -175,
        0.12,
        0
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        13,
        13,
        16
    )

Main.BorderSizePixel =
    0

Main.Active =
    true

Main.Parent =
    Gui

local MainCorner =
    Instance.new(
        "UICorner"
    )

MainCorner.CornerRadius =
    UDim.new(
        0,
        12
    )

MainCorner.Parent =
    Main

local MainStroke =
    Instance.new(
        "UIStroke"
    )

MainStroke.Color =
    Color3.fromRGB(
        55,
        55,
        62
    )

MainStroke.Thickness =
    1

MainStroke.Parent =
    Main

--==============================================================
-- HEADER
--==============================================================

local Header =
    Instance.new(
        "Frame"
    )

Header.Size =
    UDim2.new(
        1,
        0,
        0,
        38
    )

Header.BackgroundTransparency =
    1

Header.Parent =
    Main

local Title =
    Instance.new(
        "TextLabel"
    )

Title.Size =
    UDim2.new(
        1,
        -80,
        1,
        0
    )

Title.Position =
    UDim2.fromOffset(
        12,
        0
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "CAFEÍNA • TEST LAB V6.2"

Title.Font =
    Enum.Font.GothamBold

Title.TextSize =
    14

Title.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Header

local Minimize =
    Instance.new(
        "TextButton"
    )

Minimize.Size =
    UDim2.fromOffset(
        28,
        28
    )

Minimize.Position =
    UDim2.new(
        1,
        -66,
        0,
        5
    )

Minimize.BackgroundColor3 =
    Color3.fromRGB(
        28,
        28,
        33
    )

Minimize.BorderSizePixel =
    0

Minimize.Text =
    "—"

Minimize.Font =
    Enum.Font.GothamBold

Minimize.TextSize =
    16

Minimize.TextColor3 =
    Color3.fromRGB(
        240,
        240,
        240
    )

Minimize.Parent =
    Header

Instance.new(
    "UICorner",
    Minimize
).CornerRadius =
    UDim.new(
        0,
        7
    )

local Close =
    Instance.new(
        "TextButton"
    )

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
        5
    )

Close.BackgroundColor3 =
    Color3.fromRGB(
        90,
        22,
        28
    )

Close.BorderSizePixel =
    0

Close.Text =
    "×"

Close.Font =
    Enum.Font.GothamBold

Close.TextSize =
    18

Close.TextColor3 =
    Color3.fromRGB(
        255,
        245,
        245
    )

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
-- INFO
--==============================================================

local ScanLabel =
    Instance.new(
        "TextLabel"
    )

ScanLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        26
    )

ScanLabel.Position =
    UDim2.fromOffset(
        12,
        42
    )

ScanLabel.BackgroundTransparency =
    1

ScanLabel.Text =
    "SCAN • 0.0 MB / 150 MB"

ScanLabel.Font =
    Enum.Font.GothamBold

ScanLabel.TextSize =
    14

ScanLabel.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

ScanLabel.TextXAlignment =
    Enum.TextXAlignment.Left

ScanLabel.Parent =
    Main

local RecordLabel =
    Instance.new(
        "TextLabel"
    )

RecordLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        20
    )

RecordLabel.Position =
    UDim2.fromOffset(
        12,
        68
    )

RecordLabel.BackgroundTransparency =
    1

RecordLabel.Text =
    "0 registros • pass 0 • eventos 0"

RecordLabel.Font =
    Enum.Font.Gotham

RecordLabel.TextSize =
    11

RecordLabel.TextColor3 =
    Color3.fromRGB(
        175,
        175,
        182
    )

RecordLabel.TextXAlignment =
    Enum.TextXAlignment.Left

RecordLabel.Parent =
    Main

local TestLabel =
    Instance.new(
        "TextLabel"
    )

TestLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        20
    )

TestLabel.Position =
    UDim2.fromOffset(
        12,
        89
    )

TestLabel.BackgroundTransparency =
    1

TestLabel.Text =
    "TESTES • desligado"

TestLabel.Font =
    Enum.Font.Gotham

TestLabel.TextSize =
    11

TestLabel.TextColor3 =
    Color3.fromRGB(
        175,
        175,
        182
    )

TestLabel.TextXAlignment =
    Enum.TextXAlignment.Left

TestLabel.Parent =
    Main

local StatusLabel =
    Instance.new(
        "TextLabel"
    )

StatusLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        20
    )

StatusLabel.Position =
    UDim2.fromOffset(
        12,
        112
    )

StatusLabel.BackgroundTransparency =
    1

StatusLabel.Text =
    "STATUS • aguardando"

StatusLabel.Font =
    Enum.Font.GothamBold

StatusLabel.TextSize =
    11

StatusLabel.TextColor3 =
    Color3.fromRGB(
        180,
        180,
        185
    )

StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Left

StatusLabel.Parent =
    Main

--==============================================================
-- PROGRESS
--==============================================================

local ProgressBG =
    Instance.new(
        "Frame"
    )

ProgressBG.Size =
    UDim2.new(
        1,
        -24,
        0,
        8
    )

ProgressBG.Position =
    UDim2.fromOffset(
        12,
        139
    )

ProgressBG.BackgroundColor3 =
    Color3.fromRGB(
        38,
        38,
        44
    )

ProgressBG.BorderSizePixel =
    0

ProgressBG.Parent =
    Main

Instance.new(
    "UICorner",
    ProgressBG
).CornerRadius =
    UDim.new(
        1,
        0
    )

local Progress =
    Instance.new(
        "Frame"
    )

Progress.Size =
    UDim2.fromScale(
        0,
        1
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

Instance.new(
    "UICorner",
    Progress
).CornerRadius =
    UDim.new(
        1,
        0
    )

local LinkLabel =
    Instance.new(
        "TextLabel"
    )

LinkLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        18
    )

LinkLabel.Position =
    UDim2.fromOffset(
        12,
        151
    )

LinkLabel.BackgroundTransparency =
    1

LinkLabel.Text =
    ""

LinkLabel.Font =
    Enum.Font.Gotham

LinkLabel.TextSize =
    9

LinkLabel.TextColor3 =
    Color3.fromRGB(
        145,
        145,
        150
    )

LinkLabel.TextXAlignment =
    Enum.TextXAlignment.Left

LinkLabel.TextTruncate =
    Enum.TextTruncate.AtEnd

LinkLabel.Parent =
    Main

--==============================================================
-- BUTTON CREATOR
--==============================================================

local function createButton(
    text,
    position,
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
        position

    button.BackgroundColor3 =
        Color3.fromRGB(
            28,
            28,
            34
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

    button.AutoButtonColor =
        true

    button.Parent =
        Main

    Instance.new(
        "UICorner",
        button
    ).CornerRadius =
        UDim.new(
            0,
            9
        )

    return button
end

local StartButton =
    createButton(
        "INICIAR SCAN",
        UDim2.fromOffset(
            12,
            178
        ),
        159
    )

local TestsButton =
    createButton(
        "TESTES",
        UDim2.fromOffset(
            179,
            178
        ),
        159
    )

local StopButton =
    createButton(
        "INTERROMPER",
        UDim2.fromOffset(
            12,
            228
        ),
        159
    )

StopButton.BackgroundColor3 =
    Color3.fromRGB(
        78,
        24,
        30
    )

local SendButton =
    createButton(
        "ENVIAR",
        UDim2.fromOffset(
            179,
            228
        ),
        159
    )

--==============================================================
-- MINIMIZED ICON
--==============================================================

local Mini =
    Instance.new(
        "TextButton"
    )

Mini.Size =
    UDim2.fromOffset(
        48,
        48
    )

Mini.Position =
    UDim2.new(
        0.5,
        -24,
        0.5,
        -24
    )

Mini.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        22
    )

Mini.BorderSizePixel =
    0

Mini.Text =
    "C"

Mini.Font =
    Enum.Font.GothamBold

Mini.TextSize =
    20

Mini.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

Mini.Visible =
    false

Mini.Parent =
    Gui

Instance.new(
    "UICorner",
    Mini
).CornerRadius =
    UDim.new(
        1,
        0
    )

--==============================================================
-- GUI HELPERS
--==============================================================

local function setStatus(
    text,
    color
)

    StatusLabel.Text =
        "STATUS • "
        ..
        tostring(text)

    if color then
        StatusLabel.TextColor3 =
            color
    end
end

local function setProgress(
    value
)

    Progress.Size =
        UDim2.fromScale(
            math.clamp(
                tonumber(value)
                or
                0,
                0,
                1
            ),
            1
        )
end

local function refreshGUI()

    if Runtime.Closed then
        return
    end

    local mb =
        STATE.ApproxBytes
        /
        1024
        /
        1024

    ScanLabel.Text =
        string.format(
            "SCAN • %.1f MB / 150 MB",
            mb
        )

    RecordLabel.Text =
        string.format(
            "%d registros • pass %d • eventos %d • %s",
            #STATE.Records,
            STATE.Pass,
            STATE.RemoteEventsObserved,
            tostring(
                STATE.CurrentArea
            )
        )

    if STATE.AutoTesting then

        TestLabel.Text =
            string.format(
                "TESTES • ciclo %d • run %d • sent %d • ok %d • err %d",
                STATE.TestCycle,
                STATE.TestsRun,
                STATE.TestsSent,
                STATE.TestsPassed,
                STATE.TestsErrors
            )

        TestLabel.TextColor3 =
            Color3.fromRGB(
                140,
                255,
                170
            )

    else

        TestLabel.Text =
            string.format(
                "TESTES • parado • run %d • bloqueados %d",
                STATE.TestsRun,
                STATE.TestsBlocked
            )

        TestLabel.TextColor3 =
            Color3.fromRGB(
                175,
                175,
                182
            )
    end

    if not STATE.Sending then

        setProgress(
            STATE.ApproxBytes
            /
            CONFIG.MaxBytesApprox
        )
    end
end

--==============================================================
-- DRAG FUNCTION
--==============================================================

local function makeDraggable(
    object
)

    local dragging =
        false

    local dragStart =
        nil

    local startPosition =
        nil

    connect(
        object.InputBegan,

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
                    object.Position
            end
        end
    )

    connect(
        object.InputEnded,

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

            if
                not dragging
                or
                not dragStart
                or
                not startPosition
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

            object.Position =
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
end

makeDraggable(
    Main
)

makeDraggable(
    Mini
)

--==============================================================
-- INITIAL RUNTIME OBSERVERS
--==============================================================

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

local initialBackpack =
    LocalPlayer:
    FindFirstChild(
        "Backpack"
    )

if initialBackpack then

    observeRoot(
        initialBackpack,
        "Backpack"
    )
end

if LocalPlayer.Character then

    observeRoot(
        LocalPlayer.Character,
        "Character"
    )
end

connect(
    LocalPlayer.CharacterAdded,

    function(
        character
    )

        observeRoot(
            character,
            "Character"
        )

        task.delay(
            1,
            function()

                if not Runtime.Closed then

                    scanRoot(
                        character,
                        "Character",

                        function(
                            object
                        )

                            return shouldWatch(
                                object
                            )
                        end
                    )
                end
            end
        )
    end
)

--==============================================================
-- RESET SCAN
--==============================================================

local function resetScan()

    STATE.StopRequested =
        false

    STATE.TestStopRequested =
        false

    STATE.LimitReached =
        false

    STATE.Pass =
        0

    STATE.StartedAt =
        clock()

    STATE.FinishedAt =
        0

    STATE.CurrentArea =
        "Iniciando"

    STATE.Records =
        {}

    STATE.ApproxBytes =
        0

    STATE.Added =
        0

    STATE.Changed =
        0

    STATE.Removed =
        0

    STATE.NewThisPass =
        0

    STATE.CategoryCount =
        {}

    STATE.Snapshots =
        {}

    STATE.CataloguedRemotes =
        {}

    STATE.EventShapes =
        {}

    STATE.RecentEvents =
        {}

    STATE.RemoteEventsObserved =
        0

    STATE.TestCycle =
        0

    STATE.TestsRun =
        0

    STATE.TestsInvoked =
        0

    STATE.TestsSent =
        0

    STATE.TestsPassed =
        0

    STATE.TestsErrors =
        0

    STATE.TestsBlocked =
        0

    STATE.SafeServiceChecked =
        false

    STATE.SafeServiceAvailable =
        false

    STATE.SafeTestRemotes =
        {}

    STATE.ActiveTestId =
        nil

    STATE.ActiveTestRemote =
        nil

    STATE.ActiveTestStarted =
        0

    STATE.LastURL =
        nil

    LinkLabel.Text =
        ""
end

--==============================================================
-- SCANNER LOOP
--==============================================================

local function startScanner()

    if STATE.Running
    or
    STATE.Sending
    then
        return
    end

    resetScan()

    STATE.Running =
        true

    StartButton.Text =
        "SCANNER ATIVO"

    setStatus(
        "inventário inicial...",
        Color3.fromRGB(
            120,
            190,
            255
        )
    )

    task.spawn(function()

        local ok, err =
            xpcall(
                initialInventory,
                debug.traceback
            )

        if not ok then

            STATE.Running =
                false

            setStatus(
                "erro inicial: "
                ..
                tostring(err),

                Color3.fromRGB(
                    255,
                    95,
                    105
                )
            )

            StartButton.Text =
                "INICIAR SCAN"

            return
        end

        setStatus(
            "coleta contínua",
            Color3.fromRGB(
                140,
                255,
                170
            )
        )

        while
            STATE.Running
            and
            not STATE.StopRequested
            and
            not Runtime.Closed
        do

            local okPass, errPass =
                xpcall(
                    focusedPass,
                    debug.traceback
                )

            if not okPass then

                addRecord(
                    "Diagnostics",
                    "pass_error",

                    "pass-error|"
                    ..
                    tostring(
                        STATE.Pass
                    ),

                    {
                        error =
                            tostring(
                                errPass
                            )
                    }
                )
            end

            refreshGUI()

            if STATE.StopRequested then
                break
            end

            local elapsed =
                0

            while elapsed <
                CONFIG.FocusedPassInterval
            do

                if
                    STATE.StopRequested
                    or
                    Runtime.Closed
                then
                    break
                end

                task.wait(
                    0.10
                )

                elapsed +=
                    0.10
            end
        end

        STATE.Running =
            false

        STATE.AutoTesting =
            false

        STATE.TestStopRequested =
            true

        STATE.FinishedAt =
            clock()

        STATE.CurrentArea =
            "Pronto para envio"

        StartButton.Text =
            "INICIAR SCAN"

        TestsButton.Text =
            "TESTES"

        if STATE.LimitReached then

            setStatus(
                "limite atingido • pronto para enviar",
                Color3.fromRGB(
                    140,
                    255,
                    170
                )
            )

        else

            setStatus(
                "scan + testes parados",
                Color3.fromRGB(
                    190,
                    190,
                    195
                )
            )
        end

        refreshGUI()
    end)
end

--==============================================================
-- CONTINUOUS TEST LOOP
--==============================================================

local function startContinuousTests()

    if STATE.AutoTesting then
        return
    end

    if not STATE.Running then

        setStatus(
            "inicie o scan primeiro",
            Color3.fromRGB(
                255,
                210,
                110
            )
        )

        return
    end

    if not discoverSafeTestService() then

        setStatus(
            "SecurityTestService não encontrado",
            Color3.fromRGB(
                255,
                180,
                100
            )
        )

        TestsButton.Text =
            "SEM TEST SERVICE"

        refreshGUI()

        return
    end

    if #STATE.SafeTestRemotes ==
        0
    then

        setStatus(
            "nenhum teste permitido encontrado",
            Color3.fromRGB(
                255,
                180,
                100
            )
        )

        return
    end

    STATE.AutoTesting =
        true

    STATE.Testing =
        true

    STATE.TestStopRequested =
        false

    TestsButton.Text =
        "TESTES ATIVOS"

    addRecord(
        "Tests",
        "continuous_started",
        "continuous-tests",

        {
            remoteCount =
                #STATE.SafeTestRemotes,

            remoteDelay =
                CONFIG.TestRemoteDelay,

            cycleDelay =
                CONFIG.TestCycleDelay,
        }
    )

    task.spawn(function()

        while
            STATE.AutoTesting
            and
            STATE.Running
            and
            not STATE.StopRequested
            and
            not STATE.TestStopRequested
            and
            not Runtime.Closed
        do

            STATE.TestCycle +=
                1

            local cycle =
                STATE.TestCycle

            local cycleId =
                HttpService:
                GenerateGUID(
                    false
                )

            local cycleStart =
                clock()

            addRecord(
                "Tests",
                "cycle_start",

                "cycle-start|"
                ..
                cycleId,

                {
                    cycle =
                        cycle,

                    id =
                        cycleId,

                    remoteCount =
                        #STATE.SafeTestRemotes,
                }
            )

            for _, remote in ipairs(
                STATE.SafeTestRemotes
            ) do

                if
                    not STATE.AutoTesting
                    or
                    not STATE.Running
                    or
                    STATE.StopRequested
                    or
                    STATE.TestStopRequested
                    or
                    Runtime.Closed
                then
                    break
                end

                setStatus(
                    string.format(
                        "teste %d • %s",
                        cycle,
                        remote.Name
                    ),

                    Color3.fromRGB(
                        120,
                        190,
                        255
                    )
                )

                executeSafeTest(
                    remote
                )

                refreshGUI()

                local waited =
                    0

                while waited <
                    CONFIG.TestRemoteDelay
                do

                    if
                        STATE.StopRequested
                        or
                        STATE.TestStopRequested
                        or
                        not STATE.AutoTesting
                    then
                        break
                    end

                    task.wait(
                        0.05
                    )

                    waited +=
                        0.05
                end
            end

            addRecord(
                "Tests",
                "cycle_end",

                "cycle-end|"
                ..
                cycleId,

                {
                    cycle =
                        cycle,

                    duration =
                        clock()
                        -
                        cycleStart,

                    testsRun =
                        STATE.TestsRun,

                    serverEventsObserved =
                        STATE.RemoteEventsObserved,
                }
            )

            local waited =
                0

            while waited <
                CONFIG.TestCycleDelay
            do

                if
                    STATE.StopRequested
                    or
                    STATE.TestStopRequested
                    or
                    not STATE.AutoTesting
                    or
                    Runtime.Closed
                then
                    break
                end

                task.wait(
                    0.05
                )

                waited +=
                    0.05
            end
        end

        STATE.AutoTesting =
            false

        STATE.Testing =
            false

        STATE.ActiveTestId =
            nil

        STATE.ActiveTestRemote =
            nil

        STATE.ActiveTestStarted =
            0

        if not Runtime.Closed then

            TestsButton.Text =
                "TESTES"

            refreshGUI()
        end
    end)
end

--==============================================================
-- HTTP
--==============================================================

local function getRequest()

    if syn
    and
    type(syn.request) ==
        "function"
    then
        return syn.request
    end

    if type(http_request) ==
        "function"
    then
        return http_request
    end

    if type(request) ==
        "function"
    then
        return request
    end

    if http
    and
    type(http.request) ==
        "function"
    then
        return http.request
    end

    return nil
end

local function getClipboard()

    if type(setclipboard) ==
        "function"
    then
        return setclipboard
    end

    if type(toclipboard) ==
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

local function postJSON(
    url,
    data
)

    local requestFunction =
        getRequest()

    if not requestFunction then

        return false,
            "Executor sem request HTTP"
    end

    local encoded =
        encode(
            data
        )

    if not encoded then

        return false,
            "Falha ao codificar JSON"
    end

    local lastError =
        "erro desconhecido"

    for attempt = 1,
        CONFIG.UploadRetries
    do

        if
            STATE.UploadCancelled
            or
            Runtime.Closed
        then

            return false,
                "cancelado"
        end

        local ok, response =
            pcall(
                requestFunction,

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

            local status =
                tonumber(
                    response.StatusCode
                    or
                    response.Status
                    or
                    0
                )
                or
                0

            local body =
                response.Body
                or
                response.body
                or
                ""

            if
                status >= 200
                and
                status < 300
            then

                if body == "" then

                    return true,
                        {}
                end

                local decodeOK,
                      result =
                    pcall(
                        HttpService.JSONDecode,
                        HttpService,
                        body
                    )

                if decodeOK then

                    return true,
                        result
                end

                return true,
                    {
                        raw = body
                    }
            end

            lastError =
                "HTTP "
                ..
                tostring(
                    status
                )

        else

            lastError =
                tostring(
                    response
                )
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
-- FILENAME
--==============================================================

local function createFilename()

    return string.format(
        "Cafeina_TestLabV62_%s_%s.json",

        tostring(
            game.PlaceId
        ),

        os.date(
            "!%Y%m%d_%H%M%S"
        )
    )
end

--==============================================================
-- BUILD CHUNKS
--==============================================================

local function buildChunks()

    local chunks =
        {}

    local current =
        {}

    local currentBytes =
        2

    for index, record in ipairs(
        STATE.Records
    ) do

        if
            STATE.UploadCancelled
            or
            Runtime.Closed
        then
            break
        end

        local encoded =
            encode(
                record
            )

        if encoded then

            local bytes =
                #encoded
                +
                1

            if
                #current > 0
                and
                currentBytes
                +
                bytes
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
                bytes
        end

        if index % 1000 ==
            0
        then

            RunService.Heartbeat:
                Wait()
        end
    end

    if #current > 0 then

        table.insert(
            chunks,
            current
        )
    end

    return chunks
end

--==============================================================
-- UPLOAD
--==============================================================

local function sendEverything()

    if STATE.Sending then
        return
    end

    if
        STATE.Running
        or
        STATE.AutoTesting
        or
        STATE.Testing
    then

        setStatus(
            "interrompa scan/testes antes de enviar",
            Color3.fromRGB(
                255,
                210,
                110
            )
        )

        return
    end

    if #STATE.Records ==
        0
    then

        setStatus(
            "nenhum dado para enviar",
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

    STATE.ChunksSent =
        0

    STATE.BytesSent =
        0

    SendButton.Text =
        "ENVIANDO..."

    setProgress(
        0
    )

    setStatus(
        "abrindo upload...",
        Color3.fromRGB(
            120,
            190,
            255
        )
    )

    task.spawn(function()

        local filename =
            createFilename()

        --======================================================
        -- START
        --======================================================

        local startOK,
              startResult =
            postJSON(

                CONFIG.UPLOAD_BASE
                ..
                "/start",

                withToken({

                    filename =
                        filename,

                    source =
                        "cafeina-test-lab-v6.2",

                    metadata = {

                        scanner =
                            CONFIG.SCANNER_NAME,

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

                        records =
                            #STATE.Records,

                        bytesApprox =
                            STATE.ApproxBytes,

                        passes =
                            STATE.Pass,

                        remoteEventsObserved =
                            STATE.RemoteEventsObserved,

                        testCycles =
                            STATE.TestCycle,

                        testsRun =
                            STATE.TestsRun,

                        testsInvoked =
                            STATE.TestsInvoked,

                        testsSent =
                            STATE.TestsSent,

                        testsPassed =
                            STATE.TestsPassed,

                        testsErrors =
                            STATE.TestsErrors,

                        testsBlocked =
                            STATE.TestsBlocked,

                        limitReached =
                            STATE.LimitReached,
                    }
                })
            )

        if
            not startOK
            or
            type(startResult) ~=
                "table"
            or
            not startResult.uploadId
        then

            STATE.Sending =
                false

            SendButton.Text =
                "ENVIAR"

            setStatus(
                "erro ao iniciar upload",
                Color3.fromRGB(
                    255,
                    95,
                    105
                )
            )

            return
        end

        STATE.UploadId =
            tostring(
                startResult.uploadId
            )

        --======================================================
        -- CHUNKS
        --======================================================

        setStatus(
            "preparando arquivos...",
            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local chunks =
            buildChunks()

        STATE.TotalChunks =
            #chunks

        if #chunks ==
            0
        then

            STATE.Sending =
                false

            SendButton.Text =
                "ENVIAR"

            setStatus(
                "nenhum chunk gerado",
                Color3.fromRGB(
                    255,
                    95,
                    105
                )
            )

            return
        end

        for index,
            objects
        in ipairs(
            chunks
        ) do

            if
                STATE.UploadCancelled
                or
                Runtime.Closed
            then
                return
            end

            local progress =
                (
                    index - 1
                )
                /
                #chunks

            setProgress(
                progress
            )

            setStatus(
                string.format(
                    "enviando %d/%d • %d%%",
                    index,
                    #chunks,
                    math.floor(
                        progress
                        *
                        100
                    )
                ),

                Color3.fromRGB(
                    120,
                    190,
                    255
                )
            )

            local chunkOK,
                  chunkResult =
                postJSON(

                    CONFIG.UPLOAD_BASE
                    ..
                    "/chunk",

                    withToken({

                        uploadId =
                            STATE.UploadId,

                        index =
                            index,

                        objects =
                            objects,
                    })
                )

            if not chunkOK then

                STATE.Sending =
                    false

                SendButton.Text =
                    "ENVIAR"

                setStatus(
                    "erro chunk "
                    ..
                    tostring(
                        index
                    )
                    ..
                    ": "
                    ..
                    tostring(
                        chunkResult
                    ),

                    Color3.fromRGB(
                        255,
                        95,
                        105
                    )
                )

                return
            end

            STATE.ChunksSent =
                index

            local encodedObjects =
                encode(
                    objects
                )

            if encodedObjects then

                STATE.BytesSent +=
                    #encodedObjects
            end

            setProgress(
                index
                /
                #chunks
            )
        end

        --======================================================
        -- FINISH
        --======================================================

        setStatus(
            "finalizando upload...",
            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local finishOK,
              finishResult =
            postJSON(

                CONFIG.UPLOAD_BASE
                ..
                "/finish",

                withToken({

                    uploadId =
                        STATE.UploadId,

                    totalChunks =
                        STATE.ChunksSent,

                    summary = {

                        records =
                            #STATE.Records,

                        bytesApprox =
                            STATE.ApproxBytes,

                        uploadBytes =
                            STATE.BytesSent,

                        chunks =
                            STATE.ChunksSent,

                        passes =
                            STATE.Pass,

                        remoteEventsObserved =
                            STATE.RemoteEventsObserved,

                        testCycles =
                            STATE.TestCycle,

                        testsRun =
                            STATE.TestsRun,

                        testsInvoked =
                            STATE.TestsInvoked,

                        testsSent =
                            STATE.TestsSent,

                        testsPassed =
                            STATE.TestsPassed,

                        testsErrors =
                            STATE.TestsErrors,

                        testsBlocked =
                            STATE.TestsBlocked,

                        limitReached =
                            STATE.LimitReached,

                        interrupted =
                            STATE.StopRequested,

                        categories =
                            STATE.CategoryCount,

                        clientVisibleOnly =
                            true,
                    }
                })
            )

        STATE.Sending =
            false

        SendButton.Text =
            "ENVIAR"

        if not finishOK then

            setStatus(
                "erro ao finalizar upload",
                Color3.fromRGB(
                    255,
                    95,
                    105
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

        if not url then

            setStatus(
                "upload concluído • sem link",
                Color3.fromRGB(
                    255,
                    180,
                    100
                )
            )

            return
        end

        url =
            tostring(
                url
            )

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

        LinkLabel.Text =
            url

        setProgress(
            1
        )

        local clipboard =
            getClipboard()

        if clipboard then

            pcall(
                clipboard,
                url
            )
        end

        setStatus(
            "100% • enviado • link copiado",
            Color3.fromRGB(
                140,
                255,
                170
            )
        )
    end)
end

--==============================================================
-- BUTTONS
--==============================================================

connect(
    StartButton.MouseButton1Click,

    function()

        startScanner()
    end
)

connect(
    TestsButton.MouseButton1Click,

    function()

        startContinuousTests()
    end
)

connect(
    StopButton.MouseButton1Click,

    function()

        STATE.StopRequested =
            true

        STATE.TestStopRequested =
            true

        STATE.AutoTesting =
            false

        STATE.Testing =
            false

        setStatus(
            "interrompendo scan + testes...",
            Color3.fromRGB(
                255,
                210,
                110
            )
        )

        refreshGUI()
    end
)

connect(
    SendButton.MouseButton1Click,

    function()

        sendEverything()
    end
)

--==============================================================
-- MINIMIZE
--==============================================================

connect(
    Minimize.MouseButton1Click,

    function()

        Main.Visible =
            false

        Mini.Visible =
            true
    end
)

connect(
    Mini.MouseButton1Click,

    function()

        Mini.Visible =
            false

        Main.Visible =
            true
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

    STATE.TestStopRequested =
        true

    STATE.UploadCancelled =
        true

    STATE.Running =
        false

    STATE.AutoTesting =
        false

    STATE.Testing =
        false

    if
        STATE.Sending
        and
        STATE.UploadId
    then

        task.spawn(function()

            pcall(
                postJSON,

                CONFIG.UPLOAD_BASE
                ..
                "/cancel",

                withToken({

                    uploadId =
                        STATE.UploadId
                })
            )
        end)
    end

    local buckets = {

        Runtime.Connections,
        Runtime.RemoteConnections,
        Runtime.ObjectConnections,
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

    if ENV.CAFEINA_TEST_LAB_V62 ==
        Runtime
    then

        ENV.CAFEINA_TEST_LAB_V62 =
            nil
    end
end

connect(
    Close.MouseButton1Click,

    function()

        Runtime.Shutdown()
    end
)

--==============================================================
-- GUI REFRESH
--==============================================================

connect(
    RunService.Heartbeat,

    function()

        if Runtime.Closed then
            return
        end

        refreshGUI()
    end
)

--==============================================================
-- READY
--==============================================================

setProgress(
    0
)

setStatus(
    "aguardando",
    Color3.fromRGB(
        180,
        180,
        185
    )
)

refreshGUI()

print(
    "[CAFEÍNA] TEST LAB V6.2 carregado."
)
