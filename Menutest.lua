--==============================================================--
-- CAFEÍNA • MAPPING V1.4
-- MAPPING ENGINE + TEST LAB + PERSISTENT ARCHIVE + UPLOADER
-- GAME-FOCUSED BUILD • MOBILE OPTIMIZED • CLIENT-VISIBLE ONLY
--
-- Focus discovered for this game:
-- ProfileMirror/ProfileDelta, SpeedPower, Money, Treadmill,
-- EggWorld/EggCapture, GearSatchel, GearTools, GuardPatrol,
-- Homestead, PenRoster, MonsterEvent/MonsterParasite, Storefront.
--
-- IMPORTANT:
-- • Passive Test Lab: does NOT FireServer/InvokeServer arbitrarily.
-- • Mobile build: prioritized observers, throttled UI/manifest, streaming upload.
-- • Stop never erases archived data.
-- • Archive is erased only after /upload/finish confirms success.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "MAPPING_V1_4",
    GUI_NAME = "CafeinaMappingV14",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 3200000,
    BLOCK_TARGET_BYTES = 1024 * 1024,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.25,

    ATTRIBUTE_POLL_SECONDS = 0.75,
    HEARTBEAT_EVERY_CYCLES = 8,

    MAX_TRACKED_VALUES = 3200,
    MAX_TRACKED_ATTRIBUTES = 1800,
    MAX_TRACKED_REMOTES = 420,
    MAX_DYNAMIC_EVENTS = 14000,

    CORRELATION_WINDOW_SECONDS = 0.20,

    -- Mobile/performance controls
    UI_UPDATE_INTERVAL = 0.18,
    MANIFEST_FLUSH_RECORDS = 40,
    MANIFEST_FLUSH_SECONDS = 1.75,
    SCAN_YIELD_EVERY = 140,
    ATTRIBUTE_YIELD_EVERY = 90,
    MEMORY_RECORD_CAP = 3200,

    ARCHIVE_FOLDER = "CafeinaArchive",
    MANIFEST_PATH = "CafeinaArchive/manifest.json",

    SERVICES = {
        {name="ReplicatedStorage", budget=42000},
        {name="ReplicatedFirst",   budget=8000},
        {name="StarterPlayer",     budget=19000},
        {name="StarterGui",        budget=18000},
        {name="Players",           budget=20000},
        {name="Lighting",          budget=4000},
        {name="Teams",             budget=2500},
        {name="SoundService",      budget=5000},
        {name="Workspace",         budget=36000},
    }
}

if IS_MOBILE then
    -- Keep the same archive limit and behavior, but reduce simultaneous live
    -- watchers to avoid frame drops on lower-memory Android devices.
    CONFIG.MAX_TRACKED_VALUES = 2400
    CONFIG.MAX_TRACKED_ATTRIBUTES = 1250
    CONFIG.MAX_TRACKED_REMOTES = 360
    CONFIG.SCAN_YIELD_EVERY = 90
    CONFIG.ATTRIBUTE_YIELD_EVERY = 60
    CONFIG.MEMORY_RECORD_CAP = 2200
end

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

-- Prevent duplicate optimized instances after re-executing the script.
pcall(function()
    local previous = rawget(env, "__CAFEINA_MAPPING_V14_CONTROLLER")
    if type(previous) == "table" and type(previous.Stop) == "function" then
        previous.Stop("replaced_by_new_instance")
    end
end)

local function pickFunction(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then
            return v
        end
    end
    return nil
end

local synRequest = nil
pcall(function()
    if syn and type(syn.request) == "function" then
        synRequest = syn.request
    end
end)

local httpTableRequest = nil
pcall(function()
    if http and type(http.request) == "function" then
        httpTableRequest = http.request
    end
end)

local REQUEST = pickFunction(
    rawget(env, "request"),
    rawget(env, "http_request"),
    httpTableRequest,
    synRequest
)

local WRITEFILE = pickFunction(rawget(env, "writefile"))
local READFILE = pickFunction(rawget(env, "readfile"))
local APPENDFILE = pickFunction(rawget(env, "appendfile"))
local ISFILE = pickFunction(rawget(env, "isfile"))
local DELFILE = pickFunction(rawget(env, "delfile"))
local MAKEFOLDER = pickFunction(rawget(env, "makefolder"))
local ISFOLDER = pickFunction(rawget(env, "isfolder"))

local FILESYSTEM_OK =
    WRITEFILE and READFILE and ISFILE and DELFILE and MAKEFOLDER

--==============================================================--
-- HELPERS
--==============================================================--

local function nowUnix()
    return os.time()
end

local function isoUTC()
    local t = os.date("!*t")
    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        t.year, t.month, t.day, t.hour, t.min, t.sec
    )
end

local function newRunId()
    local ok, guid = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    return ok and guid or tostring(nowUnix()) .. "_" .. tostring(math.random(100000,999999))
end

local function mb(bytes)
    return bytes / (1024 * 1024)
end

local function safePath(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    return ok and result or tostring(inst)
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function shallowEqual(a, b)
    local ok1, ja = pcall(HttpService.JSONEncode, HttpService, a)
    local ok2, jb = pcall(HttpService.JSONEncode, HttpService, b)
    return ok1 and ok2 and ja == jb
end

--==============================================================--
-- SAFE SERIALIZER
--==============================================================--

local function safeSerialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 4 then
        return "<max_depth>"
    end

    local tv = typeof(value)

    if value == nil then
        return nil
    elseif tv == "string" or tv == "boolean" then
        return value
    elseif tv == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    elseif tv == "Instance" then
        return {
            type = "Instance",
            path = safePath(value),
            className = value.ClassName,
        }
    elseif tv == "Vector3" then
        return {type="Vector3", x=value.X, y=value.Y, z=value.Z}
    elseif tv == "Vector2" then
        return {type="Vector2", x=value.X, y=value.Y}
    elseif tv == "Color3" then
        return {type="Color3", r=value.R, g=value.G, b=value.B}
    elseif tv == "CFrame" then
        local p = value.Position
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z}
    elseif tv == "table" then
        if seen[value] then
            return "<cycle>"
        end
        seen[value] = true

        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count += 1
            if count > 60 then
                out["<truncated>"] = true
                break
            end
            local key = tostring(k)
            out[key] = safeSerialize(v, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end

    return tostring(value)
end

local function safeAttributes(inst)
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)
    if not ok then return {} end
    return safeSerialize(attrs) or {}
end

local function safeJson(value)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    if ok then return result end
    return HttpService:JSONEncode({
        kind = "serialization_error",
        error = tostring(result)
    })
end

--==============================================================--
-- GAME-SPECIFIC RELEVANCE / CONTEXT
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
    -- high-value systems discovered in this game
    profilemirror=90, profiledelta=100, speedpower=95, money=80,
    treadmill=100, eggworld=100, eggcapture=100, egginventory=90,
    gearsatchel=95, geartools=85, shopitems=75,
    guardpatrol=85, guard=60, homestead=80, penroster=80,
    monsterevent=90, monsterparasite=90, storefront=85,
    trailwear=75, trials=70, payouts=65, mutation=65,
    batcontroller=85, ratelimiter=75, tokenbucket=75,

    -- generic high-value words
    remote=55, network=55, damage=45, bullet=40, hit=35,
    quest=40, dialogue=35, item=35, weapon=40, gun=40,
    ammo=35, inventory=45, equip=40, reload=40, combat=45,
    stamina=40, health=40, craft=35, scrap=35, artifact=35,
    loot=40, shop=40, npc=35, state=30, ending=30,
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

