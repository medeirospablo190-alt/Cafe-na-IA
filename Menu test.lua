--[[
    CAFEÍNA • SMART SCANNER V4.1R

    Revisão da V4.1:
      - Mesmo layout.
      - Mesmos 3 botões.
      - Scanner somente leitura.
      - Não executa RemoteEvents/RemoteFunctions.
      - Não altera objetos do jogo.

    Melhorias:
      - Cache de GetDescendants por passe.
      - Cache de GetFullName por passe.
      - Intervalo menor entre passes.
      - Detecção de remoção mais segura.
      - Upload progressivo.
      - Menor uso de memória durante envio.
      - Proteção de limite de ~150 MB.
      - Snapshots só são confirmados quando o registro é salvo.
]]

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    -- V4.1 original: 1.25
    -- Reduzido porque agora GetDescendants é cacheado por passe.
    ScanInterval = 0.35,

    -- 0 = sem limite artificial de registros.
    -- O scanner para pelo limite de bytes.
    MaxRecords = 0,

    MaxBytesApprox = 150 * 1024 * 1024,

    -- Pequena reserva para a estrutura externa do JSON.
    JsonSafetyBytes = 256 * 1024,

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

    HighValuePathTokens = {
        "__remotes",
        "tycoonservice",
        "playerdataservice",
        "loadoutservice",
        "teamservice",
        "leaderboardservice",
        "tacticalairstrikeservice",

        "soldiers",
        "tycoon",
        "purchases",
        "collector",
        "money",
        "cash",

        "weapon",
        "gun",
        "loadout",

        "rebirth",
        "button",
        "projectile"
    },

    IgnoreDecorative = true,

    IgnoreClasses = {
        ["ParticleEmitter"] = true,
        ["Trail"] = true,
        ["Beam"] = true,
        ["Texture"] = true,
        ["Decal"] = true,
        ["SurfaceAppearance"] = true,
        ["SpecialMesh"] = true,

        ["MeshPart"] = false,
    },

    InterestingNames = {
        "damage",
        "health",
        "maxhealth",

        "ammo",
        "mag",
        "magazine",

        "reload",
        "firerate",
        "fire",

        "spread",
        "recoil",
        "range",

        "speed",
        "walkspeed",

        "money",
        "cash",
        "kills",

        "rebirth",
        "team",

        "weapon",
        "gun",
        "tool",

        "soldier",
        "npc",
        "aggro",
        "target",

        "cooldown",
        "cost",
        "price",

        "purchase",
        "collect",
        "button",

        "tycoon",

        "blaster",
        "bullet",
        "projectile",

        "hit",
        "headshot",

        "armor",
        "armour",

        "loadout",
        "spawn"
    },

    BASE_URL =
        "https://cafe-na-ia.onrender.com",

    UPLOAD_BASE =
        "https://cafe-na-ia.onrender.com/upload",

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
    LimitReached = false,

    Pass = 0,

    StartedAt = 0,
    FinishedAt = 0,

    Records = {},

    Seen = {},
    LastSnapshot = {},

    Added = 0,
    Changed = 0,
    Removed = 0,
    NewUseful = 0,

    PassAdded = 0,
    PassChanged = 0,
    PassRemoved = 0,

    CategoryCount = {},

    ApproxBytes = 0,

    PassCache = nil,
    ScannedCategories = {},

    CurrentPhase = "Pronto",

    LastStatus = "Pronto",
    LastDetail = "Aguardando início",

    UploadId = nil,
    BytesSent = 0,
    ChunksSent = 0,

    LastURL = nil,
}

--==============================================================
-- BASIC HELPERS
--==============================================================

local function now()
    return os.clock()
end

local function lower(value)
    return string.lower(
        tostring(value or "")
    )
end

local function clippedText(value, maxLen)

    local s =
        tostring(value or "")

    maxLen =
        maxLen or 240

    if #s > maxLen then

        return string.sub(
            s,
            1,
            maxLen
        ) .. "…"

    end

    return s
end

--==============================================================
-- PASS CACHE
--==============================================================

local function resetPassCache()

    STATE.PassCache = {

        Descendants = {},

        Paths =
            setmetatable(
                {},
                {
                    __mode = "k"
                }
            )
    }
end

local function getCachedDescendants(root)

    if not root then
        return {}
    end

    local cache =
        STATE.PassCache

    if not cache then

        local ok, result =
            pcall(function()

                return root:GetDescendants()

            end)

        if ok then
            return result
        end

        return {}
    end

    local cached =
        cache.Descendants[root]

    if cached then
        return cached
    end

    local ok, result =
        pcall(function()

            return root:GetDescendants()

        end)

    if not ok then
        result = {}
    end

    cache.Descendants[root] =
        result

    return result
end

local function safeFullName(obj)

    if not obj then
        return "nil"
    end

    local cache =
        STATE.PassCache

    if cache
        and cache.Paths then

        local cached =
            cache.Paths[obj]

        if cached then
            return cached
        end
    end

    local ok, value =
        pcall(function()

            return obj:GetFullName()

        end)

    if not ok then
        value = tostring(obj)
    end

    if cache
        and cache.Paths then

        cache.Paths[obj] =
            value
    end

    return value
end

--==============================================================
-- VALUE HELPERS
--==============================================================

local function safeAttributes(obj)

    local ok, attrs =
        pcall(function()

            return obj:GetAttributes()

        end)

    if ok then
        return attrs
    end

    return {}
end

