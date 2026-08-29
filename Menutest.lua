--[[
================================================================
 CAFEÍNA • WEAPON RESEARCH V2 CONTINUOUS
 Focused Ballistics / Cast / Piercing Research

 OBJETIVO
 ----------------------------------------------------------------
 Coletar continuamente informações CLIENT-VISIBLE sobre:

   • arma equipada
   • atributos da arma
   • _ammo
   • _reloading
   • muzzle
   • câmera
   • posição do personagem
   • efeitos de tiro
   • Beam
   • Trail
   • Attachment
   • ParticleEmitter
   • Sounds
   • impactos
   • raycast architecture
   • BlasterSystem
   • castRays
   • getRayDirections
   • canPierce
   • canDamageTarget
   • canPlayerDamageTarget
   • FastCast
   • Caster
   • ActiveCast
   • remotes relacionados
   • correlação temporal entre tiros / efeitos / ammo

 MENU
 ----------------------------------------------------------------
   INICIAR
   INTERROMPER
   ENVIAR

 IMPORTANTE
 ----------------------------------------------------------------
   NÃO:
     • FireServer
     • InvokeServer
     • altera munição
     • altera armas
     • causa dano
     • executa compras
     • executa remotes administrativos
     • modifica objetos do jogo

 O require() é usado APENAS em módulos explicitamente selecionados
 para tentar descobrir exports e assinaturas via debug.info().

================================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Workspace =
	game:GetService("Workspace")

local HttpService =
	game:GetService("HttpService")

local RunService =
	game:GetService("RunService")

local UserInputService =
	game:GetService("UserInputService")


--==============================================================
-- LOCAL PLAYER
--==============================================================

local LocalPlayer =
	Players.LocalPlayer


if not LocalPlayer then

	warn(
		"[CAFEÍNA] LocalPlayer não encontrado."
	)

	return

end


local PlayerGui =
	LocalPlayer:WaitForChild(
		"PlayerGui"
	)


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

	Scanner =
		"CAFEINA_WEAPON_RESEARCH_V2_CONTINUOUS",

	Version =
		"2.0",

	SchemaVersion =
		3,


	----------------------------------------------------------
	-- LIMITE
	----------------------------------------------------------

	MaxApproxBytes =
		150 * 1024 * 1024,


	MaxRecords =
		500000,


	----------------------------------------------------------
	-- LOOP
	----------------------------------------------------------

	SnapshotInterval =
		0.20,


	SlowSnapshotInterval =
		1.0,


	UIUpdateInterval =
		0.15,


	----------------------------------------------------------
	-- SHOT CORRELATION
	----------------------------------------------------------

	ShotCorrelationWindow =
		0.35,


	EffectCorrelationWindow =
		0.50,


	----------------------------------------------------------
	-- STRUCTURE
	----------------------------------------------------------

	MaxModuleDepth =
		6,


	MaxTableEntries =
		300,


	----------------------------------------------------------
	-- UPLOAD
	--
	-- Coloque aqui o endpoint do seu servidor.
	--
	-- Exemplo:
	-- https://seusite.com/api/upload
	--
	-- O servidor pode retornar:
	--
	-- {
	--   "ok": true,
	--   "url": "https://..."
	-- }
	--
	----------------------------------------------------------

	UploadURL =
		"",


	UploadField =
		"data",


	----------------------------------------------------------
	-- MODULE TARGETS
	----------------------------------------------------------

	ModuleTargets = {

		castrays = true,

		getraydirections = true,

		canpierce = true,

		candamagetarget = true,

		canplayerdamagetarget = true,

		blastercontroller = true,

		blasterextension = true,

		caster = true,

		fastcastredux = true,

		activecast = true,

		serialization = true,

		shotreplication = true,

		soundreplication = true,

		constants = true,
	},


	----------------------------------------------------------
	-- EFFECT CLASSES
	----------------------------------------------------------

	EffectClasses = {

		Beam = true,

		Trail = true,

		Attachment = true,

		ParticleEmitter = true,

		Sound = true,

		PointLight = true,

		SurfaceLight = true,

		SpotLight = true,
	},


	----------------------------------------------------------
	-- NAMES
	----------------------------------------------------------

	InterestingTerms = {

		"shoot",

		"shot",

		"bullet",

		"projectile",

		"impact",

		"hit",

		"damage",

		"ray",

		"cast",

		"pierce",

		"penetr",

		"muzzle",

		"tracer",

		"beam",

		"trail",

		"reload",

		"ammo",

		"blaster",

		"weapon",
	},
}


--==============================================================
-- STATE
--==============================================================

local State = {

	Running = false,

	Interrupted = false,

	Uploading = false,

	BaselineDone = false,


	StartedClock = 0,

	LastFastSnapshot = 0,

	LastSlowSnapshot = 0,

	LastShotClock = 0,

	LastEffectClock = 0,


	Passes = 0,

	Records = {},

	ApproxBytes = 0,


	CurrentTool = nil,

	CurrentToolConnections = {},

	GlobalConnections = {},


	LastAmmo = nil,

	LastReloading = nil,

	LastToolName = nil,


	ShotCounter = 0,

	EffectCounter = 0,

	RemoteCounter = 0,

	ModuleCounter = 0,

	SignatureCounter = 0,

	ErrorCounter = 0,


	LastUploadLink = nil,
}


--==============================================================
-- HELPERS
--==============================================================

local function clock()

	return os.clock()

end


local function elapsed()

	if State.StartedClock == 0 then
		return 0
	end

	return clock()
		- State.StartedClock

end


local function safeString(value)

	local ok, result =
		pcall(
			tostring,
			value
		)


	if ok then
		return result
	end


	return "<tostring-error>"

end


local function fullPath(object)

	if not object then
		return nil
	end


	local ok, result =
		pcall(function()

			return object:GetFullName()

		end)


	if ok then
		return result
	end


	return object.Name

end


local function approxRecordBytes(record)

	local total =
		30


	for key, value
		in pairs(record)
	do

		total +=
			#safeString(key)

		total +=
			#safeString(value)

		total +=
			8

	end


	return total

end


local function addRecord(record)

	if not State.Running then
		return false
	end


	if State.Interrupted then
		return false
	end


	if #State.Records >=
		CONFIG.MaxRecords
	then

		State.Interrupted =
			true


		return false

	end


	record.time =
		elapsed()


	local addedBytes =
		approxRecordBytes(
			record
		)


	if State.ApproxBytes
		+ addedBytes
		>= CONFIG.MaxApproxBytes
	then

		State.Interrupted =
			true


		return false

	end


	State.ApproxBytes +=
		addedBytes


	State.Records[
		#State.Records + 1
	] = record


	return true

end


local function bytesText(bytes)

	if bytes <
		1024
	then

		return tostring(bytes)
			.. " B"

	end


	if bytes <
		1024 * 1024
	then

		return string.format(
			"%.1f KB",
			bytes / 1024
		)

	end


	return string.format(
		"%.2f MB",
		bytes / 1024 / 1024
	)

end


--==============================================================
-- SAFE VALUE SERIALIZATION
--==============================================================

local function serializeValue(value)

	local valueType =
		typeof(value)


	if valueType == "Vector3" then

		return {

			type =
				"Vector3",

			x =
				value.X,

			y =
				value.Y,

			z =
				value.Z,
		}

	end


	if valueType == "Vector2" then

		return {

			type =
				"Vector2",

			x =
				value.X,

			y =
				value.Y,
		}

	end


	if valueType == "CFrame" then

		local position =
			value.Position


		local look =
			value.LookVector


		return {

			type =
				"CFrame",

			position = {

				x =
					position.X,

				y =
					position.Y,

				z =
					position.Z,
			},

			lookVector = {

				x =
					look.X,

				y =
					look.Y,

				z =
					look.Z,
			},
		}

	end


	if valueType == "Color3" then

		return {

			type =
				"Color3",

			r =
				value.R,

			g =
				value.G,

			b =
				value.B,
		}

	end


	if valueType == "Instance" then

		return {

			type =
				"Instance",

			class =
				value.ClassName,

			path =
				fullPath(value),
		}

	end


	if
		valueType == "number"
		or
		valueType == "string"
		or
		valueType == "boolean"
		or
		value == nil
	then

		return value

	end


	return safeString(value)

end


--==============================================================
-- ATTRIBUTES
--==============================================================

local function snapshotAttributes(
	object
)

	local output = {}


	local ok, attributes =
		pcall(function()

			return object:GetAttributes()

		end)


	if not ok then
		return output
	end


	for key, value
		in pairs(attributes)
	do

		output[key] =
			serializeValue(
				value
			)

	end


	return output

end


--==============================================================
-- INTERESTING NAME
--==============================================================

local function interestingName(name)

	name =
		string.lower(
			name or ""
		)


	for _, term
		in ipairs(
			CONFIG.InterestingTerms
		)
	do

		if string.find(
			name,
			term,
			1,
			true
		) then

			return true,
				term

		end

	end


	return false,
		nil

end


--==============================================================
-- CHARACTER
--==============================================================

local function getCharacter()

	return LocalPlayer.Character

end


local function getRoot()

	local character =
		getCharacter()


	if not character then
		return nil
	end


	return character:
		FindFirstChild(
			"HumanoidRootPart"
		)

end


local function getHumanoid()

	local character =
		getCharacter()


	if not character then
		return nil
	end


	return character:
		FindFirstChildOfClass(
			"Humanoid"
		)

end


--==============================================================
-- EQUIPPED TOOL
--==============================================================

local function getEquippedTool()

	local character =
		getCharacter()


	if not character then
		return nil
	end


	for _, child
		in ipairs(
			character:GetChildren()
		)
	do

		if child:IsA(
			"Tool"
		) then

			return child

		end

	end


	return nil

end


--==============================================================
-- FIND MUZZLE
--==============================================================

local function findMuzzle(tool)

	if not tool then
		return nil
	end


	local preferred = {

		"Muzzle",

		"MuzzleAttachment",

		"FirePoint",

		"Barrel",

		"GunMuzzle",

	}


	for _, name
		in ipairs(preferred)
	do

		local found =
			tool:
			FindFirstChild(
				name,
				true
			)


		if found then
			return found
		end

	end


	return nil

end


--==============================================================
-- OBJECT TRANSFORM
--==============================================================

local function objectPosition(
	object
)

	if not object then
		return nil
	end


	if object:IsA(
		"Attachment"
	) then

		return serializeValue(
			object.WorldCFrame
		)

	end


	if object:IsA(
		"BasePart"
	) then

		return serializeValue(
			object.CFrame
		)

	end


	return nil

end


--==============================================================
-- CAMERA SNAPSHOT
--==============================================================

local function cameraSnapshot()

	local camera =
		Workspace.CurrentCamera


	if not camera then
		return nil
	end


	return {

		cframe =
			serializeValue(
				camera.CFrame
			),

		fov =
			camera.FieldOfView,

		cameraType =
			camera.CameraType.Name,
	}

end


--==============================================================
-- CHARACTER SNAPSHOT
--==============================================================

local function characterSnapshot()

	local root =
		getRoot()


	local humanoid =
		getHumanoid()


	local output = {}


	if root then

		output.root =
			serializeValue(
				root.CFrame
			)

	end


	if humanoid then

		output.health =
			humanoid.Health

		output.state =
			humanoid:
			GetState()
			.Name

	end


	return output

end


--==============================================================
-- TOOL SNAPSHOT
--==============================================================

local function toolSnapshot(
	tool,
	reason
)

	if not tool then
		return
	end


	local muzzle =
		findMuzzle(tool)


	addRecord({

		kind =
			"tool_snapshot",

		reason =
			reason,

		name =
			tool.Name,

		path =
			fullPath(tool),

		attributes =
			snapshotAttributes(
				tool
			),

		muzzle =
			muzzle
			and
			{

				name =
					muzzle.Name,

				class =
					muzzle.ClassName,

				path =
					fullPath(
						muzzle
					),

				transform =
					objectPosition(
						muzzle
					),
			}
			or nil,

		camera =
			cameraSnapshot(),

		character =
			characterSnapshot(),
	})

end


--==============================================================
-- SHOT EVENT
--==============================================================

local function markShot(
	tool,
	reason,
	oldAmmo,
	newAmmo
)

	State.ShotCounter += 1

	State.LastShotClock =
		clock()


	local muzzle =
		findMuzzle(tool)


	addRecord({

		kind =
			"shot_candidate",

		shotId =
			State.ShotCounter,

		reason =
			reason,

		weapon =
			tool
			and
			tool.Name
			or nil,

		oldAmmo =
			oldAmmo,

		newAmmo =
			newAmmo,

		attributes =
			tool
			and
			snapshotAttributes(
				tool
			)
			or nil,

		muzzle =
			muzzle
			and
			{

				path =
					fullPath(
						muzzle
					),

				transform =
					objectPosition(
						muzzle
					),
			}
			or nil,

		camera =
			cameraSnapshot(),

		character =
			characterSnapshot(),
	})

end


--==============================================================
-- CORRELATION
--==============================================================

local function shotDelta()

	if State.LastShotClock == 0 then
		return nil
	end


	return clock()
		- State.LastShotClock

end


local function nearShot()

	local delta =
		shotDelta()


	return delta
		and
		delta <=
		CONFIG.EffectCorrelationWindow

end


--==============================================================
-- TOOL CONNECTION CLEANUP
--==============================================================

local function disconnectToolConnections()

	for _, connection
		in ipairs(
			State.CurrentToolConnections
		)
	do

		pcall(function()

			connection:
				Disconnect()

		end)

	end


	table.clear(
		State.CurrentToolConnections
	)

end


local function trackToolConnection(
	connection
)

	State.CurrentToolConnections[
		#State.CurrentToolConnections + 1
	] = connection

end


--==============================================================
-- TOOL EFFECT
--==============================================================

local function recordToolEffect(
	object,
	action
)

	if not State.Running then
		return
	end


	local interesting =
		CONFIG.EffectClasses[
			object.ClassName
		]


	local matched,
	term =
		interestingName(
			object.Name
		)


	if not interesting
		and
		not matched
	then

		return

	end


	State.EffectCounter += 1

	State.LastEffectClock =
		clock()


	addRecord({

		kind =
			"tool_effect",

		action =
			action,

		effectId =
			State.EffectCounter,

		class =
			object.ClassName,

		name =
			object.Name,

		path =
			fullPath(object),

		nameMatch =
			term,

		nearShot =
			nearShot(),

		shotDelta =
			shotDelta(),

		attributes =
			snapshotAttributes(
				object
			),
	})

end


--==============================================================
-- WATCH TOOL
--==============================================================

local function watchTool(tool)

	disconnectToolConnections()


	State.CurrentTool =
		tool


	State.LastAmmo =
		nil


	State.LastReloading =
		nil


	if not tool then

		addRecord({

			kind =
				"tool_unequipped",
		})


		return

	end


	State.LastToolName =
		tool.Name


	State.LastAmmo =
		tool:
		GetAttribute(
			"_ammo"
		)


	State.LastReloading =
		tool:
		GetAttribute(
			"_reloading"
		)


	addRecord({

		kind =
			"tool_equipped",

		name =
			tool.Name,

		path =
			fullPath(tool),

		attributes =
			snapshotAttributes(
				tool
			),
	})


	toolSnapshot(
		tool,
		"equipped"
	)


	----------------------------------------------------------
	-- ATTRIBUTE CHANGED
	----------------------------------------------------------

	trackToolConnection(

		tool.AttributeChanged:
		Connect(function(
			attributeName
		)

			if not State.Running then
				return
			end


			local value =
				tool:
				GetAttribute(
					attributeName
				)


			addRecord({

				kind =
					"attribute_change",

				weapon =
					tool.Name,

				attribute =
					attributeName,

				value =
					serializeValue(
						value
					),
			})


			--------------------------------------------------
			-- AMMO
			--------------------------------------------------

			if attributeName ==
				"_ammo"
			then

				local oldAmmo =
					State.LastAmmo


				local newAmmo =
					value


				State.LastAmmo =
					newAmmo


				if
					type(oldAmmo)
						== "number"

					and

					type(newAmmo)
						== "number"

					and

					newAmmo <
						oldAmmo
				then

					markShot(
						tool,
						"ammo_decrease",
						oldAmmo,
						newAmmo
					)

				end

			end


			--------------------------------------------------
			-- RELOAD
			--------------------------------------------------

			if attributeName ==
				"_reloading"
			then

				addRecord({

					kind =
						"reload_state",

					weapon =
						tool.Name,

					old =
						State.LastReloading,

					new =
						value,

					ammo =
						tool:
						GetAttribute(
							"_ammo"
						),
				})


				State.LastReloading =
					value

			end

		end)

	)


	----------------------------------------------------------
	-- DESCENDANT ADDED
	----------------------------------------------------------

	trackToolConnection(

		tool.DescendantAdded:
		Connect(function(object)

			recordToolEffect(
				object,
				"added"
			)

		end)

	)


	----------------------------------------------------------
	-- DESCENDANT REMOVING
	----------------------------------------------------------

	trackToolConnection(

		tool.DescendantRemoving:
		Connect(function(object)

			recordToolEffect(
				object,
				"removing"
			)

		end)

	)


	----------------------------------------------------------
	-- EXISTING DESCENDANTS
	----------------------------------------------------------

	for _, object
		in ipairs(
			tool:GetDescendants()
		)
	do

		if
			CONFIG.EffectClasses[
				object.ClassName
			]
		then

			addRecord({

				kind =
					"tool_descendant_baseline",

				weapon =
					tool.Name,

				name =
					object.Name,

				class =
					object.ClassName,

				path =
					fullPath(
						object
					),
			})

		end

	end

end


--==============================================================
-- REFRESH TOOL
--==============================================================

local function refreshEquippedTool()

	local tool =
		getEquippedTool()


	if tool ~=
		State.CurrentTool
	then

		watchTool(tool)

	end

end


--==============================================================
-- WORKSPACE EFFECT FILTER
--==============================================================

local function workspaceEffectRelevant(
	object
)

	if
		CONFIG.EffectClasses[
			object.ClassName
		]
	then

		return true
	end


	local matched =
		interestingName(
			object.Name
		)


	return matched

end


--==============================================================
-- WORKSPACE EFFECT
--==============================================================

local function recordWorkspaceEffect(
	object
)

	if not State.Running then
		return
	end


	if not
		workspaceEffectRelevant(
			object
		)
	then

		return

	end


	----------------------------------------------------------
	-- Prefer objects created near a recent shot
	----------------------------------------------------------

	local correlated =
		nearShot()


	local matched,
	term =
		interestingName(
			object.Name
		)


	if not correlated
		and
		not matched
	then

		return

	end


	State.EffectCounter += 1


	addRecord({

		kind =
			"workspace_effect",

		effectId =
			State.EffectCounter,

		name =
			object.Name,

		class =
			object.ClassName,

		path =
			fullPath(object),

		nameMatch =
			term,

		nearShot =
			correlated,

		shotDelta =
			shotDelta(),

		transform =
			objectPosition(
				object
			),

		attributes =
			snapshotAttributes(
				object
			),
	})

end


--==============================================================
-- GLOBAL CONNECTION
--==============================================================

local function trackGlobalConnection(
	connection
)

	State.GlobalConnections[
		#State.GlobalConnections + 1
	] = connection

end


local function disconnectGlobalConnections()

	for _, connection
		in ipairs(
			State.GlobalConnections
		)
	do

		pcall(function()

			connection:
				Disconnect()

		end)

	end


	table.clear(
		State.GlobalConnections
	)

end


--==============================================================
-- REMOTES
--==============================================================

local function isRemote(object)

	if object:IsA(
		"RemoteEvent"
	) then

		return true

	end


	if object:IsA(
		"RemoteFunction"
	) then

		return true

	end


	local ok,
		result =
		pcall(function()

			return object:IsA(
				"UnreliableRemoteEvent"
			)

		end)


	return ok
		and
		result

end


local function relevantRemote(
	object
)

	if not isRemote(object) then
		return false
	end


	local matched =
		interestingName(
			object.Name
		)


	return matched

end


local function recordRemote(
	object,
	reason
)

	if not relevantRemote(
		object
	) then

		return

	end


	State.RemoteCounter += 1


	addRecord({

		kind =
			"remote",

		reason =
			reason,

		id =
			State.RemoteCounter,

		name =
			object.Name,

		class =
			object.ClassName,

		path =
			fullPath(
				object
			),

		attributes =
			snapshotAttributes(
				object
			),
	})

end


--==============================================================
-- DEBUG INFO
--==============================================================

local function inspectFunction(
	fn,
	modulePath,
	exportPath
)

	if typeof(fn)
		~= "function"
	then

		return

	end


	State.SignatureCounter += 1


	local record = {

		kind =
			"function_signature",

		id =
			State.SignatureCounter,

		module =
			modulePath,

		export =
			exportPath,
	}


	if
		type(debug)
			== "table"

		and

		type(debug.info)
			== "function"
	then

		------------------------------------------------------
		-- NAME
		------------------------------------------------------

		pcall(function()

			record.debugName =
				debug.info(
					fn,
					"n"
				)

		end)


		------------------------------------------------------
		-- ARGS
		------------------------------------------------------

		pcall(function()

			local count,
				vararg =
				debug.info(
					fn,
					"a"
				)


			record.numParams =
				count


			record.isVararg =
				vararg

		end)


		------------------------------------------------------
		-- SOURCE
		------------------------------------------------------

		pcall(function()

			record.source =
				debug.info(
					fn,
					"s"
				)

		end)

	end


	addRecord(record)

end


--==============================================================
-- EXPORT WALK
--==============================================================

local function walkExport(
	value,
	modulePath,
	exportPath,
	visited,
	depth
)

	if depth >
		CONFIG.MaxModuleDepth
	then

		return

	end


	if State.Interrupted then
		return
	end


	local valueType =
		typeof(value)


	if valueType ==
		"function"
	then

		inspectFunction(
			value,
			modulePath,
			exportPath
		)


		return

	end


	if valueType ~=
		"table"
	then

		return

	end


	if visited[value] then
		return
	end


	visited[value] =
		true


	local count =
		0


	for key, child
		in pairs(value)
	do

		count += 1


		if count >
			CONFIG.MaxTableEntries
		then

			break

		end


		local childPath =
			exportPath
			.. "."
			.. safeString(key)


		addRecord({

			kind =
				"module_export_member",

			module =
				modulePath,

			export =
				childPath,

			valueType =
				typeof(child),
		})


		walkExport(

			child,

			modulePath,

			childPath,

			visited,

			depth + 1

		)

	end

end


--==============================================================
-- MODULE TARGET
--==============================================================

local function isModuleTarget(
	module
)

	if not module:IsA(
		"ModuleScript"
	) then

		return false

	end


	local lower =
		string.lower(
			module.Name
		)


	if
		CONFIG.ModuleTargets[
			lower
		]
	then

		return true

	end


	if string.find(
		lower,
		"cast",
		1,
		true
	) then

		return true

	end


	if string.find(
		lower,
		"pierce",
		1,
		true
	) then

		return true

	end


	return false

end


--==============================================================
-- MODULE INSPECT
--==============================================================

local function inspectModule(
	module
)

	local path =
		fullPath(
			module
		)


	State.ModuleCounter += 1


	addRecord({

		kind =
			"module",

		id =
			State.ModuleCounter,

		name =
			module.Name,

		path =
			path,
	})


	local ok,
		exported =
		pcall(function()

			return require(
				module
			)

		end)


	if not ok then

		State.ErrorCounter += 1


		addRecord({

			kind =
				"module_require_error",

			module =
				path,

			error =
				safeString(
					exported
				),
		})


		return

	end


	addRecord({

		kind =
			"module_export",

		module =
			path,

		exportType =
			typeof(
				exported
			),
	})


	if typeof(exported)
		== "function"
	then

		inspectFunction(
			exported,
			path,
			module.Name
		)

	elseif typeof(exported)
		== "table"
	then

		walkExport(

			exported,

			path,

			module.Name,

			{},

			0

		)

	end

end


--==============================================================
-- BASELINE
--==============================================================

local function baselineScan()

	if State.BaselineDone then
		return
	end


	addRecord({

		kind =
			"baseline_started",
	})


	local roots = {}


	local blaster =
		ReplicatedStorage:
		FindFirstChild(
			"BlasterSystem"
		)


	if blaster then

		roots[
			#roots + 1
		] = blaster

	else

		roots[
			#roots + 1
		] = ReplicatedStorage

	end


	----------------------------------------------------------
	-- MODULES
	----------------------------------------------------------

	for _, root
		in ipairs(roots)
	do

		for _, object
		in ipairs(
			root:GetDescendants()
			)
		do

			if State.Interrupted then
				return
			end


			if isModuleTarget(
				object
			) then

				inspectModule(
					object
				)

			end

		end

	end


	----------------------------------------------------------
	-- REMOTES
	----------------------------------------------------------

	for _, object
		in ipairs(
			ReplicatedStorage:
			GetDescendants()
		)
	do

		if State.Interrupted then
			return
		end


		if relevantRemote(
			object
		) then

			recordRemote(
				object,
				"baseline"
			)

		end

	end


	State.BaselineDone =
		true


	addRecord({

		kind =
			"baseline_finished",

		modules =
			State.ModuleCounter,

		signatures =
			State.SignatureCounter,

		remotes =
			State.RemoteCounter,
	})

end


--==============================================================
-- FAST SNAPSHOT
--==============================================================

local function fastSnapshot()

	refreshEquippedTool()


	local tool =
		State.CurrentTool


	if not tool then
		return
	end


	local ammo =
		tool:
		GetAttribute(
			"_ammo"
		)


	local reload =
		tool:
		GetAttribute(
			"_reloading"
		)


	----------------------------------------------------------
	-- FALLBACK SHOT DETECTION
	----------------------------------------------------------

	if
		type(State.LastAmmo)
			== "number"

		and

		type(ammo)
			== "number"

		and

		ammo <
			State.LastAmmo
	then

		markShot(

			tool,

			"poll_ammo_decrease",

			State.LastAmmo,

			ammo

		)

	end


	State.LastAmmo =
		ammo


	State.LastReloading =
		reload

end


--==============================================================
-- SLOW SNAPSHOT
--==============================================================

local function slowSnapshot()

	State.Passes += 1


	local tool =
		State.CurrentTool


	if tool then

		toolSnapshot(
			tool,
			"periodic"
		)

	end


	addRecord({

		kind =
			"pass_summary",

		pass =
			State.Passes,

		records =
			#State.Records,

		approxBytes =
			State.ApproxBytes,

		shots =
			State.ShotCounter,

		effects =
			State.EffectCounter,

		tool =
			tool
			and
			tool.Name
			or nil,
	})

end


--==============================================================
-- START OBSERVERS
--==============================================================

local function installObservers()

	disconnectGlobalConnections()


	----------------------------------------------------------
	-- Workspace additions
	----------------------------------------------------------

	trackGlobalConnection(

		Workspace.DescendantAdded:
		Connect(function(object)

			recordWorkspaceEffect(
				object
			)

		end)

	)


	----------------------------------------------------------
	-- ReplicatedStorage additions
	----------------------------------------------------------

	trackGlobalConnection(

		ReplicatedStorage.DescendantAdded:
		Connect(function(object)

			if relevantRemote(
				object
			) then

				recordRemote(
					object,
					"added"
				)

			end

		end)

	)


	----------------------------------------------------------
	-- Character changed
	----------------------------------------------------------

	trackGlobalConnection(

		LocalPlayer.CharacterAdded:
		Connect(function(character)

			addRecord({

				kind =
					"character_added",

				path =
					fullPath(
						character
					),
			})


			task.wait(
				0.5
			)


			refreshEquippedTool()

		end)

	)

end


--==============================================================
-- MAIN LOOP
--==============================================================

local function continuousLoop()

	while
		State.Running
		and
		not State.Interrupted
	do

		local now =
			clock()


		------------------------------------------------------
		-- FAST
		------------------------------------------------------

		if
			now
			- State.LastFastSnapshot

			>= CONFIG.SnapshotInterval
		then

			State.LastFastSnapshot =
				now


			fastSnapshot()

		end


		------------------------------------------------------
		-- SLOW
		------------------------------------------------------

		if
			now
			- State.LastSlowSnapshot

			>= CONFIG.SlowSnapshotInterval
		then

			State.LastSlowSnapshot =
				now


			slowSnapshot()

		end


		task.wait(
			0.03
		)

	end

end


--==============================================================
-- START SCANNER
--==============================================================

local function startScanner()

	if State.Running then
		return
	end


	State.Running =
		true


	State.Interrupted =
		false


	State.BaselineDone =
		false


	State.StartedClock =
		clock()


	State.LastFastSnapshot =
		0


	State.LastSlowSnapshot =
		0


	State.LastShotClock =
		0


	State.Records = {}


	State.ApproxBytes =
		0


	State.Passes =
		0


	State.ShotCounter =
		0


	State.EffectCounter =
		0


	State.RemoteCounter =
		0


	State.ModuleCounter =
		0


	State.SignatureCounter =
		0


	State.ErrorCounter =
		0


	addRecord({

		kind =
			"session_start",

		scanner =
			CONFIG.Scanner,

		version =
			CONFIG.Version,

		placeId =
			game.PlaceId,

		gameId =
			game.GameId,

		clientVisibleOnly =
			true,

		continuous =
			true,

		firesRemotes =
			false,

		invokesRemoteFunctions =
			false,
	})


	installObservers()


	refreshEquippedTool()


	task.spawn(function()

		baselineScan()

	end)


	task.spawn(
		continuousLoop
	)

end


--==============================================================
-- STOP
--==============================================================

local function stopScanner()

	if not State.Running then
		return
	end


	addRecord({

		kind =
			"session_end",

		reason =
			"manual_interrupt",

		passes =
			State.Passes,

		records =
			#State.Records,

		approxBytes =
			State.ApproxBytes,

		shots =
			State.ShotCounter,

		effects =
			State.EffectCounter,
	})


	State.Interrupted =
		true


	State.Running =
		false


	disconnectToolConnections()


	disconnectGlobalConnections()

end


--==============================================================
-- BUILD REPORT
--==============================================================

local function buildReport()

	return {

		schemaVersion =
			CONFIG.SchemaVersion,

		scanner =
			CONFIG.Scanner,

		version =
			CONFIG.Version,

		source =
			"cafeina-weapon-research-v2-continuous",

		area =
			"WeaponBallistics",

		placeId =
			game.PlaceId,

		gameId =
			game.GameId,

		createdAt =
			os.time(),

		clientVisibleOnly =
			true,

		safety = {

			firesRemotes =
				false,

			invokesRemoteFunctions =
				false,

			mutatesGameObjects =
				false,

			mutatesWeapons =
				false,

			mutatesAmmo =
				false,

			observational =
				true,
		},

		summary = {

			records =
				#State.Records,

			passes =
				State.Passes,

			approxBytes =
				State.ApproxBytes,

			shots =
				State.ShotCounter,

			effects =
				State.EffectCounter,

			remotes =
				State.RemoteCounter,

			modules =
				State.ModuleCounter,

			signatures =
				State.SignatureCounter,

			errors =
				State.ErrorCounter,

			interrupted =
				State.Interrupted,

			baselineDone =
				State.BaselineDone,
		},

		records =
			State.Records,
	}

end


--==============================================================
-- ENCODE
--==============================================================

local function encodeReport()

	local report =
		buildReport()


	local ok,
		encoded =
		pcall(function()

			return HttpService:
				JSONEncode(
					report
				)

		end)


	if not ok then

		return nil,
			safeString(
				encoded
			)

	end


	return encoded

end


--==============================================================
-- CLIPBOARD
--==============================================================

local function copyText(text)

	if type(setclipboard)
		== "function"
	then

		local ok =
			pcall(
				setclipboard,
				text
			)


		return ok

	end


	return false

end


--==============================================================
-- HTTP REQUEST DETECTOR
--==============================================================

local function getRequestFunction()

	if
		type(request)
			== "function"
	then

		return request

	end


	if
		type(http_request)
			== "function"
	then

		return http_request

	end


	if
		syn
		and
		type(syn.request)
			== "function"
	then

		return syn.request

	end


	if
		http
		and
		type(http.request)
			== "function"
	then

		return http.request

	end


	return nil

end


--==============================================================
-- UPLOAD
--==============================================================

local function uploadReport()

	if State.Uploading then

		return false,
			"upload em andamento"

	end


	if CONFIG.UploadURL ==
		""
	then

		return false,
			"CONFIG.UploadURL vazio"

	end


	local requestFunction =
		getRequestFunction()


	if not requestFunction then

		return false,
			"função HTTP indisponível"

	end


	State.Uploading =
		true


	local encoded,
		encodeError =
		encodeReport()


	if not encoded then

		State.Uploading =
			false


		return false,
			encodeError

	end


	local payload =
		HttpService:
		JSONEncode({

			name =
				string.format(
					"Cafeina_WeaponResearch_%d_%d.json",
					game.PlaceId,
					os.time()
				),

			area =
				"WeaponBallistics",

			bytes =
				#encoded,

			content =
				encoded,
		})


	local ok,
		response =
		pcall(function()

			return requestFunction({

				Url =
					CONFIG.UploadURL,

				Method =
					"POST",

				Headers = {

					["Content-Type"] =
						"application/json",
				},

				Body =
					payload,
			})

		end)


	State.Uploading =
		false


	if not ok then

		return false,
			safeString(
				response
			)

	end


	local body =
		response.Body
		or
		response.body
		or
		""


	local statusCode =
		response.StatusCode
		or
		response.status
		or
		0


	if statusCode <
		200
		or
		statusCode >=
		300
	then

		return false,
			"HTTP "
			..
			tostring(
				statusCode
			)

	end


	----------------------------------------------------------
	-- Parse response
	----------------------------------------------------------

	local decoded


	pcall(function()

		decoded =
			HttpService:
			JSONDecode(
				body
			)

	end)


	local link


	if type(decoded)
		== "table"
	then

		link =
			decoded.url
			or
			decoded.link
			or
			decoded.downloadUrl
			or
			decoded.downloadURL

	end


	if link then

		State.LastUploadLink =
			link


		copyText(link)


		return true,
			link

	end


	State.LastUploadLink =
		body


	if body ~= "" then

		copyText(body)

	end


	return true,
		body

end


--==============================================================
-- GUI
--==============================================================

local GUI_NAME =
	"CafeinaWeaponResearchV2"


local oldGui =
	PlayerGui:
	FindFirstChild(
		GUI_NAME
	)


if oldGui then

	oldGui:Destroy()

end


local Gui =
	Instance.new(
		"ScreenGui"
	)


Gui.Name =
	GUI_NAME


Gui.ResetOnSpawn =
	false


Gui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling


Gui.Parent =
	PlayerGui


--==============================================================
-- MAIN
--==============================================================

local Main =
	Instance.new(
		"Frame"
	)


Main.Size =
	UDim2.fromOffset(
		330,
		225
	)


Main.Position =
	UDim2.new(
		0.5,
		-165,
		0.40,
		-112
	)


Main.BackgroundColor3 =
	Color3.fromRGB(
		16,
		17,
		20
	)


Main.BorderSizePixel =
	0


Main.Parent =
	Gui


local Corner =
	Instance.new(
		"UICorner"
	)


Corner.CornerRadius =
	UDim.new(
		0,
		12
	)


Corner.Parent =
	Main


local Stroke =
	Instance.new(
		"UIStroke"
	)


Stroke.Color =
	Color3.fromRGB(
		58,
		60,
		68
	)


Stroke.Thickness =
	1


Stroke.Parent =
	Main


--==============================================================
-- HEADER
--==============================================================

local Header =
	Instance.new(
		"Frame"
	)


Header.Size =
	UDim2.new(
		1,
		0,
		0,
		46
	)


Header.BackgroundColor3 =
	Color3.fromRGB(
		21,
		22,
		26
	)


Header.BorderSizePixel =
	0


Header.Parent =
	Main


local Title =
	Instance.new(
		"TextLabel"
	)


Title.Size =
	UDim2.new(
		1,
		-20,
		0,
		25
	)


Title.Position =
	UDim2.fromOffset(
		12,
		5
	)


Title.BackgroundTransparency =
	1


Title.Text =
	"CAFEÍNA • WEAPON RESEARCH"


Title.TextColor3 =
	Color3.fromRGB(
		245,
		245,
		247
	)


Title.Font =
	Enum.Font.GothamBold


Title.TextSize =
	13


Title.TextXAlignment =
	Enum.TextXAlignment.Left


Title.Parent =
	Header


local Subtitle =
	Instance.new(
		"TextLabel"
	)


Subtitle.Size =
	UDim2.new(
		1,
		-20,
		0,
		15
	)


Subtitle.Position =
	UDim2.fromOffset(
		12,
		27
	)


Subtitle.BackgroundTransparency =
	1


Subtitle.Text =
	"BALLISTICS • CAST • PIERCING"


Subtitle.TextColor3 =
	Color3.fromRGB(
		105,
		108,
		118
	)


Subtitle.Font =
	Enum.Font.Gotham


Subtitle.TextSize =
	8


Subtitle.TextXAlignment =
	Enum.TextXAlignment.Left


Subtitle.Parent =
	Header


--==============================================================
-- STATUS
--==============================================================

local Status =
	Instance.new(
		"TextLabel"
	)


Status.Size =
	UDim2.new(
		1,
		-20,
		0,
		30
	)


Status.Position =
	UDim2.fromOffset(
		10,
		53
	)


Status.BackgroundTransparency =
	1


Status.Text =
	"Pronto para iniciar"


Status.TextColor3 =
	Color3.fromRGB(
		200,
		202,
		210
	)


Status.Font =
	Enum.Font.GothamMedium


Status.TextSize =
	11


Status.TextXAlignment =
	Enum.TextXAlignment.Left


Status.Parent =
	Main


--==============================================================
-- BUTTON
--==============================================================

local function makeButton(
	text,
	x,
	width
)

	local Button =
		Instance.new(
			"TextButton"
		)


	Button.Size =
		UDim2.fromOffset(
			width,
			44
		)


	Button.Position =
		UDim2.fromOffset(
			x,
			89
		)


	Button.BackgroundColor3 =
		Color3.fromRGB(
			33,
			34,
			40
		)


	Button.BorderSizePixel =
		0


	Button.Text =
		text


	Button.TextColor3 =
		Color3.fromRGB(
			240,
			240,
			243
		)


	Button.TextSize =
		10


	Button.Font =
		Enum.Font.GothamBold


	Button.AutoButtonColor =
		false


	local ButtonCorner =
		Instance.new(
			"UICorner"
		)


	ButtonCorner.CornerRadius =
		UDim.new(
			0,
			8
		)


	ButtonCorner.Parent =
		Button


	Button.Parent =
		Main


	return Button

end


local StartButton =
	makeButton(
		"INICIAR",
		10,
		98
	)


local StopButton =
	makeButton(
		"INTERROMPER",
		116,
		98
	)


local SendButton =
	makeButton(
		"ENVIAR",
		222,
		98
	)


--==============================================================
-- INFO
--==============================================================

local Info =
	Instance.new(
		"TextLabel"
	)


Info.Size =
	UDim2.new(
		1,
		-20,
		0,
		62
	)


Info.Position =
	UDim2.fromOffset(
		10,
		141
	)


Info.BackgroundTransparency =
	1


Info.Text =
	"0 MB • 0 registros"


Info.TextWrapped =
	true


Info.TextColor3 =
	Color3.fromRGB(
		135,
		138,
		148
	)


Info.Font =
	Enum.Font.Gotham


Info.TextSize =
	10


Info.Parent =
	Main


--==============================================================
-- FOOTER
--==============================================================

local Footer =
	Instance.new(
		"TextLabel"
	)


Footer.Size =
	UDim2.new(
		1,
		-20,
		0,
		15
	)


Footer.Position =
	UDim2.fromOffset(
		10,
		204
	)


Footer.BackgroundTransparency =
	1


Footer.Text =
	"READ ONLY • CONTINUOUS CLIENT RESEARCH"


Footer.TextColor3 =
	Color3.fromRGB(
		85,
		88,
		98
	)


Footer.Font =
	Enum.Font.Gotham


Footer.TextSize =
	8


Footer.Parent =
	Main


--==============================================================
-- BUTTON EVENTS
--==============================================================

StartButton.Activated:
Connect(function()

	if State.Running then
		return
	end


	Status.Text =
		"Iniciando análise..."


	startScanner()


	Status.Text =
		"Analisando ballistics..."

end)


StopButton.Activated:
Connect(function()

	if not State.Running then
		return
	end


	Status.Text =
		"Interrompendo..."


	stopScanner()


	Status.Text =
		"Interrompido • pronto para enviar"

end)


SendButton.Activated:
Connect(function()

	if State.Running then

		Status.Text =
			"Interrompa o scan antes de enviar"


		return

	end


	Status.Text =
		"Preparando upload..."


	task.spawn(function()

		local ok,
			result =
			uploadReport()


		if ok then

			Status.Text =
				"Enviado • link copiado"

		else

			Status.Text =
				"Falha: "
				..
				safeString(
					result
				)

		end

	end)

end)


--==============================================================
-- UI LOOP
--==============================================================

task.spawn(function()

	while Gui.Parent do

		local tool =
			State.CurrentTool


		if State.Running then

			if State.Interrupted then

				Status.Text =
					"Limite atingido • pronto para enviar"

			elseif not State.BaselineDone then

				Status.Text =
					"Analisando módulos e remotes..."

			elseif
				clock()
				- State.LastShotClock
				<
				0.7
			then

				Status.Text =
					"Correlacionando tiro..."

			else

				Status.Text =
					"Monitorando arma..."

			end

		end


		Info.Text =
			string.format(

				"%s • %d registros • %d passes\nTiros %d • Efeitos %d • Assinaturas %d\nArma: %s",

				bytesText(
					State.ApproxBytes
				),

				#State.Records,

				State.Passes,

				State.ShotCounter,

				State.EffectCounter,

				State.SignatureCounter,

				tool
				and
				tool.Name
				or
				"nenhuma"

			)


		task.wait(
			CONFIG.UIUpdateInterval
		)

	end

end)


--==============================================================
-- MOBILE / PC DRAG
--==============================================================

local dragging =
	false


local dragInput


local dragStart


local startPosition


Header.InputBegan:
Connect(function(input)

	if
		input.UserInputType
			==
			Enum.UserInputType.MouseButton1

		or

		input.UserInputType
			==
			Enum.UserInputType.Touch
	then

		dragging =
			true


		dragStart =
			input.Position


		startPosition =
			Main.Position


		input.Changed:
		Connect(function()

			if
				input.UserInputState
				==
				Enum.UserInputState.End
			then

				dragging =
					false

			end

		end)

	end

end)


Header.InputChanged:
Connect(function(input)

	if
		input.UserInputType
			==
			Enum.UserInputType.MouseMovement

		or

		input.UserInputType
			==
			Enum.UserInputType.Touch
	then

		dragInput =
			input

	end

end)


UserInputService.InputChanged:
Connect(function(input)

	if
		not dragging
		or
		input ~= dragInput
	then

		return

	end


	local delta =
		input.Position
		-
		dragStart


	Main.Position =
		UDim2.new(

			startPosition.X.Scale,

			startPosition.X.Offset
			+
			delta.X,

			startPosition.Y.Scale,

			startPosition.Y.Offset
			+
			delta.Y

		)

end)


--==============================================================
-- READY
--==============================================================

print(
	"[CAFEÍNA]",
	"Weapon Research V2 Continuous carregado"
)

print(
	"[CAFEÍNA]",
	"FireServer: DESATIVADO",
	"| InvokeServer: DESATIVADO"
)
