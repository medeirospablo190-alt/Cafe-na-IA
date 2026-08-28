--==============================================================--
--                CAFEÍNA V3.2 • TYCOON MOBILE
--     COMPRA / COLETA / PRODUÇÃO / FLY / MOBILE / SCANNER
--==============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIGURAÇÃO
--==============================================================--

local Config = {
    AutoBuy = false,
    AutoCollect = false,
    AutoBuyDelay = 0.28,
    AutoCollectDelay = 1.20,

    ReturnAfterBuy = true,
    ReturnAfterCollect = true,

    WalkSpeedEnabled = false,
    WalkSpeed = 28,

    Noclip = false,

    Fly = false,
    FlySpeed = 55,
    FlyUp = false,
    FlyDown = false,
}

--==============================================================--
-- ESTADO / CLEANUP
--==============================================================--

local Alive = true
local Connections = {}
local CharacterConnections = {}

local function Connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or Connections, connection)
    return connection
end

local function DisconnectBucket(bucket)
    for i = #bucket, 1, -1 do
        local connection = bucket[i]
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
        bucket[i] = nil
    end
end

local Character
local Humanoid
local Root
local DefaultWalkSpeed = 16
local CollisionCache = {}
local CachedTycoon
local CachedTycoonAt = 0

local Runtime = {
    Busy = false,
    Action = "Pronto",
    LastPurchase = "-",
    LastCollector = "-",
    BuyAttempts = 0,
    CollectAttempts = 0,
}

local function SetAction(text)
    Runtime.Action = tostring(text or "")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(text, search)
    return string.find(lower(text), lower(search), 1, true) ~= nil
end

local function IsAlive()
    return Alive
        and Character
        and Character.Parent
        and Humanoid
        and Humanoid.Parent
        and Humanoid.Health > 0
        and Root
        and Root.Parent
end

--==============================================================--
-- FLY CONTROLLER
--==============================================================--

local FlyVelocity
local FlyGyro

local function DestroyFlyObjects()
    if FlyVelocity then
        pcall(function() FlyVelocity:Destroy() end)
        FlyVelocity = nil
    end

    if FlyGyro then
        pcall(function() FlyGyro:Destroy() end)
        FlyGyro = nil
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.PlatformStand = false
        end)
    end

    Config.FlyUp = false
    Config.FlyDown = false
end

local function EnsureFlyObjects()
    if not IsAlive() then
        return false
    end

    if not FlyVelocity or not FlyVelocity.Parent then
        FlyVelocity = Instance.new("BodyVelocity")
        FlyVelocity.Name = "CafeinaFlyVelocity"
        FlyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        FlyVelocity.P = 18000
        FlyVelocity.Velocity = Vector3.new(0, 0, 0)
        FlyVelocity.Parent = Root
    end

    if not FlyGyro or not FlyGyro.Parent then
        FlyGyro = Instance.new("BodyGyro")
        FlyGyro.Name = "CafeinaFlyGyro"
        FlyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        FlyGyro.P = 15000
        FlyGyro.D = 450
        FlyGyro.CFrame = Root.CFrame
        FlyGyro.Parent = Root
    end

    return true
end

--==============================================================--
-- PERSONAGEM / RESPAWN
--==============================================================--

local function RestoreCollisions()
    for part, oldValue in pairs(CollisionCache) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = oldValue
            end)
        end
    end
    for key in pairs(CollisionCache) do CollisionCache[key] = nil end
end

local function BindCharacter(character)
    DisconnectBucket(CharacterConnections)
    DestroyFlyObjects()
    RestoreCollisions()

    Character = character or Player.Character or Player.CharacterAdded:Wait()
    Humanoid = Character:WaitForChild("Humanoid", 10)
    Root = Character:WaitForChild("HumanoidRootPart", 10)

    if Humanoid then
        DefaultWalkSpeed = Humanoid.WalkSpeed
    end

    CachedTycoon = nil
    CachedTycoonAt = 0

    if Humanoid then
        Connect(Humanoid.Died, function()
            DestroyFlyObjects()
            RestoreCollisions()
        end, CharacterConnections)
    end
end

-- O vínculo do personagem é propositalmente assíncrono.
-- Assim, mesmo que Humanoid/Root demorem para aparecer, a GUI abre primeiro.
task.spawn(function()
    local character = Player.Character
    if not character then
        character = Player.CharacterAdded:Wait()
    end

    if not Alive then
        return
    end

    local ok, err = pcall(function()
        BindCharacter(character)
    end)

    if not ok then
        warn("[CAFEINA V3.2] Falha inicial ao vincular personagem:", err)
    end
end)

Connect(Player.CharacterAdded, function(character)
    task.spawn(function()
        task.wait(0.35)

        if not Alive then
            return
        end

        local ok, err = pcall(function()
            BindCharacter(character)
        end)

        if not ok then
            warn("[CAFEINA V3.2] Falha no respawn:", err)
        end
    end)
end)

--==============================================================--
-- HELPERS
--==============================================================--

