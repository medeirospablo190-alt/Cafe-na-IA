--==============================================================
-- CAFEÍNA • MAPPING ENGINE + TEST LAB + UPLOADER
-- V1.1 • CLIENT-VISIBLE ONLY
--
-- CORREÇÕES PRINCIPAIS:
-- • INICIAR SCAN inicia MappingEngine + TestLab juntos
-- • estado de sessão não é encerrado antes dos workers terminarem
-- • PARAR TUDO solicita parada cooperativa
-- • TestLab não depende de Session.Running ser desligado prematuramente
-- • addRecord aceita registros finais mesmo após StopRequested
-- • proteção contra APIs/classes indisponíveis
-- • barras separadas para scan e upload
-- • limite lógico aproximado de 150 MB
--==============================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "MAPPING_V1_1",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    UPLOAD_TOKEN = "",

    MAX_TOTAL_BYTES = 150 * 1024 * 1024,
    TARGET_CHUNK_BYTES = 3200000,

    YIELD_EVERY = 120,
    RETRIES = 3,
    RETRY_DELAY = 1.25,

    TEST_INTERVAL = 1.0,
    MAX_TEST_TRACKED_VALUES = 2200,
    MAX_TEST_TRACKED_ATTRIBUTES = 1400,
    MAX_TEST_DYNAMIC_OBJECTS = 5000,

    SERVICES = {
        {name = "ReplicatedStorage", budget = 30000},
        {name = "ReplicatedFirst", budget = 10000},
        {name = "StarterPlayer", budget = 15000},
        {name = "StarterGui", budget = 12000},
        {name = "Players", budget = 12000},
        {name = "Lighting", budget = 5000},
        {name = "Teams", budget = 3000},
        {name = "SoundService", budget = 5000},
        {name = "Workspace", budget = 30000},
    },

    CLASS_LIMITS = {
        Pose = 20,
        Keyframe = 20,
        Texture = 150,
        Decal = 150,
        SurfaceAppearance = 100,
        ParticleEmitter = 200,
        Trail = 100,
        Beam = 100,
    },

    HIGH_PRIORITY_CLASSES = {
        RemoteEvent = true,
        RemoteFunction = true,
        UnreliableRemoteEvent = true,
        ModuleScript = true,
        LocalScript = true,
        Script = true,
        ObjectValue = true,
        StringValue = true,
        BoolValue = true,
        IntValue = true,
        NumberValue = true,
        Tool = true,
        ProximityPrompt = true,
        Configuration = true,
    },

    NAME_KEYWORDS = {
        "remote","event","network","module","config","setting","shared",
        "item","weapon","gun","ammo","inventory",
        "combat","damage","health","stamina","sanity",
        "round","match","state","ending",
        "loot","shop","quest","artifact","scrap",
        "npc","ai","path","track",
        "character","player",
        "gui","ui",
        "day","night","bloodmoon",
    },
}

local function hasGlobalFunction(name)
    local ok, value = pcall(function()
        return getgenv and getgenv()[name] or _G[name]
    end)
    return ok and typeof(value) == "function" and value or nil
end

local ExecutorRequest =
    hasGlobalFunction("request")
    or hasGlobalFunction("http_request")
    or (
        typeof(http) == "table"
        and typeof(http.request) == "function"
        and http.request
    )
    or (
        syn
        and typeof(syn.request) == "function"
        and syn.request
    )
    or nil

local Session = {
    Running = false,
    ScanRunning = false,
    TestsRunning = false,
    ObserversRunning = false,

    StopRequested = false,
    StopReason = nil,
    Finalized = false,

    StartedAtClock = 0,
    StartedAtUnix = 0,
    RunId = nil,

    EstimatedBytes = 0,
    ObjectsScanned = 0,
    ServicesDone = 0,
    ServicesTotal = #CONFIG.SERVICES,
    CurrentService = "",
}

local Upload = {
    Running = false,
    CancelRequested = false,
    UploadId = nil,
    ChunksSent = 0,
    BytesSent = 0,
    LastURL = "",
}

local Report = {
    meta = {},
    records = {},
    diagnostics = {
        errors = {},
        counters = {
            total = 0,
            scan = 0,
            tests = 0,
            diagnostic = 0,
            session = 0,
        },
    },
}

local ClassCounters = {}
local TestConnections = {}
local TrackedValues = {}
local TrackedAttributes = {}

local UI = {}

local function safeCall(fn, fallback)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return fallback
end

local function safeFullName(inst)
    if not inst then
        return nil
    end
    return safeCall(function()
        return inst:GetFullName()
    end, tostring(inst.Name))
end

