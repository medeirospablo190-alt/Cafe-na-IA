--[[
    CAFEÍNA • SMART SCANNER V4.2
    Foco: novas informações úteis, menos repetição, menu compacto e status visível.

    Botões:
      1) INICIAR SCAN
      2) INTERROMPER
      3) ENVIAR

    Observações:
      - Somente leitura do que é visível ao cliente.
      - Não executa RemoteEvents/RemoteFunctions.
      - Não altera objetos do jogo.
      - O envio HTTP é opcional; configure CONFIG.UploadURL.
]]

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    ScanInterval = 0.35,
    RescanInterval = 8.0,
    EventBatchSize = 220,
    InitialYieldEvery = 350,
    GuiEventCooldown = 1.0,
    MaxEventQueue = 12000,
    MaxRecords = 120000,
    MaxBytesApprox = 150 * 1024 * 1024,

    -- Prioridades
    TrackRemotes = true,
    TrackSoldiers = true,
    TrackTools = true,
    TrackTycoon = true,
    TrackPlayerData = true,
    TrackBlaster = true,
    TrackInteractions = true,
    TrackInterestingAttributes = true,
    TrackRemoteStructure = true,
    TrackScriptsMetadata = true,
    TrackRelevantGui = true,

    -- Mantém o scan útil sem voltar a despejar geometria estática.
    HighValuePathTokens = {
        "__remotes", "tycoonservice", "playerdataservice", "loadoutservice",
        "teamservice", "leaderboardservice", "tacticalairstrikeservice",
        "soldiers", "tycoon", "purchases", "collector", "money", "cash",
        "weapon", "gun", "loadout", "rebirth", "button", "projectile"
    },

    -- Evita entulho visual
    IgnoreDecorative = true,
    IgnoreClasses = {
        ["ParticleEmitter"] = true,
        ["Trail"] = true,
        ["Beam"] = true,
        ["Texture"] = true,
        ["Decal"] = true,
        ["SurfaceAppearance"] = true,
        ["SpecialMesh"] = true,
        ["MeshPart"] = false, -- ainda pode ser útil quando é Tool/arma
    },

    -- nomes que indicam informação útil
    InterestingNames = {
        "damage","health","maxhealth","ammo","mag","magazine","reload","firerate",
        "fire","spread","recoil","range","speed","walkspeed","money","cash","kills",
        "rebirth","team","weapon","gun","tool","soldier","npc","aggro","target",
        "cooldown","cost","price","purchase","collect","button","tycoon","blaster",
        "bullet","projectile","hit","headshot","armor","armour","loadout","spawn"
    },

    -- envio opcional
    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    UPLOAD_TOKEN = "",
    UploadChunkBytes = 3000000,
    UploadRetries = 3,
    UploadRetryDelay = 1.25,
}

--==============================================================
-- STATE
--==============================================================

local STATE = {
    Running = false,
    StopRequested = false,
    Sending = false,

    Pass = 0,
    StartedAt = 0,
    FinishedAt = 0,

    Records = {},
    Seen = {},
    LastSnapshot = {},
    LastData = {},

    EventQueue = {},
    EventHead = 1,
    PendingEvents = {},
    Connections = {},
    Watched = setmetatable({}, {__mode = "k"}),
    ObjectKeys = setmetatable({}, {__mode = "k"}),
    ObjectCategories = setmetatable({}, {__mode = "k"}),
    LastGuiEvent = {},
    LastRescanAt = 0,

    Added = 0,
    Changed = 0,
    Removed = 0,
    NewUseful = 0,

    PassAdded = 0,
    PassChanged = 0,
    PassRemoved = 0,

    CategoryCount = {},
    ApproxBytes = 0,

    LastStatus = "Pronto",
    LastDetail = "Aguardando início",
}

--==============================================================
-- HELPERS
--==============================================================

local function now()
    return os.clock()
end

local function safeFullName(obj)
    local ok, value = pcall(function()
        return obj:GetFullName()
    end)
    return ok and value or tostring(obj)
end

local function safeAttributes(obj)
    local ok, attrs = pcall(function()
        return obj:GetAttributes()
    end)
    return ok and attrs or {}
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function containsInterestingName(name)
    local n = lower(name)
    for _, token in ipairs(CONFIG.InterestingNames) do
        if string.find(n, token, 1, true) then
            return true
        end
    end
    return false
end

local function containsHighValuePath(path)
    local p = lower(path)
    for _, token in ipairs(CONFIG.HighValuePathTokens) do
        if string.find(p, token, 1, true) then
            return true
        end
    end
    return false
end

local function clippedText(value, maxLen)
    local s = tostring(value or "")
    maxLen = maxLen or 240
    if #s > maxLen then
        return string.sub(s, 1, maxLen) .. "…"
    end
    return s
end

local function isDecorative(obj)
    if not CONFIG.IgnoreDecorative then
        return false
    end

    if CONFIG.IgnoreClasses[obj.ClassName] then
        return true
    end

    local n = lower(obj.Name)
    if n == "mesh" or n == "accessoryweld" or n == "originalposition" or n == "originalsize" then
        return true
    end

    return false
end

local function approxLen(value)
    local ok, s = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    if ok then
        return #s
    end
    return 64
end

local function primitiveValue(v)
    local t = typeof(v)

    if t == "string" or t == "number" or t == "boolean" then
        return v
    elseif t == "Vector3" then
        return {x=v.X, y=v.Y, z=v.Z}
    elseif t == "Vector2" then
        return {x=v.X, y=v.Y}
    elseif t == "Color3" then
        return {r=v.R, g=v.G, b=v.B}
    elseif t == "CFrame" then
        local p = v.Position
        return {x=p.X, y=p.Y, z=p.Z}
    elseif t == "EnumItem" then
        return tostring(v)
    end

    return tostring(v)
