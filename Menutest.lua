--==============================================================--
-- CAFEÍNA • MAPPING V1.4 • COMPACT AUTO FLOW
--
-- MAPPING ENGINE
-- + PASSIVE TEST LAB
-- + PERSISTENT ARCHIVE
-- + AUTOMATIC UPLOAD
--
-- MOBILE / EXECUTOR / CLIENT-VISIBLE
--
-- FLUXO:
--
-- INICIAR TUDO
--      ↓
-- SCAN + TEST LAB
--      ↓
-- ENCERRAR
--      ↓
-- FINALIZA ARCHIVE
--      ↓
-- UPLOAD AUTOMÁTICO
--      ↓
-- /finish CONFIRMADO
--      ↓
-- LIMPA ARCHIVE
--
-- IMPORTANTE:
-- • Stop NÃO apaga dados.
-- • Erro de upload NÃO apaga dados.
-- • Fechar/reexecutar NÃO apaga dados.
-- • Só /finish confirmado permite apagar.
-- • Test Lab é passivo.
--==============================================================--

local Players =
    game:GetService("Players")

local HttpService =
    game:GetService("HttpService")

local UserInputService =
    game:GetService("UserInputService")

local TweenService =
    game:GetService("TweenService")

local CoreGui =
    game:GetService("CoreGui")

local Workspace =
    game:GetService("Workspace")

local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer =
        Players.PlayerAdded:Wait()
end

local IS_MOBILE =
    UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {

    VERSION =
        "MAPPING_V1_4_COMPACT",

    GUI_NAME =
        "CafeinaMappingV14Compact",

    UPLOAD_BASE =
        "https://cafe-na-ia.onrender.com/upload",

    ------------------------------------------------------------
    -- ARCHIVE
    ------------------------------------------------------------

    MAX_ARCHIVE_BYTES =
        150 * 1024 * 1024,

    BLOCK_TARGET_BYTES =
        1024 * 1024,

    UPLOAD_CHUNK_BYTES =
        3200000,

    ------------------------------------------------------------
    -- HTTP
    ------------------------------------------------------------

    HTTP_RETRIES = 3,

    HTTP_RETRY_BASE =
        1.25,

    ------------------------------------------------------------
    -- TEST LAB
    ------------------------------------------------------------

    ATTRIBUTE_POLL_SECONDS =
        0.75,

    HEARTBEAT_EVERY_CYCLES =
        8,

    CORRELATION_WINDOW_SECONDS =
        0.20,

    MAX_TRACKED_VALUES =
        3200,

    MAX_TRACKED_ATTRIBUTES =
        1800,

    MAX_TRACKED_REMOTES =
        420,

    MAX_DYNAMIC_EVENTS =
        14000,

    ------------------------------------------------------------
    -- PERFORMANCE
    ------------------------------------------------------------

    SCAN_YIELD_EVERY =
        140,

    ATTRIBUTE_YIELD_EVERY =
        90,

    UI_UPDATE_INTERVAL =
        0.12,

    MANIFEST_FLUSH_RECORDS =
        40,

    MANIFEST_FLUSH_SECONDS =
        1.5,

    MEMORY_RECORD_CAP =
        2500,

    ------------------------------------------------------------
    -- FILESYSTEM
    ------------------------------------------------------------

    ARCHIVE_FOLDER =
        "CafeinaArchive",

    MANIFEST_PATH =
        "CafeinaArchive/manifest.json",

    MANIFEST_BACKUP_PATH =
        "CafeinaArchive/manifest.bak",

    ------------------------------------------------------------
    -- SERVICE BUDGETS
    ------------------------------------------------------------

    SERVICES = {

        {
            name = "ReplicatedStorage",
            budget = 42000,
        },

        {
            name = "ReplicatedFirst",
            budget = 8000,
        },

        {
            name = "StarterPlayer",
            budget = 19000,
        },

        {
            name = "StarterGui",
            budget = 18000,
        },

        {
            name = "Players",
            budget = 20000,
        },

        {
            name = "Lighting",
            budget = 4000,
        },

        {
            name = "Teams",
            budget = 2500,
        },

        {
            name = "SoundService",
            budget = 5000,
        },

        {
            name = "Workspace",
            budget = 36000,
        },
    },
}

if IS_MOBILE then

    CONFIG.MAX_TRACKED_VALUES =
        2400

    CONFIG.MAX_TRACKED_ATTRIBUTES =
        1250

    CONFIG.MAX_TRACKED_REMOTES =
        360

    CONFIG.SCAN_YIELD_EVERY =
        90

    CONFIG.ATTRIBUTE_YIELD_EVERY =
        60

    CONFIG.MEMORY_RECORD_CAP =
        1800
end

--==============================================================--
-- EXECUTOR
--==============================================================--

local env =
    (getgenv and getgenv())
    or _G

local function pickFunction(...)

    for i = 1,
        select("#", ...) do

        local value =
            select(i, ...)

        if type(value) == "function" then
            return value
        end
    end

    return nil
end

local synRequest

pcall(function()

    if syn
    and type(syn.request)
        == "function" then

        synRequest =
            syn.request
    end
end)

local httpRequest

pcall(function()

    if http
    and type(http.request)
        == "function" then

        httpRequest =
            http.request
    end
end)

local REQUEST =
    pickFunction(
        rawget(env, "request"),
        rawget(env, "http_request"),
        httpRequest,
        synRequest
    )

local WRITEFILE =
    pickFunction(
        rawget(env, "writefile")
    )

local READFILE =
    pickFunction(
        rawget(env, "readfile")
    )

local APPENDFILE =
    pickFunction(
        rawget(env, "appendfile")
    )

local ISFILE =
    pickFunction(
        rawget(env, "isfile")
    )

local DELFILE =
    pickFunction(
        rawget(env, "delfile")
    )

local MAKEFOLDER =
    pickFunction(
        rawget(env, "makefolder")
    )

local ISFOLDER =
    pickFunction(
        rawget(env, "isfolder")
    )

local FILESYSTEM_OK =
    WRITEFILE
    and READFILE
    and ISFILE
    and DELFILE
    and MAKEFOLDER

-- Reduz reescrita pesada caso executor não tenha appendfile.
if FILESYSTEM_OK
and not APPENDFILE then

    CONFIG.BLOCK_TARGET_BYTES =
        512 * 1024
end

--==============================================================--
-- HELPERS
--==============================================================--

local function mb(bytes)

    return bytes
        / (1024 * 1024)
end

local function nowUnix()
    return os.time()
end

local function isoUTC()

    local t =
        os.date("!*t")

    return string.format(
        "%04d%02d%02d_%02d%02d%02d",

        t.year,
        t.month,
        t.day,

        t.hour,
        t.min,
        t.sec
    )
end

local function newRunId()

    local ok,
        guid =
        pcall(function()

            return HttpService:GenerateGUID(
                false
            )
        end)

    if ok then
        return guid
    end

    return tostring(os.time())
        .. "_"
        .. tostring(
            math.random(
                100000,
                999999
            )
        )
end

local function safePath(inst)

    if not inst then
        return "?"
    end

    local ok,
        path =
        pcall(function()

            return inst:GetFullName()
        end)

    return ok
        and path
        or tostring(inst)
end

local function clamp01(value)

    return math.clamp(
        value or 0,
        0,
        1
    )
end

--==============================================================--
-- SERIALIZER
--==============================================================--

local function safeSerialize(
    value,
    depth,
    seen
)

    depth =
        depth or 0

    seen =
        seen or {}

    if depth > 4 then
        return "<max_depth>"
    end

    local tv =
        typeof(value)

    if value == nil then

        return nil

    elseif tv == "string"
    or tv == "boolean" then

        return value

    elseif tv == "number" then

        if value ~= value then
            return "<nan>"
        end

        if value == math.huge then
            return "<inf>"
        end

        if value == -math.huge then
            return "<-inf>"
        end

        return value

    elseif tv == "Instance" then

        return {
            type = "Instance",
            path = safePath(value),
            className =
                value.ClassName,
        }

    elseif tv == "Vector3" then

        return {
            type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z,
        }

    elseif tv == "Vector2" then

        return {
            type = "Vector2",
            x = value.X,
            y = value.Y,
        }

    elseif tv == "Color3" then

        return {
            type = "Color3",
            r = value.R,
            g = value.G,
            b = value.B,
        }

    elseif tv == "CFrame" then

        local p =
            value.Position

        return {
            type = "CFrame",
            x = p.X,
            y = p.Y,
            z = p.Z,
        }

    elseif tv == "table" then

        if seen[value] then
            return "<cycle>"
        end

        seen[value] = true

        local out = {}
        local count = 0

        for key,
            item
        in pairs(value) do

            count += 1

            if count > 60 then

                out["<truncated>"] =
                    true

                break
            end

            out[tostring(key)] =
                safeSerialize(
                    item,
                    depth + 1,
                    seen
                )
        end

        seen[value] =
            nil

        return out
    end

    return tostring(value)
end

local function safeAttributes(inst)

    local ok,
        attrs =
        pcall(function()

            return inst:GetAttributes()
        end)

    if not ok then
        return {}
    end

    return safeSerialize(attrs)
        or {}
end

local function safeJson(value)

    local ok,
        result =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            value
        )

    if ok then
        return result
    end

    return HttpService:JSONEncode({
        kind =
            "serialization_error",

        error =
            tostring(result),
    })
end

local function shallowEqual(a, b)

    local okA,
        jsonA =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            a
        )

    local okB,
        jsonB =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            b
        )

    return okA
        and okB
        and jsonA == jsonB
end

--==============================================================--
-- RELEVÂNCIA
--==============================================================--

local CLASS_SCORE = {

    RemoteEvent = 120,
    RemoteFunction = 120,
    UnreliableRemoteEvent = 120,

    ModuleScript = 70,
    LocalScript = 55,
    Script = 50,

    ObjectValue = 65,
    StringValue = 55,
    BoolValue = 55,
    NumberValue = 60,
    IntValue = 30,

    Tool = 85,
    ProximityPrompt = 75,

    Configuration = 50,
    Humanoid = 60,
}

