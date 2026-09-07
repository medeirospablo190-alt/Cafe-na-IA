--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V6
-- Mobile/executor • CLIENT-SIDE ONLY
-- Compacto: Auto Safe + Safe manual + God/Isolar + Players
--           TP alvo / puxar alvo / puxar todos / kill / dinheiro visual
--==============================================================--

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

-- Limpa V5/V6 anterior sem empilhar listeners.
for _, key in ipairs({"__CAFEINA_EGG_V6", "__CAFEINA_EGG_V5"}) do
    pcall(function()
        local old = rawget(ENV, key)
        if type(old) == "table" and type(old.Cleanup) == "function" then old.Cleanup() end
    end)
end
for _, key in ipairs({"__CAFEINA_EGG_V6_GUI", "__CAFEINA_EGG_V5_GUI", "__CAFEINA_EGG_PLAYER_MENU_V4"}) do
    pcall(function()
        local old = rawget(ENV, key)
        if typeof(old) == "Instance" then old:Destroy() end
    end)
end

local S = {
    autoSafe = true,
    god = false,
    isolate = false,
    selected = nil,
    lastEggTp = 0,
    status = "Pronto",
    conns = {},
    isolateConns = {},
    savedParts = setmetatable({}, {__mode = "k"}),
    observedMoney = {},
    visualOffset = {},
    savedMoneyText = setmetatable({}, {__mode = "k"}),
    rows = {},
    hookedEggRemotes = setmetatable({}, {__mode = "k"}),
}

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or S.conns, c)
    return c
end

local function setStatus(text)
    S.status = tostring(text or "")
end

local function character(plr)
    plr = plr or LP
    local c = plr.Character
    if not c then return nil, nil, nil end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function tpSelf(cf)
    local c, root = character(LP)
    if not c or not root then return false, "personagem indisponivel" end
    local ok, err = pcall(function() c:PivotTo(cf) end)
    if not ok then ok, err = pcall(function() root.CFrame = cf end) end
    return ok, err
end

local function fmt(n)
    n = tonumber(n) or 0
    local a, sign = math.abs(n), n < 0 and "-" or ""
    if a >= 1e12 then return sign .. string.format("%.2fT", a / 1e12) end
    if a >= 1e9 then return sign .. string.format("%.2fB", a / 1e9) end
    if a >= 1e6 then return sign .. string.format("%.2fM", a / 1e6) end
    if a >= 1e3 then return sign .. string.format("%.2fK", a / 1e3) end
    return sign .. tostring(math.floor(a + 0.5))
end

local function net(name)
    local packages = RS:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    return networking and networking:FindFirstChild(name)
end

--============================ OVO / SAFE ============================--
local function goSafeAuto(reason)
    if not S.autoSafe then return end
    local now = os.clock()
    if now - S.lastEggTp < 0.75 then return end
    S.lastEggTp = now
    task.defer(function()
        task.wait(0.03)
        local ok, err = tpSelf(SAFE_CF)
        setStatus(ok and ("OVO > SAFE ✓ • " .. tostring(reason or "carry")) or ("AUTO SAFE falhou: " .. tostring(err)))
    end)
end

local function localCarryInTable(t, depth, targetedCarryEvent)
    if type(t) ~= "table" or (depth or 0) > 4 then return false end
    depth = depth or 0

    local carrier = tonumber(t.CarrierUserId or t.CarrierId or t.UserId)
    local state = tostring(t.State or t.state or "")
    if carrier == LP.UserId and (state == "Carried" or t.IsCarrying == true) then return true end

    -- FieldEggCarry costuma chegar ao proprio carrier sem CarrierUserId no payload.
    if targetedCarryEvent and t.IsCarrying == true and (carrier == nil or carrier == LP.UserId) then return true end

    for _, v in pairs(t) do
        if type(v) == "table" and localCarryInTable(v, depth + 1, targetedCarryEvent) then return true end
    end
    return false
end