local function containsInterestingName(name)

    local n =
        lower(name)

    for _, token
        in ipairs(CONFIG.InterestingNames) do

        if string.find(
            n,
            token,
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function containsHighValuePath(path)

    local p =
        lower(path)

    for _, token
        in ipairs(CONFIG.HighValuePathTokens) do

        if string.find(
            p,
            token,
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function isDecorative(obj)

    if not CONFIG.IgnoreDecorative then
        return false
    end

    if CONFIG.IgnoreClasses[obj.ClassName] then
        return true
    end

    local n =
        lower(obj.Name)

    if n == "mesh"
        or n == "accessoryweld"
        or n == "originalposition"
        or n == "originalsize" then

        return true
    end

    return false
end

local function primitiveValue(v)

    local t =
        typeof(v)

    if t == "string"
        or t == "number"
        or t == "boolean" then

        return v

    elseif t == "Vector3" then

        return {
            x = v.X,
            y = v.Y,
            z = v.Z
        }

    elseif t == "Vector2" then

        return {
            x = v.X,
            y = v.Y
        }

    elseif t == "Color3" then

        return {
            r = v.R,
            g = v.G,
            b = v.B
        }

    elseif t == "CFrame" then

        local p =
            v.Position

        return {
            x = p.X,
            y = p.Y,
            z = p.Z
        }

    elseif t == "EnumItem" then

        return tostring(v)
    end

    return tostring(v)
end

local function approxLen(value)

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                value
            )

        end)

    if ok then
        return #encoded
    end

    return 64
end

local function recordKey(
    category,
    obj,
    suffix
)

    return category
        .. "|"
        .. safeFullName(obj)
        .. "|"
        .. tostring(suffix or "")
end

--==============================================================
-- RECORD STORAGE
--==============================================================

local function usableByteLimit()

    return math.max(
        0,

        CONFIG.MaxBytesApprox
            - CONFIG.JsonSafetyBytes
    )
end

local function addRecord(
    category,
    kind,
    key,
    data
)

    if STATE.LimitReached then
        return false
    end

    if CONFIG.MaxRecords > 0
        and #STATE.Records >= CONFIG.MaxRecords then

        STATE.LimitReached = true
        return false
    end

    local rec = {

        t = os.time(),

        pass =
            STATE.Pass,

        category =
            category,

        kind =
            kind,

        key =
            key,

        data =
            data
    }

    local bytes =
        approxLen(rec) + 1

    if STATE.ApproxBytes + bytes
        > usableByteLimit() then

        STATE.LimitReached = true

        return false
    end

    table.insert(
        STATE.Records,
        rec
    )

    STATE.ApproxBytes +=
        bytes

    STATE.CategoryCount[category] =
        (STATE.CategoryCount[category] or 0)
        + 1

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

--==============================================================
-- SNAPSHOT
--==============================================================

local function snapshotValue(obj)

    local data = {

        class =
            obj.ClassName,

        name =
            obj.Name,

        path =
            safeFullName(obj)
    }

    if obj:IsA("ValueBase") then

        local ok, value =
            pcall(function()

                return obj.Value

            end)

        if ok then
            data.value =
                primitiveValue(value)
        end
    end

    if obj:IsA("Humanoid") then

        data.health =
            obj.Health

        data.maxHealth =
            obj.MaxHealth

        data.walkSpeed =
            obj.WalkSpeed

        data.jumpPower =
            obj.JumpPower
    end

    if obj:IsA("Tool") then

        data.toolTip =
            obj.ToolTip

        data.canBeDropped =
            obj.CanBeDropped

        data.hasHandle =
            obj:FindFirstChild("Handle")
                ~= nil
    end

    if obj:IsA("RemoteEvent")
        or obj:IsA("RemoteFunction") then

        data.remoteType =
            obj.ClassName

        data.parentPath =
            obj.Parent
            and safeFullName(obj.Parent)
            or nil
    end

    if obj:IsA("ProximityPrompt") then

        data.actionText =
            clippedText(
                obj.ActionText,
                120
            )

        data.objectText =
            clippedText(
                obj.ObjectText,
                120
            )

        data.holdDuration =
            obj.HoldDuration

        data.maxActivationDistance =
            obj.MaxActivationDistance

        data.enabled =
            obj.Enabled
    end

    if obj:IsA("LocalScript")
        or obj:IsA("ModuleScript")
        or obj:IsA("Script") then

        data.scriptClass =
            obj.ClassName

        if obj:IsA("LocalScript")
            or obj:IsA("Script") then

            local okDisabled,
                disabled =
                    pcall(function()

                        return obj.Disabled

                    end)

            if okDisabled then

                data.disabled =
                    disabled
            end
        end
    end

    if obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox") then

        data.text =
            clippedText(
                obj.Text,
                240
            )

        data.visible =
            obj.Visible

    elseif obj:IsA("GuiObject") then

        data.visible =
            obj.Visible
    end

    local attrs =
        safeAttributes(obj)

    if next(attrs) then

        data.attributes = {}

        for k, v
            in pairs(attrs) do

            if containsInterestingName(k)
                or not CONFIG.TrackInterestingAttributes then

                data.attributes[k] =
                    primitiveValue(v)
            end
        end

        if not next(data.attributes) then
            data.attributes = nil
        end
    end

    return data
end

local function fingerprint(data)

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                data
            )

        end)

    if ok then
        return encoded
    end

    return tostring(data)
end

--==============================================================
-- CONSIDER OBJECT
--==============================================================

local function consider(
    category,
    obj,
    forceUseful
)

    if STATE.StopRequested
        or STATE.LimitReached then

        return
    end

    if not obj
        or not obj.Parent then

        return
    end

    if isDecorative(obj)
        and not forceUseful then

        return
    end

    local key =
        recordKey(
            category,
            obj
        )

    local data =
        snapshotValue(obj)

    local fp =
        fingerprint(data)

    STATE.Seen[key] =
        true

    local previous =
        STATE.LastSnapshot[key]

    if previous == nil then

        if addRecord(
            category,
            "baseline",
            key,
            data
        ) then

            STATE.NewUseful += 1

            STATE.LastSnapshot[key] =
                fp
        end

    elseif previous ~= fp then

        if addRecord(
            category,
            "changed",
            key,
            data
        ) then

            STATE.NewUseful += 1

            STATE.LastSnapshot[key] =
                fp
        end
    end
