--==============================================================--
-- CAFEINA • AUTO EGG DELIVERY • V1.1
-- Mobile/executor
-- Regra fixa: melhor ovo -> coleta -> carry confirmado -> Safe
-- -> entrega confirmada -> somente entao proximo ovo
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

local RARITIES = {
    {name = "Divine",    key = "divine",    rank = 10},
    {name = "Eternal",   key = "eternal",   rank = 9},
    {name = "Secret",    key = "secret",    rank = 8},
    {name = "Cosmic",    key = "cosmic",    rank = 7},
    {name = "Mythic",    key = "mythic",    rank = 6},
    {name = "Legendary", key = "legendary", rank = 5},
    {name = "Epic",      key = "epic",      rank = 4},
    {name = "Rare",      key = "rare",      rank = 3},
    {name = "Uncommon",  key = "uncommon",  rank = 2},
    {name = "Common",    key = "common",    rank = 1},
}

pcall(function()
    local old = rawget(ENV, "__CAFEINA_AUTO_EGG_DELIVERY")
    if type(old) == "table" and type(old.Cleanup) == "function" then
        old.Cleanup()
    end
end)

pcall(function()
    local oldGui = rawget(ENV, "__CAFEINA_AUTO_EGG_DELIVERY_GUI")
    if typeof(oldGui) == "Instance" then
        oldGui:Destroy()
    end
end)