local GAME_KEYWORDS = {

    profilemirror = 90,
    profiledelta = 100,

    speedpower = 95,
    money = 80,

    treadmill = 100,

    eggworld = 100,
    eggcapture = 100,
    egginventory = 90,

    gearsatchel = 95,
    geartools = 85,

    shopitems = 75,

    guardpatrol = 85,
    guard = 60,

    homestead = 80,
    penroster = 80,

    monsterevent = 90,
    monsterparasite = 90,

    storefront = 85,

    trailwear = 75,
    trials = 70,
    payouts = 65,
    mutation = 65,

    batcontroller = 85,

    ratelimiter = 75,
    tokenbucket = 75,

    remote = 55,
    network = 55,

    damage = 45,
    bullet = 40,
    hit = 35,

    quest = 40,
    dialogue = 35,

    item = 35,
    weapon = 40,
    gun = 40,
    ammo = 35,

    inventory = 45,
    equip = 40,
    reload = 40,

    combat = 45,

    stamina = 40,
    health = 40,

    craft = 35,
    scrap = 35,
    artifact = 35,

    loot = 40,
    shop = 40,
    npc = 35,

    state = 30,
    ending = 30,
}

local CRITICAL_PATHS = {

    "ReplicatedStorage.Packages.Networking",

    "ReplicatedStorage.Shared.Modules",

    "ReplicatedStorage.GearTools",

    "ProfileMirror",

    "EggWorld",
    "EggCapture",

    "Treadmill",

    "GearSatchel",

    "GuardPatrol",

    "Homestead",
    "PenRoster",

    "MonsterEvent",
    "MonsterParasite",

    "Storefront",

    "leaderstats.Speed",
}

local function relevanceFromPath(
    inst,
    path
)

    path =
        path or safePath(inst)

    local lowerPath =
        string.lower(path)

    local lowerName =
        string.lower(
            inst.Name or ""
        )

    local score =
        CLASS_SCORE[
            inst.ClassName
        ] or 0

    for word,
        add
    in pairs(GAME_KEYWORDS) do

        if string.find(
            lowerPath,
            word,
            1,
            true
        )
        or string.find(
            lowerName,
            word,
            1,
            true
        ) then

            score += add
        end
    end

    for _,
        critical
    in ipairs(CRITICAL_PATHS) do

        if string.find(
            path,
            critical,
            1,
            true
        ) then

            score += 70
        end
    end

    return score
end

local function relevanceOf(inst)

    return relevanceFromPath(
        inst,
        safePath(inst)
    )
end

local function classifyContext(path)

    local s =
        string.lower(
            path or ""
        )

    local function has(...)

        for i = 1,
            select("#", ...) do

            local word =
                select(i, ...)

            if string.find(
                s,
                word,
                1,
                true
            ) then

                return true
            end
        end

        return false
    end

    if has(
        "damage",
        "blood",
        "limbhealth",
        "parry",
        "ammo",
        "combat",
        "weapon",
        "gun",
        "batcontroller"
    ) then

        return "COMBAT"

    elseif has(
        "guard",
        "monster",
        "npc",
        "chain"
    ) then

        return "NPC"

    elseif has(
        "party",
        "penroster",
        "owner"
    ) then

        return "PARTY"

    elseif has(
        "craft",
        "workbench",
        "deconstruct",
        "mutation"
    ) then

        return "CRAFTING"

    elseif has(
        "inventory",
        "saveditems",
        ".items",
        "gearsatchel",
        "egginventory",
        "backpack",
        "gear"
    ) then

        return "INVENTORY"

    elseif has(
        "quest",
        "objective",
        "dialogue",
        "trials"
    ) then

        return "QUEST"

    elseif has(
        "zone",
        "area",
        "homestead",
        "field"
    ) then

        return "ZONE"

    elseif has(
        "characterhandler",
        "charactermobility",
        "stamina",
        "humanoid",
        "leaderstats",
        "speedpower"
    ) then

        return "CHARACTER"

    elseif has(
        "playergui",
        "startergui",
        "gui",
        "button",
        "frame",
        "label"
    ) then

        return "UI"
    end

    return "WORLD"
end

--==============================================================--
-- STATE
--==============================================================--

local Session = {

    Running = false,

    ScanRunning = false,

    TestsRunning = false,

    ObserversRunning = false,

    StopRequested = false,

    StopReason = nil,

    StartedAtClock = 0,

    StartedAtUnix = 0,

    RunId = nil,

    RecordCount = 0,

    ObjectsScanned = 0,

    ServicesDone = 0,

    ServicesTotal =
        #CONFIG.SERVICES,

    CurrentService = "",
}

local Upload = {

    Running = false,

    CancelRequested = false,

    UploadId = nil,

    ChunksSent = 0,

    BytesSent = 0,

    TotalBytes = 0,

    CurrentChunk = 0,

    TotalChunks = 0,

    LastURL = "",
}

local Archive = {

    Persistent =
        FILESYSTEM_OK
        and true
        or false,

    Blocks = {},

    CurrentBlock = 1,

    CurrentBlockBytes = 0,

    Bytes = 0,

    Records = 0,

    Sessions = 0,

    MemoryLines = {},
}

local Report = {

    records = {},

    diagnostics = {

        errors = {},

        counters = {

            total = 0,

            scan = 0,

            tests = 0,

            session = 0,
        },
    },
}

local ObserverConnections = {}

local TrackedValues = {}

local TrackedAttributes = {}

local TrackedValueSet =
    setmetatable(
        {},
        {__mode = "k"}
    )

local TrackedAttributeSet =
    setmetatable(
        {},
        {__mode = "k"}
    )

local ObservedRemoteSet =
    setmetatable(
        {},
        {__mode = "k"}
    )

local DynamicSignatures = {}

local RemoteAggregates = {}

local DynamicEvents = 0

local ObservedRemoteCount = 0

local ManifestState = {

    dirty = false,

    recordsSinceSave = 0,

    lastSaveClock = 0,
}

local Flow = {

    Mode = "idle",

    FinalizerRunning = false,
}

local uploadAll
local requestStopAndUpload

--==============================================================--
-- TIME
--==============================================================--

local function relativeTime()

    if Session.StartedAtClock
        == 0 then

        return 0
    end

    return os.clock()
        - Session.StartedAtClock
end

local function correlationWindow()

    return math.floor(
        relativeTime()
        / CONFIG.CORRELATION_WINDOW_SECONDS
    )
end

--==============================================================--
-- ARCHIVE
--==============================================================--

local function blockPath(index)

    return string.format(
        "%s/block_%06d.jsonl",

        CONFIG.ARCHIVE_FOLDER,

        index
    )
end

local function ensureArchiveFolder()

    if not FILESYSTEM_OK then
        return false
    end

    return pcall(function()

        if not ISFOLDER
        or not ISFOLDER(
            CONFIG.ARCHIVE_FOLDER
        ) then

            MAKEFOLDER(
                CONFIG.ARCHIVE_FOLDER
            )
        end
    end)
end

local function saveManifest(force)

    if not FILESYSTEM_OK then
        return
    end

    local now =
        os.clock()

    if not force then

        if not ManifestState.dirty then
            return
        end

        if ManifestState.recordsSinceSave
            < CONFIG.MANIFEST_FLUSH_RECORDS

        and now
            - ManifestState.lastSaveClock

            < CONFIG.MANIFEST_FLUSH_SECONDS
        then

            return
        end
    end

    ensureArchiveFolder()

    local manifest = {

        schema = 2,

        scanner =
            CONFIG.VERSION,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        blocks =
            Archive.Blocks,

        currentBlock =
            Archive.CurrentBlock,

        bytes =
            Archive.Bytes,

        records =
            Archive.Records,

        sessions =
            Archive.Sessions,

        persistent = true,
    }

    local encoded =
        safeJson(manifest)

    local success =
        pcall(function()

            ----------------------------------------------------
            -- BACKUP DO MANIFEST ANTERIOR
            ----------------------------------------------------

            if ISFILE(
                CONFIG.MANIFEST_PATH
            ) then

                local ok,
                    previous =
                    pcall(
                        READFILE,
                        CONFIG.MANIFEST_PATH
                    )

                if ok
                and type(previous)
                    == "string"
                and #previous > 0 then

                    WRITEFILE(
                        CONFIG.MANIFEST_BACKUP_PATH,
                        previous
                    )
                end
            end

            ----------------------------------------------------
            -- MANIFEST NOVO
            ----------------------------------------------------

            WRITEFILE(
                CONFIG.MANIFEST_PATH,
                encoded
            )
        end)

    if success then

        ManifestState.dirty =
            false

        ManifestState.recordsSinceSave =
            0

        ManifestState.lastSaveClock =
            now
    end
end

local function decodeManifest(path)

    if not FILESYSTEM_OK
    or not ISFILE(path) then

        return nil
    end

    local ok,
        raw =
        pcall(
            READFILE,
            path
        )

    if not ok
    or type(raw) ~= "string" then

        return nil
    end

    local decodedOk,
        manifest =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            raw
        )

    if decodedOk
    and type(manifest)
        == "table" then

        return manifest
    end

    return nil
end

local function recoverBlocksByProbe()

    local blocks = {}

    if not FILESYSTEM_OK then
        return blocks
    end

    for i = 1, 10000 do

        local path =
            blockPath(i)

        if ISFILE(path) then

            table.insert(
                blocks,
                path
            )

        else
            break
        end
    end

    return blocks
end

