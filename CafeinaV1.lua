--[[
==============================================================
CAFEÍNA • WEAPON RESEARCH V1.0
Scanner focado em descobrir o fluxo legítimo de armas do jogo.

OBJETIVO
- Mapear Tools/armas visíveis ao cliente.
- Mapear remotes relacionados a armas/tycoon/inventário.
- Observar mudanças no Backpack/Character enquanto o jogador
  pega/equipa armas normalmente.
- Registrar atributos úteis e estrutura ao redor de remotes.
- NÃO dispara RemoteEvent/RemoteFunction.
- NÃO altera objetos do jogo.
- NÃO tenta burlar validações do servidor.

LAYOUT
- INICIAR
- INTERROMPER
- ENVIAR
- Status compacto, contador, tamanho e pass.

OBSERVAÇÃO
- Configure CONFIG.UploadURL se quiser enviar o relatório.
- Nunca copia o relatório inteiro para o clipboard.
- O clipboard é usado somente para o link final retornado pelo site.
==============================================================
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

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    Title = "CAFEÍNA • WEAPON RESEARCH",
    Version = "V1.2 BALLISTICS",

    -- Limite aproximado do relatório em memória.
    MaxBytes = 150 * 1024 * 1024,

    -- Intervalo entre passes do scanner incremental.
    PassInterval = 0.35,

    -- Quantos objetos processar por frame em scans maiores.
    BatchSize = 450,

    -- Intervalo mínimo para registrar mudanças repetitivas.
    ChangeDebounce = 0.18,

    -- Quantidade máxima de itens na fila de mudanças.
    MaxQueuedChanges = 20000,

    -- Endpoint opcional de upload.
    -- Ex.: "https://seusite.onrender.com/api/upload"
    UploadURL = "",

    -- Se seu backend usa um endpoint diferente para chunk:
    UploadChunkURL = "",

    -- Tamanho aproximado de chunk de upload.
    UploadChunkBytes = 900 * 1024,

    -- Pausa curta entre chunks para reduzir pico de CPU/memória.
    UploadChunkDelay = 0.08,

    -- Balística observacional.
    Ballistics = {
        Enabled = true,

        -- Janela em que objetos novos após um disparo são associados ao tiro.
        ShotWindow = 1.35,

        -- Quantos projéteis podem ser rastreados ao mesmo tempo.
        MaxTrackedProjectiles = 18,

        -- Amostras por segundo para objetos físicos visíveis.
        SamplesPerSecond = 20,

        -- Tempo máximo de trajetória observada por projétil.
        MaxTrackSeconds = 2.25,

        -- Distância máxima do raycast observacional feito no momento do tiro.
        ProbeDistance = 2500,

        -- Limite para eventos visuais associados a um único tiro.
        MaxShotArtifacts = 80,
    },

    -- Campos/nomes considerados relevantes.
    Keywords = {
        "gun", "weapon", "tool", "blaster", "rifle", "pistol",
        "shotgun", "sniper", "ammo", "magazine", "reload",
        "fire", "damage", "projectile", "bullet", "collect",
        "purchase", "equip", "inventory", "loadout",
        "tycoon", "starterpack", "armour", "armor",
        "five-seven", "ump", "ak", "famas", "mp7", "mp9",
        "awp", "barrett", "p90", "bizon", "sg553", "tec",
        "nova", "laser", "winter", "cryo"
    },

    -- Propriedades simples que vale a pena observar.
    Properties = {
        "Name",
        "ClassName",
        "Value",
        "Text",
        "Enabled",
        "Visible",
    },

    -- Atributos conhecidos encontrados no jogo.
    InterestingAttributes = {
        "_ammo",
        "_reloading",
        "magazineSize",
        "fireMode",
        "projectileType",
        "damage",
        "rateOfFire",
        "range",
        "spread",
        "reloadTime",
        "reloadType",
        "Purchase",
        "Gun",
        "Team",
        "Health",
        "HealthMult",
        "DamageMult",
        "DamagePerSecond",
        "FireRate",
        "Range",
        "ReloadTime",
        "MagSize",
        "SpeedMult",
    },
}

--==============================================================
-- STATE
--==============================================================

local STATE = {
    Running = false,
    StopRequested = false,
    Pass = 0,
    StartClock = 0,

    Records = {},
    Seen = {},
    SeenObjects = setmetatable({}, {__mode = "k"}),
    Connections = {},
    ChangeQueue = {},

    RecordCount = 0,
    ApproxBytes = 0,

    LastStatus = "Pronto",
    LastError = nil,

    BaselineDone = false,
    Uploading = false,
    ActiveShots = {},
    TrackedProjectiles = {},
    ShotSequence = 0,
    LastShotAt = 0,

}

--==============================================================
-- UTILS
--==============================================================

local function now()
    return os.clock()
end

local function unix()
    local ok, value = pcall(function()
        return DateTime.now().UnixTimestampMillis
    end)
    return ok and value or math.floor(os.time() * 1000)
end

local function safeFullName(obj)
    local ok, result = pcall(function()
        return obj:GetFullName()
    end)
    return ok and result or tostring(obj)
end

local function safeClass(obj)
    local ok, result = pcall(function()
        return obj.ClassName
    end)
    return ok and result or "Unknown"
end

local function normalize(s)
    return string.lower(tostring(s or ""))
end

local function containsKeyword(text)
    text = normalize(text)

    for _, keyword in ipairs(CONFIG.Keywords) do
        if string.find(text, keyword, 1, true) then
            return true, keyword
        end
    end

    return false, nil
end

local function approxSize(value)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    if ok then
        return #encoded
    end

    return 64
end

local function tableShallowCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

local function valueToSerializable(value)
    local t = typeof(value)

    if t == "nil" then
        return nil
    elseif t == "string" or t == "number" or t == "boolean" then
        return value
    elseif t == "Vector3" then
        return {x = value.X, y = value.Y, z = value.Z}
    elseif t == "Vector2" then
        return {x = value.X, y = value.Y}
    elseif t == "Color3" then
        return {r = value.R, g = value.G, b = value.B}
    elseif t == "CFrame" then
        return {value:GetComponents()}
    elseif t == "UDim2" then
        return {
            xs = value.X.Scale, xo = value.X.Offset,
            ys = value.Y.Scale, yo = value.Y.Offset,
        }
    elseif t == "Instance" then
        return {
            class = safeClass(value),
            name = value.Name,
            path = safeFullName(value),
        }
    elseif t == "EnumItem" then
        return tostring(value)
    else
        return tostring(value)
    end
end

local function getAttributesSafe(obj)
    local ok, attrs = pcall(function()
        return obj:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return {}
    end

    local out = {}
    for k, v in pairs(attrs) do
        out[k] = valueToSerializable(v)
    end
    return out
end

local function interestingAttributesOnly(obj)
    local attrs = getAttributesSafe(obj)
    local out = {}

    for _, key in ipairs(CONFIG.InterestingAttributes) do
        if attrs[key] ~= nil then
            out[key] = attrs[key]
        end
    end

    return out
end

local function makeRecordKey(record)
    local parts = {
        tostring(record.kind or ""),
        tostring(record.path or ""),
        tostring(record.name or ""),
        tostring(record.detail or ""),
        tostring(record.attribute or ""),
        tostring(record.value or ""),
        tostring(record.event or ""),
    }

    return table.concat(parts, "|")
end

local function canAdd()
    return STATE.ApproxBytes < CONFIG.MaxBytes
end

local function addRecord(record, dedupe)
    if not canAdd() then
        STATE.StopRequested = true
        return false
    end

    record.ts = record.ts or unix()
    record.pass = record.pass or STATE.Pass

    if dedupe ~= false then
        local key = makeRecordKey(record)

        if STATE.Seen[key] then
            return false
        end

        STATE.Seen[key] = true
    end

    local bytes = approxSize(record)

    if STATE.ApproxBytes + bytes > CONFIG.MaxBytes then
        STATE.StopRequested = true
        return false
    end

    STATE.RecordCount += 1
    STATE.ApproxBytes += bytes
    STATE.Records[#STATE.Records + 1] = record

    return true
end

local function disconnectAll()
    for _, connection in ipairs(STATE.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(STATE.Connections)
end

local function trackConnection(connection)
    STATE.Connections[#STATE.Connections + 1] = connection
    return connection
end

local function yieldBatch(index)
    if index % CONFIG.BatchSize == 0 then
        RunService.Heartbeat:Wait()
    end
end

--==============================================================
-- UI
--==============================================================

local GUI_NAME = "CafeinaWeaponResearch"

local oldGui = PlayerGui:FindFirstChild(GUI_NAME)
if oldGui then
    oldGui:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.5)
Main.Size = UDim2.fromOffset(360, 206)
Main.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(65, 65, 72)
Stroke.Transparency = 0.25
Stroke.Thickness = 1
Stroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 48)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Position = UDim2.fromOffset(14, 8)
Title.Size = UDim2.new(1, -60, 0, 20)
Title.BackgroundTransparency = 1
Title.Text = CONFIG.Title
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Version = Instance.new("TextLabel")
Version.Position = UDim2.fromOffset(14, 27)
Version.Size = UDim2.new(1, -60, 0, 14)
Version.BackgroundTransparency = 1
Version.Text = CONFIG.Version
Version.TextColor3 = Color3.fromRGB(135, 135, 145)
Version.TextSize = 10
Version.Font = Enum.Font.GothamMedium
Version.TextXAlignment = Enum.TextXAlignment.Left
Version.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.AnchorPoint = Vector2.new(1, 0)
Minimize.Position = UDim2.new(1, -10, 0, 9)
Minimize.Size = UDim2.fromOffset(32, 30)
Minimize.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
Minimize.Text = "−"
Minimize.TextColor3 = Color3.fromRGB(240, 240, 240)
Minimize.TextSize = 18
Minimize.Font = Enum.Font.GothamBold
Minimize.AutoButtonColor = false
Minimize.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 8)
MinCorner.Parent = Minimize

local Info = Instance.new("TextLabel")
Info.Position = UDim2.fromOffset(14, 52)
Info.Size = UDim2.new(1, -28, 0, 22)
Info.BackgroundTransparency = 1
Info.Text = "0 KB • 0 registros • PASS 0"
Info.TextColor3 = Color3.fromRGB(220, 220, 225)
Info.TextSize = 12
Info.Font = Enum.Font.GothamMedium
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.Parent = Main

local Status = Instance.new("TextLabel")
Status.Position = UDim2.fromOffset(14, 75)
Status.Size = UDim2.new(1, -28, 0, 20)
Status.BackgroundTransparency = 1
Status.Text = "Pronto para iniciar"
Status.TextColor3 = Color3.fromRGB(155, 155, 165)
Status.TextSize = 11
Status.Font = Enum.Font.GothamMedium
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

local ProgressBG = Instance.new("Frame")
ProgressBG.Position = UDim2.fromOffset(14, 101)
ProgressBG.Size = UDim2.new(1, -28, 0, 7)
ProgressBG.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
ProgressBG.BorderSizePixel = 0
ProgressBG.Parent = Main

local PBCorner = Instance.new("UICorner")
PBCorner.CornerRadius = UDim.new(1, 0)
PBCorner.Parent = ProgressBG

local Progress = Instance.new("Frame")
Progress.Size = UDim2.fromScale(0, 1)
Progress.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
Progress.BorderSizePixel = 0
Progress.Parent = ProgressBG

local PCorner = Instance.new("UICorner")
PCorner.CornerRadius = UDim.new(1, 0)
PCorner.Parent = Progress

local ButtonRow = Instance.new("Frame")
ButtonRow.Position = UDim2.fromOffset(14, 124)
ButtonRow.Size = UDim2.new(1, -28, 0, 34)
ButtonRow.BackgroundTransparency = 1
ButtonRow.Parent = Main

local RowLayout = Instance.new("UIListLayout")
RowLayout.FillDirection = Enum.FillDirection.Horizontal
RowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
RowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
RowLayout.Padding = UDim.new(0, 7)
RowLayout.Parent = ButtonRow

local function makeButton(text, width)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(width, 34)
    button.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
    button.Text = text
    button.TextColor3 = Color3.fromRGB(12, 12, 14)
    button.TextSize = 10
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = false
    button.Parent = ButtonRow

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = button

    return button
end

local StartButton = makeButton("INICIAR", 102)
local StopButton = makeButton("INTERROMPER", 110)
local UploadButton = makeButton("ENVIAR", 102)

StopButton.BackgroundColor3 = Color3.fromRGB(165, 35, 44)
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)

local Hint = Instance.new("TextLabel")
Hint.Position = UDim2.fromOffset(14, 166)
Hint.Size = UDim2.new(1, -28, 0, 28)
Hint.BackgroundTransparency = 1
Hint.Text = "Pegue/equipe armas normalmente enquanto o scan roda."
Hint.TextWrapped = true
Hint.TextColor3 = Color3.fromRGB(115, 115, 125)
Hint.TextSize = 9
Hint.Font = Enum.Font.GothamMedium
Hint.TextXAlignment = Enum.TextXAlignment.Left
Hint.TextYAlignment = Enum.TextYAlignment.Top
Hint.Parent = Main

local Mini = Instance.new("TextButton")
Mini.Name = "Mini"
Mini.AnchorPoint = Vector2.new(0.5, 0.5)
Mini.Position = UDim2.fromScale(0.5, 0.5)
Mini.Size = UDim2.fromOffset(52, 52)
Mini.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
Mini.Text = "C"
Mini.TextColor3 = Color3.fromRGB(245, 245, 245)
Mini.TextSize = 20
Mini.Font = Enum.Font.GothamBold
Mini.Visible = false
Mini.AutoButtonColor = false
Mini.Parent = Gui

local MiniCorner = Instance.new("UICorner")
MiniCorner.CornerRadius = UDim.new(0, 14)
MiniCorner.Parent = Mini

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Color3.fromRGB(80, 80, 88)
MiniStroke.Transparency = 0.25
MiniStroke.Parent = Mini

local function setStatus(text, color)
    STATE.LastStatus = text
    Status.Text = text
    Status.TextColor3 = color or Color3.fromRGB(155, 155, 165)
end

local function updateInfo()
    local bytes = STATE.ApproxBytes
    local sizeText

    if bytes >= 1024 * 1024 then
        sizeText = string.format("%.2f MB", bytes / 1024 / 1024)
    elseif bytes >= 1024 then
        sizeText = string.format("%.1f KB", bytes / 1024)
    else
        sizeText = tostring(bytes) .. " B"
    end

    Info.Text = string.format(
        "%s • %d registros • PASS %d",
        sizeText,
        STATE.RecordCount,
        STATE.Pass
    )

    local ratio = math.clamp(bytes / CONFIG.MaxBytes, 0, 1)
    Progress.Size = UDim2.fromScale(ratio, 1)
end

--==============================================================
-- DRAG
--==============================================================

local UserInputService = game:GetService("UserInputService")

local function makeDraggable(handle, object)
    local dragging = false
    local dragStart
    local startPosition
    local dragInput

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = object.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPosition then
            local delta = input.Position - dragStart

            object.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end))
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

