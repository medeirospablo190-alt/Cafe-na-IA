--==============================================================--
-- CAFEÍNA • ITEM COLLECTOR MOBILE
-- Compacto / Client-side / Executor
--
-- Detecta no Workspace:
-- • Tool
-- • ProximityPrompt
-- • ClickDetector
-- Exibe somente: sucatas, energéticos e armas
-- Auto sucata retorna ao ponto de origem após cada coleta
-- Inclui teleporte para loja por interação real (Prompt/ClickDetector)
--
-- Estratégia:
-- 1) Tenta a interação normal disponível no cliente/executor.
-- 2) Se necessário, aproxima o personagem do item.
-- 3) Confirma Tool pelo Backpack/Character quando possível.
--
-- Observação:
-- Jogos com inventário próprio/server-side podem exigir lógica específica.
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local SCRIPT_VERSION = "CAFEINA_ITENS_V2_FIX_STARTUP"

local CONFIG = {
    GUI_NAME = "CafeinaItemCollectorMobile",
    MAX_ITEMS = 500,
    SAFE_OFFSET = Vector3.new(0, 3.5, 0),
    WAIT_AFTER_MOVE = 0.12,
    WAIT_AFTER_INTERACT = 0.35,
}

local Items = {}
local Index = 1
local Busy = false
local AutoScrapEnabled = false
local AutoScrapGeneration = 0
local AutoScrapOrigin = nil

--==============================================================--
-- HELPERS
--==============================================================--

local function getCharacter()
    local char = LocalPlayer.Character
    if not char then
        return nil, nil, nil
    end

    local root =
        char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")

    local hum = char:FindFirstChildOfClass("Humanoid")

    return char, root, hum
end

local function getBackpack()
    return LocalPlayer:FindFirstChildOfClass("Backpack")
        or LocalPlayer:FindFirstChild("Backpack")
end

local function getBasePart(inst)
    if not inst then
        return nil
    end

    if inst:IsA("BasePart") then
        return inst
    end

    if inst:IsA("Tool") then
        return inst:FindFirstChild("Handle")
            or inst:FindFirstChildWhichIsA("BasePart", true)
    end

    local parent = inst.Parent
    while parent and parent ~= Workspace do
        if parent:IsA("BasePart") then
            return parent
        end

        if parent:IsA("Model") then
            return parent.PrimaryPart
                or parent:FindFirstChildWhichIsA("BasePart", true)
        end

        parent = parent.Parent
    end

    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function safeName(inst)
    if not inst then
        return "?"
    end

    local name = inst.Name

    if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
        local p = inst.Parent
        if p then
            name = p.Name
        end
    end

    return tostring(name)
end

local function classify(inst)
    if inst:IsA("Tool") then
        return "TOOL"
    elseif inst:IsA("ProximityPrompt") then
        return "PROMPT"
    elseif inst:IsA("ClickDetector") then
        return "CLICK"
    end

    return nil
end


local CATEGORY_KEYWORDS = {
    SCRAP = {
        "scrap", "sucata", "metal scrap", "scrap metal",
    },
    ENERGY = {
        "energy", "energetic", "energético", "energetico",
        "energy drink", "energydrink", "soda", "cola",
        "coffee", "cafe", "café",
    },
    WEAPON = {
        "weapon", "gun", "rifle", "pistol", "shotgun",
        "revolver", "smg", "sniper", "machete", "knife",
        "katana", "sword", "bat", "axe", "ak-47", "ak47",
        "awm", "mp9", "fn fal", "fal", "svd", "winchester",
    },
}

local function normalizeText(value)
    return string.lower(tostring(value or ""))
end

