--==============================================================--
-- CAFEÍNA • OUROBOROS MOBILE
-- Menu compacto para Android / executor
--
-- Sem scanner, sem logging, sem upload, sem coleta de dados.
-- Todas as opções iniciam desligadas.
--
-- Funções incluídas:
--   • Claim Offline Earnings
--   • Claim Codex
--   • Group Reward
--   • Base Tier Raise
--   • Auto Treadmill (servidor continua validando posição/estado)
--   • ESP de ovos
--   • ESP de máquinas
--   • WalkSpeed local
--   • Noclip local
--   • Infinite Jump local
--   • Return to Base
--   • Server Hop
--   • Auto Hatch somente para ovos que o cliente consegue confirmar
--     como pertencentes ao LocalPlayer.
--
-- Não contém:
--   • roubo de ovo/pet de outro jogador
--   • spoof de ownership
--   • bypass de validação server-side
--   • manipulação de votos/autoridade do servidor
--==============================================================--

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local Workspace          = game:GetService("Workspace")

local LP = Players.LocalPlayer

--==============================================================--
-- EXECUTOR COMPAT
--==============================================================--

local REQUEST =
    (syn and syn.request)
    or http_request
    or request
    or (http and http.request)

local function guiParent()
    if gethui then
        local ok, result = pcall(gethui)
        if ok and result then
            return result
        end
    end

    local ok, core = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and core then
        return core
    end

    return LP:WaitForChild("PlayerGui")
end

local ROOT = guiParent()

for _, child in ipairs(ROOT:GetChildren()) do
    if child.Name == "CafeinaOuroborosMobile" then
        child:Destroy()
    end
end

--==============================================================--
-- STATE
--==============================================================--

local State = {
    AutoTreadmill = false,
    AutoHatchOwned = false,
    EggESP = false,
    MachineESP = false,
    Noclip = false,
    InfiniteJump = false,
    WalkSpeedEnabled = false,
    WalkSpeed = 30,
    Minimized = false,
    Alive = true,
    Status = "Pronto",
}

local Connections = {}
local Highlights = {}

local function setStatus(text)
    State.Status = tostring(text)
end

local function remember(connection)
    table.insert(Connections, connection)
    return connection
end

--==============================================================--
-- NETWORK
--==============================================================--

local function networkingRoot()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    return packages:FindFirstChild("Networking")
end

local function resolveRemote(path)
    local root = networkingRoot()
    if not root then
        return nil
    end

    -- Alguns frameworks usam o caminho inteiro como nome do Instance.
    local direct = root:FindFirstChild(path)
    if direct then
        return direct
    end

    -- Fallback para hierarquia RF/AwayEarnings/AskCollect etc.
    local current = root

    for segment in string.gmatch(path, "[^/]+") do
        current = current and current:FindFirstChild(segment)
        if not current then
            return nil
        end
    end

    return current
end

local function callRemote(path, ...)
    local remote = resolveRemote(path)

    if not remote then
        return false, "Remote não encontrado: " .. path
    end

    if remote:IsA("RemoteFunction") then
        local ok, a, b, c = pcall(remote.InvokeServer, remote, ...)
        if not ok then
            return false, a
        end
        return true, a, b, c
    end

    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(remote.FireServer, remote, ...)
        if not ok then
            return false, err
        end
        return true
    end

    return false, "Objeto não é remote"
end

--==============================================================--
-- OWNERSHIP HELPERS
-- Só permite rotinas de ovo quando conseguimos confirmar owner local.
--==============================================================--

local OWNER_ATTRIBUTES = {
    "OwnerUserId",
    "OwnerId",
    "UserId",
    "PlayerUserId",
}

local UID_ATTRIBUTES = {
    "UID",
    "Uid",
    "uid",
    "EggUID",
    "AssetUID",
}