Minimize.MouseButton1Click:Connect(function()
    Main.Visible = false
    Mini.Position = Main.Position
    Mini.Visible = true
end)

Mini.MouseButton1Click:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

--==============================================================
-- CLASSIFICATION
--==============================================================

local function isRemote(obj)
    return obj:IsA("RemoteEvent")
        or obj:IsA("RemoteFunction")
        or obj:IsA("BindableEvent")
        or obj:IsA("BindableFunction")
end

local function isTool(obj)
    return obj:IsA("Tool")
end

local function isModule(obj)
    return obj:IsA("ModuleScript")
end

local function isScriptLike(obj)
    return obj:IsA("LocalScript")
        or obj:IsA("ModuleScript")
        or obj:IsA("Script")
end

local function isWeaponRelevantObject(obj)
    if isTool(obj) or isRemote(obj) then
        return true
    end

    local text = obj.Name .. " " .. safeFullName(obj)
    local matched = containsKeyword(text)

    if matched then
        return true
    end

    local attrs = getAttributesSafe(obj)
    for key, value in pairs(attrs) do
        local m1 = containsKeyword(key)
        local m2 = containsKeyword(tostring(value))
        if m1 or m2 then
            return true
        end
    end

    return false
end

--==============================================================
-- TOOL SNAPSHOT
--==============================================================

