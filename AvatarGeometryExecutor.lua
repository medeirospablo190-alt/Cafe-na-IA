--==============================================================--
-- CAFEINA • AVATAR GEOMETRY EXECUTOR
-- Target: Capuccino40 / UserId 765329164
--
-- Coleta geometria CLIENT-VISIBLE do avatar via EditableMesh.
-- Tambem tenta recuperar, via EditableImage, somente as imagens
-- que continuaram bloqueadas no download externo.
--
-- Nao coleta cookie, token, senha ou dados de outros jogadores.
-- O mesmo arquivo e o mesmo loadstring sao mantidos entre updates.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local StarterGui = game:GetService("StarterGui")
local EncodingService = game:GetService("EncodingService")

local LocalPlayer = Players.LocalPlayer
local TARGET_USER_ID = 765329164
local USERNAME = "Capuccino40"

local ENV = (getgenv and getgenv()) or _G
local BASE = ENV.GRUPO_LUA_AVATAR_BASE or "https://cafe-na-ia.onrender.com"
local UPLOAD_KEY = ENV.GRUPO_LUA_AVATAR_KEY or ""
local CHUNK_CHARS = 320000
local MAX_MESHPARTS = 60
local MAX_VERTICES_PER_MESH = 120000
local MAX_FACES_PER_MESH = 180000
local MAX_UPLOAD_ATTEMPTS = 3
local IMAGE_ZSTD_LEVEL = 9

local TARGET_IMAGE_IDS = {
    "18711605978",
    "18711607797",
    "18711609689",
    "18711640761",
    "80293630295826",
    "82530105988237",
    "83091105722329",
    "88515799809882",
    "96472780768407",
    "110426848175524",
    "117649354311112",
    "124249945746431",
    "127025880258976",
    "137182279278426",
}

local TARGET_IMAGE_SET = {}
for _, id in ipairs(TARGET_IMAGE_IDS) do
    TARGET_IMAGE_SET[id] = true
end

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function vec3(v)
    return {v.X, v.Y, v.Z}
end

local function vec2(v)
    return {v.X, v.Y}
end

local function color3(v)
    return {v.R, v.G, v.B}
end

local function cf(v)
    return {v:GetComponents()}
end

local function divSafe(a, b)
    return Vector3.new(
        math.abs(b.X) > 1e-7 and a.X / b.X or 1,
        math.abs(b.Y) > 1e-7 and a.Y / b.Y or 1,
        math.abs(b.Z) > 1e-7 and a.Z / b.Z or 1
    )
end

local function assetId(value)
    local s = tostring(value or "")
    return s:match("(%d+)") or ""
end

local function getRequestFunction()
    local candidates = {
        ENV.request,
        ENV.http_request,
        (syn and syn.request),
        (http and http.request),
        (fluxus and fluxus.request),
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then return fn end
    end
    return nil
end

local requestFn = getRequestFunction()
if not requestFn then
    error("Seu executor nao expoe request/http_request.")
end

local function headers()
    local h = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = "Cafeina-AvatarGeometry-Executor/2.0",
    }
    if UPLOAD_KEY ~= "" then
        h["x-avatar-dump-key"] = UPLOAD_KEY
    end
    return h
end

local function requestJson(method, url, payload, tries)
    tries = tries or 3
    local body = payload and HttpService:JSONEncode(payload) or nil
    local last = nil

    for attempt = 1, tries do
        local ok, response = pcall(function()
            return requestFn({
                Url = url,
                Method = method,
                Headers = headers(),
                Body = body,
            })
        end)

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or response.status_code) or 0
            local responseBody = tostring(response.Body or response.body or "")
            if status >= 200 and status < 300 then
                local decoded = safe(function()
                    return HttpService:JSONDecode(responseBody)
                end, {})
                return decoded, status, responseBody
            end
            last = "HTTP " .. tostring(status) .. " - " .. responseBody
        else
            last = tostring(response)
        end

        task.wait(0.8 * attempt)
    end

    error(last or "Falha na requisicao")
end

local function isoNow()
    return safe(function()
        return DateTime.now():ToIsoDate()
    end, os.date("!%Y-%m-%dT%H:%M:%SZ"))
end