local function readOwner(obj)
    local current = obj

    for _ = 1, 4 do
        if not current then
            break
        end

        for _, name in ipairs(OWNER_ATTRIBUTES) do
            local value = current:GetAttribute(name)
            if tonumber(value) then
                return tonumber(value)
            end
        end

        for _, name in ipairs({"Owner", "Player", "User"}) do
            local child = current:FindFirstChild(name)
            if child then
                if child:IsA("ObjectValue") and child.Value == LP then
                    return LP.UserId
                elseif child:IsA("IntValue") or child:IsA("NumberValue") then
                    return tonumber(child.Value)
                elseif child:IsA("StringValue") then
                    if child.Value == LP.Name then
                        return LP.UserId
                    end
                    if tonumber(child.Value) then
                        return tonumber(child.Value)
                    end
                end
            end
        end

        current = current.Parent
    end

    return nil
end

local function readUID(obj)
    local current = obj

    for _ = 1, 4 do
        if not current then
            break
        end

        for _, name in ipairs(UID_ATTRIBUTES) do
            local value = current:GetAttribute(name)
            if value ~= nil then
                return value
            end

            local child = current:FindFirstChild(name)
            if child and child:IsA("ValueBase") then
                return child.Value
            end
        end

        current = current.Parent
    end

    return nil
end

local function isOwnedEgg(obj)
    if not obj then
        return false
    end

    local lower = string.lower(obj.Name)

    if not string.find(lower, "egg", 1, true) then
        return false
    end

    return readOwner(obj) == LP.UserId
end

local function ownedEggCandidates()
    local result = {}
    local seen = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and isOwnedEgg(obj) then
            local uid = readUID(obj)

            if uid ~= nil and not seen[tostring(uid)] then
                seen[tostring(uid)] = true
                table.insert(result, {
                    object = obj,
                    uid = uid,
                })
            end
        end
    end

    return result
end

--==============================================================--
-- GAME FUNCTIONS
--==============================================================--

local function claimOffline()
    local ok, result = callRemote("RF/AwayEarnings/AskCollect")

    if ok then
        setStatus("Offline Earnings solicitado")
    else
        setStatus(result)
    end
end

local function claimCodex()
    local ok, result = callRemote("RF/Codex/AskRedeemAll")

    if ok then
        setStatus("Codex solicitado")
    else
        setStatus(result)
    end
end

local function claimGroupReward()
    local remote = resolveRemote("RF/GroupPerk/RedeemPerk")

    if not remote then
        setStatus("GroupPerk não encontrado")
        return
    end

    -- O próprio cliente consulta membership; o servidor continua decidindo o claim.
    local inGroup = false

    -- Não conhecemos com segurança o GroupId literal desta versão,
    -- então tentamos primeiro sem parâmetros.
    local ok, result = callRemote("RF/GroupPerk/RedeemPerk")

    if ok then
        setStatus("Group Reward solicitado")
    else
        setStatus(result)
    end
end

local function raiseBaseTier()
    local ok, result = callRemote("RE/Homestead/AskBaseTierRaise")

    if ok then
        setStatus("Upgrade da base solicitado")
    else
        setStatus(result)
    end
end

local function askTreadmillWear()
    local ok, result = callRemote("RF/Treadmill/AskWearStill")

    if not ok then
        setStatus(result)
        return false
    end

    setStatus("Esteira: pedido enviado")
    return true, result
end

local function askTreadmillDoff()
    local ok, result = callRemote("RF/Treadmill/AskDoff")

    if ok then
        setStatus("Esteira desligada")
    else
        setStatus(result)
    end
end

local function hatchOwnedEggsOnce()
    local eggs = ownedEggCandidates()

    if #eggs == 0 then
        setStatus("Nenhum ovo próprio identificável")
        return 0
    end

    local count = 0

    for _, egg in ipairs(eggs) do
        if readOwner(egg.object) == LP.UserId then
            local ok = callRemote("RF/EggWorld/AskHatch", egg.uid)

            if ok then
                task.wait(0.12)
                callRemote("RF/EggWorld/AskFinishHatch", egg.uid)
                count += 1
            end
        end
    end

    setStatus(("Hatch: %d tentativa(s) próprias"):format(count))
    return count
