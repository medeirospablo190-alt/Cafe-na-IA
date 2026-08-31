--==============================================================--
-- CAFEÍNA • EGG DELIVERY TRACE V1.5
-- Specialized build based on Menutest.lua compact flow
--
-- TARGET GAME OBSERVED:
-- PlaceId: 107778070777162
--
-- PURPOSE:
-- • Discover the REAL client-visible egg delivery flow.
-- • Capture outbound EggWorld RemoteFunction/RemoteEvent calls.
-- • Capture InvokeServer returns without modifying them.
-- • Capture inbound FieldEggCarry / Shifted / Gone / RedeemVerdict.
-- • Capture ZoneProbe / ProfileMirror egg-related traffic.
-- • Correlate all of the above with player CFrame / velocity / carry state.
-- • Snapshot SafeZone / SafeZoneBarriers / CarryAreaEgg candidates.
-- • Persistent archive.
-- • Auto-upload only after user presses ENCERRAR.
-- • Archive is deleted ONLY after confirmed /finish.
--
-- IMPORTANT:
-- This tracer is observational. It does NOT:
-- • Fire arbitrary remotes.
-- • Modify arguments.
-- • Block server calls.
-- • Fake delivery.
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
    VERSION = "EGG_DELIVERY_TRACE_V1_5",
    GUI_NAME = "CafeinaEggDeliveryTraceV15",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    MAX_ARCHIVE_BYTES = 150 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 3200000,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.25,

    ARCHIVE_ROOT = "CafeinaEggTrace",
    PLACE_FOLDER = "CafeinaEggTrace/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaEggTrace/" .. tostring(game.PlaceId) .. "/manifest.json",
    MANIFEST_BACKUP_PATH = "CafeinaEggTrace/" .. tostring(game.PlaceId) .. "/manifest.bak",

    TRAJECTORY_INTERVAL = 0.12,
    TRAJECTORY_POST_SECONDS = 3.0,
    IDLE_HEARTBEAT_SECONDS = 3.0,

    MAX_SERIALIZE_DEPTH = 6,
    MAX_TABLE_ITEMS = 100,

    EGG_KEYWORDS = {
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

    IMPORTANT_INBOUND = {
        "FieldEggCarry",
        "FieldEggShifted",
        "FieldEggGone",
        "FieldEggRedeemVerdict",
        "FieldEggBatchShifted",
        "OwnerDropped",
        "OwnerShifted",
        "AnchorForZone",
        "ProfileDelta",
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

local httpRequest
pcall(function()
    if http and type(http.request) == "function" then
        httpRequest = http.request
    end
end)

local REQUEST = pickFunction(
    rawget(env, "request"),
    rawget(env, "http_request"),
    httpRequest,
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

if FILESYSTEM_OK and not APPENDFILE then
    CONFIG.BLOCK_TARGET_BYTES = 512 * 1024
end

--==============================================================--
-- HELPERS
--==============================================================--

local function mb(bytes)
    return (bytes or 0) / (1024 * 1024)
end

local function nowUTCName()
    local t = os.date("!*t")
    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        t.year, t.month, t.day,
        t.hour, t.min, t.sec
    )
end

local function guid()
    local ok, value = pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    if ok then
        return value
    end
    return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

local function safePath(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, path = pcall(function()
        return inst:GetFullName()
    end)

    return ok and path or tostring(inst)
end

local function lower(v)
    return string.lower(tostring(v or ""))
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

local function shallowContainsEgg(value, depth, seen)
    depth = depth or 0
    if depth > 4 then
        return false
    end

    local tv = typeof(value)

    if tv == "string" then
        local s = lower(value)
        return
            string.find(s, "egg", 1, true) ~= nil
            or string.find(s, "claim", 1, true) ~= nil
            or string.find(s, "carry", 1, true) ~= nil
            or string.find(s, "slot", 1, true) ~= nil
            or string.find(s, "redeem", 1, true) ~= nil

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

            if shallowContainsEgg(k, depth + 1, seen)
            or shallowContainsEgg(v, depth + 1, seen)
            then
                seen[value] = nil
                return true
            end
        end

        seen[value] = nil
    end

    return false
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

    elseif tv == "string"
    or tv == "boolean"
    then
        return value

    elseif tv == "number" then
        if value ~= value then
            return "<nan>"
        elseif value == math.huge then
            return "<inf>"
        elseif value == -math.huge then
            return "<-inf>"
        end
        return value

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

    elseif tv == "CFrame" then
        local p = value.Position
        local rx, ry, rz = value:ToOrientation()

        return {
            type = "CFrame",
            x = p.X,
            y = p.Y,
            z = p.Z,
            rx = rx,
            ry = ry,
            rz = rz,
        }

    elseif tv == "Instance" then
        return {
            type = "Instance",
            className = value.ClassName,
            name = value.Name,
            path = safePath(value),
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

local function packSerialized(...)
    local n = select("#", ...)
    local out = {
        argc = n,
        args = {},
    }

    for i = 1, n do
        out.args[i] =
            safeSerialize(select(i, ...))
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
        kind = "serialization_error",
        error = tostring(result),
    })
end

--==============================================================--
-- SESSION / ARCHIVE
--==============================================================--

local Session = {
    Running = false,
    StopRequested = false,
    StartedAtClock = 0,
    StartedAtUnix = 0,
    RunId = nil,

    Records = 0,

    Carrying = false,
    EggUid = nil,
    EggState = nil,
    EggArea = nil,

    LastEggActivity = 0,
    LastTrajectory = 0,
    LastIdleHeartbeat = 0,

    CurrentTransaction = nil,
    TransactionCounter = 0,
}

local Archive = {
    Persistent = FILESYSTEM_OK and true or false,

    Blocks = {},
    CurrentBlock = 1,
    CurrentBlockBytes = 0,

    Bytes = 0,
    Records = 0,

    MemoryLines = {},
}

local Upload = {
    Running = false,
    UploadId = nil,
    CurrentChunk = 0,
    TotalChunks = 0,
    BytesSent = 0,
    TotalBytes = 0,
}

local ObserverConnections = {}

local OriginalNamecall = nil
local HookInstalled = false

--==============================================================--
-- TIME / PLAYER SNAPSHOT
--==============================================================--

local function relativeTime()
    if Session.StartedAtClock == 0 then
        return 0
    end
    return os.clock() - Session.StartedAtClock
end

local function characterSnapshot()
    local char = LocalPlayer.Character
    if not char then
        return {
            character = false,
        }
    end

    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    local result = {
        character = true,
    }

    if root then
        result.cframe = safeSerialize(root.CFrame)
        result.position = safeSerialize(root.Position)
        result.linearVelocity =
            safeSerialize(root.AssemblyLinearVelocity)
        result.angularVelocity =
            safeSerialize(root.AssemblyAngularVelocity)
    end

    if humanoid then
        result.health = humanoid.Health
        result.maxHealth = humanoid.MaxHealth
        result.walkSpeed = humanoid.WalkSpeed
        result.floorMaterial = tostring(humanoid.FloorMaterial)

        local ok, state = pcall(function()
            return humanoid:GetState()
        end)

        if ok then
            result.humanoidState =
                tostring(state)
        end
    end

    result.attributes =
        safeSerialize(char:GetAttributes())

    return result
end

local function safeZoneMusicState()
    local sounds = {}

    for _, inst in ipairs(
        SoundService:GetDescendants()
    ) do
        if inst:IsA("Sound")
        and string.find(
            lower(inst.Name),
            "safezone",
            1,
            true
        )
        then
            table.insert(sounds, {
                path = safePath(inst),
                isPlaying = inst.IsPlaying,
                volume = inst.Volume,
                timePosition = inst.TimePosition,
            })
        end
    end

    return sounds
end

--==============================================================--
-- FILESYSTEM
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
        CONFIG.PLACE_FOLDER,
        index
    )
end

local function writeManifest()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.PLACE_FOLDER)

    local manifest = {
        version = CONFIG.VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,

        blocks = Archive.Blocks,
        currentBlock = Archive.CurrentBlock,
        currentBlockBytes = Archive.CurrentBlockBytes,

        bytes = Archive.Bytes,
        records = Archive.Records,

        updatedAt = os.time(),
    }

    local encoded = safeJson(manifest)

    pcall(function()
        if ISFILE(CONFIG.MANIFEST_PATH) then
            local old = READFILE(CONFIG.MANIFEST_PATH)

            if type(old) == "string"
            and #old > 0
            then
                WRITEFILE(
                    CONFIG.MANIFEST_BACKUP_PATH,
                    old
                )
            end
        end

        WRITEFILE(
            CONFIG.MANIFEST_PATH,
            encoded
        )
    end)
