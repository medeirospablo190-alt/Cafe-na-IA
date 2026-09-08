--==============================================================--
-- CAFEINA • AUTO EGG DELIVERY • V1.0
-- Mobile/executor • sequencial: ovo -> carry confirmado -> safe
-- -> entrega confirmada -> proximo ovo
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

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
    status = "Pronto",
    delivered = 0,
    failed = 0,
    current = nil,
    blacklist = setmetatable({}, {__mode = "k"}),
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
    if not c or not root then return false, "root indisponivel" end
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
        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok then return cf end
    elseif inst:IsA("BasePart") then
        return inst.CFrame
    end
    return nil
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
            local untilTime = S.blacklist[d]
            if not untilTime or untilTime <= now then
                local cf = pivotOf(d)
                if cf then
                    out[#out + 1] = {
                        obj = d,
                        cf = cf,
                        dist = (cf.Position - origin).Magnitude,
                    }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return a.dist < b.dist
    end)

    return out
end

local function localCarried(uid)
    for _, d in ipairs(Workspace:GetChildren()) do
        if d:IsA("Model") then
            local carrier = tonumber(d:GetAttribute("CarrierUserId"))
            if carrier == LP.UserId then
                local name = d.Name
                local areaUid = tostring(d:GetAttribute("AreaEggUid") or "")
                if name:find("CarriedAreaEgg_", 1, true) or areaUid ~= "" then
                    if not uid or uid == "" or areaUid == uid or name:find(uid, 1, true) then
                        return d
                    end
                end
            end
        end
    end

    local c = LP.Character
    if c then
        for _, d in ipairs(c:GetDescendants()) do
            local carrier = tonumber(d:GetAttribute("CarrierUserId"))
            if carrier == LP.UserId then
                local areaUid = tostring(d:GetAttribute("AreaEggUid") or "")
                if not uid or uid == "" or areaUid == uid or d.Name:find(uid, 1, true) then
                    return d
                end
            end
        end
    end

    return nil
end

local function targetUid(target)
    if not target then return nil end
    return tostring(target:GetAttribute("AreaEggUid") or target:GetAttribute("Uid") or target.Name)
end

local function findCarryPromptNear(pos)
    local smart = Workspace:FindFirstChild("SmartPromptPart")
    local prompt = smart and smart:FindFirstChild("CarryAreaEgg")

    if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
        local p = prompt.Parent
        if p and p:IsA("BasePart") then
            if (p.Position - pos).Magnitude <= 24 then
                return prompt
            end
        else
            return prompt
        end
    end

    return nil
end

local function waitCarryPrompt(pos, token, timeout)
    local deadline = os.clock() + (timeout or 2)
    while S.running and S.token == token and os.clock() < deadline do
        local p = findCarryPromptNear(pos)
        if p then return p end
        task.wait(0.04)
    end
    return nil
end