local function safeAttributes(inst)
    local attrs = safeCall(function()
        return inst:GetAttributes()
    end, {})
    return type(attrs) == "table" and attrs or {}
end

local function relativeTime()
    if Session.StartedAtClock <= 0 then
        return 0
    end
    return math.max(0, os.clock() - Session.StartedAtClock)
end

local function formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.2f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    return tostring(bytes) .. " B"
end

local function serializeValue(value)
    local t = typeof(value)

    if t == "Instance" then
        return {
            type = "Instance",
            path = safeFullName(value),
            className = value.ClassName,
        }
    elseif t == "Vector3" then
        return {type = "Vector3", x = value.X, y = value.Y, z = value.Z}
    elseif t == "Vector2" then
        return {type = "Vector2", x = value.X, y = value.Y}
    elseif t == "Color3" then
        return {type = "Color3", r = value.R, g = value.G, b = value.B}
    elseif t == "CFrame" then
        local p = value.Position
        return {type = "CFrame", x = p.X, y = p.Y, z = p.Z}
    elseif t == "number" or t == "string" or t == "boolean" or value == nil then
        return value
    end

    return tostring(value)
end

local function estimateRecordSize(record)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, record)
    return ok and (#encoded + 1) or 0
end

local function addRecord(source, kind, data, allowAfterStop)
    if not allowAfterStop and Session.StopRequested then
        return false
    end

    local record = {}
    for k, v in pairs(data or {}) do
        record[k] = v
    end

    record.source = source
    record.kind = kind
    record.time = relativeTime()

    local bytes = estimateRecordSize(record)

    if (
        not allowAfterStop
        and Session.EstimatedBytes + bytes > CONFIG.MAX_TOTAL_BYTES
    ) then
        Session.StopRequested = true
        Session.StopReason = "size_limit"
        return false
    end

    table.insert(Report.records, record)

    if not allowAfterStop then
        Session.EstimatedBytes += bytes
    end

    local counters = Report.diagnostics.counters
    counters.total += 1
    if counters[source] ~= nil then
        counters[source] += 1
    end

    return true
end

local function logError(systemName, err)
    local item = {
        system = tostring(systemName),
        error = tostring(err),
    }
    table.insert(Report.diagnostics.errors, item)
    addRecord("diagnostic", "error", item, true)
end

local function shouldContinue()
    return Session.Running
        and not Session.StopRequested
        and Session.EstimatedBytes < CONFIG.MAX_TOTAL_BYTES
end

local function relevanceScore(inst)
    local score = 0

    if CONFIG.HIGH_PRIORITY_CLASSES[inst.ClassName] then
        score += 100
    end

    if inst:IsA("ValueBase") then
        score += 35
    end

    if inst:IsA("Tool") then
        score += 60
    end

    if next(safeAttributes(inst)) ~= nil then
        score += 20
    end

    local name = string.lower(tostring(inst.Name))
    for _, keyword in ipairs(CONFIG.NAME_KEYWORDS) do
        if string.find(name, keyword, 1, true) then
            score += 15
        end
    end

    return score
end

local function canCollectClass(inst)
    local limit = CONFIG.CLASS_LIMITS[inst.ClassName]
    if not limit then
        return true
    end

    ClassCounters[inst.ClassName] = (ClassCounters[inst.ClassName] or 0) + 1
    return ClassCounters[inst.ClassName] <= limit
end

local function serializeInstance(inst, serviceName)
    local data = {
        service = serviceName,
        name = tostring(inst.Name),
        className = tostring(inst.ClassName),
        path = safeFullName(inst),
        parentPath = inst.Parent and safeFullName(inst.Parent) or nil,
        relevance = relevanceScore(inst),
        attributes = safeAttributes(inst),
        childCount = safeCall(function()
            return #inst:GetChildren()
        end, 0),
    }

    if inst:IsA("ValueBase") then
        data.value = serializeValue(safeCall(function()
            return inst.Value
        end, nil))
    end

    if inst:IsA("ObjectValue") then
        local target = safeCall(function()
            return inst.Value
        end, nil)
        if target then
            data.reference = {
                targetPath = safeFullName(target),
                targetClass = target.ClassName,
            }
        end
    end

    local className = inst.ClassName
    if className == "RemoteEvent"
        or className == "RemoteFunction"
        or className == "UnreliableRemoteEvent"
    then
        data.remote = {
            type = className,
            path = safeFullName(inst),
        }
    end

    if inst:IsA("LuaSourceContainer") then
        data.script = {
            type = className,
            path = safeFullName(inst),
        }
    end

    if inst:IsA("Tool") then
        data.tool = {
            requiresHandle = safeCall(function()
                return inst.RequiresHandle
            end, nil),
            canBeDropped = safeCall(function()
                return inst.CanBeDropped
            end, nil),
        }
    end

    if inst:IsA("ProximityPrompt") then
        data.prompt = {
            actionText = safeCall(function()
                return inst.ActionText
            end, ""),
            objectText = safeCall(function()
                return inst.ObjectText
            end, ""),
            holdDuration = safeCall(function()
                return inst.HoldDuration
            end, 0),
            maxActivationDistance = safeCall(function()
                return inst.MaxActivationDistance
            end, 0),
        }
    end

    if inst:IsA("Humanoid") then
        data.humanoid = {
            health = safeCall(function()
                return inst.Health
            end, nil),
            maxHealth = safeCall(function()
                return inst.MaxHealth
            end, nil),
            walkSpeed = safeCall(function()
                return inst.WalkSpeed
            end, nil),
            jumpPower = safeCall(function()
                return inst.JumpPower
            end, nil),
        }
    end

    if inst:IsA("Sound") then
        data.sound = {
            soundId = safeCall(function()
                return inst.SoundId
            end, ""),
            volume = safeCall(function()
                return inst.Volume
            end, 0),
            playing = safeCall(function()
                return inst.Playing
            end, false),
        }
    end

    return data
end

local COLORS = {
    BG = Color3.fromRGB(14, 14, 17),
    PANEL = Color3.fromRGB(22, 22, 27),
    PANEL2 = Color3.fromRGB(31, 31, 38),
    RED = Color3.fromRGB(225, 42, 55),
    RED_DARK = Color3.fromRGB(120, 24, 33),
    TEXT = Color3.fromRGB(245, 245, 248),
    SUB = Color3.fromRGB(170, 170, 180),
    GREEN = Color3.fromRGB(65, 205, 115),
    YELLOW = Color3.fromRGB(235, 180, 55),
    ORANGE = Color3.fromRGB(245, 130, 55),
}

local function create(className, props)
    local object = Instance.new(className)
    for k, v in pairs(props or {}) do
        object[k] = v
    end
    return object
end

local function corner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = parent,
    })