end

local function recoverManifest(path)
    if not FILESYSTEM_OK
    or not ISFILE(path)
    then
        return nil
    end

    local ok, text =
        pcall(READFILE, path)

    if not ok
    or type(text) ~= "string"
    or #text == 0
    then
        return nil
    end

    local decodedOk, data =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            text
        )

    if decodedOk
    and type(data) == "table"
    then
        return data
    end

    return nil
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
            local ok, text =
                pcall(READFILE, path)

            if ok
            and type(text) == "string"
            then
                bytes += #text

                for _ in string.gmatch(
                    text,
                    "[^\r\n]+"
                ) do
                    records += 1
                end

                if path
                    == blockPath(
                        Archive.CurrentBlock
                    )
                then
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
        local memory =
            rawget(
                env,
                "__CAFEINA_EGG_TRACE_MEMORY"
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
    ensureFolder(CONFIG.PLACE_FOLDER)

    local manifest =
        recoverManifest(
            CONFIG.MANIFEST_PATH
        )
        or recoverManifest(
            CONFIG.MANIFEST_BACKUP_PATH
        )

    if manifest then
        Archive.Blocks =
            type(manifest.blocks) == "table"
            and manifest.blocks
            or {}

        Archive.CurrentBlock =
            tonumber(manifest.currentBlock)
            or math.max(1, #Archive.Blocks)
    else
        Archive.Blocks =
            recoverBlocksByProbe()

        Archive.CurrentBlock =
            math.max(1, #Archive.Blocks)
    end

    if #Archive.Blocks == 0 then
        Archive.Blocks = {
            blockPath(1)
        }
        Archive.CurrentBlock = 1
    end

    recountArchive()
    writeManifest()
end

local function appendLine(path, line)
    if APPENDFILE then
        return pcall(
            APPENDFILE,
            path,
            line
        )
    end

    local previous = ""

    if ISFILE(path) then
        local ok, text =
            pcall(READFILE, path)

        if ok
        and type(text) == "string"
        then
            previous = text
        end
    end

    return pcall(
        WRITEFILE,
        path,
        previous .. line
    )
end

--==============================================================--
-- RECORD WRITER
--==============================================================--

local updateUI

local function archiveRecord(record)
    record.version =
        record.version or CONFIG.VERSION

    record.placeId =
        record.placeId or game.PlaceId

    record.gameId =
        record.gameId or game.GameId

    record.runId =
        record.runId or Session.RunId

    record.time =
        record.time or relativeTime()

    record.unix =
        record.unix or os.time()

    local json =
        safeJson(record)

    local line =
        json .. "\n"

    local bytes =
        #line

    if Archive.Bytes + bytes
        > CONFIG.MAX_ARCHIVE_BYTES
    then
        Session.StopRequested = true
        return false
    end

    if Archive.Persistent then
        ensureFolder(CONFIG.ARCHIVE_ROOT)
        ensureFolder(CONFIG.PLACE_FOLDER)

        if Archive.CurrentBlockBytes > 0
        and Archive.CurrentBlockBytes + bytes
            > CONFIG.BLOCK_TARGET_BYTES
        then
            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0

            local newPath =
                blockPath(
                    Archive.CurrentBlock
                )

            table.insert(
                Archive.Blocks,
                newPath
            )
        end

        local path =
            blockPath(
                Archive.CurrentBlock
            )

        if #Archive.Blocks == 0 then
            table.insert(
                Archive.Blocks,
                path
            )
        end

        local ok =
            appendLine(
                path,
                line
            )

        if not ok then
            return false
        end
    else
        table.insert(
            Archive.MemoryLines,
            json
        )

        env.__CAFEINA_EGG_TRACE_MEMORY = {
            lines = Archive.MemoryLines,
        }
    end

    Archive.Bytes += bytes
    Archive.Records += 1

    Session.Records += 1

    if Archive.Persistent
    and (
        Archive.Records % 20 == 0
        or record.kind == "session_started"
        or record.kind == "session_finalized"
    )
    then
        writeManifest()
    end

    if updateUI then
        updateUI(false)
    end

    return true
end

--==============================================================--
-- TRANSACTION CORRELATION
--==============================================================--

local function newTransaction(reason, uid)
    Session.TransactionCounter += 1

    Session.CurrentTransaction = {
        id =
            tostring(Session.RunId)
            .. ":egg:"
            .. tostring(
                Session.TransactionCounter
            ),

        openedAt = relativeTime(),
        reason = reason,
        uid = uid,
    }

    return Session.CurrentTransaction.id
end

local function ensureTransaction(reason, uid)
    if Session.CurrentTransaction then
        if uid
        and not Session.CurrentTransaction.uid
        then
            Session.CurrentTransaction.uid =
                tostring(uid)
        end

        return Session.CurrentTransaction.id
    end

    return newTransaction(reason, uid)
end

local function closeTransaction(reason)
    if not Session.CurrentTransaction then
        return
    end

    archiveRecord({
        source = "egg_trace",
        kind = "egg_transaction_closed",

        transactionId =
            Session.CurrentTransaction.id,

        reason = reason,

        uid =
            Session.CurrentTransaction.uid,

        openedAt =
            Session.CurrentTransaction.openedAt,

        closedAt =
            relativeTime(),

        player =
            characterSnapshot(),
    })

    Session.CurrentTransaction = nil
end

local function markEggActivity()
    Session.LastEggActivity =
        os.clock()
end

--==============================================================--
-- EGG PAYLOAD EXTRACTION
--==============================================================--

local function findField(value, wanted, depth, seen)
    depth = depth or 0

    if depth > 6
    or type(value) ~= "table"
    then
        return nil
    end

    seen = seen or {}

    if seen[value] then
        return nil
    end

    seen[value] = true

    for k, v in pairs(value) do
        local key = lower(k)

        for _, w in ipairs(wanted) do
            if key == lower(w) then
                seen[value] = nil
                return v
            end
        end

        if type(v) == "table" then
            local found =
                findField(
                    v,
                    wanted,
                    depth + 1,
                    seen
                )

            if found ~= nil then
                seen[value] = nil
                return found
            end
        end
    end

    seen[value] = nil
    return nil
end

local function extractEggMeta(...)
    local result = {}
    local args = {...}

    for _, value in ipairs(args) do
        if type(value) == "table" then
            result.uid =
                result.uid
                or findField(
                    value,
                    {"Uid", "UID", "uid"}
                )

            result.state =
                result.state
                or findField(
                    value,
                    {"State", "state"}
                )

            result.isCarrying =
                result.isCarrying

            if result.isCarrying == nil then
                result.isCarrying =
                    findField(
                        value,
                        {
                            "IsCarrying",
                            "isCarrying",
                        }
                    )
            end

            result.carrierUserId =
                result.carrierUserId
                or findField(
                    value,
                    {
                        "CarrierUserId",
                        "carrierUserId",
                    }
                )

            result.areaId =
                result.areaId
                or findField(
                    value,
                    {"AreaId", "areaId"}
                )

            result.position =
                result.position
                or findField(
                    value,
                    {"Position", "position"}
                )

            result.nestId =
                result.nestId
                or findField(
                    value,
                    {"NestId", "nestId"}
                )
        end
    end

    if result.uid ~= nil then
        result.uid =
            tostring(result.uid)
    end

    if result.state ~= nil then
        result.state =
            tostring(result.state)
    end

    if result.areaId ~= nil then
        result.areaId =
            tostring(result.areaId)
    end

    result.position =
        safeSerialize(
            result.position
        )

    return result
end

--==============================================================--
-- REMOTE FILTERS
--==============================================================--

local function isEggRemotePath(path)
    return hasAny(
        path,
        CONFIG.EGG_KEYWORDS
    )
end

local function isImportantInbound(inst)
    local path =
        safePath(inst)

    if isEggRemotePath(path) then
        return true
    end

    for _, word in ipairs(
        CONFIG.IMPORTANT_INBOUND
    ) do
        if string.find(
            lower(path),
            lower(word),
            1,
            true
        )
        then
            return true
        end
    end

    return false
end

local function profilePayloadRelevant(...)
    local args = {...}

    for _, value in ipairs(args) do
        if shallowContainsEgg(value) then
            return true
        end
    end

    return false
end

--==============================================================--
-- INBOUND OBSERVER
--==============================================================--

local function observeInbound(remote)
    if not remote:IsA("RemoteEvent")
    and not remote:IsA(
        "UnreliableRemoteEvent"
    )
    then
        return
    end

    if not isImportantInbound(remote) then
        return
    end

    local path =
        safePath(remote)

    local conn =
        remote.OnClientEvent:
        Connect(function(...)
            if not Session.Running
            or Session.StopRequested
            then
                return
            end

            if string.find(
                lower(path),
                "profiledelta",
                1,
                true
            )
            and not profilePayloadRelevant(...)
            then
                return
            end

            markEggActivity()

            local meta =
                extractEggMeta(...)

            local tx =
                ensureTransaction(
                    "inbound:"
                    .. remote.Name,
                    meta.uid
                )

            -- Carry state tracker
            if string.find(
                lower(path),
                "fieldeggcarry",
                1,
                true
            )
            then
                if meta.isCarrying == true then
                    Session.Carrying = true
                elseif meta.isCarrying == false then
                    -- Do not close immediately:
                    -- final event may follow milliseconds later.
                end
            end

            if string.find(
                lower(path),
                "fieldeggshifted",
                1,
                true
            )
            then
                if meta.state == "Carried"
                and (
                    tonumber(meta.carrierUserId)
                        == nil
                    or tonumber(
                        meta.carrierUserId
                    )
                        == LocalPlayer.UserId
                )
                then
                    Session.Carrying = true
                    Session.EggUid =
                        meta.uid
                        or Session.EggUid

                    Session.EggState =
                        "Carried"

                    Session.EggArea =
                        meta.areaId
                        or Session.EggArea

                elseif meta.state == "Dropped"
                or meta.state == "GuardCarried"
                then
                    Session.Carrying = false
                    Session.EggState =
                        meta.state
                elseif meta.state == "Slot" then
                    Session.Carrying = false
                    Session.EggState = "Slot"
                end
            end

            archiveRecord({
                source = "network_in",
                kind = "remote_received",

                transactionId = tx,

                remote = {
                    name = remote.Name,
                    className =
                        remote.ClassName,
                    path = path,
                },

                payload =
                    packSerialized(...),

                egg = meta,

                carry = {
                    active =
                        Session.Carrying,
                    uid =
                        Session.EggUid,
                    state =
                        Session.EggState,
                    area =
                        Session.EggArea,
                },

                player =
                    characterSnapshot(),

                safeZoneMusic =
                    safeZoneMusicState(),
            })

            if string.find(
                lower(path),
                "redeemverdict",
                1,
                true
            )
            or (
                string.find(
                    lower(path),
                    "fieldeggshifted",
                    1,
                    true
                )
                and meta.state == "Slot"
            )
            then
                task.delay(
                    0.25,
                    function()
                        if Session.Running then
                            closeTransaction(
                                "delivery_signal"
                            )
                        end
                    end
                )
            end
        end)

    table.insert(
        ObserverConnections,
        conn
    )
end

local function installInboundObservers()
    local networking =
        ReplicatedStorage:
        FindFirstChild(
            "Packages"
        )

    local candidates =
        ReplicatedStorage:GetDescendants()

    local observed = 0

    for _, inst in ipairs(candidates) do
        if inst:IsA("RemoteEvent")
        or inst:IsA(
            "UnreliableRemoteEvent"
        )
        then
            if isImportantInbound(inst) then
                observeInbound(inst)
                observed += 1
            end
        end
    end

    local added =
        ReplicatedStorage.DescendantAdded:
        Connect(function(inst)
            if not Session.Running then
                return
            end

            if inst:IsA("RemoteEvent")
            or inst:IsA(
                "UnreliableRemoteEvent"
            )
            then
                if isImportantInbound(inst) then
                    observeInbound(inst)
                end
            end
        end)

    table.insert(
        ObserverConnections,
        added
    )

    archiveRecord({
        source = "session",
        kind = "inbound_observers_ready",
        count = observed,
        networkingRootFound =
            networking ~= nil,
    })
end

--==============================================================--
-- OUTBOUND PASSIVE NAMECALL TRACE
--==============================================================--

local function shouldTraceOutbound(self, method, ...)
    if typeof(self) ~= "Instance" then
        return false
    end

    if method ~= "FireServer"
    and method ~= "InvokeServer"
    then
        return false
    end

    if not self:IsA("RemoteEvent")
    and not self:IsA("RemoteFunction")
    and not self:IsA(
        "UnreliableRemoteEvent"
    )
    then
        return false
    end

    local path =
        safePath(self)

    if isEggRemotePath(path) then
        return true
    end

    -- ProfileMirror outbound only when payload itself looks egg-related.
    if string.find(
        lower(path),
        "profilemirror",
        1,
        true
    )
    and profilePayloadRelevant(...)
    then
        return true
    end

    return false
end

local function installOutboundHook()
    if HookInstalled then
        return true
    end

    if not HOOKMETAMETHOD
    or not GETNAMECALLMETHOD
    then
        archiveRecord({
            source = "diagnostic",
            kind = "outbound_hook_unavailable",
            hookmetamethod =
                HOOKMETAMETHOD ~= nil,
            getnamecallmethod =
                GETNAMECALLMETHOD ~= nil,
        })

        return false
    end

    local wrapper

    wrapper = function(self, ...)
        local method =
            GETNAMECALLMETHOD()

        local trace =
            Session.Running
            and not Session.StopRequested
            and shouldTraceOutbound(
                self,
                method,
                ...
            )

        local callerIsExecutor = false

        if CHECKCALLER then
            local ok, value =
                pcall(CHECKCALLER)

            callerIsExecutor =
                ok and value == true
        end

        if trace then
            markEggActivity()

            local meta =
                extractEggMeta(...)

            local tx =
                ensureTransaction(
                    "outbound:"
                    .. tostring(
                        self.Name
                    ),
                    meta.uid
                )

            local before = {
                source = "network_out",
                kind =
                    method == "InvokeServer"
                    and "remote_invoke_begin"
                    or "remote_fire",

                transactionId = tx,

                remote = {
                    name = self.Name,
                    className =
                        self.ClassName,
                    path =
                        safePath(self),
                },

                method = method,

                callerIsExecutor =
                    callerIsExecutor,

                payload =
                    packSerialized(...),

                egg = meta,

                player =
                    characterSnapshot(),

                safeZoneMusic =
                    safeZoneMusicState(),
            }

            archiveRecord(before)

            if method == "InvokeServer" then
                local started =
                    os.clock()

                local results =
                    table.pack(
                        OriginalNamecall(
                            self,
                            ...
                        )
                    )

                archiveRecord({
                    source = "network_out",
                    kind = "remote_invoke_return",

                    transactionId = tx,

                    remote = {
                        name = self.Name,
                        className =
                            self.ClassName,
                        path =
                            safePath(self),
                    },

                    duration =
                        os.clock()
                        - started,

                    returnCount =
                        results.n,

                    returns =
                        (function()
                            local values = {}

                            for i = 1,
                                results.n
                            do
                                values[i] =
                                    safeSerialize(
                                        results[i]
                                    )
                            end

                            return values
                        end)(),

                    player =
                        characterSnapshot(),

                    carry = {
                        active =
                            Session.Carrying,
                        uid =
                            Session.EggUid,
                        state =
                            Session.EggState,
                    },
                })

                return table.unpack(
                    results,
                    1,
                    results.n
                )
            end
        end

        return OriginalNamecall(
            self,
            ...
        )
    end

    if NEWCCLOSURE then
        wrapper =
            NEWCCLOSURE(wrapper)
    end

    local ok, old =
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            wrapper
        )

    if not ok
    or type(old) ~= "function"
    then
        archiveRecord({
            source = "diagnostic",
            kind = "outbound_hook_failed",
            error = tostring(old),
        })

        return false
    end

    OriginalNamecall = old
    HookInstalled = true

    archiveRecord({
        source = "session",
        kind = "outbound_hook_ready",
        observationalOnly = true,
    })

    return true
end

--==============================================================--
-- PROMPT OBSERVATION
--==============================================================--

local function isEggPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") then
        return false
    end

    local text =
        table.concat({
            prompt.Name,
            prompt.ActionText,
            prompt.ObjectText,
            prompt.Parent
                and prompt.Parent.Name
                or "",
            safePath(prompt),
        }, " ")

    return hasAny(
        text,
        {
            "egg",
            "carryareaegg",
            "steal",
        }
    )
end

local function observePrompt(prompt)
    if not isEggPrompt(prompt) then
        return
    end

    local path = safePath(prompt)

    local function record(kind, player)
        if not Session.Running
        or Session.StopRequested
        then
            return
        end

        if player
        and player ~= LocalPlayer
        then
            return
        end

        markEggActivity()

        local tx =
            ensureTransaction(
                "prompt:" .. kind,
                nil
            )

        archiveRecord({
            source = "interaction",
            kind = kind,

            transactionId = tx,

            prompt = {
                path = path,
                actionText =
                    prompt.ActionText,
                objectText =
                    prompt.ObjectText,
                holdDuration =
                    prompt.HoldDuration,
                maxActivationDistance =
                    prompt.MaxActivationDistance,
                enabled =
                    prompt.Enabled,
            },

            player =
                characterSnapshot(),
        })
    end

    table.insert(
        ObserverConnections,
        prompt.PromptButtonHoldBegan:
        Connect(function(player)
            record(
                "egg_prompt_hold_began",
                player
            )
        end)
    )

    table.insert(
        ObserverConnections,
        prompt.PromptButtonHoldEnded:
        Connect(function(player)
            record(
                "egg_prompt_hold_ended",
                player
            )
        end)
    )

    table.insert(
        ObserverConnections,
        prompt.Triggered:
        Connect(function(player)
            record(
                "egg_prompt_triggered",
                player
            )
        end)
    )
end

local function installPromptObservers()
    local count = 0

    for _, inst in ipairs(
        Workspace:GetDescendants()
    ) do
        if inst:IsA("ProximityPrompt")
        and isEggPrompt(inst)
        then
            observePrompt(inst)
            count += 1
        end
    end

    local conn =
        Workspace.DescendantAdded:
        Connect(function(inst)
            if Session.Running
            and inst:IsA(
                "ProximityPrompt"
            )
            and isEggPrompt(inst)
            then
                observePrompt(inst)
            end
        end)

    table.insert(
        ObserverConnections,
        conn
    )

    archiveRecord({
        source = "session",
        kind = "egg_prompt_observers_ready",
        count = count,
    })
end

--==============================================================--
-- STATIC TARGETED SNAPSHOT
--==============================================================--

local function snapshotCandidate(inst, reason)
    local record = {
        source = "target_scan",
        kind = "egg_world_candidate",

        reason = reason,

        className =
            inst.ClassName,

        name =
            inst.Name,

        path =
            safePath(inst),

        attributes =
            safeSerialize(
                inst:GetAttributes()
            ),
    }

    if inst:IsA("BasePart") then
        record.position =
            safeSerialize(
                inst.Position
            )

        record.cframe =
            safeSerialize(
                inst.CFrame
            )

        record.size =
            safeSerialize(
                inst.Size
            )

        record.canCollide =
            inst.CanCollide

        record.canTouch =
            inst.CanTouch

        record.canQuery =
            inst.CanQuery

    elseif inst:IsA("Attachment") then
        record.position =
            safeSerialize(
                inst.WorldPosition
            )

        record.cframe =
            safeSerialize(
                inst.WorldCFrame
            )

    elseif inst:IsA("Sound") then
        record.sound = {
            isPlaying =
                inst.IsPlaying,
            volume =
                inst.Volume,
            soundId =
                inst.SoundId,
        }

    elseif inst:IsA("ProximityPrompt") then
        record.prompt = {
            actionText =
                inst.ActionText,
            objectText =
                inst.ObjectText,
            holdDuration =
                inst.HoldDuration,
            maxActivationDistance =
                inst.MaxActivationDistance,
            enabled =
                inst.Enabled,
        }

    elseif inst:IsA("RemoteEvent")
    or inst:IsA("RemoteFunction")
    or inst:IsA(
        "UnreliableRemoteEvent"
    )
    then
        record.remote = {
            type =
                inst.ClassName,
        }
    end

    archiveRecord(record)
end

local function targetedSnapshot()
    local counts = {
        networking = 0,
        workspace = 0,
        shared = 0,
        sounds = 0,
    }

    for _, inst in ipairs(
        ReplicatedStorage:GetDescendants()
    ) do
        local path =
            safePath(inst)

        if isEggRemotePath(path)
        or hasAny(
            path,
            {
                "SafeZoneBarriers",
                "SafeZoneMusic",
                "EggWorld",
                "ZoneProbe",
            }
        )
        then
            snapshotCandidate(
                inst,
                "replicated_target"
            )

            counts.networking += 1
        end
    end

    for _, inst in ipairs(
        Workspace:GetDescendants()
    ) do
        local path =
            safePath(inst)

        if hasAny(
            path,
            {
                "CarryAreaEgg",
                "AreaEggSlotsClient",
                "SafeZone",
                "Safe Zone",
                "Redeem",
                "EggSlot",
                "SpawnPoint",
                "CenterPoint",
            }
        )
        then
            snapshotCandidate(
                inst,
                "workspace_target"
            )

            counts.workspace += 1
        end
    end

    for _, inst in ipairs(
        SoundService:GetDescendants()
    ) do
        if hasAny(
            safePath(inst),
            {"SafeZone", "Safe Zone"}
        )
        then
            snapshotCandidate(
                inst,
                "sound_target"
            )

            counts.sounds += 1
        end
    end

    archiveRecord({
        source = "target_scan",
        kind = "target_snapshot_complete",
        counts = counts,
        player =
            characterSnapshot(),
    })
end

--==============================================================--
-- TRAJECTORY / CARRY HEARTBEAT
--==============================================================--

local function trajectoryStep()
    if not Session.Running
    or Session.StopRequested
    then
        return
    end

    local now = os.clock()

    local activeWindow =
        Session.Carrying
        or (
            Session.LastEggActivity > 0
            and now
                - Session.LastEggActivity
                <= CONFIG.TRAJECTORY_POST_SECONDS
        )

    if activeWindow then
        if now - Session.LastTrajectory
            >= CONFIG.TRAJECTORY_INTERVAL
        then
            Session.LastTrajectory = now

            archiveRecord({
                source = "trajectory",
                kind = "egg_player_trajectory",

                transactionId =
                    Session.CurrentTransaction
                    and Session.CurrentTransaction.id
                    or nil,

                carry = {
                    active =
                        Session.Carrying,
                    uid =
                        Session.EggUid,
                    state =
                        Session.EggState,
                    area =
                        Session.EggArea,
                },

                player =
                    characterSnapshot(),

                safeZoneMusic =
                    safeZoneMusicState(),
            })
        end

    elseif now - Session.LastIdleHeartbeat
        >= CONFIG.IDLE_HEARTBEAT_SECONDS
    then
        Session.LastIdleHeartbeat = now

        archiveRecord({
            source = "trajectory",
            kind = "idle_position_heartbeat",

            player =
                characterSnapshot(),
        })
    end
end

local trajectoryConnection =
    RunService.Heartbeat:
    Connect(trajectoryStep)

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG = Color3.fromRGB(8, 8, 10),
    PANEL = Color3.fromRGB(13, 13, 16),
    STROKE = Color3.fromRGB(45, 45, 52),

    BUTTON = Color3.fromRGB(31, 31, 36),
    GREEN = Color3.fromRGB(26, 116, 59),

    RED = Color3.fromRGB(168, 42, 48),
    RED_DARK = Color3.fromRGB(87, 28, 32),

    TEXT = Color3.fromRGB(245, 245, 247),
    MUTED = Color3.fromRGB(155, 155, 165),

    BAR = Color3.fromRGB(230, 230, 234),
}

local GuiParent = CoreGui

if type(gethui) == "function" then
    local ok, result =
        pcall(gethui)

    if ok and result then
        GuiParent = result
    end
end

pcall(function()
    local old =
        GuiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false

local parentOk = pcall(function()
    Gui.Parent = GuiParent
end)

if not parentOk then
    Gui.Parent =
        LocalPlayer:
        WaitForChild(
            "PlayerGui"
        )
end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(236, 157)
Main.Position = UDim2.new(0.5, -118, 0.45, -78)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = COLORS.STROKE
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(8, 6)
Title.Size = UDim2.new(1, -16, 0, 21)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • EGG TRACE"
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
ActionButton.Text = "INICIAR EGG TRACE"
ActionButton.TextColor3 = COLORS.TEXT
ActionButton.TextSize = 11
ActionButton.Font = Enum.Font.GothamBold
ActionButton.Parent = Main

local ActionCorner = Instance.new("UICorner")
ActionCorner.CornerRadius = UDim.new(0, 7)
ActionCorner.Parent = ActionButton

local StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.Position = UDim2.fromOffset(8, 76)
StatusLabel.Size = UDim2.new(1, -16, 0, 18)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Pronto"
StatusLabel.TextColor3 = COLORS.TEXT
StatusLabel.TextSize = 10
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Main

local DetailLabel = Instance.new("TextLabel")
DetailLabel.BackgroundTransparency = 1
DetailLabel.Position = UDim2.fromOffset(8, 95)
DetailLabel.Size = UDim2.new(1, -16, 0, 30)
DetailLabel.Font = Enum.Font.Gotham
DetailLabel.Text = "0.00 MB • 0 registros"
DetailLabel.TextColor3 = COLORS.MUTED
DetailLabel.TextSize = 9
DetailLabel.TextWrapped = true
DetailLabel.TextXAlignment = Enum.TextXAlignment.Left
DetailLabel.TextYAlignment = Enum.TextYAlignment.Top
DetailLabel.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(8, 134)
BarBack.Size = UDim2.new(1, -16, 0, 7)
BarBack.BackgroundColor3 = Color3.fromRGB(27, 27, 31)
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local BarBackCorner = Instance.new("UICorner")
BarBackCorner.CornerRadius = UDim.new(1, 0)
BarBackCorner.Parent = BarBack

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0, 0, 1, 0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local BarFillCorner = Instance.new("UICorner")
BarFillCorner.CornerRadius = UDim.new(1, 0)
BarFillCorner.Parent = BarFill

-- drag
do
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:
    Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position

            input.Changed:
            Connect(function()
                if input.UserInputState
                    == Enum.UserInputState.End
                then
                    dragging = false
                end
            end)
        end
    end)

    Main.InputChanged:
    Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseMovement
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:
    Connect(function(input)
        if dragging
        and input == dragInput
        then
            local delta =
                input.Position - dragStart

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

local lastUI = 0

updateUI = function(force)
    local now = os.clock()

    if not force
    and now - lastUI < 0.12
    then
        return
    end

    lastUI = now

    if Upload.Running then
        local ratio = 0

        if Upload.TotalBytes > 0 then
            ratio =
                math.clamp(
                    Upload.BytesSent
                        / Upload.TotalBytes,
                    0,
                    1
                )
        end

        BarFill.Size =
            UDim2.new(
                ratio,
                0,
                1,
                0
            )

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

        return
    end

    local archiveRatio =
        math.clamp(
            Archive.Bytes
                / CONFIG.MAX_ARCHIVE_BYTES,
            0,
            1
        )

    BarFill.Size =
        UDim2.new(
            archiveRatio,
            0,
            1,
            0
        )

    if Session.Running then
        StatusLabel.Text =
            Session.Carrying
            and "Coletando • OVO CARRIED"
            or "Coletando • aguardando ação"

        DetailLabel.Text =
            string.format(
                "%.2f MB • %d registros • %s",
                mb(Archive.Bytes),
                Archive.Records,
                HookInstalled
                    and "OUT+IN"
                    or "IN"
            )
    else
        DetailLabel.Text =
            string.format(
                "%.2f MB • %d registros",
                mb(Archive.Bytes),
                Archive.Records
            )
    end
end

--==============================================================--
-- HTTP
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false, nil, "request indisponível"
    end

    local lastError

    for attempt = 1,
        CONFIG.HTTP_RETRIES
    do
        local ok, response =
            pcall(
                REQUEST,
                options
            )

        if ok
        and type(response) == "table"
        then
            local status =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or response.status
                )

            local body =
                response.Body
                or response.body
                or ""

            local success =
                response.Success

            if success == nil
            and status
            then
                success =
                    status >= 200
                    and status < 300
            end

            if success == true then
                return true, status, body
            end

            lastError =
                "HTTP "
                .. tostring(status)
                .. " "
                .. tostring(body)
        else
            lastError =
                tostring(response)
        end

        task.wait(
            CONFIG.HTTP_RETRY_BASE
                * attempt
        )
    end

    return false, nil, lastError
end

local function postJson(url, data)
    local ok, _, body =
        requestRaw({
            Url = url,
            Method = "POST",

            Headers = {
                ["Content-Type"] =
                    "application/json",
            },

            Body =
                safeJson(data),
        })

    if not ok then
        return false, body
    end

    local decodedOk, decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            body
        )

    if decodedOk then
        return true, decoded
    end

    return true, {
        raw = body,
    }
