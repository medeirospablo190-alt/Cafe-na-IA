--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V6.2
-- Mobile/executor • CLIENT-SIDE ONLY
--
-- V6.2:
-- • AUTO SAFE confirma o carry pelo modelo replicado CarriedAreaEgg
-- • Dinheiro visual mira apenas PlayerGui.Money.Bottom.Frame.Money
-- • Painel ITENS lista Tools client-visible compatíveis com Backpack
-- • ADICIONAR LOCAL clona o item selecionado para o Backpack local
--==============================================================--

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local StarterPack = game:GetService("StarterPack")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

for _, key in ipairs({
    "__CAFEINA_EGG_V62", "__CAFEINA_EGG_V61", "__CAFEINA_EGG_V6", "__CAFEINA_EGG_V5"
}) do
    pcall(function()
        local old = rawget(ENV, key)
        if type(old) == "table" and type(old.Cleanup) == "function" then
            old.Cleanup()
        end
    end)
end

for _, key in ipairs({
    "__CAFEINA_EGG_V62_GUI", "__CAFEINA_EGG_V61_GUI", "__CAFEINA_EGG_V6_GUI", "__CAFEINA_EGG_V5_GUI"
}) do
    pcall(function()
        local old = rawget(ENV, key)
        if typeof(old) == "Instance" then
            old:Destroy()
        end
    end)
end

local S = {
    autoSafe = true,
    god = false,
    isolate = false,
    selected = nil,
    status = "AUTO SAFE ON • aguardando carry confirmado",
    lastEggTp = 0,
    pendingCarryUntil = 0,

    conns = {},
    isolateConns = {},
    savedParts = setmetatable({}, {__mode = "k"}),
    hookedEggRemotes = setmetatable({}, {__mode = "k"}),
    watchedCarried = setmetatable({}, {__mode = "k"}),

    rows = {},

    moneyVisual = nil,
    moneyBase = nil,
    moneyLabel = nil,
    savedMoneyText = setmetatable({}, {__mode = "k"}),
    lastMoneyBind = 0,

    itemCandidates = {},
    selectedItem = nil,
    itemRows = {},
    itemQuery = "",
    itemRefreshQueued = false,
    itemPanelOpen = false,
}

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or S.conns, c)
    return c
end

local function status(text)
    S.status = tostring(text or "")
end

local function char(plr)
    plr = plr or LP
    local c = plr.Character
    if not c then
        return nil, nil, nil
    end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function moveModel(c, root, cf)
    if not c or not root then
        return false, "root indisponivel"
    end

    local ok, err = pcall(function()
        c:PivotTo(cf)
    end)

    if not ok then
        ok, err = pcall(function()
            root.CFrame = cf
        end)
    end

    return ok, err
end

local function tpSelf(cf)
    local c, root = char(LP)
    return moveModel(c, root, cf)
end

