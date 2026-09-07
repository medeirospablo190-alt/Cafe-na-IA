--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V4
-- Executor/mobile • CLIENT-SIDE ONLY
--
-- Funcoes:
--   • ao detectar que voce pegou um ovo -> TP imediato para Safe Zone
--   • God Mode local
--   • lista de jogadores online
--   • TP ate jogador selecionado
--   • Kill LOCAL do jogador selecionado
--   • adicionar dinheiro LOCAL ao jogador selecionado
--   • adicionar dinheiro LOCAL a voce
--
-- Nao usa FireServer / InvokeServer.
-- Kill, dinheiro e God sao apenas client-side e nao persistem no servidor.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

-- Centro aproximado da Safe Zone ja mapeada.
local SAFE_CFRAME = CFrame.new(529, 75, -360)

local S = {
    selected = nil,
    god = false,
    lastEggTp = 0,
    status = "AUTO SAFE ativo • aguardando ovo",
    eggConnections = {},
    charConnections = {},
    godConn = nil,
    originalBreakJoints = nil,
}

local MONEY_NAMES = {
    money = true,
    cash = true,
    coin = true,
    coins = true,
    dinheiro = true,
    bucks = true,
    credits = true,
    credit = true,
    currency = true,
}

local EGG_ATTRS = {
    EggId = true,
    EggID = true,
    FieldEggId = true,
    FieldEggID = true,
    EggType = true,
    EggName = true,
}

local function setStatus(text)
    S.status = tostring(text or "")
end

local function getCharacter(plr)
    plr = plr or LP
    local char = plr.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function teleportSelf(cf)
    local char, hrp = getCharacter(LP)
    if not char or not hrp then
        return false, "personagem local indisponivel"
    end

    local ok, err = pcall(function()
        char:PivotTo(cf)
    end)

    if not ok then
        ok, err = pcall(function()
            hrp.CFrame = cf
        end)
    end

    return ok, err
end

local function looksLikeEgg(obj)
    if not obj then return false end

    local lower = string.lower(tostring(obj.Name or ""))
    if string.find(lower, "egg", 1, true) or string.find(lower, "ovo", 1, true) then
        return true
    end

    for attr in pairs(EGG_ATTRS) do
        local ok, value = pcall(function()
            return obj:GetAttribute(attr)
        end)
        if ok and value ~= nil then
            return true
        end
    end

    return false
end

local function autoSafe(reason)
    local now = os.clock()
    if now - S.lastEggTp < 0.75 then
        return
    end
    S.lastEggTp = now

    task.defer(function()
        local ok, err = teleportSelf(SAFE_CFRAME)
        if ok then
            setStatus("OVO DETECTADO > SAFE ZONE ✓ • " .. tostring(reason or "carry"))
        else
            setStatus("Ovo detectado, TP falhou: " .. tostring(err))
        end
    end)
end

--==============================================================--
-- AUTO SAFE: observa o evento recebido pelo cliente.
-- Nao chama o RemoteEvent.
--==============================================================--

local connectedRemotes = setmetatable({}, {__mode = "k"})

