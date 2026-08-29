--[[
    CAFEÍNA • SMART SCANNER V4
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

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
    ScanInterval = 1.25,
    MaxPasses = 60,
    MaxRecords = 120000,
    MaxBytesApprox = 70 * 1024 * 1024,

    -- Prioridades
    TrackRemotes = true,
    TrackSoldiers = true,
    TrackTools = true,
    TrackTycoon = true,
    TrackPlayerData = true,
    TrackBlaster = true,
    TrackInteractions = true,
    TrackInterestingAttributes = true,

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
    UploadURL = "", -- ex: "https://seu-site.com/api/scanner/upload"
    UploadChunkBytes = 1800000,
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

    Added = 0,
    Changed = 0,
    Removed = 0,
    NewUseful = 0,

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

local function recordKey(category, obj, suffix)
    return category .. "|" .. safeFullName(obj) .. "|" .. tostring(suffix or "")
end

local function addRecord(category, kind, key, data)
    if #STATE.Records >= CONFIG.MaxRecords then
        return false
    end

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
    elseif kind == "changed" then
        STATE.Changed += 1
    elseif kind == "removed" then
        STATE.Removed += 1
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

    STATE.Seen[key] = true

    if STATE.LastSnapshot[key] == nil then
        if addRecord(category, "baseline", key, data) then
            STATE.NewUseful += 1
        end
        STATE.LastSnapshot[key] = fp
    elseif STATE.LastSnapshot[key] ~= fp then
        if addRecord(category, "changed", key, data) then
            STATE.NewUseful += 1
        end
        STATE.LastSnapshot[key] = fp
    end
end

local function scanDescendants(root, category, predicate)
    if not root then return end

    for _, obj in ipairs(root:GetDescendants()) do
        if STATE.StopRequested then break end
        local ok = true
        if predicate then
            ok = predicate(obj)
        end
        if ok then
            consider(category, obj, false)
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
        if not (
            string.find(p, "tycoon", 1, true)
            or string.find(p, "button", 1, true)
            or string.find(p, "collector", 1, true)
            or string.find(p, "purchase", 1, true)
        ) then
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

local function detectRemoved()
    for key, _ in pairs(STATE.LastSnapshot) do
        if not STATE.Seen[key] then
            addRecord("Lifecycle", "removed", key, {path = key})
            STATE.LastSnapshot[key] = nil
        end
    end
end

--==============================================================
-- UI
--==============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaSmartScannerV4"
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
title.Text = "CAFEÍNA • SMART SCANNER V4"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(245,245,245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 24)
status.Position = UDim2.fromOffset(10, 35)
status.BackgroundTransparency = 1
status.Text = "● PRONTO"
status.Font = Enum.Font.GothamBold
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(140,255,170)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main

local detail = Instance.new("TextLabel")
detail.Size = UDim2.new(1, -20, 0, 40)
detail.Position = UDim2.fromOffset(10, 58)
detail.BackgroundTransparency = 1
detail.Text = "Aguardando início"
detail.Font = Enum.Font.Gotham
detail.TextSize = 12
detail.TextColor3 = Color3.fromRGB(205,205,210)
detail.TextWrapped = true
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.TextYAlignment = Enum.TextYAlignment.Top
detail.Parent = main

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -20, 0, 7)
barBg.Position = UDim2.fromOffset(10, 102)
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

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -20, 0, 22)
info.Position = UDim2.fromOffset(10, 113)
info.BackgroundTransparency = 1
info.Text = "0 registros • 0 novos • 0 MB"
info.Font = Enum.Font.Gotham
info.TextSize = 11
info.TextColor3 = Color3.fromRGB(175,175,180)
info.TextXAlignment = Enum.TextXAlignment.Left
info.Parent = main

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

local function setStatus(label, detailText, color)
    STATE.LastStatus = label
    STATE.LastDetail = detailText

    status.Text = "● " .. string.upper(label)
    detail.Text = detailText
    if color then
        status.TextColor3 = color
    end
end

