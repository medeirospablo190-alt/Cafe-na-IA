--[[
================================================================
 CAFEÍNA • EXPOSURE SCANNER V1
 Scanner de superfície client-visible • Executor

 MENU
   [ INICIAR COLETA ]
   [ ENCERRAR ]
   [ ENVIAR AO SITE ]

 STATUS
   • MB coletados
   • registros
   • passes
   • área atual
   • estado do upload
   • chunks enviados

 FOCO
   • Remotes
   • Tycoon
   • Purchases
   • Money / leaderstats
   • Weapons / Blaster
   • Damage / ammo / reload / fire
   • TouchInterest
   • ProximityPrompt
   • ClickDetector
   • atributos relevantes
   • LocalScripts / ModuleScripts visíveis
   • GUIs econômicas/combat
   • alterações em runtime
   • objetos novos em runtime

 IMPORTANTE
   O scanner observa estruturas replicadas ao cliente.
   Não dispara RemoteEvents ou RemoteFunctions.
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

local StarterGui =
    game:GetService("StarterGui")

local StarterPlayer =
    game:GetService("StarterPlayer")

local RunService =
    game:GetService("RunService")

local HttpService =
    game:GetService("HttpService")

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

    local ok, result =
        pcall(getgenv)

    if ok and result then
        ENV = result
    end
end

if ENV.CAFEINA_EXPOSURE_SCANNER
and
type(
    ENV.CAFEINA_EXPOSURE_SCANNER.Shutdown
) == "function"
then

    pcall(
        ENV.CAFEINA_EXPOSURE_SCANNER.Shutdown
    )
end

local Runtime = {
    Closed = false,
    Connections = {},
}

ENV.CAFEINA_EXPOSURE_SCANNER =
    Runtime

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    VERSION =
        "1.0",

    API_BASE =
        "https://cafe-na-ia.onrender.com",

    UPLOAD_TOKEN =
        "",

    -- ~180 MB
    MAX_BYTES =
        180 * 1024 * 1024,

    -- tamanho desejado de cada request
    UPLOAD_CHUNK_BYTES =
        2500 * 1024,

    UPLOAD_RETRIES =
        4,

    RETRY_DELAY =
        1.25,

    -- scanner
    PASS_DELAY =
        0.40,

    YIELD_EVERY =
        300,

    MAX_QUEUE =
        25000,

    ATTRIBUTE_DEBOUNCE =
        0.08,

    -- não guardar lixo decorativo
    IGNORE_DECORATIVE =
        true,
}

--==============================================================
-- EXECUTOR HTTP
--==============================================================

local requestFn =
    (
        typeof(request) == "function"
        and request
    )
    or
    (
        typeof(http_request) == "function"
        and http_request
    )
    or
    (
        syn
        and
        typeof(syn.request) == "function"
        and syn.request
    )
    or
    (
        http
        and
        typeof(http.request) == "function"
        and http.request
    )
    or nil

--==============================================================
-- STATE
--==============================================================

local STATE = {

    Running =
        false,

    StopRequested =
        false,

    Finished =
        false,

    Uploading =
        false,

    UploadCancel =
        false,

    UploadId =
        nil,

    Records =
        {},

    Signatures =
        {},

    Watched =
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

    Queue =
        {},

    QueueHead =
        1,

    Bytes =
        0,

    RecordsCount =
        0,

    Passes =
        0,

    NewThisPass =
        0,

    UploadBytes =
        0,

    UploadChunks =
        0,

    UploadTotalChunks =
        0,

    CurrentArea =
        "AGUARDANDO",

    ScanStatus =
        "PRONTO",

    UploadStatus =
        "NÃO INICIADO",

    StartedAt =
        nil,

    FinishedAt =
        nil,
}

--==============================================================
-- KEYWORDS
--==============================================================

local HIGH_VALUE_WORDS = {

    -- networking
    "remote",
    "event",
    "function",
    "__remotes",

    -- dinheiro
    "money",
    "cash",
    "currency",
    "price",
    "cost",
    "purchase",
    "buy",
    "sell",
    "collect",

    -- tycoon
    "tycoon",
    "button",
    "collector",
    "purchase",
    "dependency",
    "owner",
    "rebirth",

    -- armas
    "weapon",
    "gun",
    "blaster",
    "shoot",
    "fire",
    "bullet",
    "projectile",
    "damage",
    "hit",
    "headshot",
    "ammo",
    "magazine",
    "reload",
    "recoil",
    "spread",
    "range",

    -- player
    "health",
    "speed",
    "walkspeed",
    "jump",
    "team",

    -- inventário
    "inventory",
    "loadout",
    "equip",
    "tool",
    "item",
    "armour",
    "armor",

    -- acesso
    "admin",
    "permission",
    "rank",
    "group",
    "whitelist",
    "auth",

    -- datastore-ish replicated naming
    "playerdata",
    "data",
    "stats",

    -- interações
    "touch",
    "prompt",
    "click",
}

local IMPORTANT_ATTRIBUTES = {

    price = true,
    cost = true,
    owner = true,
    dependency = true,

    gamepass = true,
    nonpurchase = true,
    rebirths = true,

    money = true,
    cash = true,

    damage = true,
    firerate = true,
    firemode = true,

    ammo = true,
    _ammo = true,

    magazine = true,
    magazinesize = true,

    reloadtime = true,
    reloadtype = true,
    _reloading = true,

    recoil = true,
    recoilmin = true,
    recoilmax = true,

    spread = true,
    range = true,

    projectiletype = true,
    rayradius = true,
    rayspershot = true,

    serverinit = true,
    clientinit = true,

    purchase = true,

    health = true,
    maxhealth = true,

    team = true,
}

--==============================================================
-- IGNORE
--==============================================================

local DECORATIVE = {

    ParticleEmitter = true,
    Trail = true,
    Beam = true,
    Texture = true,
    Decal = true,
    SpecialMesh = true,
    SurfaceAppearance = true,
    WeldConstraint = true,
    Motor6D = true,
    Bone = true,
}

--==============================================================
-- HELPERS
--==============================================================

local function connect(
    signal,
    callback
)

    local c =
        signal:Connect(
            callback
        )

    table.insert(
        Runtime.Connections,
        c
    )

    return c
end

local function lower(value)

    return string.lower(
        tostring(
            value or ""
        )
    )
end

local function safePath(obj)

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

local function safeAttributes(obj)

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

local function readableBytes(
    bytes
)

    bytes =
        tonumber(bytes)
        or 0

    if bytes >=
        1024 * 1024
    then

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

local function containsKeyword(
    value
)

    value =
        lower(value)

    for _, word in ipairs(
        HIGH_VALUE_WORDS
    ) do

        if string.find(
            value,
            word,
            1,
            true
        ) then

            return true,
                word
        end
    end

    return false,
        nil
end

local function serializeValue(
    value,
    depth
)

    depth =
        depth or 0

    if depth > 5 then
        return "[depth-limit]"
    end

    local t =
        typeof(value)

    if t == "nil"
    or
    t == "string"
    or
    t == "number"
    or
    t == "boolean"
    then

        return value
    end

    if t == "Instance" then

        return {
            type = "Instance",
            class = value.ClassName,
            name = value.Name,
            path = safePath(value),
        }
    end

    if t == "Vector3" then

        return {
            type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z,
        }
    end

    if t == "Vector2" then

        return {
            type = "Vector2",
            x = value.X,
            y = value.Y,
        }
    end

    if t == "CFrame" then

        return {
            type = "CFrame",
            position = {
                x = value.Position.X,
                y = value.Position.Y,
                z = value.Position.Z,
            }
        }
    end

    if t == "Color3" then

        return {
            type = "Color3",
            r = value.R,
            g = value.G,
            b = value.B,
        }
    end

    if t == "EnumItem" then

        return tostring(value)
    end

    if t == "table" then

        local result =
            {}

        local count =
            0

        for k, v in pairs(value) do

            count += 1

            if count > 100 then
                break
            end

            result[
                tostring(k)
            ] =
                serializeValue(
                    v,
                    depth + 1
                )
        end

        return result
    end

    return tostring(value)
end

--==============================================================
-- RECORD STORAGE
--==============================================================

local function makeSignature(
    record
)

    return
        tostring(record.kind)
        ..
        "|"
        ..
        tostring(record.path)
        ..
        "|"
        ..
        tostring(record.attribute)
        ..
        "|"
        ..
        tostring(record.value)
end

local function addRecord(
    record,
    force
)

    if Runtime.Closed then
        return false
    end

    record.time =
        os.clock()

    local signature =
        makeSignature(record)

    if not force
    and
    STATE.Signatures[
        signature
    ]
    then

        return false
    end

    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            record
        )

    if not ok then
        return false
    end

    local bytes =
        #encoded + 1

    if STATE.Bytes + bytes >
        CONFIG.MAX_BYTES
    then

        STATE.StopRequested =
            true

        STATE.ScanStatus =
            "LIMITE ATINGIDO"

        return false
    end

    STATE.Signatures[
        signature
    ] =
        true

    STATE.Records[
        #STATE.Records + 1
    ] =
        record

    STATE.Bytes +=
        bytes

    STATE.RecordsCount +=
        1

    STATE.NewThisPass +=
        1

    return true
