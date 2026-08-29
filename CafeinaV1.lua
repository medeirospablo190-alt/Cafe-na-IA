--[[
CAFEÍNA • AVAILABLE WEAPONS MENU V1.1
Correções:
- Interface aparece ANTES da busca.
- Scanner de Tools roda em lotes e cede frames.
- Não trava esperando Backpack/Remote.
- Suporte gethui/CoreGui/PlayerGui.
- Erros de inicialização mostrados no console.
- Atualização dinâmica com debounce.
]]

local okMain, mainError = pcall(function()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("LocalPlayer não encontrado")
end

local REMOTE_NAME = "CafeinaRequestWeapon"
local GUI_NAME = "CafeinaAvailableWeapons"

local function getGuiParent()
    if typeof(gethui) == "function" then
        local ok, gui = pcall(gethui)
        if ok and gui then return gui end
    end

    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then return pg end

    local ok, cg = pcall(function() return CoreGui end)
    if ok and cg then return cg end

    return LocalPlayer:WaitForChild("PlayerGui", 5)
end

local GuiParent = getGuiParent()
if not GuiParent then
    error("Nenhum container de GUI disponível")
end

pcall(function()
    local old = GuiParent:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

local function addStroke(parent, transparency)
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(70,70,78)
    s.Transparency = transparency or 0.4
    s.Thickness = 1
    s.Parent = parent
end

local function safeAttr(obj, ...)
    if not obj then return nil end
    for _, key in ipairs({...}) do
        local ok, value = pcall(function()
            return obj:GetAttribute(key)
        end)
        if ok and value ~= nil then
            return value
        end
    end
end

local function safeFullName(obj)
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj and obj.Name or "?")
end

local NON_WEAPONS = {
    ["medkit"] = true,
    ["super potion"] = true,
}

local KEYWORDS = {
    "gun","rifle","pistol","shotgun","sniper","blaster",
    "ak47","ak-47","awp","barrett","famas","mp7","mp9",
    "p90","bizon","sg553","tec-9","ump","nova","five-seven",
    "laser","cryo","winter"
}

local function looksLikeWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end

    local n = string.lower(tool.Name)
    if NON_WEAPONS[n] then return false end

    if safeAttr(tool, "damage", "Damage") ~= nil then return true end
    if safeAttr(tool, "magazineSize", "MagSize", "_ammo") ~= nil then return true end
    if safeAttr(tool, "fireMode", "FireMode") ~= nil then return true end
    if safeAttr(tool, "rateOfFire", "FireRate") ~= nil then return true end
    if safeAttr(tool, "projectileType", "ProjectileType") ~= nil then return true end

    for _, word in ipairs(KEYWORDS) do
        if string.find(n, word, 1, true) then
            return true
        end
    end

    return false
end

--==============================================================
-- GUI FIRST
--==============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = GuiParent

local Main = Instance.new("Frame")
Main.AnchorPoint = Vector2.new(0.5,0.5)
Main.Position = UDim2.fromScale(0.5,0.5)
Main.Size = UDim2.fromOffset(390,500)
Main.BackgroundColor3 = Color3.fromRGB(10,10,12)
Main.BorderSizePixel = 0
Main.Parent = Gui
corner(Main,14)
addStroke(Main,0.18)

local SizeConstraint = Instance.new("UISizeConstraint")
SizeConstraint.MinSize = Vector2.new(300,360)
SizeConstraint.MaxSize = Vector2.new(450,570)
SizeConstraint.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1,0,0,58)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Position = UDim2.fromOffset(13,10)
Logo.Size = UDim2.fromOffset(38,38)
Logo.BackgroundColor3 = Color3.fromRGB(245,245,245)
Logo.Text = "C"
Logo.TextColor3 = Color3.fromRGB(10,10,12)
Logo.TextSize = 19
Logo.Font = Enum.Font.GothamBold
Logo.Parent = Header
corner(Logo,10)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.fromOffset(61,9)
Title.Size = UDim2.new(1,-150,0,21)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA"
Title.TextColor3 = Color3.fromRGB(245,245,245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Position = UDim2.fromOffset(61,30)
Subtitle.Size = UDim2.new(1,-150,0,17)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "ARMAS DISPONÍVEIS"
Subtitle.TextColor3 = Color3.fromRGB(140,140,150)
Subtitle.TextSize = 10
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local Refresh = Instance.new("TextButton")
Refresh.AnchorPoint = Vector2.new(1,0)
Refresh.Position = UDim2.new(1,-50,0,12)
Refresh.Size = UDim2.fromOffset(34,34)
Refresh.BackgroundColor3 = Color3.fromRGB(25,25,29)
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
Minimize.BackgroundColor3 = Color3.fromRGB(25,25,29)
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
addStroke(Search,0.55)

local SearchPadding = Instance.new("UIPadding")
SearchPadding.PaddingLeft = UDim.new(0,13)
SearchPadding.PaddingRight = UDim.new(0,13)
SearchPadding.Parent = Search

local Status = Instance.new("TextLabel")
Status.Position = UDim2.fromOffset(16,104)
Status.Size = UDim2.new(1,-32,0,24)
Status.BackgroundTransparency = 1
Status.Text = "Menu iniciado • procurando armas..."
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
List.CanvasSize = UDim2.new(0,0,0,0)
List.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0,8)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = List

