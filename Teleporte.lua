--==============================================================--
-- CAFEÍNA • TELEPORT LAB V1 • COMPACT AUTO FLOW
--
-- TELEPORT-ONLY DIAGNOSTIC COLLECTOR
-- + 10 PROGRESSIVE TELEPORT TESTS
-- + SERVER-RESPONSE / ROLLBACK TRACE
-- + PERSISTENT ARCHIVE
-- + AUTOMATIC UPLOAD
--
-- MOBILE / EXECUTOR / CLIENT-VISIBLE
--
-- FLUXO:
-- INICIAR TUDO
--   ↓
-- 10 TELEPORTES PROGRESSIVOS
--   ↓
-- COLETA TRAJETÓRIA + ESTADOS + REMOTES RELACIONADOS
--   ↓
-- CLASSIFICA POSSÍVEL CORREÇÃO / ROLLBACK
--   ↓
-- FINALIZA ARCHIVE
--   ↓
-- UPLOAD AUTOMÁTICO
--   ↓
-- /finish CONFIRMADO
--   ↓
-- LIMPA ARCHIVE
--
-- IMPORTANTE:
-- • Este coletor NÃO tenta ocultar/burlar correção server-side.
-- • Ele mede somente o comportamento client-visible após o TP.
-- • Stop NÃO apaga dados.
-- • Erro de upload NÃO apaga dados.
-- • Fechar/reexecutar NÃO apaga dados persistidos.
-- • Só /finish confirmado permite apagar.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local IS_MOBILE =
    UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "TELEPORT_LAB_V1",
    GUI_NAME = "CafeinaMappingV14Compact",

    UPLOAD_BASE =
        "https://cafe-na-ia.onrender.com/upload",

    ------------------------------------------------------------
    -- ARCHIVE / UPLOAD
    ------------------------------------------------------------

    MAX_ARCHIVE_BYTES =
        150 * 1024 * 1024,

    BLOCK_TARGET_BYTES =
        1024 * 1024,

    UPLOAD_CHUNK_BYTES =
        3200000,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.25,

    ARCHIVE_FOLDER =
        "CafeinaTeleportArchive",

    MANIFEST_PATH =
        "CafeinaTeleportArchive/manifest.json",

    MANIFEST_BACKUP_PATH =
        "CafeinaTeleportArchive/manifest.bak",

    MANIFEST_FLUSH_RECORDS = 20,
    MANIFEST_FLUSH_SECONDS = 1.25,

    UI_UPDATE_INTERVAL = 0.10,

    ------------------------------------------------------------
    -- TELEPORT TEST PLAN
    ------------------------------------------------------------

    TELEPORT_DISTANCES = {
        10,
        25,
        50,
        100,
        200,
        350,
        550,
        800,
        1200,
        1800,
    },

    -- Amostragem da trajetória.
    PRE_TRACE_SECONDS = 0.28,
    POST_TRACE_SECONDS = 2.35,
    SAMPLE_INTERVAL = 0.03,

    BETWEEN_TESTS_SECONDS = 0.50,

    -- Espera adicional para posição estabilizar depois do trace.
    STABILIZE_TIMEOUT = 1.50,
    STABILIZE_REQUIRED_SECONDS = 0.30,
    STABILIZE_MOVE_EPSILON = 1.25,

    -- Classificação
    TARGET_RADIUS = 8,
    LEAVE_TARGET_RADIUS = 18,
    ORIGIN_RADIUS = 12,
    BIG_STEP_MIN = 12,

    -- Escolha segura de destino
    SEARCH_ANGLE_STEPS = 16,

    DISTANCE_FACTORS = {
        1.00,
        0.96,
        1.04,
        0.91,
        1.09,
    },

    GROUND_RAY_HEIGHT = 300,
    GROUND_RAY_DEPTH = 900,
    ROOT_EXTRA_HEIGHT = 1.20,
    CLEARANCE_XZ = 4.4,
    CLEARANCE_HEIGHT = 5.8,

    ------------------------------------------------------------
    -- REMOTES RELACIONADOS A MOVIMENTO / TELEPORTE
    ------------------------------------------------------------

    MAX_REMOTE_OBSERVERS =
        IS_MOBILE and 90 or 140,

    REMOTE_KEYWORDS = {
        "teleport",
        "position",
        "movement",
        "move",
        "character",
        "mobility",
        "cframe",
        "zone",
        "safe",
        "spawn",
        "checkpoint",
        "location",
        "area",
        "state",
        "anti",
        "verify",
        "validation",
        "correction",
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env =
    (getgenv and getgenv())
    or _G

local function pickFunction(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "function" then
            return value
        end
    end
    return nil
end

local synRequest
pcall(function()
    if syn and type(syn.request) == "function" then
        synRequest = syn.request
    end
end)

local httpRequest
pcall(function()
    if http and type(http.request) == "function" then
        httpRequest = http.request
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
    pickFunction(rawget(env, "writefile"))

local READFILE =
    pickFunction(rawget(env, "readfile"))

local APPENDFILE =
    pickFunction(rawget(env, "appendfile"))

local ISFILE =
    pickFunction(rawget(env, "isfile"))

local DELFILE =
    pickFunction(rawget(env, "delfile"))

local MAKEFOLDER =
    pickFunction(rawget(env, "makefolder"))

local ISFOLDER =
    pickFunction(rawget(env, "isfolder"))

local FILESYSTEM_OK =
    WRITEFILE
    and READFILE
    and ISFILE
    and DELFILE
    and MAKEFOLDER

if FILESYSTEM_OK
and not APPENDFILE then
    CONFIG.BLOCK_TARGET_BYTES =
        512 * 1024
end

--==============================================================--
-- HELPERS
--==============================================================--

local function mb(bytes)
    return (bytes or 0) / (1024 * 1024)
end

local function isoUTC()
    local t = os.date("!*t")
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
    local ok, guid =
        pcall(function()
            return HttpService:GenerateGUID(false)
        end)

    if ok then
        return guid
    end

    return tostring(os.time())
        .. "_"
        .. tostring(
            math.random(100000, 999999)
        )
end

local function safePath(inst)
    if not inst then
        return "?"
    end

    local ok, path =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and path or tostring(inst)
end

local function serverTime()
    local ok, result =
        pcall(function()
            return Workspace:GetServerTimeNow()
        end)

    if ok then
        return result
    end

    return nil
end

local function vec3(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end

    return {
        x = v.X,
        y = v.Y,
        z = v.Z,
    }
end

local function cfData(cf)
    if typeof(cf) ~= "CFrame" then
        return nil
    end

    local x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22 =
        cf:GetComponents()

    return {
        x = x,
        y = y,
        z = z,

        r00 = r00,
        r01 = r01,
        r02 = r02,

        r10 = r10,
        r11 = r11,
        r12 = r12,

        r20 = r20,
        r21 = r21,
        r22 = r22,
    }
end

local function safeSerialize(
    value,
    depth,
    seen
)
    depth = depth or 0
    seen = seen or {}

    if depth > 5 then
        return "<max_depth>"
    end

    local tv = typeof(value)

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
            className = value.ClassName,
        }

    elseif tv == "Vector3" then
        return vec3(value)

    elseif tv == "Vector2" then
        return {
            x = value.X,
            y = value.Y,
        }

    elseif tv == "CFrame" then
        return cfData(value)

    elseif tv == "Color3" then
        return {
            r = value.R,
            g = value.G,
            b = value.B,
        }

    elseif tv == "EnumItem" then
        return tostring(value)

    elseif tv == "table" then
        if seen[value] then
            return "<cycle>"
        end

        seen[value] = true

        local out = {}
        local count = 0

        for key, item in pairs(value) do
            count += 1

            if count > 240 then
                out["<truncated>"] = true
                break
            end

            out[tostring(key)] =
                safeSerialize(
                    item,
                    depth + 1,
                    seen
                )
        end

        seen[value] = nil
        return out
    end

    return tostring(value)
end

local function safeJson(value)
    local ok, result =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            value
        )

    if ok then
        return result
    end

    return HttpService:JSONEncode({
        kind = "serialization_error",
        error = tostring(result),
    })
end

local function decodeJson(text)
    local ok, value =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            text
        )

    if ok then
        return value
    end

    return nil
end

local function getCharacter()
    local character =
        LocalPlayer.Character

    if not character then
        return nil
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid or not root then
        return nil
    end

    return character, humanoid, root
end

local function safeAttributes(inst)
    if not inst then
        return {}
    end

    local ok, attrs =
        pcall(function()
            return inst:GetAttributes()
        end)

    if not ok then
        return {}
    end

    return safeSerialize(attrs) or {}
end

local function flatDirection(v)
    local f = Vector3.new(
        v.X,
        0,
        v.Z
    )

    if f.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end

    return f.Unit
end

local function rotateY(direction, radians)
    local cf =
        CFrame.fromAxisAngle(
            Vector3.yAxis,
            radians
        )

    return flatDirection(
        cf:VectorToWorldSpace(direction)
    )
end

--==============================================================--
-- STATE
--==============================================================--

local Session = {
    Running = false,
    TestsRunning = false,
    StopRequested = false,
    StopReason = nil,

    StartedAtClock = 0,
    StartedAtUnix = 0,
    RunId = nil,

    RecordCount = 0,

    CurrentTest = 0,
    TotalTests =
        #CONFIG.TELEPORT_DISTANCES,

    CurrentDistance = 0,

    Accepted = 0,
    Corrections = 0,
    FailedTargets = 0,
}

local Upload = {
    Running = false,
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
        FILESYSTEM_OK and true or false,

    Blocks = {},
    CurrentBlock = 1,
    CurrentBlockBytes = 0,

    Bytes = 0,
    Records = 0,
    Sessions = 0,

    MemoryLines = {},
}

local ManifestState = {
    dirty = false,
    recordsSinceSave = 0,
    lastSaveClock = 0,
}

local Flow = {
    Mode = "idle",
    FinalizerRunning = false,
}

local ActiveTest = nil
local RemoteConnections = {}
local CharacterConnections = {}

local requestStopAndUpload
local uploadAll
local updateUI

--==============================================================--
-- TIME
--==============================================================--

local function relativeTime()
    if Session.StartedAtClock == 0 then
        return 0
    end

    return os.clock()
        - Session.StartedAtClock
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
        if not ISFOLDER(CONFIG.ARCHIVE_FOLDER) then
            MAKEFOLDER(CONFIG.ARCHIVE_FOLDER)
        end
    end)