end

--==============================================================
-- ATTRIBUTE FILTER
--==============================================================

local function interestingAttributes(
    obj
)

    local attrs =
        safeAttributes(obj)

    local result =
        {}

    local count =
        0

    for name, value in pairs(
        attrs
    ) do

        local key =
            lower(name)

        local interesting =
            IMPORTANT_ATTRIBUTES[key]

        if not interesting then

            interesting =
                containsKeyword(
                    name
                )
        end

        if interesting then

            result[name] =
                serializeValue(
                    value
                )

            count += 1
        end
    end

    return result,
        count
end

--==============================================================
-- OBJECT CLASSIFICATION
--==============================================================

local function classify(
    obj
)

    if obj:IsA(
        "RemoteEvent"
    )
    then
        return "remote_event", 100
    end

    if obj:IsA(
        "UnreliableRemoteEvent"
    )
    then
        return "unreliable_remote_event", 100
    end

    if obj:IsA(
        "RemoteFunction"
    )
    then
        return "remote_function", 100
    end

    if obj:IsA(
        "TouchTransmitter"
    )
    then
        return "touch_interest", 90
    end

    if obj:IsA(
        "ProximityPrompt"
    )
    then
        return "proximity_prompt", 90
    end

    if obj:IsA(
        "ClickDetector"
    )
    then
        return "click_detector", 90
    end

    if obj:IsA(
        "Tool"
    )
    then
        return "tool", 80
    end

    if obj:IsA(
        "ModuleScript"
    )
    then
        return "module_script", 75
    end

    if obj:IsA(
        "LocalScript"
    )
    then
        return "local_script", 70
    end

    local path =
        lower(
            safePath(obj)
        )

    local matched =
        containsKeyword(path)

    if matched then
        return "interesting_object", 55
    end

    local attrs,
          count =
        interestingAttributes(obj)

    if count > 0 then
        return "attribute_holder", 50
    end

    return nil, 0
