--==============================================================--
--                  CAFEÍNA V2 • TYCOON
--             MOBILE / COMPRA / COLETA / ANALYZER
--==============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIG
--==============================================================--

local Config = {
    AutoBuyDelay = 0.8,
    AutoCollectDelay = 1.2,

    WalkSpeed = 28,
    FlySpeed = 55,

    AutoBuy = false,
    AutoCollect = false,
    WalkSpeedEnabled = false,
    Noclip = false,
    Fly = false
}

local Character
local Humanoid
local Root

local Connections = {}

--==============================================================--
-- CHARACTER
--==============================================================--

local function LoadCharacter()
    Character = Player.Character or Player.CharacterAdded:Wait()
    Humanoid = Character:WaitForChild("Humanoid")
    Root = Character:WaitForChild("HumanoidRootPart")
end

LoadCharacter()

Player.CharacterAdded:Connect(function()
    task.wait(1)
    LoadCharacter()
end)

--==============================================================--
-- HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, search)
    return string.find(lower(text), lower(search), 1, true) ~= nil
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

    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function tp(part, offset)

    if not Root or not part then
        return false
    end

    offset = offset or Vector3.new(0,3,0)

    Root.CFrame = part.CFrame + offset

    return true
end

--==============================================================--
-- TYCOON DETECTION
--==============================================================--

local function GetTycoonRoot()

    local tycoons = workspace:FindFirstChild("Tycoons")

    if not tycoons then
        return nil
    end

    ------------------------------------------------------------
    -- Procura modelo/pasta com UserId
    ------------------------------------------------------------

    for _,obj in ipairs(tycoons:GetDescendants()) do

        if tostring(obj.Name) == tostring(Player.UserId) then

            if obj:IsA("Model") or obj:IsA("Folder") then
                return obj
            end
        end
    end

    ------------------------------------------------------------
    -- Procura nome do player em SurfaceGui / BillboardGui
    ------------------------------------------------------------

    for _,label in ipairs(tycoons:GetDescendants()) do

        if label:IsA("TextLabel") then

            local text = lower(label.Text)

            if text == lower(Player.Name)
            or text == lower(Player.DisplayName) then

                local current = label

                while current and current ~= workspace do

                    if tostring(current.Name) == tostring(Player.UserId) then
                        return current
                    end

                    current = current.Parent
                end
            end
        end
    end

    ------------------------------------------------------------
    -- fallback
    ------------------------------------------------------------

    local plot = tycoons:FindFirstChild("Plot")

    if plot then

        local tycoon = plot:FindFirstChild("Tycoon")

        if tycoon then

            local playerModel =
                tycoon:FindFirstChild(tostring(Player.UserId))

            if playerModel then
                return playerModel
            end
        end
    end

    return nil
end

--==============================================================--
-- PURCHASE SCANNER
--==============================================================--

local function ScanPurchases()

    local tycoon = GetTycoonRoot()

    if not tycoon then
        return {}
    end

    local results = {}
    local seen = {}

    ------------------------------------------------------------
    -- Estrutura principal encontrada:
    --
    -- Purchase
    --   Button
    --      BypassAnim_Touch
    ------------------------------------------------------------

    for _,obj in ipairs(tycoon:GetDescendants()) do

        if obj:IsA("BasePart")
        and obj.Name == "BypassAnim_Touch" then

            local button = obj.Parent
            local purchase = button and button.Parent

            if purchase then

                local path = purchase:GetFullName()

                if not seen[path] then

                    seen[path] = true

                    table.insert(results,{
                        Name = purchase.Name,
                        Object = purchase,
                        Touch = obj
                    })
                end
            end
        end
    end

    ------------------------------------------------------------
    -- fallback: objetos chamados Button
    ------------------------------------------------------------

    for _,obj in ipairs(tycoon:GetDescendants()) do

        if obj.Name == "Button"
        and (obj:IsA("Model") or obj:IsA("Folder")) then

            local touch = getPart(obj)

            if touch then

                local purchase = obj.Parent

                if purchase then

                    local path = purchase:GetFullName()

                    if not seen[path] then

                        seen[path] = true

                        table.insert(results,{
                            Name = purchase.Name,
                            Object = purchase,
                            Touch = touch
                        })
                    end
                end
            end
        end
    end

    table.sort(results,function(a,b)
        return lower(a.Name) < lower(b.Name)
    end)

    return results
end

--==============================================================--
-- COLLECTOR
--==============================================================--

