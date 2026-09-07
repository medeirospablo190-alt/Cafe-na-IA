--==============================================================--
-- GRUPO LUA • AVATAR GEOMETRY EXECUTOR V1
-- Target: Capuccino40 / UserId 765329164
--
-- Tenta extrair geometria CLIENT-VISIBLE do avatar via EditableMesh
-- e envia em chunks para o servidor do projeto.
-- Não coleta cookie, token, senha ou dados de outros jogadores.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local StarterGui = game:GetService("StarterGui")

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

local function mul3(a, b)
    return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

local function divSafe(a, b)
    return Vector3.new(
        math.abs(b.X) > 1e-7 and a.X / b.X or 1,
        math.abs(b.Y) > 1e-7 and a.Y / b.Y or 1,
        math.abs(b.Z) > 1e-7 and a.Z / b.Z or 1
    )
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
    error("Seu executor não expõe request/http_request.")
end

local function headers()
    local h = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = "GrupoLua-AvatarGeometry-Executor/1.0",
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

    error(last or "Falha na requisição")
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
        local worldPositions = table.create(#vertexIds)

        for i, vertexId in ipairs(vertexIds) do
            vertexMap[tostring(vertexId)] = i
            local p = editable:GetPosition(vertexId)
            localPositions[i] = vec3(p)
            local world = part.CFrame:PointToWorldSpace(mul3(p, renderScale))
            worldPositions[i] = vec3(world)
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
            worldPositions = worldPositions,
            uvs = uvs,
            normals = normals,
            faces = faces,
        }
    end)

    pcall(function() editable:Destroy() end)

    if not ok then
        return nil, tostring(result)
    end
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

local function uploadMesh(uploadId, meshIndex, meshData)
    local text = HttpService:JSONEncode(meshData)
    local totalChunks = math.max(1, math.ceil(#text / CHUNK_CHARS))

    for chunkIndex = 1, totalChunks do
        local startByte = (chunkIndex - 1) * CHUNK_CHARS + 1
        local endByte = math.min(#text, chunkIndex * CHUNK_CHARS)
        local piece = string.sub(text, startByte, endByte)

        requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/chunk", {
            meshIndex = meshIndex,
            chunkIndex = chunkIndex,
            totalChunks = totalChunks,
            partName = meshData.partName,
            meshId = meshData.meshId,
            data = piece,
        }, 4)

        if chunkIndex % 3 == 0 then task.wait() end
    end

    return #text, totalChunks
end

local function main()
    notify("Avatar Geometry", "Preparando coleta das malhas reais...", 5)

    local character = getCharacter()
    if not character then
        error("Não foi possível localizar/criar o avatar Capuccino40.")
    end

    local meshParts = {}
    for _, object in ipairs(character:GetDescendants()) do
        if object:IsA("MeshPart") then
            meshParts[#meshParts + 1] = object
            if #meshParts >= MAX_MESHPARTS then break end
        end
    end

    local start = requestJson("POST", BASE .. "/api/avatar-geometry/start", {
        userId = tostring(TARGET_USER_ID),
        username = USERNAME,
        capturedAt = isoNow(),
        expectedMeshes = #meshParts,
    })

    local uploadId = start.uploadId
    if type(uploadId) ~= "string" or uploadId == "" then
        error("Servidor não retornou uploadId.")
    end

    local failed = {}
    local extracted = 0
    local uploadedBytes = 0

    for index, part in ipairs(meshParts) do
        notify("Avatar Geometry", string.format("Malha %d/%d: %s", index, #meshParts, part.Name), 2)

        local meshData, err = extractMesh(part, index)
        if meshData then
            local bytes = uploadMesh(uploadId, index, meshData)
            uploadedBytes = uploadedBytes + bytes
            extracted = extracted + 1
        else
            failed[#failed + 1] = {
                meshIndex = index,
                partName = part.Name,
                meshId = safe(function() return tostring(part.MeshId) end, ""),
                error = tostring(err):sub(1, 800),
            }
        end

        task.wait()
    end

    local finish = requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/finish", {
        failed = failed,
    }, 4)

    local summary = {
        userId = TARGET_USER_ID,
        extracted = extracted,
        failed = #failed,
        approximateUploadedJsonBytes = uploadedBytes,
        server = finish,
    }

    if type(writefile) == "function" then
        safe(function()
            writefile("Capuccino40_AvatarGeometry_Result.json", HttpService:JSONEncode(summary))
        end, nil)
    end

    notify(
        "Avatar Geometry",
        string.format("Concluído: %d malhas extraídas, %d falharam.", extracted, #failed),
        8
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