local function findAccessory(part)
    local cursor = part.Parent
    while cursor do
        if cursor:IsA("Accessory") then return cursor end
        cursor = cursor.Parent
    end
    return nil
end

local function surfaceData(part)
    local sa = part:FindFirstChildOfClass("SurfaceAppearance")
    if not sa then return nil end
    return {
        colorMap = safe(function() return tostring(sa.ColorMap) end, ""),
        normalMap = safe(function() return tostring(sa.NormalMap) end, ""),
        roughnessMap = safe(function() return tostring(sa.RoughnessMap) end, ""),
        metalnessMap = safe(function() return tostring(sa.MetalnessMap) end, ""),
        alphaMode = safe(function() return tostring(sa.AlphaMode) end, ""),
    }
end

local function wrapData(part)
    local wrap = part:FindFirstChildOfClass("WrapLayer")
    if not wrap then return nil end
    return {
        referenceMeshId = safe(function() return tostring(wrap.ReferenceMeshId) end, ""),
        cageMeshId = safe(function() return tostring(wrap.CageMeshId) end, ""),
        order = safe(function() return wrap.Order end, nil),
        puffiness = safe(function() return wrap.Puffiness end, nil),
        enabled = safe(function() return wrap.Enabled end, nil),
    }
end

local function meshContentCandidates(part)
    local out = {}

    local content = safe(function() return part.MeshContent end, nil)
    if content ~= nil then
        out[#out + 1] = content
    end

    local meshId = safe(function() return tostring(part.MeshId) end, "")
    if meshId ~= "" and Content then
        if type(Content.fromUri) == "function" then
            local c = safe(function() return Content.fromUri(meshId) end, nil)
            if c ~= nil then out[#out + 1] = c end
        end

        local numeric = tonumber(meshId:match("(%d+)$"))
        if numeric and type(Content.fromAssetId) == "function" then
            local c = safe(function() return Content.fromAssetId(numeric) end, nil)
            if c ~= nil then out[#out + 1] = c end
        end
    end

    return out
end

local function createEditable(part)
    local errors = {}
    for _, content in ipairs(meshContentCandidates(part)) do
        local ok, editable = pcall(function()
            return AssetService:CreateEditableMeshAsync(content, {FixedSize = true})
        end)
        if ok and editable then
            return editable
        end
        errors[#errors + 1] = tostring(editable)
    end
    return nil, table.concat(errors, " | ")
end

local function extractMesh(part, meshIndex)
    local editable, createError = createEditable(part)
    if not editable then
        return nil, "CreateEditableMeshAsync falhou: " .. tostring(createError)
    end

    local ok, result = pcall(function()
        local vertexIds = editable:GetVertices()
        local faceIds = editable:GetFaces()

        if #vertexIds > MAX_VERTICES_PER_MESH then
            error("vertices acima do limite: " .. tostring(#vertexIds))
        end
        if #faceIds > MAX_FACES_PER_MESH then
            error("faces acima do limite: " .. tostring(#faceIds))
        end

        local editableSize = editable:GetSize()
        local renderScale = divSafe(part.Size, editableSize)

        local vertexMap = {}
        local localPositions = table.create(#vertexIds)
        for i, vertexId in ipairs(vertexIds) do
            vertexMap[tostring(vertexId)] = i
            localPositions[i] = vec3(editable:GetPosition(vertexId))
            if i % 2500 == 0 then task.wait() end
        end

        local uvMap = {}
        local uvs = {}
        local normalMap = {}
        local normals = {}
        local faces = table.create(#faceIds)

        local function mapUV(uvId)
            if uvId == nil then return 0 end
            local key = tostring(uvId)
            local existing = uvMap[key]
            if existing then return existing end
            local uv = safe(function() return editable:GetUV(uvId) end, nil)
            if not uv then return 0 end
            local index = #uvs + 1
            uvMap[key] = index
            uvs[index] = vec2(uv)
            return index
        end

        local function mapNormal(normalId)
            if normalId == nil then return 0 end
            local key = tostring(normalId)
            local existing = normalMap[key]
            if existing then return existing end
            local n = safe(function() return editable:GetNormal(normalId) end, nil)
            if not n then return 0 end
            local index = #normals + 1
            normalMap[key] = index
            normals[index] = vec3(n)
            return index
        end

        for i, faceId in ipairs(faceIds) do
            local vids = editable:GetFaceVertices(faceId)
            if #vids >= 3 then
                local face = {
                    v = {
                        vertexMap[tostring(vids[1])] or 0,
                        vertexMap[tostring(vids[2])] or 0,
                        vertexMap[tostring(vids[3])] or 0,
                    }
                }

                local uvIds = safe(function() return editable:GetFaceUVs(faceId) end, nil)
                if type(uvIds) == "table" and #uvIds >= 3 then
                    face.uv = {mapUV(uvIds[1]), mapUV(uvIds[2]), mapUV(uvIds[3])}
                end

                local normalIds = safe(function() return editable:GetFaceNormals(faceId) end, nil)
                if type(normalIds) == "table" and #normalIds >= 3 then
                    face.n = {mapNormal(normalIds[1]), mapNormal(normalIds[2]), mapNormal(normalIds[3])}
                end

                faces[#faces + 1] = face
            end
            if i % 1500 == 0 then task.wait() end
        end

        local accessory = findAccessory(part)
        return {
            schemaVersion = 1,
            kind = "mesh",
            meshIndex = meshIndex,
            partName = part.Name,
            fullName = part:GetFullName(),
            meshId = safe(function() return tostring(part.MeshId) end, ""),
            textureId = safe(function() return tostring(part.TextureID) end, ""),
            sourceAssetId = safe(function() return part.SourceAssetId end, -1),
            partSize = vec3(part.Size),
            partCFrame = cf(part.CFrame),
            editableSize = vec3(editableSize),
            renderScale = vec3(renderScale),
            color = color3(part.Color),
            transparency = part.Transparency,
            material = tostring(part.Material),
            doubleSided = safe(function() return part.DoubleSided end, false),
            accessory = accessory and {
                name = accessory.Name,
                accessoryType = safe(function() return tostring(accessory.AccessoryType) end, ""),
            } or nil,
            surfaceAppearance = surfaceData(part),
            wrapLayer = wrapData(part),
            vertexCount = #vertexIds,
            faceCount = #faces,
            uvCount = #uvs,
            normalCount = #normals,
            positions = localPositions,
            uvs = uvs,
            normals = normals,
            faces = faces,
        }
    end)

    pcall(function() editable:Destroy() end)
    if not ok then return nil, tostring(result) end
    return result
end

local function getCharacter()
    if LocalPlayer and LocalPlayer.UserId == TARGET_USER_ID then
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    local model = safe(function()
        return Players:CreateHumanoidModelFromUserId(TARGET_USER_ID)
    end, nil)
    if model then
        model.Name = "AvatarGeometry_TemporaryModel"
        model.Parent = workspace
        task.wait(1)
    end
    return model
end

local imageCandidates = {}

local function addImageCandidate(id, content)
    id = tostring(id or "")
    if not TARGET_IMAGE_SET[id] or content == nil then return end
    local list = imageCandidates[id]
    if not list then
        list = {}
        imageCandidates[id] = list
    end
    list[#list + 1] = content
end

local function addUriFallback(id)
    if not TARGET_IMAGE_SET[id] or not Content then return end
    if type(Content.fromAssetId) == "function" then
        local c = safe(function() return Content.fromAssetId(tonumber(id)) end, nil)
        if c ~= nil then addImageCandidate(id, c) end
    end
    if type(Content.fromUri) == "function" then
        local c = safe(function() return Content.fromUri("rbxassetid://" .. id) end, nil)
        if c ~= nil then addImageCandidate(id, c) end
    end
end

local function collectImageCandidates(meshParts)
    for _, id in ipairs(TARGET_IMAGE_IDS) do
        addUriFallback(id)
    end

    for _, part in ipairs(meshParts) do
        local tid = assetId(safe(function() return part.TextureID end, ""))
        if TARGET_IMAGE_SET[tid] then
            addImageCandidate(tid, safe(function() return part.TextureContent end, nil))
        end

        local sa = part:FindFirstChildOfClass("SurfaceAppearance")
        if sa then
            local mappings = {
                {"ColorMap", "ColorMapContent"},
                {"NormalMap", "NormalMapContent"},
                {"RoughnessMap", "RoughnessMapContent"},
                {"MetalnessMap", "MetalnessMapContent"},
            }
            for _, pair in ipairs(mappings) do
                local id = assetId(safe(function() return sa[pair[1]] end, ""))
                if TARGET_IMAGE_SET[id] then
                    addImageCandidate(id, safe(function() return sa[pair[2]] end, nil))
                end
            end
        end
    end
end

local function extractImage(id, imageIndex)
    local candidates = imageCandidates[id] or {}
    local errors = {}

    for _, content in ipairs(candidates) do
        local okCreate, image = pcall(function()
            return AssetService:CreateEditableImageAsync(content)
        end)

        if okCreate and image then
            local okRead, record = pcall(function()
                local size = image.Size
                local width = math.floor(size.X + 0.5)
                local height = math.floor(size.Y + 0.5)
                if width < 1 or height < 1 or width > 4096 or height > 4096 then
                    error("dimensoes invalidas: " .. tostring(width) .. "x" .. tostring(height))
                end

                local pixels = image:ReadPixelsBuffer(Vector2.zero, Vector2.new(width, height))
                local compressed = EncodingService:CompressBuffer(
                    pixels,
                    Enum.CompressionAlgorithm.Zstd,
                    IMAGE_ZSTD_LEVEL
                )
                local encoded = EncodingService:Base64Encode(compressed)
                local data = buffer.tostring(encoded)

                return {
                    schemaVersion = 1,
                    kind = "image",
                    meshIndex = imageIndex,
                    partName = "__image_" .. id,
                    meshId = "",
                    assetId = id,
                    width = width,
                    height = height,
                    pixelFormat = "RGBA8",
                    origin = "top-left",
                    compression = "zstd",
                    uncompressedBytes = width * height * 4,
                    compressedBytes = buffer.len(compressed),
                    dataBase64 = data,
                    positions = {},
                    faces = {},
                    uvs = {},
                    normals = {},
                }
            end)

            pcall(function() image:Destroy() end)
            if okRead then return record end
            errors[#errors + 1] = tostring(record)
        else
            errors[#errors + 1] = tostring(image)
        end

        task.wait()
    end

    return nil, table.concat(errors, " | "):sub(1, 1000)
end

local function uploadRecord(uploadId, uploadIndex, record)
    local text = HttpService:JSONEncode(record)
    local totalChunks = math.max(1, math.ceil(#text / CHUNK_CHARS))

    for chunkIndex = 1, totalChunks do
        local startByte = (chunkIndex - 1) * CHUNK_CHARS + 1
        local endByte = math.min(#text, chunkIndex * CHUNK_CHARS)
        local piece = string.sub(text, startByte, endByte)

        requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/chunk", {
            meshIndex = uploadIndex,
            chunkIndex = chunkIndex,
            totalChunks = totalChunks,
            partName = record.partName or "",
            meshId = record.meshId or "",
            data = piece,
        }, 4)

        if chunkIndex % 3 == 0 then task.wait() end
    end

    return #text, totalChunks
end

local function openSession(expectedRecords)
    local start = requestJson("POST", BASE .. "/api/avatar-geometry/start", {
        userId = tostring(TARGET_USER_ID),
        username = USERNAME,
        capturedAt = isoNow(),
        expectedMeshes = expectedRecords,
    }, 4)

    local uploadId = start.uploadId
    if type(uploadId) ~= "string" or uploadId == "" then
        error("Servidor nao retornou uploadId.")
    end
    return uploadId
end

local function sendAll(records, geometryFailed)
    local lastError = nil

    for sessionAttempt = 1, MAX_UPLOAD_ATTEMPTS do
        local ok, result = pcall(function()
            local uploadId = openSession(#records)
            local uploadedBytes = 0

            for index, record in ipairs(records) do
                if record.kind == "image" then
                    notify(
                        "Avatar Geometry",
                        string.format("Enviando imagem %s (%d/%d)", record.assetId, index, #records),
                        2
                    )
                else
                    notify(
                        "Avatar Geometry",
                        string.format("Enviando malha %d/%d: %s", index, #records, record.partName),
                        2
                    )
                end

                local bytes = uploadRecord(uploadId, index, record)
                uploadedBytes = uploadedBytes + bytes
                task.wait()
            end

            local finish = requestJson(
                "POST",
                BASE .. "/api/avatar-geometry/" .. uploadId .. "/finish",
                {failed = geometryFailed},
                4
            )

            return {
                uploadId = uploadId,
                uploadedBytes = uploadedBytes,
                finish = finish,
                sessionAttempt = sessionAttempt,
            }
        end)

        if ok then return result end
        lastError = tostring(result)

        if sessionAttempt < MAX_UPLOAD_ATTEMPTS then
            notify(
                "Avatar Geometry",
                string.format("Sessao caiu. Reabrindo (%d/%d)...", sessionAttempt + 1, MAX_UPLOAD_ATTEMPTS),
                5
            )
            task.wait(1.5 * sessionAttempt)
        end
    end

    error(lastError or "Falha ao enviar pacote")
end

local function main()
    notify("Avatar Geometry", "Preparando coleta real de malhas e texturas...", 5)

    local character = getCharacter()
    if not character then
        error("Nao foi possivel localizar/criar o avatar Capuccino40.")
    end

    local meshParts = {}
    for _, object in ipairs(character:GetDescendants()) do
        if object:IsA("MeshPart") then
            meshParts[#meshParts + 1] = object
            if #meshParts >= MAX_MESHPARTS then break end
        end
    end

    collectImageCandidates(meshParts)

    local records = {}
    local geometryFailed = {}
    local extractedMeshes = 0

    for index, part in ipairs(meshParts) do
        notify(
            "Avatar Geometry",
            string.format("Extraindo malha %d/%d: %s", index, #meshParts, part.Name),
            2
        )

        local meshData, err = extractMesh(part, index)
        if meshData then
            records[#records + 1] = meshData
            extractedMeshes = extractedMeshes + 1
        else
            geometryFailed[#geometryFailed + 1] = {
                meshIndex = index,
                partName = part.Name,
                meshId = safe(function() return tostring(part.MeshId) end, ""),
                error = tostring(err):sub(1, 800),
            }
        end
        task.wait()
    end

    local imageFailures = {}
    local extractedImages = 0

    for _, id in ipairs(TARGET_IMAGE_IDS) do
        if #records >= 60 then break end
        notify("Avatar Geometry", "Tentando textura/PBR " .. id, 2)
        local record, err = extractImage(id, #records + 1)
        if record then
            records[#records + 1] = record
            extractedImages = extractedImages + 1
        else
            imageFailures[#imageFailures + 1] = {
                assetId = id,
                error = tostring(err or "indisponivel"):sub(1, 1000),
            }
        end
        task.wait()
    end

    notify(
        "Avatar Geometry",
        string.format(
            "Extraido: %d malhas, %d imagens. Enviando...",
            extractedMeshes,
            extractedImages
        ),
        5
    )

    local sent = sendAll(records, geometryFailed)

    local summary = {
        userId = TARGET_USER_ID,
        extractedMeshes = extractedMeshes,
        geometryFailed = #geometryFailed,
        extractedImages = extractedImages,
        imageFailed = #imageFailures,
        imageFailures = imageFailures,
        totalRecords = #records,
        approximateUploadedJsonBytes = sent.uploadedBytes,
        uploadId = sent.uploadId,
        sessionAttempt = sent.sessionAttempt,
        server = sent.finish,
    }

    if type(writefile) == "function" then
        safe(function()
            writefile("Capuccino40_AvatarGeometry_Result.json", HttpService:JSONEncode(summary))
        end, nil)
    end

    notify(
        "Avatar Geometry",
        string.format(
            "Concluido: %d malhas, %d imagens; falhas de imagem: %d.",
            extractedMeshes,
            extractedImages,
            #imageFailures
        ),
        10
    )

    print("[Avatar Geometry]", HttpService:JSONEncode(summary))
    return summary
end

local ok, result = pcall(main)
if not ok then
    notify("Avatar Geometry", "Falhou: " .. tostring(result), 10)
    warn("[Avatar Geometry]", result)
    return nil
end

return result
