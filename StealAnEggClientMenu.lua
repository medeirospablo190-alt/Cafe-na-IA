--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V5
-- Mobile/executor • local-only
-- Auto Safe + God + Isolamento + Players + Dinheiro visual
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

-- Limpeza da versao anterior
pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_V5")
    if type(old) == "table" and type(old.Cleanup) == "function" then old.Cleanup() end
end)
pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_PLAYER_STATE")
    if type(old) == "table" and type(old.Cleanup) == "function" then old.Cleanup() end
end)
pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_PLAYER_MENU_V4")
    if typeof(old) == "Instance" then old:Destroy() end
end)

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
    moneyTags = {},
    rows = {},
}

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or S.conns, c)
    return c
end

local function status(t) S.status = tostring(t or "") end

local function character(plr)
    plr = plr or LP
    local c = plr.Character
    if not c then return nil, nil, nil end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function tp(cf)
    local c, root = character(LP)
    if not c or not root then return false, "personagem indisponivel" end
    local ok, err = pcall(function() c:PivotTo(cf) end)
    if not ok then ok, err = pcall(function() root.CFrame = cf end) end
    return ok, err
end

local function fmt(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    local sign = n < 0 and "-" or ""
    if a >= 1e12 then return sign .. string.format("%.2fT", a / 1e12) end
    if a >= 1e9 then return sign .. string.format("%.2fB", a / 1e9) end
    if a >= 1e6 then return sign .. string.format("%.2fM", a / 1e6) end
    if a >= 1e3 then return sign .. string.format("%.2fK", a / 1e3) end
    return sign .. tostring(math.floor(a + 0.5))
end

local function net(name)
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    return networking and networking:FindFirstChild(name)
end

--============================ OVO / SAFE ============================--
local EGG_ATTR = {EggId=true, EggID=true, FieldEggId=true, FieldEggID=true, EggType=true, EggName=true}

local function looksEgg(obj)
    if not obj then return false end
    local n = string.lower(obj.Name)
    if n:find("egg", 1, true) or n:find("ovo", 1, true) then return true end
    for k in pairs(EGG_ATTR) do
        local ok, v = pcall(function() return obj:GetAttribute(k) end)
        if ok and v ~= nil then return true end
    end
    return false
end

local function goSafe(reason)
    if not S.autoSafe then return end
    local now = os.clock()
    if now - S.lastEggTp < 0.8 then return end
    S.lastEggTp = now
    task.defer(function()
        task.wait(0.02)
        local ok, err = tp(SAFE_CF)
        status(ok and ("OVO > SAFE ✓ • " .. tostring(reason or "carry")) or ("TP Safe falhou: " .. tostring(err)))
    end)
end

local function carryIsActive(...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "table" then
            if v.CarrierUserId and tonumber(v.CarrierUserId) ~= LP.UserId then return false end
            if v.IsCarrying == true then return true end
            if v.IsCarrying == false then return false end
        end
    end
    return false
end

local function hookCarryRemote(obj)
    if not obj:IsA("RemoteEvent") or obj.Name ~= "RE/EggWorld/FieldEggCarry" then return end
    connect(obj.OnClientEvent, function(...)
        if carryIsActive(...) then goSafe("FieldEggCarry") end
    end)
end

for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do hookCarryRemote(obj) end
connect(ReplicatedStorage.DescendantAdded, hookCarryRemote)

local function watchLocalContainer(container, label)
    if not container then return end
    connect(container.ChildAdded, function(obj)
        if looksEgg(obj) then goSafe(label .. ":" .. obj.Name) end
    end)
end

local function bindLocalEggWatch()
    watchLocalContainer(LP.Character, "Character")
    watchLocalContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
end
connect(LP.CharacterAdded, function() task.wait(0.2); bindLocalEggWatch() end)
task.defer(bindLocalEggWatch)

--========================== DINHEIRO VISUAL ==========================--
local function deepMoney(t, depth)
    if type(t) ~= "table" or depth > 3 then return nil end
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
    local id = plr.UserId
    return (S.observedMoney[id] or 0) + (S.visualOffset[id] or 0)
end

local function moneyPopup(amount, plr)
    local asset = ReplicatedStorage:FindFirstChild("Assets")
    asset = asset and asset:FindFirstChild("MoneyChange")
    if not asset or not asset:IsA("GuiObject") then return end

    local host = Instance.new("ScreenGui")
    host.Name = "CafeinaMoneyPopup"
    host.ResetOnSpawn = false
    local parent = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui")
    host.Parent = parent

    local ui = asset:Clone()
    ui.AnchorPoint = Vector2.new(0.5, 0.5)
    ui.Position = UDim2.fromScale(0.5, 0.78)
    ui.Size = UDim2.fromScale(0.72, 0.10)
    ui.Parent = host

    local label = ui:FindFirstChild("Label")
    if label and label:IsA("TextLabel") then
        local prefix = amount >= 0 and "+$" or "-$"
        label.Text = prefix .. fmt(math.abs(amount)) .. (plr and plr ~= LP and ("  @" .. plr.Name) or "")
        local more, less = label:FindFirstChild("More"), label:FindFirstChild("Less")
        pcall(function() if more then more.Enabled = amount >= 0 end end)
        pcall(function() if less then less.Enabled = amount < 0 end end)
    end

    task.delay(1.35, function() pcall(function() host:Destroy() end) end)
end

local function updateMoneyTag(plr)
    if not plr then return end
    local old = S.moneyTags[plr.UserId]
    if old then pcall(function() old:Destroy() end) end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local extra = assets and assets:FindFirstChild("Extra")
    local cash = extra and extra:FindFirstChild("Cash")
    local _, root = character(plr)
    if not cash or not cash:IsA("BillboardGui") or not root then return end

    local tag = cash:Clone()
    tag.Name = "CafeinaLocalCash"
    tag.AlwaysOnTop = true
    tag.StudsOffset = Vector3.new(0, 3.8, 0)
    local label = tag:FindFirstChild("Money")
    if label and label:IsA("TextLabel") then label.Text = "$" .. fmt(effectiveMoney(plr)) end
    tag.Parent = root
    S.moneyTags[plr.UserId] = tag
end

local function updateRow(plr)
    local row = plr and S.rows[plr.UserId]
    if not row then return end
    local suffix = (S.observedMoney[plr.UserId] ~= nil or S.visualOffset[plr.UserId] ~= nil)
        and ("  • V$" .. fmt(effectiveMoney(plr))) or ""
    row.Text = plr.DisplayName .. "  (@" .. plr.Name .. ")" .. suffix
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
        end
    end)
end

local function addVisualMoney(plr, amount)
    if not plr then return false, "selecione um jogador" end
    amount = tonumber(amount)
    if not amount then return false, "valor invalido" end
    amount = math.clamp(amount, -1e12, 1e12)
    S.visualOffset[plr.UserId] = (S.visualOffset[plr.UserId] or 0) + amount
    moneyPopup(amount, plr)
    updateMoneyTag(plr)
    updateRow(plr)
    return true, "$" .. fmt(effectiveMoney(plr)) .. " visual"
end

--========================= GOD / ISOLAMENTO =========================--
local function saveAndBlock(part)
    if not part:IsA("BasePart") then return end
    if not S.savedParts[part] then
        S.savedParts[part] = {part.CanCollide, part.CanTouch, part.CanQuery}
    end
    pcall(function()
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
    end)
end

local function isolateCharacter(char)
    if not S.isolate or not char or char == LP.Character then return end
    for _, d in ipairs(char:GetDescendants()) do saveAndBlock(d) end
    local c = char.DescendantAdded:Connect(function(d)
        if S.isolate then saveAndBlock(d) end
    end)
    table.insert(S.isolateConns, c)
end

local function restoreIsolation()
    for _, c in ipairs(S.isolateConns) do pcall(function() c:Disconnect() end) end
    table.clear(S.isolateConns)
    for part, old in pairs(S.savedParts) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide, part.CanTouch, part.CanQuery = old[1], old[2], old[3]
            end)
        end
    end
    table.clear(S.savedParts)