local function rebuildArchiveCounters()

    if not FILESYSTEM_OK then
        return
    end

    local bytes = 0
    local records = 0
    local currentBytes = 0

    for _,
        path
    in ipairs(Archive.Blocks) do

        if ISFILE(path) then

            local ok,
                text =
                pcall(
                    READFILE,
                    path
                )

            if ok
            and type(text)
                == "string" then

                bytes += #text

                local _,
                    count =
                    string.gsub(
                        text,
                        "\n",
                        "\n"
                    )

                records += count

                if #text > 0
                and string.sub(
                    text,
                    -1
                ) ~= "\n" then

                    records += 1
                end

                if path
                    == blockPath(
                        Archive.CurrentBlock
                    ) then

                    currentBytes =
                        #text
                end
            end
        end
    end

    Archive.Bytes =
        bytes

    Archive.Records =
        records

    Archive.CurrentBlockBytes =
        currentBytes
end

local function loadArchive()

    ------------------------------------------------------------
    -- MEMORY FALLBACK
    ------------------------------------------------------------

    if not FILESYSTEM_OK then

        Archive.Persistent =
            false

        local shared =
            rawget(
                env,
                "__CAFEINA_MAPPING_MEMORY"
            )

        if type(shared)
            == "table"

        and type(shared.lines)
            == "table" then

            Archive.MemoryLines =
                shared.lines

            Archive.Sessions =
                tonumber(
                    shared.sessions
                ) or 0

            for _,
                line
            in ipairs(
                Archive.MemoryLines
            ) do

                Archive.Bytes +=
                    #line + 1

                Archive.Records +=
                    1
            end

        else

            env.__CAFEINA_MAPPING_MEMORY =
                {
                    lines =
                        Archive.MemoryLines,

                    sessions =
                        Archive.Sessions,
                }
        end

        return
    end

    ------------------------------------------------------------
    -- FILESYSTEM
    ------------------------------------------------------------

    ensureArchiveFolder()

    local manifest =
        decodeManifest(
            CONFIG.MANIFEST_PATH
        )

    if not manifest then

        manifest =
            decodeManifest(
                CONFIG.MANIFEST_BACKUP_PATH
            )
    end

    if manifest then

        Archive.Blocks =
            manifest.blocks
            or {}

        Archive.CurrentBlock =
            tonumber(
                manifest.currentBlock
            ) or 1

        Archive.Sessions =
            tonumber(
                manifest.sessions
            ) or 0
    end

    ------------------------------------------------------------
    -- MANIFEST PODE TER SUMIDO MAS BLOCOS CONTINUAM
    ------------------------------------------------------------

    if #Archive.Blocks == 0 then

        Archive.Blocks =
            recoverBlocksByProbe()
    end

    if #Archive.Blocks == 0 then

        Archive.Blocks = {
            blockPath(1)
        }

        Archive.CurrentBlock =
            1

    else

        Archive.CurrentBlock =
            math.max(
                Archive.CurrentBlock,
                #Archive.Blocks
            )
    end

    rebuildArchiveCounters()

    ManifestState.dirty =
        true

    saveManifest(true)
end

local function appendLine(
    path,
    line
)

    if APPENDFILE then

        return pcall(
            APPENDFILE,
            path,
            line
        )
    end

    local previous = ""

    if ISFILE(path) then

        local ok,
            data =
            pcall(
                READFILE,
                path
            )

        if ok
        and type(data)
            == "string" then

            previous =
                data
        end
    end

    return pcall(
        WRITEFILE,
        path,
        previous .. line
    )
end

local function archiveJsonLine(json)

    local bytes =
        #json + 1

    if Archive.Bytes + bytes
        > CONFIG.MAX_ARCHIVE_BYTES then

        Session.StopRequested =
            true

        Session.StopReason =
            "size_limit"

        return false,
            "size_limit"
    end

    ------------------------------------------------------------
    -- DISK
    ------------------------------------------------------------

    if Archive.Persistent then

        ensureArchiveFolder()

        if Archive.CurrentBlockBytes
            > 0

        and Archive.CurrentBlockBytes
            + bytes

            > CONFIG.BLOCK_TARGET_BYTES
        then

            Archive.CurrentBlock +=
                1

            Archive.CurrentBlockBytes =
                0

            local path =
                blockPath(
                    Archive.CurrentBlock
                )

            table.insert(
                Archive.Blocks,
                path
            )

            ManifestState.dirty =
                true

            saveManifest(true)
        end

        local path =
            blockPath(
                Archive.CurrentBlock
            )

        if Archive.Blocks[
            #Archive.Blocks
        ] ~= path then

            table.insert(
                Archive.Blocks,
                path
            )
        end

        local ok,
            err =
            appendLine(
                path,
                json .. "\n"
            )

        if not ok then

            return false,
                tostring(err)
        end

        Archive.CurrentBlockBytes +=
            bytes

    ------------------------------------------------------------
    -- MEMORY
    ------------------------------------------------------------

    else

        table.insert(
            Archive.MemoryLines,
            json
        )
    end

    Archive.Bytes +=
        bytes

    Archive.Records +=
        1

    ManifestState.dirty =
        true

    ManifestState.recordsSinceSave +=
        1

    saveManifest(false)

    return true
end

--==============================================================--
-- COMPACT UI
--==============================================================--

local COLORS = {

    BG =
        Color3.fromRGB(
            7,
            7,
            9
        ),

    PANEL =
        Color3.fromRGB(
            15,
            15,
            18
        ),

    BUTTON =
        Color3.fromRGB(
            28,
            28,
            32
        ),

    RED =
        Color3.fromRGB(
            205,
            38,
            48
        ),

    RED_DARK =
        Color3.fromRGB(
            105,
            25,
            31
        ),

    GREEN =
        Color3.fromRGB(
            45,
            180,
            88
        ),

    TEXT =
        Color3.fromRGB(
            245,
            245,
            247
        ),

    SUB =
        Color3.fromRGB(
            145,
            145,
            155
        ),

    BAR_BG =
        Color3.fromRGB(
            31,
            31,
            36
        ),

    BORDER =
        Color3.fromRGB(
            44,
            44,
            49
        ),
}

local guiParent =
    CoreGui

pcall(function()

    if type(gethui)
        == "function" then

        guiParent =
            gethui()
    end
end)

