--==============================================================--
-- CAFEINA • AVATAR GEOMETRY EXECUTOR
-- Target: Capuccino40 / UserId 765329164
--
-- MODO INCREMENTAL LEVE
-- Coleta SOMENTE o que ainda falta para reconstruir layered clothing:
--   * WrapLayer cage
--   * WrapLayer reference cage
--   * WrapTarget body cages
--   * origins / ordem / bind offset
--   * bones + skin weights quando disponiveis no EditableMesh
--
-- Nao recolhe novamente as 26 render meshes nem as texturas/PBR.
-- Mantem o mesmo arquivo e o mesmo loadstring.
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

local CHUNK_CHARS = 300000
local MAX_RECORDS = 60
local MAX_VERTICES = 120000
local MAX_FACES = 180000
local MAX_SESSION_ATTEMPTS = 3

local function notify(text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Avatar Geometry",
            Text = text,
            Duration = duration or 4,
        })
    end)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function cf(v)
    if typeof(v) ~= "CFrame" then return nil end
    return {v:GetComponents()}
end

local function vec3(v)
    if typeof(v) ~= "Vector3" then return nil end
    return {v.X, v.Y, v.Z}
end

local function vec2(v)
    if typeof(v) ~= "Vector2" then return nil end
    return {v.X, v.Y}
end

local function assetId(value)
    return tostring(value or ""):match("(%d+)") or ""
end

local function requestFunction()
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

local requestFn = requestFunction()
if not requestFn then
    error("Executor sem request/http_request.")
end

local function requestJson(method, url, payload, tries)
    tries = tries or 3
    local body = payload and HttpService:JSONEncode(payload) or nil
    local lastError = nil

    for attempt = 1, tries do
        local ok, response = pcall(function()
            local headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
                ["User-Agent"] = "Cafeina-AvatarGeometry-WrapIncremental/1.0",
            }
            if UPLOAD_KEY ~= "" then
                headers["x-avatar-dump-key"] = UPLOAD_KEY
            end

            return requestFn({
                Url = url,
                Method = method,
                Headers = headers,
                Body = body,
            })
        end)

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or response.status_code) or 0
            local responseBody = tostring(response.Body or response.body or "")
            if status >= 200 and status < 300 then
                return safe(function()
                    return HttpService:JSONDecode(responseBody)
                end, {}), status
            end
            lastError = "HTTP " .. tostring(status) .. " - " .. responseBody
        else
            lastError = tostring(response)
        end

        task.wait(0.6 * attempt)
    end

    error(lastError or "Falha HTTP")
end

local function isoNow()
    return safe(function()
        return DateTime.now():ToIsoDate()
    end, os.date("!%Y-%m-%dT%H:%M:%SZ"))
end

local function findAccessory(part)
    local cursor = part
    while cursor do
        if cursor:IsA("Accessory") then return cursor end
        cursor = cursor.Parent
    end
    return nil
end

local function parentMetadata(wrap)
    local part = wrap.Parent
    local accessory = part and findAccessory(part)
    return {
        parentName = part and part.Name or "",
        parentFullName = part and part:GetFullName() or "",
        parentCFrame = part and safe(function() return cf(part.CFrame) end, nil) or nil,
        parentSize = part and safe(function() return vec3(part.Size) end, nil) or nil,
        parentMeshSize = part and safe(function() return vec3(part.MeshSize) end, nil) or nil,
        parentMeshId = part and safe(function() return tostring(part.MeshId) end, "") or "",
        accessory = accessory and {
            name = accessory.Name,
            accessoryType = safe(function() return tostring(accessory.AccessoryType) end, ""),
        } or nil,
    }
end