local function GetPart(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object
    end

    if object:IsA("Model") and object.PrimaryPart then
        return object.PrimaryPart
    end

    return object:FindFirstChildWhichIsA("BasePart", true)
end

local function Teleport(part, offset)
    if not IsAlive() or not part or not part:IsA("BasePart") then
        return false
    end

    local ok = pcall(function()
        Root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        Root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        Root.CFrame = part.CFrame + (offset or Vector3.new(0, 2.5, 0))
    end)

    return ok
end

local function GetText(object)
    if not object then
        return ""
    end

    local candidates = {}

    for _, desc in ipairs(object:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local text = tostring(desc.Text or "")
            if text ~= "" then
                table.insert(candidates, text)
            end
        end
    end

    table.sort(candidates, function(a, b)
        local aScore = 0
        local bScore = 0

        if string.match(a, "%d") then aScore = aScore + 2 end
        if contains(a, "$") or contains(a, "buy") or contains(a, "point") then aScore = aScore + 3 end
        if string.match(b, "%d") then bScore = bScore + 2 end
        if contains(b, "$") or contains(b, "buy") or contains(b, "point") then bScore = bScore + 3 end

        if aScore == bScore then
            return #a > #b
        end
        return aScore > bScore
    end)

    return candidates[1] or ""
end

local function ParsePrice(text)
    if not text or text == "" then
        return nil
    end

    local cleaned = lower(text):gsub(",", "")
    local number, suffix = string.match(cleaned, "([%d%.]+)%s*([kmbt]?)")
    local value = tonumber(number)

    if not value then
        return nil
    end

    local multipliers = {
        k = 1e3,
        m = 1e6,
        b = 1e9,
        t = 1e12,
    }

    if suffix and suffix ~= "" then
        value *= multipliers[suffix] or 1
    end

    return value
end

--==============================================================--
-- DETECÇÃO DO TYCOON
--==============================================================--

local function ValidContainer(object)
    return object
        and object.Parent
        and (object:IsA("Model") or object:IsA("Folder"))
end

local function FindUserIdContainer(container)
    if not container then
        return nil
    end

    local userId = tostring(Player.UserId)

    for _, object in ipairs(container:GetChildren()) do
        if tostring(object.Name) == userId and ValidContainer(object) then
            return object
        end
    end

    for _, object in ipairs(container:GetDescendants()) do
        if tostring(object.Name) == userId and ValidContainer(object) then
            return object
        end
    end

    return nil
end

local function GetTycoonRoot(force)
    if not force
        and ValidContainer(CachedTycoon)
        and os.clock() - CachedTycoonAt < 1.5 then
        return CachedTycoon
    end

    CachedTycoonAt = os.clock()

    local tycoons = workspace:FindFirstChild("Tycoons")
    if not tycoons then
        CachedTycoon = nil
        return nil
    end

    local plot = tycoons:FindFirstChild("Plot")
    local genericTycoon = plot and plot:FindFirstChild("Tycoon")

    if genericTycoon then
        local direct = genericTycoon:FindFirstChild(tostring(Player.UserId))
        if ValidContainer(direct) then
            CachedTycoon = direct
            return direct
        end
    end

    local byId = FindUserIdContainer(tycoons)
    if byId then
        CachedTycoon = byId
        return byId
    end

    for _, label in ipairs(tycoons:GetDescendants()) do
        if label:IsA("TextLabel") then
            local text = lower(label.Text)
            if text == lower(Player.Name) or text == lower(Player.DisplayName) then
                local current = label.Parent
                while current and current ~= workspace do
                    if tostring(current.Name) == tostring(Player.UserId) and ValidContainer(current) then
                        CachedTycoon = current
                        return current
                    end
                    current = current.Parent
                end
            end
        end
    end

    CachedTycoon = nil
    return nil
end

--==============================================================--
-- SCANNERS
--==============================================================--

local function ScanPurchases()
    local tycoon = GetTycoonRoot()
    if not tycoon then
        return {}
    end

    local results = {}
    local seen = {}

    local function AddPurchase(purchase, touch)
        if not purchase or not touch or not touch:IsA("BasePart") or not touch.Parent then
            return
        end

        if not touch:IsDescendantOf(tycoon) then
            return
        end

        local key = purchase:GetFullName()
        if seen[key] then
            return
        end

        seen[key] = true

        local display = GetText(purchase)
        table.insert(results, {
            Name = purchase.Name,
            Object = purchase,
            Touch = touch,
            Display = display,
            Price = ParsePrice(display),
        })
    end

    for _, object in ipairs(tycoon:GetDescendants()) do
        if object:IsA("BasePart") and lower(object.Name) == "bypassanim_touch" then
            local button = object.Parent
            local purchase = button and button.Parent
            AddPurchase(purchase, object)
        end
    end

    for _, object in ipairs(tycoon:GetDescendants()) do
        if (object:IsA("Model") or object:IsA("Folder")) and lower(object.Name) == "button" then
            local touch

            for _, desc in ipairs(object:GetDescendants()) do
                if desc:IsA("BasePart") and contains(desc.Name, "touch") then
                    touch = desc
                    break
                end
            end

            touch = touch or GetPart(object)
            AddPurchase(object.Parent, touch)
        end
    end

    table.sort(results, function(a, b)
        if a.Price and b.Price and a.Price ~= b.Price then
            return a.Price < b.Price
        elseif a.Price and not b.Price then
            return true
        elseif b.Price and not a.Price then
            return false
        end
        return lower(a.Name) < lower(b.Name)
    end)

    return results
end

local function ScanCollectors()
    local tycoon = GetTycoonRoot()
    if not tycoon then
        return {}
    end

    local results = {}
    local seen = {}

    for _, object in ipairs(tycoon:GetDescendants()) do
        local name = lower(object.Name)
        if name == "collect points" or name == "collector" or name == "collect" then
            local touches = {}

            for _, desc in ipairs(object:GetDescendants()) do
                if desc:IsA("BasePart") and lower(desc.Name) == "touch" then
                    table.insert(touches, desc)
                end
            end

            if #touches == 0 then
                local fallback = GetPart(object)
                if fallback then
                    table.insert(touches, fallback)
                end
            end

            for _, touch in ipairs(touches) do
                local key = touch:GetFullName()
                if not seen[key] then
                    seen[key] = true
                    table.insert(results, {
                        Name = object.Name,
                        Object = object,
                        Touch = touch,
                    })
                end
            end
        end
    end

    return results
end

local function ValueOf(object)
    if object and object:IsA("ValueBase") then
        return object.Value
    end
    return nil
end

local function ScanDroppers()
    local tycoon = GetTycoonRoot()
    if not tycoon then
        return {}
    end

    local results = {}
    local seen = {}

    for _, object in ipairs(tycoon:GetDescendants()) do
        if (object:IsA("Model") or object:IsA("Folder")) and contains(object.Name, "dropper") then
            local stats = object:FindFirstChild("Stats")
            if stats and not seen[object] then
                seen[object] = true
                table.insert(results, {
                    Name = object.Name,
                    Object = object,
                    Value = ValueOf(stats:FindFirstChild("DefaultValue")) or "?",
                    Rate = ValueOf(stats:FindFirstChild("ProductionRate")) or "?",
                    ReplicatedRate = ValueOf(stats:FindFirstChild("ReplicatedProductionRate")) or "?",
                })
            end
        end
    end

    table.sort(results, function(a, b)
        return lower(a.Name) < lower(b.Name)
    end)

    return results
end

local function ScanUpgrades()
    local tycoon = GetTycoonRoot()
    if not tycoon then
        return {}
    end

    local results = {}
    local seen = {}

    for _, object in ipairs(tycoon:GetDescendants()) do
        if object:IsA("Model") or object:IsA("Folder") then
            local name = lower(object.Name)
            if contains(name, "upgrader") or contains(name, "refiner") or contains(name, "conveyor") then
                local stats = object:FindFirstChild("Stats")
                local config = object:FindFirstChild("Config")

                if (stats or config) and not seen[object] then
                    seen[object] = true
                    local increase = stats and stats:FindFirstChild("ValueIncrease")
                    table.insert(results, {
                        Name = object.Name,
                        Object = object,
                        Increase = ValueOf(increase) or "?",
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return lower(a.Name) < lower(b.Name)
    end)

    return results
end

local function ScanTools()
    local results = {}
    local seen = {}

    local function Scan(container)
        if not container then
            return
        end

        for _, object in ipairs(container:GetChildren()) do
            if object:IsA("Tool") then
                local key = object.Name .. "|" .. container.Name
                if not seen[key] then
                    seen[key] = true
                    table.insert(results, {
                        Name = object.Name,
                        Object = object,
                        Location = container.Name,
                    })
                end
            end
        end
    end

    Scan(Player:FindFirstChild("Backpack"))
    Scan(Character)
    Scan(Player:FindFirstChild("StarterGear"))

    return results
end

local function ReadRebirth()
    local data = {
        State = "Desconhecido",
        Count = "",
        Reward = "",
        Message = "",
    }

    local ui = PlayerGui:FindFirstChild("UI")
    local base = ui and ui:FindFirstChild("Base")
    local menu = base and base:FindFirstChild("RebirthMenu")

    if not menu then
        return data
    end

    local locked = menu:FindFirstChild("Locked", true)
    local ready = menu:FindFirstChild("Ready", true)

    if ready and ready:IsA("GuiObject") and ready.Visible then
        data.State = "PRONTO"
    elseif locked and locked:IsA("GuiObject") and locked.Visible then
        data.State = "BLOQUEADO"
    end

    local container = data.State == "PRONTO" and ready or locked
    if not container then
        return data
    end

    local count = container:FindFirstChild("Count", true)
    local rewards = container:FindFirstChild("Rewards", true)
    local body = container:FindFirstChild("Body", true)

    if count and count:IsA("TextLabel") then data.Count = count.Text end
    if rewards and rewards:IsA("TextLabel") then data.Reward = rewards.Text end
    if body and body:IsA("TextLabel") then data.Message = body.Text end

    return data
end

--==============================================================--
-- COMPRA / COLETA RÁPIDA COM RETORNO
--==============================================================--

local function QuickTouch(part, shouldReturn, actionName)
    if not IsAlive() or not part or not part:IsA("BasePart") or not part.Parent then
        return false
    end

    if Runtime.Busy then
        return false
    end

    Runtime.Busy = true
    SetAction(actionName or "Interagindo")

    local originalCFrame = Root.CFrame
    local originalLinear = Root.AssemblyLinearVelocity
    local originalAngular = Root.AssemblyAngularVelocity
    local success = false

    local ok = pcall(function()
        Root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        Root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        -- Encosta fisicamente por um intervalo curto.
        Root.CFrame = part.CFrame + Vector3.new(0, math.max(0.35, part.Size.Y * 0.30), 0)
        task.wait(0.055)

        if type(firetouchinterest) == "function" then
            firetouchinterest(Root, part, 0)
            task.wait(0.055)
            firetouchinterest(Root, part, 1)
        else
            Root.CFrame = part.CFrame + Vector3.new(0, 0.10, 0)
            task.wait(0.10)
        end

        success = true
    end)

    if shouldReturn and originalCFrame and IsAlive() then
        task.wait(0.035)
        pcall(function()
            Root.CFrame = originalCFrame
            Root.AssemblyLinearVelocity = originalLinear
            Root.AssemblyAngularVelocity = originalAngular
        end)
    end

    Runtime.Busy = false

    if not ok then
        SetAction("Erro na interação")
        return false
    end

    SetAction("Pronto")
    return success
end

local function BuyItem(item)
    if not item or not item.Touch or not item.Touch.Parent then
        SetAction("Compra indisponível")
        return false
    end

    Runtime.LastPurchase = item.Name
    Runtime.BuyAttempts = Runtime.BuyAttempts + 1

    return QuickTouch(
        item.Touch,
        Config.ReturnAfterBuy,
        "Comprando: " .. item.Name
    )
end

local function CollectItem(item)
    if not item or not item.Touch or not item.Touch.Parent then
        SetAction("Coletor indisponível")
        return false
    end

    Runtime.LastCollector = item.Name
    Runtime.CollectAttempts = Runtime.CollectAttempts + 1

    return QuickTouch(
        item.Touch,
        Config.ReturnAfterCollect,
        "Coletando"
    )
end

--==============================================================--
-- GUI CLEANUP
--==============================================================--

for _, name in ipairs({"CafeinaTycoonV2", "CafeinaTycoonV25", "CafeinaTycoonV3", "CafeinaTycoonV31", "CafeinaTycoonV32"}) do
    local old = PlayerGui:FindFirstChild(name)
    if old then
        old:Destroy()
    end
end

local GUI = Instance.new("ScreenGui")
GUI.Name = "CafeinaTycoonV32"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(430, 390)
Main.Position = UDim2.new(0.5, -215, 0.5, -195)
Main.BackgroundColor3 = Color3.fromRGB(15, 15, 19)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = GUI

Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 14)

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(190, 30, 43)
MainStroke.Thickness = 1.4
MainStroke.Parent = Main

local Scale = Instance.new("UIScale")
Scale.Parent = Main

local function UpdateScale()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local width = camera.ViewportSize.X
    if width < 500 then
        Scale.Scale = math.clamp(width / 470, 0.72, 0.93)
    else
        Scale.Scale = 1
    end
end

UpdateScale()

local CameraViewportConnection

local function BindCameraScale()
    if CameraViewportConnection then
        pcall(function()
            CameraViewportConnection:Disconnect()
        end)
        CameraViewportConnection = nil
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    CameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale)
    table.insert(Connections, CameraViewportConnection)
    UpdateScale()
end

BindCameraScale()

Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    task.defer(BindCameraScale)
end)

