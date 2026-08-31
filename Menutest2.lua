--==============================================================--
-- CAFEÍNA • SECURITY FUSION COLLECTOR V3.1
-- COMPLETE BUILD • MOBILE / EXECUTOR • CLIENT-VISIBLE AUDIT
--
-- MAIN GUARANTEES
-- • Persistent local archive is the source of truth.
-- • Records are never deleted because of HTTP/start/chunk/finish failures.
-- • Recovered archives are automatically retried when the collector is idle.
-- • Local deletion happens only after explicit /finish confirmation.
-- • A local confirmation receipt prevents duplicate re-upload after a crash
--   between server confirmation and local cleanup.
-- • Manifest backup + block probing recovers from stale/corrupt manifests.
-- • Write lock prevents concurrent flushes from corrupting the archive.
--
-- ACTIVE TEST POLICY
-- • No generic fuzzing.
-- • No destructive/economy/combat/admin/inventory mutation probes.
-- • Optional active probes are restricted to exact allowlisted no-argument
--   RemoteFunctions that were already observed being called legitimately.
--
-- IMPORTANT
-- Run only in games/environments you are authorized to test.
--==============================================================--

--==============================================================--
-- SERVICES
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local ARCHIVE_ROOT = "CafeinaSecurityFusion"
local ARCHIVE_FOLDER = ARCHIVE_ROOT .. "/" .. tostring(game.PlaceId)

