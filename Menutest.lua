--==============================================================--
-- CAFEÍNA • GAME FOCUSED SCAN V2 • MOBILE
-- Scanner direcionado ao jogo analisado
--
-- Objetivo:
--   Coletar somente informações visíveis ao cliente e relevantes
--   para a estrutura do jogo:
--   • BlasterSystem / armas
--   • Soldiers / bots
--   • Tycoons / botões / coletores / compras
--   • Remotes
--   • Tools
--   • PlayerData/leaderstats/backpack
--   • GUI de munição/autofire
--
-- Não invoca remotes, não altera objetos e não tenta ler
-- dados exclusivamente do servidor.
--
-- Fluxo:
--   SCAN -> coleta contínua -> INTERROMPER opcional -> ENVIAR
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

    -- Compatível com backend que aceita requests abaixo de ~6 MB.
    CHUNK_TARGET_BYTES = 3500000,
    CHUNK_HARD_BYTES = 5500000,

    PASS_INTERVAL = 2.0,
    STABLE_PASSES_REQUIRED = 4,
    YIELD_EVERY = 100,

    MEMORY_FALLBACK_LIMIT = 64 * 1024 * 1024,

    UPLOAD_RETRIES = 4,
    RETRY_DELAY = 1.25,

    PROFILE_NAME = "game-focused-v2",
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

local SeenSignatures = {}
local TotalRecordedBytes = 0
local TotalRecords = 0
local TotalPasses = 0
local StablePasses = 0

local CurrentChunk = {}
local CurrentChunkBytes = 2
local StoredChunks = {}
local MemoryChunks = {}

local CategoryCounts = {}
local LastPassCounts = {}

local SessionFolder = "CafeinaFocused_" .. tostring(os.time())

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

