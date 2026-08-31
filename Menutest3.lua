--==============================================================--
-- CAFEÍNA • TREADMILL TRACE V1.0
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
-- • Este menu NÃO inventa nem dispara remotes de ganho.
-- • NÃO altera SpeedPower/leaderstats.
-- • NÃO altera WalkSpeed.
-- • NÃO teleporta e NÃO precisa modificar a esteira.
-- • É um tracer client-visible/passivo para aprender o fluxo real.
--
-- Uso recomendado:
-- 1. INICIAR TESTE
-- 2. alguns segundos fora da esteira
-- 3. entrar/correr na esteira por 10–20 s
-- 4. sair e esperar alguns segundos
-- 5. ENCERRAR + ENVIAR
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "TREADMILL_TRACE_V1_0",
    GUI_NAME = "CafeinaTreadmillTraceV10",

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
    CORRELATION_SECONDS = 2.5,

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

    TreadmillCandidates = {},
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
                out[i] = {
                    path=safePath(part),
                    position=safeSerialize(part.Position),
                    size=safeSerialize(part.Size),
                    canCollide=part.CanCollide,
                    canTouch=part.CanTouch,
                    canQuery=part.CanQuery,
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

local function environmentSnapshot()
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
    end

    Session.LastInbound = {
        time=relativeTime(),
        remote=info.path,
    }

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

    if now - Session.LastCandidateRefresh >= CONFIG.CANDIDATE_REFRESH then
        Session.LastCandidateRefresh = now
        task.spawn(refreshCandidates)
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
Title.Text = "CAFEÍNA • TREADMILL TRACE"
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
Action.Text = "INICIAR TESTE"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 8)
actionCorner.Parent = Action

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10, 83)
Status.Size = UDim2.new(1, -20, 0, 34)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • tracer passivo"
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
                focus="treadmill_speedpower",
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

    Action.Text = "INICIAR TESTE"
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

    Action.Text = "ENCERRAR + ENVIAR"
    Action.BackgroundColor3 = COLORS.RED

    local registryCount = buildRegistry()

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
        environment=environmentSnapshot(),
    })

    installHook()
    installInbound()
    installLeaderSpeedWatch()

    task.spawn(refreshCandidates)

    Status.Text = "Coletando • use a esteira normalmente"
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
        lastSpeedPower=Session.LastSpeedPower,
        leaderSpeed=getLeaderSpeed(),
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

print("[CAFEÍNA] TREADMILL TRACE V1.0 carregado.")