local CONFIG = {
    VERSION = "SECURITY_FUSION_COLLECTOR_V3_1",
    GUI_NAME = "CafeinaSecurityFusionCollectorV31",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    ARCHIVE_ROOT = ARCHIVE_ROOT,
    ARCHIVE_FOLDER = ARCHIVE_FOLDER,
    MANIFEST_PATH = ARCHIVE_FOLDER .. "/manifest.json",
    MANIFEST_BACKUP_PATH = ARCHIVE_FOLDER .. "/manifest.bak.json",
    RECEIPT_PATH = ARCHIVE_FOLDER .. "/upload_receipt.json",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 500000,

    -- Durability. With appendfile available, each record is written through.
    -- Without appendfile, records are still flushed aggressively with a lock.
    WRITE_THROUGH_WHEN_APPEND_AVAILABLE = true,
    FLUSH_INTERVAL = 0.15,
    FLUSH_AT_BYTES = 24 * 1024,

    MAX_RECORD_JSON_BYTES = 256 * 1024,
    MAX_SERIALIZE_DEPTH = 6,
    MAX_TABLE_ITEMS = 120,
    MAX_STRING_BYTES = 12000,

    SERVICE_BUDGETS = {
        ReplicatedStorage = 28000,
        Workspace = 24000,
        Players = 10000,
        ReplicatedFirst = 7000,
        StarterGui = 10000,
        StarterPlayer = 8000,
        SoundService = 3000,
        Lighting = 3000,
    },

    CLASS_SKIP = {
        Pose = true,
        Keyframe = true,
    },

    CLASS_SAMPLE_LIMIT = {
        Texture = 120,
        Decal = 120,
        SurfaceAppearance = 100,
        ParticleEmitter = 160,
        Trail = 100,
        Beam = 100,
        Attachment = 650,
        Motor6D = 900,
        UIGradient = 500,
        UIStroke = 500,
    },

    VALUE_WATCH_LIMIT = 8000,
    ATTRIBUTE_WATCH_LIMIT = 8000,
    REMOTE_WATCH_LIMIT = 5000,
    ENTITY_LIMIT = 12000,

    CORRELATION_WINDOW_SECONDS = 5.0,
    RECENT_EVENT_LIMIT = 140,

    UI_REFRESH_SECONDS = 0.18,
    HEALTH_HEARTBEAT_INTERVAL = 8.0,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.1,

    AUTO_UPLOAD_ENABLED = true,
    AUTO_UPLOAD_START_DELAY = 1.5,
    AUTO_UPLOAD_RETRY_SECONDS = 12,

    ACTIVE_PROBES_ENABLED = true,
    ACTIVE_PROBE_DELAY = 0.65,
    ACTIVE_PROBE_LIMIT = 30,

    ACTIVE_NOARG_ALLOWLIST = {
        ["Treadmill/AskWearStill"] = true,
        ["Treadmill/AskDoff"] = true,
    },

    SENSITIVE_KEYWORDS = {
        "speed", "speedpower", "money", "cash", "coin", "gem",
        "profile", "delta", "inventory", "item", "gear", "egg",
        "reward", "claim", "award", "grant", "give", "purchase",
        "buy", "sell", "trade", "teleport", "damage", "hit",
        "kill", "admin", "save", "load", "data", "stats", "level",
        "xp", "prestige", "rebirth", "treadmill", "capture",
        "ownership", "owner", "permission", "role", "rank",
        "prompt", "quest", "shop", "currency", "upgrade",
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

local function pickFunction(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then
            return v
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

local httpTableRequest
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
local LISTFILES = pickFunction(rawget(env, "listfiles"))

local HOOKMETAMETHOD = pickFunction(rawget(env, "hookmetamethod"))
local GETNAMECALLMETHOD = pickFunction(rawget(env, "getnamecallmethod"))
local NEWCCLOSURE = pickFunction(rawget(env, "newcclosure"))
local CHECKCALLER = pickFunction(rawget(env, "checkcaller"))

-- Persistence intentionally does not require delfile or isfolder.
local FILESYSTEM_OK = WRITEFILE and READFILE and ISFILE and MAKEFOLDER
local FILE_DELETE_OK = DELFILE ~= nil

-- Stop the previous collector instance, but never delete its archive.
pcall(function()
    local previous = rawget(env, "__CAFEINA_SECURITY_FUSION_CONTROLLER")
    if type(previous) == "table" and type(previous.Stop) == "function" then
        previous.Stop("replaced")
    end
end)

--==============================================================--
-- SMALL HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function clamp(n, a, b)
    if n < a then return a end
    if n > b then return b end
    return n
end

local function mb(bytes)
    return (bytes or 0) / (1024 * 1024)
end

local function isoUTC()
    local t = os.date("!*t")
    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        t.year, t.month, t.day,
        t.hour, t.min, t.sec
    )
end

local function newRunId()
    local ok, value = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    if ok and value then
        return value
    end
    return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

local function truncateString(s, maxBytes)
    if type(s) ~= "string" then
        return s
    end
    local limit = maxBytes or CONFIG.MAX_STRING_BYTES
    if #s <= limit then
        return s
    end
    return string.sub(s, 1, limit) .. string.format("<truncated:%d>", #s)
end

local function safeJson(value)
    local ok, result = pcall(HttpService.JSONEncode, HttpService, value)
    if ok then
        return result
    end
    local fallbackOk, fallback = pcall(HttpService.JSONEncode, HttpService, {
        kind = "json_encode_error",
        error = truncateString(tostring(result), 4000),
    })
    return fallbackOk and fallback or "{\"kind\":\"json_encode_error\"}"
end

local function safeInstanceInfo(inst)
    local out = {type = "Instance"}

    local okName, name = pcall(function()
        return inst.Name
    end)
    if okName then out.name = name else out.name = tostring(inst) end

    local okClass, className = pcall(function()
        return inst.ClassName
    end)
    if okClass then out.className = className end

    local okPath, path = pcall(function()
        return inst:GetFullName()
    end)
    if okPath then out.path = path end

    local okParent, parent = pcall(function()
        return inst.Parent
    end)
    if okParent and parent then
        local parentOk, parentName = pcall(function()
            return parent.Name
        end)
        if parentOk then out.parent = parentName end
    end

    return out
end

local function safePath(inst)
    local info = safeInstanceInfo(inst)
    return info.path or info.name or tostring(inst)
end

local function safeClass(inst)
    local ok, className = pcall(function()
        return inst.ClassName
    end)
    return ok and className or "Unknown"
end

local function safeName(inst)
    local ok, name = pcall(function()
        return inst.Name
    end)
    return ok and name or tostring(inst)
end

--==============================================================--
-- SERIALIZER
--==============================================================--

local function safeSerialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > CONFIG.MAX_SERIALIZE_DEPTH then
        return "<max_depth>"
    end

    if value == nil then
        return nil
    end

    local tv
    local okType, typeResult = pcall(typeof, value)
    tv = okType and typeResult or type(value)

    if tv == "string" then
        return truncateString(value)
    elseif tv == "boolean" then
        return value
    elseif tv == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    elseif tv == "Vector3" then
        return {type="Vector3", x=value.X, y=value.Y, z=value.Z}
    elseif tv == "Vector2" then
        return {type="Vector2", x=value.X, y=value.Y}
    elseif tv == "CFrame" then
        local ok, p = pcall(function() return value.Position end)
        if ok then
            return {type="CFrame", x=p.X, y=p.Y, z=p.Z}
        end
        return tostring(value)
    elseif tv == "Color3" then
        return {type="Color3", r=value.R, g=value.G, b=value.B}
    elseif tv == "BrickColor" or tv == "EnumItem" then
        return tostring(value)
    elseif tv == "Instance" then
        return safeInstanceInfo(value)
    elseif tv == "table" then
        if seen[value] then
            return "<cycle>"
        end
        seen[value] = true

        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count += 1
            if count > CONFIG.MAX_TABLE_ITEMS then
                out["<truncated>"] = true
                break
            end
            out[tostring(k)] = safeSerialize(v, depth + 1, seen)
        end

        seen[value] = nil
        return out
    end

    local okToString, text = pcall(tostring, value)
    return truncateString(okToString and text or "<unserializable>")
end

local function serializePacked(packed)
    local n = packed.n or #packed
    local values = {}
    local types = {}

    for i = 1, n do
        local v = packed[i]
        values[i] = safeSerialize(v)
        local ok, t = pcall(typeof, v)
        types[i] = ok and t or type(v)
    end

    return {
        count = n,
        types = types,
        values = values,
    }
end

local function signatureOfPacked(packed)
    local n = packed.n or #packed
    local parts = {}
    for i = 1, n do
        local ok, t = pcall(typeof, packed[i])
        parts[i] = ok and t or type(packed[i])
    end
    return table.concat(parts, "|")
end

--==============================================================--
-- STATE
--==============================================================--

local Session = {
    Running = false,
    StopRequested = false,
    RunId = nil,
    StartedClock = 0,
    RecordsThisRun = 0,
    MappingDone = false,
    CurrentService = "idle",

    RemoteCount = 0,
    SensitiveRemoteCount = 0,
    InboundWatchCount = 0,
    EntityCount = 0,
    ValueWatchCount = 0,
    AttributeWatchCount = 0,
    DynamicEvents = 0,

    ActiveProbeRunning = false,
    ActiveProbes = 0,

    LastOutbound = nil,
    LastInbound = nil,
    RecentEvents = {},

    LastHealthHeartbeat = 0,
    ErrorCount = 0,
    DroppedOversizeRecords = 0,
}

local Archive = {
    Persistent = FILESYSTEM_OK and true or false,
    Generation = newRunId(),
    Blocks = {},
    CurrentBlock = 1,
    CurrentBlockBytes = 0,
    Bytes = 0,
    Records = 0,

    PendingLines = {},
    PendingBytes = 0,
    MemoryLines = {},

    FlushLock = false,
    LastFlushError = nil,
    RecoveryPerformed = false,
    InvalidRecoveredLines = 0,
}

local Upload = {
    Running = false,
    UploadId = nil,
    CurrentChunk = 0,
    TotalChunks = 0,
    BytesSent = 0,
    TotalBytes = 0,
    LastURL = "",
    LastError = nil,

    Attempt = 0,
    ConsecutiveFailures = 0,
    NextRetryAt = 0,
    PendingRecovered = false,
}

local Connections = {}
local DynamicConnections = {}
local RemoteInfo = setmetatable({}, {__mode="k"})
local RemoteCounted = setmetatable({}, {__mode="k"})
local InboundObserved = setmetatable({}, {__mode="k"})
local ValueObserved = setmetatable({}, {__mode="k"})
local AttributeObserved = setmetatable({}, {__mode="k"})
local EntityObserved = setmetatable({}, {__mode="k"})

local OriginalNamecall
local HookInstalled = false

local updateUI
local queueRecord
local uploadAll
local disconnectDynamic

-- UI refs are assigned later.
local Gui
local Main
local MiniButton
local Action
local RetryButton
local Status
local Detail
local BarFill
local PersistDot
local HttpDot

--==============================================================--
-- SAFE CALLBACK WRAPPER
--==============================================================--

local function relativeTime()
    if Session.StartedClock == 0 then
        return 0
    end
    return os.clock() - Session.StartedClock
end

local function recordError(where, err)
    Session.ErrorCount += 1
    if queueRecord and Session.Running then
        queueRecord({
            source = "diagnostic",
            kind = "caught_error",
            where = tostring(where),
            error = truncateString(tostring(err), 6000),
        })
    end
end

local function guarded(where, fn, ...)
    local args = table.pack(...)
    local ok, a, b, c, d = xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        local message = tostring(err)
        if debug and type(debug.traceback) == "function" then
            local traceOk, trace = pcall(debug.traceback, message, 2)
            if traceOk then return trace end
        end
        return message
    end)

    if not ok then
        recordError(where, a)
        return false, a
    end

    return true, a, b, c, d
end

--==============================================================--
-- RECENT EVENT / CORRELATION BUFFER
--==============================================================--

local function pushRecent(item)
    item.time = item.time or relativeTime()
    table.insert(Session.RecentEvents, item)

    while #Session.RecentEvents > CONFIG.RECENT_EVENT_LIMIT do
        table.remove(Session.RecentEvents, 1)
    end

    local cutoff = relativeTime() - CONFIG.CORRELATION_WINDOW_SECONDS
    while #Session.RecentEvents > 0 do
        local first = Session.RecentEvents[1]
        if (first.time or 0) < cutoff then
            table.remove(Session.RecentEvents, 1)
        else
            break
        end
    end
end

local function recentSnapshot()
    local out = {}
    for i, item in ipairs(Session.RecentEvents) do
        out[i] = safeSerialize(item)
    end
    return out
end

--==============================================================--
-- ARCHIVE / DURABILITY
--==============================================================--

local function blockPath(index)
    return string.format("%s/block_%06d.jsonl", CONFIG.ARCHIVE_FOLDER, index)
end

local function ensureFolder(path)
    if not FILESYSTEM_OK then
        return false
    end

    local ok = pcall(function()
        if ISFOLDER then
            if not ISFOLDER(path) then
                MAKEFOLDER(path)
            end
        else
            pcall(MAKEFOLDER, path)
        end
    end)

    return ok
end

local function safeDeleteOrEmpty(path)
    if not FILESYSTEM_OK then
        return false
    end

    local existsOk, exists = pcall(ISFILE, path)
    if not existsOk or not exists then
        return true
    end

    if FILE_DELETE_OK then
        local ok = pcall(DELFILE, path)
        if ok then
            local checkOk, stillExists = pcall(ISFILE, path)
            if checkOk and not stillExists then
                return true
            end
        end
    end

    local ok = pcall(WRITEFILE, path, "")
    return ok
end

local function readJsonFile(path)
    if not FILESYSTEM_OK then
        return nil
    end

    local existsOk, exists = pcall(ISFILE, path)
    if not existsOk or not exists then
        return nil
    end

    local ok, text = pcall(READFILE, path)
    if not ok or type(text) ~= "string" or #text == 0 then
        return nil
    end

    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
    if decodeOk and type(data) == "table" then
        return data
    end

    return nil
end

local function appendText(path, text)
    if APPENDFILE then
        return pcall(APPENDFILE, path, text)
    end

    local old = ""
    local existsOk, exists = pcall(ISFILE, path)
    if existsOk and exists then
        local ok, value = pcall(READFILE, path)
        if ok and type(value) == "string" then
            old = value
        end
    end

    return pcall(WRITEFILE, path, old .. text)
end

local function writeManifest()
    if not FILESYSTEM_OK then
        return false
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local data = {
        version = CONFIG.VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = Session.RunId,
        generation = Archive.Generation,
        blocks = Archive.Blocks,
        currentBlock = Archive.CurrentBlock,
        currentBlockBytes = Archive.CurrentBlockBytes,
        bytes = Archive.Bytes,
        records = Archive.Records,
        pendingBytes = Archive.PendingBytes,
        pendingUpload = Archive.Records > 0,
        uploadId = Upload.UploadId,
        uploadAttempt = Upload.Attempt,
        updatedAt = os.time(),
    }

    local encoded = safeJson(data)

    -- Primary -> backup before replacement.
    pcall(function()
        if ISFILE(CONFIG.MANIFEST_PATH) then
            local old = READFILE(CONFIG.MANIFEST_PATH)
            if type(old) == "string" and #old > 0 then
                WRITEFILE(CONFIG.MANIFEST_BACKUP_PATH, old)
            end
        end
    end)

    local ok = pcall(WRITEFILE, CONFIG.MANIFEST_PATH, encoded)
    return ok
end

local function discoverBlocks()
    local blocks = {}

    if not FILESYSTEM_OK then
        return blocks
    end

    -- Prefer listfiles when available because it tolerates gaps.
    if LISTFILES then
        local ok, files = pcall(LISTFILES, CONFIG.ARCHIVE_FOLDER)
        if ok and type(files) == "table" then
            local indexed = {}
            for _, path in ipairs(files) do
                local normalized = tostring(path):gsub("\\", "/")
                local idx = tonumber(string.match(normalized, "block_(%d+)%.jsonl$"))
                if idx then
                    indexed[idx] = blockPath(idx)
                end
            end

            local ids = {}
            for idx in pairs(indexed) do
                table.insert(ids, idx)
            end
            table.sort(ids)

            for _, idx in ipairs(ids) do
                table.insert(blocks, indexed[idx])
            end

            if #blocks > 0 then
                return blocks
            end
        end
    end

    -- Fallback sequential probe. Continue across a few misses.
    local misses = 0
    local foundAny = false

    for i = 1, 200000 do
        local path = blockPath(i)
        local ok, exists = pcall(ISFILE, path)
        if ok and exists then
            foundAny = true
            misses = 0
            table.insert(blocks, path)
        else
            misses += 1
            if foundAny and misses >= 3 then
                break
            end
            if not foundAny and i >= 32 then
                break
            end
        end
    end

    return blocks
end

local function recountArchive()
    if not FILESYSTEM_OK then
        return
    end

    local bytes = 0
    local records = 0
    local valid = {}
    local lastBytes = 0
    local invalid = 0

    for _, path in ipairs(Archive.Blocks) do
        local existsOk, exists = pcall(ISFILE, path)
        if existsOk and exists then
            local ok, text = pcall(READFILE, path)
            if ok and type(text) == "string" and #text > 0 then
                table.insert(valid, path)
                bytes += #text
                lastBytes = #text

                for line in string.gmatch(text, "[^\r\n]+") do
                    local decodeOk = pcall(HttpService.JSONDecode, HttpService, line)
                    records += 1
                    if not decodeOk then
                        invalid += 1
                    end
                end
            end
        end
    end

    Archive.Blocks = valid
    Archive.Bytes = bytes + Archive.PendingBytes
    Archive.Records = records + #Archive.PendingLines
    Archive.InvalidRecoveredLines = invalid
    Archive.CurrentBlock = math.max(1, #valid)
    Archive.CurrentBlockBytes = (#valid > 0) and lastBytes or 0

    if #Archive.Blocks == 0 then
        Archive.Blocks = {blockPath(1)}
        Archive.CurrentBlock = 1
        Archive.CurrentBlockBytes = 0
    end
end

local function cleanupConfirmedLeftovers(receipt)
    if not FILESYSTEM_OK or type(receipt) ~= "table" or receipt.confirmed ~= true then
        return false
    end

    local manifest = readJsonFile(CONFIG.MANIFEST_PATH)

    -- Never let an old receipt delete a newer archive generation.
    if manifest
    and receipt.generation
    and manifest.generation
    and tostring(receipt.generation) ~= tostring(manifest.generation)
    then
        return false
    end

    local blocks = type(receipt.blocks) == "table" and receipt.blocks or {}
    local allClean = true

    for _, path in ipairs(blocks) do
        if not safeDeleteOrEmpty(path) then
            allClean = false
        end
    end

    if allClean then
        safeDeleteOrEmpty(CONFIG.MANIFEST_PATH)
        safeDeleteOrEmpty(CONFIG.MANIFEST_BACKUP_PATH)
        safeDeleteOrEmpty(CONFIG.RECEIPT_PATH)
    end

    return allClean
end

local function loadArchive()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    -- Finish a previously-confirmed cleanup before rebuilding the archive.
    local receipt = readJsonFile(CONFIG.RECEIPT_PATH)
    if receipt and receipt.confirmed == true then
        cleanupConfirmedLeftovers(receipt)
    end

    local manifest = readJsonFile(CONFIG.MANIFEST_PATH)
        or readJsonFile(CONFIG.MANIFEST_BACKUP_PATH)

    if manifest then
        Archive.Generation = tostring(manifest.generation or Archive.Generation or newRunId())
        Archive.Blocks = type(manifest.blocks) == "table" and manifest.blocks or {}
        Archive.CurrentBlock = tonumber(manifest.currentBlock) or math.max(1, #Archive.Blocks)
        Upload.UploadId = manifest.uploadId
        Upload.Attempt = tonumber(manifest.uploadAttempt) or 0
    else
        Archive.Generation = Archive.Generation or newRunId()
        Archive.Blocks = {}
        Archive.CurrentBlock = 1
    end

    -- Disk blocks override stale manifest data.
    local diskBlocks = discoverBlocks()
    if #diskBlocks > 0 then
        Archive.Blocks = diskBlocks
    end

    recountArchive()
    Archive.RecoveryPerformed = true
    Upload.PendingRecovered = Archive.Records > 0
    writeManifest()
end

local function acquireFlushLock()
    local started = os.clock()
    while Archive.FlushLock do
        task.wait()
        if os.clock() - started > 8 then
            return false
        end
    end
    Archive.FlushLock = true
    return true
end

local function releaseFlushLock()
    Archive.FlushLock = false
end

local function flushPending(force)
    if #Archive.PendingLines == 0 then
        if force then writeManifest() end
        return true
    end

    if not force and Archive.PendingBytes < CONFIG.FLUSH_AT_BYTES then
        return true
    end

    if not acquireFlushLock() then
        Archive.LastFlushError = "flush_lock_timeout"
        return false
    end

    local okOverall = true

    if not Archive.Persistent then
        for _, line in ipairs(Archive.PendingLines) do
            table.insert(Archive.MemoryLines, string.sub(line, 1, -2))
        end
        Archive.PendingLines = {}
        Archive.PendingBytes = 0
        releaseFlushLock()
        return true
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    -- Do not erase the pending queue before disk commit succeeds.
    local lines = Archive.PendingLines
    local i = 1

    while i <= #lines do
        if Archive.CurrentBlockBytes >= CONFIG.BLOCK_TARGET_BYTES then
            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0
        end

        local room = CONFIG.BLOCK_TARGET_BYTES - Archive.CurrentBlockBytes
        local batch = {}
        local batchBytes = 0
        local startIndex = i

        while i <= #lines do
            local line = lines[i]
            local lineBytes = #line

            if #batch > 0 and batchBytes + lineBytes > room then
                break
            end

            table.insert(batch, line)
            batchBytes += lineBytes
            i += 1

            if batchBytes >= room or #batch >= 80 then
                break
            end
        end

        local path = blockPath(Archive.CurrentBlock)
        if not table.find(Archive.Blocks, path) then
            table.insert(Archive.Blocks, path)
        end

        local ok = appendText(path, table.concat(batch))
        if not ok then
            Archive.LastFlushError = "append_failed:" .. tostring(path)

            local remaining = {}
            local remainingBytes = 0
            for j = startIndex, #lines do
                table.insert(remaining, lines[j])
                remainingBytes += #lines[j]
            end

            Archive.PendingLines = remaining
            Archive.PendingBytes = remainingBytes
            okOverall = false
            break
        end

        Archive.CurrentBlockBytes += batchBytes

        -- Remove committed lines from the live pending queue immediately.
        -- If a later batch fails, only uncommitted records remain in RAM.
        if i > #lines then
            Archive.PendingLines = {}
            Archive.PendingBytes = 0
        end
    end

    if okOverall then
        Archive.PendingLines = {}
        Archive.PendingBytes = 0
        Archive.LastFlushError = nil
    end

    writeManifest()
    releaseFlushLock()
    return okOverall
end

local function writeThroughLine(line)
    if not Archive.Persistent or not APPENDFILE or not CONFIG.WRITE_THROUGH_WHEN_APPEND_AVAILABLE then
        return false
    end

    if not acquireFlushLock() then
        return false
    end

    local bytes = #line

    if Archive.CurrentBlockBytes > 0
    and Archive.CurrentBlockBytes + bytes > CONFIG.BLOCK_TARGET_BYTES
    then
        Archive.CurrentBlock += 1
        Archive.CurrentBlockBytes = 0
    end

    local path = blockPath(Archive.CurrentBlock)
    if not table.find(Archive.Blocks, path) then
        table.insert(Archive.Blocks, path)
    end

    local ok = appendText(path, line)
    if ok then
        Archive.CurrentBlockBytes += bytes
        Archive.Bytes += bytes
        Archive.Records += 1
        Archive.LastFlushError = nil
    else
        Archive.LastFlushError = "write_through_failed:" .. tostring(path)
    end

    if Archive.Records % 32 == 0 then
        writeManifest()
    end

    releaseFlushLock()
    return ok
end

queueRecord = function(record)
    if not Session.Running and record.kind ~= "session_finalized" then
        return false
    end

    record.version = record.version or CONFIG.VERSION
    record.placeId = record.placeId or game.PlaceId
    record.gameId = record.gameId or game.GameId
    record.runId = record.runId or Session.RunId
    record.time = record.time or relativeTime()
    record.unix = record.unix or os.time()

    local line = safeJson(record) .. "\n"

    if #line > CONFIG.MAX_RECORD_JSON_BYTES then
        Session.DroppedOversizeRecords += 1
        line = safeJson({
            version = CONFIG.VERSION,
            placeId = game.PlaceId,
            gameId = game.GameId,
            runId = Session.RunId,
            time = relativeTime(),
            unix = os.time(),
            source = "diagnostic",
            kind = "oversize_record_dropped",
            originalKind = tostring(record.kind),
            originalSource = tostring(record.source),
            encodedBytes = #line,
        }) .. "\n"
    end

    local bytes = #line
    if Archive.Bytes + bytes > CONFIG.MAX_ARCHIVE_BYTES then
        Session.StopRequested = true
        if Status then
            Status.Text = "Limite do archive atingido • parando"
        end
        return false
    end

    local persisted = writeThroughLine(line)

    if not persisted then
        table.insert(Archive.PendingLines, line)
        Archive.PendingBytes += bytes
        Archive.Bytes += bytes
        Archive.Records += 1

        if Archive.PendingBytes >= CONFIG.FLUSH_AT_BYTES then
            task.defer(function()
                guarded("flushPending_deferred", flushPending, true)
            end)
        end
    end

    Session.RecordsThisRun += 1

    if updateUI then updateUI(false) end
    return true
end

-- Periodic flush for executors without appendfile or failed write-through.
task.spawn(function()
    while true do
        task.wait(CONFIG.FLUSH_INTERVAL)
        if #Archive.PendingLines > 0 then
            guarded("periodic_flush", flushPending, true)
        end
    end
end)

--==============================================================--
-- LOCAL STATE SNAPSHOT
--==============================================================--

local function localSnapshot()
    local out = {
        player = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
    }

    local okAttrs, attrs = pcall(function()
        return LocalPlayer:GetAttributes()
    end)
    if okAttrs then out.attributes = safeSerialize(attrs) end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        out.leaderstats = {}
        for _, v in ipairs(leaderstats:GetChildren()) do
            if v:IsA("ValueBase") then
                local okValue, value = pcall(function() return v.Value end)
                if okValue then
                    out.leaderstats[v.Name] = safeSerialize(value)
                end
            end
        end
    end

    local char = LocalPlayer.Character
    if char then
        out.character = {
            path = safePath(char),
        }

        local okCharAttrs, charAttrs = pcall(function()
            return char:GetAttributes()
        end)
        if okCharAttrs then out.character.attributes = safeSerialize(charAttrs) end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local h = {}
            pcall(function() h.health = hum.Health end)
            pcall(function() h.maxHealth = hum.MaxHealth end)
            pcall(function() h.walkSpeed = hum.WalkSpeed end)
            pcall(function() h.jumpPower = hum.JumpPower end)
            pcall(function() h.moveDirection = safeSerialize(hum.MoveDirection) end)
            pcall(function() h.state = tostring(hum:GetState()) end)
            out.character.humanoid = h
        end

        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            local r = {}
            pcall(function() r.position = safeSerialize(root.Position) end)
            pcall(function() r.velocity = safeSerialize(root.AssemblyLinearVelocity) end)
            out.character.root = r
        end
    end

    return out
end

--==============================================================--
-- CENTRAL REMOTE REGISTRY
--==============================================================--

local function sensitivityScore(path, className)
    local score = 0
    local hits = {}

    for _, kw in ipairs(CONFIG.SENSITIVE_KEYWORDS) do
        if contains(path, kw) then
            score += 1
            table.insert(hits, kw)
        end
    end

    if className == "RemoteFunction" then
        score += 1
    end

    return score, hits
end

local function isRemote(inst)
    local className = safeClass(inst)
    return className == "RemoteEvent"
        or className == "RemoteFunction"
        or className == "UnreliableRemoteEvent"
end

local function ensureRemoteInfo(remote)
    if not remote or not isRemote(remote) then
        return nil
    end

    local info = RemoteInfo[remote]
    if info then return info end

    local path = safePath(remote)
    local className = safeClass(remote)
    local score, hits = sensitivityScore(path, className)

    info = {
        path = path,
        name = safeName(remote),
        className = className,
        sensitivityScore = score,
        sensitivityKeywords = hits,
        outboundCount = 0,
        inboundCount = 0,
        legitimateOutboundCount = 0,
        executorOutboundCount = 0,
        invokeCount = 0,
        fireCount = 0,
        observedArgSignatures = {},
        observedReturnSignatures = {},
    }

    RemoteInfo[remote] = info

    if not RemoteCounted[remote] then
        RemoteCounted[remote] = true
        Session.RemoteCount += 1
        if score > 0 then Session.SensitiveRemoteCount += 1 end
    end

    return info
end

local function addSignature(map, signature)
    signature = tostring(signature or "")
    if signature == "" then signature = "<none>" end
    map[signature] = (map[signature] or 0) + 1
end

local function suffixMatches(path, suffix)
    if path == suffix then return true end
    if #path < #suffix then return false end
    return string.sub(path, -#suffix) == suffix
end

local function activeAllowlisted(remote)
    local info = ensureRemoteInfo(remote)
    if not info or info.className ~= "RemoteFunction" then
        return false
    end

    for suffix in pairs(CONFIG.ACTIVE_NOARG_ALLOWLIST) do
        if suffixMatches(info.path, suffix) then
            return true, suffix
        end
    end

    return false
end

local function noteOutbound(remote, method, packed, executorCaller)
    local info = ensureRemoteInfo(remote)
    if not info then return end

    info.outboundCount += 1
    if method == "InvokeServer" then info.invokeCount += 1 end
    if method == "FireServer" then info.fireCount += 1 end

    if executorCaller then
        info.executorOutboundCount += 1
    else
        info.legitimateOutboundCount += 1
    end

    addSignature(info.observedArgSignatures, signatureOfPacked(packed))

    local event = {
        direction = "out",
        path = info.path,
        method = method,
        argc = packed.n or #packed,
        executorCaller = executorCaller and true or false,
        time = relativeTime(),
    }
    Session.LastOutbound = event
    pushRecent(event)

    queueRecord({
        source = "network",
        kind = "remote_outbound",
        path = info.path,
        className = info.className,
        method = method,
        executorCaller = executorCaller and true or false,
        args = serializePacked(packed),
        localState = localSnapshot(),
    })
end

local function noteInbound(remote, packed)
    local info = ensureRemoteInfo(remote)
    if not info then return end

    info.inboundCount += 1
    addSignature(info.observedArgSignatures, "IN:" .. signatureOfPacked(packed))

    local event = {
        direction = "in",
        path = info.path,
        argc = packed.n or #packed,
        time = relativeTime(),
    }
    Session.LastInbound = event
    pushRecent(event)

    Session.DynamicEvents += 1

    queueRecord({
        source = "network",
        kind = "remote_inbound",
        path = info.path,
        className = info.className,
        args = serializePacked(packed),
        localState = localSnapshot(),
    })
end

local function installInbound(remote)
    if InboundObserved[remote] or Session.InboundWatchCount >= CONFIG.REMOTE_WATCH_LIMIT then
        return
    end

    local info = ensureRemoteInfo(remote)
    if not info then return end

    if info.className ~= "RemoteEvent" and info.className ~= "UnreliableRemoteEvent" then
        return
    end

    local ok, connection = pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            if not Session.Running then return end
            local packed = table.pack(...)
            task.defer(function()
                guarded("remote_inbound:" .. info.path, noteInbound, remote, packed)
            end)
        end)
    end)

    if ok and connection then
        InboundObserved[remote] = true
        Session.InboundWatchCount += 1
        table.insert(DynamicConnections, connection)
    end
end

local function installInboundAll()
    for remote in pairs(RemoteInfo) do
        installInbound(remote)
    end
end

local function installHook()
    if HookInstalled or not HOOKMETAMETHOD or not GETNAMECALLMETHOD then
        return false
    end

    local wrapper = function(self, ...)
        local method
        local methodOk, methodValue = pcall(GETNAMECALLMETHOD)
        if methodOk then method = methodValue end

        local shouldTrace = (method == "FireServer" or method == "InvokeServer") and isRemote(self)
        local packed
        local executorCaller = false

        if shouldTrace then
            packed = table.pack(...)
            if CHECKCALLER then
                local ok, result = pcall(CHECKCALLER)
                executorCaller = ok and result or false
            end

            -- Never serialize in the actual namecall path.
            task.defer(function()
                guarded("outbound_trace", noteOutbound, self, method, packed, executorCaller)
            end)
        end

        if method == "InvokeServer" then
            local returns = table.pack(OriginalNamecall(self, ...))

            if shouldTrace then
                task.defer(function()
                    local info = ensureRemoteInfo(self)
                    if info then
                        addSignature(info.observedReturnSignatures, signatureOfPacked(returns))
                        if Session.Running then
                            queueRecord({
                                source = "network",
                                kind = "remote_return",
                                path = info.path,
                                returns = serializePacked(returns),
                            })
                        end
                    end
                end)
            end

            return table.unpack(returns, 1, returns.n)
        end

        return OriginalNamecall(self, ...)
    end

    if NEWCCLOSURE then
        wrapper = NEWCCLOSURE(wrapper)
    end

    local ok, old = pcall(function()
        return HOOKMETAMETHOD(game, "__namecall", wrapper)
    end)

    if ok and old then
        OriginalNamecall = old
        HookInstalled = true
        return true
    end

    return false
end

local function restoreHook()
    if HookInstalled
    and HOOKMETAMETHOD
    and type(OriginalNamecall) == "function"
    then
        pcall(HOOKMETAMETHOD, game, "__namecall", OriginalNamecall)
    end

    HookInstalled = false
    OriginalNamecall = nil
end

--==============================================================--
-- ENTITY REGISTRY
--==============================================================--

local function classifyEntity(inst)
    local className = safeClass(inst)
    local name = lower(safeName(inst))

    if className == "Player" then return "player" end
    if className == "Tool" then return "tool" end
    if className == "ProximityPrompt" then return "prompt" end

    if className == "Model" then
        local hum
        pcall(function() hum = inst:FindFirstChildOfClass("Humanoid") end)
        if hum then
            if Players:GetPlayerFromCharacter(inst) then
                return "character"
            end
            return "npc"
        end

        if string.find(name, "egg", 1, true) then return "egg_model" end
        if string.find(name, "pet", 1, true) then return "pet_model" end
        if string.find(name, "guard", 1, true) then return "guard_model" end
        if string.find(name, "tread", 1, true) then return "treadmill_model" end
    end

    return nil
end

local function registerEntity(inst, reason)
    if EntityObserved[inst] or Session.EntityCount >= CONFIG.ENTITY_LIMIT then
        return
    end

    local kind = classifyEntity(inst)
    if not kind then return end

    EntityObserved[inst] = true
    Session.EntityCount += 1

    local data = {
        source = "entity",
        kind = "entity_registered",
        entityType = kind,
        reason = reason,
        object = safeInstanceInfo(inst),
    }

    local okAttrs, attrs = pcall(function() return inst:GetAttributes() end)
    if okAttrs then data.attributes = safeSerialize(attrs) end

    if safeClass(inst) == "Model" then
        local okPivot, pivot = pcall(function() return inst:GetPivot() end)
        if okPivot then data.pivot = safeSerialize(pivot) end
    end

    queueRecord(data)
end

--==============================================================--
-- VALUE / ATTRIBUTE WATCHES
--==============================================================--

local function isValueBase(inst)
    local ok, result = pcall(function() return inst:IsA("ValueBase") end)
    return ok and result
end

local function attachValueWatch(inst)
    if ValueObserved[inst] or Session.ValueWatchCount >= CONFIG.VALUE_WATCH_LIMIT then
        return
    end
    if not isValueBase(inst) then return end

    local path = safePath(inst)
    local ok, connection = pcall(function()
        return inst:GetPropertyChangedSignal("Value"):Connect(function()
            if not Session.Running then return end

            local value
            local valueOk = pcall(function() value = inst.Value end)
            if not valueOk then return end

            Session.DynamicEvents += 1
            local event = {
                direction = "state",
                kind = "value_changed",
                path = path,
                time = relativeTime(),
            }
            pushRecent(event)

            queueRecord({
                source = "state",
                kind = "value_changed",
                path = path,
                className = safeClass(inst),
                value = safeSerialize(value),
                recent = recentSnapshot(),
            })
        end)
    end)

    if ok and connection then
        ValueObserved[inst] = true
        Session.ValueWatchCount += 1
        table.insert(DynamicConnections, connection)
    end
end

local function attachAttributeWatch(inst)
    if AttributeObserved[inst] or Session.AttributeWatchCount >= CONFIG.ATTRIBUTE_WATCH_LIMIT then
        return
    end

    local path = safePath(inst)
    local ok, connection = pcall(function()
        return inst.AttributeChanged:Connect(function(attributeName)
            if not Session.Running then return end

            local value
            local valueOk = pcall(function() value = inst:GetAttribute(attributeName) end)
            if not valueOk then return end

            Session.DynamicEvents += 1
            local event = {
                direction = "state",
                kind = "attribute_changed",
                path = path,
                attribute = tostring(attributeName),
                time = relativeTime(),
            }
            pushRecent(event)

            queueRecord({
                source = "state",
                kind = "attribute_changed",
                path = path,
                className = safeClass(inst),
                attribute = tostring(attributeName),
                value = safeSerialize(value),
                recent = recentSnapshot(),
            })
        end)
    end)

    if ok and connection then
        AttributeObserved[inst] = true
        Session.AttributeWatchCount += 1
        table.insert(DynamicConnections, connection)
    end
end

local function attachInterestingWatches(inst)
    attachValueWatch(inst)

    local shouldWatchAttrs = false
    local okAttrs, attrs = pcall(function() return inst:GetAttributes() end)
    if okAttrs and type(attrs) == "table" then
        shouldWatchAttrs = next(attrs) ~= nil
    end

    if shouldWatchAttrs
    or safeClass(inst) == "Player"
    or safeClass(inst) == "Model"
    or safeClass(inst) == "Tool"
    then
        attachAttributeWatch(inst)
    end
end

--==============================================================--
-- OBJECT MAPPING
--==============================================================--

local function sampleObject(inst)
    local data = {
        source = "mapping",
        kind = "object",
        object = safeInstanceInfo(inst),
    }

    local className = safeClass(inst)

    local okAttrs, attrs = pcall(function() return inst:GetAttributes() end)
    if okAttrs and type(attrs) == "table" and next(attrs) ~= nil then
        data.attributes = safeSerialize(attrs)
    end

    if isValueBase(inst) then
        local okValue, value = pcall(function() return inst.Value end)
        if okValue then data.value = safeSerialize(value) end
    end

    if className == "Tool" then
        pcall(function() data.requiresHandle = inst.RequiresHandle end)
        pcall(function() data.canBeDropped = inst.CanBeDropped end)
    elseif className == "ProximityPrompt" then
        pcall(function() data.actionText = inst.ActionText end)
        pcall(function() data.objectText = inst.ObjectText end)
        pcall(function() data.holdDuration = inst.HoldDuration end)
        pcall(function() data.maxActivationDistance = inst.MaxActivationDistance end)
        pcall(function() data.enabled = inst.Enabled end)
    elseif className == "Humanoid" then
        pcall(function() data.health = inst.Health end)
        pcall(function() data.maxHealth = inst.MaxHealth end)
        pcall(function() data.walkSpeed = inst.WalkSpeed end)
        pcall(function() data.jumpPower = inst.JumpPower end)
    elseif className == "BasePart" or className == "Part" or className == "MeshPart" then
        pcall(function() data.position = safeSerialize(inst.Position) end)
        pcall(function() data.size = safeSerialize(inst.Size) end)
        pcall(function() data.anchored = inst.Anchored end)
        pcall(function() data.canCollide = inst.CanCollide end)
    end

    queueRecord(data)
end

local function runBroadMapping()
    local roots = {
        {name="ReplicatedStorage", object=ReplicatedStorage},
        {name="Workspace", object=Workspace},
        {name="Players", object=Players},
        {name="ReplicatedFirst", object=ReplicatedFirst},
        {name="StarterGui", object=StarterGui},
        {name="StarterPlayer", object=StarterPlayer},
        {name="SoundService", object=SoundService},
        {name="Lighting", object=Lighting},
    }

    for _, entry in ipairs(roots) do
        if not Session.Running or Session.StopRequested then break end

        Session.CurrentService = entry.name
        if updateUI then updateUI(true) end

        local budget = CONFIG.SERVICE_BUDGETS[entry.name] or 5000
        local classCounts = {}
        local processed = 0

        local ok, descendants = pcall(function() return entry.object:GetDescendants() end)
        if ok and type(descendants) == "table" then
            for _, inst in ipairs(descendants) do
                if not Session.Running or Session.StopRequested then break end
                if processed >= budget then break end

                local className = safeClass(inst)
                local skip = CONFIG.CLASS_SKIP[className] == true

                if not skip then
                    local sampleLimit = CONFIG.CLASS_SAMPLE_LIMIT[className]
                    if sampleLimit then
                        classCounts[className] = (classCounts[className] or 0) + 1
                        if classCounts[className] > sampleLimit then
                            skip = true
                        end
                    end
                end

                ensureRemoteInfo(inst)
                installInbound(inst)
                registerEntity(inst, "mapping")
                attachInterestingWatches(inst)

                if not skip then
                    sampleObject(inst)
                    processed += 1
                end

                if processed % 120 == 0 then
                    task.wait()
                end
            end
        end

        queueRecord({
            source = "mapping",
            kind = "service_completed",
            service = entry.name,
            processed = processed,
            budget = budget,
            classSamples = safeSerialize(classCounts),
        })
    end

    Session.MappingDone = true
    Session.CurrentService = "observation"

    queueRecord({
        source = "mapping",
        kind = "mapping_completed",
        remotes = Session.RemoteCount,
        entities = Session.EntityCount,
        valueWatches = Session.ValueWatchCount,
        attributeWatches = Session.AttributeWatchCount,
    })

    if updateUI then updateUI(true) end
end

--==============================================================--
-- DYNAMIC ROOT OBSERVATION
--==============================================================--

local function attachDynamicRoot(root, label)
    local addConnection = root.DescendantAdded:Connect(function(inst)
        if not Session.Running then return end

        task.defer(function()
            guarded("dynamic_added:" .. label, function()
                ensureRemoteInfo(inst)
                installInbound(inst)
                registerEntity(inst, "dynamic_added")
                attachInterestingWatches(inst)

                Session.DynamicEvents += 1
                queueRecord({
                    source = "lifecycle",
                    kind = "object_created",
                    root = label,
                    object = safeInstanceInfo(inst),
                })
            end)
        end)
    end)

    local removeConnection = root.DescendantRemoving:Connect(function(inst)
        if not Session.Running then return end

        local info = safeInstanceInfo(inst)
        Session.DynamicEvents += 1
        queueRecord({
            source = "lifecycle",
            kind = "object_removed",
            root = label,
            object = info,
        })
    end)

    table.insert(DynamicConnections, addConnection)
    table.insert(DynamicConnections, removeConnection)
end

--==============================================================--
-- ACTIVE SAFE PROBES
--==============================================================--

local function runSafeActiveProbes()
    if not CONFIG.ACTIVE_PROBES_ENABLED or not Session.Running then
        return
    end

    Session.ActiveProbeRunning = true

    local candidates = {}
    for remote, info in pairs(RemoteInfo) do
        if remote and info and info.className == "RemoteFunction" then
            local allowlisted, suffix = activeAllowlisted(remote)
            if allowlisted and info.legitimateOutboundCount > 0 then
                table.insert(candidates, {
                    remote = remote,
                    info = info,
                    suffix = suffix,
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.info.path < b.info.path
    end)

    queueRecord({
        source = "active_audit",
        kind = "active_probe_batch_started",
        candidates = #candidates,
        policy = "exact_allowlist_noarg_already_observed_legitimate_only",
    })

    for _, candidate in ipairs(candidates) do
        if not Session.Running or Session.StopRequested then break end
        if Session.ActiveProbes >= CONFIG.ACTIVE_PROBE_LIMIT then break end

        local before = localSnapshot()
        local started = os.clock()

        local ok, a, b, c = pcall(function()
            return candidate.remote:InvokeServer()
        end)

        Session.ActiveProbes += 1

        queueRecord({
            source = "active_audit",
            kind = "safe_noarg_validation_probe",
            path = candidate.info.path,
            suffix = candidate.suffix,
            success = ok,
            duration = os.clock() - started,
            returns = ok and safeSerialize({a,b,c}) or nil,
            error = ok and nil or truncateString(tostring(a), 4000),
            before = before,
            after = localSnapshot(),
        })

        task.wait(CONFIG.ACTIVE_PROBE_DELAY)
    end

    queueRecord({
        source = "active_audit",
        kind = "active_probe_batch_completed",
        probes = Session.ActiveProbes,
        candidates = #candidates,
    })

    Session.ActiveProbeRunning = false
end

--==============================================================--
-- REMOTE SECURITY SUMMARY
--==============================================================--

local function emitRemoteCatalog()
    local items = {}

    for remote, info in pairs(RemoteInfo) do
        local alive = false
        pcall(function() alive = remote.Parent ~= nil end)
        if alive then
            table.insert(items, {
                path = info.path,
                name = info.name,
                className = info.className,
                sensitivityScore = info.sensitivityScore,
                sensitivityKeywords = info.sensitivityKeywords,
                activeNoArgAllowlisted = select(1, activeAllowlisted(remote)),
                outboundCount = info.outboundCount,
                inboundCount = info.inboundCount,
                legitimateOutboundCount = info.legitimateOutboundCount,
                executorOutboundCount = info.executorOutboundCount,
                invokeCount = info.invokeCount,
                fireCount = info.fireCount,
                observedArgSignatures = info.observedArgSignatures,
                observedReturnSignatures = info.observedReturnSignatures,
            })
        end
    end

    table.sort(items, function(a, b)
        if a.sensitivityScore == b.sensitivityScore then
            return a.path < b.path
        end
        return a.sensitivityScore > b.sensitivityScore
    end)

    local top = {}
    for i = 1, math.min(180, #items) do
        top[i] = items[i]
    end

    queueRecord({
        source = "security",
        kind = "remote_security_surface",
        total = #items,
        top = top,
        note = "Sensitivity is a review heuristic. It is not proof of a vulnerability.",
    })
end

--==============================================================--
-- WATCHDOG / HEALTH
--==============================================================--

local function emitHealthHeartbeat()
    queueRecord({
        source = "health",
        kind = "collector_health",
        currentService = Session.CurrentService,
        mappingDone = Session.MappingDone,
        remotes = Session.RemoteCount,
        sensitiveRemotes = Session.SensitiveRemoteCount,
        inboundWatches = Session.InboundWatchCount,
        entities = Session.EntityCount,
        valueWatches = Session.ValueWatchCount,
        attributeWatches = Session.AttributeWatchCount,
        dynamicEvents = Session.DynamicEvents,
        activeProbes = Session.ActiveProbes,
        errors = Session.ErrorCount,
        oversizeDrops = Session.DroppedOversizeRecords,
        archiveBytes = Archive.Bytes,
        archiveRecords = Archive.Records,
        pendingBytes = Archive.PendingBytes,
        lastFlushError = Archive.LastFlushError,
        hookInstalled = HookInstalled,
        filesystem = Archive.Persistent,
        requestAvailable = REQUEST ~= nil,
        localState = localSnapshot(),
    })
end

local heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not Session.Running then return end

    local now = os.clock()

    if now - Session.LastHealthHeartbeat >= CONFIG.HEALTH_HEARTBEAT_INTERVAL then
        Session.LastHealthHeartbeat = now
        task.defer(function()
            guarded("health_heartbeat", emitHealthHeartbeat)
        end)
    end

    if Archive.Bytes >= CONFIG.MAX_ARCHIVE_BYTES then
        Session.StopRequested = true
    end
end)

table.insert(Connections, heartbeatConnection)

--==============================================================--
-- HTTP / STREAMING UPLOAD
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false, nil, "request indisponível"
    end

    local lastError

    for attempt = 1, CONFIG.HTTP_RETRIES do
        local ok, response = pcall(REQUEST, options)

        if ok and type(response) == "table" then
            local status = tonumber(response.StatusCode or response.Status or response.status)
            local body = response.Body or response.body or ""
            local success = response.Success

            if success == nil and status then
                success = status >= 200 and status < 300
            end

            if success == true then
                return true, status, body
            end

            lastError = "HTTP " .. tostring(status) .. " " .. truncateString(tostring(body), 4000)
        else
            lastError = tostring(response)
        end

        task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
    end

    return false, nil, lastError
end

local function postJson(url, data)
    local ok, _, body = requestRaw({
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = safeJson(data),
    })

    if not ok then
        return false, nil, body
    end

    local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if decodeOk then
        return true, decoded, nil
    end

    return true, {raw=body}, nil
end

local function iterateObjects(callback)
    local header = {
        recordType = "security_fusion_header",
        scanner = CONFIG.VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = game.PlaceVersion,
        clientVisibleOnly = true,
        generatedAt = os.time(),
        archiveRecords = Archive.Records,
        archiveBytes = Archive.Bytes,
        generation = Archive.Generation,
        recovered = Upload.PendingRecovered,
        invalidRecoveredLines = Archive.InvalidRecoveredLines,
        focus = "general_client_visible_security_mapping_and_correlation",
    }

    if callback(header) == false then return false end

    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            local existsOk, exists = pcall(ISFILE, path)
            if existsOk and exists then
                local ok, text = pcall(READFILE, path)
                if ok and type(text) == "string" then
                    for line in string.gmatch(text, "[^\r\n]+") do
                        local decodeOk, object = pcall(HttpService.JSONDecode, HttpService, line)

                        if not decodeOk or type(object) ~= "table" then
                            object = {
                                version = CONFIG.VERSION,
                                placeId = game.PlaceId,
                                gameId = game.GameId,
                                source = "recovery",
                                kind = "raw_unparseable_archive_line",
                                archivePath = tostring(path),
                                raw = truncateString(line, 16000),
                            }
                        end

                        if callback(object) == false then
                            return false
                        end
                    end
                end
            end
        end
    else
        for _, line in ipairs(Archive.MemoryLines) do
            local decodeOk, object = pcall(HttpService.JSONDecode, HttpService, line)
            if decodeOk and type(object) == "table" then
                if callback(object) == false then return false end
            end
        end
    end

    return true
end

local function streamChunks(onChunk)
    if not flushPending(true) then
        return false, 0, 0, Archive.LastFlushError or "flush_before_stream_failed"
    end

    if Archive.Persistent then recountArchive() end

    local current = {}
    local currentBytes = 2
    local index = 0
    local totalBytes = 0
    local streamError

    local function flushChunk()
        if #current == 0 then return true end

        index += 1
        local objects = current
        local payloadBytes = math.max(2, currentBytes - 1)

        current = {}
        currentBytes = 2

        local ok, err = onChunk(index, objects, payloadBytes)

        table.clear(objects)
        objects = nil

        if not ok then
            streamError = err
            return false
        end

        totalBytes += payloadBytes
        task.wait()

        pcall(function()
            collectgarbage("step", 180)
        end)

        return true
    end

    local iterOk = iterateObjects(function(object)
        local encoded = safeJson(object)
        local add = #encoded + 1

        if #current > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            if not flushChunk() then return false end
        end

        table.insert(current, object)
        currentBytes += add
        return true
    end)

    if not iterOk and streamError then
        return false, index, totalBytes, streamError
    end

    if #current > 0 and not flushChunk() then
        return false, index, totalBytes, streamError
    end

    return true, index, totalBytes, nil
end

local function persistUploadReceipt(finishData)
    if not Archive.Persistent then return true end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local receipt = {
        confirmed = true,
        generation = Archive.Generation,
        blocks = Archive.Blocks,
        uploadId = Upload.UploadId,
        url = Upload.LastURL,
        finish = safeSerialize(finishData),
        confirmedAt = os.time(),
    }

    return pcall(WRITEFILE, CONFIG.RECEIPT_PATH, safeJson(receipt))
end

local function deleteArchiveConfirmed(finishData)
    if Archive.Persistent then
        -- Receipt FIRST. If execution dies during cleanup, the next launch
        -- finishes cleanup instead of re-uploading already-confirmed blocks.
        if not persistUploadReceipt(finishData) then
            return false, "receipt_write_failed"
        end

        local allClean = true
        for _, path in ipairs(Archive.Blocks) do
            local existsOk, exists = pcall(ISFILE, path)
            if existsOk and exists and not safeDeleteOrEmpty(path) then
                allClean = false
            end
        end

        if allClean then
            safeDeleteOrEmpty(CONFIG.MANIFEST_PATH)
            safeDeleteOrEmpty(CONFIG.MANIFEST_BACKUP_PATH)
            safeDeleteOrEmpty(CONFIG.RECEIPT_PATH)
        else
            return false, "confirmed_cleanup_incomplete"
        end
    else
        table.clear(Archive.MemoryLines)
    end

    Archive.Generation = newRunId()
    Archive.Blocks = {blockPath(1)}
    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0
    Archive.Bytes = 0
    Archive.Records = 0
    Archive.PendingLines = {}
    Archive.PendingBytes = 0
    Archive.InvalidRecoveredLines = 0

    Upload.UploadId = nil
    Upload.PendingRecovered = false

    return true
end

local function bestEffortCancel(uploadId)
    if not uploadId or not REQUEST then return end
    task.defer(function()
        pcall(function()
            postJson(CONFIG.UPLOAD_BASE .. "/cancel", {uploadId = uploadId})
        end)
    end)
end

local function markUploadFailure(message, err)
    Upload.Running = false
    Upload.LastError = err or message
    Upload.ConsecutiveFailures += 1
    Upload.NextRetryAt = os.clock() + CONFIG.AUTO_UPLOAD_RETRY_SECONDS

    writeManifest()

    if Status then Status.Text = message .. " • dados preservados" end
    if Action then Action.Text = "REENVIAR" end
    if updateUI then updateUI(true) end
end

uploadAll = function()
    if Upload.Running or Archive.Records <= 0 or Session.Running then
        return
    end

    if not REQUEST then
        Upload.LastError = "request indisponível"
        Upload.NextRetryAt = os.clock() + CONFIG.AUTO_UPLOAD_RETRY_SECONDS
        if Status then Status.Text = "Sem HTTP • dados preservados" end
        if Action then Action.Text = "REENVIAR" end
        if updateUI then updateUI(true) end
        return
    end

    if not flushPending(true) then
        Upload.LastError = Archive.LastFlushError or "flush_failed"
        Upload.NextRetryAt = os.clock() + CONFIG.AUTO_UPLOAD_RETRY_SECONDS
        if Status then Status.Text = "Falha ao salvar • upload adiado" end
        if Action then Action.Text = "REENVIAR" end
        if updateUI then updateUI(true) end
        return
    end

    if Archive.Persistent then recountArchive() end

    Upload.Attempt += 1
    Upload.Running = true
    Upload.LastError = nil
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0
    Upload.BytesSent = 0
    Upload.TotalBytes = math.max(Archive.Bytes, 1)
    Upload.UploadId = nil

    writeManifest()

    if Action then Action.Text = "ENVIANDO..." end
    if Status then Status.Text = "Iniciando upload..." end
    if updateUI then updateUI(true) end

    local filename = string.format(
        "Cafeina_SecurityFusion_%s_%s.json",
        tostring(game.PlaceId),
        isoUTC()
    )

    local startOk, startData, startErr = postJson(
        CONFIG.UPLOAD_BASE .. "/start",
        {
            filename = filename,
            source = CONFIG.VERSION,
            metadata = {
                scanner = CONFIG.VERSION,
                placeId = game.PlaceId,
                gameId = game.GameId,
                placeVersion = game.PlaceVersion,
                clientVisibleOnly = true,
                focus = "general_client_visible_security_mapping_and_correlation",
                persistentArchive = Archive.Persistent,
                streamingUpload = true,
                targetChunkBytes = CONFIG.UPLOAD_CHUNK_BYTES,
                outboundHook = HookInstalled,
                generation = Archive.Generation,
                recovered = Upload.PendingRecovered,
                uploadAttempt = Upload.Attempt,
            },
        }
    )

    if not startOk then
        markUploadFailure("Erro /start", startErr)
        return
    end

    Upload.UploadId = type(startData) == "table"
        and (startData.uploadId or startData.id or startData.upload_id)
        or nil

    if not Upload.UploadId then
        markUploadFailure("/start inválido", "missing_upload_id")
        return
    end

    writeManifest()

    local streamOk, chunkCount, payloadBytes, streamErr = streamChunks(function(index, objects, bytes)
        Upload.CurrentChunk = index
        if updateUI then updateUI(true) end

        local ok, _, err = postJson(
            CONFIG.UPLOAD_BASE .. "/chunk",
            {
                uploadId = Upload.UploadId,
                index = index,
                objects = objects,
            }
        )

        if not ok then
            return false, err
        end

        Upload.BytesSent += bytes
        if updateUI then updateUI(true) end
        return true
    end)

    if not streamOk then
        bestEffortCancel(Upload.UploadId)
        markUploadFailure("Erro chunk", streamErr)
        return
    end

    Upload.TotalChunks = chunkCount
    Upload.TotalBytes = math.max(payloadBytes, 1)
    Upload.BytesSent = payloadBytes
    if updateUI then updateUI(true) end

    local finishOk, finishData, finishErr = postJson(
        CONFIG.UPLOAD_BASE .. "/finish",
        {
            uploadId = Upload.UploadId,
            totalChunks = chunkCount,
            totalBytes = payloadBytes,
            records = Archive.Records,
            generation = Archive.Generation,
        }
    )

    if not finishOk then
        markUploadFailure("/finish falhou", finishErr)
        return
    end

    local confirmed = type(finishData) == "table"
        and (
            finishData.confirmed == true
            or finishData.success == true
            or finishData.ok == true
        )

    if not confirmed then
        markUploadFailure("Servidor não confirmou", "finish_not_confirmed")
        return
    end

    Upload.LastURL = tostring(
        finishData.url
        or finishData.link
        or finishData.fileUrl
        or ""
    )

    local cleaned, cleanupErr = deleteArchiveConfirmed(finishData)
    if not cleaned then
        Upload.Running = false
        Upload.LastError = cleanupErr
        Upload.ConsecutiveFailures = 0
        Upload.NextRetryAt = 0

        if Status then Status.Text = "Servidor confirmou • limpeza local pendente" end
        if Action then Action.Text = "INICIAR FUSION" end
        if updateUI then updateUI(true) end
        return
    end

    Upload.Running = false
    Upload.ConsecutiveFailures = 0
    Upload.NextRetryAt = 0

    if Status then Status.Text = "Upload confirmado ✓" end
    if Detail then
        Detail.Text = Upload.LastURL ~= ""
            and ("Link recebido • " .. string.sub(Upload.LastURL, 1, 72))
            or "Servidor confirmou • archive local limpo"
    end
    if Action then Action.Text = "INICIAR FUSION" end
    if BarFill then BarFill.Size = UDim2.new(1, 0, 1, 0) end
end

--==============================================================--
-- UI • COMPACT GTA-LIKE PANEL
--==============================================================--

local COLORS = {
    BG = Color3.fromRGB(8, 8, 10),
    PANEL = Color3.fromRGB(15, 15, 18),
    STROKE = Color3.fromRGB(47, 47, 55),
    BUTTON = Color3.fromRGB(31, 31, 37),
    BUTTON_HOVER = Color3.fromRGB(42, 42, 49),
    RED = Color3.fromRGB(183, 43, 52),
    RED_DARK = Color3.fromRGB(96, 30, 35),
    GREEN = Color3.fromRGB(77, 185, 108),
    ORANGE = Color3.fromRGB(224, 160, 75),
    TEXT = Color3.fromRGB(245, 245, 247),
    MUTED = Color3.fromRGB(157, 157, 168),
    BAR = Color3.fromRGB(232, 232, 235),
}

local GuiParent = CoreGui
if type(gethui) == "function" then
    local ok, value = pcall(gethui)
    if ok and value then GuiParent = value end
end

pcall(function()
    for _, guiName in ipairs({CONFIG.GUI_NAME, "CafeinaSecurityFusionCollectorV30"}) do
        local old = GuiParent:FindFirstChild(guiName)
        if old then old:Destroy() end
    end
end)

Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parentOk = pcall(function()
    Gui.Parent = GuiParent
end)
if not parentOk then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(338, 258)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.44)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 11)
mainCorner.Parent = Main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.STROKE
mainStroke.Thickness = 1
mainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.BackgroundColor3 = COLORS.PANEL
Header.BorderSizePixel = 0
Header.Size = UDim2.new(1, 0, 0, 48)
Header.Parent = Main

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 11)
headerCorner.Parent = Header

local HeaderMask = Instance.new("Frame")
HeaderMask.BorderSizePixel = 0
HeaderMask.BackgroundColor3 = COLORS.PANEL
HeaderMask.Position = UDim2.new(0, 0, 1, -11)
HeaderMask.Size = UDim2.new(1, 0, 0, 11)
HeaderMask.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(12, 7)
Title.Size = UDim2.new(1, -96, 0, 19)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • FUSION V3.1"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(12, 25)
Subtitle.Size = UDim2.new(1, -96, 0, 15)
Subtitle.Font = Enum.Font.Gotham
Subtitle.Text = "MAP • TRACE • RECOVERY • AUTO UPLOAD"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 8
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(32, 28)
Minimize.Position = UDim2.new(1, -72, 0, 9)
Minimize.BackgroundColor3 = COLORS.BUTTON
Minimize.BorderSizePixel = 0
Minimize.Text = "—"
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 14
Minimize.TextColor3 = COLORS.TEXT
Minimize.AutoButtonColor = false
Minimize.Parent = Header

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 7)
minCorner.Parent = Minimize

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(32, 28)
Close.Position = UDim2.new(1, -37, 0, 9)
Close.BackgroundColor3 = COLORS.BUTTON
Close.BorderSizePixel = 0
Close.Text = "×"
Close.Font = Enum.Font.GothamBold
Close.TextSize = 14
Close.TextColor3 = COLORS.TEXT
Close.AutoButtonColor = false
Close.Parent = Header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 7)
closeCorner.Parent = Close

