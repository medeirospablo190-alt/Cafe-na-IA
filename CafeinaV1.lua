--==============================================================
-- CAFEÍNA • WEAPON MENU
-- Mobile / PC
--
-- Coloque em:
-- StarterPlayer > StarterPlayerScripts
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RequestWeapon =
	ReplicatedStorage:WaitForChild("CafeinaRequestWeapon")

--==============================================================
-- REMOVER MENU ANTIGO
--==============================================================

local old = PlayerGui:FindFirstChild("CafeinaWeaponMenu")

if old then
	old:Destroy()
end

--==============================================================
-- DADOS ENCONTRADOS NO JOGO
--==============================================================

local Weapons = {

	{
		name = "AK47",
		display = "AK-47",
		damage = 17,
		ammo = 40,
		fireRate = 600,
		range = 1500,
		mode = "AUTO",
	},

	{
		name = "AWP",
		display = "AWP",
		damage = 90,
		ammo = 5,
		fireRate = 40,
		range = 2000,
		mode = "SEMI",
	},

	{
		name = "Barrett",
		display = "BARRETT",
		damage = 150,
		ammo = 1,
		fireRate = 40,
		range = 2000,
		mode = "SEMI",
	},

	{
		name = "Cryogun",
		display = "CRYOGUN",
		damage = 19,
		ammo = 30,
		fireRate = 600,
		range = 1500,
		mode = "AUTO",
	},

	{
		name = "Famas",
		display = "FAMAS",
		damage = 15,
		ammo = 60,
		fireRate = 750,
		range = 1500,
		mode = "AUTO",
	},

	{
		name = "Five-Seven",
		display = "FIVE-SEVEN",
		damage = 4.22,
		ammo = 20,
		fireRate = 252,
		range = 1000,
		mode = "SEMI",
	},

	{
		name = "Laser Rifle",
		display = "LASER RIFLE",
		damage = 20,
		ammo = "∞",
		fireRate = 462,
		range = 1500,
		mode = "AUTO",
	},

	{
		name = "MP7",
		display = "MP7",
		damage = 10,
		ammo = 30,
		fireRate = 800,
		range = 1000,
		mode = "AUTO",
	},

	{
		name = "MP9",
		display = "MP9",
		damage = 2.10,
		ammo = 100,
		fireRate = 525,
		range = 1000,
		mode = "AUTO",
	},

	{
		name = "Nova",
		display = "NOVA",
		damage = 5.18,
		ammo = 12,
		fireRate = 42,
		range = 80,
		mode = "SEMI",
	},

	{
		name = "P2000",
		display = "P2000",
		damage = 3.58,
		ammo = 20,
		fireRate = 300,
		range = 1000,
		mode = "SEMI",
	},

	{
		name = "P90",
		display = "P90",
		damage = 13,
		ammo = 50,
		fireRate = 750,
		range = 1000,
		mode = "AUTO",
	},

	{
		name = "PP Bizon",
		display = "PP BIZON",
		damage = 15,
		ammo = 64,
		fireRate = 750,
		range = 700,
		mode = "AUTO",
	},

	{
		name = "SG553",
		display = "SG553",
		damage = 19,
		ammo = 40,
		fireRate = 750,
		range = 1500,
		mode = "AUTO",
	},

	{
		name = "TEC-9",
		display = "TEC-9",
		damage = 2.27,
		ammo = 100,
		fireRate = 490,
		range = 1000,
		mode = "AUTO",
	},

	{
		name = "Tactical Shotgun",
		display = "TACTICAL SHOTGUN",
		damage = 10,
		ammo = 12,
		fireRate = 75,
		range = 200,
		mode = "SEMI",
	},

	{
		name = "UMP .45",
		display = "UMP .45",
		damage = 15,
		ammo = 25,
		fireRate = 600,
		range = 1000,
		mode = "AUTO",
	},

	{
		name = "Winter Blaster",
		display = "WINTER BLASTER",
		damage = 20,
		ammo = 60,
		fireRate = 750,
		range = 1500,
		mode = "AUTO",
	},
}