end

--==============================================================
-- GENERIC SCANNER
--==============================================================

local function scanDescendants(
    root,
    category,
    predicate
)

    if not root then
        return true
    end

    local descendants =
        getCachedDescendants(root)

    for _, obj
        in ipairs(descendants) do

        if STATE.StopRequested
            or STATE.LimitReached then

            return false
        end

        local accepted = true

        if predicate then

            local okPredicate,
                result =
                    pcall(
                        predicate,
                        obj
                    )

            accepted =
                okPredicate
                and result == true
        end

        if accepted then

            consider(
                category,
                obj,
                false
            )
        end
    end

    return true
end

--==============================================================
-- SMART SCANNERS
--==============================================================

local function scanRemotes()

    if not CONFIG.TrackRemotes then
        return
    end

    local roots = {
        ReplicatedStorage,
        ReplicatedFirst
    }

    for _, root
        in ipairs(roots) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        scanDescendants(
            root,
            "Remotes",

            function(obj)

                return
                    obj:IsA("RemoteEvent")
                    or obj:IsA("RemoteFunction")
                    or obj:IsA("BindableEvent")
                    or obj:IsA("BindableFunction")
            end
        )
    end
end

local function scanRemoteStructure()

    if not CONFIG.TrackRemoteStructure then
        return
    end

    local remotesRoot =
        ReplicatedStorage:
        FindFirstChild(
            "__remotes",
            true
        )

    if not remotesRoot then
        return
    end

    consider(
        "RemoteStructure",
        remotesRoot,
        true
    )

    for _, serviceFolder
        in ipairs(remotesRoot:GetChildren()) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        consider(
            "RemoteStructure",
            serviceFolder,
            true
        )

        local descendants =
            getCachedDescendants(
                serviceFolder
            )

        for _, obj
            in ipairs(descendants) do

            if STATE.StopRequested
                or STATE.LimitReached then
                return
            end

            if obj:IsA("RemoteEvent")
                or obj:IsA("RemoteFunction")
                or obj:IsA("BindableEvent")
                or obj:IsA("BindableFunction") then

                consider(
                    "RemoteStructure",
                    obj,
                    true
                )
            end
        end
    end
end

local function scanScriptsMetadata()

    if not CONFIG.TrackScriptsMetadata then
        return
    end

    local roots = {
        ReplicatedStorage,
        ReplicatedFirst,
        StarterPlayer
    }

    for _, root
        in ipairs(roots) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        scanDescendants(
            root,
            "Scripts",

            function(obj)

                if not (
                    obj:IsA("LocalScript")
                    or obj:IsA("ModuleScript")
                    or obj:IsA("Script")
                ) then

                    return false
                end

                local path =
                    safeFullName(obj)

                return
                    containsHighValuePath(path)
                    or containsInterestingName(
                        obj.Name
                    )
            end
        )
    end
end

local function scanRelevantGui()

    if not CONFIG.TrackRelevantGui then
        return
    end

    local roots = {
        PlayerGui,
        StarterGui
    }

    for _, root
        in ipairs(roots) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        scanDescendants(
            root,
            "GUI",

            function(obj)

                if not obj:IsA("GuiObject") then
                    return false
                end

                local path =
                    safeFullName(obj)

                if containsHighValuePath(path)
                    or containsInterestingName(
                        obj.Name
                    ) then

                    return true
                end

                if obj:IsA("TextLabel")
                    or obj:IsA("TextButton")
                    or obj:IsA("TextBox") then

                    return
                        containsInterestingName(
                            obj.Text
                        )
                end

                return false
            end
        )
    end
end

local function scanBlaster()

    if not CONFIG.TrackBlaster then
        return
    end

    scanDescendants(
        ReplicatedStorage,
        "BlasterSystem",

        function(obj)

            local p =
                lower(
                    safeFullName(obj)
                )

            return
                string.find(
                    p,
                    "blaster",
                    1,
                    true
                )
                or string.find(
                    p,
                    "bullet",
                    1,
                    true
                )
                or string.find(
                    p,
                    "projectile",
                    1,
                    true
                )
                or containsInterestingName(
                    obj.Name
                )
        end
    )
end

local function scanTools()

    if not CONFIG.TrackTools then
        return
    end

    local roots = {
        Workspace,
        ReplicatedStorage
    }

    local backpack =
        LocalPlayer:
        FindFirstChild("Backpack")

    if backpack then
        table.insert(
            roots,
            backpack
        )
    end

    for _, root
        in ipairs(roots) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        scanDescendants(
            root,
            "Tools",

            function(obj)

                if obj:IsA("Tool") then
                    return true
                end

                local parent =
                    obj.Parent

                if parent
                    and parent:IsA("Tool") then

                    return
                        containsInterestingName(
                            obj.Name
                        )
                        or obj:IsA("ValueBase")
                        or obj:IsA("ModuleScript")
                        or obj:IsA("LocalScript")
                end

                return false
            end
        )
    end
end

local function scanSoldiers()

    if not CONFIG.TrackSoldiers then
        return
    end

    local soldiers =
        Workspace:
        FindFirstChild("Soldiers")

    if soldiers then

        for _, model
            in ipairs(
                soldiers:GetChildren()
            ) do

            if STATE.StopRequested
                or STATE.LimitReached then
                return
            end

            if model:IsA("Model") then

                consider(
                    "Soldiers",
                    model,
                    true
                )

                local descendants =
                    getCachedDescendants(
                        model
                    )

                for _, obj
                    in ipairs(descendants) do

                    if STATE.StopRequested
                        or STATE.LimitReached then
                        return
                    end

                    if obj:IsA("Humanoid")
                        or obj:IsA("Tool")
                        or obj:IsA("ValueBase")
                        or obj.Name == "HumanoidRootPart"
                        or containsInterestingName(
                            obj.Name
                        ) then

                        consider(
                            "Soldiers",
                            obj,
                            true
                        )
                    end
                end
            end
        end

    else

        scanDescendants(
            Workspace,
            "Soldiers",

            function(obj)

                if obj:IsA("Humanoid")
                    and obj.Parent
                    and obj.Parent:IsA("Model") then

                    local model =
                        obj.Parent

                    return
                        containsInterestingName(
                            model.Name
                        )
                        or model:
                            FindFirstChildOfClass(
                                "Tool"
                            ) ~= nil
                end

                return false
            end
        )
    end