local function hookEggRemote(obj)
    if S.hookedEggRemotes[obj] or not obj:IsA("RemoteEvent") then return end
    local name = obj.Name
    if name ~= "RE/EggWorld/FieldEggCarry" and name ~= "RE/EggWorld/FieldEggShifted" then return end
    S.hookedEggRemotes[obj] = true

    connect(obj.OnClientEvent, function(...)
        if not S.autoSafe then return end
        local targeted = name == "RE/EggWorld/FieldEggCarry"
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "table" and localCarryInTable(v, 0, targeted) then
                goSafeAuto(name == "RE/EggWorld/FieldEggCarry" and "FieldEggCarry" or "FieldEggShifted")
                return
            end
        end
    end)
end

for _, obj in ipairs(RS:GetDescendants()) do hookEggRemote(obj) end
connect(RS.DescendantAdded, hookEggRemote)

-- Fallback: o prompt observado do jogo e CarryAreaEgg / Steal / Egg.
-- PromptTriggered ocorre ao completar a interacao; um pequeno atraso deixa a
-- atualizacao de carry chegar primeiro quando ela estiver disponivel.
connect(PPS.PromptTriggered, function(prompt, player)
    if not S.autoSafe or (player and player ~= LP) then return end
    local action = string.lower(tostring(prompt.ActionText or ""))
    local object = string.lower(tostring(prompt.ObjectText or ""))
    local n = string.lower(prompt.Name)
    local eggPrompt = n:find("carryareaegg", 1, true)
        or ((action:find("steal", 1, true) or action:find("carry", 1, true) or action:find("take", 1, true))
            and (object:find("egg", 1, true) or object:find("ovo", 1, true)))
    if eggPrompt then
        task.delay(0.18, function() goSafeAuto("CarryAreaEgg") end)
    end
end)

--========================== DINHEIRO VISUAL ==========================--
local function deepMoney(t, depth)
    if type(t) ~= "table" or (depth or 0) > 4 then return nil end
    depth = depth or 0
    if type(t.Money) == "number" then return t.Money end
    for _, v in pairs(t) do
        if type(v) == "table" then
            local m = deepMoney(v, depth + 1)
            if m ~= nil then return m end
        end
    end
end

local function effectiveMoney(plr)
    if not plr then return 0 end
    return (S.observedMoney[plr.UserId] or 0) + (S.visualOffset[plr.UserId] or 0)
end

local MONEY_TERMS = {"money", "cash", "currency", "balance", "wallet", "coin", "coins"}
local MONEY_EXCLUDE = {"shop", "store", "price", "cost", "purchase", "product", "upgrade", "button"}

local function containsAny(text, terms)
    text = string.lower(tostring(text or ""))
    for _, w in ipairs(terms) do if text:find(w, 1, true) then return true end end
    return false
end

local function moneyLabelScore(label)
    if not label:IsA("TextLabel") then return -999 end
    if label:IsDescendantOf(rawget(ENV, "__CAFEINA_EGG_V6_GUI") or label) and rawget(ENV, "__CAFEINA_EGG_V6_GUI") then return -999 end
    local path = ""
    pcall(function() path = label:GetFullName() end)
    local lowPath, lowName = string.lower(path), string.lower(label.Name)
    if containsAny(lowPath, MONEY_EXCLUDE) then return -999 end
    local score = 0
    if containsAny(lowName, MONEY_TERMS) then score += 6 end
    if containsAny(lowPath, MONEY_TERMS) then score += 4 end
    local text = tostring(label.Text or "")
    if text:find("%$") then score += 4 end
    if text:match("^[%s%$]*[%d%.,]+[KMBTkmbt]?[%s]*$") then score += 2 end
    if label.Visible then score += 1 end
    return score
end

