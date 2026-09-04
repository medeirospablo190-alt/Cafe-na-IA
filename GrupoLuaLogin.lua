--[[
    GRUPO LUA — LOGIN BOOTSTRAP V4 / DELTA PNG

    O diagnóstico confirmou:
      • request funciona;
      • GitHub retorna HTTP 200;
      • writefile/readfile funcionam;
      • getcustomasset existe;
      • a execução trava exatamente ao tentar abrir o JPEG.

    Esta versão evita o JPEG no asset loader do Delta:
      1. baixa a imagem compacta em Base64;
      2. decodifica em Luau puro;
      3. grava como PNG local;
      4. faz o core usar esse PNG quando pedir a imagem antiga.
]]

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

local BASE64_URL =
    "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/assets/grupo-lua-login-mobile.png.b64.txt"

local PNG_FILE = "grupo_lua_login_delta_v4.png"

--==============================================================--
-- REQUEST NORMALIZADO PARA DELTA
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
            local status = tonumber(response.StatusCode or 0) or 0
            response.Success = status >= 200 and status < 300
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
-- BASE64 -> BINÁRIO (SEM DEPENDER DE crypt)
--==============================================================--

local alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local decodeMap = {}

for index = 1, #alphabet do
    decodeMap[string.byte(alphabet, index)] = index - 1
end

local function decodeBase64(data)
    data = tostring(data or "")
        :gsub("%s+", "")

    local output = {}
    local outIndex = 0
    local length = #data
    local index = 1

    while index <= length do
        local c1 = string.byte(data, index)
        local c2 = string.byte(data, index + 1)
        local c3 = string.byte(data, index + 2)
        local c4 = string.byte(data, index + 3)

        if not c1 or not c2 then
            break
        end

        local a = decodeMap[c1]
        local b = decodeMap[c2]

        if a == nil or b == nil then
            return nil, "Base64 inválido."
        end

        local pad3 = c3 == 61 or c3 == nil
        local pad4 = c4 == 61 or c4 == nil

        local c = pad3 and 0 or decodeMap[c3]
        local d = pad4 and 0 or decodeMap[c4]

        if c == nil or d == nil then
            return nil, "Base64 inválido."
        end

        local value =
            a * 262144
            + b * 4096
            + c * 64
            + d

        outIndex += 1
        output[outIndex] = string.char(
            math.floor(value / 65536) % 256
        )

        if not pad3 then
            outIndex += 1
            output[outIndex] = string.char(
                math.floor(value / 256) % 256
            )
        end

        if not pad4 then
            outIndex += 1
            output[outIndex] = string.char(
                value % 256
            )
        end

        index += 4
    end

    return table.concat(output)
end

--==============================================================--
-- PREPARAR PNG LOCAL
--==============================================================--

local function preparePNG()
    if type(writefile) ~= "function" then
        return false, "writefile indisponível"
    end

    if type(isfile) == "function" then
        local ok, exists = pcall(isfile, PNG_FILE)
        if ok and exists then
            local valid = true

            if type(readfile) == "function" then
                local readOK, bytes = pcall(readfile, PNG_FILE)
                valid = readOK
                    and type(bytes) == "string"
                    and #bytes > 1000
                    and string.byte(bytes, 1) == 137
                    and string.sub(bytes, 2, 4) == "PNG"
            end

            if valid then
                return true
            end
        end
    end

    local encoded

    local httpOK, result = pcall(function()
        return game:HttpGet(BASE64_URL, true)
    end)

    if httpOK and type(result) == "string" and #result > 1000 then
        encoded = result
    elseif type(originalRequest) == "function" then
        local reqOK, response = pcall(normalizedRequest, {
            Url = BASE64_URL,
            Method = "GET",
            Headers = {
                ["Accept"] = "text/plain,*/*",
            },
        })

        if reqOK
            and type(response) == "table"
            and type(response.Body) == "string"
            and #response.Body > 1000
        then
            encoded = response.Body
        end
    end

    if not encoded then
        return false, "não foi possível baixar a imagem"
    end

    local binary, decodeError = decodeBase64(encoded)
    encoded = nil

    if not binary or #binary < 1000 then
        return false, decodeError or "falha ao decodificar PNG"
    end

    if string.byte(binary, 1) ~= 137
        or string.sub(binary, 2, 4) ~= "PNG"
    then
        binary = nil
        return false, "assinatura PNG inválida"
    end

    local writeOK, writeError = pcall(
        writefile,
        PNG_FILE,
        binary
    )

    binary = nil

    if not writeOK then
        return false, tostring(writeError)
    end

    return true
end

local pngOK, pngError = preparePNG()

if not pngOK then
    warn("[GRUPO LUA] PNG não preparado:", pngError)
end

--==============================================================--
-- ASSET LOADER
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

if type(originalAsset) == "function" and pngOK then
    local function deltaAsset(path)
        path = tostring(path or "")

        -- O core V1 pede este JPEG. No Delta redirecionamos para PNG.
        if path == "grupo_lua_login_v1.jpg"
            or path == "grupo_lua_login.jpg"
            or path == "grupo-lua-login.jpg"
        then
            return originalAsset(PNG_FILE)
        end

        return originalAsset(path)
    end

    pcall(function()
        ENV.getcustomasset = deltaAsset
        ENV.getsynasset = deltaAsset
    end)
end

--==============================================================--
-- LIMPAR JPEG ANTIGO
--==============================================================--

pcall(function()
    if type(isfile) == "function" and type(delfile) == "function" then
        for _, file in ipairs({
            "grupo_lua_login_v1.jpg",
            "grupo_lua_login.jpg",
            "grupo-lua-login.jpg",
            "grupo_lua_diag.jpg",
        }) do
            if isfile(file) then
                delfile(file)
            end
        end
    end
end)

--==============================================================--
-- CORE ESTÁVEL DO LOGIN
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