local S = {
    running = false,
    token = 0,
    state = "PARADO",
    status = "Pronto • prioridade por raridade",
    delivered = 0,
    failed = 0,
    current = nil,
    currentRarity = nil,
    blacklist = setmetatable({}, {__mode = "k"}),
    rarityCache = setmetatable({}, {__mode = "k"}),
    conns = {},
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(S.conns, c)
    return c
end

local function character()
    local c = LP.Character
    if not c then return nil, nil end
    return c, c:FindFirstChild("HumanoidRootPart")
end

local function tp(cf)
    local c, root = character()
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

local function pivotOf(inst)
    if not inst or not inst.Parent then return nil end

    if inst:IsA("Model") then
        local ok, cf = pcall(function()
            return inst:GetPivot()
        end)
        if ok then return cf end
    elseif inst:IsA("BasePart") then
        return inst.CFrame
    end

    return nil
end

local function rarityFromString(value)
    local text = string.lower(tostring(value or ""))
    if text == "" then return nil, nil end

    for _, rarity in ipairs(RARITIES) do
        if text:find(rarity.key, 1, true) then
            return rarity.rank, rarity.name
        end
    end

    return nil, nil
end

local function considerRarity(bestRank, bestName, value)
    local rank, name = rarityFromString(value)
    if rank and rank > bestRank then
        return rank, name
    end
    return bestRank, bestName
end

local function inspectInstanceRarity(inst, bestRank, bestName)
    bestRank, bestName = considerRarity(bestRank, bestName, inst.Name)

    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if ok and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            bestRank, bestName = considerRarity(bestRank, bestName, key)
            bestRank, bestName = considerRarity(bestRank, bestName, value)
        end
    end

    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        bestRank, bestName = considerRarity(bestRank, bestName, inst.Text)
    end

    if inst:IsA("ProximityPrompt") then
        bestRank, bestName = considerRarity(bestRank, bestName, inst.ActionText)
        bestRank, bestName = considerRarity(bestRank, bestName, inst.ObjectText)
    end

    return bestRank, bestName
end

local function rarityOfEgg(egg)
    local cached = S.rarityCache[egg]
    if cached and os.clock() - cached.at < 1.0 then
        return cached.rank, cached.name
    end

    local bestRank, bestName = 0, "Unknown"
    bestRank, bestName = inspectInstanceRarity(egg, bestRank, bestName)

    local descendants = egg:GetDescendants()
    for i, d in ipairs(descendants) do
        bestRank, bestName = inspectInstanceRarity(d, bestRank, bestName)
        if bestRank >= 10 then break end
        if i % 120 == 0 then task.wait() end
    end

    S.rarityCache[egg] = {
        rank = bestRank,
        name = bestName,
        at = os.clock(),
    }

    return bestRank, bestName
end

local function isEggCandidate(inst)
    if not inst or not inst.Parent or not inst:IsA("Model") then return false end

    local slots = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not slots or not inst:IsDescendantOf(slots) then return false end

    local n = inst.Name
    if n:sub(1, 15) == "CarriedAreaEgg_" then return false end
    if n:sub(1, 8) == "AreaEgg_" then return true end
    if n:sub(1, 13) == "FirstAreaEgg_" then return true end
    if inst:GetAttribute("AreaEggUid") ~= nil then return true end

    return false
end

local function getEggCandidates()
    local slots = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not slots then return {} end

    local now = os.clock()
    local out = {}
    local _, root = character()
    local origin = root and root.Position or SAFE_CF.Position

    for _, d in ipairs(slots:GetDescendants()) do
        if isEggCandidate(d) then
            local blockedUntil = S.blacklist[d]
            if not blockedUntil or blockedUntil <= now then
                local cf = pivotOf(d)
                if cf then
                    local rank, rarity = rarityOfEgg(d)
                    table.insert(out, {
                        obj = d,
                        cf = cf,
                        dist = (cf.Position - origin).Magnitude,
                        rank = rank,
                        rarity = rarity,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        if math.abs(a.dist - b.dist) > 0.01 then
            return a.dist < b.dist
        end
        return a.obj.Name < b.obj.Name
    end)

    return out
end

local function carriedModels()
    local out = {}

    for _, d in ipairs(Workspace:GetChildren()) do
        if d:IsA("Model") then
            local carrier = tonumber(d:GetAttribute("CarrierUserId"))
            if carrier == LP.UserId then
                local uid = tostring(d:GetAttribute("AreaEggUid") or "")
                if d.Name:find("CarriedAreaEgg_", 1, true) or uid ~= "" then
                    table.insert(out, d)
                end
            end
        end
    end

    local c = LP.Character
    if c then
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("Model") then
                local carrier = tonumber(d:GetAttribute("CarrierUserId"))
                if carrier == LP.UserId then
                    local uid = tostring(d:GetAttribute("AreaEggUid") or "")
                    if d.Name:find("CarriedAreaEgg_", 1, true) or uid ~= "" then
                        table.insert(out, d)
                    end
                end
            end
        end
    end

    return out
end

local function findLocalCarry(uid, allowFallback)
    local all = carriedModels()
    local wanted = tostring(uid or "")

    if wanted ~= "" then
        for _, d in ipairs(all) do
            local areaUid = tostring(d:GetAttribute("AreaEggUid") or "")
            if areaUid == wanted or d.Name:find(wanted, 1, true) then
                return d
            end
        end
    end

    if allowFallback and #all > 0 then
        return all[1]
    end

    return nil
end

local function targetUid(target)
    if not target then return nil end
    return tostring(
        target:GetAttribute("AreaEggUid")
        or target:GetAttribute("Uid")
        or target:GetAttribute("UID")
        or target.Name
    )
end

local function findCarryPromptNear(pos)
    local smart = Workspace:FindFirstChild("SmartPromptPart")
    if smart then
        local prompt = smart:FindFirstChild("CarryAreaEgg", true)
        if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local holder = prompt.Parent
            if holder and holder:IsA("BasePart") then
                if (holder.Position - pos).Magnitude <= 28 then
                    return prompt
                end
            else
                return prompt
            end
        end
    end

    return nil
end

local function waitCarryPrompt(pos, token, timeout)
    local deadline = os.clock() + (timeout or 2.2)

    while S.running and S.token == token and os.clock() < deadline do
        local prompt = findCarryPromptNear(pos)
        if prompt then return prompt end
        task.wait(0.04)
    end

    return nil
end

local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then
        return false, "prompt sumiu"
    end

    if fireproximityprompt then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if ok then return true end
    end

    local ok, err = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.05, tonumber(prompt.HoldDuration) or 0) + 0.05)
        prompt:InputHoldEnd()
    end)

    return ok, err
end

