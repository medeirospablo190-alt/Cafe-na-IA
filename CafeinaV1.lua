--[[
CAFEÍNA • WEAPONS EXECUTOR MENU V1.2
Foco: iniciar de forma robusta em executor no seu próprio jogo.

FUNCIONA SEM DEPENDER DE:
- StarterPlayerScripts
- gethui obrigatório
- CafeinaRequestWeapon obrigatório
- scan pesado antes da GUI aparecer

O QUE FAZ:
- Abre a interface imediatamente.
- Procura Tools visíveis ao cliente em segundo plano.
- Lista armas encontradas.
- Atualiza automaticamente.
- EQUIPA armas que já estão no Backpack/Character.
- Se existir ReplicatedStorage.CafeinaRequestWeapon, usa esse RemoteFunction.
- Também aceita um callback autorizado opcional:
    getgenv().CafeinaWeaponRequest = function(weaponName)
        -- seu fluxo autorizado
        return true, "OK"
    end
]]

local ENV = (getgenv and getgenv()) or _G

local function boot()
    ------------------------------------------------------------
    -- SERVICES
    ------------------------------------------------------------
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local CoreGui = game:GetService("CoreGui")

    local LocalPlayer = Players.LocalPlayer
    assert(LocalPlayer, "LocalPlayer não encontrado")

    ------------------------------------------------------------
    -- GUI PARENT
    ------------------------------------------------------------
    local function resolveGuiParent()
        if typeof(gethui) == "function" then
            local ok, result = pcall(gethui)
            if ok and result then
                return result
            end
        end

        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            return playerGui
        end

        local ok, result = pcall(function()
            return CoreGui
        end)

        if ok and result then
            return result
        end

        playerGui = LocalPlayer:WaitForChild("PlayerGui", 3)
        return playerGui
    end

    local GuiParent = resolveGuiParent()
    assert(GuiParent, "Não foi possível encontrar um parent para a GUI")

    ------------------------------------------------------------
    -- CLEANUP OLD
    ------------------------------------------------------------
    local GUI_NAME = "CafeinaWeaponsExecutorV12"

    pcall(function()
        local old = GuiParent:FindFirstChild(GUI_NAME)
        if old then
            old:Destroy()
        end
    end)

    if ENV.__CAFEINA_WEAPONS_V12_CLEANUP then
        pcall(ENV.__CAFEINA_WEAPONS_V12_CLEANUP)
    end

    local Connections = {}

    local function connect(signal, fn)
        local c = signal:Connect(fn)
        Connections[#Connections + 1] = c
        return c
    end

    local function cleanup()
        for _, c in ipairs(Connections) do
            pcall(function()
                c:Disconnect()
            end)
        end
        table.clear(Connections)
    end

    ENV.__CAFEINA_WEAPONS_V12_CLEANUP = cleanup

    ------------------------------------------------------------
    -- HELPERS
    ------------------------------------------------------------
    local function corner(parent, radius)
        local x = Instance.new("UICorner")
        x.CornerRadius = UDim.new(0, radius)
        x.Parent = parent
        return x
    end

    local function stroke(parent, transparency)
        local x = Instance.new("UIStroke")
        x.Color = Color3.fromRGB(65, 65, 72)
        x.Transparency = transparency or 0.4
        x.Thickness = 1
        x.Parent = parent
        return x
    end

    local function safeAttr(obj, ...)
        for _, key in ipairs({...}) do
            local ok, value = pcall(function()
                return obj:GetAttribute(key)
            end)
            if ok and value ~= nil then
                return value
            end
        end
        return nil
    end

    local function safeFullName(obj)
        local ok, result = pcall(function()
            return obj:GetFullName()
        end)
        return ok and result or tostring(obj and obj.Name or "?")
    end

    local NON_WEAPONS = {
        ["medkit"] = true,
        ["super potion"] = true,
    }

    local WEAPON_WORDS = {
        "gun","rifle","pistol","shotgun","sniper","blaster",
        "ak47","ak-47","awp","barrett","famas","mp7","mp9",
        "p90","bizon","sg553","tec-9","ump","nova","five-seven",
        "laser","cryo","winter"
    }

    local function looksLikeWeapon(tool)
        if not tool or not tool:IsA("Tool") then
            return false
        end

        local n = string.lower(tool.Name)
        if NON_WEAPONS[n] then
            return false
        end

        if safeAttr(tool, "damage", "Damage") ~= nil then return true end
        if safeAttr(tool, "magazineSize", "MagSize", "_ammo") ~= nil then return true end
        if safeAttr(tool, "fireMode", "FireMode") ~= nil then return true end
        if safeAttr(tool, "rateOfFire", "FireRate") ~= nil then return true end
        if safeAttr(tool, "projectileType", "ProjectileType") ~= nil then return true end

        for _, word in ipairs(WEAPON_WORDS) do
            if string.find(n, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function findOwned(name)
        local character = LocalPlayer.Character
        if character then
            local tool = character:FindFirstChild(name)
            if tool and tool:IsA("Tool") then
                return tool
            end
        end

        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            local tool = backpack:FindFirstChild(name)
            if tool and tool:IsA("Tool") then
                return tool
            end
        end

        return nil
    end

    ------------------------------------------------------------
    -- GUI IMMEDIATELY
    ------------------------------------------------------------
    local Gui = Instance.new("ScreenGui")
    Gui.Name = GUI_NAME
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = false
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.Parent = GuiParent

    local Main = Instance.new("Frame")
    Main.AnchorPoint = Vector2.new(0.5, 0.5)
    Main.Position = UDim2.fromScale(0.5, 0.5)
    Main.Size = UDim2.fromOffset(390, 500)
    Main.BackgroundColor3 = Color3.fromRGB(10,10,12)
    Main.BorderSizePixel = 0
    Main.Parent = Gui
    corner(Main, 14)
    stroke(Main, 0.15)

    local SizeConstraint = Instance.new("UISizeConstraint")
    SizeConstraint.MinSize = Vector2.new(300, 360)
    SizeConstraint.MaxSize = Vector2.new(450, 570)
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
    corner(Logo, 10)

    local Title = Instance.new("TextLabel")
    Title.Position = UDim2.fromOffset(61,9)
    Title.Size = UDim2.new(1,-155,0,21)
    Title.BackgroundTransparency = 1
    Title.Text = "CAFEÍNA"
    Title.TextColor3 = Color3.fromRGB(245,245,245)
    Title.TextSize = 17
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header

    local Subtitle = Instance.new("TextLabel")
    Subtitle.Position = UDim2.fromOffset(61,30)
    Subtitle.Size = UDim2.new(1,-155,0,17)
    Subtitle.BackgroundTransparency = 1
    Subtitle.Text = "ARMAS • CARREGANDO"
    Subtitle.TextColor3 = Color3.fromRGB(140,140,150)
    Subtitle.TextSize = 10
    Subtitle.Font = Enum.Font.GothamMedium
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    Subtitle.Parent = Header

    local Refresh = Instance.new("TextButton")
    Refresh.AnchorPoint = Vector2.new(1,0)
    Refresh.Position = UDim2.new(1,-89,0,12)
    Refresh.Size = UDim2.fromOffset(34,34)
    Refresh.BackgroundColor3 = Color3.fromRGB(24,24,28)
    Refresh.Text = "↻"
    Refresh.TextColor3 = Color3.fromRGB(245,245,245)
    Refresh.TextSize = 17
    Refresh.Font = Enum.Font.GothamBold
    Refresh.AutoButtonColor = false
    Refresh.Parent = Header
    corner(Refresh, 9)

    local Minimize = Instance.new("TextButton")
    Minimize.AnchorPoint = Vector2.new(1,0)
    Minimize.Position = UDim2.new(1,-49,0,12)
    Minimize.Size = UDim2.fromOffset(34,34)
    Minimize.BackgroundColor3 = Color3.fromRGB(24,24,28)
    Minimize.Text = "−"
    Minimize.TextColor3 = Color3.fromRGB(245,245,245)
    Minimize.TextSize = 18
    Minimize.Font = Enum.Font.GothamBold
    Minimize.AutoButtonColor = false
    Minimize.Parent = Header
    corner(Minimize, 9)

    local Close = Instance.new("TextButton")
    Close.AnchorPoint = Vector2.new(1,0)
    Close.Position = UDim2.new(1,-9,0,12)
    Close.Size = UDim2.fromOffset(34,34)
    Close.BackgroundColor3 = Color3.fromRGB(85,20,24)
    Close.Text = "×"
    Close.TextColor3 = Color3.fromRGB(255,255,255)
    Close.TextSize = 18
    Close.Font = Enum.Font.GothamBold
    Close.AutoButtonColor = false
    Close.Parent = Header
    corner(Close, 9)

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
    corner(Search, 10)
    stroke(Search, 0.55)

    local SearchPadding = Instance.new("UIPadding")
    SearchPadding.PaddingLeft = UDim.new(0,13)
    SearchPadding.PaddingRight = UDim.new(0,13)
    SearchPadding.Parent = Search

    local Status = Instance.new("TextLabel")
    Status.Position = UDim2.fromOffset(16,104)
    Status.Size = UDim2.new(1,-32,0,24)
    Status.BackgroundTransparency = 1
    Status.Text = "Menu iniciado."
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

    local Padding = Instance.new("UIPadding")
    Padding.PaddingBottom = UDim.new(0,10)
    Padding.Parent = List

    connect(Layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
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
    stroke(Mini,0.15)

    ------------------------------------------------------------
    -- STATUS
    ------------------------------------------------------------
    local function setStatus(text, good)
        Status.Text = tostring(text)

        if good == true then
            Status.TextColor3 = Color3.fromRGB(80,210,115)
        elseif good == false then
            Status.TextColor3 = Color3.fromRGB(225,75,80)
        else
            Status.TextColor3 = Color3.fromRGB(145,145,155)
        end
    end

    ------------------------------------------------------------
    -- CARDS
    ------------------------------------------------------------
    local Cards = {}

    local function clearCards()
        for _, card in ipairs(Cards) do
            pcall(function()
                card.frame:Destroy()
            end)
        end
        table.clear(Cards)
    end

    local function weaponData(tool)
        return {
            name = tool.Name,
            path = safeFullName(tool),
            source = tool,
            damage = safeAttr(tool, "damage", "Damage"),
            ammo = safeAttr(tool, "_ammo"),
            magazine = safeAttr(tool, "magazineSize", "MagSize"),
            fireRate = safeAttr(tool, "rateOfFire", "FireRate"),
            range = safeAttr(tool, "range", "Range"),
            mode = safeAttr(tool, "fireMode", "FireMode"),
        }
    end

    local function equipOwned(name)
        local tool = findOwned(name)
        if not tool then
            return false, "Arma não está no Backpack."
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not humanoid then
            return false, "Humanoid não encontrado."
        end

        local ok, err = pcall(function()
            humanoid:EquipTool(tool)
        end)

        if not ok then
            return false, tostring(err)
        end

        return true, name .. " equipada."
    end

    local function requestAuthorized(name)
        local owned = findOwned(name)
        if owned then
            return equipOwned(name)
        end

        if typeof(ENV.CafeinaWeaponRequest) == "function" then
            local ok, a, b = pcall(ENV.CafeinaWeaponRequest, name)

            if not ok then
                return false, tostring(a)
            end

            if a == true then
                return true, tostring(b or (name .. " recebida."))
            end

            return false, tostring(b or a or "Solicitação recusada.")
        end

        local remote = ReplicatedStorage:FindFirstChild("CafeinaRequestWeapon")

        if remote and remote:IsA("RemoteFunction") then
            local ok, response = pcall(function()
                return remote:InvokeServer(name)
            end)

            if not ok then
                return false, tostring(response)
            end

            if type(response) == "table" then
                return response.ok == true,
                    tostring(response.message or (response.ok and "OK" or "Recusado"))
            end

            if response == true then
                return true, name .. " recebida."
            end

            return false, "Servidor recusou."
        end

        return false,
            "Arma visível, mas nenhum fluxo autorizado de coleta foi encontrado."
    end

    local function createCard(data, order)
        local Card = Instance.new("Frame")
        Card.Size = UDim2.new(1,-2,0,88)
        Card.BackgroundColor3 = Color3.fromRGB(24,24,28)
        Card.BorderSizePixel = 0
        Card.LayoutOrder = order
        Card.Parent = List
        corner(Card,11)
        stroke(Card,0.58)

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

        local info = {}
        if data.mode ~= nil then info[#info+1] = tostring(data.mode) end
        if data.magazine ~= nil then info[#info+1] = "MAG "..tostring(data.magazine) end
        if data.ammo ~= nil then info[#info+1] = "AMMO "..tostring(data.ammo) end

        local Meta = Instance.new("TextLabel")
        Meta.Position = UDim2.fromOffset(13,32)
        Meta.Size = UDim2.new(1,-110,0,17)
        Meta.BackgroundTransparency = 1
        Meta.Text = #info > 0 and table.concat(info," • ") or "Tool disponível"
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

        local Action = Instance.new("TextButton")
        Action.AnchorPoint = Vector2.new(1,.5)
        Action.Position = UDim2.new(1,-11,.5,0)
        Action.Size = UDim2.fromOffset(78,42)
        Action.BackgroundColor3 = Color3.fromRGB(245,245,245)
        Action.TextColor3 = Color3.fromRGB(10,10,12)
        Action.TextSize = 10
        Action.Font = Enum.Font.GothamBold
        Action.AutoButtonColor = false
        Action.Parent = Card
        corner(Action,9)

        local function refreshActionText()
            Action.Text = findOwned(data.name) and "EQUIPAR" or "PEGAR"
        end

        refreshActionText()

        connect(Action.MouseButton1Click, function()
            Action.Text = "..."

            task.spawn(function()
                local ok, message = requestAuthorized(data.name)

                if ok then
                    Action.Text = "✓"
                    setStatus(message, true)
                else
                    Action.Text = "!"
                    setStatus(message, false)
                end

                task.wait(0.7)

                if Action.Parent then
                    refreshActionText()
                end
            end)
        end)

        Cards[#Cards+1] = {
            frame = Card,
            data = data,
        }
    end

    ------------------------------------------------------------
    -- SEARCH
    ------------------------------------------------------------
    local function applySearch()
        local q = string.lower(Search.Text or "")
        local visible = 0

        for _, card in ipairs(Cards) do
            local match = q == ""
                or string.find(string.lower(card.data.name), q, 1, true) ~= nil

            card.frame.Visible = match

            if match then
                visible += 1
            end
        end

        if q ~= "" then
            setStatus(tostring(visible) .. " resultado(s)")
        end
    end

    connect(Search:GetPropertyChangedSignal("Text"), applySearch)

    ------------------------------------------------------------
    -- ASYNC SCAN
    ------------------------------------------------------------
    local scanToken = 0
    local scanning = false

    local function scanContainer(container, found, seen, token)
        if not container then
            return
        end

        local ok, descendants = pcall(function()
            return container:GetDescendants()
        end)

        if not ok then
            return
        end

        for i, obj in ipairs(descendants) do
            if token ~= scanToken then
                return
            end

            if obj:IsA("Tool") and looksLikeWeapon(obj) then
                local key = string.lower(obj.Name)

                if not seen[key] then
                    seen[key] = true
                    found[#found+1] = weaponData(obj)
                end
            end

            if i % 300 == 0 then
                RunService.Heartbeat:Wait()
            end
        end
    end

    local function refreshList()
        scanToken += 1
        local myToken = scanToken
        scanning = true
        Refresh.Text = "..."

        local found = {}
        local seen = {}

        setStatus("Lendo Backpack...")

        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        scanContainer(backpack, found, seen, myToken)

        setStatus("Lendo personagem...")
        scanContainer(LocalPlayer.Character, found, seen, myToken)

        setStatus("Lendo ReplicatedStorage...")
        scanContainer(ReplicatedStorage, found, seen, myToken)

        setStatus("Lendo Workspace...")
        scanContainer(workspace, found, seen, myToken)

        if myToken ~= scanToken then
            scanning = false
            Refresh.Text = "↻"
            return
        end

        table.sort(found, function(a,b)
            return string.lower(a.name) < string.lower(b.name)
        end)

        clearCards()

        for i, data in ipairs(found) do
            createCard(data, i)

            if i % 25 == 0 then
                RunService.Heartbeat:Wait()
            end
        end

        Subtitle.Text = "ARMAS DISPONÍVEIS • " .. tostring(#found)
        setStatus(tostring(#found) .. " arma(s) encontrada(s).", #found > 0)

        Refresh.Text = "↻"
        scanning = false
        applySearch()
    end

    connect(Refresh.MouseButton1Click, function()
        task.spawn(refreshList)
    end)

    ------------------------------------------------------------
    -- AUTO REFRESH LIGHTWEIGHT
    ------------------------------------------------------------
    local refreshPending = false

    local function queueRefresh()
        if refreshPending then return end
        refreshPending = true

        task.delay(0.8, function()
            refreshPending = false

            if Gui.Parent then
                task.spawn(refreshList)
            end
        end)
    end

    connect(ReplicatedStorage.DescendantAdded, function(obj)
        if obj:IsA("Tool") then
            queueRefresh()
        end
    end)

    connect(ReplicatedStorage.DescendantRemoving, function(obj)
        if obj:IsA("Tool") then
            queueRefresh()
        end
    end)

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        connect(backpack.ChildAdded, function(obj)
            if obj:IsA("Tool") then queueRefresh() end
        end)

        connect(backpack.ChildRemoved, function(obj)
            if obj:IsA("Tool") then queueRefresh() end
        end)
    end

    connect(LocalPlayer.CharacterAdded, function(character)
        connect(character.ChildAdded, function(obj)
            if obj:IsA("Tool") then queueRefresh() end
        end)

        connect(character.ChildRemoved, function(obj)
            if obj:IsA("Tool") then queueRefresh() end
        end)

        queueRefresh()
    end)

    ------------------------------------------------------------
    -- MINIMIZE / CLOSE
    ------------------------------------------------------------
    connect(Minimize.MouseButton1Click, function()
        Mini.Position = Main.Position
        Main.Visible = false
        Mini.Visible = true
    end)

    connect(Mini.MouseButton1Click, function()
        Mini.Visible = false
        Main.Visible = true
    end)

    connect(Close.MouseButton1Click, function()
        cleanup()
        Gui:Destroy()
    end)

    ------------------------------------------------------------
    -- DRAG
    ------------------------------------------------------------
    local function makeDraggable(handle, object)
        local dragging = false
        local dragInput
        local dragStart
        local startPos

        connect(handle.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = object.Position
            end
        end)

        connect(handle.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        connect(UserInputService.InputChanged, function(input)
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

        connect(UserInputService.InputEnded, function(input)
            if input == dragInput
            or input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    makeDraggable(Header, Main)
    makeDraggable(Mini, Mini)

    ------------------------------------------------------------
    -- START AFTER UI RENDERS
    ------------------------------------------------------------
    task.defer(function()
        RunService.RenderStepped:Wait()

        if Gui.Parent then
            task.spawn(refreshList)
        end
    end)

    setStatus("Menu iniciado • procurando armas...")
    print("[CAFEÍNA] Weapons Executor Menu V1.2 carregado.")

    return Gui
end

local ok, result = xpcall(boot, function(err)
    return debug.traceback(tostring(err))
end)

if not ok then
    warn("[CAFEÍNA] FALHA V1.2:\n" .. tostring(result))

    pcall(function()
        local Players = game:GetService("Players")
        local StarterGui = game:GetService("StarterGui")

        StarterGui:SetCore("SendNotification", {
            Title = "CAFEÍNA",
            Text = "Falha ao iniciar. Veja o console.",
            Duration = 6,
        })
    end)
end