local function ScanCollectors()

    local tycoon = GetTycoonRoot()

    if not tycoon then
        return {}
    end

    local found = {}
    local seen = {}

    for _,obj in ipairs(tycoon:GetDescendants()) do

        if contains(obj.Name,"collect points")
        or lower(obj.Name) == "collector"
        or lower(obj.Name) == "collect" then

            local target =
                obj:FindFirstChild("Touch",true)
                or getPart(obj)

            if target and target:IsA("BasePart") then

                local path = target:GetFullName()

                if not seen[path] then

                    seen[path] = true

                    table.insert(found,{
                        Name = obj.Name,
                        Object = obj,
                        Touch = target
                    })
                end
            end
        end
    end

    return found
end

--==============================================================--
-- DROPPERS
--==============================================================--

local function ScanDroppers()

    local tycoon = GetTycoonRoot()

    if not tycoon then
        return {}
    end

    local result = {}
    local seen = {}

    for _,obj in ipairs(tycoon:GetDescendants()) do

        if (obj:IsA("Model") or obj:IsA("Folder"))
        and contains(obj.Name,"dropper") then

            if not seen[obj] then

                seen[obj] = true

                local stats =
                    obj:FindFirstChild("Stats")

                local info = {
                    Name = obj.Name,
                    Value = "?",
                    Rate = "?",
                    ReplicatedRate = "?"
                }

                if stats then

                    local default =
                        stats:FindFirstChild("DefaultValue")

                    local rate =
                        stats:FindFirstChild("ProductionRate")

                    local replicated =
                        stats:FindFirstChild("ReplicatedProductionRate")

                    if default and default:IsA("ValueBase") then
                        info.Value = tostring(default.Value)
                    end

                    if rate and rate:IsA("ValueBase") then
                        info.Rate = tostring(rate.Value)
                    end

                    if replicated and replicated:IsA("ValueBase") then
                        info.ReplicatedRate =
                            tostring(replicated.Value)
                    end
                end

                table.insert(result,info)
            end
        end
    end

    table.sort(result,function(a,b)
        return lower(a.Name) < lower(b.Name)
    end)

    return result
end

--==============================================================--
-- UPGRADERS / REFINERS
--==============================================================--

local function ScanUpgrades()

    local tycoon = GetTycoonRoot()

    if not tycoon then
        return {}
    end

    local result = {}
    local seen = {}

    for _,obj in ipairs(tycoon:GetDescendants()) do

        if obj:IsA("Model") or obj:IsA("Folder") then

            local name = lower(obj.Name)

            if contains(name,"upgrader")
            or contains(name,"refiner")
            or contains(name,"conveyor") then

                if not seen[obj] then

                    seen[obj] = true

                    local valueIncrease = "?"

                    local stats =
                        obj:FindFirstChild("Stats")

                    if stats then

                        local increase =
                            stats:FindFirstChild(
                                "ValueIncrease"
                            )

                        if increase
                        and increase:IsA("ValueBase") then

                            valueIncrease =
                                tostring(increase.Value)
                        end
                    end

                    table.insert(result,{
                        Name = obj.Name,
                        Increase = valueIncrease,
                        Object = obj
                    })
                end
            end
        end
    end

    table.sort(result,function(a,b)
        return lower(a.Name) < lower(b.Name)
    end)

    return result
end

--==============================================================--
-- TOOLS
--==============================================================--

local function ScanTools()

    local tools = {}

    local function scan(container)

        if not container then return end

        for _,obj in ipairs(container:GetChildren()) do

            if obj:IsA("Tool") then

                table.insert(tools,{
                    Name = obj.Name,
                    Object = obj,
                    Location = container.Name
                })
            end
        end
    end

    scan(Player:FindFirstChild("Backpack"))
    scan(Character)
    scan(Player:FindFirstChild("StarterGear"))

    return tools
end

--==============================================================--
-- REBIRTH DATA
--==============================================================--