pcall(function()

    local old =
        guiParent:FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui =
    Instance.new(
        "ScreenGui"
    )

Gui.Name =
    CONFIG.GUI_NAME

Gui.ResetOnSpawn =
    false

Gui.IgnoreGuiInset =
    false

local parentOk =
    pcall(function()

        Gui.Parent =
            guiParent
    end)

if not parentOk then

    Gui.Parent =
        LocalPlayer:WaitForChild(
            "PlayerGui"
        )
end

local Main =
    Instance.new(
        "Frame"
    )

Main.Size =
    UDim2.fromOffset(
        224,
        154
    )

Main.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

Main.Position =
    UDim2.fromScale(
        0.5,
        0.5
    )

Main.BackgroundColor3 =
    COLORS.BG

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

local corner =
    Instance.new(
        "UICorner"
    )

corner.CornerRadius =
    UDim.new(
        0,
        9
    )

corner.Parent =
    Main

local stroke =
    Instance.new(
        "UIStroke"
    )

stroke.Color =
    COLORS.BORDER

stroke.Thickness =
    1

stroke.Parent =
    Main

local Header =
    Instance.new(
        "TextLabel"
    )

Header.Size =
    UDim2.new(
        1,
        -12,
        0,
        29
    )

Header.Position =
    UDim2.fromOffset(
        6,
        2
    )

Header.BackgroundTransparency =
    1

Header.Text =
    "CAFEÍNA • MAPPING V1.4"

Header.TextColor3 =
    COLORS.TEXT

Header.TextSize =
    11

Header.Font =
    Enum.Font.GothamBold

Header.Active =
    true

Header.Parent =
    Main

local ActionButton =
    Instance.new(
        "TextButton"
    )

ActionButton.Size =
    UDim2.new(
        1,
        -16,
        0,
        37
    )

ActionButton.Position =
    UDim2.fromOffset(
        8,
        32
    )

ActionButton.BackgroundColor3 =
    COLORS.BUTTON

ActionButton.BorderSizePixel =
    0

ActionButton.AutoButtonColor =
    false

ActionButton.Text =
    "INICIAR TUDO"

ActionButton.TextColor3 =
    COLORS.TEXT

ActionButton.TextSize =
    11

ActionButton.Font =
    Enum.Font.GothamBold

ActionButton.Parent =
    Main

local buttonCorner =
    Instance.new(
        "UICorner"
    )

buttonCorner.CornerRadius =
    UDim.new(
        0,
        7
    )

buttonCorner.Parent =
    ActionButton

local StatusLabel =
    Instance.new(
        "TextLabel"
    )

StatusLabel.Size =
    UDim2.new(
        1,
        -16,
        0,
        18
    )

StatusLabel.Position =
    UDim2.fromOffset(
        8,
        76
    )

StatusLabel.BackgroundTransparency =
    1

StatusLabel.Text =
    "Pronto"

StatusLabel.TextColor3 =
    COLORS.TEXT

StatusLabel.TextSize =
    10

StatusLabel.Font =
    Enum.Font.GothamBold

StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Left

StatusLabel.Parent =
    Main

local DetailLabel =
    Instance.new(
        "TextLabel"
    )

DetailLabel.Size =
    UDim2.new(
        1,
        -16,
        0,
        30
    )

DetailLabel.Position =
    UDim2.fromOffset(
        8,
        94
    )

DetailLabel.BackgroundTransparency =
    1

DetailLabel.Text =
    "0.00 MB coletados • faltam 150.00 MB"

DetailLabel.TextColor3 =
    COLORS.SUB

DetailLabel.TextSize =
    9

DetailLabel.Font =
    Enum.Font.Gotham

DetailLabel.TextWrapped =
    true

DetailLabel.TextXAlignment =
    Enum.TextXAlignment.Left

DetailLabel.Parent =
    Main

local Bar =
    Instance.new(
        "Frame"
    )

Bar.Size =
    UDim2.new(
        1,
        -16,
        0,
        9
    )

Bar.Position =
    UDim2.new(
        0,
        8,
        1,
        -19
    )

Bar.BackgroundColor3 =
    COLORS.BAR_BG

Bar.BorderSizePixel =
    0

Bar.Parent =
    Main

local barCorner =
    Instance.new(
        "UICorner"
    )

barCorner.CornerRadius =
    UDim.new(
        1,
        0
    )

barCorner.Parent =
    Bar

local BarFill =
    Instance.new(
        "Frame"
    )

BarFill.Size =
    UDim2.fromScale(
        0,
        1
    )

BarFill.BackgroundColor3 =
    COLORS.RED

BarFill.BorderSizePixel =
    0

BarFill.Parent =
    Bar

local fillCorner =
    Instance.new(
        "UICorner"
    )

fillCorner.CornerRadius =
    UDim.new(
        1,
        0
    )

fillCorner.Parent =
    BarFill

--==============================================================--
-- MOBILE SCALE
--==============================================================--

local Scale =
    Instance.new(
        "UIScale"
    )

Scale.Parent =
    Main

local function refreshScale()

    local camera =
        Workspace.CurrentCamera

    if not camera then
        return
    end

    local viewport =
        camera.ViewportSize

    Scale.Scale =
        math.min(
            1,
            math.max(
                0.82,
                (viewport.X - 16)
                    / 224
            )
        )
end

refreshScale()

pcall(function()

    if Workspace.CurrentCamera then

        Workspace.CurrentCamera:
            GetPropertyChangedSignal(
                "ViewportSize"
            ):
            Connect(
                refreshScale
            )
    end
end)

--==============================================================--
-- DRAG
--==============================================================--

do

    local dragging =
        false

    local startInput

    local startPosition

    Header.InputBegan:
        Connect(function(input)

            if input.UserInputType
                == Enum.UserInputType.Touch

            or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then

                dragging =
                    true

                startInput =
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

            if input.UserInputType
                ~= Enum.UserInputType.Touch

            and input.UserInputType
                ~= Enum.UserInputType.MouseMovement
            then

                return
            end

            local delta =
                input.Position
                - startInput

            local scale =
                math.max(
                    Scale.Scale,
                    0.01
                )

            Main.Position =
                UDim2.new(

                    startPosition.X.Scale,

                    startPosition.X.Offset
                        + delta.X
                        / scale,

                    startPosition.Y.Scale,

                    startPosition.Y.Offset
                        + delta.Y
                        / scale
                )
        end)

    UserInputService.InputEnded:
        Connect(function(input)

            if input.UserInputType
                == Enum.UserInputType.Touch

            or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then

                dragging =
                    false
            end
        end)
end

--==============================================================--
-- UI UPDATE
--==============================================================--

local lastUiUpdate =
    0

local function setBar(
    ratio,
    uploadMode
)

    ratio =
        clamp01(ratio)

    BarFill.BackgroundColor3 =
        uploadMode
        and COLORS.GREEN
        or COLORS.RED

    pcall(function()

        TweenService:Create(

            BarFill,

            TweenInfo.new(
                0.10
            ),

            {
                Size =
                    UDim2.fromScale(
                        ratio,
                        1
                    )
            }

        ):Play()
    end)
end

local function updateUI(force)

    local now =
        os.clock()

    if not force
    and now - lastUiUpdate
        < CONFIG.UI_UPDATE_INTERVAL then

        return
    end

    lastUiUpdate =
        now

    ------------------------------------------------------------
    -- COLLECTING
    ------------------------------------------------------------

    if Flow.Mode
        == "collecting" then

        local remaining =
            math.max(
                0,

                CONFIG.MAX_ARCHIVE_BYTES
                    - Archive.Bytes
            )

        StatusLabel.Text =
            "Coletando • Scan + Test Lab"

        DetailLabel.Text =
            string.format(
                "%.2f MB coletados • faltam %.2f MB",

                mb(Archive.Bytes),

                mb(remaining)
            )

        setBar(

            Archive.Bytes
                / CONFIG.MAX_ARCHIVE_BYTES,

            false
        )

    ------------------------------------------------------------
    -- FINALIZING
    ------------------------------------------------------------

    elseif Flow.Mode
        == "finalizing" then

        StatusLabel.Text =
            "Finalizando coleta..."

        DetailLabel.Text =
            string.format(
                "%.2f MB preservados • fechando observadores",

                mb(
                    Archive.Bytes
                )
            )

        setBar(

            Archive.Bytes
                / CONFIG.MAX_ARCHIVE_BYTES,

            false
        )

    ------------------------------------------------------------
    -- UPLOADING
    ------------------------------------------------------------

    elseif Flow.Mode
        == "uploading" then

        local ratio = 0

        if Upload.TotalBytes
            > 0 then

            ratio =
                Upload.BytesSent
                / Upload.TotalBytes
        end

        StatusLabel.Text =
            string.format(
                "Enviando ao servidor • %d%%",

                math.floor(
                    clamp01(ratio)
                    * 100
                )
            )

        DetailLabel.Text =
            string.format(
                "%.2f / %.2f MB • chunk %d/%d",

                mb(
                    Upload.BytesSent
                ),

                mb(
                    Upload.TotalBytes
                ),

                Upload.CurrentChunk,

                Upload.TotalChunks
            )

        setBar(
            ratio,
            true
        )

    ------------------------------------------------------------
    -- IDLE
    ------------------------------------------------------------

    else

        local remaining =
            math.max(
                0,

                CONFIG.MAX_ARCHIVE_BYTES
                    - Archive.Bytes
            )

        if Archive.Records > 0 then

            StatusLabel.Text =
                "Arquivo preservado"

            DetailLabel.Text =
                string.format(
                    "%.2f MB arquivados • faltam %.2f MB",

                    mb(
                        Archive.Bytes
                    ),

                    mb(
                        remaining
                    )
                )

            setBar(

                Archive.Bytes
                    / CONFIG.MAX_ARCHIVE_BYTES,

                false
            )

        else

            StatusLabel.Text =
                "Pronto"

            DetailLabel.Text =
                string.format(
                    "0.00 MB coletados • faltam %.2f MB",

                    mb(
                        CONFIG.MAX_ARCHIVE_BYTES
                    )
                )

            setBar(
                0,
                false
            )
        end
    end
end

--==============================================================--
-- ERROR
--==============================================================--

local function pushError(
    where,
    err
)

    table.insert(
        Report.diagnostics.errors,
        {
            where =
                tostring(where),

            error =
                tostring(err),

            time =
                relativeTime(),
        }
    )
end

--==============================================================--
-- RECORD ACCEPT
--==============================================================--

local function acceptRecord(record)

    record.source =
        record.source
        or "scan"

    record.kind =
        record.kind
        or "unknown"

    record.time =
        record.time
        or relativeTime()

    record.runId =
        record.runId
        or Session.RunId

    record.context =
        record.context
        or classifyContext(
            record.path
            or record.name
            or ""
        )

    record.correlationWindow =
        record.correlationWindow
        or correlationWindow()

    local json =
        safeJson(record)

    local ok,
        why =
        archiveJsonLine(json)

    if not ok then

        if why
            == "size_limit" then

            if requestStopAndUpload
            and Session.Running then

                task.defer(function()

                    requestStopAndUpload(
                        "size_limit"
                    )
                end)
            end

        else

            pushError(
                "archive",
                why
            )
        end

        return false
    end

    Session.RecordCount +=
        1

    table.insert(
        Report.records,
        record
    )

    if #Report.records
        > CONFIG.MEMORY_RECORD_CAP then

        -- Evita crescimento ilimitado.
        -- Remove em pequenos lotes em vez de a cada registro.
        for _ = 1, 100 do

            if #Report.records
                <= CONFIG.MEMORY_RECORD_CAP
                - 100 then

                break
            end

            table.remove(
                Report.records,
                1
            )
        end
    end

    local counters =
        Report.diagnostics.counters

    counters.total +=
        1

    counters[
        record.source
    ] =
        (
            counters[
                record.source
            ]
            or 0
        ) + 1

    if counters.total
        % 25 == 0 then

        updateUI()
    end

    return true
end

--==============================================================--
-- STATIC RECORD
--==============================================================--

local function shouldSkipStatic(inst)

    if inst:IsA("Pose")
    or inst:IsA("Keyframe") then

        return true
    end

    if inst:IsA("IntValue")
    and relevanceOf(inst)
        < 35 then

        return true
    end

    return false
end

local function buildInstanceRecord(
    inst,
    source,
    cachedPath,
    cachedScore
)

    local path =
        cachedPath
        or safePath(inst)

    local relevance =
        cachedScore
        or relevanceFromPath(
            inst,
            path
        )

    local record = {

        source =
            source or "scan",

        kind =
            "object",

        name =
            inst.Name,

        className =
            inst.ClassName,

        path =
            path,

        parentPath =
            inst.Parent
            and safePath(
                inst.Parent
            )
            or "",

        relevance =
            relevance,

        attributes =
            safeAttributes(inst),

        context =
            classifyContext(
                path
            ),
    }

    local okChildren,
        children =
        pcall(function()

            return inst:GetChildren()
        end)

    record.childCount =
        okChildren
        and #children
        or 0

    local p =
        inst

    while p
    and p.Parent do

        if p.Parent
            == game then

            record.service =
                p.Name

            break
        end

        p =
            p.Parent
    end

    if inst:IsA(
        "ValueBase"
    ) then

        pcall(function()

            record.value =
                safeSerialize(
                    inst.Value
                )
        end)
    end

    if inst:IsA(
        "ObjectValue"
    ) then

        pcall(function()

            if inst.Value then

                record.targetPath =
                    safePath(
                        inst.Value
                    )

                record.targetClass =
                    inst.Value.ClassName
            end
        end)
    end

    if inst:IsA("RemoteEvent")
    or inst:IsA("RemoteFunction")
    or inst:IsA(
        "UnreliableRemoteEvent"
    ) then

        record.remote = {

            type =
                inst.ClassName,

            path =
                path,
        }
    end

    if inst:IsA(
        "LuaSourceContainer"
    ) then

        record.script = {

            type =
                inst.ClassName,

            path =
                path,
        }
    end

    if inst:IsA("Tool") then

        pcall(function()

            record.requiresHandle =
                inst.RequiresHandle

            record.canBeDropped =
                inst.CanBeDropped
        end)
    end

    if inst:IsA(
        "ProximityPrompt"
    ) then

        pcall(function()

            record.actionText =
                inst.ActionText

            record.objectText =
                inst.ObjectText

            record.holdDuration =
                inst.HoldDuration

            record.maxActivationDistance =
                inst.MaxActivationDistance
        end)
    end

    if inst:IsA("Humanoid") then

        pcall(function()

            record.health =
                inst.Health

            record.maxHealth =
                inst.MaxHealth

            record.walkSpeed =
                inst.WalkSpeed

            record.jumpPower =
                inst.JumpPower
        end)
    end

    return record
end

--==============================================================--
-- MAPPING ENGINE
--==============================================================--

local STATIC_CLASS_LIMITS = {

    Texture = 100,

    Decal = 100,

    SurfaceAppearance = 70,

    ParticleEmitter = 120,

    Trail = 70,

    Beam = 70,
}

local function scoreBucket(score)

    if score >= 140 then
        return 1
    end

    if score >= 90 then
        return 2
    end

    if score >= 45 then
        return 3
    end

    return 4
end

local function runMappingEngine()

    Session.ScanRunning =
        true

    acceptRecord({

        source =
            "session",

        kind =
            "mapping_started",

        scanner =
            CONFIG.VERSION,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        placeVersion =
            game.PlaceVersion,
    })

    for serviceIndex,
        serviceInfo
    in ipairs(
        CONFIG.SERVICES
    ) do

        if Session.StopRequested then
            break
        end

        Session.CurrentService =
            serviceInfo.name

        local okService,
            service =
            pcall(function()

                return game:GetService(
                    serviceInfo.name
                )
            end)

        if okService
        and service then

            local descendants

            local okDesc,
                err =
                pcall(function()

                    descendants =
                        service:GetDescendants()
                end)

            if okDesc
            and descendants then

                local buckets = {
                    {},
                    {},
                    {},
                    {},
                }

                local noiseSeen = {}

                ------------------------------------------------
                -- CLASSIFICA
                ------------------------------------------------

                for i,
                    inst
                in ipairs(descendants) do

                    if Session.StopRequested then
                        break
                    end

                    if not shouldSkipStatic(
                        inst
                    ) then

                        local classLimit =
                            STATIC_CLASS_LIMITS[
                                inst.ClassName
                            ]

                        local allowed =
                            true

                        if classLimit then

                            noiseSeen[
                                inst.ClassName
                            ] =
                                (
                                    noiseSeen[
                                        inst.ClassName
                                    ]
                                    or 0
                                )

                            if noiseSeen[
                                inst.ClassName
                            ] >= classLimit then

                                allowed =
                                    false

                            else

                                noiseSeen[
                                    inst.ClassName
                                ] += 1
                            end
                        end

                        if allowed then

                            local path =
                                safePath(inst)

                            local score =
                                relevanceFromPath(
                                    inst,
                                    path
                                )

                            local bucket =
                                scoreBucket(
                                    score
                                )

                            -- Limita apenas lixo de prioridade baixa.
                            if bucket ~= 4
                            or #buckets[4]
                                < serviceInfo.budget
                            then

                                table.insert(
                                    buckets[
                                        bucket
                                    ],

                                    {
                                        inst =
                                            inst,

                                        path =
                                            path,

                                        score =
                                            score,
                                    }
                                )
                            end
                        end
                    end

                    if i
                        % CONFIG.SCAN_YIELD_EVERY
                        == 0 then

                        task.wait()
                    end
                end

                descendants =
                    nil

                ------------------------------------------------
                -- PROCESSA ALTA → BAIXA PRIORIDADE
                ------------------------------------------------

                local processed =
                    0

                for bucketIndex = 1, 4 do

                    local bucket =
                        buckets[
                            bucketIndex
                        ]

                    for _,
                        candidate
                    in ipairs(bucket) do

                        if Session.StopRequested
                        or processed
                            >= serviceInfo.budget
                        then

                            break
                        end

                        local inst =
                            candidate.inst

                        if inst
                        and inst.Parent then

                            local ok,
                                record =
                                pcall(
                                    buildInstanceRecord,

                                    inst,

                                    "scan",

                                    candidate.path,

                                    candidate.score
                                )

                            if ok
                            and record then

                                acceptRecord(
                                    record
                                )

                                Session.ObjectsScanned +=
                                    1

                                processed +=
                                    1
                            end
                        end

                        if processed
                            % CONFIG.SCAN_YIELD_EVERY
                            == 0 then

                            task.wait()
                        end
                    end

                    if Session.StopRequested
                    or processed
                        >= serviceInfo.budget
                    then

                        break
                    end
                end

                table.clear(
                    buckets
                )

            else

                pushError(
                    "mapping:"
                        .. serviceInfo.name,

                    err
                )
            end

            Session.ServicesDone =
                serviceIndex

            updateUI()
        end
    end

    Session.ScanRunning =
        false

    acceptRecord({

        source =
            "session",

        kind =
            "mapping_finished",

        objectsScanned =
            Session.ObjectsScanned,

        servicesDone =
            Session.ServicesDone,

        stopped =
            Session.StopRequested,

        stopReason =
            Session.StopReason,
    })

    updateUI(true)
end

--==============================================================--
-- TEST LAB PASSIVO
--==============================================================--

local NOISY_REMOTE_WORDS = {

    "npclook",

    "look",

    "armclient",

    "tweencommunication",
}

local function isNoisyRemote(path)

    local lower =
        string.lower(
            path
        )

    for _,
        word
    in ipairs(
        NOISY_REMOTE_WORDS
    ) do

        if string.find(
            lower,
            word,
            1,
            true
        ) then

            return true
        end
    end

    return false
end

local function recordDynamic(record)

    if DynamicEvents
        >= CONFIG.MAX_DYNAMIC_EVENTS then

        return false
    end

    DynamicEvents +=
        1

    return acceptRecord(
        record
    )
end

local function observeRemote(remote)

    if not remote:IsA(
        "RemoteEvent"
    )
    and not remote:IsA(
        "UnreliableRemoteEvent"
    ) then

        return
    end

    if ObservedRemoteSet[
        remote
    ] then

        return
    end

    if ObservedRemoteCount
        >= CONFIG.MAX_TRACKED_REMOTES then

        return
    end

    ObservedRemoteSet[
        remote
    ] =
        true

    ObservedRemoteCount +=
        1

    local path =
        safePath(remote)

    local ok,
        connection =
        pcall(function()

            return remote.OnClientEvent:
                Connect(function(...)

                    if not Session.TestsRunning
                    or Session.StopRequested then

                        return
                    end

                    local args = {
                        ...
                    }

                    if isNoisyRemote(
                        path
                    ) then

                        local aggregate =
                            RemoteAggregates[
                                path
                            ]

                        if not aggregate then

                            aggregate = {

                                count = 0,

                                firstTime =
                                    relativeTime(),

                                lastTime =
                                    relativeTime(),

                                samples = {},
                            }

                            RemoteAggregates[
                                path
                            ] =
                                aggregate
                        end

                        aggregate.count +=
                            1

                        aggregate.lastTime =
                            relativeTime()

                        if #aggregate.samples
                            < 6 then

                            table.insert(
                                aggregate.samples,

                                safeSerialize(
                                    args
                                )
                            )
                        end

                        if aggregate.count
                            == 1

                        or aggregate.count
                            % 100 == 0
                        then

                            recordDynamic({

                                source =
                                    "tests",

                                kind =
                                    "remote_aggregate",

                                path =
                                    path,

                                className =
                                    remote.ClassName,

                                count =
                                    aggregate.count,

                                firstTime =
                                    aggregate.firstTime,

                                lastTime =
                                    aggregate.lastTime,

                                samples =
                                    aggregate.samples,
                            })
                        end

                        return
                    end

                    recordDynamic({

                        source =
                            "tests",

                        kind =
                            "remote_received",

                        path =
                            path,

                        className =
                            remote.ClassName,

                        argc =
                            #args,

                        args =
                            safeSerialize(
                                args
                            ),
                    })
                end)
        end)

    if ok
    and connection then

        table.insert(
            ObserverConnections,
            connection
        )
    end
end

local function addTrackedValue(inst)

    if #TrackedValues
        >= CONFIG.MAX_TRACKED_VALUES then

        return
    end

    if TrackedValueSet[
        inst
    ] then

        return
    end

    if not inst:IsA(
        "ValueBase"
    ) then

        return
    end

    local relevance =
        relevanceOf(inst)

    if relevance < 35 then
        return
    end

    local ok,
        current =
        pcall(function()

            return inst.Value
        end)

    if not ok then
        return
    end

    local entry = {

        inst =
            inst,

        value =
            safeSerialize(
                current
            ),

        relevance =
            relevance,
    }

    TrackedValueSet[
        inst
    ] =
        true

    table.insert(
        TrackedValues,
        entry
    )

    local connection =
        inst.Changed:
        Connect(function()

            if not Session.TestsRunning
            or Session.StopRequested
            or not inst.Parent then

                return
            end

            local valueOk,
                newRaw =
                pcall(function()

                    return inst.Value
                end)

            if not valueOk then
                return
            end

            local newValue =
                safeSerialize(
                    newRaw
                )

            if not shallowEqual(
                entry.value,
                newValue
            ) then

                local before =
                    entry.value

                entry.value =
                    newValue

                recordDynamic({

                    source =
                        "tests",

                    kind =
                        "value_changed",

                    path =
                        safePath(inst),

                    className =
                        inst.ClassName,

                    before =
                        before,

                    after =
                        newValue,

                    relevance =
                        entry.relevance,
                })
            end
        end)

    table.insert(
        ObserverConnections,
        connection
    )
end

local function addTrackedAttributes(inst)

    if #TrackedAttributes
        >= CONFIG.MAX_TRACKED_ATTRIBUTES then

        return
    end

    if TrackedAttributeSet[
        inst
    ] then

        return
    end

    local relevance =
        relevanceOf(inst)

    if relevance < 30 then
        return
    end

    local attrs =
        safeAttributes(inst)

    if next(attrs)
        == nil then

        return
    end

    TrackedAttributeSet[
        inst
    ] =
        true

    table.insert(
        TrackedAttributes,

        {
            inst =
                inst,

            attrs =
                attrs,

            relevance =
                relevance,
        }
    )
end

local function dynamicSignature(inst)

    return table.concat(
        {
            inst.ClassName,

            inst.Name,

            inst.Parent
                and inst.Parent.Name
                or "",
        },

        "|"
    )
end

local function observeRoot(root)

    local descendants =
        root:GetDescendants()

    local values = {}
    local attrs = {}
    local remotes = {}

    for i,
        inst
    in ipairs(descendants) do

        if Session.StopRequested then
            break
        end

        local relevance =
            relevanceOf(inst)

        if inst:IsA(
            "ValueBase"
        )
        and relevance >= 35 then

            table.insert(
                values,

                {
                    inst =
                        inst,

                    score =
                        relevance,
                }
            )
        end

        if relevance >= 30 then

            local ok,
                attributes =
                pcall(function()

                    return inst:GetAttributes()
                end)

            if ok
            and next(attributes)
                ~= nil then

                table.insert(
                    attrs,

                    {
                        inst =
                            inst,

                        score =
                            relevance,
                    }
                )
            end
        end

        if (
            inst:IsA(
                "RemoteEvent"
            )

            or inst:IsA(
                "UnreliableRemoteEvent"
            )
        )
        and relevance >= 35
        then

            table.insert(
                remotes,

                {
                    inst =
                        inst,

                    score =
                        relevance,
                }
            )
        end

        if i
            % CONFIG.SCAN_YIELD_EVERY
            == 0 then

            task.wait()
        end
    end

    descendants =
        nil

    table.sort(
        values,

        function(a, b)

            return a.score
                > b.score
        end
    )

    table.sort(
        attrs,

        function(a, b)

            return a.score
                > b.score
        end
    )

    table.sort(
        remotes,

        function(a, b)

            return a.score
                > b.score
        end
    )

    for _,
        item
    in ipairs(values) do

        if #TrackedValues
            >= CONFIG.MAX_TRACKED_VALUES then

            break
        end

        addTrackedValue(
            item.inst
        )
    end

    for _,
        item
    in ipairs(attrs) do

        if #TrackedAttributes
            >= CONFIG.MAX_TRACKED_ATTRIBUTES then

            break
        end

        addTrackedAttributes(
            item.inst
        )
    end

    for _,
        item
    in ipairs(remotes) do

        if ObservedRemoteCount
            >= CONFIG.MAX_TRACKED_REMOTES then

            break
        end

        observeRemote(
            item.inst
        )
    end

    local added =
        root.DescendantAdded:
        Connect(function(inst)

            if not Session.TestsRunning
            or Session.StopRequested then

                return
            end

            local relevance =
                relevanceOf(inst)

            if relevance < 30 then
                return
            end

            local signature =
                dynamicSignature(
                    inst
                )

            local count =
                (
                    DynamicSignatures[
                        signature
                    ]
                    or 0
                ) + 1

            DynamicSignatures[
                signature
            ] =
                count

            if count <= 3
            or count % 25 == 0 then

                recordDynamic({

                    source =
                        "tests",

                    kind =
                        "object_created",

                    path =
                        safePath(inst),

                    className =
                        inst.ClassName,

                    name =
                        inst.Name,

                    occurrence =
                        count,

                    relevance =
                        relevance,
                })
            end

            if inst:IsA(
                "ValueBase"
            ) then

                addTrackedValue(
                    inst
                )
            end

            addTrackedAttributes(
                inst
            )

            if inst:IsA(
                "RemoteEvent"
            )
            or inst:IsA(
                "UnreliableRemoteEvent"
            ) then

                observeRemote(
                    inst
                )
            end
        end)

    local removing =
        root.DescendantRemoving:
        Connect(function(inst)

            if not Session.TestsRunning
            or Session.StopRequested then

                return
            end

            local relevance =
                relevanceOf(inst)

            if relevance < 50 then
                return
            end

            recordDynamic({

                source =
                    "tests",

                kind =
                    "object_removed",

                path =
                    safePath(inst),

                className =
                    inst.ClassName,

                name =
                    inst.Name,

                relevance =
                    relevance,
            })
        end)

    table.insert(
        ObserverConnections,
        added
    )

    table.insert(
        ObserverConnections,
        removing
    )
end

local function stopObservers()

    Session.ObserversRunning =
        false

    for _,
        connection
    in ipairs(
        ObserverConnections
    ) do

        pcall(function()

            connection:Disconnect()
        end)
    end

    table.clear(
        ObserverConnections
    )
end

local function runTestLab()

    Session.TestsRunning =
        true

    Session.ObserversRunning =
        true

    acceptRecord({

        source =
            "session",

        kind =
            "test_lab_started",

        passive =
            true,

        roots = {

            "ReplicatedStorage",

            "Players",

            "Workspace",
        },
    })

    local roots = {

        game:GetService(
            "ReplicatedStorage"
        ),

        game:GetService(
            "Players"
        ),

        game:GetService(
            "Workspace"
        ),
    }

    for _,
        root
    in ipairs(roots) do

        if Session.StopRequested then
            break
        end

        local ok,
            err =
            pcall(
                observeRoot,
                root
            )

        if not ok then

            pushError(
                "observeRoot:"
                    .. root.Name,

                err
            )
        end

        task.wait()
    end

    acceptRecord({

        source =
            "session",

        kind =
            "watch_set_ready",

        trackedValues =
            #TrackedValues,

        trackedAttributes =
            #TrackedAttributes,

        trackedRemotes =
            ObservedRemoteCount,
    })

    local cycle =
        0

    while Session.TestsRunning
    and not Session.StopRequested do

        cycle +=
            1

        --------------------------------------------------------
        -- ATTRIBUTE POLLING
        --------------------------------------------------------

        if DynamicEvents
            < CONFIG.MAX_DYNAMIC_EVENTS then

            for index,
                entry
            in ipairs(
                TrackedAttributes
            ) do

                if Session.StopRequested then
                    break
                end

                local inst =
                    entry.inst

                if inst
                and inst.Parent then

                    local newAttrs =
                        safeAttributes(
                            inst
                        )

                    if not shallowEqual(
                        entry.attrs,
                        newAttrs
                    ) then

                        local before =
                            entry.attrs

                        entry.attrs =
                            newAttrs

                        recordDynamic({

                            source =
                                "tests",

                            kind =
                                "attributes_changed",

                            path =
                                safePath(inst),

                            before =
                                before,

                            after =
                                newAttrs,

                            relevance =
                                entry.relevance,
                        })
                    end
                end

                if index
                    % CONFIG.ATTRIBUTE_YIELD_EVERY
                    == 0 then

                    task.wait()
                end
            end
        end

        --------------------------------------------------------
        -- HEARTBEAT
        --------------------------------------------------------

        if cycle
            % CONFIG.HEARTBEAT_EVERY_CYCLES
            == 0

        and DynamicEvents
            < CONFIG.MAX_DYNAMIC_EVENTS
        then

            recordDynamic({

                source =
                    "tests",

                kind =
                    "observation_heartbeat",

                cycle =
                    cycle,

                dynamicEvents =
                    DynamicEvents,
            })
        end

        updateUI()

        task.wait(
            CONFIG.ATTRIBUTE_POLL_SECONDS
        )
    end

    stopObservers()

    Session.TestsRunning =
        false

    acceptRecord({

        source =
            "session",

        kind =
            "test_lab_finished",

        cycle =
            cycle,

        dynamicEvents =
            DynamicEvents,

        stopReason =
            Session.StopReason,
    })
end

--==============================================================--
-- RESET TEMPORARY SESSION
--==============================================================--

local function resetTemporarySession()

    stopObservers()

    Report.records =
        {}

    Report.diagnostics = {

        errors = {},

        counters = {

            total = 0,

            scan = 0,

            tests = 0,

            session = 0,
        },
    }

    table.clear(
        TrackedValues
    )

    table.clear(
        TrackedAttributes
    )

    TrackedValueSet =
        setmetatable(
            {},
            {__mode = "k"}
        )

    TrackedAttributeSet =
        setmetatable(
            {},
            {__mode = "k"}
        )

    ObservedRemoteSet =
        setmetatable(
            {},
            {__mode = "k"}
        )

    table.clear(
        DynamicSignatures
    )

    table.clear(
        RemoteAggregates
    )

    DynamicEvents =
        0

    ObservedRemoteCount =
        0

    Session.Running =
        false

    Session.ScanRunning =
        false

    Session.TestsRunning =
        false

    Session.ObserversRunning =
        false

    Session.StopRequested =
        false

    Session.StopReason =
        nil

    Session.StartedAtClock =
        0

    Session.StartedAtUnix =
        0

    Session.RunId =
        nil

    Session.RecordCount =
        0

    Session.ObjectsScanned =
        0

    Session.ServicesDone =
        0

    Session.CurrentService =
        ""
end

--==============================================================--
-- START
--==============================================================--

local function startEverything()

    if Session.Running
    or Upload.Running
    or Flow.FinalizerRunning then

        return
    end

    resetTemporarySession()

    Flow.Mode =
        "collecting"

    Session.Running =
        true

    Session.StartedAtClock =
        os.clock()

    Session.StartedAtUnix =
        nowUnix()

    Session.RunId =
        newRunId()

    Archive.Sessions +=
        1

    if not Archive.Persistent
    and type(
        env.__CAFEINA_MAPPING_MEMORY
    ) == "table" then

        env.__CAFEINA_MAPPING_MEMORY.sessions =
            Archive.Sessions
    end

    ManifestState.dirty =
        true

    saveManifest(true)

    ActionButton.Text =
        "ENCERRAR"

    ActionButton.BackgroundColor3 =
        COLORS.RED

    acceptRecord({

        source =
            "session",

        kind =
            "session_started",

        mode =
            "scan_and_tests",

        passiveTestLab =
            true,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        placeVersion =
            game.PlaceVersion,

        persistent =
            Archive.Persistent,
    })

    ------------------------------------------------------------
    -- TEST LAB AUTOMÁTICO
    ------------------------------------------------------------

    task.spawn(function()

        local ok,
            err =
            pcall(
                runTestLab
            )

        if not ok then

            Session.TestsRunning =
                false

            pushError(
                "test_lab",
                err
            )
        end
    end)

    ------------------------------------------------------------
    -- SCAN AUTOMÁTICO
    ------------------------------------------------------------

    task.spawn(function()

        local ok,
            err =
            pcall(
                runMappingEngine
            )

        if not ok then

            Session.ScanRunning =
                false

            pushError(
                "mapping_engine",
                err
            )
        end
    end)

    updateUI(true)
end

--==============================================================--
-- HTTP
--==============================================================--

local function normalizeResponse(response)

    if type(response)
        ~= "table" then

        return false,
            nil,
            nil
    end

    local status =
        tonumber(

            response.StatusCode

            or response.Status

            or response.status_code

            or response.status
        )

    local body =
        response.Body
        or response.body
        or ""

    local success =
        response.Success

    if success == nil
    and status then

        success =
            status >= 200
            and status < 300
    end

    return success == true,
        status,
        body
end

local function httpPostJson(
    url,
    body,
    statusPrefix,
    allowCancel
)

    if not REQUEST then

        return false,
            nil,
            "HTTP request indisponível"
    end

    local encoded =
        safeJson(body)

    for attempt = 1,
        CONFIG.HTTP_RETRIES do

        if Upload.CancelRequested
        and not allowCancel then

            return false,
                nil,
                "cancelled"
        end

        StatusLabel.Text =
            string.format(
                "%s • tentativa %d/%d",

                statusPrefix,

                attempt,

                CONFIG.HTTP_RETRIES
            )

        local ok,
            response =
            pcall(
                REQUEST,

                {
                    Url =
                        url,

                    Method =
                        "POST",

                    Headers = {

                        ["Content-Type"] =
                            "application/json",
                    },

                    Body =
                        encoded,
                }
            )

        if ok then

            local success,
                status,
                raw =
                normalizeResponse(
                    response
                )

            if success then

                local decoded

                if type(raw)
                    == "string"

                and #raw > 0 then

                    pcall(function()

                        decoded =
                            HttpService:JSONDecode(
                                raw
                            )
                    end)
                end

                return true,
                    decoded,
                    raw
            end
        end

        if attempt
            < CONFIG.HTTP_RETRIES then

            task.wait(
                CONFIG.HTTP_RETRY_BASE
                * attempt
            )
        end
    end

    return false,
        nil,
        "request_failed"
end

--==============================================================--
-- ARCHIVE OBJECT ITERATOR
--==============================================================--

local function archiveLineIterator()

    local blockIndex =
        0

    local memoryIndex =
        0

    local lines =
        nil

    local lineIndex =
        0

    return function()

        while true do

            ----------------------------------------------------
            -- DISK
            ----------------------------------------------------

            if Archive.Persistent then

                if lines
                and lineIndex
                    < #lines then

                    lineIndex +=
                        1

                    return lines[
                        lineIndex
                    ]
                end

                blockIndex +=
                    1

                local path =
                    Archive.Blocks[
                        blockIndex
                    ]

                if not path then
                    return nil
                end

                local ok,
                    text =
                    pcall(
                        READFILE,
                        path
                    )

                lines = {}
                lineIndex = 0

                if ok
                and type(text)
                    == "string" then

                    for line
                    in string.gmatch(
                        text,
                        "[^\r\n]+"
                    ) do

                        table.insert(
                            lines,
                            line
                        )
                    end
                end

            ----------------------------------------------------
            -- MEMORY
            ----------------------------------------------------

            else

                memoryIndex +=
                    1

                return Archive.MemoryLines[
                    memoryIndex
                ]
            end
        end
    end
end

local function decodeArchiveLine(line)

    local ok,
        value =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            line
        )

    if ok
    and type(value)
        == "table" then

        return value
    end

    return {

        source =
            "diagnostic",

        kind =
            "archive_decode_error",

        bytes =
            #line,
    }
