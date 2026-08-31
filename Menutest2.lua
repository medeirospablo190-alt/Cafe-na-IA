--==============================================================--
-- CAFEÍNA • SECURITY FUSION LAB V2.0
-- GENERAL CLIENT-VISIBLE SECURITY AUDIT / DATA FUSION
--
-- PURPOSE
-- • Broad mapping of the replicated game surface.
-- • Passive capture of outgoing/incoming remotes.
-- • Correlation of remote calls with replicated state changes.
-- • Sensitive-surface scoring for remotes/values/prompts/tools.
-- • Dynamic object/value/attribute observation.
-- • Conservative active probes ONLY on read/check-style RemoteFunctions.
-- • Automatic persistent archive + upload to cafe-na-ia.onrender.com.
--
-- SAFETY MODEL
-- • Does not automatically call destructive/economic/combat/admin remotes.
-- • Active probing is blocked for risky keywords.
-- • Active probes are rate-limited and limited to RemoteFunctions that look
--   like read/check/validation APIs.
-- • Findings are evidence for server-side review, not automatic exploitation.
--
-- NOTE
-- Run only in games/environments you are authorized to test.
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

local CONFIG = {
    VERSION = "SECURITY_FUSION_LAB_V2_0",
    GUI_NAME = "CafeinaSecurityFusionLabV20",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    ARCHIVE_ROOT = "CafeinaSecurityFusion",
    ARCHIVE_FOLDER = "CafeinaSecurityFusion/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaSecurityFusion/" .. tostring(game.PlaceId) .. "/manifest.json",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 500000,
    FLUSH_INTERVAL = 0.35,
    FLUSH_AT_BYTES = 96 * 1024,

    -- Broad mapper budgets.
    SERVICE_BUDGETS = {
        ReplicatedStorage = 26000,
        Workspace = 24000,
        Players = 10000,
        ReplicatedFirst = 6000,
        StarterGui = 9000,
        StarterPlayer = 7000,
        SoundService = 2500,
        Lighting = 2500,
    },

    -- Avoid wasting the archive on animation noise.
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
        Attachment = 500,
    },

    -- Dynamic observation.
    DYNAMIC_OBJECT_SAMPLE_LIMIT = 12000,
    VALUE_WATCH_LIMIT = 7000,
    ATTRIBUTE_WATCH_LIMIT = 7000,
    REMOTE_WATCH_LIMIT = 4000,

    -- Active validation lab.
    ACTIVE_AUDIT_ENABLED = true,
    ACTIVE_AUDIT_START_DELAY = 2.0,
    ACTIVE_PROBE_DELAY = 0.45,
    ACTIVE_PROBE_LIMIT = 90,
    ACTIVE_REPEAT_COUNT = 3,
    INVOKE_TIMEOUT = 4.0,

    -- Only these read/check-like names are eligible for generic probing.
    SAFE_ACTIVE_KEYWORDS = {
        "ask", "check", "can", "get", "query", "validate",
        "verify", "is", "has", "requeststate", "requestinfo",
        "status", "inspect", "preview",
    },

    -- Anything containing these is NEVER actively probed automatically.
    HARD_BLOCK_KEYWORDS = {
        "buy", "purchase", "sell", "trade", "gift", "claim", "reward",
        "grant", "award", "give", "spawn", "delete", "remove", "wipe",
        "save", "load", "reset", "kick", "ban", "moderation", "admin",
        "damage", "hit", "shoot", "projectile", "kill", "heal",
        "equip", "unequip", "inventory", "item", "egg", "capture",
        "teleport", "currency", "money", "cash", "coin", "gem",
        "product", "receipt", "developerproduct", "gamepass",
        "opencrate", "loot", "redeem"
    },

    -- Keywords that make a surface interesting for manual review.
    SENSITIVE_KEYWORDS = {
        "speed", "speedpower", "money", "cash", "coin", "gem",
        "profile", "delta", "inventory", "item", "gear", "egg",
        "reward", "claim", "award", "grant", "give", "purchase",
        "buy", "sell", "trade", "teleport", "damage", "hit",
        "kill", "admin", "save", "load", "data", "stats", "level",
        "xp", "prestige", "rebirth", "treadmill", "capture",
        "ownership", "owner", "permission", "role", "rank",
    },

    MAX_SERIALIZE_DEPTH = 6,
    MAX_TABLE_ITEMS = 120,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.1,
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local previous = rawget(env, "__CAFEINA_SECURITY_FUSION_CONTROLLER")
    if type(previous) == "table" and type(previous.Stop) == "function" then
        previous.Stop("replaced")
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

local HOOKMETAMETHOD = pickFunction(rawget(env, "hookmetamethod"))
local GETNAMECALLMETHOD = pickFunction(rawget(env, "getnamecallmethod"))
local NEWCCLOSURE = pickFunction(rawget(env, "newcclosure"))
local CHECKCALLER = pickFunction(rawget(env, "checkcaller"))

local FILESYSTEM_OK =
    WRITEFILE and READFILE and ISFILE and DELFILE and MAKEFOLDER

--==============================================================--
-- BASIC HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function containsAny(text, list)
    local low = lower(text)
    for _, fragment in ipairs(list) do
        if string.find(low, lower(fragment), 1, true) then
            return true, fragment
        end
    end
    return false, nil
end

local function safePath(inst)
    local ok, value = pcall(function()
        return inst:GetFullName()
    end)
    return ok and value or tostring(inst)
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
    local ok, result = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    return ok and result or tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
end

local function safeJson(value)
    local ok, result = pcall(HttpService.JSONEncode, HttpService, value)
    if ok then
        return result
    end

    return HttpService:JSONEncode({
        kind = "json_error",
        error = tostring(result),
    })
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
    elseif tv == "Vector3" then
        return {type="Vector3", x=value.X, y=value.Y, z=value.Z}
    elseif tv == "Vector2" then
        return {type="Vector2", x=value.X, y=value.Y}
    elseif tv == "CFrame" then
        local p = value.Position
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z}
    elseif tv == "Color3" then
        return {type="Color3", r=value.R, g=value.G, b=value.B}
    elseif tv == "BrickColor" then
        return tostring(value)
    elseif tv == "EnumItem" then
        return tostring(value)
    elseif tv == "Instance" then
        return {
            type="Instance",
            className=value.ClassName,
            name=value.Name,
            path=safePath(value),
        }
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

    return tostring(value)