local function ReadRebirth()

    local data = {
        State = "Desconhecido",
        Count = "?",
        Reward = "",
        Message = ""
    }

    local ui = PlayerGui:FindFirstChild("UI")

    if not ui then
        return data
    end

    local base =
        ui:FindFirstChild("Base")

    if not base then
        return data
    end

    local menu =
        base:FindFirstChild("RebirthMenu")

    if not menu then
        return data
    end

    local locked =
        menu:FindFirstChild("Locked",true)

    local ready =
        menu:FindFirstChild("Ready",true)

    if ready
    and ready:IsA("GuiObject")
    and ready.Visible then

        data.State = "PRONTO"

    elseif locked
    and locked:IsA("GuiObject")
    and locked.Visible then

        data.State = "BLOQUEADO"
    end

    local container =
        data.State == "PRONTO"
        and ready
        or locked

    if container then

        local count =
            container:FindFirstChild("Count",true)

        local rewards =
            container:FindFirstChild("Rewards",true)

        local body =
            container:FindFirstChild("Body",true)

        if count and count:IsA("TextLabel") then
            data.Count = count.Text
        end

        if rewards and rewards:IsA("TextLabel") then
            data.Reward = rewards.Text
        end

        if body and body:IsA("TextLabel") then
            data.Message = body.Text
        end
    end

    return data
end

--==============================================================--
-- TOUCH
--==============================================================--

local function TouchPurchase(part)

    if not part or not Root then
        return
    end

    ------------------------------------------------------------
    -- Quando o ambiente oferece firetouchinterest
    ------------------------------------------------------------

    if firetouchinterest then

        pcall(function()

            firetouchinterest(Root,part,0)

            task.wait(0.08)

            firetouchinterest(Root,part,1)
        end)

        return
    end

    ------------------------------------------------------------
    -- fallback universal
    ------------------------------------------------------------

    tp(part,Vector3.new(0,2,0))
end

--==============================================================--
-- GUI
--==============================================================--

local old =
    PlayerGui:FindFirstChild("CafeinaTycoonV2")

if old then
    old:Destroy()
end

local GUI = Instance.new("ScreenGui")
GUI.Name = "CafeinaTycoonV2"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = false
GUI.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(430,380)
Main.Position = UDim2.new(.5,-215,.5,-190)
Main.BackgroundColor3 = Color3.fromRGB(15,15,19)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = GUI

Instance.new("UICorner",Main).CornerRadius =
    UDim.new(0,14)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(185,30,42)
mainStroke.Thickness = 1.4
mainStroke.Parent = Main

--==============================================================--
-- RESPONSIVE MOBILE SCALE
--==============================================================--

local Scale = Instance.new("UIScale")
Scale.Parent = Main

local function UpdateScale()

    local camera = workspace.CurrentCamera

    if not camera then return end

    local width =
        camera.ViewportSize.X

    if width < 500 then
        Scale.Scale = math.clamp(
            width / 470,
            0.72,
            0.93
        )
    else
        Scale.Scale = 1
    end
end

UpdateScale()

workspace.CurrentCamera
:GetPropertyChangedSignal("ViewportSize")
:Connect(UpdateScale)

--==============================================================--
-- HEADER
--==============================================================--

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1,0,0,54)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.fromOffset(38,38)
Logo.Position = UDim2.fromOffset(10,8)
Logo.BackgroundColor3 = Color3.fromRGB(125,20,30)
Logo.Text = "C"
Logo.TextColor3 = Color3.new(1,1,1)
Logo.Font = Enum.Font.GothamBlack
Logo.TextSize = 19
Logo.Parent = Header

Instance.new("UICorner",Logo).CornerRadius =
    UDim.new(0,10)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.fromOffset(57,7)
Title.Size = UDim2.new(1,-150,0,24)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA V2"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = Color3.fromRGB(245,245,248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Sub = Instance.new("TextLabel")
Sub.Position = UDim2.fromOffset(57,29)
Sub.Size = UDim2.new(1,-150,0,17)
Sub.BackgroundTransparency = 1
Sub.Text = "TYCOON • MOBILE"
Sub.Font = Enum.Font.GothamMedium
Sub.TextSize = 10
Sub.TextColor3 = Color3.fromRGB(135,135,145)
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(35,35)
Minimize.Position = UDim2.new(1,-81,0,9)
Minimize.BackgroundColor3 = Color3.fromRGB(37,37,43)
Minimize.Text = "−"
Minimize.TextColor3 = Color3.new(1,1,1)
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 20
Minimize.BorderSizePixel = 0
Minimize.Parent = Header

