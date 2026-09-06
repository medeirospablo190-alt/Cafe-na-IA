--==============================================================--
-- GRUPO LUA • AVATAR DUMP EXECUTOR V1
-- Target: Capuccino40 / UserId 765329164
--
-- Coleta dados CLIENT-VISIBLE do avatar e envia automaticamente
-- para o servidor do projeto. Não coleta cookies, tokens ou senha.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local TARGET_USER_ID = 765329164

local ENV = (getgenv and getgenv()) or _G
local ENDPOINT = ENV.GRUPO_LUA_AVATAR_ENDPOINT or "https://cafe-na-ia.onrender.com/api/avatar-dump"
local UPLOAD_KEY = ENV.GRUPO_LUA_AVATAR_KEY or ""
local MAX_INSTANCES = 3500

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

local function safeCall(fn, fallback)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return fallback
end

local function enumName(value)
    local text = tostring(value)
    return text
end

local function vector3(v)
    return {x = v.X, y = v.Y, z = v.Z}
end

local function vector2(v)
    return {x = v.X, y = v.Y}
end

local function color3(c)
    return {r = c.R, g = c.G, b = c.B}
end

local function cframe(cf)
    local values = {cf:GetComponents()}
    return values
end

local function udim2(v)
    return {
        xScale = v.X.Scale,
        xOffset = v.X.Offset,
        yScale = v.Y.Scale,
        yOffset = v.Y.Offset,
    }
end

local function sanitize(value, depth)
    depth = depth or 0
    if depth > 6 then
        return tostring(value)
    end

    local t = typeof(value)
    if t == "nil" then
        return nil
    elseif t == "string" or t == "boolean" then
        return value
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return tostring(value)
        end
        return value
    elseif t == "Vector3" then
        return vector3(value)
    elseif t == "Vector2" then
        return vector2(value)
    elseif t == "Color3" then
        return color3(value)
    elseif t == "CFrame" then
        return cframe(value)
    elseif t == "UDim2" then
        return udim2(value)
    elseif t == "EnumItem" then
        return enumName(value)
    elseif t == "BrickColor" then
        return {name = value.Name, number = value.Number, color = color3(value.Color)}
    elseif t == "Instance" then
        return value:GetFullName()
    elseif t == "table" then
        local out = {}
        for k, v in pairs(value) do
            local sk = tostring(k)
            out[sk] = sanitize(v, depth + 1)
        end
        return out
    end

    return tostring(value)
end

local function readProperty(instance, property)
    return safeCall(function()
        return sanitize(instance[property])
    end, nil)
end

local function relativePath(root, instance)
    if instance == root then
        return root.Name
    end

    local names = {}
    local cursor = instance
    while cursor and cursor ~= root do
        table.insert(names, 1, cursor.Name)
        cursor = cursor.Parent
    end
    table.insert(names, 1, root.Name)
    return table.concat(names, ".")
end

local function baseRecord(root, object)
    local record = {
        name = object.Name,
        className = object.ClassName,
        path = relativePath(root, object),
        attributes = safeCall(function()
            return sanitize(object:GetAttributes())
        end, {}),
        tags = safeCall(function()
            return CollectionService:GetTags(object)
        end, {}),
    }

    local sourceAssetId = readProperty(object, "SourceAssetId")
    if sourceAssetId ~= nil then
        record.sourceAssetId = sourceAssetId
    end

    return record
end