local function moneyLabels()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return {} end
    local candidates = {}
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local score = moneyLabelScore(d)
            if score >= 5 then candidates[#candidates + 1] = {obj=d, score=score} end
        end
    end
    table.sort(candidates, function(a,b) return a.score > b.score end)
    return candidates
end

local function moneyTextFor(label, value)
    local old = tostring(label.Text or "")
    local low = string.lower(old)
    if old:find("%$") then return "$" .. fmt(value) end
    if low:find("money",1,true) then return "Money: " .. fmt(value) end
    if low:find("cash",1,true) then return "Cash: " .. fmt(value) end
    return fmt(value)
end

local function syncSelfMoneyHud()
    local list = moneyLabels()
    local value = effectiveMoney(LP)
    local changed = 0
    for i = 1, math.min(#list, 2) do
        local label = list[i].obj
        if S.savedMoneyText[label] == nil then S.savedMoneyText[label] = label.Text end
        pcall(function() label.Text = moneyTextFor(label, value) end)
        changed += 1
    end
    return changed
end

local function updateRow(plr)
    local row = plr and S.rows[plr.UserId]
    if not row then return end
    local suffix = ""
    if S.observedMoney[plr.UserId] ~= nil or S.visualOffset[plr.UserId] ~= nil then
        suffix = "  • V$" .. fmt(effectiveMoney(plr))
    end
    row.Text = plr.DisplayName .. " (@" .. plr.Name .. ")" .. suffix
end

local profileDelta = net("RE/ProfileMirror/ProfileDelta")
if profileDelta and profileDelta:IsA("RemoteEvent") then
    connect(profileDelta.OnClientEvent, function(...)
        local target, money
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if typeof(v) == "Instance" and v:IsA("Player") then target = v end
            if money == nil and type(v) == "table" then money = deepMoney(v, 0) end
        end
        if money ~= nil then
            target = target or LP
            S.observedMoney[target.UserId] = money
            updateRow(target)
            if target == LP and S.visualOffset[LP.UserId] ~= nil then syncSelfMoneyHud() end
        end
    end)
end

local function addVisualMoney(plr, amount)
    if not plr then return false, "selecione um jogador" end
    amount = tonumber(tostring(amount):gsub(",", "."))
    if not amount then return false, "quantidade invalida" end
    amount = math.clamp(amount, -1e12, 1e12)
    S.visualOffset[plr.UserId] = (S.visualOffset[plr.UserId] or 0) + amount
    updateRow(plr)
    if plr == LP then
        local changed = syncSelfMoneyHud()
        if changed > 0 then return true, "$" .. fmt(effectiveMoney(plr)) .. " na HUD local" end
        return true, "$" .. fmt(effectiveMoney(plr)) .. " local • HUD de dinheiro nao encontrada"
    end
    return true, "$" .. fmt(effectiveMoney(plr)) .. " visual no menu"
end

local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
if pg then
    connect(pg.DescendantAdded, function(d)
        if S.visualOffset[LP.UserId] ~= nil and d:IsA("TextLabel") then
            task.delay(0.1, syncSelfMoneyHud)
        end
    end)
end

--========================= GOD / ISOLAMENTO =========================--
local function saveAndBlock(part)
    if not part:IsA("BasePart") then return end
    if not S.savedParts[part] then S.savedParts[part] = {part.CanCollide, part.CanTouch, part.CanQuery} end
    pcall(function()
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
    end)
end

local function isolateCharacter(char)
    if not S.isolate or not char or char == LP.Character then return end
    for _, d in ipairs(char:GetDescendants()) do saveAndBlock(d) end
    local c = char.DescendantAdded:Connect(function(d) if S.isolate then saveAndBlock(d) end end)
    table.insert(S.isolateConns, c)
end

local function restoreIsolation()
    for _, c in ipairs(S.isolateConns) do pcall(function() c:Disconnect() end) end
    table.clear(S.isolateConns)
    for part, old in pairs(S.savedParts) do
        if part and part.Parent then
            pcall(function() part.CanCollide, part.CanTouch, part.CanQuery = old[1], old[2], old[3] end)
        end
    end
    table.clear(S.savedParts)
end

local function setIsolation(on)
    S.isolate = on == true
    restoreIsolation()
    if S.isolate then
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LP then isolateCharacter(plr.Character) end end
    end
    setStatus(S.isolate and "ISOLAR LOCAL: ON" or "ISOLAR LOCAL: OFF")
end

connect(RunService.Heartbeat, function()
    local _, root, hum = character(LP)
    if hum and (S.god or S.isolate) then
        pcall(function()
            hum.BreakJointsOnDeath = false
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
        end)
    end
    if S.isolate and root then
        local v = root.AssemblyLinearVelocity
        if Vector3.new(v.X,0,v.Z).Magnitude > 130 then
            pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, math.clamp(v.Y,-80,80), 0) end)
        end
        if root.AssemblyAngularVelocity.Magnitude > 40 then
            pcall(function() root.AssemblyAngularVelocity = Vector3.zero end)
        end
    end
end)