end

local function eachUploadObject(callback)

    local header = {

        recordType =
            "mapping_header",

        metadata = {

            scanner =
                CONFIG.VERSION,

            clientVisibleOnly =
                true,

            passiveTestLab =
                true,

            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            placeVersion =
                game.PlaceVersion,

            archivedBytesApprox =
                Archive.Bytes,

            archivedRecordCount =
                Archive.Records,

            persistent =
                Archive.Persistent,
        },
    }

    if callback(header)
        == false then

        return false
    end

    local iterator =
        archiveLineIterator()

    while true do

        local line =
            iterator()

        if line == nil then
            break
        end

        local object =
            decodeArchiveLine(
                line
            )

        if callback(object)
            == false then

            return false
        end
    end

    return true
end

--==============================================================--
-- UPLOAD CALCULATION
--==============================================================--

local function precalculateUpload()

    local totalChunks =
        0

    local totalBytes =
        0

    local currentBytes =
        0

    local currentCount =
        0

    eachUploadObject(
        function(object)

            local encoded =
                safeJson(object)

            local bytes =
                #encoded + 1

            if currentCount > 0
            and currentBytes + bytes
                > CONFIG.UPLOAD_CHUNK_BYTES
            then

                totalChunks +=
                    1

                totalBytes +=
                    currentBytes

                currentBytes =
                    bytes

                currentCount =
                    1

            else

                currentBytes +=
                    bytes

                currentCount +=
                    1
            end
        end
    )

    if currentCount > 0 then

        totalChunks +=
            1

        totalBytes +=
            currentBytes
    end

    return totalChunks,
        totalBytes