end

local function serializePacked(packed)
    local values = {}
    local n = packed.n or #packed

    for i = 1, n do
        values[i] = safeSerialize(packed[i])
    end

    return {count=n, values=values}
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
    ValueWatchCount = 0,
    AttributeWatchCount = 0,
    DynamicEvents = 0,

    ActiveAuditRunning = false,
    ActiveProbes = 0,

    LastOutbound = nil,
    LastInbound = nil,

    RecentEvents = {},
}

local Archive = {
    Persistent = FILESYSTEM_OK and true or false,
    Blocks = {},
    CurrentBlock = 1,
    CurrentBlockBytes = 0,
    Bytes = 0,
    Records = 0,
    PendingLines = {},
    PendingBytes = 0,
    MemoryLines = {},
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
}

local Connections = {}
local RemoteInfo = setmetatable({}, {__mode="k"})
local InboundObserved = setmetatable({}, {__mode="k"})
local ObservedLegitInvoke = setmetatable({}, {__mode="k"})
local OriginalNamecall
local HookInstalled = false

local updateUI
local Status
local Detail
local Action
local BarFill

--==============================================================--
-- RECENT CORRELATION BUFFER
--==============================================================--

local function relativeTime()
    if Session.StartedClock == 0 then
        return 0
    end
    return os.clock() - Session.StartedClock
end

local function pushRecent(item)
    item.time = item.time or relativeTime()
    table.insert(Session.RecentEvents, item)

    while #Session.RecentEvents > 120 do
        table.remove(Session.RecentEvents, 1)
    end

    local cutoff = relativeTime() - 6.0
    while #Session.RecentEvents > 0 and (Session.RecentEvents[1].time or 0) < cutoff do
        table.remove(Session.RecentEvents, 1)
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
-- ARCHIVE
--==============================================================--

local function blockPath(index)
    return string.format("%s/block_%06d.jsonl", CONFIG.ARCHIVE_FOLDER, index)
end

local function ensureFolder(path)
    if not FILESYSTEM_OK then
        return
    end

    pcall(function()
        if not ISFOLDER(path) then
            MAKEFOLDER(path)
        end
    end)
end

local function appendText(path, text)
    if APPENDFILE then
        return pcall(APPENDFILE, path, text)
    end

    local old = ""
    if ISFILE(path) then
        local ok, value = pcall(READFILE, path)
        if ok and type(value) == "string" then
            old = value
        end
    end

    return pcall(WRITEFILE, path, old .. text)
end

local function writeManifest()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local data = {
        version=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        blocks=Archive.Blocks,
        currentBlock=Archive.CurrentBlock,
        currentBlockBytes=Archive.CurrentBlockBytes,
        bytes=Archive.Bytes,
        records=Archive.Records,
        updatedAt=os.time(),
    }

    pcall(WRITEFILE, CONFIG.MANIFEST_PATH, safeJson(data))
end

local function flushPending(force)
    if #Archive.PendingLines == 0 then
        if force then
            writeManifest()
        end
        return true
    end

    if not force and Archive.PendingBytes < CONFIG.FLUSH_AT_BYTES then
        return true
    end

    local lines = Archive.PendingLines
    Archive.PendingLines = {}
    Archive.PendingBytes = 0

    if not Archive.Persistent then
        for _, line in ipairs(lines) do
            table.insert(Archive.MemoryLines, string.sub(line, 1, -2))
        end
        return true
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local batch = {}

    local function commit()
        if #batch == 0 then
            return true
        end

        local text = table.concat(batch)
        table.clear(batch)

        local path = blockPath(Archive.CurrentBlock)
        if not table.find(Archive.Blocks, path) then
            table.insert(Archive.Blocks, path)
        end

        local ok = appendText(path, text)
        if ok then
            Archive.CurrentBlockBytes += #text
        end

        return ok
    end

    for _, line in ipairs(lines) do
        local bytes = #line

        if Archive.CurrentBlockBytes > 0
        and Archive.CurrentBlockBytes + bytes > CONFIG.BLOCK_TARGET_BYTES
        then
            if not commit() then
                return false
            end

            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0
        end

        table.insert(batch, line)

        if #batch >= 80 then
            if not commit() then
                return false
            end
        end
    end

    local ok = commit()
    if ok then
        writeManifest()
    end

    return ok
end

local function queueRecord(record)
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
    local bytes = #line

    if Archive.Bytes + bytes > CONFIG.MAX_ARCHIVE_BYTES then
        Session.StopRequested = true
        return false
    end

    table.insert(Archive.PendingLines, line)
    Archive.PendingBytes += bytes
    Archive.Bytes += bytes
    Archive.Records += 1
    Session.RecordsThisRun += 1

    if Archive.PendingBytes >= CONFIG.FLUSH_AT_BYTES then
        task.defer(flushPending, true)
    end

    if updateUI then
        updateUI(false)
    end

    return true
end

