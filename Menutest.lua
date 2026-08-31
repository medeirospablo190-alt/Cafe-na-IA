--==============================================================--
-- CAFEÍNA • MAPPING V1.6 • UNIVERSAL SMART COMPACT
-- MAPPING ENGINE + TEST LAB + PERSISTENT ARCHIVE + UPLOADER
-- UNIVERSAL ROBLOX BUILD • MOBILE OPTIMIZED • CLIENT-VISIBLE ONLY
--
-- Universal focus:
-- adaptive discovery of remotes/modules, player & NPC state, combat, economy,
-- inventory, quests, interactions, zones, rounds, vehicles, pets/eggs and UI state.
--
-- IMPORTANT:
-- • Passive Test Lab: does NOT FireServer/InvokeServer arbitrarily.
-- • Menutest compact one-button UI + automatic upload after ENCERRAR.
-- • Manifest backup + strict /finish confirmation before archive deletion.
-- • Adaptive passive bootstrap discovers high-value systems before the full scan.
-- • Stable change detection + event-driven attributes reduce duplicate/noisy records.
-- • Mobile build: prioritized observers, throttled UI/manifest, streaming upload.
-- • Stop never erases archived data.
-- • Archive is erased only after /upload/finish confirms success.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "MAPPING_V1_6_1_UNIVERSAL_SMART_COMPACT",
    GUI_NAME = "CafeinaMappingV16Universal",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 3200000,
    BLOCK_TARGET_BYTES = 1024 * 1024,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.25,

    ATTRIBUTE_POLL_SECONDS = 0.45,
    ATTRIBUTE_AUDIT_EVERY_CYCLES = 24,
    HEARTBEAT_EVERY_CYCLES = 12,

    MAX_TRACKED_VALUES = 3200,
    MAX_TRACKED_ATTRIBUTES = 1800,
    MAX_TRACKED_REMOTES = 420,
    MAX_DYNAMIC_EVENTS = 36000,
    FAST_BOOTSTRAP_MAX_OBJECTS = 6000,

    CORRELATION_WINDOW_SECONDS = 0.20,

    -- Mobile/performance controls
    UI_UPDATE_INTERVAL = 0.18,
    MANIFEST_FLUSH_RECORDS = 40,
    MANIFEST_FLUSH_SECONDS = 1.75,
    SCAN_YIELD_EVERY = 140,
    ATTRIBUTE_YIELD_EVERY = 90,
    MEMORY_RECORD_CAP = 3200,

    ARCHIVE_ROOT = "CafeinaArchive",
    ARCHIVE_FOLDER = "CafeinaArchive/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaArchive/" .. tostring(game.PlaceId) .. "/manifest.json",
    MANIFEST_BACKUP_PATH = "CafeinaArchive/" .. tostring(game.PlaceId) .. "/manifest.bak",

    SERVICES = {
        -- High-value runtime services first. This makes useful data arrive
        -- earlier without reducing the later full scan coverage.
        {name="ReplicatedStorage", budget=42000},
        {name="Players",           budget=20000},
        {name="Workspace",         budget=36000},
        {name="StarterPlayer",     budget=19000},
        {name="ReplicatedFirst",   budget=8000},
        {name="StarterGui",        budget=18000},
        {name="Lighting",          budget=4000},
        {name="Teams",             budget=2500},
        {name="SoundService",      budget=5000},
    }
}

if IS_MOBILE then
    -- Keep the same archive limit and behavior, but reduce simultaneous live
    -- watchers to avoid frame drops on lower-memory Android devices.
    CONFIG.MAX_TRACKED_VALUES = 2400
    CONFIG.MAX_TRACKED_ATTRIBUTES = 1250
    CONFIG.MAX_TRACKED_REMOTES = 360
    CONFIG.SCAN_YIELD_EVERY = 110
    CONFIG.ATTRIBUTE_YIELD_EVERY = 80
    CONFIG.ATTRIBUTE_POLL_SECONDS = 0.55
    CONFIG.MEMORY_RECORD_CAP = 2200
end

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G
local MEMORY_ARCHIVE_KEY = "__CAFEINA_MAPPING_UNIVERSAL_ARCHIVE_" .. tostring(game.PlaceId)