--==============================================================--
-- HEADER
--==============================================================--

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 55)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.fromOffset(39, 39)
Logo.Position = UDim2.fromOffset(9, 8)
Logo.BackgroundColor3 = Color3.fromRGB(125, 20, 31)
Logo.Text = "C"
Logo.TextColor3 = Color3.new(1, 1, 1)
Logo.Font = Enum.Font.GothamBlack
Logo.TextSize = 19
Logo.Parent = Header
Instance.new("UICorner", Logo).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.fromOffset(57, 7)
Title.Size = UDim2.new(1, -150, 0, 24)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA V3.2"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = Color3.fromRGB(245, 245, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Position = UDim2.fromOffset(57, 29)
Subtitle.Size = UDim2.new(1, -150, 0, 17)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "TYCOON • MOBILE"
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextSize = 10
Subtitle.TextColor3 = Color3.fromRGB(145, 145, 155)
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(35, 35)
Minimize.Position = UDim2.new(1, -80, 0, 10)
Minimize.BackgroundColor3 = Color3.fromRGB(36, 36, 43)
Minimize.BorderSizePixel = 0
Minimize.Text = "−"
Minimize.TextColor3 = Color3.new(1, 1, 1)
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 20
Minimize.Parent = Header
Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0, 9)

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(35, 35)
Close.Position = UDim2.new(1, -40, 0, 10)
Close.BackgroundColor3 = Color3.fromRGB(120, 20, 30)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 20
Close.Parent = Header
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 9)