end

local function sameEncoded(a, b)
    if a == b then return true end
    local oka, ea = pcall(function() return HttpService:JSONEncode(a) end)
    local okb, eb = pcall(function() return HttpService:JSONEncode(b) end)
    return oka and okb and ea == eb
end

local function makeDelta(oldData, newData)
    if type(oldData) ~= "table" then
        return newData
    end

    local changes = {}
    for k, v in pairs(newData) do
        if k ~= "path" and k ~= "class" and k ~= "name" then
            local old = oldData[k]
            if not sameEncoded(old, v) then
                changes[k] = {from = old, to = v}
            end
        end
    end
    for k, v in pairs(oldData) do
        if k ~= "path" and k ~= "class" and k ~= "name" and newData[k] == nil then
            changes[k] = {from = v, to = nil}
        end
    end

    return {
        class = newData.class,
        name = newData.name,
        path = newData.path,
        changes = changes,
    }
end

local watchObject

local function recordKey(category, obj, suffix)
    return category .. "|" .. safeFullName(obj) .. "|" .. tostring(suffix or "")
end

local function addRecord(category, kind, key, data)
    local rec = {
        t = os.time(),
        pass = STATE.Pass,
        category = category,
        kind = kind,
        key = key,
        data = data,
    }

    local bytes = approxLen(rec)
    if STATE.ApproxBytes + bytes > CONFIG.MaxBytesApprox then
        return false
    end

    table.insert(STATE.Records, rec)
    STATE.ApproxBytes += bytes
    STATE.CategoryCount[category] = (STATE.CategoryCount[category] or 0) + 1

    if kind == "baseline" then
        STATE.Added += 1
        STATE.PassAdded += 1
    elseif kind == "changed" then
        STATE.Changed += 1
        STATE.PassChanged += 1
    elseif kind == "removed" then
        STATE.Removed += 1
        STATE.PassRemoved += 1
    end

    return true
end

local function snapshotValue(obj)
    local data = {
        class = obj.ClassName,
        name = obj.Name,
        path = safeFullName(obj),
    }

    if obj:IsA("ValueBase") then
        local ok, value = pcall(function()
            return obj.Value
        end)
        if ok then
            data.value = primitiveValue(value)
        end
    end

    if obj:IsA("Humanoid") then
        data.health = obj.Health
        data.maxHealth = obj.MaxHealth
        data.walkSpeed = obj.WalkSpeed
        data.jumpPower = obj.JumpPower
    end

    if obj:IsA("Tool") then
        data.toolTip = obj.ToolTip
        data.canBeDropped = obj.CanBeDropped
        local handle = obj:FindFirstChild("Handle")
        data.hasHandle = handle ~= nil
    end

    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        data.remoteType = obj.ClassName
        data.parentPath = obj.Parent and safeFullName(obj.Parent) or nil
    end

    if obj:IsA("ProximityPrompt") then
        data.actionText = clippedText(obj.ActionText, 120)
        data.objectText = clippedText(obj.ObjectText, 120)
        data.holdDuration = obj.HoldDuration
        data.maxActivationDistance = obj.MaxActivationDistance
        data.enabled = obj.Enabled
    end

    if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
        data.scriptClass = obj.ClassName
        if obj:IsA("LocalScript") or obj:IsA("Script") then
            local okDisabled, disabled = pcall(function() return obj.Disabled end)
            if okDisabled then data.disabled = disabled end
        end
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        data.text = clippedText(obj.Text, 240)
        data.visible = obj.Visible
    elseif obj:IsA("GuiObject") then
        data.visible = obj.Visible
    end

    local attrs = safeAttributes(obj)
    if next(attrs) then
        data.attributes = {}
        for k, v in pairs(attrs) do
            if containsInterestingName(k) or not CONFIG.TrackInterestingAttributes then
                data.attributes[k] = primitiveValue(v)
            end
        end
        if not next(data.attributes) then
            data.attributes = nil
        end
    end

    return data
end

local function fingerprint(data)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    return ok and encoded or tostring(data)
end

local function rememberObjectKey(obj, category, key)
    local keys = STATE.ObjectKeys[obj]
    if not keys then
        keys = {}
        STATE.ObjectKeys[obj] = keys
    end
    keys[key] = true

    local categories = STATE.ObjectCategories[obj]
    if not categories then
        categories = {}
        STATE.ObjectCategories[obj] = categories
    end
    categories[category] = true
end

local function consider(category, obj, forceUseful)
    if not obj or not obj.Parent then
        return
    end
    if isDecorative(obj) and not forceUseful then
        return
    end

    local key = recordKey(category, obj)
    local data = snapshotValue(obj)
    local fp = fingerprint(data)
    local oldFp = STATE.LastSnapshot[key]
    local oldData = STATE.LastData[key]

    STATE.Seen[key] = true
    rememberObjectKey(obj, category, key)

    if oldFp == nil then
        if addRecord(category, "baseline", key, data) then
            STATE.NewUseful += 1
        end
        STATE.LastSnapshot[key] = fp
        STATE.LastData[key] = data
    elseif oldFp ~= fp then
        local delta = makeDelta(oldData, data)
        if addRecord(category, "changed", key, delta) then
            STATE.NewUseful += 1
        end
        STATE.LastSnapshot[key] = fp
        STATE.LastData[key] = data
    end

    if watchObject then
        watchObject(category, obj, forceUseful)
    end
end