local function wrapMetadata(wrap)
    local base = {
        wrapName = wrap.Name,
        wrapPath = wrap:GetFullName(),
        wrapClass = wrap.ClassName,
        cageMeshId = safe(function() return tostring(wrap.CageMeshId) end, ""),
        cageOrigin = safe(function() return cf(wrap.CageOrigin) end, nil),
        cageOriginWorld = safe(function() return cf(wrap.CageOriginWorld) end, nil),
        importOrigin = safe(function() return cf(wrap.ImportOrigin) end, nil),
        importOriginWorld = safe(function() return cf(wrap.ImportOriginWorld) end, nil),
    }

    if wrap:IsA("WrapLayer") then
        base.enabled = safe(function() return wrap.Enabled end, nil)
        base.order = safe(function() return wrap.Order end, nil)
        base.puffiness = safe(function() return wrap.Puffiness end, nil)
        base.autoSkin = safe(function() return tostring(wrap.AutoSkin) end, "")
        base.bindOffset = safe(function() return cf(wrap.BindOffset) end, nil)
        base.referenceMeshId = safe(function() return tostring(wrap.ReferenceMeshId) end, "")
        base.referenceOrigin = safe(function() return cf(wrap.ReferenceOrigin) end, nil)
        base.referenceOriginWorld = safe(function() return cf(wrap.ReferenceOriginWorld) end, nil)
    elseif wrap:IsA("WrapTarget") then
        base.stiffness = safe(function() return wrap.Stiffness end, nil)
    end

    return base
end

local function contentFromId(idText)
    local id = tonumber(assetId(idText))
    if not id or not Content then return nil end

    if type(Content.fromAssetId) == "function" then
        local content = safe(function() return Content.fromAssetId(id) end, nil)
        if content ~= nil then return content end
    end

    if type(Content.fromUri) == "function" then
        return safe(function()
            return Content.fromUri("rbxassetid://" .. tostring(id))
        end, nil)
    end

    return nil
end

local function candidatesFor(desc)
    local out = {}
    local seen = {}

    local function add(value)
        if value == nil then return end
        local key = tostring(value)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = value
    end

    if desc.role == "layerReferenceCage" then
        add(safe(function() return desc.wrap.ReferenceMeshContent end, nil))
        add(contentFromId(safe(function() return desc.wrap.ReferenceMeshId end, "")))
    else
        add(safe(function() return desc.wrap.CageMeshContent end, nil))
        add(contentFromId(safe(function() return desc.wrap.CageMeshId end, "")))
    end

    return out
end