end

local GuiParent
if typeof(gethui) == "function" then
    GuiParent = safeCall(gethui, nil)
end

local Gui = create("ScreenGui", {
    Name = "CafeinaMappingV11",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
})

local parented = false
if GuiParent then
    parented = pcall(function()
        Gui.Parent = GuiParent
    end)
end
if not parented then
    parented = pcall(function()
        Gui.Parent = CoreGui
    end)
end
if not parented then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

for _, old in ipairs(Gui.Parent:GetChildren()) do
    if old ~= Gui and old.Name == Gui.Name then
        old:Destroy()
    end
end

local Main = create("Frame", {
    Size = UDim2.fromOffset(360, 424),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = COLORS.BG,
    BorderSizePixel = 0,
    Parent = Gui,
})
corner(Main, 14)

local Header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = COLORS.PANEL,
    BorderSizePixel = 0,
    Parent = Main,
})
corner(Header, 14)

create("TextLabel", {
    Position = UDim2.fromOffset(14, 7),
    Size = UDim2.new(1, -28, 0, 22),
    BackgroundTransparency = 1,
    Text = "CAFEÍNA • MAPPING",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Header,
})

create("TextLabel", {
    Position = UDim2.fromOffset(14, 29),
    Size = UDim2.new(1, -28, 0, 16),
    BackgroundTransparency = 1,
    Text = "SCAN + TEST LAB • 150 MB",
    TextColor3 = COLORS.SUB,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Header,
})

local function makeButton(text, x, y, width, color)
    local button = create("TextButton", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, 42),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        Parent = Main,
    })
    corner(button, 8)
    return button
end

local ScanButton = makeButton("INICIAR SCAN", 12, 66, 164, COLORS.RED)
local TestsButton = makeButton("INICIAR TESTES", 184, 66, 164, COLORS.RED_DARK)
local SendButton = makeButton("ENVIAR TUDO", 12, 116, 164, COLORS.RED_DARK)
local StopButton = makeButton("PARAR TUDO", 184, 116, 164, Color3.fromRGB(95, 26, 32))