end

local function manifestTable()
    return {
        version = CONFIG.VERSION,

        blocks = Archive.Blocks,
        currentBlock = Archive.CurrentBlock,
        currentBlockBytes =
            Archive.CurrentBlockBytes,

        bytes = Archive.Bytes,
        records = Archive.Records,
        sessions = Archive.Sessions,

        updatedAt = os.time(),
    }
end

local function saveManifest(force)
    if not FILESYSTEM_OK then
        return
    end

    local now = os.clock()

    if not force then
        if not ManifestState.dirty then
            return
        end

        if
            ManifestState.recordsSinceSave
                < CONFIG.MANIFEST_FLUSH_RECORDS
            and
            now - ManifestState.lastSaveClock
                < CONFIG.MANIFEST_FLUSH_SECONDS
        then
            return
        end
    end

    ensureArchiveFolder()

    local encoded =
        safeJson(
            manifestTable()
        )

    pcall(function()
        if ISFILE(CONFIG.MANIFEST_PATH) then
            local current =
                READFILE(CONFIG.MANIFEST_PATH)

            if current and #current > 0 then
                WRITEFILE(
                    CONFIG.MANIFEST_BACKUP_PATH,
                    current
                )
            end
        end

        WRITEFILE(
            CONFIG.MANIFEST_PATH,
            encoded
        )
    end)

    ManifestState.dirty = false
    ManifestState.recordsSinceSave = 0
    ManifestState.lastSaveClock = now
end

local function initFreshArchive()
    Archive.Blocks = {
        blockPath(1)
    }

    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0

    Archive.Bytes = 0
    Archive.Records = 0

    if FILESYSTEM_OK then
        ensureArchiveFolder()

        local first =
            Archive.Blocks[1]

        if not ISFILE(first) then
            pcall(
                WRITEFILE,
                first,
                ""
            )
        end
    end
end

local function loadArchive()
    if not Archive.Persistent then
        local memory =
            env.__CAFEINA_TELEPORT_MEMORY

        if type(memory) == "table" then
            Archive.MemoryLines =
                memory.lines or {}

            Archive.Sessions =
                tonumber(memory.sessions)
                or 0

            Archive.Records =
                #Archive.MemoryLines

            local bytes = 0
            for _, line in ipairs(
                Archive.MemoryLines
            ) do
                bytes += #line + 1
            end

            Archive.Bytes = bytes
        else
            env.__CAFEINA_TELEPORT_MEMORY = {
                lines = Archive.MemoryLines,
                sessions = 0,
            }
        end

        return
    end

    ensureArchiveFolder()

    local decoded

    if ISFILE(CONFIG.MANIFEST_PATH) then
        local ok, text =
            pcall(
                READFILE,
                CONFIG.MANIFEST_PATH
            )

        if ok and text then
            decoded = decodeJson(text)
        end
    end

    if not decoded
    and ISFILE(CONFIG.MANIFEST_BACKUP_PATH)
    then
        local ok, text =
            pcall(
                READFILE,
                CONFIG.MANIFEST_BACKUP_PATH
            )

        if ok and text then
            decoded = decodeJson(text)
        end
    end

    if type(decoded) == "table"
    and type(decoded.blocks) == "table"
    then
        Archive.Blocks =
            decoded.blocks

        Archive.CurrentBlock =
            tonumber(decoded.currentBlock)
            or #Archive.Blocks
            or 1

        Archive.CurrentBlockBytes =
            tonumber(
                decoded.currentBlockBytes
            ) or 0

        Archive.Bytes =
            tonumber(decoded.bytes)
            or 0

        Archive.Records =
            tonumber(decoded.records)
            or 0

        Archive.Sessions =
            tonumber(decoded.sessions)
            or 0

        if #Archive.Blocks == 0 then
            initFreshArchive()
        end
    else
        initFreshArchive()
    end
end

local function rotateBlock()
    Archive.CurrentBlock += 1

    local path =
        blockPath(
            Archive.CurrentBlock
        )

    table.insert(
        Archive.Blocks,
        path
    )

    Archive.CurrentBlockBytes = 0

    if FILESYSTEM_OK then
        pcall(
            WRITEFILE,
            path,
            ""
        )
    end

    ManifestState.dirty = true
    saveManifest(true)
end