local function fmt(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    local sign = n < 0 and "-" or ""

    if a >= 1e15 then return sign .. string.format("%.2fQ", a / 1e15) end
    if a >= 1e12 then return sign .. string.format("%.2fT", a / 1e12) end
    if a >= 1e9 then return sign .. string.format("%.2fB", a / 1e9) end
    if a >= 1e6 then return sign .. string.format("%.2fM", a / 1e6) end
    if a >= 1e3 then return sign .. string.format("%.2fK", a / 1e3) end

    return sign .. tostring(math.floor(a + 0.5))
end

local function currentNetwork(name)
    local network = RS:FindFirstChild("Network")
    return network and network:FindFirstChild(name)
end

--============================ AUTO SAFE ============================--

local function autoSafe(reason)
    if not S.autoSafe then
        return
    end

    local now = os.clock()
    if now - S.lastEggTp < 0.75 then
        return
    end

    S.lastEggTp = now
    task.defer(function()
        task.wait(0.03)
        local ok, err = tpSelf(SAFE_CF)
        if ok then
            status("OVO > SAFE ✓ • " .. tostring(reason or "carry confirmado"))
        else
            status("AUTO SAFE falhou: " .. tostring(err))
        end
    end)
end

local function isLocalCarriedEgg(model)
    if not model or not model:IsA("Model") then
        return false
    end

    if not string.find(model.Name, "CarriedAreaEgg_", 1, true) then
        return false
    end

    local carrier = tonumber(model:GetAttribute("CarrierUserId"))
    return carrier == LP.UserId
end

local function checkCarriedModel(model, reason)
    if isLocalCarriedEgg(model) then
        autoSafe(reason or "CarriedAreaEgg confirmado")
        return true
    end
    return false
end

local function watchCarriedModel(model)
    if S.watchedCarried[model] or not model:IsA("Model") then
        return
    end

    if not string.find(model.Name, "CarriedAreaEgg_", 1, true) then
        return
    end

    S.watchedCarried[model] = true

    if checkCarriedModel(model, "CarrierUserId confirmado") then
        return
    end

    connect(model:GetAttributeChangedSignal("CarrierUserId"), function()
        checkCarriedModel(model, "CarrierUserId confirmado")
    end)
end

for _, obj in ipairs(Workspace:GetChildren()) do
    watchCarriedModel(obj)
end

connect(Workspace.ChildAdded, function(obj)
    if obj:IsA("Model") then
        watchCarriedModel(obj)
    end
end)

local function hasLocalCarry(t, depth, targeted)
    if type(t) ~= "table" or (depth or 0) > 4 then
        return false
    end

    depth = depth or 0
    local carrier = tonumber(t.CarrierUserId or t.CarrierId or t.UserId)
    local state = tostring(t.State or t.state or "")

    if carrier == LP.UserId and (state == "Carried" or t.IsCarrying == true) then
        return true
    end

    if targeted and t.IsCarrying == true and (carrier == nil or carrier == LP.UserId) then
        return true
    end

    for _, v in pairs(t) do
        if type(v) == "table" and hasLocalCarry(v, depth + 1, targeted) then
            return true
        end
    end

    return false
end

local function hookLegacyEggRemote(r)
    if S.hookedEggRemotes[r] or not r:IsA("RemoteEvent") then
        return
    end

    local n = r.Name
    if n ~= "RE/EggWorld/FieldEggCarry" and n ~= "RE/EggWorld/FieldEggShifted" then
        return
    end

    S.hookedEggRemotes[r] = true

    connect(r.OnClientEvent, function(...)
        if not S.autoSafe then
            return
        end

        local targeted = n == "RE/EggWorld/FieldEggCarry"
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "table" and hasLocalCarry(v, 0, targeted) then
                autoSafe(targeted and "FieldEggCarry" or "FieldEggShifted")
                return
            end
        end
    end)
end

for _, r in ipairs(RS:GetDescendants()) do
    hookLegacyEggRemote(r)
end

connect(RS.DescendantAdded, hookLegacyEggRemote)

connect(PPS.PromptTriggered, function(prompt, player)
    if not S.autoSafe or (player and player ~= LP) then
        return
    end

    local name = string.lower(prompt.Name)
    local action = string.lower(tostring(prompt.ActionText or ""))
    local object = string.lower(tostring(prompt.ObjectText or ""))

    local match = name:find("carryareaegg", 1, true)
        or (
            (action:find("steal", 1, true) or action:find("carry", 1, true) or action:find("take", 1, true))
            and (object:find("egg", 1, true) or object:find("ovo", 1, true))
        )

    if match then
        S.pendingCarryUntil = os.clock() + 3
        status("Roubo detectado • aguardando CarrierUserId do servidor")
    end
end)

--========================== DINHEIRO VISUAL =========================--

local function getMoneyRoot()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then
        return nil
    end

    local moneyGui = pg:FindFirstChild("Money")
    local bottom = moneyGui and moneyGui:FindFirstChild("Bottom")
    local frame = bottom and bottom:FindFirstChild("Frame")
    return frame and frame:FindFirstChild("Money")
end

local function isInsideNamed(obj, stop, wanted)
    local p = obj
    while p and p ~= stop do
        if p.Name == wanted then
            return true
        end
        p = p.Parent
    end
    return false
end

local function parseCompactNumber(text)
    local s = tostring(text or "")
    local suffix = string.match(s, "([KMBTQkmbtq])%s*$")
    local mult = 1

    if suffix then
        local u = string.upper(suffix)
        if u == "K" then mult = 1e3
        elseif u == "M" then mult = 1e6
        elseif u == "B" then mult = 1e9
        elseif u == "T" then mult = 1e12
        elseif u == "Q" then mult = 1e15
        end
    end

    s = s:gsub("[KMBTQkmbtq]", "")
    s = s:gsub("[^%d%.,%-]", "")

    if s == "" or s == "-" then
        return nil
    end

    local commaCount = select(2, s:gsub(",", ""))
    local dotCount = select(2, s:gsub("%.", ""))

    if commaCount > 0 and dotCount > 0 then
        s = s:gsub(",", "")
    elseif commaCount > 0 and dotCount == 0 then
        local decimals = s:match(",(%d+)$")
        if decimals and #decimals <= 2 then
            s = s:gsub(",", ".")
        else
            s = s:gsub(",", "")
        end
    elseif dotCount > 1 then
        s = s:gsub("%.", "")
    end

    local n = tonumber(s)
    if not n then
        return nil
    end

    return n * mult
end

local function moneyLabelScore(label, root)
    if not (label:IsA("TextLabel") or label:IsA("TextButton")) then
        return -999
    end

    if isInsideNamed(label, root, "Changes") then
        return -999
    end

    local score = 0
    local name = string.lower(label.Name)
    local text = tostring(label.Text or "")

    if parseCompactNumber(text) ~= nil then
        score = score + 12
    end

    if name:find("money", 1, true) then score = score + 6 end
    if name:find("value", 1, true) then score = score + 5 end
    if name:find("amount", 1, true) then score = score + 5 end
    if name == "label" then score = score + 2 end
    if label.Visible then score = score + 2 end
    if text:find("%$") then score = score + 2 end

    return score
end

local function findMoneyLabel()
    local root = getMoneyRoot()
    if not root then
        return nil
    end

    local candidates = {}

    if root:IsA("TextLabel") or root:IsA("TextButton") then
        table.insert(candidates, root)
    end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            table.insert(candidates, d)
        end
    end

    table.sort(candidates, function(a, b)
        return moneyLabelScore(a, root) > moneyLabelScore(b, root)
    end)

    local best = candidates[1]
    if best and moneyLabelScore(best, root) >= 2 then
        return best
    end

    return nil
end

local function replaceNumberPreservingText(label, value)
    local old = tostring(label.Text or "")
    local rendered = fmt(value)

    local replaced, count = old:gsub("[%d][%d%.,]*[KMBTQkmbtq]?", rendered, 1)
    if count > 0 then
        return replaced
    end

    if old:find("%$") then
        return "$" .. rendered
    end

    return rendered
end

local function captureMoneyBase()
    local label = findMoneyLabel()
    if not label then
        return nil, nil
    end

    local n = parseCompactNumber(label.Text)
    return label, n
end

local function syncMoneyHud()
    if S.moneyVisual == nil then
        return false, "dinheiro visual desligado"
    end

    local label = S.moneyLabel
    if not label or not label.Parent then
        label = findMoneyLabel()
        S.moneyLabel = label
    end

    if not label then
        return false, "HUD Money.Bottom.Frame.Money nao encontrada"
    end

    if S.savedMoneyText[label] == nil then
        S.savedMoneyText[label] = label.Text
    end

    pcall(function()
        label.Text = replaceNumberPreservingText(label, S.moneyVisual)
    end)

    return true, label:GetFullName()
end

local function setVisualMoney(raw)
    local text = tostring(raw or ""):gsub(",", ".")
    local amount = tonumber(text)
    if not amount then
        return false, "quantidade invalida"
    end

    amount = math.clamp(amount, -1e15, 1e15)

    local label, base = captureMoneyBase()
    if label then
        S.moneyLabel = label
        if S.savedMoneyText[label] == nil then
            S.savedMoneyText[label] = label.Text
        end
    end

    S.moneyBase = base or S.moneyBase or 0
    S.moneyVisual = amount

    local ok, info = syncMoneyHud()
    if ok then
        return true, "$" .. fmt(amount) .. " na HUD local"
    end
    return true, "$" .. fmt(amount) .. " preparado • " .. tostring(info)
end

local function addVisualMoney(raw)
    local text = tostring(raw or ""):gsub(",", ".")
    local amount = tonumber(text)
    if not amount then
        return false, "quantidade invalida"
    end

    amount = math.clamp(amount, -1e15, 1e15)

    if S.moneyVisual == nil then
        local label, base = captureMoneyBase()
        if label then
            S.moneyLabel = label
            if S.savedMoneyText[label] == nil then
                S.savedMoneyText[label] = label.Text
            end
        end
        S.moneyBase = base or 0
        S.moneyVisual = S.moneyBase
    end

    S.moneyVisual = math.clamp((S.moneyVisual or 0) + amount, -1e15, 1e15)
    syncMoneyHud()
    return true, "$" .. fmt(S.moneyVisual) .. " na HUD local"
end

local function clearVisualMoney()
    for label, old in pairs(S.savedMoneyText) do
        if label and label.Parent then
            pcall(function()
                label.Text = old
            end)
        end
    end

    S.savedMoneyText = setmetatable({}, {__mode = "k"})
    S.moneyVisual = nil
    S.moneyBase = nil
    S.moneyLabel = nil
    return true, "dinheiro visual restaurado"
end

local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
if pg then
    connect(pg.DescendantAdded, function(d)
        if S.moneyVisual ~= nil then
            local root = getMoneyRoot()
            if root and (d == root or d:IsDescendantOf(root)) then
                task.defer(function()
                    S.moneyLabel = nil
                    syncMoneyHud()
                end)
            end
        end
    end)
end

--============================ ITENS ================================--

local function isInsideAnyCharacter(obj)
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if c and obj:IsDescendantOf(c) then
            return true
        end
    end
    return false
end

local function itemMeta(tool)
    local itemType = tool:GetAttribute("ItemType") or tool:GetAttribute("ITEM_TYPE")
    local display = tool:GetAttribute("DisplayName")
        or tool:GetAttribute("EggName")
        or tool:GetAttribute("GearName")
        or tool.Name
    local uid = tool:GetAttribute("UID") or tool:GetAttribute("ITEM_UUID") or ""
    return tostring(display), tostring(itemType or "Tool"), tostring(uid)
end

local function itemSource(tool)
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack and tool:IsDescendantOf(backpack) then
        return "MEU"
    end

    local c = LP.Character
    if c and tool:IsDescendantOf(c) then
        return "EQUIPADO"
    end

    if tool:IsDescendantOf(RS) then
        return "TEMPLATE"
    end

    if tool:IsDescendantOf(StarterPack) then
        return "STARTER"
    end

    if tool:IsDescendantOf(Workspace) then
        return "MUNDO"
    end

    return "CLIENT"
end

local function isUsefulTool(tool)
    if not tool:IsA("Tool") then
        return false
    end

    local lower = string.lower(tool.Name)
    if lower:find("treadmillrender", 1, true) or lower:find("__client", 1, true) then
        return false
    end

    if isInsideAnyCharacter(tool) then
        local c = LP.Character
        if not (c and tool:IsDescendantOf(c)) then
            return false
        end
    end

    local source = itemSource(tool)

    if source == "TEMPLATE" or source == "STARTER" or source == "MEU" or source == "EQUIPADO" then
        return true
    end

    if source == "MUNDO" then
        if tool:GetAttribute("ItemType") ~= nil
            or tool:GetAttribute("ITEM_TYPE") ~= nil
            or tool:GetAttribute("UID") ~= nil
            or tool:GetAttribute("GearName") ~= nil
            or tool:GetAttribute("EggName") ~= nil
            or tool:GetAttribute("DisplayName") ~= nil then
            return true
        end
    end

    return false
end

local function candidateKey(tool)
    local display, itemType, uid = itemMeta(tool)
    return itemSource(tool) .. "|" .. display .. "|" .. itemType .. "|" .. uid .. "|" .. tool.Name
end

local function scanItemCandidates()
    local out = {}
    local seen = {}
    local scanned = 0
    local cap = 250

    local roots = {RS, StarterPack, Workspace}
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        table.insert(roots, 1, backpack)
    end
    if LP.Character then
        table.insert(roots, 2, LP.Character)
    end

    for _, root in ipairs(roots) do
        if #out >= cap then
            break
        end

        local objects = {root}
        for _, d in ipairs(root:GetDescendants()) do
            table.insert(objects, d)
        end

        for _, d in ipairs(objects) do
            scanned = scanned + 1
            if scanned % 600 == 0 then
                task.wait()
            end

            if d:IsA("Tool") and isUsefulTool(d) then
                local key = candidateKey(d)
                if not seen[key] then
                    seen[key] = true
                    local display, itemType, uid = itemMeta(d)
                    table.insert(out, {
                        tool = d,
                        name = display,
                        itemType = itemType,
                        uid = uid,
                        source = itemSource(d),
                        key = key,
                    })

                    if #out >= cap then
                        break
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.source ~= b.source then
            return a.source < b.source
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    S.itemCandidates = out
    return out
end

local function addSelectedItemLocal()
    local c = S.selectedItem
    if not c or not c.tool or not c.tool.Parent then
        return false, "selecione um item"
    end

    local backpack = LP:FindFirstChildOfClass("Backpack") or LP:WaitForChild("Backpack", 3)
    if not backpack then
        return false, "Backpack indisponivel"
    end

    local ok, cloneOrErr = pcall(function()
        local clone = c.tool:Clone()
        clone:SetAttribute("CafeinaLocalClone", true)
        clone.Parent = backpack
        return clone
    end)

    if not ok then
        return false, "clone falhou: " .. tostring(cloneOrErr)
    end

    return true, tostring(c.name) .. " adicionado LOCAL ao Backpack"
end

local function removeLocalClones()
    local removed = 0

    local function clear(root)
        if not root then return end
        for _, d in ipairs(root:GetChildren()) do
            if d:IsA("Tool") and d:GetAttribute("CafeinaLocalClone") == true then
                pcall(function()
                    d:Destroy()
                end)
                removed = removed + 1
            end
        end
    end

    clear(LP:FindFirstChildOfClass("Backpack"))
    clear(LP.Character)

    return removed
end

--========================== GOD / ISOLAR ============================--

local function blockPart(p)
    if not p:IsA("BasePart") then
        return
    end

    if not S.savedParts[p] then
        S.savedParts[p] = {p.CanCollide, p.CanTouch, p.CanQuery}
    end

    pcall(function()
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
    end)
end

local function isolateChar(c)
    if not S.isolate or not c or c == LP.Character then
        return
    end

    for _, d in ipairs(c:GetDescendants()) do
        blockPart(d)
    end

    local x = c.DescendantAdded:Connect(function(d)
        if S.isolate then
            blockPart(d)
        end
    end)

    table.insert(S.isolateConns, x)
end

local function restoreIsolation()
    for _, c in ipairs(S.isolateConns) do
        pcall(function()
            c:Disconnect()
        end)
    end

    table.clear(S.isolateConns)

    for p, old in pairs(S.savedParts) do
        if p and p.Parent then
            pcall(function()
                p.CanCollide = old[1]
                p.CanTouch = old[2]
                p.CanQuery = old[3]
            end)
        end
    end

    table.clear(S.savedParts)
end

local function setIsolation(on)
    S.isolate = on == true
    restoreIsolation()

    if S.isolate then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                isolateChar(p.Character)
            end
        end
    end

    status(S.isolate and "ISOLAR LOCAL ON" or "ISOLAR LOCAL OFF")
end

connect(RunService.Heartbeat, function()
    local _, root, hum = char(LP)

    if hum and (S.god or S.isolate) then
        pcall(function()
            hum.BreakJointsOnDeath = false
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            if hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        end)
    end

    if S.isolate and root then
        local v = root.AssemblyLinearVelocity
        if Vector3.new(v.X, 0, v.Z).Magnitude > 130 then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.new(0, math.clamp(v.Y, -80, 80), 0)
            end)
        end

        if root.AssemblyAngularVelocity.Magnitude > 40 then
            pcall(function()
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end)

--========================== PLAYER ACTIONS ==========================--

local function tpTo(plr)
    if not plr or plr == LP then
        return false, "selecione outro jogador"
    end

    local _, root = char(plr)
    if not root then
        return false, "alvo sem root"
    end

    return tpSelf(root.CFrame * CFrame.new(0, 0, 3))
end

local function pullOne(plr, offset)
    if not plr or plr == LP then
        return false, "selecione outro jogador"
    end

    local c, root = char(plr)
    local _, myRoot = char(LP)

    if not c or not root or not myRoot then
        return false, "personagem indisponivel"
    end

    return moveModel(c, root, myRoot.CFrame * (offset or CFrame.new(0, 0, -3)))
end

local function pullAll()
    local _, myRoot = char(LP)
    if not myRoot then
        return 0, "seu root indisponivel"
    end

    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(targets, p)
        end
    end

    local moved = 0
    for i, p in ipairs(targets) do
        local a = ((i - 1) / math.max(1, #targets)) * math.pi * 2
        local ok = pullOne(p, CFrame.new(math.cos(a) * 4, 0, math.sin(a) * 4))
        if ok then
            moved = moved + 1
        end
    end

    return moved, nil
end

local function killLocal(plr)
    if not plr or plr == LP then
        return false, "selecione outro jogador"
    end

    local _, _, hum = char(plr)
    if not hum then
        return false, "alvo sem Humanoid"
    end

    return pcall(function()
        hum.Health = 0
        hum:ChangeState(Enum.HumanoidStateType.Dead)
    end)
end

--================================ GUI ================================--

local parent
pcall(function()
    if gethui then
        parent = gethui()
    end
end)

if not parent then
    pcall(function()
        parent = CoreGui
    end)
end

if not parent then
    parent = LP:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggV62"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parentOk = pcall(function()
    gui.Parent = parent
end)
if not parentOk then
    gui.Parent = LP:WaitForChild("PlayerGui")
end

ENV.__CAFEINA_EGG_V62_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(310, 400)
frame.Position = UDim2.new(0, 10, 0.5, -200)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -62, 0, 25)
title.Position = UDim2.fromOffset(8, 5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • EGG V6.2"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local min = Instance.new("TextButton")
min.Size = UDim2.fromOffset(48, 22)
min.Position = UDim2.new(1, -56, 0, 6)
min.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
min.BorderSizePixel = 0
min.Text = "MIN"
min.TextColor3 = Color3.new(1, 1, 1)
min.Font = Enum.Font.GothamBold
min.TextSize = 8
min.Parent = frame
Instance.new("UICorner", min).CornerRadius = UDim.new(0, 6)

local stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1, -16, 0, 24)
stat.Position = UDim2.fromOffset(8, 32)
stat.BackgroundTransparency = 1
stat.TextWrapped = true
stat.TextColor3 = Color3.fromRGB(180, 180, 190)
stat.Font = Enum.Font.Gotham
stat.TextSize = 8
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Parent = frame

local function button(text, xs, xo, y, ws, wo, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(ws, wo, 0, 28)
    b.Position = UDim2.new(xs, xo, 0, y)
    b.BackgroundColor3 = color or Color3.fromRGB(43, 43, 50)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 8
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local autoBtn = button("AUTO SAFE: ON", 0, 8, 60, 1/3, -9, Color3.fromRGB(100, 30, 34))
local godBtn = button("GOD: OFF", 1/3, 3, 60, 1/3, -6)
local isoBtn = button("ISOLAR: OFF", 2/3, 1, 60, 1/3, -9)

local safeBtn = button("IR SAFE AGORA", 0, 8, 92, 0.5, -10, Color3.fromRGB(90, 30, 34))
local itemsBtn = button("ITENS", 0.5, 2, 92, 0.5, -10, Color3.fromRGB(48, 48, 60))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -16, 0, 112)
list.Position = UDim2.fromOffset(8, 124)
list.BackgroundColor3 = Color3.fromRGB(23, 23, 27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.fromOffset(0, 0)
list.Parent = frame
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 7)

local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 3)