end

--==============================================================--
-- RETURN TO BASE
--==============================================================--

local function character()
    return LP.Character
end

local function rootPart()
    local c = character()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local c = character()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function ownerMatches(obj)
    local owner = readOwner(obj)
    if owner == LP.UserId then
        return true
    end

    local name = string.lower(obj.Name)

    if string.find(name, string.lower(LP.Name), 1, true) then
        return true
    end

    return false
end

local function findOwnBasePart()
    local best

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local p = string.lower(obj:GetFullName())

            if (
                string.find(p, "homestead", 1, true)
                or string.find(p, "plot", 1, true)
                or string.find(p, "base", 1, true)
            ) and ownerMatches(obj.Parent or obj) then
                best = obj
                break
            end
        end
    end

    return best
end

local function returnToBase()
    local hrp = rootPart()
    if not hrp then
        setStatus("Personagem não encontrado")
        return
    end

    local basePart = findOwnBasePart()

    if not basePart then
        setStatus("Base própria não identificada")
        return
    end

    hrp.CFrame = basePart.CFrame + Vector3.new(0, 5, 0)
    setStatus("Retorno à base")
end

--==============================================================--
-- ESP
--==============================================================--

local function clearESP(kind)
    for obj, info in pairs(Highlights) do
        if info.kind == kind then
            pcall(function()
                info.highlight:Destroy()
            end)
            Highlights[obj] = nil
        end
    end
end

local function addHighlight(obj, kind)
    if Highlights[obj] then
        return
    end

    local target = obj

    if obj:IsA("BasePart") then
        target = obj.Parent or obj
    end

    if not target:IsA("Model") and not target:IsA("BasePart") then
        return
    end

    local h = Instance.new("Highlight")
    h.Name = "CafeinaESP"
    h.Adornee = target
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillTransparency = 0.72
    h.OutlineTransparency = 0.05
    h.Parent = target

    Highlights[obj] = {
        kind = kind,
        highlight = h,
    }
end

local function refreshEggESP()
    clearESP("egg")

    if not State.EggESP then
        return
    end

    local count = 0

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if count >= 120 then
            break
        end

        if obj:IsA("Model") then
            local n = string.lower(obj.Name)

            if string.find(n, "egg", 1, true) then
                addHighlight(obj, "egg")
                count += 1
            end
        end
    end
end

local function refreshMachineESP()
    clearESP("machine")

    if not State.MachineESP then
        return
    end

    local count = 0

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if count >= 80 then
            break
        end

        if obj:IsA("Model") then
            local n = string.lower(obj.Name)

            if (
                string.find(n, "treadmill", 1, true)
                or string.find(n, "fuse", 1, true)
                or string.find(n, "fusery", 1, true)
                or string.find(n, "machine", 1, true)
            ) then
                addHighlight(obj, "machine")
                count += 1
            end
        end
    end
end

--==============================================================--
-- MOVEMENT
--==============================================================--

remember(RunService.Stepped:Connect(function()
    if not State.Alive then
        return
    end

    local hum = humanoid()

    if hum and State.WalkSpeedEnabled then
        hum.WalkSpeed = State.WalkSpeed
    end

    if State.Noclip then
        local c = character()

        if c then
            for _, obj in ipairs(c:GetDescendants()) do
                if obj:IsA("BasePart") then
                    obj.CanCollide = false
                end
            end
        end
    end
end))