local function connectEggRemote(obj)
    if not obj or connectedRemotes[obj] then return end
    if not obj:IsA("RemoteEvent") then return end
    if obj.Name ~= "FieldEggCarry" then return end

    connectedRemotes[obj] = true
    local conn = obj.OnClientEvent:Connect(function(...)
        autoSafe("FieldEggCarry")
    end)
    S.eggConnections[#S.eggConnections + 1] = conn
end

for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    connectEggRemote(obj)
end

S.eggConnections[#S.eggConnections + 1] = ReplicatedStorage.DescendantAdded:Connect(function(obj)
    connectEggRemote(obj)
end)

local function bindLocalContainers()
    for _, conn in ipairs(S.charConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(S.charConnections)

    local char = LP.Character
    local backpack = LP:FindFirstChildOfClass("Backpack")

    local function watch(container, label)
        if not container then return end
        S.charConnections[#S.charConnections + 1] = container.ChildAdded:Connect(function(obj)
            if looksLikeEgg(obj) then
                autoSafe(label .. ":" .. tostring(obj.Name))
            end
        end)
    end

    watch(char, "Character")
    watch(backpack, "Backpack")
end

LP.CharacterAdded:Connect(function()
    task.wait(0.25)
    bindLocalContainers()
end)

task.defer(bindLocalContainers)

--==============================================================--
-- GOD MODE LOCAL
--==============================================================--

local function applyGodFrame()
    if not S.god then return end

    local _, _, hum = getCharacter(LP)
    if not hum then return end

    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    end)

    if hum.MaxHealth > 0 and hum.Health < hum.MaxHealth then
        pcall(function()
            hum.Health = hum.MaxHealth
        end)
    end
end

local function setGod(enabled)
    S.god = enabled == true

    local _, _, hum = getCharacter(LP)
    if hum then
        if S.god then
            if S.originalBreakJoints == nil then
                S.originalBreakJoints = hum.BreakJointsOnDeath
            end
            pcall(function() hum.BreakJointsOnDeath = false end)
            pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
            pcall(function() hum.Health = hum.MaxHealth end)
        else
            pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
            if S.originalBreakJoints ~= nil then
                pcall(function() hum.BreakJointsOnDeath = S.originalBreakJoints end)
            end
        end
    end

    setStatus(S.god and "GOD LOCAL ON" or "GOD LOCAL OFF")
end

S.godConn = RunService.Heartbeat:Connect(applyGodFrame)

--==============================================================--
-- PLAYER ACTIONS • TODAS LOCAIS
--==============================================================--

local function tpToPlayer(plr)
    if not plr or plr == LP then
        return false, "selecione outro jogador"
    end

    local _, targetRoot = getCharacter(plr)
    if not targetRoot then
        return false, "alvo sem HumanoidRootPart"
    end

    return teleportSelf(targetRoot.CFrame * CFrame.new(0, 0, 3))
end

local function killPlayerLocal(plr)
    if not plr or plr == LP then
        return false, "selecione outro jogador"
    end

    local _, _, hum = getCharacter(plr)
    if not hum then
        return false, "Humanoid do alvo nao encontrado"
    end

    local ok, err = pcall(function()
        hum.Health = 0
        hum:ChangeState(Enum.HumanoidStateType.Dead)
    end)

    return ok, err
end

local function normalizeMoneyName(name)
    return string.lower(tostring(name or "")):gsub("[^%w]", "")
end

local function findMoneyValue(plr)
    if not plr then return nil end

    local leaderstats = plr:FindFirstChild("leaderstats")
    if leaderstats then
        for _, obj in ipairs(leaderstats:GetChildren()) do
            if (obj:IsA("IntValue") or obj:IsA("NumberValue"))
                and MONEY_NAMES[normalizeMoneyName(obj.Name)] then
                return obj, "leaderstats." .. obj.Name
            end
        end
    end

    for _, obj in ipairs(plr:GetChildren()) do
        if (obj:IsA("IntValue") or obj:IsA("NumberValue"))
            and MONEY_NAMES[normalizeMoneyName(obj.Name)] then
            return obj, obj.Name
        end
    end

    for _, attrName in ipairs({"Money", "Cash", "Coins", "Dinheiro", "Credits", "Currency"}) do
        local ok, value = pcall(function()
            return plr:GetAttribute(attrName)
        end)
        if ok and type(value) == "number" then
            return {
                AttributeOwner = plr,
                AttributeName = attrName,
                AttributeValue = value,
            }, "Attribute:" .. attrName
        end
    end

    return nil
end

local function addMoneyLocal(plr, amount)
    amount = tonumber(amount)
    if not amount then
        return false, "valor invalido"
    end

    if amount > 1000000000 then amount = 1000000000 end
    if amount < -1000000000 then amount = -1000000000 end

    local target, path = findMoneyValue(plr)
    if not target then
        return false, "nenhum valor de dinheiro visivel no cliente"
    end

    if typeof(target) == "Instance" then
        local old = target.Value
        local ok, err = pcall(function()
            target.Value = old + amount
        end)
        if ok then
            return true, tostring(path) .. " • " .. tostring(old) .. " > " .. tostring(target.Value)
        end
        return false, err
    end

    if type(target) == "table" and target.AttributeOwner then
        local old = target.AttributeValue
        local ok, err = pcall(function()
            target.AttributeOwner:SetAttribute(target.AttributeName, old + amount)
        end)
        if ok then
            return true, tostring(path) .. " • " .. tostring(old) .. " > " .. tostring(old + amount)
        end
        return false, err
    end

    return false, "tipo de dinheiro nao suportado"
end

--==============================================================--
-- GUI MOBILE
--==============================================================--

pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_PLAYER_MENU_V4")
    if old and typeof(old) == "Instance" then
        old:Destroy()
    end
end)

