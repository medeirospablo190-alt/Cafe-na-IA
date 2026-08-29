--==============================================================
-- CAFEÍNA • WEAPON RESEARCH SCANNER V1
--
-- Objetivo:
--   Mapear o sistema CLIENTE de armas observando:
--   • Tools
--   • atributos
--   • munição / recarga
--   • RemoteEvents / RemoteFunctions
--   • Muzzle / Barrel / FirePoint
--   • projéteis criados
--   • sons / partículas
--   • equipar / ativar / desequipar
--   • mudanças durante disparos
--
-- NÃO:
--   • executa remotes
--   • intercepta tráfego
--   • altera arma
--   • altera munição
--   • usa hookmetamethod
--   • require() módulos desconhecidos
--
-- Compatível com LocalScript / cliente do próprio jogo.
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {
	MaxRecords = 30000,

	WatchWorkspace = true,
	WatchAttributes = true,
	WatchProjectiles = true,

	ProjectileLifetimeThreshold = 10,

	InterestingWords = {
		"weapon",
		"gun",
		"blaster",
		"shoot",
		"shot",
		"fire",
		"bullet",
		"projectile",
		"ammo",
		"reload",
		"hit",
		"damage",
		"muzzle",
		"barrel",
		"tracer",
		"ray",
		"impact",
		"spread",
		"recoil",
		"viewmodel",
	}
}

--==============================================================
-- STATE
--==============================================================

local Running = false
local Records = {}
local Connections = {}
local Watched = {}

local StartTime = 0

--==============================================================
-- HELPERS
--==============================================================

local function now()
	return os.clock() - StartTime
end

local function pathOf(object)
	if not object then
		return "nil"
	end

	local ok, result = pcall(function()
		return object:GetFullName()
	end)

	return ok and result or tostring(object)
end

local function cleanValue(value)
	local valueType = typeof(value)

	if valueType == "Vector3" then
		return {
			x = value.X,
			y = value.Y,
			z = value.Z
		}
	end

	if valueType == "Vector2" then
		return {
			x = value.X,
			y = value.Y
		}
	end

	if valueType == "CFrame" then
		return {
			position = {
				x = value.Position.X,
				y = value.Position.Y,
				z = value.Position.Z
			}
		}
	end

	if valueType == "Color3" then
		return {
			r = value.R,
			g = value.G,
			b = value.B
		}
	end

	if valueType == "Instance" then
		return pathOf(value)
	end

	if
		valueType == "string"
		or valueType == "number"
		or valueType == "boolean"
		or value == nil
	then
		return value
	end

	return tostring(value)
end

local function addRecord(kind, data)
	if not Running then
		return
	end

	if #Records >= CONFIG.MaxRecords then
		Running = false
		return
	end

	data = data or {}

	data.kind = kind
	data.time = math.floor(now() * 1000) / 1000

	table.insert(Records, data)
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Connections, connection)

	return connection
end