local function inspectObject(root, object)
    local r = baseRecord(root, object)

    if object:IsA("BasePart") then
        r.size = vector3(object.Size)
        r.color = color3(object.Color)
        r.material = tostring(object.Material)
        r.transparency = object.Transparency
        r.reflectance = object.Reflectance
        r.cframe = cframe(object.CFrame)
        r.canCollide = object.CanCollide
        r.massless = object.Massless
    end

    if object:IsA("MeshPart") then
        r.meshId = readProperty(object, "MeshId")
        r.textureId = readProperty(object, "TextureID")
        r.renderFidelity = readProperty(object, "RenderFidelity")
        r.collisionFidelity = readProperty(object, "CollisionFidelity")
        r.doubleSided = readProperty(object, "DoubleSided")
    elseif object:IsA("SpecialMesh") then
        r.meshType = readProperty(object, "MeshType")
        r.meshId = readProperty(object, "MeshId")
        r.textureId = readProperty(object, "TextureId")
        r.scale = readProperty(object, "Scale")
        r.offset = readProperty(object, "Offset")
        r.vertexColor = readProperty(object, "VertexColor")
    elseif object:IsA("SurfaceAppearance") then
        r.colorMap = readProperty(object, "ColorMap")
        r.metalnessMap = readProperty(object, "MetalnessMap")
        r.normalMap = readProperty(object, "NormalMap")
        r.roughnessMap = readProperty(object, "RoughnessMap")
        r.alphaMode = readProperty(object, "AlphaMode")
        r.alphaCutoff = readProperty(object, "AlphaCutoff")
    elseif object:IsA("Decal") or object:IsA("Texture") then
        r.texture = readProperty(object, "Texture")
        r.color3 = readProperty(object, "Color3")
        r.transparency = readProperty(object, "Transparency")
    elseif object:IsA("Attachment") then
        r.position = readProperty(object, "Position")
        r.orientation = readProperty(object, "Orientation")
        r.axis = readProperty(object, "Axis")
        r.secondaryAxis = readProperty(object, "SecondaryAxis")
        r.cframe = readProperty(object, "CFrame")
    elseif object:IsA("Accessory") then
        r.accessoryType = readProperty(object, "AccessoryType")
    elseif object:IsA("Shirt") then
        r.shirtTemplate = readProperty(object, "ShirtTemplate")
        r.color3 = readProperty(object, "Color3")
    elseif object:IsA("Pants") then
        r.pantsTemplate = readProperty(object, "PantsTemplate")
        r.color3 = readProperty(object, "Color3")
    elseif object:IsA("ShirtGraphic") then
        r.graphic = readProperty(object, "Graphic")
        r.color3 = readProperty(object, "Color3")
    elseif object:IsA("CharacterMesh") then
        r.bodyPart = readProperty(object, "BodyPart")
        r.meshId = readProperty(object, "MeshId")
        r.baseTextureId = readProperty(object, "BaseTextureId")
        r.overlayTextureId = readProperty(object, "OverlayTextureId")
    elseif object:IsA("BodyColors") then
        r.headColor3 = readProperty(object, "HeadColor3")
        r.leftArmColor3 = readProperty(object, "LeftArmColor3")
        r.rightArmColor3 = readProperty(object, "RightArmColor3")
        r.leftLegColor3 = readProperty(object, "LeftLegColor3")
        r.rightLegColor3 = readProperty(object, "RightLegColor3")
        r.torsoColor3 = readProperty(object, "TorsoColor3")
    elseif object:IsA("Motor6D") or object:IsA("Weld") or object:IsA("WeldConstraint") then
        r.part0 = safeCall(function() return object.Part0 and object.Part0.Name or nil end, nil)
        r.part1 = safeCall(function() return object.Part1 and object.Part1.Name or nil end, nil)
        r.c0 = readProperty(object, "C0")
        r.c1 = readProperty(object, "C1")
    elseif object:IsA("WrapLayer") then
        r.referenceMeshId = readProperty(object, "ReferenceMeshId")
        r.cageMeshId = readProperty(object, "CageMeshId")
        r.order = readProperty(object, "Order")
        r.puffiness = readProperty(object, "Puffiness")
        r.enabled = readProperty(object, "Enabled")
    elseif object:IsA("WrapTarget") then
        r.cageMeshId = readProperty(object, "CageMeshId")
        r.stiffness = readProperty(object, "Stiffness")
    end

    return r
end

local DESCRIPTION_PROPERTIES = {
    "BackAccessory", "FaceAccessory", "FrontAccessory", "HairAccessory",
    "HatAccessory", "NeckAccessory", "ShouldersAccessory", "WaistAccessory",
    "ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation",
    "RunAnimation", "SwimAnimation", "WalkAnimation",
    "Face", "Head", "LeftArm", "LeftLeg", "RightArm", "RightLeg", "Torso",
    "GraphicTShirt", "Shirt", "Pants",
    "BodyTypeScale", "DepthScale", "HeadScale", "HeightScale",
    "ProportionScale", "WidthScale",
    "HeadColor", "LeftArmColor", "LeftLegColor", "RightArmColor",
    "RightLegColor", "TorsoColor",
}

local function inspectDescription(description)
    if not description then
        return nil
    end

    local out = {properties = {}}
    for _, property in ipairs(DESCRIPTION_PROPERTIES) do
        local value = readProperty(description, property)
        if value ~= nil then
            out.properties[property] = value
        end
    end

    out.accessories = safeCall(function()
        local accessories = description:GetAccessories(true)
        local result = {}
        for i, accessory in ipairs(accessories) do
            result[i] = {
                assetId = sanitize(accessory.AssetId),
                accessoryType = sanitize(accessory.AccessoryType),
                order = sanitize(accessory.Order),
                puffiness = sanitize(accessory.Puffiness),
                isLayered = sanitize(accessory.IsLayered),
            }
        end
        return result
    end, {})

    return out
end

local function getCharacterAndDescription()
    local character = nil
    local description = nil

    if LocalPlayer and LocalPlayer.UserId == TARGET_USER_ID then
        character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    description = safeCall(function()
        return Players:GetHumanoidDescriptionFromUserId(TARGET_USER_ID)
    end, nil)

    if not character then
        character = safeCall(function()
            return Players:CreateHumanoidModelFromUserId(TARGET_USER_ID)
        end, nil)
        if character then
            character.Name = "AvatarDump_TemporaryModel"
        end
    end

    if character and not description then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            description = safeCall(function()
                return humanoid:GetAppliedDescription()
            end, nil)
        end
    end

    return character, description
end