end

local function scanPlayerData()

    if not CONFIG.TrackPlayerData then
        return
    end

    for _, plr
        in ipairs(
            Players:GetPlayers()
        ) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        local leaderstats =
            plr:
            FindFirstChild(
                "leaderstats"
            )

        if leaderstats then

            local descendants =
                getCachedDescendants(
                    leaderstats
                )

            for _, obj
                in ipairs(descendants) do

                if STATE.StopRequested
                    or STATE.LimitReached then
                    return
                end

                if obj:IsA("ValueBase") then

                    consider(
                        "PlayerData",
                        obj,
                        true
                    )
                end
            end
        end

        for _, child
            in ipairs(
                plr:GetChildren()
            ) do

            if STATE.StopRequested
                or STATE.LimitReached then
                return
            end

            if child ~= plr.Character
                and (
                    child:IsA("Folder")
                    or child:IsA("Configuration")
                    or child:IsA("ValueBase")
                ) then

                if containsInterestingName(
                    child.Name
                ) then

                    consider(
                        "PlayerData",
                        child,
                        true
                    )

                    local descendants =
                        getCachedDescendants(
                            child
                        )

                    for _, obj
                        in ipairs(descendants) do

                        if STATE.StopRequested
                            or STATE.LimitReached then
                            return
                        end

                        if obj:IsA("ValueBase")
                            or containsInterestingName(
                                obj.Name
                            ) then

                            consider(
                                "PlayerData",
                                obj,
                                true
                            )
                        end
                    end
                end
            end
        end
    end
end

local function scanTycoon()

    if not CONFIG.TrackTycoon then
        return
    end

    scanDescendants(
        Workspace,
        "Tycoon",

        function(obj)

            local p =
                lower(
                    safeFullName(obj)
                )

            if not containsHighValuePath(
                p
            ) then

                return false
            end

            return
                obj:IsA("ValueBase")
                or obj:IsA("ProximityPrompt")
                or obj:IsA("ClickDetector")
                or obj:IsA("TouchTransmitter")
                or obj:IsA("Tool")
                or containsInterestingName(
                    obj.Name
                )
        end
    )
end

local function scanInteractions()

    if not CONFIG.TrackInteractions then
        return
    end

    scanDescendants(
        Workspace,
        "Interactions",

        function(obj)

            return
                obj:IsA("ProximityPrompt")
                or obj:IsA("ClickDetector")
                or obj:IsA("TouchTransmitter")
        end
    )
end

--==============================================================
-- REMOVED DETECTION
--==============================================================

local function categoryFromKey(key)

    local separator =
        string.find(
            key,
            "|",
            1,
            true
        )

    if not separator then
        return nil
    end

    return string.sub(
        key,
        1,
        separator - 1
    )
end

local function detectRemoved()

    local removedKeys = {}

    for key
        in pairs(
            STATE.LastSnapshot
        ) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        local category =
            categoryFromKey(key)

        if category
            and STATE.ScannedCategories[
                category
            ]
            and not STATE.Seen[key] then

            table.insert(
                removedKeys,
                key
            )
        end
    end

    for _, key
        in ipairs(removedKeys) do

        if STATE.StopRequested
            or STATE.LimitReached then
            return
        end

        if addRecord(
            "Lifecycle",
            "removed",
            key,
            {
                path = key
            }
        ) then

            STATE.LastSnapshot[key] =
                nil
        end
    end
end

--==============================================================
-- UI
--==============================================================

local oldGui =
    PlayerGui:
    FindFirstChild(
        "CafeinaSmartScannerV41"
    )

if oldGui then
    oldGui:Destroy()
end

local gui =
    Instance.new("ScreenGui")

gui.Name =
    "CafeinaSmartScannerV41"

gui.ResetOnSpawn =
    false

gui.IgnoreGuiInset =
    false

gui.Parent =
    PlayerGui

local main =
    Instance.new("Frame")

main.Size =
    UDim2.fromOffset(
        330,
        178
    )

main.Position =
    UDim2.new(
        0.5,
        -165,
        0.08,
        0
    )

main.BackgroundColor3 =
    Color3.fromRGB(
        15,
        15,
        18
    )

main.BorderSizePixel =
    0

main.Active =
    true

main.Draggable =
    true

main.Parent =
    gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(
        0,
        12
    )

corner.Parent =
    main

local stroke =
    Instance.new("UIStroke")

stroke.Color =
    Color3.fromRGB(
        55,
        55,
        62
    )

stroke.Thickness =
    1

stroke.Parent =
    main

local title =
    Instance.new("TextLabel")

title.Size =
    UDim2.new(
        1,
        -20,
        0,
        28
    )

title.Position =
    UDim2.fromOffset(
        10,
        7
    )

title.BackgroundTransparency =
    1

-- Mantido igual visualmente.
title.Text =
    "CAFEÍNA • SMART SCANNER V4.1"

title.Font =
    Enum.Font.GothamBold

title.TextSize =
    14

title.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

title.TextXAlignment =
    Enum.TextXAlignment.Left

title.Parent =
    main

local scanSizeLabel =
    Instance.new("TextLabel")

scanSizeLabel.Size =
    UDim2.new(
        1,
        -20,
        0,
        34
    )

