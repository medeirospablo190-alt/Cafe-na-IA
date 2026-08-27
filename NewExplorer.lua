--[[
============================================================
            CAFEÍNA SERVER SCANNER V3
        CLIENT-VISIBLE INTELLIGENCE SCANNER
============================================================

OBJETIVO:
- Mapear somente objetos visíveis ao cliente.
- NÃO invoca RemoteEvents.
- NÃO invoca RemoteFunctions.
- NÃO tenta acessar ServerStorage.
- NÃO tenta acessar ServerScriptService.
- NÃO tenta ler DataStore.
- NÃO altera dados do jogo.

RECURSOS:
- Scanner de 9 serviços
- Relatório inteligente
- Remotes classificados por prioridade
- Economia / progressão
- Armas / loadout
- Monetização / gamepasses
- Scripts / módulos
- Arquitetura provável
- Relatório bruto
- JSON completo
- Copiar seção
- Copiar tudo
- Salvar arquivo local, quando disponível
- Mobile
- Menu arrastável
- Ícone minimizado arrastável

============================================================
]]

--============================================================
-- SERVICES
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Teams = game:GetService("Teams")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--============================================================
-- CONFIG
--============================================================

local CONFIG = {
    VERSION = "V3",

    MAX_OBJECTS = 35000,
    MAX_REPORT_CHARS = 900000,
    YIELD_EVERY = 180,

    SERVICES = {
        Workspace,
        ReplicatedStorage,
        ReplicatedFirst,
        Players,
        Lighting,
        StarterGui,
        StarterPlayer,
        Teams,
        SoundService,
    },

    SKIP_CLASSES_IN_SMART_REPORT = {
        UIStroke = true,
        UICorner = true,
        UIListLayout = true,
        UIPadding = true,
        UIAspectRatioConstraint = true,
        UISizeConstraint = true,
        UIGradient = true,
        WeldConstraint = true,
        Weld = true,
        Attachment = true,
    }
}

--============================================================
-- COLORS
--============================================================

local COLORS = {
    BG = Color3.fromRGB(12, 12, 15),
    PANEL = Color3.fromRGB(20, 20, 24),
    CARD = Color3.fromRGB(27, 27, 32),

    RED = Color3.fromRGB(225, 45, 55),
    RED_DARK = Color3.fromRGB(120, 25, 32),

    TEXT = Color3.fromRGB(245, 245, 248),
    MUTED = Color3.fromRGB(155, 155, 165),

    GREEN = Color3.fromRGB(65, 210, 125),
    YELLOW = Color3.fromRGB(245, 195, 60),
    ORANGE = Color3.fromRGB(245, 135, 50),
}

--============================================================
-- STATE
--============================================================

local State = {
    scanning = false,
    cancelled = false,
    minimized = false,

    scanned = 0,
    startedAt = 0,

    records = {},
    remotes = {},
    scripts = {},
    modules = {},
    tools = {},
    values = {},
    clientData = {},
    classes = {},
    serviceCounts = {},

    reports = {},

    currentPage = "Resumo",
}

--============================================================
-- UTILS
--============================================================

local function safeCall(callback, fallback)
    local ok, result = pcall(callback)

    if ok then
        return result
    end

    return fallback
end

local function safeFullName(instance)
    return safeCall(function()
        return instance:GetFullName()
    end, instance.Name)
end

local function round(number, decimals)
    local multiplier = 10 ^ (decimals or 0)
    return math.floor(number * multiplier + 0.5) / multiplier
end