local function makeStatusPanel(title, y)
    local panel = create("Frame", {
        Position = UDim2.fromOffset(12, y),
        Size = UDim2.new(1, -24, 0, 101),
        BackgroundColor3 = COLORS.PANEL,
        BorderSizePixel = 0,
        Parent = Main,
    })
    corner(panel, 10)

    create("TextLabel", {
        Position = UDim2.fromOffset(11, 7),
        Size = UDim2.new(1, -22, 0, 18),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = panel,
    })

    local status = create("TextLabel", {
        Position = UDim2.fromOffset(11, 29),
        Size = UDim2.new(1, -22, 0, 18),
        BackgroundTransparency = 1,
        Text = "Pronto",
        TextColor3 = COLORS.SUB,
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = panel,
    })

    local detail = create("TextLabel", {
        Position = UDim2.fromOffset(11, 49),
        Size = UDim2.new(1, -22, 0, 17),
        BackgroundTransparency = 1,
        Text = "0 B",
        TextColor3 = COLORS.SUB,
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = panel,
    })

    local barBG = create("Frame", {
        Position = UDim2.new(0, 11, 1, -20),
        Size = UDim2.new(1, -22, 0, 7),
        BackgroundColor3 = COLORS.PANEL2,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(barBG, 99)

    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.RED,
        BorderSizePixel = 0,
        Parent = barBG,
    })
    corner(fill, 99)

    return {
        Status = status,
        Detail = detail,
        Fill = fill,
    }
end

UI.Scan = makeStatusPanel("SCAN / TEST LAB", 170)
UI.Upload = makeStatusPanel("UPLOAD", 279)

UI.Link = create("TextLabel", {
    Position = UDim2.fromOffset(12, 389),
    Size = UDim2.new(1, -24, 0, 24),
    BackgroundTransparency = 1,
    Text = "Link: nenhum upload concluído",
    TextColor3 = COLORS.SUB,
    Font = Enum.Font.Code,
    TextSize = 8,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = Main,
})

local function tweenProgress(fill, value)
    value = math.clamp(tonumber(value) or 0, 0, 1)
    TweenService:Create(
        fill,
        TweenInfo.new(0.12),
        {Size = UDim2.new(value, 0, 1, 0)}
    ):Play()
end

local function updateScanUI()
    local progress = math.clamp(
        Session.EstimatedBytes / CONFIG.MAX_TOTAL_BYTES,
        0,
        1
    )
    tweenProgress(UI.Scan.Fill, progress)

    if Session.ScanRunning and Session.TestsRunning then
        UI.Scan.Status.Text = "Scan + TestLab ativos • " .. tostring(Session.CurrentService)
    elseif Session.ScanRunning then
        UI.Scan.Status.Text = "Scan ativo • " .. tostring(Session.CurrentService)
    elseif Session.TestsRunning then
        UI.Scan.Status.Text = "TestLab ativo"
    elseif Session.Finalized then
        UI.Scan.Status.Text = "Finalizado • " .. tostring(Session.StopReason or "concluído")
    elseif Session.StopRequested then
        UI.Scan.Status.Text = "Parando..."
    else
        UI.Scan.Status.Text = "Pronto"
    end

    UI.Scan.Detail.Text =
        formatBytes(Session.EstimatedBytes)
        .. " / 150 MB • "
        .. tostring(Session.ObjectsScanned)
        .. " objetos"
end

local function setUploadStatus(text)
    UI.Upload.Status.Text = tostring(text or "")
end

local function updateUploadUI()
    local total = math.max(1, Session.EstimatedBytes)
    local progress = Upload.Running and math.clamp(Upload.BytesSent / total, 0, 1)
        or (Upload.BytesSent > 0 and 1 or 0)

    tweenProgress(UI.Upload.Fill, progress)

    UI.Upload.Detail.Text =
        tostring(Upload.ChunksSent)
        .. " chunks • "
        .. formatBytes(Upload.BytesSent)
end

