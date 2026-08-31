--==============================================================--
-- CAFEÍNA • EGG DELIVERY TRACE V1.7 • STREAMING UPLOAD
--
-- Focus: discover the REAL client-visible egg pickup/delivery flow
-- without interfering with gameplay.
--
-- IMPORTANT:
-- • INFORMATION COLLECTOR ONLY.
-- • Does NOT collect eggs.
-- • Does NOT FireServer/InvokeServer by itself.
-- • Does NOT change remote arguments or returns.
-- • Does NOT alter character / speed / collision.
--
-- Improvements over V1.5:
-- • Original game network call executes BEFORE heavy logging.
-- • Heavy serialization/file work is deferred.
-- • Inbound callbacks are deferred too.
-- • Batched archive writes instead of writing every event.
-- • Targeted static scan runs in background with yields.
-- • Upload contract matches Menutest.lua:
--     /start  -> filename, source, metadata
--     /chunk  -> uploadId, index, objects[]
--     /finish -> uploadId, totalChunks, totalBytes, records
-- • Archive erased ONLY after confirmed /finish.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "EGG_DELIVERY_TRACE_V1_7_STREAMING_UPLOAD",
    GUI_NAME = "CafeinaEggDeliveryTraceV17",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 768 * 1024,
    UPLOAD_CHUNK_BYTES = 600000,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.25,

    ARCHIVE_ROOT = "CafeinaEggTrace",
    ARCHIVE_FOLDER = "CafeinaEggTrace/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaEggTrace/" .. tostring(game.PlaceId) .. "/manifest.json",
    MANIFEST_BACKUP_PATH = "CafeinaEggTrace/" .. tostring(game.PlaceId) .. "/manifest.bak",

    -- Buffered writes: keeps disk I/O out of gameplay callbacks.
    FLUSH_INTERVAL = 0.30,
    FLUSH_AT_BYTES = 96 * 1024,

    -- While egg activity is happening, record player movement.
    TRAJECTORY_INTERVAL = 0.15,
    POST_ACTIVITY_SECONDS = 3.0,
    IDLE_HEARTBEAT_SECONDS = 4.0,

    -- Keep targeted snapshot useful but lightweight.
    STATIC_SCAN_YIELD_EVERY = 25,
    STATIC_MAX_RECORDS = 900,

    MAX_SERIALIZE_DEPTH = 6,
    MAX_TABLE_ITEMS = 120,

    EGG_REMOTE_WORDS = {
        "eggworld",
        "fieldegg",
        "askplaceegg",
        "askfieldeggcarry",
        "askfieldeggdrop",
        "askhatch",
        "askfinishhatch",
        "redeem",
        "ownerdropped",
        "ownershifted",
        "zoneprobe",
        "anchorforzone",
    },

    EGG_PAYLOAD_WORDS = {
        "egg",
        "egginventory",
        "currentareaeggclaims",
        "claim",
        "carry",
        "carried",
        "slot",
        "redeem",
        "nest",
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

-- Stop prior trace instances cleanly if re-executed.
-- V1.5 used __CAFEINA_EGG_TRACE_CONTROLLER; V1.6 uses the V16 key.
pcall(function()
    for _, key in ipairs({
        "__CAFEINA_EGG_TRACE_V17_CONTROLLER",
        "__CAFEINA_EGG_TRACE_CONTROLLER",
    }) do
        local previous = rawget(env, key)

        if type(previous) == "table"
        and type(previous.Stop) == "function"
        then
            previous.Stop("replaced_by_v16")
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
-- HELPERS
--==============================================================--

local function mb(bytes)
    return (bytes or 0) / (1024 * 1024)
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function hasAny(text, words)
    local s = lower(text)
    for _, word in ipairs(words) do
        if string.find(s, lower(word), 1, true) then
            return true
        end
    end
    return false
end

local function safePath(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    return ok and result or tostring(inst)
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
    return ok and result
        or tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

--==============================================================--
-- SAFE SERIALIZER
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
        local rx, ry, rz = value:ToOrientation()
        return {
            type="CFrame",
            x=p.X, y=p.Y, z=p.Z,
            rx=rx, ry=ry, rz=rz,
        }
    elseif tv == "Color3" then
        return {type="Color3", r=value.R, g=value.G, b=value.B}
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

            out[tostring(k)] =
                safeSerialize(v, depth + 1, seen)
        end

        seen[value] = nil
        return out
    end

    return tostring(value)
end

local function serializePacked(packed)
    local out = {
        count = packed.n or #packed,
        values = {},
    }

    for i = 1, out.count do
        out.values[i] =
            safeSerialize(packed[i])
    end

    return out
end

local function safeJson(value)
    local ok, result = pcall(
        HttpService.JSONEncode,
        HttpService,
        value
    )

    if ok then
        return result
    end

    return HttpService:JSONEncode({
        kind="serialization_error",
        error=tostring(result),
    })
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

    Carrying = false,
    EggUid = nil,
    EggState = nil,
    EggArea = nil,

    LastEggActivityClock = 0,
    LastTrajectoryClock = 0,
    LastIdleHeartbeatClock = 0,

    Transaction = nil,
    TransactionCounter = 0,
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

local ObserverConnections = {}

local RemoteInfo = setmetatable({}, {__mode="k"})

local HookInstalled = false
local OriginalNamecall = nil

--==============================================================--
-- TIME / SNAPSHOT
--==============================================================--

local function relativeTime()
    if Session.StartedClock == 0 then
        return 0
    end
    return os.clock() - Session.StartedClock
end

local function playerSnapshot()
    local character = LocalPlayer.Character

    if not character then
        return {character=false}
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    local out = {
        character=true,
        attributes=safeSerialize(character:GetAttributes()),
    }

    if root then
        out.cframe = safeSerialize(root.CFrame)
        out.position = safeSerialize(root.Position)
        out.linearVelocity = safeSerialize(root.AssemblyLinearVelocity)
        out.angularVelocity = safeSerialize(root.AssemblyAngularVelocity)
    end

    if humanoid then
        out.health = humanoid.Health
        out.maxHealth = humanoid.MaxHealth
        out.walkSpeed = humanoid.WalkSpeed
        out.floorMaterial = tostring(humanoid.FloorMaterial)

        local ok, state = pcall(function()
            return humanoid:GetState()
        end)

        if ok then
            out.humanoidState = tostring(state)
        end
    end

    return out
end

local function safeZoneMusicSnapshot()
    local result = {}

    for _, inst in ipairs(SoundService:GetDescendants()) do
        if inst:IsA("Sound")
        and contains(inst.Name, "SafeZone")
        then
            table.insert(result, {
                path=safePath(inst),
                isPlaying=inst.IsPlaying,
                volume=inst.Volume,
                timePosition=inst.TimePosition,
            })
        end
    end

    return result
end

--==============================================================--
-- FILESYSTEM / ARCHIVE
--==============================================================--

local function ensureFolder(path)
    if not FILESYSTEM_OK then
        return false
    end

    return pcall(function()
        if not ISFOLDER(path) then
            MAKEFOLDER(path)
        end
    end)
end

local function blockPath(index)
    return string.format(
        "%s/block_%06d.jsonl",
        CONFIG.ARCHIVE_FOLDER,
        index
    )
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

    local encoded = safeJson(data)

    pcall(function()
        if ISFILE(CONFIG.MANIFEST_PATH) then
            local old = READFILE(CONFIG.MANIFEST_PATH)
            if type(old) == "string" and #old > 0 then
                WRITEFILE(CONFIG.MANIFEST_BACKUP_PATH, old)
            end
        end

        WRITEFILE(CONFIG.MANIFEST_PATH, encoded)
    end)
end

local function decodeManifest(path)
    if not FILESYSTEM_OK or not ISFILE(path) then
        return nil
    end

    local ok, text = pcall(READFILE, path)
    if not ok or type(text) ~= "string" or #text == 0 then
        return nil
    end

    local decodeOk, data = pcall(
        HttpService.JSONDecode,
        HttpService,
        text
    )

    return decodeOk and type(data) == "table"
        and data
        or nil
end

local function recoverBlocksByProbe()
    local blocks = {}

    if not FILESYSTEM_OK then
        return blocks
    end

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

local function recountArchive()
    if not FILESYSTEM_OK then
        return
    end

    local bytes = 0
    local records = 0
    local currentBytes = 0

    for _, path in ipairs(Archive.Blocks) do
        if ISFILE(path) then
            local ok, text = pcall(READFILE, path)

            if ok and type(text) == "string" then
                bytes += #text

                for _ in string.gmatch(text, "[^\r\n]+") do
                    records += 1
                end

                if path == blockPath(Archive.CurrentBlock) then
                    currentBytes = #text
                end
            end
        end
    end

    Archive.Bytes = bytes
    Archive.Records = records
    Archive.CurrentBlockBytes = currentBytes
end

local function loadArchive()
    if not FILESYSTEM_OK then
        local memory = rawget(
            env,
            "__CAFEINA_EGG_TRACE_V16_MEMORY_" .. tostring(game.PlaceId)
        )

        if type(memory) == "table"
        and type(memory.lines) == "table"
        then
            Archive.MemoryLines = memory.lines
            Archive.Records = #memory.lines

            local bytes = 0
            for _, line in ipairs(memory.lines) do
                bytes += #line + 1
            end

            Archive.Bytes = bytes
        end

        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local manifest =
        decodeManifest(CONFIG.MANIFEST_PATH)
        or decodeManifest(CONFIG.MANIFEST_BACKUP_PATH)

    if manifest then
        Archive.Blocks =
            type(manifest.blocks) == "table"
            and manifest.blocks
            or {}

        Archive.CurrentBlock =
            tonumber(manifest.currentBlock)
            or math.max(1, #Archive.Blocks)
    else
        Archive.Blocks = recoverBlocksByProbe()
        Archive.CurrentBlock = math.max(1, #Archive.Blocks)
    end

    if #Archive.Blocks == 0 then
        Archive.Blocks = {blockPath(1)}
        Archive.CurrentBlock = 1
    end

    recountArchive()
    writeManifest()
end

local function appendText(path, text)
    if APPENDFILE then
        return pcall(APPENDFILE, path, text)
    end

    local existing = ""

    if ISFILE(path) then
        local ok, old = pcall(READFILE, path)
        if ok and type(old) == "string" then
            existing = old
        end
    end

    return pcall(WRITEFILE, path, existing .. text)
end

local updateUI

local function flushPending(force)
    if #Archive.PendingLines == 0 then
        if force and FILESYSTEM_OK then
            writeManifest()
        end
        return true
    end

    if not force
    and Archive.PendingBytes < CONFIG.FLUSH_AT_BYTES
    then
        return true
    end

    local lines = Archive.PendingLines
    Archive.PendingLines = {}
    Archive.PendingBytes = 0

    if not Archive.Persistent then
        for _, line in ipairs(lines) do
            table.insert(Archive.MemoryLines, string.sub(line, 1, -2))
        end

        env[
            "__CAFEINA_EGG_TRACE_V16_MEMORY_" .. tostring(game.PlaceId)
        ] = {
            lines=Archive.MemoryLines,
        }

        return true
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local batch = {}

    local function flushBatch()
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
        and Archive.CurrentBlockBytes + bytes
            > CONFIG.BLOCK_TARGET_BYTES
        then
            if not flushBatch() then
                -- Requeue what wasn't persisted.
                table.insert(Archive.PendingLines, line)
                Archive.PendingBytes += bytes
                return false
            end

            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0
        end

        table.insert(batch, line)

        -- Avoid huge concat buffers.
        if #batch >= 80 then
            if not flushBatch() then
                return false
            end
        end
    end

    local ok = flushBatch()

    if ok then
        writeManifest()
    end

    return ok
end

local function queueRecord(record)
    if not Session.Running
    and record.kind ~= "session_finalized"
    and record.kind ~= "upload_diagnostic"
    then
        return false
    end

    record.version = record.version or CONFIG.VERSION
    record.placeId = record.placeId or game.PlaceId
    record.gameId = record.gameId or game.GameId
    record.runId = record.runId or Session.RunId
    record.time = record.time or relativeTime()
    record.unix = record.unix or os.time()

    local json = safeJson(record)
    local line = json .. "\n"
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

    if updateUI then
        updateUI(false)
    end

    if Archive.PendingBytes >= CONFIG.FLUSH_AT_BYTES then
        task.defer(flushPending, true)
    end

    return true
end

-- Periodic flush loop.
task.spawn(function()
    while true do
        task.wait(CONFIG.FLUSH_INTERVAL)

        if #Archive.PendingLines > 0 then
            flushPending(true)
        end
    end
end)

--==============================================================--
-- EGG META EXTRACTION
--==============================================================--

local function findField(value, wanted, depth, seen)
    depth = depth or 0

    if depth > 6 or type(value) ~= "table" then
        return nil
    end

    seen = seen or {}

    if seen[value] then
        return nil
    end

    seen[value] = true

    for k, v in pairs(value) do
        local key = lower(k)

        for _, target in ipairs(wanted) do
            if key == lower(target) then
                seen[value] = nil
                return v
            end
        end

        if type(v) == "table" then
            local found =
                findField(v, wanted, depth + 1, seen)

            if found ~= nil then
                seen[value] = nil
                return found
            end
        end
    end

    seen[value] = nil
    return nil
end

local function extractEggMetaFromPacked(packed)
    local meta = {}

    for i = 1, packed.n do
        local value = packed[i]

        if type(value) == "table" then
            meta.uid = meta.uid or findField(value, {"Uid","UID","uid"})
            meta.state = meta.state or findField(value, {"State","state"})
            meta.carrierUserId = meta.carrierUserId
                or findField(value, {"CarrierUserId","carrierUserId"})
            meta.areaId = meta.areaId
                or findField(value, {"AreaId","areaId"})
            meta.nestId = meta.nestId
                or findField(value, {"NestId","nestId"})
            meta.position = meta.position
                or findField(value, {"Position","position"})

            if meta.isCarrying == nil then
                meta.isCarrying =
                    findField(value, {"IsCarrying","isCarrying"})
            end
        end
    end

    if meta.uid ~= nil then
        meta.uid = tostring(meta.uid)
    end

    if meta.state ~= nil then
        meta.state = tostring(meta.state)
    end

    if meta.areaId ~= nil then
        meta.areaId = tostring(meta.areaId)
    end

    meta.position = safeSerialize(meta.position)

    return meta
end

local function payloadLooksEggRelated(packed)
    local function scan(value, depth, seen)
        depth = depth or 0
        if depth > 4 then
            return false
        end

        local tv = typeof(value)

        if tv == "string" then
            return hasAny(value, CONFIG.EGG_PAYLOAD_WORDS)

        elseif tv == "Instance" then
            return hasAny(safePath(value), {
                "Egg", "CarryAreaEgg", "SafeZone", "ZoneProbe"
            })

        elseif tv == "table" then
            seen = seen or {}

            if seen[value] then
                return false
            end

            seen[value] = true

            local count = 0

            for k, v in pairs(value) do
                count += 1
                if count > 80 then
                    break
                end

                if scan(k, depth + 1, seen)
                or scan(v, depth + 1, seen)
                then
                    seen[value] = nil
                    return true
                end
            end

            seen[value] = nil
        end

        return false
    end

    for i = 1, packed.n do
        if scan(packed[i], 0, {}) then
            return true
        end
    end

    return false
end

--==============================================================--
-- TRANSACTION
--==============================================================--

local function markEggActivity()
    Session.LastEggActivityClock = os.clock()
end

local function ensureTransaction(reason, uid)
    if Session.Transaction then
        if uid and not Session.Transaction.uid then
            Session.Transaction.uid = tostring(uid)
        end

        return Session.Transaction.id
    end

    Session.TransactionCounter += 1

    Session.Transaction = {
        id=tostring(Session.RunId) .. ":egg:" .. tostring(Session.TransactionCounter),
        reason=reason,
        uid=uid and tostring(uid) or nil,
        openedAt=relativeTime(),
    }

    return Session.Transaction.id
end

local function closeTransaction(reason)
    local tx = Session.Transaction

    if not tx then
        return
    end

    Session.Transaction = nil

    queueRecord({
        source="egg_trace",
        kind="egg_transaction_closed",
        transactionId=tx.id,
        uid=tx.uid,
        openedAt=tx.openedAt,
        reason=reason,
        player=playerSnapshot(),
    })
end

--==============================================================--
-- REMOTE REGISTRY
--==============================================================--

local function classifyRemote(inst)
    if not (
        inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    ) then
        return nil
    end

    local path = safePath(inst)
    local lowPath = lower(path)

    local info = {
        path=path,
        name=inst.Name,
        className=inst.ClassName,
        traceOutbound=hasAny(lowPath, CONFIG.EGG_REMOTE_WORDS),
        traceInbound=hasAny(lowPath, CONFIG.EGG_REMOTE_WORDS),
        profileDelta=contains(lowPath, "profiledelta"),
    }

    if info.profileDelta then
        info.traceInbound = true
    end

    RemoteInfo[inst] = info
    return info
end

local function buildRemoteRegistry()
    local count = 0

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        local info = classifyRemote(inst)

        if info and (
            info.traceOutbound
            or info.traceInbound
            or info.profileDelta
        ) then
            count += 1
        end
    end

    return count
end

--==============================================================--
-- INBOUND PASSIVE OBSERVATION
--==============================================================--

local function processInbound(remote, info, packed)
    if not Session.Running or Session.StopRequested then
        return
    end

    if info.profileDelta
    and not payloadLooksEggRelated(packed)
    then
        return
    end

    markEggActivity()

    local meta = extractEggMetaFromPacked(packed)

    local tx = ensureTransaction(
        "inbound:" .. tostring(info.name),
        meta.uid
    )

    if contains(info.path, "FieldEggCarry") then
        if meta.isCarrying == true then
            Session.Carrying = true
        end

    elseif contains(info.path, "FieldEggShifted") then
        if meta.state == "Carried"
        and (
            tonumber(meta.carrierUserId) == nil
            or tonumber(meta.carrierUserId) == LocalPlayer.UserId
        )
        then
            Session.Carrying = true
            Session.EggUid = meta.uid or Session.EggUid
            Session.EggState = "Carried"
            Session.EggArea = meta.areaId or Session.EggArea

        elseif meta.state == "Dropped"
            or meta.state == "GuardCarried"
        then
            Session.Carrying = false
            Session.EggState = meta.state

        elseif meta.state == "Slot" then
            Session.Carrying = false
            Session.EggState = "Slot"
        end
    end

    queueRecord({
        source="network_in",
        kind="remote_received",
        transactionId=tx,

        remote={
            name=info.name,
            className=info.className,
            path=info.path,
        },

        payload=serializePacked(packed),
        egg=meta,

        carry={
            active=Session.Carrying,
            uid=Session.EggUid,
            state=Session.EggState,
            area=Session.EggArea,
        },

        player=playerSnapshot(),
        safeZoneMusic=safeZoneMusicSnapshot(),
    })

    if contains(info.path, "FieldEggRedeemVerdict")
    or (
        contains(info.path, "FieldEggShifted")
        and meta.state == "Slot"
    )
    then
        task.delay(0.30, function()
            if Session.Running then
                closeTransaction("delivery_signal")
            end
        end)
    end
end

local ObservedInbound = setmetatable({}, {__mode="k"})

local function attachInbound(remote, info)
    if ObservedInbound[remote] then
        return
    end

    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("UnreliableRemoteEvent")
    ) then
        return
    end

    if not info.traceInbound then
        return
    end

    ObservedInbound[remote] = true

    local connection =
        remote.OnClientEvent:
        Connect(function(...)
            if not Session.Running
            or Session.StopRequested
            then
                return
            end

            -- Critical point:
            -- do almost nothing in the game's event callback.
            local packed = table.pack(...)

            task.defer(
                processInbound,
                remote,
                info,
                packed
            )
        end)

    table.insert(ObserverConnections, connection)
end

local function installInboundObservers()
    local count = 0

    for remote, info in pairs(RemoteInfo) do
        if info.traceInbound
        and (
            remote:IsA("RemoteEvent")
            or remote:IsA("UnreliableRemoteEvent")
        )
        then
            attachInbound(remote, info)
            count += 1
        end
    end

    local added =
        ReplicatedStorage.DescendantAdded:
        Connect(function(inst)
            if not (
                inst:IsA("RemoteEvent")
                or inst:IsA("RemoteFunction")
                or inst:IsA("UnreliableRemoteEvent")
            ) then
                return
            end

            local info = classifyRemote(inst)

            if info and info.traceInbound then
                attachInbound(inst, info)
            end
        end)

    table.insert(ObserverConnections, added)

    queueRecord({
        source="session",
        kind="inbound_observers_ready",
        count=count,
    })
end

--==============================================================--
-- OUTBOUND PASSIVE TAP
--==============================================================--

local function processOutbound(
    info,
    method,
    packedArgs,
    packedReturns,
    duration,
    callerIsExecutor
)
    if not Session.Running or Session.StopRequested then
        return
    end

    markEggActivity()

    local meta = extractEggMetaFromPacked(packedArgs)
    local tx = ensureTransaction(
        "outbound:" .. tostring(info.name),
        meta.uid
    )

    queueRecord({
        source="network_out",
        kind=method == "InvokeServer"
            and "remote_invoke"
            or "remote_fire",

        transactionId=tx,

        remote={
            name=info.name,
            className=info.className,
            path=info.path,
        },

        method=method,
        callerIsExecutor=callerIsExecutor,

        payload=serializePacked(packedArgs),

        egg=meta,

        duration=duration,

        returns=method == "InvokeServer"
            and serializePacked(packedReturns)
            or nil,

        player=playerSnapshot(),
        safeZoneMusic=safeZoneMusicSnapshot(),
    })
end

local function installOutboundHook()
    if HookInstalled then
        return true
    end

    if not HOOKMETAMETHOD
    or not GETNAMECALLMETHOD
    then
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

        -- Ultra-fast path for almost every namecall in the game.
        if not Session.Running
        or Session.StopRequested
        or (
            method ~= "FireServer"
            and method ~= "InvokeServer"
        )
        then
            return oldNamecall(self, ...)
        end

        local info = RemoteInfo[self]

        if not info or not info.traceOutbound then
            return oldNamecall(self, ...)
        end

        -- Copy references only. No JSON, file writes, GetFullName,
        -- character reads or recursion BEFORE the original game call.
        local packedArgs = table.pack(...)

        local callerIsExecutor = false

        if CHECKCALLER then
            local ok, value = pcall(CHECKCALLER)
            callerIsExecutor = ok and value == true
        end

        local started = os.clock()

        -- The game's REAL call happens immediately.
        local packedReturns =
            table.pack(
                oldNamecall(
                    self,
                    table.unpack(
                        packedArgs,
                        1,
                        packedArgs.n
                    )
                )
            )

        local duration = os.clock() - started

        -- Heavy logging happens only after the original call returned.
        task.defer(
            processOutbound,
            info,
            method,
            packedArgs,
            packedReturns,
            duration,
            callerIsExecutor
        )

        return table.unpack(
            packedReturns,
            1,
            packedReturns.n
        )
    end

    if NEWCCLOSURE then
        wrapper = NEWCCLOSURE(wrapper)
    end

    local ok, old = pcall(
        HOOKMETAMETHOD,
        game,
        "__namecall",
        wrapper
    )

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
        passiveTap=true,
        heavyWorkDeferred=true,
    })

    return true
end

local function restoreOutboundHook()
    if not HookInstalled
    or not HOOKMETAMETHOD
    or type(OriginalNamecall) ~= "function"
    then
        return
    end

    -- Best-effort restoration. If executor rejects it, the inactive hook's
    -- fast path still forwards directly to the previous namecall.
    pcall(
        HOOKMETAMETHOD,
        game,
        "__namecall",
        OriginalNamecall
    )

    HookInstalled = false
end

--==============================================================--
-- PROMPT OBSERVATION
--==============================================================--

local function isEggPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") then
        return false
    end

    return hasAny(
        table.concat({
            prompt.Name,
            prompt.ActionText,
            prompt.ObjectText,
            prompt.Parent and prompt.Parent.Name or "",
            safePath(prompt),
        }, " "),
        {"egg", "carryareaegg", "steal"}
    )
end

local ObservedPrompts = setmetatable({}, {__mode="k"})

local function processPrompt(kind, prompt, player)
    if not Session.Running
    or Session.StopRequested
    or (player and player ~= LocalPlayer)
    then
        return
    end

    markEggActivity()

    local tx = ensureTransaction(
        "prompt:" .. kind,
        nil
    )

    queueRecord({
        source="interaction",
        kind=kind,
        transactionId=tx,

        prompt={
            path=safePath(prompt),
            actionText=prompt.ActionText,
            objectText=prompt.ObjectText,
            holdDuration=prompt.HoldDuration,
            maxActivationDistance=prompt.MaxActivationDistance,
            enabled=prompt.Enabled,
        },

        player=playerSnapshot(),
    })
end

local function attachPrompt(prompt)
    if ObservedPrompts[prompt] or not isEggPrompt(prompt) then
        return
    end

    ObservedPrompts[prompt] = true

    table.insert(
        ObserverConnections,
        prompt.PromptButtonHoldBegan:
        Connect(function(player)
            task.defer(
                processPrompt,
                "egg_prompt_hold_began",
                prompt,
                player
            )
        end)
    )

    table.insert(
        ObserverConnections,
        prompt.PromptButtonHoldEnded:
        Connect(function(player)
            task.defer(
                processPrompt,
                "egg_prompt_hold_ended",
                prompt,
                player
            )
        end)
    )

    table.insert(
        ObserverConnections,
        prompt.Triggered:
        Connect(function(player)
            task.defer(
                processPrompt,
                "egg_prompt_triggered",
                prompt,
                player
            )
        end)
    )
end

local function installPromptObservers()
    local count = 0

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("ProximityPrompt")
        and isEggPrompt(inst)
        then
            attachPrompt(inst)
            count += 1

            if count % 30 == 0 then
                task.wait()
            end
        end
    end

    local connection =
        Workspace.DescendantAdded:
        Connect(function(inst)
            if inst:IsA("ProximityPrompt") then
                task.defer(function()
                    if isEggPrompt(inst) then
                        attachPrompt(inst)
                    end
                end)
            end
        end)

    table.insert(ObserverConnections, connection)

    queueRecord({
        source="session",
        kind="egg_prompt_observers_ready",
        count=count,
    })
end

--==============================================================--
-- LIGHT TARGETED STATIC SNAPSHOT
--==============================================================--

local function snapshotCandidate(inst, reason)
    local record = {
        source="target_scan",
        kind="egg_world_candidate",
        reason=reason,
        className=inst.ClassName,
        name=inst.Name,
        path=safePath(inst),
        attributes=safeSerialize(inst:GetAttributes()),
    }

    if inst:IsA("BasePart") then
        record.position=safeSerialize(inst.Position)
        record.cframe=safeSerialize(inst.CFrame)
        record.size=safeSerialize(inst.Size)
        record.canCollide=inst.CanCollide
        record.canTouch=inst.CanTouch
        record.canQuery=inst.CanQuery

    elseif inst:IsA("Attachment") then
        record.position=safeSerialize(inst.WorldPosition)
        record.cframe=safeSerialize(inst.WorldCFrame)

    elseif inst:IsA("Sound") then
        record.sound={
            soundId=inst.SoundId,
            isPlaying=inst.IsPlaying,
            volume=inst.Volume,
        }

    elseif inst:IsA("ProximityPrompt") then
        record.prompt={
            actionText=inst.ActionText,
            objectText=inst.ObjectText,
            holdDuration=inst.HoldDuration,
            maxActivationDistance=inst.MaxActivationDistance,
            enabled=inst.Enabled,
        }

    elseif inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    then
        record.remote={type=inst.ClassName}
    end

    queueRecord(record)
end

local function targetedSnapshot()
    local recorded = 0
    local scanned = 0

    local function maybeRecord(inst, reason, words)
        scanned += 1

        if recorded >= CONFIG.STATIC_MAX_RECORDS then
            return false
        end

        local path = safePath(inst)

        if hasAny(path, words) then
            snapshotCandidate(inst, reason)
            recorded += 1
        end

        if scanned % CONFIG.STATIC_SCAN_YIELD_EVERY == 0 then
            task.wait()
        end

        return true
    end

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if not Session.Running or Session.StopRequested then
            break
        end

        if not maybeRecord(
            inst,
            "replicated_target",
            {
                "EggWorld",
                "ZoneProbe",
                "SafeZoneBarriers",
                "SafeZoneMusic",
                "ProfileMirror",
                "EggInventory",
                "CurrentAreaEggClaims",
            }
        ) then
            break
        end
    end

    if recorded < CONFIG.STATIC_MAX_RECORDS then
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if not Session.Running or Session.StopRequested then
                break
            end

            if not maybeRecord(
                inst,
                "workspace_target",
                {
                    "CarryAreaEgg",
                    "AreaEggSlotsClient",
                    "SafeZone",
                    "Safe Zone",
                    "EggSlot",
                    "Redeem",
                    "SpawnPoint",
                    "CenterPoint",
                }
            ) then
                break
            end
        end
    end

    queueRecord({
        source="target_scan",
        kind="target_snapshot_complete",
        recorded=recorded,
        scanned=scanned,
        capped=recorded >= CONFIG.STATIC_MAX_RECORDS,
        player=playerSnapshot(),
    })
end

--==============================================================--
-- TRAJECTORY
--==============================================================--

RunService.Heartbeat:
Connect(function()
    if not Session.Running or Session.StopRequested then
        return
    end

    local now = os.clock()

    local active =
        Session.Carrying
        or (
            Session.LastEggActivityClock > 0
            and now - Session.LastEggActivityClock
                <= CONFIG.POST_ACTIVITY_SECONDS
        )

    if active then
        if now - Session.LastTrajectoryClock
            >= CONFIG.TRAJECTORY_INTERVAL
        then
            Session.LastTrajectoryClock = now

            task.defer(function()
                if not Session.Running then
                    return
                end

                queueRecord({
                    source="trajectory",
                    kind="egg_player_trajectory",

                    transactionId=
                        Session.Transaction
                        and Session.Transaction.id
                        or nil,

                    carry={
                        active=Session.Carrying,
                        uid=Session.EggUid,
                        state=Session.EggState,
                        area=Session.EggArea,
                    },

                    player=playerSnapshot(),
                    safeZoneMusic=safeZoneMusicSnapshot(),
                })
            end)
        end
    elseif now - Session.LastIdleHeartbeatClock
        >= CONFIG.IDLE_HEARTBEAT_SECONDS
    then
        Session.LastIdleHeartbeatClock = now

        task.defer(function()
            if Session.Running then
                queueRecord({
                    source="trajectory",
                    kind="idle_position_heartbeat",
                    player=playerSnapshot(),
                })
            end
        end)
    end
end)

--==============================================================--
-- UI • COMPACT BLACK
--==============================================================--

local COLORS = {
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(45,45,52),
    BUTTON=Color3.fromRGB(31,31,36),
    RED=Color3.fromRGB(168,42,48),
    RED_DARK=Color3.fromRGB(87,28,32),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(155,155,165),
    BAR=Color3.fromRGB(230,230,234),
}

local GuiParent = CoreGui

if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then
        GuiParent = result
    end
end

pcall(function()
    local old = GuiParent:FindFirstChild(CONFIG.GUI_NAME)
    if old then
        old:Destroy()
    end
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
Main.Size = UDim2.fromOffset(242, 160)
Main.Position = UDim2.new(0.5, -121, 0.45, -80)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.STROKE
stroke.Thickness = 1
stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(8, 6)
Title.Size = UDim2.new(1, -16, 0, 21)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • EGG TRACE V1.7"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local ActionButton = Instance.new("TextButton")
ActionButton.Size = UDim2.new(1, -16, 0, 37)
ActionButton.Position = UDim2.fromOffset(8, 32)
ActionButton.BackgroundColor3 = COLORS.BUTTON
ActionButton.BorderSizePixel = 0
ActionButton.AutoButtonColor = false
ActionButton.Text = "INICIAR COLETA"
ActionButton.TextColor3 = COLORS.TEXT
ActionButton.TextSize = 11
ActionButton.Font = Enum.Font.GothamBold
ActionButton.Parent = Main

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 7)
actionCorner.Parent = ActionButton

local StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.Position = UDim2.fromOffset(8, 76)
StatusLabel.Size = UDim2.new(1, -16, 0, 18)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Pronto • somente observação"
StatusLabel.TextColor3 = COLORS.TEXT
StatusLabel.TextSize = 10
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Main

local DetailLabel = Instance.new("TextLabel")
DetailLabel.BackgroundTransparency = 1
DetailLabel.Position = UDim2.fromOffset(8, 95)
DetailLabel.Size = UDim2.new(1, -16, 0, 32)
DetailLabel.Font = Enum.Font.Gotham
DetailLabel.Text = "0.00 MB • 0 registros"
DetailLabel.TextColor3 = COLORS.MUTED
DetailLabel.TextSize = 9
DetailLabel.TextWrapped = true
DetailLabel.TextXAlignment = Enum.TextXAlignment.Left
DetailLabel.TextYAlignment = Enum.TextYAlignment.Top
DetailLabel.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(8, 137)
BarBack.Size = UDim2.new(1, -16, 0, 7)
BarBack.BackgroundColor3 = Color3.fromRGB(27,27,31)
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1,0)
barCorner.Parent = BarBack

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1,0)
fillCorner.Parent = BarFill