end

local function setIsolation(on)
    S.isolate = on == true
    restoreIsolation()
    if S.isolate then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then isolateCharacter(plr.Character) end
        end
    end
    status(S.isolate and "ISOLAMENTO LOCAL ON" or "ISOLAMENTO LOCAL OFF")
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LP then
        connect(plr.CharacterAdded, function(char) task.wait(0.1); isolateCharacter(char) end)
    end
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
        local h = Vector3.new(v.X, 0, v.Z)
        if h.Magnitude > 130 then
            pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, math.clamp(v.Y, -80, 80), 0) end)
        end
        if root.AssemblyAngularVelocity.Magnitude > 40 then
            pcall(function() root.AssemblyAngularVelocity = Vector3.zero end)
        end
    end
end)

--=========================== PLAYER ACTIONS ==========================--
local function tpPlayer(plr)
    if not plr or plr == LP then return false, "selecione outro jogador" end
    local _, root = character(plr)
    if not root then return false, "alvo sem root" end
    return tp(root.CFrame * CFrame.new(0, 0, 3))
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
pcall(function()
    local old = rawget(ENV, "__CAFEINA_EGG_V5_GUI")
    if typeof(old) == "Instance" then old:Destroy() end
end)

local parent
pcall(function() if gethui then parent = gethui() end end)
if not parent then pcall(function() parent = CoreGui end) end
if not parent then parent = LP:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaEggV5"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent
ENV.__CAFEINA_EGG_V5_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(308, 438)
frame.Position = UDim2.new(0, 10, 0.5, -219)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 11)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -78, 0, 28)
title.Position = UDim2.fromOffset(9, 5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • EGG V5"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local min = Instance.new("TextButton")
min.Size = UDim2.fromOffset(54, 24)
min.Position = UDim2.new(1, -63, 0, 6)
min.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
min.BorderSizePixel = 0
min.Text = "MIN"
min.TextColor3 = Color3.new(1,1,1)
min.Font = Enum.Font.GothamBold
min.TextSize = 9
min.Parent = frame
Instance.new("UICorner", min).CornerRadius = UDim.new(0, 7)

local stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1, -18, 0, 34)
stat.Position = UDim2.fromOffset(9, 34)
stat.BackgroundTransparency = 1
stat.TextWrapped = true
stat.TextColor3 = Color3.fromRGB(180,180,190)
stat.Font = Enum.Font.Gotham
stat.TextSize = 9
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.Parent = frame