local pad = Instance.new("UIPadding", list)
pad.PaddingTop = UDim.new(0, 4)
pad.PaddingBottom = UDim.new(0, 4)
pad.PaddingLeft = UDim.new(0, 4)
pad.PaddingRight = UDim.new(0, 4)

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1, -16, 0, 22)
selectedLabel.Position = UDim2.fromOffset(8, 240)
selectedLabel.BackgroundTransparency = 1
selectedLabel.Text = "Alvo: nenhum"
selectedLabel.TextColor3 = Color3.fromRGB(205, 205, 215)
selectedLabel.Font = Enum.Font.Gotham
selectedLabel.TextSize = 8
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Parent = frame

local amount = Instance.new("TextBox")
amount.Size = UDim2.new(1, -16, 0, 28)
amount.Position = UDim2.fromOffset(8, 266)
amount.BackgroundColor3 = Color3.fromRGB(28, 28, 33)
amount.BorderSizePixel = 0
amount.ClearTextOnFocus = false
amount.Text = "1000"
amount.PlaceholderText = "Dinheiro visual local"
amount.TextColor3 = Color3.fromRGB(240, 240, 245)
amount.Font = Enum.Font.Code
amount.TextSize = 9
amount.Parent = frame
Instance.new("UICorner", amount).CornerRadius = UDim.new(0, 6)