Instance.new("UICorner",Minimize).CornerRadius =
    UDim.new(0,9)

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(35,35)
Close.Position = UDim2.new(1,-41,0,9)
Close.BackgroundColor3 = Color3.fromRGB(115,20,28)
Close.Text = "×"
Close.TextColor3 = Color3.new(1,1,1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 20
Close.BorderSizePixel = 0
Close.Parent = Header

Instance.new("UICorner",Close).CornerRadius =
    UDim.new(0,9)

--==============================================================--
-- SIDEBAR
--==============================================================--

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Position = UDim2.fromOffset(9,60)
Sidebar.Size = UDim2.new(0,120,1,-69)
Sidebar.BackgroundColor3 = Color3.fromRGB(20,20,25)
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 2
Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
Sidebar.CanvasSize = UDim2.new()
Sidebar.Parent = Main

Instance.new("UICorner",Sidebar).CornerRadius =
    UDim.new(0,11)

local sidePadding = Instance.new("UIPadding")
sidePadding.PaddingTop = UDim.new(0,7)
sidePadding.PaddingLeft = UDim.new(0,6)
sidePadding.PaddingRight = UDim.new(0,6)
sidePadding.PaddingBottom = UDim.new(0,7)
sidePadding.Parent = Sidebar

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0,5)
sideLayout.Parent = Sidebar

--==============================================================--
-- CONTENT
--==============================================================--

local Content = Instance.new("ScrollingFrame")
Content.Position = UDim2.fromOffset(137,60)
Content.Size = UDim2.new(1,-146,1,-69)
Content.BackgroundColor3 = Color3.fromRGB(20,20,25)
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.CanvasSize = UDim2.new()
Content.Parent = Main

Instance.new("UICorner",Content).CornerRadius =
    UDim.new(0,11)

local ContentPadding = Instance.new("UIPadding")
ContentPadding.PaddingTop = UDim.new(0,9)
ContentPadding.PaddingLeft = UDim.new(0,9)
ContentPadding.PaddingRight = UDim.new(0,9)
ContentPadding.PaddingBottom = UDim.new(0,15)
ContentPadding.Parent = Content

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0,7)
ContentLayout.Parent = Content

--==============================================================--
-- COMPONENTS
--==============================================================--

local function clear()

    for _,obj in ipairs(Content:GetChildren()) do

        if obj ~= ContentLayout
        and obj ~= ContentPadding then
            obj:Destroy()
        end
    end

    Content.CanvasPosition =
        Vector2.new(0,0)
end

local function label(text,size)

    local l = Instance.new("TextLabel")

    l.Size = UDim2.new(1,-2,0,size or 32)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextWrapped = true
    l.TextColor3 = Color3.fromRGB(195,195,204)
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = Content

    return l
end

local function heading(text)

    local l = label(text,34)

    l.Font = Enum.Font.GothamBold
    l.TextSize = 17
    l.TextColor3 = Color3.fromRGB(245,245,248)

    return l
end

local function button(text,callback)

    local b = Instance.new("TextButton")

    b.Size = UDim2.new(1,-2,0,44)
    b.BackgroundColor3 = Color3.fromRGB(31,31,38)
    b.BorderSizePixel = 0
    b.Text = "  "..text
    b.TextColor3 = Color3.fromRGB(236,236,241)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = Content

    Instance.new("UICorner",b).CornerRadius =
        UDim.new(0,9)

    b.MouseButton1Click:Connect(callback)

    return b
end

local function infoCard(title,value)

    local card = Instance.new("Frame")

    card.Size = UDim2.new(1,-2,0,52)
    card.BackgroundColor3 = Color3.fromRGB(28,28,34)
    card.BorderSizePixel = 0
    card.Parent = Content

    Instance.new("UICorner",card).CornerRadius =
        UDim.new(0,9)

    local t = Instance.new("TextLabel")
    t.Position = UDim2.fromOffset(10,6)
    t.Size = UDim2.new(1,-20,0,17)
    t.BackgroundTransparency = 1
    t.Text = title
    t.TextColor3 = Color3.fromRGB(145,145,155)
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 10
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = card

    local v = Instance.new("TextLabel")
    v.Position = UDim2.fromOffset(10,23)
    v.Size = UDim2.new(1,-20,0,22)
    v.BackgroundTransparency = 1
    v.Text = tostring(value)
    v.TextColor3 = Color3.fromRGB(240,240,245)
    v.Font = Enum.Font.GothamBold
    v.TextSize = 13
    v.TextXAlignment = Enum.TextXAlignment.Left
    v.Parent = card

    return card
end

local function toggle(text,state,callback)

    local b

    local function redraw()
        b.Text =
            "  "..text..
            (state()
                and "                         ON"
                or "                         OFF")

        b.BackgroundColor3 =
            state()
            and Color3.fromRGB(110,24,34)
            or Color3.fromRGB(31,31,38)
    end

    b = button(text,function()

        callback()

        redraw()
    end)

    redraw()

    return b