local function disconnectTestConnections()
    for _, connection in ipairs(TestConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(TestConnections)
    Session.ObserversRunning = false
end

local MappingEngine = {}

function MappingEngine:Run()
    Session.ScanRunning = true
    addRecord("scan", "mapping_started", {})

    for serviceIndex, info in ipairs(CONFIG.SERVICES) do
        if not shouldContinue() then
            break
        end

        Session.CurrentService = info.name
        updateScanUI()

        local service = safeCall(function()
            return game:GetService(info.name)
        end, nil)

        if service then
            local descendants = safeCall(function()
                return service:GetDescendants()
            end, {})

            local candidates = {}

            for index, inst in ipairs(descendants) do
                if not shouldContinue() then
                    break
                end

                if canCollectClass(inst) then
                    candidates[#candidates + 1] = {
                        instance = inst,
                        score = relevanceScore(inst),
                    }
                end

                if index % CONFIG.YIELD_EVERY == 0 then
                    task.wait()
                end
            end

            table.sort(candidates, function(a, b)
                return a.score > b.score
            end)

            local collected = 0

            for index, candidate in ipairs(candidates) do
                if not shouldContinue() or collected >= info.budget then
                    break
                end

                local ok, record = pcall(
                    serializeInstance,
                    candidate.instance,
                    info.name
                )

                if ok and type(record) == "table" then
                    if not addRecord("scan", "object", record) then
                        break
                    end
                    collected += 1
                    Session.ObjectsScanned += 1
                end

                if index % CONFIG.YIELD_EVERY == 0 then
                    updateScanUI()
                    task.wait()
                end
            end

            addRecord("scan", "service_summary", {
                service = info.name,
                descendants = #descendants,
                collected = collected,
            })
        end

        Session.ServicesDone = serviceIndex
        updateScanUI()
        task.wait()
    end

    Session.ScanRunning = false

    addRecord("scan", "mapping_finished", {
        objects = Session.ObjectsScanned,
    }, true)

    if not Session.StopRequested then
        Session.StopRequested = true
        Session.StopReason = "scan_completed"
    end

    updateScanUI()
end

local TestLab = {}

local function snapshotValueObject(inst)
    return serializeValue(safeCall(function()
        return inst.Value
    end, nil))
end

function TestLab:CaptureBaseline()
    addRecord("tests", "baseline_started", {})

    local countValues = 0
    local countAttributes = 0

    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
        workspace,
    }

    for _, root in ipairs(roots) do
        if not shouldContinue() then
            break
        end

        local descendants = safeCall(function()
            return root:GetDescendants()
        end, {})

        for index, inst in ipairs(descendants) do
            if not shouldContinue() then
                break
            end

            if inst:IsA("ValueBase")
                and countValues < CONFIG.MAX_TEST_TRACKED_VALUES
            then
                TrackedValues[inst] = snapshotValueObject(inst)
                countValues += 1
            end

            if countAttributes < CONFIG.MAX_TEST_TRACKED_ATTRIBUTES then
                local attrs = safeAttributes(inst)
                if next(attrs) ~= nil then
                    TrackedAttributes[inst] = attrs
                    countAttributes += 1
                end
            end

            if index % 200 == 0 then
                task.wait()
            end
        end
    end

    addRecord("tests", "baseline_finished", {
        trackedValues = countValues,
        trackedAttributes = countAttributes,
    })
end