local function loadArchive()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    if ISFILE(CONFIG.MANIFEST_PATH) then
        local ok, text = pcall(READFILE, CONFIG.MANIFEST_PATH)
        if ok and type(text) == "string" then
            local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
            if decodeOk and type(data) == "table" then
                Archive.Blocks = type(data.blocks) == "table" and data.blocks or {}
                Archive.CurrentBlock = tonumber(data.currentBlock) or math.max(1,#Archive.Blocks)
                Archive.CurrentBlockBytes = tonumber(data.currentBlockBytes) or 0
                Archive.Bytes = tonumber(data.bytes) or 0
                Archive.Records = tonumber(data.records) or 0
            end
        end
    end

    if #Archive.Blocks == 0 then
        Archive.Blocks = {blockPath(1)}
        Archive.CurrentBlock = 1
    end
end

task.spawn(function()
    while true do
        task.wait(CONFIG.FLUSH_INTERVAL)
        if #Archive.PendingLines > 0 then
            flushPending(true)
        end
    end
end)

--==============================================================--
-- LOCAL SNAPSHOT
--==============================================================--

local function localSnapshot()
    local out = {
        player = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        attributes = safeSerialize(LocalPlayer:GetAttributes()),
    }

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        out.leaderstats = {}
        for _, v in ipairs(leaderstats:GetChildren()) do
            if v:IsA("ValueBase") then
                out.leaderstats[v.Name] = safeSerialize(v.Value)
            end
        end
    end

    local char = LocalPlayer.Character
    if char then
        out.character = {
            path = safePath(char),
            attributes = safeSerialize(char:GetAttributes()),
        }

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            out.character.humanoid = {
                health = hum.Health,
                maxHealth = hum.MaxHealth,
                walkSpeed = hum.WalkSpeed,
                jumpPower = hum.JumpPower,
                moveDirection = safeSerialize(hum.MoveDirection),
            }

            local ok, state = pcall(function()
                return hum:GetState()
            end)
            if ok then
                out.character.humanoid.state = tostring(state)
            end
        end

        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            out.character.root = {
                position = safeSerialize(root.Position),
                velocity = safeSerialize(root.AssemblyLinearVelocity),
            }
        end
    end

    return out
end

--==============================================================--
-- SENSITIVITY / REMOTE CLASSIFICATION
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

local function remoteInfoFor(remote)
    local cached = RemoteInfo[remote]
    if cached then
        return cached
    end

    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("RemoteFunction")
        or remote:IsA("UnreliableRemoteEvent")
    ) then
        return nil
    end

    local path = safePath(remote)
    local score, hits = sensitivityScore(path, remote.ClassName)

    local info = {
        name=remote.Name,
        path=path,
        className=remote.ClassName,
        sensitivityScore=score,
        sensitivityKeywords=hits,
    }

    RemoteInfo[remote] = info
    return info
end

local function hardBlocked(remote)
    return containsAny(safePath(remote), CONFIG.HARD_BLOCK_KEYWORDS)
end

local function safeActiveCandidate(remote)
    if not remote:IsA("RemoteFunction") then
        return false, "not_remote_function"
    end

    local blocked, kw = hardBlocked(remote)
    if blocked then
        return false, "blocked:" .. tostring(kw)
    end

    local path = safePath(remote)
    local safe, safeKw = containsAny(path, CONFIG.SAFE_ACTIVE_KEYWORDS)
    if not safe then
        return false, "not_read_check_style"
    end

    return true, safeKw
end

--==============================================================--
-- BROAD STATIC MAPPING
--==============================================================--

local function objectDescriptor(inst)
    local data = {
        className = inst.ClassName,
        name = inst.Name,
        path = safePath(inst),
        attributes = safeSerialize(inst:GetAttributes()),
    }

    if inst:IsA("ValueBase") then
        data.value = safeSerialize(inst.Value)
    elseif inst:IsA("BasePart") then
        data.position = safeSerialize(inst.Position)
        data.size = safeSerialize(inst.Size)
        data.canCollide = inst.CanCollide
        data.canTouch = inst.CanTouch
        data.canQuery = inst.CanQuery
        data.anchored = inst.Anchored
        data.transparency = inst.Transparency
    elseif inst:IsA("ProximityPrompt") then
        data.actionText = inst.ActionText
        data.objectText = inst.ObjectText
        data.maxActivationDistance = inst.MaxActivationDistance
        data.holdDuration = inst.HoldDuration
        data.enabled = inst.Enabled
        data.requiresLineOfSight = inst.RequiresLineOfSight
    elseif inst:IsA("Tool") then
        data.toolTip = inst.ToolTip
        data.canBeDropped = inst.CanBeDropped
        data.requiresHandle = inst.RequiresHandle
    elseif inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    then
        local info = remoteInfoFor(inst)
        data.remote = info
        data.safeActiveCandidate = select(1, safeActiveCandidate(inst))
        data.hardBlocked = select(1, hardBlocked(inst))
    end

    return data
end

local function mapService(serviceName, root, budget)
    Session.CurrentService = serviceName
    if updateUI then updateUI(true) end

    local count = 0
    local classCounts = {}
    local sampledClasses = {}

    queueRecord({
        source="mapping",
        kind="service_begin",
        service=serviceName,
        budget=budget,
    })

    local descendants = root:GetDescendants()

    for _, inst in ipairs(descendants) do
        if not Session.Running or Session.StopRequested then
            break
        end

        if count >= budget then
            break
        end

        local className = inst.ClassName

        if not CONFIG.CLASS_SKIP[className] then
            classCounts[className] = (classCounts[className] or 0) + 1

            local sampleLimit = CONFIG.CLASS_SAMPLE_LIMIT[className]
            local shouldRecord = true

            if sampleLimit then
                sampledClasses[className] = (sampledClasses[className] or 0) + 1
                shouldRecord = sampledClasses[className] <= sampleLimit
            end

            if shouldRecord then
                count += 1
                queueRecord({
                    source="mapping",
                    kind="object",
                    service=serviceName,
                    object=objectDescriptor(inst),
                })
            end
        end

        if count % 180 == 0 then
            task.wait()
        end
    end

    queueRecord({
        source="mapping",
        kind="service_end",
        service=serviceName,
        recorded=count,
        classCounts=classCounts,
    })
end

local function runBroadMapping()
    local services = {
        {"ReplicatedStorage", ReplicatedStorage},
        {"Workspace", Workspace},
        {"Players", Players},
        {"ReplicatedFirst", ReplicatedFirst},
        {"StarterGui", StarterGui},
        {"StarterPlayer", StarterPlayer},
        {"SoundService", SoundService},
        {"Lighting", Lighting},
    }

    for _, pair in ipairs(services) do
        if not Session.Running or Session.StopRequested then
            break
        end

        local name, root = pair[1], pair[2]
        mapService(name, root, CONFIG.SERVICE_BUDGETS[name] or 5000)
    end

    Session.MappingDone = true
    Session.CurrentService = "dynamic observation"

    queueRecord({
        source="mapping",
        kind="mapping_completed",
    })

    if updateUI then updateUI(true) end