local DragArea = Instance.new("Frame")
DragArea.Position = UDim2.fromOffset(0, 0)
DragArea.Size = UDim2.new(1, -88, 1, 0)
DragArea.BackgroundTransparency = 1
DragArea.Active = true
DragArea.ZIndex = 20
DragArea.Parent = Header

--==============================================================--
-- SIDEBAR / CONTENT
--==============================================================--

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Position = UDim2.fromOffset(8, 60)
Sidebar.Size = UDim2.new(0, 121, 1, -68)
Sidebar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 3
Sidebar.CanvasSize = UDim2.new()
Sidebar.Parent = Main
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 11)

local SidePadding = Instance.new("UIPadding")
SidePadding.PaddingTop = UDim.new(0, 7)
SidePadding.PaddingBottom = UDim.new(0, 7)
SidePadding.PaddingLeft = UDim.new(0, 6)
SidePadding.PaddingRight = UDim.new(0, 6)
SidePadding.Parent = Sidebar

local SideLayout = Instance.new("UIListLayout")
SideLayout.Padding = UDim.new(0, 5)
SideLayout.Parent = Sidebar

Connect(SideLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    Sidebar.CanvasSize = UDim2.fromOffset(0, SideLayout.AbsoluteContentSize.Y + 18)
end)

local Content = Instance.new("ScrollingFrame")
Content.Position = UDim2.fromOffset(137, 60)
Content.Size = UDim2.new(1, -145, 1, -68)
Content.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.CanvasSize = UDim2.new()
Content.Parent = Main
Instance.new("UICorner", Content).CornerRadius = UDim.new(0, 11)

local ContentPadding = Instance.new("UIPadding")
ContentPadding.PaddingTop = UDim.new(0, 9)
ContentPadding.PaddingBottom = UDim.new(0, 14)
ContentPadding.PaddingLeft = UDim.new(0, 9)
ContentPadding.PaddingRight = UDim.new(0, 9)
ContentPadding.Parent = Content

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 7)
ContentLayout.Parent = Content

Connect(ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    Content.CanvasSize = UDim2.fromOffset(0, ContentLayout.AbsoluteContentSize.Y + 30)
end)

local function ClearPage()
    for _, object in ipairs(Content:GetChildren()) do
        if object ~= ContentLayout and object ~= ContentPadding then
            object:Destroy()
        end
    end
    Content.CanvasPosition = Vector2.zero
end

local function Label(text, height, bold)
    local object = Instance.new("TextLabel")
    object.Size = UDim2.new(1, -2, 0, height or 34)
    object.BackgroundTransparency = 1
    object.Text = tostring(text or "")
    object.TextWrapped = true
    object.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    object.TextSize = bold and 16 or 12
    object.TextColor3 = bold and Color3.fromRGB(245, 245, 248) or Color3.fromRGB(200, 200, 208)
    object.TextXAlignment = Enum.TextXAlignment.Left
    object.TextYAlignment = Enum.TextYAlignment.Center
    object.Parent = Content
    return object
end

local function Button(text, callback, height, parent)
    local object = Instance.new("TextButton")
    object.Size = UDim2.new(1, -2, 0, height or 45)
    object.BackgroundColor3 = Color3.fromRGB(31, 31, 38)
    object.BorderSizePixel = 0
    object.Text = "  " .. tostring(text or "")
    object.TextWrapped = true
    object.TextColor3 = Color3.fromRGB(238, 238, 243)
    object.Font = Enum.Font.GothamMedium
    object.TextSize = 12
    object.TextXAlignment = Enum.TextXAlignment.Left
    object.Parent = parent or Content
    Instance.new("UICorner", object).CornerRadius = UDim.new(0, 9)

    object.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then
            SetAction("Erro: " .. tostring(err))
        end
    end)

    return object
end

local function InfoCard(title, value)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -2, 0, 52)
    card.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    card.BorderSizePixel = 0
    card.Parent = Content
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 9)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Position = UDim2.fromOffset(10, 5)
    titleLabel.Size = UDim2.new(1, -20, 0, 17)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = tostring(title or "")
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.TextSize = 10
    titleLabel.TextColor3 = Color3.fromRGB(145, 145, 155)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = card

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Position = UDim2.fromOffset(10, 23)
    valueLabel.Size = UDim2.new(1, -20, 0, 23)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(value or "")
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 13
    valueLabel.TextColor3 = Color3.fromRGB(242, 242, 246)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
    valueLabel.Parent = card

    return card, valueLabel
end

local function Toggle(text, getter, setter)
    local button

    local function Refresh()
        local enabled = getter()
        button.Text = "  " .. text .. (enabled and "   [ON]" or "   [OFF]")
        button.BackgroundColor3 = enabled and Color3.fromRGB(105, 24, 34) or Color3.fromRGB(31, 31, 38)
    end

    button = Button(text, function()
        setter(not getter())
        Refresh()
    end)

    Refresh()
    return button
end