local BottomPadding = Instance.new("UIPadding")
BottomPadding.PaddingBottom = UDim.new(0,10)
BottomPadding.Parent = List

Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    List.CanvasSize = UDim2.new(0,0,0,Layout.AbsoluteContentSize.Y + 12)
end)

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
addStroke(Mini,0.18)

local Cards = {}
local scanning = false
local refreshQueued = false
local refreshGeneration = 0

local function setStatus(text, state)
    Status.Text = tostring(text)
    if state == true then
        Status.TextColor3 = Color3.fromRGB(80,210,115)
    elseif state == false then
        Status.TextColor3 = Color3.fromRGB(225,75,80)
    else
        Status.TextColor3 = Color3.fromRGB(145,145,155)
    end
end

local function clearCards()
    for _, item in ipairs(Cards) do
        if item.frame then
            item.frame:Destroy()
        end
    end
    table.clear(Cards)
end

local function findOwned(name)
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChild(name)
        if tool and tool:IsA("Tool") then return tool end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        local tool = backpack:FindFirstChild(name)
        if tool and tool:IsA("Tool") then return tool end
    end

    return nil
end

local function makeWeaponData(tool)
    return {
        name = tool.Name,
        source = tool,
        path = safeFullName(tool),
        damage = safeAttr(tool, "damage", "Damage"),
        ammo = safeAttr(tool, "_ammo"),
        magazine = safeAttr(tool, "magazineSize", "MagSize"),
        fireRate = safeAttr(tool, "rateOfFire", "FireRate"),
        range = safeAttr(tool, "range", "Range"),
        mode = safeAttr(tool, "fireMode", "FireMode"),
    }
end