local function safeFullName(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    if ok then
        return result
    end
    return inst and inst.Name or "?"
end

local function startsWith(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

local function lower(text)
    return string.lower(tostring(text or ""))
end

local function encodedSize(value)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    if not ok then
        return 0, nil
    end

    return #encoded, encoded
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
        if count > 80 then
            break
        end

        output[safeString(key, 120)] = safeString(value, 800)
    end

    return output
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

    if typeof(value) == "Instance" then
        return {
            kind = "Instance",
            path = safeFullName(value),
            className = value.ClassName,
        }
    end

    return safeString(value, 1600)
end

local function vector3(v)
    return {
        x = math.floor(v.X * 1000 + 0.5) / 1000,
        y = math.floor(v.Y * 1000 + 0.5) / 1000,
        z = math.floor(v.Z * 1000 + 0.5) / 1000,
    }
end

local function compactProperties(inst)
    local p = {}

    if inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    then
        p.remoteType = inst.ClassName

    elseif inst:IsA("Tool") then
        p.requiresHandle = inst.RequiresHandle
        p.canBeDropped = inst.CanBeDropped
        p.toolTip = safeString(inst.ToolTip, 300)

    elseif inst:IsA("ProximityPrompt") then
        p.actionText = safeString(inst.ActionText, 300)
        p.objectText = safeString(inst.ObjectText, 300)
        p.enabled = inst.Enabled
        p.holdDuration = inst.HoldDuration
        p.maxActivationDistance = inst.MaxActivationDistance
        p.requiresLineOfSight = inst.RequiresLineOfSight
        p.keyboardKeyCode = tostring(inst.KeyboardKeyCode)
        p.gamepadKeyCode = tostring(inst.GamepadKeyCode)

    elseif inst:IsA("Humanoid") then
        p.health = inst.Health
        p.maxHealth = inst.MaxHealth
        p.walkSpeed = inst.WalkSpeed
        p.jumpPower = inst.JumpPower
        p.rigType = tostring(inst.RigType)

    elseif inst:IsA("BasePart") then
        -- Para não explodir o tamanho, propriedades físicas só são
        -- mantidas em objetos já filtrados como relevantes.
        p.anchored = inst.Anchored
        p.canCollide = inst.CanCollide
        p.canTouch = inst.CanTouch
        p.canQuery = inst.CanQuery
        p.transparency = inst.Transparency
        p.position = vector3(inst.Position)
        p.size = vector3(inst.Size)

    elseif inst:IsA("GuiObject") then
        p.visible = inst.Visible

        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            p.text = safeString(inst.Text, 600)
        end

    elseif inst:IsA("Player") then
        p.displayName = safeString(inst.DisplayName, 200)
        p.userId = inst.UserId
        p.team = inst.Team and inst.Team.Name or nil

    elseif inst:IsA("ObjectValue") then
        local value = inst.Value
        if value then
            p.objectPath = safeFullName(value)
            p.objectClass = value.ClassName
        end
    end

    return p
end

--==============================================================--
-- CLASSIFICAÇÃO DIRECIONADA
--==============================================================--

local function getCategory(inst)
    local path = safeFullName(inst)
    local pathLower = lower(path)
    local nameLower = lower(inst.Name)

    -- 1. Sistema central de combate.
    if string.find(pathLower, "replicatedstorage.blastersystem", 1, true) then
        return "BlasterSystem", 100
    end

    -- 2. API/remotes do jogo.
    if inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    then
        return "Remotes", 95
    end

    -- 3. Soldados/bots.
    if string.find(pathLower, "workspace.soldiers", 1, true) then
        return "Soldiers", 95
    end

    -- 4. Tycoon.
    if string.find(pathLower, "workspace.tycoons", 1, true) then
        return "Tycoons", 90
    end

    -- 5. Ferramentas/armas.
    if inst:IsA("Tool") or inst:FindFirstAncestorOfClass("Tool") then
        return "Tools", 90
    end

    -- 6. Informações do jogador relevantes para gameplay.
    if startsWith(path, "Players.") then
        if string.find(pathLower, ".leaderstats", 1, true)
            or string.find(pathLower, ".backpack", 1, true)
            or string.find(pathLower, ".character", 1, true)
        then
            if inst:IsA("ValueBase")
                or inst:IsA("Tool")
                or inst:IsA("Humanoid")
                or inst:IsA("Folder")
                or inst:IsA("Model")
            then
                return "PlayerData", 85
            end
        end
    end

    -- 7. UI ligada a munição, reload e autofire.
    if startsWith(path, "Players." .. LocalPlayer.Name .. ".PlayerGui")
        or startsWith(path, "StarterGui")
    then
        if string.find(pathLower, "ammo", 1, true)
            or string.find(pathLower, "reload", 1, true)
            or string.find(pathLower, "autofire", 1, true)
            or string.find(pathLower, "crosshair", 1, true)
        then
            return "CombatUI", 80
        end
    end

    -- 8. Prompts e touch triggers fora das áreas acima.
    if inst:IsA("ProximityPrompt") then
        return "Prompts", 65
    end

    if inst:IsA("TouchTransmitter") then
        return "TouchTriggers", 60
    end

    -- 9. Valores com nomes economicamente importantes.
    if inst:IsA("ValueBase") then
        if string.find(nameLower, "money", 1, true)
            or string.find(nameLower, "cash", 1, true)
            or string.find(nameLower, "rebirth", 1, true)
            or string.find(nameLower, "kill", 1, true)
            or string.find(nameLower, "ammo", 1, true)
        then
            return "GameValues", 55
        end
    end

    return nil, 0
end

local function relationSnapshot(inst)
    local rel = {}

    local parent = inst.Parent
    if parent then
        rel.parent = {
            path = safeFullName(parent),
            className = parent.ClassName,
        }
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
    if tycoonRoot and inst:IsDescendantOf(tycoonRoot) then
        local current = inst
        while current and current.Parent ~= tycoonRoot do
            current = current.Parent
        end
        if current then
            rel.tycoon = current.Name
        end
    end

    local soldiersRoot = Workspace:FindFirstChild("Soldiers")
    if soldiersRoot and inst:IsDescendantOf(soldiersRoot) then
        local current = inst
        while current and current.Parent ~= soldiersRoot do
            current = current.Parent
        end
        if current then
            rel.soldier = current.Name
        end
    end

    return rel
end

local function snapshot(inst, passNumber, category, priority)
    return {
        recordType = "focused_instance_snapshot",
        profile = CONFIG.PROFILE_NAME,
        observedAt = os.time(),
        pass = passNumber,

        category = category,
        priority = priority,

        path = safeFullName(inst),
        parentPath = inst.Parent and safeFullName(inst.Parent) or "",
        name = safeString(inst.Name, 300),
        className = inst.ClassName,
        childCount = #inst:GetChildren(),

        attributes = attributesSnapshot(inst),
        value = valueSnapshot(inst),
        properties = compactProperties(inst),
        relations = relationSnapshot(inst),
    }
end

local function signatureFor(record)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            record.path,
            record.className,
            record.childCount,
            record.category,
            record.attributes,
            record.value,
            record.properties,
            record.relations,
        })
    end)

    if ok then
        return encoded
    end

    return record.path
        .. "|" .. record.className
        .. "|" .. tostring(record.childCount)
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

