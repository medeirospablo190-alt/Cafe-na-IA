--==============================================================--
-- CAFEINA • SPEED + LOCAL NAME V1
-- Mobile/executor • CLIENT-SIDE ONLY
--
-- 1) Barra de velocidade local (0-200)
-- 2) Nome local (Humanoid.DisplayName + textos exatos na PlayerGui)
--==============================================================--

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(ENV, "__CAFEINA_SPEED_NAME_V1")
    if type(old) == "table" and type(old.Cleanup) == "function" then
        old.Cleanup()
    end
end)

local S = {
    speed = 16,
    localName = "",
    connections = {},
    gui = nil,
    stopped = false,
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    S.connections[#S.connections + 1] = c
    return c
end

local function character()
    local char = LP.Character
    if not char then return nil, nil end
    return char, char:FindFirstChildOfClass("Humanoid")
end

local function applySpeed()
    local _, hum = character()
    if hum then
        pcall(function()
            hum.WalkSpeed = S.speed
        end)
    end
end

local function applyLocalName()
    local name = tostring(S.localName or "")
    if name == "" then return end

    local _, hum = character()
    if hum then
        pcall(function()
            hum.DisplayName = name
        end)
    end

    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local txt = tostring(obj.Text or "")
                if txt == LP.DisplayName or txt == LP.Name then
                    pcall(function()
                        obj.Text = name
                    end)
                end
            end
        end
    end
end

local _, initialHum = character()
if initialHum then
    S.speed = math.clamp(math.floor(initialHum.WalkSpeed + 0.5), 0, 200)
end

connect(LP.CharacterAdded, function()
    task.wait(0.2)
    applySpeed()
    applyLocalName()
end)

-- Reaplica somente o valor local escolhido caso o jogo tente trocar WalkSpeed.
connect(RunService.Heartbeat, function()
    if S.stopped then return end
    local _, hum = character()
    if hum and math.abs(hum.WalkSpeed - S.speed) > 0.01 then
        pcall(function() hum.WalkSpeed = S.speed end)
    end
end)

local parent
pcall(function()
    if gethui then parent = gethui() end
end)
if not parent then
    pcall(function() parent = CoreGui end)
end
if not parent then
    parent = LP:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaSpeedNameV1"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent
S.gui = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(292, 214)
frame.Position = UDim2.new(0, 12, 0.5, -107)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -72, 0, 28)
title.Position = UDim2.fromOffset(10, 6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • SPEED / NAME"
title.TextColor3 = Color3.fromRGB(245, 245, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local min = Instance.new("TextButton")
min.Size = UDim2.fromOffset(52, 25)
min.Position = UDim2.new(1, -62, 0, 6)
min.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
min.BorderSizePixel = 0
min.Text = "MIN"
min.TextColor3 = Color3.new(1,1,1)
min.Font = Enum.Font.GothamBold
min.TextSize = 9
min.Parent = frame
Instance.new("UICorner", min).CornerRadius = UDim.new(0, 7)

local speedText = Instance.new("TextLabel")
speedText.Size = UDim2.new(1, -20, 0, 24)
speedText.Position = UDim2.fromOffset(10, 42)
speedText.BackgroundTransparency = 1
speedText.TextColor3 = Color3.fromRGB(220, 220, 228)
speedText.Font = Enum.Font.GothamBold
speedText.TextSize = 11
speedText.TextXAlignment = Enum.TextXAlignment.Left
speedText.Parent = frame

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, -28, 0, 10)
bar.Position = UDim2.fromOffset(14, 73)
bar.BackgroundColor3 = Color3.fromRGB(48, 48, 56)
bar.BorderSizePixel = 0
bar.Active = true
bar.Parent = frame
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(S.speed / 200, 1)
fill.BackgroundColor3 = Color3.fromRGB(125, 34, 39)
fill.BorderSizePixel = 0
fill.Parent = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local knob = Instance.new("Frame")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Size = UDim2.fromOffset(20, 20)
knob.Position = UDim2.fromScale(S.speed / 200, 0.5)
knob.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
knob.BorderSizePixel = 0
knob.Active = true
knob.Parent = bar
Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

local function setSpeedFromX(x)
    local width = math.max(bar.AbsoluteSize.X, 1)
    local alpha = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
    S.speed = math.floor(alpha * 200 + 0.5)
    fill.Size = UDim2.fromScale(alpha, 1)
    knob.Position = UDim2.fromScale(alpha, 0.5)
    speedText.Text = "VELOCIDADE LOCAL: " .. tostring(S.speed)
    applySpeed()
end

speedText.Text = "VELOCIDADE LOCAL: " .. tostring(S.speed)

local draggingSpeed = false
local function beginSpeed(input)
    draggingSpeed = true
    setSpeedFromX(input.Position.X)
end
bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        beginSpeed(input)
    end
end)
knob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        beginSpeed(input)
    end
end)
connect(UIS.InputChanged, function(input)
    if draggingSpeed and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        setSpeedFromX(input.Position.X)
    end
end)
connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingSpeed = false
    end
