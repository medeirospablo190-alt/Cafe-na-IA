--[[
    GRUPO LUA — LOGIN BOOTSTRAP V5 / DELTA EXTENSIONLESS

    O diagnóstico V2 confirmou no Delta Android:
      • request = OK
      • HTTP 200 = OK
      • writefile = OK
      • getcustomasset = OK
      • Drawing = FALHOU
      • getcustomasset FUNCIONA quando o arquivo é salvo SEM EXTENSÃO

    Esta versão usa exatamente a rota que passou no teste:
      1. baixa o JPG do GitHub;
      2. salva os bytes em um arquivo local SEM extensão;
      3. chama getcustomasset nesse arquivo;
      4. guarda o rbxasset:// retornado;
      5. faz o login usar diretamente esse asset.
]]

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

local IMAGE_URL =
    "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/assets/grupo-lua-login.jpg"

-- IMPORTANTE: sem .jpg / .png.
local EXTENSIONLESS_FILE = "grupo_lua_login_delta_asset"

--==============================================================--
-- REQUEST DELTA
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

local function normalizedRequest(options)
    if type(originalRequest) ~= "function" then
        return nil
    end

    local response = originalRequest(options)

    if type(response) == "table" then
        response.Body = response.Body
            or response.body
            or response.ResponseBody
            or response.responseBody
            or response.response_body
            or response.data

        response.StatusCode = tonumber(
            response.StatusCode
            or response.status_code
            or response.statusCode
            or response.Status
            or response.status
            or response.code
            or 0
        ) or 0

        response.Headers = response.Headers
            or response.headers
            or response.responseHeaders
            or response.response_headers

        if response.Success == nil then
            response.Success = response.StatusCode >= 200
                and response.StatusCode < 300
        end
    end

    return response
end

if type(originalRequest) == "function" then
    pcall(function()
        ENV.request = normalizedRequest
        ENV.http_request = normalizedRequest
    end)
end

--==============================================================--
-- ASSET FUNCTION ORIGINAL
--==============================================================--

local originalAsset

pcall(function()
    if type(getcustomasset) == "function" then
        originalAsset = getcustomasset
    elseif type(getasset) == "function" then
        originalAsset = getasset
    elseif type(customasset) == "function" then
        originalAsset = customasset
    elseif type(getsynasset) == "function" then
        originalAsset = getsynasset
    elseif type(syn) == "table" and type(syn.getcustomasset) == "function" then
        originalAsset = syn.getcustomasset
    end
end)

--==============================================================--
-- PREPARAR O ASSET EXATAMENTE COMO NO DIAGNÓSTICO QUE PASSOU
--==============================================================--

local preparedAsset
local prepareError

local function prepareImageAsset()
    if type(originalAsset) ~= "function" then
        return nil, "getcustomasset indisponível"
    end

    if type(writefile) ~= "function" then
        return nil, "writefile indisponível"
    end

    -- Tenta reutilizar o arquivo extensionless já salvo.
    if type(isfile) == "function" then
        local existsOK, exists = pcall(isfile, EXTENSIONLESS_FILE)
        if existsOK and exists then
            local assetOK, asset = pcall(originalAsset, EXTENSIONLESS_FILE)
            if assetOK and type(asset) == "string" and asset ~= "" then
                return asset
            end
        end
    end

    local body

    if type(originalRequest) == "function" then
        local reqOK, response = pcall(normalizedRequest, {
            Url = IMAGE_URL,
            Method = "GET",
            Headers = {
                ["Accept"] = "image/jpeg,image/*,*/*",
            },
        })

        if reqOK
            and type(response) == "table"
            and response.StatusCode >= 200
            and response.StatusCode < 300
            and type(response.Body) == "string"
            and #response.Body > 1000
        then
            body = response.Body
        end
    end

    -- Fallback HttpGet.
    if not body then
        local httpOK, result = pcall(function()
            return game:HttpGet(IMAGE_URL, true)
        end)

        if httpOK and type(result) == "string" and #result > 1000 then
            body = result
        end
    end

    if not body then
        return nil, "não foi possível baixar a imagem"
    end

    -- Remove somente o arquivo extensionless antigo para evitar cache ruim.
    pcall(function()
        if type(isfile) == "function"
            and type(delfile) == "function"
            and isfile(EXTENSIONLESS_FILE)
        then
            delfile(EXTENSIONLESS_FILE)
        end
    end)

    local writeOK, writeErr = pcall(
        writefile,
        EXTENSIONLESS_FILE,
        body
    )

    body = nil

    if not writeOK then
        return nil, "writefile: " .. tostring(writeErr)
    end

    -- Esta chamada foi confirmada funcionando no Delta pelo diagnóstico V2.
    local assetOK, asset = pcall(
        originalAsset,
        EXTENSIONLESS_FILE
    )

    if not assetOK then
        return nil, "getcustomasset: " .. tostring(asset)
    end

    if type(asset) ~= "string" or asset == "" then
        return nil, "getcustomasset retornou asset vazio"
    end

    return asset
end

preparedAsset, prepareError = prepareImageAsset()

if not preparedAsset then
    warn("[GRUPO LUA] Imagem não preparada:", prepareError)
end

--==============================================================--
-- REDIRECIONAR O CORE PARA O ASSET JÁ PREPARADO
--==============================================================--

if type(originalAsset) == "function" then
    local function deltaAsset(path)
        path = tostring(path or "")

        if preparedAsset and (
            path == "grupo_lua_login_v1.jpg"
            or path == "grupo_lua_login.jpg"
            or path == "grupo-lua-login.jpg"
            or path == "grupo_lua_login_delta_v4.png"
        ) then
            -- Não chama getcustomasset novamente.
            -- Retorna exatamente o rbxasset:// que o Delta já criou.
            return preparedAsset
        end

        return originalAsset(path)
    end

    pcall(function()
        ENV.getcustomasset = deltaAsset
        ENV.getsynasset = deltaAsset
    end)
end

--==============================================================--
-- LIMPAR APENAS CACHE ANTIGO COM EXTENSÃO
--==============================================================--

pcall(function()
    if type(isfile) == "function" and type(delfile) == "function" then
        for _, file in ipairs({
            "grupo_lua_login_v1.jpg",
            "grupo_lua_login.jpg",
            "grupo-lua-login.jpg",
            "grupo_lua_login_delta_v4.png",
            "grupo_lua_diag.jpg",
        }) do
            if isfile(file) then
                delfile(file)
            end
        end
    end
end)

--==============================================================--
-- CORE DO LOGIN
--==============================================================--

local CORE_URL =
    "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/f4bbc939ae0311d1691eaa41ddee4e9351ed3afd/GrupoLuaLogin.lua"

local coreOK, source = pcall(function()
    return game:HttpGet(CORE_URL, true)
end)

if not coreOK or type(source) ~= "string" or source == "" then
    error("[GRUPO LUA] Não foi possível baixar o login.")
end

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error(
        "[GRUPO LUA] Falha ao compilar login: "
        .. tostring(compileError)
    )
end

return fn()