local function append(list, value)
    list[#list + 1] = value
end

local function trimText(text, maximum)
    maximum = maximum or CONFIG.MAX_REPORT_CHARS

    if #text <= maximum then
        return text
    end

    return string.sub(text, 1, maximum)
        .. "\n\n[CAFEÍNA] RELATÓRIO TRUNCADO."
end

local function copyText(text)
    if setclipboard then
        local ok = pcall(function()
            setclipboard(text)
        end)

        return ok
    end

    if toclipboard then
        local ok = pcall(function()
            toclipboard(text)
        end)

        return ok
    end

    return false
end

local function getValue(instance)
    return safeCall(function()
        if instance:IsA("StringValue")
            or instance:IsA("NumberValue")
            or instance:IsA("IntValue")
            or instance:IsA("BoolValue")
            or instance:IsA("Vector3Value")
            or instance:IsA("CFrameValue")
            or instance:IsA("Color3Value")
            or instance:IsA("ObjectValue") then

            return tostring(instance.Value)
        end

        return nil
    end, nil)
end

local function getAttributes(instance)
    return safeCall(function()
        return instance:GetAttributes()
    end, {})
end

--============================================================
-- REMOTE INTELLIGENCE
--============================================================

local HIGH_KEYWORDS = {
    "buy",
    "purchase",
    "upgrade",
    "reward",
    "cash",
    "currency",
    "case",
    "gift",
    "admin",
    "developer",
    "weaponprogression",
    "classsystem",
    "inventory",
}

local MEDIUM_KEYWORDS = {
    "equip",
    "skin",
    "attachment",
    "lobby",
    "setting",
    "loadout",
    "wheel",
}

local LOW_KEYWORDS = {
    "sound",
    "particle",
    "camera",
    "notification",
    "interface",
    "visual",
}

local function containsKeyword(text, list)
    text = string.lower(text)

    for _, keyword in ipairs(list) do
        if string.find(text, keyword, 1, true) then
            return true, keyword
        end
    end

    return false
end

local function classifyRemote(path)
    local found, reason = containsKeyword(path, HIGH_KEYWORDS)

    if found then
        return "ALTA", reason
    end

    found, reason = containsKeyword(path, MEDIUM_KEYWORDS)

    if found then
        return "MÉDIA", reason
    end

    found, reason = containsKeyword(path, LOW_KEYWORDS)

    if found then
        return "BAIXA", reason
    end

    return "DESCONHECIDA", "sem classificação automática"
end

--============================================================
-- RECORD BUILDER
--============================================================

local function buildRecord(instance, serviceName)
    local path = safeFullName(instance)

    local record = {
        service = serviceName,
        path = path,
        name = instance.Name,
        className = instance.ClassName,
        childCount = #safeCall(function()
            return instance:GetChildren()
        end, {}),

        attributes = getAttributes(instance),
    }

    local value = getValue(instance)

    if value ~= nil then
        record.value = value
    end

    if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
        local risk, reason = classifyRemote(path)

        record.remote = {
            type = instance.ClassName,
            risk = risk,
            reason = reason,
        }

        append(State.remotes, {
            path = path,
            name = instance.Name,
            type = instance.ClassName,
            risk = risk,
            reason = reason,
        })
    end

    if instance:IsA("LocalScript") then
        append(State.scripts, {
            path = path,
            type = "LocalScript",
        })
    elseif instance:IsA("Script") then
        append(State.scripts, {
            path = path,
            type = "Script",
        })
    elseif instance:IsA("ModuleScript") then
        append(State.modules, {
            path = path,
            type = "ModuleScript",
        })
    end

    if instance:IsA("Tool") then
        append(State.tools, {
            path = path,
            name = instance.Name,
        })
    end

    if value ~= nil then
        append(State.values, {
            path = path,
            name = instance.Name,
            className = instance.ClassName,
            value = value,
        })
    end

    State.classes[instance.ClassName] =
        (State.classes[instance.ClassName] or 0) + 1

    return record
end

--============================================================
-- UI
--============================================================

local existing = LocalPlayer:WaitForChild("PlayerGui")
    :FindFirstChild("CafeinaScannerV3")

if existing then
    existing:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaScannerV3"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = LocalPlayer.PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0.88, 0, 0.78, 0)
Main.Position = UDim2.new(0.06, 0, 0.11, 0)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = COLORS.RED_DARK
MainStroke.Thickness = 1
MainStroke.Parent = Main

--============================================================
-- HEADER
--============================================================

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 54)
Header.BackgroundColor3 = COLORS.PANEL
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 14)
HeaderCorner.Parent = Header

local HeaderFix = Instance.new("Frame")
HeaderFix.Size = UDim2.new(1, 0, 0, 14)
HeaderFix.Position = UDim2.new(0, 0, 1, -14)
HeaderFix.BackgroundColor3 = COLORS.PANEL
HeaderFix.BorderSizePixel = 0
HeaderFix.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 15, 0, 5)
Title.Size = UDim2.new(0.7, 0, 0, 25)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 19
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = COLORS.TEXT
Title.Text = "☕ CAFEÍNA • SERVER SCANNER"
Title.Parent = Header

local Version = Instance.new("TextLabel")
Version.BackgroundTransparency = 1
Version.Position = UDim2.new(0, 16, 0, 29)
Version.Size = UDim2.new(0.7, 0, 0, 17)
Version.Font = Enum.Font.Gotham
Version.TextSize = 11
Version.TextXAlignment = Enum.TextXAlignment.Left
Version.TextColor3 = COLORS.RED
Version.Text = "V3 • CLIENT-VISIBLE INTELLIGENCE"
Version.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.new(0, 40, 0, 34)
Minimize.Position = UDim2.new(1, -87, 0, 10)
Minimize.BackgroundColor3 = COLORS.CARD
Minimize.TextColor3 = COLORS.TEXT
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 21
Minimize.Text = "−"
Minimize.Parent = Header

Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0, 9)

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 40, 0, 34)
Close.Position = UDim2.new(1, -44, 0, 10)
Close.BackgroundColor3 = COLORS.RED_DARK
Close.TextColor3 = COLORS.TEXT
Close.Font = Enum.Font.GothamBold
Close.TextSize = 18
Close.Text = "×"
Close.Parent = Header

Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 9)

