--[[
CAFEÍNA • AVAILABLE WEAPONS MENU V1.0
Para uso no seu próprio jogo.

- Lista dinamicamente Tools já disponíveis/visíveis ao cliente.
- Pesquisa, atualização automática e leitura de atributos.
- Ao clicar em PEGAR, usa CafeinaRequestWeapon (RemoteFunction)
  criado pelo servidor autorizado do seu jogo.
- Se a Tool já estiver no Backpack/Character, apenas equipa.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Backpack = LocalPlayer:WaitForChild("Backpack")

local REMOTE_NAME = "CafeinaRequestWeapon"
local RequestWeapon = ReplicatedStorage:FindFirstChild(REMOTE_NAME)

local GUI_NAME = "CafeinaAvailableWeapons"
local old = PlayerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local function corner(parent, r)
    local x = Instance.new("UICorner")
    x.CornerRadius = UDim.new(0, r)
    x.Parent = parent
end

local function stroke(parent, transparency)
    local x = Instance.new("UIStroke")
    x.Color = Color3.fromRGB(65,65,72)
    x.Transparency = transparency or 0.4
    x.Thickness = 1
    x.Parent = parent
end

local function safeFullName(obj)
    local ok, result = pcall(function() return obj:GetFullName() end)
    return ok and result or obj.Name
end

local function attr(tool, ...)
    for _, name in ipairs({...}) do
        local ok, value = pcall(function() return tool:GetAttribute(name) end)
        if ok and value ~= nil then return value end
    end
    return nil
end

local function looksLikeWeapon(tool)
    if not tool:IsA("Tool") then return false end

    local name = string.lower(tool.Name)
    local nonWeapons = {
        ["medkit"] = true,
        ["super potion"] = true,
    }
    if nonWeapons[name] then return false end

    if attr(tool, "damage", "Damage") ~= nil then return true end
    if attr(tool, "magazineSize", "MagSize", "_ammo") ~= nil then return true end
    if attr(tool, "fireMode", "FireMode") ~= nil then return true end
    if attr(tool, "rateOfFire", "FireRate") ~= nil then return true end
    if attr(tool, "projectileType") ~= nil then return true end

    local keywords = {
        "gun","rifle","pistol","shotgun","sniper","blaster",
        "ak","awp","barrett","famas","mp7","mp9","p90","bizon",
        "sg553","tec","ump","nova","five-seven","laser","cryo"
    }

    for _, word in ipairs(keywords) do
        if string.find(name, word, 1, true) then return true end
    end

    return false
end

local function collectAvailableWeapons()
    local result, seen = {}, {}

    local containers = {
        ReplicatedStorage,
        workspace,
        Backpack,
        LocalPlayer.Character,
    }

    for _, container in ipairs(containers) do
        if container then
            local list = {container}
            for _, obj in ipairs(container:GetDescendants()) do
                list[#list+1] = obj
            end

            for _, obj in ipairs(list) do
                if obj:IsA("Tool") and looksLikeWeapon(obj) then
                    local key = string.lower(obj.Name)
                    if not seen[key] then
                        seen[key] = true
                        result[#result+1] = {
                            name = obj.Name,
                            source = obj,
                            path = safeFullName(obj),
                            damage = attr(obj, "damage", "Damage"),
                            ammo = attr(obj, "_ammo", "magazineSize", "MagSize"),
                            magazine = attr(obj, "magazineSize", "MagSize"),
                            fireRate = attr(obj, "rateOfFire", "FireRate"),
                            range = attr(obj, "range", "Range"),
                            mode = attr(obj, "fireMode", "FireMode"),
                        }
                    end
                end
            end
        end
    end

    table.sort(result, function(a,b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return result
end

local function findOwned(name)
    local character = LocalPlayer.Character
    if character then
        local t = character:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end

    local t = Backpack:FindFirstChild(name)
    if t and t:IsA("Tool") then return t end

    return nil
end

-- GUI
local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.AnchorPoint = Vector2.new(.5,.5)
Main.Position = UDim2.fromScale(.5,.5)
Main.Size = UDim2.new(.88,0,.72,0)
Main.BackgroundColor3 = Color3.fromRGB(10,10,12)
Main.BorderSizePixel = 0
Main.Parent = Gui
corner(Main,14)
stroke(Main,.15)

local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(300,380)
constraint.MaxSize = Vector2.new(450,570)
constraint.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1,0,0,58)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Position = UDim2.fromOffset(14,10)
Logo.Size = UDim2.fromOffset(38,38)
Logo.BackgroundColor3 = Color3.fromRGB(245,245,245)
Logo.Text = "C"
Logo.TextColor3 = Color3.fromRGB(10,10,12)
Logo.TextSize = 19
Logo.Font = Enum.Font.GothamBold
Logo.Parent = Header
corner(Logo,10)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.fromOffset(62,9)
Title.Size = UDim2.new(1,-155,0,21)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA"
Title.TextColor3 = Color3.fromRGB(245,245,245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Sub = Instance.new("TextLabel")
Sub.Position = UDim2.fromOffset(62,30)
Sub.Size = UDim2.new(1,-155,0,17)
Sub.BackgroundTransparency = 1
Sub.Text = "ARMAS DISPONÍVEIS"
Sub.TextColor3 = Color3.fromRGB(140,140,150)
Sub.TextSize = 10
Sub.Font = Enum.Font.GothamMedium
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Parent = Header

local Refresh = Instance.new("TextButton")
Refresh.AnchorPoint = Vector2.new(1,0)
Refresh.Position = UDim2.new(1,-50,0,12)
Refresh.Size = UDim2.fromOffset(34,34)
Refresh.BackgroundColor3 = Color3.fromRGB(24,24,28)
Refresh.Text = "↻"
Refresh.TextColor3 = Color3.fromRGB(245,245,245)
Refresh.TextSize = 17
Refresh.Font = Enum.Font.GothamBold
Refresh.AutoButtonColor = false
Refresh.Parent = Header
corner(Refresh,9)

local Minimize = Instance.new("TextButton")
Minimize.AnchorPoint = Vector2.new(1,0)
Minimize.Position = UDim2.new(1,-10,0,12)
Minimize.Size = UDim2.fromOffset(34,34)
Minimize.BackgroundColor3 = Color3.fromRGB(24,24,28)
Minimize.Text = "−"
Minimize.TextColor3 = Color3.fromRGB(245,245,245)
Minimize.TextSize = 19
Minimize.Font = Enum.Font.GothamBold
Minimize.AutoButtonColor = false
Minimize.Parent = Header
corner(Minimize,9)

local Search = Instance.new("TextBox")
Search.Position = UDim2.fromOffset(14,61)
Search.Size = UDim2.new(1,-28,0,40)
Search.BackgroundColor3 = Color3.fromRGB(18,18,21)
Search.PlaceholderText = "Pesquisar arma..."
Search.PlaceholderColor3 = Color3.fromRGB(120,120,130)
Search.Text = ""
Search.TextColor3 = Color3.fromRGB(245,245,245)
Search.TextSize = 13
Search.Font = Enum.Font.GothamMedium
Search.TextXAlignment = Enum.TextXAlignment.Left
Search.ClearTextOnFocus = false
Search.Parent = Main
corner(Search,10)
stroke(Search,.5)

local sp = Instance.new("UIPadding")
sp.PaddingLeft = UDim.new(0,13)
sp.PaddingRight = UDim.new(0,13)
sp.Parent = Search

local Status = Instance.new("TextLabel")
Status.Position = UDim2.fromOffset(16,104)
Status.Size = UDim2.new(1,-32,0,24)
Status.BackgroundTransparency = 1
Status.Text = "Carregando..."
Status.TextColor3 = Color3.fromRGB(145,145,155)
Status.TextSize = 10
Status.Font = Enum.Font.GothamMedium
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

local List = Instance.new("ScrollingFrame")
List.Position = UDim2.fromOffset(10,132)
List.Size = UDim2.new(1,-20,1,-142)
List.BackgroundTransparency = 1
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = Color3.fromRGB(235,235,235)
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.CanvasSize = UDim2.new()
List.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0,8)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = List

local Pad = Instance.new("UIPadding")
Pad.PaddingBottom = UDim.new(0,10)
Pad.Parent = List

local Cards = {}

local function setStatus(text, good)
    Status.Text = text
    if good == true then
        Status.TextColor3 = Color3.fromRGB(70,210,110)
    elseif good == false then
        Status.TextColor3 = Color3.fromRGB(225,70,80)
    else
        Status.TextColor3 = Color3.fromRGB(145,145,155)
    end
end

local function clearCards()
    for _, card in ipairs(Cards) do
        if card.frame then card.frame:Destroy() end
    end
    table.clear(Cards)
end

local function requestWeapon(data, button)
    local owned = findOwned(data.name)

    if owned then
        local humanoid = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")

        if humanoid then
            humanoid:EquipTool(owned)
            setStatus(data.name .. " equipada.", true)
        else
            setStatus("Humanoid não encontrado.", false)
        end
        return
    end

    if not RequestWeapon then
        RequestWeapon = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    end

    if not RequestWeapon or not RequestWeapon:IsA("RemoteFunction") then
        setStatus("CafeinaRequestWeapon não está disponível no servidor.", false)
        return
    end

    button.Text = "..."

    local ok, response = pcall(function()
        return RequestWeapon:InvokeServer(data.name)
    end)

    if ok and type(response) == "table" and response.ok then
        button.Text = "✓"
        setStatus(response.message or (data.name .. " recebida."), true)
    else
        button.Text = "ERRO"
        setStatus(
            type(response) == "table" and response.message
                or "Servidor recusou a solicitação.",
            false
        )
    end

    task.delay(.7, function()
        if button and button.Parent then
            button.Text = findOwned(data.name) and "EQUIPAR" or "PEGAR"
        end
    end)
end

local function makeCard(data, order)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1,-2,0,88)
    Card.BackgroundColor3 = Color3.fromRGB(24,24,28)
    Card.BorderSizePixel = 0
    Card.LayoutOrder = order
    Card.Parent = List
    corner(Card,11)
    stroke(Card,.55)

    local Name = Instance.new("TextLabel")
    Name.Position = UDim2.fromOffset(13,9)
    Name.Size = UDim2.new(1,-110,0,21)
    Name.BackgroundTransparency = 1
    Name.Text = data.name
    Name.TextColor3 = Color3.fromRGB(245,245,245)
    Name.TextSize = 14
    Name.Font = Enum.Font.GothamBold
    Name.TextXAlignment = Enum.TextXAlignment.Left
    Name.Parent = Card

    local meta = {}
    if data.mode ~= nil then meta[#meta+1] = tostring(data.mode) end
    if data.magazine ~= nil then meta[#meta+1] = "MAG "..tostring(data.magazine) end
    if data.ammo ~= nil and data.magazine == nil then meta[#meta+1] = "AMMO "..tostring(data.ammo) end

    local Meta = Instance.new("TextLabel")
    Meta.Position = UDim2.fromOffset(13,32)
    Meta.Size = UDim2.new(1,-110,0,17)
    Meta.BackgroundTransparency = 1
    Meta.Text = #meta > 0 and table.concat(meta," • ") or "Tool disponível"
    Meta.TextColor3 = Color3.fromRGB(145,145,155)
    Meta.TextSize = 10
    Meta.Font = Enum.Font.GothamMedium
    Meta.TextXAlignment = Enum.TextXAlignment.Left
    Meta.Parent = Card

    local stats = {}
    if data.damage ~= nil then stats[#stats+1] = "DMG "..tostring(data.damage) end
    if data.fireRate ~= nil then stats[#stats+1] = "RPM "..tostring(data.fireRate) end
    if data.range ~= nil then stats[#stats+1] = "RNG "..tostring(data.range) end

    local Stats = Instance.new("TextLabel")
    Stats.Position = UDim2.fromOffset(13,56)
    Stats.Size = UDim2.new(1,-110,0,17)
    Stats.BackgroundTransparency = 1
    Stats.Text = #stats > 0 and table.concat(stats,"   ") or data.path
    Stats.TextTruncate = Enum.TextTruncate.AtEnd
    Stats.TextColor3 = Color3.fromRGB(185,185,195)
    Stats.TextSize = 9
    Stats.Font = Enum.Font.GothamMedium
    Stats.TextXAlignment = Enum.TextXAlignment.Left
    Stats.Parent = Card

    local Get = Instance.new("TextButton")
    Get.AnchorPoint = Vector2.new(1,.5)
    Get.Position = UDim2.new(1,-11,.5,0)
    Get.Size = UDim2.fromOffset(78,42)
    Get.BackgroundColor3 = Color3.fromRGB(245,245,245)
    Get.Text = findOwned(data.name) and "EQUIPAR" or "PEGAR"
    Get.TextColor3 = Color3.fromRGB(10,10,12)
    Get.TextSize = 10
    Get.Font = Enum.Font.GothamBold
    Get.AutoButtonColor = false
    Get.Parent = Card
    corner(Get,9)

    Get.MouseButton1Click:Connect(function()
        requestWeapon(data, Get)
    end)

    Cards[#Cards+1] = {
        frame = Card,
        data = data
    }
end

local function applySearch()
    local q = string.lower(Search.Text)
    local visible = 0

    for _, card in ipairs(Cards) do
        local match = q == ""
            or string.find(string.lower(card.data.name), q, 1, true) ~= nil

        card.frame.Visible = match
        if match then visible += 1 end
    end

    if q ~= "" then
        setStatus(tostring(visible) .. " resultado(s)")
    end
end

local function refreshList()
    clearCards()

    local weapons = collectAvailableWeapons()

    for i, data in ipairs(weapons) do
        makeCard(data, i)
    end

    Sub.Text = "ARMAS DISPONÍVEIS • " .. tostring(#weapons)
    setStatus(tostring(#weapons) .. " arma(s) disponível(is).", #weapons > 0)

    applySearch()
end

Search:GetPropertyChangedSignal("Text"):Connect(applySearch)
Refresh.MouseButton1Click:Connect(refreshList)

-- Atualização automática com debounce.
local refreshQueued = false

local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true

    task.delay(.35, function()
        refreshQueued = false
        if Gui.Parent then refreshList() end
    end)
end

ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

ReplicatedStorage.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

Backpack.ChildAdded:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

Backpack.ChildRemoved:Connect(function(obj)
    if obj:IsA("Tool") then queueRefresh() end
end)

LocalPlayer.CharacterAdded:Connect(function(character)
    character.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)
    character.ChildRemoved:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)
    queueRefresh()
end)

-- Minimizar
local Mini = Instance.new("TextButton")
Mini.AnchorPoint = Vector2.new(.5,.5)
Mini.Position = UDim2.fromScale(.5,.5)
Mini.Size = UDim2.fromOffset(54,54)
Mini.BackgroundColor3 = Color3.fromRGB(10,10,12)
Mini.Text = "C"
Mini.TextColor3 = Color3.fromRGB(245,245,245)
Mini.TextSize = 21
Mini.Font = Enum.Font.GothamBold
Mini.Visible = false
Mini.AutoButtonColor = false
Mini.Parent = Gui
corner(Mini,15)
stroke(Mini,.15)

Minimize.MouseButton1Click:Connect(function()
    Mini.Position = Main.Position
    Main.Visible = false
    Mini.Visible = true
end)

Mini.MouseButton1Click:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

-- Drag mobile/PC
local function makeDraggable(handle, object)
    local dragging, dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = object.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            object.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

refreshList()

print("[CAFEÍNA] Available Weapons Menu V1.0 carregado.")