end

local function slider(
    title,
    minimum,
    maximum,
    getValue,
    setValue
)

    local frame = Instance.new("Frame")

    frame.Size = UDim2.new(1,-2,0,65)
    frame.BackgroundColor3 = Color3.fromRGB(28,28,34)
    frame.BorderSizePixel = 0
    frame.Parent = Content

    Instance.new("UICorner",frame).CornerRadius =
        UDim.new(0,9)

    local titleLabel = Instance.new("TextLabel")

    titleLabel.Position = UDim2.fromOffset(10,6)
    titleLabel.Size = UDim2.new(1,-20,0,20)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.TextColor3 = Color3.fromRGB(230,230,235)
    titleLabel.TextSize = 12
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = frame

    local bar = Instance.new("Frame")

    bar.Position = UDim2.new(0,10,1,-22)
    bar.Size = UDim2.new(1,-20,0,8)
    bar.BackgroundColor3 = Color3.fromRGB(50,50,57)
    bar.BorderSizePixel = 0
    bar.Parent = frame

    Instance.new("UICorner",bar).CornerRadius =
        UDim.new(1,0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0,1)
    fill.BackgroundColor3 = Color3.fromRGB(175,28,42)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    Instance.new("UICorner",fill).CornerRadius =
        UDim.new(1,0)

    local dragging = false

    local function updateFromX(x)

        local percent =
            math.clamp(
                (x-bar.AbsolutePosition.X)
                /bar.AbsoluteSize.X,
                0,
                1
            )

        local value =
            math.floor(
                minimum
                +(maximum-minimum)*percent
            )

        setValue(value)

        fill.Size =
            UDim2.fromScale(percent,1)

        titleLabel.Text =
            title.." • "..tostring(value)
    end

    local function redraw()

        local value = getValue()

        local percent =
            (value-minimum)
            /(maximum-minimum)

        fill.Size =
            UDim2.fromScale(
                math.clamp(percent,0,1),
                1
            )

        titleLabel.Text =
            title.." • "..tostring(value)
    end

    bar.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = true

            updateFromX(input.Position.X)
        end
    end)

    UIS.InputChanged:Connect(function(input)

        if dragging
        and (
            input.UserInputType
                == Enum.UserInputType.Touch
            or input.UserInputType
                == Enum.UserInputType.MouseMovement
        ) then

            updateFromX(input.Position.X)
        end
    end)

    UIS.InputEnded:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = false
        end
    end)

    redraw()
end

--==============================================================--
-- PAGE REGISTRY
--==============================================================--

local Pages = {}

local currentPage

local function OpenPage(name)

    currentPage = name

    if Pages[name] then
        Pages[name]()
    end
end

local function nav(name,icon)

    local b = Instance.new("TextButton")

    b.Size = UDim2.new(1,0,0,39)
    b.BackgroundColor3 = Color3.fromRGB(29,29,35)
    b.BorderSizePixel = 0
    b.Text =
        " "..icon.."  "..name
    b.TextColor3 = Color3.fromRGB(215,215,222)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = Sidebar

    Instance.new("UICorner",b).CornerRadius =
        UDim.new(0,8)

    b.MouseButton1Click:Connect(function()
        OpenPage(name)
    end)
end

--==============================================================--
-- PRINCIPAL
--==============================================================--

Pages["Principal"] = function()

    clear()

    heading("CAFEÍNA • TYCOON")

    local tycoon = GetTycoonRoot()
    local buys = ScanPurchases()
    local collectors = ScanCollectors()
    local droppers = ScanDroppers()
    local upgrades = ScanUpgrades()
    local rebirth = ReadRebirth()

    infoCard(
        "TYCOON",
        tycoon and tycoon.Name
        or "Não detectado"
    )

    infoCard(
        "COMPRAS DISPONÍVEIS",
        #buys
    )

    infoCard(
        "COLETORES",
        #collectors
    )

    infoCard(
        "DROPPERS",
        #droppers
    )

    infoCard(
        "UPGRADERS / REFINERS",
        #upgrades
    )

    infoCard(
        "REBIRTH",
        rebirth.State
    )

    button("🛒 ABRIR COMPRAS",function()
        OpenPage("Compras")
    end)

    button("💰 ABRIR COLETA",function()
        OpenPage("Coleta")
    end)
end