end

--==============================================================
-- SPECIAL PROPERTIES
--==============================================================

local function collectProperties(
    obj
)

    local result =
        {}

    if obj:IsA(
        "RemoteEvent"
    )
    or
    obj:IsA(
        "RemoteFunction"
    )
    or
    obj:IsA(
        "UnreliableRemoteEvent"
    )
    then

        result.remoteClass =
            obj.ClassName
    end

    if obj:IsA(
        "ProximityPrompt"
    )
    then

        result.actionText =
            obj.ActionText

        result.objectText =
            obj.ObjectText

        result.holdDuration =
            obj.HoldDuration

        result.maxActivationDistance =
            obj.MaxActivationDistance

        result.requiresLineOfSight =
            obj.RequiresLineOfSight
    end

    if obj:IsA(
        "ClickDetector"
    )
    then

        result.maxActivationDistance =
            obj.MaxActivationDistance
    end

    if obj:IsA(
        "BasePart"
    )
    then

        result.canTouch =
            obj.CanTouch

        result.canQuery =
            obj.CanQuery

        result.canCollide =
            obj.CanCollide

        result.anchored =
            obj.Anchored
    end

    if obj:IsA(
        "StringValue"
    )
    then

        result.value =
            obj.Value
    end

    if obj:IsA(
        "NumberValue"
    )
    or
    obj:IsA(
        "IntValue"
    )
    then

        result.value =
            obj.Value
    end

    if obj:IsA(
        "BoolValue"
    )
    then

        result.value =
            obj.Value
    end

    if obj:IsA(
        "TextLabel"
    )
    or
    obj:IsA(
        "TextButton"
    )
    then

        local interesting =
            containsKeyword(
                obj.Text
            )

        if interesting then

            result.text =
                string.sub(
                    obj.Text,
                    1,
                    500
                )
        end
    end

    return result
end

--==============================================================
-- INSPECT
--==============================================================

local function inspectObject(
    obj,
    reason
)

    if Runtime.Closed
    or
    STATE.StopRequested
    then
        return
    end

    if not obj
    or
    not obj.Parent
    then
        return
    end

    if CONFIG.IGNORE_DECORATIVE
    and
    DECORATIVE[
        obj.ClassName
    ]
    then

        return
    end

    local category,
          score =
        classify(obj)

    if not category then
        return
    end

    local attrs,
          attributeCount =
        interestingAttributes(obj)

    local parent =
        obj.Parent

    addRecord({

        kind =
            category,

        score =
            score,

        reason =
            reason,

        name =
            obj.Name,

        class =
            obj.ClassName,

        path =
            safePath(obj),

        parent = parent and {
            name =
                parent.Name,

            class =
                parent.ClassName,

            path =
                safePath(parent),
        }
        or nil,

        attributes =
            attrs,

        attributeCount =
            attributeCount,

        properties =
            collectProperties(obj),

        pass =
            STATE.Passes,
    })
end

--==============================================================
-- ATTRIBUTE WATCHER
--==============================================================