local function relevanceOf(inst)
    local path = string.lower(safePath(inst))
    local name = string.lower(inst.Name or "")
    local score = CLASS_SCORE[inst.ClassName] or 0

    for word, add in pairs(GAME_KEYWORDS) do
        if string.find(path, word, 1, true) or string.find(name, word, 1, true) then
            score += add
        end
    end

    local original = safePath(inst)
    for _, critical in ipairs(CRITICAL_PATHS) do
        if string.find(original, critical, 1, true) then
            score += 70
        end
    end

    return score
end

local function classifyContext(path)
    local s = string.lower(path or "")

    local function has(...)
        for i = 1, select("#", ...) do
            local w = select(i, ...)
            if string.find(s, w, 1, true) then
                return true
            end
        end
        return false
    end

    if has("damage","blood","limbhealth","parry","ammo","combat","weapon","gun","batcontroller") then
        return "COMBAT"
    elseif has("guard","monster","npc","chain") then
        return "NPC"
    elseif has("party","penroster","owner") then
        return "PARTY"
    elseif has("craft","workbench","deconstruct","mutation") then
        return "CRAFTING"
    elseif has("inventory","saveditems",".items","gearsatchel","egginventory","backpack","gear") then
        return "INVENTORY"
    elseif has("quest","objective","dialogue","trials") then
        return "QUEST"
    elseif has("zone","area","homestead","field") then
        return "ZONE"
    elseif has("characterhandler","charactermobility","stamina","humanoid","leaderstats","speedpower") then
        return "CHARACTER"
    elseif has("playergui","startergui","gui","button","frame","label") then
        return "UI"
    else
        return "WORLD"
    end
end

--==============================================================--
-- SESSION / REPORT / UPLOAD
--==============================================================--

local Session = {
    Running = false,
    ScanRunning = false,
    TestsRunning = false,
    ObserversRunning = false,

    StopRequested = false,
    StopReason = nil,
    Finalized = false,

    StartedAtClock = 0,
    StartedAtUnix = 0,
    RunId = nil,

    EstimatedBytes = 2,
    RecordCount = 0,
    ObjectsScanned = 0,

    ServicesDone = 0,
    ServicesTotal = #CONFIG.SERVICES,
    CurrentService = "",

    VisualStatsCleared = false,
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

local Report = {
    meta = {},
    records = {},
    diagnostics = {
        errors = {},
        counters = {
            total = 0,
            scan = 0,
            tests = 0,
            diagnostic = 0,
            session = 0,
        }
    }
}

local Archive = {
    Persistent = FILESYSTEM_OK and true or false,
    Blocks = {},
    CurrentBlock = 1,
    CurrentBlockBytes = 0,
    Bytes = 0,
    Records = 0,
    Sessions = 0,
    Uploaded = false,
    MemoryLines = {},
}

local ObserverConnections = {}
local TrackedValues = {}
local TrackedAttributes = {}
local TrackedValueSet = setmetatable({}, {__mode="k"})
local TrackedAttributeSet = setmetatable({}, {__mode="k"})
local ObservedRemoteSet = setmetatable({}, {__mode="k"})
local DynamicSignatures = {}
local RemoteAggregates = {}
local DynamicEvents = 0
local ObservedRemoteCount = 0

local ManifestState = {
    dirty = false,
    recordsSinceSave = 0,
    lastSaveClock = 0,
}

local UIState = {
    lastUpdateClock = 0,
}

local function relativeTime()
    if Session.StartedAtClock == 0 then return 0 end
    return os.clock() - Session.StartedAtClock
end

local function correlationWindow()
    return math.floor(relativeTime() / CONFIG.CORRELATION_WINDOW_SECONDS)
end

--==============================================================--
-- ARCHIVE
--==============================================================--

local function blockPath(index)
    return string.format("%s/block_%06d.jsonl", CONFIG.ARCHIVE_FOLDER, index)
end

local function ensureArchiveFolder()
    if not FILESYSTEM_OK then return false end
    local ok = pcall(function()
        if not ISFOLDER or not ISFOLDER(CONFIG.ARCHIVE_FOLDER) then
            MAKEFOLDER(CONFIG.ARCHIVE_FOLDER)
        end
    end)
    return ok
end

local function saveManifest(force)
    if not FILESYSTEM_OK then return end

    local now = os.clock()
    if not force then
        if not ManifestState.dirty then return end
        if ManifestState.recordsSinceSave < CONFIG.MANIFEST_FLUSH_RECORDS
            and (now - ManifestState.lastSaveClock) < CONFIG.MANIFEST_FLUSH_SECONDS then
            return
        end
    end

    ensureArchiveFolder()

    local manifest = {
        schema = 1,
        scanner = CONFIG.VERSION,
        build = "MOBILE_OPT_1",
        placeId = game.PlaceId,
        gameId = game.GameId,
        blocks = Archive.Blocks,
        currentBlock = Archive.CurrentBlock,
        bytes = Archive.Bytes,
        records = Archive.Records,
        sessions = Archive.Sessions,
        uploaded = Archive.Uploaded,
        persistent = true,
    }

    local ok = pcall(function()
        WRITEFILE(CONFIG.MANIFEST_PATH, safeJson(manifest))
    end)

    if ok then
        ManifestState.dirty = false
        ManifestState.recordsSinceSave = 0
        ManifestState.lastSaveClock = now
    end
end

local function rebuildArchiveCounters()
    if not FILESYSTEM_OK then return end

    local totalBytes = 0
    local totalRecords = 0
    local currentBytes = 0

    for _, path in ipairs(Archive.Blocks) do
        if ISFILE(path) then
            local ok, text = pcall(READFILE, path)
            if ok and type(text) == "string" then
                totalBytes += #text
                local _, lines = string.gsub(text, "\n", "\n")
                if #text > 0 and string.sub(text, -1) ~= "\n" then
                    lines += 1
                end
                totalRecords += lines

                if path == blockPath(Archive.CurrentBlock) then
                    currentBytes = #text
                end
            end
        end
    end

    Archive.Bytes = totalBytes
    Archive.Records = totalRecords
    Archive.CurrentBlockBytes = currentBytes
end

local function loadArchive()
    if not FILESYSTEM_OK then
        Archive.Persistent = false

        -- Same-executor fallback: survives menu/script re-execution while the
        -- executor environment itself remains alive. It cannot survive a full
        -- app/process termination without filesystem support.
        local shared = rawget(env, "__CAFEINA_MAPPING_V14_MEMORY_ARCHIVE")
        if type(shared) == "table" and type(shared.lines) == "table" then
            Archive.MemoryLines = shared.lines
            Archive.Sessions = tonumber(shared.sessions) or 0
            Archive.Bytes = 0
            Archive.Records = 0
            for _, line in ipairs(Archive.MemoryLines) do
                Archive.Bytes += #line + 1
                Archive.Records += 1
            end
        else
            env.__CAFEINA_MAPPING_V14_MEMORY_ARCHIVE = {
                lines = Archive.MemoryLines,
                sessions = Archive.Sessions,
            }
        end
        return
    end

    ensureArchiveFolder()

    if ISFILE(CONFIG.MANIFEST_PATH) then
        local ok, raw = pcall(READFILE, CONFIG.MANIFEST_PATH)
        if ok and raw then
            local decOk, manifest = pcall(HttpService.JSONDecode, HttpService, raw)
            if decOk and type(manifest) == "table" then
                Archive.Blocks = manifest.blocks or {}
                Archive.CurrentBlock = tonumber(manifest.currentBlock) or math.max(#Archive.Blocks, 1)
                Archive.Sessions = tonumber(manifest.sessions) or 0
                Archive.Uploaded = manifest.uploaded == true
            end
        end
    end

    if #Archive.Blocks == 0 then
        Archive.CurrentBlock = 1
        Archive.Blocks = {blockPath(1)}
    end

    rebuildArchiveCounters()
    ManifestState.dirty = true
    saveManifest(true)
end

local function appendLine(path, line)
    if APPENDFILE then
        return pcall(APPENDFILE, path, line)
    end

    local previous = ""
    if ISFILE(path) then
        local ok, data = pcall(READFILE, path)
        if ok and type(data) == "string" then
            previous = data
        end
    end
    return pcall(WRITEFILE, path, previous .. line)
end

local function archiveJsonLine(jsonLine)
    local bytes = #jsonLine + 1

    if Archive.Bytes + bytes > CONFIG.MAX_ARCHIVE_BYTES then
        Session.StopRequested = true
        Session.StopReason = "size_limit"
        return false, "size_limit"
    end

    if Archive.Persistent then
        ensureArchiveFolder()

        if Archive.CurrentBlockBytes > 0
            and Archive.CurrentBlockBytes + bytes > CONFIG.BLOCK_TARGET_BYTES then

            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0
            local newPath = blockPath(Archive.CurrentBlock)
            table.insert(Archive.Blocks, newPath)
            ManifestState.dirty = true
            saveManifest(true)
        end

        local path = blockPath(Archive.CurrentBlock)
        if Archive.Blocks[#Archive.Blocks] ~= path then
            table.insert(Archive.Blocks, path)
        end

        local ok, err = appendLine(path, jsonLine .. "\n")
        if not ok then
            return false, tostring(err)
        end

        Archive.CurrentBlockBytes += bytes
    else
        table.insert(Archive.MemoryLines, jsonLine)
    end

    Archive.Bytes += bytes
    Archive.Records += 1
    ManifestState.dirty = true
    ManifestState.recordsSinceSave += 1
    saveManifest(false)

    return true
end

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG = Color3.fromRGB(14,14,17),
    PANEL = Color3.fromRGB(22,22,27),
    PANEL2 = Color3.fromRGB(31,31,38),

    RED = Color3.fromRGB(225,42,55),
    RED_DARK = Color3.fromRGB(120,24,33),

    TEXT = Color3.fromRGB(245,245,248),
    SUB = Color3.fromRGB(170,170,180),

    GREEN = Color3.fromRGB(65,205,115),
    YELLOW = Color3.fromRGB(235,180,55),
    ORANGE = Color3.fromRGB(245,130,55),
}

local uiParent = nil
pcall(function()
    if type(gethui) == "function" then
        uiParent = gethui()
    end
end)
if not uiParent then uiParent = CoreGui end
if not uiParent then uiParent = LocalPlayer:WaitForChild("PlayerGui") end

pcall(function()
    local old = uiParent:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = uiParent

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(372,574)
Main.AnchorPoint = Vector2.new(0.5,0.5)
Main.Position = UDim2.fromScale(0.5,0.5)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,14)

local MainScale = Instance.new("UIScale")
MainScale.Scale = 1
MainScale.Parent = Main

local function refreshMobileScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    local sx = math.min(1, math.max(0.78, (vp.X - 18) / 372))
    local sy = math.min(1, math.max(0.78, (vp.Y - 26) / 574))
    MainScale.Scale = math.min(sx, sy)
end

refreshMobileScale()
pcall(function()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        task.defer(refreshMobileScale)
    end)
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshMobileScale)
    end
end)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1,0,0,56)
Header.BackgroundColor3 = COLORS.PANEL
Header.BorderSizePixel = 0
Header.Parent = Main
Instance.new("UICorner", Header).CornerRadius = UDim.new(0,14)