scanSizeLabel.Position =
    UDim2.fromOffset(
        10,
        38
    )

scanSizeLabel.BackgroundTransparency =
    1

scanSizeLabel.Text =
    "SCAN • 0.0 MB / 150 MB"

scanSizeLabel.Font =
    Enum.Font.GothamBold

scanSizeLabel.TextSize =
    16

scanSizeLabel.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

scanSizeLabel.TextXAlignment =
    Enum.TextXAlignment.Left

scanSizeLabel.Parent =
    main

local uploadStatus =
    Instance.new("TextLabel")

uploadStatus.Size =
    UDim2.new(
        1,
        -20,
        0,
        22
    )

uploadStatus.Position =
    UDim2.fromOffset(
        10,
        77
    )

uploadStatus.BackgroundTransparency =
    1

uploadStatus.Text =
    "UPLOAD • aguardando"

uploadStatus.Font =
    Enum.Font.Gotham

uploadStatus.TextSize =
    11

uploadStatus.TextColor3 =
    Color3.fromRGB(
        180,
        180,
        185
    )

uploadStatus.TextXAlignment =
    Enum.TextXAlignment.Left

uploadStatus.Parent =
    main

local barBg =
    Instance.new("Frame")

barBg.Size =
    UDim2.new(
        1,
        -20,
        0,
        8
    )

barBg.Position =
    UDim2.fromOffset(
        10,
        104
    )

barBg.BackgroundColor3 =
    Color3.fromRGB(
        40,
        40,
        46
    )

barBg.BorderSizePixel =
    0

barBg.Parent =
    main

Instance.new(
    "UICorner",
    barBg
).CornerRadius =
    UDim.new(
        1,
        0
    )

local bar =
    Instance.new("Frame")

bar.Size =
    UDim2.fromScale(
        0,
        1
    )

bar.BackgroundColor3 =
    Color3.fromRGB(
        235,
        235,
        235
    )

bar.BorderSizePixel =
    0

bar.Parent =
    barBg

Instance.new(
    "UICorner",
    bar
).CornerRadius =
    UDim.new(
        1,
        0
    )

local linkLabel =
    Instance.new("TextLabel")

linkLabel.Size =
    UDim2.new(
        1,
        -20,
        0,
        20
    )

linkLabel.Position =
    UDim2.fromOffset(
        10,
        116
    )

linkLabel.BackgroundTransparency =
    1

linkLabel.Text =
    ""

linkLabel.Font =
    Enum.Font.Gotham

linkLabel.TextSize =
    10

linkLabel.TextColor3 =
    Color3.fromRGB(
        150,
        150,
        155
    )

linkLabel.TextXAlignment =
    Enum.TextXAlignment.Left

linkLabel.TextTruncate =
    Enum.TextTruncate.AtEnd

linkLabel.Parent =
    main

local function makeButton(
    text,
    x,
    width
)

    local b =
        Instance.new(
            "TextButton"
        )

    b.Size =
        UDim2.fromOffset(
            width,
            30
        )

    b.Position =
        UDim2.fromOffset(
            x,
            140
        )

    b.BackgroundColor3 =
        Color3.fromRGB(
            30,
            30,
            35
        )

    b.BorderSizePixel =
        0

    b.Text =
        text

    b.Font =
        Enum.Font.GothamBold

    b.TextSize =
        11

    b.TextColor3 =
        Color3.fromRGB(
            245,
            245,
            245
        )

    b.AutoButtonColor =
        true

    b.Parent =
        main

    Instance.new(
        "UICorner",
        b
    ).CornerRadius =
        UDim.new(
            0,
            8
        )

    return b
end

local startBtn =
    makeButton(
        "INICIAR",
        10,
        98
    )

local stopBtn =
    makeButton(
        "INTERROMPER",
        116,
        98
    )

local sendBtn =
    makeButton(
        "ENVIAR",
        222,
        98
    )

--==============================================================
-- MINIMIZE
--==============================================================

local minimizeBtn =
    Instance.new(
        "TextButton"
    )

minimizeBtn.Size =
    UDim2.fromOffset(
        22,
        22
    )

minimizeBtn.Position =
    UDim2.new(
        1,
        -30,
        0,
        8
    )

minimizeBtn.BackgroundColor3 =
    Color3.fromRGB(
        30,
        30,
        35
    )

minimizeBtn.BorderSizePixel =
    0

minimizeBtn.Text =
    "−"

minimizeBtn.Font =
    Enum.Font.GothamBold

minimizeBtn.TextSize =
    14

minimizeBtn.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

minimizeBtn.AutoButtonColor =
    true

minimizeBtn.Parent =
    main

Instance.new(
    "UICorner",
    minimizeBtn
).CornerRadius =
    UDim.new(
        0,
        7
    )

local restoreBtn =
    Instance.new(
        "TextButton"
    )

restoreBtn.Size =
    UDim2.fromOffset(
        38,
        38
    )

restoreBtn.Position =
    UDim2.new(
        0.5,
        -19,
        0.08,
        0
    )

restoreBtn.BackgroundColor3 =
    Color3.fromRGB(
        15,
        15,
        18
    )

restoreBtn.BorderSizePixel =
    0

restoreBtn.Text =
    "C"

restoreBtn.Font =
    Enum.Font.GothamBold

restoreBtn.TextSize =
    15

restoreBtn.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

restoreBtn.Active =
    true

restoreBtn.Draggable =
    true

restoreBtn.Visible =
    false

restoreBtn.Parent =
    gui

Instance.new(
    "UICorner",
    restoreBtn
).CornerRadius =
    UDim.new(
        1,
        0
    )

local restoreStroke =
    Instance.new(
        "UIStroke"
    )

restoreStroke.Color =
    Color3.fromRGB(
        55,
        55,
        62
    )