local function toolSnapshot(tool)
    local snapshot = {
        name = tool.Name,
        path = safeFullName(tool),
        class = tool.ClassName,
        attributes = getAttributesSafe(tool),
        interestingAttributes = interestingAttributesOnly(tool),
        children = {},
    }

    local descendants = tool:GetDescendants()

    for i, child in ipairs(descendants) do
        if i > 180 then
            snapshot.childrenTruncated = true
            break
        end

        local relevant = isScriptLike(child)
            or child:IsA("Animation")
            or child:IsA("Sound")
            or child:IsA("NumberValue")
            or child:IsA("StringValue")
            or child:IsA("BoolValue")
            or containsKeyword(child.Name)

        if relevant then
            snapshot.children[#snapshot.children + 1] = {
                name = child.Name,
                class = child.ClassName,
                path = safeFullName(child),
                attributes = interestingAttributesOnly(child),
            }
        end
    end

    return snapshot
end

local function recordTool(tool, eventName)
    if not tool or not tool.Parent or not tool:IsA("Tool") then
        return
    end

    addRecord({
        kind = "tool",
        event = eventName or "snapshot",
        name = tool.Name,
        path = safeFullName(tool),
        data = toolSnapshot(tool),
    }, eventName == "baseline")
end

--==============================================================
-- REMOTE SNAPSHOT
--==============================================================

local function remoteSnapshot(remote)
    local parent = remote.Parent

    return {
        name = remote.Name,
        class = remote.ClassName,
        path = safeFullName(remote),
        parent = parent and {
            name = parent.Name,
            class = parent.ClassName,
            path = safeFullName(parent),
        } or nil,
        attributes = getAttributesSafe(remote),
    }
end

local function recordRemote(remote)
    if not isRemote(remote) then
        return
    end

    local relevant, keyword = containsKeyword(
        remote.Name .. " " .. safeFullName(remote)
    )

    if not relevant then
        return
    end

    addRecord({
        kind = "remote",
        name = remote.Name,
        path = safeFullName(remote),
        detail = keyword,
        data = remoteSnapshot(remote),
    }, true)
end

--==============================================================
-- MODULE/SCRIPT STRUCTURE
--==============================================================

local function recordScriptLike(obj)
    if not isScriptLike(obj) then
        return
    end

    local relevant, keyword = containsKeyword(
        obj.Name .. " " .. safeFullName(obj)
    )

    if not relevant then
        return
    end

    addRecord({
        kind = "script_structure",
        name = obj.Name,
        path = safeFullName(obj),
        class = obj.ClassName,
        detail = keyword,
        attributes = interestingAttributesOnly(obj),
    }, true)
end

--==============================================================
-- RELEVANT OBJECT STRUCTURE
--==============================================================

local function recordRelevantObject(obj, reason)
    if not obj or not obj.Parent then
        return
    end

    local attrs = interestingAttributesOnly(obj)

    addRecord({
        kind = "object_structure",
        reason = reason,
        name = obj.Name,
        class = obj.ClassName,
        path = safeFullName(obj),
        attributes = attrs,
    }, true)
end

--==============================================================
-- BACKPACK / CHARACTER OBSERVATION
--==============================================================

local lastChange = {}

local function changeKey(obj, eventName)
    return tostring(obj) .. "|" .. tostring(eventName)
end

local function shouldRecordChange(obj, eventName)
    local key = changeKey(obj, eventName)
    local current = now()
    local previous = lastChange[key] or 0

    if current - previous < CONFIG.ChangeDebounce then
        return false
    end

    lastChange[key] = current
    return true