local HeaderMask = Instance.new("Frame")
HeaderMask.Size = UDim2.new(1,0,0,16)
HeaderMask.Position = UDim2.new(0,0,1,-16)
HeaderMask.BackgroundColor3 = COLORS.PANEL
HeaderMask.BorderSizePixel = 0
HeaderMask.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(14,7)
Title.Size = UDim2.new(1,-70,0,21)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextColor3 = COLORS.TEXT
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "CAFEÍNA • MAPPING V1.4"
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(14,29)
Subtitle.Size = UDim2.new(1,-70,0,14)
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 9
Subtitle.TextColor3 = COLORS.SUB
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Text = "SCAN + TEST LAB • CLIENT-VISIBLE • 150 MB"
Subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Position = UDim2.new(1,-42,0,10)
Minimize.Size = UDim2.fromOffset(30,30)
Minimize.BackgroundColor3 = COLORS.PANEL2
Minimize.BorderSizePixel = 0
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 17
Minimize.TextColor3 = COLORS.TEXT
Minimize.Text = "—"
Minimize.Parent = Header
Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0,8)

local function makeButton(text, x, y, width, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(width,42)
    b.Position = UDim2.fromOffset(x,y)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = COLORS.TEXT
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = Main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local ScanButton = makeButton("INICIAR SCAN",12,68,170,COLORS.RED)
local TestButton = makeButton("INICIAR TESTES",190,68,170,COLORS.RED_DARK)
local UploadButton = makeButton("ENVIAR TUDO",12,118,170,COLORS.RED_DARK)
local StopButton = makeButton("PARAR TUDO",190,118,170,Color3.fromRGB(95,26,32))

local function makePanel(y, titleText)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1,-24,0,118)
    p.Position = UDim2.fromOffset(12,y)
    p.BackgroundColor3 = COLORS.PANEL
    p.BorderSizePixel = 0
    p.Parent = Main
    Instance.new("UICorner", p).CornerRadius = UDim.new(0,10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12,9)
    title.Size = UDim2.new(1,-24,0,16)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 10
    title.TextColor3 = COLORS.SUB
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = titleText
    title.Parent = p

    local status = Instance.new("TextLabel")
    status.BackgroundTransparency = 1
    status.Position = UDim2.fromOffset(12,28)
    status.Size = UDim2.new(1,-24,0,19)
    status.Font = Enum.Font.GothamBold
    status.TextSize = 12
    status.TextColor3 = COLORS.TEXT
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Text = "Pronto"
    status.Parent = p

    local d1 = Instance.new("TextLabel")
    d1.BackgroundTransparency = 1
    d1.Position = UDim2.fromOffset(12,51)
    d1.Size = UDim2.new(1,-24,0,16)
    d1.Font = Enum.Font.Gotham
    d1.TextSize = 9
    d1.TextColor3 = COLORS.SUB
    d1.TextXAlignment = Enum.TextXAlignment.Left
    d1.Text = "-"
    d1.Parent = p

    local d2 = Instance.new("TextLabel")
    d2.BackgroundTransparency = 1
    d2.Position = UDim2.fromOffset(12,69)
    d2.Size = UDim2.new(1,-24,0,16)
    d2.Font = Enum.Font.Gotham
    d2.TextSize = 9
    d2.TextColor3 = COLORS.SUB
    d2.TextXAlignment = Enum.TextXAlignment.Left
    d2.Text = "-"
    d2.Parent = p

    local bar = Instance.new("Frame")
    bar.Position = UDim2.new(0,12,1,-19)
    bar.Size = UDim2.new(1,-24,0,7)
    bar.BackgroundColor3 = COLORS.PANEL2
    bar.BorderSizePixel = 0
    bar.Parent = p
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0,1)
    fill.BackgroundColor3 = COLORS.RED
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)

    return {frame=p,title=title,status=status,d1=d1,d2=d2,bar=bar,fill=fill}