local tpBtn = button("TP > ALVO", 0, 8, 298, 1/3, -9)
local pullBtn = button("ALVO > MIM", 1/3, 3, 298, 1/3, -6)
local allBtn = button("TODOS > MIM", 2/3, 1, 298, 1/3, -9)

local killBtn = button("KILL LOCAL", 0, 8, 330, 1/3, -9, Color3.fromRGB(112, 28, 32))
local moneySetBtn = button("SET $ EU", 1/3, 3, 330, 1/3, -6)
local moneyAddBtn = button("+ $ EU", 2/3, 1, 330, 1/3, -9)

local moneyClearBtn = button("LIMPAR $ VISUAL", 0, 8, 362, 1, -16)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(82, 36)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mini.BorderSizePixel = 0
mini.Text = "EGG V6.2"
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 8
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 8)

--=========================== GUI ITENS ==============================--

local itemFrame = Instance.new("Frame")
itemFrame.Size = UDim2.fromOffset(330, 430)
itemFrame.Position = UDim2.new(0.5, -165, 0.5, -215)
itemFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
itemFrame.BorderSizePixel = 0
itemFrame.Active = true
itemFrame.Visible = false
itemFrame.Parent = gui
Instance.new("UICorner", itemFrame).CornerRadius = UDim.new(0, 10)

