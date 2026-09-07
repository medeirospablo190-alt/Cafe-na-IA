--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V3.2
-- Executor/mobile • client-side only
--
-- Funcoes:
--   1) listar ovos visiveis ao cliente
--   2) tocar em um ovo = selecionar + trazer localmente ate voce
--   3) trazer novamente o selecionado
--   4) pegar selecionado e ir para Safe Zone
--   5) pegar automaticamente o mais proximo e ir para Safe Zone
--   6) ir somente para Safe Zone
--
-- Nao chama FireServer/InvokeServer manualmente.
-- Nao cria logica server-side.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local KNOWN_PLACE = 107778070777162
local SAFE_CFRAME = CFrame.new(529, 75, -360)

local S = {
    busy = false,
    selected = nil,
    eggs = {},
    carrySignal = false,
    status = "Iniciando...",
    gui = nil,
}

local EGG_ATTRIBUTES = {
    "EggId",
    "EggID",
    "FieldEggId",
    "FieldEggID",
    "EggType",
    "EggName",
    "Id",
}

local function setStatus(text)
    S.status = tostring(text or "")
end

local function getCharacter(timeout)
    local char = LP.Character
    if not char then
        char = LP.CharacterAdded:Wait()
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        hrp = char:WaitForChild("HumanoidRootPart", timeout or 5)
    end

    return char, hrp
end

local function teleportCharacter(cf)
    local char, hrp = getCharacter(5)
    if not char or not hrp then
        return false, "HumanoidRootPart ausente"
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

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function eggNameLike(name)
    local n = lower(name)
    return string.find(n, "egg", 1, true) ~= nil
        or string.find(n, "ovo", 1, true) ~= nil
end

local function hasEggAttribute(obj)
    if not obj then
        return false
    end

    for _, attr in ipairs(EGG_ATTRIBUTES) do
        local ok, value = pcall(function()
            return obj:GetAttribute(attr)
        end)

        if ok and value ~= nil then
            if attr ~= "Id" or eggNameLike(obj.Name) or eggNameLike(obj.Parent and obj.Parent.Name) then
                return true
            end
        end
    end

    return false
end