local CapabilityRow = Instance.new("Frame")
CapabilityRow.BackgroundTransparency = 1
CapabilityRow.Position = UDim2.fromOffset(12, 56)
CapabilityRow.Size = UDim2.new(1, -24, 0, 20)
CapabilityRow.Parent = Main

PersistDot = Instance.new("Frame")
PersistDot.Size = UDim2.fromOffset(8, 8)
PersistDot.Position = UDim2.fromOffset(0, 6)
PersistDot.BackgroundColor3 = Archive.Persistent and COLORS.GREEN or COLORS.RED
PersistDot.BorderSizePixel = 0
PersistDot.Parent = CapabilityRow
Instance.new("UICorner", PersistDot).CornerRadius = UDim.new(1, 0)

local PersistText = Instance.new("TextLabel")
PersistText.BackgroundTransparency = 1
PersistText.Position = UDim2.fromOffset(13, 0)
PersistText.Size = UDim2.fromOffset(78, 20)
PersistText.Font = Enum.Font.Gotham
PersistText.Text = Archive.Persistent and "DISCO OK" or "SEM DISCO"
PersistText.TextColor3 = COLORS.MUTED
PersistText.TextSize = 8
PersistText.TextXAlignment = Enum.TextXAlignment.Left
PersistText.Parent = CapabilityRow