local itemTitle = Instance.new("TextLabel")
itemTitle.Size = UDim2.new(1, -60, 0, 28)
itemTitle.Position = UDim2.fromOffset(10, 6)
itemTitle.BackgroundTransparency = 1
itemTitle.Text = "ITENS • BACKPACK LOCAL"
itemTitle.TextColor3 = Color3.fromRGB(245, 245, 248)
itemTitle.Font = Enum.Font.GothamBold
itemTitle.TextSize = 11
itemTitle.TextXAlignment = Enum.TextXAlignment.Left
itemTitle.Active = true
itemTitle.Parent = itemFrame

local itemClose = Instance.new("TextButton")
itemClose.Size = UDim2.fromOffset(42, 24)
itemClose.Position = UDim2.new(1, -50, 0, 7)
itemClose.BackgroundColor3 = Color3.fromRGB(96, 31, 36)
itemClose.BorderSizePixel = 0
itemClose.Text = "X"
itemClose.TextColor3 = Color3.new(1, 1, 1)
itemClose.Font = Enum.Font.GothamBold
itemClose.TextSize = 9
itemClose.Parent = itemFrame
Instance.new("UICorner", itemClose).CornerRadius = UDim.new(0, 6)

local itemInfo = Instance.new("TextLabel")
itemInfo.Size = UDim2.new(1, -20, 0, 34)
itemInfo.Position = UDim2.fromOffset(10, 36)
itemInfo.BackgroundTransparency = 1
itemInfo.Text = "Lista apenas Tools client-visible. ADICIONAR LOCAL nao cria item no servidor."
itemInfo.TextWrapped = true
itemInfo.TextColor3 = Color3.fromRGB(175, 175, 188)
itemInfo.Font = Enum.Font.Gotham
itemInfo.TextSize = 8
itemInfo.TextXAlignment = Enum.TextXAlignment.Left
itemInfo.Parent = itemFrame