end

local function observeAttributes(obj)
    if STATE.SeenObjects[obj] then
        return
    end

    STATE.SeenObjects[obj] = true

    local ok, signal = pcall(function()
        return obj.AttributeChanged
    end)

    if ok and signal then
        trackConnection(signal:Connect(function(attributeName)
            if not STATE.Running then
                return
            end

            if not shouldRecordChange(obj, "attr:" .. attributeName) then
                return
            end

            local value
            pcall(function()
                value = obj:GetAttribute(attributeName)
            end)

            local relevant = containsKeyword(attributeName)
                or containsKeyword(tostring(value))
                or isTool(obj)
                or isWeaponRelevantObject(obj)

            if not relevant then
                return
            end

            addRecord({
                kind = "attribute_change",
                name = obj.Name,
                class = safeClass(obj),
                path = safeFullName(obj),
                attribute = attributeName,
                value = valueToSerializable(value),
            }, false)

            updateInfo()
        end))
    end
end

local function observeTool(tool)
    if not tool or not tool:IsA("Tool") then
        return
    end

    observeAttributes(tool)

    for _, child in ipairs(tool:GetDescendants()) do
        observeAttributes(child)
    end

    trackConnection(tool.DescendantAdded:Connect(function(child)
        if not STATE.Running then
            return
        end

        observeAttributes(child)

        if isWeaponRelevantObject(child) or isScriptLike(child) then
            addRecord({
                kind = "tool_descendant_added",
                tool = tool.Name,
                name = child.Name,
                class = child.ClassName,
                path = safeFullName(child),
                attributes = interestingAttributesOnly(child),
            }, false)

            updateInfo()
        end
    end))

    trackConnection(tool.DescendantRemoving:Connect(function(child)
        if not STATE.Running then
            return
        end

        if isWeaponRelevantObject(child) or isScriptLike(child) then
            addRecord({
                kind = "tool_descendant_removing",
                tool = tool.Name,
                name = child.Name,
                class = child.ClassName,
                path = safeFullName(child),
            }, false)

            updateInfo()
        end
    end))
end

local function observeContainer(container, label)
    if not container then
        return
    end

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            observeTool(child)
        end
    end

    trackConnection(container.ChildAdded:Connect(function(child)
        if not STATE.Running then
            return
        end

        if child:IsA("Tool") then
            addRecord({
                kind = "inventory_change",
                event = "added",
                container = label,
                name = child.Name,
                path = safeFullName(child),
                data = toolSnapshot(child),
            }, false)

            observeTool(child)
            updateInfo()
        elseif isWeaponRelevantObject(child) then
            addRecord({
                kind = "inventory_related_added",
                event = "added",
                container = label,
                name = child.Name,
                class = child.ClassName,
                path = safeFullName(child),
                attributes = interestingAttributesOnly(child),
            }, false)

            updateInfo()
        end
    end))

    trackConnection(container.ChildRemoved:Connect(function(child)
        if not STATE.Running then
            return
        end

        if child:IsA("Tool") or isWeaponRelevantObject(child) then
            addRecord({
                kind = "inventory_change",
                event = "removed",
                container = label,
                name = child.Name,
                class = child.ClassName,
                lastPath = label .. "." .. child.Name,
                attributes = interestingAttributesOnly(child),
            }, false)

            updateInfo()
        end
    end))
end

local function attachPlayerObservers()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        or LocalPlayer:WaitForChild("Backpack", 5)

    if backpack then
        observeContainer(backpack, "Backpack")
    end

    local function attachCharacter(character)
        if not character then
            return
        end

        observeContainer(character, "Character")

        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                observeTool(child)
            end
        end
    end

    if LocalPlayer.Character then
        attachCharacter(LocalPlayer.Character)
    end

    trackConnection(LocalPlayer.CharacterAdded:Connect(function(character)
        if STATE.Running then
            task.wait(0.5)
            attachCharacter(character)
        end
    end))
end

--==============================================================
-- BASELINE SCANS
--==============================================================

local function scanContainer(container, label)
    if not container then
        return
    end

    local descendants = container:GetDescendants()

    for i, obj in ipairs(descendants) do
        if STATE.StopRequested then
            break
        end

        if isTool(obj) then
            recordTool(obj, "baseline")

        elseif isRemote(obj) then
            recordRemote(obj)

        elseif isScriptLike(obj) then
            recordScriptLike(obj)

        elseif isWeaponRelevantObject(obj) then
            recordRelevantObject(obj, label)
        end

        yieldBatch(i)
    end
end

local function baselineScan()
    setStatus("Mapeando ReplicatedStorage...")
    scanContainer(ReplicatedStorage, "ReplicatedStorage")
    updateInfo()

    if STATE.StopRequested then
        return
    end

    setStatus("Mapeando ReplicatedFirst...")
    scanContainer(ReplicatedFirst, "ReplicatedFirst")
    updateInfo()

    if STATE.StopRequested then
        return
    end

    setStatus("Mapeando Workspace relevante...")
    scanContainer(Workspace, "Workspace")
    updateInfo()

    if STATE.StopRequested then
        return
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if backpack then
        setStatus("Mapeando Backpack...")
        scanContainer(backpack, "Backpack")
        updateInfo()
    end

    local character = LocalPlayer.Character

    if character then
        setStatus("Mapeando Character...")
        scanContainer(character, "Character")
        updateInfo()
    end

    STATE.BaselineDone = true
end

--==============================================================
-- INCREMENTAL PASS
--==============================================================

local function scanIncrementalContainer(container, label)
    local descendants = container:GetDescendants()

    for i, obj in ipairs(descendants) do
        if STATE.StopRequested then
            break
        end

        if isTool(obj) then
            recordTool(obj, "incremental")

        elseif isRemote(obj) then
            recordRemote(obj)

        elseif isScriptLike(obj) then
            recordScriptLike(obj)

        elseif isWeaponRelevantObject(obj) then
            recordRelevantObject(obj, label)
        end

        yieldBatch(i)
    end
end

local function incrementalPass()
    STATE.Pass += 1

    setStatus("Analisando remotes e armas...")
    scanIncrementalContainer(ReplicatedStorage, "ReplicatedStorage")

    if STATE.StopRequested then
        return
    end

    setStatus("Analisando Tycoon e mundo...")
    scanIncrementalContainer(Workspace, "Workspace")

    if STATE.StopRequested then
        return
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        setStatus("Analisando Backpack...")
        scanIncrementalContainer(backpack, "Backpack")
    end

    local character = LocalPlayer.Character
    if character then
        setStatus("Analisando arma equipada...")
        scanIncrementalContainer(character, "Character")
    end

    addRecord({
        kind = "pass_summary",
        detail = "weapon_research",
        recordCount = STATE.RecordCount,
        approxBytes = STATE.ApproxBytes,
    }, false)

    updateInfo()