end

--==============================================================--
-- DYNAMIC WATCHERS
--==============================================================--

local function isInterestingValue(inst)
    if not inst:IsA("ValueBase") then
        return false
    end

    local path = safePath(inst)
    local sensitive = containsAny(path, CONFIG.SENSITIVE_KEYWORDS)

    if sensitive then
        return true
    end

    local parent = inst.Parent
    if parent and (
        contains(parent.Name, "Stats")
        or contains(parent.Name, "Profile")
        or contains(parent.Name, "Data")
        or contains(parent.Name, "Inventory")
    ) then
        return true
    end

    return false
end

local function attachValueWatch(inst)
    if Session.ValueWatchCount >= CONFIG.VALUE_WATCH_LIMIT then
        return
    end

    if not isInterestingValue(inst) then
        return
    end

    Session.ValueWatchCount += 1
    local last = safeSerialize(inst.Value)

    local c = inst:GetPropertyChangedSignal("Value"):Connect(function()
        if not Session.Running then
            return
        end

        local now = safeSerialize(inst.Value)

        pushRecent({
            kind="value_changed",
            path=safePath(inst),
            before=last,
            after=now,
        })

        queueRecord({
            source="dynamic",
            kind="value_changed",
            object={
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
            },
            before=last,
            after=now,
            localState=localSnapshot(),
            recent=recentSnapshot(),
        })

        last = now
        Session.DynamicEvents += 1
    end)

    table.insert(Connections, c)
end

local function isInterestingAttributeOwner(inst)
    local path = safePath(inst)
    if containsAny(path, CONFIG.SENSITIVE_KEYWORDS) then
        return true
    end

    return inst:IsA("Player")
        or inst:IsA("Model")
        or inst:IsA("Tool")
        or inst:IsA("ProximityPrompt")
end

local function attachAttributeWatch(inst)
    if Session.AttributeWatchCount >= CONFIG.ATTRIBUTE_WATCH_LIMIT then
        return
    end

    if not isInterestingAttributeOwner(inst) then
        return
    end

    Session.AttributeWatchCount += 1

    local c = inst.AttributeChanged:Connect(function(attr)
        if not Session.Running then
            return
        end

        local value = safeSerialize(inst:GetAttribute(attr))

        pushRecent({
            kind="attribute_changed",
            path=safePath(inst),
            attribute=attr,
            value=value,
        })

        queueRecord({
            source="dynamic",
            kind="attribute_changed",
            object={
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
            },
            attribute=attr,
            value=value,
            localState=localSnapshot(),
            recent=recentSnapshot(),
        })

        Session.DynamicEvents += 1
    end)

    table.insert(Connections, c)
end

local function attachDynamicRoot(root, label)
    local initial = 0

    for _, inst in ipairs(root:GetDescendants()) do
        if initial >= CONFIG.DYNAMIC_OBJECT_SAMPLE_LIMIT then
            break
        end

        attachValueWatch(inst)
        attachAttributeWatch(inst)

        local info = remoteInfoFor(inst)
        if info then
            Session.RemoteCount += 1
            if info.sensitivityScore > 0 then
                Session.SensitiveRemoteCount += 1
            end
        end

        initial += 1
    end

    local added = root.DescendantAdded:Connect(function(inst)
        if not Session.Running then
            return
        end

        attachValueWatch(inst)
        attachAttributeWatch(inst)

        local info = remoteInfoFor(inst)
        if info then
            Session.RemoteCount += 1
            if info.sensitivityScore > 0 then
                Session.SensitiveRemoteCount += 1
            end
            task.defer(function()
                if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
                    if not InboundObserved[inst] then
                        -- Inbound hookup is installed below after definition.
                    end
                end
            end)
        end

        pushRecent({
            kind="object_created",
            path=safePath(inst),
            className=inst.ClassName,
        })

        queueRecord({
            source="dynamic",
            kind="object_created",
            root=label,
            object=objectDescriptor(inst),
            localState=localSnapshot(),
        })

        Session.DynamicEvents += 1
    end)

    local removing = root.DescendantRemoving:Connect(function(inst)
        if not Session.Running then
            return
        end

        pushRecent({
            kind="object_removed",
            path=safePath(inst),
            className=inst.ClassName,
        })

        queueRecord({
            source="dynamic",
            kind="object_removed",
            root=label,
            object={
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
            },
            localState=localSnapshot(),
        })

        Session.DynamicEvents += 1
    end)

    table.insert(Connections, added)
    table.insert(Connections, removing)
end

--==============================================================--
-- INBOUND REMOTE CAPTURE
--==============================================================--

local attachInbound

attachInbound = function(remote)
    if InboundObserved[remote] then
        return
    end

    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
        return
    end

    if Session.RemoteCount > CONFIG.REMOTE_WATCH_LIMIT then
        return
    end

    InboundObserved[remote] = true

    local info = remoteInfoFor(remote)

    local c = remote.OnClientEvent:Connect(function(...)
        if not Session.Running or Session.StopRequested then
            return
        end

        local packed = table.pack(...)
        Session.LastInbound = {
            time=relativeTime(),
            remote=info.path,
        }

        pushRecent({
            kind="remote_received",
            remote=info.path,
            payload=serializePacked(packed),
        })

        queueRecord({
            source="network_in",
            kind="remote_received",
            remote=info,
            payload=serializePacked(packed),
            localState=localSnapshot(),
            recent=recentSnapshot(),
        })
    end)

    table.insert(Connections, c)
end

local function installInboundAll()
    local roots = {ReplicatedStorage, Workspace, Players}

    for _, root in ipairs(roots) do
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
                attachInbound(inst)
            end
        end

        local c = root.DescendantAdded:Connect(function(inst)
            if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
                task.defer(attachInbound, inst)
            end
        end)

        table.insert(Connections, c)
    end
end

--==============================================================--
-- OUTBOUND PASSIVE TAP
--==============================================================--