local function appendJsonLine(json)
    local line =
        json .. "\n"

    local bytes = #line

    if Archive.Bytes + bytes
        > CONFIG.MAX_ARCHIVE_BYTES
    then
        return false, "size_limit"
    end

    if Archive.CurrentBlockBytes > 0
    and Archive.CurrentBlockBytes + bytes
        > CONFIG.BLOCK_TARGET_BYTES
    then
        rotateBlock()
    end

    if Archive.Persistent then
        local path =
            Archive.Blocks[
                Archive.CurrentBlock
            ]

        if not path then
            rotateBlock()
            path =
                Archive.Blocks[
                    Archive.CurrentBlock
                ]
        end

        local ok, err =
            pcall(function()
                if APPENDFILE then
                    APPENDFILE(
                        path,
                        line
                    )
                else
                    local current = ""

                    if ISFILE(path) then
                        current =
                            READFILE(path)
                            or ""
                    end

                    WRITEFILE(
                        path,
                        current .. line
                    )
                end
            end)

        if not ok then
            return false, tostring(err)
        end
    else
        table.insert(
            Archive.MemoryLines,
            json
        )

        env.__CAFEINA_TELEPORT_MEMORY = {
            lines =
                Archive.MemoryLines,
            sessions =
                Archive.Sessions,
        }
    end

    Archive.CurrentBlockBytes += bytes
    Archive.Bytes += bytes
    Archive.Records += 1

    ManifestState.dirty = true
    ManifestState.recordsSinceSave += 1

    saveManifest(false)

    return true
end

local function acceptRecord(record)
    if type(record) ~= "table" then
        return false
    end

    record.scanner =
        record.scanner
        or CONFIG.VERSION

    record.runId =
        record.runId
        or Session.RunId

    record.t =
        record.t
        or relativeTime()

    record.serverTime =
        record.serverTime
        or serverTime()

    record.placeId =
        record.placeId
        or game.PlaceId

    record.gameId =
        record.gameId
        or game.GameId

    record.placeVersion =
        record.placeVersion
        or game.PlaceVersion

    local serialized =
        safeSerialize(record)

    local json =
        safeJson(serialized)

    local ok, why =
        appendJsonLine(json)

    if not ok then
        if why == "size_limit" then
            if
                requestStopAndUpload
                and Session.Running
            then
                task.defer(function()
                    requestStopAndUpload(
                        "size_limit"
                    )
                end)
            end
        end

        return false
    end

    Session.RecordCount += 1
    return true
end

local function clearConfirmedArchive()
    if Archive.Persistent then
        for _, path in ipairs(
            Archive.Blocks
        ) do
            if ISFILE(path) then
                pcall(
                    DELFILE,
                    path
                )
            end
        end

        if ISFILE(CONFIG.MANIFEST_PATH) then
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

        env.__CAFEINA_TELEPORT_MEMORY = {
            lines =
                Archive.MemoryLines,
            sessions =
                Archive.Sessions,
        }
    end

    initFreshArchive()

    Archive.Records = 0
    Archive.Bytes = 0
end

--==============================================================--
-- UI • SAME COMPACT STYLE
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

    BORDER =
        Color3.fromRGB(
            43,
            43,
            50
        ),
}

local guiParent =
    CoreGui

if type(gethui) == "function" then
    local ok, result =
        pcall(gethui)

    if ok and result then
        guiParent = result
    end
end

pcall(function()
    local old =
        guiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    CONFIG.GUI_NAME

Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false

local parentOk =
    pcall(function()
        Gui.Parent =
            guiParent
    end)

if not parentOk then
    Gui.Parent =
        LocalPlayer:
        WaitForChild("PlayerGui")
end

local Main =
    Instance.new("Frame")

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

Main.BorderSizePixel = 0
Main.Parent = Gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0, 9)

corner.Parent = Main

local stroke =
    Instance.new("UIStroke")

stroke.Color =
    COLORS.BORDER

stroke.Thickness = 1
stroke.Parent = Main

local Title =
    Instance.new("TextLabel")

Title.Size =
    UDim2.new(
        1,
        -16,
        0,
        22
    )

Title.Position =
    UDim2.fromOffset(
        8,
        5
    )

Title.BackgroundTransparency = 1

Title.Text =
    "CAFEÍNA • TELEPORT LAB"

Title.TextColor3 =
    COLORS.TEXT

Title.TextSize = 11
Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent = Main

local ActionButton =
    Instance.new("TextButton")

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

ActionButton.BorderSizePixel = 0
ActionButton.AutoButtonColor = false

ActionButton.Text =
    "INICIAR TUDO"

ActionButton.TextColor3 =
    COLORS.TEXT

ActionButton.TextSize = 11
ActionButton.Font =
    Enum.Font.GothamBold

ActionButton.Parent = Main

local buttonCorner =
    Instance.new("UICorner")

buttonCorner.CornerRadius =
    UDim.new(0, 7)

buttonCorner.Parent =
    ActionButton

local StatusLabel =
    Instance.new("TextLabel")

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

StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Pronto"

StatusLabel.TextColor3 =
    COLORS.TEXT

StatusLabel.TextSize = 10
StatusLabel.Font =
    Enum.Font.GothamBold

StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Left

StatusLabel.Parent = Main

local DetailLabel =
    Instance.new("TextLabel")

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

DetailLabel.BackgroundTransparency = 1

DetailLabel.Text =
    "10 testes progressivos • teleport-only"

DetailLabel.TextColor3 =
    COLORS.SUB

DetailLabel.TextSize = 9
DetailLabel.Font =
    Enum.Font.Gotham

DetailLabel.TextWrapped = true

DetailLabel.TextXAlignment =
    Enum.TextXAlignment.Left

DetailLabel.TextYAlignment =
    Enum.TextYAlignment.Top

DetailLabel.Parent = Main

local BarBack =
    Instance.new("Frame")

BarBack.Size =
    UDim2.new(
        1,
        -16,
        0,
        10
    )

BarBack.Position =
    UDim2.fromOffset(
        8,
        136
    )

BarBack.BackgroundColor3 =
    COLORS.PANEL

BarBack.BorderSizePixel = 0
BarBack.ClipsDescendants = true
BarBack.Parent = Main

local barCorner =
    Instance.new("UICorner")

barCorner.CornerRadius =
    UDim.new(1, 0)

barCorner.Parent = BarBack

local BarFill =
    Instance.new("Frame")

BarFill.Size =
    UDim2.fromScale(
        0,
        1
    )

BarFill.BackgroundColor3 =
    COLORS.RED

BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local barFillCorner =
    Instance.new("UICorner")

barFillCorner.CornerRadius =
    UDim.new(1, 0)

barFillCorner.Parent = BarFill

--==============================================================--
-- DRAG • MOBILE + PC
--==============================================================--

do
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:
        Connect(function(input)
            if
                input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or
                input.UserInputType
                    == Enum.UserInputType.Touch
            then
                dragging = true
                dragStart =
                    input.Position

                startPos =
                    Main.Position

                input.Changed:
                    Connect(function()
                        if
                            input.UserInputState
                                == Enum.UserInputState.End
                        then
                            dragging = false
                        end
                    end)
            end
        end)

    Main.InputChanged:
        Connect(function(input)
            if
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or
                input.UserInputType
                    == Enum.UserInputType.Touch
            then
                dragInput = input
            end
        end)

    UserInputService.InputChanged:
        Connect(function(input)
            if
                input == dragInput
                and dragging
            then
                local delta =
                    input.Position
                    - dragStart

                Main.Position =
                    UDim2.new(
                        startPos.X.Scale,
                        startPos.X.Offset
                            + delta.X,

                        startPos.Y.Scale,
                        startPos.Y.Offset
                            + delta.Y
                    )
            end
        end)
end

local lastUiUpdate = 0