-- Drag mobile/PC.
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
        local ratio = Upload.TotalBytes > 0
            and math.clamp(Upload.BytesSent / Upload.TotalBytes, 0, 1)
            or 0

        BarFill.Size = UDim2.new(ratio, 0, 1, 0)

        if Upload.TotalChunks and Upload.TotalChunks > 0 then
            StatusLabel.Text = string.format(
                "Enviando chunk %d/%d",
                Upload.CurrentChunk,
                Upload.TotalChunks
            )
        else
            StatusLabel.Text = string.format(
                "Enviando chunk %d • streaming",
                Upload.CurrentChunk
            )
        end

        DetailLabel.Text = string.format(
            "%.2f / %.2f MB",
            mb(Upload.BytesSent),
            mb(Upload.TotalBytes)
        )

        return
    end

    local ratio = math.clamp(
        Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES,
        0,
        1
    )

    BarFill.Size = UDim2.new(ratio, 0, 1, 0)

    if Session.Running then
        StatusLabel.Text =
            Session.Carrying
            and "Coletando • ovo carregado"
            or "Coletando • jogue normalmente"

        DetailLabel.Text = string.format(
            "%.2f MB • %d registros • %s",
            mb(Archive.Bytes),
            Archive.Records,
            HookInstalled and "IN+OUT" or "IN apenas"
        )
    else
        DetailLabel.Text = string.format(
            "%.2f MB • %d registros",
            mb(Archive.Bytes),
            Archive.Records
        )
    end
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

            local body =
                response.Body
                or response.body
                or ""

            local success = response.Success

            if success == nil and status then
                success = status >= 200 and status < 300
            end

            if success == true then
                return true, status, body
            end

            lastError =
                "HTTP " .. tostring(status)
                .. " " .. tostring(body)
        else
            lastError = tostring(response)
        end

        task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
    end

    return false, nil, lastError
