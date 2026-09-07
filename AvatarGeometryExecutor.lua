--==============================================================--
-- CAFEINA • AVATAR GEOMETRY EXECUTOR
-- Target: Capuccino40 / UserId 765329164
--
-- MODO INCREMENTAL ULTRA-LEVE
-- Coleta SOMENTE os cages RUNTIME que o proprio Roblox calculou:
--   * WrapLayer Inner + Outer (5 x 2)
--   * WrapTarget Outer (15)
--
-- Nao baixa malhas, texturas, PBR, source cages ou skinning.
-- Envia cada cage imediatamente e libera a tabela local.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local TARGET_USER_ID = 765329164
local USERNAME = "Capuccino40"

local ENV = (getgenv and getgenv()) or _G
local BASE = ENV.GRUPO_LUA_AVATAR_BASE or "https://cafe-na-ia.onrender.com"
local UPLOAD_KEY = ENV.GRUPO_LUA_AVATAR_KEY or ""
local CHUNK_CHARS = 280000
local MAX_RECORDS = 40
local MAX_SESSION_ATTEMPTS = 3

local CAGE_INNER = safe and nil or Enum.CageType.Inner
local CAGE_OUTER = Enum.CageType.Outer

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

CAGE_INNER = safe(function() return Enum.CageType.Inner end, nil)
local OUTER = safe(function() return Enum.CageType.Outer end, nil)

local function cf(v)
    if typeof(v) ~= "CFrame" then return nil end
    return {v:GetComponents()}
end

local function plainVector(value)
    if typeof(value) == "Vector3" then return {value.X, value.Y, value.Z} end
    if typeof(value) == "Vector2" then return {value.X, value.Y} end
    if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then return value end
    if type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do out[k] = plainVector(v) end
        return out
    end
    return tostring(value)
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
if not requestFn then error("Executor sem request/http_request.") end

local function headers()
    local h = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = "Cafeina-AvatarGeometry-RuntimeCage/1.0",
    }
    if UPLOAD_KEY ~= "" then h["x-avatar-dump-key"] = UPLOAD_KEY end
    return h
end

local function requestJson(method, url, payload, tries)
    tries = tries or 3
    local body = payload and HttpService:JSONEncode(payload) or nil
    local last = nil
    for attempt = 1, tries do
        local ok, response = pcall(function()
            return requestFn({Url=url, Method=method, Headers=headers(), Body=body})
        end)
        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or response.status_code) or 0
            local text = tostring(response.Body or response.body or "")
            if status >= 200 and status < 300 then
                return safe(function() return HttpService:JSONDecode(text) end, {}), status
            end
            last = "HTTP " .. tostring(status) .. " - " .. text
        else
            last = tostring(response)
        end
        task.wait(0.5 * attempt)
    end
    error(last or "Falha HTTP")
end

local function isoNow()
    return safe(function() return DateTime.now():ToIsoDate() end, os.date("!%Y-%m-%dT%H:%M:%SZ"))
end

local function getCharacter()
    local character
    if LocalPlayer and LocalPlayer.UserId == TARGET_USER_ID then
        character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    else
        character = safe(function() return Players:CreateHumanoidModelFromUserId(TARGET_USER_ID) end, nil)
        if character then
            character.Name = "AvatarGeometry_TemporaryModel"
            character.Parent = workspace
        end
    end
    if not character then return nil end

    -- Deixa o engine terminar a composicao das roupas.
    local deadline = os.clock() + 12
    repeat
        local layers, targets = 0, 0
        for _, obj in ipairs(character:GetDescendants()) do
            if obj:IsA("WrapLayer") then layers += 1 end
            if obj:IsA("WrapTarget") then targets += 1 end
        end
        if layers >= 5 and targets >= 15 then
            task.wait(2.0)
            break
        end
        task.wait(0.35)
    until os.clock() >= deadline
    return character
end