local function scanDescendants(root, category, predicate)
    if not root then return end

    local n = 0
    for _, obj in ipairs(root:GetDescendants()) do
        if STATE.StopRequested then break end
        local ok = true
        if predicate then
            local predOk, predValue = pcall(predicate, obj)
            ok = predOk and predValue
        end
        if ok then
            consider(category, obj, false)
        end

        n += 1
        if n % CONFIG.InitialYieldEvery == 0 then
            task.wait()
        end
    end
end

--==============================================================
-- SMART SCANNERS
--==============================================================

local function scanRemotes()
    if not CONFIG.TrackRemotes then return end

    local roots = {ReplicatedStorage, ReplicatedFirst}
    for _, root in ipairs(roots) do
        scanDescendants(root, "Remotes", function(obj)
            return obj:IsA("RemoteEvent")
                or obj:IsA("RemoteFunction")
                or obj:IsA("BindableEvent")
                or obj:IsA("BindableFunction")
        end)
    end
end

local function scanRemoteStructure()
    if not CONFIG.TrackRemoteStructure then return end

    local remotesRoot = ReplicatedStorage:FindFirstChild("__remotes", true)
    if not remotesRoot then return end

    consider("RemoteStructure", remotesRoot, true)

    for _, serviceFolder in ipairs(remotesRoot:GetChildren()) do
        if STATE.StopRequested then break end
        consider("RemoteStructure", serviceFolder, true)

        for _, obj in ipairs(serviceFolder:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")
                or obj:IsA("BindableEvent") or obj:IsA("BindableFunction") then
                consider("RemoteStructure", obj, true)
            end
        end
    end
end

local function scanScriptsMetadata()
    if not CONFIG.TrackScriptsMetadata then return end

    local roots = {ReplicatedStorage, ReplicatedFirst, StarterPlayer}
    for _, root in ipairs(roots) do
        scanDescendants(root, "Scripts", function(obj)
            if not (obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script")) then
                return false
            end

            local path = safeFullName(obj)
            return containsHighValuePath(path) or containsInterestingName(obj.Name)
        end)
    end
end

local function scanRelevantGui()
    if not CONFIG.TrackRelevantGui then return end

    local roots = {PlayerGui, StarterGui}
    for _, root in ipairs(roots) do
        scanDescendants(root, "GUI", function(obj)
            if not obj:IsA("GuiObject") then return false end

            local path = safeFullName(obj)
            if containsHighValuePath(path) or containsInterestingName(obj.Name) then
                return true
            end

            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local text = lower(obj.Text)
                return containsInterestingName(text)
            end

            return false
        end)
    end
end

local function scanBlaster()
    if not CONFIG.TrackBlaster then return end

    scanDescendants(ReplicatedStorage, "BlasterSystem", function(obj)
        local p = lower(safeFullName(obj))
        return string.find(p, "blaster", 1, true)
            or string.find(p, "bullet", 1, true)
            or string.find(p, "projectile", 1, true)
            or containsInterestingName(obj.Name)
    end)
end

local function scanTools()
    if not CONFIG.TrackTools then return end

    local roots = {Workspace, ReplicatedStorage}
    if LocalPlayer:FindFirstChild("Backpack") then
        table.insert(roots, LocalPlayer.Backpack)
    end

    for _, root in ipairs(roots) do
        scanDescendants(root, "Tools", function(obj)
            if obj:IsA("Tool") then
                return true
            end
            local parent = obj.Parent
            if parent and parent:IsA("Tool") then
                return containsInterestingName(obj.Name)
                    or obj:IsA("ValueBase")
                    or obj:IsA("ModuleScript")
                    or obj:IsA("LocalScript")
            end
            return false
        end)
    end
end

local function scanSoldiers()
    if not CONFIG.TrackSoldiers then return end

    local soldiers = Workspace:FindFirstChild("Soldiers")
    if soldiers then
        for _, model in ipairs(soldiers:GetChildren()) do
            if STATE.StopRequested then break end
            if model:IsA("Model") then
                consider("Soldiers", model, true)

                for _, obj in ipairs(model:GetDescendants()) do
                    if obj:IsA("Humanoid")
                        or obj:IsA("Tool")
                        or obj:IsA("ValueBase")
                        or obj.Name == "HumanoidRootPart"
                        or containsInterestingName(obj.Name) then
                        consider("Soldiers", obj, true)
                    end
                end
            end
        end
    else
        -- fallback inteligente
        scanDescendants(Workspace, "Soldiers", function(obj)
            if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
                local p = obj.Parent
                return containsInterestingName(p.Name)
                    or p:FindFirstChildOfClass("Tool") ~= nil
            end
            return false
        end)
    end
end

local function scanPlayerData()
    if not CONFIG.TrackPlayerData then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if STATE.StopRequested then break end

        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, obj in ipairs(ls:GetDescendants()) do
                if obj:IsA("ValueBase") then
                    consider("PlayerData", obj, true)
                end
            end
        end

        for _, child in ipairs(plr:GetChildren()) do
            if child ~= plr.Character and (
                child:IsA("Folder")
                or child:IsA("Configuration")
                or child:IsA("ValueBase")
            ) then
                if containsInterestingName(child.Name) then
                    consider("PlayerData", child, true)
                    for _, obj in ipairs(child:GetDescendants()) do
                        if obj:IsA("ValueBase") or containsInterestingName(obj.Name) then
                            consider("PlayerData", obj, true)
                        end
                    end
                end
            end
        end
    end
end

local function scanTycoon()
    if not CONFIG.TrackTycoon then return end

    scanDescendants(Workspace, "Tycoon", function(obj)
        local p = lower(safeFullName(obj))
        if not containsHighValuePath(p) then
            return false
        end

        if obj:IsA("ValueBase")
            or obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")
            or obj:IsA("TouchTransmitter")
            or obj:IsA("Tool")
            or containsInterestingName(obj.Name) then
            return true
        end

        return false
    end)
end

local function scanInteractions()
    if not CONFIG.TrackInteractions then return end

    scanDescendants(Workspace, "Interactions", function(obj)
        return obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")
            or obj:IsA("TouchTransmitter")
    end)
end

local function disconnectWatchers()
    for _, conn in ipairs(STATE.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    STATE.Connections = {}
    STATE.Watched = setmetatable({}, {__mode = "k"})
    STATE.ObjectKeys = setmetatable({}, {__mode = "k"})
    STATE.ObjectCategories = setmetatable({}, {__mode = "k"})
end

local function addConnection(conn)
    if conn then
        table.insert(STATE.Connections, conn)
    end
end

local function enqueue(category, obj, forceUseful)
    if not STATE.Running or STATE.StopRequested or not obj or not obj.Parent then
        return
    end

    local key = recordKey(category, obj)
    if category == "GUI" then
        local t = now()
        local last = STATE.LastGuiEvent[key] or 0
        if t - last < CONFIG.GuiEventCooldown then
            return
        end
        STATE.LastGuiEvent[key] = t
    end

    if STATE.PendingEvents[key] then
        return
    end

    local queued = #STATE.EventQueue - STATE.EventHead + 1
    if queued >= CONFIG.MaxEventQueue then
        return
    end

    STATE.PendingEvents[key] = true
    table.insert(STATE.EventQueue, {
        category = category,
        obj = obj,
        forceUseful = forceUseful == true,
        key = key,
    })
end

local function enqueueKnownCategories(obj)
    local cats = STATE.ObjectCategories[obj]
    if not cats then return end
    for category, _ in pairs(cats) do
        enqueue(category, obj, true)
    end
end

watchObject = function(category, obj, forceUseful)
    if STATE.Watched[obj] then
        return
    end
    STATE.Watched[obj] = true

    local function changed()
        enqueueKnownCategories(obj)
    end

    addConnection(obj.AttributeChanged:Connect(function(attr)
        if containsInterestingName(attr) then
            changed()
        end
    end))

    addConnection(obj:GetPropertyChangedSignal("Name"):Connect(changed))

    if obj:IsA("ValueBase") then
        addConnection(obj.Changed:Connect(changed))
    elseif obj:IsA("Humanoid") then
        addConnection(obj.HealthChanged:Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("MaxHealth"):Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("WalkSpeed"):Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("JumpPower"):Connect(changed))
    elseif obj:IsA("ProximityPrompt") then
        addConnection(obj:GetPropertyChangedSignal("Enabled"):Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("HoldDuration"):Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("MaxActivationDistance"):Connect(changed))
    elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        addConnection(obj:GetPropertyChangedSignal("Text"):Connect(changed))
        addConnection(obj:GetPropertyChangedSignal("Visible"):Connect(changed))
    elseif obj:IsA("GuiObject") then
        addConnection(obj:GetPropertyChangedSignal("Visible"):Connect(changed))
    end
end

local function isUnder(root, obj)
    local ok, result = pcall(function()
        return obj:IsDescendantOf(root)
    end)
    return ok and result
end

local function routeDynamic(obj)
    if not obj or not obj.Parent then return end

    local path = safeFullName(obj)
    local lp = lower(path)
    local interesting = containsInterestingName(obj.Name)
    local highPath = containsHighValuePath(path)

    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")
        or obj:IsA("BindableEvent") or obj:IsA("BindableFunction") then
        consider("Remotes", obj, true)
        if string.find(lp, "__remotes", 1, true) then
            consider("RemoteStructure", obj, true)
        end
    end

    if CONFIG.TrackScriptsMetadata and (obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script"))
        and (highPath or interesting) then
        consider("Scripts", obj, true)
    end

    if CONFIG.TrackRelevantGui and obj:IsA("GuiObject") then
        local guiUseful = highPath or interesting
        if not guiUseful and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
            guiUseful = containsInterestingName(obj.Text)
        end
        if guiUseful then
            consider("GUI", obj, true)
        end
    end

    if CONFIG.TrackBlaster and (
        string.find(lp, "blaster", 1, true)
        or string.find(lp, "bullet", 1, true)
        or string.find(lp, "projectile", 1, true)
    ) then
        consider("BlasterSystem", obj, true)
    end

    if CONFIG.TrackTools then
        local tool = obj:IsA("Tool") and obj or obj:FindFirstAncestorOfClass("Tool")
        if tool and (obj == tool or obj:IsA("ValueBase") or interesting or obj:IsA("ModuleScript") or obj:IsA("LocalScript")) then
            consider("Tools", obj, true)
        end
    end

    if CONFIG.TrackSoldiers and string.find(lp, ".soldiers", 1, true) then
        if obj:IsA("Model") or obj:IsA("Humanoid") or obj:IsA("Tool") or obj:IsA("ValueBase")
            or obj.Name == "HumanoidRootPart" or interesting then
            consider("Soldiers", obj, true)
        end
    end

    if CONFIG.TrackTycoon and highPath and isUnder(Workspace, obj) then
        if obj:IsA("ValueBase") or obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")
            or obj:IsA("TouchTransmitter") or obj:IsA("Tool") or interesting then
            consider("Tycoon", obj, true)
        end
    end

    if CONFIG.TrackInteractions and isUnder(Workspace, obj)
        and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") or obj:IsA("TouchTransmitter")) then
        consider("Interactions", obj, true)
    end

    if CONFIG.TrackPlayerData and isUnder(Players, obj) and (obj:IsA("ValueBase") or interesting) then
        local characterOwned = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character and isUnder(plr.Character, obj) then
                characterOwned = true
                break
            end
        end
        if not characterOwned then
            consider("PlayerData", obj, true)
        end
    end
end

local function handleRemoved(obj)
    local keys = STATE.ObjectKeys[obj]
    if not keys then return end

    local removedKeys = {}
    for key, _ in pairs(keys) do
        table.insert(removedKeys, key)
        STATE.LastSnapshot[key] = nil
        STATE.LastData[key] = nil
        STATE.PendingEvents[key] = nil
    end

    if #removedKeys > 0 then
        addRecord("Lifecycle", "removed", "removed|" .. safeFullName(obj), {
            class = obj.ClassName,
            name = obj.Name,
            keys = removedKeys,
        })
    end

    STATE.ObjectKeys[obj] = nil
    STATE.ObjectCategories[obj] = nil
end

local function connectRoot(root)
    if not root then return end

    addConnection(root.DescendantAdded:Connect(function(obj)
        task.defer(function()
            if STATE.Running and not STATE.StopRequested and obj.Parent then
                routeDynamic(obj)
            end
        end)
    end))

    addConnection(root.DescendantRemoving:Connect(function(obj)
        if STATE.Running and not STATE.StopRequested then
            handleRemoved(obj)
        end
    end))
end

local function connectEventRoots()
    connectRoot(Workspace)
    connectRoot(ReplicatedStorage)
    connectRoot(ReplicatedFirst)
    connectRoot(PlayerGui)
    connectRoot(StarterGui)
    connectRoot(StarterPlayer)
    connectRoot(LocalPlayer)
end

local function processEventQueue()
    local processed = 0
    while processed < CONFIG.EventBatchSize and STATE.EventHead <= #STATE.EventQueue do
        if STATE.StopRequested then break end

        local item = STATE.EventQueue[STATE.EventHead]
        STATE.EventHead += 1
        STATE.PendingEvents[item.key] = nil

        if item.obj and item.obj.Parent then
            consider(item.category, item.obj, item.forceUseful)
        end
        processed += 1
    end

    if STATE.EventHead > #STATE.EventQueue then
        STATE.EventQueue = {}
        STATE.EventHead = 1
    elseif STATE.EventHead > 2000 then
        local compact = {}
        for i = STATE.EventHead, #STATE.EventQueue do
            compact[#compact + 1] = STATE.EventQueue[i]
        end
        STATE.EventQueue = compact
        STATE.EventHead = 1
    end

    return processed
end

--==============================================================
-- UI
--==============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaSmartScannerV42"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(330, 178)
main.Position = UDim2.new(0.5, -165, 0.08, 0)
main.BackgroundColor3 = Color3.fromRGB(15,15,18)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(55,55,62)
stroke.Thickness = 1
stroke.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 28)
title.Position = UDim2.fromOffset(10, 7)
title.BackgroundTransparency = 1
title.Text = "CAFEÍNA • SMART SCANNER V4.2"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(245,245,245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local scanSizeLabel = Instance.new("TextLabel")
scanSizeLabel.Size = UDim2.new(1, -20, 0, 34)
scanSizeLabel.Position = UDim2.fromOffset(10, 38)
scanSizeLabel.BackgroundTransparency = 1
scanSizeLabel.Text = "SCAN • 0.0 MB / 150 MB"
scanSizeLabel.Font = Enum.Font.GothamBold
scanSizeLabel.TextSize = 16
scanSizeLabel.TextColor3 = Color3.fromRGB(245,245,245)
scanSizeLabel.TextXAlignment = Enum.TextXAlignment.Left
scanSizeLabel.Parent = main

local uploadStatus = Instance.new("TextLabel")
uploadStatus.Size = UDim2.new(1, -20, 0, 22)
uploadStatus.Position = UDim2.fromOffset(10, 77)
uploadStatus.BackgroundTransparency = 1
uploadStatus.Text = "UPLOAD • aguardando"
uploadStatus.Font = Enum.Font.Gotham
uploadStatus.TextSize = 11
uploadStatus.TextColor3 = Color3.fromRGB(180,180,185)
uploadStatus.TextXAlignment = Enum.TextXAlignment.Left
uploadStatus.Parent = main

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -20, 0, 8)
barBg.Position = UDim2.fromOffset(10, 104)
barBg.BackgroundColor3 = Color3.fromRGB(40,40,46)
barBg.BorderSizePixel = 0
barBg.Parent = main
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1,0)

local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0,1)
bar.BackgroundColor3 = Color3.fromRGB(235,235,235)
bar.BorderSizePixel = 0
bar.Parent = barBg
Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

local linkLabel = Instance.new("TextLabel")
linkLabel.Size = UDim2.new(1, -20, 0, 20)
linkLabel.Position = UDim2.fromOffset(10, 116)
linkLabel.BackgroundTransparency = 1
linkLabel.Text = ""
linkLabel.Font = Enum.Font.Gotham
linkLabel.TextSize = 10
linkLabel.TextColor3 = Color3.fromRGB(150,150,155)
linkLabel.TextXAlignment = Enum.TextXAlignment.Left
linkLabel.TextTruncate = Enum.TextTruncate.AtEnd
linkLabel.Parent = main

local function makeButton(text, x, width)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(width, 30)
    b.Position = UDim2.fromOffset(x, 140)
    b.BackgroundColor3 = Color3.fromRGB(30,30,35)
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(245,245,245)
    b.AutoButtonColor = true
    b.Parent = main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local startBtn = makeButton("INICIAR", 10, 98)
local stopBtn = makeButton("INTERROMPER", 116, 98)
local sendBtn = makeButton("ENVIAR", 222, 98)

-- Minimizar/restaurar sem alterar o layout principal.
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.fromOffset(22, 22)
minimizeBtn.Position = UDim2.new(1, -30, 0, 8)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(30,30,35)
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "−"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 14
minimizeBtn.TextColor3 = Color3.fromRGB(245,245,245)
minimizeBtn.AutoButtonColor = true
minimizeBtn.Parent = main
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0,7)

local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.fromOffset(38, 38)
restoreBtn.Position = UDim2.new(0.5, -19, 0.08, 0)
restoreBtn.BackgroundColor3 = Color3.fromRGB(15,15,18)
restoreBtn.BorderSizePixel = 0
restoreBtn.Text = "C"
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 15
restoreBtn.TextColor3 = Color3.fromRGB(245,245,245)
restoreBtn.Active = true
restoreBtn.Draggable = true
restoreBtn.Visible = false
restoreBtn.Parent = gui
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(1,0)
local restoreStroke = Instance.new("UIStroke")
restoreStroke.Color = Color3.fromRGB(55,55,62)
restoreStroke.Thickness = 1
restoreStroke.Parent = restoreBtn

minimizeBtn.MouseButton1Click:Connect(function()
    restoreBtn.Position = main.Position
    main.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    main.Position = restoreBtn.Position
    restoreBtn.Visible = false
    main.Visible = true
end)

local function setUploadStatus(textValue, color)
    uploadStatus.Text = "UPLOAD • " .. tostring(textValue or "")
    if color then
        uploadStatus.TextColor3 = color
    end
end

local function setUploadProgress(value)
    bar.Size = UDim2.fromScale(math.clamp(tonumber(value) or 0, 0, 1), 1)
end

local function refreshInfo()
    local mb = STATE.ApproxBytes / 1024 / 1024
    scanSizeLabel.Text = string.format("SCAN • %.1f MB / 150 MB • P%d", mb, STATE.Pass)
end

--==============================================================
-- EXPORT
--==============================================================

local function buildExport()
    return {
        schemaVersion = 6,
        scanner = "CAFEINA SMART SCANNER V4.2 INCREMENTAL",
        generatedAt = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        clientVisibleOnly = true,

        scan = {
            complete = (not STATE.StopRequested) and STATE.ApproxBytes >= CONFIG.MaxBytesApprox,
            interrupted = STATE.StopRequested,
            passes = STATE.Pass,
            records = #STATE.Records,
            added = STATE.Added,
            changed = STATE.Changed,
            removed = STATE.Removed,
            newUseful = STATE.NewUseful,
            approxBytes = STATE.ApproxBytes,
            categories = STATE.CategoryCount,
            mode = "initial+events+light-rescan",
        },

        records = STATE.Records,
    }
end

local function resetState()
    disconnectWatchers()
    STATE.StopRequested = false
    STATE.Pass = 0
    STATE.StartedAt = now()
    STATE.FinishedAt = 0
    STATE.Records = {}
    STATE.Seen = {}
    STATE.LastSnapshot = {}
    STATE.LastData = {}
    STATE.EventQueue = {}
    STATE.EventHead = 1
    STATE.PendingEvents = {}
    STATE.Watched = setmetatable({}, {__mode = "k"})
    STATE.ObjectKeys = setmetatable({}, {__mode = "k"})
    STATE.ObjectCategories = setmetatable({}, {__mode = "k"})
    STATE.LastGuiEvent = {}
    STATE.LastRescanAt = now()
    STATE.Added = 0
    STATE.Changed = 0
    STATE.Removed = 0
    STATE.NewUseful = 0
    STATE.PassAdded = 0
    STATE.PassChanged = 0
    STATE.PassRemoved = 0
    STATE.CategoryCount = {}
    STATE.ApproxBytes = 0
end

local function initialRouteRoot(root)
    if not root then return end
    local n = 0
    for _, obj in ipairs(root:GetDescendants()) do
        if STATE.StopRequested then break end
        routeDynamic(obj)
        n += 1
        if n % CONFIG.InitialYieldEvery == 0 then
            task.wait()
        end
    end
end

local function initialScan()
    STATE.Pass += 1
    STATE.PassAdded = 0
    STATE.PassChanged = 0
    STATE.PassRemoved = 0

    -- Conecta primeiro para não perder objetos criados durante o levantamento inicial.
    connectEventRoots()

    -- V4.2: uma passagem por árvore, em vez de várias GetDescendants() sobre o Workspace.
    initialRouteRoot(Workspace)
    if STATE.StopRequested then return end
    initialRouteRoot(ReplicatedStorage)
    if STATE.StopRequested then return end
    initialRouteRoot(ReplicatedFirst)
    if STATE.StopRequested then return end
    initialRouteRoot(Players)
    if STATE.StopRequested then return end
    initialRouteRoot(StarterGui)
    if STATE.StopRequested then return end
    initialRouteRoot(StarterPlayer)

    -- Pastas de serviço dos remotes também são úteis como estrutura, mesmo sem serem remotes.
    if CONFIG.TrackRemoteStructure then
        local remotesRoot = ReplicatedStorage:FindFirstChild("__remotes", true)
        if remotesRoot then
            consider("RemoteStructure", remotesRoot, true)
            for _, serviceFolder in ipairs(remotesRoot:GetChildren()) do
                consider("RemoteStructure", serviceFolder, true)
            end
        end
    end

    addRecord("Analysis", "pass_summary", "pass|" .. tostring(STATE.Pass), {
        phase = "initial",
        pass = STATE.Pass,
        added = STATE.PassAdded,
        changed = STATE.PassChanged,
        removed = STATE.PassRemoved,
        totalRecords = #STATE.Records,
        approxBytes = STATE.ApproxBytes,
    })

    STATE.LastRescanAt = now()
    refreshInfo()
end

local function lightRescan()
    -- Rescan deliberadamente pequeno. O restante é capturado por eventos.
    scanRemoteStructure()
    if STATE.StopRequested then return end
    scanPlayerData()
    if STATE.StopRequested then return end

    local soldiers = Workspace:FindFirstChild("Soldiers")
    if soldiers then
        for _, model in ipairs(soldiers:GetChildren()) do
            if STATE.StopRequested then break end
            if model:IsA("Model") then
                consider("Soldiers", model, true)
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                if humanoid then consider("Soldiers", humanoid, true) end
                local tool = model:FindFirstChildOfClass("Tool")
                if tool then consider("Soldiers", tool, true) end
            end
        end
    end

    STATE.LastRescanAt = now()
end

local function runPass()
    STATE.Pass += 1
    STATE.PassAdded = 0
    STATE.PassChanged = 0
    STATE.PassRemoved = 0

    local processed = processEventQueue()

    if now() - STATE.LastRescanAt >= CONFIG.RescanInterval then
        lightRescan()
    end

    -- Só grava resumo quando houve informação nova; evita crescer parado.
    if STATE.PassAdded > 0 or STATE.PassChanged > 0 or STATE.PassRemoved > 0 then
        addRecord("Analysis", "pass_summary", "pass|" .. tostring(STATE.Pass), {
            phase = "events",
            pass = STATE.Pass,
            processedEvents = processed,
            added = STATE.PassAdded,
            changed = STATE.PassChanged,
            removed = STATE.PassRemoved,
            totalRecords = #STATE.Records,
            approxBytes = STATE.ApproxBytes,
        })
    end

    refreshInfo()
end

local function scannerLoop()
    if STATE.Running then
        return
    end

    resetState()
    STATE.Running = true
    setUploadProgress(0)
    setUploadStatus("aguardando")
    linkLabel.Text = ""
    refreshInfo()

    task.spawn(function()
        local okInitial, initialErr = pcall(initialScan)
        if not okInitial then
            STATE.Running = false
            disconnectWatchers()
            setUploadStatus("scanner encontrou erro: " .. tostring(initialErr), Color3.fromRGB(255,100,100))
            return
        end

        while STATE.Running and not STATE.StopRequested do
            if STATE.ApproxBytes >= CONFIG.MaxBytesApprox then
                break
            end

            local ok, err = pcall(runPass)
            if not ok then
                STATE.Running = false
                disconnectWatchers()
                setUploadStatus("scanner encontrou erro: " .. tostring(err), Color3.fromRGB(255,100,100))
                return
            end

            if STATE.StopRequested or STATE.ApproxBytes >= CONFIG.MaxBytesApprox then
                break
            end

            task.wait(CONFIG.ScanInterval)
        end

        STATE.Running = false
        STATE.FinishedAt = now()
        disconnectWatchers()
        refreshInfo()

        if STATE.ApproxBytes >= CONFIG.MaxBytesApprox then
            scanSizeLabel.Text = string.format("SCAN • 150.0 MB / 150 MB • P%d", STATE.Pass)
        end
    end)
end

--==============================================================
-- HTTP SEND
--==============================================================

local function getRequest()
    return (syn and syn.request)
        or http_request
        or request
        or (http and http.request)
end

local function getClipboard()
    if typeof(setclipboard) == "function" then
        return setclipboard
    end
    if typeof(toclipboard) == "function" then
        return toclipboard
    end
    return nil
end

local function withToken(body)
    if CONFIG.UPLOAD_TOKEN ~= "" then
        body.token = CONFIG.UPLOAD_TOKEN
    end
    return body
end

local function postJson(url, body)
    local req = getRequest()
    if not req then
        return false, "Executor sem função HTTP compatível."
    end

    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(body)
    end)
    if not okEncode then
        return false, "Erro ao codificar JSON: " .. tostring(encoded)
    end

    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.UploadRetries do
        local ok, response = pcall(function()
            return req({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json",
                },
                Body = encoded,
            })
        end)

        if ok and response then
            local code = tonumber(response.StatusCode or response.Status or 0) or 0
            local raw = response.Body or response.body or ""

            if code >= 200 and code < 300 then
                if raw == "" then
                    return true, {}
                end

                local decodeOk, decoded = pcall(function()
                    return HttpService:JSONDecode(raw)
                end)

                if decodeOk then
                    return true, decoded
                end

                return true, {raw = raw}
            end

            lastError = "HTTP " .. tostring(code)
            if raw ~= "" then
                local decodeOk, decoded = pcall(function()
                    return HttpService:JSONDecode(raw)
                end)
                if decodeOk and type(decoded) == "table" then
                    lastError = tostring(decoded.message or decoded.error or lastError)
                end
            end
        else
            lastError = tostring(response)
        end

        if attempt < CONFIG.UploadRetries then
            task.wait(CONFIG.UploadRetryDelay * attempt)
        end
    end

    return false, lastError