remember(UserInputService.JumpRequest:Connect(function()
    if not State.InfiniteJump then
        return
    end

    local hum = humanoid()

    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

--==============================================================--
-- LOOPS
--==============================================================--

task.spawn(function()
    while State.Alive do
        if State.AutoTreadmill then
            askTreadmillWear()
        end

        task.wait(1.0)
    end
end)

task.spawn(function()
    while State.Alive do
        if State.AutoHatchOwned then
            hatchOwnedEggsOnce()
        end

        task.wait(1.5)
    end
end)

task.spawn(function()
    while State.Alive do
        if State.EggESP then
            refreshEggESP()
        end

        if State.MachineESP then
            refreshMachineESP()
        end

        task.wait(3)
    end
end)

--==============================================================--
-- SERVER HOP
--==============================================================--

local function serverHop()
    if not REQUEST then
        setStatus("Executor sem request HTTP")
        return
    end

    setStatus("Buscando servidor...")

    local cursor = ""
    local found

    for _ = 1, 4 do
        local url =
            "https://games.roblox.com/v1/games/"
            .. tostring(game.PlaceId)
            .. "/servers/Public?sortOrder=Asc&limit=100"

        if cursor ~= "" then
            url ..= "&cursor=" .. HttpService:UrlEncode(cursor)
        end

        local ok, response = pcall(function()
            return REQUEST({
                Url = url,
                Method = "GET",
            })
        end)

        if not ok or not response then
            break
        end

        local body = response.Body or response.body

        if not body then
            break
        end

        local decoded

        local decodeOk = pcall(function()
            decoded = HttpService:JSONDecode(body)
        end)

        if not decodeOk or not decoded then
            break
        end

        for _, server in ipairs(decoded.data or {}) do
            if (
                server.id ~= game.JobId
                and tonumber(server.playing or 0) < tonumber(server.maxPlayers or 0)
            ) then
                found = server.id
                break
            end
        end

        if found then
            break
        end

        cursor = decoded.nextPageCursor or ""

        if cursor == "" then
            break
        end
    end

    if not found then
        setStatus("Nenhum servidor disponível")
        return
    end

    setStatus("Trocando servidor...")

    TeleportService:TeleportToPlaceInstance(
        game.PlaceId,
        found,
        LP
    )
end

--==============================================================--
-- UI HELPERS
--==============================================================--

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaOuroborosMobile"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = ROOT

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(320, 452)
Main.Position = UDim2.new(0.5, -160, 0.5, -226)
Main.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
Main.BorderSizePixel = 0
Main.Parent = Gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -92, 1, 0)
Title.Position = UDim2.fromOffset(14, 0)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA • OUROBOROS"
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.Parent = Header

local function smallButton(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(36, 34)
    b.Position = UDim2.new(1, x, 0, 8)
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 35)
    b.TextColor3 = Color3.fromRGB(240, 240, 240)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 15
    b.Text = text
    b.Parent = Header

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    return b
end

local Minimize = smallButton("—", -80)
local Close = smallButton("×", -40)

local Tabs = Instance.new("ScrollingFrame")
Tabs.Size = UDim2.new(1, -20, 0, 38)
Tabs.Position = UDim2.fromOffset(10, 51)
Tabs.BackgroundTransparency = 1
Tabs.BorderSizePixel = 0
Tabs.ScrollBarThickness = 0
Tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
Tabs.CanvasSize = UDim2.new()
Tabs.ScrollingDirection = Enum.ScrollingDirection.X
Tabs.Parent = Main

local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 5)
tabsLayout.Parent = Tabs

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -20, 1, -142)
Content.Position = UDim2.fromOffset(10, 94)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 34)
Status.Position = UDim2.new(0, 10, 1, -40)
Status.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
Status.TextColor3 = Color3.fromRGB(215, 215, 215)
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.Text = "Pronto"
Status.TextWrapped = true
Status.Parent = Main

local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0, 8)
sc.Parent = Status

local Pages = {}
local TabButtons = {}

local function makePage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new()
    page.Visible = false
    page.Parent = Content

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.Parent = page

    Pages[name] = page
    return page
end

local function showPage(name)
    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end

    for tabName, button in pairs(TabButtons) do
        button.BackgroundColor3 =
            tabName == name
            and Color3.fromRGB(54, 54, 62)
            or Color3.fromRGB(27, 27, 31)
    end
end