function TestLab:StartObservers()
    disconnectTestConnections()

    local roots = {
        workspace,
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
    }

    local dynamicCount = 0

    for _, root in ipairs(roots) do
        TestConnections[#TestConnections + 1] =
            root.DescendantAdded:Connect(function(inst)
                if not shouldContinue() then
                    return
                end

                if dynamicCount >= CONFIG.MAX_TEST_DYNAMIC_OBJECTS then
                    return
                end

                dynamicCount += 1

                addRecord("tests", "object_created", {
                    path = safeFullName(inst),
                    className = inst.ClassName,
                    name = inst.Name,
                })
            end)

        TestConnections[#TestConnections + 1] =
            root.DescendantRemoving:Connect(function(inst)
                if not shouldContinue() then
                    return
                end

                addRecord("tests", "object_removed", {
                    path = safeFullName(inst),
                    className = inst.ClassName,
                    name = inst.Name,
                })
            end)
    end

    TestConnections[#TestConnections + 1] =
        Players.PlayerAdded:Connect(function(player)
            if shouldContinue() then
                addRecord("tests", "player_added", {
                    name = player.Name,
                    userId = player.UserId,
                })
            end
        end)

    TestConnections[#TestConnections + 1] =
        Players.PlayerRemoving:Connect(function(player)
            if shouldContinue() then
                addRecord("tests", "player_removed", {
                    name = player.Name,
                    userId = player.UserId,
                })
            end
        end)

    Session.ObserversRunning = true
    addRecord("tests", "observers_started", {})
end

function TestLab:Run()
    Session.TestsRunning = true
    addRecord("tests", "test_lab_started", {})

    self:CaptureBaseline()

    if shouldContinue() then
        self:StartObservers()
    end

    local cycle = 0

    while shouldContinue() do
        cycle += 1

        for inst, oldValue in pairs(TrackedValues) do
            if not shouldContinue() then
                break
            end

            if inst and inst.Parent then
                local newValue = snapshotValueObject(inst)

                local oldEncoded = safeCall(function()
                    return HttpService:JSONEncode(oldValue)
                end, tostring(oldValue))

                local newEncoded = safeCall(function()
                    return HttpService:JSONEncode(newValue)
                end, tostring(newValue))

                if oldEncoded ~= newEncoded then
                    addRecord("tests", "value_changed", {
                        path = safeFullName(inst),
                        className = inst.ClassName,
                        before = oldValue,
                        after = newValue,
                    })
                    TrackedValues[inst] = newValue
                end
            else
                TrackedValues[inst] = nil
            end
        end

        for inst, oldAttrs in pairs(TrackedAttributes) do
            if not shouldContinue() then
                break
            end

            if inst and inst.Parent then
                local newAttrs = safeAttributes(inst)

                local oldEncoded = safeCall(function()
                    return HttpService:JSONEncode(oldAttrs)
                end, "")

                local newEncoded = safeCall(function()
                    return HttpService:JSONEncode(newAttrs)
                end, "")

                if oldEncoded ~= newEncoded then
                    addRecord("tests", "attributes_changed", {
                        path = safeFullName(inst),
                        before = oldAttrs,
                        after = newAttrs,
                    })
                    TrackedAttributes[inst] = newAttrs
                end
            else
                TrackedAttributes[inst] = nil
            end
        end

        if cycle % 5 == 0 then
            addRecord("tests", "test_cycle", {
                cycle = cycle,
                trackedValues = (function()
                    local n = 0
                    for _ in pairs(TrackedValues) do
                        n += 1
                    end
                    return n
                end)(),
                trackedAttributes = (function()
                    local n = 0
                    for _ in pairs(TrackedAttributes) do
                        n += 1
                    end
                    return n
                end)(),
            })
        end

        updateScanUI()
        task.wait(CONFIG.TEST_INTERVAL)
    end

    disconnectTestConnections()
    Session.TestsRunning = false

    addRecord("tests", "test_lab_finished", {
        cycles = cycle,
    }, true)

    updateScanUI()
end

local function decodeResponse(response)
    if type(response) == "string" then
        return safeCall(function()
            return HttpService:JSONDecode(response)
        end, nil)
    end

    if type(response) ~= "table" then
        return nil
    end

    local body = response.Body or response.body or response.ResponseBody
    if type(body) ~= "string" then
        return nil
    end

    return safeCall(function()
        return HttpService:JSONDecode(body)
    end, nil)
end

local function rawRequest(url, payload)
    local okEncode, body = pcall(
        HttpService.JSONEncode,
        HttpService,
        payload
    )

    if not okEncode then
        return false, "Erro ao codificar JSON"
    end

    if ExecutorRequest then
        local ok, response = pcall(function()
            return ExecutorRequest({
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

        local status = type(response) == "table"
            and tonumber(
                response.StatusCode
                or response.Status
                or response.status
            )
            or nil

        local decoded = decodeResponse(response)

        if status and (status < 200 or status >= 300) then
            return false,
                decoded
                and (decoded.message or decoded.error)
                or ("HTTP " .. tostring(status))
        end

        if not decoded then
            return false, "Resposta inválida do servidor"
        end

        return true, decoded
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
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

    local decoded = decodeResponse(response)

    if not response.Success then
        return false,
            decoded
            and (decoded.message or decoded.error)
            or ("HTTP " .. tostring(response.StatusCode))
    end

    return true, decoded
end

local function withToken(payload)
    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end
    return payload
end

local function requestRetry(url, payload, label)
    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.RETRIES do
        if Upload.CancelRequested then
            return false, "Cancelado"
        end

        setUploadStatus(
            label
            .. " • tentativa "
            .. tostring(attempt)
            .. "/"
            .. tostring(CONFIG.RETRIES)
        )

        local ok, result = rawRequest(url, payload)
        if ok then
            return true, result
        end

        lastError = tostring(result)

        if attempt < CONFIG.RETRIES then
            task.wait(CONFIG.RETRY_DELAY * attempt)
        end
    end

    return false, lastError
end

local function cancelUpload()
    if not Upload.UploadId then
        return
    end

    local uploadId = Upload.UploadId

    task.spawn(function()
        pcall(function()
            rawRequest(
                CONFIG.UPLOAD_BASE .. "/cancel",
                withToken({
                    uploadId = uploadId,
                })
            )
        end)
    end)
end

local function uploadReport()
    if Upload.Running then
        return false, "Upload já ativo"
    end

    if Session.Running then
        return false, "Pare ou finalize a coleta antes de enviar"
    end

    if #Report.records == 0 then
        return false, "Nenhum dado coletado"
    end

    Upload.Running = true
    Upload.CancelRequested = false
    Upload.UploadId = nil
    Upload.ChunksSent = 0
    Upload.BytesSent = 0

    updateUploadUI()
    setUploadStatus("Abrindo upload...")

    local timestamp = os.date("!%Y%m%d_%H%M%S")
    local filename =
        "Cafeina_Mapping_"
        .. tostring(game.PlaceId)
        .. "_"
        .. timestamp
        .. ".json"

    local startOk, startResult = requestRetry(
        CONFIG.UPLOAD_BASE .. "/start",
        withToken({
            filename = filename,
            source = "cafeina-mapping-engine",
            metadata = {
                runId = Session.RunId,
                recordCount = #Report.records,
                clientVisibleOnly = true,
                maxBytes = CONFIG.MAX_TOTAL_BYTES,
                placeId = game.PlaceId,
                gameId = game.GameId,
                placeVersion = safeCall(function()
                    return game.PlaceVersion
                end, nil),
            },
        }),
        "Abrindo upload"
    )

    if not startOk
        or type(startResult) ~= "table"
        or not startResult.uploadId
    then
        Upload.Running = false
        setUploadStatus("Erro ao abrir upload")
        return false, startResult or "uploadId não retornado"
    end

    Upload.UploadId = tostring(startResult.uploadId)

    local chunk = {}
    local chunkBytes = 2

    local function flushChunk()
        if #chunk == 0 then
            return true
        end

        if Upload.CancelRequested then
            return false, "Cancelado"
        end

        local chunkIndex = Upload.ChunksSent + 1

        setUploadStatus("Enviando parte " .. tostring(chunkIndex))

        local encodeOk, encoded = pcall(
            HttpService.JSONEncode,
            HttpService,
            chunk
        )

        if not encodeOk then
            return false, "Erro ao codificar chunk"
        end

        local uploadOk, uploadResult = requestRetry(
            CONFIG.UPLOAD_BASE .. "/chunk",
            withToken({
                uploadId = Upload.UploadId,
                index = chunkIndex,
                objects = chunk,
            }),
            "Parte " .. tostring(chunkIndex)
        )

        if not uploadOk then
            return false, uploadResult
        end

        Upload.ChunksSent = chunkIndex
        Upload.BytesSent += #encoded

        updateUploadUI()

        chunk = {}
        chunkBytes = 2

        return true
    end

    chunk[#chunk + 1] = {
        recordType = "mapping_header",
        runId = Session.RunId,
        metadata = {
            scanner = CONFIG.VERSION,
            clientVisibleOnly = true,
            placeId = game.PlaceId,
            gameId = game.GameId,
            placeVersion = safeCall(function()
                return game.PlaceVersion
            end, nil),
            collectedBytesApprox = Session.EstimatedBytes,
            recordCount = #Report.records,
        },
    }

    for index, record in ipairs(Report.records) do
        if Upload.CancelRequested then
            cancelUpload()
            Upload.Running = false
            return false, "Cancelado"
        end

        local encodeOk, encoded = pcall(
            HttpService.JSONEncode,
            HttpService,
            record
        )

        if encodeOk then
            local recordBytes = #encoded + 1

            if chunkBytes + recordBytes > CONFIG.TARGET_CHUNK_BYTES
                and #chunk > 0
            then
                local okFlush, flushError = flushChunk()
                if not okFlush then
                    cancelUpload()
                    Upload.Running = false
                    return false, flushError
                end
            end

            chunk[#chunk + 1] = record
            chunkBytes += recordBytes
        end

        if index % 100 == 0 then
            tweenProgress(
                UI.Upload.Fill,
                (index / #Report.records) * 0.90
            )
            task.wait()
        end
    end

    local okFlush, flushError = flushChunk()
    if not okFlush then
        cancelUpload()
        Upload.Running = false
        return false, flushError
    end

    tweenProgress(UI.Upload.Fill, 0.95)
    setUploadStatus("Finalizando...")

    local finishOk, finishResult = requestRetry(
        CONFIG.UPLOAD_BASE .. "/finish",
        withToken({
            uploadId = Upload.UploadId,
            totalChunks = Upload.ChunksSent,
            summary = {
                runId = Session.RunId,
                records = #Report.records,
                chunks = Upload.ChunksSent,
                bytesApprox = Upload.BytesSent,
                clientVisibleOnly = true,
                mappingEngine = true,
                testLab = true,
            },
        }),
        "Finalizando"
    )

    Upload.Running = false

    if not finishOk then
        cancelUpload()
        setUploadStatus("Erro na finalização")
        return false, finishResult
    end

    local url = type(finishResult) == "table"
        and (finishResult.downloadUrl or finishResult.url)
        or nil

    if url then
        Upload.LastURL = tostring(url)
        UI.Link.Text = "Link: " .. Upload.LastURL
    else
        UI.Link.Text = "Upload concluído sem URL retornada"
    end

    tweenProgress(UI.Upload.Fill, 1)
    setUploadStatus("Upload concluído")
    updateUploadUI()

    return true, url
end

local function resetSession()
    disconnectTestConnections()

    Session.Running = false
    Session.ScanRunning = false
    Session.TestsRunning = false
    Session.ObserversRunning = false
    Session.StopRequested = false
    Session.StopReason = nil
    Session.Finalized = false

    Session.StartedAtClock = 0
    Session.StartedAtUnix = 0
    Session.RunId = nil

    Session.EstimatedBytes = 0
    Session.ObjectsScanned = 0
    Session.ServicesDone = 0
    Session.CurrentService = ""

    Report.meta = {}
    Report.records = {}
    Report.diagnostics = {
        errors = {},
        counters = {
            total = 0,
            scan = 0,
            tests = 0,
            diagnostic = 0,
            session = 0,
        },
    }

    ClassCounters = {}
    TrackedValues = {}
    TrackedAttributes = {}

    updateScanUI()
end

local function finalizeSession()
    if Session.Finalized then
        return
    end

    if Session.ScanRunning or Session.TestsRunning then
        return
    end

    Session.Finalized = true
    Session.Running = false
    disconnectTestConnections()

    addRecord("session", "finished", {
        runId = Session.RunId,
        stopReason = Session.StopReason or "completed",
        duration = relativeTime(),
        records = #Report.records,
        bytesApprox = Session.EstimatedBytes,
    }, true)

    updateScanUI()
end

local function startTestsWorker()
    if Session.TestsRunning then
        return
    end

    task.spawn(function()
        local ok, err = pcall(function()
            TestLab:Run()
        end)

        if not ok then
            logError("TestLab", err)
            Session.TestsRunning = false
            disconnectTestConnections()
        end

        finalizeSession()
    end)
end

local function startScanWorker()
    if Session.ScanRunning then
        return
    end

    task.spawn(function()
        local ok, err = pcall(function()
            MappingEngine:Run()
        end)

        if not ok then
            logError("MappingEngine", err)
            Session.ScanRunning = false

            if not Session.StopRequested then
                Session.StopRequested = true
                Session.StopReason = "scan_error"
            end
        end

        finalizeSession()
    end)
end

local function startFullSession()
    if Session.Running or Upload.Running then
        return
    end

    resetSession()

    Session.Running = true
    Session.StartedAtClock = os.clock()
    Session.StartedAtUnix = os.time()
    Session.RunId = HttpService:GenerateGUID(false)

    Report.meta = {
        scanner = CONFIG.VERSION,
        runId = Session.RunId,
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = safeCall(function()
            return game.PlaceVersion
        end, nil),
        clientVisibleOnly = true,
        startedAt = Session.StartedAtUnix,
    }

    addRecord("session", "started", {
        runId = Session.RunId,
        mode = "scan_and_tests",
    })

    -- IMPORTANTE: os dois são iniciados juntos.
    startTestsWorker()
    startScanWorker()

    updateScanUI()
end

local function startTestsOnly()
    if Session.Running or Upload.Running then
        return
    end

    resetSession()

    Session.Running = true
    Session.StartedAtClock = os.clock()
    Session.StartedAtUnix = os.time()
    Session.RunId = HttpService:GenerateGUID(false)

    Report.meta = {
        scanner = CONFIG.VERSION,
        runId = Session.RunId,
        placeId = game.PlaceId,
        gameId = game.GameId,
        clientVisibleOnly = true,
        startedAt = Session.StartedAtUnix,
        testOnly = true,
    }

    addRecord("session", "started", {
        runId = Session.RunId,
        mode = "tests_only",
    })

    startTestsWorker()
    updateScanUI()
end

local function stopEverything()
    if Session.Running and not Session.StopRequested then
        Session.StopRequested = true
        Session.StopReason = "manual"

        addRecord("session", "stop_requested", {
            reason = "manual",
        }, true)

        disconnectTestConnections()

        -- NÃO força flags dos workers para false aqui.
        -- Eles encerram cooperativamente e finalizeSession espera os dois.
        updateScanUI()
    end

    if Upload.Running and not Upload.CancelRequested then
        Upload.CancelRequested = true
        setUploadStatus("Cancelando upload...")
        cancelUpload()
    end
end

ScanButton.Activated:Connect(function()
    startFullSession()
end)

TestsButton.Activated:Connect(function()
    startTestsOnly()
end)

SendButton.Activated:Connect(function()
    if Upload.Running then
        return
    end

    task.spawn(function()
        local ok, result = uploadReport()
        if not ok then
            setUploadStatus("Erro: " .. tostring(result))
        end
    end)
end)

StopButton.Activated:Connect(function()
    stopEverything()
end)

local dragging = false
local dragStart
local startPosition

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
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

    if not dragStart or not startPosition then
        return
    end

    local delta = input.Position - dragStart

    Main.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = false
    end
end)

updateScanUI()
setUploadStatus("Aguardando envio")
updateUploadUI()

print("[CAFEÍNA] Mapping Engine V1.1 carregado.")