end)

local nameLabel = Instance.new("TextLabel")
nameLabel.Size = UDim2.new(1, -20, 0, 20)
nameLabel.Position = UDim2.fromOffset(10, 99)
nameLabel.BackgroundTransparency = 1
nameLabel.Text = "NOME LOCAL"
nameLabel.TextColor3 = Color3.fromRGB(210, 210, 218)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 10
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = frame

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -20, 0, 36)
nameBox.Position = UDim2.fromOffset(10, 122)
nameBox.BackgroundColor3 = Color3.fromRGB(27, 27, 32)
nameBox.BorderSizePixel = 0
nameBox.ClearTextOnFocus = false
nameBox.PlaceholderText = "Digite o nome que quer ver localmente"
nameBox.Text = ""
nameBox.TextColor3 = Color3.fromRGB(240, 240, 245)
nameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 10
nameBox.Parent = frame
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 8)

local applyName = Instance.new("TextButton")
applyName.Size = UDim2.new(1, -20, 0, 34)
applyName.Position = UDim2.fromOffset(10, 168)
applyName.BackgroundColor3 = Color3.fromRGB(105, 28, 33)
applyName.BorderSizePixel = 0
applyName.Text = "APLICAR NOME LOCAL"
applyName.TextColor3 = Color3.new(1,1,1)
applyName.Font = Enum.Font.GothamBold
applyName.TextSize = 10
applyName.Parent = frame
Instance.new("UICorner", applyName).CornerRadius = UDim.new(0, 8)

local function doApplyName()
    local text = tostring(nameBox.Text or ""):match("^%s*(.-)%s*$") or ""
    if text == "" then return end
    if #text > 32 then text = text:sub(1, 32) end
    S.localName = text
    nameBox.Text = text
    applyLocalName()
    applyName.Text = "APLICADO: " .. text:sub(1, 18)
    task.delay(1.2, function()
        if applyName.Parent then applyName.Text = "APLICAR NOME LOCAL" end
    end)
end

applyName.MouseButton1Click:Connect(doApplyName)
nameBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then doApplyName() end
end)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(92, 38)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mini.BorderSizePixel = 0
mini.Text = "SPEED/NAME"
mini.TextColor3 = Color3.new(1,1,1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 9
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 10)

min.MouseButton1Click:Connect(function()
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
local dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
connect(UIS.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function cleanup()
    if S.stopped then return end
    S.stopped = true
    for _, c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    table.clear(S.connections)
    if S.gui then pcall(function() S.gui:Destroy() end) end
end

ENV.__CAFEINA_SPEED_NAME_V1 = {
    State = S,
    Cleanup = cleanup,
}

applySpeed()
print("[CAFEINA] SPEED + LOCAL NAME V1 carregado")