local function makeTab(text, pageName)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(76, 36)
    b.BackgroundColor3 = Color3.fromRGB(27, 27, 31)
    b.TextColor3 = Color3.fromRGB(242, 242, 242)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.Text = text
    b.Parent = Tabs

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    TabButtons[pageName] = b

    b.Activated:Connect(function()
        showPage(pageName)
    end)
end

local function actionButton(parent, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, 42)
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
    b.TextColor3 = Color3.fromRGB(245, 245, 245)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.Text = text
    b.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b

    b.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then
            setStatus("Erro: " .. tostring(err))
        end
    end)

    return b
end

local function toggleButton(parent, label, getter, setter, onChanged)
    local b

    local function refresh()
        local enabled = getter()
        b.Text = label .. (enabled and " • ON" or " • OFF")
        b.BackgroundColor3 =
            enabled
            and Color3.fromRGB(47, 67, 49)
            or Color3.fromRGB(31, 31, 36)
    end

    b = actionButton(parent, "", function()
        setter(not getter())
        refresh()

        if onChanged then
            onChanged(getter())
        end
    end)

    refresh()
    return b
end

local function label(parent, text)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -4, 0, 32)
    t.BackgroundTransparency = 1
    t.TextColor3 = Color3.fromRGB(185, 185, 190)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Font = Enum.Font.Gotham
    t.TextSize = 11
    t.Text = text
    t.Parent = parent
    return t
end

--==============================================================--
-- PAGES
--==============================================================--

local HomePage     = makePage("HOME")
local EggPage      = makePage("OVOS")
local TrainPage    = makePage("TREINO")
local VisualPage   = makePage("VISUAL")
local MovePage     = makePage("MOVIMENTO")
local UtilPage     = makePage("UTIL")

makeTab("PRINCIPAL", "HOME")
makeTab("OVOS", "OVOS")
makeTab("TREINO", "TREINO")
makeTab("VISUAL", "VISUAL")
makeTab("MOV.", "MOVIMENTO")
makeTab("UTIL", "UTIL")

-- HOME
label(HomePage, "Recompensas e base do próprio jogador")

actionButton(HomePage, "CLAIM OFFLINE EARNINGS", claimOffline)
actionButton(HomePage, "CLAIM CODEX", claimCodex)
actionButton(HomePage, "CLAIM GROUP REWARD", claimGroupReward)
actionButton(HomePage, "SUBIR TIER DA BASE", raiseBaseTier)

-- EGGS
label(EggPage, "Ovos: somente ações com ownership local confirmado")

toggleButton(
    EggPage,
    "AUTO HATCH PRÓPRIOS",
    function() return State.AutoHatchOwned end,
    function(v) State.AutoHatchOwned = v end
)

actionButton(EggPage, "HATCH PRÓPRIOS AGORA", hatchOwnedEggsOnce)

toggleButton(
    EggPage,
    "ESP OVOS",
    function() return State.EggESP end,
    function(v) State.EggESP = v end,
    function(v)
        if v then
            refreshEggESP()
        else
            clearESP("egg")
        end
    end
)

-- TRAIN
label(TrainPage, "Esteira: o servidor continua validando se você está nela")

toggleButton(
    TrainPage,
    "AUTO TREADMILL",
    function() return State.AutoTreadmill end,
    function(v) State.AutoTreadmill = v end,
    function(v)
        if not v then
            askTreadmillDoff()
        end
    end
)

actionButton(TrainPage, "ASK WEAR STILL", askTreadmillWear)
actionButton(TrainPage, "SAIR DA ESTEIRA", askTreadmillDoff)

-- VISUAL
label(VisualPage, "ESP local; não altera estado do servidor")

toggleButton(
    VisualPage,
    "ESP OVOS",
    function() return State.EggESP end,
    function(v) State.EggESP = v end,
    function(v)
        if v then refreshEggESP() else clearESP("egg") end
    end
)

toggleButton(
    VisualPage,
    "ESP MÁQUINAS",
    function() return State.MachineESP end,
    function(v) State.MachineESP = v end,
    function(v)
        if v then refreshMachineESP() else clearESP("machine") end
    end
)