end

--==============================================================--
-- ARCHIVE ITERATION / UPLOAD
--==============================================================--

local function eachArchiveObject(callback)
    local header = {
        recordType =
            "egg_delivery_trace_header",

        scanner =
            CONFIG.VERSION,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        clientVisibleOnly =
            true,

        observationalOnly =
            true,

        generatedAt =
            os.time(),

        archiveRecords =
            Archive.Records,

        archiveBytes =
            Archive.Bytes,
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
                and type(text)
                    == "string"
                then
                    for line in
                        string.gmatch(
                            text,
                            "[^\r\n]+"
                        )
                    do
                        local decodedOk,
                            value =
                            pcall(
                                HttpService.JSONDecode,
                                HttpService,
                                line
                            )

                        if decodedOk
                        and type(value)
                            == "table"
                        then
                            if callback(value)
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
            local ok, value =
                pcall(
                    HttpService.JSONDecode,
                    HttpService,
                    line
                )

            if ok
            and type(value)
                == "table"
            then
                if callback(value)
                    == false
                then
                    return false
                end
            end
        end
    end

    return true
end

local function prepareChunks()
    local chunks = {}
    local current = {}
    local currentBytes = 0

    eachArchiveObject(
        function(object)
            local encoded =
                safeJson(object)

            local add =
                #encoded + 1

            if #current > 0
            and currentBytes + add
                > CONFIG.UPLOAD_CHUNK_BYTES
            then
                table.insert(
                    chunks,
                    current
                )

                current = {}
                currentBytes = 0
            end

            table.insert(
                current,
                object
            )

            currentBytes += add

            return true
        end
    )

    if #current > 0 then
        table.insert(
            chunks,
            current
        )
    end

    local bytes = 0

    for _, chunk in ipairs(chunks) do
        bytes +=
            #safeJson(chunk)
    end

    return chunks, bytes
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

        if ISFILE(
            CONFIG.MANIFEST_PATH
        )
        then
            pcall(
                DELFILE,
                CONFIG.MANIFEST_PATH
            )
        end

        if ISFILE(
            CONFIG.MANIFEST_BACKUP_PATH
        )
        then
            pcall(
                DELFILE,
                CONFIG.MANIFEST_BACKUP_PATH
            )
        end
    else
        table.clear(
            Archive.MemoryLines
        )
    end

    Archive.Blocks = {
        blockPath(1)
    }

    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0
    Archive.Bytes = 0
    Archive.Records = 0

    env.__CAFEINA_EGG_TRACE_MEMORY = {
        lines = Archive.MemoryLines,
    }
end

local function uploadAll()
    if Upload.Running
    or Archive.Records <= 0
    then
        return
    end

    Upload.Running = true
    ActionButton.Text = "ENVIANDO..."
    ActionButton.BackgroundColor3 =
        COLORS.RED_DARK

    updateUI(true)

    writeManifest()

    local chunks, totalBytes =
        prepareChunks()

    Upload.TotalChunks =
        #chunks

    Upload.TotalBytes =
        totalBytes

    Upload.CurrentChunk = 0
    Upload.BytesSent = 0

    local filename =
        string.format(
            "Cafeina_EggTrace_%s_%s.json",
            tostring(game.PlaceId),
            nowUTCName()
        )

    local startOk, startData =
        postJson(
            CONFIG.UPLOAD_BASE
                .. "/start",

            {
                filename = filename,
                fileName = filename,

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

                metadata = {
                    focus =
                        "egg_delivery_trace",

                    clientVisibleOnly =
                        true,

                    observationalOnly =
                        true,

                    outboundHook =
                        HookInstalled,
                },
            }
        )

    if not startOk then
        Upload.Running = false

        StatusLabel.Text =
            "Upload falhou • preservado"

        ActionButton.Text =
            "INICIAR EGG TRACE"

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
            "/start inválido • preservado"

        ActionButton.Text =
            "INICIAR EGG TRACE"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    for index, objects in ipairs(chunks) do
        Upload.CurrentChunk = index

        local ok =
            postJson(
                CONFIG.UPLOAD_BASE
                    .. "/chunk",

                {
                    uploadId =
                        Upload.UploadId,

                    index = index,
                    chunkIndex = index,

                    totalChunks =
                        Upload.TotalChunks,

                    objects =
                        objects,
                }
            )

        if not ok then
            Upload.Running = false

            StatusLabel.Text =
                "Erro no chunk • preservado"

            ActionButton.Text =
                "INICIAR EGG TRACE"

            ActionButton.BackgroundColor3 =
                COLORS.BUTTON

            updateUI(true)
            return
        end

        Upload.BytesSent +=
            #safeJson(objects)

        updateUI(true)
        task.wait()
    end

    Upload.BytesSent =
        Upload.TotalBytes

    local finishOk, finishData =
        postJson(
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
            }
        )

    if not finishOk then
        Upload.Running = false

        StatusLabel.Text =
            "/finish falhou • preservado"

        ActionButton.Text =
            "INICIAR EGG TRACE"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    local confirmed = false

    if type(finishData)
        == "table"
    then
        confirmed =
            finishData.confirmed
                == true
            or finishData.success
                == true
            or finishData.ok
                == true
    end

    if not confirmed then
        Upload.Running = false

        StatusLabel.Text =
            "Servidor não confirmou • preservado"

        ActionButton.Text =
            "INICIAR EGG TRACE"

        ActionButton.BackgroundColor3 =
            COLORS.BUTTON

        updateUI(true)
        return
    end

    clearConfirmedArchive()

    Upload.Running = false

    ActionButton.Text =
        "INICIAR EGG TRACE"

    ActionButton.BackgroundColor3 =
        COLORS.BUTTON

    StatusLabel.Text =
        "Upload confirmado"

    updateUI(true)