--==============================================================--
-- COMPRAS
--==============================================================--

Pages["Compras"] = function()

    clear()

    heading("Compras")

    local purchases =
        ScanPurchases()

    infoCard(
        "Encontradas",
        #purchases
    )

    toggle(
        "AUTO COMPRA",
        function()
            return Config.AutoBuy
        end,
        function()
            Config.AutoBuy =
                not Config.AutoBuy
        end
    )

    button("🔄 ATUALIZAR LISTA",function()
        OpenPage("Compras")
    end)

    if #purchases == 0 then
        label("Nenhum botão disponível.")
        return
    end

    for i,item in ipairs(purchases) do

        button(
            "🛒 "..i..". "..item.Name,
            function()

                if item.Touch
                and item.Touch.Parent then

                    TouchPurchase(
                        item.Touch
                    )
                end
            end
        )
    end
end

--==============================================================--
-- COLETA
--==============================================================--

Pages["Coleta"] = function()

    clear()

    heading("Coleta")

    local collectors =
        ScanCollectors()

    infoCard(
        "Coletores encontrados",
        #collectors
    )

    toggle(
        "AUTO COLETA",
        function()
            return Config.AutoCollect
        end,
        function()
            Config.AutoCollect =
                not Config.AutoCollect
        end
    )

    button("💰 COLETAR AGORA",function()

        local list =
            ScanCollectors()

        if list[1] then
            TouchPurchase(
                list[1].Touch
            )
        end
    end)

    button("🔄 LOCALIZAR NOVAMENTE",function()
        OpenPage("Coleta")
    end)

    for i,item in ipairs(collectors) do

        button(
            "📍 "..i..". "..item.Name,
            function()
                tp(item.Touch)
            end
        )
    end
end

--==============================================================--
-- PRODUÇÃO
--==============================================================--

Pages["Produção"] = function()

    clear()

    heading("Produção")

    local list =
        ScanDroppers()

    infoCard(
        "Droppers detectados",
        #list
    )

    for _,item in ipairs(list) do

        local text =
            item.Name..
            "\nValor: "..item.Value..
            " • Rate: "..item.Rate..
            " • Rep: "..item.ReplicatedRate

        local b =
            button("⚙ "..text,function() end)

        b.Size =
            UDim2.new(1,-2,0,57)

        b.TextWrapped = true
    end
end

--==============================================================--
-- UPGRADES
--==============================================================--

Pages["Upgrades"] = function()

    clear()

    heading("Upgraders / Refiners")

    local list =
        ScanUpgrades()

    infoCard(
        "Detectados",
        #list
    )

    for _,item in ipairs(list) do

        local text =
            "⬆ "..item.Name

        if item.Increase ~= "?" then
            text =
                text..
                " • +"..
                item.Increase
        end

        button(text,function()

            local part =
                getPart(item.Object)

            if part then
                tp(part)
            end
        end)
    end
end

--==============================================================--
-- PROGRESSO
--==============================================================--

Pages["Progresso"] = function()

    clear()

    heading("Progressão")

    local data =
        ReadRebirth()

    infoCard(
        "Estado do Rebirth",
        data.State
    )

    label(
        data.Count ~= ""
        and data.Count
        or "Contagem indisponível",
        48
    )

    if data.Reward ~= "" then

        local clean =
            data.Reward
            :gsub("<.->","")

        label(
            clean,
            52
        )
    end

    if data.Message ~= "" then

        label(
            data.Message:gsub("<.->",""),
            70
        )
    end

    button("🔄 ATUALIZAR",function()
        OpenPage("Progresso")
    end)
end

--==============================================================--
-- ITENS
--==============================================================--

Pages["Itens"] = function()

    clear()

    heading("Itens")

    local tools =
        ScanTools()

    infoCard(
        "Tools detectadas",
        #tools
    )

    for _,tool in ipairs(tools) do

        button(
            "🗡 "..tool.Name..
            " • "..tool.Location,
            function()

                if Humanoid
                and tool.Object.Parent
                    == Player.Backpack then

                    Humanoid:EquipTool(
                        tool.Object
                    )
                end
            end
        )
    end
end

--==============================================================--
-- MOVIMENTO
--==============================================================--