end

local CollectionPanel = makePanel(172,"COLETA ATUAL")
local ArchivePanel = makePanel(298,"ARQUIVADO / PRESERVADO")
local UploadPanel = makePanel(424,"ENVIO AO SITE")

local LinkLabel = Instance.new("TextLabel")
LinkLabel.Position = UDim2.fromOffset(12,548)
LinkLabel.Size = UDim2.new(1,-24,0,16)
LinkLabel.BackgroundTransparency = 1
LinkLabel.Font = Enum.Font.Code
LinkLabel.TextSize = 8
LinkLabel.TextColor3 = COLORS.SUB
LinkLabel.TextXAlignment = Enum.TextXAlignment.Left
LinkLabel.TextTruncate = Enum.TextTruncate.AtEnd
LinkLabel.Text = "Link: nenhum upload concluído"
LinkLabel.Parent = Main

local MiniButton = Instance.new("TextButton")
MiniButton.Size = UDim2.fromOffset(54,54)
MiniButton.AnchorPoint = Vector2.new(0.5,0.5)
MiniButton.Position = UDim2.fromScale(0.5,0.5)
MiniButton.BackgroundColor3 = COLORS.RED
MiniButton.BorderSizePixel = 0
MiniButton.Font = Enum.Font.GothamBlack
MiniButton.TextSize = 20
MiniButton.TextColor3 = COLORS.TEXT
MiniButton.Text = "C"
MiniButton.Visible = false
MiniButton.Parent = Gui
Instance.new("UICorner", MiniButton).CornerRadius = UDim.new(1,0)

local function tweenBar(fill, ratio)
    ratio = clamp01(ratio)
    pcall(function()
        TweenService:Create(
            fill,
            TweenInfo.new(0.12),
            {Size=UDim2.fromScale(ratio,1)}
        ):Play()
    end)
end

local function updateUI(force)
    local now = os.clock()
    if not force and (now - UIState.lastUpdateClock) < CONFIG.UI_UPDATE_INTERVAL then
        return
    end
    UIState.lastUpdateClock = now

    local testCount = Report.diagnostics.counters.tests or 0

    CollectionPanel.d1.Text = string.format(
        "%d registros nesta sessão • %.2f MB",
        Session.RecordCount,
        mb(Session.EstimatedBytes)
    )
    CollectionPanel.d2.Text = string.format(
        "%d objetos • %d/%d serviços • T:%d",
        Session.ObjectsScanned,
        Session.ServicesDone,
        Session.ServicesTotal,
        testCount
    )
    tweenBar(CollectionPanel.fill, Session.EstimatedBytes / CONFIG.MAX_ARCHIVE_BYTES)

    ArchivePanel.status.Text =
        Archive.Persistent and "Persistência local ativa"
        or "Modo memória • persistência local indisponível"

    ArchivePanel.d1.Text = string.format(
        "%d registros • %.2f MB / 150 MB",
        Archive.Records,
        mb(Archive.Bytes)
    )
    ArchivePanel.d2.Text = string.format(
        "%d blocos • dados preservados até upload confirmado",
        Archive.Persistent and #Archive.Blocks or 1
    )
    tweenBar(ArchivePanel.fill, Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES)

    UploadPanel.d1.Text = string.format(
        "%d/%d chunks • %.2f MB / %.2f MB",
        Upload.ChunksSent,
        Upload.TotalChunks,
        mb(Upload.BytesSent),
        mb(Upload.TotalBytes)
    )
    UploadPanel.d2.Text =
        Upload.UploadId and ("uploadId: " .. tostring(Upload.UploadId))
        or "Aguardando envio"

    local ratio = 0
    if Upload.TotalBytes > 0 then
        ratio = Upload.BytesSent / Upload.TotalBytes
    end
    tweenBar(UploadPanel.fill, ratio)
end

--==============================================================--
-- DRAGGING
--==============================================================--

local function makeDraggable(handle, target, clickCallback)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local moved = false
    local activeInput = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            activeInput = input
            dragStart = input.Position
            startPos = target.Position
            moved = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        if delta.Magnitude > 6 then moved = true end

        local scale = 1
        if target == Main and MainScale then
            scale = math.max(MainScale.Scale, 0.01)
        end

        target.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + (delta.X / scale),
            startPos.Y.Scale,
            startPos.Y.Offset + (delta.Y / scale)
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if dragging and (
            input == activeInput
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            dragging = false
            activeInput = nil
            if not moved and clickCallback then
                clickCallback()
            end
        end
    end)
end

makeDraggable(Header, Main)

Minimize.MouseButton1Click:Connect(function()
    Main.Visible = false
    MiniButton.Visible = true
end)

makeDraggable(MiniButton, MiniButton, function()
    MiniButton.Visible = false
    Main.Visible = true
end)

--==============================================================--
-- RECORD ACCEPTANCE
--==============================================================--

local function pushError(where, err)
    local item = {
        source = "diagnostic",
        kind = "error",
        time = relativeTime(),
        context = "WORLD",
        correlationWindow = correlationWindow(),
        runId = Session.RunId,
        where = tostring(where),
        error = tostring(err),
    }
    table.insert(Report.diagnostics.errors, item)
end

local function acceptRecord(record)
    if Session.StopRequested and Session.StopReason == "size_limit" then
        return false
    end

    record.source = record.source or "scan"
    record.kind = record.kind or "unknown"
    record.time = record.time or relativeTime()
    record.context = record.context or classifyContext(record.path or record.name or "")
    record.correlationWindow = record.correlationWindow or correlationWindow()
    record.runId = record.runId or Session.RunId

    local json = safeJson(record)
    local ok, why = archiveJsonLine(json)
    if not ok then
        if why ~= "size_limit" then
            pushError("archive", why)
        end
        return false
    end

    Session.RecordCount += 1
    Session.EstimatedBytes += #json + 1

    -- Keep only a rolling in-memory cache on mobile; the full dataset is already
    -- durably archived before this point and upload reads from Archive, not RAM.
    table.insert(Report.records, record)
    if #Report.records > CONFIG.MEMORY_RECORD_CAP then
        table.remove(Report.records, 1)
    end

    local c = Report.diagnostics.counters
    c.total += 1
    c[record.source] = (c[record.source] or 0) + 1

    if c.total % 30 == 0 then updateUI() end
    return true
end

--==============================================================--
-- INSTANCE RECORD BUILDER
--==============================================================--

local function shouldSkipStatic(inst)
    if inst:IsA("Pose") or inst:IsA("Keyframe") then
        return true
    end

    if inst:IsA("IntValue") then
        local rel = relevanceOf(inst)
        if rel < 35 then return true end
    end

    return false
end