local function setBar(ratio, uploadMode)
    ratio =
        math.clamp(
            ratio or 0,
            0,
            1
        )

    BarFill.BackgroundColor3 =
        uploadMode
        and COLORS.GREEN
        or COLORS.RED

    pcall(function()
        TweenService:Create(
            BarFill,

            TweenInfo.new(0.10),

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

updateUI =
    function(force)
        local now = os.clock()

        if
            not force
            and now - lastUiUpdate
                < CONFIG.UI_UPDATE_INTERVAL
        then
            return
        end

        lastUiUpdate = now

        if Flow.Mode == "collecting" then
            local index =
                Session.CurrentTest

            local total =
                Session.TotalTests

            local progress =
                total > 0
                and math.max(
                    0,
                    (index - 1) / total
                )
                or 0

            StatusLabel.Text =
                string.format(
                    "Teste %d/%d • %s studs",
                    index,
                    total,
                    tostring(
                        Session.CurrentDistance
                    )
                )

            DetailLabel.Text =
                string.format(
                    "%.2f MB • %d registros • correções %d",
                    mb(Archive.Bytes),
                    Archive.Records,
                    Session.Corrections
                )

            setBar(
                progress,
                false
            )

        elseif Flow.Mode == "finalizing" then
            StatusLabel.Text =
                "Encerrando coleta..."

            DetailLabel.Text =
                string.format(
                    "%.2f MB • preservando archive",
                    mb(Archive.Bytes)
                )

        elseif Flow.Mode == "uploading" then
            local ratio = 0

            if Upload.TotalBytes > 0 then
                ratio =
                    Upload.BytesSent
                    / Upload.TotalBytes
            elseif Upload.TotalChunks > 0 then
                ratio =
                    Upload.ChunksSent
                    / Upload.TotalChunks
            end

            StatusLabel.Text =
                string.format(
                    "Enviando %d/%d",
                    Upload.CurrentChunk,
                    Upload.TotalChunks
                )

            DetailLabel.Text =
                string.format(
                    "%.2f / %.2f MB",
                    mb(Upload.BytesSent),
                    mb(Upload.TotalBytes)
                )

            setBar(
                ratio,
                true
            )

        else
            if Archive.Records > 0 then
                StatusLabel.Text =
                    "Arquivo anterior recuperado"

                DetailLabel.Text =
                    string.format(
                        "%.2f MB • %d registros preservados",
                        mb(Archive.Bytes),
                        Archive.Records
                    )
            else
                StatusLabel.Text =
                    "Pronto"

                DetailLabel.Text =
                    "10 testes progressivos • teleport-only"
            end

            setBar(0, false)
        end
    end

--==============================================================--
-- TELEPORT-RELATED REMOTE OBSERVATION
--==============================================================--

local function remoteLooksRelevant(inst)
    if not inst then
        return false
    end

    local lower =
        string.lower(
            safePath(inst)
        )

    for _, keyword in ipairs(
        CONFIG.REMOTE_KEYWORDS
    ) do
        if
            string.find(
                lower,
                keyword,
                1,
                true
            )
        then
            return true
        end
    end

    return false
end

local function stopRemoteObservers()
    for _, conn in ipairs(
        RemoteConnections
    ) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    table.clear(
        RemoteConnections
    )
end

local function startRemoteObservers()
    stopRemoteObservers()

    local count = 0

    for _, inst in ipairs(
        ReplicatedStorage:GetDescendants()
    ) do
        if
            count
                >= CONFIG.MAX_REMOTE_OBSERVERS
        then
            break
        end

        if
            (
                inst:IsA("RemoteEvent")
                or
                inst:IsA(
                    "UnreliableRemoteEvent"
                )
            )
            and remoteLooksRelevant(inst)
        then
            count += 1

            local conn =
                inst.OnClientEvent:
                Connect(function(...)
                    local active =
                        ActiveTest

                    if
                        not active
                        or
                        not Session.TestsRunning
                    then
                        return
                    end

                    local args = {...}

                    acceptRecord({
                        source =
                            "teleport_remote",

                        kind =
                            "remote_received_during_test",

                        testId =
                            active.id,

                        requestedDistance =
                            active.requestedDistance,

                        remotePath =
                            safePath(inst),

                        argc =
                            select("#", ...),

                        args =
                            safeSerialize(args),
                    })
                end)

            table.insert(
                RemoteConnections,
                conn
            )
        end
    end

    acceptRecord({
        source =
            "teleport_observer",

        kind =
            "remote_observers_ready",

        observedRemotes =
            count,
    })
end

--==============================================================--
-- CHARACTER EVENT OBSERVATION
--==============================================================--

local function stopCharacterObservers()
    for _, conn in ipairs(
        CharacterConnections
    ) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    table.clear(
        CharacterConnections
    )
end

local function recordActiveEvent(
    kind,
    data
)
    local active =
        ActiveTest

    if
        not active
        or
        not Session.TestsRunning
    then
        return
    end

    local record = {
        source =
            "teleport_character",

        kind =
            kind,

        testId =
            active.id,

        requestedDistance =
            active.requestedDistance,
    }

    if type(data) == "table" then
        for k, v in pairs(data) do
            record[k] = v
        end
    end

    acceptRecord(record)
end

local function startCharacterObservers()
    stopCharacterObservers()

    local character,
        humanoid,
        root =
        getCharacter()

    if not character then
        return false
    end

    table.insert(
        CharacterConnections,

        humanoid.StateChanged:
        Connect(function(old, new)
            recordActiveEvent(
                "humanoid_state_changed",
                {
                    oldState =
                        tostring(old),

                    newState =
                        tostring(new),

                    position =
                        vec3(root.Position),
                }
            )
        end)
    )

    table.insert(
        CharacterConnections,

        root:GetPropertyChangedSignal(
            "Anchored"
        ):
        Connect(function()
            recordActiveEvent(
                "root_anchored_changed",
                {
                    anchored =
                        root.Anchored,

                    position =
                        vec3(root.Position),
                }
            )
        end)
    )

    table.insert(
        CharacterConnections,

        character.AncestryChanged:
        Connect(function(_, parent)
            if parent == nil then
                recordActiveEvent(
                    "character_removed",
                    {}
                )
            end
        end)
    )

    for _, target in ipairs({
        character,
        humanoid,
        root,
    }) do
        local ok, attrs =
            pcall(function()
                return target:
                    GetAttributes()
            end)

        if ok then
            for name in pairs(attrs) do
                table.insert(
                    CharacterConnections,

                    target:
                    GetAttributeChangedSignal(
                        name
                    ):
                    Connect(function()
                        local value

                        pcall(function()
                            value =
                                target:
                                GetAttribute(
                                    name
                                )
                        end)

                        recordActiveEvent(
                            "attribute_changed",
                            {
                                path =
                                    safePath(target),

                                attribute =
                                    name,

                                value =
                                    safeSerialize(
                                        value
                                    ),
                            }
                        )
                    end)
                )
            end
        end
    end

    return true
end

--==============================================================--
-- SNAPSHOT / TRACE
--==============================================================--

local function snapshot(
    testId,
    phase
)
    local character,
        humanoid,
        root =
        getCharacter()

    if not character then
        return {
            t =
                relativeTime(),

            serverTime =
                serverTime(),

            phase =
                phase,

            missingCharacter =
                true,
        }
    end

    local receiveAge

    pcall(function()
        receiveAge =
            root.ReceiveAge
    end)

    return {
        t =
            relativeTime(),

        serverTime =
            serverTime(),

        testId =
            testId,

        phase =
            phase,

        position =
            vec3(root.Position),

        cframe =
            cfData(root.CFrame),

        linearVelocity =
            vec3(
                root.AssemblyLinearVelocity
            ),

        angularVelocity =
            vec3(
                root.AssemblyAngularVelocity
            ),

        anchored =
            root.Anchored,

        receiveAge =
            receiveAge,

        humanoidState =
            tostring(
                humanoid:GetState()
            ),

        floorMaterial =
            tostring(
                humanoid.FloorMaterial
            ),

        health =
            humanoid.Health,

        walkSpeed =
            humanoid.WalkSpeed,

        jumpPower =
            humanoid.JumpPower,

        characterAttributes =
            safeAttributes(character),

        humanoidAttributes =
            safeAttributes(humanoid),

        rootAttributes =
            safeAttributes(root),
    }
end

local function samplePosition(
    sample
)
    if
        type(sample) ~= "table"
        or
        type(sample.position) ~= "table"
    then
        return nil
    end

    local p =
        sample.position

    if
        type(p.x) ~= "number"
        or
        type(p.y) ~= "number"
        or
        type(p.z) ~= "number"
    then
        return nil
    end

    return Vector3.new(
        p.x,
        p.y,
        p.z
    )
end

--==============================================================--
-- SAFE TARGET SEARCH
--==============================================================--

local function raycastGround(
    x,
    z,
    referenceY,
    character
)
    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character
    }

    pcall(function()
        params.RespectCanCollide = true
    end)

    local origin =
        Vector3.new(
            x,
            referenceY
                + CONFIG.GROUND_RAY_HEIGHT,
            z
        )

    local direction =
        Vector3.new(
            0,
            -CONFIG.GROUND_RAY_DEPTH,
            0
        )

    return Workspace:Raycast(
        origin,
        direction,
        params
    )
end

local function clearForCharacter(
    position,
    character
)
    local params =
        OverlapParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character
    }

    local center =
        position
        + Vector3.new(
            0,
            CONFIG.CLEARANCE_HEIGHT
                * 0.46,
            0
        )

    local parts =
        Workspace:GetPartBoundsInBox(
            CFrame.new(center),

            Vector3.new(
                CONFIG.CLEARANCE_XZ,
                CONFIG.CLEARANCE_HEIGHT,
                CONFIG.CLEARANCE_XZ
            ),

            params
        )

    for _, part in ipairs(parts) do
        if
            part:IsA("BasePart")
            and part.CanCollide
        then
            return false
        end
    end

    return true
