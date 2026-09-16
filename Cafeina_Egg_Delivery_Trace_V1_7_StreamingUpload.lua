--==============================================================--
-- CAFEINA • EGG DELIVERY TRACE V1.7 • UPLOAD ADAPTER
-- Keeps the proven passive collector and maps its old streaming
-- /upload/start|chunk|finish contract to the live inventory-trace API.
--==============================================================--

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local PINNED_COLLECTOR = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/63e367f28944329a5f43fa522995be33c38be27c/Cafeina_Egg_Delivery_Trace_V1_7_StreamingUpload.lua"
local LIVE_ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace"
local OLD_BASE = "https://cafe-na-ia.onrender.com/upload"
local VERSION = "EGG_DELIVERY_TRACE_V1_7_STREAMING_UPLOAD"
local MAX_REMOTES = 500

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
    return nil
end

local synRequest
pcall(function()
    if syn and type(syn.request) == "function" then synRequest = syn.request end
end)

local httpTableRequest
pcall(function()
    if http and type(http.request) == "function" then httpTableRequest = http.request end
end)

local previousRequest = rawget(ENV, "request")
local originalRequest = pick(
    previousRequest,
    rawget(ENV, "http_request"),
    httpTableRequest,
    synRequest
)

if not originalRequest then
    error("[CAFEINA] Executor sem request/http_request; upload indisponível.")
end

local sessions = {}

local function response(statusCode, bodyTable)
    return {
        Success = statusCode >= 200 and statusCode < 300,
        StatusCode = statusCode,
        Status = statusCode,
        Body = HttpService:JSONEncode(bodyTable or {}),
        Headers = {["Content-Type"] = "application/json"},
    }
end

local function decodeBody(options)
    local raw = options and options.Body
    if type(raw) ~= "string" or raw == "" then return {} end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
    return ok and type(data) == "table" and data or {}
end

local function isOldRoute(url, suffix)
    return tostring(url or "") == OLD_BASE .. suffix
end

local function collectRemotes(records)
    local out, seen = {}, {}
    for _, record in ipairs(records or {}) do
        local remote = type(record) == "table" and record.remote or nil
        if type(remote) == "table" then
            local path = tostring(remote.path or remote.name or "")
            if path ~= "" and not seen[path] then
                seen[path] = true
                out[#out + 1] = {
                    path = remote.path,
                    name = remote.name,
                    className = remote.className,
                }
                if #out >= MAX_REMOTES then break end
            end
        end
    end
    return out
end

local function forwardChunk(session, index, objects)
    local traceRunId = tostring(session.uploadId)
    local payload = {
        schemaVersion = 1,
        userId = tostring(LP.UserId),
        username = tostring(LP.Name),
        capturedAt = DateTime.now():ToIsoDate(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = traceRunId,
        trace = {
            version = VERSION,
            purpose = "egg_delivery_trace",
            runId = traceRunId,
            batchIndex = index,
            source = "egg_v17_upload_adapter",
            passive = true,
            metadata = session.metadata,
            records = objects,
            remotes = collectRemotes(objects),
        },
    }

    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then
        return false, "json_encode_failed: " .. tostring(encoded)
    end

    local okRequest, result = pcall(originalRequest, {
        Url = LIVE_ENDPOINT,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            Accept = "application/json",
        },
        Body = encoded,
    })

    if not okRequest or type(result) ~= "table" then
        return false, "request_failed: " .. tostring(result)
    end

    local status = tonumber(result.StatusCode or result.Status or result.status) or 0
    local bodyText = result.Body or result.body or "{}"
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, bodyText)

    if status < 200 or status >= 300 then
        return false, "HTTP " .. tostring(status) .. " " .. tostring(bodyText)
    end

    if not okDecode or type(data) ~= "table" or data.ok ~= true then
        return false, "invalid_api_response: " .. tostring(bodyText)
    end

    local github = data.github
    if type(github) ~= "table" then
        return false, "github_status_missing"
    end
    if github.configured ~= true then
        return false, "github_mirror_not_configured"
    end
    if github.mirrored ~= true then
        return false, tostring(github.error or "github_mirror_failed")
    end

    return true, data
end

local function adapter(options)
    local url = tostring(options and (options.Url or options.URL or options.url) or "")

    if isOldRoute(url, "/start") then
        local body = decodeBody(options)
        local uploadId = HttpService:GenerateGUID(false)
        sessions[uploadId] = {
            uploadId = uploadId,
            filename = tostring(body.filename or ""),
            source = tostring(body.source or VERSION),
            metadata = type(body.metadata) == "table" and body.metadata or {},
            chunks = {},
            githubPaths = {},
        }
        return response(200, {ok=true, uploadId=uploadId})
    end

    if isOldRoute(url, "/chunk") then
        local body = decodeBody(options)
        local uploadId = tostring(body.uploadId or "")
        local index = tonumber(body.index)
        local objects = body.objects
        local session = sessions[uploadId]

        if not session then return response(400, {ok=false, message="uploadId inválido"}) end
        if not index or index < 1 then return response(400, {ok=false, message="index inválido"}) end
        if type(objects) ~= "table" then return response(400, {ok=false, message="objects inválido"}) end

        if session.chunks[index] == true then
            return response(200, {ok=true, duplicate=true, index=index})
        end

        local ok, dataOrError = forwardChunk(session, index, objects)
        if not ok then
            return response(502, {ok=false, message=tostring(dataOrError), index=index})
        end

        session.chunks[index] = true
        if type(dataOrError) == "table" and type(dataOrError.github) == "table" then
            session.githubPaths[index] = dataOrError.github.path
        end
        return response(200, {ok=true, index=index, github=dataOrError.github})
    end

    if isOldRoute(url, "/finish") then
        local body = decodeBody(options)
        local uploadId = tostring(body.uploadId or "")
        local totalChunks = tonumber(body.totalChunks) or 0
        local session = sessions[uploadId]
        if not session then return response(400, {ok=false, message="uploadId inválido"}) end

        for i = 1, totalChunks do
            if session.chunks[i] ~= true then
                return response(409, {ok=false, message="chunk ausente", index=i})
            end
        end

        sessions[uploadId] = nil
        local latestUrl = "https://github.com/medeirospablo190-alt/Cafe-na-IA/blob/main/inventory-traces/" .. tostring(game.PlaceId) .. "/latest.json"
        return response(200, {
            ok = true,
            success = true,
            confirmed = true,
            records = tonumber(body.records) or 0,
            totalChunks = totalChunks,
            url = latestUrl,
        })
    end

    return originalRequest(options)
end

-- Make the adapter the first request function selected by the pinned collector.
ENV.request = adapter

local okSource, source = pcall(function()
    return game:HttpGet(PINNED_COLLECTOR)
end)

if not okSource or type(source) ~= "string" or source == "" then
    ENV.request = previousRequest
    error("[CAFEINA] Falha ao carregar coletor base: " .. tostring(source))
end

local fn, compileError = loadstring(source)
if not fn then
    ENV.request = previousRequest
    error("[CAFEINA] Falha ao compilar coletor base: " .. tostring(compileError))
end

local okRun, runError = pcall(fn)

-- The collector already captured the adapter in its local REQUEST.
ENV.request = previousRequest

if not okRun then
    error("[CAFEINA] Falha ao iniciar coletor base: " .. tostring(runError))
end

print("[CAFEINA] V1.7 upload corrigido -> /api/inventory-trace + GitHub mirror check")