local function disconnectAll()
	for _, connection in ipairs(Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	table.clear(Connections)
	table.clear(Watched)
end

local function containsInterestingWord(text)
	text = string.lower(tostring(text or ""))

	for _, word in ipairs(CONFIG.InterestingWords) do
		if string.find(text, word, 1, true) then
			return true
		end
	end

	return false
end

local function getAttributesSafe(object)
	local result = {}

	local ok, attributes = pcall(function()
		return object:GetAttributes()
	end)

	if ok then
		for key, value in pairs(attributes) do
			result[key] = cleanValue(value)
		end
	end

	return result
end

--==============================================================
-- REMOTES
--==============================================================

local function scanRemotes(container)
	for _, object in ipairs(container:GetDescendants()) do
		if
			object:IsA("RemoteEvent")
			or object:IsA("RemoteFunction")
			or object:IsA("UnreliableRemoteEvent")
		then
			addRecord("remote", {
				class = object.ClassName,
				name = object.Name,
				path = pathOf(object),
				attributes = getAttributesSafe(object)
			})
		end
	end
end

--==============================================================
-- MODULE / SCRIPT MAP
--==============================================================

local function scanScripts(container)
	for _, object in ipairs(container:GetDescendants()) do
		if
			object:IsA("LocalScript")
			or object:IsA("ModuleScript")
		then

			if
				containsInterestingWord(object.Name)
				or containsInterestingWord(pathOf(object))
			then
				addRecord("weapon_script_candidate", {
					class = object.ClassName,
					name = object.Name,
					path = pathOf(object),
					attributes = getAttributesSafe(object)
				})
			end
		end
	end
end

--==============================================================
-- PART DETECTION
--==============================================================

local function isWeaponPart(object)
	local name = string.lower(object.Name)

	return
		string.find(name, "muzzle", 1, true)
		or string.find(name, "barrel", 1, true)
		or string.find(name, "firepoint", 1, true)
		or string.find(name, "fire_point", 1, true)
		or string.find(name, "shootpoint", 1, true)
		or string.find(name, "shoot_point", 1, true)
		or string.find(name, "origin", 1, true)
end

local function scanWeaponParts(tool)
	for _, object in ipairs(tool:GetDescendants()) do
		if object:IsA("BasePart") or object:IsA("Attachment") then
			if isWeaponPart(object) then

				local position

				if object:IsA("Attachment") then
					position = object.WorldPosition
				else
					position = object.Position
				end

				addRecord("weapon_origin_candidate", {
					name = object.Name,
					class = object.ClassName,
					path = pathOf(object),
					position = cleanValue(position)
				})
			end
		end
	end
end

--==============================================================
-- ATTRIBUTE WATCH
--==============================================================

local function watchAttributes(object)
	if not CONFIG.WatchAttributes then
		return
	end

	local ok, attributes = pcall(function()
		return object:GetAttributes()
	end)

	if not ok then
		return
	end

	for attributeName in pairs(attributes) do
		connect(
			object:GetAttributeChangedSignal(attributeName),
			function()

				addRecord("attribute_changed", {
					object = pathOf(object),
					class = object.ClassName,
					attribute = attributeName,
					value = cleanValue(
						object:GetAttribute(attributeName)
					)
				})

			end
		)
	end
end

--==============================================================
-- VALUEOBJECT WATCH
--==============================================================

local function watchValueObject(object)
	if not object:IsA("ValueBase") then
		return
	end

	connect(
		object.Changed,
		function(value)

			addRecord("value_changed", {
				path = pathOf(object),
				class = object.ClassName,
				name = object.Name,
				value = cleanValue(value)
			})

		end
	)
end

--==============================================================
-- EFFECT WATCH
--==============================================================

local function watchEffects(object)
	if object:IsA("Sound") then

		connect(
			object.Played,
			function()

				addRecord("sound_played", {
					path = pathOf(object),
					name = object.Name,
					soundId = object.SoundId,
					volume = object.Volume,
					playbackSpeed = object.PlaybackSpeed
				})

			end
		)

	elseif object:IsA("ParticleEmitter") then

		connect(
			object:GetPropertyChangedSignal("Enabled"),
			function()

				addRecord("particle_enabled", {
					path = pathOf(object),
					enabled = object.Enabled
				})

			end
		)

	end
end

--==============================================================
-- TOOL WATCH
--==============================================================

local function watchTool(tool)
	if Watched[tool] then
		return
	end

	Watched[tool] = true

	addRecord("tool_detected", {
		name = tool.Name,
		path = pathOf(tool),
		attributes = getAttributesSafe(tool)
	})

	scanWeaponParts(tool)

	watchAttributes(tool)

	for _, object in ipairs(tool:GetDescendants()) do
		watchAttributes(object)
		watchValueObject(object)
		watchEffects(object)
	end

	connect(
		tool.DescendantAdded,
		function(object)

			addRecord("tool_descendant_added", {
				tool = tool.Name,
				class = object.ClassName,
				name = object.Name,
				path = pathOf(object)
			})

			watchAttributes(object)
			watchValueObject(object)
			watchEffects(object)

			if
				object:IsA("BasePart")
				or object:IsA("Attachment")
			then
				if isWeaponPart(object) then
					addRecord("weapon_origin_candidate", {
						name = object.Name,
						class = object.ClassName,
						path = pathOf(object)
					})
				end
			end

		end
	)

	connect(
		tool.Equipped,
		function()

			addRecord("tool_equipped", {
				name = tool.Name,
				path = pathOf(tool),
				attributes = getAttributesSafe(tool)
			})

		end
	)

	connect(
		tool.Unequipped,
		function()

			addRecord("tool_unequipped", {
				name = tool.Name
			})

		end
	)

	connect(
		tool.Activated,
		function()

			addRecord("tool_activated", {
				name = tool.Name,
				attributes = getAttributesSafe(tool)
			})

		end
	)

	connect(
		tool.Deactivated,
		function()

			addRecord("tool_deactivated", {
				name = tool.Name,
				attributes = getAttributesSafe(tool)
			})

		end
	)
end

--==============================================================
-- PLAYER TOOL DISCOVERY
--==============================================================

local function scanPlayerTools()
	local backpack =
		LocalPlayer:FindFirstChildOfClass("Backpack")

	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				watchTool(child)
			end
		end

		connect(
			backpack.ChildAdded,
			function(child)

				if child:IsA("Tool") then
					watchTool(child)
				end

			end
		)
	end

	if LocalPlayer.Character then
		for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
			if child:IsA("Tool") then
				watchTool(child)
			end
		end
	end

	connect(
		LocalPlayer.CharacterAdded,
		function(character)

			connect(
				character.ChildAdded,
				function(child)

					if child:IsA("Tool") then
						watchTool(child)
					end

				end
			)

		end
	)
end

--==============================================================
-- PROJECTILE DETECTION
--==============================================================

local function looksLikeProjectile(object)
	if not CONFIG.WatchProjectiles then
		return false
	end

	local text =
		string.lower(
			object.Name
			.. " "
			.. object.ClassName
		)

	return
		string.find(text, "bullet", 1, true)
		or string.find(text, "projectile", 1, true)
		or string.find(text, "tracer", 1, true)
		or string.find(text, "rocket", 1, true)
		or string.find(text, "shell", 1, true)
end

local function inspectWorkspaceAddition(object)
	if looksLikeProjectile(object) then

		local position

		if object:IsA("BasePart") then
			position = cleanValue(object.Position)
		end

		addRecord("projectile_candidate_created", {
			name = object.Name,
			class = object.ClassName,
			path = pathOf(object),
			position = position,
			attributes = getAttributesSafe(object)
		})
	end

	if
		object:IsA("Sound")
		and containsInterestingWord(pathOf(object))
	then
		watchEffects(object)
	end
end

--==============================================================
-- GLOBAL OBJECT SNAPSHOT
--==============================================================

local function scanInterestingObjects(container)
	for _, object in ipairs(container:GetDescendants()) do

		local interesting =
			containsInterestingWord(object.Name)
			or containsInterestingWord(pathOf(object))

		if interesting then

			if
				object:IsA("Folder")
				or object:IsA("Configuration")
				or object:IsA("Model")
				or object:IsA("ModuleScript")
				or object:IsA("LocalScript")
				or object:IsA("Attachment")
				or object:IsA("ValueBase")
			then

				addRecord("interesting_object", {
					name = object.Name,
					class = object.ClassName,
					path = pathOf(object),
					attributes = getAttributesSafe(object)
				})

			end

		end
	end
end

--==============================================================
-- SCAN
--==============================================================

local function startScan()
	disconnectAll()

	table.clear(Records)

	Running = true
	StartTime = os.clock()

	addRecord("scan_started", {
		placeId = game.PlaceId,
		gameId = game.GameId
	})

	scanRemotes(ReplicatedStorage)
	scanRemotes(ReplicatedFirst)

	scanScripts(ReplicatedStorage)
	scanScripts(ReplicatedFirst)

	pcall(function()
		scanScripts(
			StarterPlayer.StarterPlayerScripts
		)
	end)

	scanInterestingObjects(
		ReplicatedStorage
	)

	scanPlayerTools()

	if CONFIG.WatchWorkspace then
		connect(
			Workspace.DescendantAdded,
			inspectWorkspaceAddition
		)
	end

	addRecord("initial_scan_complete", {
		records = #Records
	})
end

local function stopScan()
	addRecord("scan_stopped", {
		records = #Records
	})

	Running = false

	disconnectAll()
end

--==============================================================
-- REPORT
--==============================================================

local function buildReport()
	local equippedTool

	if LocalPlayer.Character then
		equippedTool =
			LocalPlayer.Character:
				FindFirstChildOfClass("Tool")
	end

	local report = {
		schemaVersion = 1,

		scanner =
			"CAFEINA_WEAPON_RESEARCH_V1",

		placeId =
			game.PlaceId,

		gameId =
			game.GameId,

		generatedAt =
			os.date("!%Y-%m-%dT%H:%M:%SZ"),

		equippedTool =
			equippedTool
			and equippedTool.Name
			or nil,

		recordCount =
			#Records,

		records =
			Records
	}

	local success, json =
		pcall(
			HttpService.JSONEncode,
			HttpService,
			report
		)

	if success then
		return json
	end

	return nil
end

--==============================================================
-- GUI
--==============================================================

local old =
	PlayerGui:FindFirstChild(
		"CafeinaWeaponScanner"
	)

if old then
	old:Destroy()
end

local Gui =
	Instance.new("ScreenGui")

Gui.Name =
	"CafeinaWeaponScanner"

Gui.ResetOnSpawn =
	false

Gui.Parent =
	PlayerGui

local Main =
	Instance.new("Frame")

Main.Size =
	UDim2.fromOffset(300, 210)

Main.Position =
	UDim2.new(
		0.5,
		-150,
		0.5,
		-105
	)

Main.BackgroundColor3 =
	Color3.fromRGB(
		17,
		18,
		22
	)

Main.BorderSizePixel =
	0

Main.Parent =
	Gui

local Corner =
	Instance.new("UICorner")

Corner.CornerRadius =
	UDim.new(0, 14)

Corner.Parent =
	Main

local Title =
	Instance.new("TextLabel")

Title.Size =
	UDim2.new(
		1,
		-20,
		0,
		40
	)

Title.Position =
	UDim2.fromOffset(10, 5)

Title.BackgroundTransparency =
	1

Title.Text =
	"CAFEÍNA • WEAPON SCANNER"

Title.TextColor3 =
	Color3.new(1, 1, 1)

Title.Font =
	Enum.Font.GothamBold

Title.TextSize =
	15

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent =
	Main

local Status =
	Instance.new("TextLabel")

Status.Size =
	UDim2.new(
		1,
		-20,
		0,
		32
	)

Status.Position =
	UDim2.fromOffset(10, 42)

Status.BackgroundTransparency =
	1

Status.Text =
	"Pronto"

Status.TextColor3 =
	Color3.fromRGB(
		200,
		200,
		200
	)

Status.Font =
	Enum.Font.Gotham

Status.TextSize =
	13

Status.TextXAlignment =
	Enum.TextXAlignment.Left

Status.Parent =
	Main

local function createButton(text, y)
	local Button =
		Instance.new("TextButton")

	Button.Size =
		UDim2.new(
			1,
			-20,
			0,
			38
		)

	Button.Position =
		UDim2.fromOffset(
			10,
			y
		)

	Button.BackgroundColor3 =
		Color3.fromRGB(
			36,
			38,
			44
		)

	Button.BorderSizePixel =
		0

	Button.Text =
		text

	Button.TextColor3 =
		Color3.new(1, 1, 1)

	Button.Font =
		Enum.Font.GothamSemibold

	Button.TextSize =
		13

	Button.Parent =
		Main

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(0, 9)

	corner.Parent =
		Button

	return Button
end

local StartButton =
	createButton(
		"INICIAR CAPTURA",
		78
	)

local StopButton =
	createButton(
		"PARAR CAPTURA",
		122
	)

local CopyButton =
	createButton(
		"COPIAR RELATÓRIO",
		166
	)

StartButton.Activated:
	Connect(function()

		startScan()

		Status.Text =
			"Capturando... equipe, atire e recarregue"

	end)

StopButton.Activated:
	Connect(function()

		stopScan()

		Status.Text =
			"Parado • "
			.. tostring(#Records)
			.. " registros"

	end)

CopyButton.Activated:
	Connect(function()

		local report =
			buildReport()

		if not report then
			Status.Text =
				"Erro ao gerar JSON"

			return
		end

		if setclipboard then

			setclipboard(report)

			Status.Text =
				"Copiado • "
				.. tostring(#Records)
				.. " registros"

		else

			Status.Text =
				"setclipboard indisponível"

			print(report)

		end

	end)

--==============================================================
-- DRAG MOBILE / PC
--==============================================================

local dragging = false
local dragStart
local startPosition

Main.InputBegan:
	Connect(function(input)

		if
			input.UserInputType
				== Enum.UserInputType.Touch
			or
			input.UserInputType
				== Enum.UserInputType.MouseButton1
		then

			dragging = true
			dragStart = input.Position
			startPosition = Main.Position

		end

	end)

UserInputService.InputChanged:
	Connect(function(input)

		if not dragging then
			return
		end

		if
			input.UserInputType
				~= Enum.UserInputType.Touch
			and
			input.UserInputType
				~= Enum.UserInputType.MouseMovement
		then
			return
		end

		local delta =
			input.Position - dragStart

		Main.Position =
			UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset
					+ delta.X,

				startPosition.Y.Scale,
				startPosition.Y.Offset
					+ delta.Y
			)

	end)

UserInputService.InputEnded:
	Connect(function(input)

		if
			input.UserInputType
				== Enum.UserInputType.Touch
			or
			input.UserInputType
				== Enum.UserInputType.MouseButton1
		then

			dragging = false

		end

	end)