local function buildInstanceRecord(inst, source)
    local path = safePath(inst)
    local rec = {
        source = source or "scan",
        kind = "object",
        service = nil,
        name = inst.Name,
        className = inst.ClassName,
        path = path,
        parentPath = inst.Parent and safePath(inst.Parent) or "",
        relevance = relevanceOf(inst),
        attributes = safeAttributes(inst),
        childCount = #inst:GetChildren(),
        context = classifyContext(path),
    }

    local p = inst
    while p and p.Parent do
        if p.Parent == game then
            rec.service = p.Name
            break
        end
        p = p.Parent
    end

    if inst:IsA("ValueBase") then
        local ok, v = pcall(function() return inst.Value end)
        if ok then rec.value = safeSerialize(v) end
    end

    if inst:IsA("ObjectValue") then
        local ok, v = pcall(function() return inst.Value end)
        if ok and v then
            rec.targetPath = safePath(v)
            rec.targetClass = v.ClassName
        end
    end

    if inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent") then
        rec.remote = {
            type = inst.ClassName,
            path = path,
        }
    end

    if inst:IsA("LuaSourceContainer") then
        rec.script = {
            type = inst.ClassName,
            path = path,
        }
    end

    if inst:IsA("Tool") then
        local ok1, rh = pcall(function() return inst.RequiresHandle end)
        local ok2, cd = pcall(function() return inst.CanBeDropped end)
        if ok1 then rec.requiresHandle = rh end
        if ok2 then rec.canBeDropped = cd end
    end

    if inst:IsA("ProximityPrompt") then
        local ok = pcall(function()
            rec.actionText = inst.ActionText
            rec.objectText = inst.ObjectText
            rec.holdDuration = inst.HoldDuration
            rec.maxActivationDistance = inst.MaxActivationDistance
        end)
    end

    if inst:IsA("Humanoid") then
        pcall(function()
            rec.health = inst.Health
            rec.maxHealth = inst.MaxHealth
            rec.walkSpeed = inst.WalkSpeed
            rec.jumpPower = inst.JumpPower
        end)
    end

    return rec
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

local function runMappingEngine()
    Session.ScanRunning = true
    local classCounters = {}

    acceptRecord({
        source="session",
        kind="mapping_started",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
    })

    for serviceIndex, item in ipairs(CONFIG.SERVICES) do
        if Session.StopRequested then break end

        local okService, service = pcall(function()
            return game:GetService(item.name)
        end)

        if okService and service then
            Session.CurrentService = item.name
            CollectionPanel.status.Text = "Scan • " .. item.name
            updateUI()

            local descendants = {}
            local okDesc, errDesc = pcall(function()
                descendants = service:GetDescendants()
            end)

            if okDesc then
                local candidates = {}

                for scanIndex, inst in ipairs(descendants) do
                    if Session.StopRequested then break end
                    if not shouldSkipStatic(inst) then
                        local limit = STATIC_CLASS_LIMITS[inst.ClassName]
                        if limit then
                            classCounters[inst.ClassName] = classCounters[inst.ClassName] or 0
                            if classCounters[inst.ClassName] >= limit then
                                continue
                            end
                        end

                        table.insert(candidates, {
                            inst = inst,
                            score = relevanceOf(inst)
                        })
                    end

                    if scanIndex % CONFIG.SCAN_YIELD_EVERY == 0 then
                        task.wait()
                    end
                end

                table.sort(candidates, function(a,b)
                    return a.score > b.score
                end)

                local count = 0
                for _, candidate in ipairs(candidates) do
                    if Session.StopRequested then break end
                    if count >= item.budget then break end

                    local inst = candidate.inst
                    if inst and inst.Parent then
                        local limit = STATIC_CLASS_LIMITS[inst.ClassName]
                        if limit then
                            classCounters[inst.ClassName] += 1
                        end

                        local okBuild, rec = pcall(buildInstanceRecord, inst, "scan")
                        if okBuild and rec then
                            acceptRecord(rec)
                            Session.ObjectsScanned += 1
                            count += 1
                        end
                    end

                    if count % CONFIG.SCAN_YIELD_EVERY == 0 then
                        task.wait()
                    end
                end
            else
                pushError("mapping:" .. item.name, errDesc)
            end

            Session.ServicesDone = serviceIndex
            updateUI()
        end
    end

    Session.ScanRunning = false

    acceptRecord({
        source="session",
        kind="mapping_finished",
        objectsScanned=Session.ObjectsScanned,
        servicesDone=Session.ServicesDone,
        stopped=Session.StopRequested,
        stopReason=Session.StopReason,
    })

    if not Session.TestsRunning then
        Session.Running = false
        CollectionPanel.status.Text =
            Session.StopRequested and ("Coleta finalizada • " .. tostring(Session.StopReason))
            or "Coleta finalizada • scan_completed"
    end

    updateUI()
end

--==============================================================--
-- TEST LAB
--==============================================================--

local function isRelevantDynamic(inst)
    if not inst then return false end

    if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
        return true
    end

    if inst:IsA("ValueBase") then
        return relevanceOf(inst) >= 35
    end

    local attrs = safeAttributes(inst)
    if next(attrs) ~= nil and relevanceOf(inst) >= 30 then
        return true
    end

    return relevanceOf(inst) >= 70
end

local NOISY_REMOTE_WORDS = {
    "npclook",
    "look",
    "armclient",
    "tweencommunication",
}

local function isNoisyRemote(path)
    local s = string.lower(path)
    for _, word in ipairs(NOISY_REMOTE_WORDS) do
        if string.find(s, word, 1, true) then return true end
    end
    return false
end

local function recordDynamic(rec)
    if DynamicEvents >= CONFIG.MAX_DYNAMIC_EVENTS then
        return false
    end
    DynamicEvents += 1
    return acceptRecord(rec)
end

local function observeRemote(remote)
    if not remote:IsA("RemoteEvent") and not remote:IsA("UnreliableRemoteEvent") then
        return
    end
    if ObservedRemoteSet[remote] then return end
    if ObservedRemoteCount >= CONFIG.MAX_TRACKED_REMOTES then return end

    ObservedRemoteSet[remote] = true
    ObservedRemoteCount += 1

    local path = safePath(remote)

    local ok, conn = pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            if not Session.TestsRunning or Session.StopRequested then return end

            local args = {...}

            if isNoisyRemote(path) then
                local agg = RemoteAggregates[path]
                if not agg then
                    agg = {
                        count=0,
                        firstTime=relativeTime(),
                        lastTime=relativeTime(),
                        samples={}
                    }
                    RemoteAggregates[path] = agg
                end

                agg.count += 1
                agg.lastTime = relativeTime()

                if #agg.samples < 8 then
                    table.insert(agg.samples, safeSerialize(args))
                end

                if agg.count == 1 or agg.count % 100 == 0 then
                    recordDynamic({
                        source="tests",
                        kind="remote_aggregate",
                        path=path,
                        className=remote.ClassName,
                        relevance=relevanceOf(remote),
                        count=agg.count,
                        firstTime=agg.firstTime,
                        lastTime=agg.lastTime,
                        samples=agg.samples,
                    })
                end
                return
            end

            recordDynamic({
                source="tests",
                kind="remote_received",
                path=path,
                className=remote.ClassName,
                relevance=relevanceOf(remote),
                argc=#args,
                args=safeSerialize(args),
            })
        end)
    end)

    if ok and conn then
        table.insert(ObserverConnections, conn)
    end
end

local function addTrackedValue(inst)
    if #TrackedValues >= CONFIG.MAX_TRACKED_VALUES then return end
    if TrackedValueSet[inst] then return end
    if not inst:IsA("ValueBase") then return end
    if relevanceOf(inst) < 35 then return end

    local ok, current = pcall(function() return inst.Value end)
    if not ok then return end

    local entry = {
        inst=inst,
        value=safeSerialize(current),
    }
    TrackedValueSet[inst] = true
    table.insert(TrackedValues, entry)

    local conn = inst.Changed:Connect(function()
        if not Session.TestsRunning or Session.StopRequested then return end
        if not inst.Parent then return end

        local ok2, newRaw = pcall(function() return inst.Value end)
        if not ok2 then return end

        local newValue = safeSerialize(newRaw)
        if not shallowEqual(entry.value, newValue) then
            local before = entry.value
            entry.value = newValue
            recordDynamic({
                source="tests",
                kind="value_changed",
                path=safePath(inst),
                className=inst.ClassName,
                before=before,
                after=newValue,
                relevance=relevanceOf(inst),
            })
        end
    end)

    table.insert(ObserverConnections, conn)