local function openEditable(desc)
    local errors = {}
    for _, content in ipairs(candidatesFor(desc)) do
        local ok, editable = pcall(function()
            return AssetService:CreateEditableMeshAsync(content, {FixedSize = true})
        end)
        if ok and editable then return editable end
        errors[#errors + 1] = tostring(editable)
    end
    return nil, table.concat(errors, " | "):sub(1, 1000)
end

local function extractCage(desc, recordIndex)
    local editable, openError = openEditable(desc)
    if not editable then
        return nil, "CreateEditableMeshAsync: " .. tostring(openError)
    end

    local ok, result = pcall(function()
        local vertexIds = editable:GetVertices()
        local faceIds = editable:GetFaces()
        if #vertexIds > MAX_VERTICES then error("vertices acima do limite") end
        if #faceIds > MAX_FACES then error("faces acima do limite") end

        local vertexMap = {}
        local positions = table.create(#vertexIds)
        for i, vertexId in ipairs(vertexIds) do
            vertexMap[tostring(vertexId)] = i
            positions[i] = vec3(editable:GetPosition(vertexId))
            if i % 3000 == 0 then task.wait() end
        end

        local uvMap, uvs = {}, {}
        local normalMap, normals = {}, {}

        local function mapUV(id)
            if id == nil then return 0 end
            local key = tostring(id)
            if uvMap[key] then return uvMap[key] end
            local value = safe(function() return editable:GetUV(id) end, nil)
            if not value then return 0 end
            local idx = #uvs + 1
            uvMap[key] = idx
            uvs[idx] = vec2(value)
            return idx
        end

        local function mapNormal(id)
            if id == nil then return 0 end
            local key = tostring(id)
            if normalMap[key] then return normalMap[key] end
            local value = safe(function() return editable:GetNormal(id) end, nil)
            if not value then return 0 end
            local idx = #normals + 1
            normalMap[key] = idx
            normals[idx] = vec3(value)
            return idx
        end

        local faces = {}
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
            if i % 2000 == 0 then task.wait() end
        end

        -- Bone hierarchy + sparse per-vertex weights, only if present.
        local boneIds = safe(function() return editable:GetBones() end, {})
        local boneIndexById = {}
        local bones = {}
        if type(boneIds) == "table" then
            for i, boneId in ipairs(boneIds) do
                boneIndexById[tostring(boneId)] = i
            end
            for i, boneId in ipairs(boneIds) do
                local parentId = safe(function() return editable:GetBoneParent(boneId) end, 0)
                bones[i] = {
                    name = safe(function() return editable:GetBoneName(boneId) end, ""),
                    cframe = safe(function() return cf(editable:GetBoneCFrame(boneId)) end, nil),
                    parent = boneIndexById[tostring(parentId)] or 0,
                    virtual = safe(function() return editable:GetBoneIsVirtual(boneId) end, false),
                }
            end
        end

        local skin = {}
        if #bones > 0 then
            for i, vertexId in ipairs(vertexIds) do
                local vb = safe(function() return editable:GetVertexBones(vertexId) end, nil)
                local vw = safe(function() return editable:GetVertexBoneWeights(vertexId) end, nil)
                if type(vb) == "table" and type(vw) == "table" and #vb > 0 and #vw > 0 then
                    local mapped = {}
                    local weights = {}
                    local count = math.min(#vb, #vw)
                    for j = 1, count do
                        mapped[j] = boneIndexById[tostring(vb[j])] or 0
                        weights[j] = vw[j]
                    end
                    skin[#skin + 1] = {vertex = i, bones = mapped, weights = weights}
                end
                if i % 3000 == 0 then task.wait() end
            end
        end

        local meta = wrapMetadata(desc.wrap)
        local parent = parentMetadata(desc.wrap)
        local meshId = desc.role == "layerReferenceCage"
            and safe(function() return tostring(desc.wrap.ReferenceMeshId) end, "")
            or safe(function() return tostring(desc.wrap.CageMeshId) end, "")

        return {
            schemaVersion = 2,
            captureMode = "incremental_wrap_cages_only",
            kind = "wrapCage",
            meshIndex = recordIndex,
            role = desc.role,
            partName = parent.parentName,
            fullName = meta.wrapPath .. "::" .. desc.role,
            meshId = meshId,
            assetId = assetId(meshId),
            editableSize = safe(function() return vec3(editable:GetSize()) end, nil),
            vertexCount = #vertexIds,
            faceCount = #faces,
            uvCount = #uvs,
            normalCount = #normals,
            positions = positions,
            uvs = uvs,
            normals = normals,
            faces = faces,
            bones = bones,
            skin = skin,
            wrap = meta,
            parent = parent,
        }
    end)

    pcall(function() editable:Destroy() end)
    if not ok then return nil, tostring(result) end
    return result
end

local function getCharacter()
    local character
    if LocalPlayer and LocalPlayer.UserId == TARGET_USER_ID then
        character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    else
        character = safe(function()
            return Players:CreateHumanoidModelFromUserId(TARGET_USER_ID)
        end, nil)
        if character then
            character.Name = "AvatarGeometry_TemporaryModel"
            character.Parent = workspace
        end
    end

    if not character then return nil end

    -- Aguarda layered clothing terminar de aparecer, sem forcar nada pesado.
    local deadline = os.clock() + 12
    repeat
        local layers, targets = 0, 0
        for _, obj in ipairs(character:GetDescendants()) do
            if obj:IsA("WrapLayer") then layers = layers + 1 end
            if obj:IsA("WrapTarget") then targets = targets + 1 end
        end
        if layers >= 5 and targets >= 15 then break end
        task.wait(0.4)
    until os.clock() >= deadline

    return character
end

local function collectDescriptors(character)
    local descriptors = {}

    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("WrapLayer") then
            descriptors[#descriptors + 1] = {wrap = obj, role = "layerCage"}
            descriptors[#descriptors + 1] = {wrap = obj, role = "layerReferenceCage"}
        elseif obj:IsA("WrapTarget") then
            descriptors[#descriptors + 1] = {wrap = obj, role = "targetCage"}
        end
    end

    table.sort(descriptors, function(a, b)
        local ak = a.wrap:GetFullName() .. "::" .. a.role
        local bk = b.wrap:GetFullName() .. "::" .. b.role
        return ak < bk
    end)

    while #descriptors > MAX_RECORDS do
        descriptors[#descriptors] = nil
    end

    return descriptors
end

local function uploadRecord(uploadId, index, record)
    local text = HttpService:JSONEncode(record)
    local totalChunks = math.max(1, math.ceil(#text / CHUNK_CHARS))

    for chunkIndex = 1, totalChunks do
        local first = (chunkIndex - 1) * CHUNK_CHARS + 1
        local last = math.min(#text, chunkIndex * CHUNK_CHARS)
        requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/chunk", {
            meshIndex = index,
            chunkIndex = chunkIndex,
            totalChunks = totalChunks,
            partName = record.fullName or record.partName or "",
            meshId = record.meshId or "",
            data = string.sub(text, first, last),
        }, 4)
        task.wait()
    end

    return #text
end

local function openSession(expected)
    local response = requestJson("POST", BASE .. "/api/avatar-geometry/start", {
        userId = tostring(TARGET_USER_ID),
        username = USERNAME,
        capturedAt = isoNow(),
        expectedMeshes = expected,
    }, 4)

    if type(response.uploadId) ~= "string" or response.uploadId == "" then
        error("Servidor nao retornou uploadId")
    end
    return response.uploadId
end

local function runUpload(descriptors)
    local lastError

    for attempt = 1, MAX_SESSION_ATTEMPTS do
        local ok, result = pcall(function()
            local uploadId = openSession(#descriptors)
            local failed = {}
            local extracted = 0
            local bytes = 0
            local roles = {layerCage = 0, layerReferenceCage = 0, targetCage = 0}

            for index, desc in ipairs(descriptors) do
                notify(string.format("Cage %d/%d: %s", index, #descriptors, desc.role), 2)

                local record, err = extractCage(desc, index)
                if record then
                    bytes = bytes + uploadRecord(uploadId, index, record)
                    extracted = extracted + 1
                    roles[desc.role] = (roles[desc.role] or 0) + 1
                else
                    failed[#failed + 1] = {
                        meshIndex = index,
                        partName = desc.wrap:GetFullName() .. "::" .. desc.role,
                        meshId = desc.role == "layerReferenceCage"
                            and safe(function() return tostring(desc.wrap.ReferenceMeshId) end, "")
                            or safe(function() return tostring(desc.wrap.CageMeshId) end, ""),
                        error = tostring(err):sub(1, 800),
                    }
                end

                -- Nao mantem a malha em memoria: record sai de escopo aqui.
                record = nil
                task.wait(0.05)
            end

            local finish = requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/finish", {
                failed = failed,
            }, 4)

            return {
                uploadId = uploadId,
                extracted = extracted,
                failed = #failed,
                roles = roles,
                approximateJsonBytes = bytes,
                server = finish,
                attempt = attempt,
            }
        end)

        if ok then return result end
        lastError = tostring(result)

        if attempt < MAX_SESSION_ATTEMPTS then
            notify(string.format("Sessao caiu; repetindo cages (%d/%d)...", attempt + 1, MAX_SESSION_ATTEMPTS), 5)
            task.wait(attempt)
        end
    end

    error(lastError or "Falha ao enviar cages")
end

local function main()
    notify("Coleta leve: somente cages/wraps que faltam.", 5)

    local character = getCharacter()
    if not character then
        error("Nao foi possivel carregar o avatar Capuccino40")
    end

    local descriptors = collectDescriptors(character)
    local layerCount, targetCount = 0, 0
    for _, desc in ipairs(descriptors) do
        if desc.role == "targetCage" then
            targetCount = targetCount + 1
        elseif desc.role == "layerCage" then
            layerCount = layerCount + 1
        end
    end

    if #descriptors == 0 then
        error("Nenhum WrapLayer/WrapTarget encontrado")
    end

    notify(string.format("Encontrado: %d layers, %d targets, %d cages a tentar.", layerCount, targetCount, #descriptors), 6)

    local summary = runUpload(descriptors)
    summary.userId = TARGET_USER_ID
    summary.mode = "incremental_wrap_cages_only"
    summary.descriptors = #descriptors
    summary.layerCount = layerCount
    summary.targetCount = targetCount

    if type(writefile) == "function" then
        safe(function()
            writefile("Capuccino40_WrapCages_Result.json", HttpService:JSONEncode(summary))
        end, nil)
    end

    notify(string.format(
        "Concluido: %d cages; falhas: %d. Layers %d/%d, referencias %d/%d, targets %d/%d.",
        summary.extracted,
        summary.failed,
        summary.roles.layerCage or 0,
        layerCount,
        summary.roles.layerReferenceCage or 0,
        layerCount,
        summary.roles.targetCage or 0,
        targetCount
    ), 12)

    print("[Avatar Geometry Wrap Incremental]", HttpService:JSONEncode(summary))
    return summary
end

local ok, result = pcall(main)
if not ok then
    notify("Falhou: " .. tostring(result), 10)
    warn("[Avatar Geometry Wrap Incremental]", result)
    return nil
end

return result
