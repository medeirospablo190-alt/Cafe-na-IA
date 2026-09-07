--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V3
-- Executor/mobile • client-side only
--
-- Funcoes combinadas:
--   • atualizar/listar ovos visiveis
--   • selecionar um ovo
--   • trazer o ovo selecionado localmente ate voce
--   • pegar selecionado e ir direto para Safe Zone
--   • pegar automaticamente o ovo mais proximo e ir para Safe Zone
--   • ir apenas para Safe Zone
--
-- Nao chama FireServer/InvokeServer manualmente.
-- Nao cria logica server-side.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local TARGET_PLACE = 107778070777162
local SAFE_CFRAME = CFrame.new(529, 75, -360)

if game.PlaceId ~= TARGET_PLACE then
    warn("[CAFEINA EGG] PlaceId incorreto:", game.PlaceId, "esperado:", TARGET_PLACE)
    return
end

local S = {
    busy = false,
    selected = nil,
    eggs = {},
    carrySignal = false,
    status = "Pronto • atualizando ovos...",
}

local EGG_ATTRIBUTES = {
    "EggId", "EggID", "FieldEggId", "FieldEggID", "EggType", "EggName",
}

local function getCharacter()
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
    return char, hrp
end

local function teleportCharacter(cf)
    local char, hrp = getCharacter()
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

local function eggNameLike(name)
    local n = string.lower(tostring(name or ""))
    return string.find(n, "egg", 1, true) ~= nil
        or string.find(n, "ovo", 1, true) ~= nil
end

local function hasEggAttribute(obj)
    if not obj then return false end
    for _, attr in ipairs(EGG_ATTRIBUTES) do
        local ok, value = pcall(function()
            return obj:GetAttribute(attr)
        end)
        if ok and value ~= nil then
            return true
        end
    end
    return false
end

local function getPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function eggScore(obj)
    if not obj then return 0 end
    local score = 0

    if eggNameLike(obj.Name) then score = score + 100 end
    if hasEggAttribute(obj) then score = score + 160 end

    local parent = obj.Parent
    if parent then
        if eggNameLike(parent.Name) then score = score + 50 end
        if hasEggAttribute(parent) then score = score + 80 end
    end

    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local txt = string.lower(tostring(prompt.ActionText or "") .. " " .. tostring(prompt.ObjectText or ""))
        if string.find(txt, "egg", 1, true) or string.find(txt, "ovo", 1, true) then
            score = score + 120
        end
    end

    return score
end

local function normalizeEgg(obj)
    if not obj then return nil end

    local current = obj
    local best, bestScore

    for _ = 1, 5 do
        if not current or current == workspace then break end
        if current:IsA("Model") or current:IsA("BasePart") then
            local score = eggScore(current)
            local part = getPart(current)
            if part and score > 0 and (not bestScore or score > bestScore) then
                best = current
                bestScore = score
            end
        end
        current = current.Parent
    end

    return best
end

local function scanEggs()
    local _, hrp = getCharacter()
    if not hrp then return {} end

    local seen = {}
    local found = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local root = normalizeEgg(obj)
            if root and not seen[root] then
                local part = getPart(root)
                if part and not (LP.Character and part:IsDescendantOf(LP.Character)) then
                    seen[root] = true
                    found[#found + 1] = {
                        root = root,
                        part = part,
                        name = tostring(root.Name),
                        distance = (part.Position - hrp.Position).Magnitude,
                        score = eggScore(root),
                    }
                end
            end
        end
    end

    table.sort(found, function(a, b)
        if a.distance == b.distance then
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
    local _, hrp = getCharacter()
    if hrp then
        item.distance = (part.Position - hrp.Position).Magnitude
    end
    return item
end

local function bringEggToMe(item)
    item = refreshItem(item)
    if not item then return false, "ovo indisponivel" end

    local _, hrp = getCharacter()
    if not hrp then return false, "personagem indisponivel" end

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
        S.status = "Selecionado e trazido localmente: " .. item.name
        return true
    end

    return false, tostring(err)
end

local function findPrompt(item)
    if not item then return nil end
    local root = item.root
    local part = item.part

    if root then
        local p = root:FindFirstChildWhichIsA("ProximityPrompt", true)
        if p then return p end
    end

    if part then
        local p = part:FindFirstChildWhichIsA("ProximityPrompt", true)
        if p then return p end
    end

    return nil
end

local function triggerPrompt(prompt)
    if not prompt then return false end

    if type(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if ok then return true end
    end

    return pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(tonumber(prompt.HoldDuration) or 0, 0.05))
        prompt:InputHoldEnd()
    end)
end

local function triggerTouch(part)
    if not part then return false end
    if type(firetouchinterest) ~= "function" then return false end

    local _, hrp = getCharacter()
    if not hrp then return false end

    return pcall(function()
        firetouchinterest(hrp, part, 0)
        task.wait()
        firetouchinterest(hrp, part, 1)
    end)
end

local function interactEgg(item)
    item = refreshItem(item)
    if not item then return false, "ovo indisponivel" end

    local _, hrp = getCharacter()
    if not hrp then return false, "personagem indisponivel" end

    local currentDistance = (hrp.Position - item.part.Position).Magnitude
    if currentDistance > 7 then
        local ok, err = teleportCharacter(item.part.CFrame * CFrame.new(0, 2.2, 0))
        if not ok then return false, "falha ao chegar no ovo: " .. tostring(err) end
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