local function collectAvatar()
    notify("Avatar Dump", "Coletando avatar e texturas...", 4)

    local character, description = getCharacterAndDescription()
    if not character then
        error("Não foi possível localizar/criar o avatar alvo.")
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local objects = {}
    local counts = {}
    local uniqueAssets = {}

    local descendants = character:GetDescendants()
    local total = math.min(#descendants, MAX_INSTANCES)

    for i = 1, total do
        local object = descendants[i]
        local record = inspectObject(character, object)
        objects[#objects + 1] = record
        counts[object.ClassName] = (counts[object.ClassName] or 0) + 1

        for _, key in ipairs({"meshId", "textureId", "texture", "colorMap", "metalnessMap", "normalMap", "roughnessMap", "shirtTemplate", "pantsTemplate", "graphic", "baseTextureId", "overlayTextureId", "referenceMeshId", "cageMeshId", "sourceAssetId"}) do
            local value = record[key]
            if value ~= nil and tostring(value) ~= "" and tostring(value) ~= "0" then
                uniqueAssets[tostring(value)] = true
            end
        end

        if i % 100 == 0 then
            task.wait()
        end
    end

    local assets = {}
    for value in pairs(uniqueAssets) do
        assets[#assets + 1] = value
    end
    table.sort(assets)

    local avatar = {
        modelName = character.Name,
        rigType = humanoid and tostring(humanoid.RigType) or nil,
        objectCount = total,
        truncated = #descendants > MAX_INSTANCES,
        totalDescendants = #descendants,
        classCounts = counts,
        humanoidDescription = inspectDescription(description),
        uniqueAssetReferences = assets,
        objects = objects,
    }

    return avatar
end

local function getRequestFunction()
    local candidates = {
        ENV.request,
        ENV.http_request,
        syn and syn.request,
        http and http.request,
        fluxus and fluxus.request,
    }

    for _, candidate in ipairs(candidates) do
        if type(candidate) == "function" then
            return candidate
        end
    end

    return nil
end

local function isoNow()
    return safeCall(function()
        return DateTime.now():ToIsoDate()
    end, os.date("!%Y-%m-%dT%H:%M:%SZ"))
end

local function buildPayload(avatar)
    return {
        schemaVersion = 1,
        userId = tostring(TARGET_USER_ID),
        username = LocalPlayer and LocalPlayer.UserId == TARGET_USER_ID and LocalPlayer.Name or "Capuccino40",
        capturedAt = isoNow(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        avatar = avatar,
    }
end

local function saveLocal(text)
    if type(writefile) ~= "function" then
        return nil
    end

    local filename = "Capuccino40_AvatarDump_" .. tostring(os.time()) .. ".json"
    safeCall(function()
        writefile(filename, text)
    end, nil)
    return filename
end

local function upload(text)
    local requestFn = getRequestFunction()
    if not requestFn then
        error("Seu executor não expõe request/http_request.")
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = "GrupoLua-AvatarDump-Executor/1.0",
    }
    if UPLOAD_KEY ~= "" then
        headers["x-avatar-dump-key"] = UPLOAD_KEY
    end

    local lastError = nil
    for attempt = 1, 3 do
        local ok, response = pcall(function()
            return requestFn({
                Url = ENDPOINT,
                Method = "POST",
                Headers = headers,
                Body = text,
            })
        end)

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or response.status_code) or 0
            local body = tostring(response.Body or response.body or "")
            if status >= 200 and status < 300 then
                return status, body
            end
            lastError = "HTTP " .. tostring(status) .. " - " .. body
        else
            lastError = tostring(response)
        end

        task.wait(attempt * 1.25)
    end

    error(lastError or "Falha desconhecida no upload.")
end

local function main()
    local started = os.clock()
    local avatar = collectAvatar()
    local payload = buildPayload(avatar)
    local text = HttpService:JSONEncode(payload)
    local localFile = saveLocal(text)

    notify("Avatar Dump", string.format("Coleta pronta: %.1f KB. Enviando...", #text / 1024), 4)
    local status, responseBody = upload(text)

    local decoded = safeCall(function()
        return HttpService:JSONDecode(responseBody)
    end, nil)

    local latestUrl = nil
    if type(decoded) == "table" and decoded.latestUrl then
        latestUrl = ENDPOINT:gsub("/api/avatar%-dump$", "") .. tostring(decoded.latestUrl)
    end

    notify("Avatar Dump", "Enviado com sucesso. Agora é só pedir ao ChatGPT para analisar.", 7)

    print("[GRUPO LUA Avatar Dump] OK")
    print("Status:", status)
    print("Objetos:", avatar.objectCount)
    print("Referências de assets:", #avatar.uniqueAssetReferences)
    print("Bytes JSON:", #text)
    print("Tempo:", string.format("%.2fs", os.clock() - started))
    if localFile then print("Cópia local:", localFile) end
    if latestUrl then print("Latest:", latestUrl) end

    ENV.GRUPO_LUA_LAST_AVATAR_DUMP = payload
    ENV.GRUPO_LUA_LAST_AVATAR_DUMP_RESPONSE = decoded or responseBody

    return decoded or responseBody
end

local ok, result = pcall(main)
if not ok then
    warn("[GRUPO LUA Avatar Dump]", result)
    notify("Avatar Dump", "Falha: " .. tostring(result), 8)
end

return ok and result or nil