local function watchObject(
    obj
)

    if STATE.Watched[obj] then
        return
    end

    STATE.Watched[obj] =
        true

    local category =
        classify(obj)

    if not category then
        return
    end

    local ok, connection =
        pcall(function()

            return obj.AttributeChanged:
                Connect(function(
                    attribute
                )

                    if not STATE.Running
                    or
                    Runtime.Closed
                    then
                        return
                    end

                    local key =
                        lower(attribute)

                    if not
                        IMPORTANT_ATTRIBUTES[
                            key
                        ]
                        and
                        not containsKeyword(
                            attribute
                        )
                    then

                        return
                    end

                    local now =
                        os.clock()

                    local lastMap =
                        STATE.AttributeLast[
                            obj
                        ]

                    if not lastMap then

                        lastMap =
                            {}

                        STATE.AttributeLast[
                            obj
                        ] =
                            lastMap
                    end

                    local previous =
                        lastMap[
                            attribute
                        ]
                        or 0

                    if now - previous <
                        CONFIG.ATTRIBUTE_DEBOUNCE
                    then

                        return
                    end

                    lastMap[
                        attribute
                    ] =
                        now

                    local success,
                          value =
                        pcall(
                            obj.GetAttribute,
                            obj,
                            attribute
                        )

                    if success then

                        addRecord(
                            {
                                kind =
                                    "attribute_change",

                                path =
                                    safePath(obj),

                                class =
                                    obj.ClassName,

                                name =
                                    obj.Name,

                                attribute =
                                    attribute,

                                value =
                                    serializeValue(
                                        value
                                    ),

                                pass =
                                    STATE.Passes,
                            },
                            true
                        )
                    end
                end)
        end)

    if ok
    and
    connection
    then

        table.insert(
            Runtime.Connections,
            connection
        )
    end
end

--==============================================================
-- PRIORITY ROOTS
--==============================================================

local function getRoots()

    local roots =
        {}

    local function push(
        name,
        obj
    )

        if obj then

            roots[
                #roots + 1
            ] = {
                name = name,
                object = obj
            }
        end
    end

    push(
        "ReplicatedStorage",
        ReplicatedStorage
    )

    push(
        "ReplicatedFirst",
        ReplicatedFirst
    )

    push(
        "Workspace.Tycoons",
        Workspace:
            FindFirstChild(
                "Tycoons"
            )
    )

    push(
        "Workspace.Soldiers",
        Workspace:
            FindFirstChild(
                "Soldiers"
            )
    )

    push(
        "PlayerGui",
        PlayerGui
    )

    push(
        "Backpack",
        LocalPlayer:
            FindFirstChild(
                "Backpack"
            )
    )

    push(
        "Character",
        LocalPlayer.Character
    )

    push(
        "StarterPlayerScripts",
        StarterPlayer:
            FindFirstChild(
                "StarterPlayerScripts"
            )
    )

    push(
        "StarterCharacterScripts",
        StarterPlayer:
            FindFirstChild(
                "StarterCharacterScripts"
            )
    )

    return roots
end

--==============================================================
-- SCAN ROOT
--==============================================================

local function scanRoot(
    rootName,
    root
)

    STATE.CurrentArea =
        rootName

    inspectObject(
        root,
        "root"
    )

    local descendants =
        root:GetDescendants()

    for index, obj in ipairs(
        descendants
    ) do

        if Runtime.Closed
        or
        STATE.StopRequested
        then
            break
        end

        inspectObject(
            obj,
            "pass"
        )

        watchObject(
            obj
        )

        if index %
            CONFIG.YIELD_EVERY
            ==
            0
        then

            RunService.Heartbeat:
                Wait()
        end
    end
end

--==============================================================
-- RUNTIME DISCOVERY
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
        function(obj)

            if not STATE.Running then
                return
            end

            task.defer(function()

                if Runtime.Closed then
                    return
                end

                inspectObject(
                    obj,
                    "runtime_added:"
                    ..
                    rootName
                )

                watchObject(
                    obj
                )
            end)
        end
    )

    connect(
        root.DescendantRemoving,
        function(obj)

            if not STATE.Running then
                return
            end

            local category =
                classify(obj)

            if category then

                addRecord(
                    {
                        kind =
                            "interesting_removed",

                        category =
                            category,

                        name =
                            obj.Name,

                        class =
                            obj.ClassName,

                        path =
                            safePath(obj),

                        area =
                            rootName,

                        pass =
                            STATE.Passes,
                    },
                    true
                )
            end
        end
    )
end

--==============================================================
-- HEADER
--==============================================================