HttpDot = Instance.new("Frame")
HttpDot.Size = UDim2.fromOffset(8, 8)
HttpDot.Position = UDim2.fromOffset(98, 6)
HttpDot.BackgroundColor3 = REQUEST and COLORS.GREEN or COLORS.RED
HttpDot.BorderSizePixel = 0
HttpDot.Parent = CapabilityRow
Instance.new("UICorner", HttpDot).CornerRadius = UDim.new(1, 0)

local HttpText = Instance.new("TextLabel")
HttpText.BackgroundTransparency = 1
HttpText.Position = UDim2.fromOffset(111, 0)
HttpText.Size = UDim2.fromOffset(70, 20)
HttpText.Font = Enum.Font.Gotham
HttpText.Text = REQUEST and "HTTP OK" or "SEM HTTP"
HttpText.TextColor3 = COLORS.MUTED
HttpText.TextSize = 8
HttpText.TextXAlignment = Enum.TextXAlignment.Left
HttpText.Parent = CapabilityRow

Action = Instance.new("TextButton")
Action.Position = UDim2.fromOffset(12, 82)
Action.Size = UDim2.new(1, -24, 0, 42)
Action.BackgroundColor3 = COLORS.BUTTON
Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "INICIAR FUSION"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 8)
actionCorner.Parent = Action