end

local function findTeleportTarget(
    requestedDistance
)
    local character,
        humanoid,
        root =
        getCharacter()

    if not character then
        return nil, "character_missing"
    end

    local origin =
        root.Position

    local baseDirection =
        flatDirection(
            root.CFrame.LookVector
        )

    local rotation =
        root.CFrame.Rotation

    for _, factor in ipairs(
        CONFIG.DISTANCE_FACTORS
    ) do
        local radius =
            requestedDistance
            * factor

        for i = 0,
            CONFIG.SEARCH_ANGLE_STEPS - 1
        do
            local angle =
                (
                    math.pi * 2
                    * i
                )
                / CONFIG.SEARCH_ANGLE_STEPS

            local direction =
                rotateY(
                    baseDirection,
                    angle
                )

            local flatTarget =
                origin
                + direction * radius

            local hit =
                raycastGround(
                    flatTarget.X,
                    flatTarget.Z,
                    origin.Y,
                    character
                )

            if hit then
                local target =
                    hit.Position
                    + Vector3.new(
                        0,
                        humanoid.HipHeight
                            + root.Size.Y / 2
                            + CONFIG.ROOT_EXTRA_HEIGHT,
                        0
                    )

                if clearForCharacter(
                    target,
                    character
                ) then
                    return {
                        position =
                            target,

                        cframe =
                            CFrame.new(target)
                            * rotation,

                        requestedDistance =
                            requestedDistance,

                        actualDistance =
                            (
                                target
                                - origin
                            ).Magnitude,

                        horizontalDistance =
                            Vector3.new(
                                target.X
                                    - origin.X,
                                0,
                                target.Z
                                    - origin.Z
                            ).Magnitude,

                        direction =
                            vec3(direction),

                        ground = {
                            path =
                                safePath(
                                    hit.Instance
                                ),

                            className =
                                hit.Instance
                                and
                                hit.Instance.ClassName
                                or nil,

                            material =
                                tostring(
                                    hit.Material
                                ),

                            position =
                                vec3(
                                    hit.Position
                                ),

                            normal =
                                vec3(
                                    hit.Normal
                                ),
                        },
                    }
                end
            end
        end
    end

    return nil, "no_safe_ground_at_radius"
end

--==============================================================--
-- TRACE ANALYSIS
--==============================================================--