--============================================================
-- STATUS
--============================================================

local StatusFrame = Instance.new("Frame")
StatusFrame.Position = UDim2.new(0, 8, 0, 60)
StatusFrame.Size = UDim2.new(1, -16, 0, 48)
StatusFrame.BackgroundColor3 = COLORS.CARD
StatusFrame.BorderSizePixel = 0
StatusFrame.Parent = Main

Instance.new("UICorner", StatusFrame).CornerRadius = UDim.new(0, 10)

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 9, 0, 9)
StatusDot.Position = UDim2.new(0, 12, 0, 11)
StatusDot.BackgroundColor3 = COLORS.GREEN
StatusDot.BorderSizePixel = 0
StatusDot.Parent = StatusFrame

Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0, 28, 0, 4)
Status.Size = UDim2.new(1, -38, 0, 22)
Status.Font = Enum.Font.GothamMedium
Status.TextSize = 12
Status.TextColor3 = COLORS.TEXT
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "Pronto para iniciar"
Status.Parent = StatusFrame

local ProgressBack = Instance.new("Frame")
ProgressBack.Position = UDim2.new(0, 12, 0, 31)
ProgressBack.Size = UDim2.new(1, -24, 0, 6)
ProgressBack.BackgroundColor3 = COLORS.BG
ProgressBack.BorderSizePixel = 0
ProgressBack.Parent = StatusFrame

Instance.new("UICorner", ProgressBack).CornerRadius = UDim.new(1, 0)

local Progress = Instance.new("Frame")
Progress.Size = UDim2.new(0, 0, 1, 0)
Progress.BackgroundColor3 = COLORS.RED
Progress.BorderSizePixel = 0
Progress.Parent = ProgressBack

Instance.new("UICorner", Progress).CornerRadius = UDim.new(1, 0)

local function setStatus(text, color)
    Status.Text = text
    StatusDot.BackgroundColor3 = color or COLORS.YELLOW
end

local function setProgress(value)
    value = math.clamp(value, 0, 1)

    Progress.Size = UDim2.new(value, 0, 1, 0)
end

--============================================================
-- SIDEBAR
--============================================================

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Position = UDim2.new(0, 8, 0, 116)
Sidebar.Size = UDim2.new(0.30, -10, 1, -124)
Sidebar.BackgroundColor3 = COLORS.PANEL
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 3
Sidebar.ScrollBarImageColor3 = COLORS.RED
Sidebar.CanvasSize = UDim2.new()
Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
Sidebar.Parent = Main

Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)

local SidePadding = Instance.new("UIPadding")
SidePadding.PaddingTop = UDim.new(0, 8)
SidePadding.PaddingLeft = UDim.new(0, 7)
SidePadding.PaddingRight = UDim.new(0, 7)
SidePadding.PaddingBottom = UDim.new(0, 8)
SidePadding.Parent = Sidebar

local SideLayout = Instance.new("UIListLayout")
SideLayout.Padding = UDim.new(0, 6)
SideLayout.Parent = Sidebar

--============================================================
-- CONTENT
--============================================================

local Content = Instance.new("Frame")
Content.Position = UDim2.new(0.30, 5, 0, 116)
Content.Size = UDim2.new(0.70, -13, 1, -124)
Content.BackgroundColor3 = COLORS.PANEL
Content.BorderSizePixel = 0
Content.Parent = Main

Instance.new("UICorner", Content).CornerRadius = UDim.new(0, 10)

local PageTitle = Instance.new("TextLabel")
PageTitle.BackgroundTransparency = 1
PageTitle.Position = UDim2.new(0, 12, 0, 7)
PageTitle.Size = UDim2.new(1, -24, 0, 28)
PageTitle.Text = "RESUMO"
PageTitle.Font = Enum.Font.GothamBold
PageTitle.TextSize = 16
PageTitle.TextColor3 = COLORS.TEXT
PageTitle.TextXAlignment = Enum.TextXAlignment.Left
PageTitle.Parent = Content