local function storeChunk(chunk, encoded)
    local index = #StoredChunks + #MemoryChunks + 1

    if CAN_SPOOL_TO_DISK and ensureFolder() then
        local path =
            SessionFolder
            .. "/chunk_"
            .. string.format("%05d", index)
            .. ".json"

        local ok = pcall(writefileFn, path, encoded)
        if ok then
            StoredChunks[#StoredChunks + 1] = path
            return true
        end
    end

    local projected = #encoded

    for _, item in ipairs(MemoryChunks) do
        projected += item.bytes
    end

    if projected > CONFIG.MEMORY_FALLBACK_LIMIT then
        return false, "Sem armazenamento local; limite de memória atingido"
    end

    MemoryChunks[#MemoryChunks + 1] = {
        objects = chunk,
        bytes = #encoded,
    }

    return true
end

local function flushChunk()
    if #CurrentChunk == 0 then
        return true
    end

    local _, encoded = encodedSize(CurrentChunk)

    if not encoded then
        return false, "Falha ao codificar bloco"
    end

    if #encoded > CONFIG.CHUNK_HARD_BYTES then
        return false, "Bloco excedeu limite seguro de upload"
    end

    local ok, err = storeChunk(CurrentChunk, encoded)
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

    local signature = signatureFor(record)
    local key = record.category .. "|" .. record.path
    local previous = SeenSignatures[key]

    if previous == signature then
        return true, false
    end

    if TotalRecordedBytes + CurrentChunkBytes + bytes > CONFIG.MAX_TOTAL_BYTES then
        return false, "LIMIT_REACHED"
    end

    if CurrentChunkBytes + bytes > CONFIG.CHUNK_TARGET_BYTES
        and #CurrentChunk > 0
    then
        local ok, err = flushChunk()
        if not ok then
            return false, err
        end
    end

    SeenSignatures[key] = signature
    CurrentChunk[#CurrentChunk + 1] = record
    CurrentChunkBytes += bytes
    TotalRecordedBytes += bytes
    TotalRecords += 1

    CategoryCounts[record.category] =
        (CategoryCounts[record.category] or 0) + 1

    return true, true
end

local function addHeader()
    local header = {
        recordType = "focused_scan_header",
        scanner = "CAFEINA",
        version = "V2-GAME-FOCUSED",
        profile = CONFIG.PROFILE_NAME,
        clientVisibleOnly = true,
        passiveOnly = true,
        remoteInvocation = false,

        generatedAtUnix = os.time(),

        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,

        focus = {
            "BlasterSystem",
            "Remotes",
            "Soldiers",
            "Tycoons",
            "Tools",
            "PlayerData",
            "CombatUI",
            "Prompts",
            "TouchTriggers",
            "GameValues",
        },
    }

    local bytes = encodedSize(header)
    CurrentChunk[#CurrentChunk + 1] = header
    CurrentChunkBytes += bytes
    TotalRecordedBytes += bytes
    TotalRecords += 1
end

--==============================================================--
-- ENUMERAÇÃO
--==============================================================--

local function roots()
    local output = {
        ReplicatedStorage,
        Workspace,
        Players,
        StarterPack,
        StarterGui,
    }

    return output
end

local function enumerateRelevantObjects()
    local output = {}
    local seen = {}

    local function consider(inst)
        if not inst or seen[inst] then
            return
        end

        local category, priority = getCategory(inst)
        if category then
            seen[inst] = true
            output[#output + 1] = {
                instance = inst,
                category = category,
                priority = priority,
            }
        end
    end

    for _, root in ipairs(roots()) do
        consider(root)

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

--==============================================================--
-- UI
--==============================================================--

local old = PlayerGui:FindFirstChild("CafeinaFocusedScan")
if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaFocusedScan"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(382, 112)
Main.Position = UDim2.new(0.5, -191, 0.14, 0)
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

local ScanButton = makeButton("SCAN", 8, 98)
local StopButton = makeButton("INTERROMPER", 114, 112)
local SendButton = makeButton("ENVIAR AO SITE", 234, 140)

StopButton.BackgroundColor3 = Color3.fromRGB(70, 24, 28)
StopButton.TextColor3 = Color3.fromRGB(255, 150, 155)

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -16, 0, 21)
StatusText.Position = UDim2.fromOffset(8, 47)
StatusText.BackgroundTransparency = 1
StatusText.TextColor3 = Color3.fromRGB(175, 175, 185)
StatusText.Text = "Pronto • scanner direcionado ao jogo"
StatusText.TextSize = 9
StatusText.Font = Enum.Font.Gotham
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextTruncate = Enum.TextTruncate.AtEnd
StatusText.Parent = Main

local ProgressBG = Instance.new("Frame")
ProgressBG.Size = UDim2.new(1, -16, 0, 12)
ProgressBG.Position = UDim2.fromOffset(8, 77)
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
PercentText.Position = UDim2.fromOffset(8, 94)
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
    PercentText.Text =
        tostring(math.floor(fraction * 100 + 0.5)) .. "%"
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

-- Mobile drag.
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

    SeenSignatures = {}
    TotalRecordedBytes = 0
    TotalRecords = 0
    TotalPasses = 0
    StablePasses = 0

    CurrentChunk = {}
    CurrentChunkBytes = 2
    StoredChunks = {}
    MemoryChunks = {}

    CategoryCounts = {}
    LastPassCounts = {}

    SessionFolder = "CafeinaFocused_" .. tostring(os.time())

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

        ScanButton.Text = "SCAN"
        ScanButton.Active = true

        setProgress(
            "Erro ao fechar Scan: " .. tostring(err),
            0
        )

        return
    end

    if TotalRecords <= 1 then
        ScanComplete = false
        setSendEnabled(false)

        ScanButton.Text = "SCAN"
        ScanButton.Active = true

        setProgress(
            "Scan interrompido sem registros úteis",
            0
        )

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

    CancelGeneration += 1
    ScanRunning = false

    StopButton.Active = false
    ScanButton.Active = false

    setProgress(
        "Interrompendo e fechando conteúdo coletado...",
        math.min(TotalRecordedBytes / CONFIG.MAX_TOTAL_BYTES, 0.95)
    )

    -- Chamado fora do loop depois de invalidar a geração.
    finishScan("INTERRUPTED")
end

--==============================================================--
-- SCAN CONTÍNUO DIRECIONADO
--==============================================================--

local function runFocusedScan()
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
            local changedThisPass = 0
            local total = math.max(#objects, 1)

            LastPassCounts = {}

            for i, item in ipairs(objects) do
                if generation ~= CancelGeneration or not ScanRunning then
                    return
                end

                local inst = item.instance

                if inst and inst.Parent then
                    local okSnapshot, record = pcall(
                        snapshot,
                        inst,
                        passNumber,
                        item.category,
                        item.priority
                    )

                    if okSnapshot and record then
                        LastPassCounts[item.category] =
                            (LastPassCounts[item.category] or 0) + 1

                        local okAdd, result = addRecord(record)

                        if not okAdd then
                            if result == "LIMIT_REACHED" then
                                finishScan("LIMIT_REACHED")
                                return
                            end

                            ScanRunning = false
                            ScanComplete = false
                            setStopEnabled(false)
                            setSendEnabled(false)

                            ScanButton.Text = "SCAN"
                            ScanButton.Active = true

                            setProgress(
                                "Erro: " .. tostring(result),
                                0
                            )

                            return
                        end

                        if result then
                            changedThisPass += 1
                        end
                    end
                end

                if i % CONFIG.YIELD_EVERY == 0 then
                    local passProgress = i / total
                    local capacityProgress = math.min(
                        TotalRecordedBytes / CONFIG.MAX_TOTAL_BYTES,
                        0.95
                    )

                    local visual =
                        math.max(
                            capacityProgress,
                            passProgress * 0.82
                        )

                    setProgress(
                        "Scan " .. tostring(passNumber)
                        .. " • " .. tostring(i)
                        .. "/" .. tostring(#objects)
                        .. " • " .. tostring(changedThisPass)
                        .. " mudanças"
                        .. " • " .. readableSize(TotalRecordedBytes),
                        visual
                    )

                    task.wait()
                end
            end

            if changedThisPass == 0 then
                StablePasses += 1
            else
                StablePasses = 0
            end

            if StablePasses >= CONFIG.STABLE_PASSES_REQUIRED then
                finishScan("STABLE")
                return
            end

            setProgress(
                "Passagem " .. tostring(passNumber)
                .. " • " .. tostring(#objects) .. " relevantes"
                .. " • " .. tostring(changedThisPass) .. " mudanças"
                .. " • estabilidade "
                .. tostring(StablePasses) .. "/"
                .. tostring(CONFIG.STABLE_PASSES_REQUIRED),
                math.min(
                    math.max(
                        TotalRecordedBytes / CONFIG.MAX_TOTAL_BYTES,
                        0.10
                    ),
                    0.95
                )
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
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = payload,
        })

        if ok and response then
            local status =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or 0
                ) or 0

            local bodyText = tostring(response.Body or "")
            local decoded = nil

            pcall(function()
                decoded = HttpService:JSONDecode(bodyText)
            end)

            if status >= 200 and status < 300 then
                return true, decoded or bodyText
            end

            lastError =
                (
                    type(decoded) == "table"
                    and (decoded.message or decoded.error)
                )
                or (
                    "HTTP "
                    .. tostring(status)
                    .. " • "
                    .. bodyText:sub(1, 300)
                )
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
                    "Cafeina_GameFocused_"
                    .. tostring(game.PlaceId)
                    .. "_"
                    .. timestamp
                    .. ".json",

                source = "cafeina-game-focused-v2",

                metadata = {
                    profile = CONFIG.PROFILE_NAME,
                    placeId = game.PlaceId,
                    gameId = game.GameId,
                    jobId = game.JobId,
                    passes = TotalPasses,
                    records = TotalRecords,
                    approximateBytes = TotalRecordedBytes,
                    interrupted = false,
                    categories = CategoryCounts,
                    clientVisibleOnly = true,
                    passiveOnly = true,
                },
            }
        )

        if not okStart
            or type(startResult) ~= "table"
            or not startResult.uploadId
        then
            UploadRunning = false
            ScanButton.Active = true
            setSendEnabled(true)

            setProgress(
                "Falha ao iniciar envio: "
                .. tostring(startResult),
                0
            )

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

                setProgress(
                    "Falha: " .. tostring(loadErr),
                    (index - 1) / totalChunks
                )

                return
            end

            setProgress(
                "Enviando • parte "
                .. tostring(index)
                .. "/"
                .. tostring(totalChunks),
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
                    "Falha na parte "
                    .. tostring(index)
                    .. ": "
                    .. tostring(chunkResult),
                    (index - 1) / totalChunks
                )

                return
            end

            task.wait()
        end

        setProgress(
            "Finalizando arquivo no site...",
            0.98
        )

        local okFinish, finishResult = doRequest(
            "POST",
            "/upload/finish",
            {
                token = CONFIG.UPLOAD_TOKEN,
                uploadId = uploadId,
                totalChunks = totalChunks,

                summary = {
                    profile = CONFIG.PROFILE_NAME,
                    objectCount = TotalRecords,
                    approximateBytes = TotalRecordedBytes,
                    passes = TotalPasses,
                    categories = CategoryCounts,
                    scanComplete = true,
                },
            }
        )

        UploadRunning = false
        ScanButton.Active = true

        if not okFinish then
            setSendEnabled(true)

            setProgress(
                "Falha ao finalizar: "
                .. tostring(finishResult),
                0.98
            )

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

        if link ~= ""
            and type(setclipboard) == "function"
        then
            pcall(setclipboard, link)
        end

        setProgress(
            link ~= ""
                and "Envio concluído • link copiado"
                or "Envio concluído",
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

    runFocusedScan()
end)

StopButton.Activated:Connect(interruptScan)
SendButton.Activated:Connect(uploadCompletedScan)