local function waitCarryConfirmed(uid, token, timeout)
    local deadline = os.clock() + (timeout or 4.5)

    while S.running and S.token == token and os.clock() < deadline do
        local carried = findLocalCarry(uid, true)
        if carried then
            return carried
        end
        task.wait(0.04)
    end

    return nil
end

local function carryStillAlive(carried, uid)
    if carried and carried.Parent then
        local carrier = tonumber(carried:GetAttribute("CarrierUserId"))
        if carrier == LP.UserId then
            return true
        end
    end

    return findLocalCarry(uid, false) ~= nil
end

local function waitDeliveryConfirmed(carried, uid, token)
    local absentSince = nil
    local lastSafeTp = 0

    while S.running and S.token == token do
        if carryStillAlive(carried, uid) then
            absentSince = nil
        else
            absentSince = absentSince or os.clock()
            if os.clock() - absentSince >= 0.45 then
                return true
            end
        end

        if os.clock() - lastSafeTp >= 0.7 then
            lastSafeTp = os.clock()
            tp(SAFE_CF)
        end

        task.wait(0.05)
    end

    return false
end

local function deliverExistingCarry(token)
    local carried = findLocalCarry(nil, true)
    if not carried then return false end

    local uid = tostring(carried:GetAttribute("AreaEggUid") or carried.Name)
    S.current = uid
    S.currentRarity = "carregado"
    S.state = "INDO_SAFE"
    S.status = "Ovo ja carregado • indo Safe"
    tp(SAFE_CF)

    S.state = "CONFIRMANDO_ENTREGA"
    S.status = "Safe • aguardando entrega confirmada"

    local delivered = waitDeliveryConfirmed(carried, uid, token)
    if delivered then
        S.delivered = S.delivered + 1
        S.current = nil
        S.currentRarity = nil
        S.status = "Entrega confirmada • liberando proximo ovo"
        task.wait(0.12)
    end

    return true
end

local function run(token)
    while S.running and S.token == token do
        if not deliverExistingCarry(token) then
            S.state = "BUSCANDO_OVO"
            local eggs = getEggCandidates()

            if #eggs == 0 then
                S.current = nil
                S.currentRarity = nil
                S.status = "Nenhum ovo coletavel visivel • aguardando"
                task.wait(0.3)
            else
                local entry = eggs[1]
                local egg = entry.obj
                local uid = targetUid(egg)

                S.current = uid
                S.currentRarity = entry.rarity
                S.state = "INDO_OVO"
                S.status = "Melhor disponivel: " .. entry.rarity .. " • " .. egg.Name

                local approach = entry.cf * CFrame.new(0, 3.2, 2.5)
                local moved = tp(approach)

                if not moved then
                    S.failed = S.failed + 1
                    S.blacklist[egg] = os.clock() + 1.5
                    S.status = "Falha no TP do ovo " .. entry.rarity
                    task.wait(0.15)
                else
                    task.wait(0.08)
                    S.state = "COLETANDO"
                    S.status = "Coletando " .. entry.rarity .. " • aguardando prompt"

                    local prompt = waitCarryPrompt(entry.cf.Position, token, 2.2)
                    if not prompt then
                        S.failed = S.failed + 1
                        S.blacklist[egg] = os.clock() + 2.0
                        S.status = "Sem prompt • " .. entry.rarity .. " temporariamente ignorado"
                        task.wait(0.12)
                    else
                        local fired = triggerPrompt(prompt)
                        if not fired then
                            S.failed = S.failed + 1
                            S.blacklist[egg] = os.clock() + 2.0
                            S.status = "Falha ao coletar " .. entry.rarity
                            task.wait(0.12)
                        else
                            S.state = "CONFIRMANDO_CARRY"
                            S.status = entry.rarity .. " • esperando CarrierUserId"

                            local carried = waitCarryConfirmed(uid, token, 4.5)
                            if not carried then
                                S.failed = S.failed + 1
                                if egg and egg.Parent then
                                    S.blacklist[egg] = os.clock() + 2.5
                                end
                                S.status = "Carry nao confirmado • nao libero proximo"
                                task.wait(0.2)
                            else
                                local carriedUid = tostring(carried:GetAttribute("AreaEggUid") or uid)
                                S.current = carriedUid
                                S.state = "INDO_SAFE"
                                S.status = entry.rarity .. " coletado • indo Safe"
                                tp(SAFE_CF)

                                S.state = "CONFIRMANDO_ENTREGA"
                                S.status = entry.rarity .. " na Safe • aguardando entrega"

                                local delivered = waitDeliveryConfirmed(carried, carriedUid, token)
                                if delivered then
                                    S.delivered = S.delivered + 1
                                    S.current = nil
                                    S.currentRarity = nil
                                    S.status = "Entrega confirmada • recalculando melhor ovo"
                                    task.wait(0.12)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if S.token == token then
        S.state = "PARADO"
        S.current = nil
        S.currentRarity = nil
    end