local itemSearch = Instance.new("TextBox")
itemSearch.Size = UDim2.new(1, -92, 0, 30)
itemSearch.Position = UDim2.fromOffset(10, 74)
itemSearch.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
itemSearch.BorderSizePixel = 0
itemSearch.ClearTextOnFocus = false
itemSearch.PlaceholderText = "Pesquisar item..."
itemSearch.Text = ""
itemSearch.TextColor3 = Color3.fromRGB(240, 240, 245)
itemSearch.Font = Enum.Font.Gotham
itemSearch.TextSize = 9
itemSearch.Parent = itemFrame
Instance.new("UICorner", itemSearch).CornerRadius = UDim.new(0, 6)

local itemRefresh = Instance.new("TextButton")
itemRefresh.Size = UDim2.fromOffset(66, 30)
itemRefresh.Position = UDim2.new(1, -76, 0, 74)
itemRefresh.BackgroundColor3 = Color3.fromRGB(46, 46, 55)
itemRefresh.BorderSizePixel = 0
itemRefresh.Text = "ATUALIZAR"
itemRefresh.TextColor3 = Color3.new(1, 1, 1)
itemRefresh.Font = Enum.Font.GothamBold
itemRefresh.TextSize = 7
itemRefresh.Parent = itemFrame
Instance.new("UICorner", itemRefresh).CornerRadius = UDim.new(0, 6)

local itemList = Instance.new("ScrollingFrame")
itemList.Size = UDim2.new(1, -20, 0, 238)
itemList.Position = UDim2.fromOffset(10, 110)
itemList.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
itemList.BorderSizePixel = 0
itemList.ScrollBarThickness = 3
itemList.CanvasSize = UDim2.fromOffset(0, 0)
itemList.Parent = itemFrame
Instance.new("UICorner", itemList).CornerRadius = UDim.new(0, 7)

local itemLayout = Instance.new("UIListLayout", itemList)
itemLayout.Padding = UDim.new(0, 3)

local itemPad = Instance.new("UIPadding", itemList)
itemPad.PaddingTop = UDim.new(0, 4)
itemPad.PaddingBottom = UDim.new(0, 4)
itemPad.PaddingLeft = UDim.new(0, 4)
itemPad.PaddingRight = UDim.new(0, 4)

local itemSelectedLabel = Instance.new("TextLabel")
itemSelectedLabel.Size = UDim2.new(1, -20, 0, 30)
itemSelectedLabel.Position = UDim2.fromOffset(10, 352)
itemSelectedLabel.BackgroundTransparency = 1
itemSelectedLabel.Text = "Item: nenhum"
itemSelectedLabel.TextWrapped = true
itemSelectedLabel.TextColor3 = Color3.fromRGB(205, 205, 215)
itemSelectedLabel.Font = Enum.Font.Gotham
itemSelectedLabel.TextSize = 8
itemSelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
itemSelectedLabel.Parent = itemFrame

local addItemBtn = Instance.new("TextButton")
addItemBtn.Size = UDim2.new(0.66, -14, 0, 34)
addItemBtn.Position = UDim2.fromOffset(10, 386)
addItemBtn.BackgroundColor3 = Color3.fromRGB(91, 31, 36)
addItemBtn.BorderSizePixel = 0
addItemBtn.Text = "ADICIONAR LOCAL"
addItemBtn.TextColor3 = Color3.new(1, 1, 1)
addItemBtn.Font = Enum.Font.GothamBold
addItemBtn.TextSize = 8
addItemBtn.Parent = itemFrame
Instance.new("UICorner", addItemBtn).CornerRadius = UDim.new(0, 7)