--==============================================================
-- CORES
--==============================================================

local COLORS = {
	BG = Color3.fromRGB(10, 10, 12),
	PANEL = Color3.fromRGB(17, 17, 20),
	CARD = Color3.fromRGB(24, 24, 28),

	WHITE = Color3.fromRGB(245, 245, 245),
	MUTED = Color3.fromRGB(145, 145, 155),

	ACCENT = Color3.fromRGB(255, 255, 255),

	GREEN = Color3.fromRGB(55, 210, 105),
	RED = Color3.fromRGB(230, 55, 65),
}

--==============================================================
-- HELPERS
--==============================================================

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, transparency)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(60, 60, 70)
	s.Transparency = transparency or 0.4
	s.Thickness = 1
	s.Parent = parent
	return s
end

local function tween(object, properties, duration)
	TweenService:Create(
		object,
		TweenInfo.new(
			duration or 0.15,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		properties
	):Play()
end

--==============================================================
-- GUI
--==============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaWeaponMenu"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

--==============================================================
-- MAIN
--==============================================================

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.5)
Main.Size = UDim2.new(0.88, 0, 0.72, 0)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

corner(Main, 14)
stroke(Main, 0.15)

local SizeConstraint = Instance.new("UISizeConstraint")
SizeConstraint.MinSize = Vector2.new(300, 380)
SizeConstraint.MaxSize = Vector2.new(450, 570)
SizeConstraint.Parent = Main

--==============================================================
-- HEADER
--==============================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 62)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Logo = Instance.new("TextLabel")
Logo.Position = UDim2.new(0, 16, 0, 10)
Logo.Size = UDim2.new(0, 38, 0, 38)
Logo.BackgroundColor3 = COLORS.WHITE
Logo.Text = "C"
Logo.TextColor3 = COLORS.BG
Logo.TextSize = 19
Logo.Font = Enum.Font.GothamBold
Logo.Parent = Header

corner(Logo, 10)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.new(0, 64, 0, 10)
Title.Size = UDim2.new(1, -150, 0, 21)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA"
Title.TextColor3 = COLORS.WHITE
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Position = UDim2.new(0, 64, 0, 31)
Subtitle.Size = UDim2.new(1, -150, 0, 18)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "ARMAS • " .. #Weapons .. " encontradas"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 11
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

--==============================================================
-- MINIMIZAR
--==============================================================

local Minimize = Instance.new("TextButton")
Minimize.AnchorPoint = Vector2.new(1, 0)
Minimize.Position = UDim2.new(1, -50, 0, 13)
Minimize.Size = UDim2.fromOffset(34, 34)
Minimize.BackgroundColor3 = COLORS.CARD
Minimize.Text = "−"
Minimize.TextColor3 = COLORS.WHITE
Minimize.TextSize = 21
Minimize.Font = Enum.Font.GothamBold
Minimize.AutoButtonColor = false
Minimize.Parent = Header

corner(Minimize, 9)

--==============================================================
-- FECHAR
--==============================================================

local Close = Instance.new("TextButton")
Close.AnchorPoint = Vector2.new(1, 0)
Close.Position = UDim2.new(1, -10, 0, 13)
Close.Size = UDim2.fromOffset(34, 34)
Close.BackgroundColor3 = COLORS.CARD
Close.Text = "×"
Close.TextColor3 = COLORS.WHITE
Close.TextSize = 18
Close.Font = Enum.Font.GothamBold
Close.AutoButtonColor = false
Close.Parent = Header

corner(Close, 9)

--==============================================================
-- PESQUISA
--==============================================================

local Search = Instance.new("TextBox")
Search.Position = UDim2.new(0, 14, 0, 66)
Search.Size = UDim2.new(1, -28, 0, 42)
Search.BackgroundColor3 = COLORS.PANEL
Search.PlaceholderText = "Pesquisar arma..."
Search.PlaceholderColor3 = COLORS.MUTED
Search.Text = ""
Search.TextColor3 = COLORS.WHITE
Search.TextSize = 14
Search.Font = Enum.Font.GothamMedium
Search.TextXAlignment = Enum.TextXAlignment.Left
Search.ClearTextOnFocus = false
Search.Parent = Main

