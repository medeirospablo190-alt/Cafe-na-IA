--==============================================================
-- CAFEÍNA • MAPPING ENGINE + TEST LAB + UPLOADER
-- V1.2 • CLIENT-VISIBLE ONLY
--
-- V1.2:
-- • INICIAR SCAN inicia scan + testes juntos
-- • TestLab passivo e orientado a eventos relevantes
-- • Observa mudanças de Values/atributos, criação/remoção e eventos recebidos
-- • Prioridade extra para ReplicatedStorage.GameStuff e sistemas conhecidos
-- • Menos ruído de Pose/Keyframe/IntValue repetitivo
-- • Estatísticas de coleta e upload separadas
-- • Upload calcula total de chunks/bytes antes de enviar
-- • PARAR TUDO preserva a coleta para ENVIAR TUDO, mas zera os stats visuais
-- • Limite lógico aproximado de 150 MB
--==============================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "MAPPING_V1_3",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    UPLOAD_TOKEN = "",

    MAX_TOTAL_BYTES = 150 * 1024 * 1024,
    TARGET_CHUNK_BYTES = 3200000,

    YIELD_EVERY = 100,
    RETRIES = 3,
    RETRY_DELAY = 1.25,

    TEST_ATTRIBUTE_POLL = 0.75,
    MAX_TRACKED_VALUES = 1800,
    MAX_TRACKED_ATTRIBUTES = 900,
    MAX_REMOTE_OBSERVERS = 250,
    MAX_DYNAMIC_EVENTS = 6000,
    MAX_ARG_DEPTH = 3,
    MAX_ARG_ITEMS = 40,

    SERVICES = {
        {name = "ReplicatedStorage", budget = 36000},
        {name = "ReplicatedFirst", budget = 8000},
        {name = "StarterPlayer", budget = 16000},
        {name = "StarterGui", budget = 15000},
        {name = "Players", budget = 16000},
        {name = "Lighting", budget = 4000},
        {name = "Teams", budget = 2500},
        {name = "SoundService", budget = 5000},
        {name = "Workspace", budget = 28000},
    },

    CLASS_LIMITS = {
        Pose = 12,
        Keyframe = 12,
        Texture = 100,
        Decal = 100,
        SurfaceAppearance = 70,
        ParticleEmitter = 120,
        Trail = 70,
        Beam = 70,
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
        NumberValue = true,
        Tool = true,
        ProximityPrompt = true,
        Configuration = true,
    },

    CRITICAL_PATH_HINTS = {
        "replicatedstorage.gamestuff",
        "iteminfo",
        "craftinginfo",
        "deconstructinfo",
        "upgradesinfo",
        "remotes",
        "modules",
        "playerstats",
        "characterhandler",
        "charactermobility",
        "limbhealth",
        ".stats",
        ".items",
        "workspace.misc.ai.chain",
        "shopuihandler",
        "workbench",
        "deconstructor",
        "quest",
        "dialogue",
        "objective",
    },

    NAME_KEYWORDS = {
        "remote","network","damage","inflict","bullet","shell","hit","mag",
        "quest","dialogue","objective","party","receiver","sendserver","clientfx","fxclient",
        "item","weapon","gun","ammo","reserve","inventory","equip","reload",
        "combat","parry","clash","stun","stagger","deflect","choke","blood",
        "health","limb","stamina","sanity","alive","damageDealt",
        "craft","workbench","deconstruct","upgrade","scrap","artifact","loot","shop",
        "npc","chain","alert","anger","enraged","charging","trapped","phase",
        "path","track","character","playerstats","state","ending","bloodmoon",
    },
}

--==============================================================
-- EXECUTOR HTTP DETECTION
--==============================================================

local function getGlobal(name)
    local env = nil
    pcall(function()
        if typeof(getgenv) == "function" then
            env = getgenv()
        end
    end)

    if type(env) == "table" then
        local value = rawget(env, name)
        if value ~= nil then
            return value
        end
    end

    return rawget(_G, name)
end

local function getExecutorRequest()
    local r = getGlobal("request")
    if typeof(r) == "function" then return r end

    r = getGlobal("http_request")
    if typeof(r) == "function" then return r end

    local h = getGlobal("http")
    if type(h) == "table" and typeof(h.request) == "function" then
        return h.request
    end

    local s = getGlobal("syn")
    if type(s) == "table" and typeof(s.request) == "function" then
        return s.request
    end

    return nil
end

local ExecutorRequest = getExecutorRequest()

--==============================================================
-- STATE
--==============================================================

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

    EstimatedBytes = 2,
    ObjectsScanned = 0,
    ServicesDone = 0,
    ServicesTotal = #CONFIG.SERVICES,
    CurrentService = "",

    -- stats visuais podem ser zerados sem apagar o relatório
    VisualStatsCleared = false,
}