local clearItemsBtn = Instance.new("TextButton")
clearItemsBtn.Size = UDim2.new(0.34, -6, 0, 34)
clearItemsBtn.Position = UDim2.new(0.66, 2, 0, 386)
clearItemsBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
clearItemsBtn.BorderSizePixel = 0
clearItemsBtn.Text = "LIMPAR CLONES"
clearItemsBtn.TextColor3 = Color3.new(1, 1, 1)
clearItemsBtn.Font = Enum.Font.GothamBold
clearItemsBtn.TextSize = 7
clearItemsBtn.Parent = itemFrame
Instance.new("UICorner", clearItemsBtn).CornerRadius = UDim.new(0, 7)

local function clearRows()
    S.rows = {}
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextButton") then
            c:Destroy()
        end
    end
end

local function updatePlayerRow(plr)
    local row = plr and S.rows[plr.UserId]
    if not row then
        return
    end

    row.Text = plr.DisplayName .. " (@" .. plr.Name .. ")"
end

local function rebuildPlayers()
    clearRows()
    local count = 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            count = count + 1

            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, 27)
            row.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
            row.BorderSizePixel = 0
            row.TextColor3 = Color3.fromRGB(235, 235, 240)
            row.Font = Enum.Font.Gotham
            row.TextSize = 8
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local rp = Instance.new("UIPadding", row)
            rp.PaddingLeft = UDim.new(0, 7)

            S.rows[plr.UserId] = row
            updatePlayerRow(plr)

            row.MouseButton1Click:Connect(function()
                S.selected = plr
                selectedLabel.Text = "Alvo: " .. plr.DisplayName .. " (@" .. plr.Name .. ")"
                status("Selecionado: " .. plr.DisplayName)
            end)
        end
    end

    task.wait()
    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)

    if count == 0 then
        status("Nenhum outro jogador online")
    end
end

local function clearItemRows()
    S.itemRows = {}
    for _, c in ipairs(itemList:GetChildren()) do
        if c:IsA("TextButton") then
            c:Destroy()
        end
    end
end

