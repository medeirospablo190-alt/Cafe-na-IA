--[[
    GRUPO LUA — LOGIN BOOTSTRAP V3 / DELTA MOBILE

    Ajustes específicos para Delta:
    • normaliza o formato de resposta do request/http_request;
    • aceita Body/body/ResponseBody e StatusCode/status_code/status;
    • mantém aliases extras de custom asset;
    • limpa cache antigo da imagem antes de abrir o login;
    • carrega o core estável do login.
]]

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

--==============================================================--
-- DELTA REQUEST COMPAT
-- Alguns builds/executores retornam campos HTTP em minúsculas.
-- O core antigo esperava Body + StatusCode.
--==============================================================--

local originalRequest

pcall(function()
    if type(request) == "function" then
        originalRequest = request
    elseif type(http_request) == "function" then
        originalRequest = http_request
    elseif type(syn) == "table" and type(syn.request) == "function" then
        originalRequest = syn.request
    elseif type(fluxus) == "table" and type(fluxus.request) == "function" then
        originalRequest = fluxus.request
    end
end)

if type(originalRequest) == "function" then
    local function normalizedRequest(options)
        local response = originalRequest(options)

        if type(response) == "table" then
            if response.Body == nil then
                response.Body = response.body
                    or response.ResponseBody
                    or response.responseBody
                    or response.response_body
                    or response.data
            end

            if response.StatusCode == nil then
                response.StatusCode = tonumber(
                    response.status_code
                    or response.statusCode
                    or response.Status
                    or response.status
                    or response.code
                    or 0
                ) or 0
            end

            if response.Headers == nil then
                response.Headers = response.headers
                    or response.responseHeaders
                    or response.response_headers
            end

            if response.Success == nil then
                local code = tonumber(response.StatusCode or 0) or 0
                response.Success = code >= 200 and code < 300
            end
        end

        return response
    end

    pcall(function()
        ENV.request = normalizedRequest
    end)

    pcall(function()
        ENV.http_request = normalizedRequest
    end)
end

--==============================================================--
-- CUSTOM ASSET COMPAT
--==============================================================--

pcall(function()
    if type(getcustomasset) ~= "function" then
        if type(getasset) == "function" then
            ENV.getcustomasset = getasset
        elseif type(customasset) == "function" then
            ENV.getcustomasset = customasset
        elseif type(syn) == "table" and type(syn.getcustomasset) == "function" then
            ENV.getcustomasset = syn.getcustomasset
        elseif type(getsynasset) == "function" then
            ENV.getcustomasset = getsynasset
        end
    end
end)

--==============================================================--
-- LIMPAR CACHE ANTIGO
--==============================================================--

pcall(function()
    if type(isfile) == "function" and type(delfile) == "function" then
        local files = {
            "grupo_lua_login_v1.jpg",
            "grupo_lua_login.jpg",
            "grupo-lua-login.jpg",
        }

        for _, file in ipairs(files) do
            if isfile(file) then
                delfile(file)
            end
        end
    end
end)

--==============================================================--
-- CORE DO LOGIN
--==============================================================--

local CORE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/f4bbc939ae0311d1691eaa41ddee4e9351ed3afd/GrupoLuaLogin.lua"

local ok, source = pcall(function()
    return game:HttpGet(CORE_URL, true)
end)

if not ok or type(source) ~= "string" or source == "" then
    error("[GRUPO LUA] Não foi possível baixar o login.")
end

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
