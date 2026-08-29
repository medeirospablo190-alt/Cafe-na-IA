--==============================================================--
-- CAFEÍNA • INSIGHT SCANNER V3 • MOBILE
--
-- Scanner passivo e direcionado a dados client-visible.
-- Foco: estrutura útil + mudanças reais de estado.
--
-- Melhorias sobre V2:
--   • baseline + delta (não repete snapshot inteiro sem necessidade)
--   • remoções/reaparecimentos registrados
--   • filtros semânticos para Tycoons/Soldiers/Tools
--   • resumos de Models/Tools
--   • atributos preservam tipos simples/Vector/Color/Enum
--   • posição de NPC agregada no Model, não em todos os membros
--   • remotes são apenas inventariados; nunca são invocados
--   • upload em chunks para o mesmo backend
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIG
--==============================================================--
local CONFIG = {
    API_BASE = "https://cafe-na-ia.onrender.com",
    UPLOAD_TOKEN = "",

    MAX_TOTAL_BYTES = 250 * 1024 * 1024,
    CHUNK_TARGET_BYTES = 3200000,
    CHUNK_HARD_BYTES = 5500000,
    MEMORY_FALLBACK_LIMIT = 64 * 1024 * 1024,

    PASS_INTERVAL = 1.5,
    STABLE_PASSES_REQUIRED = 6,
    MAX_PASSES = 60,
    YIELD_EVERY = 120,

    UPLOAD_RETRIES = 4,
    RETRY_DELAY = 1.25,

    PROFILE_NAME = "insight-focused-v3",
    VERSION = "V3-INSIGHT-FOCUSED",
    SOURCE = "cafeina-insight-focused-v3",
}

--==============================================================--
-- EXECUTOR APIs
--==============================================================--
local requestFn =
    (syn and syn.request)
    or http_request
    or request
    or (http and http.request)

local writefileFn = writefile
local readfileFn = readfile
local isfileFn = isfile
local delfileFn = delfile
local makefolderFn = makefolder
local isfolderFn = isfolder

local CAN_SPOOL_TO_DISK =
    type(writefileFn) == "function"
    and type(readfileFn) == "function"

--==============================================================--
-- ESTADO
--==============================================================--
local ScanRunning = false
local ScanComplete = false
local UploadRunning = false
local CancelGeneration = 0
local WasInterrupted = false

local TotalRecordedBytes = 0
local TotalRecords = 0
local TotalPasses = 0
local StablePasses = 0

local CurrentChunk = {}
local CurrentChunkBytes = 2
local StoredChunks = {}
local MemoryChunks = {}

local CategoryCounts = {}
local RecordTypeCounts = {}
local LastPassCounts = {}

-- Estado semântico persistente entre passes.
local LastStates = {}
local LastSignatures = {}
local ActiveKeys = {}

local SessionFolder = "CafeinaInsight_" .. tostring(os.time())

--==============================================================--
-- HELPERS
--==============================================================--
local function readableSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    return tostring(bytes) .. " B"
end

