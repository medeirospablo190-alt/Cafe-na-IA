--==============================================================--
-- CAFEINA • UNIVERSAL GAME TRACE V3.0.1
-- Adaptive, bidirectional, persistent-per-game collector.
--
-- DESIGN RULES
--  1) Observe inbound AND client->server remote calls without changing their arguments.
--  2) Never generate unknown remote calls; outbound observation is passive.
--  3) Exact duplicates are suppressed; repeated noise is counted, not stored.
--  4) Knowledge is scoped by game.GameId. A different game starts fresh.
--  5) New/high-interest remote shapes receive temporary deeper observation.
--  6) Important outbound calls open bounded cause/effect correlation windows.
--  7) Argument schemas are inferred from observed calls, never guessed.
--  8) Collection adapts to novelty yield instead of self-modifying code.
--  9) Static scans are incremental and time-budgeted to protect mobile FPS.
-- 10) Backpressure reduces low-value collection before memory can grow.
-- 11) Uploads are coalesced; tiny batches are not flushed every UI tick.
-- 12) One manifest slot is always reserved; batch exhaustion cannot deadlock finalization.
-- 13) 96 MB = soft budget, 128 MB = protection, 150 MB = hard stop.
-- 14) A batch is acknowledged only after the server confirms GitHub mirroring.
-- 15) Historical batches are append-only/idempotent on the V3 server route.
-- 16) The UI stays compact: MB collected + upload % + one action button.
-- 17) No replay buffer and no verbose analysis UI.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local MB = 1024 * 1024
local C = {
    VERSION = "CAFEINA_UNIVERSAL_GAME_TRACE_V3_0_1",
    PURPOSE = "adaptive_bidirectional_game_mapping",

    BASE = "https://cafe-na-ia.onrender.com/api/inventory-trace-v3",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace-v3/health",

    HARD_BYTES = 150 * MB,
    PROTECT_BYTES = 128 * MB,
    SOFT_BYTES = 96 * MB,

    BATCH_TARGET_BYTES = math.floor(1.75 * MB),
    BATCH_MIN_FLUSH_BYTES = math.floor(1.75 * MB * 0.70),
    BATCH_MAX_LATENCY = 10.0,
    QUEUE_SOFT_BYTES = 4 * MB,
    QUEUE_HARD_BYTES = 8 * MB,

    MAX_RECORDS_PER_BATCH = 6000,
    MAX_REMOTES_PER_BATCH = 1000,
    MAX_BATCHES = 180,

    MAX_STRING = 1400,
    MAX_TABLE = 64,
    MAX_DEPTH = 5,
    MAX_ARGS = 28,

    MAX_INBOUND = 1100,
    MAX_VALUES = 850,
    MAX_GUI = 1200,
    MAX_NEARBY = 650,
    NEARBY_RADIUS = 150,

    RS_NODE_CAP = 18000,
    WS_NODE_CAP = 26000,
    GUI_NODE_CAP = 4500,
    SCAN_SLICE_MS = 0.0035,
    SCAN_SLICE_ITEMS = 70,

    TRAJECTORY_MIN_INTERVAL = 1.0,
    TRAJECTORY_IDLE_INTERVAL = 5.0,
    TRAJECTORY_MOVE_STUDS = 5.0,

    INVESTIGATION_SECONDS = 8.0,
    CORRELATION_SECONDS = 5.0,
    CORRELATION_MIN_GAP = 0.75,
    MAX_CORRELATION_WINDOWS = 10,
    FOCUS_SCORE = 72,
    MIN_SEND_INTERVAL = 1.25,
    RETRIES = 4,
    RETRY_BASE = 0.8,

    DELTA_LOW_CAP = 6000,
    DELTA_SHAPE_CAP = 4000,
    DELTA_REMOTE_CAP = 1500,
    EXACT_SESSION_CAP = 50000,

    CACHE_SUFFIX = "CafeinaUniversalTraceV30_pending.json",
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synReq, httpReq
pcall(function() if syn and type(syn.request) == "function" then synReq = syn.request end end)
pcall(function() if http and type(http.request) == "function" then httpReq = http.request end end)

local REQUEST = pick(rawget(ENV, "request"), rawget(ENV, "http_request"), request, http_request, httpReq, synReq)
local WRITEFILE = pick(rawget(ENV, "writefile"), writefile)
local READFILE = pick(rawget(ENV, "readfile"), readfile)
local ISFILE = pick(rawget(ENV, "isfile"), isfile)
local DELFILE = pick(rawget(ENV, "delfile"), delfile)
local HOOKMETAMETHOD = pick(rawget(ENV, "hookmetamethod"), hookmetamethod)
local GETNAMECALLMETHOD = pick(rawget(ENV, "getnamecallmethod"), getnamecallmethod)
local NEWCLOSURE = pick(rawget(ENV, "newcclosure"), newcclosure)

--==============================================================--
-- SAFE SERIALIZATION + STABLE SIGNATURES
--==============================================================--

local function iso()
    local ok, value = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and value or tostring(os.time())
end

local function pathOf(x)
    if typeof(x) ~= "Instance" then return tostring(x) end
    local ok, value = pcall(function() return x:GetFullName() end)
    return ok and value or (x.ClassName .. ":" .. x.Name)
end

local function ser(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > C.MAX_DEPTH then return "<max_depth>" end

    local t = typeof(v)
    if v == nil or t == "boolean" then return v end
    if t == "number" then
        if v ~= v then return "<nan>" end
        if v == math.huge then return "<inf>" end
        if v == -math.huge then return "<-inf>" end
        return v
    end
    if t == "string" then
        if #v > C.MAX_STRING then return string.sub(v, 1, C.MAX_STRING) .. "...[truncated]" end
        return v
    end
    if t == "Vector2" then return { type = "Vector2", x = v.X, y = v.Y } end
    if t == "Vector3" then return { type = "Vector3", x = v.X, y = v.Y, z = v.Z } end
    if t == "CFrame" then
        local p = v.Position
        local rx, ry, rz = v:ToOrientation()
        return { type = "CFrame", x = p.X, y = p.Y, z = p.Z, rx = rx, ry = ry, rz = rz }
    end
    if t == "Color3" then return { type = "Color3", r = v.R, g = v.G, b = v.B } end
    if t == "UDim2" then return { type = "UDim2", xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset } end
    if t == "EnumItem" then return tostring(v) end
    if t == "Instance" then return { type = "Instance", name = v.Name, className = v.ClassName, path = pathOf(v) } end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out, n = {}, 0
        for k, item in pairs(v) do
            n = n + 1
            if n > C.MAX_TABLE then out["<truncated>"] = true break end
            out[tostring(k)] = ser(item, depth + 1, seen)
        end
        seen[v] = nil
        return out
    end
    return tostring(v)
end

local function attrs(inst)
    local ok, value = pcall(function() return inst:GetAttributes() end)
    return ok and ser(value) or {}
end

local function canon(v, depth, seen, shapeOnly)
    depth = depth or 0
    seen = seen or {}
    if depth > C.MAX_DEPTH then return "D" end

    local t = typeof(v)
    if v == nil then return "Z" end
    if t == "boolean" then return shapeOnly and "B" or (v and "B1" or "B0") end
    if t == "number" then
        if shapeOnly then return "N" end
        if v ~= v then return "N:nan" end
        if v == math.huge then return "N:inf" end
        if v == -math.huge then return "N:-inf" end
        return "N:" .. tostring(v)
    end
    if t == "string" then
        if shapeOnly then return "S" end
        local text = #v > C.MAX_STRING and string.sub(v, 1, C.MAX_STRING) or v
        return "S:" .. text
    end
    if t == "EnumItem" then return shapeOnly and "E" or ("E:" .. tostring(v)) end
    if t == "Instance" then
        return shapeOnly and ("I:" .. v.ClassName) or ("I:" .. v.ClassName .. ":" .. pathOf(v))
    end
    if t == "Vector2" then return shapeOnly and "V2" or string.format("V2:%.3f,%.3f", v.X, v.Y) end
    if t == "Vector3" then return shapeOnly and "V3" or string.format("V3:%.3f,%.3f,%.3f", v.X, v.Y, v.Z) end
    if t == "CFrame" then
        if shapeOnly then return "CF" end
        local p = v.Position
        return string.format("CF:%.3f,%.3f,%.3f", p.X, p.Y, p.Z)
    end
    if t == "Color3" then return shapeOnly and "C3" or string.format("C3:%.3f,%.3f,%.3f", v.R, v.G, v.B) end
    if t == "UDim2" then
        return shapeOnly and "U2" or string.format("U2:%.3f,%d,%.3f,%d", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    end
    if t == "table" then
        if seen[v] then return "T:<cycle>" end
        seen[v] = true
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = tostring(k)
            if #keys >= C.MAX_TABLE then break end
        end
        table.sort(keys)
        local parts = { "T{" }
        for _, key in ipairs(keys) do
            local item = v[key]
            if item == nil then
                for realKey, realValue in pairs(v) do
                    if tostring(realKey) == key then item = realValue break end
                end
            end
            parts[#parts + 1] = key
            parts[#parts + 1] = "="
            parts[#parts + 1] = canon(item, depth + 1, seen, shapeOnly)
            parts[#parts + 1] = ";"
        end
        parts[#parts + 1] = "}"
        seen[v] = nil
        return table.concat(parts)
    end
    return shapeOnly and ("X:" .. t) or ("X:" .. t .. ":" .. tostring(v))
end

local function hashText(text)
    local h1, h2 = 216613, 131071
    for i = 1, #text do
        local b = string.byte(text, i)
        h1 = (h1 * 131 + b) % 16777213
        h2 = (h2 * 137 + b) % 16777199
    end
    return string.format("%06x%06x", h1, h2)
end

local function signature(kind, key, value, shapeOnly)
    return hashText(tostring(kind) .. "\31" .. tostring(key or "") .. "\31" .. canon(value, 0, {}, shapeOnly == true))
end

local function tagsOf(inst)
    local ok, value = pcall(function() return CollectionService:GetTags(inst) end)
    if not ok or type(value) ~= "table" or #value == 0 then return nil end
    table.sort(value)
    return value
end

local function packed(args)
    local n = tonumber(args and args.n) or 0
    local out = { count = n, values = {} }
    local lim = math.min(n, C.MAX_ARGS)
    for i = 1, lim do out.values[i] = ser(args[i]) end
    if n > lim then out.truncated = n - lim end
    return out
end

local function packedCanon(args, shapeOnly)
    local n = tonumber(args and args.n) or 0
    local parts = { tostring(n), "[" }
    local lim = math.min(n, C.MAX_ARGS)
    for i = 1, lim do
        parts[#parts + 1] = canon(args[i], 0, {}, shapeOnly)
        parts[#parts + 1] = ";"
    end
    if n > lim then parts[#parts + 1] = "+" .. tostring(n - lim) end
    parts[#parts + 1] = "]"
    return table.concat(parts)
end

--==============================================================--
-- NETWORK
--==============================================================--

local function rawRequest(options)
    if not REQUEST then return false, nil, "executor_request_unavailable" end
    local last = "unknown"
    for attempt = 1, C.RETRIES do
        local ok, response = pcall(REQUEST, options)
        if ok and type(response) == "table" then
            local code = tonumber(response.StatusCode or response.Status or response.status) or 0
            if code >= 200 and code < 300 then return true, response, nil end
            last = "HTTP " .. tostring(code) .. " " .. tostring(response.Body or response.body or "")
            if code == 429 or code >= 500 then task.wait(C.RETRY_BASE * attempt) else break end
        else
            last = tostring(response)
            task.wait(C.RETRY_BASE * attempt)
        end
    end
    return false, nil, last
end

local function getJson(url)
    local ok, response, err = rawRequest({ Url = url, Method = "GET", Headers = { Accept = "application/json" } })
    if not ok then return false, nil, err end
    local good, data = pcall(HttpService.JSONDecode, HttpService, response.Body or response.body or "{}")
    if not good then return false, nil, tostring(data) end
    return true, data, nil
end

local function postRaw(url, body)
    local ok, response, err = rawRequest({
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
        Body = body,
    })
    if not ok then return false, nil, err end
    local good, data = pcall(HttpService.JSONDecode, HttpService, response.Body or response.body or "{}")
    if not good or type(data) ~= "table" then return false, nil, "invalid_api_response" end
    if data.ok ~= true then return false, data, tostring(data.message or "api_not_ok") end
    if type(data.github) ~= "table" or data.github.configured ~= true or data.github.mirrored ~= true then
        return false, data, tostring((data.github and data.github.error) or "github_not_confirmed")
    end
    return true, data, nil
end

--==============================================================--
-- STATE + PROFILE MEMORY
--==============================================================--

local function arrayToSet(list)
    local out = {}
    if type(list) == "table" then
        for _, value in ipairs(list) do out[tostring(value)] = true end
    end
    return out
end

local S = {
    running = false,
    stopping = false,
    finalizing = false,
    uploading = false,
    uploadKick = false,
    runId = nil,
    runPlaceId = game.PlaceId,
    runGameId = game.GameId,
    runPlaceVersion = game.PlaceVersion,
    runEpoch = 0,
    startClock = 0,
    startIso = nil,

    queue = {},
    queueHead = 1,
    queueBytes = 0,
    totalBytes = 0,
    ackBytes = 0,
    batchIndex = 0,
    pendingSend = nil,
    finalManifest = nil,
    firstQueuedClock = 0,
    lastSendClock = 0,
    nextRetryClock = 0,
    lastUploadError = nil,

    profile = nil,
    profileLow = {},
    profileShape = {},
    profileRemote = {},
    profileFrontier = {},
    frontier = {}, frontierSet = {},
    deltaLow = {}, deltaLowSet = {},
    deltaShape = {}, deltaShapeSet = {},
    deltaRemote = {}, deltaRemoteSet = {},

    sessionExact = {},
    sessionExactCount = 0,
    remoteSeen = {},
    inbound = setmetatable({}, { __mode = "k" }),
    values = setmetatable({}, { __mode = "k" }),
    inboundCount = 0,
    valueCount = 0,
    conns = {},

    strategy = {},
    suppressed = {},
    dropped = {},
    repeatCounts = {},
    repeatKeyCount = 0,
    coverage = {},
    investigation = {},
    recentRefs = {},
    correlationWindows = {},
    correlationSeq = 0,
    lastCorrelationByRemote = {},
    smartStats = {
        outboundObserved = 0,
        outboundAccepted = 0,
        highInterestOutbound = 0,
        correlationsOpened = 0,
        batchBudgetDrops = 0,
    },
    focusRemote = nil,
    focusScore = 0,
    outboundHookRegistry = nil,
    outboundHookReady = false,

    frameDt = 1 / 60,
    lastTrajectoryAt = 0,
    lastTrajectoryPos = nil,
    lastTrajectoryState = nil,

    preflightReady = false,
    serverReady = false,
    profileReady = false,
    cached = nil,
    manifestConfirmed = false,
    finishCallback = nil,
}

local function bump(tbl, key, amount)
    tbl[key] = (tbl[key] or 0) + (amount or 1)
end

local function addBoundedDelta(array, set, value, cap)
    value = tostring(value)
    if set[value] or #array >= cap then return end
    set[value] = true
    array[#array + 1] = value
end

local function strategyFor(category)
    local state = S.strategy[category]
    if state then return state end
    local prior = S.profile and S.profile.strategy and S.profile.strategy[category]
    state = {
        observed = 0, accepted = 0, novel = 0, suppressed = 0,
        sampleN = math.clamp(tonumber(prior and prior.sampleN) or 1, 1, 16),
        cursor = 0,
    }
    S.strategy[category] = state
    return state
end

local function tuneStrategy(state)
    if state.observed < 50 or state.observed % 50 ~= 0 then return end
    local novelty = state.novel / math.max(1, state.observed)
    if novelty < 0.01 then
        state.sampleN = math.min(16, math.max(4, state.sampleN * 2))
    elseif novelty < 0.05 then
        state.sampleN = math.min(8, math.max(2, state.sampleN))
    elseif novelty > 0.20 then
        state.sampleN = math.max(1, math.floor(state.sampleN / 2))
    end
end

local function pressureLevel()
    if S.totalBytes >= C.HARD_BYTES or S.queueBytes >= C.QUEUE_HARD_BYTES then return 3 end
    if S.totalBytes >= C.PROTECT_BYTES or S.queueBytes >= C.QUEUE_SOFT_BYTES or S.frameDt > 0.055 then return 2 end
    if S.totalBytes >= C.SOFT_BYTES or S.queueBytes >= C.QUEUE_SOFT_BYTES * 0.5 or S.frameDt > 0.038 then return 1 end
    return 0
end

local function adaptiveAllow(category, priority, novel, bypassSampling)
    local st = strategyFor(category)
    st.observed = st.observed + 1
    if novel then st.novel = st.novel + 1 end
    tuneStrategy(st)

    local pressure = pressureLevel()
    local minPriority = ({ [0] = 0, [1] = 45, [2] = 72, [3] = 101 })[pressure]
    if priority < minPriority then
        st.suppressed = st.suppressed + 1
        bump(S.suppressed, category)
        return false
    end

    if priority >= 90 or bypassSampling then return true end
    st.cursor = st.cursor + 1
    if st.sampleN > 1 and (st.cursor % st.sampleN) ~= 0 then
        st.suppressed = st.suppressed + 1
        bump(S.suppressed, category)
        return false
    end
    return true
end

local function rememberRecent(ref)
    S.recentRefs[#S.recentRefs + 1] = ref
    if #S.recentRefs > 10 then table.remove(S.recentRefs, 1) end
end

local function contextRefs()
    local out = {}
    local first = math.max(1, #S.recentRefs - 3)
    for i = first, #S.recentRefs do out[#out + 1] = S.recentRefs[i] end
    return out
end

local function applyProfile(profile)
    profile = type(profile) == "table" and profile or {}
    S.profile = profile
    S.profileLow = arrayToSet(profile.knownLowValueHashes)
    S.profileShape = arrayToSet(profile.knownShapeHashes)
    S.profileRemote = arrayToSet(profile.knownRemoteHashes)
    S.profileFrontier = arrayToSet(profile.frontier)
    S.profileReady = true
end

local function loadRemoteProfile(preserveOnFailure)
    if not REQUEST then
        if not preserveOnFailure then applyProfile({}) end
        return false, "no_request"
    end
    local ok, data, err = getJson(C.BASE .. "/profile/" .. tostring(game.GameId))
    if ok and type(data) == "table" and data.ok == true then
        applyProfile(data.profile or {})
        return true
    end
    if not preserveOnFailure then applyProfile({}) end
    return false, err or "profile_unavailable"
end

--==============================================================--
-- PLAYER / OBJECT SNAPSHOTS
--==============================================================--

local function playerContext(full)
    local ch = LP.Character
    local out = { userId = LP.UserId, character = ch ~= nil }
    if not ch then return out end
    local root = ch:FindFirstChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if root then
        out.position = ser(root.Position)
        if full then
            out.velocity = ser(root.AssemblyLinearVelocity)
            out.angularVelocity = ser(root.AssemblyAngularVelocity)
        end
    end
    if hum then
        out.health = hum.Health
        out.state = tostring(hum:GetState())
        if full then
            out.maxHealth = hum.MaxHealth
            out.walkSpeed = hum.WalkSpeed
            out.jumpPower = hum.JumpPower
            out.floor = tostring(hum.FloorMaterial)
            out.moveDirection = ser(hum.MoveDirection)
        end
    end
    return out
end

local function isRemote(x)
    return x:IsA("RemoteEvent") or x:IsA("RemoteFunction") or x:IsA("UnreliableRemoteEvent")
end

local function remoteDesc(r)
    return {
        path = pathOf(r), name = r.Name, className = r.ClassName,
        parent = r.Parent and pathOf(r.Parent) or nil,
        attributes = attrs(r),
    }
end

local function valueSnap(v)
    local out = { path = pathOf(v), name = v.Name, className = v.ClassName, attributes = attrs(v) }
    pcall(function() out.value = ser(v.Value) end)
    return out
end

local function obj(inst, source, cachedAttrs)
    local out = {
        source = source, path = pathOf(inst), name = inst.Name, className = inst.ClassName,
        parent = inst.Parent and pathOf(inst.Parent) or nil, attributes = cachedAttrs or attrs(inst),
        tags = tagsOf(inst),
    }
    if inst:IsA("ValueBase") then
        pcall(function() out.value = ser(inst.Value) end)
    elseif inst:IsA("ProximityPrompt") then
        out.prompt = {
            actionText = inst.ActionText, objectText = inst.ObjectText, enabled = inst.Enabled,
            hold = inst.HoldDuration, distance = inst.MaxActivationDistance,
            lineOfSight = inst.RequiresLineOfSight,
        }
    elseif inst:IsA("ClickDetector") then
        out.click = { distance = inst.MaxActivationDistance }
    elseif inst:IsA("Tool") then
        out.tool = { requiresHandle = inst.RequiresHandle, canBeDropped = inst.CanBeDropped }
    elseif inst:IsA("BasePart") then
        out.part = {
            position = ser(inst.Position), size = ser(inst.Size), material = tostring(inst.Material), anchored = inst.Anchored,
            canCollide = inst.CanCollide, canTouch = inst.CanTouch, canQuery = inst.CanQuery,
            transparency = inst.Transparency,
        }
    elseif inst:IsA("GuiObject") then
        out.gui = { visible = inst.Visible, position = ser(inst.Position), size = ser(inst.Size) }
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then out.gui.text = ser(inst.Text) end
    end
    return out
end

--==============================================================--
-- SMART IMPORTANCE / ARGUMENT SCHEMA / CORRELATION
--==============================================================--

local IMPORTANT_REMOTE_TERMS = {
    { "purchase", 20 }, { "buy", 18 }, { "sell", 18 }, { "trade", 20 },
    { "place", 18 }, { "deploy", 18 }, { "spawn", 14 }, { "upgrade", 16 },
    { "inventory", 15 }, { "weapon", 12 }, { "equip", 12 }, { "interact", 10 },
    { "teleport", 18 }, { "revive", 18 }, { "reward", 15 }, { "claim", 15 },
    { "cash", 12 }, { "currency", 12 }, { "damage", 10 }, { "heal", 10 },
    { "fire", 8 }, { "reload", 7 },
}
local LOW_VALUE_REMOTE_TERMS = {
    "analytics", "footstep", "particle", "camera", "soundeffect", "console",
}

local function importanceScore(remotePath, method, newShape, className)
    local score = method == "InvokeServer" and 50 or (method == "FireServer" and 42 or 34)
    if newShape then score = score + 22 end
    if className == "RemoteFunction" then score = score + 8 end

    local lower = string.lower(tostring(remotePath or ""))
    for _, row in ipairs(IMPORTANT_REMOTE_TERMS) do
        if string.find(lower, row[1], 1, true) then score = score + row[2] end
    end
    for _, term in ipairs(LOW_VALUE_REMOTE_TERMS) do
        if string.find(lower, term, 1, true) then score = score - 18 end
    end
    return math.clamp(score, 0, 100)
end

local function schemaOf(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)

    if t == "table" then
        if seen[v] then return { type = "table", cycle = true } end
        if depth >= 3 then return { type = "table", truncated = true } end
        seen[v] = true
        local fields, count = {}, 0
        for k, item in pairs(v) do
            count = count + 1
            if count > 16 then break end
            fields[tostring(k)] = schemaOf(item, depth + 1, seen)
        end
        seen[v] = nil
        return { type = "table", fields = fields, fieldCountAtLeast = count }
    end
    if t == "Instance" then return { type = "Instance", className = v.ClassName } end
    if t == "EnumItem" then return { type = "EnumItem", enum = tostring(v.EnumType) } end
    return { type = t }
end

local function packedSchema(args)
    local n = tonumber(args and args.n) or 0
    local out = { count = n, args = {} }
    local lim = math.min(n, C.MAX_ARGS)
    for i = 1, lim do out.args[i] = schemaOf(args[i], 0, {}) end
    if n > lim then out.truncated = n - lim end
    return out
end

local CORRELATABLE_CATEGORIES = {
    remote_inbound = true,
    value_changed = true,
    runtime_added = true,
    runtime_remove = true,
    tool_transition = true,
    player_attribute = true,
    prompt_triggered = true,
    character = true,
}

local function pruneCorrelationWindows()
    local now = os.clock()
    local out = {}
    for _, window in ipairs(S.correlationWindows) do
        if window.expiresAt > now then out[#out + 1] = window end
    end
    S.correlationWindows = out
end

local function correlationCandidates(category)
    if not CORRELATABLE_CATEGORIES[category] then return nil end
    pruneCorrelationWindows()
    if #S.correlationWindows == 0 then return nil end

    local now, out = os.clock(), {}
    local first = math.max(1, #S.correlationWindows - 2)
    for i = first, #S.correlationWindows do
        local w = S.correlationWindows[i]
        out[#out + 1] = {
            id = w.id, remote = w.remote, method = w.method, shape = w.shape,
            importance = w.importance, age = math.max(0, now - w.startedAt),
        }
    end
    return out
end

local function openCorrelationWindow(remotePath, method, shapeHash, importance)
    local now = os.clock()
    local last = S.lastCorrelationByRemote[remotePath] or 0
    if now - last < C.CORRELATION_MIN_GAP then return end
    S.lastCorrelationByRemote[remotePath] = now
    pruneCorrelationWindows()

    S.correlationSeq = S.correlationSeq + 1
    S.correlationWindows[#S.correlationWindows + 1] = {
        id = S.correlationSeq,
        remote = remotePath,
        method = method,
        shape = shapeHash,
        importance = importance,
        startedAt = now,
        expiresAt = now + C.CORRELATION_SECONDS,
    }
    while #S.correlationWindows > C.MAX_CORRELATION_WINDOWS do table.remove(S.correlationWindows, 1) end
    S.smartStats.correlationsOpened = (S.smartStats.correlationsOpened or 0) + 1
end

--==============================================================--
-- STREAMING QUEUE
--==============================================================--

local kickUpload

local function hasSeenExact(hash)
    return hash ~= nil and S.sessionExact[hash] == true
end

local function markExact(hash)
    if not hash or S.sessionExact[hash] then return end
    if S.sessionExactCount >= C.EXACT_SESSION_CAP then return end
    S.sessionExact[hash] = true
    S.sessionExactCount = S.sessionExactCount + 1
end

local function noteRepeat(hash)
    if not hash then return end
    if S.repeatCounts[hash] then
        S.repeatCounts[hash] = S.repeatCounts[hash] + 1
    elseif S.repeatKeyCount < 2000 then
        S.repeatCounts[hash] = 1
        S.repeatKeyCount = S.repeatKeyCount + 1
    end
end

local function enqueue(channel, category, object, priority, novelty, persistentKind, persistentHash, exactHash, bypassSampling)
    if not S.running or S.stopping then return false end

    if exactHash and hasSeenExact(exactHash) then
        noteRepeat(exactHash)
        bump(S.suppressed, category)
        local st = strategyFor(category)
        st.observed = st.observed + 1
        st.suppressed = st.suppressed + 1
        return false
    end

    if persistentKind == "low" and persistentHash and S.profileLow[persistentHash] then
        bump(S.suppressed, category)
        local st = strategyFor(category)
        st.observed = st.observed + 1
        st.suppressed = st.suppressed + 1
        return false
    end

    if not adaptiveAllow(category, priority, novelty == true, bypassSampling == true) then return false end

    object = object or {}
    object.kind = object.kind or category
    if exactHash or persistentHash then object.sig = exactHash or persistentHash end
    object.clock = os.clock() - S.startClock
    object.unix = os.time()
    object.runId = S.runId
    object.quality = math.clamp(priority + (novelty and 5 or 0), 0, 100)
    object.corr = math.floor(object.clock * 2)
    if priority >= 80 then object.contextRefs = contextRefs() end
    local causeCandidates = correlationCandidates(category)
    if causeCandidates then object.causeCandidates = causeCandidates end

    local ok, json = pcall(HttpService.JSONEncode, HttpService, object)
    if not ok or type(json) ~= "string" then
        bump(S.dropped, category)
        return false
    end

    local bytes = #json + 1
    if bytes > 256 * 1024 then
        bump(S.dropped, category)
        return false
    end
    if S.totalBytes + bytes > C.HARD_BYTES then
        bump(S.dropped, "hard_cap")
        S.stopping = true
        task.defer(function() if S.finishCallback then S.finishCallback(true) end end)
        return false
    end
    if S.queueBytes + bytes > C.QUEUE_HARD_BYTES then
        bump(S.dropped, "queue_hard_cap")
        return false
    end

    local wasEmpty = S.queueBytes <= 0
    S.queue[#S.queue + 1] = { channel = channel, json = json, bytes = bytes }
    S.queueBytes = S.queueBytes + bytes
    S.totalBytes = S.totalBytes + bytes
    if wasEmpty then S.firstQueuedClock = os.clock() end
    markExact(exactHash)

    local st = strategyFor(category)
    st.accepted = st.accepted + 1

    local ref = exactHash or persistentHash or hashText(json)
    rememberRecent(ref)

    if persistentKind == "low" and persistentHash then
        S.profileLow[persistentHash] = true
        addBoundedDelta(S.deltaLow, S.deltaLowSet, persistentHash, C.DELTA_LOW_CAP)
    elseif persistentKind == "shape" and persistentHash then
        S.profileShape[persistentHash] = true
        addBoundedDelta(S.deltaShape, S.deltaShapeSet, persistentHash, C.DELTA_SHAPE_CAP)
    elseif persistentKind == "remote" and persistentHash then
        S.profileRemote[persistentHash] = true
        addBoundedDelta(S.deltaRemote, S.deltaRemoteSet, persistentHash, C.DELTA_REMOTE_CAP)
    end

    if S.queueBytes >= C.BATCH_MIN_FLUSH_BYTES and kickUpload then kickUpload() end
    return true
end

local function shouldFlushQueue(force)
    if S.queueHead > #S.queue or S.queueBytes <= 0 then return false end
    if force then return true end
    if S.queueBytes >= C.BATCH_MIN_FLUSH_BYTES then return true end
    if S.queueBytes >= C.QUEUE_SOFT_BYTES then return true end
    if S.firstQueuedClock > 0 and os.clock() - S.firstQueuedClock >= C.BATCH_MAX_LATENCY then return true end
    return false
end

local function dropPendingForBatchBudget()
    if S.queueBytes > 0 then
        bump(S.dropped, "batch_budget_bytes", S.queueBytes)
        bump(S.dropped, "batch_budget_events")
        S.smartStats.batchBudgetDrops = (S.smartStats.batchBudgetDrops or 0) + 1
    end
    S.queue = {}
    S.queueHead = 1
    S.queueBytes = 0
    S.firstQueuedClock = 0
    S.pendingSend = nil
end

local function compactQueue()
    if S.queueHead <= 256 then return end
    local out = {}
    for i = S.queueHead, #S.queue do out[#out + 1] = S.queue[i] end
    S.queue = out
    S.queueHead = 1
end

local function buildDataBatch()
    if S.pendingSend then return S.pendingSend end
    if S.queueHead > #S.queue then return nil end

    local records, remotes = {}, {}
    local bytes, countR, countM = 0, 0, 0
    local stop = S.queueHead - 1

    for i = S.queueHead, #S.queue do
        local item = S.queue[i]
        if bytes > 0 and bytes + item.bytes > C.BATCH_TARGET_BYTES then break end
        if item.channel == "remote" then
            if countM >= C.MAX_REMOTES_PER_BATCH then break end
            remotes[#remotes + 1] = item.json
            countM = countM + 1
        else
            if countR >= C.MAX_RECORDS_PER_BATCH then break end
            records[#records + 1] = item.json
            countR = countR + 1
        end
        bytes = bytes + item.bytes
        stop = i
    end

    if stop < S.queueHead then return nil end
    if S.batchIndex + 2 > C.MAX_BATCHES then
        -- Keep the final manifest slot. If this guard is ever reached, discard only
        -- the still-pending tail and record its byte count instead of deadlocking.
        dropPendingForBatchBudget()
        S.stopping = true
        task.defer(function() if S.finishCallback then S.finishCallback(true) end end)
        return nil
    end

    S.pendingSend = {
        index = S.batchIndex + 1, start = S.queueHead, stop = stop,
        records = records, remotes = remotes, bytes = bytes,
    }
    return S.pendingSend
end

local function encodeBatchBody(batch, isManifest, manifest)
    local meta = {
        schemaVersion = 3,
        userId = tostring(LP.UserId), username = tostring(LP.Name), capturedAt = S.startIso or iso(),
        gameId = S.runGameId, placeId = S.runPlaceId, placeVersion = S.runPlaceVersion,
        runId = S.runId,
        batchIndex = batch.index,
        batchKind = isManifest and "manifest" or "data",
        payloadBytes = batch.bytes or 0,
        collector = { version = C.VERSION, purpose = C.PURPOSE },
        stats = {
            totalBytes = S.totalBytes, ackBytes = S.ackBytes,
            queueBytes = S.queueBytes, pressure = pressureLevel(),
            inboundListeners = S.inboundCount, valueWatchers = S.valueCount,
        },
    }
    if isManifest then
        meta.batchTotal = batch.index
        meta.manifest = manifest
    end
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, meta)
    if not ok then return nil, "meta_encode_failed" end
    encoded = string.sub(encoded, 1, #encoded - 1)
    local recordJson = isManifest and "" or table.concat(batch.records or {}, ",")
    local remoteJson = isManifest and "" or table.concat(batch.remotes or {}, ",")
    return encoded .. ',"records":[' .. recordJson .. '],"remotes":[' .. remoteJson .. ']}'
end

local function sendDataBatch(batch)
    local since = os.clock() - S.lastSendClock
    if since < C.MIN_SEND_INTERVAL then task.wait(C.MIN_SEND_INTERVAL - since) end
    local body, err = encodeBatchBody(batch, false, nil)
    if not body then return false, err end
    local ok, data, postErr = postRaw(C.BASE .. "/batch", body)
    S.lastSendClock = os.clock()
    return ok, ok and data or postErr
end

local function acknowledgeBatch(batch)
    S.batchIndex = batch.index
    S.queueHead = batch.stop + 1
    S.queueBytes = math.max(0, S.queueBytes - batch.bytes)
    S.ackBytes = S.ackBytes + batch.bytes
    S.pendingSend = nil
    S.lastUploadError = nil
    compactQueue()
    if S.queueHead > #S.queue or S.queueBytes <= 0 then
        S.firstQueuedClock = 0
    else
        S.firstQueuedClock = os.clock()
    end
end

kickUpload = function()
    if S.uploading or os.clock() < S.nextRetryClock then return end
    if not shouldFlushQueue(S.finalizing or S.stopping) then return end
    S.uploading = true
    task.spawn(function()
        while (S.running or S.finalizing) and S.queueHead <= #S.queue do
            local force = S.finalizing or S.stopping
            if not shouldFlushQueue(force) then break end
            local batch = buildDataBatch()
            if not batch then break end
            local ok, err = sendDataBatch(batch)
            if ok then
                acknowledgeBatch(batch)
                S.serverReady = true
            else
                S.serverReady = false
                S.lastUploadError = tostring(err)
                S.nextRetryClock = os.clock() + 5
                break
            end
            if S.running and not S.finalizing and not shouldFlushQueue(false) then break end
            task.wait()
        end
        S.uploading = false
    end)
end

--==============================================================--
-- PASSIVE OUTBOUND REMOTE OBSERVER
--==============================================================--

local OUTBOUND_HOOK_KEY = "__CAFEINA_V3_OUTBOUND_HOOK"

local function installOutboundObserver()
    if not HOOKMETAMETHOD or not GETNAMECALLMETHOD then
        S.coverage.outboundObserver = "unavailable"
        S.outboundHookReady = false
        return false
    end

    local registry = rawget(ENV, OUTBOUND_HOOK_KEY)
    if type(registry) ~= "table" or registry.installed ~= true then
        registry = { installed = false, callback = nil }
        local oldNamecall
        local function wrapper(self, ...)
            local method = GETNAMECALLMETHOD()
            local callback = registry.callback
            if callback and (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and isRemote(self) then
                local args = table.pack(...)
                pcall(callback, self, method, args)
            end
            return oldNamecall(self, ...)
        end

        local wrapped = NEWCLOSURE and NEWCLOSURE(wrapper) or wrapper
        local ok, old = pcall(HOOKMETAMETHOD, game, "__namecall", wrapped)
        if not ok or type(old) ~= "function" then
            S.coverage.outboundObserver = "hook_failed"
            S.outboundHookReady = false
            return false
        end
        oldNamecall = old
        registry.installed = true
        rawset(ENV, OUTBOUND_HOOK_KEY, registry)
    end

    registry.callback = function(remote, method, args)
        if not S.running or S.stopping then return end
        task.defer(function()
            if not S.running or S.stopping then return end

            local remotePath = pathOf(remote)
            registerRemote(remote, "outbound")

            local shapeHash = hashText("remote_out_shape\31" .. remotePath .. "\31" .. method .. "\31" .. packedCanon(args, true))
            local exactHash = hashText("remote_out_value\31" .. remotePath .. "\31" .. method .. "\31" .. packedCanon(args, false))
            local newShape = not S.profileShape[shapeHash]
            local score = importanceScore(remotePath, method, newShape, remote.ClassName)
            local focused = score >= C.FOCUS_SCORE

            S.smartStats.outboundObserved = (S.smartStats.outboundObserved or 0) + 1
            if focused then
                S.smartStats.highInterestOutbound = (S.smartStats.highInterestOutbound or 0) + 1
                S.investigation[remotePath] = os.clock() + C.INVESTIGATION_SECONDS
                if score >= S.focusScore then
                    S.focusRemote = remotePath
                    S.focusScore = score
                end
            end
            if newShape then
                bump(S.coverage, "newOutboundShapes")
                S.investigation[remotePath] = os.clock() + C.INVESTIGATION_SECONDS
                task.defer(function()
                    if S.running and not S.stopping then focusedRemoteContext(remote, shapeHash) end
                end)
            end

            local accepted = enqueue("record", "remote_outbound", {
                kind = "remote_outbound",
                method = method,
                remote = remoteDesc(remote),
                payload = packed(args),
                schema = (newShape or focused) and packedSchema(args) or nil,
                newShape = newShape,
                investigating = focused,
                importance = score,
                player = (newShape or focused) and playerContext(false) or nil,
            }, math.clamp(math.max(82, score), 0, 100), newShape,
                newShape and "shape" or nil, newShape and shapeHash or nil, exactHash,
                focused or newShape)

            if accepted then
                S.smartStats.outboundAccepted = (S.smartStats.outboundAccepted or 0) + 1
            end
            if focused or newShape then
                openCorrelationWindow(remotePath, method, shapeHash, score)
            end
        end)
    end

    S.outboundHookRegistry = registry
    S.outboundHookReady = true
    S.coverage.outboundObserver = "active"
    return true
end

local function disableOutboundObserver()
    local registry = S.outboundHookRegistry
    if type(registry) == "table" then registry.callback = nil end
    S.outboundHookRegistry = nil
    S.outboundHookReady = false
end

--==============================================================--
-- PERSISTENT CACHE FOR UNSENT QUEUE
--==============================================================--

local function cacheFile()
    return tostring(game.GameId) .. "_" .. C.CACHE_SUFFIX
end

local function queueForCache()
    local out = {}
    for i = S.queueHead, #S.queue do
        local item = S.queue[i]
        out[#out + 1] = { channel = item.channel, json = item.json, bytes = item.bytes }
    end
    return out
end

local function strategySnapshot()
    local out = {}
    for category, st in pairs(S.strategy) do
        out[category] = {
            observed = st.observed, accepted = st.accepted, novel = st.novel,
            suppressed = st.suppressed, sampleN = st.sampleN,
        }
    end
    return out
end

local function cacheSnapshot()
    return {
        schemaVersion = 1, gameId = S.runGameId, placeId = S.runPlaceId,
        placeVersion = S.runPlaceVersion, runId = S.runId, startIso = S.startIso,
        batchIndex = S.batchIndex, totalBytes = S.totalBytes, ackBytes = S.ackBytes,
        finalManifest = S.finalManifest,
        queue = queueForCache(),
        deltaLow = S.deltaLow, deltaShape = S.deltaShape, deltaRemote = S.deltaRemote,
        strategy = strategySnapshot(), coverage = S.coverage, frontier = S.frontier,
        suppressed = S.suppressed, dropped = S.dropped, repeatCounts = S.repeatCounts,
    }
end

local function saveCache(snap)
    snap = snap or cacheSnapshot()
    if not WRITEFILE then return false, "writefile_unavailable" end
    local ok, text = pcall(HttpService.JSONEncode, HttpService, snap)
    if not ok then return false, "cache_encode_failed" end
    local wrote, err = pcall(WRITEFILE, cacheFile(), text)
    return wrote, wrote and nil or tostring(err)
end

local function loadCache()
    if not READFILE or not ISFILE then return nil end
    local ok, exists = pcall(ISFILE, cacheFile())
    if not ok or not exists then return nil end
    local readOk, text = pcall(READFILE, cacheFile())
    if not readOk or type(text) ~= "string" then return nil end
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
    if not decodeOk or type(data) ~= "table" or data.gameId ~= game.GameId then return nil end
    return data
end

local function clearCache()
    if DELFILE and ISFILE then
        local ok, exists = pcall(ISFILE, cacheFile())
        if ok and exists then pcall(DELFILE, cacheFile()) end
    end
end

local function restoreCache(data)
    S.runGameId = tonumber(data.gameId) or game.GameId
    S.runPlaceId = tonumber(data.placeId) or game.PlaceId
    S.runPlaceVersion = tonumber(data.placeVersion) or game.PlaceVersion
    S.runId = tostring(data.runId or HttpService:GenerateGUID(false))
    S.startIso = tostring(data.startIso or iso())
    S.startClock = os.clock()
    S.batchIndex = tonumber(data.batchIndex) or 0
    S.finalManifest = type(data.finalManifest) == "table" and data.finalManifest or nil
    S.totalBytes = tonumber(data.totalBytes) or 0
    S.ackBytes = tonumber(data.ackBytes) or 0
    S.queue, S.queueHead, S.queueBytes = {}, 1, 0
    for _, item in ipairs(type(data.queue) == "table" and data.queue or {}) do
        if type(item) == "table" and type(item.json) == "string" then
            local bytes = tonumber(item.bytes) or (#item.json + 1)
            S.queue[#S.queue + 1] = { channel = item.channel == "remote" and "remote" or "record", json = item.json, bytes = bytes }
            S.queueBytes = S.queueBytes + bytes
        end
    end
    S.deltaLow = type(data.deltaLow) == "table" and data.deltaLow or {}
    S.deltaShape = type(data.deltaShape) == "table" and data.deltaShape or {}
    S.deltaRemote = type(data.deltaRemote) == "table" and data.deltaRemote or {}
    S.deltaLowSet, S.deltaShapeSet, S.deltaRemoteSet = arrayToSet(S.deltaLow), arrayToSet(S.deltaShape), arrayToSet(S.deltaRemote)
    S.strategy = {}
    if type(data.strategy) == "table" then
        for category, value in pairs(data.strategy) do
            if type(value) == "table" then
                S.strategy[category] = {
                    observed = tonumber(value.observed) or 0, accepted = tonumber(value.accepted) or 0,
                    novel = tonumber(value.novel) or 0, suppressed = tonumber(value.suppressed) or 0,
                    sampleN = math.clamp(tonumber(value.sampleN) or 1, 1, 16), cursor = 0,
                }
            end
        end
    end
    S.coverage = type(data.coverage) == "table" and data.coverage or {}
    S.frontier = type(data.frontier) == "table" and data.frontier or {}
    S.frontierSet = arrayToSet(S.frontier)
    S.pendingSend = nil
    S.nextRetryClock = 0
    S.uploading = false
    S.suppressed = type(data.suppressed) == "table" and data.suppressed or {}
    S.dropped = type(data.dropped) == "table" and data.dropped or {}
    S.repeatCounts = type(data.repeatCounts) == "table" and data.repeatCounts or {}
    S.repeatKeyCount = 0
    for _ in pairs(S.repeatCounts) do S.repeatKeyCount = S.repeatKeyCount + 1 end
end

--==============================================================--
-- REMOTES / VALUES / RUNTIME WATCHERS
--==============================================================--

local function addFrontier(path)
    path = tostring(path or "")
    if path == "" or S.frontierSet[path] or #S.frontier >= 100 then return end
    S.frontierSet[path] = true
    S.frontier[#S.frontier + 1] = path
end

local function focusedRemoteContext(r, shapeHash)
    local parent = r.Parent
    local siblings = {}
    if parent then
        local ok, children = pcall(function() return parent:GetChildren() end)
        if ok then
            for i = 1, math.min(#children, 24) do
                local x = children[i]
                siblings[#siblings + 1] = { name = x.Name, className = x.ClassName, path = pathOf(x) }
            end
        end
    end
    enqueue("record", "investigation_context", {
        kind = "investigation_context", triggerShape = shapeHash, remote = remoteDesc(r),
        parent = parent and { path = pathOf(parent), attributes = attrs(parent), children = siblings } or nil,
        player = playerContext(true),
    }, 99, true, nil, nil, hashText("investigation\31" .. tostring(shapeHash)), true)
end

local function registerRemote(r, source)
    if not isRemote(r) then return end
    local path = pathOf(r)
    if S.remoteSeen[path] then return end
    S.remoteSeen[path] = true

    local remoteHash = signature("remote", path, { className = r.ClassName, attributes = attrs(r) }, true)
    local isNew = not S.profileRemote[remoteHash]
    if isNew then
        bump(S.coverage, "newRemotes")
        local descriptor = remoteDesc(r)
        descriptor.source = source
        enqueue("remote", "remote_catalog", descriptor, 96, true, "remote", remoteHash, nil, true)
    end
end

local function attachInbound(r)
    if S.inbound[r] or S.inboundCount >= C.MAX_INBOUND then return end
    if not (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then return end
    S.inbound[r] = true
    S.inboundCount = S.inboundCount + 1
    registerRemote(r, "inbound")

    local connection = r.OnClientEvent:Connect(function(...)
        if not S.running or S.stopping then return end
        local args = table.pack(...)
        task.defer(function()
            if not S.running or S.stopping then return end
            local remotePath = pathOf(r)
            local shapeHash = hashText("remote_shape\31" .. remotePath .. "\31" .. packedCanon(args, true))
            local exactHash = hashText("remote_value\31" .. remotePath .. "\31" .. packedCanon(args, false))
            local newShape = not S.profileShape[shapeHash]
            local investigating = (S.investigation[remotePath] or 0) > os.clock()
            if newShape then
                S.investigation[remotePath] = os.clock() + C.INVESTIGATION_SECONDS
                bump(S.coverage, "newShapes")
                task.defer(function()
                    if S.running and not S.stopping then focusedRemoteContext(r, shapeHash) end
                end)
            end
            local priority = newShape and 98 or (investigating and 88 or 78)
            local data = {
                kind = "remote_inbound",
                remote = remoteDesc(r), payload = packed(args),                newShape = newShape, investigating = investigating,
                player = (newShape or investigating) and playerContext(false) or nil,
            }
            enqueue("record", "remote_inbound", data, priority, newShape, newShape and "shape" or nil,
                newShape and shapeHash or nil, exactHash, investigating)
        end)
    end)
    S.conns[#S.conns + 1] = connection
end

local function attachValue(v)
    if S.values[v] or S.valueCount >= C.MAX_VALUES or not v:IsA("ValueBase") then return end
    S.values[v] = { last = canon(v.Value, 0, {}, false) }
    S.valueCount = S.valueCount + 1
    local connection = v.Changed:Connect(function(newValue)
        if not S.running or S.stopping then return end
        local state = S.values[v]
        local nowCanon = canon(newValue, 0, {}, false)
        if state and state.last == nowCanon then return end
        if state then state.last = nowCanon end
        local path = pathOf(v)
        local exact = hashText("value\31" .. path .. "\31" .. nowCanon)
        enqueue("record", "value_changed", {
            kind = "value_changed", object = valueSnap(v), value = ser(newValue),
        }, 72, false, nil, nil, exact, false)
    end)
    S.conns[#S.conns + 1] = connection
end

local toolState = {}
local function watchContainer(container, label)
    if not container then return end
    for _, x in ipairs(container:GetChildren()) do
        if x:IsA("Tool") then toolState[pathOf(x)] = label end
    end
    local added = container.ChildAdded:Connect(function(x)
        if not S.running or S.stopping or not x:IsA("Tool") then return end
        local p = pathOf(x)
        if toolState[p] == label then return end
        toolState[p] = label
        enqueue("record", "tool_transition", {
            kind = "tool_added", container = label, tool = obj(x, label), player = playerContext(false),
        }, 90, false, nil, nil, nil, true)
    end)
    local removed = container.ChildRemoved:Connect(function(x)
        if not S.running or S.stopping or not x:IsA("Tool") then return end
        local p = pathOf(x)
        toolState[p] = "removed:" .. label
        enqueue("record", "tool_transition", {
            kind = "tool_removed", container = label, tool = { name = x.Name, path = p }, player = playerContext(false),
        }, 90, false, nil, nil, nil, true)
    end)
    S.conns[#S.conns + 1] = added
    S.conns[#S.conns + 1] = removed
end

local function runtimeWatchers()
    local ra = ReplicatedStorage.DescendantAdded:Connect(function(x)
        if not S.running or S.stopping then return end
        if isRemote(x) then
            registerRemote(x, "runtime_added")
            if x:IsA("RemoteEvent") or x:IsA("UnreliableRemoteEvent") then attachInbound(x) end
        elseif x:IsA("ValueBase") then
            attachValue(x)
            local h = signature("static", pathOf(x), obj(x, "fingerprint"), false)
            enqueue("record", "runtime_added", { kind = "replicated_added", object = obj(x, "runtime_added") }, 82,
                not S.profileLow[h], "low", h, nil, true)
        elseif x:IsA("Tool") or x:IsA("ProximityPrompt") then
            local h = signature("static", pathOf(x), obj(x, "fingerprint"), false)
            enqueue("record", "runtime_added", { kind = "replicated_added", object = obj(x, "runtime_added") }, 85,
                not S.profileLow[h], "low", h, nil, true)
        end
    end)
    S.conns[#S.conns + 1] = ra

    local wa = Workspace.DescendantAdded:Connect(function(x)
        if not S.running or S.stopping then return end
        if x:IsA("ValueBase") then attachValue(x) end
        if x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then
            local h = signature("static", pathOf(x), obj(x, "fingerprint"), false)
            enqueue("record", "runtime_added", { kind = "workspace_added", object = obj(x, "runtime_added") }, 82,
                not S.profileLow[h], "low", h, nil, true)
        end
    end)
    S.conns[#S.conns + 1] = wa

    local wr = Workspace.DescendantRemoving:Connect(function(x)
        if not S.running or S.stopping then return end
        if x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then
            local exact = hashText("remove\31" .. pathOf(x) .. "\31" .. x.ClassName)
            enqueue("record", "runtime_remove", {
                kind = "workspace_removing", path = pathOf(x), name = x.Name,
                className = x.ClassName, attributes = attrs(x),
            }, 80, false, nil, nil, exact, false)
        end
    end)
    S.conns[#S.conns + 1] = wr

    local pp = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not S.running or S.stopping or (player and player ~= LP) then return end
        enqueue("record", "prompt_triggered", {
            kind = "prompt_triggered", prompt = obj(prompt, "triggered"), player = playerContext(false),
        }, 95, false, nil, nil, nil, true)
    end)
    S.conns[#S.conns + 1] = pp

    local ac = LP.AttributeChanged:Connect(function(name)
        if not S.running or S.stopping then return end
        local value = LP:GetAttribute(name)
        local exact = signature("player_attr", tostring(name), value, false)
        enqueue("record", "player_attribute", {
            kind = "player_attribute_changed", name = tostring(name), value = ser(value),
        }, 82, false, nil, nil, exact, false)
    end)
    S.conns[#S.conns + 1] = ac

    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")

    local ca = LP.CharacterAdded:Connect(function(ch)
        if not S.running or S.stopping then return end
        enqueue("record", "character", { kind = "character_added", path = pathOf(ch) }, 90, false, nil, nil, nil, true)
        watchContainer(ch, "Character")
    end)
    S.conns[#S.conns + 1] = ca
end

local function disconnect()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    table.clear(S.conns)
    S.inbound = setmetatable({}, { __mode = "k" })
    S.values = setmetatable({}, { __mode = "k" })
end

--==============================================================--
-- INCREMENTAL DISCOVERY SCANS
--==============================================================--

local function rotatedChildren(root)
    local list = root:GetChildren()
    local n = #list
    if n <= 1 then return list end

    -- Resume approximate gap/frontier areas first when a previous bounded scan hit its cap.
    local prioritized, rest = {}, {}
    for _, child in ipairs(list) do
        local prefix = pathOf(child)
        local hit = false
        for frontierPath in pairs(S.profileFrontier) do
            if string.sub(frontierPath, 1, #prefix) == prefix then hit = true break end
        end
        if hit then prioritized[#prioritized + 1] = child else rest[#rest + 1] = child end
    end

    local sessions = tonumber(S.profile and S.profile.sessions) or 0
    local function rotate(items)
        if #items <= 1 then return items end
        local offset = (sessions % #items) + 1
        local out = {}
        for i = 0, #items - 1 do out[#out + 1] = items[((offset - 1 + i) % #items) + 1] end
        return out
    end

    local out = rotate(prioritized)
    for _, item in ipairs(rotate(rest)) do out[#out + 1] = item end
    return out
end

local function staticRecord(inst, label)
    if isRemote(inst) then
        registerRemote(inst, label)
        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then attachInbound(inst) end
        return
    end

    local important = inst:IsA("ValueBase") or inst:IsA("Tool") or inst:IsA("ProximityPrompt") or
        inst:IsA("ClickDetector") or inst:IsA("ModuleScript") or inst:IsA("LocalScript") or
        inst:IsA("Script") or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") or
        inst:IsA("Configuration")

    if inst:IsA("ValueBase") then attachValue(inst) end

    if important then
        local a = attrs(inst)
        local fingerprint = obj(inst, "fingerprint", a)
        local h = signature("static", pathOf(inst), fingerprint, false)
        if S.profileLow[h] then
            bump(S.suppressed, "important_instance")
            return
        end
        local priority = (inst:IsA("Tool") or inst:IsA("ProximityPrompt")) and 72 or 58
        enqueue("record", "important_instance", { kind = "important_instance", object = obj(inst, label, a) }, priority,
            true, "low", h, nil, false)
    elseif inst:IsA("Folder") or inst:IsA("Model") or inst:IsA("Accessory") then
        local a = attrs(inst)
        local h = signature("structure", pathOf(inst), {
            className = inst.ClassName, attributes = a, children = #inst:GetChildren(),
        }, false)
        if S.profileLow[h] then
            bump(S.suppressed, "structure")
            return
        end
        enqueue("record", "structure", {
            kind = "structure_path", source = label, path = pathOf(inst), className = inst.ClassName, attributes = a,
        }, 30, true, "low", h, nil, false)
    end
end

local function scanActive(epoch)
    return S.running and not S.stopping and S.runEpoch == epoch
end

local function scanTree(root, label, cap, coverageKey, epoch)
    -- Bounded DFS: unlike GetDescendants()/unbounded BFS this never keeps more
    -- than the remaining scan budget worth of Instance references in memory.
    local roots = rotatedChildren(root)
    local stack = {}
    local rootLimit = math.min(#roots, cap)
    for i = rootLimit, 1, -1 do stack[#stack + 1] = roots[i] end

    local visited, sliceCount, sliceStart = 0, 0, os.clock()
    while #stack > 0 and visited < cap and scanActive(epoch) do
        local inst = stack[#stack]
        stack[#stack] = nil
        visited = visited + 1
        staticRecord(inst, label)

        local ok, children = pcall(function() return inst:GetChildren() end)
        if ok and #children > 0 then
            local room = math.max(0, cap - visited - #stack)
            local take = math.min(#children, room)
            for i = take, 1, -1 do stack[#stack + 1] = children[i] end
        end

        sliceCount = sliceCount + 1
        if sliceCount >= C.SCAN_SLICE_ITEMS or os.clock() - sliceStart >= C.SCAN_SLICE_MS then
            task.wait()
            sliceCount = 0
            sliceStart = os.clock()
        end
    end

    S.coverage[coverageKey] = visited
    S.coverage[coverageKey .. "CapHit"] = (#stack > 0) or (#roots > rootLimit)
    if #stack > 0 then
        S.coverage[coverageKey .. "RemainingApprox"] = #stack
        local first = math.max(1, #stack - 39)
        for i = #stack, first, -1 do addFrontier(pathOf(stack[i])) end
    end
end

local function scanNearby(epoch)
    if not scanActive(epoch) then return end
    local ch = LP.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { ch }
    params.MaxParts = C.MAX_NEARBY

    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInRadius(root.Position, C.NEARBY_RADIUS, params)
    end)
    if not ok then return end

    S.coverage.nearbyParts = #parts
    local sliceStart = os.clock()
    for i, part in ipairs(parts) do
        if not scanActive(epoch) then break end
        local h = signature("nearby", pathOf(part), {
            className = part.ClassName, size = part.Size, material = part.Material,
            anchored = part.Anchored, canCollide = part.CanCollide, transparency = part.Transparency,
        }, false)
        enqueue("record", "nearby", { kind = "nearby_part", object = obj(part, "nearby") }, 34,
            not S.profileLow[h], "low", h, nil, false)
        if i % 50 == 0 or os.clock() - sliceStart >= C.SCAN_SLICE_MS then task.wait(); sliceStart = os.clock() end
    end
end

local function scanTags(epoch)
    if not scanActive(epoch) then return end
    local ok, tags = pcall(function() return CollectionService:GetAllTags() end)
    if not ok then return end
    table.sort(tags)
    S.coverage.tags = #tags
    for i, tag in ipairs(tags) do
        if not scanActive(epoch) then break end
        local list = CollectionService:GetTagged(tag)
        local samples = {}
        for j = 1, math.min(#list, 16) do samples[j] = pathOf(list[j]) end
        local h = signature("tag", tostring(tag), { count = #list, samples = samples }, false)
        if not S.profileLow[h] then
            enqueue("record", "tag", { kind = "tag_entry", tag = tag, count = #list, samples = samples }, 48,
                true, "low", h, nil, false)
        else
            bump(S.suppressed, "tag")
        end
        if i % 20 == 0 then task.wait() end
    end
end

local function scanPlayer(epoch)
    if not scanActive(epoch) then return end
    enqueue("record", "player_snapshot", {
        kind = "player_snapshot", player = playerContext(true), attributes = attrs(LP),
    }, 65, false, nil, nil, signature("player_snapshot", "initial", playerContext(false), false), false)

    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, x in ipairs(backpack:GetChildren()) do
            if x:IsA("Tool") then
                local h = signature("tool_static", pathOf(x), obj(x, "fingerprint"), false)
                enqueue("record", "inventory", { kind = "inventory_tool", object = obj(x, "Backpack") }, 62,
                    not S.profileLow[h], "low", h, nil, false)
            end
        end
    end

    local leaderstats = LP:FindFirstChild("leaderstats")
    if leaderstats then
        for _, x in ipairs(leaderstats:GetChildren()) do
            if x:IsA("ValueBase") then
                attachValue(x)
                local h = signature("leaderstat", pathOf(x), valueSnap(x), false)
                enqueue("record", "leaderstat", { kind = "leaderstat", object = valueSnap(x) }, 68,
                    not S.profileLow[h], "low", h, nil, false)
            end
        end
    end
end

local function scanGui(epoch)
    if not scanActive(epoch) then return end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local roots = pg:GetChildren()
    local stack = {}
    local rootLimit = math.min(#roots, C.GUI_NODE_CAP)
    for i = rootLimit, 1, -1 do stack[#stack + 1] = roots[i] end

    local visited, captured, sliceStart = 0, 0, os.clock()
    while #stack > 0 and visited < C.GUI_NODE_CAP and captured < C.MAX_GUI and scanActive(epoch) do
        local x = stack[#stack]
        stack[#stack] = nil
        visited = visited + 1
        local ok, children = pcall(function() return x:GetChildren() end)
        if ok and #children > 0 then
            local room = math.max(0, C.GUI_NODE_CAP - visited - #stack)
            local take = math.min(#children, room)
            for i = take, 1, -1 do stack[#stack + 1] = children[i] end
        end

        if x:IsA("ScreenGui") then
            local h = signature("gui_screen", pathOf(x), {
                className = x.ClassName, enabled = x.Enabled, displayOrder = x.DisplayOrder, attributes = attrs(x),
            }, false)
            if not S.profileLow[h] then
                enqueue("record", "gui", {
                    kind = "gui_screen", path = pathOf(x), name = x.Name,
                    enabled = x.Enabled, displayOrder = x.DisplayOrder, attributes = attrs(x),
                }, 45, true, "low", h, nil, false)
                captured = captured + 1
            end
        elseif x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
            local h = signature("gui_text", pathOf(x), {
                className = x.ClassName, text = x.Text, visible = x.Visible, position = x.Position, size = x.Size,
            }, false)
            if not S.profileLow[h] then
                enqueue("record", "gui", { kind = "gui_text", object = obj(x, "PlayerGui") }, 46,
                    true, "low", h, nil, false)
                captured = captured + 1
            end
        end
        if visited % 60 == 0 or os.clock() - sliceStart >= C.SCAN_SLICE_MS then task.wait(); sliceStart = os.clock() end
    end
    S.coverage.guiVisited = visited
    S.coverage.guiCaptured = captured
    S.coverage.guiCapHit = (#stack > 0) or (#roots > rootLimit)
    if #stack > 0 then
        local first = math.max(1, #stack - 19)
        for i = #stack, first, -1 do addFrontier(pathOf(stack[i])) end
    end
end

local function startScans(epoch)
    task.spawn(function()
        scanTree(ReplicatedStorage, "ReplicatedStorage", C.RS_NODE_CAP, "replicatedVisited", epoch)
        if scanActive(epoch) then scanTree(Workspace, "Workspace", C.WS_NODE_CAP, "workspaceVisited", epoch) end
        if scanActive(epoch) then scanNearby(epoch) end
        if scanActive(epoch) then scanTags(epoch) end
        if scanActive(epoch) then scanPlayer(epoch) end
        if scanActive(epoch) then scanGui(epoch) end
        if S.runEpoch == epoch then S.coverage.staticComplete = scanActive(epoch) end
    end)
end

--==============================================================--
-- TRAJECTORY: CHANGE-BASED, NOT EVERY FRAME
--==============================================================--

local function maybeTrajectory()
    if not S.running or S.stopping then return end
    local now = os.clock()
    if now - S.lastTrajectoryAt < C.TRAJECTORY_MIN_INTERVAL then return end

    local ch = LP.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    local pos = root.Position
    local state = tostring(hum:GetState())
    local moved = not S.lastTrajectoryPos or (pos - S.lastTrajectoryPos).Magnitude >= C.TRAJECTORY_MOVE_STUDS
    local changedState = state ~= S.lastTrajectoryState
    local idleDue = now - S.lastTrajectoryAt >= C.TRAJECTORY_IDLE_INTERVAL
    if not moved and not changedState and not idleDue then return end

    S.lastTrajectoryAt = now
    S.lastTrajectoryPos = pos
    S.lastTrajectoryState = state
    enqueue("record", "trajectory", {
        kind = "trajectory", player = playerContext(false),
        velocity = ser(root.AssemblyLinearVelocity), state = state,
    }, changedState and 58 or 26, changedState, nil, nil, nil, false)
end

--==============================================================--
-- FINALIZATION
--==============================================================--

local function repeatSummary()
    local rows = {}
    for hash, count in pairs(S.repeatCounts) do rows[#rows + 1] = { sig = hash, repeats = count } end
    table.sort(rows, function(a, b) return a.repeats > b.repeats end)
    local out = {}
    for i = 1, math.min(#rows, 500) do out[i] = rows[i] end
    return out
end

local function manifestTable()
    return {
        version = C.VERSION, purpose = C.PURPOSE,
        startedAt = S.startIso, finishedAt = iso(),
        totalDataBytes = S.totalBytes, acknowledgedDataBytes = S.ackBytes,
        dataBatches = S.batchIndex,
        suppressed = S.suppressed, dropped = S.dropped, repeatSummary = repeatSummary(),
        profileDelta = {
            knownLowValueHashes = S.deltaLow,
            knownShapeHashes = S.deltaShape,
            knownRemoteHashes = S.deltaRemote,
            frontier = S.frontier,
        },
        strategyDelta = strategySnapshot(),
        coverage = S.coverage,
    }
end

local function sendManifest()
    if S.batchIndex + 1 > C.MAX_BATCHES then return false, "max_batches_reached" end
    if not S.finalManifest then S.finalManifest = manifestTable() end
    local batch = { index = S.batchIndex + 1, bytes = 0, records = {}, remotes = {} }
    local body, err = encodeBatchBody(batch, true, S.finalManifest)
    if not body then return false, err end
    local since = os.clock() - S.lastSendClock
    if since < C.MIN_SEND_INTERVAL then task.wait(C.MIN_SEND_INTERVAL - since) end
    local ok, data, postErr = postRaw(C.BASE .. "/batch", body)
    S.lastSendClock = os.clock()
    if ok then S.batchIndex = batch.index end
    return ok, ok and data or postErr
end

local function drainQueue(timeoutSeconds)
    local deadline = os.clock() + (timeoutSeconds or 120)
    while S.queueHead <= #S.queue and os.clock() < deadline do
        if not S.uploading and os.clock() >= S.nextRetryClock then kickUpload() end
        task.wait(0.15)
    end
    return S.queueHead > #S.queue
end

local function resetRunState()
    S.running = false
    S.stopping = false
    S.finalizing = false
    S.uploading = false
    S.queue, S.queueHead, S.queueBytes = {}, 1, 0
    S.totalBytes, S.ackBytes, S.batchIndex = 0, 0, 0
    S.pendingSend = nil
    S.finalManifest = nil
    S.manifestConfirmed = false
    S.sessionExact, S.remoteSeen = {}, {}
    S.sessionExactCount = 0
    S.deltaLow, S.deltaShape, S.deltaRemote = {}, {}, {}
    S.deltaLowSet, S.deltaShapeSet, S.deltaRemoteSet = {}, {}, {}
    S.strategy, S.suppressed, S.dropped, S.repeatCounts, S.coverage, S.investigation, S.recentRefs = {}, {}, {}, {}, {}, {}, {}
    S.frontier, S.frontierSet = {}, {}
    S.repeatKeyCount = 0
    S.inboundCount, S.valueCount = 0, 0
    S.lastTrajectoryAt, S.lastTrajectoryPos, S.lastTrajectoryState = 0, nil, nil
end

local uiRefresh
local mainButton

local function finalize(auto)
    if S.finalizing then return end
    if not S.running and not S.cached and S.queueHead > #S.queue then return end

    S.finalizing = true
    S.stopping = true
    S.running = false
    S.runEpoch = S.runEpoch + 1
    disconnect()
    if mainButton then mainButton.Text = "ENVIANDO" end

    task.spawn(function()
        local drained = drainQueue(120)
        if not drained then
            S.cached = cacheSnapshot()
            saveCache(S.cached)
            S.finalizing = false
            if mainButton then mainButton.Text = "REENVIAR" end
            return
        end

        S.ackBytes = S.totalBytes
        local ok = false
        local err
        for attempt = 1, C.RETRIES do
            ok, err = sendManifest()
            if ok then break end
            task.wait(C.RETRY_BASE * attempt)
        end

        if ok then
            S.manifestConfirmed = true
            loadRemoteProfile(true)
            if uiRefresh then uiRefresh() end
            task.wait(0.6)
            clearCache()
            S.cached = nil
            if mainButton then mainButton.Text = "INICIAR" end
            resetRunState()
        else
            S.cached = cacheSnapshot()
            saveCache(S.cached)
            S.finalizing = false
            if mainButton then mainButton.Text = "REENVIAR" end
        end
        if uiRefresh then uiRefresh() end
    end)
end
S.finishCallback = finalize

local function begin()
    if S.running or S.finalizing or not S.preflightReady then return end
    if not S.serverReady then return end

    resetRunState()
    S.runId = HttpService:GenerateGUID(false)
    S.runPlaceId = game.PlaceId
    S.runGameId = game.GameId
    S.runPlaceVersion = game.PlaceVersion
    S.startClock = os.clock()
    S.startIso = iso()
    S.runEpoch = S.runEpoch + 1
    local epoch = S.runEpoch
    S.running = true

    runtimeWatchers()
    enqueue("record", "session", {
        kind = "session_started", version = C.VERSION, purpose = C.PURPOSE,
        gameId = game.GameId, placeId = game.PlaceId, placeVersion = game.PlaceVersion,
        profileRevision = tonumber(S.profile and S.profile.revision) or 0,
        profileSessions = tonumber(S.profile and S.profile.sessions) or 0,
        capabilities = { request = REQUEST ~= nil, writefile = WRITEFILE ~= nil },
        player = playerContext(true),
    }, 100, true, nil, nil, nil, true)

    startScans(epoch)
    if mainButton then mainButton.Text = "ENCERRAR + ENVIAR" end
end

local function retryCached()
    if S.finalizing or not S.cached then return end
    restoreCache(S.cached)
    S.finalizing = true
    S.stopping = true
    S.running = false
    if mainButton then mainButton.Text = "ENVIANDO" end
    task.spawn(function()
        local drained = drainQueue(120)
        if not drained then
            S.cached = cacheSnapshot()
            saveCache(S.cached)
            S.finalizing = false
            if mainButton then mainButton.Text = "REENVIAR" end
            return
        end
        S.ackBytes = S.totalBytes
        local ok = false
        for attempt = 1, C.RETRIES do
            ok = sendManifest()
            if ok then break end
            task.wait(C.RETRY_BASE * attempt)
        end
        if ok then
            S.manifestConfirmed = true
            loadRemoteProfile(true)
            if uiRefresh then uiRefresh() end
            task.wait(0.6)
            clearCache(); S.cached = nil; resetRunState()
            if mainButton then mainButton.Text = "INICIAR" end
        else
            S.cached = cacheSnapshot(); saveCache(S.cached); S.finalizing = false
            if mainButton then mainButton.Text = "REENVIAR" end
        end
    end)
end

--==============================================================--
-- COMPACT MOBILE UI
--==============================================================--

local GUI_NAME = "CafeinaUniversalGameTraceV30"
local parent = CoreGui
pcall(function() if type(gethui) == "function" then parent = gethui() end end)
pcall(function() local old = parent:FindFirstChild(GUI_NAME); if old then old:Destroy() end end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 9999
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
if not pcall(function() gui.Parent = parent end) then gui.Parent = LP:WaitForChild("PlayerGui") end

local safeRoot = Instance.new("Frame")
safeRoot.Name = "SafeRoot"
safeRoot.BackgroundTransparency = 1
safeRoot.BorderSizePixel = 0
safeRoot.Size = UDim2.fromScale(1, 1)
safeRoot.Position = UDim2.fromOffset(0, 0)
safeRoot.Parent = gui

local frame = Instance.new("Frame")
frame.Name = "Compact"
frame.Size = UDim2.fromOffset(226, 104)
frame.Position = UDim2.new(0.5, -113, 0.18, 0)
frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = safeRoot

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(52, 52, 60)
stroke.Thickness = 1
stroke.Parent = frame

local mbLabel = Instance.new("TextLabel")
mbLabel.BackgroundTransparency = 1
mbLabel.Position = UDim2.fromOffset(10, 7)
mbLabel.Size = UDim2.fromOffset(145, 20)
mbLabel.Font = Enum.Font.GothamBold
mbLabel.TextSize = 11
mbLabel.TextColor3 = Color3.fromRGB(238, 238, 242)
mbLabel.TextXAlignment = Enum.TextXAlignment.Left
mbLabel.Text = "0.0 / 150 MB"
mbLabel.Parent = frame

local pctLabel = Instance.new("TextLabel")
pctLabel.BackgroundTransparency = 1
pctLabel.Position = UDim2.new(1, -60, 0, 7)
pctLabel.Size = UDim2.fromOffset(50, 20)
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextSize = 11
pctLabel.TextColor3 = Color3.fromRGB(190, 190, 198)
pctLabel.TextXAlignment = Enum.TextXAlignment.Right
pctLabel.Text = "0%"
pctLabel.Parent = frame

local bar = Instance.new("Frame")
bar.Position = UDim2.fromOffset(10, 32)
bar.Size = UDim2.new(1, -20, 0, 8)
bar.BackgroundColor3 = Color3.fromRGB(29, 29, 34)
bar.BorderSizePixel = 0
bar.Parent = frame
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(220, 220, 226)
fill.BorderSizePixel = 0
fill.Parent = bar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

mainButton = Instance.new("TextButton")
mainButton.Position = UDim2.fromOffset(10, 50)
mainButton.Size = UDim2.new(1, -20, 0, 44)
mainButton.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
mainButton.BorderSizePixel = 0
mainButton.Font = Enum.Font.GothamBold
mainButton.TextSize = 11
mainButton.TextColor3 = Color3.fromRGB(245, 245, 247)
mainButton.Text = REQUEST and "CONECTANDO" or "SEM HTTP"
mainButton.AutoButtonColor = true
mainButton.Parent = frame
local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = mainButton

uiRefresh = function()
    local total = S.totalBytes
    local ack = math.min(S.ackBytes, total)
    local pct = total > 0 and math.floor((ack / total) * 100 + 0.5) or 0
    if S.finalizing and not S.manifestConfirmed then pct = math.min(math.max(pct, 99), 99) end
    mbLabel.Text = string.format("%.1f / 150 MB", total / MB)
    pctLabel.Text = tostring(math.clamp(pct, 0, 100)) .. "%"
    fill.Size = UDim2.fromScale(math.clamp(pct / 100, 0, 1), 1)
end

task.spawn(function()
    while gui.Parent do
        uiRefresh()
        if S.running then maybeTrajectory() end
        if (S.running or S.finalizing) and not S.uploading and S.queueHead <= #S.queue and os.clock() >= S.nextRetryClock then
            kickUpload()
        end
        task.wait(0.25)
    end
end)

local uiConns = {}
local function uiConnect(signal, callback)
    local connection = signal:Connect(callback)
    uiConns[#uiConns + 1] = connection
    return connection
end
local function disconnectUi()
    for _, connection in ipairs(uiConns) do pcall(function() connection:Disconnect() end) end
    table.clear(uiConns)
end

-- Tiny frame-time EWMA only; no expensive work runs per frame.
local heartbeat = uiConnect(RunService.Heartbeat, function(dt)
    S.frameDt = S.frameDt * 0.94 + dt * 0.06
end)

-- Drag only from the top 46 px so the action button remains reliable on touch.
local dragging, dragInput, dragMotion, dragStart, startPos = false, nil, nil, nil, nil
local function clampFrame()
    local rootPos = safeRoot.AbsolutePosition
    local rootSize = safeRoot.AbsoluteSize
    local size = frame.AbsoluteSize
    if rootSize.X <= 0 or rootSize.Y <= 0 then return end
    local minX, minY = rootPos.X + 4, rootPos.Y + 4
    local maxX = math.max(minX, rootPos.X + rootSize.X - size.X - 4)
    local maxY = math.max(minY, rootPos.Y + rootSize.Y - size.Y - 4)
    local x = math.clamp(frame.AbsolutePosition.X, minX, maxX)
    local y = math.clamp(frame.AbsolutePosition.Y, minY, maxY)
    frame.Position = UDim2.fromOffset(x - rootPos.X, y - rootPos.Y)
end

uiConnect(frame.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local localY = input.Position.Y - frame.AbsolutePosition.Y
    if localY > 46 then return end
    dragging = true
    dragInput = input
    dragMotion = input.UserInputType == Enum.UserInputType.Touch and input or nil
    dragStart = input.Position
    startPos = frame.Position
end)

uiConnect(frame.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then dragMotion = input end
end)

uiConnect(UserInputService.InputChanged, function(input)
    if not dragging or not dragStart or not startPos then return end
    if input ~= dragMotion and input ~= dragInput then return end
    local d = input.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    clampFrame()
end)

uiConnect(UserInputService.InputEnded, function(input)
    if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = false
        dragInput, dragMotion = nil, nil
    end
end)

pcall(function()
    local camera = Workspace.CurrentCamera
    if camera then uiConnect(camera:GetPropertyChangedSignal("ViewportSize"), function() task.defer(clampFrame) end) end
end)
uiConnect(safeRoot:GetPropertyChangedSignal("AbsoluteSize"), function() task.defer(clampFrame) end)
uiConnect(safeRoot:GetPropertyChangedSignal("AbsolutePosition"), function() task.defer(clampFrame) end)
task.defer(clampFrame)

uiConnect(mainButton.Activated, function()
    if S.finalizing then return end
    if S.cached then retryCached()
    elseif S.running then finalize(false)
    elseif not S.preflightReady then return
    elseif not S.serverReady then
        mainButton.Text = "RETESTAR"
        task.spawn(function()
            local ok, health = getJson(C.HEALTH)
            S.serverReady = ok and type(health) == "table" and health.ok == true and health.githubMirrorConfigured == true
            mainButton.Text = S.serverReady and "INICIAR" or "RETESTAR"
        end)
    else begin() end
end)

--==============================================================--
-- PREFLIGHT
--==============================================================--

task.spawn(function()
    if not REQUEST then
        S.preflightReady = true
        S.serverReady = false
        return
    end

    local ok, health = getJson(C.HEALTH)
    S.serverReady = ok and type(health) == "table" and health.ok == true and
        health.githubMirrorConfigured == true and tonumber(health.hardSessionBytes) == C.HARD_BYTES

    loadRemoteProfile(false)
    S.cached = loadCache()
    S.preflightReady = true

    if S.cached then
        restoreCache(S.cached)
        mainButton.Text = "REENVIAR"
    else
        mainButton.Text = S.serverReady and "INICIAR" or "RETESTAR"
    end
end)

ENV.__CAFEINA_UNIVERSAL_TRACE_V30 = {
    Gui = gui,
    State = S,
    Config = C,
    Mark = function(label)
        if S.running and not S.stopping then
            enqueue("record", "external_marker", {
                kind = "external_marker", label = tostring(label or "marker"), player = playerContext(false),
            }, 100, true, nil, nil, nil, true)
        end
    end,
    Finish = function() finalize(false) end,
    Stop = function()
        S.stopping = true; S.running = false; S.runEpoch = S.runEpoch + 1
        disconnect()
        disconnectUi()
        pcall(function() gui:Destroy() end)
    end,
}

gui.Destroying:Connect(function()
    if S.running and not S.finalizing then saveCache() end
    S.stopping = true
    S.running = false
    S.runEpoch = S.runEpoch + 1
    disconnect()
    disconnectUi()
end)

print("[CAFEINA] UNIVERSAL GAME TRACE V3.0 carregado • adaptativo • memória por GameId • streaming protegido")