local Viewer = Instance.new("TextBox")
Viewer.Position = UDim2.new(0, 10, 0, 40)
Viewer.Size = UDim2.new(1, -20, 1, -95)
Viewer.BackgroundColor3 = COLORS.BG
Viewer.BorderSizePixel = 0
Viewer.TextColor3 = COLORS.TEXT
Viewer.TextSize = 12
Viewer.Font = Enum.Font.Code
Viewer.TextXAlignment = Enum.TextXAlignment.Left
Viewer.TextYAlignment = Enum.TextYAlignment.Top
Viewer.TextWrapped = false
Viewer.ClearTextOnFocus = false
Viewer.MultiLine = true
Viewer.TextEditable = false
Viewer.Text = "Execute o scanner para gerar o relatório."
Viewer.Parent = Content

Instance.new("UICorner", Viewer).CornerRadius = UDim.new(0, 8)

local ButtonBar = Instance.new("Frame")
ButtonBar.Position = UDim2.new(0, 10, 1, -48)
ButtonBar.Size = UDim2.new(1, -20, 0, 38)
ButtonBar.BackgroundTransparency = 1
ButtonBar.Parent = Content

local ButtonLayout = Instance.new("UIListLayout")
ButtonLayout.FillDirection = Enum.FillDirection.Horizontal
ButtonLayout.Padding = UDim.new(0, 6)
ButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ButtonLayout.Parent = ButtonBar

local function makeAction(text)
    local button = Instance.new("TextButton")

    button.Size = UDim2.new(0.32, -4, 1, 0)
    button.BackgroundColor3 = COLORS.CARD
    button.TextColor3 = COLORS.TEXT
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.Text = text
    button.Parent = ButtonBar

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

    return button
end

local CopySection = makeAction("📋 SEÇÃO")
local CopyAll = makeAction("📋 RELATÓRIO")
local Save = makeAction("💾 SALVAR")

--============================================================
-- PAGE SYSTEM
--============================================================

local PAGES = {
    "Resumo",
    "Inteligência",
    "Remotes",
    "Economia",
    "Armas",
    "Monetização",
    "Scripts",
    "Arquitetura",
    "Bruto",
}

local pageButtons = {}

local function refreshPage()
    PageTitle.Text = string.upper(State.currentPage)

    local report = State.reports[State.currentPage]

    if report then
        Viewer.Text = trimText(report)
    else
        Viewer.Text =
            "Nenhum relatório disponível.\n\nExecute o scanner."
    end

    for name, button in pairs(pageButtons) do
        if name == State.currentPage then
            button.BackgroundColor3 = COLORS.RED_DARK
        else
            button.BackgroundColor3 = COLORS.CARD
        end
    end
end

local function createPageButton(name)
    local button = Instance.new("TextButton")

    button.Size = UDim2.new(1, 0, 0, 36)
    button.BackgroundColor3 = COLORS.CARD
    button.TextColor3 = COLORS.TEXT
    button.Text = name
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 12
    button.Parent = Sidebar

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

    button.MouseButton1Click:Connect(function()
        State.currentPage = name
        refreshPage()
    end)

    pageButtons[name] = button
end

local StartButton = Instance.new("TextButton")
StartButton.Size = UDim2.new(1, 0, 0, 43)
StartButton.BackgroundColor3 = COLORS.RED
StartButton.TextColor3 = COLORS.TEXT
StartButton.Font = Enum.Font.GothamBold
StartButton.TextSize = 12
StartButton.Text = "🔍 INICIAR SCANNER"
StartButton.Parent = Sidebar

Instance.new("UICorner", StartButton).CornerRadius = UDim.new(0, 9)

for _, page in ipairs(PAGES) do
    createPageButton(page)
end

--============================================================
-- SMART ANALYSIS
--============================================================

local function collectPathsContaining(...)
    local terms = {...}
    local found = {}

    for _, record in ipairs(State.records) do
        local lower = string.lower(record.path)

        for _, term in ipairs(terms) do
            if string.find(
                lower,
                string.lower(term),
                1,
                true
            ) then
                append(found, record)
                break
            end
        end
    end

    return found
end