local function requestWeapon(data, button)
    local owned = findOwned(data.name)

    if owned then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

        if humanoid then
            pcall(function()
                humanoid:EquipTool(owned)
            end)
            setStatus(data.name .. " equipada.", true)
        else
            setStatus("Humanoid não encontrado.", false)
        end
        return
    end

    local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)

    if not remote or not remote:IsA("RemoteFunction") then
        setStatus("Servidor não expôs " .. REMOTE_NAME .. ".", false)
        return
    end

    button.Text = "..."

    task.spawn(function()
        local ok, response = pcall(function()
            return remote:InvokeServer(data.name)
        end)

        if ok and type(response) == "table" and response.ok then
            button.Text = "✓"
            setStatus(response.message or (data.name .. " recebida."), true)
        else
            button.Text = "ERRO"
            local msg = type(response) == "table" and response.message
                or tostring(response or "Servidor recusou.")
            setStatus(msg, false)
        end

        task.wait(.7)
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
    addStroke(Card,.58)

    local Name = Instance.new("TextLabel")
    Name.Position = UDim2.fromOffset(13,9)
    Name.Size = UDim2.new(1,-108,0,21)
    Name.BackgroundTransparency = 1
    Name.Text = data.name
    Name.TextColor3 = Color3.fromRGB(245,245,245)
    Name.TextSize = 14
    Name.Font = Enum.Font.GothamBold
    Name.TextXAlignment = Enum.TextXAlignment.Left
    Name.Parent = Card

    local bits = {}
    if data.mode ~= nil then bits[#bits+1] = tostring(data.mode) end
    if data.magazine ~= nil then bits[#bits+1] = "MAG "..tostring(data.magazine) end
    if data.ammo ~= nil then bits[#bits+1] = "AMMO "..tostring(data.ammo) end

    local Meta = Instance.new("TextLabel")
    Meta.Position = UDim2.fromOffset(13,32)
    Meta.Size = UDim2.new(1,-108,0,17)
    Meta.BackgroundTransparency = 1
    Meta.Text = #bits > 0 and table.concat(bits," • ") or "Tool disponível"
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
    Stats.Size = UDim2.new(1,-108,0,17)
    Stats.BackgroundTransparency = 1
    Stats.Text = #stats > 0 and table.concat(stats,"   ") or data.path
    Stats.TextTruncate = Enum.TextTruncate.AtEnd
    Stats.TextColor3 = Color3.fromRGB(185,185,195)
    Stats.TextSize = 9
    Stats.Font = Enum.Font.GothamMedium
    Stats.TextXAlignment = Enum.TextXAlignment.Left
    Stats.Parent = Card

    local Action = Instance.new("TextButton")
    Action.AnchorPoint = Vector2.new(1,.5)
    Action.Position = UDim2.new(1,-11,.5,0)
    Action.Size = UDim2.fromOffset(78,42)
    Action.BackgroundColor3 = Color3.fromRGB(245,245,245)
    Action.Text = findOwned(data.name) and "EQUIPAR" or "PEGAR"
    Action.TextColor3 = Color3.fromRGB(10,10,12)
    Action.TextSize = 10
    Action.Font = Enum.Font.GothamBold
    Action.AutoButtonColor = false
    Action.Parent = Card
    corner(Action,9)

    Action.MouseButton1Click:Connect(function()
        requestWeapon(data, Action)
    end)

    Cards[#Cards+1] = {
        frame = Card,
        data = data,
    }
end

local function applySearch()
    local q = string.lower(Search.Text or "")
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

Search:GetPropertyChangedSignal("Text"):Connect(applySearch)

--==============================================================
-- ASYNC/BATCHED DISCOVERY
--==============================================================

local function addFromContainer(container, found, seen, generation)
    if not container or not container.Parent and container ~= workspace and container ~= ReplicatedStorage then
        return true
    end

    local ok, descendants = pcall(function()
        return container:GetDescendants()
    end)
    if not ok then return true end

    for i, obj in ipairs(descendants) do
        if generation ~= refreshGeneration then
            return false
        end

        if obj:IsA("Tool") and looksLikeWeapon(obj) then
            local key = string.lower(obj.Name)
            if not seen[key] then
                seen[key] = true
                found[#found+1] = makeWeaponData(obj)
            end
        end

        if i % 350 == 0 then
            RunService.Heartbeat:Wait()
        end
    end

    return true
end

local function refreshList()
    if scanning then
        refreshGeneration += 1
    end

    scanning = true
    refreshGeneration += 1
    local generation = refreshGeneration

    Refresh.Text = "..."
    setStatus("Procurando armas disponíveis...")

    local found = {}
    local seen = {}

    -- Primeiro: itens do jogador, que são pequenos e rápidos.
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local character = LocalPlayer.Character

    if backpack then
        addFromContainer(backpack, found, seen, generation)
    end
    if character then
        addFromContainer(character, found, seen, generation)
    end

    -- Depois: ReplicatedStorage.
    if generation == refreshGeneration then
        setStatus("Analisando ReplicatedStorage...")
        addFromContainer(ReplicatedStorage, found, seen, generation)
    end

    -- Por último: Workspace, em lotes.
    if generation == refreshGeneration then
        setStatus("Analisando Workspace...")
        addFromContainer(workspace, found, seen, generation)
    end

    if generation ~= refreshGeneration then
        scanning = false
        Refresh.Text = "↻"
        return
    end

    table.sort(found, function(a,b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    clearCards()

    for i, data in ipairs(found) do
        makeCard(data, i)

        if i % 30 == 0 then
            RunService.Heartbeat:Wait()
        end
    end

    Subtitle.Text = "ARMAS DISPONÍVEIS • " .. tostring(#found)
    setStatus(tostring(#found) .. " arma(s) encontrada(s).", #found > 0)

    Refresh.Text = "↻"
    scanning = false
    applySearch()
end

local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true

    task.delay(.6, function()
        refreshQueued = false
        if Gui and Gui.Parent then
            task.spawn(refreshList)
        end
    end)
end

Refresh.MouseButton1Click:Connect(function()
    task.spawn(refreshList)
end)

--==============================================================
-- LIVE CHANGES
--==============================================================

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

local function bindBackpack()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return end

    backpack.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)

    backpack.ChildRemoved:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)
end

bindBackpack()

LocalPlayer.CharacterAdded:Connect(function(character)
    character.ChildAdded:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)

    character.ChildRemoved:Connect(function(obj)
        if obj:IsA("Tool") then queueRefresh() end
    end)

    queueRefresh()
end)

--==============================================================
-- MINIMIZE + DRAG
--==============================================================

Minimize.MouseButton1Click:Connect(function()
    Mini.Position = Main.Position
    Main.Visible = false
    Mini.Visible = true
end)

Mini.MouseButton1Click:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

local function makeDraggable(handle, object)
    local dragging = false
    local dragInput
    local dragStart
    local startPos

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
        if dragging and input == dragInput and dragStart and startPos then
            local delta = input.Position - dragStart
            object.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

-- Dá um frame para a GUI renderizar antes da varredura.
task.defer(function()
    RunService.Heartbeat:Wait()
    refreshList()
end)

print("[CAFEÍNA] Available Weapons Menu V1.1 iniciado.")

end)

if not okMain then
    warn("[CAFEÍNA] ERRO AO INICIAR MENU: " .. tostring(mainError))
end