local function addHeader()

    addRecord(
        {
            kind =
                "scan_header",

            scanner =
                "CAFEINA_EXPOSURE_SCANNER",

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

            startedUnix =
                os.time(),

            player = {
                name =
                    LocalPlayer.Name,

                userId =
                    LocalPlayer.UserId,
            },

            capabilities = {

                executorHttp =
                    requestFn ~= nil,

                firetouchinterest =
                    typeof(
                        firetouchinterest
                    )
                    ==
                    "function",

                fireproximityprompt =
                    typeof(
                        fireproximityprompt
                    )
                    ==
                    "function",

                fireclickdetector =
                    typeof(
                        fireclickdetector
                    )
                    ==
                    "function",

                getgc =
                    typeof(
                        getgc
                    )
                    ==
                    "function",

                getconnections =
                    typeof(
                        getconnections
                    )
                    ==
                    "function",

                hookfunction =
                    typeof(
                        hookfunction
                    )
                    ==
                    "function",

                getrawmetatable =
                    typeof(
                        getrawmetatable
                    )
                    ==
                    "function",
            },
        },
        true
    )
end

--==============================================================
-- SCANNER
--==============================================================

local function startScan()

    if STATE.Running
    or
    STATE.Uploading
    then
        return
    end

    -- limpa scan anterior

    STATE.Records =
        {}

    STATE.Signatures =
        {}

    STATE.Bytes =
        0

    STATE.RecordsCount =
        0

    STATE.Passes =
        0

    STATE.NewThisPass =
        0

    STATE.StopRequested =
        false

    STATE.Finished =
        false

    STATE.StartedAt =
        os.time()

    STATE.FinishedAt =
        nil

    STATE.ScanStatus =
        "INICIANDO"

    STATE.UploadStatus =
        "AGUARDANDO COLETA"

    addHeader()

    STATE.Running =
        true

    task.spawn(function()

        while
            STATE.Running
            and
            not STATE.StopRequested
            and
            not Runtime.Closed
        do

            STATE.Passes +=
                1

            STATE.NewThisPass =
                0

            STATE.ScanStatus =
                "COLETANDO"

            for _, data in ipairs(
                getRoots()
            ) do

                if STATE.StopRequested
                or
                Runtime.Closed
                then
                    break
                end

                scanRoot(
                    data.name,
                    data.object
                )
            end

            STATE.CurrentArea =
                "MONITORANDO RUNTIME"

            if STATE.Bytes >=
                CONFIG.MAX_BYTES
            then

                STATE.StopRequested =
                    true

                STATE.ScanStatus =
                    "LIMITE ATINGIDO"

                break
            end

            task.wait(
                CONFIG.PASS_DELAY
            )
        end

        STATE.Running =
            false

        STATE.Finished =
            true

        STATE.FinishedAt =
            os.time()

        if STATE.ScanStatus ~=
            "LIMITE ATINGIDO"
        then

            STATE.ScanStatus =
                "ENCERRADO"
        end

        STATE.CurrentArea =
            "PRONTO PARA ENVIO"

        STATE.UploadStatus =
            "PRONTO PARA ENVIAR"

        addRecord(
            {
                kind =
                    "scan_finished",

                passes =
                    STATE.Passes,

                records =
                    STATE.RecordsCount,

                bytes =
                    STATE.Bytes,

                startedUnix =
                    STATE.StartedAt,

                finishedUnix =
                    STATE.FinishedAt,
            },
            true
        )
    end)
end

local function stopScan()

    if STATE.Running then

        STATE.ScanStatus =
            "ENCERRANDO"

        STATE.StopRequested =
            true
    else

        STATE.Finished =
            true

        STATE.ScanStatus =
            "ENCERRADO"

        STATE.UploadStatus =
            "PRONTO PARA ENVIAR"
    end
end

--==============================================================
-- HTTP HELPERS
--==============================================================

local function responseStatus(
    response
)

    if type(response) ~=
        "table"
    then
        return nil
    end

    return tonumber(
        response.StatusCode
        or
        response.Status
        or
        response.status
    )
end

local function responseBody(
    response
)

    if type(response) ~=
        "table"
    then
        return nil
    end

    return
        response.Body
        or
        response.body
end

local function postJson(
    url,
    data
)

    if not requestFn then

        return false,
            "Executor sem HTTP request"
    end

    if CONFIG.UPLOAD_TOKEN ~= "" then

        data.token =
            CONFIG.UPLOAD_TOKEN
    end

    local body =
        HttpService:
        JSONEncode(data)

    local lastError =
        "erro desconhecido"

    for attempt = 1,
        CONFIG.UPLOAD_RETRIES
    do

        if STATE.UploadCancel
        or
        Runtime.Closed
        then

            return false,
                "cancelado"
        end

        local ok, response =
            pcall(
                requestFn,
                {
                    Url =
                        url,

                    Method =
                        "POST",

                    Headers = {
                        ["Content-Type"] =
                            "application/json"
                    },

                    Body =
                        body,
                }
            )

        if ok then

            local status =
                responseStatus(
                    response
                )

            if not status
            or
            (
                status >= 200
                and
                status < 300
            )
            then

                local raw =
                    responseBody(
                        response
                    )

                if raw
                and raw ~= ""
                then

                    local decodeOk,
                          decoded =
                        pcall(
                            HttpService.JSONDecode,
                            HttpService,
                            raw
                        )

                    if decodeOk then

                        return true,
                            decoded
                    end
                end

                return true,
                    response
            end

            lastError =
                "HTTP "
                ..
                tostring(status)
        else

            lastError =
                tostring(response)
        end

        if attempt <
            CONFIG.UPLOAD_RETRIES
        then

            task.wait(
                CONFIG.RETRY_DELAY
                *
                attempt
            )
        end
    end

    return false,
        lastError