local function buildSummaryReport()
    local elapsed = os.clock() - State.startedAt

    local lines = {
        "==================================================",
        "          CAFEÍNA INTELLIGENCE REPORT",
        "==================================================",
        "",
        "MODO:",
        "  CLIENT-VISIBLE ONLY",
        "",
        "GAME:",
        "  PlaceId: " .. tostring(game.PlaceId),
        "  GameId: " .. tostring(game.GameId),
        "  PlaceVersion: " .. tostring(game.PlaceVersion),
        "",
        "SCAN:",
        "  Objetos: " .. tostring(State.scanned),
        "  Serviços: " .. tostring(#CONFIG.SERVICES),
        "  Tempo: " .. tostring(round(elapsed, 2)) .. "s",
        "",
        "DESCOBERTAS:",
        "  Remotes: " .. tostring(#State.remotes),
        "  Scripts: " .. tostring(#State.scripts),
        "  ModuleScripts: " .. tostring(#State.modules),
        "  Tools: " .. tostring(#State.tools),
        "  Values: " .. tostring(#State.values),
        "",
        "SERVIÇOS:",
    }

    for _, service in ipairs(CONFIG.SERVICES) do
        append(
            lines,
            string.format(
                "  %-20s %d",
                service.Name,
                State.serviceCounts[service.Name] or 0
            )
        )
    end

    append(lines, "")
    append(lines, "CLASSES MAIS NUMEROSAS:")

    local sorted = {}

    for className, amount in pairs(State.classes) do
        append(sorted, {
            name = className,
            amount = amount,
        })
    end

    table.sort(sorted, function(a, b)
        return a.amount > b.amount
    end)

    for index = 1, math.min(20, #sorted) do
        append(
            lines,
            string.format(
                "  %-25s %d",
                sorted[index].name,
                sorted[index].amount
            )
        )
    end

    return table.concat(lines, "\n")
end

local function buildRemoteReport()
    local high = {}
    local medium = {}
    local low = {}
    local unknown = {}

    for _, remote in ipairs(State.remotes) do
        if remote.risk == "ALTA" then
            append(high, remote)
        elseif remote.risk == "MÉDIA" then
            append(medium, remote)
        elseif remote.risk == "BAIXA" then
            append(low, remote)
        else
            append(unknown, remote)
        end
    end

    local lines = {
        "CAFEÍNA • REMOTE MAP",
        "",
        "IMPORTANTE:",
        "A classificação é baseada somente em nome/caminho.",
        "Ela NÃO prova que um Remote seja vulnerável.",
        "",
        string.format(
            "TOTAL: %d | ALTA: %d | MÉDIA: %d | BAIXA: %d",
            #State.remotes,
            #high,
            #medium,
            #low
        ),
        "",
    }

    local function writeGroup(title, list)
        append(lines, "------------------------------------------")
        append(lines, title)
        append(lines, "------------------------------------------")

        if #list == 0 then
            append(lines, "Nenhum.")
            append(lines, "")
            return
        end

        table.sort(list, function(a, b)
            return a.path < b.path
        end)

        for _, remote in ipairs(list) do
            append(
                lines,
                string.format(
                    "[%s] %s\n  %s\n  motivo: %s\n",
                    remote.type,
                    remote.name,
                    remote.path,
                    remote.reason
                )
            )
        end
    end

    writeGroup("PRIORIDADE ALTA", high)
    writeGroup("PRIORIDADE MÉDIA", medium)
    writeGroup("PRIORIDADE BAIXA", low)
    writeGroup("NÃO CLASSIFICADOS", unknown)

    return table.concat(lines, "\n")
end

local function buildEconomyReport()
    local records = collectPathsContaining(
        "cash",
        "zombux",
        "level",
        "exp",
        "prestige",
        "reward",
        "stattracking",
        "difficulty"
    )

    local lines = {
        "CAFEÍNA • ECONOMIA / PROGRESSÃO",
        "",
        "Valores localizados:",
        "",
    }

    for _, record in ipairs(records) do
        if record.value ~= nil then
            append(
                lines,
                record.path .. " = " .. tostring(record.value)
            )
        end
    end

    return table.concat(lines, "\n")
end

local function buildWeaponsReport()
    local records = collectPathsContaining(
        ".weapons.",
        "currentloadout",
        "equippedattachments",
        "viewpor weapons",
        "viewportweapons"
    )

    local lines = {
        "CAFEÍNA • WEAPONS / LOADOUT",
        "",
    }

    for _, record in ipairs(records) do
        if not CONFIG.SKIP_CLASSES_IN_SMART_REPORT[
            record.className
        ] then

            local line =
                "[" .. record.className .. "] "
                .. record.path

            if record.value ~= nil then
                line = line .. " = " .. tostring(record.value)
            end

            append(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

local function buildMonetizationReport()
    local records = collectPathsContaining(
        "monetization",
        "receipt",
        "gamepass",
        "bundle",
        "gift",
        "purchase"
    )

    local lines = {
        "CAFEÍNA • MONETIZAÇÃO",
        "",
        "Objetos relacionados:",
        "",
    }

    for _, record in ipairs(records) do
        local line =
            "[" .. record.className .. "] "
            .. record.path

        if record.value ~= nil then
            line = line .. " = " .. tostring(record.value)
        end

        append(lines, line)
    end

    return table.concat(lines, "\n")
end

local function buildScriptsReport()
    local lines = {
        "CAFEÍNA • SCRIPTS / MODULES",
        "",
        "MODULES:",
        "",
    }

    table.sort(State.modules, function(a, b)
        return a.path < b.path
    end)

    for _, item in ipairs(State.modules) do
        append(lines, item.path)
    end

    append(lines, "")
    append(lines, "SCRIPTS / LOCALSCRIPTS:")
    append(lines, "")

    table.sort(State.scripts, function(a, b)
        return a.path < b.path
    end)

    for _, item in ipairs(State.scripts) do
        append(
            lines,
            "[" .. item.type .. "] " .. item.path
        )
    end

    return table.concat(lines, "\n")
end

local function buildArchitectureReport()
    local hasClientData = false
    local hasDataReplication = false
    local hasWeapons = false
    local hasClasses = false
    local hasCaseSystem = false
    local hasWeaponProgression = false
    local hasMonetization = false

    for _, record in ipairs(State.records) do
        local lower = string.lower(record.path)

        if string.find(lower, "clientdata", 1, true) then
            hasClientData = true
        end

        if string.find(lower, "datareplication", 1, true) then
            hasDataReplication = true
        end

        if string.find(lower, ".weapons", 1, true) then
            hasWeapons = true
        end

        if string.find(lower, "classsystem", 1, true) then
            hasClasses = true
        end

        if string.find(lower, "casesystem", 1, true) then
            hasCaseSystem = true
        end

        if string.find(
            lower,
            "weaponprogression",
            1,
            true
        ) then
            hasWeaponProgression = true
        end

        if string.find(lower, "monetization", 1, true) then
            hasMonetization = true
        end
    end

    local lines = {
        "CAFEÍNA • ARCHITECTURE MAP",
        "",
        "MAPA GERADO POR NOMES/CAMINHOS VISÍVEIS AO CLIENTE.",
        "",
        "                 SERVER",
        "                    │",
        "                    ▼",
    }

    if hasDataReplication then
        append(lines, "             DataReplication")
        append(lines, "                    │")
        append(lines, "                    ▼")
    end

    if hasClientData then
        append(lines, "     ReplicatedStorage.ClientData")
        append(lines, "                    │")
        append(lines, "        ┌───────────┼───────────┐")
    end

    if hasWeapons then
        append(lines, "     Weapons")
    end

    if hasClasses then
        append(lines, "     Classes / Deployables")
    end

    if hasMonetization then
        append(lines, "     Monetization")
    end

    append(lines, "")
    append(lines, "SISTEMAS DETECTADOS:")

    append(
        lines,
        "  ClientData: "
        .. tostring(hasClientData)
    )

    append(
        lines,
        "  DataReplication: "
        .. tostring(hasDataReplication)
    )

    append(
        lines,
        "  Weapons: "
        .. tostring(hasWeapons)
    )

    append(
        lines,
        "  Classes: "
        .. tostring(hasClasses)
    )

    append(
        lines,
        "  CaseSystem: "
        .. tostring(hasCaseSystem)
    )

    append(
        lines,
        "  WeaponProgression: "
        .. tostring(hasWeaponProgression)
    )

    append(
        lines,
        "  Monetization: "
        .. tostring(hasMonetization)
    )

    append(lines, "")
    append(lines, "FRONTEIRAS DE CONFIANÇA:")

    for _, remote in ipairs(State.remotes) do
        if remote.risk == "ALTA" then
            append(
                lines,
                "  [ALTA] " .. remote.path
            )
        end
    end

    append(lines, "")
    append(lines, "OBSERVAÇÃO:")
    append(
        lines,
        "O scanner não conhece a implementação privada "
        .. "dos handlers server-side."
    )

    return table.concat(lines, "\n")
end

local function buildIntelligenceReport()
    local lines = {
        "==================================================",
        "          CAFEÍNA SMART INTELLIGENCE",
        "==================================================",
        "",
        "REMOTES IMPORTANTES",
        "",
    }

    for _, remote in ipairs(State.remotes) do
        if remote.risk == "ALTA"
            or remote.risk == "MÉDIA" then

            append(
                lines,
                string.format(
                    "[%s] %s",
                    remote.risk,
                    remote.path
                )
            )
        end
    end

    append(lines, "")
    append(lines, "CLIENT DATA")
    append(lines, "")

    local clientRecords = collectPathsContaining(
        "replicatedstorage.clientdata"
    )

    local firstLevel = {}

    for _, record in ipairs(clientRecords) do
        local path = record.path

        local suffix = string.match(
            path,
            "ClientData%.[^%.]+%.([^%.]+)$"
        )

        if suffix then
            firstLevel[suffix] = true
        end
    end

    local names = {}

    for name in pairs(firstLevel) do
        append(names, name)
    end

    table.sort(names)

    for _, name in ipairs(names) do
        append(lines, "  • " .. name)
    end

    append(lines, "")
    append(lines, "RECOMENDAÇÃO DE AUDITORIA:")
    append(lines, "")
    append(
        lines,
        "1. Verificar handlers server-side de remotes ALTA."
    )
    append(
        lines,
        "2. Servidor deve recalcular preço/recompensa."
    )
    append(
        lines,
        "3. Cliente nunca deve definir saldo diretamente."
    )
    append(
        lines,
        "4. Compras devem validar ownership no servidor."
    )
    append(
        lines,
        "5. Admin/Developer devem validar UserId/role server-side."
    )
    append(
        lines,
        "6. Rewards/cases devem ser sorteados no servidor."
    )

    return table.concat(lines, "\n")
end

local function buildRawReport()
    local lines = {
        "CAFEÍNA • RAW CLIENT-VISIBLE OBJECT MAP",
        "",
    }

    for _, record in ipairs(State.records) do
        local line =
            "[" .. record.className .. "] "
            .. record.path

        if record.value ~= nil then
            line = line .. " = " .. tostring(record.value)
        end

        append(lines, line)
    end

    return table.concat(lines, "\n")
end

--============================================================
-- FINAL REPORT GENERATION
--============================================================

local function generateReports()
    setStatus(
        "Gerando relatório inteligente...",
        COLORS.YELLOW
    )

    State.reports.Resumo =
        buildSummaryReport()

    State.reports.Inteligência =
        buildIntelligenceReport()

    State.reports.Remotes =
        buildRemoteReport()

    State.reports.Economia =
        buildEconomyReport()

    State.reports.Armas =
        buildWeaponsReport()

    State.reports.Monetização =
        buildMonetizationReport()

    State.reports.Scripts =
        buildScriptsReport()

    State.reports.Arquitetura =
        buildArchitectureReport()

    State.reports.Bruto =
        buildRawReport()

    refreshPage()
end

--============================================================
-- RESET
--============================================================

local function resetScan()
    State.records = {}
    State.remotes = {}
    State.scripts = {}
    State.modules = {}
    State.tools = {}
    State.values = {}
    State.clientData = {}
    State.classes = {}
    State.serviceCounts = {}
    State.reports = {}

    State.scanned = 0
end

--============================================================
-- SCAN
--============================================================

local function scanService(service, serviceIndex)
    local descendants = safeCall(function()
        return service:GetDescendants()
    end, {})

    State.serviceCounts[service.Name] = 0

    for index, instance in ipairs(descendants) do
        if State.cancelled then
            return false
        end

        if State.scanned >= CONFIG.MAX_OBJECTS then
            return false
        end

        State.scanned += 1
        State.serviceCounts[service.Name] += 1

        append(
            State.records,
            buildRecord(instance, service.Name)
        )

        if index % CONFIG.YIELD_EVERY == 0 then
            task.wait()

            setStatus(
                string.format(
                    "Lendo %s • %d objetos",
                    service.Name,
                    State.scanned
                ),
                COLORS.YELLOW
            )
        end
    end

    local progressValue =
        serviceIndex / #CONFIG.SERVICES

    setProgress(progressValue)

    return true
end

local function runScanner()
    if State.scanning then
        return
    end

    State.scanning = true
    State.cancelled = false
    State.startedAt = os.clock()

    resetScan()

    StartButton.Text = "⏹ CANCELAR"
    StartButton.BackgroundColor3 = COLORS.ORANGE

    setProgress(0)

    setStatus(
        "Iniciando análise...",
        COLORS.YELLOW
    )

    task.spawn(function()
        for index, service in ipairs(CONFIG.SERVICES) do
            if State.cancelled then
                break
            end

            setStatus(
                "Analisando " .. service.Name .. "...",
                COLORS.YELLOW
            )

            local continue =
                scanService(service, index)

            if not continue
                and State.scanned >= CONFIG.MAX_OBJECTS then

                break
            end
        end

        if State.cancelled then
            setStatus(
                "Scanner cancelado",
                COLORS.ORANGE
            )
        else
            generateReports()

            setProgress(1)

            setStatus(
                string.format(
                    "Pronto • %d objetos • %d remotes",
                    State.scanned,
                    #State.remotes
                ),
                COLORS.GREEN
            )
        end

        StartButton.Text = "🔍 INICIAR SCANNER"
        StartButton.BackgroundColor3 = COLORS.RED

        State.scanning = false
    end)
end

StartButton.MouseButton1Click:Connect(function()
    if State.scanning then
        State.cancelled = true
        return
    end

    runScanner()
end)

--============================================================
-- COPY
--============================================================

CopySection.MouseButton1Click:Connect(function()
    local report =
        State.reports[State.currentPage]

    if not report then
        setStatus(
            "Nada para copiar",
            COLORS.ORANGE
        )

        return
    end

    if copyText(report) then
        setStatus(
            "Seção copiada",
            COLORS.GREEN
        )
    else
        setStatus(
            "Clipboard não disponível",
            COLORS.ORANGE
        )
    end
end)

CopyAll.MouseButton1Click:Connect(function()
    local output = {}

    for _, page in ipairs(PAGES) do
        if State.reports[page] then
            append(
                output,
                "\n\n==============================\n"
                .. page
                .. "\n==============================\n"
            )

            append(
                output,
                State.reports[page]
            )
        end
    end

    local result = table.concat(output, "\n")

    if copyText(trimText(result)) then
        setStatus(
            "Relatório completo copiado",
            COLORS.GREEN
        )
    else
        setStatus(
            "Clipboard não disponível",
            COLORS.ORANGE
        )
    end
end)

--============================================================
-- SAVE JSON
--============================================================

local function buildExport()
    return {
        metadata = {
            generatedBy =
                "CAFEÍNA SERVER SCANNER V3",

            scannerVersion =
                CONFIG.VERSION,

            clientVisibleOnly =
                true,

            generatedAt =
                os.time(),

            game = {
                placeId = game.PlaceId,
                gameId = game.GameId,
                placeVersion = game.PlaceVersion,
            },

            summary = {
                objects = State.scanned,
                remotes = #State.remotes,
                scripts = #State.scripts,
                modules = #State.modules,
                tools = #State.tools,
            }
        },

        intelligence = {
            remotes = State.remotes,
            classes = State.classes,
        },

        objects = State.records,
    }
end

Save.MouseButton1Click:Connect(function()
    if #State.records == 0 then
        setStatus(
            "Execute o scanner primeiro",
            COLORS.ORANGE
        )

        return
    end

    local json

    local ok = pcall(function()
        json = HttpService:JSONEncode(
            buildExport()
        )
    end)

    if not ok or not json then
        setStatus(
            "Erro ao gerar JSON",
            COLORS.ORANGE
        )

        return
    end

    if writefile then
        local filename =
            "Cafeina_ServerScan_V3_"
            .. tostring(game.PlaceId)
            .. "_"
            .. tostring(os.time())
            .. ".json"

        local saved = pcall(function()
            writefile(filename, json)
        end)

        if saved then
            setStatus(
                "Arquivo salvo: " .. filename,
                COLORS.GREEN
            )

            return
        end
    end

    if copyText(json) then
        setStatus(
            "JSON copiado para clipboard",
            COLORS.GREEN
        )
    else
        setStatus(
            "Sem writefile/clipboard",
            COLORS.ORANGE
        )
    end
end)

--============================================================
-- DRAG SUPPORT
--============================================================

local function makeDraggable(handle, target)
    local dragging = false
    local dragStart
    local startPosition
    local dragInput

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = target.Position

            input.Changed:Connect(function()
                if input.UserInputState ==
                    Enum.UserInputState.End then

                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType ==
                Enum.UserInputType.MouseMovement
            or input.UserInputType ==
                Enum.UserInputType.Touch then

            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta =
                input.Position - dragStart

            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,

                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(Header, Main)

--============================================================
-- MINIMIZED ICON
--============================================================

local Floating = Instance.new("TextButton")
Floating.Size = UDim2.new(0, 55, 0, 55)
Floating.Position = UDim2.new(0.5, -27, 0.5, -27)
Floating.BackgroundColor3 = COLORS.RED_DARK
Floating.TextColor3 = COLORS.TEXT
Floating.Font = Enum.Font.GothamBold
Floating.TextSize = 24
Floating.Text = "☕"
Floating.Visible = false
Floating.Parent = Gui

Instance.new("UICorner", Floating).CornerRadius =
    UDim.new(1, 0)

local FloatingStroke =
    Instance.new("UIStroke")

FloatingStroke.Color = COLORS.RED
FloatingStroke.Thickness = 2
FloatingStroke.Parent = Floating

makeDraggable(Floating, Floating)

Minimize.MouseButton1Click:Connect(function()
    State.minimized = true

    Main.Visible = false
    Floating.Visible = true
end)

Floating.MouseButton1Click:Connect(function()
    State.minimized = false

    Floating.Visible = false
    Main.Visible = true
end)

Close.MouseButton1Click:Connect(function()
    State.cancelled = true

    Gui:Destroy()
end)

--============================================================
-- INITIAL
--============================================================

State.currentPage = "Resumo"
refreshPage()

setStatus(
    "Pronto para iniciar • client-visible only",
    COLORS.GREEN
)

print(
    "[CAFEÍNA V3] Scanner carregado."
)