end

local function httpPostJson(url, data)
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

    local decodeOk, decoded = pcall(
        HttpService.JSONDecode,
        HttpService,
        body
    )

    if decodeOk then
        return true, decoded, nil
    end

    return true, {raw=body}, nil
end

local function iterateArchiveObjects(callback)
    local header = {
        recordType="egg_delivery_trace_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        clientVisibleOnly=true,
        observationalOnly=true,
        generatedAt=os.time(),
        archiveRecords=Archive.Records,
        archiveBytes=Archive.Bytes,
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
                        local decodeOk, object = pcall(
                            HttpService.JSONDecode,
                            HttpService,
                            line
                        )

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
            local decodeOk, object = pcall(
                HttpService.JSONDecode,
                HttpService,
                line
            )

            if decodeOk and type(object) == "table" then
                if callback(object) == false then
                    return false
                end
            end
        end
    end

    return true
end

local function streamArchiveChunks(onChunk)
    -- Flush everything first so the stream sees a stable archive.
    flushPending(true)

    local current = {}
    local currentBytes = 2 -- opening + closing []

    local chunkIndex = 0
    local totalPayloadBytes = 0
    local streamError = nil

    local function flushChunk()
        if #current == 0 then
            return true
        end

        chunkIndex += 1

        -- currentBytes was tracked without having to JSON-encode
        -- the whole array again. Actual [] + commas is about -1 byte.
        local payloadBytes =
            math.max(2, currentBytes - 1)

        local objects = current

        -- Drop our reference before the network request returns so the
        -- next chunk cannot accidentally accumulate alongside this one.
        current = {}
        currentBytes = 2

        local ok, err =
            onChunk(
                chunkIndex,
                objects,
                payloadBytes
            )

        -- Release the large object array as soon as the request finishes.
        table.clear(objects)
        objects = nil

        if not ok then
            streamError = err
            return false
        end

        totalPayloadBytes += payloadBytes

        -- Give Roblox/executor a frame to reclaim temporary JSON/request
        -- strings before reading/building the next chunk.
        task.wait()

        pcall(function()
            collectgarbage("step", 200)
        end)

        return true
    end

    local iterOk =
        iterateArchiveObjects(
            function(object)
                local encoded =
                    safeJson(object)

                local add =
                    #encoded + 1

                if #current > 0
                and currentBytes + add
                    > CONFIG.UPLOAD_CHUNK_BYTES
                then
                    if not flushChunk() then
                        return false
                    end
                end

                table.insert(
                    current,
                    object
                )

                currentBytes += add

                return true
            end
        )

    if not iterOk and streamError then
        return false, chunkIndex, totalPayloadBytes, streamError
    end

    if #current > 0 then
        if not flushChunk() then
            return false, chunkIndex, totalPayloadBytes, streamError
        end
    end

    return true, chunkIndex, totalPayloadBytes, nil
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
    else
        table.clear(Archive.MemoryLines)

        env[
            "__CAFEINA_EGG_TRACE_V16_MEMORY_" .. tostring(game.PlaceId)
        ] = {lines={}}
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

    Upload.UploadId = nil
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0
    Upload.BytesSent = 0

    -- During streaming we do not need the final byte count in advance.
    -- Use archived bytes as a progress denominator only.
    Upload.TotalBytes =
        math.max(
            1,
            Archive.Bytes
        )

    ActionButton.Text = "ENVIANDO..."
    ActionButton.BackgroundColor3 =
        COLORS.RED_DARK

    StatusLabel.Text =
        "Iniciando upload streaming..."

    updateUI(true)

    flushPending(true)
    writeManifest()

    local fileName = string.format(
        "Cafeina_EggTrace_%s_%s.json",
        tostring(game.PlaceId),
        isoUTC()
    )

    -- /start first. No need to build or count every chunk in RAM.
    local startOk, startData, startErr =
        httpPostJson(
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
                    focus="egg_delivery_trace",
                    passive=true,
                    streamingUpload=true,
                    targetChunkBytes=
                        CONFIG.UPLOAD_CHUNK_BYTES,
                    archiveBytes=
                        Archive.Bytes,
                    archiveRecords=
                        Archive.Records,
                    outboundHook=
                        HookInstalled,
                },
            }
        )

    if not startOk then
        Upload.Running = false
        Upload.LastError = startErr

        StatusLabel.Text =
            "Erro /start • dados preservados"

        ActionButton.Text =
            "REENVIAR ARQUIVO"

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

        StatusLabel.Text =
            "/start inválido • dados preservados"

        ActionButton.Text =
            "REENVIAR ARQUIVO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    local streamOk,
        sentChunks,
        sentPayloadBytes,
        streamErr =
        streamArchiveChunks(
            function(index, objects, payloadBytes)
                Upload.CurrentChunk = index

                -- TotalChunks intentionally remains 0 while streaming.
                -- This prevents a pre-scan that would duplicate memory use.
                updateUI(true)

                local chunkOk,
                    _,
                    chunkErr =
                    httpPostJson(
                        CONFIG.UPLOAD_BASE
                            .. "/chunk",
                        {
                            uploadId =
                                Upload.UploadId,

                            index =
                                index,

                            objects =
                                objects,
                        }
                    )

                if not chunkOk then
                    return false, chunkErr
                end

                Upload.BytesSent +=
                    payloadBytes

                updateUI(true)

                return true
            end
        )

    if not streamOk then
        Upload.Running = false
        Upload.LastError = streamErr

        StatusLabel.Text =
            "Erro no chunk • dados preservados"

        ActionButton.Text =
            "REENVIAR ARQUIVO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    Upload.TotalChunks =
        sentChunks

    -- Switch from approximate archive denominator to the actual streamed
    -- JSON-array payload size for the final state.
    Upload.TotalBytes =
        math.max(
            1,
            sentPayloadBytes
        )

    Upload.BytesSent =
        sentPayloadBytes

    updateUI(true)

    local finishOk,
        finishData,
        finishErr =
        httpPostJson(
            CONFIG.UPLOAD_BASE .. "/finish",
            {
                uploadId =
                    Upload.UploadId,

                totalChunks =
                    sentChunks,

                totalBytes =
                    sentPayloadBytes,

                records =
                    Archive.Records,
            }
        )

    if not finishOk then
        Upload.Running = false
        Upload.LastError = finishErr

        StatusLabel.Text =
            "/finish falhou • dados preservados"

        ActionButton.Text =
            "REENVIAR ARQUIVO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

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

        StatusLabel.Text =
            "Servidor não confirmou • preservado"

        ActionButton.Text =
            "REENVIAR ARQUIVO"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    Upload.LastURL =
        tostring(
            finishData.url
            or finishData.link
            or finishData.fileUrl
            or ""
        )

    deleteArchiveAfterConfirmedUpload()

    Upload.Running = false

    StatusLabel.Text =
        "Upload confirmado ✓"

    DetailLabel.Text =
        Upload.LastURL ~= ""
        and (
            "Link recebido • "
            .. string.sub(
                Upload.LastURL,
                1,
                70
            )
        )
        or
        "Servidor confirmou • archive local limpo"

    ActionButton.Text =
        "INICIAR COLETA"

    ActionButton.BackgroundColor3 =
        COLORS.BUTTON

    BarFill.Size =
        UDim2.new(
            1,
            0,
            1,
            0
        )