end

local function addTrackedAttributes(inst)
    if #TrackedAttributes >= CONFIG.MAX_TRACKED_ATTRIBUTES then return end
    if TrackedAttributeSet[inst] then return end
    if relevanceOf(inst) < 30 then return end
    local attrs = safeAttributes(inst)
    if next(attrs) == nil then return end

    TrackedAttributeSet[inst] = true
    table.insert(TrackedAttributes, {
        inst=inst,
        attrs=attrs,
    })
end

local function dynamicSignature(inst)
    local parentName = inst.Parent and inst.Parent.Name or ""
    return table.concat({inst.ClassName, inst.Name, parentName}, "|")
end

local function observeRoot(root)
    local descendants = root:GetDescendants()
    local valueCandidates = {}
    local attrCandidates = {}
    local remoteCandidates = {}

    for i, inst in ipairs(descendants) do
        if Session.StopRequested then break end

        local rel = relevanceOf(inst)

        if inst:IsA("ValueBase") and rel >= 35 and not TrackedValueSet[inst] then
            table.insert(valueCandidates, {inst=inst, score=rel})
        end

        if rel >= 30 and not TrackedAttributeSet[inst] then
            -- Do not call GetAttributes on every low-value object.
            local ok, attrs = pcall(function() return inst:GetAttributes() end)
            if ok and next(attrs) ~= nil then
                table.insert(attrCandidates, {inst=inst, score=rel, attrs=attrs})
            end
        end

        if (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent"))
            and rel >= 35 and not ObservedRemoteSet[inst] then
            table.insert(remoteCandidates, {inst=inst, score=rel})
        end

        if i % CONFIG.SCAN_YIELD_EVERY == 0 then
            task.wait()
        end
    end

    table.sort(valueCandidates, function(a,b) return a.score > b.score end)
    table.sort(attrCandidates, function(a,b) return a.score > b.score end)
    table.sort(remoteCandidates, function(a,b) return a.score > b.score end)

    for _, item in ipairs(valueCandidates) do
        if #TrackedValues >= CONFIG.MAX_TRACKED_VALUES then break end
        addTrackedValue(item.inst)
    end

    for _, item in ipairs(attrCandidates) do
        if #TrackedAttributes >= CONFIG.MAX_TRACKED_ATTRIBUTES then break end
        addTrackedAttributes(item.inst)
    end

    for _, item in ipairs(remoteCandidates) do
        if ObservedRemoteCount >= CONFIG.MAX_TRACKED_REMOTES then break end
        observeRemote(item.inst)
    end

    local addConn = root.DescendantAdded:Connect(function(inst)
        if not Session.TestsRunning or Session.StopRequested then return end
        if not isRelevantDynamic(inst) then return end

        local sig = dynamicSignature(inst)
        local n = (DynamicSignatures[sig] or 0) + 1
        DynamicSignatures[sig] = n

        if n <= 3 or n % 25 == 0 then
            recordDynamic({
                source="tests",
                kind="object_created",
                path=safePath(inst),
                className=inst.ClassName,
                name=inst.Name,
                signature=sig,
                occurrence=n,
                relevance=relevanceOf(inst),
            })
        end

        if inst:IsA("ValueBase") then
            addTrackedValue(inst)
        end

        addTrackedAttributes(inst)

        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
            observeRemote(inst)
        end
    end)

    local remConn = root.DescendantRemoving:Connect(function(inst)
        if not Session.TestsRunning or Session.StopRequested then return end
        if not isRelevantDynamic(inst) then return end

        recordDynamic({
            source="tests",
            kind="object_removed",
            path=safePath(inst),
            className=inst.ClassName,
            name=inst.Name,
            relevance=relevanceOf(inst),
        })
    end)

    table.insert(ObserverConnections, addConn)
    table.insert(ObserverConnections, remConn)
end

local function stopObservers()
    Session.ObserversRunning = false

    for _, conn in ipairs(ObserverConnections) do
        pcall(function() conn:Disconnect() end)
    end

    table.clear(ObserverConnections)
end

local function runTestLab()
    Session.TestsRunning = true
    Session.ObserversRunning = true

    acceptRecord({
        source="session",
        kind="test_lab_started",
        passive=true,
        roots={"ReplicatedStorage","Players","Workspace"},
    })

    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
        game:GetService("Workspace"),
    }

    for _, root in ipairs(roots) do
        if Session.StopRequested then break end
        pcall(observeRoot, root)
        task.wait()
    end

    acceptRecord({
        source="session",
        kind="watch_set_ready",
        trackedValues=#TrackedValues,
        trackedAttributes=#TrackedAttributes,
    })

    acceptRecord({
        source="session",
        kind="dynamic_observers_started",
    })

    CollectionPanel.status.Text =
        Session.ScanRunning and ("Scan + TestLab • " .. (Session.CurrentService ~= "" and Session.CurrentService or "iniciando"))
        or "TestLab ativo"

    local cycle = 0

    while Session.TestsRunning and not Session.StopRequested do
        cycle += 1

        for attrIndex, entry in ipairs(TrackedAttributes) do
            if Session.StopRequested then break end

            local inst = entry.inst
            if inst and inst.Parent then
                local attrs = safeAttributes(inst)
                if not shallowEqual(entry.attrs, attrs) then
                    local before = entry.attrs
                    entry.attrs = attrs

                    recordDynamic({
                        source="tests",
                        kind="attributes_changed",
                        path=safePath(inst),
                        before=before,
                        after=attrs,
                        relevance=relevanceOf(inst),
                    })
                end
            end

            if attrIndex % CONFIG.ATTRIBUTE_YIELD_EVERY == 0 then
                task.wait()
            end
        end

        if cycle % CONFIG.HEARTBEAT_EVERY_CYCLES == 0 then
            recordDynamic({
                source="tests",
                kind="observation_heartbeat",
                cycle=cycle,
                dynamicEvents=DynamicEvents,
            })
        end

        updateUI()
        task.wait(CONFIG.ATTRIBUTE_POLL_SECONDS)
    end

    stopObservers()
    Session.TestsRunning = false

    acceptRecord({
        source="session",
        kind="test_lab_finished",
        cycle=cycle,
        dynamicEvents=DynamicEvents,
        stopReason=Session.StopReason,
    })

    if not Session.ScanRunning then
        Session.Running = false
    end

    updateUI()
end

--==============================================================--
-- SESSION CONTROL
--==============================================================--

local function resetTemporarySession()
    Report.meta = {}
    Report.records = {}
    Report.diagnostics = {
        errors={},
        counters={
            total=0,
            scan=0,
            tests=0,
            diagnostic=0,
            session=0,
        }
    }

    table.clear(TrackedValues)
    table.clear(TrackedAttributes)
    TrackedValueSet = setmetatable({}, {__mode="k"})
    TrackedAttributeSet = setmetatable({}, {__mode="k"})
    ObservedRemoteSet = setmetatable({}, {__mode="k"})
    table.clear(DynamicSignatures)
    table.clear(RemoteAggregates)

    DynamicEvents = 0
    ObservedRemoteCount = 0

    Session.Running = false
    Session.ScanRunning = false
    Session.TestsRunning = false
    Session.ObserversRunning = false
    Session.StopRequested = false
    Session.StopReason = nil
    Session.Finalized = false
    Session.StartedAtClock = 0
    Session.StartedAtUnix = 0
    Session.RunId = nil
    Session.EstimatedBytes = 2
    Session.RecordCount = 0
    Session.ObjectsScanned = 0
    Session.ServicesDone = 0
    Session.ServicesTotal = #CONFIG.SERVICES
    Session.CurrentService = ""
    Session.VisualStatsCleared = false