end

local function streamUploadChunks(
    callback
)

    local objects = {}

    local bytes =
        0

    local function flush()

        if #objects == 0 then
            return true
        end

        local current =
            objects

        objects =
            {}

        bytes =
            0

        return callback(
            current
        ) ~= false
    end

    local stopped =
        false

    eachUploadObject(
        function(object)

            if stopped then
                return false
            end

            local encoded =
                safeJson(object)

            local add =
                #encoded + 1

            if #objects > 0
            and bytes + add
                > CONFIG.UPLOAD_CHUNK_BYTES
            then

                if not flush() then

                    stopped =
                        true

                    return false
                end
            end

            table.insert(
                objects,
                object
            )

            bytes +=
                add

            return true
        end
    )

    if stopped then
        return false
    end

    return flush()
end

--==============================================================--
-- CLEAN ARCHIVE ONLY AFTER CONFIRMED FINISH
--==============================================================--

local function clearConfirmedArchive()

    if Archive.Persistent then

        for _,
            path
        in ipairs(
            Archive.Blocks
        ) do

            if ISFILE(path) then

                pcall(
                    DELFILE,
                    path
                )
            end
        end

        if ISFILE(
            CONFIG.MANIFEST_PATH
        ) then

            pcall(
                DELFILE,
                CONFIG.MANIFEST_PATH
            )
        end

        if ISFILE(
            CONFIG.MANIFEST_BACKUP_PATH
        ) then

            pcall(
                DELFILE,
                CONFIG.MANIFEST_BACKUP_PATH
            )
        end

    else

        table.clear(
            Archive.MemoryLines
        )

        env.__CAFEINA_MAPPING_MEMORY =
            {
                lines =
                    Archive.MemoryLines,

                sessions =
                    Archive.Sessions,
            }
    end

    Archive.Blocks = {
        blockPath(1)
    }

    Archive.CurrentBlock =
        1

    Archive.CurrentBlockBytes =
        0

    Archive.Bytes =
        0

    Archive.Records =
        0

    Report.records =
        {}