local function button(text, x, y, w, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(w, -12, 0, 30)
    b.Position = UDim2.new(x, 8, 0, y)
    b.BackgroundColor3 = color or Color3.fromRGB(43,43,50)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 8
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    return b
end

local autoBtn = button("AUTO SAFE: ON", 0, 72, 1/3, Color3.fromRGB(100,30,34))
autoBtn.Size = UDim2.new(1/3, -10, 0, 30)
local godBtn = button("GOD: OFF", 1/3, 72, 1/3)
godBtn.Position = UDim2.new(1/3, 4, 0, 72); godBtn.Size = UDim2.new(1/3, -8, 0, 30)
local isoBtn = button("ISOLAR: OFF", 2/3, 72, 1/3)
isoBtn.Position = UDim2.new(2/3, 2, 0, 72); isoBtn.Size = UDim2.new(1/3, -10, 0, 30)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -16, 0, 172)
list.Position = UDim2.fromOffset(8, 108)
list.BackgroundColor3 = Color3.fromRGB(23,23,27)
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.CanvasSize = UDim2.fromOffset(0,0)
list.Parent = frame
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0,4)
local pad = Instance.new("UIPadding", list)
pad.PaddingTop = UDim.new(0,5); pad.PaddingBottom = UDim.new(0,5); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)

local amount = Instance.new("TextBox")
amount.Size = UDim2.new(1, -16, 0, 30)
amount.Position = UDim2.fromOffset(8, 286)
amount.BackgroundColor3 = Color3.fromRGB(28,28,33)
amount.BorderSizePixel = 0
amount.ClearTextOnFocus = false
amount.Text = "1000"
amount.PlaceholderText = "Dinheiro visual local"
amount.TextColor3 = Color3.fromRGB(240,240,245)
amount.Font = Enum.Font.Code
amount.TextSize = 10
amount.Parent = frame
Instance.new("UICorner", amount).CornerRadius = UDim.new(0,7)