end

--==============================================================
-- BUILD CHUNKS
--==============================================================

local function buildUploadChunks()

    local chunks =
        {}

    local current =
        {}

    local currentBytes =
        2

    for _, record in ipairs(
        STATE.Records
    ) do

        local ok, encoded =
            pcall(
                HttpService.JSONEncode,
                HttpService,
                record
            )

        if ok then

            local bytes =
                #encoded + 1

            if
                #current > 0
                and
                currentBytes + bytes >
                    CONFIG.UPLOAD_CHUNK_BYTES
            then

                chunks[
                    #chunks + 1
                ] =
                    current

                current =
                    {}

                currentBytes =
                    2
            end

            current[
                #current + 1
            ] =
                record

            currentBytes +=
                bytes
        end
    end

    if #current > 0 then

        chunks[
            #chunks + 1
        ] =
            current
    end

    return chunks
end

--==============================================================
-- UPLOAD
--==============================================================

local function uploadScan()

    if STATE.Uploading then
        return
    end

    if STATE.Running then

        STATE.UploadStatus =
            "ENCERRE A COLETA"

        return
    end

    if #STATE.Records == 0 then

        STATE.UploadStatus =
            "SEM DADOS"

        return
    end

    if not requestFn then

        STATE.UploadStatus =
            "HTTP INDISPONÍVEL"

        return
    end

    STATE.Uploading =
        true

    STATE.UploadCancel =
        false

    STATE.UploadBytes =
        0

    STATE.UploadChunks =
        0

    STATE.UploadTotalChunks =
        0

    STATE.UploadStatus =
        "PREPARANDO"

    task.spawn(function()

        local filename =
            string.format(
                "Cafeina_Exposure_%s_%s.json",
                tostring(
                    game.PlaceId
                ),
                os.date(
                    "!%Y%m%d_%H%M%S"
                )
            )

        -- START

        STATE.UploadStatus =
            "ABRINDO SESSÃO"

        local startOk,
              startResponse =
            postJson(
                CONFIG.API_BASE
                ..
                "/upload/start",

                {
                    filename =
                        filename,

                    source =
                        "cafeina-exposure-scanner-v1",

                    metadata = {

                        area =
                            "ExposureResearch",

                        scanner =
                            "CAFEINA_EXPOSURE_SCANNER",

                        scannerVersion =
                            CONFIG.VERSION,

                        placeId =
                            game.PlaceId,

                        gameId =
                            game.GameId,

                        clientVisibleOnly =
                            true,

                        records =
                            STATE.RecordsCount,

                        bytes =
                            STATE.Bytes,

                        passes =
                            STATE.Passes,
                    }
                }
            )

        if not startOk
        or
        type(startResponse) ~=
            "table"
        or
        not startResponse.uploadId
        then

            STATE.UploadStatus =
                "ERRO AO ABRIR UPLOAD"

            STATE.Uploading =
                false

            return
        end

        STATE.UploadId =
            tostring(
                startResponse.uploadId
            )

        -- CHUNKS

        STATE.UploadStatus =
            "GERANDO CHUNKS"

        local chunks =
            buildUploadChunks()

        STATE.UploadTotalChunks =
            #chunks

        for index, objects in ipairs(
            chunks
        ) do

            if STATE.UploadCancel
            or
            Runtime.Closed
            then
                break
            end

            STATE.UploadStatus =
                string.format(
                    "ENVIANDO %d/%d",
                    index,
                    #chunks
                )

            local ok, result =
                postJson(
                    CONFIG.API_BASE
                    ..
                    "/upload/chunk",

                    {
                        uploadId =
                            STATE.UploadId,

                        index =
                            index,

                        objects =
                            objects,
                    }
                )

            if not ok then

                STATE.UploadStatus =
                    "ERRO NO CHUNK "
                    ..
                    tostring(index)

                STATE.Uploading =
                    false

                return
            end

            STATE.UploadChunks =
                index

            local encodedOk,
                  encoded =
                pcall(
                    HttpService.JSONEncode,
                    HttpService,
                    objects
                )

            if encodedOk then

                STATE.UploadBytes +=
                    #encoded
            end

            RunService.Heartbeat:
                Wait()
        end

        if STATE.UploadCancel then

            STATE.UploadStatus =
                "UPLOAD CANCELADO"

            if STATE.UploadId then

                pcall(function()

                    postJson(
                        CONFIG.API_BASE
                        ..
                        "/upload/cancel",

                        {
                            uploadId =
                                STATE.UploadId
                        }
                    )
                end)
            end

            STATE.Uploading =
                false

            return
        end

        -- FINISH

        STATE.UploadStatus =
            "FINALIZANDO"

        local finishOk,
              finishResponse =
            postJson(
                CONFIG.API_BASE
                ..
                "/upload/finish",

                {
                    uploadId =
                        STATE.UploadId,

                    totalChunks =
                        #chunks,

                    summary = {

                        records =
                            STATE.RecordsCount,

                        bytes =
                            STATE.Bytes,

                        passes =
                            STATE.Passes,

                        placeId =
                            game.PlaceId,

                        scanner =
                            "CAFEINA_EXPOSURE_SCANNER",

                        version =
                            CONFIG.VERSION,
                    }
                }
            )

        if not finishOk then

            STATE.UploadStatus =
                "ERRO AO FINALIZAR"

            STATE.Uploading =
                false

            return
        end

        STATE.UploadStatus =
            "ENVIADO COM SUCESSO"

        STATE.Uploading =
            false

        -- copia somente URL final

        if type(finishResponse) ==
            "table"
        then

            local finalUrl =
                finishResponse.downloadUrl
                or
                finishResponse.url

            if finalUrl
            and
            type(setclipboard) ==
                "function"
            then

                pcall(
                    setclipboard,
                    tostring(finalUrl)
                )
            end
        end
    end)