--=========================== PLAYER ACTIONS ==========================--
local function tpToPlayer(plr)
    if not plr or plr == LP then return false, "selecione outro jogador" end
    local _, root = character(plr)
    if not root then return false, "alvo sem root" end
    return tpSelf(root.CFrame * CFrame.new(0,0,3))
end

local function pullPlayerLocal(plr, offset)
    if not plr or plr == LP then return false, "selecione outro jogador" end
    local c, root = character(plr)
    local _, myRoot = character(LP)
    if not c or not root or not myRoot then return false, "personagem indisponivel" end
    local cf = myRoot.CFrame * (offset or CFrame.new(0,0,-3))
    local ok, err = pcall(function() c:PivotTo(cf) end)
    if not ok then ok, err = pcall(function() root.CFrame = cf end) end
    return ok, err
end

local function pullAllLocal()
    local _, myRoot = character(LP)
    if not myRoot then return 0, "seu root indisponivel" end
    local targets = {}
    for _, plr in ipairs(Players:GetPlayers()) do if plr ~= LP then targets[#targets+1] = plr end end
    local moved = 0
    for i, plr in ipairs(targets) do
        local angle = ((i-1) / math.max(1,#targets)) * math.pi * 2
        local radius = 4
        local offset = CFrame.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)
        local ok = pullPlayerLocal(plr, offset)
        if ok then moved += 1 end
    end
    return moved, nil
end

local function killLocal(plr)
    if not plr or plr == LP then return false, "selecione outro jogador" end
    local _, _, hum = character(plr)
    if not hum then return false, "alvo sem Humanoid" end
    return pcall(function()
        hum.Health = 0
        hum:ChangeState(Enum.HumanoidStateType.Dead)
    end)
end

--================================ GUI ================================--
local parent
pcall(function() if gethui then parent = gethui() end end)
if not parent then pcall(function() parent = CoreGui end) end
if not parent then parent = LP:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggV6"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local parentOK = pcall(function() gui.Parent = parent end)
if not parentOK then gui.Parent = LP:WaitForChild("PlayerGui") end
ENV.__CAFEINA_EGG_V6_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300, 368)
frame.Position = UDim2.new(0, 10, 0.5, -184)
frame.BackgroundColor3 = Color3.fromRGB(15,15,18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-62,0,25)
title.Position = UDim2.fromOffset(8,5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • EGG V6"
title.TextColor3 = Color3.fromRGB(245,245,248)
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local min = Instance.new("TextButton")
min.Size = UDim2.fromOffset(48,22)
min.Position = UDim2.new(1,-56,0,6)
min.BackgroundColor3 = Color3.fromRGB(42,42,48)
min.BorderSizePixel = 0
min.Text = "MIN"
min.TextColor3 = Color3.new(1,1,1)
min.Font = Enum.Font.GothamBold
min.TextSize = 8
min.Parent = frame
Instance.new("UICorner", min).CornerRadius = UDim.new(0,6)

local stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1,-16,0,24)
stat.Position = UDim2.fromOffset(8,32)
stat.BackgroundTransparency = 1
stat.TextWrapped = true
stat.TextColor3 = Color3.fromRGB(180,180,190)
stat.Font = Enum.Font.Gotham
stat.TextSize = 8
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Parent = frame

local function button(text, xScale, xOffset, y, wScale, wOffset, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(wScale,wOffset,0,28)
    b.Position = UDim2.new(xScale,xOffset,0,y)
    b.BackgroundColor3 = color or Color3.fromRGB(43,43,50)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 8
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    return b
end

local autoBtn = button("AUTO SAFE: ON",0,8,60,1/3,-9,Color3.fromRGB(100,30,34))
local godBtn = button("GOD: OFF",1/3,3,60,1/3,-6)
local isoBtn = button("ISOLAR: OFF",2/3,1,60,1/3,-9)
local safeBtn = button("IR SAFE AGORA",0,8,92,1,-16,Color3.fromRGB(90,30,34))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1,-16,0,112)
list.Position = UDim2.fromOffset(8,124)
list.BackgroundColor3 = Color3.fromRGB(23,23,27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.fromOffset(0,0)
list.Parent = frame
Instance.new("UICorner", list).CornerRadius = UDim.new(0,7)
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0,3)
local pad = Instance.new("UIPadding", list)
pad.PaddingTop=UDim.new(0,4); pad.PaddingBottom=UDim.new(0,4); pad.PaddingLeft=UDim.new(0,4); pad.PaddingRight=UDim.new(0,4)

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1,-16,0,22)
selectedLabel.Position = UDim2.fromOffset(8,240)
selectedLabel.BackgroundTransparency = 1
selectedLabel.Text = "Alvo: nenhum"
selectedLabel.TextColor3 = Color3.fromRGB(205,205,215)
selectedLabel.Font = Enum.Font.Gotham
selectedLabel.TextSize = 8
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Parent = frame