local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false, "prompt sumiu" end

    if fireproximityprompt then
        local ok, err = pcall(function()
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
    local deadline = os.clock() + (timeout or 4)
    while S.running and S.token == token and os.clock() < deadline do
        local carried = localCarried(uid)
        if carried then
            return carried
        end
        task.wait(0.04)
    end
    return nil
end

local function waitDeliveryConfirmed(uid, token)
    local absentSince = nil
    local lastTp = 0

    while S.running and S.token == token do
        local carried = localCarried(uid)

        if not carried then
            absentSince = absentSince or os.clock()
            if os.clock() - absentSince >= 0.35 then
                return true
            end
        else
            absentSince = nil
        end

        if os.clock() - lastTp >= 0.75 then
            lastTp = os.clock()
            tp(SAFE_CF)
        end

        task.wait(0.05)
    end

    return false
end

local function deliverExistingCarry(token)
    local carried = localCarried(nil)
    if not carried then return false end

    local uid = tostring(carried:GetAttribute("AreaEggUid") or carried.Name)
    S.current = uid
    S.state = "INDO_SAFE"
    S.status = "Ovo ja carregado • indo Safe"
    tp(SAFE_CF)

    S.state = "CONFIRMANDO_ENTREGA"
    S.status = "Safe • aguardando entrega confirmada"
    local delivered = waitDeliveryConfirmed(uid, token)
    if delivered then
        S.delivered += 1
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
                S.status = "Nenhum ovo coletavel visivel • aguardando"
                task.wait(0.3)
            else
                local entry = eggs[1]
                local egg = entry.obj
                local uid = targetUid(egg)
                S.current = uid

                S.state = "INDO_OVO"
                S.status = "Indo para: " .. egg.Name

                local approach = entry.cf * CFrame.new(0, 3.2, 2.5)
                local moved = tp(approach)

                if not moved then
                    S.failed += 1
                    S.blacklist[egg] = os.clock() + 1.5
                    S.status = "Falha no TP do ovo"
                    task.wait(0.15)
                else
                    task.wait(0.08)

                    S.state = "COLETANDO"
                    S.status = "Ovo encontrado • aguardando prompt"
                    local prompt = waitCarryPrompt(entry.cf.Position, token, 2.2)

                    if not prompt then
                        S.failed += 1
                        S.blacklist[egg] = os.clock() + 2.0
                        S.status = "Sem prompt coletavel • pulando por enquanto"
                        task.wait(0.12)
                    else
                        S.status = "Coletando ovo..."
                        local fired = triggerPrompt(prompt)

                        if not fired then
                            S.failed += 1
                            S.blacklist[egg] = os.clock() + 2.0
                            S.status = "Falha ao acionar coleta"
                            task.wait(0.12)
                        else
                            S.state = "CONFIRMANDO_CARRY"
                            S.status = "Coleta enviada • esperando CarrierUserId"
                            local carried = waitCarryConfirmed(uid, token, 4.0)

                            if not carried then
                                S.failed += 1
                                if egg and egg.Parent then
                                    S.blacklist[egg] = os.clock() + 2.5
                                end
                                S.status = "Carry nao confirmado • nao vou para o proximo"
                                task.wait(0.2)
                            else
                                local carriedUid = tostring(carried:GetAttribute("AreaEggUid") or uid)
                                S.current = carriedUid

                                S.state = "INDO_SAFE"
                                S.status = "Carry confirmado • indo Safe"
                                tp(SAFE_CF)

                                S.state = "CONFIRMANDO_ENTREGA"
                                S.status = "Na Safe • aguardando entrega concluir"
                                local delivered = waitDeliveryConfirmed(carriedUid, token)

                                if delivered then
                                    S.delivered += 1
                                    S.current = nil
                                    S.status = "Entrega confirmada • buscando proximo"
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
frame.Size = UDim2.fromOffset(274, 150)
frame.Position = UDim2.new(0, 10, 0.5, -75)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 24)
title.Position = UDim2.fromOffset(8, 6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • AUTO OVOS"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, -16, 0, 34)
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
counters.Position = UDim2.fromOffset(8, 72)
counters.BackgroundTransparency = 1
counters.TextColor3 = Color3.fromRGB(160, 160, 172)
counters.Font = Enum.Font.Code
counters.TextSize = 8
counters.TextXAlignment = Enum.TextXAlignment.Left
counters.Parent = frame

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -16, 0, 42)
toggle.Position = UDim2.fromOffset(8, 100)
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
    S.token += 1
    local token = S.token
    S.state = "INICIANDO"
    S.status = "Regra ativa: 1 ovo por vez"
    task.spawn(function()
        run(token)
    end)
end

local function stop()
    if not S.running then return end
    S.running = false
    S.token += 1
    S.state = "PARADO"
    S.current = nil
    S.status = "Parado pelo usuario"
end

toggle.MouseButton1Click:Connect(function()
    if S.running then stop() else start() end
end)

connect(game:GetService("RunService").RenderStepped, function()
    toggle.Text = S.running and "PARAR AUTO OVOS" or "INICIAR AUTO OVOS"
    stateLabel.Text = S.state .. "\n" .. S.status
    counters.Text = "entregues: " .. S.delivered .. "   falhas: " .. S.failed
end)

local function cleanup()
    stop()
    for _, c in ipairs(S.conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function() gui:Destroy() end)
end

S.Start = start
S.Stop = stop
S.Cleanup = cleanup
ENV.__CAFEINA_AUTO_EGG_DELIVERY = S

print("[CAFEINA] AUTO EGG DELIVERY V1.0 carregado")