end

local function beginSession(mode)
    if Session.Running then return end

    stopObservers()
    resetTemporarySession()

    Session.Running = true
    Session.StartedAtClock = os.clock()
    Session.StartedAtUnix = nowUnix()
    Session.RunId = newRunId()

    Archive.Sessions += 1
    Archive.Uploaded = false
    if not Archive.Persistent and type(env.__CAFEINA_MAPPING_V14_MEMORY_ARCHIVE) == "table" then
        env.__CAFEINA_MAPPING_V14_MEMORY_ARCHIVE.sessions = Archive.Sessions
    end
    ManifestState.dirty = true
    saveManifest(true)

    Report.meta = {
        scanner=CONFIG.VERSION,
        mode=mode,
        clientVisibleOnly=true,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        startedAt=Session.StartedAtUnix,
        runId=Session.RunId,
        persistent=Archive.Persistent,
    }

    acceptRecord({
        source="session",
        kind="session.started",
        mode=mode,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        persistent=Archive.Persistent,
    })

    ScanButton.Text = mode == "scan_and_tests" and "SCAN ATIVO" or "INICIAR SCAN"
    TestButton.Text = "TESTES ATIVOS"
    CollectionPanel.status.Text =
        mode == "scan_and_tests" and "Scan + TestLab • iniciando"
        or "TestLab ativo"

    task.spawn(runTestLab)

    if mode == "scan_and_tests" then
        task.spawn(runMappingEngine)
    end

    updateUI()
end

local function stopEverything(reason)
    if not Session.Running and not Upload.Running then
        return
    end

    if Session.Running then
        Session.StopRequested = true
        Session.StopReason = reason or "manual_stop"
        CollectionPanel.status.Text = "Finalizando parada..."

        acceptRecord({
            source="session",
            kind="stop_requested",
            reason=Session.StopReason,
        })
    end

    if Upload.Running then
        Upload.CancelRequested = true
    end

    task.spawn(function()
        local deadline = os.clock() + 3
        while (Session.ScanRunning or Session.TestsRunning) and os.clock() < deadline do
            task.wait(0.05)
        end

        stopObservers()
        Session.Running = false
        Session.ScanRunning = false
        Session.TestsRunning = false

        ScanButton.Text = "INICIAR SCAN"
        TestButton.Text = "INICIAR TESTES"

        -- visual-only reset, archive remains preserved
        Session.EstimatedBytes = 2
        Session.ObjectsScanned = 0
        Session.ServicesDone = 0
        Session.VisualStatsCleared = true

        CollectionPanel.status.Text = "Parado • stats limpos"
        ManifestState.dirty = true
        saveManifest(true)
        updateUI(true)
    end)
end

--==============================================================--
-- HTTP / UPLOADER
--==============================================================--

local function normalizeResponse(resp)
    if type(resp) ~= "table" then
        return false, nil, nil
    end

    local status = tonumber(resp.StatusCode or resp.Status or resp.status_code or resp.status)
    local body = resp.Body or resp.body or ""

    local success = resp.Success
    if success == nil and status then
        success = status >= 200 and status < 300
    end

    return success == true, status, body
end

local function httpPostJson(url, body, statusPrefix)
    if not REQUEST then
        return false, nil, "HTTP request indisponível no executor"
    end

    local encoded = safeJson(body)

    for attempt = 1, CONFIG.HTTP_RETRIES do
        if Upload.CancelRequested then
            return false, nil, "cancelled"
        end

        UploadPanel.status.Text = string.format("%s • %d/%d", statusPrefix, attempt, CONFIG.HTTP_RETRIES)
        updateUI()

        local ok, resp = pcall(REQUEST, {
            Url=url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
            },
            Body=encoded,
        })

        if ok then
            local success, status, raw = normalizeResponse(resp)
            if success then
                local decoded = nil
                if type(raw) == "string" and #raw > 0 then
                    pcall(function()
                        decoded = HttpService:JSONDecode(raw)
                    end)
                end
                return true, decoded, raw
            end
        end

        if attempt < CONFIG.HTTP_RETRIES then
            task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
        end
    end

    return false, nil, "request_failed"
end

local function archiveLinesIterator()
    local blockIndex = 0
    local memoryIndex = 0
    local currentLines = nil
    local currentLineIndex = 0

    return function()
        while true do
            if Archive.Persistent then
                if currentLines and currentLineIndex < #currentLines then
                    currentLineIndex += 1
                    return currentLines[currentLineIndex]
                end

                blockIndex += 1
                local path = Archive.Blocks[blockIndex]
                if not path then return nil end

                local ok, text = pcall(READFILE, path)
                if ok and type(text) == "string" then
                    currentLines = {}
                    currentLineIndex = 0
                    for line in string.gmatch(text, "[^\r\n]+") do
                        table.insert(currentLines, line)
                    end
                else
                    currentLines = {}
                    currentLineIndex = 0
                end
            else
                memoryIndex += 1
                return Archive.MemoryLines[memoryIndex]
            end
        end
    end
end

local function buildUploadHeaderLine()
    return safeJson({
        recordType="mapping_header",
        runId=Session.RunId or newRunId(),
        metadata={
            scanner=CONFIG.VERSION,
            build="MOBILE_OPT_1",
            clientVisibleOnly=true,
            placeId=game.PlaceId,
            gameId=game.GameId,
            placeVersion=game.PlaceVersion,
            archivedBytesApprox=Archive.Bytes,
            archivedRecordCount=Archive.Records,
            persistent=Archive.Persistent,
            archivedBlocks=Archive.Persistent and #Archive.Blocks or 1,
        }
    })
end

local function eachUploadLine(callback)
    if callback(buildUploadHeaderLine()) == false then
        return false
    end

    local iterator = archiveLinesIterator()
    while true do
        local line = iterator()
        if line == nil then break end
        if callback(line) == false then
            return false
        end
    end
    return true
end

local function precalculateUpload()
    local totalChunks = 0
    local totalBytes = 0
    local currentBytes = 0
    local currentLines = 0

    eachUploadLine(function(line)
        local add = #line + (currentLines > 0 and 1 or 0)
        if currentLines > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            totalChunks += 1
            totalBytes += currentBytes
            currentBytes = #line
            currentLines = 1
        else
            currentBytes += add
            currentLines += 1
        end
    end)

    if currentLines > 0 then
        totalChunks += 1
        totalBytes += currentBytes
    end

    return totalChunks, totalBytes
end

local function streamUploadChunks(callback)
    local current = {}
    local currentBytes = 0

    local function flush()
        if #current == 0 then return true end
        local chunk = table.concat(current, "\n")
        current = {}
        currentBytes = 0
        return callback(chunk) ~= false
    end

    local stopped = false
    eachUploadLine(function(line)
        if stopped then return false end
        local add = #line + (#current > 0 and 1 or 0)
        if #current > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            if not flush() then
                stopped = true
                return false
            end
            add = #line
        end
        table.insert(current, line)
        currentBytes += add
        return true
    end)

    if stopped then return false end
    return flush()
end