Pages["Movimento"] = function()

    clear()

    heading("Movimento")

    toggle(
        "NOCLIP",
        function()
            return Config.Noclip
        end,
        function()
            Config.Noclip =
                not Config.Noclip
        end
    )

    toggle(
        "FLY",
        function()
            return Config.Fly
        end,
        function()
            Config.Fly =
                not Config.Fly
        end
    )

    slider(
        "Fly Speed",
        10,
        180,
        function()
            return Config.FlySpeed
        end,
        function(v)
            Config.FlySpeed = v
        end
    )

    toggle(
        "WALK SPEED",
        function()
            return Config.WalkSpeedEnabled
        end,
        function()
            Config.WalkSpeedEnabled =
                not Config.WalkSpeedEnabled
        end
    )

    slider(
        "Walk Speed",
        16,
        100,
        function()
            return Config.WalkSpeed
        end,
        function(v)
            Config.WalkSpeed = v
        end
    )

    button("🏠 IR PARA MEU TYCOON",function()

        local tycoon =
            GetTycoonRoot()

        local spawn

        if tycoon then
            spawn =
                tycoon:FindFirstChild(
                    "Spawn",
                    true
                )
        end

        local part =
            getPart(spawn)
            or getPart(tycoon)

        if part then
            tp(part)
        end
    end)

    button("💰 IR PARA COLETOR",function()

        local list =
            ScanCollectors()

        if list[1] then
            tp(list[1].Touch)
        end
    end)
end

--==============================================================--
-- SCANNER
--==============================================================--

Pages["Scanner"] = function()

    clear()

    heading("Scanner Tycoon")

    local tycoon =
        GetTycoonRoot()

    if not tycoon then

        label(
            "Tycoon não encontrado."
        )

        return
    end

    local purchases =
        ScanPurchases()

    local collectors =
        ScanCollectors()

    local droppers =
        ScanDroppers()

    local upgrades =
        ScanUpgrades()

    local tools =
        ScanTools()

    infoCard(
        "Tycoon",
        tycoon:GetFullName()
    )

    infoCard(
        "Compras",
        #purchases
    )

    infoCard(
        "Collectors",
        #collectors
    )

    infoCard(
        "Droppers",
        #droppers
    )

    infoCard(
        "Upgrades",
        #upgrades
    )

    infoCard(
        "Tools",
        #tools
    )

    button("📋 COPIAR RELATÓRIO",function()

        local report = {
            Player = Player.Name,
            UserId = Player.UserId,
            Tycoon = tycoon:GetFullName(),
            Purchases = {},
            Droppers = droppers,
            Upgrades = {},
            Tools = {}
        }

        for _,v in ipairs(purchases) do
            table.insert(
                report.Purchases,
                v.Name
            )
        end

        for _,v in ipairs(upgrades) do
            table.insert(
                report.Upgrades,
                {
                    Name = v.Name,
                    Increase = v.Increase
                }
            )
        end

        for _,v in ipairs(tools) do
            table.insert(
                report.Tools,
                {
                    Name = v.Name,
                    Location = v.Location
                }
            )
        end

        local text =
            HttpService:JSONEncode(
                report
            )

        if setclipboard then
            setclipboard(text)
        end
    end)
end

--==============================================================--
-- NAVIGATION
--==============================================================--

nav("Principal","⌂")
nav("Compras","🛒")
nav("Coleta","💰")
nav("Produção","⚙")
nav("Upgrades","⬆")
nav("Progresso","★")
nav("Itens","◆")
nav("Movimento","➤")
nav("Scanner","⌕")

--==============================================================--
-- AUTO BUY LOOP
--==============================================================--

task.spawn(function()

    while GUI.Parent do

        if Config.AutoBuy then

            local purchases =
                ScanPurchases()

            for _,item in ipairs(purchases) do

                if not Config.AutoBuy then
                    break
                end

                if item.Touch
                and item.Touch.Parent then

                    TouchPurchase(
                        item.Touch
                    )

                    task.wait(
                        Config.AutoBuyDelay
                    )
                end
            end
        end

        task.wait(1)
    end
end)

--==============================================================--
-- AUTO COLLECT LOOP
--==============================================================--

task.spawn(function()

    while GUI.Parent do

        if Config.AutoCollect then

            local collectors =
                ScanCollectors()

            for _,item in ipairs(collectors) do

                if item.Touch
                and item.Touch.Parent then

                    TouchPurchase(
                        item.Touch
                    )
                end
            end
        end

        task.wait(
            Config.AutoCollect
            and Config.AutoCollectDelay
            or 0.5
        )
    end
end)

--==============================================================--
-- WALK SPEED
--==============================================================--

