--==============================================================--
--        CAFEÍNA GAME EXPLORER V8 • MOBILE SPLIT VIEW + SITE FIX
--==============================================================--
--
-- EXPLORADOR DO JOGO VISÍVEL AO CLIENTE
--
-- • Navegação por Instances
-- • Serviços principais
-- • Pasta pai / voltar / home / atualizar
-- • Busca
-- • Seleção de objetos
-- • Propriedades úteis
-- • Preview de ImageLabel/ImageButton/Decal/Texture
-- • Editor local de propriedades suportadas
-- • Exportar objeto selecionado
-- • Copiar objeto selecionado
-- • Salvar localmente ou enviar para servidor
-- • Copiar/exportar todos os resultados do Scan
-- • Exportar TODO o Explorer visível ao cliente
-- • Streaming em chunks ~4 MB
-- • Retry automático por chunk
-- • Cancelar upload
-- • Limite configurável de ~250 MB
-- • Link de download exibido no topo
-- • Botão para copiar link
-- • Atributos
-- • Filhos
-- • Scanner com barra de progresso
-- • Pastas virtuais de resultados
-- • Remotes
-- • Tools
-- • Values
-- • GUI
-- • Models
-- • Scripts visíveis
-- • Players
-- • Objetos com atributos
-- • Status de scanner
-- • Suporte mobile
-- • Menu arrastável
-- • Ícone minimizado arrastável
--
-- IMPORTANTE
-- Este script só enxerga objetos replicados/visíveis ao cliente.
-- Ele não acessa conteúdo exclusivamente server-side.
--
--==============================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local API = {
    setclipboard = typeof(setclipboard) == "function" and setclipboard or nil,
    writefile = typeof(writefile) == "function" and writefile or nil,
    makefolder = typeof(makefolder) == "function" and makefolder or nil,

    request =
        typeof(request) == "function" and request
        or typeof(http_request) == "function" and http_request
        or (
            syn
            and typeof(syn.request) == "function"
            and syn.request
        )
        or nil,
}


--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    MAX_VISIBLE_ROWS = 500,
    SEARCH_DELAY = 0.15,
    MAX_SCAN_OBJECTS = 30000,
    SCAN_YIELD_EVERY = 120,
    MAX_VIRTUAL_RESULTS = 5000,
    EXPORT_FOLDER = "Cafeina_Game_Explorer",
    EXPORT_MAX_CHILDREN = 120,
    EXPORT_MAX_SCAN_RESULTS_PER_GROUP = 5000,

    -- Upload remoto
    UPLOAD_ENDPOINT = "https://cafe-na-ia.onrender.com/upload",

    -- Upload progressivo em chunks.
    UPLOAD_TOKEN = "",

    -- Backend atual: 300 MB final / 6 MB por requisição.
    -- Mantemos margem de segurança no mobile.
    FULL_EXPORT_MAX_TOTAL_BYTES = 250 * 1024 * 1024,
    FULL_EXPORT_CHUNK_TARGET_BYTES = 4 * 1024 * 1024,
    FULL_EXPORT_CHUNK_SOFT_BYTES = 3500000,

    -- O limite principal passa a ser bytes; este é apenas um teto anti-loop.
    FULL_EXPORT_MAX_OBJECTS = 1000000,
    FULL_EXPORT_YIELD_EVERY = 100,
    FULL_EXPORT_MAX_ATTRIBUTES_PER_OBJECT = 40,

    UPLOAD_RETRIES = 3,
    UPLOAD_RETRY_DELAY = 1.25,
    UPLOAD_REQUEST_TIMEOUT = 75,
}

local COLORS = {
    BG = Color3.fromRGB(12, 12, 15),
    PANEL = Color3.fromRGB(20, 20, 24),
    PANEL2 = Color3.fromRGB(27, 27, 33),
    PANEL3 = Color3.fromRGB(34, 34, 41),

    RED = Color3.fromRGB(238, 38, 52),
    RED_DARK = Color3.fromRGB(110, 20, 29),

    TEXT = Color3.fromRGB(244, 244, 248),
    SUB = Color3.fromRGB(155, 155, 168),
    STROKE = Color3.fromRGB(52, 52, 62),

    GREEN = Color3.fromRGB(72, 214, 121),
    YELLOW = Color3.fromRGB(240, 185, 60),
    BLUE = Color3.fromRGB(90, 160, 255),
}

--==============================================================--
-- CLEANUP
--==============================================================--

local old = PlayerGui:FindFirstChild("CafeinaGameExplorer")
if old then
    old:Destroy()
end

--==============================================================--
-- STATE
--==============================================================--

local CurrentParent = game
local CurrentRows = {}
local FilteredRows = {}
local History = {}

local SelectedInstance = nil

local SearchGeneration = 0
local RenderGeneration = 0
local ScanGeneration = 0

local ScanRunning = false
local ScanFoundSomething = false

local FullExportRunning = false
local FullExportGeneration = 0
local LastDownloadURL = ""

local VirtualFolders = {
    REMOTES = {},
    TOOLS = {},
    VALUES = {},
    GUI = {},
    MODELS = {},
    SCRIPTS = {},
    PLAYERS = {},
    ATTRIBUTES = {},
}

local VirtualFolderNames = {
    REMOTES = "Remotes",
    TOOLS = "Tools",
    VALUES = "Values",
    GUI = "GUI",
    MODELS = "Models",
    SCRIPTS = "Scripts visíveis",
    PLAYERS = "Players",
    ATTRIBUTES = "Com atributos",
}

local CurrentVirtualFolder = nil

--==============================================================--
-- HELPERS
--==============================================================--

local function safeCall(fn, ...)
    local args = {...}
    return pcall(function()
        return fn(table.unpack(args))
    end)
end

local function fullName(inst)
    if not inst then
        return "?"
    end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    return ok and result or inst.Name
end

local function classIcon(inst)
    if not inst then
        return "•"
    end

    if inst:IsA("Folder") then
        return "▣"
    elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        return "◈"
    elseif inst:IsA("Tool") then
        return "◆"
    elseif inst:IsA("Model") then
        return "▧"
    elseif inst:IsA("BasePart") then
        return "■"
    elseif inst:IsA("GuiObject") then
        return "▤"
    elseif inst:IsA("ValueBase") then
        return "●"
    elseif inst:IsA("LuaSourceContainer") then
        return "◇"
    elseif inst:IsA("Player") then
        return "♟"
    end

    return "•"
end