restoreStroke.Thickness =
    1

restoreStroke.Parent =
    restoreBtn

minimizeBtn.MouseButton1Click:
Connect(function()

    restoreBtn.Position =
        main.Position

    main.Visible =
        false

    restoreBtn.Visible =
        true
end)

restoreBtn.MouseButton1Click:
Connect(function()

    main.Position =
        restoreBtn.Position

    restoreBtn.Visible =
        false

    main.Visible =
        true
end)

--==============================================================
-- UI STATUS
--==============================================================

local function setUploadStatus(
    textValue,
    color
)

    uploadStatus.Text =
        "UPLOAD • "
        .. tostring(
            textValue or ""
        )

    if color then

        uploadStatus.TextColor3 =
            color

    else

        uploadStatus.TextColor3 =
            Color3.fromRGB(
                180,
                180,
                185
            )
    end
end

local function setUploadProgress(value)

    value =
        math.clamp(
            tonumber(value) or 0,
            0,
            1
        )

    bar.Size =
        UDim2.fromScale(
            value,
            1
        )
end

local function refreshInfo()

    local mb =
        STATE.ApproxBytes
        / 1024
        / 1024

    scanSizeLabel.Text =
        string.format(
            "SCAN • %.1f MB / 150 MB • P%d",
            mb,
            STATE.Pass
        )
end

--==============================================================
-- EXPORT METADATA
--==============================================================

local function buildExport()

    return {

        schemaVersion = 6,

        scanner =
            "CAFEINA SMART SCANNER V4.1R SELECTIVE",

        generatedAt =
            os.time(),

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        jobId =
            game.JobId,

        clientVisibleOnly =
            true,

        scan = {

            complete =
                STATE.LimitReached,

            interrupted =
                STATE.StopRequested,

            passes =
                STATE.Pass,

            records =
                #STATE.Records,

            added =
                STATE.Added,

            changed =
                STATE.Changed,

            removed =
                STATE.Removed,

            newUseful =
                STATE.NewUseful,

            approxBytes =
                STATE.ApproxBytes,

            categories =
                STATE.CategoryCount
        },

        records =
            STATE.Records
    }
end

--==============================================================
-- RESET
--==============================================================

local function resetState()

    STATE.StopRequested =
        false

    STATE.LimitReached =
        false

    STATE.Pass =
        0

    STATE.StartedAt =
        now()

    STATE.FinishedAt =
        0

    STATE.Records =
        {}

    STATE.Seen =
        {}

    STATE.LastSnapshot =
        {}

    STATE.PassCache =
        nil

    STATE.ScannedCategories =
        {}

    STATE.Added =
        0

    STATE.Changed =
        0

    STATE.Removed =
        0

    STATE.NewUseful =
        0

    STATE.PassAdded =
        0

    STATE.PassChanged =
        0

    STATE.PassRemoved =
        0

    STATE.CategoryCount =
        {}

    STATE.ApproxBytes =
        0

    STATE.CurrentPhase =
        "Iniciando"

    STATE.LastURL =
        nil
end

--==============================================================
-- PASS EXECUTOR
--==============================================================

local function runPass()

    STATE.Pass += 1

    STATE.Seen =
        {}

    STATE.ScannedCategories =
        {}

    STATE.PassAdded =
        0

    STATE.PassChanged =
        0

    STATE.PassRemoved =
        0

    resetPassCache()

    local function execute(
        name,
        category,
        callback
    )

        if STATE.StopRequested
            or STATE.LimitReached then

            return false
        end

        STATE.CurrentPhase =
            name

        local ok, err =
            pcall(
                callback
            )

        if not ok then

            warn(
                "[CAFEINA SMART SCANNER] "
                .. tostring(name)
                .. ": "
                .. tostring(err)
            )

            -- Não marca categoria como concluída.
            -- Isso evita falsos "removed".
            return true
        end

        if not STATE.StopRequested
            and not STATE.LimitReached then

            STATE.ScannedCategories[
                category
            ] = true
        end

        return true
    end

    execute(
        "Remotes",
        "Remotes",
        scanRemotes
    )

    execute(
        "RemoteStructure",
        "RemoteStructure",
        scanRemoteStructure
    )

    execute(
        "Tycoon",
        "Tycoon",
        scanTycoon
    )

    execute(
        "Soldiers",
        "Soldiers",
        scanSoldiers
    )

    execute(
        "Tools",
        "Tools",
        scanTools
    )

    execute(
        "PlayerData",
        "PlayerData",
        scanPlayerData
    )

    execute(
        "Blaster",
        "BlasterSystem",
        scanBlaster
    )

    execute(
        "Scripts",
        "Scripts",
        scanScriptsMetadata
    )

    execute(
        "GUI",
        "GUI",
        scanRelevantGui
    )

    execute(
        "Interactions",
        "Interactions",
        scanInteractions
    )

    if not STATE.StopRequested
        and not STATE.LimitReached then

        detectRemoved()
    end

    if not STATE.StopRequested
        and not STATE.LimitReached then

        addRecord(
            "Analysis",
            "pass_summary",
            "pass|"
                .. tostring(
                    STATE.Pass
                ),

            {
                pass =
                    STATE.Pass,

                added =
                    STATE.PassAdded,

                changed =
                    STATE.PassChanged,

                removed =
                    STATE.PassRemoved,

                totalRecords =
                    #STATE.Records,

                approxBytes =
                    STATE.ApproxBytes
            }
        )
    end

    STATE.PassCache =
        nil

    refreshInfo()
end

--==============================================================
-- SCANNER LOOP
--==============================================================