local function getPart(obj)
    if not obj then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj
    end

    if obj:IsA("Model") then
        if obj.PrimaryPart then
            return obj.PrimaryPart
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function promptLooksEgg(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end

    local txt = lower(prompt.ActionText) .. " " .. lower(prompt.ObjectText)
    return string.find(txt, "egg", 1, true) ~= nil
        or string.find(txt, "ovo", 1, true) ~= nil
        or string.find(txt, "steal", 1, true) ~= nil
        or string.find(txt, "take", 1, true) ~= nil
        or string.find(txt, "grab", 1, true) ~= nil
        or string.find(txt, "pick", 1, true) ~= nil
end

local function basicEggScore(obj)
    if not obj then
        return 0
    end

    local score = 0

    if eggNameLike(obj.Name) then
        score = score + 120
    end

    if hasEggAttribute(obj) then
        score = score + 180
    end

    local parent = obj.Parent
    if parent then
        if eggNameLike(parent.Name) then
            score = score + 55
        end
        if hasEggAttribute(parent) then
            score = score + 90
        end
    end

    local directPrompt = obj:FindFirstChildOfClass("ProximityPrompt")
    if directPrompt and promptLooksEgg(directPrompt) then
        score = score + 140
    end

    return score
end

local function normalizeEgg(obj)
    if not obj then
        return nil
    end

    local current = obj
    local best = nil
    local bestScore = 0

    for _ = 1, 5 do
        if not current or current == workspace then
            break
        end

        if current:IsA("Model") or current:IsA("BasePart") then
            local part = getPart(current)
            if part then
                local score = basicEggScore(current)
                if score > bestScore then
                    best = current
                    bestScore = score
                end
            end
        end

        current = current.Parent
    end

    if bestScore <= 0 then
        return nil
    end

    return best
end

local function addCandidate(found, seen, root, hrp)
    if not root or seen[root] then
        return
    end

    local part = getPart(root)
    if not part or not part.Parent then
        return
    end

    if LP.Character and part:IsDescendantOf(LP.Character) then
        return
    end

    seen[root] = true

    local distance = (part.Position - hrp.Position).Magnitude
    found[#found + 1] = {
        root = root,
        part = part,
        name = tostring(root.Name),
        distance = distance,
        score = basicEggScore(root),
    }
end

local function scanEggs()
    local _, hrp = getCharacter(5)
    if not hrp then
        return {}
    end

    local found = {}
    local seen = {}
    local descendants = workspace:GetDescendants()

    for i, obj in ipairs(descendants) do
        if obj:IsA("ProximityPrompt") and promptLooksEgg(obj) then
            local root = normalizeEgg(obj.Parent) or obj.Parent
            if root and (root:IsA("Model") or root:IsA("BasePart")) then
                addCandidate(found, seen, root, hrp)
            end
        elseif obj:IsA("Model") or obj:IsA("BasePart") then
            if basicEggScore(obj) > 0 then
                local root = normalizeEgg(obj) or obj
                addCandidate(found, seen, root, hrp)
            end
        end

        if i % 700 == 0 then
            task.wait()
        end
    end

    table.sort(found, function(a, b)
        if math.abs(a.distance - b.distance) < 0.01 then
            return a.score > b.score
        end
        return a.distance < b.distance
    end)

    S.eggs = found
    return found
end

local function refreshItem(item)
    if not item or not item.root or not item.root.Parent then
        return nil, "ovo nao existe mais"
    end

    local part = getPart(item.root)
    if not part or not part.Parent then
        return nil, "parte do ovo nao encontrada"
    end

    item.part = part

    local _, hrp = getCharacter(3)
    if hrp then
        item.distance = (part.Position - hrp.Position).Magnitude
    end

    return item
end

local function bringEggToMe(item)
    local refreshed, refreshErr = refreshItem(item)
    if not refreshed then
        return false, refreshErr
    end

    item = refreshed

    local _, hrp = getCharacter(5)
    if not hrp then
        return false, "personagem indisponivel"
    end

    local target = hrp.CFrame * CFrame.new(0, 0.8, -3)
    local ok, err

    if item.root:IsA("Model") then
        ok, err = pcall(function()
            item.root:PivotTo(target)
        end)
    else
        ok, err = pcall(function()
            item.part.CFrame = target
        end)
    end

    if ok then
        S.selected = item
        setStatus("Selecionado e trazido localmente: " .. item.name)
        return true
    end

    return false, tostring(err)
end

local function findPrompt(item)
    if not item then
        return nil
    end

    if item.root and item.root.Parent then
        local prompt = item.root:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            return prompt
        end
    end

    if item.part and item.part.Parent then
        local prompt = item.part:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            return prompt
        end
    end

    return nil
end

local function triggerPrompt(prompt)
    if not prompt then
        return false
    end

    if type(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if ok then
            return true
        end
    end

    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(tonumber(prompt.HoldDuration) or 0, 0.05))
        prompt:InputHoldEnd()
    end)

    return ok
end

local function triggerTouch(part)
    if not part or type(firetouchinterest) ~= "function" then
        return false
    end

    local _, hrp = getCharacter(3)
    if not hrp then
        return false
    end

    local ok = pcall(function()
        firetouchinterest(hrp, part, 0)
        task.wait()
        firetouchinterest(hrp, part, 1)
    end)

    return ok
end

local function interactEgg(item)
    local refreshed, refreshErr = refreshItem(item)
    if not refreshed then
        return false, refreshErr
    end

    item = refreshed

    local _, hrp = getCharacter(5)
    if not hrp then
        return false, "personagem indisponivel"
    end

    local distance = (hrp.Position - item.part.Position).Magnitude
    if distance > 7 then
        local ok, err = teleportCharacter(item.part.CFrame * CFrame.new(0, 2.2, 0))
        if not ok then
            return false, "falha ao chegar no ovo: " .. tostring(err)
        end
        task.wait(0.12)
    end

    local prompt = findPrompt(item)
    if prompt and triggerPrompt(prompt) then
        return true, "prompt"
    end

    if triggerTouch(item.part) then
        return true, "touch"
    end

    return false, "nenhuma interacao cliente compativel"
end

local function looksLikeCarriedEgg()
    local char = LP.Character
    local backpack = LP:FindFirstChildOfClass("Backpack")

    for _, container in ipairs({char, backpack}) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if eggNameLike(obj.Name) or hasEggAttribute(obj) then
                    return true
                end
            end
        end
    end

    return false