RetryButton = Instance.new("TextButton")
RetryButton.Position = UDim2.fromOffset(12, 130)
RetryButton.Size = UDim2.new(1, -24, 0, 28)
RetryButton.BackgroundColor3 = COLORS.PANEL
RetryButton.BorderSizePixel = 0
RetryButton.Font = Enum.Font.GothamBold
RetryButton.Text = "ENVIAR ARQUIVO PENDENTE"
RetryButton.TextColor3 = COLORS.MUTED
RetryButton.TextSize = 9
RetryButton.AutoButtonColor = false
RetryButton.Parent = Main

local retryCorner = Instance.new("UICorner")
retryCorner.CornerRadius = UDim.new(0, 7)
retryCorner.Parent = RetryButton

Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(12, 166)
Status.Size = UDim2.new(1, -24, 0, 18)
Status.Font = Enum.Font.GothamBold
Status.Text = "Pronto"
Status.TextColor3 = COLORS.TEXT
Status.TextSize = 9
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

Detail = Instance.new("TextLabel")
Detail.BackgroundTransparency = 1
Detail.Position = UDim2.fromOffset(12, 184)
Detail.Size = UDim2.new(1, -24, 0, 35)
Detail.Font = Enum.Font.Gotham
Detail.Text = "0.00 MB • 0 registros"
Detail.TextColor3 = COLORS.MUTED
Detail.TextSize = 8
Detail.TextWrapped = true
Detail.TextXAlignment = Enum.TextXAlignment.Left
Detail.TextYAlignment = Enum.TextYAlignment.Top
Detail.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(12, 229)
BarBack.Size = UDim2.new(1, -24, 0, 8)
BarBack.BackgroundColor3 = COLORS.PANEL
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local barBackCorner = Instance.new("UICorner")
barBackCorner.CornerRadius = UDim.new(1, 0)
barBackCorner.Parent = BarBack

BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0, 0, 1, 0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = BarFill

local Footer = Instance.new("TextLabel")
Footer.BackgroundTransparency = 1
Footer.Position = UDim2.fromOffset(12, 240)
Footer.Size = UDim2.new(1, -24, 0, 13)
Footer.Font = Enum.Font.Gotham
Footer.Text = "LOCAL FIRST • SERVER CONFIRMATION BEFORE DELETE"
Footer.TextColor3 = Color3.fromRGB(102, 102, 112)
Footer.TextSize = 7
Footer.TextXAlignment = Enum.TextXAlignment.Center
Footer.Parent = Main

MiniButton = Instance.new("TextButton")
MiniButton.Size = UDim2.fromOffset(52, 52)
MiniButton.AnchorPoint = Vector2.new(0.5, 0.5)
MiniButton.Position = UDim2.fromScale(0.5, 0.5)
MiniButton.BackgroundColor3 = COLORS.BG
MiniButton.BorderSizePixel = 0
MiniButton.Font = Enum.Font.GothamBold
MiniButton.Text = "C"
MiniButton.TextColor3 = COLORS.TEXT
MiniButton.TextSize = 19
MiniButton.Visible = false
MiniButton.AutoButtonColor = false
MiniButton.Parent = Gui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(1, 0)
miniCorner.Parent = MiniButton