local function scannerLoop()

    if STATE.Running then
        return
    end

    resetState()

    STATE.Running =
        true

    setUploadProgress(0)

    setUploadStatus(
        "aguardando"
    )

    linkLabel.Text =
        ""

    refreshInfo()

    task.spawn(function()

        while STATE.Running
            and not STATE.StopRequested do

            if STATE.LimitReached then
                break
            end

            local ok, err =
                pcall(
                    runPass
                )

            if not ok then

                STATE.Running =
                    false

                STATE.PassCache =
                    nil

                setUploadStatus(
                    "scanner encontrou erro: "
                    .. tostring(err),

                    Color3.fromRGB(
                        255,
                        100,
                        100
                    )
                )

                return
            end

            if STATE.StopRequested
                or STATE.LimitReached then

                break
            end

            local elapsed =
                0

            while elapsed
                < CONFIG.ScanInterval
                and not STATE.StopRequested do

                task.wait(
                    0.05
                )

                elapsed +=
                    0.05
            end
        end

        STATE.Running =
            false

        STATE.FinishedAt =
            now()

        STATE.PassCache =
            nil

        refreshInfo()

        if STATE.LimitReached then

            scanSizeLabel.Text =
                string.format(
                    "SCAN • 150.0 MB / 150 MB • P%d",
                    STATE.Pass
                )
        end
    end)
end

--==============================================================
-- HTTP
--==============================================================

local function getRequest()

    return
        (syn and syn.request)
        or http_request
        or request
        or (
            http
            and http.request
        )
end

local function getClipboard()

    if typeof(setclipboard)
        == "function" then

        return setclipboard
    end

    if typeof(toclipboard)
        == "function" then

        return toclipboard
    end

    return nil
end

local function withToken(body)

    if CONFIG.UPLOAD_TOKEN ~= "" then

        body.token =
            CONFIG.UPLOAD_TOKEN
    end

    return body
end

local function postJson(
    url,
    body
)

    local req =
        getRequest()

    if not req then

        return false,
            "Executor sem função HTTP compatível."
    end

    local okEncode,
        encoded =
            pcall(function()

                return HttpService:
                    JSONEncode(
                        body
                    )

            end)

    if not okEncode then

        return false,
            "Erro ao codificar JSON: "
            .. tostring(
                encoded
            )
    end

    local lastError =
        "Falha desconhecida"

    for attempt =
        1,
        CONFIG.UploadRetries do

        local ok,
            response =
                pcall(function()

                    return req({

                        Url =
                            url,

                        Method =
                            "POST",

                        Headers = {

                            ["Content-Type"] =
                                "application/json",

                            ["Accept"] =
                                "application/json"
                        },

                        Body =
                            encoded
                    })

                end)

        if ok and response then

            local code =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or 0
                ) or 0

            local raw =
                response.Body
                or response.body
                or ""

            if code >= 200
                and code < 300 then

                if raw == "" then
                    return true, {}
                end

                local decodeOk,
                    decoded =
                        pcall(function()

                            return HttpService:
                                JSONDecode(
                                    raw
                                )

                        end)

                if decodeOk then
                    return true, decoded
                end

                return true, {
                    raw = raw
                }
            end

            lastError =
                "HTTP "
                .. tostring(code)

            if raw ~= "" then

                local decodeOk,
                    decoded =
                        pcall(function()

                            return HttpService:
                                JSONDecode(
                                    raw
                                )

                        end)

                if decodeOk
                    and type(decoded)
                        == "table" then

                    lastError =
                        tostring(
                            decoded.message
                            or decoded.error
                            or lastError
                        )
                end
            end

        else

            lastError =
                tostring(response)
        end

        if attempt
            < CONFIG.UploadRetries then

            task.wait(
                CONFIG.UploadRetryDelay
                * attempt
            )
        end
    end

    return false,
        lastError
end

--==============================================================
-- FILE NAME
--==============================================================

local function makeFilename()

    local stamp =
        os.date(
            "!%Y%m%d_%H%M%S"
        )

    return string.format(
        "Cafeina_Smart_%s_%s.json",
        tostring(game.PlaceId),
        stamp
    )
end

--==============================================================
-- UPLOAD
--==============================================================