end

local function hookCarryRemote(remote)
    if not remote or not remote:IsA("RemoteEvent") or remote.Name ~= "FieldEggCarry" then
        return
    end

    pcall(function()
        remote.OnClientEvent:Connect(function()
            S.carrySignal = true
        end)
    end)
end

for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    hookCarryRemote(obj)
end

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    hookCarryRemote(obj)
end)

local function waitCarry(timeout)
    local started = os.clock()

    while os.clock() - started < timeout do
        if S.carrySignal or looksLikeCarriedEgg() then
            return true
        end
        task.wait(0.05)
    end

    return false
end

local function pickupAndSafe(item)
    if S.busy then
        return
    end

    if not item then
        setStatus("Escolha um ovo primeiro.")
        return
    end

    S.busy = true
    S.carrySignal = false
    setStatus("Pegando: " .. tostring(item.name))

    local ok, method = interactEgg(item)
    if not ok then
        setStatus("Falha ao interagir: " .. tostring(method))
        S.busy = false
        return
    end

    setStatus("Interacao " .. tostring(method) .. " • aguardando carry...")
    local confirmed = waitCarry(1.8)

    if confirmed then
        setStatus("Carry confirmado • indo para Safe Zone...")
    else
        setStatus("Carry sem confirmacao local • indo para Safe Zone...")
    end

    local tpOK, err = teleportCharacter(SAFE_CFRAME)
    if tpOK then
        setStatus("SAFE ZONE OK")
    else
        setStatus("Falha no TP Safe: " .. tostring(err))
    end

    S.busy = false
end

local function nearestAndSafe()
    if S.busy then
        return
    end

    S.busy = true
    setStatus("Procurando ovo mais proximo...")

    local eggs = scanEggs()
    if #eggs == 0 then
        setStatus("Nenhum ovo encontrado.")
        S.busy = false
        return
    end

    local item = eggs[1]
    S.selected = item
    S.busy = false
    pickupAndSafe(item)
end

--==============================================================--
-- GUI STARTUP ROBUSTO
--==============================================================--

pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_MENU")
    if old and typeof(old) == "Instance" then
        old:Destroy()
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggClientV32"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999

local parented = false

pcall(function()
    if gethui then
        local hui = gethui()
        if hui then
            gui.Parent = hui
            parented = gui.Parent ~= nil
        end
    end
end)

if not parented then
    pcall(function()
        gui.Parent = CoreGui
        parented = gui.Parent ~= nil
    end)
end

if not parented then
    local playerGui = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
    if playerGui then
        local ok = pcall(function()
            gui.Parent = playerGui
        end)
        parented = ok and gui.Parent ~= nil
    end
end

if not parented then
    warn("[CAFEINA EGG] Falha: executor bloqueou gethui/CoreGui/PlayerGui")
    return
end

ENV.__CAFEINA_EGG_MENU = gui
S.gui = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(318, 500)
frame.Position = UDim2.new(0, 10, 0.5, -250)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 12)
frameCorner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -78, 0, 30)
title.Position = UDim2.fromOffset(10, 6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • EGG CLIENT V3.2"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
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

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 7)
minCorner.Parent = minButton

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 42)
status.Position = UDim2.fromOffset(10, 40)
status.BackgroundTransparency = 1
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(185, 185, 195)
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local function makeButton(text, y, color)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -20, 0, 34)
    button.Position = UDim2.fromOffset(10, y)
    button.BackgroundColor3 = color or Color3.fromRGB(43, 43, 50)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    return button
end

local refreshButton = makeButton("ATUALIZAR LISTA DE OVOS", 86)
local nearestButton = makeButton("MAIS PROXIMO > PEGAR > SAFE", 126, Color3.fromRGB(115, 28, 32))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 0, 205)
list.Position = UDim2.fromOffset(10, 168)
list.BackgroundColor3 = Color3.fromRGB(23, 23, 27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.fromOffset(0, 0)
list.Parent = frame

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 8)
listCorner.Parent = list

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

local bringButton = makeButton("TRAZER SELECIONADO ATE MIM", 383)
local pickupButton = makeButton("PEGAR SELECIONADO > SAFE", 423, Color3.fromRGB(115, 28, 32))
local safeButton = makeButton("IR PARA SAFE ZONE", 463)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(94, 40)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mini.BorderSizePixel = 0
mini.Text = "EGG MENU"
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 10
mini.Visible = false
mini.Parent = gui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(0, 10)
miniCorner.Parent = mini