local function refreshInfo()
    local mb = STATE.ApproxBytes / 1024 / 1024
    info.Text = string.format(
        "%d registros • %d novos • %.1f MB • passe %d/%d",
        #STATE.Records,
        STATE.NewUseful,
        mb,
        STATE.Pass,
        CONFIG.MaxPasses
    )
    bar.Size = UDim2.fromScale(math.clamp(STATE.Pass / CONFIG.MaxPasses, 0, 1), 1)
end

--==============================================================
-- EXPORT
--==============================================================

local function buildExport()
    return {
        schemaVersion = 4,
        scanner = "CAFEINA SMART SCANNER V4",
        generatedAt = os.time(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        clientVisibleOnly = true,

        scan = {
            complete = not STATE.StopRequested and STATE.Pass >= CONFIG.MaxPasses,
            interrupted = STATE.StopRequested,
            passes = STATE.Pass,
            records = #STATE.Records,
            added = STATE.Added,
            changed = STATE.Changed,
            removed = STATE.Removed,
            newUseful = STATE.NewUseful,
            approxBytes = STATE.ApproxBytes,
            categories = STATE.CategoryCount,
        },

        records = STATE.Records,
    }
end

local function resetState()
    STATE.StopRequested = false
    STATE.Pass = 0
    STATE.StartedAt = now()
    STATE.FinishedAt = 0
    STATE.Records = {}
    STATE.Seen = {}
    STATE.LastSnapshot = {}
    STATE.Added = 0
    STATE.Changed = 0
    STATE.Removed = 0
    STATE.NewUseful = 0
    STATE.CategoryCount = {}
    STATE.ApproxBytes = 0
end

local function runPass()
    STATE.Pass += 1
    STATE.Seen = {}

    setStatus("Analisando", "Remotes e serviços...", Color3.fromRGB(255,220,120))
    scanRemotes()
    if STATE.StopRequested then return end

    setStatus("Analisando", "Armas e BlasterSystem...", Color3.fromRGB(255,220,120))
    scanBlaster()
    if STATE.StopRequested then return end

    setStatus("Analisando", "Soldados, NPCs e ciclo de vida...", Color3.fromRGB(255,220,120))
    scanSoldiers()
    if STATE.StopRequested then return end

    setStatus("Analisando", "PlayerData e valores dinâmicos...", Color3.fromRGB(255,220,120))
    scanPlayerData()
    if STATE.StopRequested then return end

    setStatus("Analisando", "Tycoon: compra, coleta e custos...", Color3.fromRGB(255,220,120))
    scanTycoon()
    if STATE.StopRequested then return end

    setStatus("Analisando", "Tools e configurações úteis...", Color3.fromRGB(255,220,120))
    scanTools()
    if STATE.StopRequested then return end

    setStatus("Analisando", "Interações relevantes...", Color3.fromRGB(255,220,120))
    scanInteractions()

    detectRemoved()
    refreshInfo()
end

local function scannerLoop()
    if STATE.Running then
        return
    end

    resetState()
    STATE.Running = true

    setStatus("Iniciando", "Preparando scanner inteligente...", Color3.fromRGB(120,190,255))

    task.spawn(function()
        while STATE.Running and not STATE.StopRequested do
            if STATE.Pass >= CONFIG.MaxPasses then
                break
            end
            if #STATE.Records >= CONFIG.MaxRecords then
                setStatus("Limite atingido", "Limite máximo de registros alcançado.", Color3.fromRGB(255,170,90))
                break
            end
            if STATE.ApproxBytes >= CONFIG.MaxBytesApprox then
                setStatus("Limite atingido", "Limite aproximado de tamanho alcançado.", Color3.fromRGB(255,170,90))
                break
            end

            local ok, err = pcall(runPass)
            if not ok then
                setStatus("Erro", tostring(err), Color3.fromRGB(255,100,100))
                STATE.Running = false
                return
            end

            if STATE.StopRequested then
                break
            end

            setStatus(
                "Observando",
                string.format("Passe %d concluído. Aguardando novas mudanças...", STATE.Pass),
                Color3.fromRGB(140,255,170)
            )
            refreshInfo()

            local elapsed = 0
            while elapsed < CONFIG.ScanInterval and not STATE.StopRequested do
                task.wait(0.1)
                elapsed += 0.1
            end
        end

        STATE.Running = false
        STATE.FinishedAt = now()

        refreshInfo()

        if STATE.StopRequested then
            setStatus(
                "Interrompido",
                string.format("Scan parado com %d registros úteis.", #STATE.Records),
                Color3.fromRGB(255,145,145)
            )
        else
            setStatus(
                "Concluído",
                string.format("Scan finalizado: %d registros, %d alterações.", #STATE.Records, STATE.Changed),
                Color3.fromRGB(140,255,170)
            )
            bar.Size = UDim2.fromScale(1,1)
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

local function sendExport()
    if STATE.Sending then return end
    if #STATE.Records == 0 then
        setStatus("Sem dados", "Faça um scan antes de enviar.", Color3.fromRGB(255,180,100))
        return
    end

    if CONFIG.UploadURL == "" then
        local payload = HttpService:JSONEncode(buildExport())
        if setclipboard then
            setclipboard(payload)
            setStatus("Copiado", "UploadURL vazio: JSON completo copiado.", Color3.fromRGB(140,255,170))
        else
            setStatus("Sem URL", "Configure CONFIG.UploadURL para enviar ao site.", Color3.fromRGB(255,180,100))
        end
        return
    end

    local req = getRequest()
    if not req then
        setStatus("Erro", "Executor não oferece função HTTP compatível.", Color3.fromRGB(255,100,100))
        return
    end

    STATE.Sending = true
    sendBtn.Text = "ENVIANDO..."

    task.spawn(function()
        local payload
        local okEncode, encodeErr = pcall(function()
            payload = HttpService:JSONEncode(buildExport())
        end)

        if not okEncode then
            STATE.Sending = false
            sendBtn.Text = "ENVIAR"
            setStatus("Erro", "Falha ao serializar: " .. tostring(encodeErr), Color3.fromRGB(255,100,100))
            return
        end

        setStatus("Enviando", string.format("%.1f MB preparados para envio.", #payload/1024/1024), Color3.fromRGB(120,190,255))

        local ok, response = pcall(function()
            return req({
                Url = CONFIG.UploadURL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = payload
            })
        end)

        STATE.Sending = false
        sendBtn.Text = "ENVIAR"

        if ok and response and tonumber(response.StatusCode or response.Status or 0) and tonumber(response.StatusCode or response.Status or 0) >= 200 and tonumber(response.StatusCode or response.Status or 0) < 300 then
            setStatus("Enviado", "Dados enviados com sucesso.", Color3.fromRGB(140,255,170))
        else
            local msg = "Falha no envio."
            if response then
                msg = msg .. " HTTP " .. tostring(response.StatusCode or response.Status or "?")
            end
            setStatus("Erro de envio", msg, Color3.fromRGB(255,100,100))
        end
    end)
end

--==============================================================
-- BUTTONS
--==============================================================

startBtn.MouseButton1Click:Connect(function()
    if STATE.Running then
        setStatus("Já executando", "O scanner já está ativo.", Color3.fromRGB(255,220,120))
        return
    end
    scannerLoop()
end)

stopBtn.MouseButton1Click:Connect(function()
    if not STATE.Running then
        setStatus("Parado", "Nenhum scan ativo no momento.", Color3.fromRGB(190,190,195))
        return
    end

    STATE.StopRequested = true
    setStatus("Interrompendo", "Finalizando o passe atual com segurança...", Color3.fromRGB(255,145,145))
end)

sendBtn.MouseButton1Click:Connect(function()
    if STATE.Running then
        setStatus("Scan ativo", "Interrompa ou aguarde o scan terminar antes de enviar.", Color3.fromRGB(255,220,120))
        return
    end
    sendExport()
end)

refreshInfo()