local function Slider(title, minimum, maximum, getter, setter)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -2, 0, 68)
    frame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    frame.BorderSizePixel = 0
    frame.Parent = Content
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)

    local text = Instance.new("TextLabel")
    text.Position = UDim2.fromOffset(10, 5)
    text.Size = UDim2.new(1, -20, 0, 21)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamMedium
    text.TextSize = 12
    text.TextColor3 = Color3.fromRGB(235, 235, 240)
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.Parent = frame

    local bar = Instance.new("Frame")
    bar.Position = UDim2.new(0, 10, 1, -24)
    bar.Size = UDim2.new(1, -20, 0, 10)
    bar.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
    bar.BorderSizePixel = 0
    bar.Active = true
    bar.Parent = frame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(190, 31, 45)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false

    local function Draw()
        local value = math.clamp(getter(), minimum, maximum)
        local pct = (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.fromScale(pct, 1)
        text.Text = title .. " • " .. math.floor(value)
    end

    local function Update(x)
        if not bar.Parent or bar.AbsoluteSize.X <= 0 then
            return
        end
        local pct = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        setter(math.floor(minimum + (maximum - minimum) * pct))
        Draw()
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            Update(input.Position.X)
        end
    end)

    bar.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
            Update(input.Position.X)
        end
    end)

    local sliderEndConnection
    sliderEndConnection = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    frame.AncestryChanged:Connect(function(_, parent)
        if parent == nil and sliderEndConnection then
            sliderEndConnection:Disconnect()
            sliderEndConnection = nil
        end
    end)

    Draw()
    return frame
end

--==============================================================--
-- PÁGINAS / NAVEGAÇÃO
--==============================================================--

local Pages = {}
local CurrentPage = "Principal"
local PageVersion = 0

local function OpenPage(name)
    if not Pages[name] then
        return
    end

    CurrentPage = name
    PageVersion = PageVersion + 1
    Pages[name](PageVersion)
end

local function Nav(name, icon)
    local object = Instance.new("TextButton")
    object.Size = UDim2.new(1, 0, 0, 40)
    object.BackgroundColor3 = Color3.fromRGB(29, 29, 35)
    object.BorderSizePixel = 0
    object.Text = " " .. icon .. "  " .. name
    object.TextColor3 = Color3.fromRGB(220, 220, 226)
    object.Font = Enum.Font.GothamMedium
    object.TextSize = 11
    object.TextXAlignment = Enum.TextXAlignment.Left
    object.Parent = Sidebar
    Instance.new("UICorner", object).CornerRadius = UDim.new(0, 8)

    object.Activated:Connect(function()
        OpenPage(name)
    end)
end