end

--==============================================================
-- GUI
--==============================================================

local oldGui =
    PlayerGui:
    FindFirstChild(
        "CafeinaExposureScanner"
    )

if oldGui then
    oldGui:Destroy()
end

local Gui =
    Instance.new(
        "ScreenGui"
    )

Gui.Name =
    "CafeinaExposureScanner"

Gui.ResetOnSpawn =
    false

Gui.IgnoreGuiInset =
    false

Gui.Parent =
    PlayerGui

Runtime.Gui =
    Gui

local Main =
    Instance.new(
        "Frame"
    )

Main.Size =
    UDim2.fromOffset(
        330,
        285
    )

Main.Position =
    UDim2.new(
        0.5,
        -165,
        0.5,
        -142
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        12,
        12,
        15
    )

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

local mainCorner =
    Instance.new(
        "UICorner"
    )

mainCorner.CornerRadius =
    UDim.new(
        0,
        11
    )

mainCorner.Parent =
    Main

local stroke =
    Instance.new(
        "UIStroke"
    )

stroke.Color =
    Color3.fromRGB(
        65,
        65,
        72
    )

stroke.Thickness =
    1

stroke.Parent =
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
        44
    )

Header.BackgroundColor3 =
    Color3.fromRGB(
        22,
        22,
        27
    )

Header.BorderSizePixel =
    0

Header.Parent =
    Main

local title =
    Instance.new(
        "TextLabel"
    )

title.Size =
    UDim2.new(
        1,
        -55,
        1,
        0
    )

title.Position =
    UDim2.fromOffset(
        14,
        0
    )

title.BackgroundTransparency =
    1

title.Text =
    "CAFEÍNA • EXPOSURE SCANNER"

title.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        248
    )

title.Font =
    Enum.Font.GothamBold

title.TextSize =
    14

title.TextXAlignment =
    Enum.TextXAlignment.Left

title.Parent =
    Header

local Close =
    Instance.new(
        "TextButton"
    )

Close.Size =
    UDim2.fromOffset(
        32,
        30
    )

Close.Position =
    UDim2.new(
        1,
        -39,
        0,
        7
    )

Close.BackgroundColor3 =
    Color3.fromRGB(
        120,
        22,
        30
    )

Close.Text =
    "×"

Close.TextColor3 =
    Color3.new(
        1,
        1,
        1
    )

Close.Font =
    Enum.Font.GothamBold

Close.TextSize =
    18

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
        6
    )

--==============================================================
-- BUTTON CREATOR
--==============================================================