local function descriptors(character)
    local out = {}
    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("WrapLayer") then
            out[#out+1] = {wrap=obj, cageType=CAGE_INNER, role="runtimeLayerInner"}
            out[#out+1] = {wrap=obj, cageType=OUTER, role="runtimeLayerOuter"}
        elseif obj:IsA("WrapTarget") then
            out[#out+1] = {wrap=obj, cageType=OUTER, role="runtimeTargetOuter"}
        end
    end
    table.sort(out, function(a,b)
        return (a.wrap:GetFullName() .. a.role) < (b.wrap:GetFullName() .. b.role)
    end)
    return out
end

local function extractRuntime(desc, recordIndex)
    if desc.cageType == nil then return nil, "Enum.CageType indisponivel" end
    local wrap = desc.wrap

    local okV, vertices = pcall(function() return wrap:GetVertices(desc.cageType) end)
    if not okV or type(vertices) ~= "table" then
        return nil, "GetVertices: " .. tostring(vertices)
    end
    if #vertices == 0 then return nil, "GetVertices retornou vazio" end

    local okF, faces = pcall(function() return wrap:GetFaces(desc.cageType) end)
    if not okF or type(faces) ~= "table" then
        return nil, "GetFaces: " .. tostring(faces)
    end

    local okU, uvs = pcall(function() return wrap:GetUVs(desc.cageType) end)
    if not okU or type(uvs) ~= "table" then
        uvs = {}
    end

    local part = wrap.Parent
    local meshId = desc.role == "runtimeLayerInner"
        and safe(function() return tostring(wrap.ReferenceMeshId) end, "")
        or safe(function() return tostring(wrap.CageMeshId) end, "")

    local positions = table.create(#vertices)
    for i, v in ipairs(vertices) do positions[i] = plainVector(v) end
    local faceData = plainVector(faces)
    local uvData = plainVector(uvs)

    local record = {
        schemaVersion = 3,
        captureMode = "runtime_deformed_wrap_cages_only",
        kind = "runtimeWrapCage",
        meshIndex = recordIndex,
        role = desc.role,
        partName = part and part.Name or "",
        fullName = wrap:GetFullName() .. "::" .. desc.role,
        meshId = meshId,
        assetId = assetId(meshId),
        vertexCount = #vertices,
        faceEntryCount = #faces,
        uvEntryCount = #uvs,
        positions = positions,
        faces = faceData,
        uvs = uvData,
        normals = {},
        wrap = {
            className = wrap.ClassName,
            path = wrap:GetFullName(),
            cageOrigin = safe(function() return cf(wrap.CageOrigin) end, nil),
            cageOriginWorld = safe(function() return cf(wrap.CageOriginWorld) end, nil),
            importOrigin = safe(function() return cf(wrap.ImportOrigin) end, nil),
            importOriginWorld = safe(function() return cf(wrap.ImportOriginWorld) end, nil),
            cageOffset = safe(function() return plainVector(wrap:GetCageOffset()) end, nil),
        },
        parent = part and {
            cframe = safe(function() return cf(part.CFrame) end, nil),
            meshId = safe(function() return tostring(part.MeshId) end, ""),
        } or nil,
    }

    if wrap:IsA("WrapLayer") then
        record.wrap.order = safe(function() return wrap.Order end, nil)
        record.wrap.bindOffset = safe(function() return cf(wrap.BindOffset) end, nil)
        record.wrap.referenceOrigin = safe(function() return cf(wrap.ReferenceOrigin) end, nil)
        record.wrap.referenceOriginWorld = safe(function() return cf(wrap.ReferenceOriginWorld) end, nil)
    end

    vertices, faces, uvs = nil, nil, nil
    return record
end

local function openSession(expected)
    local start = requestJson("POST", BASE .. "/api/avatar-geometry/start", {
        userId=tostring(TARGET_USER_ID), username=USERNAME, capturedAt=isoNow(), expectedMeshes=expected,
    }, 4)
    if type(start.uploadId) ~= "string" or start.uploadId == "" then error("Sem uploadId") end
    return start.uploadId
end

local function uploadRecord(uploadId, index, record)
    local text = HttpService:JSONEncode(record)
    local total = math.max(1, math.ceil(#text / CHUNK_CHARS))
    for chunk = 1, total do
        local a = (chunk-1)*CHUNK_CHARS + 1
        local b = math.min(#text, chunk*CHUNK_CHARS)
        requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/chunk", {
            meshIndex=index, chunkIndex=chunk, totalChunks=total,
            partName=record.partName or "", meshId=record.meshId or "",
            data=string.sub(text,a,b),
        }, 4)
        task.wait()
    end
    return #text
end

local function runSession(descs)
    local lastError
    for sessionAttempt = 1, MAX_SESSION_ATTEMPTS do
        local ok, result = pcall(function()
            local uploadId = openSession(#descs)
            local failures = {}
            local sent = 0
            local successCount = 0

            for i, desc in ipairs(descs) do
                notify(string.format("Runtime cage %d/%d", i, #descs), 2)
                local record, err = extractRuntime(desc, i)
                if record then
                    sent += uploadRecord(uploadId, i, record)
                    successCount += 1
                    record = nil
                    collectgarbage("collect")
                else
                    failures[#failures+1] = {
                        meshIndex=i,
                        partName=desc.wrap:GetFullName() .. "::" .. desc.role,
                        meshId="",
                        error=tostring(err):sub(1,800),
                    }
                end
                task.wait(0.08)
            end

            if successCount == 0 then
                error("Nenhum runtime cage acessivel. Primeiro erro: " .. tostring(failures[1] and failures[1].error or "desconhecido"))
            end

            local finish = requestJson("POST", BASE .. "/api/avatar-geometry/" .. uploadId .. "/finish", {failed=failures}, 4)
            return {uploadId=uploadId, success=successCount, failed=#failures, bytes=sent, finish=finish, attempt=sessionAttempt}
        end)
        if ok then return result end
        lastError = tostring(result)
        if sessionAttempt < MAX_SESSION_ATTEMPTS then
            notify("Sessao caiu; reabrindo...", 4)
            task.wait(sessionAttempt)
        end
    end
    error(lastError or "Falha")
end

local function main()
    notify("Coletando apenas cages runtime do Roblox...", 5)
    local character = getCharacter()
    if not character then error("Avatar nao encontrado") end
    local descs = descriptors(character)
    if #descs == 0 or #descs > MAX_RECORDS then error("Quantidade de wraps inesperada: " .. #descs) end

    local result = runSession(descs)
    notify(string.format("Concluido: %d cages runtime; %d falhas.", result.success, result.failed), 10)
    print("[Avatar Geometry Runtime]", HttpService:JSONEncode(result))
    return result
end

local ok, result = pcall(main)
if not ok then
    notify("Falhou: " .. tostring(result), 10)
    warn("[Avatar Geometry Runtime]", result)
    return nil
end
return result