local amount = Instance.new("TextBox")
amount.Size = UDim2.new(1,-16,0,28)
amount.Position = UDim2.fromOffset(8,266)
amount.BackgroundColor3 = Color3.fromRGB(28,28,33)
amount.BorderSizePixel = 0
amount.ClearTextOnFocus = false
amount.Text = "1000"
amount.PlaceholderText = "Quantidade de dinheiro visual"
amount.TextColor3 = Color3.fromRGB(240,240,245)
amount.Font = Enum.Font.Code
amount.TextSize = 9
amount.Parent = frame
Instance.new("UICorner", amount).CornerRadius = UDim.new(0,6)

local tpBtn = button("TP > ALVO",0,8,298,1/3,-9)
local pullBtn = button("ALVO > MIM",1/3,3,298,1/3,-6)
local allBtn = button("TODOS > MIM",2/3,1,298,1/3,-9)
local killBtn = button("KILL LOCAL",0,8,330,1/3,-9,Color3.fromRGB(112,28,32))
local moneyTargetBtn = button("$ ALVO",1/3,3,330,1/3,-6)
local moneySelfBtn = button("$ EU",2/3,1,330,1/3,-9)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(82,36)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18,18,22)
mini.BorderSizePixel = 0
mini.Text = "EGG V6"
mini.TextColor3 = Color3.new(1,1,1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 8
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0,8)

local function clearRows()
    S.rows = {}
    for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
end

local function rebuildPlayers()
    clearRows()
    local count = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            count += 1
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1,0,0,27)
            row.BackgroundColor3 = Color3.fromRGB(36,36,42)
            row.BorderSizePixel = 0
            row.TextColor3 = Color3.fromRGB(235,235,240)
            row.Font = Enum.Font.Gotham
            row.TextSize = 8
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0,5)
            local rp = Instance.new("UIPadding", row); rp.PaddingLeft = UDim.new(0,7)
            S.rows[plr.UserId] = row
            updateRow(plr)
            row.MouseButton1Click:Connect(function()
                S.selected = plr
                selectedLabel.Text = "Alvo: " .. plr.DisplayName .. " (@" .. plr.Name .. ")"
                setStatus("Selecionado: " .. plr.DisplayName)
            end)
        end
    end
    task.wait()
    list.CanvasSize = UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+8)
    if count == 0 then setStatus("Nenhum outro jogador online") end
