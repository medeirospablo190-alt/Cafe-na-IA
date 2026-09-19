--==============================================================--
-- CAFEINA • UNIVERSAL GAME TRACE V3.2.7
-- Adaptive, bidirectional, persistent-per-game collector.
--
-- DESIGN RULES
--  1) Observe inbound AND client->server remote calls without changing their arguments.
--  2) Never invent unknown remote calls; active tests may replay only previously observed low-impact FireServer calls after generic risk gates.
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
-- 16) The UI stays compact and can minimize to a draggable investigation-status icon.
-- 17) A bounded circular context buffer is kept in memory only to build action bundles.
-- 18) Semantic novelty is learned independently from raw argument shapes.
-- 19) Opaque buffers are fingerprinted generically without game-specific decoders.
-- 20) New/high-impact behavior opens bounded delayed deep-state probes.
-- 21) Correlation confidence is evidence-based and never treated as proven causality.
-- 22) Compact behavior transitions are learned as a universal session graph.
-- 23) Runtime/static fingerprints normalize dynamic character/id path segments before novelty decisions.
-- 24) Investigation state is explicit: GREEN free, YELLOW warning, RED controlled test, BLUE consequence observation.
-- 25) RED/BLUE quarantine player input without changing Humanoid/Camera state; the CAFEINA icon remains an emergency escape.
-- 26) Controlled active tests are bounded, one-at-a-time, and skipped when side-effect evidence or pressure makes replay unsafe.
-- 27) Each investigation emits one action bundle with prelude, before/mid/after state and a compact diff.
-- 28) Upload retries preserve the exact in-flight body so a lost ACK cannot rebuild a conflicting batch.
-- 29) Upload/cache failures are classified and surfaced by a compact on-screen diagnostic panel.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local MB = 1024 * 1024
local C = {
    VERSION = "CAFEINA_UNIVERSAL_GAME_TRACE_V3_2_7",
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
    MAX_BATCHES = 260,

    MAX_STRING = 1400,
    MAX_TABLE = 64,
    MAX_DEPTH = 5,
    MAX_ARGS = 28,

    BUFFER_SAMPLE_BYTES = 24,
    BUFFER_EDGE_BYTES = 8,
    SEMANTIC_MAX_STRING = 96,
    SEMANTIC_TABLE_FIELDS = 16,
    MAX_SEMANTIC_PER_REMOTE = 96,

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
    CORRELATION_EVIDENCE_CAP = 1200,
    CORRELATION_IMPACT_MIN_SUPPORT = 3,
    CORRELATION_IMPACT_MIN_TRUSTED_SUPPORT = 2.0,
    CORRELATION_IMPACT_MIN_DISTINCT = 2,
    CORRELATION_IMPACT_MIN_CONFIDENCE = 35,
    CORRELATION_CONFIRM_MIN_TRUSTED_SUPPORT = 2.0,
    CORRELATION_CONFIRM_MIN_DISTINCT = 2,
    CORRELATION_CONFIRM_MIN_CONFIDENCE = 25,
    CORRELATION_CONFIRM_MAX_BASELINE = 1,
    BEHAVIOR_TRANSITION_CAP = 800,
    DEEP_PROBE_MAX = 36,
    DEEP_PROBE_COOLDOWN = 1.25,
    DEEP_PROBE_DELAYS = { 0.20, 1.25, 3.00 },
    RECENT_VALUE_CAP = 32,
    RECENT_VALUE_SNAPSHOT_CAP = 16,
    RECENT_VALUE_BACKGROUND_CAP = 4,
    RECENT_VALUE_NOISY_AFTER = 4,
    RECENT_GUI_CAP = 32,
    TIMELINE_SECONDS = 7.0,
    TIMELINE_CAP = 180,
    INTERACTION_CONTEXT_SECONDS = 0.5,

    INVESTIGATOR_QUEUE_CAP = 10,
    INVESTIGATOR_MAX_PER_SESSION = 18,
    INVESTIGATOR_YELLOW_SECONDS = 1.6,
    INVESTIGATOR_YELLOW_MAX = 4.0,
    INVESTIGATOR_RED_SETTLE = 0.16,
    INVESTIGATOR_BLUE_MIN = 2.4,
    INVESTIGATOR_BLUE_MAX = 5.5,
    INVESTIGATOR_BLUE_IDLE = 0.9,
    INVESTIGATOR_COOLDOWN = 8.0,
    INVESTIGATOR_DIAGNOSTIC_CAP = 40,
    MENU_HEALTH_DIAGNOSTIC_CAP = 160,
    MENU_HEALTH_CHECK_INTERVAL = 1.5,
    MENU_HEALTH_YELLOW_STUCK = 5.5,
    MENU_HEALTH_RED_STUCK = 4.0,
    MENU_HEALTH_BLUE_STUCK = 7.0,
    MENU_HEALTH_QUEUE_STUCK = 2.0,
    UPLOAD_DIAGNOSTIC_CAP = 20,
    UPLOAD_ERROR_TEXT_MAX = 900,
    ACTIVE_TEST_MAX_IMPORTANCE = 86,
    ACTIVE_TEST_MAX_ARGS = 12,
    INPUT_LOCK_PRIORITY = 10000,
    INVESTIGATION_KNOWLEDGE_CAP = 300,
    PROTOCOL_MODEL_CAP = 320,
    ARGUMENT_FIELD_CAP = 900,

    RUNTIME_BURST_FIRST = 3,
    RUNTIME_BURST_EVERY = 16,
    FOCUS_SCORE = 72,
    MIN_SEND_INTERVAL = 1.25,
    RETRIES = 4,
    RETRY_BASE = 0.8,

    DELTA_LOW_CAP = 6000,
    DELTA_SHAPE_CAP = 4000,
    DELTA_SEMANTIC_CAP = 4000,
    DELTA_REMOTE_CAP = 1500,
    DELTA_INVESTIGATION_CAP = 300,
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

local function bufferLength(v)
    if typeof(v) ~= "buffer" or type(buffer) ~= "table" or type(buffer.len) ~= "function" then return nil end
    local ok, n = pcall(buffer.len, v)
    if not ok or type(n) ~= "number" or n < 0 then return nil end
    return math.floor(n)
end

local function bufferByte(v, index)
    if type(buffer) ~= "table" or type(buffer.readu8) ~= "function" then return nil end
    local ok, b = pcall(buffer.readu8, v, index)
    if not ok or type(b) ~= "number" then return nil end
    return math.clamp(math.floor(b), 0, 255)
end

local function bufferLengthBucket(n)
    n = tonumber(n)
    if not n then return "unknown" end
    if n <= 8 then return "0-8" end
    if n <= 16 then return "9-16" end
    if n <= 32 then return "17-32" end
    if n <= 64 then return "33-64" end
    if n <= 128 then return "65-128" end
    if n <= 256 then return "129-256" end
    if n <= 512 then return "257-512" end
    if n <= 1024 then return "513-1024" end
    return "1025+"
end

local function bufferFingerprint(v)
    local len = bufferLength(v)
    if not len then return { type = "buffer", readable = false, repr = tostring(v) } end
    local sampleTarget = math.min(len, C.BUFFER_SAMPLE_BYTES)
    local h1, h2, sampled, zeros = 216613, 131071, 0, 0
    local sampleHex, byteFreq = {}, {}
    for i = 1, sampleTarget do
        local index = sampleTarget <= 1 and 0 or math.floor(((i - 1) * math.max(0, len - 1)) / (sampleTarget - 1))
        local b = bufferByte(v, index)
        if b ~= nil then
            sampled = sampled + 1
            if b == 0 then zeros = zeros + 1 end
            h1 = (h1 * 131 + b + (index % 251)) % 16777213
            h2 = (h2 * 137 + b + (index % 241)) % 16777199
            sampleHex[#sampleHex + 1] = string.format("%02x", b)
            byteFreq[b] = (byteFreq[b] or 0) + 1
        end
    end
    local distinct, entropy = 0, 0
    if sampled > 0 then
        for _, freq in pairs(byteFreq) do
            distinct = distinct + 1
            local p = freq / sampled
            entropy = entropy - (p * (math.log(p) / math.log(2)))
        end
    end
    local maxEntropy = sampled > 1 and (math.log(math.min(256, sampled)) / math.log(2)) or 0
    local edge = math.min(len, C.BUFFER_EDGE_BYTES)
    local head, tail = {}, {}
    for i = 0, edge - 1 do
        local b = bufferByte(v, i)
        if b ~= nil then head[#head + 1] = string.format("%02x", b) end
    end
    for i = math.max(0, len - edge), len - 1 do
        local b = bufferByte(v, i)
        if b ~= nil then tail[#tail + 1] = string.format("%02x", b) end
    end
    return {
        type = "buffer", length = len, lengthBucket = bufferLengthBucket(len),
        sampleHash = string.format("%06x%06x", h1, h2), sampledBytes = sampled,
        sampleHex = table.concat(sampleHex), headHex = table.concat(head), tailHex = table.concat(tail),
        zeroRatio = sampled > 0 and math.floor((zeros / sampled) * 1000 + 0.5) / 1000 or 0,
        distinctRatio = sampled > 0 and math.floor((distinct / sampled) * 1000 + 0.5) / 1000 or 0,
        sampleEntropy = math.floor(entropy * 1000 + 0.5) / 1000,
        normalizedEntropy = maxEntropy > 0 and math.floor((entropy / maxEntropy) * 1000 + 0.5) / 1000 or 0,
    }
end

local function bufferShallow(v)
    local len = bufferLength(v)
    if len then return { type = "buffer", length = len, lengthBucket = bufferLengthBucket(len) } end
    return { type = "buffer", readable = false, repr = tostring(v) }
end

local function bufferSemanticToken(v)
    local len = bufferLength(v)
    if not len then return "BUF:unknown" end
    local b0 = bufferByte(v, 0) or 0
    local b1 = len > 1 and (bufferByte(v, 1) or 0) or 0
    return string.format("BUF:%s:%02x%02x", bufferLengthBucket(len), b0, b1)
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
    if t == "buffer" then return bufferShallow(v) end
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
    if t == "buffer" then
        if shapeOnly then return "BUF" end
        local info = bufferFingerprint(v)
        return "BUF:" .. tostring(info.length or "?") .. ":" .. tostring(info.sampleHash or info.repr or "?")
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

local function semanticNumber(v)
    if v ~= v then return "N:nan" end
    if v == math.huge then return "N:inf" end
    if v == -math.huge then return "N:-inf" end
    if v == 0 then return "N:0" end
    if v == math.floor(v) and math.abs(v) <= 32 then return "N:i:" .. tostring(v) end
    local a = math.abs(v)
    local bucket
    if a < 1 then bucket = "lt1"
    elseif a < 10 then bucket = "1-9"
    elseif a < 100 then bucket = "10-99"
    elseif a < 1000 then bucket = "100-999"
    elseif a < 10000 then bucket = "1k-9k"
    elseif a < 1000000 then bucket = "10k-999k"
    else bucket = "1m+"
    end
    return "N:" .. (v < 0 and "-" or "+") .. bucket
end

local function semanticString(v)
    local text = tostring(v)
    if #text <= C.SEMANTIC_MAX_STRING then return "S:" .. text end
    return "S:" .. string.sub(text, 1, math.floor(C.SEMANTIC_MAX_STRING / 2)) .. "#len=" .. tostring(#text)
end

local function semanticCanon(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 3 then return "D" end
    local t = typeof(v)
    if v == nil then return "Z" end
    if t == "boolean" then return v and "B1" or "B0" end
    if t == "number" then return semanticNumber(v) end
    if t == "string" then return semanticString(v) end
    if t == "buffer" then return bufferSemanticToken(v) end
    if t == "EnumItem" then return "E:" .. tostring(v) end
    if t == "Instance" then
        if v.ClassName == "Player" then return "I:Player" end
        return "I:" .. v.ClassName .. ":" .. v.Name
    end
    if t == "Vector2" then return "V2" end
    if t == "Vector3" then return "V3" end
    if t == "CFrame" then return "CF" end
    if t == "Color3" then return "C3" end
    if t == "UDim2" then return "U2" end
    if t == "table" then
        if seen[v] then return "T:<cycle>" end
        seen[v] = true
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = tostring(k)
            if #keys >= C.SEMANTIC_TABLE_FIELDS then break end
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
            parts[#parts + 1] = key .. "=" .. semanticCanon(item, depth + 1, seen) .. ";"
        end
        parts[#parts + 1] = "}"
        seen[v] = nil
        return table.concat(parts)
    end
    return "X:" .. t
end

local function packedSemantic(args)
    local n = tonumber(args and args.n) or 0
    local parts = { tostring(n), "[" }
    local lim = math.min(n, C.MAX_ARGS)
    for i = 1, lim do
        parts[#parts + 1] = semanticCanon(args[i], 0, {})
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
    pendingManifestBody = nil,
    pendingManifestIndex = nil,
    finalManifest = nil,
    firstQueuedClock = 0,
    lastSendClock = 0,
    nextRetryClock = 0,
    lastUploadError = nil,
    uploadBlocked = false,
    uploadError = nil,
    uploadDiagnostics = {},
    uploadDiagSeq = 0,
    uploadFailureCount = 0,
    lastUploadDiagSignature = nil,
    cacheSchemaVersion = nil,
    inflightRestored = false,

    profile = nil,
    profileLow = {},
    profileShape = {},
    profileSemantic = {},
    profileRemote = {},
    profileFrontier = {},
    profileInvestigation = {},
    frontier = {}, frontierSet = {},
    deltaLow = {}, deltaLowSet = {},
    deltaShape = {}, deltaShapeSet = {},
    deltaSemantic = {}, deltaSemanticSet = {},
    deltaRemote = {}, deltaRemoteSet = {},

    sessionExact = {},
    sessionExactCount = 0,
    sessionSemantic = {},
    semanticCountByRemote = {},
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
    recentTimeline = {},
    recentGuiChanges = {},
    correlationWindows = {},
    correlationSeq = 0,
    lastCorrelationByRemote = {},
    effectTotals = {},
    effectBaseline = {},
    correlationEvidence = {},
    correlationEvidenceCount = 0,
    remoteImpact = {},
    behaviorTransitions = {},
    behaviorTransitionCount = 0,
    lastBehavior = nil,
    recentValueChanges = {},
    valueActivity = {},
    deepProbeCount = 0,
    lastDeepProbeByRemote = {},
    opaquePrevious = {},
    opaqueCounters = {},
    runtimePatternCounts = {},
    runtimePatternSeen = {},
    objectBorn = setmetatable({}, { __mode = "k" }),
    toolSignals = setmetatable({}, { __mode = "k" }),
    guiSignals = setmetatable({}, { __mode = "k" }),

    investigatorState = "GREEN",
    investigatorReason = "livre",
    investigatorStateSince = 0,
    investigatorStage = "idle",
    investigatorStageDetail = "livre",
    investigatorStageSince = 0,
    lastInvestigatorError = nil,
    activeInvestigation = nil,
    investigationQueue = {},
    investigationQueuedKeys = {},
    investigationSeq = 0,
    investigationEpoch = 0,
    investigationCount = 0,
    investigationLastByKey = {},
    investigationKnowledgeDelta = {},
    actionSeenCounts = {},
    inputQuarantine = false,
    investigationNextStartAt = 0,

    menuHealthDiagnostics = {},
    menuHealthDiagSeq = 0,
    menuHealthLastCheck = 0,
    menuHealthLastStatus = nil,
    menuHealthLastAnomaly = nil,
    menuHealthLastError = nil,

    protocolModels = {},
    protocolModelCount = 0,
    argumentFields = {},
    argumentFieldCount = 0,

    smartStats = {
        outboundObserved = 0,
        outboundAccepted = 0,
        highInterestOutbound = 0,
        correlationsOpened = 0,
        semanticNovel = 0,
        opaqueSamples = 0,
        deepProbes = 0,
        investigationsQueued = 0,
        investigationsCompleted = 0,
        investigationsActive = 0,
        investigationsPassive = 0,
        investigationsCancelled = 0,
        investigationsBlocked = 0,
        inputQuarantines = 0,
        investigatorDiagnostics = 0,
        investigatorErrors = 0,
        menuHealthChecks = 0,
        menuHealthAnomalies = 0,
        menuHealthUiErrors = 0,
        menuHealthQueueStarts = 0,
        menuHealthQueueErrors = 0,
        investigationsConfirmedSkipped = 0,
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

local function classifyUploadError(err)
    local raw = string.sub(tostring(err or "unknown"), 1, C.UPLOAD_ERROR_TEXT_MAX)
    local code = tonumber(string.match(raw, "HTTP%s+(%d%d%d)"))
    local kind, label, retryable = "network", "FALHA DE REDE", true

    if code == 409 or string.find(string.lower(raw), "conteúdo diferente", 1, true) then
        kind, label, retryable = "ack_conflict", "CONFLITO ACK/LOTE", false
    elseif code == 400 then
        kind, label, retryable = "bad_request", "REQUISIÇÃO INVÁLIDA", false
    elseif code == 413 then
        kind, label, retryable = "payload_too_large", "LOTE GRANDE DEMAIS", false
    elseif code == 429 then
        kind, label, retryable = "rate_limit", "LIMITE DA API", true
    elseif code and code >= 500 then
        kind, label, retryable = "server_error", "SERVIDOR/GITHUB", true
    elseif string.find(raw, "invalid_api_response", 1, true) then
        kind, label, retryable = "invalid_response", "RESPOSTA INVÁLIDA", true
    elseif string.find(raw, "github_not_confirmed", 1, true) then
        kind, label, retryable = "github_unconfirmed", "GITHUB NÃO CONFIRMOU", true
    elseif string.find(raw, "meta_encode_failed", 1, true) then
        kind, label, retryable = "encode_error", "ERRO AO MONTAR LOTE", false
    end

    return { raw = raw, code = code, kind = kind, label = label, retryable = retryable }
end

local function noteUploadError(phase, err, batchIndex)
    phase = tostring(phase or "upload")
    local info = classifyUploadError(err)
    if phase == "orphan_inflight" or phase == "inflight_sequence" or phase == "inflight_restore" then
        info.kind = "recovery_state"
        info.label = "ESTADO DE RECUPERAÇÃO"
        info.retryable = false
    end
    S.uploadFailureCount = (tonumber(S.uploadFailureCount) or 0) + 1
    local signature = table.concat({
        tostring(phase or "?"), tostring(batchIndex or "?"), tostring(info.code or 0),
        tostring(info.kind), string.sub(info.raw, 1, 180),
    }, "|")

    if S.uploadError and signature == S.lastUploadDiagSignature then
        S.uploadError.attempts = (tonumber(S.uploadError.attempts) or 1) + 1
        S.uploadError.clock = os.clock() - (S.startClock or os.clock())
    else
        S.uploadDiagSeq = (tonumber(S.uploadDiagSeq) or 0) + 1
        local row = {
            seq = S.uploadDiagSeq,
            phase = phase,
            batchIndex = tonumber(batchIndex),
            code = info.code,
            kind = info.kind,
            label = info.label,
            retryable = info.retryable,
            raw = info.raw,
            attempts = 1,
            clock = os.clock() - (S.startClock or os.clock()),
        }
        S.uploadError = row
        S.uploadDiagnostics[#S.uploadDiagnostics + 1] = row
        while #S.uploadDiagnostics > C.UPLOAD_DIAGNOSTIC_CAP do
            table.remove(S.uploadDiagnostics, 1)
        end
        S.lastUploadDiagSignature = signature
    end

    S.lastUploadError = info.raw
    if not info.retryable then
        S.uploadBlocked = true
        S.nextRetryClock = math.huge
    end
    return S.uploadError
end

local function clearActiveUploadError()
    S.uploadError = nil
    S.lastUploadDiagSignature = nil
    S.uploadFailureCount = 0
    if not S.uploadBlocked then S.lastUploadError = nil end
end

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

local setInputQuarantine

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

local TIMELINE_CATEGORIES = {
    remote_outbound = true, remote_inbound = true, value_changed = true,
    tool_transition = true, tool_signal = true, player_attribute = true,
    prompt_triggered = true, gui_interaction = true, gui_state = true, character = true,
}

local function timelineIdentity(category, object)
    object = type(object) == "table" and object or {}
    local row = {
        clock = os.clock() - S.startClock, category = category, kind = tostring(object.kind or category),
        priority = tonumber(object.quality) or nil,
    }
    if object.remote then
        row.remote = tostring(object.remote.path or object.remote.name or "?")
        row.method = object.method
        row.semanticHash = object.semanticHash
    elseif object.object then
        row.path = tostring(object.object.path or object.object.name or "?")
    elseif object.tool then
        row.path = tostring(object.tool.path or object.tool.name or "?")
    elseif object.prompt then
        row.path = tostring(object.prompt.path or object.prompt.name or "?")
    elseif object.gui then
        row.path = tostring(object.gui.path or object.gui.name or "?")
    elseif object.name then
        row.path = tostring(object.name)
    end
    return row
end

local function noteTimeline(category, object)
    if not TIMELINE_CATEGORIES[category] then return end
    local now = os.clock() - S.startClock
    S.recentTimeline[#S.recentTimeline + 1] = timelineIdentity(category, object)
    local cutoff = now - C.TIMELINE_SECONDS
    while #S.recentTimeline > 0 and (#S.recentTimeline > C.TIMELINE_CAP or (S.recentTimeline[1].clock or 0) < cutoff) do
        table.remove(S.recentTimeline, 1)
    end
end

local function timelineSnapshot(sinceClock)
    local out = {}
    local since = tonumber(sinceClock) or ((os.clock() - S.startClock) - C.TIMELINE_SECONDS)
    for _, row in ipairs(S.recentTimeline) do
        if (row.clock or 0) >= since then out[#out + 1] = row end
    end
    return out
end

local function recentDirectInteraction(maxAge)
    local now = os.clock() - S.startClock
    local limit = tonumber(maxAge) or C.INTERACTION_CONTEXT_SECONDS
    for i = #S.recentTimeline, 1, -1 do
        local row = S.recentTimeline[i]
        local age = now - (tonumber(row.clock) or 0)
        if age > limit then break end
        local direct = (row.category == "gui_interaction" and row.kind == "gui_activated") or
            (row.category == "tool_signal" and row.kind == "tool_activated") or
            row.category == "prompt_triggered"
        if direct then
            return {
                category = row.category, kind = row.kind, path = row.path,
                age = math.floor(math.max(0, age) * 1000 + 0.5) / 1000,
            }
        end
    end
    return nil
end

local function modelProtocol(direction, remotePath, method, shapeHash, semanticHash)
    local key = tostring(direction) .. "|" .. tostring(remotePath) .. "|" .. tostring(method)
    local row = S.protocolModels[key]
    if not row then
        if S.protocolModelCount >= C.PROTOCOL_MODEL_CAP then return end
        row = {
            direction = direction, remote = remotePath, method = method,
            observed = 0, shapeChanges = 0, semanticChanges = 0,
            lastShape = nil, lastSemantic = nil, shapes = {}, semantics = {},
        }
        S.protocolModels[key] = row
        S.protocolModelCount = S.protocolModelCount + 1
    end
    row.observed = row.observed + 1
    if shapeHash then
        if row.lastShape and row.lastShape ~= shapeHash then row.shapeChanges = row.shapeChanges + 1 end
        row.lastShape = shapeHash
        if #row.shapes < 12 then
            local exists = false
            for _, h in ipairs(row.shapes) do if h == shapeHash then exists = true break end end
            if not exists then row.shapes[#row.shapes + 1] = shapeHash end
        end
    end
    if semanticHash then
        if row.lastSemantic and row.lastSemantic ~= semanticHash then row.semanticChanges = row.semanticChanges + 1 end
        row.lastSemantic = semanticHash
        if #row.semantics < 16 then
            local exists = false
            for _, h in ipairs(row.semantics) do if h == semanticHash then exists = true break end end
            if not exists then row.semantics[#row.semantics + 1] = semanticHash end
        end
    end
end

local function fieldModelTouch(streamKey, fieldPath, value)
    local key = hashText("field|" .. tostring(streamKey) .. "|" .. tostring(fieldPath))
    local row = S.argumentFields[key]
    if not row then
        if S.argumentFieldCount >= C.ARGUMENT_FIELD_CAP then return end
        row = {
            stream = string.sub(tostring(streamKey), 1, 220), field = string.sub(tostring(fieldPath), 1, 120),
            observed = 0, changes = 0, last = nil, types = {},
        }
        S.argumentFields[key] = row
        S.argumentFieldCount = S.argumentFieldCount + 1
    end
    row.observed = row.observed + 1
    local token = semanticCanon(value, 0, {})
    if row.last and row.last ~= token then row.changes = row.changes + 1 end
    row.last = token
    local t = typeof(value)
    if #row.types < 6 then
        local exists = false
        for _, item in ipairs(row.types) do if item == t then exists = true break end end
        if not exists then row.types[#row.types + 1] = t end
    end
end

local function observeArgumentFields(remotePath, method, args, namespace)
    local stream = tostring(namespace or "out") .. "|" .. tostring(remotePath) .. "|" .. tostring(method)
    local n = math.min(tonumber(args and args.n) or 0, C.ACTIVE_TEST_MAX_ARGS)
    for i = 1, n do
        local value = args[i]
        fieldModelTouch(stream, "arg" .. tostring(i), value)
        if typeof(value) == "table" then
            local count = 0
            for k, item in pairs(value) do
                count = count + 1
                if count > C.SEMANTIC_TABLE_FIELDS then break end
                fieldModelTouch(stream, "arg" .. tostring(i) .. "." .. tostring(k), item)
            end
        end
    end
end

local function applyProfile(profile)
    profile = type(profile) == "table" and profile or {}
    S.profile = profile
    S.profileLow = arrayToSet(profile.knownLowValueHashes)
    S.profileShape = arrayToSet(profile.knownShapeHashes)
    S.profileSemantic = arrayToSet(profile.knownSemanticHashes)
    S.profileRemote = arrayToSet(profile.knownRemoteHashes)
    S.profileFrontier = arrayToSet(profile.frontier)
    S.profileInvestigation = {}
    for _, row in ipairs(type(profile.investigationKnowledge) == "table" and profile.investigationKnowledge or {}) do
        if type(row) == "table" and type(row.key) == "string" then
            S.profileInvestigation[row.key] = row
        end
    end
    S.profileReady = true
end

local function semanticStatus(remotePath, method, args, namespace)
    namespace = tostring(namespace or "call")
    local semanticHash = hashText("semantic\31" .. namespace .. "\31" .. tostring(remotePath) .. "\31" ..
        tostring(method) .. "\31" .. packedSemantic(args))
    local remoteKey = namespace .. "\31" .. tostring(remotePath) .. "\31" .. tostring(method)
    local count = tonumber(S.semanticCountByRemote[remoteKey]) or 0
    local isNew = not S.profileSemantic[semanticHash] and not S.sessionSemantic[semanticHash] and
        count < C.MAX_SEMANTIC_PER_REMOTE
    return semanticHash, isNew, remoteKey
end

local function rememberSemantic(semanticHash, remoteKey)
    if not semanticHash or S.sessionSemantic[semanticHash] then return end
    S.sessionSemantic[semanticHash] = true
    S.profileSemantic[semanticHash] = true
    S.semanticCountByRemote[remoteKey] = (tonumber(S.semanticCountByRemote[remoteKey]) or 0) + 1
    addBoundedDelta(S.deltaSemantic, S.deltaSemanticSet, semanticHash, C.DELTA_SEMANTIC_CAP)
    S.smartStats.semanticNovel = (S.smartStats.semanticNovel or 0) + 1
end

local function rememberShape(shapeHash)
    if not shapeHash or S.profileShape[shapeHash] then return end
    S.profileShape[shapeHash] = true
    addBoundedDelta(S.deltaShape, S.deltaShapeSet, shapeHash, C.DELTA_SHAPE_CAP)
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

local function normalizeDynamicSegment(segment)
    local text = tostring(segment or "")
    if #text >= 8 and string.match(text, "^%d+$") then return "<id>" end
    local compact = string.gsub(text, "%-", "")
    if #compact >= 16 and string.match(compact, "^%x+$") then return "<id>" end
    return string.gsub(text, "%d%d%d%d+", "<n>")
end

local NORMALIZED_CHARACTER_ROOT = setmetatable({}, { __mode = "k" })

local function normalizedPath(inst)
    if typeof(inst) ~= "Instance" then return tostring(inst) end
    local raw = pathOf(inst)
    local top = inst
    local guard = 0
    while top and top.Parent and top.Parent ~= Workspace and top.Parent ~= ReplicatedStorage and guard < 48 do
        top = top.Parent
        guard = guard + 1
    end
    if top and top.Parent == Workspace then
        local cached = NORMALIZED_CHARACTER_ROOT[top]
        if cached == nil then
            local ok, player = pcall(function() return Players:GetPlayerFromCharacter(top) end)
            cached = ok and player ~= nil
            NORMALIZED_CHARACTER_ROOT[top] = cached
        end
        if cached then
            local prefix = pathOf(top)
            if string.sub(raw, 1, #prefix) == prefix then
                raw = "Workspace.<Character>" .. string.sub(raw, #prefix + 1)
            end
        end
    end
    local parts = {}
    for segment in string.gmatch(raw, "[^%.]+") do parts[#parts + 1] = normalizeDynamicSegment(segment) end
    return table.concat(parts, ".")
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

local function importanceScore(remotePath, method, newShape, className, newSemantic, newResponseShape, newResponseSemantic)
    local score = method == "InvokeServer" and 50 or (method == "FireServer" and 42 or 34)
    if newShape then score = score + 22 end
    if newSemantic then score = score + 14 end
    if newResponseShape then score = score + 12 end
    if newResponseSemantic then score = score + 10 end
    if className == "RemoteFunction" then score = score + 8 end
    score = score + math.min(18, math.floor(tonumber(S.remoteImpact[remotePath]) or 0))

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

    if t == "buffer" then
        local len = bufferLength(v)
        return { type = "buffer", length = len, lengthBucket = bufferLengthBucket(len) }
    end

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
    gui_state = true,
    character = true,
}

local BEHAVIOR_CATEGORIES = {
    remote_outbound = true,
    remote_inbound = true,
    tool_transition = true,
    tool_signal = true,
    gui_interaction = true,
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

local function effectIdentity(category, object)
    object = type(object) == "table" and object or {}
    if category == "remote_inbound" then
        return "remote:" .. tostring(object.remote and object.remote.path or "?")
    elseif category == "value_changed" then
        return "value:" .. tostring(object.object and object.object.path or "?")
    elseif category == "runtime_added" or category == "runtime_remove" then
        local o = object.object or {}
        return category .. ":" .. tostring(o.className or object.className or "?") .. ":" ..
            tostring(o.name or object.name or o.path or object.path or "?")
    elseif category == "tool_transition" then
        return "tool:" .. tostring(object.kind or "?") .. ":" .. tostring(object.tool and object.tool.name or "?")
    elseif category == "player_attribute" then
        return "attribute:" .. tostring(object.name or "?")
    elseif category == "gui_state" then
        return "gui:" .. tostring(object.gui and object.gui.path or object.path or "?") .. ":" .. tostring(object.state or "?")
    elseif category == "prompt_triggered" then
        return "prompt:" .. tostring(object.prompt and object.prompt.path or "?")
    elseif category == "character" then
        return "character:" .. tostring(object.kind or "?")
    end
    return tostring(category) .. ":" .. tostring(object.kind or "?")
end


local function pathInsidePlayerCharacter(path)
    local text = tostring(path or "")
    if text == "" then return false end
    local ok, players = pcall(function() return Players:GetPlayers() end)
    if not ok then return false end
    for _, player in ipairs(players) do
        local prefix = "Workspace." .. tostring(player.Name)
        if text == prefix or string.sub(text, 1, #prefix + 1) == prefix .. "." then
            return true
        end
    end
    return false
end

local function correlationEffectReliability(category, object)
    if category ~= "runtime_added" and category ~= "runtime_remove" then return 1 end
    object = type(object) == "table" and object or {}
    local o = type(object.object) == "table" and object.object or {}
    if tostring(o.className or object.className or "") == "Tool" then return 1 end
    local path = o.path or object.path
    if pathInsidePlayerCharacter(path) then
        return 0.25
    end
    return 1
end

local function correlationMetrics(evidence)
    if type(evidence) ~= "table" then
        return { baseline = 0, total = 0, confidence = 0, stage = "candidate", trustedSupport = 0 }
    end
    local effectHash = evidence.effectHash
    local baseline = tonumber(S.effectBaseline[effectHash]) or 0
    local total = tonumber(S.effectTotals[effectHash]) or tonumber(evidence.support) or 1
    local support = tonumber(evidence.support) or 0
    local trustedSupport = tonumber(evidence.trustedSupport) or support
    local consistency = trustedSupport / math.max(1, total)
    local separation = trustedSupport / math.max(1, trustedSupport + baseline + 2)
    local meanRecency = (tonumber(evidence.weighted) or 0) / math.max(0.001, trustedSupport)

    local timingConsistency = 1
    if support >= 2 then
        local meanAge = (tonumber(evidence.ageSum) or 0) / support
        local meanSq = (tonumber(evidence.ageSqSum) or 0) / support
        local variance = math.max(0, meanSq - meanAge * meanAge)
        local stdDev = math.sqrt(variance)
        timingConsistency = 1 / (1 + stdDev * 1.5)
    end

    local confidence = math.floor(math.clamp(
        consistency * separation * meanRecency * timingConsistency * 100, 0, 99
    ) + 0.5)

    local maxReliability = tonumber(evidence.maxReliability) or 1
    local distinctEffects = tonumber(evidence.distinctEffects) or support
    local stage = "candidate"
    if maxReliability < 0.5 then
        stage = "weak_context"
    elseif distinctEffects >= C.CORRELATION_CONFIRM_MIN_DISTINCT and
        trustedSupport >= C.CORRELATION_CONFIRM_MIN_TRUSTED_SUPPORT and
        confidence >= C.CORRELATION_CONFIRM_MIN_CONFIDENCE and
        baseline <= C.CORRELATION_CONFIRM_MAX_BASELINE then
        stage = "confirmed"
    elseif distinctEffects >= 2 then
        stage = "repeated"
    end

    return {
        baseline = baseline,
        total = total,
        confidence = confidence,
        stage = stage,
        distinctEffects = distinctEffects,
        trustedSupport = math.floor(trustedSupport * 100 + 0.5) / 100,
        timingConsistency = math.floor(timingConsistency * 1000 + 0.5) / 1000,
    }
end

local function relationStageForCandidate(remotePath, shapeHash, semanticHash)
    local rank = { weak_context = 0, candidate = 1, repeated = 2, confirmed = 3 }
    local best = nil
    for _, row in pairs(S.correlationEvidence) do
        if row.remote == remotePath and
            (row.semantic == semanticHash or row.shape == shapeHash) then
            local stage = correlationMetrics(row).stage
            if best == nil or (rank[stage] or 0) > (rank[best] or 0) then best = stage end
            if best == "confirmed" then break end
        end
    end
    return best or "candidate"
end

local function correlationCandidates(category, object, priority)
    if not CORRELATABLE_CATEGORIES[category] then return nil end
    pruneCorrelationWindows()
    local effectLabel = string.sub(effectIdentity(category, object), 1, 220)
    local effectHash = hashText("effect\31" .. effectLabel)
    S.effectTotals[effectHash] = (S.effectTotals[effectHash] or 0) + 1
    if #S.correlationWindows == 0 then
        S.effectBaseline[effectHash] = (S.effectBaseline[effectHash] or 0) + 1
        return nil
    end
    local now, out = os.clock(), {}
    local first = math.max(1, #S.correlationWindows - 2)
    for i = first, #S.correlationWindows do
        local w = S.correlationWindows[i]
        local age = math.max(0, now - w.startedAt)
        local actionKey = tostring(w.semantic or w.shape or w.remote)
        local pairKey = hashText("corr\31" .. actionKey .. "\31" .. effectHash)
        local evidence = S.correlationEvidence[pairKey]
        if not evidence and S.correlationEvidenceCount < C.CORRELATION_EVIDENCE_CAP then
            evidence = {
                remote = w.remote, method = w.method, shape = w.shape, semantic = w.semantic,
                effect = effectLabel, effectHash = effectHash, support = 0, trustedSupport = 0,
                distinctEffects = 0, lastOccurrence = nil,
                weighted = 0, ageSum = 0, ageSqSum = 0, maxReliability = 0,
            }
            S.correlationEvidence[pairKey] = evidence
            S.correlationEvidenceCount = S.correlationEvidenceCount + 1
        end
        local confidence, support, stage, trustedSupport, timingConsistency, distinctEffects =
            0, 0, "candidate", 0, 1, 0
        local baseline = S.effectBaseline[effectHash] or 0
        local total = S.effectTotals[effectHash] or 1
        local reliability = correlationEffectReliability(category, object)
        local occurrence = tostring(object.clock or (now - S.startClock)) .. "|" .. tostring(category) .. "|" .. effectHash
        if evidence then
            local recency = math.max(0.05, 1 - (age / math.max(0.001, C.CORRELATION_SECONDS)))
            evidence.support = evidence.support + 1
            if evidence.lastOccurrence ~= occurrence then
                evidence.lastOccurrence = occurrence
                evidence.distinctEffects = (tonumber(evidence.distinctEffects) or 0) + 1
            end
            evidence.trustedSupport = (tonumber(evidence.trustedSupport) or 0) + reliability
            evidence.weighted = (tonumber(evidence.weighted) or 0) + recency * reliability
            evidence.ageSum = (tonumber(evidence.ageSum) or 0) + age
            evidence.ageSqSum = (tonumber(evidence.ageSqSum) or 0) + age * age
            evidence.maxReliability = math.max(tonumber(evidence.maxReliability) or 0, reliability)
            evidence.lastAge = age
            local metrics = correlationMetrics(evidence)
            support = evidence.support
            baseline = metrics.baseline
            total = metrics.total
            confidence = metrics.confidence
            stage = metrics.stage
            distinctEffects = metrics.distinctEffects
            trustedSupport = metrics.trustedSupport
            timingConsistency = metrics.timingConsistency
            if support >= C.CORRELATION_IMPACT_MIN_SUPPORT and
                distinctEffects >= C.CORRELATION_IMPACT_MIN_DISTINCT and
                trustedSupport >= C.CORRELATION_IMPACT_MIN_TRUSTED_SUPPORT and
                confidence >= C.CORRELATION_IMPACT_MIN_CONFIDENCE and
                (tonumber(priority) or 0) >= 72 then
                S.remoteImpact[w.remote] = math.max(
                    tonumber(S.remoteImpact[w.remote]) or 0,
                    confidence * 0.18
                )
            end
        end
        out[#out + 1] = {
            id = w.id, remote = w.remote, method = w.method, shape = w.shape, semantic = w.semantic,
            importance = w.importance, age = age, effect = effectLabel,
            support = support, distinctEffects = distinctEffects,
            trustedSupport = trustedSupport, baseline = baseline,
            effectTotal = total, confidence = confidence, relationStage = stage,
            timingConsistency = timingConsistency, reliability = reliability,
        }
    end
    return out
end

local function openCorrelationWindow(remotePath, method, shapeHash, importance, semanticHash)
    local now = os.clock()
    local correlationKey = tostring(remotePath) .. "\31" .. tostring(semanticHash or shapeHash or "")
    local last = S.lastCorrelationByRemote[correlationKey] or 0
    if now - last < C.CORRELATION_MIN_GAP then return end
    S.lastCorrelationByRemote[correlationKey] = now
    pruneCorrelationWindows()
    S.correlationSeq = S.correlationSeq + 1
    S.correlationWindows[#S.correlationWindows + 1] = {
        id = S.correlationSeq, remote = remotePath, method = method, shape = shapeHash,
        semantic = semanticHash, importance = importance, startedAt = now,
        expiresAt = now + C.CORRELATION_SECONDS,
    }
    while #S.correlationWindows > C.MAX_CORRELATION_WINDOWS do table.remove(S.correlationWindows, 1) end
    S.smartStats.correlationsOpened = (S.smartStats.correlationsOpened or 0) + 1
end

local function behaviorIdentity(category, object)
    object = type(object) == "table" and object or {}
    if category == "remote_outbound" or category == "remote_inbound" then
        local path = tostring(object.remote and object.remote.path or "?")
        local semantic = tostring(object.semanticHash or object.responseSemanticHash or "")
        local key = category .. ":" .. path .. ":" .. semantic
        local label = category .. ":" .. path
        return hashText(key), string.sub(label, 1, 220)
    elseif category == "tool_transition" or category == "tool_signal" then
        local label = "tool:" .. tostring(object.kind or "?") .. ":" .. tostring(object.tool and object.tool.name or "?")
        return hashText(label), string.sub(label, 1, 220)
    elseif category == "gui_interaction" then
        local label = "gui:" .. tostring(object.gui and object.gui.path or "?")
        return hashText(label), string.sub(label, 1, 220)
    elseif category == "player_attribute" then
        local label = "attribute:" .. tostring(object.name or "?")
        return hashText(label), label
    elseif category == "prompt_triggered" then
        local label = "prompt:" .. tostring(object.prompt and object.prompt.path or "?")
        return hashText(label), string.sub(label, 1, 220)
    elseif category == "character" then
        local label = "character:" .. tostring(object.kind or "?")
        return hashText(label), label
    end
    return nil, nil
end

local function observeBehavior(category, object, priority)
    if not BEHAVIOR_CATEGORIES[category] or (tonumber(priority) or 0) < 72 then return end
    local key, label = behaviorIdentity(category, object)
    if not key then return end
    local now = tonumber(object and object.clock) or (os.clock() - S.startClock)
    local last = S.lastBehavior
    if last and last.key ~= key then
        local gap = math.max(0, now - last.clock)
        if gap <= 8 then
            local pairKey = hashText("transition\31" .. last.key .. "\31" .. key)
            local row = S.behaviorTransitions[pairKey]
            if not row and S.behaviorTransitionCount < C.BEHAVIOR_TRANSITION_CAP then
                row = { from = last.label, to = label, count = 0, totalGap = 0, minGap = gap, maxGap = gap }
                S.behaviorTransitions[pairKey] = row
                S.behaviorTransitionCount = S.behaviorTransitionCount + 1
            end
            if row then
                row.count = row.count + 1
                row.totalGap = row.totalGap + gap
                row.minGap = math.min(row.minGap, gap)
                row.maxGap = math.max(row.maxGap, gap)
            end
        end
    end
    S.lastBehavior = { key = key, label = label, clock = now }
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

    noteTimeline(category, object)
    if S.activeInvestigation and TIMELINE_CATEGORIES[category] then
        S.activeInvestigation.lastRelevantClock = os.clock()
    end

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
    local causeCandidates = correlationCandidates(category, object, priority)
    if causeCandidates then
        object.causeCandidates = causeCandidates
        object.correlationModel = "evidence_v2"
    end

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
    observeBehavior(category, object, priority)

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

local saveCache
local cacheSnapshot
local saveInflight
local clearInflight

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

    local body = batch.body
    if type(body) ~= "string" then
        local encoded, err = encodeBatchBody(batch, false, nil)
        if not encoded then return false, err end
        body = encoded
        batch.body = body
    end

    if WRITEFILE and saveInflight then
        local persisted, persistErr = saveInflight(batch, body)
        if not persisted then
            noteUploadError("outbox_write", persistErr, batch.index)
        end
    end

    local ok, data, postErr = postRaw(C.BASE .. "/batch", body)
    S.lastSendClock = os.clock()
    return ok, ok and data or postErr
end

local function acknowledgeBatch(batch)
    local recoveryMode = S.cached ~= nil
    S.batchIndex = batch.index
    S.queueHead = batch.stop + 1
    S.queueBytes = math.max(0, S.queueBytes - batch.bytes)
    S.ackBytes = S.ackBytes + batch.bytes
    S.pendingSend = nil
    S.uploadBlocked = false
    clearActiveUploadError()
    compactQueue()
    if S.queueHead > #S.queue or S.queueBytes <= 0 then
        S.firstQueuedClock = 0
    else
        S.firstQueuedClock = os.clock()
    end

    if recoveryMode and saveCache and cacheSnapshot then
        local snap = cacheSnapshot()
        local saved = saveCache(snap)
        if saved then S.cached = snap end
    end
    if clearInflight then clearInflight() end
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
                noteUploadError("data_batch", err, batch.index)
                if not S.uploadBlocked then S.nextRetryClock = os.clock() + 5 end
                if saveCache and cacheSnapshot then saveCache(cacheSnapshot()) end
                break
            end
            if S.running and not S.finalizing and not shouldFlushQueue(false) then break end
            task.wait()
        end
        S.uploading = false
    end)
end

--==============================================================--
-- PERSISTENT CACHE FOR UNSENT QUEUE
--==============================================================--

local function cacheFile()
    return tostring(game.GameId) .. "_" .. C.CACHE_SUFFIX
end

local function inflightFile()
    return tostring(game.GameId) .. "_CafeinaUniversalTraceV30_inflight.json"
end

saveInflight = function(batch, body)
    if not WRITEFILE then return false, "writefile_unavailable" end
    local payload = {
        schemaVersion = 1,
        gameId = S.runGameId,
        placeId = S.runPlaceId,
        placeVersion = S.runPlaceVersion,
        runId = S.runId,
        startIso = S.startIso,
        batchIndex = batch.index,
        payloadBytes = batch.bytes or 0,
        itemCount = math.max(0, (tonumber(batch.stop) or 0) - (tonumber(batch.start) or 1) + 1),
        body = body,
    }
    local ok, text = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then return false, "inflight_encode_failed" end
    local wrote, err = pcall(WRITEFILE, inflightFile(), text)
    return wrote, wrote and nil or tostring(err)
end

local function loadInflight()
    if not READFILE or not ISFILE then return nil end
    local ok, exists = pcall(ISFILE, inflightFile())
    if not ok or not exists then return nil end
    local readOk, text = pcall(READFILE, inflightFile())
    if not readOk or type(text) ~= "string" then return nil end
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
    if not decodeOk or type(data) ~= "table" or tonumber(data.gameId) ~= game.GameId then return nil end
    return data
end

clearInflight = function()
    if DELFILE and ISFILE then
        local ok, exists = pcall(ISFILE, inflightFile())
        if ok and exists then pcall(DELFILE, inflightFile()) end
    end
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

cacheSnapshot = function()
    local pending = nil
    if type(S.pendingSend) == "table" and type(S.pendingSend.body) == "string" then
        pending = {
            index = S.pendingSend.index,
            bytes = S.pendingSend.bytes,
            itemCount = math.max(0, (tonumber(S.pendingSend.stop) or 0) - (tonumber(S.pendingSend.start) or 1) + 1),
            body = S.pendingSend.body,
        }
    end
    return {
        schemaVersion = 4, collectorVersion = C.VERSION,
        gameId = S.runGameId, placeId = S.runPlaceId,
        placeVersion = S.runPlaceVersion, runId = S.runId, startIso = S.startIso,
        batchIndex = S.batchIndex, totalBytes = S.totalBytes, ackBytes = S.ackBytes,
        finalManifest = S.finalManifest,
        pendingSend = pending,
        pendingManifestBody = S.pendingManifestBody,
        pendingManifestIndex = S.pendingManifestIndex,
        lastUploadError = S.lastUploadError,
        queue = queueForCache(),
        deltaLow = S.deltaLow, deltaShape = S.deltaShape, deltaSemantic = S.deltaSemantic, deltaRemote = S.deltaRemote,
        strategy = strategySnapshot(), coverage = S.coverage, frontier = S.frontier,
        suppressed = S.suppressed, dropped = S.dropped, repeatCounts = S.repeatCounts,
        smartStats = S.smartStats, focusRemote = S.focusRemote, focusScore = S.focusScore,
        correlationEvidence = S.correlationEvidence, effectTotals = S.effectTotals, effectBaseline = S.effectBaseline,
        remoteImpact = S.remoteImpact, behaviorTransitions = S.behaviorTransitions,
        investigationKnowledgeDelta = S.investigationKnowledgeDelta,
        protocolModels = S.protocolModels, argumentFields = S.argumentFields,
    }
end

saveCache = function(snap)
    snap = snap or cacheSnapshot()
    if not WRITEFILE then
        noteUploadError("cache_write", "writefile_unavailable", S.batchIndex)
        return false, "writefile_unavailable"
    end
    local ok, text = pcall(HttpService.JSONEncode, HttpService, snap)
    if not ok then
        noteUploadError("cache_write", "cache_encode_failed", S.batchIndex)
        return false, "cache_encode_failed"
    end
    local wrote, err = pcall(WRITEFILE, cacheFile(), text)
    if not wrote then
        noteUploadError("cache_write", tostring(err), S.batchIndex)
        return false, tostring(err)
    end
    return true, nil
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
    setInputQuarantine(false)
    S.investigatorState, S.investigatorReason = "GREEN", "cache"
    S.activeInvestigation, S.investigationQueue, S.investigationQueuedKeys = nil, {}, {}
    S.investigationEpoch = S.investigationEpoch + 1
    S.runGameId = tonumber(data.gameId) or game.GameId
    S.runPlaceId = tonumber(data.placeId) or game.PlaceId
    S.runPlaceVersion = tonumber(data.placeVersion) or game.PlaceVersion
    S.runId = tostring(data.runId or HttpService:GenerateGUID(false))
    S.startIso = tostring(data.startIso or iso())
    S.startClock = os.clock()
    S.batchIndex = tonumber(data.batchIndex) or 0
    S.cacheSchemaVersion = tonumber(data.schemaVersion) or 0
    S.finalManifest = type(data.finalManifest) == "table" and data.finalManifest or nil
    S.pendingManifestBody = type(data.pendingManifestBody) == "string" and data.pendingManifestBody or nil
    S.pendingManifestIndex = tonumber(data.pendingManifestIndex)
    S.lastUploadError = type(data.lastUploadError) == "string" and data.lastUploadError or nil
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
    S.firstQueuedClock = S.queueBytes > 0 and os.clock() or 0
    S.deltaLow = type(data.deltaLow) == "table" and data.deltaLow or {}
    S.deltaShape = type(data.deltaShape) == "table" and data.deltaShape or {}
    S.deltaSemantic = type(data.deltaSemantic) == "table" and data.deltaSemantic or {}
    S.deltaRemote = type(data.deltaRemote) == "table" and data.deltaRemote or {}
    S.deltaLowSet, S.deltaShapeSet, S.deltaSemanticSet, S.deltaRemoteSet =
        arrayToSet(S.deltaLow), arrayToSet(S.deltaShape), arrayToSet(S.deltaSemantic), arrayToSet(S.deltaRemote)
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
    local savedPending = type(data.pendingSend) == "table" and data.pendingSend or nil
    if savedPending and type(savedPending.body) == "string" then
        local itemCount = math.max(0, math.floor(tonumber(savedPending.itemCount) or 0))
        if itemCount > 0 and itemCount <= #S.queue and tonumber(savedPending.index) == S.batchIndex + 1 then
            S.pendingSend = {
                index = tonumber(savedPending.index),
                start = 1,
                stop = itemCount,
                bytes = tonumber(savedPending.bytes) or 0,
                body = savedPending.body,
            }
            S.inflightRestored = true
        end
    end
    S.nextRetryClock = 0
    S.uploading = false
    S.uploadBlocked = false
    S.uploadError = nil
    S.suppressed = type(data.suppressed) == "table" and data.suppressed or {}
    S.dropped = type(data.dropped) == "table" and data.dropped or {}
    S.smartStats = type(data.smartStats) == "table" and data.smartStats or {
        outboundObserved = 0, outboundAccepted = 0, highInterestOutbound = 0,
        highInterestInbound = 0, correlationsOpened = 0, semanticNovel = 0,
        opaqueSamples = 0, deepProbes = 0,
        investigationsQueued = 0, investigationsCompleted = 0, investigationsActive = 0,
        investigationsPassive = 0, investigationsCancelled = 0, investigationsBlocked = 0,
        inputQuarantines = 0, investigatorDiagnostics = 0, investigatorErrors = 0,
        batchBudgetDrops = 0,
    }
    S.focusRemote = type(data.focusRemote) == "string" and data.focusRemote or nil
    S.focusScore = tonumber(data.focusScore) or 0
    S.correlationWindows, S.lastCorrelationByRemote = {}, {}
    S.correlationSeq = 0
    S.correlationEvidence = type(data.correlationEvidence) == "table" and data.correlationEvidence or {}
    S.correlationEvidenceCount = 0
    for _ in pairs(S.correlationEvidence) do S.correlationEvidenceCount = S.correlationEvidenceCount + 1 end
    S.effectTotals = type(data.effectTotals) == "table" and data.effectTotals or {}
    S.effectBaseline = type(data.effectBaseline) == "table" and data.effectBaseline or {}
    S.remoteImpact = type(data.remoteImpact) == "table" and data.remoteImpact or {}
    S.behaviorTransitions = type(data.behaviorTransitions) == "table" and data.behaviorTransitions or {}
    S.behaviorTransitionCount = 0
    for _ in pairs(S.behaviorTransitions) do S.behaviorTransitionCount = S.behaviorTransitionCount + 1 end
    S.investigationKnowledgeDelta = type(data.investigationKnowledgeDelta) == "table" and data.investigationKnowledgeDelta or {}
    S.protocolModels = type(data.protocolModels) == "table" and data.protocolModels or {}
    S.protocolModelCount = 0
    for _ in pairs(S.protocolModels) do S.protocolModelCount = S.protocolModelCount + 1 end
    S.argumentFields = type(data.argumentFields) == "table" and data.argumentFields or {}
    S.argumentFieldCount = 0
    for _ in pairs(S.argumentFields) do S.argumentFieldCount = S.argumentFieldCount + 1 end
    S.repeatCounts = type(data.repeatCounts) == "table" and data.repeatCounts or {}
    S.repeatKeyCount = 0
    for _ in pairs(S.repeatCounts) do S.repeatKeyCount = S.repeatKeyCount + 1 end
end

local function restoreInflight(data)
    if type(data) ~= "table" or tostring(data.runId or "") ~= tostring(S.runId or "") then return false end
    local index = tonumber(data.batchIndex)
    if not index then return false end
    if index <= S.batchIndex then
        clearInflight()
        return false
    end
    if index ~= S.batchIndex + 1 then
        noteUploadError("inflight_sequence", "inflight_index_mismatch", index)
        return false
    end
    local itemCount = math.max(0, math.floor(tonumber(data.itemCount) or 0))
    if itemCount < 1 or itemCount > #S.queue or type(data.body) ~= "string" then
        noteUploadError("inflight_restore", "inflight_cache_mismatch", index)
        return false
    end
    S.pendingSend = {
        index = index,
        start = 1,
        stop = itemCount,
        bytes = tonumber(data.payloadBytes) or 0,
        body = data.body,
    }
    S.inflightRestored = true
    return true
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

local function rememberRecentValue(path, eventValue, observedAfterValue)
    path = tostring(path)
    local activity = (tonumber(S.valueActivity[path]) or 0) + 1
    S.valueActivity[path] = activity
    S.recentValueChanges[#S.recentValueChanges + 1] = {
        path = path, eventValue = eventValue, observedAfterValue = observedAfterValue,
        clock = os.clock() - S.startClock, activityCount = activity,
    }
    while #S.recentValueChanges > C.RECENT_VALUE_CAP do table.remove(S.recentValueChanges, 1) end
end

local function compactToolState()
    local out = {}
    local function add(container, label)
        if not container then return end
        local ok, children = pcall(function() return container:GetChildren() end)
        if not ok then return end
        for _, x in ipairs(children) do
            if x:IsA("Tool") then
                out[#out + 1] = { container = label, name = x.Name, attributes = attrs(x) }
                if #out >= 20 then return end
            end
        end
    end
    add(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    if #out < 20 then add(LP.Character, "Character") end
    return out
end

local function compactDeepState()
    local rare, background = {}, {}
    for i = #S.recentValueChanges, 1, -1 do
        local row = S.recentValueChanges[i]
        local currentActivity = tonumber(S.valueActivity[row.path]) or tonumber(row.activityCount) or 0
        if currentActivity <= C.RECENT_VALUE_NOISY_AFTER then
            rare[#rare + 1] = row
        elseif #background < C.RECENT_VALUE_BACKGROUND_CAP then
            background[#background + 1] = row
        end
        if #rare >= C.RECENT_VALUE_SNAPSHOT_CAP then break end
    end

    local selected = {}
    for _, row in ipairs(rare) do selected[#selected + 1] = row end
    for _, row in ipairs(background) do
        if #selected >= C.RECENT_VALUE_SNAPSHOT_CAP then break end
        selected[#selected + 1] = row
    end
    table.sort(selected, function(a, b) return (a.clock or 0) < (b.clock or 0) end)

    local recent = {}
    local first = math.max(1, #selected - C.RECENT_VALUE_SNAPSHOT_CAP + 1)
    for i = first, #selected do recent[#recent + 1] = selected[i] end
    if #recent == 0 then
        local fallbackFirst = math.max(1, #S.recentValueChanges - C.RECENT_VALUE_SNAPSHOT_CAP + 1)
        for i = fallbackFirst, #S.recentValueChanges do recent[#recent + 1] = S.recentValueChanges[i] end
    end

    local guiRecent = {}
    local guiFirst = math.max(1, #S.recentGuiChanges - 15)
    for i = guiFirst, #S.recentGuiChanges do guiRecent[#guiRecent + 1] = S.recentGuiChanges[i] end
    local ch = LP.Character
    return {
        player = playerContext(true), playerAttributes = attrs(LP),
        characterAttributes = ch and attrs(ch) or nil, tools = compactToolState(),
        recentValues = recent, recentGui = guiRecent, recentRefs = contextRefs(),
    }
end


local function compactInvestigationCondition()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local guiTail = {}
    local first = math.max(1, #S.recentGuiChanges - 3)
    for i = first, #S.recentGuiChanges do guiTail[#guiTail + 1] = S.recentGuiChanges[i] end
    return {
        player = {
            state = hum and tostring(hum:GetState()) or nil,
            health = hum and hum.Health or nil,
            floor = hum and tostring(hum.FloorMaterial) or nil,
            position = root and ser(root.Position) or nil,
        },
        playerAttributes = attrs(LP),
        characterAttributes = ch and attrs(ch) or nil,
        tools = compactToolState(),
        recentGui = guiTail,
    }
end

local function conditionHash(context)
    return hashText("condition|" .. canon(context or {}, 0, {}, false))
end

local function opaqueDiagnostics(args, streamKey, force)
    local n = tonumber(args and args.n) or 0
    local hasBuffer = false
    for i = 1, math.min(n, C.MAX_ARGS) do
        if typeof(args[i]) == "buffer" then hasBuffer = true break end
    end
    if not hasBuffer then return nil end
    local count = (S.opaqueCounters[streamKey] or 0) + 1
    S.opaqueCounters[streamKey] = count
    if not force and count > 3 and count % 32 ~= 0 then return nil end
    local rows = {}
    for i = 1, math.min(n, C.MAX_ARGS) do
        if typeof(args[i]) == "buffer" then
            local info = bufferFingerprint(args[i])
            local key = streamKey .. "\31" .. tostring(i)
            local previous = S.opaquePrevious[key]
            rows[#rows + 1] = {
                index = i, fingerprint = info,
                previous = previous and {
                    sameLength = previous.length == info.length,
                    sameSample = previous.sampleHash == info.sampleHash,
                    headChanged = previous.headHex ~= info.headHex,
                    tailChanged = previous.tailHex ~= info.tailHex,
                    sampleChangedRatio = (function()
                        local a, b = tostring(previous.sampleHex or ""), tostring(info.sampleHex or "")
                        local bytes = math.min(math.floor(#a / 2), math.floor(#b / 2))
                        if bytes <= 0 then return nil end
                        local changed = 0
                        for j = 1, bytes do
                            local s = (j - 1) * 2 + 1
                            if string.sub(a, s, s + 1) ~= string.sub(b, s, s + 1) then changed = changed + 1 end
                        end
                        return math.floor((changed / bytes) * 1000 + 0.5) / 1000
                    end)(),
                } or nil,
                observation = count,
            }
            S.opaquePrevious[key] = {
                length = info.length, sampleHash = info.sampleHash, headHex = info.headHex, tailHex = info.tailHex,
            }
        end
    end
    if #rows > 0 then S.smartStats.opaqueSamples = (S.smartStats.opaqueSamples or 0) + 1 end
    return #rows > 0 and rows or nil
end

local function scheduleDeepProbe(r, triggerHash, triggerKind, semanticHash)
    if not S.running or S.stopping or pressureLevel() >= 2 then return end
    if S.deepProbeCount >= C.DEEP_PROBE_MAX then return end
    local remotePath = pathOf(r)
    local now = os.clock()
    local last = S.lastDeepProbeByRemote[remotePath] or 0
    if now - last < C.DEEP_PROBE_COOLDOWN then return end
    S.lastDeepProbeByRemote[remotePath] = now
    S.deepProbeCount = S.deepProbeCount + 1
    S.smartStats.deepProbes = (S.smartStats.deepProbes or 0) + 1
    S.coverage.deepProbes = (S.coverage.deepProbes or 0) + 1
    local probeId = S.deepProbeCount
    for phase, delaySeconds in ipairs(C.DEEP_PROBE_DELAYS) do
        task.delay(delaySeconds, function()
            if not S.running or S.stopping then return end
            enqueue("record", "deep_snapshot", {
                kind = "deep_snapshot", probeId = probeId, phase = phase, delay = delaySeconds,
                triggerKind = triggerKind, triggerHash = triggerHash, semanticHash = semanticHash,
                remote = remoteDesc(r), state = compactDeepState(),
            }, 98, false, nil, nil,
                hashText("deep\31" .. tostring(probeId) .. "\31" .. tostring(phase)), true)
        end)
    end
end

local investigatorUiRefresh
local setInvestigatorStage
local processInvestigationQueue
local inputShield
local INPUT_LOCK_ACTION = "CafeinaInvestigationInputLock"
local INPUT_LOCK_KEYS = {
    Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
    Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump,
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
    Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
    Enum.KeyCode.ButtonA, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2,
}

setInputQuarantine = function(enabled)
    enabled = enabled == true
    if S.inputQuarantine == enabled then
        if inputShield then inputShield.Visible = enabled end
        return
    end
    S.inputQuarantine = enabled
    pcall(function() ContextActionService:UnbindAction(INPUT_LOCK_ACTION) end)
    if enabled then
        S.smartStats.inputQuarantines = (S.smartStats.inputQuarantines or 0) + 1
        pcall(function()
            ContextActionService:BindActionAtPriority(
                INPUT_LOCK_ACTION,
                function() return Enum.ContextActionResult.Sink end,
                false,
                C.INPUT_LOCK_PRIORITY,
                table.unpack(INPUT_LOCK_KEYS)
            )
        end)
    end
    if inputShield then inputShield.Visible = enabled end
end

local function appendInvestigatorDiagnostic(stage, detail, inv, emitRecord)
    stage = tostring(stage or "unknown")
    detail = tostring(detail or "")
    local now = os.clock()

    S.investigatorStage = stage
    S.investigatorStageDetail = detail
    S.investigatorStageSince = now

    if not inv then return end

    inv.stage = stage
    inv.stageDetail = detail
    inv.stageSince = now
    inv.diagSeq = (tonumber(inv.diagSeq) or 0) + 1
    inv.diagnostics = type(inv.diagnostics) == "table" and inv.diagnostics or {}

    local row = {
        seq = inv.diagSeq,
        stage = stage,
        detail = string.sub(detail, 1, 180),
        clock = math.floor((now - S.startClock) * 1000 + 0.5) / 1000,
        state = S.investigatorState,
        mode = inv.mode,
        pressure = pressureLevel(),
        frameDtMs = math.floor((S.frameDt or 0) * 100000 + 0.5) / 100,
    }
    inv.diagnostics[#inv.diagnostics + 1] = row
    while #inv.diagnostics > C.INVESTIGATOR_DIAGNOSTIC_CAP do
        table.remove(inv.diagnostics, 1)
    end

    if emitRecord ~= false and S.running and not S.stopping then
        S.smartStats.investigatorDiagnostics = (S.smartStats.investigatorDiagnostics or 0) + 1
        enqueue("record", "investigator_diag", {
            kind = "investigator_diag",
            investigationId = inv.id,
            stage = row.stage,
            detail = row.detail,
            state = row.state,
            mode = row.mode,
            pressure = row.pressure,
            frameDtMs = row.frameDtMs,
            remote = inv.candidate and inv.candidate.remote and remoteDesc(inv.candidate.remote) or nil,
        }, 97, true, nil, nil,
            hashText("investigator_diag|" .. tostring(inv.id) .. "|" .. tostring(inv.diagSeq) .. "|" .. stage), true)
    end
end

local function probeYellowTransition(inv, stage, detail)
    if not inv then return end
    local ok, err = pcall(function()
        appendInvestigatorDiagnostic(stage, detail, inv, false)
    end)
    if not ok then
        S.lastInvestigatorError = "yellow_probe:" .. string.sub(tostring(err), 1, 220)
        S.smartStats.investigatorErrors = (S.smartStats.investigatorErrors or 0) + 1
    end
end

local function setInvestigatorState(state, reason)
    state = tostring(state or "GREEN")
    local inv = S.activeInvestigation

    S.investigatorState = state
    S.investigatorReason = tostring(reason or "")
    S.investigatorStateSince = os.clock()

    if state == "YELLOW" and inv then
        probeYellowTransition(inv, "yellow_state_set", "estado YELLOW definido")
        probeYellowTransition(inv, "yellow_before_quarantine", "antes de setInputQuarantine(false)")
    end

    local okInput, inputErr = pcall(function()
        setInputQuarantine(state == "RED" or state == "BLUE")
    end)
    if not okInput then
        if state == "YELLOW" and inv then
            probeYellowTransition(inv, "yellow_quarantine_error", tostring(inputErr))
        end
        error(inputErr, 0)
    end

    if state == "YELLOW" and inv then
        probeYellowTransition(inv, "yellow_after_quarantine", "setInputQuarantine(false) retornou")
    end

    if investigatorUiRefresh then
        if state == "YELLOW" and inv then
            probeYellowTransition(inv, "yellow_before_ui_defer", "antes de task.defer(UI)")
        end

        local okUi, uiErr = pcall(function()
            task.defer(investigatorUiRefresh)
        end)
        if not okUi then
            if state == "YELLOW" and inv then
                probeYellowTransition(inv, "yellow_ui_defer_error", tostring(uiErr))
            end
            error(uiErr, 0)
        end

        if state == "YELLOW" and inv then
            probeYellowTransition(inv, "yellow_after_ui_defer", "task.defer(UI) retornou")
        end
    elseif state == "YELLOW" and inv then
        probeYellowTransition(inv, "yellow_ui_missing", "investigatorUiRefresh=nil")
    end
end

setInvestigatorStage = function(stage, detail, inv, emitRecord)
    appendInvestigatorDiagnostic(stage, detail, inv, emitRecord)
    if investigatorUiRefresh then task.defer(investigatorUiRefresh) end
end

local function markInvestigatorError(inv, source, err)
    local message = string.sub(tostring(err or "unknown_error"), 1, 260)
    S.lastInvestigatorError = tostring(source or "unknown") .. ": " .. message
    S.smartStats.investigatorErrors = (S.smartStats.investigatorErrors or 0) + 1
    setInvestigatorStage("execute_error", S.lastInvestigatorError, inv, true)
end

local function compactErrorTrace(err)
    local message = tostring(err or "unknown_error")
    local traced = nil
    pcall(function()
        if debug and type(debug.traceback) == "function" then
            traced = debug.traceback(message, 2)
        end
    end)
    return string.sub(tostring(traced or message), 1, 520)
end

local function appendMenuHealthDiagnostic(kind, detail, severity, emitRecord)
    local now = os.clock()
    S.menuHealthDiagSeq = (tonumber(S.menuHealthDiagSeq) or 0) + 1
    local row = {
        seq = S.menuHealthDiagSeq,
        kind = tostring(kind or "status"),
        detail = string.sub(tostring(detail or ""), 1, 360),
        severity = tostring(severity or "info"),
        clock = math.floor((now - S.startClock) * 1000 + 0.5) / 1000,
        state = S.investigatorState,
        stage = S.investigatorStage,
        stageAgeMs = math.floor(math.max(0, now - (tonumber(S.investigatorStageSince) or now)) * 1000 + 0.5),
        activeInvestigationId = S.activeInvestigation and S.activeInvestigation.id or nil,
        queueDepth = #S.investigationQueue,
        inputQuarantine = S.inputQuarantine == true,
        uploading = S.uploading == true,
        pressure = pressureLevel(),
        frameDtMs = math.floor((S.frameDt or 0) * 100000 + 0.5) / 100,
    }
    S.menuHealthDiagnostics[#S.menuHealthDiagnostics + 1] = row
    while #S.menuHealthDiagnostics > C.MENU_HEALTH_DIAGNOSTIC_CAP do
        table.remove(S.menuHealthDiagnostics, 1)
    end

    if emitRecord == true and S.running and not S.stopping then
        enqueue("record", "menu_health_diag", {
            kind = "menu_health_diag",
            diagnostic = row,
        }, severity == "error" and 100 or 97, true, nil, nil,
            hashText("menu_health|" .. tostring(row.seq) .. "|" .. row.kind), true)
    end
    return row
end

local function menuHealthTail(limit)
    local out = {}
    local rows = S.menuHealthDiagnostics
    local first = math.max(1, #rows - math.max(1, tonumber(limit) or 24) + 1)
    for i = first, #rows do out[#out + 1] = rows[i] end
    return out
end

local function menuHealthWatchdogTick()
    local now = os.clock()
    if now - (tonumber(S.menuHealthLastCheck) or 0) < C.MENU_HEALTH_CHECK_INTERVAL then return end
    S.menuHealthLastCheck = now
    S.smartStats.menuHealthChecks = (S.smartStats.menuHealthChecks or 0) + 1

    local active = S.activeInvestigation ~= nil
    local queueDepth = #S.investigationQueue
    local state = tostring(S.investigatorState or "GREEN")
    local stage = tostring(S.investigatorStage or "idle")
    local stageAge = math.max(0, now - (tonumber(S.investigatorStageSince) or now))
    local statusSignature = table.concat({
        state, stage, active and "1" or "0", tostring(queueDepth),
        S.inputQuarantine and "1" or "0", S.uploading and "1" or "0",
    }, "|")

    if statusSignature ~= S.menuHealthLastStatus then
        S.menuHealthLastStatus = statusSignature
        appendMenuHealthDiagnostic("status_change",
            "state=" .. state .. " stage=" .. stage .. " active=" .. tostring(active) ..
            " queue=" .. tostring(queueDepth) .. " quarantine=" .. tostring(S.inputQuarantine == true),
            "info", false)
    end

    local issues = {}
    if not active and state ~= "GREEN" then issues[#issues + 1] = "state_without_active" end
    if active and state == "GREEN" then issues[#issues + 1] = "active_without_state" end

    local expectedQuarantine = state == "RED" or state == "BLUE"
    if S.inputQuarantine ~= expectedQuarantine then
        issues[#issues + 1] = "quarantine_mismatch"
    end

    local stuckLimit = nil
    if state == "YELLOW" then stuckLimit = C.MENU_HEALTH_YELLOW_STUCK
    elseif state == "RED" then stuckLimit = C.MENU_HEALTH_RED_STUCK
    elseif state == "BLUE" then stuckLimit = C.MENU_HEALTH_BLUE_STUCK end
    if active and stuckLimit and stageAge > stuckLimit then
        issues[#issues + 1] = "stage_stuck:" .. stage
    end

    if queueDepth > 0 and not active then
        local oldest = S.investigationQueue[1]
        local queuedAt = oldest and tonumber(oldest.queuedAt) or now
        local queueAge = math.max(0, now - queuedAt)
        if queueAge > C.MENU_HEALTH_QUEUE_STUCK and now > (tonumber(S.investigationNextStartAt) or 0) + 0.5 then
            issues[#issues + 1] = "queue_waiting_without_active:" ..
                tostring(math.floor(queueAge * 1000 + 0.5)) .. "ms"
        end
    end

    local lastError = tostring(S.lastInvestigatorError or "")
    if lastError ~= "" and lastError ~= tostring(S.menuHealthLastError or "") then
        S.menuHealthLastError = lastError
        appendMenuHealthDiagnostic("investigator_error_seen", lastError, "error", true)
    end

    local anomalySignature = #issues > 0 and table.concat(issues, ",") or nil
    if anomalySignature ~= S.menuHealthLastAnomaly then
        if anomalySignature then
            S.smartStats.menuHealthAnomalies = (S.smartStats.menuHealthAnomalies or 0) + 1
            appendMenuHealthDiagnostic("health_anomaly", anomalySignature, "error", true)
        elseif S.menuHealthLastAnomaly then
            appendMenuHealthDiagnostic("health_recovered", tostring(S.menuHealthLastAnomaly), "info", false)
        end
        S.menuHealthLastAnomaly = anomalySignature
    end
end

local function rememberGuiChange(kind, inst, state)
    local row = {
        kind = tostring(kind), path = pathOf(inst), className = inst.ClassName,
        state = ser(state), clock = os.clock() - S.startClock,
    }
    S.recentGuiChanges[#S.recentGuiChanges + 1] = row
    while #S.recentGuiChanges > C.RECENT_GUI_CAP do table.remove(S.recentGuiChanges, 1) end
end

local function stateMapDiff(before, after, cap)
    before = type(before) == "table" and before or {}
    after = type(after) == "table" and after or {}
    local keys, seen = {}, {}
    for k in pairs(before) do seen[tostring(k)] = true end
    for k in pairs(after) do seen[tostring(k)] = true end
    for k in pairs(seen) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, key in ipairs(keys) do
        local a, b = before[key], after[key]
        if canon(a, 0, {}, false) ~= canon(b, 0, {}, false) then
            out[#out + 1] = { key = key, before = a, after = b }
            if #out >= (cap or 24) then break end
        end
    end
    return out
end

local function toolKey(row)
    return tostring(row and row.container or "?") .. "|" .. tostring(row and row.name or "?")
end

local function stateDiff(before, after, sinceClock)
    before = type(before) == "table" and before or {}
    after = type(after) == "table" and after or {}
    local bTools, aTools = {}, {}
    for _, row in ipairs(type(before.tools) == "table" and before.tools or {}) do bTools[toolKey(row)] = row end
    for _, row in ipairs(type(after.tools) == "table" and after.tools or {}) do aTools[toolKey(row)] = row end
    local added, removed = {}, {}
    for key, row in pairs(aTools) do if not bTools[key] then added[#added + 1] = row end end
    for key, row in pairs(bTools) do if not aTools[key] then removed[#removed + 1] = row end end
    local recentValues = {}
    for _, row in ipairs(type(after.recentValues) == "table" and after.recentValues or {}) do
        if (tonumber(row.clock) or 0) >= (tonumber(sinceClock) or 0) then recentValues[#recentValues + 1] = row end
    end
    local recentGui = {}
    for _, row in ipairs(type(after.recentGui) == "table" and after.recentGui or {}) do
        if (tonumber(row.clock) or 0) >= (tonumber(sinceClock) or 0) then recentGui[#recentGui + 1] = row end
    end
    local bp, ap = before.player or {}, after.player or {}
    local positionDelta = nil
    if type(bp.position) == "table" and type(ap.position) == "table" and bp.position.x and ap.position.x then
        local dx = (ap.position.x or 0) - (bp.position.x or 0)
        local dy = (ap.position.y or 0) - (bp.position.y or 0)
        local dz = (ap.position.z or 0) - (bp.position.z or 0)
        positionDelta = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) * 1000 + 0.5) / 1000
    end
    return {
        playerAttributes = stateMapDiff(before.playerAttributes, after.playerAttributes, 24),
        characterAttributes = stateMapDiff(before.characterAttributes, after.characterAttributes, 24),
        toolsAdded = added, toolsRemoved = removed,
        healthBefore = bp.health, healthAfter = ap.health,
        stateBefore = bp.state, stateAfter = ap.state,
        positionDelta = positionDelta,
        recentValues = recentValues, recentGui = recentGui,
    }
end

local function investigationImpact(diff)
    diff = type(diff) == "table" and diff or {}
    local score = 0
    score = score + math.min(24, #(diff.recentValues or {}) * 6)
    score = score + math.min(20, (#(diff.toolsAdded or {}) + #(diff.toolsRemoved or {})) * 8)
    score = score + math.min(18, (#(diff.playerAttributes or {}) + #(diff.characterAttributes or {})) * 5)
    score = score + math.min(12, #(diff.recentGui or {}) * 3)
    if diff.healthBefore ~= diff.healthAfter then score = score + 15 end
    if diff.stateBefore ~= diff.stateAfter then score = score + 8 end
    return math.clamp(score, 0, 100)
end

local function replayCloneValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 3 then return false, nil end
    local t = typeof(v)
    if v == nil or t == "boolean" then return true, v end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return false, nil end
        return true, v
    end
    if t == "string" then
        if #v > 256 then return false, nil end
        return true, v
    end
    if t == "Vector2" or t == "Vector3" or t == "CFrame" or t == "Color3" or t == "UDim2" or t == "EnumItem" then
        return true, v
    end
    if t ~= "table" or seen[v] then return false, nil end
    local okMeta, meta = pcall(getmetatable, v)
    if not okMeta or meta ~= nil then return false, nil end
    seen[v] = true
    local out, count = {}, 0
    for k, item in pairs(v) do
        count = count + 1
        if count > 32 then seen[v] = nil return false, nil end
        local kt = typeof(k)
        if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then seen[v] = nil return false, nil end
        local okItem, copied = replayCloneValue(item, depth + 1, seen)
        if not okItem then seen[v] = nil return false, nil end
        out[k] = copied
    end
    seen[v] = nil
    return true, out
end

local function cloneReplayArgs(args)
    local n = tonumber(args and args.n) or 0
    if n > C.ACTIVE_TEST_MAX_ARGS then return nil, "too_many_args" end
    local out = { n = n }
    for i = 1, n do
        local ok, copied = replayCloneValue(args[i], 0, {})
        if not ok then return nil, "unsupported_arg_" .. tostring(i) end
        out[i] = copied
    end
    return out
end

local function sideEffectReason(candidate)
    if candidate.method ~= "FireServer" then return "not_fire_server" end
    if (tonumber(candidate.importance) or 0) > C.ACTIVE_TEST_MAX_IMPORTANCE then return "high_importance" end
    if (tonumber(S.remoteImpact[candidate.remotePath]) or 0) >= 12 then return "learned_impact" end
    local prior = S.profileInvestigation[candidate.key]
    if type(prior) == "table" and (tonumber(prior.activeTests) or 0) >= 2 then return "already_learned" end
    for _, row in pairs(S.correlationEvidence) do
        if row.remote == candidate.remotePath and
            (row.semantic == candidate.semanticHash or row.shape == candidate.shapeHash) and
            (tonumber(row.support) or 0) > 0 then
            local effect = tostring(row.effect or "")
            if string.sub(effect, 1, 6) == "value:" or string.sub(effect, 1, 5) == "tool:" or
                string.sub(effect, 1, 10) == "attribute:" or string.sub(effect, 1, 10) == "character:" or
                string.find(effect, "runtime_added:Tool:", 1, true) then
                return "stateful_effect"
            end
        end
    end
    return nil
end

local function investigatorStable()
    if pressureLevel() >= 2 then return false, "pressure" end
    local ch = LP.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return false, "character_unavailable" end
    if hum.MoveDirection.Magnitude > 0.05 or root.AssemblyLinearVelocity.Magnitude > 3.5 then return false, "player_moving" end
    if S.frameDt > 0.055 then return false, "frame_pressure" end
    return true
end

local function knowledgeDeltaRow(key)
    local row = S.investigationKnowledgeDelta[key]
    if not row then
        if (function() local n = 0 for _ in pairs(S.investigationKnowledgeDelta) do n = n + 1 end return n end)() >= C.DELTA_INVESTIGATION_CAP then
            return nil
        end
        row = { key = key, observations = 0, activeTests = 0, completed = 0, passiveOnly = 0, cancelled = 0 }
        S.investigationKnowledgeDelta[key] = row
    end
    return row
end

local function recordKnowledge(candidate, field, amount, extra)
    local row = knowledgeDeltaRow(candidate.key)
    if not row then return end
    row[field] = (tonumber(row[field]) or 0) + (amount or 1)
    if type(extra) == "table" then
        for k, v in pairs(extra) do row[k] = v end
    end
end

local function finishActiveInvestigation(status, reason)
    local inv = S.activeInvestigation
    if not inv then
        setInvestigatorState("GREEN", "livre")
        return
    end
    S.investigationEpoch = S.investigationEpoch + 1
    setInvestigatorStage(status == "cancelled" and "cancelled" or "finishing", tostring(reason or ""), inv, true)
    local after = compactDeepState()
    local diff = stateDiff(inv.beforeState or inv.detectedState, after, inv.startedRelative)
    local impact = investigationImpact(diff)
    if inv.candidate and inv.candidate.remotePath then
        S.remoteImpact[inv.candidate.remotePath] = math.max(tonumber(S.remoteImpact[inv.candidate.remotePath]) or 0, impact * 0.22)
    end
    if status == "cancelled" then
        S.smartStats.investigationsCancelled = (S.smartStats.investigationsCancelled or 0) + 1
        recordKnowledge(inv.candidate, "cancelled", 1, { status = "cancelled", lastReason = reason, lastImpact = impact })
    else
        S.smartStats.investigationsCompleted = (S.smartStats.investigationsCompleted or 0) + 1
        local outcomeHash = hashText(canon(diff, 0, {}, false))
        local knowledge = knowledgeDeltaRow(inv.candidate.key)
        local sameOutcome = knowledge and knowledge.lastOutcome == outcomeHash
        local confirmations = sameOutcome and ((tonumber(knowledge.outcomeConfirmations) or 1) + 1) or 1
        recordKnowledge(inv.candidate, "completed", 1, {
            status = inv.mode == "active" and "tested" or "passive",
            lastReason = reason, lastImpact = impact,
            lastOutcome = outcomeHash,
            outcomeConfirmations = confirmations,
            outcomeStage = confirmations >= 2 and "confirmed" or "observed",
        })
    end
    local bundle = {
        kind = "investigation_bundle", investigationId = inv.id, status = status,
        mode = inv.mode, reason = reason, candidate = {
            key = inv.candidate.key, remote = remoteDesc(inv.candidate.remote),
            method = inv.candidate.method, shapeHash = inv.candidate.shapeHash,
            semanticHash = inv.candidate.semanticHash, importance = inv.candidate.importance,
            triggerContext = inv.candidate.triggerContext,
            relationStage = inv.candidate.relationStage,
            queuedAt = inv.candidate.queuedRelative,
            payload = packed(inv.candidate.replayArgs),
        },
        conditions = {
            queued = inv.candidate.queuedContext,
            started = inv.conditionAtStart,
            beforeTest = inv.conditionBeforeTest,
            queuedHash = inv.candidate.queuedContextHash,
            startedHash = inv.conditionAtStartHash,
            beforeTestHash = inv.conditionBeforeTestHash,
            queuedToStartSame = inv.candidate.queuedContextHash == inv.conditionAtStartHash,
            queuedToTestSame = inv.conditionBeforeTestHash and
                inv.candidate.queuedContextHash == inv.conditionBeforeTestHash or nil,
        },
        prelude = inv.prelude, detectedState = inv.detectedState,
        before = inv.beforeState, middle = inv.middleState, after = after,
        diff = diff, impact = impact, timeline = timelineSnapshot(inv.startedRelative),
        execution = inv.execution,
        diagnostics = inv.diagnostics,
        menuHealth = menuHealthTail(24),
        finalStage = inv.stage,
        finalStageDetail = inv.stageDetail,
    }
    S.activeInvestigation = nil
    setInvestigatorState("GREEN", status == "cancelled" and "cancelado" or "livre")
    S.investigatorStage = "idle"
    S.investigatorStageDetail = status == "cancelled" and "cancelado" or "livre"
    S.investigatorStageSince = os.clock()
    if S.running and not S.stopping then
        enqueue("record", "investigation_bundle", bundle, 100, true, nil, nil,
            hashText("bundle|" .. tostring(inv.id) .. "|" .. tostring(status)), true)
    end
    S.investigationNextStartAt = os.clock() + 0.35
end

local function cancelActiveInvestigation(reason)
    if not S.activeInvestigation then
        setInputQuarantine(false)
        setInvestigatorState("GREEN", "livre")
        return
    end
    finishActiveInvestigation("cancelled", tostring(reason or "manual"))
end

local function beginBluePhase(inv, reason)
    if S.activeInvestigation ~= inv then return end
    inv.blueStarted = os.clock()
    inv.lastRelevantClock = os.clock()
    setInvestigatorState("BLUE", reason or "observando resultado")
    setInvestigatorStage("blue_observing", reason or "observando resultado", inv, true)
    task.delay(1.0, function()
        if S.activeInvestigation == inv then inv.middleState = compactDeepState() end
    end)
    task.spawn(function()
        while S.activeInvestigation == inv and S.running and not S.stopping do
            local elapsed = os.clock() - inv.blueStarted
            local idle = os.clock() - (inv.lastRelevantClock or inv.blueStarted)
            if elapsed >= C.INVESTIGATOR_BLUE_MAX or
                (elapsed >= C.INVESTIGATOR_BLUE_MIN and idle >= C.INVESTIGATOR_BLUE_IDLE) then
                finishActiveInvestigation("completed", inv.mode == "active" and "active_test_complete" or "passive_observation_complete")
                return
            end
            task.wait(0.20)
        end
    end)
end

local function executeCandidate(inv)
    if S.activeInvestigation ~= inv or not S.running or S.stopping then return end
    setInvestigatorStage("execute_entered", "avaliando risco", inv, true)

    local risk = sideEffectReason(inv.candidate)
    if risk then
        setInvestigatorStage("risk_blocked", risk, inv, true)
        inv.mode = "passive"
        S.smartStats.investigationsPassive = (S.smartStats.investigationsPassive or 0) + 1
        S.smartStats.investigationsBlocked = (S.smartStats.investigationsBlocked or 0) + 1
        recordKnowledge(inv.candidate, "passiveOnly", 1, { status = "blocked", lastReason = risk })
        beginBluePhase(inv, "observação segura")
        return
    end

    setInvestigatorStage("risk_clear", "avaliando estabilidade", inv, true)
    local stable, why = investigatorStable()
    local yellowElapsed = os.clock() - inv.yellowStarted
    setInvestigatorStage("stability_checked",
        stable and "estável" or ("instável:" .. tostring(why or "unknown")),
        inv, true)
    if not stable and yellowElapsed < C.INVESTIGATOR_YELLOW_MAX then
        S.investigatorReason = "aguardando estabilidade"
        setInvestigatorStage("yellow_retry_wait", tostring(why or "instável"), inv, true)
        if investigatorUiRefresh then task.defer(investigatorUiRefresh) end
        task.delay(0.25, function()
            if S.activeInvestigation ~= inv then return end
            setInvestigatorStage("yellow_retry_fired", "retry disparou", inv, true)
            local ok, err = pcall(function() executeCandidate(inv) end)
            if not ok and S.activeInvestigation == inv then
                markInvestigatorError(inv, "yellow_retry", err)
            end
        end)
        return
    elseif not stable then
        setInvestigatorStage("passive_selected", "ambiente instável:" .. tostring(why or "unknown"), inv, true)
        inv.mode = "passive"
        S.smartStats.investigationsPassive = (S.smartStats.investigationsPassive or 0) + 1
        S.smartStats.investigationsBlocked = (S.smartStats.investigationsBlocked or 0) + 1
        recordKnowledge(inv.candidate, "passiveOnly", 1, { status = "blocked", lastReason = why })
        beginBluePhase(inv, "ambiente instável")
        return
    end

    inv.mode = "active"
    inv.conditionBeforeTest = compactInvestigationCondition()
    inv.conditionBeforeTestHash = conditionHash(inv.conditionBeforeTest)
    inv.beforeState = compactDeepState()
    inv.startedRelative = os.clock() - S.startClock
    setInvestigatorStage("red_prepare", "entrando no teste", inv, true)
    setInvestigatorState("RED", "teste automático")
    task.delay(C.INVESTIGATOR_RED_SETTLE, function()
        if S.activeInvestigation ~= inv or not S.running or S.stopping then return end
        setInvestigatorStage("red_settle_fired", "preparando chamada", inv, true)
        local remote = inv.candidate.remote
        if typeof(remote) ~= "Instance" or remote.Parent == nil or remote.ClassName ~= "RemoteEvent" then
            inv.execution = { ok = false, error = "remote_unavailable" }
            beginBluePhase(inv, "remote indisponível")
            return
        end
        local registry = S.outboundHookRegistry
        if type(registry) == "table" then registry.syntheticToken = inv.id end
        setInvestigatorStage("fire_call_started", "FireServer controlado", inv, true)
        local ok, err = pcall(function()
            remote:FireServer(table.unpack(inv.candidate.replayArgs, 1, inv.candidate.replayArgs.n))
        end)
        if type(registry) == "table" then registry.syntheticToken = nil end
        inv.execution = { ok = ok, error = ok and nil or tostring(err) }
        setInvestigatorStage("fire_call_finished", ok and "chamada concluída" or ("falha:" .. tostring(err)), inv, true)
        S.smartStats.investigationsActive = (S.smartStats.investigationsActive or 0) + 1
        recordKnowledge(inv.candidate, "activeTests", 1, { status = ok and "tested" or "error" })
        task.delay(0.12, function()
            if S.activeInvestigation == inv then beginBluePhase(inv, ok and "observando resultado" or "observando falha") end
        end)
    end)
end

local function startInvestigationCandidate(candidate)
    if not S.running or S.stopping or S.activeInvestigation then return end
    S.investigationSeq = S.investigationSeq + 1
    S.investigationCount = S.investigationCount + 1
    local startCondition = compactInvestigationCondition()
    local inv = {
        id = S.investigationSeq, candidate = candidate, mode = "pending",
        yellowStarted = os.clock(), startedRelative = os.clock() - S.startClock,
        prelude = timelineSnapshot(), detectedState = compactDeepState(),
        conditionAtStart = startCondition, conditionAtStartHash = conditionHash(startCondition),
        lastRelevantClock = os.clock(), diagnostics = {}, diagSeq = 0,
    }
    S.activeInvestigation = inv
    local stateOk, stateErr = pcall(function()
        setInvestigatorState("YELLOW", "nova interação • pare de mexer")
    end)
    if not stateOk then
        markInvestigatorError(inv, "yellow_state_transition", stateErr)
        return
    end
    setInvestigatorStage("yellow_timer_scheduled",
        "aguardando " .. tostring(C.INVESTIGATOR_YELLOW_SECONDS) .. "s", inv, true)
    task.delay(C.INVESTIGATOR_YELLOW_SECONDS, function()
        if S.activeInvestigation ~= inv then return end
        setInvestigatorStage("yellow_timer_fired", "timer disparou", inv, true)
        local ok, err = pcall(function() executeCandidate(inv) end)
        if not ok and S.activeInvestigation == inv then
            markInvestigatorError(inv, "yellow_timer", err)
        end
    end)
end

local function queueInvestigationCandidate(remote, method, args, shapeHash, semanticHash, importance, triggerContext)
    if not S.running or S.stopping or pressureLevel() >= 2 then return end
    if S.investigationCount + #S.investigationQueue >= C.INVESTIGATOR_MAX_PER_SESSION then return end
    if method ~= "FireServer" or remote.ClassName ~= "RemoteEvent" then return end
    local replayArgs, cloneErr = cloneReplayArgs(args)
    if not replayArgs then return end
    local remotePath = pathOf(remote)
    local key = hashText("action|" .. remotePath .. "|" .. tostring(method) .. "|" .. tostring(semanticHash or shapeHash))
    S.actionSeenCounts[key] = (S.actionSeenCounts[key] or 0) + 1
    local relationStage = relationStageForCandidate(remotePath, shapeHash, semanticHash)
    recordKnowledge({ key = key }, "observations", 1, {
        status = "observed",
        relationStage = relationStage,
    })
    if relationStage == "confirmed" and S.actionSeenCounts[key] > 1 then
        S.smartStats.investigationsConfirmedSkipped =
            (S.smartStats.investigationsConfirmedSkipped or 0) + 1
        return
    end
    if S.investigationQueuedKeys[key] then return end
    if S.activeInvestigation and S.activeInvestigation.candidate and S.activeInvestigation.candidate.key == key then return end
    local last = S.investigationLastByKey[key] or 0
    if os.clock() - last < C.INVESTIGATOR_COOLDOWN then return end
    local prior = S.profileInvestigation[key]
    if type(prior) == "table" and (tonumber(prior.activeTests) or 0) >= 2 then return end

    local queuedAt = os.clock()
    local queuedContext = compactInvestigationCondition()
    local candidate = {
        key = key, remote = remote, remotePath = remotePath, method = method,
        replayArgs = replayArgs, shapeHash = shapeHash, semanticHash = semanticHash,
        importance = importance, cloneError = cloneErr, triggerContext = triggerContext,
        relationStage = relationStage,
        queuedAt = queuedAt, queuedRelative = queuedAt - S.startClock,
        queuedContext = queuedContext, queuedContextHash = conditionHash(queuedContext),
    }
    if #S.investigationQueue >= C.INVESTIGATOR_QUEUE_CAP then return end
    S.investigationLastByKey[key] = os.clock()
    S.investigationQueuedKeys[key] = true
    S.investigationQueue[#S.investigationQueue + 1] = candidate
    S.smartStats.investigationsQueued = (S.smartStats.investigationsQueued or 0) + 1
end

processInvestigationQueue = function()
    if not S.running or S.stopping or S.activeInvestigation then return end
    if os.clock() < (tonumber(S.investigationNextStartAt) or 0) then return end
    local candidate = table.remove(S.investigationQueue, 1)
    if not candidate then return end
    S.investigationQueuedKeys[candidate.key] = nil
    S.smartStats.menuHealthQueueStarts = (S.smartStats.menuHealthQueueStarts or 0) + 1
    appendMenuHealthDiagnostic("queue_start",
        "remote=" .. string.sub(tostring(candidate.remotePath or "?"), 1, 180) ..
        " ageMs=" .. tostring(math.floor(math.max(0, os.clock() - (tonumber(candidate.queuedAt) or os.clock())) * 1000 + 0.5)) ..
        " relation=" .. tostring(candidate.relationStage or "candidate"),
        "info", false)
    local ok, err = pcall(function()
        startInvestigationCandidate(candidate)
    end)
    if not ok then
        S.smartStats.menuHealthQueueErrors = (S.smartStats.menuHealthQueueErrors or 0) + 1
        S.lastInvestigatorError = "queue_worker: " .. string.sub(tostring(err), 1, 260)
        appendMenuHealthDiagnostic("queue_start_error", compactErrorTrace(err), "error", true)
    end
end

local function focusedRemoteContext(r, shapeHash, triggerKind, semanticHash)
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
        kind = "investigation_context", triggerShape = shapeHash, triggerKind = triggerKind or "shape",
        semanticHash = semanticHash, remote = remoteDesc(r),
        parent = parent and { path = pathOf(parent), attributes = attrs(parent), children = siblings } or nil,
        player = playerContext(true),
    }, 99, true, nil, nil,
        hashText("investigation\31" .. tostring(triggerKind or "shape") .. "\31" .. tostring(shapeHash)), true)
    scheduleDeepProbe(r, shapeHash, triggerKind or "shape", semanticHash)
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
            local semanticHash, newSemantic, semanticKey = semanticStatus(remotePath, "OnClientEvent", args, "in")
            local newShape = not S.profileShape[shapeHash]
            local investigating = (S.investigation[remotePath] or 0) > os.clock()
            local score = importanceScore(remotePath, "OnClientEvent", newShape, r.ClassName, newSemantic)
            modelProtocol("in", remotePath, "OnClientEvent", shapeHash, semanticHash)
            if newShape or newSemantic then observeArgumentFields(remotePath, "OnClientEvent", args, "in") end
            if newShape then bump(S.coverage, "newShapes") end
            if newSemantic then bump(S.coverage, "newSemanticPatterns") end
            if newShape or newSemantic or score >= C.FOCUS_SCORE then
                S.investigation[remotePath] = os.clock() + C.INVESTIGATION_SECONDS
                investigating = true
            end
            if score >= C.FOCUS_SCORE then
                S.smartStats.highInterestInbound = (S.smartStats.highInterestInbound or 0) + 1
                if score >= S.focusScore then S.focusRemote, S.focusScore = remotePath, score end
            end
            local deep = newShape or newSemantic or score >= C.FOCUS_SCORE
            local priority = newShape and 98 or (newSemantic and 94 or (investigating and 88 or math.max(78, score)))
            local data = {
                kind = "remote_inbound", remote = remoteDesc(r), payload = packed(args),
                schema = deep and packedSchema(args) or nil, semanticHash = semanticHash,
                newSemantic = newSemantic, opaque = opaqueDiagnostics(args, "in:" .. remotePath, deep),
                newShape = newShape, investigating = investigating, importance = score,
                player = deep and playerContext(false) or nil,
            }
            local accepted = enqueue("record", "remote_inbound", data, math.clamp(priority, 0, 100),
                newShape or newSemantic, newShape and "shape" or nil, newShape and shapeHash or nil, exactHash,
                deep or investigating)
            if accepted then
                if newSemantic then rememberSemantic(semanticHash, semanticKey) end
                if deep then
                    task.defer(function()
                        if S.running and not S.stopping then
                            focusedRemoteContext(r, newShape and shapeHash or semanticHash,
                                newShape and (newSemantic and "shape+semantic" or "shape") or "semantic", semanticHash)
                        end
                    end)
                end
            end
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
        local eventValue = ser(newValue)
        local observedAfterValue = nil
        pcall(function() observedAfterValue = ser(v.Value) end)
        rememberRecentValue(path, eventValue, observedAfterValue)
        enqueue("record", "value_changed", {
            kind = "value_changed", object = valueSnap(v), value = eventValue,
            eventValue = eventValue, observedAfterValue = observedAfterValue,
        }, 72, false, nil, nil, exact, false)
    end)
    S.conns[#S.conns + 1] = connection
end

--==============================================================--
-- PASSIVE OUTBOUND REMOTE OBSERVER
--==============================================================--

local OUTBOUND_HOOK_KEY = "__CAFEINA_V3_OUTBOUND_HOOK"
local OUTBOUND_HOOK_VERSION = 4

local function installOutboundObserver()
    if not HOOKMETAMETHOD or not GETNAMECALLMETHOD then
        S.coverage.outboundObserver = "unavailable"
        S.outboundHookReady = false
        return false
    end

    local registry = rawget(ENV, OUTBOUND_HOOK_KEY)

    -- Neutralize the V1 dispatcher before chaining a corrected hook over it.
    -- The old wrapper called Instance:IsA() inside __namecall before forwarding,
    -- which can disturb the active namecall method on some executors.
    if type(registry) == "table" and registry.installed == true and registry.version ~= OUTBOUND_HOOK_VERSION then
        registry.callback = nil
        registry = nil
    end

    if type(registry) ~= "table" or registry.installed ~= true then
        registry = { installed = false, callback = nil, version = OUTBOUND_HOOK_VERSION }
        local oldNamecall
        local function wrapper(self, ...)
            local method = GETNAMECALLMETHOD()
            local callback = registry.callback
            local className = typeof(self) == "Instance" and self.ClassName or nil
            local outboundRemote =
                className == "RemoteEvent" or className == "RemoteFunction" or className == "UnreliableRemoteEvent"

            if callback and outboundRemote and method == "InvokeServer" then
                local args = table.pack(...)
                local syntheticToken = registry.syntheticToken
                local startedAt = os.clock()
                local results = table.pack(oldNamecall(self, ...))
                local latencyMs = math.max(0, (os.clock() - startedAt) * 1000)
                task.defer(function() pcall(callback, self, method, args, results, latencyMs, syntheticToken) end)
                return table.unpack(results, 1, results.n)
            end

            if callback and outboundRemote and method == "FireServer" then
                local args = table.pack(...)
                local syntheticToken = registry.syntheticToken
                task.defer(function() pcall(callback, self, method, args, nil, nil, syntheticToken) end)
            end

            return oldNamecall(self, ...)
        end

        local wrapped = NEWCLOSURE and NEWCLOSURE(wrapper) or wrapper
        local ok, old = pcall(HOOKMETAMETHOD, game, "__namecall", wrapped)
        if not ok or type(old) ~= "function" then
            registry.callback = nil
            S.coverage.outboundObserver = "hook_failed"
            S.outboundHookReady = false
            return false
        end
        oldNamecall = old
        registry.installed = true
        registry.version = OUTBOUND_HOOK_VERSION
        rawset(ENV, OUTBOUND_HOOK_KEY, registry)
    end

    registry.callback = function(remote, method, args, results, latencyMs, syntheticToken)
        if not S.running or S.stopping then return end
        task.defer(function()
            if not S.running or S.stopping then return end
            local remotePath = pathOf(remote)
            registerRemote(remote, "outbound")
            local shapeHash = hashText("remote_out_shape\31" .. remotePath .. "\31" .. method .. "\31" .. packedCanon(args, true))
            local semanticHash, newSemantic, semanticKey = semanticStatus(remotePath, method, args, "out")
            local responseShapeHash, newResponseShape = nil, false
            local responseSemanticHash, newResponseSemantic, responseSemanticKey = nil, false, nil
            if results then
                responseShapeHash = hashText("remote_return_shape\31" .. remotePath .. "\31" .. packedCanon(results, true))
                newResponseShape = not S.profileShape[responseShapeHash]
                responseSemanticHash, newResponseSemantic, responseSemanticKey = semanticStatus(remotePath, method, results, "return")
            end
            local exactParts = { "remote_out_value\31", remotePath, "\31", method, "\31", packedCanon(args, false) }
            if results then
                exactParts[#exactParts + 1] = "\31return\31"
                exactParts[#exactParts + 1] = packedCanon(results, false)
            end
            if syntheticToken then
                exactParts[#exactParts + 1] = "|investigation|"
                exactParts[#exactParts + 1] = tostring(syntheticToken)
            end
            local exactHash = hashText(table.concat(exactParts))
            local newShape = not S.profileShape[shapeHash]
            local score = importanceScore(remotePath, method, newShape, remote.ClassName,
                newSemantic, newResponseShape, newResponseSemantic)
            modelProtocol("out", remotePath, method, shapeHash, semanticHash)
            if newShape or newSemantic or newResponseShape or newResponseSemantic then
                observeArgumentFields(remotePath, method, args, "out")
                if results then observeArgumentFields(remotePath, method, results, "return") end
            end
            local focused = score >= C.FOCUS_SCORE
            local interactionContext = syntheticToken == nil and recentDirectInteraction(C.INTERACTION_CONTEXT_SECONDS) or nil
            local deep = syntheticToken ~= nil or focused or newShape or newSemantic or newResponseShape or newResponseSemantic
            S.smartStats.outboundObserved = (S.smartStats.outboundObserved or 0) + 1
            if focused then
                S.smartStats.highInterestOutbound = (S.smartStats.highInterestOutbound or 0) + 1
                if score >= S.focusScore then S.focusRemote, S.focusScore = remotePath, score end
            end
            if newShape then bump(S.coverage, "newOutboundShapes") end
            if newSemantic then bump(S.coverage, "newSemanticPatterns") end
            if newResponseShape then bump(S.coverage, "newOutboundResponseShapes") end
            if newResponseSemantic then bump(S.coverage, "newResponseSemanticPatterns") end
            if deep then S.investigation[remotePath] = os.clock() + C.INVESTIGATION_SECONDS end

            local record = {
                kind = "remote_outbound", method = method, remote = remoteDesc(remote),
                payload = packed(args), schema = deep and packedSchema(args) or nil,
                semanticHash = semanticHash, newSemantic = newSemantic,
                response = results and packed(results) or nil,
                responseSchema = results and packedSchema(results) or nil,
                responseShapeHash = responseShapeHash, newResponseShape = newResponseShape,
                responseSemanticHash = responseSemanticHash, newResponseSemantic = newResponseSemantic,
                invokeLatencyMs = latencyMs and math.floor(latencyMs * 100 + 0.5) / 100 or nil,
                opaque = opaqueDiagnostics(args, "out:" .. remotePath, deep),
                responseOpaque = results and opaqueDiagnostics(results, "return:" .. remotePath, deep) or nil,
                newShape = newShape, investigating = deep, importance = score,
                automatedInvestigation = syntheticToken ~= nil,
                investigationId = syntheticToken,
                triggerContext = interactionContext,
                player = deep and playerContext(false) or nil,
            }
            local accepted = enqueue("record", "remote_outbound", record,
                math.clamp(math.max(82, score), 0, 100), newShape or newSemantic or newResponseShape or newResponseSemantic,
                newShape and "shape" or nil, newShape and shapeHash or nil, exactHash, deep)
            if accepted then
                S.smartStats.outboundAccepted = (S.smartStats.outboundAccepted or 0) + 1
                if newSemantic then rememberSemantic(semanticHash, semanticKey) end
                if newResponseShape then rememberShape(responseShapeHash) end
                if newResponseSemantic then rememberSemantic(responseSemanticHash, responseSemanticKey) end
                if deep then
                    local triggerHash = newShape and shapeHash or
                        (newSemantic and semanticHash or (newResponseShape and responseShapeHash or responseSemanticHash))
                    local triggerKind = newShape and (newSemantic and "shape+semantic" or "shape") or
                        (newSemantic and "semantic" or (newResponseShape and "response_shape" or
                            (newResponseSemantic and "response_semantic" or "focus")))
                    task.defer(function()
                        if S.running and not S.stopping then
                            focusedRemoteContext(remote, triggerHash or shapeHash, triggerKind, semanticHash)
                        end
                    end)
                end
            end
            if deep or interactionContext then
                openCorrelationWindow(remotePath, method, shapeHash, score, semanticHash)
            end
            if not syntheticToken and ((accepted and deep) or interactionContext) then
                queueInvestigationCandidate(remote, method, args, shapeHash, semanticHash, score, interactionContext)
            end
        end)
    end

    S.outboundHookRegistry = registry
    S.outboundHookReady = true
    S.coverage.outboundObserver = "active"
    S.coverage.outboundObserverVersion = OUTBOUND_HOOK_VERSION
    return true
end

local function disableOutboundObserver()
    local registry = S.outboundHookRegistry
    if type(registry) == "table" then registry.callback = nil end
    S.outboundHookRegistry = nil
    S.outboundHookReady = false
end

local function attachToolSignals(tool, label)
    if not tool or not tool:IsA("Tool") or S.toolSignals[tool] then return end
    S.toolSignals[tool] = true
    local function emit(kind)
        if not S.running or S.stopping then return end
        enqueue("record", "tool_signal", {
            kind = kind, container = label, tool = obj(tool, label), player = playerContext(false),
        }, 91, false, nil, nil,
            hashText("tool_signal|" .. kind .. "|" .. normalizedPath(tool) .. "|" .. tostring(math.floor((os.clock() - S.startClock) * 4))), true)
    end
    S.conns[#S.conns + 1] = tool.Equipped:Connect(function() emit("tool_equipped") end)
    S.conns[#S.conns + 1] = tool.Unequipped:Connect(function() emit("tool_unequipped") end)
    S.conns[#S.conns + 1] = tool.Activated:Connect(function() emit("tool_activated") end)
end

local function attachGuiSignals(inst)
    if not inst or S.guiSignals[inst] then return end
    if not (inst:IsA("GuiButton") or inst:IsA("ScreenGui")) then return end
    S.guiSignals[inst] = true
    if inst:IsA("GuiButton") then
        S.conns[#S.conns + 1] = inst.Activated:Connect(function()
            if not S.running or S.stopping then return end
            enqueue("record", "gui_interaction", {
                kind = "gui_activated", gui = obj(inst, "PlayerGui"), player = playerContext(false),
            }, 94, false, nil, nil, nil, true)
        end)
        S.conns[#S.conns + 1] = inst:GetPropertyChangedSignal("Visible"):Connect(function()
            if not S.running or S.stopping then return end
            local state = inst.Visible
            rememberGuiChange("visible", inst, state)
            enqueue("record", "gui_state", {
                kind = "gui_state", state = "visible", value = state,
                gui = { path = pathOf(inst), name = inst.Name, className = inst.ClassName },
            }, 68, false, nil, nil,
                hashText("gui_visible|" .. normalizedPath(inst) .. "|" .. tostring(state)), false)
        end)
    else
        S.conns[#S.conns + 1] = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not S.running or S.stopping then return end
            local state = inst.Enabled
            rememberGuiChange("enabled", inst, state)
            enqueue("record", "gui_state", {
                kind = "gui_state", state = "enabled", value = state,
                gui = { path = pathOf(inst), name = inst.Name, className = inst.ClassName },
            }, 70, false, nil, nil,
                hashText("gui_enabled|" .. normalizedPath(inst) .. "|" .. tostring(state)), false)
        end)
    end
end

local toolState = {}
local function watchContainer(container, label)
    if not container then return end
    for _, x in ipairs(container:GetChildren()) do
        if x:IsA("Tool") then
            toolState[pathOf(x)] = label
            attachToolSignals(x, label)
        end
    end
    local added = container.ChildAdded:Connect(function(x)
        if not S.running or S.stopping or not x:IsA("Tool") then return end
        local p = pathOf(x)
        if toolState[p] == label then return end
        toolState[p] = label
        attachToolSignals(x, label)
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

local function runtimePatternDecision(x, source)
    local patternPath = normalizedPath(x)
    local patternHash = signature("runtime_pattern", tostring(source) .. ":" .. patternPath, {
        className = x.ClassName, name = normalizeDynamicSegment(x.Name),
    }, true)
    local count = (S.runtimePatternCounts[patternHash] or 0) + 1
    S.runtimePatternCounts[patternHash] = count
    local firstThisRun = not S.runtimePatternSeen[patternHash]
    S.runtimePatternSeen[patternHash] = true
    pruneCorrelationWindows()
    local active = #S.correlationWindows > 0
    local keep = firstThisRun or count <= C.RUNTIME_BURST_FIRST or count % C.RUNTIME_BURST_EVERY == 0 or
        (active and count % 4 == 0)
    local newPattern = firstThisRun and not S.profileLow[patternHash]
    return keep, newPattern, patternHash, count, active
end

local function recordRuntimeAdded(x, source, kind, priority)
    S.objectBorn[x] = os.clock()
    local keep, newPattern, patternHash, count, active = runtimePatternDecision(x, source)
    if not keep then bump(S.suppressed, "runtime_pattern"); return end
    local snapshot = obj(x, source)
    enqueue("record", "runtime_added", {
        kind = kind, object = snapshot,
        runtimePattern = { hash = patternHash, count = count, newPattern = newPattern },
    }, priority, newPattern, newPattern and "low" or nil, newPattern and patternHash or nil,
        signature("runtime_event", normalizedPath(x), { className = x.ClassName, name = normalizeDynamicSegment(x.Name) }, false),
        newPattern or active)
end

local function recordRuntimeRemoving(x, source, kind)
    local born = S.objectBorn[x]
    local lifetime = born and math.max(0, os.clock() - born) or nil
    S.objectBorn[x] = nil
    local exact = hashText("remove|" .. tostring(source) .. "|" .. normalizedPath(x) .. "|" .. x.ClassName ..
        "|" .. tostring(math.floor((lifetime or 0) * 10)))
    enqueue("record", "runtime_remove", {
        kind = kind, source = source, path = pathOf(x), name = x.Name, className = x.ClassName,
        attributes = attrs(x), lifetimeSeconds = lifetime and math.floor(lifetime * 1000 + 0.5) / 1000 or nil,
    }, 80, false, nil, nil, exact, false)
end

local function runtimeWatchers()
    installOutboundObserver()

    local ra = ReplicatedStorage.DescendantAdded:Connect(function(x)
        if not S.running or S.stopping then return end
        if isRemote(x) then
            registerRemote(x, "runtime_added")
            if x:IsA("RemoteEvent") or x:IsA("UnreliableRemoteEvent") then attachInbound(x) end
        elseif x:IsA("ValueBase") then
            attachValue(x)
            recordRuntimeAdded(x, "ReplicatedStorage", "replicated_added", 82)
        elseif x:IsA("Tool") or x:IsA("ProximityPrompt") then
            recordRuntimeAdded(x, "ReplicatedStorage", "replicated_added", 85)
        end
    end)
    S.conns[#S.conns + 1] = ra

    local rr = ReplicatedStorage.DescendantRemoving:Connect(function(x)
        if not S.running or S.stopping then return end
        if x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") then
            recordRuntimeRemoving(x, "ReplicatedStorage", "replicated_removing")
        end
    end)
    S.conns[#S.conns + 1] = rr

    local wa = Workspace.DescendantAdded:Connect(function(x)
        if not S.running or S.stopping then return end
        if x:IsA("ValueBase") then attachValue(x) end
        if x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then
            recordRuntimeAdded(x, "Workspace", "workspace_added", 82)
        end
    end)
    S.conns[#S.conns + 1] = wa

    local wr = Workspace.DescendantRemoving:Connect(function(x)
        if not S.running or S.stopping then return end
        if x:IsA("ValueBase") or x:IsA("Tool") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then
            recordRuntimeRemoving(x, "Workspace", "workspace_removing")
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
    S.conns[#S.conns + 1] = ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
        if not S.running or S.stopping then return end
        enqueue("record", "prompt_signal", {
            kind = "prompt_shown", prompt = obj(prompt, "shown"), inputType = tostring(inputType),
        }, 54, false, nil, nil,
            hashText("prompt_shown|" .. normalizedPath(prompt)), false)
    end)
    S.conns[#S.conns + 1] = ProximityPromptService.PromptHidden:Connect(function(prompt)
        if not S.running or S.stopping then return end
        enqueue("record", "prompt_signal", {
            kind = "prompt_hidden", prompt = { path = pathOf(prompt), name = prompt.Name },
        }, 46, false, nil, nil,
            hashText("prompt_hidden|" .. normalizedPath(prompt)), false)
    end)

    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        S.conns[#S.conns + 1] = pg.DescendantAdded:Connect(function(x)
            if S.running and not S.stopping then attachGuiSignals(x) end
        end)
        task.spawn(function()
            local roots = pg:GetChildren()
            local stack = {}
            for i = math.min(#roots, C.GUI_NODE_CAP), 1, -1 do stack[#stack + 1] = roots[i] end
            local visited, sliceStart = 0, os.clock()
            while #stack > 0 and visited < C.GUI_NODE_CAP and S.running and not S.stopping do
                local x = stack[#stack]
                stack[#stack] = nil
                visited = visited + 1
                attachGuiSignals(x)
                local ok, children = pcall(function() return x:GetChildren() end)
                if ok and #children > 0 then
                    local room = math.max(0, C.GUI_NODE_CAP - visited - #stack)
                    local take = math.min(#children, room)
                    for i = take, 1, -1 do stack[#stack + 1] = children[i] end
                end
                if visited % 80 == 0 or os.clock() - sliceStart >= C.SCAN_SLICE_MS then
                    task.wait()
                    sliceStart = os.clock()
                end
            end
        end)
    end

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
    disableOutboundObserver()
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
        local fingerprint = { className = inst.ClassName, name = normalizeDynamicSegment(inst.Name), attributes = a }
        if inst:IsA("ValueBase") then pcall(function() fingerprint.value = ser(inst.Value) end) end
        if inst:IsA("ProximityPrompt") then
            fingerprint.prompt = {
                actionText = inst.ActionText, objectText = inst.ObjectText, hold = inst.HoldDuration,
                distance = inst.MaxActivationDistance, lineOfSight = inst.RequiresLineOfSight,
            }
        end
        local h = signature("static", normalizedPath(inst), fingerprint, false)
        if S.profileLow[h] then
            bump(S.suppressed, "important_instance")
            return
        end
        local priority = (inst:IsA("Tool") or inst:IsA("ProximityPrompt")) and 72 or 58
        enqueue("record", "important_instance", { kind = "important_instance", object = obj(inst, label, a) }, priority,
            true, "low", h, nil, false)
    elseif inst:IsA("Folder") or inst:IsA("Model") or inst:IsA("Accessory") then
        local a = attrs(inst)
        local h = signature("structure", normalizedPath(inst), {
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
        local h = signature("nearby", normalizedPath(part), {
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
            attachGuiSignals(x)
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
            attachGuiSignals(x)
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

local function correlationEvidenceSummary()
    local rows = {}
    for _, row in pairs(S.correlationEvidence) do
        local metrics = correlationMetrics(row)
        rows[#rows + 1] = {
            remote = row.remote, method = row.method, shape = row.shape, semantic = row.semantic,
            effect = row.effect, support = row.support, distinctEffects = metrics.distinctEffects,
            trustedSupport = metrics.trustedSupport,
            baseline = metrics.baseline, effectTotal = metrics.total, confidence = metrics.confidence,
            relationStage = metrics.stage, timingConsistency = metrics.timingConsistency,
        }
    end
    table.sort(rows, function(a, b)
        if a.confidence == b.confidence then return (a.support or 0) > (b.support or 0) end
        return a.confidence > b.confidence
    end)
    local out = {}
    for i = 1, math.min(#rows, 60) do out[i] = rows[i] end
    return out
end

local function behaviorSummary()
    local rows = {}
    for _, row in pairs(S.behaviorTransitions) do
        rows[#rows + 1] = {
            from = row.from, to = row.to, count = row.count,
            avgGap = row.count > 0 and math.floor((row.totalGap / row.count) * 1000 + 0.5) / 1000 or 0,
            minGap = math.floor((row.minGap or 0) * 1000 + 0.5) / 1000,
            maxGap = math.floor((row.maxGap or 0) * 1000 + 0.5) / 1000,
        }
    end
    table.sort(rows, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(#rows, 60) do out[i] = rows[i] end
    return out
end

local function impactSummary()
    local rows = {}
    for remote, score in pairs(S.remoteImpact) do rows[#rows + 1] = { remote = remote, score = score } end
    table.sort(rows, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(#rows, 30) do
        out[i] = { remote = rows[i].remote, score = math.floor(rows[i].score * 100 + 0.5) / 100 }
    end
    return out
end

local function protocolSummary()
    local rows = {}
    for _, row in pairs(S.protocolModels) do
        rows[#rows + 1] = {
            direction = row.direction, remote = row.remote, method = row.method, observed = row.observed,
            shapeChanges = row.shapeChanges, semanticChanges = row.semanticChanges,
            shapeCount = #(row.shapes or {}), semanticCount = #(row.semantics or {}),
        }
    end
    table.sort(rows, function(a, b)
        local aa = (a.shapeChanges or 0) + (a.semanticChanges or 0)
        local bb = (b.shapeChanges or 0) + (b.semanticChanges or 0)
        if aa == bb then return (a.observed or 0) > (b.observed or 0) end
        return aa > bb
    end)
    local out = {}
    for i = 1, math.min(#rows, 50) do out[i] = rows[i] end
    return out
end

local function argumentFieldSummary()
    local rows = {}
    for _, row in pairs(S.argumentFields) do
        rows[#rows + 1] = {
            stream = row.stream, field = row.field, observed = row.observed, changes = row.changes,
            stability = row.observed > 1 and math.floor((1 - ((row.changes or 0) / math.max(1, row.observed - 1))) * 1000 + 0.5) / 1000 or nil,
            types = row.types,
        }
    end
    table.sort(rows, function(a, b)
        if (a.changes or 0) == (b.changes or 0) then return (a.observed or 0) > (b.observed or 0) end
        return (a.changes or 0) > (b.changes or 0)
    end)
    local out = {}
    for i = 1, math.min(#rows, 80) do out[i] = rows[i] end
    return out
end

local function investigationKnowledgeDeltaSummary()
    local rows = {}
    for _, row in pairs(S.investigationKnowledgeDelta) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b) return (a.completed or 0) > (b.completed or 0) end)
    local out = {}
    for i = 1, math.min(#rows, C.DELTA_INVESTIGATION_CAP) do out[i] = rows[i] end
    return out
end

local function runtimePatternSummary()
    local rows = {}
    for hash, count in pairs(S.runtimePatternCounts) do
        if count > 1 then rows[#rows + 1] = { hash = hash, count = count } end
    end
    table.sort(rows, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(#rows, 50) do out[i] = rows[i] end
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
            knownSemanticHashes = S.deltaSemantic,
            knownRemoteHashes = S.deltaRemote,
            investigationKnowledge = investigationKnowledgeDeltaSummary(),
            frontier = S.frontier,
        },
        strategyDelta = strategySnapshot(),
        coverage = S.coverage,
        intelligence = {
            outboundObserver = S.coverage.outboundObserver,
            outboundObserved = S.smartStats.outboundObserved or 0,
            outboundAccepted = S.smartStats.outboundAccepted or 0,
            highInterestOutbound = S.smartStats.highInterestOutbound or 0,
            highInterestInbound = S.smartStats.highInterestInbound or 0,
            correlationsOpened = S.smartStats.correlationsOpened or 0,
            semanticNovel = S.smartStats.semanticNovel or 0,
            opaqueSamples = S.smartStats.opaqueSamples or 0,
            deepProbes = S.smartStats.deepProbes or 0,
            batchBudgetDrops = S.smartStats.batchBudgetDrops or 0,
            focusRemote = S.focusRemote,
            focusScore = S.focusScore,
            correlationEvidence = correlationEvidenceSummary(),
            behaviorTransitions = behaviorSummary(),
            impactRemotes = impactSummary(),
            runtimePatterns = runtimePatternSummary(),
            protocolEvolution = protocolSummary(),
            argumentFields = argumentFieldSummary(),
            investigator = {
                state = S.investigatorState,
                stage = S.investigatorStage,
                stageDetail = S.investigatorStageDetail,
                stageAgeMs = math.floor(math.max(0, os.clock() - (tonumber(S.investigatorStageSince) or os.clock())) * 1000 + 0.5),
                lastError = S.lastInvestigatorError,
                diagnosticMarkers = S.smartStats.investigatorDiagnostics or 0,
                errors = S.smartStats.investigatorErrors or 0,
                queued = S.smartStats.investigationsQueued or 0,
                active = S.smartStats.investigationsActive or 0,
                passive = S.smartStats.investigationsPassive or 0,
                completed = S.smartStats.investigationsCompleted or 0,
                cancelled = S.smartStats.investigationsCancelled or 0,
                blocked = S.smartStats.investigationsBlocked or 0,
                inputQuarantines = S.smartStats.inputQuarantines or 0,
                health = {
                    checks = S.smartStats.menuHealthChecks or 0,
                    anomalies = S.smartStats.menuHealthAnomalies or 0,
                    uiErrors = S.smartStats.menuHealthUiErrors or 0,
                    queueStarts = S.smartStats.menuHealthQueueStarts or 0,
                    queueErrors = S.smartStats.menuHealthQueueErrors or 0,
                    confirmedSkipped = S.smartStats.investigationsConfirmedSkipped or 0,
                    recent = menuHealthTail(30),
                },
            },
        },
    }
end

local function sendManifest()
    if S.batchIndex + 1 > C.MAX_BATCHES and not S.pendingManifestBody then
        return false, "max_batches_reached"
    end
    if not S.finalManifest then S.finalManifest = manifestTable() end

    local index = tonumber(S.pendingManifestIndex) or (S.batchIndex + 1)
    local body = S.pendingManifestBody
    if type(body) ~= "string" then
        local batch = { index = index, bytes = 0, records = {}, remotes = {} }
        local encoded, err = encodeBatchBody(batch, true, S.finalManifest)
        if not encoded then return false, err end
        body = encoded
        S.pendingManifestBody = body
        S.pendingManifestIndex = index
        if saveCache and cacheSnapshot then saveCache(cacheSnapshot()) end
    end

    local since = os.clock() - S.lastSendClock
    if since < C.MIN_SEND_INTERVAL then task.wait(C.MIN_SEND_INTERVAL - since) end
    local ok, data, postErr = postRaw(C.BASE .. "/batch", body)
    S.lastSendClock = os.clock()
    if ok then
        S.batchIndex = index
        S.pendingManifestBody = nil
        S.pendingManifestIndex = nil
        S.uploadBlocked = false
        clearActiveUploadError()
    else
        noteUploadError("manifest", postErr, index)
        if saveCache and cacheSnapshot then saveCache(cacheSnapshot()) end
    end
    return ok, ok and data or postErr
end

local function drainQueue(timeoutSeconds)
    local deadline = os.clock() + (timeoutSeconds or 120)
    while S.queueHead <= #S.queue and os.clock() < deadline do
        if S.uploadBlocked then return false end
        if not S.uploading and os.clock() >= S.nextRetryClock then kickUpload() end
        task.wait(0.15)
    end
    return S.queueHead > #S.queue
end

local function resetRunState()
    setInputQuarantine(false)
    S.running = false
    S.stopping = false
    S.finalizing = false
    S.uploading = false
    S.queue, S.queueHead, S.queueBytes = {}, 1, 0
    S.totalBytes, S.ackBytes, S.batchIndex = 0, 0, 0
    S.pendingSend = nil
    S.pendingManifestBody, S.pendingManifestIndex = nil, nil
    S.finalManifest = nil
    S.firstQueuedClock = 0
    S.lastUploadError = nil
    S.uploadBlocked = false
    S.uploadError = nil
    S.uploadDiagnostics = {}
    S.uploadDiagSeq = 0
    S.uploadFailureCount = 0
    S.lastUploadDiagSignature = nil
    S.cacheSchemaVersion = nil
    S.inflightRestored = false
    S.manifestConfirmed = false
    if clearInflight then clearInflight() end
    S.sessionExact, S.remoteSeen = {}, {}
    S.sessionExactCount = 0
    S.sessionSemantic, S.semanticCountByRemote = {}, {}
    S.deltaLow, S.deltaShape, S.deltaSemantic, S.deltaRemote = {}, {}, {}, {}
    S.deltaLowSet, S.deltaShapeSet, S.deltaSemanticSet, S.deltaRemoteSet = {}, {}, {}, {}
    S.strategy, S.suppressed, S.dropped, S.repeatCounts, S.coverage, S.investigation, S.recentRefs = {}, {}, {}, {}, {}, {}, {}
    S.recentTimeline, S.recentGuiChanges = {}, {}
    S.frontier, S.frontierSet = {}, {}
    S.correlationWindows, S.lastCorrelationByRemote = {}, {}
    S.correlationSeq = 0
    S.effectTotals, S.effectBaseline, S.correlationEvidence, S.remoteImpact = {}, {}, {}, {}
    S.correlationEvidenceCount = 0
    S.behaviorTransitions, S.lastBehavior = {}, nil
    S.behaviorTransitionCount = 0
    S.recentValueChanges, S.valueActivity = {}, {}
    S.deepProbeCount, S.lastDeepProbeByRemote = 0, {}
    S.opaquePrevious, S.opaqueCounters = {}, {}
    S.runtimePatternCounts, S.runtimePatternSeen = {}, {}
    S.objectBorn = setmetatable({}, { __mode = "k" })
    S.toolSignals = setmetatable({}, { __mode = "k" })
    S.guiSignals = setmetatable({}, { __mode = "k" })
    S.investigatorState, S.investigatorReason, S.investigatorStateSince = "GREEN", "livre", os.clock()
    S.investigatorStage, S.investigatorStageDetail, S.investigatorStageSince = "idle", "livre", os.clock()
    S.lastInvestigatorError = nil
    S.activeInvestigation, S.investigationQueue, S.investigationQueuedKeys = nil, {}, {}
    S.investigationSeq, S.investigationCount, S.investigationEpoch = 0, 0, S.investigationEpoch + 1
    S.investigationNextStartAt = 0
    S.investigationLastByKey, S.investigationKnowledgeDelta, S.actionSeenCounts = {}, {}, {}
    S.menuHealthDiagnostics, S.menuHealthDiagSeq, S.menuHealthLastCheck = {}, 0, 0
    S.menuHealthLastStatus, S.menuHealthLastAnomaly, S.menuHealthLastError = nil, nil, nil
    S.protocolModels, S.protocolModelCount = {}, 0
    S.argumentFields, S.argumentFieldCount = {}, 0
    S.smartStats = {
        outboundObserved = 0, outboundAccepted = 0, highInterestOutbound = 0,
        highInterestInbound = 0, correlationsOpened = 0, semanticNovel = 0,
        opaqueSamples = 0, deepProbes = 0,
        investigationsQueued = 0, investigationsCompleted = 0, investigationsActive = 0,
        investigationsPassive = 0, investigationsCancelled = 0, investigationsBlocked = 0,
        inputQuarantines = 0, investigatorDiagnostics = 0, investigatorErrors = 0,
        menuHealthChecks = 0, menuHealthAnomalies = 0, menuHealthUiErrors = 0,
        menuHealthQueueStarts = 0, menuHealthQueueErrors = 0,
        investigationsConfirmedSkipped = 0,
        batchBudgetDrops = 0,
    }
    S.focusRemote, S.focusScore = nil, 0
    S.outboundHookRegistry, S.outboundHookReady = nil, false
    S.repeatKeyCount = 0
    S.inboundCount, S.valueCount = 0, 0
    S.lastTrajectoryAt, S.lastTrajectoryPos, S.lastTrajectoryState = 0, nil, nil
end

local uiRefresh
local mainButton
local gui
local disconnectUi

local function finalize(auto)
    if S.finalizing then return end
    if not S.running and not S.cached and S.queueHead > #S.queue then return end

    cancelActiveInvestigation("session_finalizing")
    setInputQuarantine(false)
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

        local ok = false
        local err
        for attempt = 1, C.RETRIES do
            ok, err = sendManifest()
            if ok or S.uploadBlocked then break end
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
        capabilities = {
            request = REQUEST ~= nil,
            writefile = WRITEFILE ~= nil,
            outboundHook = S.outboundHookReady,
            hookmetamethod = HOOKMETAMETHOD ~= nil,
            getnamecallmethod = GETNAMECALLMETHOD ~= nil,
        },
        player = playerContext(true),
    }, 100, true, nil, nil, nil, true)

    startScans(epoch)
    if mainButton then mainButton.Text = "ENCERRAR + ENVIAR" end
end

local function retryCached()
    if S.finalizing or not S.cached then return end
    restoreCache(S.cached)
    cancelActiveInvestigation("retry_cached")
    setInputQuarantine(false)
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
        local ok = false
        local err
        for attempt = 1, C.RETRIES do
            ok, err = sendManifest()
            if ok or S.uploadBlocked then break end
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
-- COMPACT MOBILE UI + INVESTIGATION STATUS ICON
--==============================================================--

local function buildCompactUi()
local GUI_NAME = "CafeinaUniversalGameTraceV30"
local parent = CoreGui
pcall(function() if type(gethui) == "function" then parent = gethui() end end)
pcall(function() local old = parent:FindFirstChild(GUI_NAME); if old then old:Destroy() end end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 9999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
if not pcall(function() gui.Parent = parent end) then gui.Parent = LP:WaitForChild("PlayerGui") end

local safeRoot = Instance.new("Frame")
safeRoot.Name = "SafeRoot"
safeRoot.BackgroundTransparency = 1
safeRoot.BorderSizePixel = 0
safeRoot.Size = UDim2.fromScale(1, 1)
safeRoot.Position = UDim2.fromOffset(0, 0)
safeRoot.ZIndex = 1
safeRoot.Parent = gui

inputShield = Instance.new("TextButton")
inputShield.Name = "InvestigationInputShield"
inputShield.BackgroundTransparency = 1
inputShield.BorderSizePixel = 0
inputShield.Text = ""
inputShield.AutoButtonColor = false
inputShield.Active = true
inputShield.Modal = true
inputShield.Visible = false
inputShield.Size = UDim2.fromScale(1, 1)
inputShield.Position = UDim2.fromOffset(0, 0)
inputShield.ZIndex = 80
inputShield.Parent = safeRoot

local frame = Instance.new("Frame")
frame.Name = "Compact"
frame.Size = UDim2.fromOffset(232, 132)
frame.Position = UDim2.new(0.5, -116, 0.18, 0)
frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
frame.BorderSizePixel = 0
frame.Active = true
frame.ZIndex = 100
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
mbLabel.Position = UDim2.fromOffset(10, 6)
mbLabel.Size = UDim2.fromOffset(116, 20)
mbLabel.Font = Enum.Font.GothamBold
mbLabel.TextSize = 11
mbLabel.TextColor3 = Color3.fromRGB(238, 238, 242)
mbLabel.TextXAlignment = Enum.TextXAlignment.Left
mbLabel.Text = "0.0 / 150 MB"
mbLabel.ZIndex = 101
mbLabel.Parent = frame

local pctLabel = Instance.new("TextLabel")
pctLabel.BackgroundTransparency = 1
pctLabel.Position = UDim2.new(1, -94, 0, 6)
pctLabel.Size = UDim2.fromOffset(52, 20)
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextSize = 11
pctLabel.TextColor3 = Color3.fromRGB(190, 190, 198)
pctLabel.TextXAlignment = Enum.TextXAlignment.Right
pctLabel.Text = "0%"
pctLabel.ZIndex = 101
pctLabel.Parent = frame

local minimizeButton = Instance.new("TextButton")
minimizeButton.Name = "Minimize"
minimizeButton.Position = UDim2.new(1, -34, 0, 5)
minimizeButton.Size = UDim2.fromOffset(24, 22)
minimizeButton.BackgroundColor3 = Color3.fromRGB(26, 26, 31)
minimizeButton.BorderSizePixel = 0
minimizeButton.Text = "—"
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextSize = 14
minimizeButton.TextColor3 = Color3.fromRGB(220, 220, 225)
minimizeButton.AutoButtonColor = true
minimizeButton.ZIndex = 102
minimizeButton.Parent = frame
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeButton

local stateStrip = Instance.new("Frame")
stateStrip.Position = UDim2.fromOffset(10, 31)
stateStrip.Size = UDim2.new(1, -20, 0, 22)
stateStrip.BackgroundColor3 = Color3.fromRGB(21, 21, 25)
stateStrip.BorderSizePixel = 0
stateStrip.ZIndex = 101
stateStrip.Parent = frame
local stateCorner = Instance.new("UICorner")
stateCorner.CornerRadius = UDim.new(0, 7)
stateCorner.Parent = stateStrip

local stateDot = Instance.new("Frame")
stateDot.Position = UDim2.fromOffset(8, 7)
stateDot.Size = UDim2.fromOffset(8, 8)
stateDot.BorderSizePixel = 0
stateDot.ZIndex = 102
stateDot.Parent = stateStrip
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = stateDot

local stateLabel = Instance.new("TextLabel")
stateLabel.BackgroundTransparency = 1
stateLabel.Position = UDim2.fromOffset(22, 1)
stateLabel.Size = UDim2.new(1, -28, 1, -2)
stateLabel.Font = Enum.Font.GothamBold
stateLabel.TextSize = 10
stateLabel.TextColor3 = Color3.fromRGB(236, 236, 240)
stateLabel.TextXAlignment = Enum.TextXAlignment.Left
stateLabel.TextTruncate = Enum.TextTruncate.AtEnd
stateLabel.ZIndex = 102
stateLabel.Parent = stateStrip

local bar = Instance.new("Frame")
bar.Position = UDim2.fromOffset(10, 59)
bar.Size = UDim2.new(1, -20, 0, 7)
bar.BackgroundColor3 = Color3.fromRGB(29, 29, 34)
bar.BorderSizePixel = 0
bar.ZIndex = 101
bar.Parent = frame
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(220, 220, 226)
fill.BorderSizePixel = 0
fill.ZIndex = 102
fill.Parent = bar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

mainButton = Instance.new("TextButton")
mainButton.Position = UDim2.fromOffset(10, 75)
mainButton.Size = UDim2.new(1, -20, 0, 46)
mainButton.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
mainButton.BorderSizePixel = 0
mainButton.Font = Enum.Font.GothamBold
mainButton.TextSize = 11
mainButton.TextColor3 = Color3.fromRGB(245, 245, 247)
mainButton.Text = REQUEST and "CONECTANDO" or "SEM HTTP"
mainButton.AutoButtonColor = true
mainButton.ZIndex = 101
mainButton.Parent = frame
local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = mainButton

local diagButton = Instance.new("TextButton")
diagButton.Name = "Diagnostic"
diagButton.Position = UDim2.new(1, -52, 0, 2)
diagButton.Size = UDim2.fromOffset(48, 18)
diagButton.BackgroundColor3 = Color3.fromRGB(82, 34, 34)
diagButton.BorderSizePixel = 0
diagButton.Text = "DIAG"
diagButton.Font = Enum.Font.GothamBold
diagButton.TextSize = 9
diagButton.TextColor3 = Color3.fromRGB(255, 235, 235)
diagButton.Visible = false
diagButton.ZIndex = 104
diagButton.Parent = stateStrip
local diagButtonCorner = Instance.new("UICorner")
diagButtonCorner.CornerRadius = UDim.new(0, 5)
diagButtonCorner.Parent = diagButton

local diagFrame = Instance.new("Frame")
diagFrame.Name = "UploadDiagnostic"
diagFrame.Size = UDim2.fromOffset(310, 270)
diagFrame.Position = UDim2.new(0.5, -155, 0.5, -135)
diagFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 13)
diagFrame.BorderSizePixel = 0
diagFrame.Visible = false
diagFrame.ZIndex = 160
diagFrame.Parent = safeRoot
local diagCorner = Instance.new("UICorner")
diagCorner.CornerRadius = UDim.new(0, 10)
diagCorner.Parent = diagFrame
local diagStroke = Instance.new("UIStroke")
diagStroke.Color = Color3.fromRGB(95, 55, 55)
diagStroke.Thickness = 1
diagStroke.Parent = diagFrame

local diagTitle = Instance.new("TextLabel")
diagTitle.BackgroundTransparency = 1
diagTitle.Position = UDim2.fromOffset(10, 7)
diagTitle.Size = UDim2.new(1, -48, 0, 24)
diagTitle.Font = Enum.Font.GothamBold
diagTitle.TextSize = 12
diagTitle.TextColor3 = Color3.fromRGB(245, 238, 238)
diagTitle.TextXAlignment = Enum.TextXAlignment.Left
diagTitle.Text = "CAFEÍNA • DIAGNÓSTICO"
diagTitle.ZIndex = 161
diagTitle.Parent = diagFrame

local diagClose = Instance.new("TextButton")
diagClose.Position = UDim2.new(1, -35, 0, 5)
diagClose.Size = UDim2.fromOffset(28, 26)
diagClose.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
diagClose.BorderSizePixel = 0
diagClose.Text = "×"
diagClose.Font = Enum.Font.GothamBold
diagClose.TextSize = 17
diagClose.TextColor3 = Color3.fromRGB(240, 240, 244)
diagClose.ZIndex = 162
diagClose.Parent = diagFrame
local diagCloseCorner = Instance.new("UICorner")
diagCloseCorner.CornerRadius = UDim.new(0, 6)
diagCloseCorner.Parent = diagClose

local diagText = Instance.new("TextLabel")
diagText.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
diagText.BorderSizePixel = 0
diagText.Position = UDim2.fromOffset(10, 38)
diagText.Size = UDim2.new(1, -20, 1, -48)
diagText.Font = Enum.Font.Code
diagText.TextSize = 10
diagText.TextColor3 = Color3.fromRGB(228, 228, 232)
diagText.TextWrapped = true
diagText.TextXAlignment = Enum.TextXAlignment.Left
diagText.TextYAlignment = Enum.TextYAlignment.Top
diagText.Text = "Sem erros registrados."
diagText.ZIndex = 161
diagText.Parent = diagFrame
local diagTextCorner = Instance.new("UICorner")
diagTextCorner.CornerRadius = UDim.new(0, 7)
diagTextCorner.Parent = diagText

local lastAutoShownUploadDiag = 0

local function diagnosticText()
    local e = S.uploadError or S.uploadDiagnostics[#S.uploadDiagnostics]
    local queueItems = math.max(0, #S.queue - S.queueHead + 1)
    local pendingExact = type(S.pendingSend) == "table" and type(S.pendingSend.body) == "string"
    local lines = {
        "Versão: " .. C.VERSION,
        "Run: " .. tostring(S.runId or "-"),
        "Game: " .. tostring(S.runGameId or game.GameId),
        "Place run/atual: " .. tostring(S.runPlaceId or "-") .. " / " .. tostring(game.PlaceId),
        "Batch local: " .. tostring(S.batchIndex or 0) ..
            " | alvo: " .. tostring(e and e.batchIndex or ((S.batchIndex or 0) + 1)),
        string.format("Fila: %d itens • %.2f MB", queueItems, (S.queueBytes or 0) / MB),
        string.format("ACK/total: %.2f / %.2f MB", (S.ackBytes or 0) / MB, (S.totalBytes or 0) / MB),
        "Cache schema: " .. tostring(S.cacheSchemaVersion or "-") ..
            " | lote exato: " .. (pendingExact and "SIM" or "NÃO"),
        "Cache legado: " .. tostring(S.cacheSchemaVersion ~= nil and S.cacheSchemaVersion < 4) ..
            " | inflight restaurado: " .. tostring(S.inflightRestored == true),
        "Enviando/finalizando: " .. tostring(S.uploading == true) .. " / " .. tostring(S.finalizing == true),
        "Bloqueado: " .. tostring(S.uploadBlocked == true),
        "Investigador: " .. tostring(S.investigatorState) .. " • " .. tostring(S.investigatorStage),
    }
    if S.menuHealthLastAnomaly then lines[#lines + 1] = "Watchdog: " .. tostring(S.menuHealthLastAnomaly) end
    if S.lastInvestigatorError then lines[#lines + 1] = "Erro investigador: " .. tostring(S.lastInvestigatorError) end
    if e then
        lines[#lines + 1] = "Upload: " .. tostring(e.code and ("HTTP " .. e.code) or e.kind) ..
            " • " .. tostring(e.label)
        lines[#lines + 1] = "Fase: " .. tostring(e.phase) ..
            " | retry: " .. tostring(e.retryable) .. " | tentativas: " .. tostring(e.attempts or 1)
        lines[#lines + 1] = "Erro: " .. string.sub(tostring(e.raw or S.lastUploadError or "-"), 1, 620)
    elseif S.lastUploadError then
        lines[#lines + 1] = "Erro upload: " .. string.sub(tostring(S.lastUploadError), 1, 620)
    end
    return table.concat(lines, "\n")
end

local miniIcon = Instance.new("TextButton")
miniIcon.Name = "InvestigationIcon"
miniIcon.Size = UDim2.fromOffset(46, 46)
miniIcon.Position = UDim2.new(0, 12, 0.28, 0)
miniIcon.BackgroundColor3 = Color3.fromRGB(55, 190, 105)
miniIcon.BorderSizePixel = 0
miniIcon.Text = "✓"
miniIcon.Font = Enum.Font.GothamBold
miniIcon.TextSize = 17
miniIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
miniIcon.AutoButtonColor = false
miniIcon.Active = true
miniIcon.Visible = false
miniIcon.ZIndex = 120
miniIcon.Parent = safeRoot
local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(1, 0)
iconCorner.Parent = miniIcon
local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.fromRGB(240, 240, 245)
iconStroke.Transparency = 0.45
iconStroke.Thickness = 1
iconStroke.Parent = miniIcon

local stateVisuals = {
    GREEN = { color = Color3.fromRGB(55, 190, 105), label = "VERDE", icon = "✓" },
    YELLOW = { color = Color3.fromRGB(235, 190, 55), label = "AMARELO", icon = "!" },
    RED = { color = Color3.fromRGB(235, 72, 72), label = "VERMELHO", icon = "●" },
    BLUE = { color = Color3.fromRGB(72, 145, 235), label = "AZUL", icon = "…" },
}

local stageLabels = {
    idle = "LIVRE",
    yellow_state_set = "ESTADO AMARELO",
    yellow_before_quarantine = "ANTES INPUT",
    yellow_after_quarantine = "INPUT OK",
    yellow_quarantine_error = "ERRO INPUT",
    yellow_before_ui_defer = "ANTES UI",
    yellow_after_ui_defer = "UI AGENDADA",
    yellow_ui_defer_error = "ERRO UI",
    yellow_ui_missing = "UI INDISPONÍVEL",
    yellow_timer_scheduled = "TIMER AGENDADO",
    yellow_timer_fired = "TIMER DISPAROU",
    execute_entered = "EXECUTANDO",
    risk_blocked = "RISCO BLOQUEOU",
    risk_clear = "RISCO OK",
    stability_checked = "ESTABILIDADE",
    yellow_retry_wait = "AGUARDANDO ESTAB.",
    yellow_retry_fired = "RETRY DISPAROU",
    passive_selected = "MODO PASSIVO",
    red_prepare = "PREPARANDO TESTE",
    red_settle_fired = "TESTE LIBERADO",
    fire_call_started = "EXECUTANDO AÇÃO",
    fire_call_finished = "AÇÃO CONCLUÍDA",
    blue_observing = "OBSERVANDO",
    execute_error = "ERRO INTERNO",
    cancelled = "CANCELANDO",
    finishing = "FINALIZANDO",
}

local minimized = false
local function setMinimized(value)
    minimized = value == true
    frame.Visible = not minimized
    miniIcon.Visible = minimized
end

investigatorUiRefresh = function()
    local hasDiag = S.uploadError ~= nil or S.uploadBlocked or S.menuHealthLastAnomaly ~= nil or S.lastInvestigatorError ~= nil
    diagButton.Visible = hasDiag
    stateLabel.Size = hasDiag and UDim2.new(1, -78, 1, -2) or UDim2.new(1, -28, 1, -2)

    if S.uploadError then
        stateDot.BackgroundColor3 = Color3.fromRGB(235, 72, 72)
        miniIcon.BackgroundColor3 = Color3.fromRGB(235, 72, 72)
        miniIcon.Text = "!"
        local code = S.uploadError.code and (" " .. tostring(S.uploadError.code)) or ""
        stateLabel.Text = "UPLOAD" .. code .. " • " .. tostring(S.uploadError.label or "ERRO")
        return
    end

    local visual = stateVisuals[S.investigatorState] or stateVisuals.GREEN
    if (S.investigatorState == "RED" or S.investigatorState == "BLUE") and not minimized then
        setMinimized(true)
    end
    stateDot.BackgroundColor3 = visual.color
    miniIcon.BackgroundColor3 = visual.color
    miniIcon.Text = visual.icon
    local stage = stageLabels[S.investigatorStage] or string.upper(tostring(S.investigatorStage or "?"))
    local elapsed = math.max(0, os.clock() - (tonumber(S.investigatorStageSince) or os.clock()))
    local suffix = S.investigatorState ~= "GREEN" and string.format(" • %.1fs", elapsed) or ""
    stateLabel.Text = visual.label .. " • " .. stage .. suffix
end

uiRefresh = function()
    local total = S.totalBytes
    local ack = math.min(S.ackBytes, total)
    local pct = total > 0 and math.floor((ack / total) * 100 + 0.5) or 0
    if S.finalizing and not S.manifestConfirmed then pct = math.min(math.max(pct, 99), 99) end
    mbLabel.Text = string.format("%.1f / 150 MB", total / MB)
    pctLabel.Text = tostring(math.clamp(pct, 0, 100)) .. "%"
    fill.Size = UDim2.fromScale(math.clamp(pct / 100, 0, 1), 1)
    investigatorUiRefresh()
    diagText.Text = diagnosticText()
    if S.uploadError and (tonumber(S.uploadError.seq) or 0) > lastAutoShownUploadDiag then
        lastAutoShownUploadDiag = tonumber(S.uploadError.seq) or lastAutoShownUploadDiag
        diagFrame.Visible = true
    end
    if S.uploadBlocked and not S.finalizing then
        mainButton.Text = "ERRO • VER DIAGNÓSTICO"
    end
end

task.spawn(function()
    while gui.Parent do
        local okUi, uiErr = pcall(uiRefresh)
        if not okUi then
            S.smartStats.menuHealthUiErrors = (S.smartStats.menuHealthUiErrors or 0) + 1
            appendMenuHealthDiagnostic("ui_refresh_error", compactErrorTrace(uiErr), "error", true)
        end
        if S.running then
            if processInvestigationQueue then processInvestigationQueue() end
            maybeTrajectory()
        end
        menuHealthWatchdogTick()
        if (S.running or S.finalizing) and not S.uploadBlocked and not S.uploading and os.clock() >= S.nextRetryClock and
            shouldFlushQueue(S.finalizing or S.stopping) then
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

local heartbeat = uiConnect(RunService.Heartbeat, function(dt)
    S.frameDt = S.frameDt * 0.94 + dt * 0.06
end)

local function clampObject(object, margin)
    margin = margin or 4
    local rootPos = safeRoot.AbsolutePosition
    local rootSize = safeRoot.AbsoluteSize
    local size = object.AbsoluteSize
    if rootSize.X <= 0 or rootSize.Y <= 0 then return end
    local minX, minY = rootPos.X + margin, rootPos.Y + margin
    local maxX = math.max(minX, rootPos.X + rootSize.X - size.X - margin)
    local maxY = math.max(minY, rootPos.Y + rootSize.Y - size.Y - margin)
    local x = math.clamp(object.AbsolutePosition.X, minX, maxX)
    local y = math.clamp(object.AbsolutePosition.Y, minY, maxY)
    object.Position = UDim2.fromOffset(x - rootPos.X, y - rootPos.Y)
end

local dragging, dragInput, dragMotion, dragStart, startPos = false, nil, nil, nil, nil
uiConnect(frame.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local localY = input.Position.Y - frame.AbsolutePosition.Y
    if localY > 54 then return end
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
    clampObject(frame, 4)
end)
uiConnect(UserInputService.InputEnded, function(input)
    if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = false
        dragInput, dragMotion = nil, nil
    end
end)

local iconDragging, iconInput, iconMotion, iconStart, iconStartPos, iconMoved = false, nil, nil, nil, nil, false
uiConnect(miniIcon.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    iconDragging = true
    iconInput = input
    iconMotion = input.UserInputType == Enum.UserInputType.Touch and input or nil
    iconStart = input.Position
    iconStartPos = miniIcon.Position
    iconMoved = false
end)
uiConnect(miniIcon.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then iconMotion = input end
end)
uiConnect(UserInputService.InputChanged, function(input)
    if not iconDragging or not iconStart or not iconStartPos then return end
    if input ~= iconMotion and input ~= iconInput then return end
    local d = input.Position - iconStart
    if math.abs(d.X) + math.abs(d.Y) > 8 then iconMoved = true end
    miniIcon.Position = UDim2.new(iconStartPos.X.Scale, iconStartPos.X.Offset + d.X, iconStartPos.Y.Scale, iconStartPos.Y.Offset + d.Y)
    clampObject(miniIcon, 5)
end)
uiConnect(UserInputService.InputEnded, function(input)
    if iconDragging and (input == iconInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
        iconDragging = false
        iconInput, iconMotion = nil, nil
    end
end)

uiConnect(diagButton.Activated, function()
    diagText.Text = diagnosticText()
    diagFrame.Visible = true
end)
uiConnect(diagClose.Activated, function()
    diagFrame.Visible = false
end)

uiConnect(minimizeButton.Activated, function()
    if S.investigatorState == "RED" or S.investigatorState == "BLUE" then return end
    setMinimized(true)
end)

uiConnect(miniIcon.Activated, function()
    if iconMoved then iconMoved = false return end
    if S.investigatorState ~= "GREEN" then cancelActiveInvestigation("icone_do_menu") end
    setMinimized(false)
end)

pcall(function()
    local camera = Workspace.CurrentCamera
    if camera then
        uiConnect(camera:GetPropertyChangedSignal("ViewportSize"), function()
            task.defer(function() clampObject(frame, 4); clampObject(miniIcon, 5) end)
        end)
    end
end)
uiConnect(safeRoot:GetPropertyChangedSignal("AbsoluteSize"), function()
    task.defer(function() clampObject(frame, 4); clampObject(miniIcon, 5) end)
end)
uiConnect(safeRoot:GetPropertyChangedSignal("AbsolutePosition"), function()
    task.defer(function() clampObject(frame, 4); clampObject(miniIcon, 5) end)
end)
task.defer(function() clampObject(frame, 4); clampObject(miniIcon, 5) end)

uiConnect(mainButton.Activated, function()
    if S.investigatorState == "RED" or S.investigatorState == "BLUE" then return end
    if S.finalizing then return end
    if S.uploadBlocked then
        diagText.Text = diagnosticText()
        diagFrame.Visible = true
        return
    end
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

investigatorUiRefresh()


    return gui, disconnectUi
end

gui, disconnectUi = buildCompactUi()

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
        health.githubMirrorConfigured == true and tonumber(health.hardSessionBytes) == C.HARD_BYTES and
        (tonumber(health.maxBatches) or 0) >= C.MAX_BATCHES

    loadRemoteProfile(false)
    S.cached = loadCache()
    local inflight = loadInflight()
    S.preflightReady = true

    if S.cached then
        restoreCache(S.cached)
        if inflight then restoreInflight(inflight) end
        mainButton.Text = "REENVIAR"
    elseif inflight then
        noteUploadError("orphan_inflight", "lote_em_voo_sem_cache_da_fila", tonumber(inflight.batchIndex))
        mainButton.Text = "ERRO • DIAGNÓSTICO"
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
    Diagnostic = function()
        return {
            version = C.VERSION,
            runId = S.runId,
            gameId = S.runGameId,
            placeId = S.runPlaceId,
            currentPlaceId = game.PlaceId,
            batchIndex = S.batchIndex,
            queueBytes = S.queueBytes,
            ackBytes = S.ackBytes,
            totalBytes = S.totalBytes,
            uploadBlocked = S.uploadBlocked,
            uploadError = S.uploadError,
            lastUploadError = S.lastUploadError,
            cacheSchemaVersion = S.cacheSchemaVersion,
            pendingExactBody = type(S.pendingSend) == "table" and type(S.pendingSend.body) == "string",
        }
    end,
    Finish = function() finalize(false) end,
    Stop = function()
        cancelActiveInvestigation("stop")
        setInputQuarantine(false)
        S.stopping = true; S.running = false; S.runEpoch = S.runEpoch + 1
        disconnect()
        disconnectUi()
        pcall(function() gui:Destroy() end)
    end,
}

gui.Destroying:Connect(function()
    if S.running and not S.finalizing then saveCache() end
    setInputQuarantine(false)
    S.stopping = true
    S.running = false
    S.runEpoch = S.runEpoch + 1
    disconnect()
    disconnectUi()
end)

print("[CAFEINA] UNIVERSAL GAME TRACE V3.2.7 carregado • upload durável • diagnóstico automático • streaming protegido")