local function entryText(inst)
    local pieces = {}

    if inst then
        pieces[#pieces + 1] = inst.Name

        local current = inst.Parent
        for _ = 1, 5 do
            if not current then break end
            pieces[#pieces + 1] = current.Name
            current = current.Parent
        end

        local ok, full = pcall(function()
            return inst:GetFullName()
        end)

        if ok then
            pieces[#pieces + 1] = full
        end
    end

    return normalizeText(table.concat(pieces, " "))
end

local function matchesAny(text, list)
    for _, keyword in ipairs(list) do
        if string.find(text, normalizeText(keyword), 1, true) then
            return true
        end
    end
    return false
end

local function getCategory(inst)
    local text = entryText(inst)

    if matchesAny(text, CATEGORY_KEYWORDS.SCRAP) then
        return "SUCATA"
    end

    if matchesAny(text, CATEGORY_KEYWORDS.ENERGY) then
        return "ENERGÉTICO"
    end

    if matchesAny(text, CATEGORY_KEYWORDS.WEAPON) then
        return "ARMA"
    end

    return nil
end

local function addUnique(inst, kind, seen)
    if not inst or not inst.Parent then
        return
    end

    local category = getCategory(inst)

    if not category then
        return
    end

    local key = inst

    if seen[key] then
        return
    end

    seen[key] = true

    Items[#Items + 1] = {
        instance = inst,
        kind = kind,
        category = category,
        name = safeName(inst),
    }
end

local function scanItems()
    table.clear(Items)

    local seen = {}

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if #Items >= CONFIG.MAX_ITEMS then
            break
        end

        local kind = classify(inst)

        if kind then
            addUnique(inst, kind, seen)
        end
    end

    table.sort(Items, function(a, b)
        if a.name == b.name then
            return a.kind < b.kind
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    if #Items == 0 then
        Index = 1
    else
        Index = math.clamp(Index, 1, #Items)
    end
end

local function selected()
    return Items[Index]
end

local function moveNear(inst)
    local char, root = getCharacter()

    if not char or not root then
        return false, "personagem não carregado"
    end

    local part = getBasePart(inst)

    if not part then
        return false, "item sem posição detectável"
    end

    local target =
        CFrame.new(part.Position + CONFIG.SAFE_OFFSET)

    local ok = pcall(function()
        char:PivotTo(target)
    end)

    if not ok then
        pcall(function()
            root.CFrame = target
        end)
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    return true
end

local function toolOwned(tool)
    if not tool then
        return false
    end

    local backpack = getBackpack()
    local char = LocalPlayer.Character

    if backpack and tool:IsDescendantOf(backpack) then
        return true
    end

    if char and tool:IsDescendantOf(char) then
        return true
    end

    return false
end

local function tryTool(tool)
    if toolOwned(tool) then
        return true, "já está no inventário"
    end

    local handle = getBasePart(tool)

    if not handle then
        return false, "Tool sem Handle/parte"
    end

    local _, root = getCharacter()

    if not root then
        return false, "personagem não carregado"
    end

    if typeof(firetouchinterest) == "function" then
        local ok = pcall(function()
            firetouchinterest(root, handle, 0)
            task.wait(0.05)
            firetouchinterest(root, handle, 1)
        end)

        if ok then
            task.wait(CONFIG.WAIT_AFTER_INTERACT)

            if toolOwned(tool) then
                return true, "Tool coletada"
            end
        end
    end

    local moved, err = moveNear(tool)

    if not moved then
        return false, err
    end

    task.wait(CONFIG.WAIT_AFTER_MOVE)

    if typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(root, handle, 0)
            task.wait(0.05)
            firetouchinterest(root, handle, 1)
        end)
    end

    task.wait(CONFIG.WAIT_AFTER_INTERACT)

    if toolOwned(tool) then
        return true, "Tool coletada"
    end

    return false, "interação feita; servidor pode exigir outra lógica"
end

local function tryPrompt(prompt)
    if not prompt or not prompt.Parent then
        return false, "Prompt removido"
    end

    local moved, err = moveNear(prompt)

    if not moved then
        return false, err
    end

    task.wait(CONFIG.WAIT_AFTER_MOVE)

    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)

        if ok then
            task.wait(CONFIG.WAIT_AFTER_INTERACT)
            return true, "Prompt acionado"
        end
    end

    return false, "executor sem fireproximityprompt"
end

local function tryClick(detector)
    if not detector or not detector.Parent then
        return false, "ClickDetector removido"
    end

    local moved, err = moveNear(detector)

    if not moved then
        return false, err
    end

    task.wait(CONFIG.WAIT_AFTER_MOVE)

    if typeof(fireclickdetector) == "function" then
        local ok = pcall(function()
            fireclickdetector(detector)
        end)

        if ok then
            task.wait(CONFIG.WAIT_AFTER_INTERACT)
            return true, "ClickDetector acionado"
        end
    end

    return false, "executor sem fireclickdetector"
end

local function collect(entry)
    if not entry or not entry.instance or not entry.instance.Parent then
        return false, "item não existe mais"
    end

    if entry.kind == "TOOL" then
        return tryTool(entry.instance)
    elseif entry.kind == "PROMPT" then
        return tryPrompt(entry.instance)
    elseif entry.kind == "CLICK" then
        return tryClick(entry.instance)
    end

    return false, "tipo não suportado"
end


--==============================================================--
-- SCRAP / SUCATA
--==============================================================--

local SCRAP_KEYWORDS = {
    "scrap",
    "sucata",
    "metal scrap",
    "scrap metal",
}

local function containsScrapKeyword(text)
    text = string.lower(tostring(text or ""))

    for _, keyword in ipairs(SCRAP_KEYWORDS) do
        if string.find(text, keyword, 1, true) then
            return true
        end
    end

    return false
end

local function isScrapEntry(entry)
    if not entry or not entry.instance then
        return false
    end

    if entry.category == "SUCATA" then
        return true
    end

    if containsScrapKeyword(entry.name) then
        return true
    end

    local inst = entry.instance
    local current = inst

    for _ = 1, 6 do
        if not current then
            break
        end

        if containsScrapKeyword(current.Name) then
            return true
        end

        current = current.Parent
    end

    local ok, fullName = pcall(function()
        return inst:GetFullName()
    end)

    return ok and containsScrapKeyword(fullName)
end

local function getScrapEntries()
    local result = {}

    for _, entry in ipairs(Items) do
        if isScrapEntry(entry) then
            result[#result + 1] = entry
        end
    end

    return result
end


--==============================================================--
-- RETORNO À ORIGEM / LOJA
--==============================================================--

local function captureOrigin()
    local char = LocalPlayer.Character
    if not char then
        return nil
    end

    local ok, pivot = pcall(function()
        return char:GetPivot()
    end)

    return ok and pivot or nil
end

local function returnToOrigin(origin)
    if not origin then
        return false
    end

    local char, root = getCharacter()
    if not char or not root then
        return false
    end

    local ok = pcall(function()
        char:PivotTo(origin)
    end)

    if not ok then
        pcall(function()
            root.CFrame = origin
        end)
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    return true
end


local SHOP_KEYWORDS = {
    "shop","store","buy","purchase","comprar","compra","loja",
    "vendor","merchant","trader","shopkeeper",
    "weaponshop","gunshop","itemshop","upgrade"
}

local function containsShopWord(value)
    local s = normalizeText(value)

    for _, keyword in ipairs(SHOP_KEYWORDS) do
        if string.find(s, keyword, 1, true) then
            return true
        end
    end

    return false
end

local function getShopText(object)
    local parts = {}

    if object then
        parts[#parts + 1] = object.Name

        local parent = object.Parent
        for _ = 1, 4 do
            if not parent then
                break
            end

            parts[#parts + 1] = parent.Name
            parent = parent.Parent
        end

        if object:IsA("ProximityPrompt") then
            parts[#parts + 1] = tostring(object.ActionText or "")
            parts[#parts + 1] = tostring(object.ObjectText or "")
        end
    end

    return table.concat(parts, " ")
end

local function getInteractionPart(object)
    if not object then
        return nil
    end

    if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
        return getBasePart(object)
    end

    return nil
end

local function classifyShopInteraction(object)
    if not object then
        return nil
    end

    if not (
        object:IsA("ProximityPrompt")
        or object:IsA("ClickDetector")
    ) then
        return nil
    end

    local combined = getShopText(object)

    if containsShopWord(combined) then
        return "Shop"
    end

    return nil
end

local function findShopTarget()
    local _, root = getCharacter()
    local candidates = {}

    for _, object in ipairs(Workspace:GetDescendants()) do
        local kind = classifyShopInteraction(object)

        if kind == "Shop" then
            local part = getInteractionPart(object)

            if part then
                local score = 0
                local combined = normalizeText(getShopText(object))

                if object:IsA("ProximityPrompt") then
                    score += 100

                    local action = normalizeText(object.ActionText or "")
                    local objectText = normalizeText(object.ObjectText or "")

                    if containsShopWord(action) then
                        score += 80
                    end

                    if containsShopWord(objectText) then
                        score += 80
                    end
                elseif object:IsA("ClickDetector") then
                    score += 45
                end

                if string.find(combined, "weaponshop", 1, true)
                or string.find(combined, "gunshop", 1, true)
                or string.find(combined, "itemshop", 1, true) then
                    score += 40
                end

                if root then
                    local distance =
                        (root.Position - part.Position).Magnitude

                    score -= math.min(distance / 300, 25)
                end

                candidates[#candidates + 1] = {
                    Object = object,
                    Part = part,
                    Score = score,
                    Text = combined,
                }
            end
        end
    end

    table.sort(candidates, function(a, b)
        if math.abs(a.Score - b.Score) > 0.01 then
            return a.Score > b.Score
        end

        if root then
            local da =
                (root.Position - a.Part.Position).Magnitude
            local db =
                (root.Position - b.Part.Position).Magnitude

            if math.abs(da - db) > 0.01 then
                return da < db
            end
        end

        return a.Part:GetFullName() < b.Part:GetFullName()
    end)

    return candidates[1]
end

local function teleportToShop()
    local char, root = getCharacter()

    if not char or not root then
        return false, "personagem não carregado"
    end

    local entry = findShopTarget()

    if not entry or not entry.Part or not entry.Part.Parent then
        return false, "LOJA NÃO ENCONTRADA"
    end

    local target = entry.Part
    local targetPosition = target.Position

    local away = root.Position - targetPosition
    away = Vector3.new(away.X, 0, away.Z)

    if away.Magnitude < 0.1 then
        away = Vector3.new(0, 0, 1)
    end

    away = away.Unit

    local destinationPosition =
        targetPosition
        + away * 4
        + Vector3.new(0, 3, 0)

    local destination =
        CFrame.lookAt(
            destinationPosition,
            Vector3.new(
                targetPosition.X,
                destinationPosition.Y,
                targetPosition.Z
            )
        )

    local ok = pcall(function()
        char:PivotTo(destination)
    end)

    if not ok then
        pcall(function()
            root.CFrame = destination
        end)
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    return true,
        "Loja: "
        .. entry.Object:GetFullName()
end

--==============================================================--
-- GUI CLEANUP
--==============================================================--

pcall(function()
    local old = CoreGui:FindFirstChild(CONFIG.GUI_NAME)
    if old then
        old:Destroy()
    end
end)

pcall(function()
    if gethui then
        local old = gethui():FindFirstChild(CONFIG.GUI_NAME)
        if old then
            old:Destroy()
        end
    end
end)

--==============================================================--
-- GUI
--==============================================================--

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

local parent = CoreGui
pcall(function()
    if gethui then
        parent = gethui()
    end
end)
Gui.Parent = parent

local BG = Color3.fromRGB(8,8,9)
local PANEL = Color3.fromRGB(16,16,18)
local BUTTON = Color3.fromRGB(24,24,27)
local TEXT = Color3.fromRGB(244,244,246)
local MUTED = Color3.fromRGB(155,155,162)
local BORDER = Color3.fromRGB(46,46,50)
local GREEN = Color3.fromRGB(55,185,95)

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(245, 279)
Main.Position = UDim2.new(0.5,-122,0.62,-95)
Main.BackgroundColor3 = BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local c = Instance.new("UICorner")
c.CornerRadius = UDim.new(0,10)
c.Parent = Main

local s = Instance.new("UIStroke")
s.Color = BORDER
s.Parent = Main

local Header = Instance.new("TextLabel")
Header.Size = UDim2.new(1,0,0,30)
Header.BackgroundTransparency = 1
Header.Text = "CAFEÍNA | ITENS"
Header.TextColor3 = TEXT
Header.TextSize = 12
Header.Font = Enum.Font.GothamBold
Header.Parent = Main

local SelectedLabel = Instance.new("TextLabel")
SelectedLabel.Size = UDim2.new(1,-16,0,48)
SelectedLabel.Position = UDim2.fromOffset(8,34)
SelectedLabel.BackgroundColor3 = PANEL
SelectedLabel.BorderSizePixel = 0
SelectedLabel.TextColor3 = TEXT
SelectedLabel.TextSize = 11
SelectedLabel.Font = Enum.Font.GothamBold
SelectedLabel.TextWrapped = true
SelectedLabel.Parent = Main

local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0,7)
cc.Parent = SelectedLabel

local Prev = Instance.new("TextButton")
Prev.Size = UDim2.fromOffset(54,34)
Prev.Position = UDim2.fromOffset(8,89)
Prev.BackgroundColor3 = BUTTON
Prev.BorderSizePixel = 0
Prev.Text = "<"
Prev.TextColor3 = TEXT
Prev.TextSize = 16
Prev.Font = Enum.Font.GothamBold
Prev.Parent = Main

local Next = Prev:Clone()
Next.Position = UDim2.fromOffset(183,89)
Next.Text = ">"
Next.Parent = Main

local Refresh = Instance.new("TextButton")
Refresh.Size = UDim2.fromOffset(105,34)
Refresh.Position = UDim2.fromOffset(70,89)
Refresh.BackgroundColor3 = BUTTON
Refresh.BorderSizePixel = 0
Refresh.Text = "ATUALIZAR"
Refresh.TextColor3 = TEXT
Refresh.TextSize = 10
Refresh.Font = Enum.Font.GothamBold
Refresh.Parent = Main

for _,b in ipairs({Prev,Next,Refresh}) do
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0,7)
    bc.Parent = b
end

local Collect = Instance.new("TextButton")
Collect.Size = UDim2.new(1,-16,0,38)
Collect.Position = UDim2.fromOffset(8,130)
Collect.BackgroundColor3 = GREEN
Collect.BorderSizePixel = 0
Collect.Text = "PEGAR ITEM"
Collect.TextColor3 = TEXT
Collect.TextSize = 11
Collect.Font = Enum.Font.GothamBold
Collect.Parent = Main

local collectCorner = Instance.new("UICorner")
collectCorner.CornerRadius = UDim.new(0,7)
collectCorner.Parent = Collect


local ScrapCollect = Instance.new("TextButton")
ScrapCollect.Size = UDim2.new(1,-16,0,38)
ScrapCollect.Position = UDim2.fromOffset(8,175)
ScrapCollect.BackgroundColor3 = Color3.fromRGB(115, 76, 35)
ScrapCollect.BorderSizePixel = 0
ScrapCollect.Text = "COLETAR SUCATAS"
ScrapCollect.TextColor3 = TEXT
ScrapCollect.TextSize = 11
ScrapCollect.Font = Enum.Font.GothamBold
ScrapCollect.Parent = Main

local scrapCorner = Instance.new("UICorner")
scrapCorner.CornerRadius = UDim.new(0,7)
scrapCorner.Parent = ScrapCollect


local ShopButton = Instance.new("TextButton")
ShopButton.Size = UDim2.new(1,-16,0,38)
ShopButton.Position = UDim2.fromOffset(8,217)
ShopButton.BackgroundColor3 = BUTTON
ShopButton.BorderSizePixel = 0
ShopButton.Text = "TELEPORTAR PARA LOJA"
ShopButton.TextColor3 = TEXT
ShopButton.TextSize = 11
ShopButton.Font = Enum.Font.GothamBold
ShopButton.Parent = Main

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0,7)
shopCorner.Parent = ShopButton

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1,-16,0,16)
Status.Position = UDim2.fromOffset(8,260)
Status.BackgroundTransparency = 1
Status.Text = "Pronto"
Status.TextColor3 = MUTED
Status.TextSize = 9
Status.Font = Enum.Font.Gotham
Status.TextTruncate = Enum.TextTruncate.AtEnd
Status.Parent = Main

local function updateSelection()
    local entry = selected()

    if not entry then
        SelectedLabel.Text = "Nenhum item detectado"
        return
    end

    SelectedLabel.Text =
        string.format(
            "%d/%d  •  %s\n%s",
            Index,
            #Items,
            entry.category or entry.kind,
            entry.name
        )
end

local function rescan()
    Status.Text = "Buscando itens..."
    scanItems()
    updateSelection()

    if #Items > 0 then
        Status.Text = tostring(#Items) .. " sucata(s)/energético(s)/arma(s)"
    else
        Status.Text = "Nenhum item detectado"
    end
end

Prev.Activated:Connect(function()
    if #Items == 0 then return end
    Index -= 1
    if Index < 1 then Index = #Items end
    updateSelection()
end)

Next.Activated:Connect(function()
    if #Items == 0 then return end
    Index += 1
    if Index > #Items then Index = 1 end
    updateSelection()
end)

Refresh.Activated:Connect(rescan)

Collect.Activated:Connect(function()
    if Busy then
        return
    end

    local entry = selected()

    if not entry then
        Status.Text = "Nenhum item selecionado"
        return
    end

    Busy = true
    Collect.Text = "COLETANDO..."

    local ok, msg = collect(entry)

    Status.Text =
        (ok and "OK: " or "Aviso: ")
        .. tostring(msg)

    task.wait(0.15)
    scanItems()
    updateSelection()

    Collect.Text = "PEGAR ITEM"
    Busy = false
end)



ShopButton.Activated:Connect(function()
    if Busy then
        return
    end

    Busy = true
    ShopButton.Text = "VALIDANDO LOJA..."

    local ok, msg = teleportToShop()
    Status.Text = (ok and "OK: " or "Aviso: ") .. tostring(msg)

    ShopButton.Text = "TELEPORTAR PARA LOJA"
    Busy = false
end)

local function setScrapButtonVisual()
    if AutoScrapEnabled then
        ScrapCollect.Text = "AUTO SUCATA: ON"
        ScrapCollect.BackgroundColor3 = GREEN
    else
        ScrapCollect.Text = "AUTO SUCATA: OFF"
        ScrapCollect.BackgroundColor3 = Color3.fromRGB(115, 76, 35)
    end
end

local function runAutoScrapLoop(generation)
    task.spawn(function()
        while AutoScrapEnabled
        and generation == AutoScrapGeneration
        and Gui.Parent do

            if not Busy then
                Busy = true

                Status.Text = "Procurando sucatas..."
                scanItems()

                local scraps = getScrapEntries()

                if #scraps == 0 then
                    Status.Text = "Auto sucata ativo • aguardando spawn"
                else
                    for _, entry in ipairs(scraps) do
                        if not AutoScrapEnabled
                        or generation ~= AutoScrapGeneration then
                            break
                        end

                        if entry.instance
                        and entry.instance.Parent then
                            Status.Text =
                                "Sucata detectada • coletando "
                                .. tostring(entry.name)

                            pcall(function()
                                collect(entry)
                            end)

                            task.wait(0.10)

                            if AutoScrapOrigin then
                                returnToOrigin(AutoScrapOrigin)
                                Status.Text = "Sucata coletada • retornando"
                            end

                            task.wait(0.10)
                        end
                    end

                    scanItems()
                    updateSelection()

                    if AutoScrapEnabled then
                        Status.Text =
                            "Auto sucata ativo • buscando novamente"
                    end
                end

                Busy = false
            end

            task.wait(0.15)
        end

        if generation == AutoScrapGeneration then
            Busy = false
        end
    end)
end

ScrapCollect.Activated:Connect(function()
    AutoScrapEnabled = not AutoScrapEnabled
    AutoScrapGeneration += 1

    setScrapButtonVisual()

    if AutoScrapEnabled then
        AutoScrapOrigin = captureOrigin()

        if not AutoScrapOrigin then
            AutoScrapEnabled = false
            setScrapButtonVisual()
            Status.Text = "Não foi possível salvar a origem"
            return
        end

        Status.Text = "Auto sucata iniciado • origem salva"
        runAutoScrapLoop(AutoScrapGeneration)
    else
        if AutoScrapOrigin then
            returnToOrigin(AutoScrapOrigin)
        end

        AutoScrapOrigin = nil
        Status.Text = "Auto sucata desligado"
    end
end)

setScrapButtonVisual()

--==============================================================--
-- DRAG MOBILE
--==============================================================--

local dragging = false
local dragStart
local startPos
local dragInput

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart

        Main.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

rescan()

print("[CAFEÍNA] Item Collector Mobile carregado.")