local Upload = {
    Running = false,
    CancelRequested = false,
    UploadId = nil,
    ChunksSent = 0,
    BytesSent = 0,
    TotalBytes = 0,
    CurrentChunk = 0,
    TotalChunks = 0,
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
local SeenDynamicSignatures = {}
local DynamicEventCount = 0
local UI = {}

--==============================================================
-- HELPERS
--==============================================================

local function safeCall(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback
end

local function safeFullName(inst)
    if not inst then return nil end
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
    if Session.StartedAtClock <= 0 then return 0 end
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
        return {type="Instance", path=safeFullName(value), className=value.ClassName}
    elseif t == "Vector3" then
        return {type="Vector3", x=value.X, y=value.Y, z=value.Z}
    elseif t == "Vector2" then
        return {type="Vector2", x=value.X, y=value.Y}
    elseif t == "Color3" then
        return {type="Color3", r=value.R, g=value.G, b=value.B}
    elseif t == "CFrame" then
        local p = value.Position
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z}
    elseif t == "number" or t == "string" or t == "boolean" or value == nil then
        return value
    end

    return tostring(value)
end

local function serializeArgs(value, depth, visited)
    depth = depth or 0
    visited = visited or {}

    if depth > CONFIG.MAX_ARG_DEPTH then
        return "<depth-limit>"
    end

    local t = typeof(value)
    if t == "table" then
        if visited[value] then return "<cycle>" end
        visited[value] = true

        local out = {}
        local n = 0
        for k, v in pairs(value) do
            n += 1
            if n > CONFIG.MAX_ARG_ITEMS then
                out["__truncated"] = true
                break
            end
            out[tostring(k)] = serializeArgs(v, depth + 1, visited)
        end
        visited[value] = nil
        return out
    end

    return serializeValue(value)
end

local function estimateRecordSize(record)
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, record)
    return ok and #encoded or 0
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

    local recordBytes = estimateRecordSize(record)
    local separatorBytes = (#Report.records > 0) and 1 or 0
    local projected = Session.EstimatedBytes + separatorBytes + recordBytes

    if not allowAfterStop and projected > CONFIG.MAX_TOTAL_BYTES then
        Session.StopRequested = true
        Session.StopReason = "size_limit"
        return false
    end

    table.insert(Report.records, record)
    Session.EstimatedBytes = projected

    local counters = Report.diagnostics.counters
    counters.total += 1
    if counters[source] ~= nil then
        counters[source] += 1
    end

    return true
end

local function logError(systemName, err)
    local item = {system=tostring(systemName), error=tostring(err)}
    table.insert(Report.diagnostics.errors, item)
    addRecord("diagnostic", "error", item, true)
end

local function shouldContinue()
    return Session.Running
        and not Session.StopRequested
        and Session.EstimatedBytes < CONFIG.MAX_TOTAL_BYTES
end

local function pathHasHint(path)
    local lower = string.lower(path or "")
    for _, hint in ipairs(CONFIG.CRITICAL_PATH_HINTS) do
        if string.find(lower, hint, 1, true) then
            return true
        end
    end
    return false
end

local function keywordScore(text)
    local lower = string.lower(text or "")
    local score = 0
    for _, keyword in ipairs(CONFIG.NAME_KEYWORDS) do
        if string.find(lower, string.lower(keyword), 1, true) then
            score += 1
        end
    end
    return score
end

local function relevanceScore(inst)
    local score = 0
    local className = inst.ClassName
    local path = safeFullName(inst) or ""

    if CONFIG.HIGH_PRIORITY_CLASSES[className] then score += 100 end
    if pathHasHint(path) then score += 180 end
    if inst:IsA("Tool") then score += 80 end
    if inst:IsA("ObjectValue") then score += 60 end
    if inst:IsA("ProximityPrompt") then score += 70 end
    if next(safeAttributes(inst)) ~= nil then score += 30 end

    score += keywordScore(inst.Name) * 25
    score += keywordScore(path) * 8

    -- IntValue só ganha prioridade real quando o nome/caminho é útil.
    if className == "IntValue" and score < 70 then
        score -= 60
    end

    return score
end

local function canCollectClass(inst)
    local limit = CONFIG.CLASS_LIMITS[inst.ClassName]
    if not limit then return true end
    ClassCounters[inst.ClassName] = (ClassCounters[inst.ClassName] or 0) + 1
    return ClassCounters[inst.ClassName] <= limit
end

local function shouldKeepStatic(inst, score)
    local className = inst.ClassName

    if className == "Pose" or className == "Keyframe" then
        return false
    end

    if className == "IntValue" and score < 55 then
        return false
    end

    if className == "Folder" or className == "Model" then
        return score >= 25 or pathHasHint(safeFullName(inst))
    end

    return score >= 0
end

local function serializeInstance(inst, serviceName, knownScore)
    local data = {
        service = serviceName,
        name = tostring(inst.Name),
        className = tostring(inst.ClassName),
        path = safeFullName(inst),
        parentPath = inst.Parent and safeFullName(inst.Parent) or nil,
        relevance = knownScore or relevanceScore(inst),
        attributes = safeAttributes(inst),
        childCount = safeCall(function() return #inst:GetChildren() end, 0),
    }

    if inst:IsA("ValueBase") then
        data.value = serializeValue(safeCall(function() return inst.Value end, nil))
    end

    if inst:IsA("ObjectValue") then
        local target = safeCall(function() return inst.Value end, nil)
        if target then
            data.reference = {
                targetPath = safeFullName(target),
                targetClass = target.ClassName,
            }
        end
    end

    local className = inst.ClassName
    if className == "RemoteEvent" or className == "RemoteFunction" or className == "UnreliableRemoteEvent" then
        data.remote = {type=className, path=safeFullName(inst)}
    end

    if inst:IsA("LuaSourceContainer") then
        data.script = {type=className, path=safeFullName(inst)}
    end

    if inst:IsA("Tool") then
        data.tool = {
            requiresHandle = safeCall(function() return inst.RequiresHandle end, nil),
            canBeDropped = safeCall(function() return inst.CanBeDropped end, nil),
        }
    end

    if inst:IsA("ProximityPrompt") then
        data.prompt = {
            actionText = safeCall(function() return inst.ActionText end, ""),
            objectText = safeCall(function() return inst.ObjectText end, ""),
            holdDuration = safeCall(function() return inst.HoldDuration end, 0),
            maxActivationDistance = safeCall(function() return inst.MaxActivationDistance end, 0),
        }
    end

    if inst:IsA("Humanoid") then
        data.humanoid = {
            health = safeCall(function() return inst.Health end, nil),
            maxHealth = safeCall(function() return inst.MaxHealth end, nil),
            walkSpeed = safeCall(function() return inst.WalkSpeed end, nil),
            jumpPower = safeCall(function() return inst.JumpPower end, nil),
        }
    end

    return data
end

--==============================================================
-- UI
--==============================================================

local COLORS = {
    BG = Color3.fromRGB(14,14,17),
    PANEL = Color3.fromRGB(22,22,27),
    PANEL2 = Color3.fromRGB(31,31,38),
    RED = Color3.fromRGB(225,42,55),
    RED_DARK = Color3.fromRGB(120,24,33),
    TEXT = Color3.fromRGB(245,245,248),
    SUB = Color3.fromRGB(170,170,180),
    GREEN = Color3.fromRGB(65,205,115),
    YELLOW = Color3.fromRGB(235,180,55),
    ORANGE = Color3.fromRGB(245,130,55),
}

local function create(className, props)
    local object = Instance.new(className)
    for k, v in pairs(props or {}) do object[k] = v end
    return object
end

local function corner(parent, radius)
    return create("UICorner", {CornerRadius=UDim.new(0, radius or 8), Parent=parent})
end

local GuiParent = nil
if typeof(gethui) == "function" then
    GuiParent = safeCall(gethui, nil)
end

local Gui = create("ScreenGui", {
    Name = "CafeinaMappingV12",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local parented = false
if GuiParent then parented = pcall(function() Gui.Parent = GuiParent end) end
if not parented then parented = pcall(function() Gui.Parent = CoreGui end) end
if not parented then Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

for _, old in ipairs(Gui.Parent:GetChildren()) do
    if old ~= Gui and old.Name == Gui.Name then old:Destroy() end
end

local Main = create("Frame", {
    Size = UDim2.fromOffset(372, 456),
    AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.fromScale(0.5,0.5),
    BackgroundColor3 = COLORS.BG,
    BorderSizePixel = 0,
    Parent = Gui,
})
corner(Main, 14)

local Header = create("Frame", {
    Size = UDim2.new(1,0,0,56),
    BackgroundColor3 = COLORS.PANEL,
    BorderSizePixel = 0,
    Parent = Main,
})
corner(Header, 14)

create("TextLabel", {
    Position=UDim2.fromOffset(14,7), Size=UDim2.new(1,-28,0,22),
    BackgroundTransparency=1, Text="CAFEÍNA • MAPPING V1.2",
    TextColor3=COLORS.TEXT, Font=Enum.Font.GothamBold, TextSize=15,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=Header,
})

create("TextLabel", {
    Position=UDim2.fromOffset(14,30), Size=UDim2.new(1,-28,0,16),
    BackgroundTransparency=1, Text="SCAN + TEST LAB • CLIENT-VISIBLE • 150 MB",
    TextColor3=COLORS.SUB, Font=Enum.Font.Gotham, TextSize=9,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=Header,
})

local function makeButton(text, x, y, width, color)
    local b = create("TextButton", {
        Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(width,42),
        BackgroundColor3=color, BorderSizePixel=0, Text=text,
        TextColor3=COLORS.TEXT, Font=Enum.Font.GothamBold, TextSize=10,
        AutoButtonColor=true, Parent=Main,
    })
    corner(b, 8)
    return b
end

local ScanButton = makeButton("INICIAR SCAN", 12, 68, 170, COLORS.RED)
local TestsButton = makeButton("INICIAR TESTES", 190, 68, 170, COLORS.RED_DARK)
local SendButton = makeButton("ENVIAR TUDO", 12, 118, 170, COLORS.RED_DARK)
local StopButton = makeButton("PARAR TUDO", 190, 118, 170, Color3.fromRGB(95,26,32))

--==============================================================
-- MINIMIZAR / RESTAURAR
--==============================================================

local miniMoved = false

local MinimizeButton = create("TextButton", {
    Position = UDim2.new(1, -42, 0, 10),
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = COLORS.PANEL2,
    BorderSizePixel = 0,
    Text = "—",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    Parent = Header,
})
corner(MinimizeButton, 8)

local MiniButton = create("TextButton", {
    Visible = false,
    Size = UDim2.fromOffset(54, 54),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = COLORS.RED,
    BorderSizePixel = 0,
    Text = "C",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBlack,
    TextSize = 20,
    Parent = Gui,
})
corner(MiniButton, 99)

MinimizeButton.Activated:Connect(function()
    Main.Visible = false
    MiniButton.Visible = true
end)

MiniButton.Activated:Connect(function()
    if miniMoved then
        miniMoved = false
        return
    end

    MiniButton.Visible = false
    Main.Visible = true
end)

local function makeStatusPanel(title, y)
    local panel = create("Frame", {
        Position=UDim2.fromOffset(12,y), Size=UDim2.new(1,-24,0,118),
        BackgroundColor3=COLORS.PANEL, BorderSizePixel=0, Parent=Main,
    })
    corner(panel, 10)

    create("TextLabel", {
        Position=UDim2.fromOffset(11,7), Size=UDim2.new(1,-22,0,18),
        BackgroundTransparency=1, Text=title, TextColor3=COLORS.TEXT,
        Font=Enum.Font.GothamBold, TextSize=10,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=panel,
    })

    local status = create("TextLabel", {
        Position=UDim2.fromOffset(11,29), Size=UDim2.new(1,-22,0,18),
        BackgroundTransparency=1, Text="Pronto", TextColor3=COLORS.SUB,
        Font=Enum.Font.Gotham, TextSize=9,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=panel,
    })

    local detail = create("TextLabel", {
        Position=UDim2.fromOffset(11,49), Size=UDim2.new(1,-22,0,18),
        BackgroundTransparency=1, Text="0 registros • 0 B", TextColor3=COLORS.SUB,
        Font=Enum.Font.Gotham, TextSize=9,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=panel,
    })

    local detail2 = create("TextLabel", {
        Position=UDim2.fromOffset(11,68), Size=UDim2.new(1,-22,0,18),
        BackgroundTransparency=1, Text="Aguardando", TextColor3=COLORS.SUB,
        Font=Enum.Font.Gotham, TextSize=8,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=panel,
    })

    local bg = create("Frame", {
        Position=UDim2.new(0,11,1,-20), Size=UDim2.new(1,-22,0,7),
        BackgroundColor3=COLORS.PANEL2, BorderSizePixel=0, Parent=panel,
    })
    corner(bg, 99)

    local fill = create("Frame", {
        Size=UDim2.new(0,0,1,0), BackgroundColor3=COLORS.RED,
        BorderSizePixel=0, Parent=bg,
    })
    corner(fill, 99)

    return {Status=status, Detail=detail, Detail2=detail2, Fill=fill}
end

UI.Scan = makeStatusPanel("COLETA", 172)
UI.Upload = makeStatusPanel("ENVIO AO SITE", 298)

UI.Link = create("TextLabel", {
    Position=UDim2.fromOffset(12,425), Size=UDim2.new(1,-24,0,22),
    BackgroundTransparency=1, Text="Link: nenhum upload concluído",
    TextColor3=COLORS.SUB, Font=Enum.Font.Code, TextSize=8,
    TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
    Parent=Main,
})

local function tweenProgress(fill, value)
    value = math.clamp(tonumber(value) or 0, 0, 1)
    TweenService:Create(fill, TweenInfo.new(0.12), {
        Size=UDim2.new(value,0,1,0)
    }):Play()
end

local function updateButtons()
    ScanButton.Text = Session.Running and "SCAN ATIVO" or "INICIAR SCAN"
    TestsButton.Text = Session.TestsRunning and "TESTES ATIVOS" or "INICIAR TESTES"
    SendButton.Text = Upload.Running and "ENVIANDO..." or "ENVIAR TUDO"
end

local function clearCollectionVisualStats()
    Session.VisualStatsCleared = true
    UI.Scan.Status.Text = "Parado • stats limpos"
    UI.Scan.Detail.Text = "0 registros • 0 B / 150 MB"
    UI.Scan.Detail2.Text = "0 objetos • 0 serviços"
    tweenProgress(UI.Scan.Fill, 0)
end

local function updateScanUI()
    updateButtons()

    if Session.VisualStatsCleared then
        return
    end

    local progress = math.clamp(Session.EstimatedBytes / CONFIG.MAX_TOTAL_BYTES, 0, 1)
    tweenProgress(UI.Scan.Fill, progress)

    if Session.ScanRunning and Session.TestsRunning then
        UI.Scan.Status.Text = "Scan + TestLab • " .. tostring(Session.CurrentService)
    elseif Session.ScanRunning then
        UI.Scan.Status.Text = "Scan • " .. tostring(Session.CurrentService)
    elseif Session.TestsRunning then
        UI.Scan.Status.Text = "TestLab ativo"
    elseif Session.Finalized then
        UI.Scan.Status.Text = "Coleta finalizada • " .. tostring(Session.StopReason or "concluído")
    elseif Session.StopRequested then
        UI.Scan.Status.Text = "Finalizando parada..."
    else
        UI.Scan.Status.Text = "Pronto"
    end

    UI.Scan.Detail.Text =
        tostring(#Report.records) .. " registros • "
        .. formatBytes(Session.EstimatedBytes) .. " / 150 MB"

    UI.Scan.Detail2.Text =
        tostring(Session.ObjectsScanned) .. " objetos • "
        .. tostring(Session.ServicesDone) .. "/" .. tostring(Session.ServicesTotal) .. " serviços • "
        .. "T:" .. tostring(Report.diagnostics.counters.tests)
end

local function setUploadStatus(text)
    UI.Upload.Status.Text = tostring(text or "")
end

local function updateUploadUI()
    updateButtons()

    local progress = 0
    if Upload.TotalBytes > 0 then
        progress = math.clamp(Upload.BytesSent / Upload.TotalBytes, 0, 1)
    end
    tweenProgress(UI.Upload.Fill, progress)

    UI.Upload.Detail.Text =
        tostring(Upload.CurrentChunk) .. "/" .. tostring(Upload.TotalChunks)
        .. " chunks • " .. formatBytes(Upload.BytesSent)
        .. " / " .. formatBytes(Upload.TotalBytes)

    UI.Upload.Detail2.Text = Upload.UploadId
        and ("uploadId: " .. tostring(Upload.UploadId))
        or "Aguardando envio"
end

--==============================================================
-- CONNECTIONS / TEST LAB
--==============================================================

local function disconnectTestConnections()
    for _, c in ipairs(TestConnections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(TestConnections)
    Session.ObserversRunning = false
end

local function addConnection(connection)
    if connection then
        TestConnections[#TestConnections + 1] = connection
    end
end

local function snapshotValue(inst)
    return serializeValue(safeCall(function() return inst.Value end, nil))
end

local function encodeComparable(value)
    return safeCall(function() return HttpService:JSONEncode(value) end, tostring(value))
end

local function isInterestingDynamic(inst)
    local score = relevanceScore(inst)
    if CONFIG.HIGH_PRIORITY_CLASSES[inst.ClassName] then return true end
    if pathHasHint(safeFullName(inst)) then return true end
    return score >= 80
end

local TestLab = {}

function TestLab:BuildWatchSet()
    local roots = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
        workspace,
    }

    local valueCandidates = {}
    local attrCandidates = {}
    local remoteCandidates = {}

    for _, root in ipairs(roots) do
        if not shouldContinue() then break end

        local descendants = safeCall(function() return root:GetDescendants() end, {})
        for i, inst in ipairs(descendants) do
            if not shouldContinue() then break end

            local score = relevanceScore(inst)

            if inst:IsA("ValueBase") and score >= 50 then
                valueCandidates[#valueCandidates + 1] = {inst=inst, score=score}
            end

            if next(safeAttributes(inst)) ~= nil and score >= 60 then
                attrCandidates[#attrCandidates + 1] = {inst=inst, score=score}
            end

            if inst.ClassName == "RemoteEvent" or inst.ClassName == "UnreliableRemoteEvent" then
                remoteCandidates[#remoteCandidates + 1] = {inst=inst, score=score}
            end

            if i % 180 == 0 then task.wait() end
        end
    end

    table.sort(valueCandidates, function(a,b) return a.score > b.score end)
    table.sort(attrCandidates, function(a,b) return a.score > b.score end)
    table.sort(remoteCandidates, function(a,b) return a.score > b.score end)

    local trackedValues = 0
    for i = 1, math.min(#valueCandidates, CONFIG.MAX_TRACKED_VALUES) do
        local candidate = valueCandidates[i]
        local inst = candidate.inst
        local candidateScore = candidate.score
        TrackedValues[inst] = snapshotValue(inst)
        trackedValues += 1

        local ok, connection = pcall(function()
            return inst.Changed:Connect(function(newValue)
                if not shouldContinue() then return end
                local before = TrackedValues[inst]
                local after = serializeValue(newValue)
                if encodeComparable(before) ~= encodeComparable(after) then
                    addRecord("tests", "value_changed", {
                        path=safeFullName(inst), className=inst.ClassName,
                        before=before, after=after, relevance=candidateScore,
                    })
                    TrackedValues[inst] = after
                    updateScanUI()
                end
            end)
        end)
        if ok then addConnection(connection) end
    end

    local trackedAttrs = 0
    for i = 1, math.min(#attrCandidates, CONFIG.MAX_TRACKED_ATTRIBUTES) do
        local inst = attrCandidates[i].inst
        TrackedAttributes[inst] = safeAttributes(inst)
        trackedAttrs += 1
    end

    local remoteObservers = 0
    for i = 1, math.min(#remoteCandidates, CONFIG.MAX_REMOTE_OBSERVERS) do
        local candidate = remoteCandidates[i]
        local remote = candidate.inst
        local candidateScore = candidate.score
        local ok, connection = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                if not shouldContinue() then return end

                local args = table.pack(...)
                local serialized = {}
                for n = 1, math.min(args.n, CONFIG.MAX_ARG_ITEMS) do
                    serialized[n] = serializeArgs(args[n])
                end

                addRecord("tests", "remote_received", {
                    path=safeFullName(remote),
                    className=remote.ClassName,
                    relevance=candidateScore,
                    argc=args.n,
                    args=serialized,
                })
                updateScanUI()
            end)
        end)
        if ok then
            addConnection(connection)
            remoteObservers += 1
        end
    end

    addRecord("tests", "watch_set_ready", {
        values=trackedValues,
        attributes=trackedAttrs,
        remoteObservers=remoteObservers,
    })
end

function TestLab:StartDynamicObservers()
    local roots = {
        workspace,
        game:GetService("ReplicatedStorage"),
        game:GetService("Players"),
    }

    for _, root in ipairs(roots) do
        addConnection(root.DescendantAdded:Connect(function(inst)
            if not shouldContinue() or DynamicEventCount >= CONFIG.MAX_DYNAMIC_EVENTS then return end
            if not isInterestingDynamic(inst) then return end

            local signature = inst.ClassName .. "|" .. tostring(inst.Name) .. "|" .. tostring(inst.Parent and inst.Parent.Name or "")
            local seen = SeenDynamicSignatures[signature] or 0
            SeenDynamicSignatures[signature] = seen + 1

            -- registra primeiras ocorrências e depois apenas marcos para reduzir ruído
            if seen < 3 or (seen + 1) % 25 == 0 then
                DynamicEventCount += 1
                addRecord("tests", "object_created", {
                    path=safeFullName(inst), className=inst.ClassName,
                    name=inst.Name, signature=signature, occurrence=seen+1,
                    relevance=relevanceScore(inst),
                })
                updateScanUI()
            end
        end))

        addConnection(root.DescendantRemoving:Connect(function(inst)
            if not shouldContinue() or DynamicEventCount >= CONFIG.MAX_DYNAMIC_EVENTS then return end
            if not isInterestingDynamic(inst) then return end
            DynamicEventCount += 1
            addRecord("tests", "object_removed", {
                path=safeFullName(inst), className=inst.ClassName,
                name=inst.Name, relevance=relevanceScore(inst),
            })
            updateScanUI()
        end))
    end

    Session.ObserversRunning = true
    addRecord("tests", "dynamic_observers_started", {})
end

function TestLab:PollAttributes()
    local cycle = 0

    while shouldContinue() do
        cycle += 1

        for inst, before in pairs(TrackedAttributes) do
            if not shouldContinue() then break end

            if inst and inst.Parent then
                local after = safeAttributes(inst)
                if encodeComparable(before) ~= encodeComparable(after) then
                    addRecord("tests", "attributes_changed", {
                        path=safeFullName(inst), before=before, after=after,
                        relevance=relevanceScore(inst),
                    })
                    TrackedAttributes[inst] = after
                    updateScanUI()
                end
            else
                TrackedAttributes[inst] = nil
            end
        end

        if cycle % 8 == 0 then
            addRecord("tests", "observation_heartbeat", {
                cycle=cycle,
                dynamicEvents=DynamicEventCount,
            })
        end

        task.wait(CONFIG.TEST_ATTRIBUTE_POLL)
    end
end

function TestLab:Run()
    Session.TestsRunning = true
    addRecord("tests", "test_lab_started", {})
    updateScanUI()

    self:BuildWatchSet()
    if shouldContinue() then self:StartDynamicObservers() end
    if shouldContinue() then self:PollAttributes() end

    disconnectTestConnections()
    Session.TestsRunning = false
    addRecord("tests", "test_lab_finished", {
        dynamicEvents=DynamicEventCount,
    }, true)
    updateScanUI()
end

--==============================================================
-- MAPPING ENGINE
--==============================================================

local MappingEngine = {}

function MappingEngine:Run()
    Session.ScanRunning = true
    addRecord("scan", "mapping_started", {})
    updateScanUI()

    for serviceIndex, info in ipairs(CONFIG.SERVICES) do
        if not shouldContinue() then break end

        Session.CurrentService = info.name
        updateScanUI()

        local service = safeCall(function() return game:GetService(info.name) end, nil)
        if service then
            local descendants = safeCall(function() return service:GetDescendants() end, {})
            local candidates = {}

            for index, inst in ipairs(descendants) do
                if not shouldContinue() then break end

                if canCollectClass(inst) then
                    local score = relevanceScore(inst)
                    if shouldKeepStatic(inst, score) then
                        candidates[#candidates + 1] = {instance=inst, score=score}
                    end
                end

                if index % CONFIG.YIELD_EVERY == 0 then task.wait() end
            end

            table.sort(candidates, function(a,b)
                if a.score == b.score then
                    return safeFullName(a.instance) < safeFullName(b.instance)
                end
                return a.score > b.score
            end)

            local collected = 0
            for index, candidate in ipairs(candidates) do
                if not shouldContinue() or collected >= info.budget then break end

                local ok, record = pcall(serializeInstance, candidate.instance, info.name, candidate.score)
                if ok and type(record) == "table" then
                    if not addRecord("scan", "object", record) then break end
                    collected += 1
                    Session.ObjectsScanned += 1
                end

                if index % CONFIG.YIELD_EVERY == 0 then
                    updateScanUI()
                    task.wait()
                end
            end

            addRecord("scan", "service_summary", {
                service=info.name,
                descendants=#descendants,
                candidates=#candidates,
                collected=collected,
            })
        end

        Session.ServicesDone = serviceIndex
        updateScanUI()
        task.wait()
    end

    Session.ScanRunning = false
    addRecord("scan", "mapping_finished", {
        objects=Session.ObjectsScanned,
        services=Session.ServicesDone,
    }, true)

    if not Session.StopRequested then
        Session.StopRequested = true
        Session.StopReason = "scan_completed"
    end

    updateScanUI()
end

--==============================================================
-- HTTP / UPLOAD
--==============================================================

local function decodeResponse(response)
    if type(response) == "string" then
        return safeCall(function() return HttpService:JSONDecode(response) end, nil)
    end

    if type(response) ~= "table" then return nil end
    local body = response.Body or response.body or response.ResponseBody
    if type(body) ~= "string" then return nil end
    return safeCall(function() return HttpService:JSONDecode(body) end, nil)
end

local function rawRequest(url, payload)
    local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then return false, "Erro ao codificar JSON" end

    if ExecutorRequest then
        local ok, response = pcall(function()
            return ExecutorRequest({
                Url=url,
                Method="POST",
                Headers={
                    ["Content-Type"]="application/json",
                    ["Accept"]="application/json",
                },
                Body=body,
            })
        end)

        if not ok then return false, tostring(response) end

        local status = type(response) == "table" and tonumber(
            response.StatusCode or response.Status or response.status
        ) or nil
        local decoded = decodeResponse(response)

        if status and (status < 200 or status >= 300) then
            return false, decoded and (decoded.message or decoded.error) or ("HTTP " .. tostring(status))
        end

        if not decoded then return false, "Resposta inválida do servidor" end
        return true, decoded
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url=url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
                ["Accept"]="application/json",
            },
            Body=body,
        })
    end)

    if not ok then return false, tostring(response) end
    local decoded = decodeResponse(response)
    if not response.Success then
        return false, decoded and (decoded.message or decoded.error) or ("HTTP " .. tostring(response.StatusCode))
    end
    if not decoded then return false, "Resposta inválida do servidor" end
    return true, decoded
end

local function withToken(payload)
    if CONFIG.UPLOAD_TOKEN ~= "" then payload.token = CONFIG.UPLOAD_TOKEN end
    return payload
end

local function requestRetry(url, payload, label)
    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.RETRIES do
        if Upload.CancelRequested then return false, "Cancelado" end

        setUploadStatus(label .. " • " .. tostring(attempt) .. "/" .. tostring(CONFIG.RETRIES))
        local ok, result = rawRequest(url, payload)
        if ok then return true, result end

        lastError = tostring(result)
        if attempt < CONFIG.RETRIES then task.wait(CONFIG.RETRY_DELAY * attempt) end
    end

    return false, lastError
end

local function cancelUpload()
    if not Upload.UploadId then return end
    local id = Upload.UploadId
    task.spawn(function()
        pcall(function()
            rawRequest(CONFIG.UPLOAD_BASE .. "/cancel", withToken({uploadId=id}))
        end)
    end)
end

local function buildUploadPlan(records, headerRecord)
    -- Calcula exatamente os bytes dos arrays JSON enviados em `objects`.
    -- Não inclui o envelope externo da requisição HTTP, pois BytesSent mede o
    -- mesmo conteúdo que flushChunk codifica: o array de objetos.
    local chunks = 0
    local totalBytes = 0

    local currentCount = 0
    local currentBytes = 2 -- []

    local function pushItemBytes(itemBytes)
        local separator = currentCount > 0 and 1 or 0

        if currentCount > 0
            and currentBytes + separator + itemBytes > CONFIG.TARGET_CHUNK_BYTES
        then
            chunks += 1
            totalBytes += currentBytes
            currentCount = 0
            currentBytes = 2
            separator = 0
        end

        currentBytes += separator + itemBytes
        currentCount += 1
    end

    if headerRecord then
        pushItemBytes(estimateRecordSize(headerRecord))
    end

    for index, record in ipairs(records) do
        pushItemBytes(estimateRecordSize(record))
        if index % 400 == 0 then task.wait() end
    end

    if currentCount > 0 then
        chunks += 1
        totalBytes += currentBytes
    end

    return chunks, totalBytes
end

local function uploadReport()
    if Upload.Running then return false, "Upload já ativo" end
    if Session.Running then return false, "Pare ou aguarde a coleta finalizar" end
    if #Report.records == 0 then return false, "Nenhum dado coletado" end

    Upload.Running = true
    Upload.CancelRequested = false
    Upload.UploadId = nil
    Upload.ChunksSent = 0
    Upload.BytesSent = 0
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0
    Upload.TotalBytes = 0

    setUploadStatus("Calculando envio...")
    updateUploadUI()

    local uploadHeader = {
        recordType="mapping_header",
        runId=Session.RunId,
        metadata={
            scanner=CONFIG.VERSION,
            clientVisibleOnly=true,
            placeId=game.PlaceId,
            gameId=game.GameId,
            placeVersion=safeCall(function() return game.PlaceVersion end, nil),
            collectedBytesApprox=Session.EstimatedBytes,
            recordCount=#Report.records,
        },
    }

    Upload.TotalChunks, Upload.TotalBytes = buildUploadPlan(Report.records, uploadHeader)
    updateUploadUI()

    local filename = "Cafeina_Mapping_" .. tostring(game.PlaceId) .. "_" .. os.date("!%Y%m%d_%H%M%S") .. ".json"

    local startOk, startResult = requestRetry(
        CONFIG.UPLOAD_BASE .. "/start",
        withToken({
            filename=filename,
            source="cafeina-mapping-engine",
            metadata={
                runId=Session.RunId,
                recordCount=#Report.records,
                clientVisibleOnly=true,
                maxBytes=CONFIG.MAX_TOTAL_BYTES,
                placeId=game.PlaceId,
                gameId=game.GameId,
                placeVersion=safeCall(function() return game.PlaceVersion end, nil),
                plannedChunks=Upload.TotalChunks,
                plannedBytesApprox=Upload.TotalBytes,
            },
        }),
        "Abrindo upload"
    )

    if not startOk or type(startResult) ~= "table" or not startResult.uploadId then
        Upload.Running = false
        setUploadStatus("Erro ao abrir upload")
        updateButtons()
        return false, startResult or "uploadId não retornado"
    end

    Upload.UploadId = tostring(startResult.uploadId)
    updateUploadUI()

    local chunk = {uploadHeader}
    local chunkBytes = 2 + estimateRecordSize(uploadHeader)

    local function flushChunk()
        if #chunk == 0 then return true end
        if Upload.CancelRequested then return false, "Cancelado" end

        local chunkIndex = Upload.ChunksSent + 1
        Upload.CurrentChunk = chunkIndex
        setUploadStatus("Enviando chunk " .. tostring(chunkIndex) .. "/" .. tostring(Upload.TotalChunks))
        updateUploadUI()

        local encodeOk, encoded = pcall(HttpService.JSONEncode, HttpService, chunk)
        if not encodeOk then return false, "Erro ao codificar chunk" end

        local ok, result = requestRetry(
            CONFIG.UPLOAD_BASE .. "/chunk",
            withToken({
                uploadId=Upload.UploadId,
                index=chunkIndex,
                objects=chunk,
            }),
            "Chunk " .. tostring(chunkIndex) .. "/" .. tostring(Upload.TotalChunks)
        )
        if not ok then return false, result end

        Upload.ChunksSent = chunkIndex
        Upload.BytesSent += #encoded
        updateUploadUI()

        chunk = {}
        chunkBytes = 2
        return true
    end

    for index, record in ipairs(Report.records) do
        if Upload.CancelRequested then
            cancelUpload()
            Upload.Running = false
            updateButtons()
            return false, "Cancelado"
        end

        local recordBytes = estimateRecordSize(record)
        local separatorBytes = #chunk > 0 and 1 or 0

        if chunkBytes + separatorBytes + recordBytes > CONFIG.TARGET_CHUNK_BYTES and #chunk > 0 then
            local ok, err = flushChunk()
            if not ok then
                cancelUpload()
                Upload.Running = false
                updateButtons()
                return false, err
            end
        end

        local separatorBytes = #chunk > 0 and 1 or 0
        chunk[#chunk + 1] = record
        chunkBytes += separatorBytes + recordBytes

        if index % 120 == 0 then task.wait() end
    end

    local okFlush, flushError = flushChunk()
    if not okFlush then
        cancelUpload()
        Upload.Running = false
        updateButtons()
        return false, flushError
    end

    setUploadStatus("Finalizando upload...")

    local finishOk, finishResult = requestRetry(
        CONFIG.UPLOAD_BASE .. "/finish",
        withToken({
            uploadId=Upload.UploadId,
            totalChunks=Upload.ChunksSent,
            summary={
                runId=Session.RunId,
                records=#Report.records,
                chunks=Upload.ChunksSent,
                bytesApprox=Upload.BytesSent,
                clientVisibleOnly=true,
                mappingEngine=true,
                testLab=true,
            },
        }),
        "Finalizando"
    )

    Upload.Running = false
    updateButtons()

    if not finishOk then
        cancelUpload()
        setUploadStatus("Erro na finalização")
        return false, finishResult
    end

    if Upload.ChunksSent ~= Upload.TotalChunks then
        setUploadStatus("Falha de integridade no envio")
        return false,
            "Chunks enviados não correspondem ao plano: "
            .. tostring(Upload.ChunksSent)
            .. "/"
            .. tostring(Upload.TotalChunks)
    end

    local url = type(finishResult) == "table" and (finishResult.downloadUrl or finishResult.url) or nil
    if url then
        Upload.LastURL = tostring(url)
        UI.Link.Text = "Link: " .. Upload.LastURL
    else
        UI.Link.Text = "Upload concluído sem URL retornada"
    end

    -- BytesSent e TotalBytes usam a mesma métrica: arrays JSON enviados em `objects`.
    Upload.CurrentChunk = Upload.ChunksSent
    tweenProgress(UI.Upload.Fill, 1)
    setUploadStatus("Upload concluído")
    updateUploadUI()
    return true, url
end

--==============================================================
-- SESSION CONTROL
--==============================================================

local function resetSessionData()
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
    Session.EstimatedBytes = 2
    Session.ObjectsScanned = 0
    Session.ServicesDone = 0
    Session.CurrentService = ""
    Session.VisualStatsCleared = false

    Report.meta = {}
    Report.records = {}
    Report.diagnostics = {
        errors={},
        counters={total=0,scan=0,tests=0,diagnostic=0,session=0},
    }

    ClassCounters = {}
    TrackedValues = {}
    TrackedAttributes = {}
    SeenDynamicSignatures = {}
    DynamicEventCount = 0

    updateScanUI()
end

local function finalizeSession()
    if Session.Finalized then return end
    if Session.ScanRunning or Session.TestsRunning then return end

    Session.Finalized = true
    Session.Running = false
    disconnectTestConnections()

    addRecord("session", "finished", {
        runId=Session.RunId,
        stopReason=Session.StopReason or "completed",
        duration=relativeTime(),
        records=#Report.records,
        bytesApprox=Session.EstimatedBytes,
    }, true)

    if not Session.VisualStatsCleared then updateScanUI() end
end

local function startTestsWorker()
    if Session.TestsRunning then return end

    task.spawn(function()
        local ok, err = pcall(function() TestLab:Run() end)
        if not ok then
            logError("TestLab", err)
            Session.TestsRunning = false
            disconnectTestConnections()
            if not Session.StopRequested then
                Session.StopRequested = true
                Session.StopReason = "test_error"
            end
        end
        finalizeSession()
    end)
end

local function startScanWorker()
    if Session.ScanRunning then return end

    task.spawn(function()
        local ok, err = pcall(function() MappingEngine:Run() end)
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

local function beginSession(mode)
    if Session.Running or Upload.Running then return false end

    resetSessionData()

    Session.Running = true
    Session.StartedAtClock = os.clock()
    Session.StartedAtUnix = os.time()
    Session.RunId = HttpService:GenerateGUID(false)

    Report.meta = {
        scanner=CONFIG.VERSION,
        runId=Session.RunId,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=safeCall(function() return game.PlaceVersion end, nil),
        clientVisibleOnly=true,
        startedAt=Session.StartedAtUnix,
        mode=mode,
    }

    addRecord("session", "started", {runId=Session.RunId, mode=mode})

    if mode == "scan_and_tests" then
        -- inicia ambos no mesmo ciclo da sessão
        startTestsWorker()
        startScanWorker()
    elseif mode == "tests_only" then
        startTestsWorker()
    end

    updateScanUI()
    return true
end

local function stopEverything()
    if Session.Running and not Session.StopRequested then
        Session.StopRequested = true
        Session.StopReason = "manual"

        -- Registro é preservado para upload posterior.
        addRecord("session", "stop_requested", {reason="manual"}, true)
        disconnectTestConnections()

        -- Requisito do menu: ao apertar PARAR, stats visuais da coleta zeram.
        clearCollectionVisualStats()
        updateButtons()
    elseif not Session.Running then
        -- também limpa a área visual se já estiver parada.
        clearCollectionVisualStats()
        updateButtons()
    end

    if Upload.Running and not Upload.CancelRequested then
        Upload.CancelRequested = true
        setUploadStatus("Cancelando upload...")
        cancelUpload()

        Upload.CurrentChunk = 0
        Upload.TotalChunks = 0
        Upload.BytesSent = 0
        Upload.TotalBytes = 0
        updateUploadUI()
    end
end

--==============================================================
-- BUTTONS
--==============================================================

ScanButton.Activated:Connect(function()
    beginSession("scan_and_tests")
end)

TestsButton.Activated:Connect(function()
    beginSession("tests_only")
end)

SendButton.Activated:Connect(function()
    if Upload.Running then return end
    task.spawn(function()
        local ok, result = uploadReport()
        if not ok then setUploadStatus("Erro: " .. tostring(result)) end
    end)
end)

StopButton.Activated:Connect(function()
    stopEverything()
end)

--==============================================================
-- MOBILE DRAG
--==============================================================

local dragging = false
local dragStart = nil
local startPosition = nil

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
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement
    then return end
    if not dragStart or not startPosition then return end

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

--==============================================================
-- READY
--==============================================================


--==============================================================
-- MINI BUTTON DRAG • MOBILE / MOUSE
--==============================================================

local miniDragging = false
local miniDragStart = nil
local miniStartPosition = nil

MiniButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        miniDragging = true
        miniMoved = false
        miniDragStart = input.Position
        miniStartPosition = MiniButton.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not miniDragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement
    then
        return
    end

    if not miniDragStart or not miniStartPosition then
        return
    end

    local delta = input.Position - miniDragStart

    if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
        miniMoved = true
    end

    MiniButton.Position = UDim2.new(
        miniStartPosition.X.Scale,
        miniStartPosition.X.Offset + delta.X,
        miniStartPosition.Y.Scale,
        miniStartPosition.Y.Offset + delta.Y
    )
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        miniDragging = false
    end
end)

updateScanUI()
setUploadStatus("Aguardando envio")
updateUploadUI()
print("[CAFEÍNA] Mapping Engine V1.3 carregado.")