local function clearRows()
    for _, obj in ipairs(list:GetChildren()) do
        if obj:IsA("TextButton") then
            obj:Destroy()
        end
    end
end

local function rebuildEggList()
    if S.busy then
        return
    end

    S.busy = true
    setStatus("Procurando ovos...")
    clearRows()

    local ok, eggsOrErr = pcall(scanEggs)
    if not ok then
        setStatus("Erro no scanner: " .. tostring(eggsOrErr))
        S.busy = false
        return
    end

    local eggs = eggsOrErr

    for i, item in ipairs(eggs) do
        local row = Instance.new("TextButton")
        row.Name = "Egg_" .. tostring(i)
        row.Size = UDim2.new(1, 0, 0, 38)
        row.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
        row.BorderSizePixel = 0
        row.Text = string.format("%02d • %s • %.0f studs", i, item.name, item.distance)
        row.TextColor3 = Color3.fromRGB(235, 235, 240)
        row.Font = Enum.Font.Gotham
        row.TextSize = 10
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Parent = list

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 7)
        rowCorner.Parent = row

        local rowPadding = Instance.new("UIPadding")
        rowPadding.PaddingLeft = UDim.new(0, 10)
        rowPadding.Parent = row

        row.MouseButton1Click:Connect(function()
            if S.busy then
                return
            end

            local refreshed, err = refreshItem(item)
            if not refreshed then
                setStatus(tostring(err))
                return
            end

            S.selected = refreshed
            local brought, bringErr = bringEggToMe(refreshed)
            if not brought then
                setStatus("Selecionado: " .. refreshed.name .. " • trazer falhou: " .. tostring(bringErr))
            end
        end)
    end

    task.wait()
    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)

    if #eggs == 0 then
        setStatus("Nenhum ovo encontrado.")
    else
        setStatus(tostring(#eggs) .. " ovos encontrados • toque em um para trazer.")
    end

    S.busy = false
end

refreshButton.MouseButton1Click:Connect(function()
    if not S.busy then
        task.spawn(rebuildEggList)
    end
end)

nearestButton.MouseButton1Click:Connect(function()
    if not S.busy then
        task.spawn(nearestAndSafe)
    end
end)

bringButton.MouseButton1Click:Connect(function()
    if S.busy then
        return
    end

    if not S.selected then
        setStatus("Escolha um ovo primeiro.")
        return
    end

    local ok, err = bringEggToMe(S.selected)
    if not ok then
        setStatus("Nao foi possivel trazer: " .. tostring(err))
    end
end)

pickupButton.MouseButton1Click:Connect(function()
    if not S.busy then
        task.spawn(pickupAndSafe, S.selected)
    end
end)

safeButton.MouseButton1Click:Connect(function()
    if S.busy then
        return
    end

    local ok, err = teleportCharacter(SAFE_CFRAME)
    if ok then
        setStatus("SAFE ZONE OK")
    else
        setStatus("Falha no TP Safe: " .. tostring(err))
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
local dragStart = nil
local startPos = nil

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

UserInputService.InputChanged:Connect(function(input)
    if dragging and dragStart and startPos then
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        status.Text = S.status

        if S.busy then
            nearestButton.Text = "PROCESSANDO..."
            pickupButton.Text = "PROCESSANDO..."
        else
            nearestButton.Text = "MAIS PROXIMO > PEGAR > SAFE"

            if S.selected then
                pickupButton.Text = "PEGAR " .. tostring(S.selected.name):sub(1, 14) .. " > SAFE"
            else
                pickupButton.Text = "PEGAR SELECIONADO > SAFE"
            end
        end

        task.wait(0.08)
    end
end)

if game.PlaceId ~= KNOWN_PLACE then
    setStatus("Menu iniciado • Place atual " .. tostring(game.PlaceId) .. " • mapa conhecido " .. tostring(KNOWN_PLACE))
else
    setStatus("Menu iniciado • procurando ovos...")
end

task.delay(0.35, function()
    if gui.Parent and not S.busy then
        rebuildEggList()
    end
end)

print("[CAFEINA EGG] CLIENT MENU V3.2 carregado")