end

--=============================== GUI ================================--
local parent
pcall(function()
    if gethui then parent = gethui() end
end)
if not parent then pcall(function() parent = CoreGui end) end
if not parent then parent = LP:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaAutoEggDelivery"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if not pcall(function() gui.Parent = parent end) then
    gui.Parent = LP:WaitForChild("PlayerGui")
end
ENV.__CAFEINA_AUTO_EGG_DELIVERY_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(280, 160)
frame.Position = UDim2.new(0, 10, 0.5, -80)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 24)
title.Position = UDim2.fromOffset(8, 6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • AUTO OVOS • MELHOR PRIMEIRO"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 9
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, -16, 0, 42)
stateLabel.Position = UDim2.fromOffset(8, 34)
stateLabel.BackgroundTransparency = 1
stateLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
stateLabel.Font = Enum.Font.Gotham
stateLabel.TextSize = 8
stateLabel.TextWrapped = true
stateLabel.TextXAlignment = Enum.TextXAlignment.Left
stateLabel.TextYAlignment = Enum.TextYAlignment.Top
stateLabel.Parent = frame

local counters = Instance.new("TextLabel")
counters.Size = UDim2.new(1, -16, 0, 20)
counters.Position = UDim2.fromOffset(8, 78)
counters.BackgroundTransparency = 1
counters.TextColor3 = Color3.fromRGB(160, 160, 172)
counters.Font = Enum.Font.Code
counters.TextSize = 8
counters.TextXAlignment = Enum.TextXAlignment.Left
counters.Parent = frame

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -16, 0, 46)
toggle.Position = UDim2.fromOffset(8, 106)
toggle.BackgroundColor3 = Color3.fromRGB(105, 30, 35)
toggle.BorderSizePixel = 0
toggle.Text = "INICIAR AUTO OVOS"
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 10
toggle.Parent = frame
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

local dragging = false
local dragStart
local startPos

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
end)

local function start()
    if S.running then return end
    S.running = true
    S.token = S.token + 1
    local token = S.token
    S.state = "INICIANDO"
    S.status = "Prioridade: Divine > Eternal > Secret > ... > Common"
    task.spawn(function()
        run(token)
    end)
end

local function stop()
    if not S.running then return end
    S.running = false
    S.token = S.token + 1
    S.state = "PARADO"
    S.current = nil
    S.currentRarity = nil
    S.status = "Parado pelo usuario"
end

toggle.MouseButton1Click:Connect(function()
    if S.running then
        stop()
    else
        start()
    end
end)

connect(RunService.RenderStepped, function()
    toggle.Text = S.running and "PARAR AUTO OVOS" or "INICIAR AUTO OVOS"
    stateLabel.Text = S.state .. "\n" .. S.status
    counters.Text = "entregues: " .. S.delivered .. "   falhas: " .. S.failed .. "   atual: " .. tostring(S.currentRarity or "-")
end)

local function cleanup()
    stop()
    for _, c in ipairs(S.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    pcall(function()
        gui:Destroy()
    end)
end

S.Start = start
S.Stop = stop
S.Cleanup = cleanup
S.GetEggCandidates = getEggCandidates
S.GetRarity = rarityOfEgg
ENV.__CAFEINA_AUTO_EGG_DELIVERY = S

print("[CAFEINA] AUTO EGG DELIVERY V1.1 • MELHOR PRIMEIRO carregado")