Pages.Principal = function(version)
    ClearPage()
    Label("CAFEÍNA • TYCOON", 35, true)

    local _, tycoonValue = InfoCard("TYCOON", "Carregando...")
    local _, purchasesValue = InfoCard("COMPRAS", "...")
    local _, collectorsValue = InfoCard("COLETORES", "...")
    local _, droppersValue = InfoCard("DROPPERS", "...")
    local _, upgradesValue = InfoCard("UPGRADES / REFINERS", "...")
    local _, rebirthValue = InfoCard("REBIRTH", "...")
    local _, actionValue = InfoCard("AÇÃO", Runtime.Action)

    Button("🔄 REESCANEAR", function()
        CachedTycoon = nil
        OpenPage("Principal")
    end)

    Button("🛒 ABRIR COMPRAS", function()
        OpenPage("Compras")
    end)

    Button("💰 ABRIR COLETA", function()
        OpenPage("Coleta")
    end)

    -- Nunca bloquear o primeiro frame da interface com scans grandes.
    task.spawn(function()
        task.wait(0.12)

        if not Alive or CurrentPage ~= "Principal" or version ~= PageVersion then
            return
        end

        local okTycoon, tycoon = pcall(GetTycoonRoot, true)
        tycoonValue.Text = (okTycoon and tycoon) and tycoon.Name or "Não detectado"
        task.wait()

        local okPurchases, purchases = pcall(ScanPurchases)
        purchasesValue.Text = okPurchases and tostring(#purchases) or "Erro"
        task.wait()

        local okCollectors, collectors = pcall(ScanCollectors)
        collectorsValue.Text = okCollectors and tostring(#collectors) or "Erro"
        task.wait()

        local okDroppers, droppers = pcall(ScanDroppers)
        droppersValue.Text = okDroppers and tostring(#droppers) or "Erro"
        task.wait()

        local okUpgrades, upgrades = pcall(ScanUpgrades)
        upgradesValue.Text = okUpgrades and tostring(#upgrades) or "Erro"
        task.wait()

        local okRebirth, rebirth = pcall(ReadRebirth)
        rebirthValue.Text = (okRebirth and rebirth and rebirth.State) or "Erro"
        actionValue.Text = Runtime.Action
    end)
end

Pages.Compras = function(version)
    ClearPage()
    Label("Compras • tempo real", 35, true)

    local _, countValue = InfoCard("COMPRAS DISPONÍVEIS", "0")
    local _, lastValue = InfoCard("ÚLTIMA COMPRA", Runtime.LastPurchase)

    Toggle("AUTO COMPRA", function()
        return Config.AutoBuy
    end, function(value)
        Config.AutoBuy = value
        SetAction(value and "Auto compra ligado" or "Auto compra parado")
    end)

    Toggle("VOLTAR APÓS COMPRAR", function()
        return Config.ReturnAfterBuy
    end, function(value)
        Config.ReturnAfterBuy = value
    end)

    Button("🛒 COMPRAR PRÓXIMO", function()
        local list = ScanPurchases()
        if list[1] then
            BuyItem(list[1])
        else
            SetAction("Nenhuma compra disponível")
        end
    end)

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -2, 0, 1)
    container.BackgroundTransparency = 1
    container.Parent = Content

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.Parent = container

    local function UpdatePurchaseContainerSize()
        if container and container.Parent then
            container.Size = UDim2.new(1, -2, 0, math.max(1, layout.AbsoluteContentSize.Y))
        end
    end

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdatePurchaseContainerSize)

    local lastSignature = nil

    local function Refresh(force)
        if not Alive or CurrentPage ~= "Compras" or version ~= PageVersion or not container.Parent then
            return
        end

        local list = ScanPurchases()
        local signatureParts = {}

        for _, item in ipairs(list) do
            table.insert(signatureParts, item.Touch and item.Touch:GetFullName() or item.Name)
        end

        local signature = table.concat(signatureParts, "|")
        if not force and signature == lastSignature then
            countValue.Text = tostring(#list)
            lastValue.Text = Runtime.LastPurchase
            return
        end

        lastSignature = signature
        countValue.Text = tostring(#list)
        lastValue.Text = Runtime.LastPurchase

        for _, child in ipairs(container:GetChildren()) do
            if child ~= layout then
                child:Destroy()
            end
        end

        if #list == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 46)
            empty.BackgroundColor3 = Color3.fromRGB(27, 27, 33)
            empty.BorderSizePixel = 0
            empty.Text = "Nenhuma compra disponível"
            empty.TextColor3 = Color3.fromRGB(155, 155, 165)
            empty.Font = Enum.Font.GothamMedium
            empty.TextSize = 12
            empty.Parent = container
            Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 9)
            task.defer(UpdatePurchaseContainerSize)
            return
        end

        for index, item in ipairs(list) do
            local text = "🛒 " .. index .. ". " .. item.Name
            if item.Display ~= "" then
                text = text .. "\n" .. item.Display
            end

            Button(text, function()
                if item.Touch and item.Touch.Parent then
                    BuyItem(item)
                    task.delay(0.15, function()
                        if Alive and CurrentPage == "Compras" and version == PageVersion then
                            Refresh(true)
                        end
                    end)
                else
                    SetAction("Compra já removida")
                    Refresh(true)
                end
            end, item.Display ~= "" and 58 or 46, container)
        end
        task.defer(UpdatePurchaseContainerSize)
    end

    Refresh(true)

    task.spawn(function()
        while Alive and GUI.Parent and CurrentPage == "Compras" and version == PageVersion do
            pcall(Refresh, false)
            task.wait(0.22)
        end
    end)
end

Pages.Coleta = function()
    ClearPage()
    Label("Coleta", 35, true)

    local collectors = ScanCollectors()
    InfoCard("COLETORES", #collectors)
    InfoCard("ÚLTIMA COLETA", Runtime.LastCollector)

    Toggle("AUTO COLETA", function()
        return Config.AutoCollect
    end, function(value)
        Config.AutoCollect = value
    end)

    Toggle("VOLTAR APÓS COLETAR", function()
        return Config.ReturnAfterCollect
    end, function(value)
        Config.ReturnAfterCollect = value
    end)

    Button("💰 COLETAR AGORA", function()
        local list = ScanCollectors()
        if list[1] then
            CollectItem(list[1])
        else
            SetAction("Coletor não encontrado")
        end
    end)

    for index, item in ipairs(collectors) do
        Button("📍 " .. index .. ". " .. item.Name, function()
            Teleport(item.Touch)
        end)
    end
end

Pages.Produção = function()
    ClearPage()
    Label("Produção", 35, true)

    local droppers = ScanDroppers()
    InfoCard("DROPPERS", #droppers)

    for _, item in ipairs(droppers) do
        Button(
            "⚙ " .. item.Name .. "\nValor: " .. tostring(item.Value) .. " • Rate: " .. tostring(item.Rate) .. " • Rep: " .. tostring(item.ReplicatedRate),
            function() end,
            58
        )
    end
end

Pages.Upgrades = function()
    ClearPage()
    Label("Upgraders / Refiners", 35, true)

    local list = ScanUpgrades()
    InfoCard("DETECTADOS", #list)

    for _, item in ipairs(list) do
        local text = "⬆ " .. item.Name
        if item.Increase ~= "?" then
            text = text .. " • " .. tostring(item.Increase)
        end

        Button(text, function()
            local part = GetPart(item.Object)
            if part then
                Teleport(part)
            end
        end)
    end
end

Pages.Progresso = function()
    ClearPage()
    Label("Progressão", 35, true)

    local data = ReadRebirth()
    InfoCard("REBIRTH", data.State)

    if data.Count ~= "" then
        Label(data.Count:gsub("<.->", ""), 55)
    end

    if data.Reward ~= "" then
        Label(data.Reward:gsub("<.->", ""), 70)
    end

    if data.Message ~= "" then
        Label(data.Message:gsub("<.->", ""), 85)
    end

    Button("🔄 ATUALIZAR", function()
        OpenPage("Progresso")
    end)
end

Pages.Itens = function()
    ClearPage()
    Label("Itens", 35, true)

    local list = ScanTools()
    InfoCard("TOOLS", #list)

    for _, item in ipairs(list) do
        Button("◆ " .. item.Name .. " • " .. item.Location, function()
            if IsAlive() and item.Object and item.Object.Parent == Player:FindFirstChild("Backpack") then
                Humanoid:EquipTool(item.Object)
            end
        end)
    end
end

Pages.Movimento = function()
    ClearPage()
    Label("Movimento", 35, true)

    Toggle("NOCLIP", function()
        return Config.Noclip
    end, function(value)
        Config.Noclip = value
        if not value then
            RestoreCollisions()
        end
    end)

    Toggle("FLY", function()
        return Config.Fly
    end, function(value)
        Config.Fly = value
        if not value then
            DestroyFlyObjects()
        end
    end)

    Slider("Fly Speed", 10, 200, function()
        return Config.FlySpeed
    end, function(value)
        Config.FlySpeed = value
    end)

    Toggle("WALK SPEED", function()
        return Config.WalkSpeedEnabled
    end, function(value)
        Config.WalkSpeedEnabled = value
        if not value and Humanoid and Humanoid.Parent then
            Humanoid.WalkSpeed = DefaultWalkSpeed
        end
    end)

    Slider("Walk Speed", 16, 120, function()
        return Config.WalkSpeed
    end, function(value)
        Config.WalkSpeed = value
    end)

    Button("🏠 IR PARA MEU TYCOON", function()
        local tycoon = GetTycoonRoot(true)
        if tycoon then
            local spawn = tycoon:FindFirstChild("Spawn", true)
            local part = GetPart(spawn) or GetPart(tycoon)
            if part then Teleport(part) end
        end
    end)

    Button("💰 IR PARA COLETOR", function()
        local collectors = ScanCollectors()
        if collectors[1] then
            Teleport(collectors[1].Touch)
        end
    end)
end

Pages.Scanner = function(version)
    ClearPage()
    Label("Scanner Tycoon", 35, true)

    local _, tycoonValue = InfoCard("TYCOON", "Carregando...")
    local _, purchasesValue = InfoCard("COMPRAS", "...")
    local _, collectorsValue = InfoCard("COLETORES", "...")
    local _, droppersValue = InfoCard("DROPPERS", "...")
    local _, upgradesValue = InfoCard("UPGRADES", "...")
    local _, toolsValue = InfoCard("TOOLS", "...")
    local _, statusValue = InfoCard("STATUS", "Preparando scan...")

    local LatestReport = nil

    Button("🔄 REESCANEAR", function()
        OpenPage("Scanner")
    end)

    Button("📋 COPIAR DIAGNÓSTICO", function()
        if not LatestReport then
            SetAction("Scanner ainda carregando")
            statusValue.Text = "Aguarde o scan terminar"
            return
        end

        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(LatestReport)
        end)

        if not okEncode then
            SetAction("Falha ao gerar diagnóstico")
            statusValue.Text = "Erro ao gerar JSON"
            return
        end

        if type(setclipboard) == "function" then
            local okClipboard = pcall(function()
                setclipboard(encoded)
            end)

            if okClipboard then
                SetAction("Diagnóstico copiado")
                statusValue.Text = "Diagnóstico copiado"
            else
                SetAction("Falha ao copiar")
                statusValue.Text = "Clipboard falhou"
            end
        else
            SetAction("Clipboard indisponível")
            statusValue.Text = "Clipboard indisponível"
        end
    end)

    task.spawn(function()
        task.wait(0.08)

        if not Alive or CurrentPage ~= "Scanner" or version ~= PageVersion then
            return
        end

        statusValue.Text = "Localizando Tycoon..."

        local okTycoon, tycoon = pcall(GetTycoonRoot, true)
        if not okTycoon or not tycoon then
            tycoonValue.Text = "Não detectado"
            statusValue.Text = "Tycoon não encontrado"
            return
        end

        tycoonValue.Text = tycoon:GetFullName()
        task.wait()

        statusValue.Text = "Analisando compras..."
        local okPurchases, purchases = pcall(ScanPurchases)
        purchases = okPurchases and purchases or {}
        purchasesValue.Text = okPurchases and tostring(#purchases) or "Erro"
        task.wait()

        if not Alive or CurrentPage ~= "Scanner" or version ~= PageVersion then
            return
        end

        statusValue.Text = "Analisando coletores..."
        local okCollectors, collectors = pcall(ScanCollectors)
        collectors = okCollectors and collectors or {}
        collectorsValue.Text = okCollectors and tostring(#collectors) or "Erro"
        task.wait()

        statusValue.Text = "Analisando droppers..."
        local okDroppers, droppers = pcall(ScanDroppers)
        droppers = okDroppers and droppers or {}
        droppersValue.Text = okDroppers and tostring(#droppers) or "Erro"
        task.wait()

        statusValue.Text = "Analisando upgrades..."
        local okUpgrades, upgrades = pcall(ScanUpgrades)
        upgrades = okUpgrades and upgrades or {}
        upgradesValue.Text = okUpgrades and tostring(#upgrades) or "Erro"
        task.wait()

        statusValue.Text = "Analisando ferramentas..."
        local okTools, tools = pcall(ScanTools)
        tools = okTools and tools or {}
        toolsValue.Text = okTools and tostring(#tools) or "Erro"
        task.wait()

        LatestReport = {
            generatedBy = "CAFEINA TYCOON V3.2",
            player = Player.Name,
            userId = Player.UserId,
            tycoon = tycoon:GetFullName(),
            action = Runtime.Action,
            purchases = {},
            collectors = {},
            droppers = {},
            upgrades = {},
            tools = {},
        }

        for _, item in ipairs(purchases) do
            table.insert(LatestReport.purchases, {
                name = item.Name,
                display = item.Display,
                price = item.Price,
                touch = item.Touch and item.Touch:GetFullName() or "",
            })
        end

        for _, item in ipairs(collectors) do
            table.insert(LatestReport.collectors, {
                name = item.Name,
                touch = item.Touch and item.Touch:GetFullName() or "",
            })
        end

        for _, item in ipairs(droppers) do
            table.insert(LatestReport.droppers, {
                name = item.Name,
                value = item.Value,
                rate = item.Rate,
                replicatedRate = item.ReplicatedRate,
            })
        end

        for _, item in ipairs(upgrades) do
            table.insert(LatestReport.upgrades, {
                name = item.Name,
                increase = item.Increase,
            })
        end

        for _, item in ipairs(tools) do
            table.insert(LatestReport.tools, {
                name = item.Name,
                location = item.Location,
            })
        end

        statusValue.Text = "Pronto para copiar"
        SetAction("Scanner concluído")
    end)
end

Nav("Principal", "⌂")
Nav("Compras", "🛒")
Nav("Coleta", "💰")
Nav("Produção", "⚙")
Nav("Upgrades", "⬆")
Nav("Progresso", "★")
Nav("Itens", "◆")
Nav("Movimento", "➤")
Nav("Scanner", "⌕")

--==============================================================--
-- AUTO BUY / AUTO COLLECT
--==============================================================--

task.spawn(function()
    while Alive and GUI.Parent do
        if Config.AutoBuy and not Runtime.Busy and IsAlive() then
            local purchases = ScanPurchases()
            local item = purchases[1]

            if item and item.Touch and item.Touch.Parent then
                BuyItem(item)
                task.wait(Config.AutoBuyDelay)
            else
                SetAction("Aguardando próxima compra")
                task.wait(0.35)
            end
        else
            task.wait(0.20)
        end
    end
end)

task.spawn(function()
    while Alive and GUI.Parent do
        if Config.AutoCollect and not Runtime.Busy and IsAlive() then
            local collectors = ScanCollectors()
            local item = collectors[1]

            if item and item.Touch and item.Touch.Parent then
                CollectItem(item)
            end
        end

        task.wait(Config.AutoCollect and Config.AutoCollectDelay or 0.40)
    end
end)

--==============================================================--
-- WALK SPEED / NOCLIP
--==============================================================--

Connect(RunService.Heartbeat, function()
    if not IsAlive() then
        return
    end

    if Config.WalkSpeedEnabled and Humanoid.WalkSpeed ~= Config.WalkSpeed then
        Humanoid.WalkSpeed = Config.WalkSpeed
    end
end)

Connect(RunService.Stepped, function()
    if not Character or not Character.Parent then
        return
    end

    if Config.Noclip then
        for _, object in ipairs(Character:GetDescendants()) do
            if object:IsA("BasePart") then
                if CollisionCache[object] == nil then
                    CollisionCache[object] = object.CanCollide
                end
                object.CanCollide = false
            end
        end
    end
end)

--==============================================================--
-- FLY MOBILE CORRIGIDO
--==============================================================--

Connect(RunService.RenderStepped, function()
    if not Config.Fly then
        if FlyVelocity or FlyGyro then
            DestroyFlyObjects()
        end
        return
    end

    if not EnsureFlyObjects() then
        return
    end

    Humanoid.PlatformStand = true

    local horizontal = Humanoid.MoveDirection
    local vertical = 0

    if Config.FlyUp then
        vertical = vertical + 1
    end
    if Config.FlyDown then
        vertical = vertical - 1
    end

    FlyVelocity.Velocity = Vector3.new(
        horizontal.X * Config.FlySpeed,
        vertical * Config.FlySpeed,
        horizontal.Z * Config.FlySpeed
    )

    local camera = workspace.CurrentCamera
    if camera then
        local look = camera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.01 then
            FlyGyro.CFrame = CFrame.lookAt(Root.Position, Root.Position + flat.Unit)
        end
    end
end)

Connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.Space then
        Config.FlyUp = true
    elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
        Config.FlyDown = true
    end
end)

Connect(UserInputService.InputEnded, function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        Config.FlyUp = false
    elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
        Config.FlyDown = false
    end
end)

--==============================================================--
-- BOTÕES FLY MOBILE
--==============================================================--

local FlyControls = Instance.new("Frame")
FlyControls.Size = UDim2.fromOffset(58, 126)
FlyControls.Position = UDim2.new(1, -72, 0.5, -63)
FlyControls.BackgroundTransparency = 1
FlyControls.Visible = false
FlyControls.Parent = GUI

local function FlyButton(text, y)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(54, 54)
    button.Position = UDim2.fromOffset(0, y)
    button.BackgroundColor3 = Color3.fromRGB(105, 22, 33)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 18
    button.Parent = FlyControls
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)
    return button
end

local UpButton = FlyButton("▲", 0)
local DownButton = FlyButton("▼", 64)

local function Hold(button, field)
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            Config[field] = true
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            Config[field] = false
        end
    end)
end

Hold(UpButton, "FlyUp")
Hold(DownButton, "FlyDown")

task.spawn(function()
    while Alive and GUI.Parent do
        FlyControls.Visible = Config.Fly
        task.wait(0.10)
    end
end)

--==============================================================--
-- ÍCONE MINIMIZADO
--==============================================================--

local Mini = Instance.new("TextButton")
Mini.Size = UDim2.fromOffset(54, 54)
Mini.Position = UDim2.new(0.5, -27, 0.5, -27)
Mini.BackgroundColor3 = Color3.fromRGB(120, 20, 31)
Mini.BorderSizePixel = 0
Mini.Text = "C"
Mini.TextColor3 = Color3.new(1, 1, 1)
Mini.Font = Enum.Font.GothamBlack
Mini.TextSize = 21
Mini.Visible = false
Mini.Active = true
Mini.Parent = GUI
Instance.new("UICorner", Mini).CornerRadius = UDim.new(1, 0)

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Color3.fromRGB(225, 42, 55)
MiniStroke.Thickness = 1.4
MiniStroke.Parent = Mini

--==============================================================--
-- DRAG ROBUSTO • TOUCH + MOUSE • TAP != DRAG
--==============================================================--

local function ClampToScreen(target, x, y)
    local camera = workspace.CurrentCamera
    if not camera then
        return x, y
    end

    local viewport = camera.ViewportSize
    local size = target.AbsoluteSize

    local maxX = math.max(0, viewport.X - size.X)
    local maxY = math.max(0, viewport.Y - size.Y)

    return math.clamp(x, 0, maxX), math.clamp(y, 0, maxY)
end

local function MakeDraggable(handle, target, onTap)
    local dragging = false
    local moved = false
    local activeInput = nil
    local startPointer = nil
    local startAbsolute = nil
    local threshold = 7

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        dragging = true
        moved = false
        activeInput = input
        startPointer = Vector2.new(input.Position.X, input.Position.Y)
        startAbsolute = target.AbsolutePosition
    end)

    Connect(UserInputService.InputChanged, function(input)
        if not dragging or not startPointer or not startAbsolute then
            return
        end

        local valid = false

        if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
            valid = input == activeInput
        elseif activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1 then
            valid = input.UserInputType == Enum.UserInputType.MouseMovement
        end

        if not valid then
            return
        end

        local pointer = Vector2.new(input.Position.X, input.Position.Y)
        local delta = pointer - startPointer

        if delta.Magnitude >= threshold then
            moved = true
        end

        local x, y = ClampToScreen(target, startAbsolute.X + delta.X, startAbsolute.Y + delta.Y)
        target.Position = UDim2.fromOffset(x, y)
    end)

    Connect(UserInputService.InputEnded, function(input)
        if not dragging then
            return
        end

        local finished = false
        if activeInput and activeInput.UserInputType == Enum.UserInputType.Touch then
            finished = input == activeInput
        elseif activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1 then
            finished = input.UserInputType == Enum.UserInputType.MouseButton1
        end

        if not finished then
            return
        end

        local wasMoved = moved
        dragging = false
        moved = false
        activeInput = nil
        startPointer = nil
        startAbsolute = nil

        if not wasMoved and onTap then
            onTap()
        end
    end)
end

MakeDraggable(DragArea, Main)
MakeDraggable(Mini, Mini, function()
    Mini.Visible = false
    Main.Visible = true
end)

Minimize.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

--==============================================================--
-- FECHAR / RESTAURAR ESTADO
--==============================================================--

local function Shutdown()
    if not Alive then
        return
    end

    Alive = false

    Config.AutoBuy = false
    Config.AutoCollect = false
    Config.Fly = false
    Config.Noclip = false
    Config.WalkSpeedEnabled = false

    DestroyFlyObjects()
    RestoreCollisions()

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.WalkSpeed = DefaultWalkSpeed
            Humanoid.PlatformStand = false
        end)
    end

    DisconnectBucket(CharacterConnections)
    DisconnectBucket(Connections)

    if GUI and GUI.Parent then
        GUI:Destroy()
    end
end

Close.Activated:Connect(Shutdown)

--==============================================================--
-- START
--==============================================================--

task.delay(0.12, function()
    if not Alive or not GUI.Parent then
        return
    end

    local ok, err = pcall(function()
        OpenPage("Principal")
    end)

    if not ok then
        warn("[CAFEÍNA V3.2] Falha ao abrir Principal:", err)
    end
end)

print("[CAFEÍNA V3.2] GUI criada; carregamento assíncrono iniciado")