RunService.Heartbeat:Connect(function()

    if Humanoid then

        if Config.WalkSpeedEnabled then

            Humanoid.WalkSpeed =
                Config.WalkSpeed

        elseif Humanoid.WalkSpeed
            ~= 16 then

            -- não força se outro sistema mudou
        end
    end
end)

--==============================================================--
-- NOCLIP
--==============================================================--

RunService.Stepped:Connect(function()

    if Config.Noclip
    and Character then

        for _,obj in ipairs(
            Character:GetDescendants()
        ) do

            if obj:IsA("BasePart") then
                obj.CanCollide = false
            end
        end
    end
end)

--==============================================================--
-- MOBILE FLY
-- MoveDirection resolve o problema do joystick:
-- direção acompanha o controle/câmera.
--==============================================================--

local FlyVelocity
local FlyGyro

local function StopFly()

    if FlyVelocity then
        FlyVelocity:Destroy()
        FlyVelocity = nil
    end

    if FlyGyro then
        FlyGyro:Destroy()
        FlyGyro = nil
    end

    if Humanoid then
        Humanoid.PlatformStand = false
    end
end

RunService.RenderStepped:Connect(function()

    if not Config.Fly then

        StopFly()

        return
    end

    if not Root
    or not Humanoid then
        return
    end

    if not FlyVelocity then

        FlyVelocity =
            Instance.new("BodyVelocity")

        FlyVelocity.MaxForce =
            Vector3.new(
                math.huge,
                math.huge,
                math.huge
            )

        FlyVelocity.P =
            10000

        FlyVelocity.Parent =
            Root
    end

    if not FlyGyro then

        FlyGyro =
            Instance.new("BodyGyro")

        FlyGyro.MaxTorque =
            Vector3.new(
                math.huge,
                math.huge,
                math.huge
            )

        FlyGyro.P =
            9000

        FlyGyro.Parent =
            Root
    end

    Humanoid.PlatformStand =
        true

    local camera =
        workspace.CurrentCamera

    local move =
        Humanoid.MoveDirection

    ------------------------------------------------------------
    -- MoveDirection já funciona com joystick mobile.
    ------------------------------------------------------------

    FlyVelocity.Velocity =
        move * Config.FlySpeed

    if camera then

        local look =
            camera.CFrame.LookVector

        FlyGyro.CFrame =
            CFrame.lookAt(
                Root.Position,
                Root.Position
                +Vector3.new(
                    look.X,
                    0,
                    look.Z
                )
            )
    end
end)

--==============================================================--
-- MINIMIZED ICON
--==============================================================--

local Mini = Instance.new("TextButton")

Mini.Size = UDim2.fromOffset(52,52)
Mini.Position = UDim2.new(.5,-26,.5,-26)
Mini.BackgroundColor3 =
    Color3.fromRGB(115,20,30)

Mini.Text = "C"
Mini.TextColor3 = Color3.new(1,1,1)
Mini.Font = Enum.Font.GothamBlack
Mini.TextSize = 21
Mini.BorderSizePixel = 0
Mini.Visible = false
Mini.Parent = GUI

Instance.new("UICorner",Mini).CornerRadius =
    UDim.new(1,0)

local miniStroke = Instance.new("UIStroke")
miniStroke.Color =
    Color3.fromRGB(220,45,55)
miniStroke.Thickness = 1.5
miniStroke.Parent = Mini

Minimize.MouseButton1Click:Connect(function()

    Main.Visible = false
    Mini.Visible = true
end)

Mini.MouseButton1Click:Connect(function()

    Mini.Visible = false
    Main.Visible = true
end)

Close.MouseButton1Click:Connect(function()

    Config.AutoBuy = false
    Config.AutoCollect = false
    Config.Fly = false
    Config.Noclip = false

    StopFly()

    GUI:Destroy()
end)

--==============================================================--
-- DRAG SYSTEM
--==============================================================--

local function MakeDraggable(object,target)

    local dragging = false
    local dragStart
    local startPosition

    object.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = true
            dragStart = input.Position
            startPosition = target.Position
        end
    end)

    UIS.InputChanged:Connect(function(input)

        if not dragging then
            return
        end

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseMovement then

            local delta =
                input.Position-dragStart

            target.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        +delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        +delta.Y
                )
        end
    end)

    UIS.InputEnded:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = false
        end
    end)
end

MakeDraggable(Header,Main)
MakeDraggable(Mini,Mini)

--==============================================================--
-- START
--==============================================================--

OpenPage("Principal")
