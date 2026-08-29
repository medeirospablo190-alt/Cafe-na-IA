--==============================================================
-- CAFEINA • DIAGNOSTIC REPORTER V1
-- Envia telemetria operacional do script para o site.
-- Falhas de diagnóstico NÃO interrompem o script principal.
--==============================================================

local HttpService = game:GetService("HttpService")

local Diagnostic = {}

-- MUDE ESTES 3 CAMPOS EM CADA SCRIPT
Diagnostic.SCRIPT_NAME = "Scamtest.lua"
Diagnostic.VERSION = "1.0"
Diagnostic.SERVER_URL = "https://cafe-na-ia.onrender.com/api/runtime-diagnostics"

-- Recomendado: configure DIAGNOSTIC_TOKEN no Render e coloque o mesmo aqui.
-- Se seu servidor estiver sem token de diagnóstico, deixe vazio.
Diagnostic.TOKEN = ""

Diagnostic.RUN_ID = HttpService:GenerateGUID(false)
Diagnostic.STARTED_AT = os.time()
Diagnostic.ENABLED = true

local function getRequestFunction()
    local env = (getgenv and getgenv()) or _G

    local candidates = {
        env and env.request,
        env and env.http_request,
        request,
        http_request,
        syn and syn.request,
        http and http.request
    }

    for _, candidate in ipairs(candidates) do
        if type(candidate) == "function" then
            return candidate
        end
    end

    return nil
end

local requestFn = getRequestFunction()

local function safeString(value, limit)
    local text = tostring(value == nil and "" or value)
    limit = tonumber(limit) or 4000

    if #text > limit then
        return string.sub(text, 1, limit) .. "...[truncado]"
    end

    return text
end

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, name = pcall(function()
            return select(1, identifyexecutor())
        end)

        if ok and name then
            return safeString(name, 120)
        end
    end

    return "desconhecido"
end

local function getTraceback(err)
    local text = safeString(err, 10000)

    if debug and type(debug.traceback) == "function" then
        local ok, trace = pcall(debug.traceback, text, 3)
        if ok and trace then
            return safeString(trace, 30000)
        end
    end

    return text
end

local function parseLine(text)
    text = tostring(text or "")

    return tonumber(
        text:match(":(%d+):")
        or text:match("line%s+(%d+)")
        or text:match("linha%s+(%d+)")
    )
end

local function post(payload)
    if not Diagnostic.ENABLED then
        return false, "disabled"
    end

    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then
        return false, "json_encode_failed"
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }

    if Diagnostic.TOKEN ~= "" then
        headers["X-Diagnostic-Token"] = Diagnostic.TOKEN
    end

    local options = {
        Url = Diagnostic.SERVER_URL,
        Method = "POST",
        Headers = headers,
        Body = body
    }

    if requestFn then
        local okRequest, response = pcall(requestFn, options)
        return okRequest, response
    end

    local okRequest, response = pcall(function()
        return HttpService:RequestAsync(options)
    end)

    return okRequest, response
end

function Diagnostic.report(status, phase, data)
    status = safeString(status or "running", 40)
    phase = safeString(phase or "unknown", 120)
    data = type(data) == "table" and data or {}

    local report = {
        status = status,
        phase = phase,
        startedAt = Diagnostic.STARTED_AT,
        clientTime = os.time(),
        version = Diagnostic.VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = safeString(game.JobId, 120),
        executor = executorName(),
        message = data.message and safeString(data.message, 10000) or nil,
        error = data.error and safeString(data.error, 10000) or nil,
        traceback = data.traceback and safeString(data.traceback, 30000) or nil,
        line = tonumber(data.line),
        metrics = type(data.metrics) == "table" and data.metrics or nil,
        extra = type(data.extra) == "table" and data.extra or nil
    }

    if status == "success" or status == "error" or status == "interrupted" then
        report.finishedAt = os.time()
    end

    local payload = {
        script = Diagnostic.SCRIPT_NAME,
        runId = Diagnostic.RUN_ID,
        report = report
    }

    -- Nunca bloqueia o fluxo principal do script.
    task.spawn(function()
        pcall(post, payload)
    end)

    return payload
end

function Diagnostic.start(message)
    return Diagnostic.report("running", "startup", {
        message = message or "Script iniciado"
    })
end

function Diagnostic.step(phase, message, metrics, extra)
    return Diagnostic.report("running", phase, {
        message = message,
        metrics = metrics,
        extra = extra
    })
end

function Diagnostic.success(message, metrics, extra)
    return Diagnostic.report("success", "complete", {
        message = message or "Execução concluída",
        metrics = metrics,
        extra = extra
    })
end

function Diagnostic.interrupted(phase, message, metrics)
    return Diagnostic.report("interrupted", phase or "interrupted", {
        message = message or "Execução interrompida",
        metrics = metrics
    })
end

function Diagnostic.error(phase, err, extra)
    local trace = getTraceback(err)

    return Diagnostic.report("error", phase or "runtime", {
        message = "Erro durante a execução",
        error = safeString(err, 10000),
        traceback = trace,
        line = parseLine(trace) or parseLine(err),
        extra = extra
    })
end

-- Executa uma etapa e registra sucesso/erro sem esconder o retorno.
function Diagnostic.runStep(phase, callback)
    local started = os.clock()

    local packed = table.pack(xpcall(
        callback,
        function(err)
            return {
                __diagnosticError = true,
                error = err,
                traceback = getTraceback(err)
            }
        end
    ))

    local elapsedMs = math.floor((os.clock() - started) * 1000)

    if packed[1] then
        Diagnostic.step(phase, "Etapa concluída", {
            durationMs = elapsedMs
        })

        return true, table.unpack(packed, 2, packed.n)
    end

    local info = packed[2]
    local err = type(info) == "table" and info.error or info
    local trace = type(info) == "table" and info.traceback or getTraceback(err)

    Diagnostic.report("error", phase, {
        message = "Falha na etapa",
        error = safeString(err, 10000),
        traceback = safeString(trace, 30000),
        line = parseLine(trace) or parseLine(err),
        metrics = {
            durationMs = elapsedMs
        }
    })

    return false, err
end

return Diagnostic
