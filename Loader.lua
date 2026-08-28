--==============================================================--
-- CAFEINA • LOADER COM DIAGNOSTICO WEB
--==============================================================--

local HttpService = game:GetService("HttpService")

local SITE = "https://cafe-na-ia.onrender.com"
local SCRIPT_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/refs/heads/main/Tyy.lua"
local VERSION = "CAFEINA TYCOON LOADER V1"

local function getRequest()
    if type(request) == "function" then
        return request
    end

    if type(http_request) == "function" then
        return http_request
    end

    if type(syn) == "table" and type(syn.request) == "function" then
        return syn.request
    end

    if type(fluxus) == "table" and type(fluxus.request) == "function" then
        return fluxus.request
    end

    return nil
end

local Request = getRequest()

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and name then
            return tostring(name)
        end
    end
    return "desconhecido"
end

local function sendDiagnostic(kind, message, trace)
    if not Request then
        return false
    end

    local body = {
        type = tostring(kind or "unknown"),
        message = tostring(message or "Sem mensagem"),
        trace = tostring(trace or ""),
        version = VERSION,
        scriptUrl = SCRIPT_URL,
        placeId = tostring(game.PlaceId or ""),
        gameId = tostring(game.GameId or ""),
        executor = executorName(),
        clientTime = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(body)
    end)

    if not okEncode then
        return false
    end

    local ok = pcall(function()
        Request({
            Url = SITE .. "/api/diagnostics",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json"
            },
            Body = encoded
        })
    end)

    return ok
end

-- Tenta capturar erros que acontecem depois, inclusive em tasks assíncronas.
pcall(function()
    local ScriptContext = game:GetService("ScriptContext")

    ScriptContext.Error:Connect(function(message, stackTrace)
        sendDiagnostic(
            "async-runtime",
            tostring(message),
            tostring(stackTrace or "")
        )
    end)
end)

local okHttp, source = pcall(function()
    return game:HttpGet(SCRIPT_URL, true)
end)

if not okHttp then
    sendDiagnostic("http", source, "")
    warn("[CAFEINA] HTTP ERROR:", source)
    return
end

if type(source) ~= "string" or source == "" then
    sendDiagnostic("http", "Tyy.lua retornou conteúdo vazio.", "")
    warn("[CAFEINA] Tyy.lua vazio.")
    return
end

local fn, compileError = loadstring(source)

if not fn then
    sendDiagnostic("compile", compileError, "")
    warn("[CAFEINA] COMPILE ERROR:", compileError)
    return
end

local function errorHandler(err)
    local trace = ""

    pcall(function()
        if debug and type(debug.traceback) == "function" then
            trace = debug.traceback(tostring(err), 2)
        end
    end)

    if trace == "" then
        trace = tostring(err)
    end

    sendDiagnostic("runtime", err, trace)
    return trace
end

local okRun, runError = xpcall(fn, errorHandler)

if not okRun then
    warn("[CAFEINA] RUNTIME ERROR:", runError)
end