end

--==============================================================--
-- UPLOAD
--==============================================================--

uploadAll = function()

    if Upload.Running then
        return
    end

    ------------------------------------------------------------
    -- ARCHIVE DEVE ESTAR FECHADO
    ------------------------------------------------------------

    if Session.ScanRunning
    or Session.TestsRunning
    or Session.ObserversRunning
    then

        StatusLabel.Text =
            "Aguardando fechamento da coleta"

        return
    end

    if Archive.Records <= 0 then

        Flow.Mode =
            "idle"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    Flow.Mode =
        "uploading"

    Upload.Running =
        true

    Upload.CancelRequested =
        false

    Upload.UploadId =
        nil

    Upload.ChunksSent =
        0

    Upload.BytesSent =
        0

    Upload.CurrentChunk =
        0

    Upload.TotalChunks =
        0

    Upload.TotalBytes =
        0

    ActionButton.Text =
        "ENVIANDO..."

    ActionButton.BackgroundColor3 =
        COLORS.RED_DARK

    ------------------------------------------------------------
    -- FORCE MANIFEST
    ------------------------------------------------------------

    ManifestState.dirty =
        true

    saveManifest(true)

    ------------------------------------------------------------
    -- CALCULATE
    ------------------------------------------------------------

    StatusLabel.Text =
        "Preparando upload..."

    local calculated,
        totalChunks,
        totalBytes =
        pcall(
            precalculateUpload
        )

    if not calculated
    or not totalChunks
    or totalChunks <= 0 then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Falha ao preparar • dados preservados"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    Upload.TotalChunks =
        totalChunks

    Upload.TotalBytes =
        totalBytes

    updateUI(true)

    ------------------------------------------------------------
    -- START
    ------------------------------------------------------------

    local fileName =
        string.format(
            "Cafeina_Mapping_%s_%s.json",

            tostring(
                game.PlaceId
            ),

            isoUTC()
        )

    local startOk,
        startData =
        httpPostJson(

            CONFIG.UPLOAD_BASE
                .. "/start",

            {
                filename =
                    fileName,

                fileName =
                    fileName,

                scanner =
                    CONFIG.VERSION,

                placeId =
                    game.PlaceId,

                gameId =
                    game.GameId,

                totalChunks =
                    Upload.TotalChunks,

                totalBytes =
                    Upload.TotalBytes,
            },

            "Abrindo upload"
        )

    if not startOk then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Upload falhou • dados preservados"

        DetailLabel.Text =
            string.format(
                "%.2f MB continuam arquivados",

                mb(
                    Archive.Bytes
                )
            )

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    Upload.UploadId =
        type(startData)
            == "table"

        and (
            startData.uploadId

            or startData.id

            or startData.upload_id
        )

        or nil

    if not Upload.UploadId then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Resposta /start inválida • preservado"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    ------------------------------------------------------------
    -- CHUNKS
    ------------------------------------------------------------

    local index =
        0

    local failed =
        false

    local streamOk =
        streamUploadChunks(
            function(objects)

                index +=
                    1

                Upload.CurrentChunk =
                    index

                updateUI(true)

                local ok =
                    httpPostJson(

                        CONFIG.UPLOAD_BASE
                            .. "/chunk",

                        {
                            uploadId =
                                Upload.UploadId,

                            index =
                                index,

                            chunkIndex =
                                index,

                            totalChunks =
                                Upload.TotalChunks,

                            objects =
                                objects,
                        },

                        string.format(
                            "Chunk %d/%d",

                            index,

                            Upload.TotalChunks
                        )
                    )

                if not ok then

                    failed =
                        true

                    return false
                end

                local size =
                    #safeJson(
                        objects
                    )

                Upload.ChunksSent +=
                    1

                Upload.BytesSent =
                    math.min(

                        Upload.TotalBytes,

                        Upload.BytesSent
                            + size
                    )

                updateUI(true)

                task.wait()

                return true
            end
        )

    if not streamOk
    or failed then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Erro no upload • dados preservados"

        DetailLabel.Text =
            string.format(
                "%.2f MB continuam no archive",

                mb(
                    Archive.Bytes
                )
            )

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    ------------------------------------------------------------
    -- INTEGRITY
    ------------------------------------------------------------

    if Upload.ChunksSent
        ~= Upload.TotalChunks then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Chunks incompletos • preservado"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    ------------------------------------------------------------
    -- FINISH
    ------------------------------------------------------------

    StatusLabel.Text =
        "Confirmando arquivo..."

    Upload.BytesSent =
        Upload.TotalBytes

    updateUI(true)

    local finishOk,
        finishData =
        httpPostJson(

            CONFIG.UPLOAD_BASE
                .. "/finish",

            {
                uploadId =
                    Upload.UploadId,

                totalChunks =
                    Upload.TotalChunks,

                totalBytes =
                    Upload.TotalBytes,

                records =
                    Archive.Records,
            },

            "Confirmando /finish"
        )

    if not finishOk then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Finalização falhou • preservado"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    ------------------------------------------------------------
    -- EXPLICIT CONFIRMATION REQUIRED
    ------------------------------------------------------------

    local confirmed =
        false

    if type(finishData)
        == "table" then

        if finishData.confirmed
            == true

        or finishData.success
            == true

        or finishData.ok
            == true
        then

            confirmed =
                true
        end
    end

    if not confirmed then

        Upload.Running =
            false

        Flow.Mode =
            "idle"

        StatusLabel.Text =
            "Servidor não confirmou • preservado"

        DetailLabel.Text =
            string.format(
                "%.2f MB continuam arquivados",

                mb(
                    Archive.Bytes
                )
            )

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)

        return
    end

    ------------------------------------------------------------
    -- CONFIRMED: NOW WE MAY DELETE
    ------------------------------------------------------------

    local url =
        type(finishData)
            == "table"

        and tostring(
            finishData.url

            or finishData.link

            or finishData.fileUrl

            or ""
        )

        or ""

    Upload.LastURL =
        url

    clearConfirmedArchive()

    Upload.Running =
        false

    Flow.Mode =
        "idle"

    ActionButton.Text =
        "INICIAR TUDO"

    ActionButton.BackgroundColor3 =
        COLORS.BUTTON

    StatusLabel.Text =
        "Upload concluído"

    if url ~= "" then

        DetailLabel.Text =
            "Servidor confirmou • archive local limpo"

    else

        DetailLabel.Text =
            "100% enviado • archive local limpo"
    end

    setBar(
        1,
        true
    )

    task.delay(
        1.2,

        function()

            if Flow.Mode
                == "idle"

            and Archive.Records
                == 0 then

                updateUI(true)
            end
        end
    )