local function safeString(value, maxLen)
    local text = tostring(value == nil and "" or value)
    maxLen = maxLen or 1000
    if #text > maxLen then
        return text:sub(1, maxLen)
    end
    return text
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function startsWith(text, prefix)
    text = tostring(text or "")
    prefix = tostring(prefix or "")
    return text:sub(1, #prefix) == prefix
end

local function containsAny(text, needles)
    text = lower(text)
    for _, needle in ipairs(needles) do
        if string.find(text, needle, 1, true) then
            return true
        end
    end
    return false
end

local function safeFullName(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    if ok then
        return result
    end
    return inst and inst.Name or "?"
end

local function roundNumber(n, decimals)
    n = tonumber(n) or 0
    local m = 10 ^ (decimals or 3)
    if n >= 0 then
        return math.floor(n * m + 0.5) / m
    end
    return math.ceil(n * m - 0.5) / m
end

local function serializeValue(value, depth)
    depth = depth or 0
    if depth > 4 then
        return safeString(value, 300)
    end

    local kind = typeof(value)

    if kind == "nil" then
        return nil
    elseif kind == "string" then
        return safeString(value, 1600)
    elseif kind == "number" then
        return roundNumber(value, 6)
    elseif kind == "boolean" then
        return value
    elseif kind == "Vector2" then
        return {type = "Vector2", x = roundNumber(value.X, 3), y = roundNumber(value.Y, 3)}
    elseif kind == "Vector3" then
        return {type = "Vector3", x = roundNumber(value.X, 3), y = roundNumber(value.Y, 3), z = roundNumber(value.Z, 3)}
    elseif kind == "Color3" then
        return {type = "Color3", r = roundNumber(value.R, 4), g = roundNumber(value.G, 4), b = roundNumber(value.B, 4)}
    elseif kind == "UDim" then
        return {type = "UDim", scale = roundNumber(value.Scale, 4), offset = value.Offset}
    elseif kind == "UDim2" then
        return {
            type = "UDim2",
            x = {scale = roundNumber(value.X.Scale, 4), offset = value.X.Offset},
            y = {scale = roundNumber(value.Y.Scale, 4), offset = value.Y.Offset},
        }
    elseif kind == "CFrame" then
        local p = value.Position
        return {type = "CFrame", position = {x = roundNumber(p.X, 2), y = roundNumber(p.Y, 2), z = roundNumber(p.Z, 2)}}
    elseif kind == "EnumItem" then
        return tostring(value)
    elseif kind == "BrickColor" then
        return tostring(value)
    elseif kind == "Instance" then
        return {type = "Instance", path = safeFullName(value), className = value.ClassName}
    elseif kind == "table" then
        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count += 1
            if count > 120 then
                out.__truncated = true
                break
            end
            out[safeString(k, 120)] = serializeValue(v, depth + 1)
        end
        return out
    end

    return safeString(value, 800)
end

local function encoded(value)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    if not ok then
        return nil
    end
    return result
end

local function encodedSize(value)
    local result = encoded(value)
    if not result then
        return 0, nil
    end
    return #result, result
end

local function attributesSnapshot(inst)
    local output = {}
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return output
    end

    local count = 0
    for key, value in pairs(attrs) do
        count += 1
        if count > 120 then
            output.__truncated = true
            break
        end
        output[safeString(key, 120)] = serializeValue(value)
    end

    return output
end

local function hasAttributes(inst)
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)
    return ok and type(attrs) == "table" and next(attrs) ~= nil
end

local function valueSnapshot(inst)
    if not inst:IsA("ValueBase") then
        return nil
    end

    local ok, value = pcall(function()
        return inst.Value
    end)
    if not ok then
        return nil
    end

    return serializeValue(value)
end

local function classHistogram(root, limit)
    local counts = {}
    local total = 0
    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if not ok then
        return {total = 0, classes = {}}
    end

    for _, inst in ipairs(descendants) do
        total += 1
        counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
        if limit and total >= limit then
            break
        end
    end

    return {total = #descendants, classes = counts}
end

local IMPORTANT_TYCOON_NAMES = {
    "button", "buy", "purchase", "collector", "collect", "cash", "money",
    "income", "rebirth", "dropper", "conveyor", "spawn", "door", "gate",
    "weapon", "gun", "armor", "armour", "vehicle", "atv", "owner", "price",
    "cost", "unlock", "upgrade", "terminal", "claim",
}

local IMPORTANT_TOOL_NAMES = {
    "ammo", "mag", "reload", "fire", "rate", "damage", "range", "spread",
    "recoil", "ray", "projectile", "bullet", "beam", "tracer", "muzzle",
    "aim", "zoom", "handle", "sound", "animation", "effect", "hit",
}

local IMPORTANT_GAME_VALUES = {
    "money", "cash", "coin", "kill", "rebirth", "ammo", "mag", "damage",
    "health", "price", "cost", "income", "level", "xp", "team", "plot",
}

local COMBAT_UI_NAMES = {
    "ammo", "magazine", "reload", "autofire", "crosshair", "reticle",
    "weapon", "gun", "firemode", "hitmarker", "health", "damage",
}

local function isRemote(inst)
    return inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
end

local function isInteraction(inst)
    return inst:IsA("ProximityPrompt")
        or inst:IsA("TouchTransmitter")
        or inst:IsA("ClickDetector")
end

local function getTopChildUnder(root, inst)
    if not root or not inst or not inst:IsDescendantOf(root) then
        return nil
    end
    local current = inst
    while current and current.Parent ~= root do
        current = current.Parent
    end
    return current
end

local function isTopChildUnder(root, inst)
    return root and inst and inst.Parent == root
end

local function getCategory(inst)
    local path = safeFullName(inst)
    local pathLower = lower(path)
    local nameLower = lower(inst.Name)

    if string.find(pathLower, "replicatedstorage.blastersystem", 1, true) then
        return "BlasterSystem", 100
    end

    if isRemote(inst) then
        return "Remotes", 99
    end

    if string.find(pathLower, "workspace.soldiers", 1, true) then
        return "Soldiers", 98
    end

    if string.find(pathLower, "workspace.tycoons", 1, true) then
        return "Tycoons", 94
    end

    if inst:IsA("Tool") or inst:FindFirstAncestorOfClass("Tool") then
        return "Tools", 92
    end

    if startsWith(path, "Players.") then
        if string.find(pathLower, ".leaderstats", 1, true)
            or string.find(pathLower, ".backpack", 1, true)
            or string.find(pathLower, ".character", 1, true)
        then
            return "PlayerData", 86
        end
    end

    if startsWith(path, "Players." .. LocalPlayer.Name .. ".PlayerGui")
        or startsWith(path, "StarterGui")
    then
        if containsAny(pathLower, COMBAT_UI_NAMES) or containsAny(nameLower, COMBAT_UI_NAMES) then
            return "CombatUI", 84
        end
    end

    if isInteraction(inst) then
        return "Interactions", 74
    end

    if inst:IsA("ValueBase") and containsAny(nameLower, IMPORTANT_GAME_VALUES) then
        return "GameValues", 66
    end

    return nil, 0
end

--==============================================================--
-- FILTRO SEMÂNTICO
--==============================================================--
local function shouldCollect(inst, category)
    if not inst or not inst.Parent then
        return false
    end

    if category == "Remotes" then
        return true
    end

    if category == "BlasterSystem" then
        -- Estrutura do sistema de combate é pequena e altamente relevante.
        -- Geometria repetitiva só entra se tiver attrs ou nome semântico.
        if inst:IsA("BasePart") then
            return hasAttributes(inst)
                or containsAny(inst.Name, IMPORTANT_TOOL_NAMES)
                or inst.Name == "Handle"
        end
        return true
    end

    if category == "Soldiers" then
        local root = Workspace:FindFirstChild("Soldiers")
        if isTopChildUnder(root, inst) then
            return true -- resumo do Soldier Model
        end

        if inst:IsA("Humanoid")
            or inst:IsA("Tool")
            or inst:IsA("ValueBase")
            or inst:IsA("BindableEvent")
            or inst:IsA("BindableFunction")
            or inst:IsA("Animation")
            or inst:IsA("Sound")
        then
            return true
        end

        if inst:IsA("Attachment") then
            return containsAny(inst.Name, {"muzzle", "fire", "gun", "weapon", "aim", "barrel"})
        end

        if inst:IsA("BasePart") then
            -- Só peças que representam posição/colisão importante.
            return inst.Name == "HumanoidRootPart"
                or inst.Name == "Head"
                or containsAny(inst.Name, {"hitbox", "root", "torso"})
        end

        return hasAttributes(inst)
    end

    if category == "Tycoons" then
        local root = Workspace:FindFirstChild("Tycoons")
        if isTopChildUnder(root, inst) then
            return true -- resumo do Tycoon Model
        end

        if inst:IsA("ValueBase")
            or inst:IsA("Tool")
            or isInteraction(inst)
            or inst:IsA("BindableEvent")
            or inst:IsA("BindableFunction")
        then
            return true
        end

        if hasAttributes(inst) then
            return true
        end

        return containsAny(inst.Name, IMPORTANT_TYCOON_NAMES)
            or containsAny(safeFullName(inst), IMPORTANT_TYCOON_NAMES)
    end

    if category == "Tools" then
        if inst:IsA("Tool")
            or inst:IsA("ValueBase")
            or inst:IsA("Animation")
            or inst:IsA("Sound")
        then
            return true
        end

        if hasAttributes(inst) then
            return true
        end

        if inst:IsA("Attachment") or inst:IsA("BasePart") or inst:IsA("Folder") then
            return containsAny(inst.Name, IMPORTANT_TOOL_NAMES)
                or inst.Name == "Handle"
        end

        return containsAny(inst.Name, IMPORTANT_TOOL_NAMES)
    end

    if category == "PlayerData" then
        if inst:IsA("ValueBase") or inst:IsA("Tool") or inst:IsA("Humanoid") then
            return true
        end
        if inst:IsA("Folder") then
            return inst.Name == "leaderstats" or inst.Name == "Backpack"
        end
        if inst:IsA("Model") then
            return inst == LocalPlayer.Character
        end
        return hasAttributes(inst)
    end

    if category == "CombatUI" then
        return inst:IsA("GuiObject")
            or inst:IsA("ValueBase")
            or hasAttributes(inst)
    end

    return true
end

--==============================================================--
-- PROPRIEDADES / RELAÇÕES / RESUMOS
--==============================================================--
local function compactProperties(inst, category)
    local p = {}

    if isRemote(inst) then
        p.remoteType = inst.ClassName
    elseif inst:IsA("Tool") then
        p.requiresHandle = inst.RequiresHandle
        p.canBeDropped = inst.CanBeDropped
        p.toolTip = safeString(inst.ToolTip, 300)
    elseif inst:IsA("Humanoid") then
        p.health = roundNumber(inst.Health, 3)
        p.maxHealth = roundNumber(inst.MaxHealth, 3)
        p.walkSpeed = roundNumber(inst.WalkSpeed, 3)
        p.jumpPower = roundNumber(inst.JumpPower, 3)
        p.rigType = tostring(inst.RigType)
        p.floorMaterial = tostring(inst.FloorMaterial)
        p.moveDirection = serializeValue(inst.MoveDirection)
    elseif inst:IsA("ProximityPrompt") then
        p.actionText = safeString(inst.ActionText, 300)
        p.objectText = safeString(inst.ObjectText, 300)
        p.enabled = inst.Enabled
        p.holdDuration = roundNumber(inst.HoldDuration, 3)
        p.maxActivationDistance = roundNumber(inst.MaxActivationDistance, 3)
        p.requiresLineOfSight = inst.RequiresLineOfSight
    elseif inst:IsA("ClickDetector") then
        p.maxActivationDistance = roundNumber(inst.MaxActivationDistance, 3)
    elseif inst:IsA("BasePart") then
        p.anchored = inst.Anchored
        p.canCollide = inst.CanCollide
        p.canTouch = inst.CanTouch
        p.canQuery = inst.CanQuery
        p.transparency = roundNumber(inst.Transparency, 3)
        p.size = serializeValue(inst.Size)

        -- Posição só para peças semanticamente relevantes.
        if category ~= "Tycoons" or containsAny(inst.Name, IMPORTANT_TYCOON_NAMES) then
            local pos = inst.Position
            -- 0.25 stud reduz ruído de microvariações.
            p.position = {
                x = roundNumber(math.floor(pos.X * 4 + 0.5) / 4, 2),
                y = roundNumber(math.floor(pos.Y * 4 + 0.5) / 4, 2),
                z = roundNumber(math.floor(pos.Z * 4 + 0.5) / 4, 2),
            }
        end
    elseif inst:IsA("GuiObject") then
        p.visible = inst.Visible
        p.active = inst.Active
        p.absoluteSize = serializeValue(inst.AbsoluteSize)
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            p.text = safeString(inst.Text, 600)
        end
    elseif inst:IsA("Sound") then
        p.soundId = safeString(inst.SoundId, 500)
        p.volume = roundNumber(inst.Volume, 3)
        p.playbackSpeed = roundNumber(inst.PlaybackSpeed, 3)
        p.looped = inst.Looped
        p.playing = inst.Playing
    elseif inst:IsA("Animation") then
        p.animationId = safeString(inst.AnimationId, 500)
    elseif inst:IsA("Attachment") then
        p.position = serializeValue(inst.Position)
        p.axis = serializeValue(inst.Axis)
    elseif inst:IsA("Model") then
        local ok, pivot = pcall(function()
            return inst:GetPivot()
        end)
        if ok and pivot then
            local pos = pivot.Position
            p.pivot = {
                x = roundNumber(math.floor(pos.X * 2 + 0.5) / 2, 2),
                y = roundNumber(math.floor(pos.Y * 2 + 0.5) / 2, 2),
                z = roundNumber(math.floor(pos.Z * 2 + 0.5) / 2, 2),
            }
        end
        if inst.PrimaryPart then
            p.primaryPart = inst.PrimaryPart.Name
        end
    end

    return p
end

local function relationSnapshot(inst)
    local rel = {}
    local parent = inst.Parent

    if parent then
        rel.parent = {path = safeFullName(parent), className = parent.ClassName}
    end

    local tool = inst:FindFirstAncestorOfClass("Tool")
    if tool and tool ~= inst then
        rel.tool = safeFullName(tool)
    end

    local model = inst:FindFirstAncestorOfClass("Model")
    if model and model ~= inst then
        rel.model = safeFullName(model)
    end

    local tycoonRoot = Workspace:FindFirstChild("Tycoons")
    local tycoon = getTopChildUnder(tycoonRoot, inst)
    if tycoon then
        rel.tycoon = tycoon.Name
    end

    local soldiersRoot = Workspace:FindFirstChild("Soldiers")
    local soldier = getTopChildUnder(soldiersRoot, inst)
    if soldier then
        rel.soldier = soldier.Name
    end

    -- Agrupamento de remotes por serviço/pasta pai.
    if isRemote(inst) and parent then
        rel.remoteGroup = parent.Name
        if parent.Parent then
            rel.remoteService = parent.Parent.Name
        end
    end

    return rel
end

local function semanticChildren(root, category)
    local names = {}
    local seen = {}
    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if not ok then
        return names
    end

    for _, inst in ipairs(descendants) do
        local include = false

        if inst:IsA("Tool") or inst:IsA("ValueBase") or isInteraction(inst) or isRemote(inst) then
            include = true
        elseif category == "Soldiers" and (inst:IsA("BindableEvent") or inst:IsA("BindableFunction")) then
            include = true
        elseif category == "Tycoons" and containsAny(inst.Name, IMPORTANT_TYCOON_NAMES) then
            include = true
        elseif category == "Tools" and containsAny(inst.Name, IMPORTANT_TOOL_NAMES) then
            include = true
        end

        if include then
            local key = inst.ClassName .. ":" .. inst.Name
            if not seen[key] then
                seen[key] = true
                names[#names + 1] = key
                if #names >= 80 then
                    names[#names + 1] = "__truncated"
                    break
                end
            end
        end
    end

    table.sort(names)
    return names
end

local function summarySnapshot(inst, category)
    local summary = nil

    if inst:IsA("Model") and (category == "Soldiers" or category == "Tycoons") then
        summary = {
            descendants = classHistogram(inst, 5000),
            semanticChildren = semanticChildren(inst, category),
        }

        if category == "Soldiers" then
            local hum = inst:FindFirstChildOfClass("Humanoid")
            if hum then
                summary.humanoid = {
                    health = roundNumber(hum.Health, 3),
                    maxHealth = roundNumber(hum.MaxHealth, 3),
                    walkSpeed = roundNumber(hum.WalkSpeed, 3),
                }
            end

            local tools = {}
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("Tool") then
                    tools[#tools + 1] = d.Name
                end
            end
            table.sort(tools)
            summary.tools = tools
        end
    elseif inst:IsA("Tool") then
        summary = {
            descendants = classHistogram(inst, 1500),
            semanticChildren = semanticChildren(inst, "Tools"),
        }
    end

    return summary
end

local function snapshotState(inst, category, priority)
    return {
        category = category,
        priority = priority,
        path = safeFullName(inst),
        parentPath = inst.Parent and safeFullName(inst.Parent) or "",
        name = safeString(inst.Name, 300),
        className = inst.ClassName,
        childCount = #inst:GetChildren(),
        attributes = attributesSnapshot(inst),
        value = valueSnapshot(inst),
        properties = compactProperties(inst, category),
        relations = relationSnapshot(inst),
        summary = summarySnapshot(inst, category),
    }
end

--==============================================================--
-- DELTA
--==============================================================--
local function tablesEqual(a, b)
    local ea = encoded(a)
    local eb = encoded(b)
    return ea ~= nil and eb ~= nil and ea == eb
end

local function shallowDelta(previous, current)
    local changes = {}

    local scalarFields = {
        "parentPath", "name", "className", "childCount", "priority", "value",
    }

    for _, field in ipairs(scalarFields) do
        if not tablesEqual(previous[field], current[field]) then
            changes[field] = current[field]
            if current[field] == nil then
                changes[field] = {__removed = true}
            end
        end
    end

    local tableFields = {"attributes", "properties", "relations", "summary"}
    for _, field in ipairs(tableFields) do
        local oldTable = previous[field] or {}
        local newTable = current[field] or {}
        if not tablesEqual(oldTable, newTable) then
            local fieldDelta = {}
            local keys = {}
            for k in pairs(oldTable) do keys[k] = true end
            for k in pairs(newTable) do keys[k] = true end

            for k in pairs(keys) do
                if not tablesEqual(oldTable[k], newTable[k]) then
                    if newTable[k] == nil then
                        fieldDelta[k] = {__removed = true}
                    else
                        fieldDelta[k] = newTable[k]
                    end
                end
            end
            changes[field] = fieldDelta
        end
    end

    return changes
end

local function stateSignature(state)
    return encoded({
        state.parentPath,
        state.name,
        state.className,
        state.childCount,
        state.attributes,
        state.value,
        state.properties,
        state.relations,
        state.summary,
    }) or (state.path .. "|" .. state.className)
end

--==============================================================--
-- CHUNKS / ARMAZENAMENTO
--==============================================================--
local function ensureFolder()
    if not CAN_SPOOL_TO_DISK then
        return false
    end

    if type(isfolderFn) == "function" and isfolderFn(SessionFolder) then
        return true
    end

    if type(makefolderFn) == "function" then
        pcall(makefolderFn, SessionFolder)
    end

    if type(isfolderFn) == "function" then
        return isfolderFn(SessionFolder)
    end

    return true
end

local function storeChunk(chunk, chunkEncoded)
    local index = #StoredChunks + #MemoryChunks + 1

    if CAN_SPOOL_TO_DISK and ensureFolder() then
        local path = SessionFolder .. "/chunk_" .. string.format("%05d", index) .. ".json"
        local ok = pcall(writefileFn, path, chunkEncoded)
        if ok then
            StoredChunks[#StoredChunks + 1] = path
            return true
        end
    end

    local projected = #chunkEncoded
    for _, item in ipairs(MemoryChunks) do
        projected += item.bytes
    end

    if projected > CONFIG.MEMORY_FALLBACK_LIMIT then
        return false, "Sem armazenamento local; limite de memória atingido"
    end

    MemoryChunks[#MemoryChunks + 1] = {objects = chunk, bytes = #chunkEncoded}
    return true
end

local function flushChunk()
    if #CurrentChunk == 0 then
        return true
    end

    local _, chunkEncoded = encodedSize(CurrentChunk)
    if not chunkEncoded then
        return false, "Falha ao codificar bloco"
    end

    if #chunkEncoded > CONFIG.CHUNK_HARD_BYTES then
        return false, "Bloco excedeu limite seguro de upload"
    end

    local ok, err = storeChunk(CurrentChunk, chunkEncoded)
    if not ok then
        return false, err
    end

    CurrentChunk = {}
    CurrentChunkBytes = 2
    return true
end

local function addRecord(record)
    local bytes = encodedSize(record)
    if bytes <= 0 then
        return true, false
    end

    if TotalRecordedBytes + CurrentChunkBytes + bytes > CONFIG.MAX_TOTAL_BYTES then
        return false, "LIMIT_REACHED"
    end

    if CurrentChunkBytes + bytes > CONFIG.CHUNK_TARGET_BYTES and #CurrentChunk > 0 then
        local ok, err = flushChunk()
        if not ok then
            return false, err
        end
    end

    CurrentChunk[#CurrentChunk + 1] = record
    CurrentChunkBytes += bytes
    TotalRecordedBytes += bytes
    TotalRecords += 1

    local category = record.category or "Meta"
    local recordType = record.recordType or "unknown"
    CategoryCounts[category] = (CategoryCounts[category] or 0) + 1
    RecordTypeCounts[recordType] = (RecordTypeCounts[recordType] or 0) + 1

    return true, true
end

local function addHeader()
    return addRecord({
        recordType = "insight_scan_header",
        scanner = "CAFEINA",
        version = CONFIG.VERSION,
        profile = CONFIG.PROFILE_NAME,
        generatedAtUnix = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        clientVisibleOnly = true,
        passiveOnly = true,
        remoteInvocation = false,
        strategy = {
            "baseline_then_delta",
            "semantic_filtering",
            "model_summaries",
            "removal_tracking",
            "typed_attributes",
        },
        focus = {
            "BlasterSystem", "Remotes", "Soldiers", "Tycoons", "Tools",
            "PlayerData", "CombatUI", "Interactions", "GameValues",
        },
    })
end

--==============================================================--
-- ENUMERAÇÃO
--==============================================================--
local function roots()
    return {ReplicatedStorage, Workspace, Players, StarterPack, StarterGui}
end

local function enumerateRelevantObjects()
    local output = {}
    local seen = {}

    local function consider(inst)
        if not inst or seen[inst] then
            return
        end

        local category, priority = getCategory(inst)
        if category and shouldCollect(inst, category) then
            seen[inst] = true
            output[#output + 1] = {
                instance = inst,
                category = category,
                priority = priority,
            }
        end
    end

    for _, root in ipairs(roots()) do
        local ok, descendants = pcall(function()
            return root:GetDescendants()
        end)

        if ok then
            for _, inst in ipairs(descendants) do
                consider(inst)
            end
        end
    end

    table.sort(output, function(a, b)
        if a.priority == b.priority then
            return safeFullName(a.instance) < safeFullName(b.instance)
        end
        return a.priority > b.priority
    end)

    return output
end

local function processState(inst, category, priority, passNumber, currentKeys)
    local state = snapshotState(inst, category, priority)
    local key = category .. "|" .. state.path
    local signature = stateSignature(state)

    currentKeys[key] = true
    LastPassCounts[category] = (LastPassCounts[category] or 0) + 1

    local previousSignature = LastSignatures[key]
    if previousSignature == signature then
        ActiveKeys[key] = true
        return true, false
    end

    local record
    local previous = LastStates[key]

    if previous == nil then
        record = {
            recordType = "insight_baseline",
            profile = CONFIG.PROFILE_NAME,
            observedAt = os.time(),
            pass = passNumber,
            category = category,
            path = state.path,
            state = state,
        }
    else
        local changes = shallowDelta(previous, state)
        record = {
            recordType = "insight_delta",
            profile = CONFIG.PROFILE_NAME,
            observedAt = os.time(),
            pass = passNumber,
            category = category,
            path = state.path,
            className = state.className,
            changes = changes,
        }
    end

    local okAdd, result = addRecord(record)
    if not okAdd then
        return false, result
    end

    LastStates[key] = state
    LastSignatures[key] = signature
    ActiveKeys[key] = true
    return true, true
end

local function processRemovals(currentKeys, passNumber)
    local removed = 0
    local oldKeys = {}
    for key in pairs(ActiveKeys) do
        oldKeys[#oldKeys + 1] = key
    end

    for _, key in ipairs(oldKeys) do
        if not currentKeys[key] then
            local previous = LastStates[key]
            if previous then
                local okAdd, result = addRecord({
                    recordType = "insight_removed",
                    profile = CONFIG.PROFILE_NAME,
                    observedAt = os.time(),
                    pass = passNumber,
                    category = previous.category,
                    path = previous.path,
                    className = previous.className,
                    lastState = {
                        attributes = previous.attributes,
                        value = previous.value,
                        properties = previous.properties,
                        relations = previous.relations,
                    },
                })

                if not okAdd then
                    return false, result, removed
                end
                removed += 1
            end

            ActiveKeys[key] = nil
            LastStates[key] = nil
            LastSignatures[key] = nil
        end
    end

    return true, nil, removed
end

--==============================================================--
-- UI
--==============================================================--
local old = PlayerGui:FindFirstChild("CafeinaInsightScan")
if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaInsightScan"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(390, 116)
Main.Position = UDim2.new(0.5, -195, 0.14, 0)
Main.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(55, 55, 60)
Stroke.Thickness = 1
Stroke.Parent = Main

local function makeButton(text, x, width)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(width, 34)
    b.Position = UDim2.fromOffset(x, 8)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    b.TextColor3 = Color3.fromRGB(245, 245, 245)
    b.Text = text
    b.TextSize = 10
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = Main

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b
    return b
end

local ScanButton = makeButton("SCAN V3", 8, 100)
local StopButton = makeButton("INTERROMPER", 116, 116)
local SendButton = makeButton("ENVIAR AO SITE", 240, 142)

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -16, 0, 21)
StatusText.Position = UDim2.fromOffset(8, 47)
StatusText.BackgroundTransparency = 1
StatusText.TextColor3 = Color3.fromRGB(175, 175, 185)
StatusText.Text = "Pronto • V3 baseline + delta"
StatusText.TextSize = 9
StatusText.Font = Enum.Font.Gotham
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextTruncate = Enum.TextTruncate.AtEnd
StatusText.Parent = Main

local ProgressBG = Instance.new("Frame")
ProgressBG.Size = UDim2.new(1, -16, 0, 12)
ProgressBG.Position = UDim2.fromOffset(8, 78)
ProgressBG.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
ProgressBG.BorderSizePixel = 0
ProgressBG.Parent = Main

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(1, 0)
pc.Parent = ProgressBG

local Progress = Instance.new("Frame")
Progress.Size = UDim2.new(0, 0, 1, 0)
Progress.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
Progress.BorderSizePixel = 0
Progress.Parent = ProgressBG

local pfc = Instance.new("UICorner")
pfc.CornerRadius = UDim.new(1, 0)
pfc.Parent = Progress

local PercentText = Instance.new("TextLabel")
PercentText.Size = UDim2.new(1, -16, 0, 13)
PercentText.Position = UDim2.fromOffset(8, 96)
PercentText.BackgroundTransparency = 1
PercentText.TextColor3 = Color3.fromRGB(110, 110, 120)
PercentText.Text = "0%"
PercentText.TextSize = 8
PercentText.Font = Enum.Font.Gotham
PercentText.TextXAlignment = Enum.TextXAlignment.Right
PercentText.Parent = Main

local function setProgress(text, fraction)
    fraction = math.clamp(tonumber(fraction) or 0, 0, 1)
    StatusText.Text = tostring(text or "")
    Progress.Size = UDim2.new(fraction, 0, 1, 0)
    PercentText.Text = tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function setSendEnabled(enabled)
    SendButton.Active = enabled
    SendButton.AutoButtonColor = enabled
    if enabled then
        SendButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
        SendButton.TextColor3 = Color3.fromRGB(20, 20, 22)
    else
        SendButton.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
        SendButton.TextColor3 = Color3.fromRGB(90, 90, 98)
    end
end

local function setStopEnabled(enabled)
    StopButton.Active = enabled
    StopButton.AutoButtonColor = enabled
    if enabled then
        StopButton.BackgroundColor3 = Color3.fromRGB(180, 35, 43)
        StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        StopButton.BackgroundColor3 = Color3.fromRGB(70, 24, 28)
        StopButton.TextColor3 = Color3.fromRGB(130, 85, 88)
    end
end

setSendEnabled(false)
setStopEnabled(false)

-- Drag mobile/desktop.
local dragging = false
local dragStart
local startPos

Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement
    then
        return
    end

    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = false
    end
end)

--==============================================================--
-- RESET / FINALIZAÇÃO
--==============================================================--
local function resetScan()
    CancelGeneration += 1
    ScanRunning = false
    ScanComplete = false
    UploadRunning = false
    WasInterrupted = false

    TotalRecordedBytes = 0
    TotalRecords = 0
    TotalPasses = 0
    StablePasses = 0

    CurrentChunk = {}
    CurrentChunkBytes = 2
    StoredChunks = {}
    MemoryChunks = {}

    CategoryCounts = {}
    RecordTypeCounts = {}
    LastPassCounts = {}

    LastStates = {}
    LastSignatures = {}
    ActiveKeys = {}

    SessionFolder = "CafeinaInsight_" .. tostring(os.time())

    setSendEnabled(false)
    setStopEnabled(false)
    addHeader()
end

local function finishScan(reason)
    local ok, err = flushChunk()

    ScanRunning = false
    setStopEnabled(false)

    if not ok then
        ScanComplete = false
        setSendEnabled(false)
        ScanButton.Text = "SCAN V3"
        ScanButton.Active = true
        setProgress("Erro ao fechar Scan: " .. tostring(err), 0)
        return
    end

    if TotalRecords <= 1 then
        ScanComplete = false
        setSendEnabled(false)
        ScanButton.Text = "SCAN V3"
        ScanButton.Active = true
        setProgress("Scan terminou sem registros úteis", 0)
        return
    end

    ScanComplete = true
    setSendEnabled(true)
    ScanButton.Text = "NOVO SCAN"
    ScanButton.Active = true

    local reasonText = "concluído"
    if reason == "LIMIT_REACHED" then
        reasonText = "limite atingido"
    elseif reason == "STABLE" then
        reasonText = "estabilizado"
    elseif reason == "INTERRUPTED" then
        reasonText = "interrompido"
    elseif reason == "MAX_PASSES" then
        reasonText = "máx. passes"
    end

    setProgress(
        "Scan " .. reasonText
        .. " • " .. tostring(TotalRecords) .. " registros"
        .. " • " .. readableSize(TotalRecordedBytes),
        1
    )
end

local function interruptScan()
    if not ScanRunning or UploadRunning then
        return
    end

    WasInterrupted = true
    CancelGeneration += 1
    ScanRunning = false
    StopButton.Active = false
    ScanButton.Active = false

    setProgress(
        "Interrompendo e fechando conteúdo coletado...",
        math.min(TotalPasses / CONFIG.MAX_PASSES, 0.95)
    )

    finishScan("INTERRUPTED")
end

--==============================================================--
-- SCAN CONTÍNUO V3
--==============================================================--
local function runInsightScan()
    if ScanRunning or UploadRunning then
        return
    end

    resetScan()
    ScanRunning = true
    ScanButton.Text = "COLETANDO..."
    ScanButton.Active = false
    setStopEnabled(true)

    local generation = CancelGeneration

    task.spawn(function()
        while generation == CancelGeneration and ScanRunning do
            TotalPasses += 1
            local passNumber = TotalPasses
            local objects = enumerateRelevantObjects()
            local total = math.max(#objects, 1)
            local changedThisPass = 0
            local currentKeys = {}

            LastPassCounts = {}

            for i, item in ipairs(objects) do
                if generation ~= CancelGeneration or not ScanRunning then
                    return
                end

                local inst = item.instance
                if inst and inst.Parent then
                    local okProcess, okOrErr, changed = pcall(
                        processState,
                        inst,
                        item.category,
                        item.priority,
                        passNumber,
                        currentKeys
                    )

                    if not okProcess then
                        -- Um objeto ruim não derruba o Scan inteiro.
                    elseif not okOrErr then
                        if changed == "LIMIT_REACHED" then
                            finishScan("LIMIT_REACHED")
                            return
                        end
                        ScanRunning = false
                        ScanComplete = false
                        setStopEnabled(false)
                        setSendEnabled(false)
                        ScanButton.Text = "SCAN V3"
                        ScanButton.Active = true
                        setProgress("Erro: " .. tostring(changed), 0)
                        return
                    elseif changed then
                        changedThisPass += 1
                    end
                end

                if i % CONFIG.YIELD_EVERY == 0 then
                    local passProgress = i / total
                    local scanProgress = math.min(passNumber / CONFIG.MAX_PASSES, 0.95)
                    local visual = math.max(scanProgress, passProgress * 0.72)

                    setProgress(
                        "Pass " .. tostring(passNumber)
                        .. " • " .. tostring(i) .. "/" .. tostring(#objects)
                        .. " • " .. tostring(changedThisPass) .. " deltas"
                        .. " • " .. readableSize(TotalRecordedBytes),
                        visual
                    )
                    task.wait()
                end
            end

            local okRemove, removeErr, removed = processRemovals(currentKeys, passNumber)
            if not okRemove then
                if removeErr == "LIMIT_REACHED" then
                    finishScan("LIMIT_REACHED")
                    return
                end
            else
                changedThisPass += removed or 0
            end

            if passNumber == 1 then
                StablePasses = 0
            elseif changedThisPass == 0 then
                StablePasses += 1
            else
                StablePasses = 0
            end

            if StablePasses >= CONFIG.STABLE_PASSES_REQUIRED then
                finishScan("STABLE")
                return
            end

            if TotalPasses >= CONFIG.MAX_PASSES then
                finishScan("MAX_PASSES")
                return
            end

            setProgress(
                "Pass " .. tostring(passNumber)
                .. " • " .. tostring(#objects) .. " úteis"
                .. " • " .. tostring(changedThisPass) .. " mudanças"
                .. " • estável " .. tostring(StablePasses)
                .. "/" .. tostring(CONFIG.STABLE_PASSES_REQUIRED),
                math.min(passNumber / CONFIG.MAX_PASSES, 0.95)
            )

            task.wait(CONFIG.PASS_INTERVAL)
        end
    end)
end

--==============================================================--
-- UPLOAD
--==============================================================--
local function doRequest(method, path, body)
    if type(requestFn) ~= "function" then
        return false, "request/http_request não disponível"
    end

    local payload = HttpService:JSONEncode(body or {})
    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.UPLOAD_RETRIES do
        local ok, response = pcall(requestFn, {
            Url = CONFIG.API_BASE .. path,
            Method = method,
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload,
        })

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or 0) or 0
            local bodyText = tostring(response.Body or "")
            local decoded = nil

            pcall(function()
                decoded = HttpService:JSONDecode(bodyText)
            end)

            if status >= 200 and status < 300 then
                return true, decoded or bodyText
            end

            lastError =
                (type(decoded) == "table" and (decoded.message or decoded.error))
                or ("HTTP " .. tostring(status) .. " • " .. bodyText:sub(1, 300))
        else
            lastError = tostring(response)
        end

        if attempt < CONFIG.UPLOAD_RETRIES then
            task.wait(CONFIG.RETRY_DELAY * attempt)
        end
    end

    return false, lastError
end

local function loadChunk(index)
    local path = StoredChunks[index]
    if path then
        local ok, text = pcall(readfileFn, path)
        if not ok then
            return nil, "Não foi possível ler " .. tostring(path)
        end

        local okDecode, objects = pcall(function()
            return HttpService:JSONDecode(text)
        end)

        if not okDecode or type(objects) ~= "table" then
            return nil, "Chunk local inválido"
        end

        return objects
    end

    local memoryIndex = index - #StoredChunks
    local item = MemoryChunks[memoryIndex]
    if item then
        return item.objects
    end

    return nil, "Chunk não encontrado"
end

local function cleanupLocalChunks()
    if type(delfileFn) ~= "function" then
        return
    end

    for _, path in ipairs(StoredChunks) do
        pcall(function()
            if type(isfileFn) ~= "function" or isfileFn(path) then
                delfileFn(path)
            end
        end)
    end
end

local function uploadCompletedScan()
    if not ScanComplete or ScanRunning or UploadRunning then
        return
    end

    UploadRunning = true
    setSendEnabled(false)
    setStopEnabled(false)
    ScanButton.Active = false

    task.spawn(function()
        local timestamp = os.date("!%Y%m%d_%H%M%S")

        local okStart, startResult = doRequest(
            "POST",
            "/upload/start",
            {
                token = CONFIG.UPLOAD_TOKEN,
                filename =
                    "Cafeina_InsightV3_"
                    .. tostring(game.PlaceId)
                    .. "_"
                    .. timestamp
                    .. ".json",
                source = CONFIG.SOURCE,
                metadata = {
                    profile = CONFIG.PROFILE_NAME,
                    version = CONFIG.VERSION,
                    placeId = game.PlaceId,
                    gameId = game.GameId,
                    jobId = game.JobId,
                    passes = TotalPasses,
                    records = TotalRecords,
                    approximateBytes = TotalRecordedBytes,
                    interrupted = WasInterrupted,
                    categories = CategoryCounts,
                    recordTypes = RecordTypeCounts,
                    clientVisibleOnly = true,
                    passiveOnly = true,
                    remoteInvocation = false,
                    deltaMode = true,
                },
            }
        )

        if not okStart or type(startResult) ~= "table" or not startResult.uploadId then
            UploadRunning = false
            ScanButton.Active = true
            setSendEnabled(true)
            setProgress("Falha ao iniciar envio: " .. tostring(startResult), 0)
            return
        end

        local uploadId = tostring(startResult.uploadId)
        local totalChunks = #StoredChunks + #MemoryChunks

        if totalChunks < 1 then
            UploadRunning = false
            ScanButton.Active = true
            setSendEnabled(true)
            setProgress("Nenhum bloco para enviar", 0)
            return
        end

        for index = 1, totalChunks do
            local objects, loadErr = loadChunk(index)
            if not objects then
                UploadRunning = false
                ScanButton.Active = true
                setSendEnabled(true)
                setProgress("Falha: " .. tostring(loadErr), (index - 1) / totalChunks)
                return
            end

            setProgress(
                "Enviando • parte " .. tostring(index) .. "/" .. tostring(totalChunks),
                (index - 1) / totalChunks
            )

            local okChunk, chunkResult = doRequest(
                "POST",
                "/upload/chunk",
                {
                    token = CONFIG.UPLOAD_TOKEN,
                    uploadId = uploadId,
                    index = index,
                    objects = objects,
                }
            )

            if not okChunk then
                UploadRunning = false
                ScanButton.Active = true
                setSendEnabled(true)
                setProgress(
                    "Falha na parte " .. tostring(index) .. ": " .. tostring(chunkResult),
                    (index - 1) / totalChunks
                )
                return
            end

            task.wait()
        end

        setProgress("Finalizando arquivo no site...", 0.98)

        local okFinish, finishResult = doRequest(
            "POST",
            "/upload/finish",
            {
                token = CONFIG.UPLOAD_TOKEN,
                uploadId = uploadId,
                totalChunks = totalChunks,
                summary = {
                    profile = CONFIG.PROFILE_NAME,
                    version = CONFIG.VERSION,
                    objectCount = TotalRecords,
                    approximateBytes = TotalRecordedBytes,
                    passes = TotalPasses,
                    categories = CategoryCounts,
                    recordTypes = RecordTypeCounts,
                    scanComplete = true,
                    interrupted = WasInterrupted,
                    deltaMode = true,
                },
            }
        )

        UploadRunning = false
        ScanButton.Active = true

        if not okFinish then
            setSendEnabled(true)
            setProgress("Falha ao finalizar: " .. tostring(finishResult), 0.98)
            return
        end

        cleanupLocalChunks()

        local link = ""
        if type(finishResult) == "table" then
            link = tostring(
                finishResult.url
                or finishResult.downloadUrl
                or finishResult.download_url
                or finishResult.link
                or ""
            )
        end

        if link ~= "" and type(setclipboard) == "function" then
            pcall(setclipboard, link)
        end

        setProgress(
            link ~= "" and "Envio concluído • link copiado" or "Envio concluído",
            1
        )
    end)
end

--==============================================================--
-- BOTÕES
--==============================================================--
ScanButton.Activated:Connect(function()
    if UploadRunning or ScanRunning then
        return
    end
    runInsightScan()
end)

StopButton.Activated:Connect(interruptScan)
SendButton.Activated:Connect(uploadCompletedScan)