local function instanceSummary(inst)
    if not inst then
        return ""
    end

    if inst:IsA("RemoteEvent") then
        return "RemoteEvent"
    elseif inst:IsA("RemoteFunction") then
        return "RemoteFunction"
    elseif inst:IsA("Tool") then
        return "Tool"
    elseif inst:IsA("ValueBase") then
        local valueText = "?"
        pcall(function()
            valueText = tostring(inst.Value)
        end)
        return inst.ClassName .. " • " .. valueText
    elseif inst:IsA("BasePart") then
        return inst.ClassName
    elseif inst:IsA("Model") then
        return "Model • " .. tostring(#inst:GetChildren()) .. " filho(s)"
    elseif inst:IsA("Folder") then
        return "Pasta • " .. tostring(#inst:GetChildren()) .. " item(ns)"
    elseif inst:IsA("Player") then
        return "Player"
    end

    return inst.ClassName
end

local function getMainServices()
    local names = {
        "Workspace",
        "ReplicatedStorage",
        "ReplicatedFirst",
        "Players",
        "Lighting",
        "StarterGui",
        "StarterPlayer",
        "SoundService",
        "Teams",
    }

    local result = {}

    for _, serviceName in ipairs(names) do
        local ok, service = pcall(function()
            return game:GetService(serviceName)
        end)

        if ok and service then
            result[#result + 1] = service
        end
    end

    return result
end

--==============================================================--
-- DECLARAÇÕES ANTECIPADAS
-- Corrige referências usadas por funções criadas antes da GUI.
--==============================================================--

local setStatus
local setScanStatus
local buildDetails

--==============================================================--
-- EXPORT / COPY HELPERS
--==============================================================--

local function sanitizeFileName(name)
    name = tostring(name or "export")
    name = name:gsub("[\\/:*?\"<>|]", "_")
    name = name:gsub("%s+", "_")

    if name == "" then
        name = "export"
    end

    return name
end

local function ensureExportFolder()
    if not API.makefolder then
        return
    end

    pcall(function()
        API.makefolder(CONFIG.EXPORT_FOLDER)
    end)
end

local function copyToClipboard(textValue)
    if not API.setclipboard then
        return false, "Clipboard não disponível"
    end

    local ok, err = pcall(function()
        API.setclipboard(tostring(textValue or ""))
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

local function writeExportFile(fileName, content)
    if not API.writefile then
        return false, "writefile não disponível"
    end

    ensureExportFolder()

    local destination =
        CONFIG.EXPORT_FOLDER
        .. "/"
        .. sanitizeFileName(fileName)

    local ok, err = pcall(function()
        API.writefile(destination, tostring(content or ""))
    end)

    if not ok then
        return false, tostring(err)
    end

    return true, destination
end

local function decodeResponseBody(response)
    if type(response) == "string" then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(response)
        end)

        if ok and type(decoded) == "table" then
            return decoded
        end

        return nil
    end

    if type(response) ~= "table" then
        return nil
    end

    local body =
        response.Body
        or response.body
        or response.ResponseBody
        or response.responseBody

    if type(body) ~= "string" then
        return nil
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if ok and type(decoded) == "table" then
        return decoded
    end

    return nil
end

local function requestJSON(url, payload)
    if not API.request then
        return false, "request/http_request não disponível"
    end

    local body = HttpService:JSONEncode(payload)

    local ok, response = pcall(function()
        return API.request({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
            },
            Body = body,
        })
    end)

    if not ok then
        return false, tostring(response)
    end

    local statusCode = nil

    if type(response) == "table" then
        statusCode = tonumber(
            response.StatusCode
            or response.Status
            or response.status_code
            or response.status
        )
    end

    local decoded = decodeResponseBody(response)

    if statusCode and statusCode >= 400 then
        return false,
            (
                decoded
                and (
                    decoded.message
                    or decoded.error
                )
            )
            or ("HTTP " .. tostring(statusCode))
    end

    if not decoded then
        return false, "Resposta inválida do servidor"
    end

    return true, decoded
end

local function requestJSONWithTimeout(url, payload, timeoutSeconds)
    local finished = false
    local requestOk = false
    local requestResult = nil

    task.spawn(function()
        local ok, result = requestJSON(url, payload)
        requestOk = ok
        requestResult = result
        finished = true
    end)

    local startedAt = os.clock()
    local timeout = tonumber(timeoutSeconds) or 30

    while not finished do
        if os.clock() - startedAt >= timeout then
            return false,
                "Tempo limite de "
                .. tostring(timeout)
                .. "s ao conectar com o servidor"
        end

        task.wait(0.1)
    end

    return requestOk, requestResult
end

local function requestJSONWithRetry(url, payload, retryLabel)
    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.UPLOAD_RETRIES do
        local ok, result = requestJSONWithTimeout(
            url,
            payload,
            CONFIG.UPLOAD_REQUEST_TIMEOUT
        )

        if ok then
            return true, result
        end

        lastError = tostring(result)

        if attempt < CONFIG.UPLOAD_RETRIES then
            setStatus(
                tostring(retryLabel or "Upload")
                .. " • tentativa "
                .. tostring(attempt + 1)
                .. "/"
                .. tostring(CONFIG.UPLOAD_RETRIES),
                COLORS.YELLOW
            )

            task.wait(
                CONFIG.UPLOAD_RETRY_DELAY
                * attempt
            )
        end
    end

    return false, lastError
end

local function uploadStartSession(metadata, fileName, sourceName)
    local payload = {
        filename = sanitizeFileName(
            fileName or "Cafeina_Explorer_Completo.json"
        ),
        source = tostring(
            sourceName or "cafeina-game-explorer"
        ),
        metadata = metadata or {},
    }

    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end

    return requestJSONWithRetry(
        CONFIG.UPLOAD_ENDPOINT .. "/start",
        payload,
        "Iniciando upload"
    )
end

local function uploadChunk(uploadId, index, objects)
    local payload = {
        uploadId = uploadId,
        index = index,
        objects = objects,
    }

    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end

    return requestJSONWithRetry(
        CONFIG.UPLOAD_ENDPOINT .. "/chunk",
        payload,
        "Enviando parte " .. tostring(index)
    )
end

local function uploadFinish(uploadId, totalChunks, summary)
    local payload = {
        uploadId = uploadId,
        totalChunks = totalChunks,
        summary = summary,
    }

    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end

    return requestJSONWithRetry(
        CONFIG.UPLOAD_ENDPOINT .. "/finish",
        payload,
        "Finalizando upload"
    )
end

local function uploadCancel(uploadId)
    if not uploadId or uploadId == "" then
        return
    end

    local payload = {
        uploadId = uploadId,
    }

    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end

    task.spawn(function()
        pcall(function()
            requestJSON(
                CONFIG.UPLOAD_ENDPOINT .. "/cancel",
                payload
            )
        end)
    end)
end


--==============================================================--
-- UPLOAD DE EXPORTAÇÃO INDIVIDUAL
-- Usado pelos botões "Enviar objeto" e "Enviar Scan".
--==============================================================--

local function uploadExportFile(fileName, content)
    if not API.request then
        return false, "request/http_request não disponível"
    end

    local text = tostring(content or "")

    if text == "" then
        return false, "Conteúdo vazio"
    end

    local metadata = {
        generatedBy = "CAFEÍNA GAME EXPLORER",
        version = "V8",
        generatedAt = os.time(),
        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
            creatorId = game.CreatorId,
        },
        export = {
            type = "single-export",
            originalFileName = tostring(fileName),
            sourceBytes = #text,
        },
    }

    local startOk, startResult =
        uploadStartSession(
            metadata,
            fileName,
            "cafeina-game-explorer"
        )

    if not startOk then
        return false, tostring(startResult)
    end

    if type(startResult) ~= "table"
        or not startResult.uploadId
    then
        return false, "Servidor não retornou uploadId"
    end

    local uploadId = tostring(startResult.uploadId)

    -- Arquivos JSON pequenos permanecem estruturados em um único objeto.
    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(text)
    end)

    local chunkPayloads = {}

    if decodeOk
        and type(decoded) == "table"
        and #text <= 1000000
    then
        chunkPayloads[1] = {
            {
                exportType = "cafeina-export",
                fileName = tostring(fileName),
                part = 1,
                totalParts = 1,
                encoding = "json",
                data = decoded,
            }
        }
    else
        -- ~1 MB de texto bruto por parte mantém folga ampla em relação
        -- ao limite de 6 MB do backend após JSONEncode.
        local maxRawPartBytes = 1000000
        local parts = {}
        local cursor = 1

        while cursor <= #text do
            local lastByte =
                math.min(
                    #text,
                    cursor + maxRawPartBytes - 1
                )

            -- Evita cortar no meio de um caractere UTF-8.
            if lastByte < #text then
                while lastByte > cursor do
                    local nextByte =
                        string.byte(text, lastByte + 1)

                    if not nextByte
                        or nextByte < 128
                        or nextByte > 191
                    then
                        break
                    end

                    lastByte -= 1
                end
            end

            if lastByte < cursor then
                lastByte =
                    math.min(
                        #text,
                        cursor + maxRawPartBytes - 1
                    )
            end

            parts[#parts + 1] =
                text:sub(cursor, lastByte)

            cursor = lastByte + 1

            if #parts > 400 then
                uploadCancel(uploadId)

                return false,
                    "Arquivo individual grande demais para upload"
            end
        end

        for index, partText in ipairs(parts) do
            chunkPayloads[index] = {
                {
                    exportType = "cafeina-export-part",
                    fileName = tostring(fileName),
                    part = index,
                    totalParts = #parts,
                    encoding = "utf8-text",
                    content = partText,
                }
            }
        end
    end

    for index, objects in ipairs(chunkPayloads) do
        setStatus(
            "Enviando parte "
            .. tostring(index)
            .. "/"
            .. tostring(#chunkPayloads)
            .. "...",
            COLORS.YELLOW
        )

        local chunkOk, chunkResult =
            uploadChunk(
                uploadId,
                index,
                objects
            )

        if not chunkOk then
            uploadCancel(uploadId)

            return false,
                "Parte "
                .. tostring(index)
                .. ": "
                .. tostring(chunkResult)
        end

        task.wait()
    end

    local finishOk, finishResult =
        uploadFinish(
            uploadId,
            #chunkPayloads,
            {
                type = "single-export",
                originalFileName = tostring(fileName),
                sourceBytes = #text,
                parts = #chunkPayloads,
            }
        )

    if not finishOk then
        uploadCancel(uploadId)
        return false, tostring(finishResult)
    end

    if type(finishResult) ~= "table" then
        return false, "Resposta final inválida"
    end

    local url =
        finishResult.downloadUrl
        or finishResult.url
        or finishResult.download_url
        or finishResult.link

    if not url
        or tostring(url) == ""
    then
        return false,
            "Upload concluído, mas o servidor não retornou link"
    end

    LastDownloadURL = tostring(url)

    return true, LastDownloadURL
end

local function safeProperty(inst, propertyName)
    local ok, value = pcall(function()
        return inst[propertyName]
    end)

    if ok then
        return value
    end

    return nil
end

local function serializeAttributes(inst)
    local attrs = {}

    pcall(function()
        attrs = inst:GetAttributes()
    end)

    local output = {}

    for key, value in pairs(attrs) do
        output[tostring(key)] = tostring(value)
    end

    return output
end

local function serializeInstance(inst)
    if not inst then
        return nil
    end

    local data = {
        name = inst.Name,
        className = inst.ClassName,
        path = fullName(inst),
        childCount = #inst:GetChildren(),
        attributes = serializeAttributes(inst),
    }

    if inst:IsA("ValueBase") then
        data.value = tostring(safeProperty(inst, "Value"))
    end

    if inst:IsA("BasePart") then
        data.properties = {
            anchored = tostring(safeProperty(inst, "Anchored")),
            canCollide = tostring(safeProperty(inst, "CanCollide")),
            transparency = tostring(safeProperty(inst, "Transparency")),
            position = tostring(safeProperty(inst, "Position")),
            size = tostring(safeProperty(inst, "Size")),
        }
    elseif inst:IsA("GuiObject") then
        data.properties = {
            visible = tostring(safeProperty(inst, "Visible")),
            backgroundTransparency = tostring(
                safeProperty(inst, "BackgroundTransparency")
            ),
        }
    elseif inst:IsA("ImageLabel")
        or inst:IsA("ImageButton")
    then
        data.properties = data.properties or {}
        data.properties.image = tostring(safeProperty(inst, "Image"))
        data.properties.imageTransparency =
            tostring(safeProperty(inst, "ImageTransparency"))
    elseif inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        data.properties = {
            texture = tostring(safeProperty(inst, "Texture")),
            transparency = tostring(safeProperty(inst, "Transparency")),
        }
    elseif inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
    then
        data.remoteType = inst.ClassName
    elseif inst:IsA("Tool") then
        data.properties = {
            requiresHandle = tostring(safeProperty(inst, "RequiresHandle")),
            canBeDropped = tostring(safeProperty(inst, "CanBeDropped")),
        }
    elseif inst:IsA("Player") then
        data.properties = {
            displayName = tostring(safeProperty(inst, "DisplayName")),
            userId = tostring(safeProperty(inst, "UserId")),
        }
    end

    local childSummaries = {}
    local children = inst:GetChildren()
    local limit = math.min(#children, CONFIG.EXPORT_MAX_CHILDREN)

    for i = 1, limit do
        local child = children[i]

        childSummaries[#childSummaries + 1] = {
            name = child.Name,
            className = child.ClassName,
            path = fullName(child),
        }
    end

    data.children = childSummaries

    if #children > limit then
        data.childrenTruncated = #children - limit
    end

    return data
end

local function selectedExportText(inst)
    local serialized = serializeInstance(inst)

    if not serialized then
        return "Nenhum objeto selecionado."
    end

    local ok, jsonText = pcall(function()
        return HttpService:JSONEncode(serialized)
    end)

    if ok then
        return jsonText
    end

    return buildDetails(inst)
end

local function scanExportTable()
    local report = {
        generatedBy = "CAFEÍNA GAME EXPLORER",
        scan = {},
    }

    for key, list in pairs(VirtualFolders) do
        local group = {
            name = VirtualFolderNames[key],
            count = #list,
            items = {},
        }

        local limit = math.min(
            #list,
            CONFIG.EXPORT_MAX_SCAN_RESULTS_PER_GROUP
        )

        for i = 1, limit do
            local inst = list[i]

            group.items[#group.items + 1] = {
                name = inst.Name,
                className = inst.ClassName,
                path = fullName(inst),
            }
        end

        if #list > limit then
            group.truncated = #list - limit
        end

        report.scan[key] = group
    end

    return report
end

local function scanExportText()
    local ok, result = pcall(function()
        return HttpService:JSONEncode(scanExportTable())
    end)

    if ok then
        return result
    end

    local lines = {
        "CAFEÍNA GAME EXPLORER • SCAN REPORT",
        "",
    }

    for key, list in pairs(VirtualFolders) do
        lines[#lines + 1] =
            VirtualFolderNames[key]
            .. " • "
            .. tostring(#list)

        for _, inst in ipairs(list) do
            lines[#lines + 1] =
                "  ["
                .. inst.ClassName
                .. "] "
                .. fullName(inst)
        end

        lines[#lines + 1] = ""
    end

    return table.concat(lines, "\n")
end

--==============================================================--
-- FULL EXPLORER EXPORT • STREAMING
--==============================================================--

local function compactAttributes(inst)
    local output = {}
    local count = 0
    local attrs = {}

    pcall(function()
        attrs = inst:GetAttributes()
    end)

    for key, value in pairs(attrs) do
        count += 1

        if count > CONFIG.FULL_EXPORT_MAX_ATTRIBUTES_PER_OBJECT then
            output.__truncated = true
            break
        end

        output[tostring(key)] = tostring(value)
    end

    return output
end

local function compactObjectSnapshot(inst)
    local data = {
        name = inst.Name,
        className = inst.ClassName,
        path = fullName(inst),
    }

    local attrs = compactAttributes(inst)

    if next(attrs) ~= nil then
        data.attributes = attrs
        data.hasAttributes = true
    end

    if inst:IsA("ValueBase") then
        local ok, value = pcall(function()
            return inst.Value
        end)

        if ok then
            data.value = tostring(value)
        end

        data.scanCategory = "VALUES"

    elseif inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
    then
        data.scanCategory = "REMOTES"

    elseif inst:IsA("Tool") then
        data.scanCategory = "TOOLS"

    elseif inst:IsA("Player") then
        data.scanCategory = "PLAYERS"

    elseif inst:IsA("Model") then
        data.scanCategory = "MODELS"

    elseif inst:IsA("LuaSourceContainer") then
        data.scanCategory = "SCRIPTS"

    elseif inst:IsA("GuiObject")
        or inst:IsA("ScreenGui")
    then
        data.scanCategory = "GUI"
    end

    if inst:IsA("ImageLabel")
        or inst:IsA("ImageButton")
    then
        local ok, image = pcall(function()
            return inst.Image
        end)

        if ok and image ~= "" then
            data.image = tostring(image)
        end

    elseif inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        local ok, texture = pcall(function()
            return inst.Texture
        end)

        if ok and texture ~= "" then
            data.image = tostring(texture)
        end
    end

    return data
end

local function buildExportMetadata()
    local roots = getMainServices()
    local services = {}

    for _, root in ipairs(roots) do
        services[#services + 1] = {
            name = root.Name,
            className = root.ClassName,
            path = fullName(root),
            childCount = #root:GetChildren(),
        }
    end

    return {
        generatedBy = "CAFEÍNA GAME EXPLORER",
        version = "V8",
        generatedAt = os.time(),

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
            creatorId = game.CreatorId,
        },

        services = services,
    }
end

local function newTraversalState()
    local roots = getMainServices()
    local stack = {}

    -- Push reversed so the first service is processed first.
    for i = #roots, 1, -1 do
        stack[#stack + 1] = roots[i]
    end

    return {
        stack = stack,
        visited = 0,
    }
end

local function traversalNext(state)
    local stack = state.stack

    if #stack == 0 then
        return nil
    end

    local inst = table.remove(stack)

    local ok, children = pcall(function()
        return inst:GetChildren()
    end)

    if ok and children then
        for i = #children, 1, -1 do
            stack[#stack + 1] = children[i]
        end
    end

    state.visited += 1

    return inst
end

local function encodedObjectSize(objectData)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(objectData)
    end)

    if not ok then
        return 0
    end

    return #encoded + 2
end

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function corner(object, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = object
    return c
end

local function stroke(object, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or COLORS.STROKE
    s.Thickness = thickness or 1
    s.Parent = object
    return s
end

local function label(parent, text, size, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = size or 12
    l.TextColor3 = color or COLORS.TEXT
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function button(parent, text)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.BackgroundColor3 = COLORS.PANEL3
    b.BorderSizePixel = 0
    b.Text = text or ""
    b.TextSize = 11
    b.TextColor3 = COLORS.TEXT
    b.Font = Enum.Font.GothamMedium
    corner(b, 8)
    stroke(b)
    b.Parent = parent
    return b
end

--==============================================================--
-- GUI ROOT
--==============================================================--

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaGameExplorer"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0.97, 0, 0.90, 0)
Main.Position = UDim2.new(0.015, 0, 0.05, 0)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
corner(Main, 14)
stroke(Main)
Main.Parent = Gui

local Constraint = Instance.new("UISizeConstraint")
Constraint.MinSize = Vector2.new(310, 450)
Constraint.MaxSize = Vector2.new(980, 820)
Constraint.Parent = Main

--==============================================================--
-- HEADER
--==============================================================--

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 55)
Header.BackgroundColor3 = COLORS.PANEL
Header.BorderSizePixel = 0
corner(Header, 14)
Header.Parent = Main

local Back = button(Header, "‹")
Back.Size = UDim2.fromOffset(34, 34)
Back.Position = UDim2.fromOffset(7, 10)

local Up = button(Header, "↑")
Up.Size = UDim2.fromOffset(34, 34)
Up.Position = UDim2.fromOffset(45, 10)

local Home = button(Header, "⌂")
Home.Size = UDim2.fromOffset(34, 34)
Home.Position = UDim2.fromOffset(83, 10)

local Title = label(Header, "CAFEÍNA GAME EXPLORER", 13, COLORS.TEXT)
Title.Font = Enum.Font.GothamBold
Title.Size = UDim2.new(1, -210, 0, 24)
Title.Position = UDim2.fromOffset(126, 5)

local Subtitle = label(Header, "CLIENT VISIBLE OBJECTS", 8, COLORS.RED)
Subtitle.Font = Enum.Font.GothamBold
Subtitle.Size = UDim2.new(1, -210, 0, 18)
Subtitle.Position = UDim2.fromOffset(126, 29)

local Minimize = button(Header, "−")
Minimize.Size = UDim2.fromOffset(34, 34)
Minimize.Position = UDim2.new(1, -76, 0, 10)

local Close = button(Header, "×")
Close.Size = UDim2.fromOffset(34, 34)
Close.Position = UDim2.new(1, -39, 0, 10)
Close.BackgroundColor3 = COLORS.RED_DARK

--==============================================================--
-- EXPORTAÇÃO COMPLETA • TOPO
--==============================================================--

local ExportPanel = Instance.new("Frame")
ExportPanel.Size = UDim2.new(1, -14, 0, 66)
ExportPanel.Position = UDim2.fromOffset(7, 60)
ExportPanel.BackgroundColor3 = COLORS.PANEL
ExportPanel.BorderSizePixel = 0
corner(ExportPanel, 10)
stroke(ExportPanel, COLORS.RED_DARK, 1)
ExportPanel.Parent = Main

local ExportTitle = label(
    ExportPanel,
    "EXPORTAR EXPLORER COMPLETO",
    10,
    COLORS.TEXT
)
ExportTitle.Font = Enum.Font.GothamBold
ExportTitle.Size = UDim2.new(0.34, -8, 0, 18)
ExportTitle.Position = UDim2.fromOffset(9, 3)

local ExportStatus = label(
    ExportPanel,
    "Pronto • até 250 MB • chunks ~4 MB",
    8,
    COLORS.SUB
)
ExportStatus.Size = UDim2.new(0.34, -8, 0, 17)
ExportStatus.Position = UDim2.fromOffset(9, 20)
ExportStatus.TextTruncate = Enum.TextTruncate.AtEnd

local UploadAll = button(
    ExportPanel,
    "ENVIAR TUDO"
)
UploadAll.Size = UDim2.fromOffset(76, 26)
UploadAll.Position = UDim2.new(0.34, 2, 0, 7)
UploadAll.BackgroundColor3 = COLORS.RED_DARK
UploadAll.TextSize = 7

local CancelUpload = button(
    ExportPanel,
    "CANCELAR"
)
CancelUpload.Size = UDim2.fromOffset(68, 26)
CancelUpload.Position = UDim2.new(0.34, 82, 0, 7)
CancelUpload.TextSize = 7
CancelUpload.Visible = false

local ExportProgressBG = Instance.new("Frame")
ExportProgressBG.Size = UDim2.new(1, -18, 0, 8)
ExportProgressBG.Position = UDim2.fromOffset(9, 40)
ExportProgressBG.BackgroundColor3 = COLORS.PANEL3
ExportProgressBG.BorderSizePixel = 0
corner(ExportProgressBG, 20)
ExportProgressBG.Parent = ExportPanel

local ExportProgressFill = Instance.new("Frame")
ExportProgressFill.Size = UDim2.new(0, 0, 1, 0)
ExportProgressFill.BackgroundColor3 = COLORS.RED
ExportProgressFill.BorderSizePixel = 0
corner(ExportProgressFill, 20)
ExportProgressFill.Parent = ExportProgressBG

local DownloadLink = Instance.new("TextBox")
DownloadLink.Size = UDim2.new(0.43, -4, 0, 28)
DownloadLink.Position = UDim2.new(0.49, 0, 0, 5)
DownloadLink.BackgroundColor3 = COLORS.PANEL2
DownloadLink.BorderSizePixel = 0
DownloadLink.Text = ""
DownloadLink.PlaceholderText = "O link de download aparecerá aqui..."
DownloadLink.ClearTextOnFocus = false
DownloadLink.TextEditable = false
DownloadLink.TextColor3 = COLORS.TEXT
DownloadLink.PlaceholderColor3 = COLORS.SUB
DownloadLink.TextSize = 8
DownloadLink.Font = Enum.Font.Code
DownloadLink.TextXAlignment = Enum.TextXAlignment.Left
corner(DownloadLink, 7)
stroke(DownloadLink)
DownloadLink.Parent = ExportPanel

local CopyDownloadLink = button(
    ExportPanel,
    "COPIAR LINK"
)
CopyDownloadLink.Size = UDim2.new(0.08, -4, 0, 28)
CopyDownloadLink.Position = UDim2.new(0.92, 0, 0, 5)
CopyDownloadLink.TextSize = 7
CopyDownloadLink.BackgroundColor3 = COLORS.RED

local function setExportStatus(textValue, progress, color)
    ExportStatus.Text = tostring(textValue or "")

    ExportProgressFill.Size =
        UDim2.new(
            math.clamp(tonumber(progress) or 0, 0, 1),
            0,
            1,
            0
        )

    if color then
        ExportProgressFill.BackgroundColor3 = color
    end
end

--==============================================================--
-- PATH
--==============================================================--

local PathBar = Instance.new("Frame")
PathBar.Size = UDim2.new(1, -14, 0, 38)
PathBar.Position = UDim2.fromOffset(7, 166)
PathBar.BackgroundColor3 = COLORS.PANEL
PathBar.BorderSizePixel = 0
corner(PathBar, 9)
stroke(PathBar)
PathBar.Parent = Main

local PathText = label(PathBar, "game", 9, COLORS.SUB)
PathText.Size = UDim2.new(1, -48, 1, 0)
PathText.Position = UDim2.fromOffset(10, 0)
PathText.TextTruncate = Enum.TextTruncate.AtEnd

local Refresh = button(PathBar, "↻")
Refresh.Size = UDim2.fromOffset(32, 28)
Refresh.Position = UDim2.new(1, -37, 0, 5)

--==============================================================--
-- SEARCH
--==============================================================--

local Search = Instance.new("TextBox")
Search.Size = UDim2.new(1, -14, 0, 36)
Search.Position = UDim2.fromOffset(7, 210)
Search.BackgroundColor3 = COLORS.PANEL
Search.BorderSizePixel = 0
Search.Text = ""
Search.PlaceholderText = "Pesquisar objeto..."
Search.ClearTextOnFocus = false
Search.TextColor3 = COLORS.TEXT
Search.PlaceholderColor3 = COLORS.SUB
Search.TextSize = 11
Search.Font = Enum.Font.Gotham
corner(Search, 9)
stroke(Search)
Search.Parent = Main

--==============================================================--
-- SCAN BAR
--==============================================================--

local ScanBar = Instance.new("Frame")
ScanBar.Size = UDim2.new(1, -14, 0, 58)
ScanBar.Position = UDim2.fromOffset(7, 132)
ScanBar.BackgroundColor3 = COLORS.PANEL
ScanBar.BorderSizePixel = 0
corner(ScanBar, 9)
stroke(ScanBar, COLORS.RED_DARK, 1)
ScanBar.Parent = Main

local ScanButton = button(ScanBar, "SCAN")
ScanButton.Size = UDim2.fromOffset(58, 26)
ScanButton.Position = UDim2.fromOffset(7, 6)
ScanButton.BackgroundColor3 = COLORS.RED_DARK
ScanButton.TextSize = 9

local ScanStatus = label(ScanBar, "Pronto para analisar o jogo", 9, COLORS.SUB)
ScanStatus.Size = UDim2.new(1, -260, 0, 18)
ScanStatus.Position = UDim2.fromOffset(72, 3)
ScanStatus.TextTruncate = Enum.TextTruncate.AtEnd

local ProgressBG = Instance.new("Frame")
ProgressBG.Size = UDim2.new(1, -79, 0, 9)
ProgressBG.Position = UDim2.fromOffset(72, 25)
ProgressBG.BackgroundColor3 = COLORS.PANEL3
ProgressBG.BorderSizePixel = 0
corner(ProgressBG, 20)
ProgressBG.Parent = ScanBar

local ProgressFill = Instance.new("Frame")
ProgressFill.Size = UDim2.new(0, 0, 1, 0)
ProgressFill.BackgroundColor3 = COLORS.RED
ProgressFill.BorderSizePixel = 0
corner(ProgressFill, 20)
ProgressFill.Parent = ProgressBG

local ScanHint = label(
    ScanBar,
    "Resultados serão separados em pastas virtuais",
    8,
    COLORS.SUB
)
ScanHint.Size = UDim2.new(1, -240, 0, 15)
ScanHint.Position = UDim2.fromOffset(7, 39)
ScanHint.TextTruncate = Enum.TextTruncate.AtEnd

local CopyScan = button(ScanBar, "COPIAR")
CopyScan.Size = UDim2.fromOffset(54, 22)
CopyScan.Position = UDim2.new(1, -177, 0, 34)
CopyScan.TextSize = 7
CopyScan.BackgroundColor3 = COLORS.RED_DARK

local ExportScan = button(ScanBar, "LOCAL")
ExportScan.Size = UDim2.fromOffset(54, 22)
ExportScan.Position = UDim2.new(1, -119, 0, 34)
ExportScan.TextSize = 7
ExportScan.Text = "BAIXAR"

local UploadScan = button(ScanBar, "SERVIDOR")
UploadScan.Size = UDim2.fromOffset(54, 22)
UploadScan.Position = UDim2.new(1, -61, 0, 34)
UploadScan.TextSize = 7
UploadScan.Text = "LINK"
UploadScan.BackgroundColor3 = COLORS.RED_DARK

--==============================================================--
-- CONTENT SPLIT
--==============================================================--

local Left = Instance.new("Frame")
Left.Size = UDim2.new(0.38, -10, 1, -202)
Left.Position = UDim2.fromOffset(7, 196)
Left.BackgroundColor3 = COLORS.PANEL
Left.BorderSizePixel = 0
corner(Left, 9)
stroke(Left)
Left.Parent = Main

-- Visualizador permanente em lateral; ocupa a maior área.
local Right = Instance.new("Frame")
Right.Size = UDim2.new(0.62, -11, 1, -202)
Right.Position = UDim2.new(0.38, 3, 0, 196)
Right.BackgroundColor3 = COLORS.PANEL
Right.BorderSizePixel = 0
corner(Right, 9)
stroke(Right, COLORS.RED_DARK, 1)
Right.Visible = true
Right.ZIndex = 20
Right.Parent = Main

-- Caminho e busca passam a fazer parte da coluna de arquivos.
PathBar.Parent = Left
PathBar.Size = UDim2.new(1, -8, 0, 30)
PathBar.Position = UDim2.fromOffset(4, 4)

Search.Parent = Left
Search.Size = UDim2.new(1, -8, 0, 32)
Search.Position = UDim2.fromOffset(4, 38)

--==============================================================--
-- LIST
--==============================================================--

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -8, 1, -78)
List.Position = UDim2.fromOffset(4, 74)
List.BackgroundTransparency = 1
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = COLORS.RED
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.CanvasSize = UDim2.new()
List.Parent = Left

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 4)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

--==============================================================--
-- DETAILS / INSPECTOR
--==============================================================--

local InspectorBack = button(Right, "×")
InspectorBack.Size = UDim2.fromOffset(28, 26)
InspectorBack.Position = UDim2.new(1, -33, 0, 4)
InspectorBack.ZIndex = 22
InspectorBack.TextSize = 9

local DetailsTitle = label(Right, "Nenhum objeto selecionado", 11, COLORS.TEXT)
DetailsTitle.Font = Enum.Font.GothamBold
DetailsTitle.Size = UDim2.new(1, -44, 0, 29)
DetailsTitle.Position = UDim2.fromOffset(8, 3)
DetailsTitle.TextTruncate = Enum.TextTruncate.AtEnd

local InspectorTabs = Instance.new("Frame")
InspectorTabs.Size = UDim2.new(1, -10, 0, 30)
InspectorTabs.Position = UDim2.fromOffset(5, 35)
InspectorTabs.BackgroundTransparency = 1
InspectorTabs.Parent = Right

local InfoTab = button(InspectorTabs, "INFO")
InfoTab.Size = UDim2.new(0.34, -3, 1, 0)
InfoTab.Position = UDim2.new(0, 0, 0, 0)
InfoTab.BackgroundColor3 = COLORS.RED_DARK

local PreviewTab = button(InspectorTabs, "PREVIEW")
PreviewTab.Size = UDim2.new(0.33, -3, 1, 0)
PreviewTab.Position = UDim2.new(0.34, 1, 0, 0)

local EditTab = button(InspectorTabs, "EDITAR")
EditTab.Size = UDim2.new(0.33, -3, 1, 0)
EditTab.Position = UDim2.new(0.67, 2, 0, 0)

local InspectorBody = Instance.new("Frame")
InspectorBody.Size = UDim2.new(1, -10, 1, -107)
InspectorBody.Position = UDim2.fromOffset(5, 68)
InspectorBody.BackgroundColor3 = COLORS.PANEL2
InspectorBody.BorderSizePixel = 0
corner(InspectorBody, 8)
stroke(InspectorBody)
InspectorBody.Parent = Right

local InspectorActions = Instance.new("Frame")
InspectorActions.Size = UDim2.new(1, -10, 0, 34)
InspectorActions.Position = UDim2.new(0, 5, 1, -38)
InspectorActions.BackgroundTransparency = 1
InspectorActions.ZIndex = 22
InspectorActions.Parent = Right

local CopySelected = button(InspectorActions, "COPIAR")
CopySelected.Size = UDim2.new(0.44, -3, 1, 0)
CopySelected.Position = UDim2.new(0, 0, 0, 0)
CopySelected.BackgroundColor3 = COLORS.RED

local ExportSelected = button(InspectorActions, "BAIXAR")
ExportSelected.Size = UDim2.new(0.27, -3, 1, 0)
ExportSelected.Position = UDim2.new(0.44, 2, 0, 0)
ExportSelected.BackgroundColor3 = COLORS.PANEL3

local UploadSelected = button(InspectorActions, "LINK")
UploadSelected.Size = UDim2.new(0.29, -3, 1, 0)
UploadSelected.Position = UDim2.new(0.71, 4, 0, 0)
UploadSelected.BackgroundColor3 = COLORS.RED_DARK

local DetailsScroll = Instance.new("ScrollingFrame")
DetailsScroll.Size = UDim2.new(1, -6, 1, -6)
DetailsScroll.Position = UDim2.fromOffset(3, 3)
DetailsScroll.BackgroundTransparency = 1
DetailsScroll.BorderSizePixel = 0
DetailsScroll.ScrollBarThickness = 3
DetailsScroll.ScrollBarImageColor3 = COLORS.RED
DetailsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
DetailsScroll.CanvasSize = UDim2.new()
DetailsScroll.Parent = InspectorBody

local DetailsText = Instance.new("TextLabel")
DetailsText.BackgroundTransparency = 1
DetailsText.Position = UDim2.fromOffset(8, 8)
DetailsText.Size = UDim2.new(1, -16, 0, 0)
DetailsText.AutomaticSize = Enum.AutomaticSize.Y
DetailsText.Text = "Selecione um arquivo/objeto à esquerda para visualizar aqui."
DetailsText.TextColor3 = COLORS.TEXT
DetailsText.TextSize = 10
DetailsText.Font = Enum.Font.Code
DetailsText.TextWrapped = true
DetailsText.TextXAlignment = Enum.TextXAlignment.Left
DetailsText.TextYAlignment = Enum.TextYAlignment.Top
DetailsText.Parent = DetailsScroll

local PreviewFrame = Instance.new("Frame")
PreviewFrame.Size = UDim2.new(1, -6, 1, -6)
PreviewFrame.Position = UDim2.fromOffset(3, 3)
PreviewFrame.BackgroundTransparency = 1
PreviewFrame.Visible = false
PreviewFrame.Parent = InspectorBody

local PreviewImage = Instance.new("ImageLabel")
PreviewImage.Size = UDim2.new(1, -16, 1, -52)
PreviewImage.Position = UDim2.fromOffset(8, 8)
PreviewImage.BackgroundColor3 = COLORS.PANEL3
PreviewImage.BorderSizePixel = 0
PreviewImage.ScaleType = Enum.ScaleType.Fit
PreviewImage.Image = ""
corner(PreviewImage, 8)
PreviewImage.Parent = PreviewFrame

local PreviewInfo = label(
    PreviewFrame,
    "Este objeto não possui imagem visualizável.",
    9,
    COLORS.SUB
)
PreviewInfo.Size = UDim2.new(1, -16, 0, 35)
PreviewInfo.Position = UDim2.new(0, 8, 1, -40)
PreviewInfo.TextWrapped = true

local EditScroll = Instance.new("ScrollingFrame")
EditScroll.Size = UDim2.new(1, -6, 1, -6)
EditScroll.Position = UDim2.fromOffset(3, 3)
EditScroll.BackgroundTransparency = 1
EditScroll.BorderSizePixel = 0
EditScroll.ScrollBarThickness = 3
EditScroll.ScrollBarImageColor3 = COLORS.RED
EditScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
EditScroll.CanvasSize = UDim2.new()
EditScroll.Visible = false
EditScroll.Parent = InspectorBody

local EditLayout = Instance.new("UIListLayout")
EditLayout.Padding = UDim.new(0, 6)
EditLayout.SortOrder = Enum.SortOrder.LayoutOrder
EditLayout.Parent = EditScroll

local EditPadding = Instance.new("UIPadding")
EditPadding.PaddingTop = UDim.new(0, 7)
EditPadding.PaddingBottom = UDim.new(0, 7)
EditPadding.PaddingLeft = UDim.new(0, 7)
EditPadding.PaddingRight = UDim.new(0, 7)
EditPadding.Parent = EditScroll

local InspectorMode = "INFO"

local function setInspectorMode(mode)
    InspectorMode = mode

    DetailsScroll.Visible = mode == "INFO"
    PreviewFrame.Visible = mode == "PREVIEW"
    EditScroll.Visible = mode == "EDITAR"

    InfoTab.BackgroundColor3 =
        mode == "INFO" and COLORS.RED_DARK or COLORS.PANEL3

    PreviewTab.BackgroundColor3 =
        mode == "PREVIEW" and COLORS.RED_DARK or COLORS.PANEL3

    EditTab.BackgroundColor3 =
        mode == "EDITAR" and COLORS.RED_DARK or COLORS.PANEL3
end

InfoTab.Activated:Connect(function()
    setInspectorMode("INFO")
end)

PreviewTab.Activated:Connect(function()
    setInspectorMode("PREVIEW")
end)

EditTab.Activated:Connect(function()
    setInspectorMode("EDITAR")
end)

local function clearEditRows()
    for _, child in ipairs(EditScroll:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function createEditRow(titleText, currentValue, applyCallback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 68)
    row.BackgroundColor3 = COLORS.PANEL3
    row.BorderSizePixel = 0
    corner(row, 8)
    stroke(row)
    row.Parent = EditScroll

    local title = label(row, titleText, 9, COLORS.SUB)
    title.Size = UDim2.new(1, -12, 0, 20)
    title.Position = UDim2.fromOffset(7, 3)

    local input = Instance.new("TextBox")
    input.Size = UDim2.new(1, -78, 0, 34)
    input.Position = UDim2.fromOffset(7, 27)
    input.BackgroundColor3 = COLORS.PANEL2
    input.BorderSizePixel = 0
    input.Text = tostring(currentValue)
    input.TextColor3 = COLORS.TEXT
    input.TextSize = 10
    input.Font = Enum.Font.Code
    input.ClearTextOnFocus = false
    corner(input, 7)
    stroke(input)
    input.Parent = row

    local apply = button(row, "APLICAR")
    apply.Size = UDim2.fromOffset(64, 34)
    apply.Position = UDim2.new(1, -71, 0, 27)
    apply.BackgroundColor3 = COLORS.RED_DARK
    apply.TextSize = 8

    apply.Activated:Connect(function()
        local ok, result = pcall(function()
            return applyCallback(input.Text)
        end)

        if ok then
            setStatus(
                tostring(titleText) .. " atualizado localmente",
                COLORS.GREEN
            )
        else
            setStatus(
                "Não foi possível alterar " .. tostring(titleText),
                COLORS.RED
            )
        end
    end)
end

local function createBoolEditRow(titleText, currentValue, applyCallback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = COLORS.PANEL3
    row.BorderSizePixel = 0
    corner(row, 8)
    stroke(row)
    row.Parent = EditScroll

    local title = label(row, titleText, 9, COLORS.SUB)
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.fromOffset(8, 0)

    local toggle = button(
        row,
        currentValue and "ON" or "OFF"
    )
    toggle.Size = UDim2.fromOffset(66, 30)
    toggle.Position = UDim2.new(1, -73, 0.5, -15)
    toggle.BackgroundColor3 =
        currentValue and COLORS.RED_DARK or COLORS.PANEL2

    local state = currentValue == true

    toggle.Activated:Connect(function()
        state = not state

        local ok = pcall(function()
            applyCallback(state)
        end)

        if ok then
            toggle.Text = state and "ON" or "OFF"
            toggle.BackgroundColor3 =
                state and COLORS.RED_DARK or COLORS.PANEL2

            setStatus(
                tostring(titleText) .. " atualizado localmente",
                COLORS.GREEN
            )
        else
            state = not state
            setStatus(
                "Não foi possível alterar " .. tostring(titleText),
                COLORS.RED
            )
        end
    end)
end

local function updatePreview(inst)
    PreviewImage.Image = ""
    PreviewInfo.Text =
        "Este objeto não possui imagem visualizável."

    if not inst then
        return
    end

    local imageId = nil
    local sourceName = nil

    if inst:IsA("ImageLabel")
        or inst:IsA("ImageButton")
    then
        imageId = inst.Image
        sourceName = "Image"

    elseif inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        imageId = inst.Texture
        sourceName = "Texture"
    end

    if imageId and imageId ~= "" then
        PreviewImage.Image = imageId
        PreviewInfo.Text =
            tostring(sourceName)
            .. ": "
            .. tostring(imageId)
    else
        PreviewInfo.Text =
            "Nenhuma imagem encontrada neste objeto."
    end
end

local function rebuildEditor(inst)
    clearEditRows()

    if not inst then
        local msg = label(
            EditScroll,
            "Selecione um objeto para editar propriedades locais.",
            9,
            COLORS.SUB
        )
        msg.Size = UDim2.new(1, 0, 0, 40)
        msg.TextWrapped = true
        return
    end

    createEditRow(
        "Name",
        inst.Name,
        function(value)
            inst.Name = tostring(value)
        end
    )

    if inst:IsA("ValueBase") then
        createEditRow(
            "Value",
            inst.Value,
            function(value)
                if inst:IsA("BoolValue") then
                    inst.Value =
                        tostring(value):lower() == "true"
                        or tostring(value) == "1"

                elseif inst:IsA("IntValue") then
                    inst.Value = math.floor(tonumber(value) or inst.Value)

                elseif inst:IsA("NumberValue") then
                    inst.Value = tonumber(value) or inst.Value

                elseif inst:IsA("StringValue") then
                    inst.Value = tostring(value)

                else
                    inst.Value = value
                end
            end
        )
    end

    if inst:IsA("BasePart") then
        createEditRow(
            "Transparency",
            inst.Transparency,
            function(value)
                inst.Transparency = math.clamp(
                    tonumber(value) or inst.Transparency,
                    0,
                    1
                )
            end
        )

        createBoolEditRow(
            "Anchored",
            inst.Anchored,
            function(value)
                inst.Anchored = value
            end
        )

        createBoolEditRow(
            "CanCollide",
            inst.CanCollide,
            function(value)
                inst.CanCollide = value
            end
        )
    end

    if inst:IsA("GuiObject") then
        createBoolEditRow(
            "Visible",
            inst.Visible,
            function(value)
                inst.Visible = value
            end
        )

        createEditRow(
            "BackgroundTransparency",
            inst.BackgroundTransparency,
            function(value)
                inst.BackgroundTransparency = math.clamp(
                    tonumber(value) or inst.BackgroundTransparency,
                    0,
                    1
                )
            end
        )
    end

    if inst:IsA("ImageLabel")
        or inst:IsA("ImageButton")
    then
        createEditRow(
            "Image",
            inst.Image,
            function(value)
                inst.Image = tostring(value)
                updatePreview(inst)
            end
        )

        createEditRow(
            "ImageTransparency",
            inst.ImageTransparency,
            function(value)
                inst.ImageTransparency = math.clamp(
                    tonumber(value) or inst.ImageTransparency,
                    0,
                    1
                )
            end
        )
    end

    if inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        createEditRow(
            "Texture",
            inst.Texture,
            function(value)
                inst.Texture = tostring(value)
                updatePreview(inst)
            end
        )

        createEditRow(
            "Transparency",
            inst.Transparency,
            function(value)
                inst.Transparency = math.clamp(
                    tonumber(value) or inst.Transparency,
                    0,
                    1
                )
            end
        )
    end

    if inst:IsA("Humanoid") then
        createEditRow(
            "WalkSpeed",
            inst.WalkSpeed,
            function(value)
                inst.WalkSpeed = tonumber(value) or inst.WalkSpeed
            end
        )

        createEditRow(
            "JumpPower",
            inst.JumpPower,
            function(value)
                inst.JumpPower = tonumber(value) or inst.JumpPower
            end
        )
    end

    local warning = label(
        EditScroll,
        "Alterações feitas aqui são locais ao cliente quando o jogo não replica essa propriedade de volta ao servidor.",
        8,
        COLORS.YELLOW
    )
    warning.Size = UDim2.new(1, 0, 0, 52)
    warning.TextWrapped = true
end

--==============================================================--
-- STATUS
--==============================================================--

local Status = Instance.new("Frame")
Status.Size = UDim2.new(1, -14, 0, 40)
Status.Position = UDim2.new(0, 7, 1, -47)
Status.BackgroundColor3 = COLORS.PANEL
Status.BorderSizePixel = 0
corner(Status, 9)
stroke(Status)
Status.Parent = Main

local Dot = Instance.new("Frame")
Dot.Size = UDim2.fromOffset(8, 8)
Dot.Position = UDim2.new(0, 11, 0.5, -4)
Dot.BackgroundColor3 = COLORS.GREEN
Dot.BorderSizePixel = 0
corner(Dot, 20)
Dot.Parent = Status

local StatusText = label(Status, "Pronto", 9, COLORS.SUB)
StatusText.Size = UDim2.new(1, -35, 1, 0)
StatusText.Position = UDim2.fromOffset(27, 0)
StatusText.TextTruncate = Enum.TextTruncate.AtEnd

setStatus = function(text, color)
    StatusText.Text = tostring(text or "")
    if color then
        Dot.BackgroundColor3 = color
    end
end

setScanStatus = function(text, progress, color)
    ScanStatus.Text = tostring(text or "")

    local p = math.clamp(tonumber(progress) or 0, 0, 1)
    ProgressFill.Size = UDim2.new(p, 0, 1, 0)

    if color then
        ProgressFill.BackgroundColor3 = color
    end
end

--==============================================================--
-- DETAILS BUILDER
--==============================================================--

buildDetails = function(inst)
    if not inst then
        return "Nenhum objeto selecionado."
    end

    local lines = {
        "CAFEÍNA GAME OBJECT",
        "",
        "Nome: " .. inst.Name,
        "Classe: " .. inst.ClassName,
        "Caminho: " .. fullName(inst),
        "",
        "Filhos: " .. tostring(#inst:GetChildren()),
    }

    local attrs = {}

    pcall(function()
        attrs = inst:GetAttributes()
    end)

    local attrCount = 0
    for _ in pairs(attrs) do
        attrCount += 1
    end

    lines[#lines + 1] = "Atributos: " .. tostring(attrCount)

    if inst:IsA("ValueBase") then
        local ok, value = pcall(function()
            return inst.Value
        end)

        if ok then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "VALOR"
            lines[#lines + 1] = tostring(value)
        end
    end

    if inst:IsA("BasePart") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "PARTE"
        lines[#lines + 1] = "Anchored: " .. tostring(inst.Anchored)
        lines[#lines + 1] = "CanCollide: " .. tostring(inst.CanCollide)
        lines[#lines + 1] = "Transparency: " .. tostring(inst.Transparency)
        lines[#lines + 1] = "Position: " .. tostring(inst.Position)
        lines[#lines + 1] = "Size: " .. tostring(inst.Size)
    end

    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "REMOTE"
        lines[#lines + 1] = "Tipo: " .. inst.ClassName
        lines[#lines + 1] = "Path: " .. fullName(inst)
    end

    if inst:IsA("Tool") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "TOOL"
        lines[#lines + 1] = "RequiresHandle: " .. tostring(inst.RequiresHandle)
        lines[#lines + 1] = "CanBeDropped: " .. tostring(inst.CanBeDropped)
    end

    if inst:IsA("Player") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "PLAYER"
        lines[#lines + 1] = "DisplayName: " .. tostring(inst.DisplayName)
        lines[#lines + 1] = "UserId: " .. tostring(inst.UserId)
    end

    if attrCount > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "ATRIBUTOS"

        for key, value in pairs(attrs) do
            lines[#lines + 1] =
                tostring(key) .. " = " .. tostring(value)
        end
    end

    local children = inst:GetChildren()

    if #children > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "FILHOS"

        local limit = math.min(#children, 60)

        for i = 1, limit do
            local child = children[i]
            lines[#lines + 1] =
                child.ClassName .. " • " .. child.Name
        end

        if #children > limit then
            lines[#lines + 1] =
                "[... " .. tostring(#children - limit) .. " adicional(is)]"
        end
    end

    return table.concat(lines, "\n")
end

local function selectInstance(inst)
    SelectedInstance = inst

    DetailsTitle.Text = inst and inst.Name or "Nenhum objeto"
    DetailsText.Text = buildDetails(inst)
    DetailsScroll.CanvasPosition = Vector2.new(0, 0)

    updatePreview(inst)
    rebuildEditor(inst)
    setInspectorMode("INFO")

    Left.Visible = true
    Right.Visible = true
end

InspectorBack.Activated:Connect(function()
    selectInstance(nil)
end)

CopySelected.Activated:Connect(function()
    if not SelectedInstance then
        setStatus("Nenhum objeto selecionado", COLORS.YELLOW)
        return
    end

    local ok, err = copyToClipboard(
        selectedExportText(SelectedInstance)
    )

    setStatus(
        ok and "Objeto copiado" or tostring(err),
        ok and COLORS.GREEN or COLORS.YELLOW
    )
end)

ExportSelected.Activated:Connect(function()
    if not SelectedInstance then
        setStatus("Nenhum objeto selecionado", COLORS.YELLOW)
        return
    end

    local fileName =
        sanitizeFileName(SelectedInstance.Name)
        .. "_"
        .. sanitizeFileName(SelectedInstance.ClassName)
        .. ".json"

    local ok, result = writeExportFile(
        fileName,
        selectedExportText(SelectedInstance)
    )

    setStatus(
        ok and ("Exportado: " .. tostring(result)) or tostring(result),
        ok and COLORS.GREEN or COLORS.YELLOW
    )
end)

UploadSelected.Activated:Connect(function()
    if not SelectedInstance then
        setStatus("Nenhum objeto selecionado", COLORS.YELLOW)
        return
    end

    local fileName =
        sanitizeFileName(SelectedInstance.Name)
        .. "_"
        .. sanitizeFileName(SelectedInstance.ClassName)
        .. ".json"

    setStatus(
        "Enviando para o servidor...",
        COLORS.YELLOW
    )

    task.spawn(function()
        local ok, result = uploadExportFile(
            fileName,
            selectedExportText(SelectedInstance)
        )

        if ok then
            if API.setclipboard then
                pcall(function()
                    API.setclipboard(result)
                end)
            end

            setStatus(
                "Link copiado: " .. tostring(result),
                COLORS.GREEN
            )
        else
            setStatus(
                "Falha no upload: " .. tostring(result),
                COLORS.RED
            )
        end
    end)
end)

--==============================================================--
-- LIST RENDER
--==============================================================--

local function clearList()
    for _, child in ipairs(List:GetChildren()) do
        if child:IsA("GuiObject")
            and child ~= ListLayout
        then
            child:Destroy()
        end
    end
end

local function createRow(inst, order, virtualName)
    local Row = Instance.new("TextButton")
    Row.Size = UDim2.new(1, -4, 0, 54)
    Row.BackgroundColor3 = COLORS.PANEL2
    Row.BorderSizePixel = 0
    Row.AutoButtonColor = false
    Row.Text = ""
    Row.LayoutOrder = order
    corner(Row, 8)
    stroke(Row)
    Row.Parent = List

    local isVirtual = type(inst) == "table" and inst.__virtual == true

    local iconText
    local nameText
    local metaText

    if isVirtual then
        iconText = "▣"
        nameText = inst.name
        metaText = tostring(inst.count) .. " resultado(s)"
    else
        iconText = classIcon(inst)
        nameText = inst.Name
        metaText = instanceSummary(inst)
    end

    local Icon = label(
        Row,
        iconText,
        15,
        isVirtual and COLORS.RED or COLORS.SUB
    )
    Icon.Size = UDim2.fromOffset(38, 54)
    Icon.Position = UDim2.fromOffset(2, 0)
    Icon.TextXAlignment = Enum.TextXAlignment.Center

    local Name = label(Row, nameText, 11, COLORS.TEXT)
    Name.Font = Enum.Font.GothamMedium
    Name.Size = UDim2.new(1, -76, 0, 25)
    Name.Position = UDim2.fromOffset(40, 4)
    Name.TextTruncate = Enum.TextTruncate.AtEnd

    local Meta = label(Row, metaText, 8, COLORS.SUB)
    Meta.Size = UDim2.new(1, -76, 0, 17)
    Meta.Position = UDim2.fromOffset(40, 29)
    Meta.TextTruncate = Enum.TextTruncate.AtEnd

    local Arrow = label(Row, "›", 17, COLORS.SUB)
    Arrow.Size = UDim2.fromOffset(28, 54)
    Arrow.Position = UDim2.new(1, -31, 0, 0)
    Arrow.TextXAlignment = Enum.TextXAlignment.Center

    Row.Activated:Connect(function()
        if isVirtual then
            CurrentVirtualFolder = inst.key
            CurrentParent = nil
            History[#History + 1] = {
                parent = game,
                virtual = "__SCAN_ROOT",
            }

            Search.Text = ""
            PathText.Text =
                "Scan/" .. tostring(inst.name)

            CurrentRows = {}

            for _, resultInst in ipairs(VirtualFolders[inst.key]) do
                CurrentRows[#CurrentRows + 1] = resultInst
            end

            -- render below
            RenderGeneration += 1
        else
            selectInstance(inst)

            local children = inst:GetChildren()

            if #children > 0 then
                History[#History + 1] = {
                    parent = CurrentParent,
                    virtual = CurrentVirtualFolder,
                }

                CurrentVirtualFolder = nil
                CurrentParent = inst
                Search.Text = ""
                PathText.Text = fullName(inst)

                CurrentRows = children
            end
        end

        -- force render
        SearchGeneration += 1

        task.defer(function()
            clearList()

            local query = Search.Text:lower()
            FilteredRows = {}

            for _, item in ipairs(CurrentRows) do
                local itemName =
                    (type(item) == "table" and item.name or item.Name):lower()

                if query == ""
                    or itemName:find(query, 1, true)
                then
                    FilteredRows[#FilteredRows + 1] = item
                end
            end

            local limit = math.min(
                #FilteredRows,
                CONFIG.MAX_VISIBLE_ROWS
            )

            for i = 1, limit do
                createRow(FilteredRows[i], i)
            end

            setStatus(
                tostring(#FilteredRows) .. " item(ns)",
                COLORS.GREEN
            )
        end)
    end)
end

local function renderRows()
    clearList()

    local query = Search.Text:lower()
    FilteredRows = {}

    for _, item in ipairs(CurrentRows) do
        local itemName =
            (type(item) == "table" and item.name or item.Name):lower()

        if query == ""
            or itemName:find(query, 1, true)
        then
            FilteredRows[#FilteredRows + 1] = item
        end
    end

    table.sort(
        FilteredRows,
        function(a, b)
            local an =
                (type(a) == "table" and a.name or a.Name):lower()
            local bn =
                (type(b) == "table" and b.name or b.Name):lower()

            return an < bn
        end
    )

    local limit = math.min(
        #FilteredRows,
        CONFIG.MAX_VISIBLE_ROWS
    )

    for i = 1, limit do
        local ok, err = pcall(function()
            createRow(FilteredRows[i], i)
        end)

        if not ok then
            warn("[CAFEÍNA GAME EXPLORER] Render error:", err)
        end
    end

    if #FilteredRows > CONFIG.MAX_VISIBLE_ROWS then
        setStatus(
            tostring(#FilteredRows)
            .. " resultados • mostrando "
            .. tostring(CONFIG.MAX_VISIBLE_ROWS),
            COLORS.YELLOW
        )
    else
        setStatus(
            tostring(#FilteredRows) .. " item(ns)",
            COLORS.GREEN
        )
    end
end

--==============================================================--
-- NAVIGATION
--==============================================================--

local function openGameRoot()
    Right.Visible = true
    Left.Visible = true

    CurrentVirtualFolder = nil
    CurrentParent = game
    CurrentRows = getMainServices()

    History = {}
    Search.Text = ""
    PathText.Text = "game"

    selectInstance(nil)
    renderRows()
end

local function openScanRoot()
    Right.Visible = true
    Left.Visible = true

    CurrentParent = nil
    CurrentVirtualFolder = "__SCAN_ROOT"
    CurrentRows = {}

    for key, list in pairs(VirtualFolders) do
        if #list > 0 then
            CurrentRows[#CurrentRows + 1] = {
                __virtual = true,
                key = key,
                name = VirtualFolderNames[key],
                count = #list,
            }
        end
    end

    Search.Text = ""
    PathText.Text = "Scan"

    renderRows()
end

Back.Activated:Connect(function()
    if #History == 0 then
        setStatus("Sem histórico anterior", COLORS.YELLOW)
        return
    end

    local previous = table.remove(History)

    if previous.virtual == "__SCAN_ROOT" then
        openScanRoot()
        return
    end

    CurrentParent = previous.parent or game
    CurrentVirtualFolder = previous.virtual

    if CurrentVirtualFolder
        and VirtualFolders[CurrentVirtualFolder]
    then
        CurrentRows = VirtualFolders[CurrentVirtualFolder]
        PathText.Text =
            "Scan/" .. tostring(VirtualFolderNames[CurrentVirtualFolder])
    else
        CurrentRows =
            CurrentParent == game
            and getMainServices()
            or CurrentParent:GetChildren()

        PathText.Text =
            CurrentParent == game
            and "game"
            or fullName(CurrentParent)
    end

    Search.Text = ""
    renderRows()
end)

Up.Activated:Connect(function()
    if CurrentVirtualFolder then
        openScanRoot()
        return
    end

    if not CurrentParent or CurrentParent == game then
        setStatus("Você já está na raiz", COLORS.YELLOW)
        return
    end

    local parent = CurrentParent.Parent

    if not parent then
        openGameRoot()
        return
    end

    History[#History + 1] = {
        parent = CurrentParent,
        virtual = nil,
    }

    CurrentParent = parent

    if CurrentParent == game then
        CurrentRows = getMainServices()
        PathText.Text = "game"
    else
        CurrentRows = CurrentParent:GetChildren()
        PathText.Text = fullName(CurrentParent)
    end

    Search.Text = ""
    renderRows()
end)

Home.Activated:Connect(
    openGameRoot
)

Refresh.Activated:Connect(function()
    if CurrentVirtualFolder == "__SCAN_ROOT" then
        openScanRoot()

    elseif CurrentVirtualFolder
        and VirtualFolders[CurrentVirtualFolder]
    then
        CurrentRows = VirtualFolders[CurrentVirtualFolder]
        renderRows()

    elseif CurrentParent then
        CurrentRows =
            CurrentParent == game
            and getMainServices()
            or CurrentParent:GetChildren()

        renderRows()
    end
end)

--==============================================================--
-- SEARCH
--==============================================================--

Search:GetPropertyChangedSignal("Text"):Connect(function()
    SearchGeneration += 1
    local generation = SearchGeneration

    task.delay(CONFIG.SEARCH_DELAY, function()
        if generation ~= SearchGeneration then
            return
        end

        renderRows()
    end)
end)

CopyScan.Activated:Connect(function()
    local report = scanExportText()

    local ok, err = copyToClipboard(report)

    setStatus(
        ok and "Todos os resultados do Scan foram copiados" or tostring(err),
        ok and COLORS.GREEN or COLORS.YELLOW
    )
end)

ExportScan.Activated:Connect(function()
    local report = scanExportText()

    local ok, result = writeExportFile(
        "Cafeina_Scan_Report.json",
        report
    )

    setStatus(
        ok and ("Scan exportado: " .. tostring(result)) or tostring(result),
        ok and COLORS.GREEN or COLORS.YELLOW
    )
end)

UploadScan.Activated:Connect(function()
    local report = scanExportText()

    setStatus(
        "Enviando Scan para o servidor...",
        COLORS.YELLOW
    )

    task.spawn(function()
        local ok, result = uploadExportFile(
            "Cafeina_Scan_Report.json",
            report
        )

        if ok then
            if API.setclipboard then
                pcall(function()
                    API.setclipboard(result)
                end)
            end

            setStatus(
                "Link do Scan copiado: " .. tostring(result),
                COLORS.GREEN
            )
        else
            setStatus(
                "Falha no upload: " .. tostring(result),
                COLORS.RED
            )
        end
    end)
end)

--==============================================================--
-- EXPORTAÇÃO COMPLETA • STREAMING ACTIONS
--==============================================================--

local CurrentUploadId = nil

CopyDownloadLink.Activated:Connect(function()
    if LastDownloadURL == "" then
        setStatus(
            "Nenhum link de download disponível",
            COLORS.YELLOW
        )
        return
    end

    local ok, err = copyToClipboard(LastDownloadURL)

    setStatus(
        ok and "Link de download copiado" or tostring(err),
        ok and COLORS.GREEN or COLORS.YELLOW
    )
end)

CancelUpload.Activated:Connect(function()
    if not FullExportRunning then
        return
    end

    FullExportGeneration += 1
    FullExportRunning = false

    local uploadId = CurrentUploadId
    CurrentUploadId = nil

    uploadCancel(uploadId)

    UploadAll.Text = "ENVIAR TUDO"
    UploadAll.Active = true
    CancelUpload.Visible = false

    setExportStatus(
        "Exportação cancelada",
        0,
        COLORS.YELLOW
    )

    setStatus(
        "Upload cancelado",
        COLORS.YELLOW
    )
end)

UploadAll.Activated:Connect(function()
    if FullExportRunning then
        setStatus(
            "Exportação completa já está em andamento",
            COLORS.YELLOW
        )
        return
    end

    if not API.request then
        setExportStatus(
            "request/http_request não disponível",
            0,
            COLORS.RED
        )

        setStatus(
            "Upload remoto indisponível neste ambiente",
            COLORS.RED
        )
        return
    end

    FullExportRunning = true
    FullExportGeneration += 1

    local generation = FullExportGeneration

    LastDownloadURL = ""
    DownloadLink.Text = ""
    CurrentUploadId = nil

    UploadAll.Text = "PREPARANDO"
    UploadAll.Active = false
    CancelUpload.Visible = true

    setExportStatus(
        "Conectando ao servidor • limite 250 MB...",
        0.01,
        COLORS.YELLOW
    )

    task.spawn(function()
        local metadata = buildExportMetadata()

        local startOk, startResult =
            uploadStartSession(
                metadata,
                "Cafeina_Explorer_Completo.json",
                "cafeina-game-explorer"
            )

        if generation ~= FullExportGeneration then
            return
        end

        if not startOk
            or not startResult
            or not startResult.uploadId
        then
            FullExportRunning = false
            UploadAll.Text = "ENVIAR TUDO"
            UploadAll.Active = true
            CancelUpload.Visible = false

            local startError =
                tostring(
                    startResult
                    or "Servidor não retornou uploadId"
                )

            setExportStatus(
                "Falha: " .. startError,
                0,
                COLORS.RED
            )

            setStatus(
                "Upload: " .. startError,
                COLORS.RED
            )
            return
        end

        local uploadId = tostring(startResult.uploadId)
        CurrentUploadId = uploadId

        local traversal = newTraversalState()

        local chunk = {}
        local chunkBytes = 2
        local chunkIndex = 0

        local sentBytes = 0
        local sentObjects = 0

        local function abortWithError(message)
            uploadCancel(uploadId)

            CurrentUploadId = nil
            FullExportRunning = false
            UploadAll.Text = "ENVIAR TUDO"
            UploadAll.Active = true
            CancelUpload.Visible = false

            setExportStatus(
                "Falha durante o envio",
                math.min(
                    sentBytes / CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES,
                    1
                ),
                COLORS.RED
            )

            setStatus(
                tostring(message),
                COLORS.RED
            )
        end

        local function sendCurrentChunk()
            if #chunk == 0 then
                return true
            end

            chunkIndex += 1

            setExportStatus(
                "Enviando parte "
                .. tostring(chunkIndex)
                .. " • "
                .. readableSize(sentBytes)
                .. " enviados",
                math.min(
                    sentBytes / CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES,
                    0.95
                ),
                COLORS.RED
            )

            local ok, result =
                uploadChunk(
                    uploadId,
                    chunkIndex,
                    chunk
                )

            if generation ~= FullExportGeneration then
                return false
            end

            if not ok then
                abortWithError(result)
                return false
            end

            local encodedOk, encodedChunk =
                pcall(function()
                    return HttpService:JSONEncode(chunk)
                end)

            if encodedOk then
                sentBytes += #encodedChunk
            else
                sentBytes += chunkBytes
            end

            sentObjects += #chunk

            chunk = {}
            chunkBytes = 2

            return true
        end

        while generation == FullExportGeneration do
            if sentObjects >= CONFIG.FULL_EXPORT_MAX_OBJECTS then
                break
            end

            local inst = traversalNext(traversal)

            if not inst then
                break
            end

            local objectData =
                compactObjectSnapshot(inst)

            local objectBytes =
                encodedObjectSize(objectData)

            if objectBytes <= 0 then
                objectBytes = 128
            end

            if chunkBytes + objectBytes
                > CONFIG.FULL_EXPORT_CHUNK_SOFT_BYTES
                and #chunk > 0
            then
                if not sendCurrentChunk() then
                    return
                end

                if sentBytes >= CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES then
                    break
                end
            end

            local projectedTotal =
                sentBytes
                + chunkBytes
                + objectBytes

            if projectedTotal
                > CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES
            then
                setStatus(
                    "Limite máximo da exportação atingido",
                    COLORS.YELLOW
                )
                break
            end

            chunk[#chunk + 1] = objectData
            chunkBytes += objectBytes

            if traversal.visited
                % CONFIG.FULL_EXPORT_YIELD_EVERY
                == 0
            then
                setExportStatus(
                    "Lendo objetos: "
                    .. tostring(traversal.visited)
                    .. " • partes "
                    .. tostring(chunkIndex)
                    .. " • "
                    .. readableSize(sentBytes),
                    math.min(
                        sentBytes / CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES,
                        0.90
                    ),
                    COLORS.YELLOW
                )

                task.wait()
            end
        end

        if generation ~= FullExportGeneration then
            return
        end

        if #chunk > 0 then
            if not sendCurrentChunk() then
                return
            end
        end

        if generation ~= FullExportGeneration then
            return
        end

        setExportStatus(
            "Finalizando "
            .. tostring(chunkIndex)
            .. " parte(s)...",
            0.96,
            COLORS.YELLOW
        )

        local finishOk, finishResult =
            uploadFinish(
                uploadId,
                chunkIndex,
                {
                    objectCount = sentObjects,
                    approximateBytes = sentBytes,
                    maxObjectsReached =
                        sentObjects >= CONFIG.FULL_EXPORT_MAX_OBJECTS,
                    maxBytesReached =
                        sentBytes >= CONFIG.FULL_EXPORT_MAX_TOTAL_BYTES,
                }
            )

        if generation ~= FullExportGeneration then
            return
        end

        CurrentUploadId = nil
        FullExportRunning = false
        UploadAll.Text = "ENVIAR TUDO"
        UploadAll.Active = true
        CancelUpload.Visible = false

        if not finishOk then
            setExportStatus(
                "Falha ao finalizar upload",
                0.96,
                COLORS.RED
            )

            setStatus(
                tostring(finishResult),
                COLORS.RED
            )
            return
        end

        local url =
            finishResult.url
            or finishResult.downloadUrl
            or finishResult.download_url
            or finishResult.link

        if not url or tostring(url) == "" then
            setExportStatus(
                "Servidor não retornou link",
                0.96,
                COLORS.YELLOW
            )

            setStatus(
                "Upload terminou, mas o link não foi retornado",
                COLORS.YELLOW
            )
            return
        end

        LastDownloadURL = tostring(url)
        DownloadLink.Text = LastDownloadURL

        setExportStatus(
            "Concluído • "
            .. tostring(sentObjects)
            .. " objeto(s) • "
            .. readableSize(sentBytes),
            1,
            COLORS.GREEN
        )

        if API.setclipboard then
            pcall(function()
                API.setclipboard(LastDownloadURL)
            end)
        end

        setStatus(
            "Link pronto para download",
            COLORS.GREEN
        )
    end)
end)

--==============================================================--
-- SCANNER
--==============================================================--

local function clearScanResults()
    for key in pairs(VirtualFolders) do
        table.clear(VirtualFolders[key])
    end

    ScanFoundSomething = false
end

local function addScanResult(key, inst)
    local list = VirtualFolders[key]

    if not list then
        return
    end

    if #list >= CONFIG.MAX_VIRTUAL_RESULTS then
        return
    end

    list[#list + 1] = inst
    ScanFoundSomething = true
end

local function classify(inst)
    if inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
    then
        addScanResult("REMOTES", inst)
    end

    if inst:IsA("Tool") then
        addScanResult("TOOLS", inst)
    end

    if inst:IsA("ValueBase") then
        addScanResult("VALUES", inst)
    end

    if inst:IsA("GuiObject")
        or inst:IsA("ScreenGui")
    then
        addScanResult("GUI", inst)
    end

    if inst:IsA("Model") then
        addScanResult("MODELS", inst)
    end

    if inst:IsA("LuaSourceContainer") then
        addScanResult("SCRIPTS", inst)
    end

    if inst:IsA("Player") then
        addScanResult("PLAYERS", inst)
    end

    local attrs = {}
    pcall(function()
        attrs = inst:GetAttributes()
    end)

    if next(attrs) ~= nil then
        addScanResult("ATTRIBUTES", inst)
    end
end

local function runScan()
    if ScanRunning then
        setScanStatus(
            "Scanner já está em execução...",
            ProgressFill.Size.X.Scale,
            COLORS.YELLOW
        )
        return
    end

    ScanRunning = true
    ScanGeneration += 1

    local generation = ScanGeneration

    clearScanResults()

    ScanButton.Text = "..."
    ScanButton.Active = false

    setScanStatus(
        "Preparando scanner...",
        0.02,
        COLORS.YELLOW
    )

    task.spawn(function()
        local roots = getMainServices()
        local all = {}

        for _, root in ipairs(roots) do
            all[#all + 1] = root

            local ok, descendants = pcall(function()
                return root:GetDescendants()
            end)

            if ok then
                for _, inst in ipairs(descendants) do
                    all[#all + 1] = inst

                    if #all >= CONFIG.MAX_SCAN_OBJECTS then
                        break
                    end
                end
            end

            if #all >= CONFIG.MAX_SCAN_OBJECTS then
                break
            end
        end

        local total = math.max(#all, 1)

        setScanStatus(
            "Analisando "
            .. tostring(#all)
            .. " objeto(s)...",
            0.08,
            COLORS.YELLOW
        )

        for i, inst in ipairs(all) do
            if generation ~= ScanGeneration then
                return
            end

            classify(inst)

            if i % CONFIG.SCAN_YIELD_EVERY == 0 then
                local progress =
                    0.08 + (i / total) * 0.88

                setScanStatus(
                    "Analisando... "
                    .. tostring(i)
                    .. "/"
                    .. tostring(total),
                    progress,
                    COLORS.RED
                )

                task.wait()
            end
        end

        ScanRunning = false
        ScanButton.Text = "SCAN"
        ScanButton.Active = true

        if ScanFoundSomething then
            local totalFound = 0

            for _, list in pairs(VirtualFolders) do
                totalFound += #list
            end

            setScanStatus(
                "Encontrado: "
                .. tostring(totalFound)
                .. " resultado(s)",
                1,
                COLORS.GREEN
            )

            setStatus(
                "Scan concluído • resultados disponíveis",
                COLORS.GREEN
            )

            openScanRoot()

        else
            setScanStatus(
                "Nenhum resultado útil encontrado",
                1,
                COLORS.YELLOW
            )

            setStatus(
                "Scan concluído sem resultados",
                COLORS.YELLOW
            )
        end
    end)
end

ScanButton.Activated:Connect(
    runScan
)

--==============================================================--
-- DRAG
--==============================================================--

local function clampFrame(frame)
    task.defer(function()
        local camera = workspace.CurrentCamera
        if not camera or not frame.Parent then
            return
        end

        local viewport = camera.ViewportSize
        local size = frame.AbsoluteSize
        local pos = frame.AbsolutePosition

        local x = math.clamp(
            pos.X,
            0,
            math.max(0, viewport.X - size.X)
        )

        local y = math.clamp(
            pos.Y,
            0,
            math.max(0, viewport.Y - size.Y)
        )

        frame.Position = UDim2.fromOffset(x, y)
    end)
end

local function makeDraggable(frame, handle)
    local dragging = false
    local startInput = nil
    local startFrame = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1
        then
            return
        end

        dragging = true
        startInput = input.Position
        startFrame = frame.Position
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging
            or not startInput
            or not startFrame
        then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement
        then
            return
        end

        local delta = input.Position - startInput

        frame.Position = UDim2.new(
            startFrame.X.Scale,
            startFrame.X.Offset + delta.X,
            startFrame.Y.Scale,
            startFrame.Y.Offset + delta.Y
        )
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            dragging = false
            clampFrame(frame)
        end
    end)
end

makeDraggable(Main, Header)

--==============================================================--
-- MINIMIZED ICON
--==============================================================--

local Floating = Instance.new("TextButton")
Floating.Size = UDim2.fromOffset(54, 54)
Floating.Position = UDim2.new(0.5, -27, 0.5, -27)
Floating.BackgroundColor3 = COLORS.PANEL
Floating.BorderSizePixel = 0
Floating.Text = "☕"
Floating.TextSize = 22
Floating.TextColor3 = COLORS.RED
Floating.Font = Enum.Font.GothamBold
Floating.Visible = false
corner(Floating, 15)
stroke(Floating, COLORS.RED_DARK, 2)
Floating.Parent = Gui

makeDraggable(Floating, Floating)

Minimize.Activated:Connect(function()
    Main.Visible = false
    Floating.Visible = true
end)

Floating.Activated:Connect(function()
    Floating.Visible = false
    Main.Visible = true
    clampFrame(Main)
end)

Close.Activated:Connect(function()
    ScanGeneration += 1
    FullExportGeneration += 1

    if FullExportRunning then
        uploadCancel(CurrentUploadId)
    end

    FullExportRunning = false
    CurrentUploadId = nil

    Gui:Destroy()
end)

--==============================================================--
-- START
--==============================================================--

openGameRoot()

setScanStatus(
    "Pronto para analisar o jogo",
    0,
    COLORS.RED
)

setStatus(
    "Explorer carregado",
    COLORS.GREEN
)

--==============================================================--
-- END
--==============================================================--