local function deleteArchiveAfterConfirmedUpload()
    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            if ISFILE(path) then
                pcall(DELFILE, path)
            end
        end

        if ISFILE(CONFIG.MANIFEST_PATH) then
            pcall(DELFILE, CONFIG.MANIFEST_PATH)
        end
    end

    Archive.Blocks = {blockPath(1)}
    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0
    Archive.Bytes = 0
    Archive.Records = 0
    Archive.Uploaded = true
    if not Archive.Persistent then
        table.clear(Archive.MemoryLines)
        env.__CAFEINA_MAPPING_V14_MEMORY_ARCHIVE = {
            lines = Archive.MemoryLines,
            sessions = Archive.Sessions,
        }
    else
        Archive.MemoryLines = {}
    end

    Report.records = {}
    Session.EstimatedBytes = 2
    Session.RecordCount = 0

    ManifestState.dirty = true
    saveManifest(true)
end

local function requestCancelUpload()
    if not Upload.UploadId then return end

    pcall(function()
        httpPostJson(
            CONFIG.UPLOAD_BASE .. "/cancel",
            {uploadId=Upload.UploadId},
            "Cancelando upload"
        )
    end)
end

local function uploadAll()
    if Upload.Running then return end
    if Archive.Records <= 0 then
        UploadPanel.status.Text = "Nada arquivado para enviar"
        updateUI()
        return
    end

    ManifestState.dirty = true
    saveManifest(true)

    Upload.Running = true
    Upload.CancelRequested = false
    Upload.UploadId = nil
    Upload.ChunksSent = 0
    Upload.BytesSent = 0
    Upload.TotalBytes = 0
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0

    UploadButton.Text = "ENVIANDO..."
    UploadPanel.status.Text = "Calculando arquivo preservado..."
    updateUI()

    local okBuild, totalChunks, totalBytes = pcall(precalculateUpload)
    if not okBuild or not totalChunks or totalChunks <= 0 then
        UploadPanel.status.Text = "Integridade falhou • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI(true)
        return
    end

    Upload.TotalChunks = totalChunks
    Upload.TotalBytes = totalBytes
    updateUI(true)

    local fileName = string.format(
        "Cafeina_Mapping_%s_%s.json",
        tostring(game.PlaceId),
        isoUTC()
    )

    -- NOTE:
    -- The report specifies the endpoint sequence but not the server's exact
    -- request/response JSON contract. These fields are isolated here so they
    -- can be adjusted without touching scanner/archive logic.
    local startOk, startData = httpPostJson(
        CONFIG.UPLOAD_BASE .. "/start",
        {
            filename=fileName,
            fileName=fileName,
            scanner=CONFIG.VERSION,
            placeId=game.PlaceId,
            gameId=game.GameId,
            totalChunks=Upload.TotalChunks,
            totalBytes=Upload.TotalBytes,
        },
        "Abrindo upload"
    )

    if not startOk then
        UploadPanel.status.Text = "Erro ao abrir upload • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI()
        return
    end

    Upload.UploadId =
        type(startData) == "table"
        and (startData.uploadId or startData.id or startData.upload_id)
        or nil

    if not Upload.UploadId then
        UploadPanel.status.Text = "Resposta /start inválida • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI()
        return
    end

    local streamIndex = 0
    local streamFailed = false

    local streamOk = streamUploadChunks(function(chunk)
        if Upload.CancelRequested then
            streamFailed = true
            return false
        end

        streamIndex += 1
        local i = streamIndex
        Upload.CurrentChunk = i
        UploadPanel.status.Text = string.format("Enviando chunk %d/%d", i, Upload.TotalChunks)
        updateUI(true)

        local chunkOk = httpPostJson(
            CONFIG.UPLOAD_BASE .. "/chunk",
            {
                uploadId=Upload.UploadId,
                index=i,
                chunkIndex=i,
                totalChunks=Upload.TotalChunks,
                data=chunk,
            },
            string.format("Chunk %d/%d", i, Upload.TotalChunks)
        )

        if not chunkOk then
            streamFailed = true
            return false
        end

        Upload.ChunksSent += 1
        Upload.BytesSent += #chunk
        updateUI()
        task.wait()
        return true
    end)

    if not streamOk or streamFailed then
        requestCancelUpload()
        UploadPanel.status.Text = Upload.CancelRequested
            and "Upload interrompido • arquivo preservado"
            or "Erro no envio • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI(true)
        return
    end

    if Upload.ChunksSent ~= Upload.TotalChunks then
        requestCancelUpload()
        UploadPanel.status.Text = "Integridade falhou • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI()
        return
    end

    UploadPanel.status.Text = "Confirmando /finish..."
    updateUI()

    local finishOk, finishData = httpPostJson(
        CONFIG.UPLOAD_BASE .. "/finish",
        {
            uploadId=Upload.UploadId,
            totalChunks=Upload.TotalChunks,
            totalBytes=Upload.TotalBytes,
            records=Archive.Records,
        },
        "Confirmando /finish"
    )

    if not finishOk then
        UploadPanel.status.Text = "Finalização falhou • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI()
        return
    end

    local confirmed = true
    if type(finishData) == "table" then
        if finishData.success == false or finishData.confirmed == false then
            confirmed = false
        end
    end

    if not confirmed then
        UploadPanel.status.Text = "Integridade falhou • arquivo preservado"
        Upload.Running = false
        UploadButton.Text = "ENVIAR TUDO"
        updateUI()
        return
    end

    local url = ""
    if type(finishData) == "table" then
        url = tostring(finishData.url or finishData.link or finishData.fileUrl or "")
    end

    Upload.LastURL = url

    deleteArchiveAfterConfirmedUpload()

    UploadPanel.status.Text = "Upload confirmado • dados arquivados apagados"

    if url ~= "" then
        LinkLabel.Text = "Link: " .. url
    else
        LinkLabel.Text = "Upload confirmado • arquivo local limpo"
    end

    Upload.Running = false
    UploadButton.Text = "ENVIAR TUDO"
    updateUI()
end

--==============================================================--
-- BUTTONS
--==============================================================--

ScanButton.MouseButton1Click:Connect(function()
    if not Session.Running then
        beginSession("scan_and_tests")
    end
end)

TestButton.MouseButton1Click:Connect(function()
    if not Session.Running then
        beginSession("tests_only")
    end
end)

UploadButton.MouseButton1Click:Connect(function()
    if not Upload.Running then
        task.spawn(uploadAll)
    end
end)

StopButton.MouseButton1Click:Connect(function()
    stopEverything("manual_stop")
end)

--==============================================================--
-- INITIAL LOAD
--==============================================================--

loadArchive()

if Archive.Records > 0 then
    UploadPanel.status.Text = "Arquivo recuperado • pronto para enviar"
else
    UploadPanel.status.Text = "Aguardando envio"
end

ArchivePanel.status.Text =
    Archive.Persistent and "Persistência local ativa"
    or "Modo memória • persistência local indisponível"

CollectionPanel.status.Text = "Pronto"
updateUI(true)

-- Flush archive metadata and stop observers if the GUI is externally destroyed.
Gui.Destroying:Connect(function()
    pcall(function()
        ManifestState.dirty = true
        saveManifest(true)
    end)
    pcall(function()
        Session.StopRequested = true
        Session.StopReason = Session.StopReason or "gui_destroyed"
        stopObservers()
    end)
end)

env.__CAFEINA_MAPPING_V14_CONTROLLER = {
    Stop = function(reason)
        pcall(function() stopEverything(reason or "external_stop") end)
        pcall(function()
            ManifestState.dirty = true
            saveManifest(true)
        end)
        pcall(function() Gui:Destroy() end)
    end,
    Gui = Gui,
}

--==============================================================--
-- END
--==============================================================--