local function installHook()
    if HookInstalled then
        return true
    end

    if not HOOKMETAMETHOD or not GETNAMECALLMETHOD then
        queueRecord({
            source="diagnostic",
            kind="outbound_hook_unavailable",
            hookmetamethod=HOOKMETAMETHOD ~= nil,
            getnamecallmethod=GETNAMECALLMETHOD ~= nil,
        })
        return false
    end

    local oldNamecall

    local wrapper = function(self, ...)
        local method = GETNAMECALLMETHOD()

        if not Session.Running
        or Session.StopRequested
        or (method ~= "FireServer" and method ~= "InvokeServer")
        then
            return oldNamecall(self, ...)
        end

        if typeof(self) ~= "Instance"
        or not (
            self:IsA("RemoteEvent")
            or self:IsA("RemoteFunction")
            or self:IsA("UnreliableRemoteEvent")
        )
        then
            return oldNamecall(self, ...)
        end

        local info = remoteInfoFor(self)
        local args = table.pack(...)

        local callerIsExecutor = false
        if CHECKCALLER then
            local ok, value = pcall(CHECKCALLER)
            callerIsExecutor = ok and value == true
        end

        local before = localSnapshot()
        local started = os.clock()

        if method == "InvokeServer" then
            local packedReturns = table.pack(
                oldNamecall(self, table.unpack(args, 1, args.n))
            )

            local duration = os.clock() - started

            if not callerIsExecutor then
                ObservedLegitInvoke[self] = {
                    args=args,
                    returns=packedReturns,
                    time=relativeTime(),
                }
            end

            Session.LastOutbound = {
                time=relativeTime(),
                remote=info.path,
                method=method,
            }

            pushRecent({
                kind="remote_invoke",
                remote=info.path,
                callerIsExecutor=callerIsExecutor,
                payload=serializePacked(args),
                returns=serializePacked(packedReturns),
            })

            task.defer(function()
                queueRecord({
                    source="network_out",
                    kind="remote_invoke",
                    remote=info,
                    callerIsExecutor=callerIsExecutor,
                    payload=serializePacked(args),
                    returns=serializePacked(packedReturns),
                    duration=duration,
                    before=before,
                    after=localSnapshot(),
                    recent=recentSnapshot(),
                })
            end)

            return table.unpack(packedReturns, 1, packedReturns.n)
        else
            Session.LastOutbound = {
                time=relativeTime(),
                remote=info.path,
                method=method,
            }

            pushRecent({
                kind="remote_fire",
                remote=info.path,
                callerIsExecutor=callerIsExecutor,
                payload=serializePacked(args),
            })

            task.defer(function()
                queueRecord({
                    source="network_out",
                    kind="remote_fire",
                    remote=info,
                    callerIsExecutor=callerIsExecutor,
                    payload=serializePacked(args),
                    before=before,
                    recent=recentSnapshot(),
                })
            end)

            return oldNamecall(self, table.unpack(args, 1, args.n))
        end
    end

    if NEWCCLOSURE then
        wrapper = NEWCCLOSURE(wrapper)
    end

    local ok, old = pcall(HOOKMETAMETHOD, game, "__namecall", wrapper)

    if not ok or type(old) ~= "function" then
        queueRecord({
            source="diagnostic",
            kind="outbound_hook_failed",
            error=tostring(old),
        })
        return false
    end

    oldNamecall = old
    OriginalNamecall = old
    HookInstalled = true

    queueRecord({
        source="session",
        kind="outbound_hook_ready",
        passive=true,
    })

    return true
end

local function restoreHook()
    if HookInstalled and HOOKMETAMETHOD and type(OriginalNamecall) == "function" then
        pcall(HOOKMETAMETHOD, game, "__namecall", OriginalNamecall)
    end

    HookInstalled = false
end

--==============================================================--
-- CONSERVATIVE ACTIVE AUDIT
--==============================================================--