local function createButton(
    text,
    y,
    color
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.new(
            1,
            -24,
            0,
            38
        )

    button.Position =
        UDim2.fromOffset(
            12,
            y
        )

    button.BackgroundColor3 =
        color

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        Color3.fromRGB(
            245,
            245,
            248
        )

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        13

    button.Parent =
        Main

    Instance.new(
        "UICorner",
        button
    ).CornerRadius =
        UDim.new(
            0,
            7
        )

    return button
end

local StartButton =
    createButton(
        "INICIAR COLETA",
        54,
        Color3.fromRGB(
            85,
            20,
            28
        )
    )

local StopButton =
    createButton(
        "ENCERRAR",
        98,
        Color3.fromRGB(
            62,
            25,
            29
        )
    )

local SendButton =
    createButton(
        "ENVIAR AO SITE",
        142,
        Color3.fromRGB(
            37,
            37,
            44
        )
    )

--==============================================================
-- STATUS PANEL
--==============================================================

local Status =
    Instance.new(
        "TextLabel"
    )

Status.Size =
    UDim2.new(
        1,
        -24,
        0,
        88
    )

Status.Position =
    UDim2.fromOffset(
        12,
        188
    )

Status.BackgroundColor3 =
    Color3.fromRGB(
        20,
        20,
        24
    )

Status.BorderSizePixel =
    0

Status.TextColor3 =
    Color3.fromRGB(
        225,
        225,
        230
    )

Status.Font =
    Enum.Font.Gotham

Status.TextSize =
    11

Status.TextWrapped =
    true

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.TextYAlignment =
    Enum.TextYAlignment.Top

Status.Parent =
    Main

Instance.new(
    "UICorner",
    Status
).CornerRadius =
    UDim.new(
        0,
        7
    )

local padding =
    Instance.new(
        "UIPadding"
    )

padding.PaddingTop =
    UDim.new(
        0,
        7
    )

padding.PaddingLeft =
    UDim.new(
        0,
        8
    )

padding.Parent =
    Status

--==============================================================
-- BUTTON ACTIONS
--==============================================================

StartButton.MouseButton1Click:
    Connect(function()

        startScan()
    end)

StopButton.MouseButton1Click:
    Connect(function()

        stopScan()
    end)

SendButton.MouseButton1Click:
    Connect(function()

        uploadScan()
    end)

--==============================================================
-- DRAG MOBILE
--==============================================================

local dragging =
    false

local dragStart =
    nil

local startPos =
    nil

Header.InputBegan:
    Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
        then

            dragging =
                true

            dragStart =
                input.Position

            startPos =
                Main.Position
        end
    end)

Header.InputEnded:
    Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
        then

            dragging =
                false
        end
    end)

connect(
    UserInputService.InputChanged,
    function(input)

        if not dragging
        or
        not dragStart
        or
        not startPos
        then
            return
        end

        if input.UserInputType ~=
            Enum.UserInputType.MouseMovement
        and
        input.UserInputType ~=
            Enum.UserInputType.Touch
        then
            return
        end

        local delta =
            input.Position
            -
            dragStart

        Main.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset
                    +
                    delta.X,

                startPos.Y.Scale,
                startPos.Y.Offset
                    +
                    delta.Y
            )
    end
)

--==============================================================
-- OBSERVERS
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

--==============================================================
-- GUI STATUS
--==============================================================

connect(
    RunService.Heartbeat,
    function()

        if Runtime.Closed then
            return
        end

        local percent =
            math.clamp(
                STATE.Bytes
                /
                CONFIG.MAX_BYTES,
                0,
                1
            )
            *
            100

        local uploadPercent =
            0

        if STATE.UploadTotalChunks >
            0
        then

            uploadPercent =
                STATE.UploadChunks
                /
                STATE.UploadTotalChunks
                *
                100
        end

        Status.Text =
            "SCAN: "
            ..
            STATE.ScanStatus
            ..
            "  •  "
            ..
            readableBytes(
                STATE.Bytes
            )
            ..
            " / "
            ..
            readableBytes(
                CONFIG.MAX_BYTES
            )
            ..
            string.format(
                " (%.1f%%)",
                percent
            )
            ..
            "\nREGISTROS: "
            ..
            tostring(
                STATE.RecordsCount
            )
            ..
            "  •  PASSES: "
            ..
            tostring(
                STATE.Passes
            )
            ..
            "\nÁREA: "
            ..
            tostring(
                STATE.CurrentArea
            )
            ..
            "\nUPLOAD: "
            ..
            tostring(
                STATE.UploadStatus
            )
            ..
            string.format(
                "  %.0f%%",
                uploadPercent
            )
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

    STATE.UploadCancel =
        true

    for _, c in ipairs(
        Runtime.Connections
    ) do

        pcall(function()

            c:Disconnect()
        end)
    end

    table.clear(
        Runtime.Connections
    )

    if Runtime.Gui then

        pcall(function()

            Runtime.Gui:
                Destroy()
        end)
    end

    if ENV.CAFEINA_EXPOSURE_SCANNER ==
        Runtime
    then

        ENV.CAFEINA_EXPOSURE_SCANNER =
            nil
    end
end

Close.MouseButton1Click:
    Connect(function()

        Runtime.Shutdown()
    end)

print(
    "[CAFEÍNA] Exposure Scanner V1 carregado."
)