-- Prevent duplicate optimized instances after re-executing the script.
pcall(function()
    for _, key in ipairs({
        "__CAFEINA_MAPPING_V16_CONTROLLER",
        "__CAFEINA_MAPPING_V15_CONTROLLER",
    }) do
        local previous = rawget(env, key)
        if type(previous) == "table" and type(previous.Stop) == "function" then
            previous.Stop("replaced_by_new_instance")
            break
        end
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
    -- Stable structural equality. JSON key ordering can vary for Lua tables and
    -- prevents serialized tables/instances from creating false duplicate changes.
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for k, v in pairs(a) do
        if not shallowEqual(v, b[k]) then
            return false
        end
    end

    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
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
-- UNIVERSAL RELEVANCE / CONTEXT
--==============================================================--

local CLASS_SCORE = {
    RemoteEvent = 130,
    RemoteFunction = 130,
    UnreliableRemoteEvent = 125,
    BindableEvent = 45,
    BindableFunction = 45,
    ModuleScript = 80,
    LocalScript = 60,
    Script = 55,
    ObjectValue = 70,
    StringValue = 60,
    BoolValue = 60,
    NumberValue = 65,
    IntValue = 45,
    Tool = 90,
    ProximityPrompt = 85,
    ClickDetector = 70,
    Configuration = 60,
    Humanoid = 75,
    Animator = 35,
    Folder = 8,
    Model = 8,
}

-- These are intentionally generic. They are signals, not hard requirements.
local UNIVERSAL_KEYWORDS = {
    remote=80, remotes=85, event=55, events=60, network=85, net=35, rpc=70,
    module=45, shared=35, framework=40, controller=45, handler=45, manager=40, service=35,
    data=45, profile=55, datastore=55, save=45, config=45, setting=45, settings=45,
    stat=50, stats=55, leaderstats=65, value=20, state=45, status=45,

    combat=70, damage=70, health=55, hit=55, hurt=50, attack=55, melee=55,
    weapon=60, weapons=65, gun=60, guns=60, bullet=55, projectile=55, ammo=55,
    shoot=55, fire=40, reload=45, parry=50, block=45, stamina=45, skill=45, ability=50,

    inventory=70, backpack=55, item=50, items=55, iteminfo=60, tool=50, equip=55,
    loot=65, drop=50, pickup=60, collect=55, reward=55, currency=60, money=60, cash=60,
    coin=55, gem=55, shop=55, store=50, merchant=50, purchase=55, sell=50, trade=50,
    crafting=55, craft=55, recipe=50, upgrade=50, resource=45,

    npc=60, ai=65, enemy=60, enemies=65, mob=60, mobs=65, monster=55, boss=65,
    target=60, lookingat=55, aggro=55, patrol=45, path=35, spawn=45, spawner=50,

    quest=65, objective=65, mission=60, dialogue=55, task=45, tutorial=45,
    round=55, match=55, wave=55, timer=35, lobby=45, team=45, party=45,
    zone=50, area=45, region=40, checkpoint=50, safezone=55, trigger=45, interact=55,
    prompt=50, door=35, chest=50, crate=50, portal=50, teleport=50,

    character=55, humanoid=55, movement=50, mobility=50, speed=40, jump=40,
    vehicle=55, car=45, boat=45, plane=45, seat=30,
    pet=55, pets=60, egg=55, hatch=55, tycoon=55, plot=50, base=35, farm=45,

    gui=25, ui=25, hud=30, menu=25, button=20, frame=10,
}

local function textSignalScore(text)
    local s = string.lower(tostring(text or ""))
    local score = 0
    for word, add in pairs(UNIVERSAL_KEYWORDS) do
        if string.find(s, word, 1, true) then
            score += add
        end
    end
    return score
end

local CRITICAL_HINTS = {
    "Remotes", "Remote", "Events", "Network", "Modules", "Shared",
    "Controllers", "Handlers", "Services", "Data", "Profiles", "Stats",
    "Inventory", "Items", "ItemInfo", "Combat", "Weapons", "NPC", "NPCs",
    "AI", "Enemies", "Mobs", "Quests", "Objectives", "Loot", "Interactables",
    "Zones", "Rounds", "Tycoon", "Pets", "Eggs", "Vehicles",
}

local function relevanceOf(inst)
    if not inst then return 0 end
    local original = safePath(inst)
    local path = string.lower(original)
    local name = string.lower(inst.Name or "")
    local score = CLASS_SCORE[inst.ClassName] or 0

    for word, add in pairs(UNIVERSAL_KEYWORDS) do
        if string.find(path, word, 1, true) or string.find(name, word, 1, true) then
            score += add
        end
    end

    for _, hint in ipairs(CRITICAL_HINTS) do
        if string.find(original, hint, 1, true) then
            score += 55
        end
    end

    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
        score += 80
    elseif inst:IsA("ModuleScript") then
        score += 25
    elseif inst:IsA("Humanoid") then
        score += 40
    elseif inst:IsA("Tool") or inst:IsA("ProximityPrompt") then
        score += 35
    end

    local okAttrs, attrs = pcall(function() return inst:GetAttributes() end)
    if okAttrs and type(attrs) == "table" then
        local n = 0
        for _ in pairs(attrs) do n += 1 end
        score += math.min(n * 4, 28)
    end

    return score
end

local function classifyContext(path)
    local s = string.lower(path or "")

    local function has(...)
        for i = 1, select("#", ...) do
            local w = select(i, ...)
            if string.find(s, w, 1, true) then return true end
        end
        return false
    end

    if has("damage","blood","hurt","attack","combat","weapon","gun","bullet","projectile","ammo","parry","block") then
        return "COMBAT"
    elseif has("npc","enemy","mob","monster","boss","aggro","patrol","ai.",".ai") then
        return "NPC"
    elseif has("inventory","backpack","item","loot","pickup","drop","equip","tool") then
        return "INVENTORY"
    elseif has("money","cash","coin","gem","currency","shop","store","merchant","purchase","sell","trade") then
        return "ECONOMY"
    elseif has("craft","recipe","upgrade","workbench","resource") then
        return "CRAFTING"
    elseif has("quest","objective","mission","dialogue","tutorial") then
        return "QUEST"
    elseif has("round","match","wave","lobby","party","team") then
        return "MATCH"
    elseif has("zone","area","checkpoint","safezone","portal","teleport","trigger") then
        return "ZONE"
    elseif has("pet","egg","hatch") then
        return "PET"
    elseif has("vehicle","car","boat","plane") then
        return "VEHICLE"
    elseif has("tycoon","plot","farm") then
        return "TYCOON"
    elseif has("character","humanoid","movement","mobility","stamina","health","leaderstats","walkspeed","jumppower") then
        return "CHARACTER"
    elseif has("playergui","startergui","screenui","gui","hud","button","frame","label") then
        return "UI"
    elseif has("remote","event","network","rpc") then
        return "NETWORK"
    else
        return "WORLD"
    end
end

local GENERIC_FAST_PATHS = {
    "ReplicatedStorage.Remotes", "ReplicatedStorage.RemoteEvents", "ReplicatedStorage.Events",
    "ReplicatedStorage.Network", "ReplicatedStorage.Modules", "ReplicatedStorage.Shared",
    "ReplicatedStorage.Controllers", "ReplicatedStorage.GameStuff.Remotes",
    "ReplicatedStorage.GameStuff.Modules", "ReplicatedStorage.GameStuff.ItemInfo",
    "Workspace.NPCs", "Workspace.NPC", "Workspace.AI", "Workspace.Enemies",
    "Workspace.Mobs", "Workspace.Loot", "Workspace.Items", "Workspace.Interactables",
    "Workspace.Zones", "Workspace.GameStuff",
}

local function resolvePath(path)
    local current = game
    for segment in string.gmatch(path or "", "[^%.]+") do
        if current == game then
            local ok, service = pcall(function()
                return game:GetService(segment)
            end)
            current = ok and service or game:FindFirstChild(segment)
        else
            current = current:FindFirstChild(segment)
        end

        if not current then
            return nil
        end
    end
    return current
end

local function getFastRoots(pathList, includeCharacters)
    local roots = {}
    local seen = setmetatable({}, {__mode="k"})

    local function add(inst)
        if inst and not seen[inst] then
            seen[inst] = true
            table.insert(roots, inst)
        end
    end

    for _, path in ipairs(pathList or GENERIC_FAST_PATHS) do
        add(resolvePath(path))
    end

    -- ReplicatedStorage is the most common home for client-visible protocols and
    -- shared game definitions, so inspect it early even when the game uses custom names.
    pcall(function() add(game:GetService("ReplicatedStorage")) end)

    -- Adaptive discovery: inspect only the upper tree first and select containers
    -- that look important. Full coverage still happens in the normal scan.
    for _, serviceName in ipairs({"ReplicatedStorage", "Workspace"}) do
        local okService, service = pcall(function() return game:GetService(serviceName) end)
        if okService and service then
            local okChildren, children = pcall(function() return service:GetChildren() end)
            if okChildren then
                for _, child in ipairs(children) do
                    if relevanceOf(child) >= 55 then add(child) end
                    local okGrand, grand = pcall(function() return child:GetChildren() end)
                    if okGrand then
                        for _, item in ipairs(grand) do
                            if relevanceOf(item) >= 95 then add(item) end
                        end
                    end
                end
            end
        end
    end

    -- CollectionService tags often carry semantics even when hierarchy names do not.
    local taggedAdded = 0
    pcall(function()
        for _, tag in ipairs(CollectionService:GetAllTags()) do
            if taggedAdded >= 400 then break end
            if textSignalScore(tag) >= 40 then
                for _, inst in ipairs(CollectionService:GetTagged(tag)) do
                    add(inst)
                    taggedAdded += 1
                    if taggedAdded >= 400 then break end
                end
            end
        end
    end)

    if LocalPlayer then
        add(LocalPlayer:FindFirstChild("Backpack"))
        add(LocalPlayer:FindFirstChild("PlayerScripts"))
        add(LocalPlayer:FindFirstChild("PlayerGui"))
    end

    if includeCharacters then
        for _, player in ipairs(Players:GetPlayers()) do
            add(player.Character)
            add(player:FindFirstChild("Backpack"))
        end
    end

    return roots
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
local ObservedHumanoidSet = setmetatable({}, {__mode="k"})
local DynamicSignatures = {}
local RemoteAggregates = {}
local DynamicPathCounts = {}
local ScannedInstanceSet = setmetatable({}, {__mode="k"})
local RootSignalSet = setmetatable({}, {__mode="k"})
local DynamicEvents = 0
local ObservedRemoteCount = 0
local FastSeededObjects = 0

local ManifestState = {
    dirty = false,
    recordsSinceSave = 0,
    lastSaveClock = 0,
}

local UIState = {
    lastUpdateClock = 0,
}

local requestStopAndUpload

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
        if not ISFOLDER or not ISFOLDER(CONFIG.ARCHIVE_ROOT) then
            MAKEFOLDER(CONFIG.ARCHIVE_ROOT)
        end
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
        schema = 2,
        scanner = CONFIG.VERSION,
        build = "UNIVERSAL_SMART_COMPACT_1",
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

    local encoded = safeJson(manifest)
    local ok = pcall(function()
        -- Keep the previous known-good manifest before replacing it.
        if ISFILE(CONFIG.MANIFEST_PATH) then
            local readOk, previous = pcall(READFILE, CONFIG.MANIFEST_PATH)
            if readOk and type(previous) == "string" and #previous > 0 then
                pcall(WRITEFILE, CONFIG.MANIFEST_BACKUP_PATH, previous)
            end
        end
        WRITEFILE(CONFIG.MANIFEST_PATH, encoded)
    end)

    if ok then
        ManifestState.dirty = false
        ManifestState.recordsSinceSave = 0
        ManifestState.lastSaveClock = now
    end
end

local function decodeManifest(path)
    if not FILESYSTEM_OK or not ISFILE(path) then return nil end
    local ok, raw = pcall(READFILE, path)
    if not ok or type(raw) ~= "string" then return nil end
    local decOk, manifest = pcall(HttpService.JSONDecode, HttpService, raw)
    if decOk and type(manifest) == "table" then return manifest end
    return nil
end

local function recoverBlocksByProbe()
    local blocks = {}
    if not FILESYSTEM_OK then return blocks end
    for i = 1, 10000 do
        local path = blockPath(i)
        if ISFILE(path) then
            table.insert(blocks, path)
        else
            break
        end
    end
    return blocks
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
        local shared = rawget(env, MEMORY_ARCHIVE_KEY)
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
            env[MEMORY_ARCHIVE_KEY] = {
                lines = Archive.MemoryLines,
                sessions = Archive.Sessions,
            }
        end
        return
    end

    ensureArchiveFolder()

    local manifest = decodeManifest(CONFIG.MANIFEST_PATH)
        or decodeManifest(CONFIG.MANIFEST_BACKUP_PATH)

    if manifest then
        Archive.Blocks = manifest.blocks or {}
        Archive.CurrentBlock = tonumber(manifest.currentBlock) or math.max(#Archive.Blocks, 1)
        Archive.Sessions = tonumber(manifest.sessions) or 0
        Archive.Uploaded = manifest.uploaded == true
    end

    -- If both manifests are unavailable/corrupt, recover the JSONL blocks
    -- directly instead of treating the archive as empty.
    if #Archive.Blocks == 0 then
        Archive.Blocks = recoverBlocksByProbe()
    end

    if #Archive.Blocks == 0 then
        Archive.CurrentBlock = 1
        Archive.Blocks = {blockPath(1)}
    else
        Archive.CurrentBlock = math.max(1, math.min(Archive.CurrentBlock, #Archive.Blocks))
        if Archive.CurrentBlock < #Archive.Blocks then
            Archive.CurrentBlock = #Archive.Blocks
        end
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

-- Same compact layout used by Menutest.lua, with the V1.5 engine behind it.
local COLORS = {
    BG = Color3.fromRGB(7,7,9),
    PANEL = Color3.fromRGB(15,15,18),
    BUTTON = Color3.fromRGB(28,28,32),
    RED = Color3.fromRGB(205,38,48),
    RED_DARK = Color3.fromRGB(105,25,31),
    GREEN = Color3.fromRGB(45,180,88),
    TEXT = Color3.fromRGB(245,245,247),
    SUB = Color3.fromRGB(145,145,155),
    BAR_BG = Color3.fromRGB(31,31,36),
    BORDER = Color3.fromRGB(44,44,49),
}

local Flow = {
    Mode = "idle", -- idle | collecting | finalizing | uploading | retry
    FinalizerRunning = false,
}

UIState.overrideStatus = nil
UIState.overrideDetail = nil

local function setUiMessage(status, detail)
    UIState.overrideStatus = status
    UIState.overrideDetail = detail
end

local guiParent = CoreGui
pcall(function()
    if type(gethui) == "function" then
        guiParent = gethui()
    end
end)
if not guiParent then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end

pcall(function()
    local old = guiParent:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
local parentOk = pcall(function() Gui.Parent = guiParent end)
if not parentOk then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(224,154)
Main.AnchorPoint = Vector2.new(0.5,0.5)
Main.Position = UDim2.fromScale(0.5,0.5)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,9)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.BORDER
stroke.Thickness = 1
stroke.Parent = Main

local Header = Instance.new("TextLabel")
Header.Size = UDim2.new(1,-12,0,29)
Header.Position = UDim2.fromOffset(6,2)
Header.BackgroundTransparency = 1
Header.Text = "CAFEÍNA • MAPPING V1.6"
Header.TextColor3 = COLORS.TEXT
Header.TextSize = 11
Header.Font = Enum.Font.GothamBold
Header.Active = true
Header.Parent = Main

local ActionButton = Instance.new("TextButton")
ActionButton.Size = UDim2.new(1,-16,0,37)
ActionButton.Position = UDim2.fromOffset(8,32)
ActionButton.BackgroundColor3 = COLORS.BUTTON
ActionButton.BorderSizePixel = 0
ActionButton.AutoButtonColor = false
ActionButton.Text = "INICIAR TUDO"
ActionButton.TextColor3 = COLORS.TEXT
ActionButton.TextSize = 11
ActionButton.Font = Enum.Font.GothamBold
ActionButton.Parent = Main
Instance.new("UICorner", ActionButton).CornerRadius = UDim.new(0,7)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1,-16,0,18)
StatusLabel.Position = UDim2.fromOffset(8,76)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Pronto"
StatusLabel.TextColor3 = COLORS.TEXT
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Main

local DetailLabel = Instance.new("TextLabel")
DetailLabel.Size = UDim2.new(1,-16,0,30)
DetailLabel.Position = UDim2.fromOffset(8,94)
DetailLabel.BackgroundTransparency = 1
DetailLabel.Text = "0.00 MB coletados • faltam 150.00 MB"
DetailLabel.TextColor3 = COLORS.SUB
DetailLabel.TextSize = 9
DetailLabel.Font = Enum.Font.Gotham
DetailLabel.TextWrapped = true
DetailLabel.TextXAlignment = Enum.TextXAlignment.Left
DetailLabel.Parent = Main

local Bar = Instance.new("Frame")
Bar.Size = UDim2.new(1,-16,0,9)
Bar.Position = UDim2.new(0,8,1,-19)
Bar.BackgroundColor3 = COLORS.BAR_BG
Bar.BorderSizePixel = 0
Bar.Parent = Main
Instance.new("UICorner", Bar).CornerRadius = UDim.new(1,0)

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.fromScale(0,1)
BarFill.BackgroundColor3 = COLORS.RED
BarFill.BorderSizePixel = 0
BarFill.Parent = Bar
Instance.new("UICorner", BarFill).CornerRadius = UDim.new(1,0)

local Scale = Instance.new("UIScale")
Scale.Parent = Main
local function refreshScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    Scale.Scale = math.min(1, math.max(0.82, (viewport.X - 16) / 224))
end
refreshScale()
pcall(function()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        task.defer(refreshScale)
    end)
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
    end
end)

-- Header drag, matching the compact Menutest behavior.
do
    local dragging = false
    local startInput
    local startPosition

    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startInput = input.Position
            startPosition = Main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        local delta = input.Position - startInput
        local scale = math.max(Scale.Scale, 0.01)
        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X / scale,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y / scale
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

local function setBar(ratio, uploadMode)
    ratio = clamp01(ratio)
    BarFill.BackgroundColor3 = uploadMode and COLORS.GREEN or COLORS.RED
    pcall(function()
        TweenService:Create(
            BarFill,
            TweenInfo.new(0.10),
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

    if Flow.Mode == "collecting" then
        local remaining = math.max(0, CONFIG.MAX_ARCHIVE_BYTES - Archive.Bytes)
        StatusLabel.Text = "Coletando • Scan + Test Lab"
        DetailLabel.Text = string.format(
            "%.2f MB coletados • faltam %.2f MB",
            mb(Archive.Bytes), mb(remaining)
        )
        setBar(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES, false)

    elseif Flow.Mode == "finalizing" then
        StatusLabel.Text = "Finalizando coleta..."
        DetailLabel.Text = string.format(
            "%.2f MB preservados • fechando observadores",
            mb(Archive.Bytes)
        )
        setBar(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES, false)

    elseif Flow.Mode == "uploading" then
        local ratio = Upload.TotalBytes > 0 and (Upload.BytesSent / Upload.TotalBytes) or 0
        StatusLabel.Text = string.format(
            "Enviando ao servidor • %d%%",
            math.floor(clamp01(ratio) * 100)
        )
        DetailLabel.Text = string.format(
            "%.2f / %.2f MB • chunk %d/%d",
            mb(Upload.BytesSent), mb(Upload.TotalBytes),
            Upload.CurrentChunk, Upload.TotalChunks
        )
        setBar(ratio, true)

    else
        if UIState.overrideStatus then
            StatusLabel.Text = UIState.overrideStatus
            DetailLabel.Text = UIState.overrideDetail or ""
        elseif Archive.Records > 0 then
            local remaining = math.max(0, CONFIG.MAX_ARCHIVE_BYTES - Archive.Bytes)
            StatusLabel.Text = "Arquivo preservado"
            DetailLabel.Text = string.format(
                "%.2f MB arquivados • faltam %.2f MB",
                mb(Archive.Bytes), mb(remaining)
            )
        else
            StatusLabel.Text = "Pronto"
            DetailLabel.Text = string.format(
                "0.00 MB coletados • faltam %.2f MB",
                mb(CONFIG.MAX_ARCHIVE_BYTES)
            )
        end
        setBar(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES, false)
    end
end

-- Compatibility aliases let the V1.5 engine keep its internal status writes
-- without adding extra panels/buttons to the compact interface.
local CollectionPanel = {status=StatusLabel, d1=DetailLabel, d2=DetailLabel, fill=BarFill}
local ArchivePanel = {status=StatusLabel, d1=DetailLabel, d2=DetailLabel, fill=BarFill}
local UploadPanel = {status=StatusLabel, d1=DetailLabel, d2=DetailLabel, fill=BarFill}
local ScanButton = ActionButton
local TestButton = ActionButton
local UploadButton = ActionButton
local StopButton = ActionButton
local LinkLabel = DetailLabel

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
        if why == "size_limit" then
            if requestStopAndUpload and Session.Running then
                task.defer(function()
                    requestStopAndUpload("size_limit")
                end)
            end
        else
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

    if inst:IsA("ClickDetector") then
        pcall(function() rec.maxActivationDistance = inst.MaxActivationDistance end)
    end

    if inst:IsA("Player") then
        pcall(function()
            rec.userId = inst.UserId
            rec.displayName = inst.DisplayName
        end)
    end

    -- Tags are one of the best universal semantic signals because many games use
    -- CollectionService instead of descriptive folder names.
    pcall(function()
        local tags = inst:GetTags()
        if type(tags) == "table" and #tags > 0 then
            rec.tags = tags
        end
    end)

    -- Geometry is expensive, so preserve it only for high-value parts such as
    -- hitboxes, zones, interactables, spawns and other semantically scored objects.
    if inst:IsA("BasePart") and rec.relevance >= 80 then
        pcall(function()
            rec.position = safeSerialize(inst.Position)
            rec.size = safeSerialize(inst.Size)
            rec.anchored = inst.Anchored
            rec.canCollide = inst.CanCollide
            rec.transparency = inst.Transparency
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

local function emitStaticInstance(inst, phase, classCounters)
    if not inst or not inst.Parent then return false end
    if ScannedInstanceSet[inst] then return false end
    if shouldSkipStatic(inst) then return false end

    local limit = STATIC_CLASS_LIMITS[inst.ClassName]
    if limit then
        classCounters[inst.ClassName] = classCounters[inst.ClassName] or 0
        if classCounters[inst.ClassName] >= limit then
            return false
        end
    end

    local okBuild, rec = pcall(buildInstanceRecord, inst, "scan")
    if not okBuild or not rec then
        return false
    end

    rec.phase = phase
    if acceptRecord(rec) then
        ScannedInstanceSet[inst] = true
        if limit then
            classCounters[inst.ClassName] += 1
        end
        Session.ObjectsScanned += 1
        return true
    end

    return false
end

local function runPriorityBootstrap(classCounters)
    Session.CurrentService = "PRIORITY"
    CollectionPanel.status.Text = "Scan • prioridade adaptativa"
    updateUI(true)

    local candidates = {}
    local seen = setmetatable({}, {__mode="k"})
    local roots = getFastRoots(GENERIC_FAST_PATHS, true)
    local inspected = 0

    local function consider(inst)
        if not inst or seen[inst] or ScannedInstanceSet[inst] then return end
        seen[inst] = true
        if shouldSkipStatic(inst) then return end

        local score = relevanceOf(inst)
        -- Keep bootstrap small and useful. Full coverage still runs afterwards.
        if score >= 45 then
            table.insert(candidates, {inst=inst, score=score})
        end
    end

    for _, root in ipairs(roots) do
        consider(root)
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, inst in ipairs(descendants) do
                if Session.StopRequested then break end
                consider(inst)
                inspected += 1
                if inspected % CONFIG.SCAN_YIELD_EVERY == 0 then
                    task.wait()
                end
            end
        end
        if Session.StopRequested then break end
    end

    table.sort(candidates, function(a,b)
        return a.score > b.score
    end)

    local emitted = 0
    for _, candidate in ipairs(candidates) do
        if Session.StopRequested then break end
        if emitted >= CONFIG.FAST_BOOTSTRAP_MAX_OBJECTS then break end

        if emitStaticInstance(candidate.inst, "priority_bootstrap", classCounters) then
            emitted += 1
        end

        if emitted > 0 and emitted % CONFIG.SCAN_YIELD_EVERY == 0 then
            task.wait()
        end
    end

    acceptRecord({
        source="session",
        kind="priority_bootstrap_finished",
        roots=#roots,
        candidates=#candidates,
        emitted=emitted,
    })
end

local function runMappingEngine()
    Session.ScanRunning = true
    local classCounters = {}

    acceptRecord({
        source="session",
        kind="mapping_started",
        scanner=CONFIG.VERSION,
        optimization="UNIVERSAL_SMART_COMPACT_1",
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
    })

    -- First collect automatically discovered high-value runtime systems, then
    -- continue with the complete service scan.
    runPriorityBootstrap(classCounters)

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

                    if not ScannedInstanceSet[inst] and not shouldSkipStatic(inst) then
                        local limit = STATIC_CLASS_LIMITS[inst.ClassName]
                        if not limit or (classCounters[inst.ClassName] or 0) < limit then
                            table.insert(candidates, {
                                inst = inst,
                                score = relevanceOf(inst)
                            })
                        end
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

                    if emitStaticInstance(candidate.inst, "full_scan", classCounters) then
                        count += 1
                    end

                    if count > 0 and count % CONFIG.SCAN_YIELD_EVERY == 0 then
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

local function isIgnoredDynamicValue(inst)
    if not inst or not inst:IsA("ValueBase") then return false end

    local path = string.lower(safePath(inst))
    local name = string.lower(inst.Name or "")

    -- High-frequency visual timers can dominate archives without describing
    -- meaningful gameplay state, so suppress the most common rendering-only forms.
    if classifyContext(path) == "UI" then
        if name == "currenttime"
            or string.find(path, "progresscircle.currenttime", 1, true) then
            return true
        end
    end

    return false
end

local function isRelevantDynamic(inst)
    if not inst then return false end

    if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
        return true
    end

    if inst:IsA("ValueBase") then
        if isIgnoredDynamicValue(inst) then return false end
        local threshold = classifyContext(safePath(inst)) == "UI" and 90 or 35
        return relevanceOf(inst) >= threshold
    end

    local attrs = safeAttributes(inst)
    if next(attrs) ~= nil and relevanceOf(inst) >= 30 then
        return true
    end

    return relevanceOf(inst) >= 70
end

local NOISY_REMOTE_WORDS = {
    "timesync", "heartbeat", "ping", "replicateposition", "replicatemovement",
    "look", "aimupdate", "mouseposition", "camera", "footstep", "tween",
    "armclient", "updateposition", "updatecframe",
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
    local state = {
        count=0,
        firstTime=relativeTime(),
        lastTime=relativeTime(),
        samples={},
        forcedAggregate=isNoisyRemote(path),
    }
    RemoteAggregates[path] = state

    local ok, conn = pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            if not Session.TestsRunning or Session.StopRequested then return end

            local args = {...}
            state.count += 1
            state.lastTime = relativeTime()
            if #state.samples < 8 then
                table.insert(state.samples, safeSerialize(args))
            end

            local elapsed = math.max(0.001, state.lastTime - state.firstTime)
            local rate = state.count / elapsed
            local adaptiveAggregate = state.forcedAggregate or (state.count >= 30 and rate >= 8)

            -- Preserve the first messages from every remote so unknown protocols
            -- still expose their argument shapes. Only noisy/high-rate streams are
            -- compacted after that initial evidence is captured.
            if adaptiveAggregate and state.count > 8 then
                if state.count == 9 or state.count == 30 or state.count % 50 == 0 then
                    recordDynamic({
                        source="tests",
                        kind="remote_aggregate",
                        path=path,
                        className=remote.ClassName,
                        relevance=relevanceOf(remote),
                        count=state.count,
                        ratePerSecond=rate,
                        firstTime=state.firstTime,
                        lastTime=state.lastTime,
                        samples=state.samples,
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


local function observeHumanoid(humanoid)
    if not humanoid or not humanoid:IsA("Humanoid") then return end
    if ObservedHumanoidSet[humanoid] then return end
    ObservedHumanoidSet[humanoid] = true

    local path = safePath(humanoid)
    local state = {
        Health = safeSerialize(humanoid.Health),
        MaxHealth = safeSerialize(humanoid.MaxHealth),
        WalkSpeed = safeSerialize(humanoid.WalkSpeed),
        JumpPower = safeSerialize(humanoid.JumpPower),
    }

    local function capture(property)
        if not Session.TestsRunning or Session.StopRequested then return end
        if not humanoid.Parent then return end

        local ok, raw = pcall(function()
            return humanoid[property]
        end)
        if not ok then return end

        local value = safeSerialize(raw)
        if shallowEqual(state[property], value) then return end

        local before = state[property]
        state[property] = value
        recordDynamic({
            source="tests",
            kind=property == "Health" and "humanoid_health_changed" or "humanoid_property_changed",
            path=path,
            property=property,
            before=before,
            after=value,
            relevance=relevanceOf(humanoid),
        })
    end

    local okHealth, healthConn = pcall(function()
        return humanoid.HealthChanged:Connect(function()
            capture("Health")
        end)
    end)
    if okHealth and healthConn then
        table.insert(ObserverConnections, healthConn)
    end

    for _, property in ipairs({"MaxHealth","WalkSpeed","JumpPower"}) do
        local ok, conn = pcall(function()
            return humanoid:GetPropertyChangedSignal(property):Connect(function()
                capture(property)
            end)
        end)
        if ok and conn then
            table.insert(ObserverConnections, conn)
        end
    end
end

local function addTrackedValue(inst)
    if #TrackedValues >= CONFIG.MAX_TRACKED_VALUES then return end
    if TrackedValueSet[inst] then return end
    if not inst:IsA("ValueBase") then return end
    if isIgnoredDynamicValue(inst) then return end
    if relevanceOf(inst) < 35 then return end

    local ok, current = pcall(function() return inst.Value end)
    if not ok then return end

    local path = safePath(inst)
    local entry = {
        inst=inst,
        path=path,
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

            local kind = "value_changed"
            local lname = string.lower(inst.Name or "")
            if inst:IsA("ObjectValue") and (
                lname == "lookingat" or lname == "target" or lname == "currenttarget"
                or lname == "targetplayer" or lname == "targetcharacter" or lname == "focus"
            ) then
                kind = "target_changed"
            end

            recordDynamic({
                source="tests",
                kind=kind,
                path=entry.path,
                className=inst.ClassName,
                before=before,
                after=newValue,
                relevance=relevanceOf(inst),
            })
        end
    end)

    table.insert(ObserverConnections, conn)
end

local function attributeDiff(before, after)
    local changes = {}
    local seen = {}

    for k, oldValue in pairs(before or {}) do
        seen[k] = true
        local newValue = after and after[k] or nil
        if not shallowEqual(oldValue, newValue) then
            changes[k] = {
                before = oldValue == nil and "<nil>" or oldValue,
                after = newValue == nil and "<nil>" or newValue,
            }
        end
    end

    for k, newValue in pairs(after or {}) do
        if not seen[k] then
            changes[k] = {
                before = "<nil>",
                after = newValue == nil and "<nil>" or newValue,
            }
        end
    end

    return changes
end

local function emitAttributeChange(entry, changedName, kind)
    local inst = entry.inst
    if not inst or not inst.Parent then return end

    local attrs = safeAttributes(inst)
    if shallowEqual(entry.attrs, attrs) then return end

    local before = entry.attrs
    entry.attrs = attrs
    local changes = attributeDiff(before, attrs)

    recordDynamic({
        source="tests",
        kind=kind or "attributes_changed",
        path=entry.path or safePath(inst),
        attribute=changedName,
        changes=changes,
        relevance=relevanceOf(inst),
    })
end

local function addTrackedAttributes(inst)
    if #TrackedAttributes >= CONFIG.MAX_TRACKED_ATTRIBUTES then return end
    if TrackedAttributeSet[inst] then return end
    if relevanceOf(inst) < 30 then return end

    local attrs = safeAttributes(inst)
    if next(attrs) == nil then return end

    local entry = {
        inst=inst,
        path=safePath(inst),
        attrs=attrs,
        eventDriven=false,
    }

    TrackedAttributeSet[inst] = true
    table.insert(TrackedAttributes, entry)

    -- Event-driven attributes remove the expensive full-table polling loop for
    -- most tracked objects. A slower audit remains as a fallback.
    local ok, conn = pcall(function()
        return inst.AttributeChanged:Connect(function(attributeName)
            if not Session.TestsRunning or Session.StopRequested then return end
            emitAttributeChange(entry, tostring(attributeName), "attributes_changed")
        end)
    end)

    if ok and conn then
        entry.eventDriven = true
        table.insert(ObserverConnections, conn)
    end
end

local function dynamicSignature(inst)
    local parentName = inst.Parent and inst.Parent.Name or ""
    return table.concat({inst.ClassName, inst.Name, parentName}, "|")
end

local function recordObjectPulse(kind, inst)
    local rel = relevanceOf(inst)
    local sig = kind .. "|" .. dynamicSignature(inst)
    local n = (DynamicPathCounts[sig] or 0) + 1
    DynamicPathCounts[sig] = n

    local firstLimit = rel >= 80 and 8 or 3
    local stride = rel >= 80 and 10 or 25
    if n > firstLimit and n % stride ~= 0 then
        return
    end

    recordDynamic({
        source="tests",
        kind=kind,
        path=safePath(inst),
        className=inst.ClassName,
        name=inst.Name,
        signature=sig,
        occurrence=n,
        relevance=rel,
    })
end

local function connectRootSignals(root)
    if not root or RootSignalSet[root] then return end
    RootSignalSet[root] = true

    local addConn = root.DescendantAdded:Connect(function(inst)
        if not Session.TestsRunning or Session.StopRequested then return end
        if not isRelevantDynamic(inst) then return end

        recordObjectPulse("object_created", inst)

        if inst:IsA("ValueBase") then
            addTrackedValue(inst)
        end

        if inst:IsA("Humanoid") then
            observeHumanoid(inst)
        end

        addTrackedAttributes(inst)

        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
            observeRemote(inst)
        end
    end)

    local remConn = root.DescendantRemoving:Connect(function(inst)
        if not Session.TestsRunning or Session.StopRequested then return end
        if not isRelevantDynamic(inst) then return end

        recordObjectPulse("object_removed", inst)
    end)

    table.insert(ObserverConnections, addConn)
    table.insert(ObserverConnections, remConn)
end

local function inventoryRoot(root)
    local descendants = root:GetDescendants()
    local valueCandidates = {}
    local attrCandidates = {}
    local remoteCandidates = {}

    for i, inst in ipairs(descendants) do
        if Session.StopRequested then break end

        local rel = relevanceOf(inst)

        if inst:IsA("Humanoid") then
            observeHumanoid(inst)
        end

        if inst:IsA("ValueBase")
            and not isIgnoredDynamicValue(inst)
            and rel >= 35
            and not TrackedValueSet[inst] then
            table.insert(valueCandidates, {inst=inst, score=rel})
        end

        if rel >= 30 and not TrackedAttributeSet[inst] then
            local ok, attrs = pcall(function() return inst:GetAttributes() end)
            if ok and next(attrs) ~= nil then
                table.insert(attrCandidates, {inst=inst, score=rel})
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
end

local function seedFastWatchSet()
    local roots = getFastRoots(GENERIC_FAST_PATHS, true)
    local seen = setmetatable({}, {__mode="k"})
    local inspected = 0

    local function seed(inst)
        if not inst or seen[inst] then return end
        seen[inst] = true

        local rel = relevanceOf(inst)
        if inst:IsA("ValueBase") and rel >= 35 then
            addTrackedValue(inst)
        end
        if inst:IsA("Humanoid") then
            observeHumanoid(inst)
        end
        if rel >= 30 then
            addTrackedAttributes(inst)
        end
        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
            observeRemote(inst)
        end
        FastSeededObjects += 1
    end

    for _, root in ipairs(roots) do
        seed(root)
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, inst in ipairs(descendants) do
                if Session.StopRequested then break end
                seed(inst)
                inspected += 1
                if inspected % CONFIG.SCAN_YIELD_EVERY == 0 then
                    task.wait()
                end
            end
        end
        if Session.StopRequested then break end
    end

    return #roots
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
        optimization="UNIVERSAL_SMART_COMPACT_1",
        roots={"ReplicatedStorage","Players","Workspace"},
    })

    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
        game:GetService("Workspace"),
    }

    -- Connect creation/removal listeners immediately so the inventory pass can
    -- never create a blind window.
    for _, root in ipairs(roots) do
        if Session.StopRequested then break end
        pcall(connectRootSignals, root)
    end

    -- Seed automatically discovered high-value systems before inventorying every
    -- descendant. This avoids a long blind period on large games.
    local fastRootCount = 0
    if not Session.StopRequested then
        local ok, count = pcall(seedFastWatchSet)
        if ok then fastRootCount = count or 0 end
    end

    acceptRecord({
        source="session",
        kind="adaptive_watch_ready",
        roots=fastRootCount,
        seededObjects=FastSeededObjects,
        trackedValues=#TrackedValues,
        trackedAttributes=#TrackedAttributes,
        trackedRemotes=ObservedRemoteCount,
    })

    for _, root in ipairs(roots) do
        if Session.StopRequested then break end
        pcall(inventoryRoot, root)
        task.wait()
    end

    acceptRecord({
        source="session",
        kind="watch_set_ready",
        trackedValues=#TrackedValues,
        trackedAttributes=#TrackedAttributes,
        trackedRemotes=ObservedRemoteCount,
        adaptiveSeededObjects=FastSeededObjects,
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
        local doAudit = cycle % CONFIG.ATTRIBUTE_AUDIT_EVERY_CYCLES == 0

        for attrIndex, entry in ipairs(TrackedAttributes) do
            if Session.StopRequested then break end

            -- Event-driven entries only need an occasional integrity audit.
            if not entry.eventDriven or doAudit then
                emitAttributeChange(
                    entry,
                    nil,
                    entry.eventDriven and "attributes_audit_changed" or "attributes_changed"
                )
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
                trackedValues=#TrackedValues,
                trackedAttributes=#TrackedAttributes,
                trackedRemotes=ObservedRemoteCount,
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
    ObservedHumanoidSet = setmetatable({}, {__mode="k"})
    table.clear(DynamicSignatures)
    table.clear(RemoteAggregates)
    table.clear(DynamicPathCounts)
    ScannedInstanceSet = setmetatable({}, {__mode="k"})
    RootSignalSet = setmetatable({}, {__mode="k"})

    DynamicEvents = 0
    ObservedRemoteCount = 0
    FastSeededObjects = 0

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
    if not Archive.Persistent and type(env[MEMORY_ARCHIVE_KEY]) == "table" then
        env[MEMORY_ARCHIVE_KEY].sessions = Archive.Sessions
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
        optimization="UNIVERSAL_SMART_COMPACT_1",
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

    UIState.overrideStatus = nil
    UIState.overrideDetail = nil
    Flow.Mode = "collecting"
    ActionButton.Text = "ENCERRAR"
    ActionButton.BackgroundColor3 = COLORS.RED
    StatusLabel.Text = "Coletando • Scan + Test Lab"

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

        Flow.Mode = "idle"
        ActionButton.Text = "INICIAR TUDO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON

        -- visual-only reset, archive remains preserved
        Session.EstimatedBytes = 2
        Session.ObjectsScanned = 0
        Session.ServicesDone = 0
        Session.VisualStatsCleared = true

        setUiMessage("Parado • dados preservados", string.format("%.2f MB arquivados", mb(Archive.Bytes)))
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
    local lastError = "request_failed"

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

            local serverMessage = nil
            if type(raw) == "string" and #raw > 0 then
                pcall(function()
                    local decodedError = HttpService:JSONDecode(raw)
                    if type(decodedError) == "table" then
                        serverMessage = decodedError.error or decodedError.message
                    end
                end)
            end

            if status then
                lastError = "HTTP " .. tostring(status)
                if serverMessage then
                    lastError = lastError .. " • " .. tostring(serverMessage)
                end
            elseif type(raw) == "string" and #raw > 0 then
                lastError = tostring(raw):sub(1, 180)
            end
        else
            lastError = "request_error • " .. tostring(resp):sub(1, 160)
        end

        if attempt < CONFIG.HTTP_RETRIES then
            task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
        end
    end

    return false, nil, lastError
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
            build="UNIVERSAL_SMART_PASSIVE_2_UPLOAD_FIX",
            clientVisibleOnly=true,
            placeId=game.PlaceId,
            gameId=game.GameId,
            placeVersion=game.PlaceVersion,
            archivedBytesApprox=Archive.Bytes,
            archivedRecordCount=Archive.Records,
            persistent=Archive.Persistent,
            archiveScope="placeId",
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

local function decodeArchiveObject(line)
    local ok, object = pcall(function()
        return HttpService:JSONDecode(line)
    end)
    if ok and type(object) == "table" then
        return object
    end
    return nil
end

local function precalculateUpload()
    local totalChunks = 0
    local totalBytes = 0
    local currentBytes = 2 -- []
    local currentObjects = 0

    eachUploadLine(function(line)
        -- Fast pre-count: archived lines were JSON-encoded when written. Actual
        -- decoding is done once during streaming, avoiding a double parse pass.
        local add = #line + (currentObjects > 0 and 1 or 0)
        if currentObjects > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            totalChunks += 1
            totalBytes += currentBytes
            currentBytes = 2 + #line
            currentObjects = 1
        else
            currentBytes += add
            currentObjects += 1
        end
    end)

    if currentObjects > 0 then
        totalChunks += 1
        totalBytes += currentBytes
    end

    return totalChunks, totalBytes
end

local function streamUploadChunks(callback)
    local current = {}
    local currentBytes = 2 -- []

    local function flush()
        if #current == 0 then return true end

        local payload = current
        current = {}
        currentBytes = 2

        -- The backend expects `objects` to be a JSON array. Re-encode the exact
        -- array here only to measure the bytes shown in upload progress.
        local encoded = safeJson(payload)
        return callback(payload, #encoded) ~= false
    end

    local stopped = false
    eachUploadLine(function(line)
        if stopped then return false end

        local object = decodeArchiveObject(line)
        if not object then
            stopped = true
            return false
        end

        local add = #line + (#current > 0 and 1 or 0)
        if #current > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            if not flush() then
                stopped = true
                return false
            end
            add = #line
        end

        table.insert(current, object)
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
        if ISFILE(CONFIG.MANIFEST_BACKUP_PATH) then
            pcall(DELFILE, CONFIG.MANIFEST_BACKUP_PATH)
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
        env[MEMORY_ARCHIVE_KEY] = {
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
        Flow.Mode = "idle"
        ActionButton.Text = "INICIAR TUDO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        setUiMessage("Nada arquivado para enviar", "A coleta pode ser iniciada novamente")
        updateUI(true)
        return
    end

    Flow.Mode = "uploading"
    ActionButton.Text = "ENVIANDO..."
    ActionButton.BackgroundColor3 = COLORS.RED_DARK

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
        ActionButton.Text = "REENVIAR ARQUIVO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        setUiMessage("Falha ao preparar upload", string.format("%.2f MB continuam arquivados", mb(Archive.Bytes)))
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
    local startOk, startData, startErr = httpPostJson(
        CONFIG.UPLOAD_BASE .. "/start",
        {
            filename=fileName,
            source=CONFIG.VERSION,
            metadata={
                scanner=CONFIG.VERSION,
                placeId=game.PlaceId,
                gameId=game.GameId,
                placeVersion=game.PlaceVersion,
                clientVisibleOnly=true,
                persistent=Archive.Persistent,
            },
        },
        "Abrindo upload"
    )

    if not startOk then
        UploadPanel.status.Text = "Erro ao abrir upload • arquivo preservado"
        Upload.Running = false
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        ActionButton.Text = "REENVIAR ARQUIVO"
        setUiMessage("Erro ao abrir upload", tostring(startErr or "arquivo preservado"):sub(1, 180))
        updateUI(true)
        return
    end

    Upload.UploadId =
        type(startData) == "table"
        and (startData.uploadId or startData.id or startData.upload_id)
        or nil

    if not Upload.UploadId then
        UploadPanel.status.Text = "Resposta /start inválida • arquivo preservado"
        Upload.Running = false
        ActionButton.Text = "INICIAR TUDO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        ActionButton.Text = "REENVIAR ARQUIVO"
        setUiMessage("Resposta /start inválida", string.format("%.2f MB continuam arquivados", mb(Archive.Bytes)))
        updateUI(true)
        return
    end

    local streamIndex = 0
    local streamFailed = false

    local streamOk = streamUploadChunks(function(objects, chunkBytes)
        if Upload.CancelRequested then
            streamFailed = true
            return false
        end

        streamIndex += 1
        local i = streamIndex
        Upload.CurrentChunk = i
        UploadPanel.status.Text = string.format("Enviando chunk %d/%d", i, Upload.TotalChunks)
        updateUI(true)

        -- Current backend contract: /upload/chunk requires uploadId, index and
        -- `objects` as an actual JSON array (not a JSONL string).
        local chunkOk, _, chunkErr = httpPostJson(
            CONFIG.UPLOAD_BASE .. "/chunk",
            {
                uploadId=Upload.UploadId,
                index=i,
                objects=objects,
            },
            string.format("Chunk %d/%d", i, Upload.TotalChunks)
        )

        if not chunkOk then
            Upload.LastError = chunkErr
            streamFailed = true
            return false
        end

        Upload.ChunksSent += 1
        Upload.BytesSent += chunkBytes
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
        ActionButton.Text = "REENVIAR ARQUIVO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        setUiMessage("Erro no envio • arquivo preservado", tostring(Upload.LastError or "falha no chunk"):sub(1, 180))
        updateUI(true)
        return
    end

    if Upload.ChunksSent ~= Upload.TotalChunks then
        requestCancelUpload()
        UploadPanel.status.Text = "Integridade falhou • arquivo preservado"
        Upload.Running = false
        ActionButton.Text = "REENVIAR ARQUIVO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        setUiMessage("Integridade de chunks falhou", string.format("%.2f MB continuam arquivados", mb(Archive.Bytes)))
        updateUI(true)
        return
    end

    UploadPanel.status.Text = "Confirmando /finish..."
    updateUI()

    local finishOk, finishData, finishErr = httpPostJson(
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
        ActionButton.Text = "REENVIAR ARQUIVO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        setUiMessage("Finalização falhou • arquivo preservado", tostring(finishErr or "falha no /finish"):sub(1, 180))
        updateUI(true)
        return
    end

    local confirmed = false
    if type(finishData) == "table" then
        if finishData.confirmed == true
            or finishData.success == true
            or finishData.ok == true then
            confirmed = true
        end
    end

    if not confirmed then
        UploadPanel.status.Text = "Integridade falhou • arquivo preservado"
        Upload.Running = false
        ActionButton.Text = "REENVIAR ARQUIVO"
        ActionButton.BackgroundColor3 = COLORS.BUTTON
        Flow.Mode = "retry"
        setUiMessage("Servidor não confirmou integridade", string.format("%.2f MB continuam arquivados", mb(Archive.Bytes)))
        updateUI(true)
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
    Flow.Mode = "idle"
    ActionButton.Text = "INICIAR TUDO"
    ActionButton.BackgroundColor3 = COLORS.BUTTON
    setUiMessage("Upload concluído", "Servidor confirmou • archive local limpo")
    setBar(1, true)
    updateUI(true)
end

--==============================================================--
-- BUTTONS
--==============================================================--

requestStopAndUpload = function(reason)
    if Flow.FinalizerRunning then return end
    if not Session.Running and not Session.ScanRunning and not Session.TestsRunning then
        return
    end

    Flow.FinalizerRunning = true
    Flow.Mode = "finalizing"
    Session.StopRequested = true
    Session.StopReason = reason or "manual_stop"
    ActionButton.Text = "ENCERRANDO..."
    ActionButton.BackgroundColor3 = COLORS.RED_DARK

    acceptRecord({
        source="session",
        kind="stop_requested",
        reason=Session.StopReason,
        automaticUpload=true,
    })

    ManifestState.dirty = true
    saveManifest(true)
    updateUI(true)

    task.spawn(function()
        -- Do not race the archive writers: only start upload after scan/tests exit.
        while Session.ScanRunning or Session.TestsRunning do
            updateUI()
            task.wait(0.05)
        end

        stopObservers()
        Session.ScanRunning = false
        Session.TestsRunning = false
        Session.ObserversRunning = false

        if Session.StopReason ~= "size_limit" then
            acceptRecord({
                source="session",
                kind="session_finalized",
                reason=Session.StopReason,
                records=Session.RecordCount,
                objects=Session.ObjectsScanned,
                archivedRecords=Archive.Records,
                archivedBytes=Archive.Bytes,
            })
        end

        ManifestState.dirty = true
        saveManifest(true)
        Session.Running = false
        Flow.FinalizerRunning = false

        if Archive.Records > 0 then
            Flow.Mode = "uploading"
            ActionButton.Text = "ENVIANDO..."
            ActionButton.BackgroundColor3 = COLORS.RED_DARK
            updateUI(true)
            task.wait(0.10)
            uploadAll()
        else
            Flow.Mode = "idle"
            ActionButton.Text = "INICIAR TUDO"
            ActionButton.BackgroundColor3 = COLORS.BUTTON
            updateUI(true)
        end
    end)
end

ActionButton.Activated:Connect(function()
    if Flow.Mode == "retry" then
        task.spawn(uploadAll)
        return
    end

    if Flow.Mode == "idle" then
        beginSession("scan_and_tests")
        return
    end

    if Flow.Mode == "collecting" then
        requestStopAndUpload("manual_stop")
        return
    end

    -- finalizing/uploading are intentionally locked to protect archive integrity.
end)

--==============================================================--
-- INITIAL LOAD
--==============================================================--

loadArchive()

if Archive.Records > 0 then
    Flow.Mode = "retry"
    ActionButton.Text = "REENVIAR ARQUIVO"
    ActionButton.BackgroundColor3 = COLORS.BUTTON
    setUiMessage(
        "Arquivo anterior recuperado",
        string.format("%.2f MB preservados • toque para reenviar", mb(Archive.Bytes))
    )
end
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

local Controller = {
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

pcall(function()
    local previous = rawget(env, "__CAFEINA_MAPPING_V16_CONTROLLER")
        or rawget(env, "__CAFEINA_MAPPING_V15_CONTROLLER")
        or rawget(env, "__CAFEINA_MAPPING_V14_CONTROLLER")
    if type(previous) == "table" and previous.Gui and previous.Gui ~= Gui
        and type(previous.Stop) == "function" then
        previous.Stop("replaced_by_new_instance")
    end
end)

env.__CAFEINA_MAPPING_V16_CONTROLLER = Controller
-- Compatibility aliases so older loaders can close this instance.
env.__CAFEINA_MAPPING_V15_CONTROLLER = Controller
env.__CAFEINA_MAPPING_V14_CONTROLLER = Controller

--==============================================================--
-- END
--==============================================================--