local parent
pcall(function()
    if gethui then
        parent = gethui()
    end
end)

if not parent then
    local ok, cg = pcall(function() return CoreGui end)
    if ok then parent = cg end
end

if not parent then
    parent = LP:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggPlayerMenuV4"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent
ENV.__CAFEINA_EGG_PLAYER_MENU_V4 = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(315, 505)
frame.Position = UDim2.new(0, 10, 0.5, -250)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -78, 0, 30)
title.Position = UDim2.fromOffset(10, 6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • EGG PLAYER V4"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local minButton = Instance.new("TextButton")
minButton.Size = UDim2.fromOffset(58, 26)
minButton.Position = UDim2.new(1, -68, 0, 7)
minButton.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
minButton.BorderSizePixel = 0
minButton.Text = "MIN"
minButton.TextColor3 = Color3.new(1, 1, 1)
minButton.Font = Enum.Font.GothamBold
minButton.TextSize = 10
minButton.Parent = frame
Instance.new("UICorner", minButton).CornerRadius = UDim.new(0, 7)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 42)
status.Position = UDim2.fromOffset(10, 38)
status.BackgroundTransparency = 1
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(185, 185, 195)
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local function makeButton(text, x, y, w, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(w or 1, -15, 0, 34)
    b.Position = UDim2.new(x or 0, 10, 0, y)
    b.BackgroundColor3 = color or Color3.fromRGB(43, 43, 50)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local refreshButton = makeButton("ATUALIZAR JOGADORES", 0, 84, 0.5)
refreshButton.Size = UDim2.new(0.5, -15, 0, 34)

local godButton = makeButton("GOD LOCAL: OFF", 0.5, 84, 0.5, Color3.fromRGB(92, 30, 34))
godButton.Position = UDim2.new(0.5, 5, 0, 84)
godButton.Size = UDim2.new(0.5, -15, 0, 34)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 0, 205)
list.Position = UDim2.fromOffset(10, 126)
list.BackgroundColor3 = Color3.fromRGB(23, 23, 27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.fromOffset(0, 0)
list.Parent = frame
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = list

local amountBox = Instance.new("TextBox")
amountBox.Size = UDim2.new(1, -20, 0, 34)
amountBox.Position = UDim2.fromOffset(10, 339)
amountBox.BackgroundColor3 = Color3.fromRGB(28, 28, 33)
amountBox.BorderSizePixel = 0
amountBox.ClearTextOnFocus = false
amountBox.Text = "1000"
amountBox.PlaceholderText = "Quantidade de dinheiro LOCAL"
amountBox.TextColor3 = Color3.fromRGB(240, 240, 245)
amountBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
amountBox.Font = Enum.Font.Code
amountBox.TextSize = 11
amountBox.Parent = frame
Instance.new("UICorner", amountBox).CornerRadius = UDim.new(0, 8)

local tpButton = makeButton("TP NO SELECIONADO", 0, 381, 0.5)
tpButton.Size = UDim2.new(0.5, -15, 0, 34)

local killButton = makeButton("KILL LOCAL", 0.5, 381, 0.5, Color3.fromRGB(115, 28, 32))
killButton.Position = UDim2.new(0.5, 5, 0, 381)
killButton.Size = UDim2.new(0.5, -15, 0, 34)

local giveButton = makeButton("$ LOCAL > SELECIONADO", 0, 423, 0.5)
giveButton.Size = UDim2.new(0.5, -15, 0, 34)

local selfMoneyButton = makeButton("$ LOCAL > EU", 0.5, 423, 0.5)
selfMoneyButton.Position = UDim2.new(0.5, 5, 0, 423)
selfMoneyButton.Size = UDim2.new(0.5, -15, 0, 34)

local safeButton = makeButton("IR PARA SAFE AGORA", 0, 465, 1, Color3.fromRGB(95, 30, 34))
safeButton.Size = UDim2.new(1, -20, 0, 30)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(96, 40)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mini.BorderSizePixel = 0
mini.Text = "EGG PLAYER"
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 9
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 10)