end

autoBtn.MouseButton1Click:Connect(function()
    S.autoSafe = not S.autoSafe
    setStatus(S.autoSafe and "AUTO SAFE ON" or "AUTO SAFE OFF")
end)
godBtn.MouseButton1Click:Connect(function()
    S.god = not S.god
    setStatus(S.god and "GOD LOCAL ON" or "GOD LOCAL OFF")
end)
isoBtn.MouseButton1Click:Connect(function() setIsolation(not S.isolate) end)
safeBtn.MouseButton1Click:Connect(function()
    local ok,e=tpSelf(SAFE_CF); setStatus(ok and "SAFE ZONE ✓" or ("Safe falhou: "..tostring(e)))
end)
tpBtn.MouseButton1Click:Connect(function()
    local ok,e=tpToPlayer(S.selected); setStatus(ok and "Voce > alvo ✓" or ("TP falhou: "..tostring(e)))
end)
pullBtn.MouseButton1Click:Connect(function()
    local ok,e=pullPlayerLocal(S.selected,CFrame.new(0,0,-3)); setStatus(ok and "Alvo > voce LOCAL ✓" or ("Puxar falhou: "..tostring(e)))
end)
allBtn.MouseButton1Click:Connect(function()
    local n,e=pullAllLocal(); setStatus(e and ("Puxar todos: "..e) or ("Todos > voce LOCAL: "..n))
end)
killBtn.MouseButton1Click:Connect(function()
    local ok,e=killLocal(S.selected); setStatus(ok and "Kill LOCAL aplicado" or ("Kill falhou: "..tostring(e)))
end)
moneyTargetBtn.MouseButton1Click:Connect(function()
    local ok,e=addVisualMoney(S.selected,amount.Text); setStatus(ok and ("Alvo: "..e) or e)
end)
moneySelfBtn.MouseButton1Click:Connect(function()
    local ok,e=addVisualMoney(LP,amount.Text); setStatus(ok and ("Voce: "..e) or e)
end)
min.MouseButton1Click:Connect(function() mini.Position=frame.Position; frame.Visible=false; mini.Visible=true end)
mini.MouseButton1Click:Connect(function() frame.Position=mini.Position; mini.Visible=false; frame.Visible=true end)

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LP then connect(plr.CharacterAdded,function(char) task.wait(.1); isolateCharacter(char) end) end
end
connect(Players.PlayerAdded,function(plr)
    connect(plr.CharacterAdded,function(char) task.wait(.1); isolateCharacter(char) end)
    task.defer(rebuildPlayers)
end)
connect(Players.PlayerRemoving,function(plr)
    if S.selected == plr then S.selected=nil; selectedLabel.Text="Alvo: nenhum" end
    task.defer(rebuildPlayers)
end)

local dragging, dragStart, startPos = false, nil, nil
connect(title.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=i.Position; startPos=frame.Position
    end
end)
connect(title.InputEnded,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
connect(UIS.InputChanged,function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

connect(RunService.RenderStepped,function()
    stat.Text=S.status
    autoBtn.Text=S.autoSafe and "AUTO SAFE: ON" or "AUTO SAFE: OFF"
    godBtn.Text=S.god and "GOD: ON" or "GOD: OFF"
    isoBtn.Text=S.isolate and "ISOLAR: ON" or "ISOLAR: OFF"
end)

local function cleanup()
    restoreIsolation()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    for label, old in pairs(S.savedMoneyText) do
        if label and label.Parent then pcall(function() label.Text=old end) end
    end
    pcall(function() gui:Destroy() end)
end

S.Cleanup = cleanup
ENV.__CAFEINA_EGG_V6 = S

task.defer(rebuildPlayers)
setStatus("AUTO SAFE ON • aguardando carry")
print("[CAFEINA EGG] V6 carregado ✓")