actionButton(VisualPage, "ATUALIZAR ESP", function()
    refreshEggESP()
    refreshMachineESP()
    setStatus("ESP atualizado")
end)

-- MOVE
label(MovePage, "Movimento local")

toggleButton(
    MovePage,
    "WALKSPEED",
    function() return State.WalkSpeedEnabled end,
    function(v)
        State.WalkSpeedEnabled = v

        if not v then
            local hum = humanoid()
            if hum then
                hum.WalkSpeed = 16
            end
        end
    end
)

actionButton(MovePage, "VELOCIDADE +10", function()
    State.WalkSpeed = math.clamp(State.WalkSpeed + 10, 16, 200)
    setStatus("WalkSpeed: " .. State.WalkSpeed)
end)

actionButton(MovePage, "VELOCIDADE -10", function()
    State.WalkSpeed = math.clamp(State.WalkSpeed - 10, 16, 200)
    setStatus("WalkSpeed: " .. State.WalkSpeed)
end)

toggleButton(
    MovePage,
    "NOCLIP",
    function() return State.Noclip end,
    function(v) State.Noclip = v end
)

toggleButton(
    MovePage,
    "INFINITE JUMP",
    function() return State.InfiniteJump end,
    function(v) State.InfiniteJump = v end
)

actionButton(MovePage, "VOLTAR PARA BASE", returnToBase)

-- UTIL
label(UtilPage, "Utilidades")

actionButton(UtilPage, "SERVER HOP", serverHop)

actionButton(UtilPage, "REJOIN", function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
end)

actionButton(UtilPage, "DESLIGAR TODAS AS FUNÇÕES", function()
    State.AutoTreadmill = false
    State.AutoHatchOwned = false
    State.EggESP = false
    State.MachineESP = false
    State.Noclip = false
    State.InfiniteJump = false
    State.WalkSpeedEnabled = false

    clearESP("egg")
    clearESP("machine")
    askTreadmillDoff()

    local hum = humanoid()
    if hum then
        hum.WalkSpeed = 16
    end

    setStatus("Tudo desligado")
end)

--==============================================================--
-- MINIMIZE
--==============================================================--

local Mini = Instance.new("TextButton")
Mini.Size = UDim2.fromOffset(52, 52)
Mini.Position = UDim2.new(0.5, -26, 0.5, -26)
Mini.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
Mini.TextColor3 = Color3.fromRGB(245, 245, 245)
Mini.Font = Enum.Font.GothamBold
Mini.TextSize = 18
Mini.Text = "C"
Mini.Visible = false
Mini.Parent = Gui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(1, 0)
miniCorner.Parent = Mini

Minimize.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

--==============================================================--
-- DRAG
--==============================================================--

local function makeDraggable(handle, target)
    local dragging = false
    local dragStart
    local startPos
    local activeInput

    handle.InputBegan:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        ) then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            activeInput = input
        end
    end)

    handle.InputChanged:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement
        ) then
            activeInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == activeInput then
            local delta = input.Position - dragStart

            target.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        ) then
            dragging = false
        end
    end)
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

--==============================================================--
-- CLOSE
--==============================================================--

Close.Activated:Connect(function()
    State.Alive = false

    State.AutoTreadmill = false
    State.AutoHatchOwned = false
    State.EggESP = false
    State.MachineESP = false
    State.Noclip = false
    State.InfiniteJump = false
    State.WalkSpeedEnabled = false

    pcall(askTreadmillDoff)

    clearESP("egg")
    clearESP("machine")

    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    local hum = humanoid()
    if hum then
        pcall(function()
            hum.WalkSpeed = 16
        end)
    end

    Gui:Destroy()
end)

--==============================================================--
-- STATUS LOOP
--==============================================================--

task.spawn(function()
    while State.Alive and Gui.Parent do
        Status.Text =
            State.Status
            .. "  |  WS "
            .. tostring(State.WalkSpeed)

        task.wait(0.25)
    end
end)

showPage("HOME")
setStatus("Pronto")