end

local function makeFilename()
    local stamp = os.date("!%Y%m%d_%H%M%S")
    return string.format(
        "Cafeina_SmartV42_%s_%s.json",
        tostring(game.PlaceId),
        stamp
    )
end

local function sendExport()
    if STATE.Sending then
        return
    end

    if STATE.Running then
        setUploadStatus("interrompa o scan antes de enviar", Color3.fromRGB(255,220,120))
        return
    end

    if #STATE.Records == 0 then
        setUploadStatus("nenhum dado para enviar", Color3.fromRGB(255,180,100))
        return
    end

    if not getRequest() then
        setUploadStatus("executor sem HTTP", Color3.fromRGB(255,100,100))
        return
    end

    STATE.Sending = true
    STATE.UploadId = nil
    STATE.BytesSent = 0
    STATE.ChunksSent = 0
    setUploadProgress(0)
    linkLabel.Text = ""
    sendBtn.Text = "ENVIANDO..."

    task.spawn(function()
        local filename = makeFilename()

        setUploadStatus("abrindo envio...", Color3.fromRGB(120,190,255))

        local startOk, startResult = postJson(
            CONFIG.UPLOAD_BASE .. "/start",
            withToken({
                filename = filename,
                source = "cafeina-smart-scanner-v4.2-incremental",
                metadata = {
                    placeId = game.PlaceId,
                    gameId = game.GameId,
                    jobId = game.JobId,
                    clientVisibleOnly = true,
                    recordCount = #STATE.Records,
                    bytesApprox = STATE.ApproxBytes,
                    scanner = "CAFEINA SMART SCANNER V4.2 INCREMENTAL",
                }
            })
        )

        if not startOk or type(startResult) ~= "table" or not startResult.uploadId then
            STATE.Sending = false
            sendBtn.Text = "ENVIAR"
            setUploadStatus("erro: " .. tostring(startResult or "uploadId ausente"), Color3.fromRGB(255,100,100))
            return
        end

        STATE.UploadId = tostring(startResult.uploadId)

        -- Calcula chunks pelo tamanho aproximado codificado dos registros.
        local chunks = {}
        local current = {}
        local currentBytes = 2

        for _, record in ipairs(STATE.Records) do
            local ok, encoded = pcall(function()
                return HttpService:JSONEncode(record)
            end)

            if ok then
                local recordBytes = #encoded + 1

                if currentBytes + recordBytes > CONFIG.UploadChunkBytes and #current > 0 then
                    table.insert(chunks, current)
                    current = {}
                    currentBytes = 2
                end

                table.insert(current, record)
                currentBytes += recordBytes
            end
        end

        if #current > 0 then
            table.insert(chunks, current)
        end

        local totalChunks = #chunks
        if totalChunks == 0 then
            STATE.Sending = false
            sendBtn.Text = "ENVIAR"
            setUploadStatus("nenhum chunk gerado", Color3.fromRGB(255,100,100))
            return
        end

        for index, objects in ipairs(chunks) do
            local progressBefore = (index - 1) / totalChunks
            setUploadProgress(progressBefore)
            setUploadStatus(
                string.format("parte %d/%d • %d%%", index, totalChunks, math.floor(progressBefore * 100)),
                Color3.fromRGB(120,190,255)
            )

            local chunkOk, chunkResult = postJson(
                CONFIG.UPLOAD_BASE .. "/chunk",
                withToken({
                    uploadId = STATE.UploadId,
                    index = index,
                    objects = objects,
                })
            )

            if not chunkOk then
                STATE.Sending = false
                sendBtn.Text = "ENVIAR"
                setUploadStatus("erro na parte " .. tostring(index) .. ": " .. tostring(chunkResult), Color3.fromRGB(255,100,100))
                return
            end

            STATE.ChunksSent = index

            local okBytes, encodedObjects = pcall(function()
                return HttpService:JSONEncode(objects)
            end)
            if okBytes then
                STATE.BytesSent += #encodedObjects
            end

            setUploadProgress(index / totalChunks)
        end

        setUploadStatus("finalizando...", Color3.fromRGB(120,190,255))

        local finishOk, finishResult = postJson(
            CONFIG.UPLOAD_BASE .. "/finish",
            withToken({
                uploadId = STATE.UploadId,
                totalChunks = STATE.ChunksSent,
                summary = {
                    records = #STATE.Records,
                    chunks = STATE.ChunksSent,
                    bytesApprox = STATE.BytesSent,
                    scanBytesApprox = STATE.ApproxBytes,
                    clientVisibleOnly = true,
                    interrupted = STATE.StopRequested,
                    reached150MB = STATE.ApproxBytes >= CONFIG.MaxBytesApprox,
                }
            })
        )

        STATE.Sending = false
        sendBtn.Text = "ENVIAR"

        if not finishOk then
            setUploadStatus("erro ao finalizar: " .. tostring(finishResult), Color3.fromRGB(255,100,100))
            return
        end

        local url = type(finishResult) == "table"
            and (finishResult.downloadUrl or finishResult.url)
            or nil

        if not url or tostring(url) == "" then
            setUploadStatus("concluído, mas site não retornou link", Color3.fromRGB(255,180,100))
            return
        end

        url = tostring(url)

        -- Se o backend devolver caminho relativo, transforma em URL completa.
        if string.sub(url, 1, 1) == "/" then
            url = CONFIG.BASE_URL .. url
        end

        STATE.LastURL = url
        linkLabel.Text = url
        setUploadProgress(1)
        setUploadStatus("100% • link copiado", Color3.fromRGB(140,255,170))

        -- ÚNICO conteúdo copiado pelo scanner: o link devolvido pelo site.
        local clipboard = getClipboard()
        if clipboard then
            pcall(clipboard, url)
        end
    end)
end

--==============================================================
-- BUTTONS
--==============================================================

startBtn.MouseButton1Click:Connect(function()
    if STATE.Running then
        return
    end

    if STATE.Sending then
        setUploadStatus("aguarde o envio terminar", Color3.fromRGB(255,220,120))
        return
    end

    scannerLoop()
end)

stopBtn.MouseButton1Click:Connect(function()
    if STATE.Running then
        STATE.StopRequested = true
    end
end)

sendBtn.MouseButton1Click:Connect(function()
    sendExport()
end)

refreshInfo()
setUploadProgress(0)