local tpBtn = button("TP ALVO", 0, 322, .5)
tpBtn.Size = UDim2.new(.5,-12,0,30)
local killBtn = button("KILL LOCAL", .5, 322, .5, Color3.fromRGB(112,28,32))
killBtn.Position = UDim2.new(.5,4,0,322); killBtn.Size = UDim2.new(.5,-12,0,30)
local moneyTargetBtn = button("$ VISUAL ALVO", 0, 358, .5)
moneyTargetBtn.Size = UDim2.new(.5,-12,0,30)
local moneySelfBtn = button("$ VISUAL EU", .5, 358, .5)
moneySelfBtn.Position = UDim2.new(.5,4,0,358); moneySelfBtn.Size = UDim2.new(.5,-12,0,30)
local safeBtn = button("IR SAFE AGORA", 0, 394, 1, Color3.fromRGB(90,30,34))
safeBtn.Size = UDim2.new(1,-16,0,30)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(88,38)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18,18,22)
mini.BorderSizePixel = 0
mini.Text = "EGG V5"
mini.TextColor3 = Color3.new(1,1,1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 9
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0,9)

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
            row.Size = UDim2.new(1,0,0,32)
            row.BackgroundColor3 = Color3.fromRGB(36,36,42)
            row.BorderSizePixel = 0
            row.TextColor3 = Color3.fromRGB(235,235,240)
            row.Font = Enum.Font.Gotham
            row.TextSize = 9
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0,6)
            local rp = Instance.new("UIPadding", row); rp.PaddingLeft = UDim.new(0,8)
            S.rows[plr.UserId] = row
            updateRow(plr)
            row.MouseButton1Click:Connect(function()
                S.selected = plr
                status("Selecionado: " .. plr.DisplayName .. " (@" .. plr.Name .. ")")
            end)
        end
    end
    task.wait()
    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 10)
    if count == 0 then status("Nenhum outro jogador online") end
end

autoBtn.MouseButton1Click:Connect(function() S.autoSafe = not S.autoSafe; status(S.autoSafe and "AUTO SAFE ON" or "AUTO SAFE OFF") end)
godBtn.MouseButton1Click:Connect(function() S.god = not S.god; status(S.god and "GOD LOCAL ON" or "GOD LOCAL OFF") end)
isoBtn.MouseButton1Click:Connect(function() setIsolation(not S.isolate) end)
tpBtn.MouseButton1Click:Connect(function() local ok,e=tpPlayer(S.selected); status(ok and "TP local concluido" or ("TP falhou: "..tostring(e))) end)
killBtn.MouseButton1Click:Connect(function() local ok,e=killLocal(S.selected); status(ok and "Kill LOCAL aplicado" or ("Kill falhou: "..tostring(e))) end)
moneyTargetBtn.MouseButton1Click:Connect(function() local ok,e=addVisualMoney(S.selected,amount.Text); status(ok and ("Alvo: "..e) or e) end)
moneySelfBtn.MouseButton1Click:Connect(function() local ok,e=addVisualMoney(LP,amount.Text); status(ok and ("Voce: "..e) or e) end)
safeBtn.MouseButton1Click:Connect(function() local ok,e=tp(SAFE_CF); status(ok and "SAFE ZONE ✓" or ("Safe falhou: "..tostring(e))) end)
min.MouseButton1Click:Connect(function() mini.Position=frame.Position; frame.Visible=false; mini.Visible=true end)
mini.MouseButton1Click:Connect(function() frame.Position=mini.Position; mini.Visible=false; frame.Visible=true end)

connect(Players.PlayerAdded, function(plr)
    connect(plr.CharacterAdded, function(char) task.wait(.1); isolateCharacter(char) end)
    task.defer(rebuildPlayers)
end)
connect(Players.PlayerRemoving, function(plr)
    if S.selected == plr then S.selected = nil end
    local tag = S.moneyTags[plr.UserId]; if tag then pcall(function() tag:Destroy() end) end
    task.defer(rebuildPlayers)
end)

local dragging, dragStart, startPos = false
connect(title.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging=true; dragStart=i.Position; startPos=frame.Position
    end
end)
connect(title.InputEnded, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging=false end
end)
connect(UIS.InputChanged, function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

connect(RunService.RenderStepped, function()
    stat.Text = S.status
    autoBtn.Text = S.autoSafe and "AUTO SAFE: ON" or "AUTO SAFE: OFF"
    godBtn.Text = S.god and "GOD: ON" or "GOD: OFF"
    isoBtn.Text = S.isolate and "ISOLAR: ON" or "ISOLAR: OFF"
end)

local function cleanup()
    restoreIsolation()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    for _, tag in pairs(S.moneyTags) do pcall(function() tag:Destroy() end) end
    pcall(function() gui:Destroy() end)
end
S.Cleanup = cleanup
ENV.__CAFEINA_EGG_V5 = S

task.defer(rebuildPlayers)
status("AUTO SAFE ON • cliente local")
print("[CAFEINA EGG] V5 carregado ✓")