local function analyzeTrace(
    origin,
    target,
    samples,
    issuedAt
)
    local result = {
        classification =
            "unknown",

        targetReached =
            false,

        reachedAt =
            nil,

        closestTargetDistance =
            math.huge,

        finalDistanceFromTarget =
            nil,

        finalDistanceFromOrigin =
            nil,

        remainedAtTargetFor =
            0,

        correctionCandidates = {},

        firstCorrectionAt =
            nil,

        correctionDelay =
            nil,

        progressRatio =
            nil,
    }

    local firstReachedIndex
    local leaveIndex

    local previousPos
    local previousTime

    local targetVector =
        target - origin

    local targetDistance =
        targetVector.Magnitude

    for index, sample in ipairs(
        samples
    ) do
        local pos =
            samplePosition(sample)

        if pos then
            local dTarget =
                (pos - target).Magnitude

            if
                dTarget
                    < result.closestTargetDistance
            then
                result.closestTargetDistance =
                    dTarget
            end

            if
                not result.targetReached
                and
                dTarget
                    <= CONFIG.TARGET_RADIUS
            then
                result.targetReached = true
                result.reachedAt =
                    sample.t

                firstReachedIndex =
                    index
            end

            if
                firstReachedIndex
                and
                not leaveIndex
                and
                index > firstReachedIndex
                and
                dTarget
                    >= CONFIG.LEAVE_TARGET_RADIUS
            then
                leaveIndex =
                    index
            end

            if previousPos
            and previousTime
            and sample.t > issuedAt + 0.055
            then
                local step =
                    (
                        pos
                        - previousPos
                    ).Magnitude

                local threshold =
                    math.max(
                        CONFIG.BIG_STEP_MIN,
                        targetDistance * 0.04
                    )

                if step >= threshold then
                    table.insert(
                        result.correctionCandidates,
                        {
                            t =
                                sample.t,

                            dt =
                                sample.t
                                - previousTime,

                            distance =
                                step,

                            from =
                                vec3(
                                    previousPos
                                ),

                            to =
                                vec3(pos),
                        }
                    )

                    if not result.firstCorrectionAt then
                        result.firstCorrectionAt =
                            sample.t

                        result.correctionDelay =
                            sample.t
                            - issuedAt
                    end
                end
            end

            previousPos =
                pos

            previousTime =
                sample.t
        end
    end

    if
        firstReachedIndex
        and samples[firstReachedIndex]
    then
        local endSample =
            leaveIndex
            and samples[leaveIndex]
            or samples[#samples]

        if endSample then
            result.remainedAtTargetFor =
                math.max(
                    0,
                    (
                        endSample.t
                        or 0
                    )
                    -
                    (
                        samples[
                            firstReachedIndex
                        ].t
                        or 0
                    )
                )
        end
    end

    local finalPos =
        samplePosition(
            samples[#samples]
            or {}
        )

    if finalPos then
        result.finalDistanceFromTarget =
            (
                finalPos
                - target
            ).Magnitude

        result.finalDistanceFromOrigin =
            (
                finalPos
                - origin
            ).Magnitude

        if targetDistance > 0.01 then
            local unit =
                targetVector.Unit

            local along =
                (
                    finalPos
                    - origin
                ):Dot(unit)

            result.progressRatio =
                along
                / targetDistance
        end
    end

    local finalTarget =
        result.finalDistanceFromTarget
        or math.huge

    local finalOrigin =
        result.finalDistanceFromOrigin
        or math.huge

    if
        result.targetReached
        and
        finalTarget
            <= CONFIG.TARGET_RADIUS
    then
        result.classification =
            "accepted"

    elseif
        result.targetReached
        and
        finalOrigin
            <= CONFIG.ORIGIN_RADIUS
    then
        if
            result.remainedAtTargetFor
                >= 0.10
        then
            result.classification =
                "delayed_full_rollback"
        else
            result.classification =
                "full_rollback"
        end

    elseif
        finalOrigin
            <= CONFIG.ORIGIN_RADIUS
    then
        result.classification =
            "full_rollback"

    elseif
        result.targetReached
        and
        finalTarget
            > CONFIG.LEAVE_TARGET_RADIUS
    then
        if
            #result.correctionCandidates
                >= 2
        then
            result.classification =
                "multi_step_correction"
        else
            result.classification =
                "delayed_correction"
        end

    elseif
        result.progressRatio
        and
        result.progressRatio > 0.08
        and
        result.progressRatio < 0.90
    then
        result.classification =
            "partial_rollback"

    elseif
        result.progressRatio
        and
        result.progressRatio >= 0.90
        and
        finalTarget
            > CONFIG.TARGET_RADIUS
    then
        result.classification =
            "position_clamp"

    else
        result.classification =
            "unknown_correction"
    end

    return result
end

--==============================================================--
-- STABILIZATION
--==============================================================--

local function waitForStability()
    local deadline =
        os.clock()
        + CONFIG.STABILIZE_TIMEOUT

    local stableSince = nil
    local lastPosition = nil

    while
        os.clock() < deadline
        and not Session.StopRequested
    do
        local _, _, root =
            getCharacter()

        if not root then
            return {
                stable = false,
                reason =
                    "character_missing",
            }
        end

        local position =
            root.Position

        if lastPosition then
            local movement =
                (
                    position
                    - lastPosition
                ).Magnitude

            if movement
                <= CONFIG.STABILIZE_MOVE_EPSILON
            then
                stableSince =
                    stableSince
                    or os.clock()

                if
                    os.clock()
                        - stableSince
                        >= CONFIG.STABILIZE_REQUIRED_SECONDS
                then
                    return {
                        stable = true,
                        finalPosition =
                            vec3(position),

                        waited =
                            CONFIG.STABILIZE_TIMEOUT
                            - (
                                deadline
                                - os.clock()
                            ),
                    }
                end
            else
                stableSince = nil
            end
        end

        lastPosition =
            position

        task.wait(0.06)
    end

    local _, _, root =
        getCharacter()

    return {
        stable = false,
        reason =
            "timeout",

        finalPosition =
            root
            and vec3(root.Position)
            or nil,
    }
end

--==============================================================--
-- SINGLE TELEPORT TEST
--==============================================================--

local function runTeleportTest(
    testId,
    requestedDistance
)
    local character,
        humanoid,
        root =
        getCharacter()

    if not character then
        acceptRecord({
            source =
                "teleport_test",

            kind =
                "test_skipped",

            testId =
                testId,

            requestedDistance =
                requestedDistance,

            reason =
                "character_missing",
        })

        return false
    end

    ActiveTest = {
        id =
            testId,

        requestedDistance =
            requestedDistance,
    }

    startCharacterObservers()

    local originCFrame =
        root.CFrame

    local origin =
        root.Position

    local preSamples = {}

    local preDeadline =
        os.clock()
        + CONFIG.PRE_TRACE_SECONDS

    while
        os.clock() < preDeadline
        and not Session.StopRequested
    do
        table.insert(
            preSamples,
            snapshot(
                testId,
                "pre"
            )
        )

        task.wait(
            CONFIG.SAMPLE_INTERVAL
        )
    end

    if Session.StopRequested then
        ActiveTest = nil
        stopCharacterObservers()
        return false
    end

    local target,
        targetError =
        findTeleportTarget(
            requestedDistance
        )

    if not target then
        Session.FailedTargets += 1

        acceptRecord({
            source =
                "teleport_test",

            kind =
                "target_unavailable",

            testId =
                testId,

            requestedDistance =
                requestedDistance,

            origin =
                vec3(origin),

            reason =
                targetError,
        })

        ActiveTest = nil
        stopCharacterObservers()

        return false
    end

    acceptRecord({
        source =
            "teleport_test",

        kind =
            "teleport_plan",

        testId =
            testId,

        requestedDistance =
            requestedDistance,

        origin =
            vec3(origin),

        originCFrame =
            cfData(originCFrame),

        target =
            safeSerialize(target),
    })

    pcall(function()
        root.AssemblyLinearVelocity =
            Vector3.zero

        root.AssemblyAngularVelocity =
            Vector3.zero
    end)

    local issuedAt =
        relativeTime()

    local issuedServerTime =
        serverTime()

    local issuedClock =
        os.clock()

    local pivotOk,
        pivotError =
        pcall(function()
            character:PivotTo(
                target.cframe
            )
        end)

    acceptRecord({
        source =
            "teleport_test",

        kind =
            "teleport_issued",

        testId =
            testId,

        requestedDistance =
            requestedDistance,

        actualTargetDistance =
            target.actualDistance,

        horizontalTargetDistance =
            target.horizontalDistance,

        issuedAt =
            issuedAt,

        issuedServerTime =
            issuedServerTime,

        pivotOk =
            pivotOk,

        pivotError =
            pivotOk
            and nil
            or tostring(pivotError),

        immediate =
            snapshot(
                testId,
                "immediate"
            ),
    })

    local samples = {}

    for _, s in ipairs(
        preSamples
    ) do
        table.insert(
            samples,
            s
        )
    end

    local deadline =
        issuedClock
        + CONFIG.POST_TRACE_SECONDS

    while
        os.clock() < deadline
        and not Session.StopRequested
    do
        table.insert(
            samples,
            snapshot(
                testId,
                "post"
            )
        )

        task.wait(
            CONFIG.SAMPLE_INTERVAL
        )
    end

    local analysis =
        analyzeTrace(
            origin,
            target.position,
            samples,
            issuedAt
        )

    if analysis.classification
        == "accepted"
    then
        Session.Accepted += 1
    else
        Session.Corrections += 1
    end

    acceptRecord({
        source =
            "teleport_test",

        kind =
            "teleport_trace",

        testId =
            testId,

        requestedDistance =
            requestedDistance,

        actualTargetDistance =
            target.actualDistance,

        horizontalTargetDistance =
            target.horizontalDistance,

        origin =
            vec3(origin),

        target =
            vec3(
                target.position
            ),

        ground =
            target.ground,

        issuedAt =
            issuedAt,

        issuedServerTime =
            issuedServerTime,

        samples =
            samples,

        analysis =
            analysis,
    })

    local stability =
        waitForStability()

    acceptRecord({
        source =
            "teleport_test",

        kind =
            "teleport_test_finished",

        testId =
            testId,

        requestedDistance =
            requestedDistance,

        classification =
            analysis.classification,

        targetReached =
            analysis.targetReached,

        closestTargetDistance =
            analysis.closestTargetDistance,

        finalDistanceFromTarget =
            analysis.finalDistanceFromTarget,

        finalDistanceFromOrigin =
            analysis.finalDistanceFromOrigin,

        correctionCandidates =
            #analysis.correctionCandidates,

        stability =
            stability,
    })

    ActiveTest = nil
    stopCharacterObservers()

    return true
end

--==============================================================--
-- TEST LAB
--==============================================================--

local function runTeleportLab()
    Session.TestsRunning = true

    startRemoteObservers()

    acceptRecord({
        source =
            "teleport_session",

        kind =
            "test_plan",

        distances =
            CONFIG.TELEPORT_DISTANCES,

        totalTests =
            #CONFIG.TELEPORT_DISTANCES,

        preTraceSeconds =
            CONFIG.PRE_TRACE_SECONDS,

        postTraceSeconds =
            CONFIG.POST_TRACE_SECONDS,

        sampleInterval =
            CONFIG.SAMPLE_INTERVAL,

        targetRadius =
            CONFIG.TARGET_RADIUS,

        note =
            "server intervention is inferred only from client-visible replicated behavior",
    })

    for index, distance in ipairs(
        CONFIG.TELEPORT_DISTANCES
    ) do
        if Session.StopRequested then
            break
        end

        Session.CurrentTest =
            index

        Session.CurrentDistance =
            distance

        updateUI(true)

        acceptRecord({
            source =
                "teleport_session",

            kind =
                "test_starting",

            testId =
                index,

            requestedDistance =
                distance,
        })

        local ok, err =
            pcall(
                runTeleportTest,
                index,
                distance
            )

        if not ok then
            acceptRecord({
                source =
                    "teleport_session",

                kind =
                    "test_error",

                testId =
                    index,

                requestedDistance =
                    distance,

                error =
                    tostring(err),
            })
        end

        updateUI(true)

        if
            index
                < #CONFIG.TELEPORT_DISTANCES
            and
            not Session.StopRequested
        then
            task.wait(
                CONFIG.BETWEEN_TESTS_SECONDS
            )
        end
    end

    ActiveTest = nil

    stopCharacterObservers()
    stopRemoteObservers()

    Session.TestsRunning = false

    acceptRecord({
        source =
            "teleport_session",

        kind =
            "test_plan_finished",

        completedTests =
            Session.CurrentTest,

        totalTests =
            Session.TotalTests,

        accepted =
            Session.Accepted,

        corrections =
            Session.Corrections,

        failedTargets =
            Session.FailedTargets,

        stopped =
            Session.StopRequested,

        stopReason =
            Session.StopReason,
    })

    if
        not Session.StopRequested
        and requestStopAndUpload
    then
        task.defer(function()
            requestStopAndUpload(
                "tests_completed"
            )
        end)
    end
end

--==============================================================--
-- HTTP
--==============================================================--

local function normalizeResponse(response)
    if type(response) ~= "table" then
        return false, nil, nil
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

    if success == nil and status then
        success =
            status >= 200
            and status < 300
    end

    return
        success == true,
        status,
        body
end

local function httpPostJson(
    url,
    payload,
    label
)
    if not REQUEST then
        return false, {
            error =
                "executor_request_unavailable",
        }
    end

    local body =
        safeJson(payload)

    local lastError

    for attempt = 1,
        CONFIG.HTTP_RETRIES
    do
        local ok, response =
            pcall(
                REQUEST,
                {
                    Url = url,
                    Method = "POST",

                    Headers = {
                        ["Content-Type"] =
                            "application/json",
                    },

                    Body = body,
                }
            )

        if ok then
            local success,
                status,
                responseBody =
                normalizeResponse(
                    response
                )

            if success then
                local decoded =
                    decodeJson(
                        responseBody
                    )

                if type(decoded)
                    ~= "table"
                then
                    decoded = {
                        raw =
                            responseBody,

                        status =
                            status,
                    }
                end

                return true, decoded
            end

            lastError =
                tostring(status)
                .. " "
                .. tostring(
                    responseBody
                )
        else
            lastError =
                tostring(response)
        end

        if attempt
            < CONFIG.HTTP_RETRIES
        then
            task.wait(
                CONFIG.HTTP_RETRY_BASE
                * attempt
            )
        end
    end

    acceptRecord({
        source =
            "upload",

        kind =
            "http_error",

        label =
            label,

        url =
            url,

        error =
            lastError,
    })

    return false, {
        error =
            lastError,
    }
end

--==============================================================--
-- ARCHIVE READER FOR UPLOAD
--==============================================================--

local function decodedLine(line)
    local value =
        decodeJson(line)

    if type(value) == "table" then
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
            "teleport_header",

        scanner =
            CONFIG.VERSION,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        placeVersion =
            game.PlaceVersion,

        archiveRecords =
            Archive.Records,

        archiveBytes =
            Archive.Bytes,

        sessions =
            Archive.Sessions,

        distances =
            CONFIG.TELEPORT_DISTANCES,

        clientVisibleOnly =
            true,
    }

    if callback(header) == false then
        return false
    end

    if Archive.Persistent then
        for _, path in ipairs(
            Archive.Blocks
        ) do
            if ISFILE(path) then
                local ok, text =
                    pcall(
                        READFILE,
                        path
                    )

                if ok
                and type(text) == "string"
                then
                    for line in
                        string.gmatch(
                            text,
                            "[^\r\n]+"
                        )
                    do
                        if line ~= "" then
                            if
                                callback(
                                    decodedLine(
                                        line
                                    )
                                )
                                == false
                            then
                                return false
                            end
                        end
                    end
                end
            end
        end
    else
        for _, line in ipairs(
            Archive.MemoryLines
        ) do
            if
                callback(
                    decodedLine(line)
                )
                == false
            then
                return false
            end
        end
    end

    return true
end

local function precalculateUpload()
    local totalChunks = 0
    local totalBytes = 0

    local currentBytes = 0
    local currentCount = 0

    eachUploadObject(
        function(object)
            local encoded =
                safeJson(object)

            local bytes =
                #encoded + 1

            if
                currentCount > 0
                and
                currentBytes + bytes
                    > CONFIG.UPLOAD_CHUNK_BYTES
            then
                totalChunks += 1
                totalBytes +=
                    currentBytes

                currentBytes =
                    bytes

                currentCount = 1
            else
                currentBytes += bytes
                currentCount += 1
            end
        end
    )

    if currentCount > 0 then
        totalChunks += 1
        totalBytes +=
            currentBytes
    end

    return
        totalChunks,
        totalBytes
end

local function streamUploadChunks(
    callback
)
    local objects = {}
    local bytes = 0

    local function flush()
        if #objects == 0 then
            return true
        end

        local current =
            objects

        objects = {}
        bytes = 0

        return
            callback(current)
            ~= false
    end

    local stopped = false

    eachUploadObject(
        function(object)
            if stopped then
                return false
            end

            local encoded =
                safeJson(object)

            local add =
                #encoded + 1

            if
                #objects > 0
                and
                bytes + add
                    > CONFIG.UPLOAD_CHUNK_BYTES
            then
                if not flush() then
                    stopped = true
                    return false
                end
            end

            table.insert(
                objects,
                object
            )

            bytes += add

            return true
        end
    )

    if stopped then
        return false
    end

    return flush()
end

--==============================================================--
-- UPLOAD
--==============================================================--

uploadAll =
    function()
        if Upload.Running then
            return
        end

        if Session.TestsRunning then
            StatusLabel.Text =
                "Aguardando fechamento da coleta"

            return
        end

        if Archive.Records <= 0 then
            Flow.Mode = "idle"

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        Flow.Mode =
            "uploading"

        Upload.Running = true

        Upload.UploadId = nil
        Upload.ChunksSent = 0
        Upload.BytesSent = 0

        Upload.CurrentChunk = 0
        Upload.TotalChunks = 0
        Upload.TotalBytes = 0

        ActionButton.Text =
            "ENVIANDO..."

        ActionButton.BackgroundColor3 =
            COLORS.RED_DARK

        ManifestState.dirty = true
        saveManifest(true)

        StatusLabel.Text =
            "Preparando upload..."

        local calculated,
            totalChunks,
            totalBytes =
            pcall(
                precalculateUpload
            )

        if
            not calculated
            or not totalChunks
            or totalChunks <= 0
        then
            Upload.Running = false
            Flow.Mode = "idle"

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

        local fileName =
            string.format(
                "Cafeina_Teleport_%s_%s.json",

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
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Upload falhou • dados preservados"

            DetailLabel.Text =
                string.format(
                    "%.2f MB continuam arquivados",
                    mb(Archive.Bytes)
                )

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        Upload.UploadId =
            type(startData) == "table"
            and (
                startData.uploadId
                or startData.id
                or startData.upload_id
            )
            or nil

        if not Upload.UploadId then
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Resposta /start inválida • preservado"

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        local index = 0
        local failed = false

        local streamOk =
            streamUploadChunks(
                function(objects)
                    index += 1

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
                        failed = true
                        return false
                    end

                    local size =
                        #safeJson(
                            objects
                        )

                    Upload.ChunksSent += 1

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

        if
            not streamOk
            or failed
        then
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Erro no upload • dados preservados"

            DetailLabel.Text =
                string.format(
                    "%.2f MB continuam no archive",
                    mb(Archive.Bytes)
                )

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        if
            Upload.ChunksSent
                ~= Upload.TotalChunks
        then
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Chunks incompletos • preservado"

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

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
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Finalização falhou • preservado"

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        local confirmed = false

        if type(finishData) == "table" then
            if
                finishData.confirmed == true
                or finishData.success == true
                or finishData.ok == true
            then
                confirmed = true
            end
        end

        if not confirmed then
            Upload.Running = false
            Flow.Mode = "idle"

            StatusLabel.Text =
                "Servidor não confirmou • preservado"

            DetailLabel.Text =
                string.format(
                    "%.2f MB continuam arquivados",
                    mb(Archive.Bytes)
                )

            ActionButton.Text =
                "INICIAR TUDO"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        Upload.LastURL =
            type(finishData) == "table"
            and tostring(
                finishData.url
                or finishData.link
                or finishData.fileUrl
                or ""
            )
            or ""

        clearConfirmedArchive()

        Upload.Running = false
        Flow.Mode = "idle"

        ActionButton.Text =
            "INICIAR TUDO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        StatusLabel.Text =
            "Upload concluído"

        DetailLabel.Text =
            "Servidor confirmou • archive local limpo"

        setBar(1, true)

        task.delay(
            1.2,

            function()
                if
                    Flow.Mode == "idle"
                    and Archive.Records == 0
                then
                    updateUI(true)
                end
            end
        )
    end

--==============================================================--
-- SESSION RESET / START
--==============================================================--

local function resetTemporarySession()
    stopCharacterObservers()
    stopRemoteObservers()

    ActiveTest = nil

    Session.Running = false
    Session.TestsRunning = false

    Session.StopRequested = false
    Session.StopReason = nil

    Session.StartedAtClock = 0
    Session.StartedAtUnix = 0
    Session.RunId = nil

    Session.RecordCount = 0

    Session.CurrentTest = 0
    Session.CurrentDistance = 0

    Session.Accepted = 0
    Session.Corrections = 0
    Session.FailedTargets = 0
end

local function startEverything()
    if
        Session.Running
        or Upload.Running
        or Flow.FinalizerRunning
    then
        return
    end

    resetTemporarySession()

    Flow.Mode =
        "collecting"

    Session.Running = true

    Session.StartedAtClock =
        os.clock()

    Session.StartedAtUnix =
        os.time()

    Session.RunId =
        newRunId()

    Archive.Sessions += 1

    if not Archive.Persistent then
        env.__CAFEINA_TELEPORT_MEMORY.sessions =
            Archive.Sessions
    end

    ManifestState.dirty = true
    saveManifest(true)

    ActionButton.Text =
        "ENCERRAR"

    ActionButton.BackgroundColor3 =
        COLORS.RED

    acceptRecord({
        source =
            "teleport_session",

        kind =
            "session_started",

        mode =
            "progressive_teleport_tests",

        totalTests =
            Session.TotalTests,

        distances =
            CONFIG.TELEPORT_DISTANCES,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        placeVersion =
            game.PlaceVersion,

        userId =
            LocalPlayer.UserId,

        persistent =
            Archive.Persistent,

        executorRequestAvailable =
            REQUEST ~= nil,

        note =
            "client-visible telemetry only; no server-side bypass attempted",
    })

    task.spawn(function()
        local ok, err =
            pcall(
                runTeleportLab
            )

        if not ok then
            Session.TestsRunning = false

            acceptRecord({
                source =
                    "teleport_session",

                kind =
                    "lab_error",

                error =
                    tostring(err),
            })

            if requestStopAndUpload then
                requestStopAndUpload(
                    "lab_error"
                )
            end
        end
    end)

    updateUI(true)
end

--==============================================================--
-- STOP + AUTO UPLOAD
--==============================================================--

requestStopAndUpload =
    function(reason)
        if Flow.FinalizerRunning then
            return
        end

        if
            not Session.Running
            and not Session.TestsRunning
        then
            return
        end

        Flow.FinalizerRunning = true
        Flow.Mode = "finalizing"

        Session.StopRequested = true

        Session.StopReason =
            reason
            or "manual_stop"

        ActionButton.Text =
            "ENCERRANDO..."

        ActionButton.BackgroundColor3 =
            COLORS.RED_DARK

        acceptRecord({
            source =
                "teleport_session",

            kind =
                "stop_requested",

            reason =
                Session.StopReason,

            automaticUpload =
                true,
        })

        ManifestState.dirty = true
        saveManifest(true)

        updateUI(true)

        task.spawn(function()
            while Session.TestsRunning do
                updateUI()
                task.wait(0.05)
            end

            stopCharacterObservers()
            stopRemoteObservers()

            ActiveTest = nil

            acceptRecord({
                source =
                    "teleport_session",

                kind =
                    "session_finalized",

                reason =
                    Session.StopReason,

                records =
                    Session.RecordCount,

                archivedRecords =
                    Archive.Records,

                archivedBytes =
                    Archive.Bytes,

                completedTests =
                    Session.CurrentTest,

                accepted =
                    Session.Accepted,

                corrections =
                    Session.Corrections,

                failedTargets =
                    Session.FailedTargets,
            })

            ManifestState.dirty = true
            saveManifest(true)

            Session.Running = false

            Flow.FinalizerRunning = false

            if Archive.Records > 0 then
                Flow.Mode =
                    "uploading"

                ActionButton.Text =
                    "ENVIANDO..."

                ActionButton.BackgroundColor3 =
                    COLORS.RED_DARK

                updateUI(true)

                task.wait(0.10)

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
-- BUTTON
--==============================================================--

ActionButton.Activated:
    Connect(function()
        if Flow.Mode == "idle" then
            startEverything()
            return
        end

        if Flow.Mode == "collecting" then
            requestStopAndUpload(
                "manual_stop"
            )

            return
        end
    end)

--==============================================================--
-- CHARACTER RESPAWN TRACE
--==============================================================--

LocalPlayer.CharacterAdded:
    Connect(function(character)
        if
            Session.TestsRunning
            and ActiveTest
        then
            acceptRecord({
                source =
                    "teleport_character",

                kind =
                    "character_respawned_during_test",

                testId =
                    ActiveTest.id,

                requestedDistance =
                    ActiveTest.requestedDistance,

                newCharacter =
                    safePath(character),
            })
        end
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
            "%.2f MB • %d registros preservados",
            mb(Archive.Bytes),
            Archive.Records
        )
else
    updateUI(true)
end

--==============================================================--
-- READY
--==============================================================--

print(
    "[CAFEÍNA TELEPORT LAB] pronto • "
    .. tostring(
        Session.TotalTests
    )
    .. " testes • archive="
    .. CONFIG.ARCHIVE_FOLDER
)