corner(Search, 10)
stroke(Search, 0.45)

local SearchPadding = Instance.new("UIPadding")
SearchPadding.PaddingLeft = UDim.new(0, 14)
SearchPadding.PaddingRight = UDim.new(0, 14)
SearchPadding.Parent = Search

--==============================================================
-- STATUS
--==============================================================

local Status = Instance.new("TextLabel")
Status.Position = UDim2.new(0, 16, 0, 111)
Status.Size = UDim2.new(1, -32, 0, 25)
Status.BackgroundTransparency = 1
Status.Text = "Selecione uma arma"
Status.TextColor3 = COLORS.MUTED
Status.TextSize = 11
Status.Font = Enum.Font.GothamMedium
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

--==============================================================
-- LISTA
--==============================================================

local List = Instance.new("ScrollingFrame")
List.Position = UDim2.new(0, 10, 0, 138)
List.Size = UDim2.new(1, -20, 1, -148)
List.BackgroundTransparency = 1
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = COLORS.WHITE
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.CanvasSize = UDim2.new()
List.ScrollingDirection = Enum.ScrollingDirection.Y
List.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 8)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = List

local Padding = Instance.new("UIPadding")
Padding.PaddingBottom = UDim.new(0, 10)
Padding.Parent = List

--==============================================================
-- NOTIFICAÇÃO
--==============================================================

local function setStatus(text, color)
	Status.Text = text
	Status.TextColor3 = color or COLORS.MUTED
end

--==============================================================
-- PEGAR ARMA
--==============================================================

local requesting = false

local function requestWeapon(weapon, button)
	if requesting then
		return
	end

	requesting = true

	local oldText = button.Text

	button.Text = "..."
	setStatus(
		"Solicitando " .. weapon.display .. "...",
		COLORS.WHITE
	)

	local success, response = pcall(function()
		return RequestWeapon:InvokeServer(weapon.name)
	end)

	if not success then
		button.Text = "ERRO"

		setStatus(
			"Erro de comunicação com servidor.",
			COLORS.RED
		)

		task.wait(0.8)

		button.Text = oldText
		requesting = false

		return
	end

	if response and response.ok then
		button.Text = "✓"

		setStatus(
			response.message or
			(weapon.display .. " recebida."),
			COLORS.GREEN
		)

		task.wait(0.65)

		button.Text = "PEGAR"
	else
		button.Text = "ERRO"

		setStatus(
			(response and response.message) or
			"Não foi possível pegar a arma.",
			COLORS.RED
		)

		task.wait(0.8)

		button.Text = "PEGAR"
	end

	requesting = false
end

--==============================================================
-- CRIAR CARD
--==============================================================

local Cards = {}