end

--==============================================================--
-- SESSION START / STOP
--==============================================================--

local function disconnectObservers()
    for _, connection in ipairs(ObserverConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(ObserverConnections)
    table.clear(ObservedInbound)
    table.clear(ObservedPrompts)
end

local function beginSession()
    if Session.Running or Upload.Running then
        return
    end

    Session.Running = true
    Session.StopRequested = false
    Session.RunId = newRunId()
    Session.StartedClock = os.clock()
    Session.RecordsThisRun = 0

    Session.Carrying = false
    Session.EggUid = nil
    Session.EggState = nil
    Session.EggArea = nil

    Session.LastEggActivityClock = 0
    Session.LastTrajectoryClock = 0
    Session.LastIdleHeartbeatClock = 0

    Session.Transaction = nil
    Session.TransactionCounter = 0

    ActionButton.Text = "ENCERRAR + ENVIAR"
    ActionButton.BackgroundColor3 = COLORS.RED

    local registered = buildRemoteRegistry()

    queueRecord({
        source="session",
        kind="session_started",

        capabilities={
            filesystem=FILESYSTEM_OK and true or false,
            appendfile=APPENDFILE ~= nil,
            request=REQUEST ~= nil,
            hookmetamethod=HOOKMETAMETHOD ~= nil,
            getnamecallmethod=GETNAMECALLMETHOD ~= nil,
        },

        registeredRelevantRemotes=registered,
        player=playerSnapshot(),
    })

    installOutboundHook()
    installInboundObservers()

    -- These setup scans are intentionally background/yielding.
    task.spawn(function()
        task.wait(0.20)

        if Session.Running then
            installPromptObservers()
        end
    end)

    task.spawn(function()
        task.wait(0.60)

        if Session.Running then
            targetedSnapshot()
        end
    end)

    StatusLabel.Text = "Coletando • jogue normalmente"
    updateUI(true)
end

local function stopSessionAndUpload()
    if not Session.Running or Upload.Running then
        return
    end

    Session.StopRequested = true

    if Session.Transaction then
        -- closeTransaction needs queueRecord while Running is still true.
        closeTransaction("manual_stop")
    end

    queueRecord({
        source="session",
        kind="session_finalized",

        recordsThisRun=Session.RecordsThisRun,
        archivedRecords=Archive.Records,
        archivedBytes=Archive.Bytes,

        carry={
            active=Session.Carrying,
            uid=Session.EggUid,
            state=Session.EggState,
            area=Session.EggArea,
        },

        player=playerSnapshot(),
    })

    disconnectObservers()

    flushPending(true)
    writeManifest()

    Session.Running = false

    -- Restore hook before upload so upload's own HTTP/JSON operations
    -- have zero relation to game network tapping.
    restoreOutboundHook()

    ActionButton.Text = "ENVIANDO..."
    ActionButton.BackgroundColor3 = COLORS.RED_DARK
    StatusLabel.Text = "Finalizando archive..."
    updateUI(true)

    task.spawn(function()
        task.wait(0.10)
        uploadAll()
    end)
end

ActionButton.Activated:
Connect(function()
    if Upload.Running then
        return
    end

    if ActionButton.Text == "REENVIAR ARQUIVO" then
        task.spawn(uploadAll)
        return
    end

    if Session.Running then
        stopSessionAndUpload()
    else
        beginSession()
    end
end)

--==============================================================--
-- INITIAL LOAD
--==============================================================--

loadArchive()

if Archive.Records > 0 then
    StatusLabel.Text = "Arquivo anterior recuperado"
    DetailLabel.Text = string.format(
        "%.2f MB • %d registros preservados",
        mb(Archive.Bytes),
        Archive.Records
    )
end

updateUI(true)

--==============================================================--
-- CONTROLLER / CLEANUP
--==============================================================--

env.__CAFEINA_EGG_TRACE_V17_CONTROLLER = {
    Gui=Gui,

    Stop=function(reason)
        Session.StopRequested = true

        if Session.Running then
            queueRecord({
                source="session",
                kind="controller_stop",
                reason=reason or "external_stop",
            })
        end

        disconnectObservers()
        flushPending(true)
        writeManifest()
        Session.Running = false
        restoreOutboundHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

Gui.Destroying:
Connect(function()
    pcall(function()
        Session.StopRequested = true
        disconnectObservers()
        flushPending(true)
        writeManifest()
        Session.Running = false
        restoreOutboundHook()
    end)
end)

print(
    "[CAFEÍNA] EGG DELIVERY TRACE V1.7 STREAMING UPLOAD carregado."
)