local function invokeWithTimeout(remote, packedArgs)
    local done = false
    local result = nil

    task.spawn(function()
        local packed
        local ok, err = pcall(function()
            packed = table.pack(
                remote:InvokeServer(
                    table.unpack(packedArgs, 1, packedArgs.n or #packedArgs)
                )
            )
        end)

        result = {
            ok=ok,
            error=ok and nil or tostring(err),
            returns=ok and serializePacked(packed) or nil,
        }
        done = true
    end)

    local started = os.clock()
    while not done and os.clock() - started < CONFIG.INVOKE_TIMEOUT do
        RunService.Heartbeat:Wait()
    end

    if not done then
        return {
            ok=false,
            timeout=true,
        }
    end

    return result
end

local function runProbe(remote, label, args)
    if Session.ActiveProbes >= CONFIG.ACTIVE_PROBE_LIMIT then
        return false
    end

    local eligible, why = safeActiveCandidate(remote)
    if not eligible then
        return false
    end

    Session.ActiveProbes += 1

    local before = localSnapshot()
    local started = os.clock()
    local result = invokeWithTimeout(remote, args)
    local duration = os.clock() - started
    local after = localSnapshot()

    queueRecord({
        source="active_audit",
        kind="validation_probe",
        label=label,
        remote=remoteInfoFor(remote),
        eligibility=why,
        args=serializePacked(args),
        result=result,
        duration=duration,
        before=before,
        after=after,
        recent=recentSnapshot(),
    })

    task.wait(CONFIG.ACTIVE_PROBE_DELAY)
    return true
end

local function runActiveAudit()
    if not CONFIG.ACTIVE_AUDIT_ENABLED or Session.ActiveAuditRunning then
        return
    end

    Session.ActiveAuditRunning = true

    queueRecord({
        source="active_audit",
        kind="active_audit_started",
        policy={
            remoteFunctionsOnly=true,
            readCheckStyleOnly=true,
            hardBlockedKeywords=CONFIG.HARD_BLOCK_KEYWORDS,
            rateLimited=true,
            noCombatEconomyAdminMutation=true,
        },
    })

    local candidates = {}

    for remote, info in pairs(RemoteInfo) do
        if remote and remote.Parent and remote:IsA("RemoteFunction") then
            local eligible = safeActiveCandidate(remote)
            if eligible then
                table.insert(candidates, {
                    remote=remote,
                    info=info,
                })
            end
        end
    end

    table.sort(candidates, function(a,b)
        if a.info.sensitivityScore == b.info.sensitivityScore then
            return a.info.path < b.info.path
        end
        return a.info.sensitivityScore > b.info.sensitivityScore
    end)

    for _, item in ipairs(candidates) do
        if not Session.Running
        or Session.StopRequested
        or Session.ActiveProbes >= CONFIG.ACTIVE_PROBE_LIMIT
        then
            break
        end

        local remote = item.remote

        -- Probe 1: no arguments.
        runProbe(remote, "no_args", table.pack())

        if not Session.Running or Session.StopRequested then
            break
        end

        -- Probe 2: repeat no-arg call a few times to observe server-side throttling.
        for i = 1, CONFIG.ACTIVE_REPEAT_COUNT do
            if Session.ActiveProbes >= CONFIG.ACTIVE_PROBE_LIMIT then break end
            runProbe(remote, "repeat_no_args_" .. tostring(i), table.pack())
        end

        -- Probe 3: only replay a previously observed legitimate call once,
        -- and only for a read/check-style RF that passed the hard block.
        local observed = ObservedLegitInvoke[remote]
        if observed and observed.args then
            runProbe(remote, "replay_observed_legit_args_once", observed.args)
        end
    end

    queueRecord({
        source="active_audit",
        kind="active_audit_completed",
        probes=Session.ActiveProbes,
        candidates=#candidates,
    })

    Session.ActiveAuditRunning = false
end

--==============================================================--
-- SECURITY SURFACE SUMMARY
--==============================================================--

local function emitRemoteCatalog()
    local items = {}

    for remote, info in pairs(RemoteInfo) do
        local eligible, why = safeActiveCandidate(remote)
        local blocked, blockedKw = hardBlocked(remote)

        table.insert(items, {
            path=info.path,
            name=info.name,
            className=info.className,
            sensitivityScore=info.sensitivityScore,
            sensitivityKeywords=info.sensitivityKeywords,
            safeActiveCandidate=eligible,
            safeReason=why,
            hardBlocked=blocked,
            blockedKeyword=blockedKw,
        })
    end

    table.sort(items, function(a,b)
        if a.sensitivityScore == b.sensitivityScore then
            return a.path < b.path
        end
        return a.sensitivityScore > b.sensitivityScore
    end)

    local top = {}
    for i = 1, math.min(120, #items) do
        top[i] = items[i]
    end

    queueRecord({
        source="security",
        kind="remote_security_surface",
        total=#items,
        top=top,
        note="Sensitivity is a review heuristic, not proof of a vulnerability.",
    })
end

--==============================================================--
-- HTTP / UPLOAD
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false, nil, "request indisponível"
    end

    local lastError

    for attempt = 1, CONFIG.HTTP_RETRIES do
        local ok, response = pcall(REQUEST, options)

        if ok and type(response) == "table" then
            local status = tonumber(
                response.StatusCode
                or response.Status
                or response.status
            )

            local body = response.Body or response.body or ""
            local success = response.Success

            if success == nil and status then
                success = status >= 200 and status < 300
            end

            if success == true then
                return true, status, body
            end

            lastError = "HTTP " .. tostring(status) .. " " .. tostring(body)
        else
            lastError = tostring(response)
        end

        task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
    end

    return false, nil, lastError
end

local function postJson(url, data)
    local ok, _, body = requestRaw({
        Url=url,
        Method="POST",
        Headers={
            ["Content-Type"]="application/json",
        },
        Body=safeJson(data),
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
        recordType="security_fusion_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        clientVisibleOnly=true,
        generatedAt=os.time(),
        archiveRecords=Archive.Records,
        archiveBytes=Archive.Bytes,
        focus="general_security_surface_and_validation",
    }

    if callback(header) == false then
        return false
    end

    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            if ISFILE(path) then
                local ok, text = pcall(READFILE, path)
                if ok and type(text) == "string" then
                    for line in string.gmatch(text, "[^\r\n]+") do
                        local decodeOk, object = pcall(HttpService.JSONDecode, HttpService, line)
                        if decodeOk and type(object) == "table" then
                            if callback(object) == false then
                                return false
                            end
                        end
                    end
                end
            end
        end
    else
        for _, line in ipairs(Archive.MemoryLines) do
            local decodeOk, object = pcall(HttpService.JSONDecode, HttpService, line)
            if decodeOk and type(object) == "table" then
                if callback(object) == false then
                    return false
                end
            end
        end
    end

    return true
end

local function streamChunks(onChunk)
    flushPending(true)

    local current = {}
    local currentBytes = 2
    local index = 0
    local totalBytes = 0
    local streamError

    local function flush()
        if #current == 0 then
            return true
        end

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
            collectgarbage("step",180)
        end)

        return true
    end

    local iterOk = iterateObjects(function(object)
        local encoded = safeJson(object)
        local add = #encoded + 1

        if #current > 0 and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES then
            if not flush() then
                return false
            end
        end

        table.insert(current, object)
        currentBytes += add
        return true
    end)

    if not iterOk and streamError then
        return false, index, totalBytes, streamError
    end

    if #current > 0 and not flush() then
        return false, index, totalBytes, streamError
    end

    return true, index, totalBytes, nil
end

local function deleteArchive()
    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            if ISFILE(path) then
                pcall(DELFILE, path)
            end
        end

        if ISFILE(CONFIG.MANIFEST_PATH) then
            pcall(DELFILE, CONFIG.MANIFEST_PATH)
        end
    else
        table.clear(Archive.MemoryLines)
    end

    Archive.Blocks = {blockPath(1)}
    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0
    Archive.Bytes = 0
    Archive.Records = 0
    Archive.PendingLines = {}
    Archive.PendingBytes = 0
end

local function uploadAll()
    if Upload.Running or Archive.Records <= 0 then
        return
    end

    Upload.Running = true
    Upload.LastError = nil
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0
    Upload.BytesSent = 0
    Upload.TotalBytes = math.max(Archive.Bytes,1)

    Action.Text = "ENVIANDO..."
    Status.Text = "Iniciando upload..."
    updateUI(true)

    flushPending(true)
    writeManifest()

    local filename = string.format(
        "Cafeina_SecurityFusion_%s_%s.json",
        tostring(game.PlaceId),
        isoUTC()
    )

    local startOk, startData, startErr = postJson(
        CONFIG.UPLOAD_BASE .. "/start",
        {
            filename=filename,
            source=CONFIG.VERSION,
            metadata={
                scanner=CONFIG.VERSION,
                placeId=game.PlaceId,
                gameId=game.GameId,
                placeVersion=game.PlaceVersion,
                clientVisibleOnly=true,
                focus="general_security_surface_and_validation",
                persistentArchive=Archive.Persistent,
                streamingUpload=true,
                targetChunkBytes=CONFIG.UPLOAD_CHUNK_BYTES,
                outboundHook=HookInstalled,
            },
        }
    )

    if not startOk then
        Upload.Running = false
        Upload.LastError = startErr
        Status.Text = "Erro /start • dados preservados"
        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.UploadId =
        type(startData) == "table"
        and (startData.uploadId or startData.id or startData.upload_id)
        or nil

    if not Upload.UploadId then
        Upload.Running = false
        Status.Text = "/start inválido • dados preservados"
        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    local streamOk, chunkCount, payloadBytes, streamErr =
        streamChunks(function(index, objects, bytes)
            Upload.CurrentChunk = index
            updateUI(true)

            local ok, _, err = postJson(
                CONFIG.UPLOAD_BASE .. "/chunk",
                {
                    uploadId=Upload.UploadId,
                    index=index,
                    objects=objects,
                }
            )

            if not ok then
                return false, err
            end

            Upload.BytesSent += bytes
            updateUI(true)
            return true
        end)

    if not streamOk then
        Upload.Running = false
        Upload.LastError = streamErr
        Status.Text = "Erro chunk • dados preservados"
        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.TotalChunks = chunkCount
    Upload.TotalBytes = math.max(payloadBytes,1)
    Upload.BytesSent = payloadBytes
    updateUI(true)

    local finishOk, finishData, finishErr = postJson(
        CONFIG.UPLOAD_BASE .. "/finish",
        {
            uploadId=Upload.UploadId,
            totalChunks=chunkCount,
            totalBytes=payloadBytes,
            records=Archive.Records,
        }
    )

    if not finishOk then
        Upload.Running = false
        Upload.LastError = finishErr
        Status.Text = "/finish falhou • dados preservados"
        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    local confirmed =
        type(finishData) == "table"
        and (
            finishData.confirmed == true
            or finishData.success == true
            or finishData.ok == true
        )

    if not confirmed then
        Upload.Running = false
        Status.Text = "Servidor não confirmou • preservado"
        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.LastURL = tostring(
        finishData.url
        or finishData.link
        or finishData.fileUrl
        or ""
    )

    deleteArchive()

    Upload.Running = false
    Status.Text = "Upload confirmado ✓"
    Detail.Text =
        Upload.LastURL ~= ""
        and ("Link recebido • " .. string.sub(Upload.LastURL,1,70))
        or "Servidor confirmou • arquivo local limpo"

    Action.Text = "INICIAR FUSION"
    BarFill.Size = UDim2.new(1,0,1,0)
end

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    RED=Color3.fromRGB(169,42,49),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
    BAR=Color3.fromRGB(232,232,235),
}

local GuiParent = CoreGui

if type(gethui) == "function" then
    local ok, value = pcall(gethui)
    if ok and value then
        GuiParent = value
    end
end

pcall(function()
    local old = GuiParent:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

local parentOk = pcall(function()
    Gui.Parent = GuiParent
end)

if not parentOk then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(302, 202)
Main.AnchorPoint = Vector2.new(0.5,0.5)
Main.Position = UDim2.fromScale(0.5,0.44)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.STROKE
stroke.Thickness = 1
stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(10,7)
Title.Size = UDim2.new(1,-20,0,23)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • SECURITY FUSION"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(10,27)
Subtitle.Size = UDim2.new(1,-20,0,18)
Subtitle.Font = Enum.Font.Gotham
Subtitle.Text = "TOTAL SCAN + PASSIVE TRACE + SAFE AUDIT"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 9
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Main

Action = Instance.new("TextButton")
Action.Position = UDim2.fromOffset(10,50)
Action.Size = UDim2.new(1,-20,0,40)
Action.BackgroundColor3 = COLORS.BUTTON
Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "INICIAR FUSION"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

local ac = Instance.new("UICorner")
ac.CornerRadius = UDim.new(0,8)
ac.Parent = Action

Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10,97)
Status.Size = UDim2.new(1,-20,0,38)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • coleta geral + auditoria segura"
Status.TextColor3 = COLORS.TEXT
Status.TextSize = 10
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

Detail = Instance.new("TextLabel")
Detail.BackgroundTransparency = 1
Detail.Position = UDim2.fromOffset(10,137)
Detail.Size = UDim2.new(1,-20,0,37)
Detail.Font = Enum.Font.Gotham
Detail.Text = "0.00 MB • 0 registros"
Detail.TextColor3 = COLORS.MUTED
Detail.TextSize = 9
Detail.TextWrapped = true
Detail.TextXAlignment = Enum.TextXAlignment.Left
Detail.TextYAlignment = Enum.TextYAlignment.Top
Detail.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(10,184)
BarBack.Size = UDim2.new(1,-20,0,7)
BarBack.BackgroundColor3 = Color3.fromRGB(27,27,31)
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(1,0)
bc.Parent = BarBack

BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(1,0)
fc.Parent = BarFill

-- Drag support.
do
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    Main.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local lastUiClock = 0

updateUI = function(force)
    local now = os.clock()
    if not force and now - lastUiClock < 0.15 then
        return
    end
    lastUiClock = now

    if Upload.Running then
        Status.Text = string.format(
            "Enviando chunk %d%s",
            Upload.CurrentChunk,
            Upload.TotalChunks > 0 and ("/" .. tostring(Upload.TotalChunks)) or " • streaming"
        )

        local ratio =
            Upload.TotalBytes > 0
            and math.clamp(Upload.BytesSent / Upload.TotalBytes,0,1)
            or 0

        BarFill.Size = UDim2.new(ratio,0,1,0)
        Detail.Text = string.format(
            "%.2f / %.2f MB",
            mb(Upload.BytesSent),
            mb(Upload.TotalBytes)
        )
        return
    end

    BarFill.Size = UDim2.new(
        math.clamp(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES,0,1),
        0,1,0
    )

    if Session.Running then
        Status.Text = string.format(
            "Coletando • %s%s",
            Session.CurrentService,
            Session.ActiveAuditRunning and " • SAFE AUDIT" or ""
        )

        Detail.Text = string.format(
            "%.2f MB • %d regs • %d remotes • %d sensíveis • %d probes",
            mb(Archive.Bytes),
            Archive.Records,
            Session.RemoteCount,
            Session.SensitiveRemoteCount,
            Session.ActiveProbes
        )
    else
        Detail.Text = string.format(
            "%.2f MB • %d registros preservados",
            mb(Archive.Bytes),
            Archive.Records
        )
    end
end

--==============================================================--
-- SESSION
--==============================================================--

local function disconnectAll()
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end

    table.clear(Connections)
    table.clear(InboundObserved)
end

local function startDynamicObservation()
    attachDynamicRoot(ReplicatedStorage, "ReplicatedStorage")
    attachDynamicRoot(Workspace, "Workspace")
    attachDynamicRoot(Players, "Players")
end

local function begin()
    if Session.Running or Upload.Running then
        return
    end

    Session.Running = true
    Session.StopRequested = false
    Session.RunId = newRunId()
    Session.StartedClock = os.clock()
    Session.RecordsThisRun = 0
    Session.MappingDone = false
    Session.CurrentService = "initializing"
    Session.RemoteCount = 0
    Session.SensitiveRemoteCount = 0
    Session.ValueWatchCount = 0
    Session.AttributeWatchCount = 0
    Session.DynamicEvents = 0
    Session.ActiveAuditRunning = false
    Session.ActiveProbes = 0
    Session.RecentEvents = {}
    Session.LastOutbound = nil
    Session.LastInbound = nil

    Action.Text = "PARAR + ENVIAR"
    Action.BackgroundColor3 = COLORS.RED

    queueRecord({
        source="session",
        kind="session_started",
        capabilities={
            filesystem=FILESYSTEM_OK and true or false,
            request=REQUEST ~= nil,
            hookmetamethod=HOOKMETAMETHOD ~= nil,
            getnamecallmethod=GETNAMECALLMETHOD ~= nil,
        },
        policy={
            broadMapping=true,
            passiveInbound=true,
            passiveOutbound=true,
            dynamicStateCorrelation=true,
            sensitiveSurfaceScoring=true,
            conservativeActiveValidationAudit=CONFIG.ACTIVE_AUDIT_ENABLED,
            destructiveAutoFuzzing=false,
        },
        localState=localSnapshot(),
    })

    -- Prebuild remote registry before hook/observers.
    for _, root in ipairs({ReplicatedStorage, Workspace, Players}) do
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("RemoteEvent")
            or inst:IsA("RemoteFunction")
            or inst:IsA("UnreliableRemoteEvent")
            then
                local info = remoteInfoFor(inst)
                Session.RemoteCount += 1
                if info and info.sensitivityScore > 0 then
                    Session.SensitiveRemoteCount += 1
                end
            end
        end
    end

    emitRemoteCatalog()
    installHook()
    installInboundAll()
    startDynamicObservation()

    task.spawn(runBroadMapping)

    if CONFIG.ACTIVE_AUDIT_ENABLED then
        task.spawn(function()
            task.wait(CONFIG.ACTIVE_AUDIT_START_DELAY)

            if Session.Running and not Session.StopRequested then
                runActiveAudit()
            end
        end)
    end

    Session.CurrentService = "mapping + dynamic observation"
    updateUI(true)
end

local function stopAndUpload()
    if not Session.Running or Upload.Running then
        return
    end

    Session.StopRequested = true

    queueRecord({
        source="session",
        kind="session_finalized",
        recordsThisRun=Session.RecordsThisRun,
        archivedRecords=Archive.Records,
        archivedBytes=Archive.Bytes,
        mappingDone=Session.MappingDone,
        currentService=Session.CurrentService,
        remoteCount=Session.RemoteCount,
        sensitiveRemoteCount=Session.SensitiveRemoteCount,
        valueWatchCount=Session.ValueWatchCount,
        attributeWatchCount=Session.AttributeWatchCount,
        dynamicEvents=Session.DynamicEvents,
        activeProbes=Session.ActiveProbes,
        localState=localSnapshot(),
        recent=recentSnapshot(),
    })

    disconnectAll()
    flushPending(true)
    writeManifest()

    Session.Running = false
    Session.ActiveAuditRunning = false
    restoreHook()

    Action.Text = "ENVIANDO..."
    Status.Text = "Finalizando arquivo..."
    updateUI(true)

    task.spawn(function()
        task.wait(0.10)
        uploadAll()
    end)
end

Action.Activated:Connect(function()
    if Upload.Running then
        return
    end

    if Action.Text == "REENVIAR" then
        task.spawn(uploadAll)
        return
    end

    if Session.Running then
        stopAndUpload()
    else
        begin()
    end
end)

--==============================================================--
-- LOAD / CLEANUP
--==============================================================--

loadArchive()
updateUI(true)

env.__CAFEINA_SECURITY_FUSION_CONTROLLER = {
    Stop=function(reason)
        Session.StopRequested = true

        if Session.Running then
            queueRecord({
                source="session",
                kind="controller_stop",
                reason=reason or "external_stop",
            })
        end

        disconnectAll()
        flushPending(true)
        writeManifest()
        Session.Running = false
        Session.ActiveAuditRunning = false
        restoreHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] SECURITY FUSION LAB V2.0 carregado.")