local function clearPlayerRows()
    for _, obj in ipairs(list:GetChildren()) do
        if obj:IsA("TextButton") then
            obj:Destroy()
        end
    end
end

local function rebuildPlayers()
    clearPlayerRows()

    local count = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            count = count + 1
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, 38)
            row.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
            row.BorderSizePixel = 0
            row.Text = tostring(plr.DisplayName) .. "  (@" .. tostring(plr.Name) .. ")"
            row.TextColor3 = Color3.fromRGB(235, 235, 240)
            row.Font = Enum.Font.Gotham
            row.TextSize = 10
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 10)
            pad.Parent = row

            row.MouseButton1Click:Connect(function()
                S.selected = plr
                setStatus("Selecionado: " .. tostring(plr.DisplayName) .. " (@" .. tostring(plr.Name) .. ")")
            end)
        end
    end

    task.wait()
    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)

    if count == 0 then
        setStatus("Nenhum outro jogador online")
    else
        setStatus(tostring(count) .. " jogadores online • selecione um")
    end
end

refreshButton.MouseButton1Click:Connect(rebuildPlayers)

godButton.MouseButton1Click:Connect(function()
    setGod(not S.god)
end)

tpButton.MouseButton1Click:Connect(function()
    local ok, err = tpToPlayer(S.selected)
    if ok then
        setStatus("TP local concluido")
    else
        setStatus("TP falhou: " .. tostring(err))
    end
end)

killButton.MouseButton1Click:Connect(function()
    local ok, err = killPlayerLocal(S.selected)
    if ok then
        setStatus("KILL LOCAL aplicado em " .. tostring(S.selected and S.selected.Name or "alvo"))
    else
        setStatus("Kill local falhou: " .. tostring(err))
    end
end)

giveButton.MouseButton1Click:Connect(function()
    if not S.selected then
        setStatus("Selecione um jogador")
        return
    end

    local ok, info = addMoneyLocal(S.selected, amountBox.Text)
    if ok then
        setStatus("Dinheiro LOCAL alterado • " .. tostring(info))
    else
        setStatus("Dinheiro local falhou: " .. tostring(info))
    end
end)

selfMoneyButton.MouseButton1Click:Connect(function()
    local ok, info = addMoneyLocal(LP, amountBox.Text)
    if ok then
        setStatus("Seu dinheiro LOCAL alterado • " .. tostring(info))
    else
        setStatus("Seu dinheiro local falhou: " .. tostring(info))
    end
end)

safeButton.MouseButton1Click:Connect(function()
    local ok, err = teleportSelf(SAFE_CFRAME)
    if ok then
        setStatus("SAFE ZONE ✓")
    else
        setStatus("Safe falhou: " .. tostring(err))
    end
end)

minButton.MouseButton1Click:Connect(function()
    mini.Position = frame.Position
    frame.Visible = false
    mini.Visible = true
end)

mini.MouseButton1Click:Connect(function()
    frame.Position = mini.Position
    mini.Visible = false
    frame.Visible = true
end)

local dragging = false
local dragStart
local startPos

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)

title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if S.selected == plr then
        S.selected = nil
        setStatus("Jogador selecionado saiu do servidor")
    end
    task.defer(rebuildPlayers)
end)

Players.PlayerAdded:Connect(function()
    task.defer(rebuildPlayers)
end)

task.spawn(function()
    while gui.Parent do
        status.Text = S.status
        godButton.Text = S.god and "GOD LOCAL: ON" or "GOD LOCAL: OFF"
        task.wait(0.08)
    end
end)

task.defer(rebuildPlayers)
print("[CAFEINA EGG] CLIENT MENU V4 carregado ✓ • AUTO SAFE ON")