local function createWeaponCard(weapon, index)
	local Card = Instance.new("Frame")
	Card.Name = weapon.name
	Card.Size = UDim2.new(1, -2, 0, 88)
	Card.BackgroundColor3 = COLORS.CARD
	Card.BorderSizePixel = 0
	Card.LayoutOrder = index
	Card.Parent = List

	corner(Card, 11)
	stroke(Card, 0.55)

	----------------------------------------------------------
	-- NOME
	----------------------------------------------------------

	local Name = Instance.new("TextLabel")
	Name.Position = UDim2.new(0, 13, 0, 9)
	Name.Size = UDim2.new(1, -105, 0, 22)
	Name.BackgroundTransparency = 1
	Name.Text = weapon.display
	Name.TextColor3 = COLORS.WHITE
	Name.TextSize = 14
	Name.Font = Enum.Font.GothamBold
	Name.TextXAlignment = Enum.TextXAlignment.Left
	Name.Parent = Card

	----------------------------------------------------------
	-- TIPO
	----------------------------------------------------------

	local Mode = Instance.new("TextLabel")
	Mode.Position = UDim2.new(0, 13, 0, 33)
	Mode.Size = UDim2.new(1, -110, 0, 17)
	Mode.BackgroundTransparency = 1

	Mode.Text =
		weapon.mode ..
		"  •  " ..
		tostring(weapon.ammo) ..
		" munição"

	Mode.TextColor3 = COLORS.MUTED
	Mode.TextSize = 10
	Mode.Font = Enum.Font.GothamMedium
	Mode.TextXAlignment = Enum.TextXAlignment.Left
	Mode.Parent = Card

	----------------------------------------------------------
	-- STATS
	----------------------------------------------------------

	local Stats = Instance.new("TextLabel")
	Stats.Position = UDim2.new(0, 13, 0, 56)
	Stats.Size = UDim2.new(1, -110, 0, 18)
	Stats.BackgroundTransparency = 1

	Stats.Text =
		"DMG " .. tostring(weapon.damage) ..
		"   RPM " .. tostring(math.floor(weapon.fireRate)) ..
		"   RNG " .. tostring(weapon.range)

	Stats.TextColor3 = Color3.fromRGB(185, 185, 195)
	Stats.TextSize = 10
	Stats.Font = Enum.Font.GothamMedium
	Stats.TextXAlignment = Enum.TextXAlignment.Left
	Stats.Parent = Card

	----------------------------------------------------------
	-- PEGAR
	----------------------------------------------------------

	local Get = Instance.new("TextButton")
	Get.AnchorPoint = Vector2.new(1, 0.5)
	Get.Position = UDim2.new(1, -11, 0.5, 0)
	Get.Size = UDim2.fromOffset(78, 42)
	Get.BackgroundColor3 = COLORS.WHITE
	Get.Text = "PEGAR"
	Get.TextColor3 = COLORS.BG
	Get.TextSize = 11
	Get.Font = Enum.Font.GothamBold
	Get.AutoButtonColor = false
	Get.Parent = Card

	corner(Get, 9)

	Get.MouseButton1Click:Connect(function()
		requestWeapon(weapon, Get)
	end)

	Cards[#Cards + 1] = {
		frame = Card,
		weapon = weapon
	}
end

for index, weapon in ipairs(Weapons) do
	createWeaponCard(weapon, index)
end

--==============================================================
-- PESQUISA
--==============================================================

local function updateSearch()
	local query = string.lower(Search.Text)

	for _, card in ipairs(Cards) do
		local weapon = card.weapon

		local searchable =
			string.lower(
				weapon.name .. " " ..
				weapon.display .. " " ..
				weapon.mode
			)

		card.frame.Visible =
			query == "" or
			string.find(
				searchable,
				query,
				1,
				true
			) ~= nil
	end
end

Search:GetPropertyChangedSignal("Text"):Connect(updateSearch)

--==============================================================
-- MINIMIZADO
--==============================================================

local Mini = Instance.new("TextButton")
Mini.Name = "Mini"
Mini.AnchorPoint = Vector2.new(0.5, 0.5)
Mini.Position = UDim2.fromScale(0.5, 0.5)
Mini.Size = UDim2.fromOffset(54, 54)
Mini.BackgroundColor3 = COLORS.BG
Mini.Text = "C"
Mini.TextColor3 = COLORS.WHITE
Mini.TextSize = 21
Mini.Font = Enum.Font.GothamBold
Mini.Visible = false
Mini.AutoButtonColor = false
Mini.Parent = Gui

corner(Mini, 15)
stroke(Mini, 0.15)

Minimize.MouseButton1Click:Connect(function()
	Main.Visible = false
	Mini.Position = Main.Position
	Mini.Visible = true
end)

Mini.MouseButton1Click:Connect(function()
	Mini.Visible = false
	Main.Visible = true
end)

Close.MouseButton1Click:Connect(function()
	Gui:Destroy()
end)

--==============================================================
-- ARRASTAR
--==============================================================

local function makeDraggable(handle, object)
	local dragging = false
	local dragStart
	local startPosition
	local dragInput

	handle.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1 or
			input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPosition = object.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement or
			input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if
			dragging and
			input == dragInput and
			dragStart and
			startPosition
		then
			local delta =
				input.Position -
				dragStart

			object.Position =
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
		end
	end)
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)