local function sendExport()

    if STATE.Sending then
        return
    end

    if STATE.Running then

        setUploadStatus(
            "interrompa o scan antes de enviar",

            Color3.fromRGB(
                255,
                220,
                120
            )
        )

        return
    end

    if #STATE.Records == 0 then

        setUploadStatus(
            "nenhum dado para enviar",

            Color3.fromRGB(
                255,
                180,
                100
            )
        )

        return
    end

    if not getRequest() then

        setUploadStatus(
            "executor sem HTTP",

            Color3.fromRGB(
                255,
                100,
                100
            )
        )

        return
    end

    STATE.Sending =
        true

    STATE.UploadId =
        nil

    STATE.BytesSent =
        0

    STATE.ChunksSent =
        0

    setUploadProgress(0)

    linkLabel.Text =
        ""

    sendBtn.Text =
        "ENVIANDO..."

    task.spawn(function()

        local filename =
            makeFilename()

        setUploadStatus(
            "abrindo envio...",

            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local startOk,
            startResult =
                postJson(

                    CONFIG.UPLOAD_BASE
                        .. "/start",

                    withToken({

                        filename =
                            filename,

                        source =
                            "cafeina-smart-scanner-v4.1r-selective",

                        metadata = {

                            placeId =
                                game.PlaceId,

                            gameId =
                                game.GameId,

                            jobId =
                                game.JobId,

                            clientVisibleOnly =
                                true,

                            recordCount =
                                #STATE.Records,

                            bytesApprox =
                                STATE.ApproxBytes,

                            scanner =
                                "CAFEINA SMART SCANNER V4.1R SELECTIVE"
                        }
                    })
                )

        if not startOk
            or type(startResult)
                ~= "table"
            or not startResult.uploadId then

            STATE.Sending =
                false

            sendBtn.Text =
                "ENVIAR"

            setUploadStatus(
                "erro: "
                .. tostring(
                    type(startResult)
                        == "table"
                        and (
                            startResult.message
                            or startResult.error
                            or "uploadId ausente"
                        )
                        or startResult
                ),

                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

            return
        end

        STATE.UploadId =
            tostring(
                startResult.uploadId
            )

        --======================================================
        -- STREAMING CHUNKS
        --
        -- Não cria:
        --     chunks = {}
        --
        -- Só mantém o chunk atual em memória.
        --======================================================

        local current =
            {}

        local currentBytes =
            2

        local chunkIndex =
            0

        local processedBytes =
            0

        local totalApprox =
            math.max(
                STATE.ApproxBytes,
                1
            )

        local function failUpload(message)

            STATE.Sending =
                false

            sendBtn.Text =
                "ENVIAR"

            setUploadStatus(
                tostring(message),

                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )
        end

        local function flushChunk()

            if #current == 0 then
                return true
            end

            chunkIndex += 1

            local progress =
                math.clamp(
                    processedBytes
                    / totalApprox,
                    0,
                    0.99
                )

            setUploadProgress(
                progress
            )

            setUploadStatus(
                string.format(
                    "parte %d • %d%%",
                    chunkIndex,
                    math.floor(
                        progress
                        * 100
                    )
                ),

                Color3.fromRGB(
                    120,
                    190,
                    255
                )
            )

            local chunkOk,
                chunkResult =
                    postJson(

                        CONFIG.UPLOAD_BASE
                            .. "/chunk",

                        withToken({

                            uploadId =
                                STATE.UploadId,

                            index =
                                chunkIndex,

                            objects =
                                current
                        })
                    )

            if not chunkOk then

                return false,
                    tostring(
                        chunkResult
                    )
            end

            STATE.ChunksSent =
                chunkIndex

            STATE.BytesSent +=
                currentBytes

            -- Libera o chunk enviado.
            current =
                {}

            currentBytes =
                2

            return true
        end

        for _, record
            in ipairs(
                STATE.Records
            ) do

            local okRecord,
                encoded =
                    pcall(function()

                        return HttpService:
                            JSONEncode(
                                record
                            )

                    end)

            if okRecord then

                local recordBytes =
                    #encoded + 1

                if currentBytes
                    + recordBytes
                    > CONFIG.UploadChunkBytes
                    and #current > 0 then

                    local flushOk,
                        flushError =
                            flushChunk()

                    if not flushOk then

                        failUpload(
                            "erro na parte "
                            .. tostring(
                                chunkIndex
                            )
                            .. ": "
                            .. tostring(
                                flushError
                            )
                        )

                        return
                    end
                end

                table.insert(
                    current,
                    record
                )

                currentBytes +=
                    recordBytes

                processedBytes +=
                    recordBytes
            end
        end

        local finalFlushOk,
            finalFlushError =
                flushChunk()

        if not finalFlushOk then

            failUpload(
                "erro ao enviar última parte: "
                .. tostring(
                    finalFlushError
                )
            )

            return
        end

        if STATE.ChunksSent <= 0 then

            failUpload(
                "nenhum chunk gerado"
            )

            return
        end

        setUploadStatus(
            "finalizando...",

            Color3.fromRGB(
                120,
                190,
                255
            )
        )

        local finishOk,
            finishResult =
                postJson(

                    CONFIG.UPLOAD_BASE
                        .. "/finish",

                    withToken({

                        uploadId =
                            STATE.UploadId,

                        totalChunks =
                            STATE.ChunksSent,

                        summary = {

                            records =
                                #STATE.Records,

                            chunks =
                                STATE.ChunksSent,

                            bytesApprox =
                                STATE.BytesSent,

                            scanBytesApprox =
                                STATE.ApproxBytes,

                            clientVisibleOnly =
                                true,

                            interrupted =
                                STATE.StopRequested,

                            reached150MB =
                                STATE.LimitReached
                        }
                    })
                )

        STATE.Sending =
            false

        sendBtn.Text =
            "ENVIAR"

        if not finishOk then

            setUploadStatus(
                "erro ao finalizar: "
                .. tostring(
                    finishResult
                ),

                Color3.fromRGB(
                    255,
                    100,
                    100
                )
            )

            return
        end

        local url = nil

        if type(finishResult)
            == "table" then

            url =
                finishResult.downloadUrl
                or finishResult.url
                or finishResult.link
        end

        if not url
            or tostring(url) == "" then

            setUploadStatus(
                "concluído, mas site não retornou link",

                Color3.fromRGB(
                    255,
                    180,
                    100
                )
            )

            return
        end

        url =
            tostring(url)

        if string.sub(
            url,
            1,
            1
        ) == "/" then

            url =
                CONFIG.BASE_URL
                .. url
        end

        STATE.LastURL =
            url

        linkLabel.Text =
            url

        setUploadProgress(1)

        setUploadStatus(
            "100% • link copiado",

            Color3.fromRGB(
                140,
                255,
                170
            )
        )

        -- ÚNICO conteúdo enviado ao clipboard:
        -- o link final retornado pelo site.
        local clipboard =
            getClipboard()

        if clipboard then

            pcall(
                clipboard,
                url
            )
        end
    end)
end

--==============================================================
-- BUTTONS
--==============================================================

startBtn.MouseButton1Click:
Connect(function()

    if STATE.Running then
        return
    end

    if STATE.Sending then

        setUploadStatus(
            "aguarde o envio terminar",

            Color3.fromRGB(
                255,
                220,
                120
            )
        )

        return
    end

    scannerLoop()
end)

stopBtn.MouseButton1Click:
Connect(function()

    if STATE.Running then

        STATE.StopRequested =
            true
    end
end)

sendBtn.MouseButton1Click:
Connect(function()

    sendExport()
end)

--==============================================================
-- INITIAL UI
--==============================================================

refreshInfo()
setUploadProgress(0)
setUploadStatus("aguardando")