end

--==============================================================--
-- START / STOP
--==============================================================--

local function disconnectObservers()
    for _, connection in ipairs(
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

local function startTrace()
    if Session.Running
    or Upload.Running
    then
        return
    end

    Session.Running = true
    Session.StopRequested = false

    Session.StartedAtClock =
        os.clock()

    Session.StartedAtUnix =
        os.time()

    Session.RunId =
        guid()

    Session.Records = 0

    Session.Carrying = false
    Session.EggUid = nil
    Session.EggState = nil
    Session.EggArea = nil

    Session.LastEggActivity = 0
    Session.LastTrajectory = 0
    Session.LastIdleHeartbeat = 0

    Session.CurrentTransaction = nil
    Session.TransactionCounter = 0

    ActionButton.Text =
        "ENCERRAR + ENVIAR"

    ActionButton.BackgroundColor3 =
        COLORS.RED

    archiveRecord({
        source = "session",
        kind = "session_started",

        capabilities = {
            filesystem =
                FILESYSTEM_OK
                    and true
                    or false,

            request =
                REQUEST ~= nil,

            hookmetamethod =
                HOOKMETAMETHOD ~= nil,

            getnamecallmethod =
                GETNAMECALLMETHOD ~= nil,

            checkcaller =
                CHECKCALLER ~= nil,
        },

        player =
            characterSnapshot(),
    })

    installOutboundHook()
    installInboundObservers()
    installPromptObservers()

    task.spawn(function()
        local ok, err =
            pcall(
                targetedSnapshot
            )

        if not ok then
            archiveRecord({
                source = "diagnostic",
                kind = "target_snapshot_error",
                error = tostring(err),
            })
        end
    end)

    updateUI(true)
end

local function stopTraceAndUpload()
    if not Session.Running
    or Upload.Running
    then
        return
    end

    Session.StopRequested = true

    if Session.CurrentTransaction then
        closeTransaction(
            "manual_stop"
        )
    end

    archiveRecord({
        source = "session",
        kind = "session_finalized",

        recordsThisRun =
            Session.Records,

        archivedRecords =
            Archive.Records,

        archivedBytes =
            Archive.Bytes,

        carry = {
            active =
                Session.Carrying,

            uid =
                Session.EggUid,

            state =
                Session.EggState,

            area =
                Session.EggArea,
        },

        player =
            characterSnapshot(),
    })

    disconnectObservers()
    writeManifest()

    Session.Running = false

    ActionButton.Text =
        "ENVIANDO..."

    ActionButton.BackgroundColor3 =
        COLORS.RED_DARK

    StatusLabel.Text =
        "Finalizando archive..."

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

    if Session.Running then
        stopTraceAndUpload()
    else
        startTrace()
    end
end)

--==============================================================--
-- RESTORE ARCHIVE
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
end

updateUI(true)

--==============================================================--
-- GUI DESTROY = PRESERVE ONLY
--==============================================================--

Gui.Destroying:
Connect(function()
    pcall(function()
        Session.StopRequested = true
        disconnectObservers()
        writeManifest()
    end)
end)

--==============================================================--
-- CONTROLLER
--==============================================================--

pcall(function()
    local previous =
        rawget(
            env,
            "__CAFEINA_EGG_TRACE_CONTROLLER"
        )

    if type(previous) == "table"
    and previous.Gui
    and previous.Gui ~= Gui
    then
        pcall(function()
            previous.Stop()
        end)
    end
end)

env.__CAFEINA_EGG_TRACE_CONTROLLER = {
    Gui = Gui,

    Stop = function()
        Session.StopRequested = true
        disconnectObservers()
        writeManifest()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print(
    "[CAFEÍNA] EGG DELIVERY TRACE V1.5 carregado."
)