local function rebuildItemRows()
    clearItemRows()

    local q = string.lower(tostring(itemSearch.Text or ""))
    S.itemQuery = q
    local shown = 0

    for _, c in ipairs(S.itemCandidates) do
        local hay = string.lower(c.name .. " " .. c.itemType .. " " .. c.source .. " " .. c.uid)

        if q == "" or hay:find(q, 1, true) then
            shown = shown + 1

            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, 31)
            row.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
            row.BorderSizePixel = 0
            row.TextColor3 = Color3.fromRGB(238, 238, 242)
            row.Font = Enum.Font.Gotham
            row.TextSize = 8
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Text = c.name .. " • " .. c.itemType .. " • " .. c.source
            row.Parent = itemList
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local rp = Instance.new("UIPadding", row)
            rp.PaddingLeft = UDim.new(0, 7)

            table.insert(S.itemRows, row)

            row.MouseButton1Click:Connect(function()
                S.selectedItem = c
                local uid = c.uid ~= "" and (" • UID " .. string.sub(c.uid, 1, 10)) or ""
                itemSelectedLabel.Text = "Item: " .. c.name .. " • " .. c.source .. uid
                status("Item selecionado: " .. c.name)
            end)
        end
    end

    task.wait()
    itemList.CanvasSize = UDim2.fromOffset(0, itemLayout.AbsoluteContentSize.Y + 8)
    itemTitle.Text = "ITENS • " .. tostring(shown) .. "/" .. tostring(#S.itemCandidates)
end

local function refreshItems()
    itemTitle.Text = "ITENS • ESCANEANDO..."
    S.selectedItem = nil
    itemSelectedLabel.Text = "Item: nenhum"

    task.defer(function()
        scanItemCandidates()
        rebuildItemRows()
        status("Itens client-visible atualizados: " .. tostring(#S.itemCandidates))
    end)
end

local function queueItemRefresh()
    if S.itemRefreshQueued then
        return
    end

    S.itemRefreshQueued = true
    task.delay(0.5, function()
        S.itemRefreshQueued = false
        if S.itemPanelOpen then
            refreshItems()
        end
    end)
end

autoBtn.MouseButton1Click:Connect(function()
    S.autoSafe = not S.autoSafe
    status(S.autoSafe and "AUTO SAFE ON • aguardando carry confirmado" or "AUTO SAFE OFF")
end)

godBtn.MouseButton1Click:Connect(function()
    S.god = not S.god
    status(S.god and "GOD LOCAL ON" or "GOD LOCAL OFF")
end)

isoBtn.MouseButton1Click:Connect(function()
    setIsolation(not S.isolate)
end)

safeBtn.MouseButton1Click:Connect(function()
    local ok, err = tpSelf(SAFE_CF)
    status(ok and "SAFE ZONE ✓" or ("Safe falhou: " .. tostring(err)))
end)

itemsBtn.MouseButton1Click:Connect(function()
    S.itemPanelOpen = not S.itemPanelOpen
    itemFrame.Visible = S.itemPanelOpen
    if S.itemPanelOpen then
        refreshItems()
    end
end)

itemClose.MouseButton1Click:Connect(function()
    S.itemPanelOpen = false
    itemFrame.Visible = false
end)

itemRefresh.MouseButton1Click:Connect(refreshItems)
itemSearch:GetPropertyChangedSignal("Text"):Connect(rebuildItemRows)

addItemBtn.MouseButton1Click:Connect(function()
    local ok, info = addSelectedItemLocal()
    status(ok and info or ("Item: " .. tostring(info)))
    if ok then
        queueItemRefresh()
    end
end)

clearItemsBtn.MouseButton1Click:Connect(function()
    local n = removeLocalClones()
    status("Clones locais removidos: " .. tostring(n))
    queueItemRefresh()
end)

tpBtn.MouseButton1Click:Connect(function()
    local ok, err = tpTo(S.selected)
    status(ok and "Voce > alvo ✓" or ("TP falhou: " .. tostring(err)))
end)

pullBtn.MouseButton1Click:Connect(function()
    local ok, err = pullOne(S.selected, CFrame.new(0, 0, -3))
    status(ok and "Alvo > voce LOCAL ✓" or ("Puxar falhou: " .. tostring(err)))
end)

allBtn.MouseButton1Click:Connect(function()
    local n, err = pullAll()
    status(err and ("Puxar todos: " .. err) or ("Todos > voce LOCAL: " .. tostring(n)))
end)

killBtn.MouseButton1Click:Connect(function()
    local ok, err = killLocal(S.selected)
    status(ok and "Kill LOCAL aplicado" or ("Kill falhou: " .. tostring(err)))
end)

moneySetBtn.MouseButton1Click:Connect(function()
    local ok, info = setVisualMoney(amount.Text)
    status(ok and ("Voce: " .. info) or info)
end)

moneyAddBtn.MouseButton1Click:Connect(function()
    local ok, info = addVisualMoney(amount.Text)
    status(ok and ("Voce: " .. info) or info)
end)

moneyClearBtn.MouseButton1Click:Connect(function()
    local _, info = clearVisualMoney()
    status(info)
end)

min.MouseButton1Click:Connect(function()
    mini.Position = frame.Position
    frame.Visible = false
    mini.Visible = true
    itemFrame.Visible = false
end)

mini.MouseButton1Click:Connect(function()
    frame.Position = mini.Position
    mini.Visible = false
    frame.Visible = true
    if S.itemPanelOpen then
        itemFrame.Visible = true
    end
end)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then
        connect(p.CharacterAdded, function(c)
            task.wait(0.1)
            isolateChar(c)
        end)
    end
end

connect(Players.PlayerAdded, function(p)
    connect(p.CharacterAdded, function(c)
        task.wait(0.1)
        isolateChar(c)
    end)
    task.defer(rebuildPlayers)
end)

connect(Players.PlayerRemoving, function(p)
    if S.selected == p then
        S.selected = nil
        selectedLabel.Text = "Alvo: nenhum"
    end
    task.defer(rebuildPlayers)
end)

connect(RS.DescendantAdded, queueItemRefresh)
connect(StarterPack.DescendantAdded, queueItemRefresh)
connect(Workspace.ChildAdded, queueItemRefresh)

local backpack = LP:FindFirstChildOfClass("Backpack")
if backpack then
    connect(backpack.ChildAdded, queueItemRefresh)
    connect(backpack.ChildRemoved, queueItemRefresh)
end

local dragging = false
local dragStart = nil
local startPos = nil

connect(title.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = frame.Position
    end
end)

connect(title.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local itemDragging = false
local itemDragStart = nil
local itemStartPos = nil

connect(itemTitle.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        itemDragging = true
        itemDragStart = i.Position
        itemStartPos = itemFrame.Position
    end
end)

connect(itemTitle.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        itemDragging = false
    end
end)

connect(UIS.InputChanged, function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + d.X,
            startPos.Y.Scale,
            startPos.Y.Offset + d.Y
        )
    end

    if itemDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - itemDragStart
        itemFrame.Position = UDim2.new(
            itemStartPos.X.Scale,
            itemStartPos.X.Offset + d.X,
            itemStartPos.Y.Scale,
            itemStartPos.Y.Offset + d.Y
        )
    end
end)

connect(RunService.RenderStepped, function()
    stat.Text = S.status
    autoBtn.Text = S.autoSafe and "AUTO SAFE: ON" or "AUTO SAFE: OFF"
    godBtn.Text = S.god and "GOD: ON" or "GOD: OFF"
    isoBtn.Text = S.isolate and "ISOLAR: ON" or "ISOLAR: OFF"

    if S.moneyVisual ~= nil then
        syncMoneyHud()
    end
end)

local function cleanup()
    restoreIsolation()
    clearVisualMoney()

    for _, c in ipairs(S.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end

    pcall(function()
        gui:Destroy()
    end)
end

S.Cleanup = cleanup
S.RefreshItems = refreshItems
S.AddSelectedItemLocal = addSelectedItemLocal
S.ClearVisualMoney = clearVisualMoney
ENV.__CAFEINA_EGG_V62 = S

task.defer(rebuildPlayers)

local carryRemote = currentNetwork("Eggs: RequestAreaEggCarry")
if carryRemote and carryRemote:IsA("RemoteFunction") then
    status("V6.2 pronto • RequestAreaEggCarry detectado • AUTO SAFE confirmado por CarrierUserId")
else
    status("V6.2 pronto • AUTO SAFE por CarrierUserId/legacy")
end

print("[CAFEINA EGG] V6.2 carregado ✓")