pcall(function()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") and obj.Name == "FieldEggCarry" then
            obj.OnClientEvent:Connect(function()
                S.carrySignal = true
            end)
        end
    end
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
    if S.busy then return end
    if not item then
        S.status = "Escolha um ovo primeiro."
        return
    end

    S.busy = true
    S.carrySignal = false
    S.status = "Pegando: " .. tostring(item.name)

    local ok, method = interactEgg(item)
    if not ok then
        S.status = "Falha: " .. tostring(method)
        S.busy = false
        return
    end

    S.status = "Interacao " .. tostring(method) .. " • aguardando carry..."
    local confirmed = waitCarry(1.8)

    if confirmed then
        S.status = "Carry confirmado • indo para Safe Zone..."
    else
        S.status = "Sem confirmacao de carry • indo para Safe Zone..."
    end

    local tpOK, err = teleportCharacter(SAFE_CFRAME)
    if tpOK then
        S.status = "SAFE ZONE ✓"
    else
        S.status = "Falha no TP Safe: " .. tostring(err)
    end

    S.busy = false
end

local function nearestAndSafe()
    if S.busy then return end
    S.status = "Atualizando e procurando ovo mais proximo..."
    local eggs = scanEggs()

    if #eggs == 0 then
        S.status = "Nenhum ovo encontrado."
        return
    end

    S.selected = eggs[1]
    pickupAndSafe(eggs[1])
end

pcall(function()
    local old = rawget((getgenv and getgenv()) or _G, "__CAFEINA_EGG_MENU_V3")
    if old and typeof(old) == "Instance" then old:Destroy() end
end)

local parent = CoreGui
pcall(function()
    if gethui then parent = gethui() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggClientV3"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local ENV = (getgenv and getgenv()) or _G
ENV.__CAFEINA_EGG_MENU_V3 = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(318, 500)
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
title.Text = "CAFEINA • EGG CLIENT V3"
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
Instance.new("UICorner", minButton).CornerRadius = UDim.new(0, 7)

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
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -20, 0, 34)
    b.Position = UDim2.fromOffset(10, y)
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

local refreshButton = makeButton("ATUALIZAR LISTA DE OVOS", 86)
local nearestButton = makeButton("MAIS PROXIMO → PEGAR → SAFE", 126, Color3.fromRGB(115, 28, 32))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 0, 205)
list.Position = UDim2.fromOffset(10, 168)
list.BackgroundColor3 = Color3.fromRGB(23, 23, 27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.new()
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

local bringButton = makeButton("TRAZER SELECIONADO ATE MIM", 383)
local pickupButton = makeButton("PEGAR SELECIONADO → SAFE", 423, Color3.fromRGB(115, 28, 32))
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
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 10)

local function clearRows()
    for _, obj in ipairs(list:GetChildren()) do
        if obj:IsA("TextButton") then
            obj:Destroy()
        end
    end
end

local function rebuildEggList()
    if S.busy then return end
    S.status = "Procurando ovos..."
    clearRows()

    local eggs = scanEggs()

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
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.Parent = row

        row.MouseButton1Click:Connect(function()
            if S.busy then return end
            local refreshed, err = refreshItem(item)
            if not refreshed then
                S.status = tostring(err)
                return
            end
            S.selected = refreshed
            S.status = "Selecionado: " .. refreshed.name .. " • " .. string.format("%.0f studs", refreshed.distance)
        end)
    end

    task.wait()
    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)

    if #eggs == 0 then
        S.status = "Nenhum ovo encontrado."
    else
        S.status = tostring(#eggs) .. " ovos encontrados • escolha um ou use MAIS PROXIMO."
    end
end

refreshButton.MouseButton1Click:Connect(function()
    task.spawn(rebuildEggList)
end)

nearestButton.MouseButton1Click:Connect(function()
    if not S.busy then task.spawn(nearestAndSafe) end
end)

bringButton.MouseButton1Click:Connect(function()
    if S.busy then return end
    if not S.selected then
        S.status = "Escolha um ovo primeiro."
        return
    end

    local ok, err = bringEggToMe(S.selected)
    if not ok then
        S.status = "Nao foi possivel trazer: " .. tostring(err)
    end
end)

pickupButton.MouseButton1Click:Connect(function()
    if not S.busy then task.spawn(pickupAndSafe, S.selected) end
end)

safeButton.MouseButton1Click:Connect(function()
    if S.busy then return end
    local ok, err = teleportCharacter(SAFE_CFRAME)
    if ok then
        S.status = "SAFE ZONE ✓"
    else
        S.status = "Falha no TP Safe: " .. tostring(err)
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

task.spawn(function()
    while gui.Parent do
        status.Text = S.status

        if S.busy then
            nearestButton.Text = "PROCESSANDO..."
            pickupButton.Text = "PROCESSANDO..."
        else
            nearestButton.Text = "MAIS PROXIMO → PEGAR → SAFE"
            if S.selected then
                pickupButton.Text = "PEGAR " .. tostring(S.selected.name):sub(1, 14) .. " → SAFE"
            else
                pickupButton.Text = "PEGAR SELECIONADO → SAFE"
            end
        end

        task.wait(0.08)
    end
end)

task.spawn(rebuildEggList)

print("[CAFEINA EGG] CLIENT MENU V3 carregado ✓")