local miniStroke = Instance.new("UIStroke")
miniStroke.Color = COLORS.STROKE
miniStroke.Thickness = 1
miniStroke.Parent = MiniButton

--==============================================================--
-- DRAGGING / MINIMIZE
--==============================================================--

local function makeDraggable(handle, object)
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    table.insert(Connections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = object.Position

            local changed
            changed = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if changed then changed:Disconnect() end
                end
            end)
        end
    end))

    table.insert(Connections, handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragInput = input
        end
    end))

    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            object.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end

makeDraggable(Header, Main)
makeDraggable(MiniButton, MiniButton)

Minimize.MouseButton1Click:Connect(function()
    Main.Visible = false
    MiniButton.Visible = true
end)

MiniButton.MouseButton1Click:Connect(function()
    MiniButton.Visible = false
    Main.Visible = true
end)

--==============================================================--
-- UI UPDATE
--==============================================================--

local lastUiClock = 0

updateUI = function(force)
    if not Gui or not Gui.Parent then return end

    local now = os.clock()
    if not force and now - lastUiClock < CONFIG.UI_REFRESH_SECONDS then
        return
    end
    lastUiClock = now

    PersistDot.BackgroundColor3 = Archive.Persistent and COLORS.GREEN or COLORS.RED
    HttpDot.BackgroundColor3 = REQUEST and COLORS.GREEN or COLORS.RED

    if Upload.Running then
        Status.Text = string.format(
            "Enviando chunk %d%s",
            Upload.CurrentChunk,
            Upload.TotalChunks > 0 and ("/" .. tostring(Upload.TotalChunks)) or " • streaming"
        )

        local ratio = Upload.TotalBytes > 0
            and clamp(Upload.BytesSent / Upload.TotalBytes, 0, 1)
            or 0

        BarFill.Size = UDim2.new(ratio, 0, 1, 0)
        Detail.Text = string.format(
            "%.2f / %.2f MB • tentativa %d",
            mb(Upload.BytesSent),
            mb(Upload.TotalBytes),
            Upload.Attempt
        )
        RetryButton.Text = "UPLOAD EM ANDAMENTO"
        RetryButton.TextColor3 = COLORS.MUTED
        return
    end

    BarFill.Size = UDim2.new(
        clamp(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES, 0, 1),
        0, 1, 0
    )

    if Session.Running then
        Status.Text = string.format(
            "Coletando • %s%s",
            Session.CurrentService,
            Session.ActiveProbeRunning and " • SAFE PROBE" or ""
        )

        Detail.Text = string.format(
            "%.2f MB • %d regs • R:%d S:%d E:%d\nDyn:%d • P:%d • Err:%d",
            mb(Archive.Bytes),
            Archive.Records,
            Session.RemoteCount,
            Session.SensitiveRemoteCount,
            Session.EntityCount,
            Session.DynamicEvents,
            Session.ActiveProbes,
            Session.ErrorCount
        )

        RetryButton.Text = "ARQUIVO É PRESERVADO ENQUANTO COLETA"
        RetryButton.TextColor3 = COLORS.MUTED
    else
        Detail.Text = string.format(
            "%.2f MB • %d registros preservados%s",
            mb(Archive.Bytes),
            Archive.Records,
            Archive.InvalidRecoveredLines > 0
                and (" • " .. tostring(Archive.InvalidRecoveredLines) .. " linhas recuperadas")
                or ""
        )

        if Archive.Records > 0 then
            RetryButton.Text = "ENVIAR ARQUIVO PENDENTE"
            RetryButton.TextColor3 = COLORS.TEXT
        else
            RetryButton.Text = "NENHUM ARQUIVO PENDENTE"
            RetryButton.TextColor3 = COLORS.MUTED
        end
    end