end

--==============================================================
-- REPORT
--==============================================================

local function buildMetadata()
    return {
        schemaVersion = 2,
        scanner = CONFIG.Title,
        version = CONFIG.Version,

        createdAt = unix(),

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
            creatorId = game.CreatorId,
        },

        player = {
            userId = LocalPlayer.UserId,
            name = LocalPlayer.Name,
        },

        stats = {
            passes = STATE.Pass,
            records = STATE.RecordCount,
            approxBytes = STATE.ApproxBytes,
            stopped = STATE.StopRequested,
            baselineDone = STATE.BaselineDone,
        },

        focus = {
            "Tools",
            "Weapon attributes",
            "Ballistics / projectile trajectory",
            "Shot timing",
            "Wall/material impacts",
            "Impact decals/particles/sounds",
            "Backpack changes",
            "Character/equip changes",
            "Weapon remotes",
            "TycoonService",
            "CollectGun structure",
            "Inventory/loadout",
        },

        safety = {
            invokesRemotes = false,
            firesRemotes = false,
            mutatesGameObjects = false,
            observationalRaycastsOnly = true,
        },
    }
end

--==============================================================
-- CLIPBOARD
--==============================================================

local function copyText(text)
    local copied = false

    if type(text) ~= "string" or text == "" then
        return false
    end

    if typeof(setclipboard) == "function" then
        copied = pcall(function()
            setclipboard(text)
        end)
    end

    if not copied and typeof(toclipboard) == "function" then
        copied = pcall(function()
            toclipboard(text)
        end)
    end

    return copied
end

--==============================================================
-- HTTP HELPERS
--==============================================================

local function getRequestFunction()
    if typeof(request) == "function" then
        return request
    end

    if syn and typeof(syn.request) == "function" then
        return syn.request
    end

    if http and typeof(http.request) == "function" then
        return http.request
    end

    return nil
end

local function postJson(url, body)
    local requestFn = getRequestFunction()

    if requestFn then
        return requestFn({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })
    end

    local responseBody = HttpService:PostAsync(
        url,
        body,
        Enum.HttpContentType.ApplicationJson,
        false
    )

    return {
        Success = true,
        StatusCode = 200,
        Body = responseBody,
    }
end

local function responseSucceeded(response)
    if not response then
        return false
    end

    if response.Success == true then
        return true
    end

    local status = tonumber(response.StatusCode)
    return status and status >= 200 and status < 300
end

local function decodeResponse(response)
    if not response or type(response.Body) ~= "string" then
        return nil
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if ok and type(decoded) == "table" then
        return decoded
    end

    return nil
end

local function extractLink(decoded)
    if type(decoded) ~= "table" then
        return nil
    end

    return decoded.url
        or decoded.link
        or decoded.downloadUrl
        or decoded.fileUrl
        or decoded.viewUrl
end

--==============================================================
-- SAFE STREAMING UPLOAD
--==============================================================

local function safeEncode(value)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    if not ok then
        return nil, tostring(encoded)
    end

    return encoded
end

local function flushChunk(uploadId, chunkIndex, totalHint, records, isFinal)
    local endpoint = CONFIG.UploadChunkURL ~= "" and CONFIG.UploadChunkURL
        or CONFIG.UploadURL

    if endpoint == "" then
        return false, "CONFIG.UploadURL não configurado."
    end

    local packet = {
        schemaVersion = 2,
        uploadId = uploadId,
        index = chunkIndex,
        total = totalHint,
        final = isFinal == true,
        filename = string.format(
            "Cafeina_WeaponResearch_%s_%s.json",
            tostring(game.PlaceId),
            tostring(uploadId)
        ),
        metadata = chunkIndex == 1 and buildMetadata() or nil,
        records = records,
    }

    local body, encodeErr = safeEncode(packet)

    if not body then
        return false, "Falha ao codificar chunk: " .. tostring(encodeErr)
    end

    local response = postJson(endpoint, body)

    -- solta referência do body o mais cedo possível
    body = nil

    if not responseSucceeded(response) then
        return false,
            "Falha HTTP no chunk "
            .. tostring(chunkIndex)
            .. ": "
            .. tostring(response and response.StatusCode)
    end

    return true, decodeResponse(response)
end

