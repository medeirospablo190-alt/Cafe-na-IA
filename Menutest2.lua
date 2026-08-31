--==============================================================--
-- CAFEÍNA • TREADMILL AUTO LAB V2.0
-- PlaceId alvo observado: 107778070777162
--
-- OBJETIVO
-- • Descobrir como a esteira concede SpeedPower de verdade.
-- • Registrar chamadas reais RF/Treadmill/* feitas pelo jogo.
-- • Registrar retornos das RemoteFunctions.
-- • Registrar RE/Treadmill/* recebidos.
-- • Correlacionar SpeedPower / leaderstats.Speed / posição / distância.
-- • Enviar automaticamente ao site ao encerrar.
--
-- IMPORTANTE
-- • Automatiza movimento físico normal para dentro/fora da esteira.
-- • Faz apenas probes ativos de RFs já observados legitimamente:
--   AskWearStill() e AskDoff(), SEM argumentos inventados.
-- • NÃO altera SpeedPower/leaderstats/WalkSpeed.
-- • NÃO teleporta, não usa noclip e não faz fuzzing.
-- • Repete vários ciclos e envia tudo automaticamente ao concluir.
--
-- Uso:
-- 1. Pressione INICIAR AUTO TESTES.
-- 2. O laboratório faz os ciclos sozinho.
-- 3. Ao terminar, o arquivo é enviado automaticamente.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "TREADMILL_AUTO_LAB_V2_0",
    GUI_NAME = "CafeinaTreadmillAutoLabV20",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    ARCHIVE_ROOT = "CafeinaTreadmillTrace",
    ARCHIVE_FOLDER = "CafeinaTreadmillTrace/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaTreadmillTrace/" .. tostring(game.PlaceId) .. "/manifest.json",

    MAX_ARCHIVE_BYTES = 120 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 768 * 1024,
    UPLOAD_CHUNK_BYTES = 500000,

    FLUSH_INTERVAL = 0.35,
    FLUSH_AT_BYTES = 80 * 1024,

    SAMPLE_INTERVAL = 0.12,
    IDLE_SAMPLE_INTERVAL = 0.75,
    CANDIDATE_REFRESH = 3.0,

    NEAR_TREADMILL_DISTANCE = 18,
    CORRELATION_SECONDS = 3.5,

    -- Deep correlation buffer around real speed gains.
    HISTORY_SECONDS = 6.0,
    HISTORY_MAX = 180,
    POST_GAIN_SNAPSHOT_DELAY = 0.75,

    -- Candidate/touch analysis.
    TOUCH_SCAN_INTERVAL = 0.08,
    WATCH_CANDIDATE_LIMIT = 100,

    -- Fully automated, controlled treadmill experiments.
    AUTO_TRIALS = 6,
    FAR_BASELINE_SECONDS = 1.8,
    ON_BELT_SECONDS = 6.0,
    POST_EXIT_SECONDS = 1.8,
    BETWEEN_TRIALS_SECONDS = 0.45,

    -- Physical positioning.
    OUTSIDE_OFFSET = 16,
    BELT_TOP_OFFSET = 2.6,
    MOVE_TIMEOUT = 7.0,
    PATH_WAYPOINT_TIMEOUT = 2.8,

    -- Known legitimate no-argument RF probes only.
    -- Kept controlled rather than spammed so server behavior remains measurable.
    ACTIVE_PROBE_MIDRUN = true,
    MIDRUN_PROBE_AT = 3.0,

    -- Normal Humanoid movement while on the treadmill.
    BELT_RUN_INPUT_INTERVAL = 0.05,

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
    local previous = rawget(env, "__CAFEINA_TREADMILL_TRACE_CONTROLLER")
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
-- HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
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
    return ok and result or tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
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

    return {
        count=n,
        values=values,
    }
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

    LastOutbound = nil,
    LastInbound = nil,
    LastSpeedPower = nil,
    LastLeaderSpeed = nil,
    LastSpeedGainClock = 0,

    LastSampleClock = 0,
    LastIdleSampleClock = 0,
    LastCandidateRefresh = 0,
    LastTouchScanClock = 0,

    TreadmillCandidates = {},
    CandidateWatchState = {},
    History = {},
    CurrentTouching = {},
    GainCounter = 0,

    AutoRunning = false,
    AutoAbort = false,
    AutoTrial = 0,
    AutoPhase = "idle",
    AutoTreadmillPath = nil,
    ActiveRemoteCallsByCollector = 0,
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
local InboundObserved = setmetatable({}, {__mode="k"})
local RemoteInfo = setmetatable({}, {__mode="k"})

local HookInstalled = false
local OriginalNamecall = nil

local updateUI
local Status

--==============================================================--
-- SHORT HISTORY BUFFER
--==============================================================--

local function pushHistory(item)
    if not Session.Running then
        return
    end

    item.t = item.t or (
        Session.StartedClock ~= 0
        and (os.clock() - Session.StartedClock)
        or 0
    )

    table.insert(Session.History, item)

    local cutoff =
        (
            Session.StartedClock ~= 0
            and (os.clock() - Session.StartedClock)
            or 0
        )
        - CONFIG.HISTORY_SECONDS

    while #Session.History > 0 do
        local first = Session.History[1]

        if #Session.History > CONFIG.HISTORY_MAX
        or (first.t or 0) < cutoff
        then
            table.remove(Session.History, 1)
        else
            break
        end
    end
end

local function historySnapshot()
    local out = {}

    for i, item in ipairs(Session.History) do
        out[i] = safeSerialize(item)
    end

    return out
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
                Archive.Blocks =
                    type(data.blocks) == "table"
                    and data.blocks
                    or {}

                Archive.CurrentBlock =
                    tonumber(data.currentBlock)
                    or math.max(1, #Archive.Blocks)

                Archive.CurrentBlockBytes =
                    tonumber(data.currentBlockBytes)
                    or 0

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

local function relativeTime()
    if Session.StartedClock == 0 then
        return 0
    end
    return os.clock() - Session.StartedClock
end

local function queueRecord(record)
    if not Session.Running
    and record.kind ~= "session_finalized"
    then
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

task.spawn(function()
    while true do
        task.wait(CONFIG.FLUSH_INTERVAL)
        if #Archive.PendingLines > 0 then
            flushPending(true)
        end
    end
end)

--==============================================================--
-- PLAYER / SPEED
--==============================================================--

local function getCharacterState()
    local character = LocalPlayer.Character

    if not character then
        return {
            character=false,
        }
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    local out = {
        character=true,
    }

    if root then
        out.position=safeSerialize(root.Position)
        out.cframe=safeSerialize(root.CFrame)
        out.linearVelocity=safeSerialize(root.AssemblyLinearVelocity)
        out.horizontalVelocity=
            Vector3.new(
                root.AssemblyLinearVelocity.X,
                0,
                root.AssemblyLinearVelocity.Z
            ).Magnitude
    end

    if humanoid then
        out.walkSpeed=humanoid.WalkSpeed
        out.moveDirection=safeSerialize(humanoid.MoveDirection)

        local ok, state = pcall(function()
            return humanoid:GetState()
        end)

        if ok then
            out.humanoidState=tostring(state)
        end
    end

    return out
end

local function getLeaderSpeed()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if not leaderstats then
        return nil
    end

    local speed = leaderstats:FindFirstChild("Speed")
    if speed and speed:IsA("ValueBase") then
        return speed.Value
    end

    return nil
end

--==============================================================--
-- TREADMILL CANDIDATES
--==============================================================--

local function isCandidate(inst)
    if not inst:IsA("BasePart") then
        return false
    end

    local path = lower(safePath(inst))
    local name = lower(inst.Name)

    return
        contains(path, "treadmill")
        or contains(path, "belt")
        or contains(name, "treadmill")
        or contains(name, "belt")
end

local function refreshCandidates()
    local list = {}
    local seen = 0

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if isCandidate(inst) then
            table.insert(list, inst)
            seen += 1

            if seen % 50 == 0 then
                task.wait()
            end
        end
    end

    Session.TreadmillCandidates = list
    Session.LastCandidateRefresh = os.clock()

    queueRecord({
        source="world",
        kind="treadmill_candidates_refreshed",
        count=#list,
        candidates=(function()
            local out = {}
            for i = 1, math.min(#list, 60) do
                local part = list[i]
                local model = part:FindFirstAncestorOfClass("Model")

                out[i] = {
                    path=safePath(part),
                    position=safeSerialize(part.Position),
                    size=safeSerialize(part.Size),
                    canCollide=part.CanCollide,
                    canTouch=part.CanTouch,
                    canQuery=part.CanQuery,
                    attributes=safeSerialize(part:GetAttributes()),
                    model=model and {
                        path=safePath(model),
                        attributes=safeSerialize(model:GetAttributes()),
                    } or nil,
                }
            end
            return out
        end)(),
    })
end

local function nearestCandidate(position)
    local bestPart = nil
    local bestDistance = math.huge

    for _, part in ipairs(Session.TreadmillCandidates) do
        if part and part.Parent then
            local d = (part.Position - position).Magnitude
            if d < bestDistance then
                bestDistance = d
                bestPart = part
            end
        end
    end

    if bestPart then
        return {
            path=safePath(bestPart),
            position=safeSerialize(bestPart.Position),
            distance=bestDistance,
            near=bestDistance <= CONFIG.NEAR_TREADMILL_DISTANCE,
        }
    end

    return {
        distance=nil,
        near=false,
    }
end


local environmentSnapshot

local function compactCandidateState(part)
    if not part or not part.Parent then
        return nil
    end

    local model = part:FindFirstAncestorOfClass("Model")

    return {
        path=safePath(part),
        position=safeSerialize(part.Position),
        attributes=safeSerialize(part:GetAttributes()),
        model=model and {
            path=safePath(model),
            attributes=safeSerialize(model:GetAttributes()),
        } or nil,
    }
end

local function scanCandidateStateChanges()
    local count = 0

    for _, part in ipairs(Session.TreadmillCandidates) do
        if part and part.Parent then
            count += 1

            if count > CONFIG.WATCH_CANDIDATE_LIMIT then
                break
            end

            local nowState = compactCandidateState(part)
            local key = safePath(part)
            local encoded = safeJson(nowState)
            local before = Session.CandidateWatchState[key]

            if before ~= nil and before ~= encoded then
                queueRecord({
                    source="world",
                    kind="treadmill_candidate_state_changed",
                    path=key,
                    state=nowState,
                    environment=environmentSnapshot and environmentSnapshot() or nil,
                })

                pushHistory({
                    kind="candidate_state_changed",
                    path=key,
                    state=nowState,
                })
            end

            Session.CandidateWatchState[key] = encoded
        end
    end
end

local function localCharacterParts()
    local character = LocalPlayer.Character
    if not character then
        return {}
    end

    local parts = {}

    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            table.insert(parts, inst)
        end
    end

    return parts
end

local function scanTouchingTreadmills()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not character or not root then
        return
    end

    local touching = {}

    -- Broad overlap around the character so CanTouch=false belts are still detectable.
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}

    local ok, nearbyParts = pcall(function()
        return Workspace:GetPartBoundsInBox(
            root.CFrame,
            Vector3.new(7, 8, 7),
            params
        )
    end)

    if ok and type(nearbyParts) == "table" then
        for _, part in ipairs(nearbyParts) do
            if isCandidate(part) then
                local path = safePath(part)
                touching[path] = {
                    path=path,
                    position=safeSerialize(part.Position),
                    attributes=safeSerialize(part:GetAttributes()),
                }
            end
        end
    end

    for path, state in pairs(touching) do
        if not Session.CurrentTouching[path] then
            queueRecord({
                source="contact",
                kind="treadmill_entered",
                treadmill=state,
                environment=environmentSnapshot and environmentSnapshot() or nil,
            })

            pushHistory({
                kind="treadmill_entered",
                path=path,
            })
        end
    end

    for path, state in pairs(Session.CurrentTouching) do
        if not touching[path] then
            queueRecord({
                source="contact",
                kind="treadmill_left",
                treadmill=state,
                environment=environmentSnapshot and environmentSnapshot() or nil,
            })

            pushHistory({
                kind="treadmill_left",
                path=path,
            })
        end
    end

    Session.CurrentTouching = touching
end

environmentSnapshot = function()
    local char = getCharacterState()
    local nearest = {near=false}

    if char.position and type(char.position) == "table" then
        local rawPos
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if root then
            nearest = nearestCandidate(root.Position)
        end
    end

    return {
        player=char,
        treadmill=nearest,
        leaderSpeed=getLeaderSpeed(),
    }
end

--==============================================================--
-- PAYLOAD SPEEDPOWER
--==============================================================--

local function findSpeedPower(value, depth, seen)
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
        if lower(k) == "speedpower" then
            seen[value] = nil
            return tonumber(v) or v
        end

        if type(v) == "table" then
            local found = findSpeedPower(v, depth + 1, seen)
            if found ~= nil then
                seen[value] = nil
                return found
            end
        end
    end

    seen[value] = nil
    return nil
end

local function speedPowerInPacked(packed)
    for i = 1, packed.n do
        local v = packed[i]
        if type(v) == "table" then
            local found = findSpeedPower(v, 0, {})
            if found ~= nil then
                return found
            end
        end
    end
    return nil
end

--==============================================================--
-- REMOTE REGISTRY / INBOUND
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
    local low = lower(path)

    local info = {
        path=path,
        name=inst.Name,
        className=inst.ClassName,
        treadmill=contains(low, "treadmill"),
        profileDelta=contains(low, "profilemirror")
            and contains(low, "profiledelta"),
    }

    if info.treadmill or info.profileDelta then
        RemoteInfo[inst] = info
        return info
    end

    return nil
end

local function buildRegistry()
    local count = 0

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if classifyRemote(inst) then
            count += 1
        end
    end

    return count
end

local function processInbound(remote, info, packed)
    if not Session.Running or Session.StopRequested then
        return
    end

    local speedPower = speedPowerInPacked(packed)

    if info.profileDelta and speedPower == nil then
        return
    end

    local snapshot = environmentSnapshot()

    if speedPower ~= nil then
        local previous = Session.LastSpeedPower
        Session.LastSpeedPower = speedPower
        Session.LastSpeedGainClock = os.clock()

        queueRecord({
            source="profile",
            kind="speedpower_changed",
            before=previous,
            after=speedPower,
            delta=
                type(previous) == "number"
                and type(speedPower) == "number"
                and (speedPower - previous)
                or nil,
            lastOutbound=Session.LastOutbound,
            environment=snapshot,
        })

        Session.GainCounter += 1

        queueRecord({
            source="correlation",
            kind="speed_gain_window",
            gainIndex=Session.GainCounter,
            speedPowerBefore=previous,
            speedPowerAfter=speedPower,
            delta=
                type(previous) == "number"
                and type(speedPower) == "number"
                and (speedPower - previous)
                or nil,
            history=historySnapshot(),
            current=snapshot,
        })

        local capturedIndex = Session.GainCounter

        task.delay(CONFIG.POST_GAIN_SNAPSHOT_DELAY, function()
            if Session.Running then
                queueRecord({
                    source="correlation",
                    kind="speed_gain_post_snapshot",
                    gainIndex=capturedIndex,
                    environment=environmentSnapshot(),
                    history=historySnapshot(),
                })
            end
        end)
    end

    Session.LastInbound = {
        time=relativeTime(),
        remote=info.path,
    }

    pushHistory({
        kind="remote_in",
        remote=info.path,
        payload=serializePacked(packed),
        speedPower=speedPower,
    })

    queueRecord({
        source="network_in",
        kind="remote_received",
        remote={
            name=info.name,
            path=info.path,
            className=info.className,
        },
        payload=serializePacked(packed),
        speedPower=speedPower,
        environment=snapshot,
    })
end

local function attachInbound(remote, info)
    if InboundObserved[remote] then
        return
    end

    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("UnreliableRemoteEvent")
    ) then
        return
    end

    InboundObserved[remote] = true

    local c = remote.OnClientEvent:Connect(function(...)
        if not Session.Running or Session.StopRequested then
            return
        end

        local packed = table.pack(...)
        task.defer(processInbound, remote, info, packed)
    end)

    table.insert(Connections, c)
end

local function installInbound()
    local count = 0

    for remote, info in pairs(RemoteInfo) do
        if info.treadmill or info.profileDelta then
            if remote:IsA("RemoteEvent")
            or remote:IsA("UnreliableRemoteEvent")
            then
                attachInbound(remote, info)
                count += 1
            end
        end
    end

    local c = ReplicatedStorage.DescendantAdded:Connect(function(inst)
        local info = classifyRemote(inst)
        if info and (
            inst:IsA("RemoteEvent")
            or inst:IsA("UnreliableRemoteEvent")
        ) then
            attachInbound(inst, info)
        end
    end)

    table.insert(Connections, c)

    queueRecord({
        source="session",
        kind="inbound_ready",
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

    local snapshot = environmentSnapshot()

    Session.LastOutbound = {
        time=relativeTime(),
        remote=info.path,
        method=method,
        environment=snapshot,
    }

    pushHistory({
        kind="remote_out",
        remote=info.path,
        method=method,
        payload=serializePacked(packedArgs),
        returns=
            method == "InvokeServer"
            and serializePacked(packedReturns)
            or nil,
    })

    queueRecord({
        source="network_out",
        kind=
            method == "InvokeServer"
            and "remote_invoke"
            or "remote_fire",

        remote={
            name=info.name,
            path=info.path,
            className=info.className,
        },

        method=method,
        callerIsExecutor=callerIsExecutor,
        payload=serializePacked(packedArgs),
        returns=
            method == "InvokeServer"
            and serializePacked(packedReturns)
            or nil,
        duration=duration,
        environment=snapshot,
    })
end

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
        or (
            method ~= "FireServer"
            and method ~= "InvokeServer"
        )
        then
            return oldNamecall(self, ...)
        end

        local info = RemoteInfo[self]

        if not info or not info.treadmill then
            return oldNamecall(self, ...)
        end

        local packedArgs = table.pack(...)

        local callerIsExecutor = false
        if CHECKCALLER then
            local ok, value = pcall(CHECKCALLER)
            callerIsExecutor = ok and value == true
        end

        local started = os.clock()

        -- Real game call is executed immediately and untouched.
        local packedReturns = table.pack(
            oldNamecall(
                self,
                table.unpack(packedArgs, 1, packedArgs.n)
            )
        )

        local duration = os.clock() - started

        task.defer(
            processOutbound,
            info,
            method,
            packedArgs,
            packedReturns,
            duration,
            callerIsExecutor
        )

        return table.unpack(packedReturns, 1, packedReturns.n)
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
        passive=true,
    })

    return true
end

local function restoreHook()
    if HookInstalled
    and HOOKMETAMETHOD
    and type(OriginalNamecall) == "function"
    then
        pcall(HOOKMETAMETHOD, game, "__namecall", OriginalNamecall)
    end

    HookInstalled = false
end

--==============================================================--
-- LEADERSTATS WATCH
--==============================================================--

local function installLeaderSpeedWatch()
    task.spawn(function()
        local leaderstats = LocalPlayer:WaitForChild("leaderstats", 20)
        if not leaderstats then
            queueRecord({
                source="diagnostic",
                kind="leaderstats_missing",
            })
            return
        end

        local speed = leaderstats:WaitForChild("Speed", 20)
        if not speed or not speed:IsA("ValueBase") then
            queueRecord({
                source="diagnostic",
                kind="leader_speed_missing",
            })
            return
        end

        Session.LastLeaderSpeed = speed.Value

        queueRecord({
            source="leaderstats",
            kind="leader_speed_initial",
            value=speed.Value,
            environment=environmentSnapshot(),
        })

        local c = speed.Changed:Connect(function(newValue)
            if not Session.Running then
                return
            end

            local before = Session.LastLeaderSpeed
            Session.LastLeaderSpeed = newValue

            local snapshot = environmentSnapshot()

            pushHistory({
                kind="leader_speed_changed",
                before=before,
                after=newValue,
                delta=
                    type(before) == "number"
                    and type(newValue) == "number"
                    and (newValue - before)
                    or nil,
            })

            queueRecord({
                source="leaderstats",
                kind="leader_speed_changed",
                before=before,
                after=newValue,
                delta=
                    type(before) == "number"
                    and type(newValue) == "number"
                    and (newValue - before)
                    or nil,
                secondsSinceLastOutbound=
                    Session.LastOutbound
                    and (
                        relativeTime()
                        - (Session.LastOutbound.time or 0)
                    )
                    or nil,
                lastOutbound=Session.LastOutbound,
                environment=snapshot,
            })

            if updateUI then
                updateUI(true)
            end
        end)

        table.insert(Connections, c)
    end)
end

--==============================================================--
-- SAMPLER
--==============================================================--

RunService.Heartbeat:Connect(function()
    if not Session.Running or Session.StopRequested then
        return
    end

    local now = os.clock()

    if now - Session.LastTouchScanClock >= CONFIG.TOUCH_SCAN_INTERVAL then
        Session.LastTouchScanClock = now
        task.defer(scanTouchingTreadmills)
    end

    if now - Session.LastCandidateRefresh >= CONFIG.CANDIDATE_REFRESH then
        Session.LastCandidateRefresh = now
        task.spawn(function()
            refreshCandidates()
            scanCandidateStateChanges()
        end)
    end

    if now - Session.LastSampleClock < CONFIG.SAMPLE_INTERVAL then
        return
    end

    Session.LastSampleClock = now

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not root then
        return
    end

    local nearest = nearestCandidate(root.Position)

    local highInterest =
        nearest.near
        or (
            Session.LastSpeedGainClock > 0
            and now - Session.LastSpeedGainClock <= CONFIG.CORRELATION_SECONDS
        )
        or (
            Session.LastOutbound
            and relativeTime() - (Session.LastOutbound.time or 0)
                <= CONFIG.CORRELATION_SECONDS
        )

    if not highInterest
    and now - Session.LastIdleSampleClock < CONFIG.IDLE_SAMPLE_INTERVAL
    then
        return
    end

    if not highInterest then
        Session.LastIdleSampleClock = now
    end

    task.defer(function()
        if Session.Running then
            queueRecord({
                source="sampler",
                kind=
                    highInterest
                    and "treadmill_activity_sample"
                    or "idle_sample",
                environment=environmentSnapshot(),
                lastOutbound=Session.LastOutbound,
                lastInbound=Session.LastInbound,
                lastSpeedPower=Session.LastSpeedPower,
            })
        end
    end)
end)

--==============================================================--
-- AUTOMATED TREADMILL LAB
--==============================================================--

local function getCharacterRig()
    local character = LocalPlayer.Character

    if not character then
        return nil, nil, nil
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    return character, humanoid, root
end

local function horizontalUnit(v)
    local flat =
        Vector3.new(
            v.X,
            0,
            v.Z
        )

    if flat.Magnitude <= 0.001 then
        return Vector3.new(0, 0, -1)
    end

    return flat.Unit
end

local function findTreadmillRemote(fragment, className)
    local needle = lower(fragment)

    for remote, info in pairs(RemoteInfo) do
        if
            info
            and info.treadmill
            and (
                className == nil
                or remote.ClassName == className
            )
            and (
                contains(info.path, needle)
                or contains(info.name, needle)
            )
        then
            return remote, info
        end
    end

    -- Registry may have changed after startup.
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if
            (
                inst:IsA("RemoteFunction")
                or inst:IsA("RemoteEvent")
                or inst:IsA("UnreliableRemoteEvent")
            )
            and (
                className == nil
                or inst.ClassName == className
            )
            and contains(safePath(inst), "Treadmill")
            and (
                contains(inst.Name, needle)
                or contains(safePath(inst), needle)
            )
        then
            local info = classifyRemote(inst)
            return inst, info
        end
    end

    return nil, nil
end

local function autoCheckpoint(name, extra)
    queueRecord({
        source="auto_lab",
        kind="checkpoint",
        trial=Session.AutoTrial,
        phase=Session.AutoPhase,
        name=name,
        extra=extra,
        environment=environmentSnapshot(),
        lastSpeedPower=Session.LastSpeedPower,
        leaderSpeed=getLeaderSpeed(),
        gainCounter=Session.GainCounter,
        history=historySnapshot(),
    })
end

local function setAutoPhase(phase, extra)
    Session.AutoPhase = phase

    queueRecord({
        source="auto_lab",
        kind="phase_changed",
        trial=Session.AutoTrial,
        phase=phase,
        extra=extra,
        environment=environmentSnapshot(),
    })

    pushHistory({
        kind="auto_phase",
        trial=Session.AutoTrial,
        phase=phase,
        extra=extra,
    })

    if updateUI then
        updateUI(true)
    end
end

local function invokeKnownNoArg(remote, label)
    if not remote or not remote:IsA("RemoteFunction") then
        queueRecord({
            source="auto_lab",
            kind="active_probe_missing",
            trial=Session.AutoTrial,
            phase=Session.AutoPhase,
            label=label,
        })

        return false, nil
    end

    Session.ActiveRemoteCallsByCollector += 1

    local before =
        environmentSnapshot()

    local started =
        os.clock()

    local packed

    local ok, err =
        pcall(function()
            packed =
                table.pack(
                    remote:InvokeServer()
                )
        end)

    local duration =
        os.clock() - started

    local after =
        environmentSnapshot()

    queueRecord({
        source="auto_lab",
        kind="active_known_remote_probe",
        trial=Session.AutoTrial,
        phase=Session.AutoPhase,
        label=label,
        remote={
            name=remote.Name,
            path=safePath(remote),
            className=remote.ClassName,
        },
        noArguments=true,
        ok=ok,
        error=ok and nil or tostring(err),
        returns=
            ok and serializePacked(packed) or nil,
        duration=duration,
        before=before,
        after=after,
    })

    pushHistory({
        kind="active_probe",
        label=label,
        remote=safePath(remote),
        ok=ok,
        returns=
            ok and serializePacked(packed) or nil,
    })

    return ok, packed
end

local function candidateScore(part, rootPosition)
    if not part or not part.Parent then
        return -math.huge
    end

    local path =
        lower(safePath(part))

    local score = 0

    if contains(path, "treadmill") then
        score += 1000
    end

    if contains(path, "belt") then
        score += 220
    end

    if contains(part.Name, "treadmill") then
        score += 650
    end

    if contains(part.Name, "belt") then
        score += 120
    end

    -- Prefer wide/long physical surfaces.
    score += math.min(
        120,
        math.max(part.Size.X, part.Size.Z) * 2
    )

    if rootPosition then
        score -=
            math.min(
                400,
                (part.Position - rootPosition).Magnitude * 0.25
            )
    end

    return score
end

local function selectBestTreadmill()
    refreshCandidates()

    local _, _, root =
        getCharacterRig()

    local rootPosition =
        root and root.Position or nil

    local best
    local bestScore =
        -math.huge

    for _, part in ipairs(Session.TreadmillCandidates) do
        local score =
            candidateScore(
                part,
                rootPosition
            )

        if score > bestScore then
            bestScore = score
            best = part
        end
    end

    if best then
        queueRecord({
            source="auto_lab",
            kind="auto_treadmill_selected",
            score=bestScore,
            treadmill=compactCandidateState(best),
            environment=environmentSnapshot(),
        })
    end

    return best
end

local function treadmillGeometry(part)
    local longAxis

    if part.Size.Z >= part.Size.X then
        longAxis =
            horizontalUnit(
                part.CFrame.LookVector
            )
    else
        longAxis =
            horizontalUnit(
                part.CFrame.RightVector
            )
    end

    local topY =
        part.Position.Y
        + part.Size.Y * 0.5
        + CONFIG.BELT_TOP_OFFSET

    local onBelt =
        Vector3.new(
            part.Position.X,
            topY,
            part.Position.Z
        )

    local outside =
        onBelt
        - longAxis
            * (
                math.max(part.Size.X, part.Size.Z) * 0.5
                + CONFIG.OUTSIDE_OFFSET
            )

    return outside, onBelt, longAxis
end

local function moveDirect(target, timeout)
    local _, humanoid, root =
        getCharacterRig()

    if not humanoid or not root then
        return false, "character_missing"
    end

    humanoid.Sit = false

    local reached = false
    local finished = false

    local connection =
        humanoid.MoveToFinished:
        Connect(function(ok)
            reached = ok == true
            finished = true
        end)

    humanoid:MoveTo(target)

    local started =
        os.clock()

    while
        Session.Running
        and Session.AutoRunning
        and not Session.AutoAbort
        and not finished
    do
        local distance =
            (root.Position - target).Magnitude

        if distance <= 4.5 then
            reached = true
            break
        end

        if os.clock() - started >= timeout then
            break
        end

        task.wait(0.06)
    end

    connection:Disconnect()

    return reached,
        reached and nil or "move_timeout"
end

local function movePath(target)
    local _, humanoid, root =
        getCharacterRig()

    if not humanoid or not root then
        return false, "character_missing"
    end

    local path =
        PathfindingService:CreatePath({
            AgentRadius=2,
            AgentHeight=5,
            AgentCanJump=true,
            AgentCanClimb=true,
            WaypointSpacing=5,
        })

    local ok =
        pcall(function()
            path:ComputeAsync(
                root.Position,
                target
            )
        end)

    if not ok
    or path.Status ~= Enum.PathStatus.Success
    then
        return moveDirect(
            target,
            CONFIG.MOVE_TIMEOUT
        )
    end

    local waypoints =
        path:GetWaypoints()

    for i, waypoint in ipairs(waypoints) do
        if
            not Session.AutoRunning
            or Session.AutoAbort
        then
            return false, "aborted"
        end

        if i > 1 then
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end

            local reached, err =
                moveDirect(
                    waypoint.Position,
                    CONFIG.PATH_WAYPOINT_TIMEOUT
                )

            if not reached then
                return false, err
            end
        end
    end

    return true
end

local function passiveWait(seconds, driveDirection, midCallback)
    local started =
        os.clock()

    local midDone = false

    while
        Session.Running
        and Session.AutoRunning
        and not Session.AutoAbort
        and os.clock() - started < seconds
    do
        if driveDirection then
            local _, humanoid =
                getCharacterRig()

            if humanoid then
                humanoid.Sit = false

                humanoid:Move(
                    driveDirection,
                    false
                )
            end
        end

        if
            midCallback
            and not midDone
            and os.clock() - started
                >= CONFIG.MIDRUN_PROBE_AT
        then
            midDone = true
            midCallback()
        end

        task.wait(
            driveDirection
            and CONFIG.BELT_RUN_INPUT_INTERVAL
            or 0.08
        )
    end

    if driveDirection then
        local _, humanoid =
            getCharacterRig()

        if humanoid then
            humanoid:Move(
                Vector3.zero,
                false
            )
        end
    end
end

local function runAutoTrial(part, trial)
    Session.AutoTrial = trial

    local outside,
        onBelt,
        beltDirection =
        treadmillGeometry(part)

    local askWear =
        findTreadmillRemote(
            "AskWearStill",
            "RemoteFunction"
        )

    local askDoff =
        findTreadmillRemote(
            "AskDoff",
            "RemoteFunction"
        )

    local gainsBefore =
        Session.GainCounter

    local leaderBefore =
        getLeaderSpeed()

    local speedPowerBefore =
        Session.LastSpeedPower

    -- CONTROL: outside the treadmill.
    setAutoPhase(
        "control_outside",
        {
            trial=trial,
            target=safeSerialize(outside),
        }
    )

    movePath(outside)

    autoCheckpoint(
        "outside_arrived"
    )

    invokeKnownNoArg(
        askWear,
        "AskWearStill_outside_control"
    )

    passiveWait(
        CONFIG.FAR_BASELINE_SECONDS
    )

    autoCheckpoint(
        "outside_control_complete"
    )

    -- ENTER.
    setAutoPhase(
        "enter_treadmill",
        {
            trial=trial,
            target=safeSerialize(onBelt),
        }
    )

    movePath(
        outside
        + horizontalUnit(onBelt - outside)
            * math.max(
                2,
                (onBelt - outside).Magnitude - 4
            )
    )

    moveDirect(
        onBelt,
        CONFIG.MOVE_TIMEOUT
    )

    autoCheckpoint(
        "on_belt_arrived"
    )

    -- Known legitimate no-arg request after physically reaching the belt.
    invokeKnownNoArg(
        askWear,
        "AskWearStill_on_belt"
    )

    -- TRAIN.
    setAutoPhase(
        "training",
        {
            trial=trial,
            seconds=CONFIG.ON_BELT_SECONDS,
        }
    )

    passiveWait(
        CONFIG.ON_BELT_SECONDS,
        beltDirection,
        CONFIG.ACTIVE_PROBE_MIDRUN
            and function()
                invokeKnownNoArg(
                    askWear,
                    "AskWearStill_mid_training"
                )
            end
            or nil
    )

    autoCheckpoint(
        "training_complete"
    )

    -- EXIT.
    setAutoPhase(
        "exit_treadmill",
        {
            trial=trial,
        }
    )

    movePath(outside)

    autoCheckpoint(
        "outside_after_training"
    )

    invokeKnownNoArg(
        askDoff,
        "AskDoff_after_exit"
    )

    passiveWait(
        CONFIG.POST_EXIT_SECONDS
    )

    autoCheckpoint(
        "post_exit_complete"
    )

    queueRecord({
        source="auto_lab",
        kind="trial_summary",
        trial=trial,

        speedPowerBefore=
            speedPowerBefore,

        speedPowerAfter=
            Session.LastSpeedPower,

        speedPowerDelta=
            type(speedPowerBefore) == "number"
            and type(Session.LastSpeedPower) == "number"
            and (
                Session.LastSpeedPower
                - speedPowerBefore
            )
            or nil,

        leaderSpeedBefore=
            leaderBefore,

        leaderSpeedAfter=
            getLeaderSpeed(),

        leaderSpeedDelta=
            type(leaderBefore) == "number"
            and type(getLeaderSpeed()) == "number"
            and (
                getLeaderSpeed()
                - leaderBefore
            )
            or nil,

        speedGainEvents=
            Session.GainCounter
            - gainsBefore,

        treadmill=
            compactCandidateState(part),

        environment=
            environmentSnapshot(),

        history=
            historySnapshot(),
    })
end

local stopAndUpload

local function runAutoLab()
    if Session.AutoRunning then
        return
    end

    Session.AutoRunning = true
    Session.AutoAbort = false
    Session.AutoTrial = 0
    Session.AutoPhase = "selecting_treadmill"

    local part =
        selectBestTreadmill()

    if not part then
        Session.AutoRunning = false

        queueRecord({
            source="auto_lab",
            kind="auto_lab_failed",
            reason="no_treadmill_candidate",
            environment=environmentSnapshot(),
        })

        Status.Text =
            "Esteira não encontrada • dados preservados"

        if updateUI then
            updateUI(true)
        end

        return
    end

    Session.AutoTreadmillPath =
        safePath(part)

    queueRecord({
        source="auto_lab",
        kind="auto_lab_started",
        configuredTrials=CONFIG.AUTO_TRIALS,
        treadmill=compactCandidateState(part),
        activeProbePolicy={
            onlyKnownNoArgRemotes=true,
            askWearStill=true,
            askDoff=true,
            fuzzing=false,
            inventedArguments=false,
        },
        environment=environmentSnapshot(),
    })

    for trial = 1, CONFIG.AUTO_TRIALS do
        if
            not Session.Running
            or Session.AutoAbort
        then
            break
        end

        runAutoTrial(
            part,
            trial
        )

        if trial < CONFIG.AUTO_TRIALS then
            setAutoPhase(
                "between_trials",
                {
                    trial=trial,
                }
            )

            passiveWait(
                CONFIG.BETWEEN_TRIALS_SECONDS
            )
        end
    end

    Session.AutoRunning = false
    Session.AutoPhase = "completed"

    queueRecord({
        source="auto_lab",
        kind="auto_lab_completed",
        completedTrials=Session.AutoTrial,
        activeRemoteCallsByCollector=
            Session.ActiveRemoteCallsByCollector,
        totalSpeedGainEvents=
            Session.GainCounter,
        lastSpeedPower=
            Session.LastSpeedPower,
        leaderSpeed=
            getLeaderSpeed(),
        treadmillPath=
            Session.AutoTreadmillPath,
        environment=
            environmentSnapshot(),
        history=
            historySnapshot(),
    })

    if
        Session.Running
        and not Session.AutoAbort
        and stopAndUpload
    then
        task.wait(0.35)
        stopAndUpload()
    end
end

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    RED=Color3.fromRGB(169,42,49),
    GREEN=Color3.fromRGB(29,111,58),
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
Main.Size = UDim2.fromOffset(286, 184)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.44)
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
Title.Position = UDim2.fromOffset(10, 7)
Title.Size = UDim2.new(1, -20, 0, 23)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • TREADMILL AUTO LAB"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Action = Instance.new("TextButton")
Action.Position = UDim2.fromOffset(10, 36)
Action.Size = UDim2.new(1, -20, 0, 40)
Action.BackgroundColor3 = COLORS.BUTTON
Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "INICIAR AUTO TESTES"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 8)
actionCorner.Parent = Action

Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10, 83)
Status.Size = UDim2.new(1, -20, 0, 34)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • testes automáticos da esteira"
Status.TextColor3 = COLORS.TEXT
Status.TextSize = 10
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

local Detail = Instance.new("TextLabel")
Detail.BackgroundTransparency = 1
Detail.Position = UDim2.fromOffset(10, 119)
Detail.Size = UDim2.new(1, -20, 0, 32)
Detail.Font = Enum.Font.Gotham
Detail.Text = "0.00 MB • 0 registros"
Detail.TextColor3 = COLORS.MUTED
Detail.TextSize = 9
Detail.TextWrapped = true
Detail.TextXAlignment = Enum.TextXAlignment.Left
Detail.TextYAlignment = Enum.TextYAlignment.Top
Detail.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(10, 162)
BarBack.Size = UDim2.new(1, -20, 0, 7)
BarBack.BackgroundColor3 = Color3.fromRGB(27,27,31)
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(1,0)
bc.Parent = BarBack

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(1,0)
fc.Parent = BarFill

-- Drag
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
            Upload.TotalChunks > 0
                and ("/" .. tostring(Upload.TotalChunks))
                or " • streaming"
        )

        local ratio =
            Upload.TotalBytes > 0
            and math.clamp(Upload.BytesSent / Upload.TotalBytes, 0, 1)
            or 0

        BarFill.Size = UDim2.new(ratio, 0, 1, 0)

        Detail.Text = string.format(
            "%.2f / %.2f MB",
            mb(Upload.BytesSent),
            mb(Upload.TotalBytes)
        )
        return
    end

    BarFill.Size = UDim2.new(
        math.clamp(Archive.Bytes / CONFIG.MAX_ARCHIVE_BYTES, 0, 1),
        0, 1, 0
    )

    if Session.Running then
        local leader = getLeaderSpeed()

        Status.Text =
            "Coletando • use a esteira normalmente"

        Detail.Text = string.format(
            "%.2f MB • %d regs • Speed %s • %s",
            mb(Archive.Bytes),
            Archive.Records,
            leader ~= nil and tostring(leader) or "?",
            HookInstalled and "IN+OUT" or "IN"
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

    local decodeOk, decoded =
        pcall(HttpService.JSONDecode, HttpService, body)

    if decodeOk then
        return true, decoded, nil
    end

    return true, {raw=body}, nil
end

local function iterateObjects(callback)
    local header = {
        recordType="treadmill_trace_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        clientVisibleOnly=true,
        passive=true,
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
                        local decodeOk, object =
                            pcall(HttpService.JSONDecode, HttpService, line)

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
            local decodeOk, object =
                pcall(HttpService.JSONDecode, HttpService, line)

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
    local streamError = nil

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
            collectgarbage("step", 180)
        end)

        return true
    end

    local iterOk = iterateObjects(function(object)
        local encoded = safeJson(object)
        local add = #encoded + 1

        if #current > 0
        and currentBytes + add > CONFIG.UPLOAD_CHUNK_BYTES
        then
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
    Upload.TotalBytes = math.max(Archive.Bytes, 1)

    Action.Text = "ENVIANDO..."
    Action.BackgroundColor3 = COLORS.RED
    Status.Text = "Iniciando upload streaming..."
    updateUI(true)

    flushPending(true)
    writeManifest()

    local filename = string.format(
        "Cafeina_TreadmillTrace_%s_%s.json",
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
                passive=true,
                focus="treadmill_auto_transition_active_lab",
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
        Action.BackgroundColor3 = COLORS.BUTTON
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
        Status.Text = "/start inválido • dados preservados"
        Action.Text = "REENVIAR"
        Action.BackgroundColor3 = COLORS.BUTTON
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
        Action.BackgroundColor3 = COLORS.BUTTON
        updateUI(true)
        return
    end

    Upload.TotalChunks = chunkCount
    Upload.TotalBytes = math.max(payloadBytes, 1)
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
        Action.BackgroundColor3 = COLORS.BUTTON
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
        Action.BackgroundColor3 = COLORS.BUTTON
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
        and ("Link recebido • " .. string.sub(Upload.LastURL, 1, 70))
        or "Servidor confirmou • arquivo local limpo"

    Action.Text = "INICIAR AUTO TESTES"
    Action.BackgroundColor3 = COLORS.BUTTON
    BarFill.Size = UDim2.new(1,0,1,0)
end

--==============================================================--
-- SESSION
--==============================================================--

local function disconnectAll()
    for _, c in ipairs(Connections) do
        pcall(function()
            c:Disconnect()
        end)
    end
    table.clear(Connections)
    table.clear(InboundObserved)
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

    Session.LastOutbound = nil
    Session.LastInbound = nil
    Session.LastSpeedPower = nil
    Session.LastLeaderSpeed = getLeaderSpeed()
    Session.LastSpeedGainClock = 0

    Session.LastSampleClock = 0
    Session.LastIdleSampleClock = 0
    Session.LastCandidateRefresh = 0
    Session.LastTouchScanClock = 0
    Session.History = {}
    Session.CurrentTouching = {}
    Session.CandidateWatchState = {}
    Session.GainCounter = 0

    Action.Text = "PARAR + ENVIAR"
    Action.BackgroundColor3 = COLORS.RED

    local registryCount = buildRegistry()

    local remoteCatalog = {}
    for remote, info in pairs(RemoteInfo) do
        if info.treadmill then
            table.insert(remoteCatalog, {
                name=info.name,
                path=info.path,
                className=info.className,
            })
        end
    end

    table.sort(remoteCatalog, function(a, b)
        return tostring(a.path) < tostring(b.path)
    end)

    queueRecord({
        source="session",
        kind="treadmill_remote_catalog",
        count=#remoteCatalog,
        remotes=remoteCatalog,
    })

    queueRecord({
        source="session",
        kind="session_started",
        registryCount=registryCount,
        capabilities={
            filesystem=FILESYSTEM_OK and true or false,
            request=REQUEST ~= nil,
            hookmetamethod=HOOKMETAMETHOD ~= nil,
            getnamecallmethod=GETNAMECALLMETHOD ~= nil,
        },
        automatedPhysicalTrials=true,
        activeRemoteTests=true,
        activeRemotePolicy="known legitimate no-argument Treadmill RFs only",
        environment=environmentSnapshot(),
    })

    installHook()
    installInbound()
    installLeaderSpeedWatch()

    task.spawn(refreshCandidates)

    Status.Text = "Preparando testes automáticos..."
    updateUI(true)

    task.spawn(function()
        task.wait(0.55)

        if Session.Running then
            runAutoLab()
        end
    end)
end

stopAndUpload = function()
    if not Session.Running or Upload.Running then
        return
    end

    Session.AutoAbort = true
    Session.AutoRunning = false
    Session.StopRequested = true

    queueRecord({
        source="session",
        kind="session_finalized",
        recordsThisRun=Session.RecordsThisRun,
        archivedRecords=Archive.Records,
        archivedBytes=Archive.Bytes,
        lastSpeedPower=Session.LastSpeedPower,
        leaderSpeed=getLeaderSpeed(),
        activeRemoteCallsByCollector=
            Session.ActiveRemoteCallsByCollector,
        completedAutoTrials=
            Session.AutoTrial,
        autoPhase=
            Session.AutoPhase,
        environment=environmentSnapshot(),
    })

    disconnectAll()
    flushPending(true)
    writeManifest()

    Session.Running = false
    restoreHook()

    Action.Text = "ENVIANDO..."
    Action.BackgroundColor3 = COLORS.RED
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

env.__CAFEINA_TREADMILL_TRACE_CONTROLLER = {
    Stop=function(reason)
        Session.AutoAbort = true
        Session.AutoRunning = false
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
        restoreHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] TREADMILL AUTO LAB V2.0 carregado.")