end

--==============================================================--
-- SESSION CONTROL
--==============================================================--

disconnectDynamic = function()
    for _, connection in ipairs(DynamicConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(DynamicConnections)
    table.clear(InboundObserved)
    table.clear(ValueObserved)
    table.clear(AttributeObserved)
end

local function prebuildRegistries()
    for _, root in ipairs({ReplicatedStorage, Workspace, Players}) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok and type(descendants) == "table" then
            for _, inst in ipairs(descendants) do
                ensureRemoteInfo(inst)
                registerEntity(inst, "prebuild")
            end
        end
    end
end

local function startDynamicObservation()
    attachDynamicRoot(ReplicatedStorage, "ReplicatedStorage")
    attachDynamicRoot(Workspace, "Workspace")
    attachDynamicRoot(Players, "Players")
end

local function begin()
    if Session.Running or Upload.Running then return end

    Session.Running = true
    Session.StopRequested = false
    Session.RunId = newRunId()
    Session.StartedClock = os.clock()
    Session.RecordsThisRun = 0
    Session.MappingDone = false
    Session.CurrentService = "initializing"

    Session.RemoteCount = 0
    Session.SensitiveRemoteCount = 0
    Session.InboundWatchCount = 0
    Session.EntityCount = 0
    Session.ValueWatchCount = 0
    Session.AttributeWatchCount = 0
    Session.DynamicEvents = 0
    Session.ActiveProbeRunning = false
    Session.ActiveProbes = 0
    Session.LastOutbound = nil
    Session.LastInbound = nil
    Session.RecentEvents = {}
    Session.LastHealthHeartbeat = 0
    Session.ErrorCount = 0
    Session.DroppedOversizeRecords = 0

    table.clear(RemoteInfo)
    table.clear(RemoteCounted)
    table.clear(EntityObserved)
    table.clear(InboundObserved)
    table.clear(ValueObserved)
    table.clear(AttributeObserved)

    Action.Text = "PARAR + ENVIAR"
    Action.BackgroundColor3 = COLORS.RED

    queueRecord({
        source = "session",
        kind = "session_started",
        capabilities = {
            filesystem = FILESYSTEM_OK and true or false,
            appendfile = APPENDFILE ~= nil,
            request = REQUEST ~= nil,
            hookmetamethod = HOOKMETAMETHOD ~= nil,
            getnamecallmethod = GETNAMECALLMETHOD ~= nil,
            listfiles = LISTFILES ~= nil,
        },
        durability = {
            diskSourceOfTruth = Archive.Persistent,
            writeThrough = APPENDFILE ~= nil and CONFIG.WRITE_THROUGH_WHEN_APPEND_AVAILABLE,
            manifestBackup = true,
            blockRecovery = true,
            confirmationReceipt = true,
            autoUploadRecovery = CONFIG.AUTO_UPLOAD_ENABLED,
        },
        architecture = {
            remoteRegistry = true,
            entityRegistry = true,
            stateCorrelation = true,
            broadMapping = true,
            passiveInbound = true,
            passiveOutbound = true,
            persistentArchive = true,
            automaticUpload = true,
        },
        activeProbePolicy = {
            enabled = CONFIG.ACTIVE_PROBES_ENABLED,
            exactAllowlistOnly = true,
            noArgumentsOnly = true,
            mustHaveLegitimateObservation = true,
            genericFuzzing = false,
            destructiveTesting = false,
        },
        localState = localSnapshot(),
    })

    guarded("prebuildRegistries", prebuildRegistries)
    guarded("emitRemoteCatalog_initial", emitRemoteCatalog)
    guarded("installHook", installHook)
    guarded("installInboundAll", installInboundAll)
    guarded("startDynamicObservation", startDynamicObservation)

    task.spawn(function()
        guarded("runBroadMapping", runBroadMapping)
    end)

    if CONFIG.ACTIVE_PROBES_ENABLED then
        task.spawn(function()
            task.wait(2.0)
            if Session.Running and not Session.StopRequested then
                guarded("runSafeActiveProbes", runSafeActiveProbes)
            end
        end)
    end

    updateUI(true)
end

local function stopAndUpload()
    if not Session.Running or Upload.Running then return end

    Session.StopRequested = true
    Session.CurrentService = "finalizing"

    guarded("emitRemoteCatalog_final", emitRemoteCatalog)

    queueRecord({
        source = "session",
        kind = "session_finalized",
        recordsThisRun = Session.RecordsThisRun,
        archivedRecords = Archive.Records,
        archivedBytes = Archive.Bytes,
        mappingDone = Session.MappingDone,
        currentService = Session.CurrentService,
        remoteCount = Session.RemoteCount,
        sensitiveRemoteCount = Session.SensitiveRemoteCount,
        inboundWatchCount = Session.InboundWatchCount,
        entityCount = Session.EntityCount,
        valueWatchCount = Session.ValueWatchCount,
        attributeWatchCount = Session.AttributeWatchCount,
        dynamicEvents = Session.DynamicEvents,
        activeProbes = Session.ActiveProbes,
        errors = Session.ErrorCount,
        oversizeDrops = Session.DroppedOversizeRecords,
        localState = localSnapshot(),
        recent = recentSnapshot(),
    })

    Session.Running = false
    Session.ActiveProbeRunning = false
    disconnectDynamic()
    restoreHook()

    guarded("final_flush", flushPending, true)
    guarded("final_manifest", writeManifest)

    Action.Text = "ENVIANDO..."
    Action.BackgroundColor3 = COLORS.RED
    Status.Text = "Archive salvo • preparando upload..."
    updateUI(true)

    task.defer(function()
        guarded("stop_upload", uploadAll)
    end)
end

--==============================================================--
-- BUTTONS
--==============================================================--

Action.MouseButton1Click:Connect(function()
    if Upload.Running then return end

    if Session.Running then
        stopAndUpload()
    elseif Archive.Records > 0 then
        task.defer(function()
            guarded("manual_retry_action", uploadAll)
        end)
    else
        begin()
    end
end)

RetryButton.MouseButton1Click:Connect(function()
    if not Session.Running and not Upload.Running and Archive.Records > 0 then
        Upload.NextRetryAt = 0
        task.defer(function()
            guarded("manual_retry_button", uploadAll)
        end)
    end
end)

Close.MouseButton1Click:Connect(function()
    -- Closing the panel never deletes local data. Stop collection, persist it,
    -- hide the UI, and keep the auto-uploader alive so it can send ASAP.
    if Session.Running then
        Session.StopRequested = true
        queueRecord({
            source = "session",
            kind = "session_finalized",
            reason = "ui_closed",
            recordsThisRun = Session.RecordsThisRun,
            archivedRecords = Archive.Records,
            archivedBytes = Archive.Bytes,
            localState = localSnapshot(),
        })
        Session.Running = false
        Session.ActiveProbeRunning = false
    end

    if disconnectDynamic then disconnectDynamic() end
    restoreHook()
    guarded("close_flush", flushPending, true)
    guarded("close_manifest", writeManifest)

    if Gui then Gui.Enabled = false end

    if Archive.Records > 0 and REQUEST and not Upload.Running then
        task.defer(function()
            guarded("close_auto_upload", uploadAll)
        end)
    end
end)

--==============================================================--
-- AUTO STOP ON SIZE LIMIT / STOP REQUEST
--==============================================================--

task.spawn(function()
    while Gui and Gui.Parent do
        task.wait(0.5)
        if Session.Running
        and Session.StopRequested
        and not Upload.Running
        then
            guarded("auto_stop_size_or_request", stopAndUpload)
        end
    end
end)

--==============================================================--
-- LOAD / RECOVERY / AUTO-RESUME
--==============================================================--

loadArchive()

if Archive.Records > 0 then
    Action.Text = "REENVIAR"
    Action.BackgroundColor3 = COLORS.RED
    Status.Text = string.format(
        "Recuperado %.2f MB • envio automático pendente",
        mb(Archive.Bytes)
    )
    Detail.Text = string.format(
        "%d registros preservados no disco",
        Archive.Records
    )
elseif not Archive.Persistent then
    Status.Text = "ATENÇÃO • executor sem persistência em disco"
end

updateUI(true)

task.spawn(function()
    task.wait(CONFIG.AUTO_UPLOAD_START_DELAY)

    while Gui and Gui.Parent do
        if CONFIG.AUTO_UPLOAD_ENABLED
        and Archive.Records > 0
        and not Session.Running
        and not Upload.Running
        and REQUEST
        and os.clock() >= (Upload.NextRetryAt or 0)
        then
            guarded("auto_resume_upload", uploadAll)
        end

        task.wait(1.0)
    end
end)

--==============================================================--
-- CONTROLLER FOR REPLACEMENT / RELOAD
--==============================================================--

local Controller = {}

function Controller.Stop(reason)
    reason = tostring(reason or "external_stop")

    if Session.Running then
        Session.StopRequested = true
        queueRecord({
            source = "session",
            kind = "session_finalized",
            reason = reason,
            recordsThisRun = Session.RecordsThisRun,
            archivedRecords = Archive.Records,
            archivedBytes = Archive.Bytes,
            mappingDone = Session.MappingDone,
            localState = localSnapshot(),
        })
        Session.Running = false
        Session.ActiveProbeRunning = false
    end

    if disconnectDynamic then disconnectDynamic() end
    restoreHook()

    guarded("controller_stop_flush", flushPending, true)
    guarded("controller_stop_manifest", writeManifest)

    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)

    pcall(function()
        if Gui then Gui:Destroy() end
    end)

    -- Never delete archive here. The next launch recovers and auto-uploads it.
end

function Controller.Begin()
    begin()
end

function Controller.StopAndUpload()
    stopAndUpload()
end

function Controller.Upload()
    if not Session.Running then
        task.defer(function()
            guarded("controller_upload", uploadAll)
        end)
    end
end

function Controller.GetState()
    return {
        version = CONFIG.VERSION,
        running = Session.Running,
        uploading = Upload.Running,
        archiveBytes = Archive.Bytes,
        archiveRecords = Archive.Records,
        persistent = Archive.Persistent,
        recovered = Upload.PendingRecovered,
        uploadAttempt = Upload.Attempt,
        lastUploadError = Upload.LastError,
        lastURL = Upload.LastURL,
    }
end

rawset(env, "__CAFEINA_SECURITY_FUSION_CONTROLLER", Controller)

-- Final startup diagnostic is only recorded when a collection is started.
-- Existing recovered data is left byte-for-byte intact until upload confirms.