local function uploadReport()
    if STATE.Uploading then
        return
    end

    if STATE.RecordCount <= 0 then
        setStatus(
            "Nenhum dado para enviar",
            Color3.fromRGB(230, 170, 65)
        )
        return
    end

    if CONFIG.UploadURL == "" and CONFIG.UploadChunkURL == "" then
        setStatus(
            "Configure a URL do site • nada foi copiado",
            Color3.fromRGB(225, 75, 80)
        )
        return
    end

    STATE.Uploading = true
    UploadButton.Text = "..."

    local ok, err = pcall(function()
        setStatus("Preparando envio em blocos...")

        local uploadId = HttpService:GenerateGUID(false)

        local current = {}
        local currentBytes = 0
        local chunkIndex = 0
        local lastDecoded = nil
        local sentRecords = 0

        -- Não criamos um JSON gigante.
        -- Cada record é estimado/codificado isoladamente.
        for i, record in ipairs(STATE.Records) do
            local recordJson, encodeErr = safeEncode(record)

            if not recordJson then
                error(
                    "Falha ao serializar registro "
                    .. tostring(i)
                    .. ": "
                    .. tostring(encodeErr)
                )
            end

            local recordBytes = #recordJson + 2
            recordJson = nil

            if #current > 0
            and currentBytes + recordBytes > CONFIG.UploadChunkBytes then
                chunkIndex += 1

                setStatus(
                    string.format(
                        "Enviando bloco %d • %d/%d registros",
                        chunkIndex,
                        sentRecords,
                        STATE.RecordCount
                    )
                )

                local success, decodedOrError = flushChunk(
                    uploadId,
                    chunkIndex,
                    nil,
                    current,
                    false
                )

                if not success then
                    error(decodedOrError)
                end

                lastDecoded = decodedOrError
                sentRecords += #current

                table.clear(current)
                currentBytes = 0

                updateInfo()

                task.wait(CONFIG.UploadChunkDelay)
            end

            current[#current + 1] = record
            currentBytes += recordBytes

            if i % 250 == 0 then
                RunService.Heartbeat:Wait()
            end
        end

        -- Último bloco.
        chunkIndex += 1

        setStatus(
            string.format(
                "Enviando bloco final %d...",
                chunkIndex
            )
        )

        local success, decodedOrError = flushChunk(
            uploadId,
            chunkIndex,
            chunkIndex,
            current,
            true
        )

        if not success then
            error(decodedOrError)
        end

        lastDecoded = decodedOrError
        sentRecords += #current

        table.clear(current)

        -- tenta usar resposta final do servidor
        local link = extractLink(lastDecoded)

        if link then
            if copyText(link) then
                setStatus(
                    "Enviado • link copiado",
                    Color3.fromRGB(80, 210, 115)
                )
            else
                setStatus(
                    "Enviado • link recebido",
                    Color3.fromRGB(80, 210, 115)
                )
            end

            return
        end

        setStatus(
            string.format(
                "Enviado • %d registros • %d blocos",
                sentRecords,
                chunkIndex
            ),
            Color3.fromRGB(80, 210, 115)
        )
    end)

    if not ok then
        STATE.LastError = tostring(err)

        setStatus(
            "Erro no envio: " .. tostring(err),
            Color3.fromRGB(225, 75, 80)
        )
    end

    UploadButton.Text = "ENVIAR"
    STATE.Uploading = false
    updateInfo()
end


--==============================================================
-- BALLISTICS / SHOT PHYSICS RESEARCH
--==============================================================

local BALLISTIC_WORDS = {
    "bullet", "projectile", "tracer", "shell", "pellet",
    "rocket", "missile", "beam", "laser", "impact", "hit",
    "muzzle", "flash", "debris", "hole"
}

local function vectorTable(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end

    return {
        x = math.round(v.X * 10000) / 10000,
        y = math.round(v.Y * 10000) / 10000,
        z = math.round(v.Z * 10000) / 10000,
        magnitude = math.round(v.Magnitude * 10000) / 10000,
    }
end

local function cframeTable(cf)
    if typeof(cf) ~= "CFrame" then
        return nil
    end

    return {
        position = vectorTable(cf.Position),
        lookVector = vectorTable(cf.LookVector),
        rightVector = vectorTable(cf.RightVector),
        upVector = vectorTable(cf.UpVector),
    }
end

local function isBallisticLike(obj)
    if not obj then
        return false
    end

    local n = string.lower(obj.Name)

    for _, word in ipairs(BALLISTIC_WORDS) do
        if string.find(n, word, 1, true) then
            return true
        end
    end

    if obj:IsA("Beam")
    or obj:IsA("Trail")
    or obj:IsA("Decal")
    or obj:IsA("ParticleEmitter") then
        return true
    end

    if obj:IsA("BasePart") then
        local speed = 0
        pcall(function()
            speed = obj.AssemblyLinearVelocity.Magnitude
        end)

        if speed >= 45 and obj.Size.Magnitude <= 12 then
            return true
        end
    end

    return false
end

local function equippedTool()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end
end

local function findMuzzle(tool)
    if not tool then
        return nil
    end

    local preferred = {
        "Muzzle",
        "MuzzleAttachment",
        "FirePoint",
        "ShootPoint",
        "Barrel",
        "Tip",
    }

    for _, name in ipairs(preferred) do
        local item = tool:FindFirstChild(name, true)
        if item and (item:IsA("Attachment") or item:IsA("BasePart")) then
            return item
        end
    end

    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle
    end
end

local function muzzleWorldPosition(muzzle)
    if not muzzle then return nil end

    if muzzle:IsA("Attachment") then
        return muzzle.WorldPosition
    end

    if muzzle:IsA("BasePart") then
        return muzzle.Position
    end
end

local function muzzleWorldCFrame(muzzle)
    if not muzzle then return nil end

    if muzzle:IsA("Attachment") then
        return muzzle.WorldCFrame
    end

    if muzzle:IsA("BasePart") then
        return muzzle.CFrame
    end
end

local function observationalRayProbe(origin, direction)
    if typeof(origin) ~= "Vector3"
    or typeof(direction) ~= "Vector3"
    or direction.Magnitude <= 0.0001 then
        return nil
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local filter = {}
    if LocalPlayer.Character then
        filter[#filter + 1] = LocalPlayer.Character
    end

    params.FilterDescendantsInstances = filter
    params.IgnoreWater = false

    local result = Workspace:Raycast(
        origin,
        direction.Unit * CONFIG.Ballistics.ProbeDistance,
        params
    )

    if not result then
        return {
            hit = false,
            origin = vectorTable(origin),
            direction = vectorTable(direction.Unit),
        }
    end

    local incidence = nil
    pcall(function()
        local incoming = direction.Unit
        local normal = result.Normal.Unit
        local cosine = math.clamp((-incoming):Dot(normal), -1, 1)
        incidence = math.deg(math.acos(cosine))
    end)

    local reflected = direction.Unit - 2 * direction.Unit:Dot(result.Normal) * result.Normal

    return {
        hit = true,
        origin = vectorTable(origin),
        direction = vectorTable(direction.Unit),
        position = vectorTable(result.Position),
        normal = vectorTable(result.Normal),
        distance = (result.Position - origin).Magnitude,
        material = tostring(result.Material),
        instance = result.Instance and safeFullName(result.Instance) or nil,
        class = result.Instance and result.Instance.ClassName or nil,
        incidenceAngleDegrees = incidence,
        reflectedDirection = vectorTable(reflected),
    }
end

local function getShotContext(tool)
    local camera = Workspace.CurrentCamera
    local muzzle = findMuzzle(tool)

    local origin = muzzleWorldPosition(muzzle)
    local muzzleCf = muzzleWorldCFrame(muzzle)

    if not origin and camera then
        origin = camera.CFrame.Position
    end

    local direction = nil

    if muzzleCf then
        direction = muzzleCf.LookVector
    elseif camera then
        direction = camera.CFrame.LookVector
    end

    local context = {
        tool = tool and tool.Name or nil,
        toolPath = tool and safeFullName(tool) or nil,
        toolAttributes = tool and safeAttributes(tool) or nil,

        muzzle = muzzle and {
            name = muzzle.Name,
            class = muzzle.ClassName,
            path = safeFullName(muzzle),
            cframe = cframeTable(muzzleCf),
        } or nil,

        camera = camera and {
            cframe = cframeTable(camera.CFrame),
            fieldOfView = camera.FieldOfView,
        } or nil,

        probe = origin and direction
            and observationalRayProbe(origin, direction)
            or nil,
    }

    return context
end

local function beginShot(tool, source)
    if not CONFIG.Ballistics.Enabled then
        return
    end

    STATE.ShotSequence += 1
    STATE.LastShotAt = os.clock()

    local shot = {
        id = STATE.ShotSequence,
        startedAtClock = STATE.LastShotAt,
        startedAtUnix = unix(),
        source = source,
        context = getShotContext(tool),
        artifacts = 0,
    }

    STATE.ActiveShots[shot.id] = shot

    addRecord("Ballistics", "shot", {
        shotId = shot.id,
        source = source,
        context = shot.context,
    })

    task.delay(CONFIG.Ballistics.ShotWindow, function()
        STATE.ActiveShots[shot.id] = nil
    end)
end

local function nearestActiveShot()
    local now = os.clock()
    local best = nil
    local bestDt = math.huge

    for _, shot in pairs(STATE.ActiveShots) do
        local dt = now - shot.startedAtClock

        if dt >= 0
        and dt <= CONFIG.Ballistics.ShotWindow
        and dt < bestDt
        and shot.artifacts < CONFIG.Ballistics.MaxShotArtifacts then
            best = shot
            bestDt = dt
        end
    end

    return best, bestDt
end

local function describeArtifact(obj)
    local data = {
        name = obj.Name,
        class = obj.ClassName,
        path = safeFullName(obj),
        attributes = safeAttributes(obj),
    }

    if obj:IsA("BasePart") then
        data.position = vectorTable(obj.Position)
        data.size = vectorTable(obj.Size)
        data.material = tostring(obj.Material)
        data.color = tostring(obj.Color)

        pcall(function()
            data.linearVelocity = vectorTable(obj.AssemblyLinearVelocity)
            data.angularVelocity = vectorTable(obj.AssemblyAngularVelocity)
        end)
    elseif obj:IsA("Attachment") then
        data.worldPosition = vectorTable(obj.WorldPosition)
        data.worldCFrame = cframeTable(obj.WorldCFrame)
    elseif obj:IsA("Beam") then
        data.width0 = obj.Width0
        data.width1 = obj.Width1
        data.faceCamera = obj.FaceCamera
        data.attachment0 = obj.Attachment0 and safeFullName(obj.Attachment0) or nil
        data.attachment1 = obj.Attachment1 and safeFullName(obj.Attachment1) or nil
    elseif obj:IsA("Trail") then
        data.lifetime = obj.Lifetime
        data.minLength = obj.MinLength
    elseif obj:IsA("ParticleEmitter") then
        data.rate = obj.Rate
        data.lifetime = tostring(obj.Lifetime)
        data.speed = tostring(obj.Speed)
        data.acceleration = vectorTable(obj.Acceleration)
    elseif obj:IsA("Decal") then
        data.texture = obj.Texture
        data.face = tostring(obj.Face)
        data.transparency = obj.Transparency
    elseif obj:IsA("Sound") then
        data.soundId = obj.SoundId
        data.playbackSpeed = obj.PlaybackSpeed
        data.volume = obj.Volume
    end

    return data
end

local function trackProjectile(part, shot)
    if not part:IsA("BasePart") then
        return
    end

    if STATE.TrackedProjectiles[part] then
        return
    end

    local count = 0
    for _ in pairs(STATE.TrackedProjectiles) do
        count += 1
    end

    if count >= CONFIG.Ballistics.MaxTrackedProjectiles then
        return
    end

    local token = {}
    STATE.TrackedProjectiles[part] = token

    task.spawn(function()
        local startClock = os.clock()
        local interval = 1 / math.max(1, CONFIG.Ballistics.SamplesPerSecond)
        local lastVelocity = nil
        local lastTime = nil
        local sampleIndex = 0

        while part.Parent
        and STATE.TrackedProjectiles[part] == token
        and os.clock() - startClock <= CONFIG.Ballistics.MaxTrackSeconds do

            sampleIndex += 1

            local now = os.clock()
            local velocity = part.AssemblyLinearVelocity
            local acceleration = nil

            if lastVelocity and lastTime then
                local dt = now - lastTime
                if dt > 0.0001 then
                    acceleration = (velocity - lastVelocity) / dt
                end
            end

            addRecord("Ballistics", "trajectory_sample", {
                shotId = shot and shot.id or nil,
                projectile = safeFullName(part),
                sample = sampleIndex,
                elapsed = now - startClock,
                position = vectorTable(part.Position),
                velocity = vectorTable(velocity),
                acceleration = vectorTable(acceleration),
                material = tostring(part.Material),
            })

            lastVelocity = velocity
            lastTime = now

            task.wait(interval)
        end

        STATE.TrackedProjectiles[part] = nil
    end)

    local touchConnection
    touchConnection = part.Touched:Connect(function(hit)
        if not hit then return end

        local beforeVelocity = part.AssemblyLinearVelocity

        addRecord("Ballistics", "projectile_touched", {
            shotId = shot and shot.id or nil,
            projectile = safeFullName(part),
            projectilePosition = vectorTable(part.Position),
            velocityAtTouch = vectorTable(beforeVelocity),

            hit = {
                name = hit.Name,
                class = hit.ClassName,
                path = safeFullName(hit),
                material = hit:IsA("BasePart") and tostring(hit.Material) or nil,
                position = hit:IsA("BasePart") and vectorTable(hit.Position) or nil,
                size = hit:IsA("BasePart") and vectorTable(hit.Size) or nil,
            },
        })

        task.delay(0.03, function()
            if part and part.Parent then
                addRecord("Ballistics", "post_impact_velocity", {
                    shotId = shot and shot.id or nil,
                    projectile = safeFullName(part),
                    velocity = vectorTable(part.AssemblyLinearVelocity),
                    position = vectorTable(part.Position),
                })
            end
        end)
    end)

    task.delay(CONFIG.Ballistics.MaxTrackSeconds + 0.5, function()
        if touchConnection then
            pcall(function()
                touchConnection:Disconnect()
            end)
        end
    end)
end

local function observeShotArtifact(obj)
    if not CONFIG.Ballistics.Enabled then
        return
    end

    local shot, dt = nearestActiveShot()

    if not shot then
        return
    end

    if not isBallisticLike(obj) then
        return
    end

    shot.artifacts += 1

    addRecord("Ballistics", "shot_artifact", {
        shotId = shot.id,
        timeAfterShot = dt,
        artifact = describeArtifact(obj),
    })

    if obj:IsA("BasePart") then
        trackProjectile(obj, shot)
    end

    -- Captura efeitos que aparecem logo após o objeto principal.
    if obj:IsA("Decal")
    or obj:IsA("ParticleEmitter")
    or obj:IsA("Sound")
    or obj:IsA("Beam")
    or obj:IsA("Trail") then

        addRecord("Impacts", "effect", {
            shotId = shot.id,
            timeAfterShot = dt,
            effect = describeArtifact(obj),
        })
    end
end

local BoundTools = setmetatable({}, { __mode = "k" })

local function bindToolBallistics(tool)
    if not CONFIG.Ballistics.Enabled
    or not tool
    or not tool:IsA("Tool")
    or BoundTools[tool] then
        return
    end

    BoundTools[tool] = true

    local activatedConnection = tool.Activated:Connect(function()
        beginShot(tool, "Tool.Activated")
    end)

    Connections[#Connections + 1] = activatedConnection

    local deactivatedConnection = tool.Deactivated:Connect(function()
        addRecord("Ballistics", "tool_deactivated", {
            tool = tool.Name,
            path = safeFullName(tool),
            at = unix(),
        })
    end)

    Connections[#Connections + 1] = deactivatedConnection
end

local function bindExistingWeaponTools()
    local roots = {
        ReplicatedStorage,
        Workspace,
        LocalPlayer:FindFirstChildOfClass("Backpack"),
        LocalPlayer.Character,
    }

    for _, root in ipairs(roots) do
        if root then
            if root:IsA("Tool") then
                bindToolBallistics(root)
            end

            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("Tool") then
                    bindToolBallistics(obj)
                end
            end
        end
    end
end

local function startBallisticsObservers()
    if not CONFIG.Ballistics.Enabled then
        return
    end

    bindExistingWeaponTools()

    Connections[#Connections + 1] = Workspace.DescendantAdded:Connect(function(obj)
        observeShotArtifact(obj)

        if obj:IsA("Tool") then
            bindToolBallistics(obj)
        end
    end)

    Connections[#Connections + 1] = ReplicatedStorage.DescendantAdded:Connect(function(obj)
        if obj:IsA("Tool") then
            bindToolBallistics(obj)
        end
    end)

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if backpack then
        Connections[#Connections + 1] = backpack.ChildAdded:Connect(function(obj)
            if obj:IsA("Tool") then
                bindToolBallistics(obj)
            end
        end)
    end

    Connections[#Connections + 1] = LocalPlayer.CharacterAdded:Connect(function(character)
        task.defer(function()
            for _, obj in ipairs(character:GetDescendants()) do
                if obj:IsA("Tool") then
                    bindToolBallistics(obj)
                end
            end
        end)

        Connections[#Connections + 1] = character.ChildAdded:Connect(function(obj)
            if obj:IsA("Tool") then
                bindToolBallistics(obj)
            end
        end)
    end)

    addRecord("Analysis", "ballistics_observer_started", {
        shotWindow = CONFIG.Ballistics.ShotWindow,
        samplesPerSecond = CONFIG.Ballistics.SamplesPerSecond,
        maxTrackSeconds = CONFIG.Ballistics.MaxTrackSeconds,
        probeDistance = CONFIG.Ballistics.ProbeDistance,
        note = "Observational only; no RemoteEvent/RemoteFunction is fired or invoked.",
    })
end

--==============================================================
-- SCANNER LOOP
--==============================================================

local function runScanner()
    if STATE.Running then
        return
    end

    disconnectAll()

    STATE.Running = true
    STATE.StopRequested = false
    STATE.Pass = 0
    STATE.StartClock = now()
    STATE.Records = {}
    STATE.Seen = {}
    STATE.SeenObjects = setmetatable({}, {__mode = "k"})
    STATE.RecordCount = 0
    STATE.ApproxBytes = 0
    STATE.BaselineDone = false
    STATE.LastError = nil

    Progress.Size = UDim2.fromScale(0, 1)

    setStatus(
        "Iniciando análise...",
        Color3.fromRGB(245, 245, 245)
    )

    addRecord({
        kind = "session_start",
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
    }, false)

    attachPlayerObservers()

    local ok, err = pcall(function()
        baselineScan()

        while STATE.Running
        and not STATE.StopRequested
        and canAdd() do

            incrementalPass()

            local elapsed = 0

            while elapsed < CONFIG.PassInterval do
                if STATE.StopRequested or not STATE.Running then
                    break
                end

                local dt = RunService.Heartbeat:Wait()
                elapsed += dt
            end
        end
    end)

    if not ok then
        STATE.LastError = tostring(err)

        addRecord({
            kind = "scanner_error",
            detail = tostring(err),
        }, false)

        setStatus(
            "Erro: " .. tostring(err),
            Color3.fromRGB(225, 75, 80)
        )
    elseif STATE.ApproxBytes >= CONFIG.MaxBytes then
        setStatus(
            "Limite atingido • pronto para enviar",
            Color3.fromRGB(80, 210, 115)
        )
    elseif STATE.StopRequested then
        setStatus(
            "Interrompido • pronto para enviar",
            Color3.fromRGB(230, 170, 65)
        )
    else
        setStatus(
            "Finalizado • pronto para enviar",
            Color3.fromRGB(80, 210, 115)
        )
    end

    STATE.Running = false

    addRecord({
        kind = "session_end",
        stopped = STATE.StopRequested,
        error = STATE.LastError,
        duration = now() - STATE.StartClock,
    }, false)

    updateInfo()
end

--==============================================================
-- BUTTONS
--==============================================================

StartButton.MouseButton1Click:Connect(function()
    if STATE.Running then
        setStatus("Scanner já está rodando")
        return
    end

    task.spawn(runScanner)
end)

StopButton.MouseButton1Click:Connect(function()
    if not STATE.Running then
        setStatus("Scanner não está rodando")
        return
    end

    STATE.StopRequested = true
    setStatus(
        "Interrompendo...",
        Color3.fromRGB(230, 170, 65)
    )
end)

UploadButton.MouseButton1Click:Connect(function()
    if STATE.RecordCount <= 0 then
        setStatus(
            "Nenhum dado para enviar",
            Color3.fromRGB(230, 170, 65)
        )
        return
    end

    task.spawn(uploadReport)
end)

--==============================================================
-- FINAL UI STATE
--==============================================================

updateInfo()
setStatus("Pronto para iniciar")

--==============================================================
-- GLOBAL DEBUG API (opcional)
--==============================================================

getgenv = getgenv or function()
    return _G
end

local env = getgenv()

env.CafeinaWeaponResearch = {
    Start = function()
        if not STATE.Running then
            task.spawn(runScanner)
        end
    end,

    Stop = function()
        STATE.StopRequested = true
    end,

    ExportMetadata = function()
        return buildMetadata()
    end,

    Stats = function()
        return {
            running = STATE.Running,
            pass = STATE.Pass,
            records = STATE.RecordCount,
            approxBytes = STATE.ApproxBytes,
            status = STATE.LastStatus,
            error = STATE.LastError,
        }
    end,
}


-- Inicializa a observação de tiros imediatamente.
task.defer(function()
    local ok, err = pcall(startBallisticsObservers)
    if not ok then
        STATE.LastError = "Ballistics observer: " .. tostring(err)
        warn("[CAFEÍNA] Ballistics observer error: " .. tostring(err))
    end
end)

print("[CAFEÍNA] Weapon Research V1.0 carregado.")