end

--==============================================================--
-- STOP + AUTO UPLOAD
--==============================================================--

requestStopAndUpload =
    function(reason)

        if Flow.FinalizerRunning then
            return
        end

        if not Session.Running
        and not Session.ScanRunning
        and not Session.TestsRunning then

            return
        end

        Flow.FinalizerRunning =
            true

        Flow.Mode =
            "finalizing"

        Session.StopRequested =
            true

        Session.StopReason =
            reason
            or "manual_stop"

        ActionButton.Text =
            "ENCERRANDO..."

        ActionButton.BackgroundColor3 =
            COLORS.RED_DARK

        acceptRecord({

            source =
                "session",

            kind =
                "stop_requested",

            reason =
                Session.StopReason,

            automaticUpload =
                true,
        })

        ManifestState.dirty =
            true

        saveManifest(true)

        updateUI(true)

        task.spawn(function()

            ----------------------------------------------------
            -- WAIT UNTIL WRITERS FINISH
            ----------------------------------------------------

            while Session.ScanRunning
            or Session.TestsRunning do

                updateUI()

                task.wait(
                    0.05
                )
            end

            ----------------------------------------------------
            -- DISCONNECT EVERYTHING
            ----------------------------------------------------

            stopObservers()

            Session.ScanRunning =
                false

            Session.TestsRunning =
                false

            Session.ObserversRunning =
                false

            ----------------------------------------------------
            -- FINAL RECORD
            ----------------------------------------------------

            if Session.StopReason
                ~= "size_limit" then

                acceptRecord({

                    source =
                        "session",

                    kind =
                        "session_finalized",

                    reason =
                        Session.StopReason,

                    records =
                        Session.RecordCount,

                    objects =
                        Session.ObjectsScanned,

                    archivedRecords =
                        Archive.Records,

                    archivedBytes =
                        Archive.Bytes,
                })
            end

            ----------------------------------------------------
            -- FORCE SAVE
            ----------------------------------------------------

            ManifestState.dirty =
                true

            saveManifest(true)

            Session.Running =
                false

            Flow.FinalizerRunning =
                false

            ----------------------------------------------------
            -- AUTO UPLOAD
            ----------------------------------------------------

            if Archive.Records > 0 then

                Flow.Mode =
                    "uploading"

                ActionButton.Text =
                    "ENVIANDO..."

                ActionButton.BackgroundColor3 =
                    COLORS.RED_DARK

                updateUI(true)

                task.wait(
                    0.10
                )

                uploadAll()

            else

                Flow.Mode =
                    "idle"

                ActionButton.Text =
                    "INICIAR TUDO"

                ActionButton.BackgroundColor3 =
                    COLORS.BUTTON

                updateUI(true)
            end
        end)
    end

--==============================================================--
-- ONE BUTTON
--==============================================================--

ActionButton.Activated:
    Connect(function()

        --------------------------------------------------------
        -- START
        --------------------------------------------------------

        if Flow.Mode
            == "idle" then

            startEverything()

            return
        end

        --------------------------------------------------------
        -- STOP
        --------------------------------------------------------

        if Flow.Mode
            == "collecting" then

            requestStopAndUpload(
                "manual_stop"
            )

            return
        end

        --------------------------------------------------------
        -- finalizing/uploading:
        -- bloqueado para proteger integridade
        --------------------------------------------------------
    end)

--==============================================================--
-- LOAD ARCHIVE
--==============================================================--

loadArchive()

if Archive.Records > 0 then

    StatusLabel.Text =
        "Arquivo anterior recuperado"

    DetailLabel.Text =
        string.format(
            "%.2f MB preservados • nova coleta será adicionada",

            mb(
                Archive.Bytes
            )
        )
end

updateUI(true)

--==============================================================--
-- EXTERNAL DESTROY
--==============================================================--

Gui.Destroying:
    Connect(function()

        --------------------------------------------------------
        -- NÃO FAZ AUTO-UPLOAD AO DESTRUIR GUI.
        -- APENAS PRESERVA.
        --------------------------------------------------------

        pcall(function()

            Session.StopRequested =
                true

            Session.StopReason =
                Session.StopReason
                or "gui_destroyed"

            stopObservers()

            ManifestState.dirty =
                true

            saveManifest(true)
        end)
    end)

--==============================================================--
-- PREVENT DUPLICATE INSTANCE
--==============================================================--

pcall(function()

    local previous =
        rawget(
            env,
            "__CAFEINA_MAPPING_V14_CONTROLLER"
        )

    if type(previous)
        == "table"

    and previous.Gui

    and previous.Gui ~= Gui then

        pcall(function()

            previous.Stop(
                "replaced_by_new_instance"
            )
        end)
    end
end)

env.__CAFEINA_MAPPING_V14_CONTROLLER =
    {

        Gui =
            Gui,

        Stop =
            function(reason)

                ------------------------------------------------
                -- EXTERNAL STOP PRESERVES DATA.
                ------------------------------------------------

                Session.StopRequested =
                    true

                Session.StopReason =
                    reason
                    or "external_stop"

                stopObservers()

                ManifestState.dirty =
                    true

                saveManifest(true)

                pcall(function()

                    Gui:Destroy()
                end)
            end,
    }

--==============================================================--
-- READY
--==============================================================--

print(
    "[CAFEÍNA] MAPPING V1.4 Compact Auto Flow carregado."
)
