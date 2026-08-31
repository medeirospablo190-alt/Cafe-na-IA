--==============================================================--
-- CAFEÍNA • T-REX DIRECT CHARACTER V5.0
-- 100% EXECUTOR / LOCAL CHARACTER REPLACEMENT
--
-- O QUE MUDA
-- • O T-Rex vira LocalPlayer.Character NO SEU CLIENTE.
-- • Ele possui Humanoid + HumanoidRootPart + Head invisível.
-- • Joystick/WASD controlam o Humanoid do próprio T-Rex.
-- • JumpRequest controla o pulo do T-Rex.
-- • Câmera segue o Humanoid do T-Rex.
-- • Idle / Walk / Run usam as animações do asset.
-- • O personagem original fica preservado e invisível como driver/fallback.
-- • A frente já vem corrigida. NÃO existe botão de inverter.
--
-- LIMITAÇÃO
-- • Isso continua sendo client-side/executor.
-- • O servidor ainda mantém o Character verdadeiro do jogador.
--==============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera

local CONFIG = {
    GUI_NAME = "CafeinaTRexDirectCharacterV50",
    ASSET_ID = 135258367627855,

    SCALE = 0.38,

    -- Na versão anterior, o botão de inverter corrigia a frente.
    -- O valor correto agora já fica fixo aqui.
    FIXED_VISUAL_YAW = 0,

    WALK_SPEED = 12,
    RUN_SPEED = 21,
    RUN_INPUT_THRESHOLD = 0.72,

    JUMP_POWER = 48,

    INPUT_DEADZONE = 0.08,

    ROOT_HEIGHT = 3.2,
    MIN_ROOT_WIDTH = 2.0,
    MAX_ROOT_WIDTH = 4.2,
    MIN_ROOT_DEPTH = 2.0,
    MAX_ROOT_DEPTH = 4.2,
    ROOT_WIDTH_FACTOR = 0.30,
    ROOT_DEPTH_FACTOR = 0.20,

    SPAWN_RAY_UP = 35,
    SPAWN_RAY_DOWN = 120,

    CAMERA_OFFSET_FACTOR = 0.20,
    CAMERA_OFFSET_MIN = 1.6,
    CAMERA_OFFSET_MAX = 5.0,

    ANIM_FADE = 0.16,

    -- Se o servidor trocar o Character real durante o morph, a V5 guarda
    -- o novo driver e reassume o T-Rex local automaticamente.
    RECOVER_AFTER_SERVER_CHARACTER_CHANGE = true,
}

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_TREX_DIRECT_CHARACTER_V5")
    if type(old) == "table" and type(old.Destroy) == "function" then
        old.Destroy()
    end
end)

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Enabled = false,
    Busy = false,
    InternalCharacterAssign = false,

    DriverCharacter = nil,
    DinoCharacter = nil,

    DinoHumanoid = nil,
    DinoRoot = nil,

    Controls = nil,
    ControlsAvailable = false,

    RenderConn = nil,
    JumpConn = nil,
    CharacterAddedConn = nil,
    CharacterChangedConn = nil,
    DriverDescConn = nil,

    SavedParts = setmetatable({}, {__mode="k"}),
    SavedTextures = setmetatable({}, {__mode="k"}),
    SavedFx = setmetatable({}, {__mode="k"}),
    SavedHumanoid = setmetatable({}, {__mode="k"}),

    Animator = nil,
    Tracks = {
        idle=nil,
        walk=nil,
        run=nil,
    },
    CurrentTrack = nil,

    Status = nil,
    Action = nil,
    Gui = nil,
}

--==============================================================--
-- HELPERS
--==============================================================--

local function clamp(v,lo,hi)
    return math.max(lo,math.min(hi,v))
end

local function disconnect(conn)
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function safeDestroy(inst)
    if inst then
        pcall(function()
            inst:Destroy()
        end)
    end
end

local function setStatus(text)
    if State.Status and State.Status.Parent then
        State.Status.Text = tostring(text)
    end
end

local function currentDriver()
    if State.DriverCharacter and State.DriverCharacter.Parent then
        return State.DriverCharacter
    end
    return nil
end

--==============================================================--
-- STANDARD PLAYER CONTROLS
--==============================================================--

local function setupControls()
    State.Controls = nil
    State.ControlsAvailable = false

    local scripts =
        LP:FindFirstChild("PlayerScripts")
        or LP:WaitForChild("PlayerScripts",8)

    if not scripts then
        return false
    end

    local playerModule =
        scripts:FindFirstChild("PlayerModule")

    if not playerModule then
        return false
    end

    local ok,module =
        pcall(require,playerModule)

    if not ok
    or type(module) ~= "table"
    or type(module.GetControls) ~= "function"
    then
        return false
    end

    local controlsOk,controls =
        pcall(function()
            return module:GetControls()
        end)

    if not controlsOk or not controls then
        return false
    end

    State.Controls = controls
    State.ControlsAvailable = true

    return true
end

local function getRawMoveVector()
    if State.ControlsAvailable and State.Controls then
        local ok,v =
            pcall(function()
                return State.Controls:GetMoveVector()
            end)

        if ok and typeof(v) == "Vector3" then
            local flat =
                Vector3.new(
                    v.X,
                    0,
                    v.Z
                )

            return flat,flat.Magnitude
        end
    end

    return Vector3.zero,0
end

local function inputToWorld(raw)
    if raw.Magnitude <= 0.001 then
        return Vector3.zero
    end

    Camera = Workspace.CurrentCamera

    local look =
        Camera.CFrame.LookVector

    local right =
        Camera.CFrame.RightVector

    look =
        Vector3.new(
            look.X,
            0,
            look.Z
        )

    right =
        Vector3.new(
            right.X,
            0,
            right.Z
        )

    if look.Magnitude <= 0.001 then
        look = Vector3.new(0,0,-1)
    else
        look = look.Unit
    end

    if right.Magnitude <= 0.001 then
        right =
            Vector3.new(
                -look.Z,
                0,
                look.X
            )
    else
        right = right.Unit
    end

    -- PlayerModule: frente = -Z.
    local world =
        right * raw.X
        + look * (-raw.Z)

    if world.Magnitude <= 0.001 then
        return Vector3.zero
    end

    return world.Unit
end

--==============================================================--
-- HIDE / RESTORE REAL SERVER CHARACTER LOCALLY
--==============================================================--

local function hideDriverObject(inst)
    if inst:IsA("BasePart") then
        if not State.SavedParts[inst] then
            State.SavedParts[inst] = {
                transparency=inst.Transparency,
                localTransparency=inst.LocalTransparencyModifier,
                castShadow=inst.CastShadow,
            }
        end

        inst.Transparency = 1
        inst.LocalTransparencyModifier = 1
        inst.CastShadow = false

    elseif inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        if State.SavedTextures[inst] == nil then
            State.SavedTextures[inst] = inst.Transparency
        end

        inst.Transparency = 1

    elseif inst:IsA("ParticleEmitter")
        or inst:IsA("Trail")
        or inst:IsA("Beam")
        or inst:IsA("Smoke")
        or inst:IsA("Fire")
        or inst:IsA("Sparkles")
    then
        if State.SavedFx[inst] == nil then
            State.SavedFx[inst] = inst.Enabled
        end

        inst.Enabled = false
    end
end

local function hideDriver(character)
    if not character then
        return
    end

    for _,inst in ipairs(character:GetDescendants()) do
        pcall(hideDriverObject,inst)
    end

    local hum =
        character:
        FindFirstChildOfClass("Humanoid")

    if hum then
        if not State.SavedHumanoid[hum] then
            State.SavedHumanoid[hum] = {
                displayDistanceType=hum.DisplayDistanceType,
                healthDisplayType=hum.HealthDisplayType,
                nameDisplayDistance=hum.NameDisplayDistance,
                healthDisplayDistance=hum.HealthDisplayDistance,
            }
        end

        hum.DisplayDistanceType =
            Enum.HumanoidDisplayDistanceType.None

        hum.HealthDisplayType =
            Enum.HumanoidHealthDisplayType.AlwaysOff

        hum.NameDisplayDistance = 0
        hum.HealthDisplayDistance = 0
    end

    disconnect(State.DriverDescConn)

    State.DriverDescConn =
        character.DescendantAdded:
        Connect(function(inst)
            if State.Enabled
            and character == State.DriverCharacter
            then
                task.defer(function()
                    if inst and inst.Parent then
                        pcall(hideDriverObject,inst)
                    end
                end)
            end
        end)
end

local function enforceDriverHidden()
    local character =
        currentDriver()

    if not character then
        return
    end

    for _,inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.Transparency = 1
            inst.LocalTransparencyModifier = 1
            inst.CastShadow = false

        elseif inst:IsA("Decal")
            or inst:IsA("Texture")
        then
            inst.Transparency = 1
        end
    end
end

local function restoreDriver()
    disconnect(State.DriverDescConn)
    State.DriverDescConn = nil

    for inst,data in pairs(State.SavedParts) do
        if inst and inst.Parent then
            pcall(function()
                inst.Transparency = data.transparency
                inst.LocalTransparencyModifier = data.localTransparency
                inst.CastShadow = data.castShadow
            end)
        end
    end

    for inst,value in pairs(State.SavedTextures) do
        if inst and inst.Parent then
            pcall(function()
                inst.Transparency = value
            end)
        end
    end

    for inst,value in pairs(State.SavedFx) do
        if inst and inst.Parent then
            pcall(function()
                inst.Enabled = value
            end)
        end
    end

    for hum,data in pairs(State.SavedHumanoid) do
        if hum and hum.Parent then
            pcall(function()
                hum.DisplayDistanceType = data.displayDistanceType
                hum.HealthDisplayType = data.healthDisplayType
                hum.NameDisplayDistance = data.nameDisplayDistance
                hum.HealthDisplayDistance = data.healthDisplayDistance
            end)
        end
    end

    table.clear(State.SavedParts)
    table.clear(State.SavedTextures)
    table.clear(State.SavedFx)
    table.clear(State.SavedHumanoid)
end

--==============================================================--
-- LOAD PUBLIC T-REX ASSET
--==============================================================--

local function scoreModel(model)
    local score = 0
    local low = string.lower(model.Name)

    if string.find(low,"rex",1,true)
    or string.find(low,"dino",1,true)
    or string.find(low,"tyr",1,true)
    then
        score += 900
    end

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("MeshPart") then
            score += 16
        elseif inst:IsA("BasePart") then
            score += 1
        elseif inst:IsA("Bone") then
            score += 3
        elseif inst:IsA("Motor6D") then
            score += 5
        elseif inst:IsA("Animation") then
            score += 5
        end
    end

    return score
end

local function chooseModel(objects)
    local best
    local bestScore = -math.huge

    for _,obj in ipairs(objects) do
        if obj:IsA("Model") then
            local s = scoreModel(obj)

            if s > bestScore then
                best = obj
                bestScore = s
            end
        else
            for _,candidate in ipairs(obj:GetDescendants()) do
                if candidate:IsA("Model") then
                    local s = scoreModel(candidate)

                    if s > bestScore then
                        best = candidate
                        bestScore = s
                    end
                end
            end
        end
    end

    return best
end

local function loadTRex()
    local ok,objects =
        pcall(function()
            return game:GetObjects(
                "rbxassetid://"
                .. tostring(CONFIG.ASSET_ID)
            )
        end)

    if not ok
    or type(objects) ~= "table"
    or #objects == 0
    then
        return nil,
            "game:GetObjects não conseguiu carregar o T-Rex"
    end

    local model =
        chooseModel(objects)

    if not model then
        for _,obj in ipairs(objects) do
            safeDestroy(obj)
        end

        return nil,
            "nenhum Model utilizável encontrado"
    end

    model.Parent = nil

    for _,obj in ipairs(objects) do
        if obj ~= model then
            safeDestroy(obj)
        end
    end

    return model
end

--==============================================================--
-- RIG PREPARATION
--==============================================================--

local function getParts(model)
    local result = {}

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            table.insert(result,inst)
        end
    end

    return result
end

local function connectedSet(root)
    local set = {
        [root]=true,
    }

    local ok,list =
        pcall(function()
            return root:GetConnectedParts(true)
        end)

    if ok and type(list) == "table" then
        for _,part in ipairs(list) do
            set[part]=true
        end
    end

    return set
end

local function rotateVisibleRig(rootCF,parts,degrees)
    if degrees == 0 then
        return
    end

    local rot =
        CFrame.Angles(
            0,
            math.rad(degrees),
            0
        )

    for _,part in ipairs(parts) do
        local rel =
            rootCF:
            ToObjectSpace(part.CFrame)

        part.CFrame =
            rootCF
            * rot
            * rel
    end
end

local function prepareCharacter(model)
    -- Never run scripts contained in the public model.
    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Script")
        or inst:IsA("LocalScript")
        or inst:IsA("ModuleScript")
        or inst:IsA("ProximityPrompt")
        or inst:IsA("ClickDetector")
        then
            safeDestroy(inst)
        end
    end

    pcall(function()
        model:ScaleTo(CONFIG.SCALE)
    end)

    -- Preserve animations, but remove pre-existing Humanoids.
    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Humanoid") then
            safeDestroy(inst)
        end
    end

    local parts = getParts(model)

    if #parts == 0 then
        return nil,
            "o modelo não possui BaseParts"
    end

    for _,part in ipairs(parts) do
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = true
        part.Massless = true
    end

    local boxCF,boxSize =
        model:GetBoundingBox()

    local floorY =
        boxCF.Position.Y
        - boxSize.Y * 0.5

    -- Rename existing root so only our controller uses HumanoidRootPart.
    local oldRoot =
        model:
        FindFirstChild(
            "HumanoidRootPart",
            true
        )

    if oldRoot and oldRoot:IsA("BasePart") then
        oldRoot.Name = "DinoRigRoot"
    end

    local width =
        clamp(
            boxSize.X
            * CONFIG.ROOT_WIDTH_FACTOR,
            CONFIG.MIN_ROOT_WIDTH,
            CONFIG.MAX_ROOT_WIDTH
        )

    local depth =
        clamp(
            boxSize.Z
            * CONFIG.ROOT_DEPTH_FACTOR,
            CONFIG.MIN_ROOT_DEPTH,
            CONFIG.MAX_ROOT_DEPTH
        )

    local root =
        Instance.new("Part")

    root.Name =
        "HumanoidRootPart"

    root.Size =
        Vector3.new(
            width,
            CONFIG.ROOT_HEIGHT,
            depth
        )

    root.Transparency = 1
    root.CastShadow = false
    root.CanCollide = true
    root.CanTouch = false
    root.CanQuery = true
    root.Massless = false
    root.Anchored = true

    root.CFrame =
        CFrame.new(
            boxCF.Position.X,
            floorY
            + CONFIG.ROOT_HEIGHT * 0.5,
            boxCF.Position.Z
        )

    root.Parent = model

    -- Fixed correct orientation. There is no invert button in V5.
    rotateVisibleRig(
        root.CFrame,
        parts,
        CONFIG.FIXED_VISUAL_YAW
    )

    -- A Head helps Roblox camera/character systems behave consistently.
    local head =
        Instance.new("Part")

    head.Name = "Head"
    head.Size = Vector3.new(1,1,1)
    head.Transparency = 1
    head.CastShadow = false
    head.CanCollide = false
    head.CanTouch = false
    head.CanQuery = false
    head.Massless = true
    head.Anchored = true

    head.CFrame =
        root.CFrame
        * CFrame.new(
            0,
            math.max(
                1.5,
                boxSize.Y
                * CONFIG.CAMERA_OFFSET_FACTOR
            ),
            0
        )

    head.Parent = model

    -- Attach root to the original rig without destroying Motor6D/Bones.
    local rigRoot =
        oldRoot

    if not rigRoot
    or not rigRoot.Parent
    then
        rigRoot =
            model.PrimaryPart
    end

    if not rigRoot
    or rigRoot == root
    or not rigRoot:IsA("BasePart")
    then
        for _,part in ipairs(parts) do
            if part ~= root then
                rigRoot = part
                break
            end
        end
    end

    if not rigRoot then
        safeDestroy(model)
        return nil,
            "não encontrei root físico do rig"
    end

    local rootWeld =
        Instance.new("WeldConstraint")

    rootWeld.Name =
        "CafeinaRootToDinoRig"

    rootWeld.Part0 = root
    rootWeld.Part1 = rigRoot
    rootWeld.Parent = root

    local headWeld =
        Instance.new("WeldConstraint")

    headWeld.Name =
        "CafeinaHeadWeld"

    headWeld.Part0 = root
    headWeld.Part1 = head
    headWeld.Parent = root

    -- Any physically disconnected assemblies are attached to our controller.
    local connected =
        connectedSet(rigRoot)

    for _,part in ipairs(parts) do
        if part ~= root
        and part ~= head
        and not connected[part]
        then
            local weld =
                Instance.new(
                    "WeldConstraint"
                )

            weld.Name =
                "CafeinaDisconnectedAssemblyWeld"

            weld.Part0 = root
            weld.Part1 = part
            weld.Parent = root

            connected[part] = true
        end
    end

    local humanoid =
        Instance.new("Humanoid")

    humanoid.Name = "Humanoid"
    humanoid.WalkSpeed = CONFIG.RUN_SPEED
    humanoid.JumpPower = CONFIG.JUMP_POWER
    humanoid.AutoRotate = true
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    humanoid.HipHeight = 0
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.Parent = model

    local animator =
        Instance.new("Animator")

    animator.Name = "Animator"
    animator.Parent = humanoid

    -- Release physics after all welds are ready.
    for _,part in ipairs(getParts(model)) do
        part.Anchored = false

        if part ~= root then
            part.CanCollide = false
            part.Massless = true
        end
    end

    root.Anchored = false
    head.Anchored = false

    model.PrimaryPart = root

    return {
        model=model,
        humanoid=humanoid,
        root=root,
        animator=animator,
        visualHeight=boxSize.Y,
    }
end

--==============================================================--
-- ANIMATION DETECTION
--==============================================================--

local function animScore(anim,kind)
    local name =
        string.lower(anim.Name)

    local positive = {
        idle={"idle","stand","breath","rest"},
        walk={"walk","walking","step"},
        run={"run","running","sprint","charge"},
    }

    local negative = {
        "attack","bite","roar","death","die",
        "hurt","eat","sleep","sit","jump","fall",
    }

    local score = 0

    for _,term in ipairs(positive[kind]) do
        if string.find(name,term,1,true) then
            score += 100
        end
    end

    for _,term in ipairs(negative) do
        if string.find(name,term,1,true) then
            score -= 150
        end
    end

    return score
end

local function findAnim(model,kind)
    local best
    local bestScore = -math.huge

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Animation")
        and inst.AnimationId ~= ""
        then
            local score =
                animScore(
                    inst,
                    kind
                )

            if score > bestScore then
                best = inst
                bestScore = score
            end
        end
    end

    if bestScore <= 0 then
        return nil
    end

    return best
end

local function loadTracks(model,animator)
    State.Animator = animator

    for _,kind in ipairs({"idle","walk","run"}) do
        local anim =
            findAnim(model,kind)

        if anim then
            local ok,track =
                pcall(function()
                    return animator:
                        LoadAnimation(anim)
                end)

            if ok and track then
                track.Looped = true

                if kind == "idle" then
                    track.Priority =
                        Enum.AnimationPriority.Idle
                else
                    track.Priority =
                        Enum.AnimationPriority.Movement
                end

                State.Tracks[kind] =
                    track
            end
        end
    end
end

local function stopTracks()
    for _,track in pairs(State.Tracks) do
        if track then
            pcall(function()
                track:Stop(0.12)
            end)
        end
    end

    State.Tracks = {
        idle=nil,
        walk=nil,
        run=nil,
    }

    State.CurrentTrack = nil
end

local function playTrack(kind,speedScale)
    local track =
        State.Tracks[kind]

    local actual =
        kind

    if not track then
        if kind == "run"
        and State.Tracks.walk
        then
            track = State.Tracks.walk
            actual = "walk"

        elseif kind == "walk"
        and State.Tracks.run
        then
            track = State.Tracks.run
            actual = "run"

        elseif kind == "idle" then
            track =
                State.Tracks.idle
                or State.Tracks.walk
                or State.Tracks.run

            if track == State.Tracks.walk then
                actual = "walk"
                speedScale = 0.16
            elseif track == State.Tracks.run then
                actual = "run"
                speedScale = 0.13
            end
        end
    end

    if not track then
        return
    end

    if State.CurrentTrack ~= actual then
        for _,other in pairs(State.Tracks) do
            if other and other ~= track then
                pcall(function()
                    other:Stop(
                        CONFIG.ANIM_FADE
                    )
                end)
            end
        end

        pcall(function()
            if not track.IsPlaying then
                track:Play(
                    CONFIG.ANIM_FADE,
                    1,
                    1
                )
            end
        end)

        State.CurrentTrack = actual
    end

    pcall(function()
        track:AdjustSpeed(
            clamp(
                speedScale or 1,
                0.12,
                2
            )
        )
    end)
end

--==============================================================--
-- SPAWN ON FLOOR
--==============================================================--

local function floorCFrameFromDriver(driverRoot,dinoRoot,dinoModel)
    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    local ignore = {dinoModel}

    if State.DriverCharacter then
        table.insert(
            ignore,
            State.DriverCharacter
        )
    end

    params.FilterDescendantsInstances =
        ignore

    params.IgnoreWater = false

    local result =
        Workspace:Raycast(
            driverRoot.Position
            + Vector3.new(
                0,
                CONFIG.SPAWN_RAY_UP,
                0
            ),
            Vector3.new(
                0,
                -(
                    CONFIG.SPAWN_RAY_UP
                    + CONFIG.SPAWN_RAY_DOWN
                ),
                0
            ),
            params
        )

    local groundY =
        result
        and result.Position.Y
        or (
            driverRoot.Position.Y
            - 3
        )

    local rootY =
        groundY
        + dinoRoot.Size.Y * 0.5

    local look =
        Vector3.new(
            driverRoot.CFrame.LookVector.X,
            0,
            driverRoot.CFrame.LookVector.Z
        )

    if look.Magnitude <= 0.001 then
        look = Vector3.new(0,0,-1)
    else
        look = look.Unit
    end

    local pos =
        Vector3.new(
            driverRoot.Position.X,
            rootY,
            driverRoot.Position.Z
        )

    return CFrame.lookAt(
        pos,
        pos + look,
        Vector3.yAxis
    )
end

--==============================================================--
-- LOCAL CHARACTER OWNERSHIP
--==============================================================--

local function assignLocalCharacter(character)
    State.InternalCharacterAssign = true

    local ok =
        pcall(function()
            LP.Character = character
        end)

    State.InternalCharacterAssign = false

    return ok
end

local function useDinoCamera()
    Camera = Workspace.CurrentCamera

    if State.DinoHumanoid then
        pcall(function()
            Camera.CameraSubject =
                State.DinoHumanoid

            Camera.CameraType =
                Enum.CameraType.Custom
        end)
    end
end

local function restoreDriverCamera()
    Camera = Workspace.CurrentCamera

    local driver =
        currentDriver()

    local hum =
        driver
        and driver:
        FindFirstChildOfClass(
            "Humanoid"
        )

    if hum then
        pcall(function()
            Camera.CameraSubject = hum
            Camera.CameraType =
                Enum.CameraType.Custom
        end)
    end
end

--==============================================================--
-- DIRECT T-REX CONTROL
--==============================================================--

local function startControlLoop()
    disconnect(State.RenderConn)

    State.RenderConn =
        RunService.RenderStepped:
        Connect(function()
            if not State.Enabled
            or not State.DinoCharacter
            or LP.Character ~= State.DinoCharacter
            or not State.DinoHumanoid
            or not State.DinoRoot
            then
                return
            end

            enforceDriverHidden()

            local raw,magnitude =
                getRawMoveVector()

            local active =
                magnitude
                > CONFIG.INPUT_DEADZONE

            if not active then
                -- Directly stop T-Rex. No backward walk or residual MoveTo.
                pcall(function()
                    State.DinoHumanoid:
                    Move(
                        Vector3.zero,
                        false
                    )
                end)

                playTrack("idle",1)
                return
            end

            local world =
                inputToWorld(raw)

            if world.Magnitude <= 0.001 then
                pcall(function()
                    State.DinoHumanoid:
                    Move(
                        Vector3.zero,
                        false
                    )
                end)

                playTrack("idle",1)
                return
            end

            local normalized =
                clamp(
                    (
                        magnitude
                        - CONFIG.INPUT_DEADZONE
                    )
                    / (
                        1
                        - CONFIG.INPUT_DEADZONE
                    ),
                    0,
                    1
                )

            local running =
                normalized
                >= CONFIG.RUN_INPUT_THRESHOLD

            State.DinoHumanoid.WalkSpeed =
                running
                and CONFIG.RUN_SPEED
                or CONFIG.WALK_SPEED

            -- World-space direction. AutoRotate turns the Character naturally.
            pcall(function()
                State.DinoHumanoid:
                Move(
                    world,
                    false
                )
            end)

            if running then
                playTrack(
                    "run",
                    CONFIG.RUN_SPEED / 16
                )
            else
                playTrack(
                    "walk",
                    CONFIG.WALK_SPEED / 10
                )
            end

            if Camera.CameraSubject
            ~= State.DinoHumanoid
            then
                useDinoCamera()
            end
        end)
end

local function startJumpControl()
    disconnect(State.JumpConn)

    State.JumpConn =
        UserInputService.JumpRequest:
        Connect(function()
            if State.Enabled
            and State.DinoHumanoid
            and State.DinoHumanoid.Parent
            then
                State.DinoHumanoid.Jump = true
            end
        end)
end

--==============================================================--
-- ENABLE / DISABLE
--==============================================================--

local function destroyDino()
    disconnect(State.RenderConn)
    State.RenderConn = nil

    disconnect(State.JumpConn)
    State.JumpConn = nil

    stopTracks()

    if State.DinoCharacter then
        safeDestroy(
            State.DinoCharacter
        )
    end

    State.DinoCharacter = nil
    State.DinoHumanoid = nil
    State.DinoRoot = nil
    State.Animator = nil
end

local function enableMorph()
    if State.Enabled then
        return true
    end

    local driver =
        LP.Character

    if not driver then
        return false,
            "Character real ainda não carregou"
    end

    local driverRoot =
        driver:
        FindFirstChild(
            "HumanoidRootPart"
        )

    if not driverRoot then
        return false,
            "HumanoidRootPart real não encontrado"
    end

    setupControls()

    if not State.ControlsAvailable then
        return false,
            "PlayerModule/GetControls indisponível neste executor"
    end

    local model,loadError =
        loadTRex()

    if not model then
        return false,loadError
    end

    model.Name =
        "Cafeina_Local_TRex_Character"

    model.Parent =
        Workspace

    local prepared,prepareError =
        prepareCharacter(model)

    if not prepared then
        safeDestroy(model)

        return false,
            prepareError
    end

    State.DriverCharacter =
        driver

    State.DinoCharacter =
        prepared.model

    State.DinoHumanoid =
        prepared.humanoid

    State.DinoRoot =
        prepared.root

    State.Animator =
        prepared.animator

    hideDriver(driver)

    local spawnCF =
        floorCFrameFromDriver(
            driverRoot,
            prepared.root,
            prepared.model
        )

    prepared.model:
        PivotTo(spawnCF)

    State.DinoHumanoid.CameraOffset =
        Vector3.new(
            0,
            clamp(
                prepared.visualHeight
                * CONFIG.CAMERA_OFFSET_FACTOR,
                CONFIG.CAMERA_OFFSET_MIN,
                CONFIG.CAMERA_OFFSET_MAX
            ),
            0
        )

    loadTracks(
        prepared.model,
        prepared.animator
    )

    State.Enabled = true

    if not assignLocalCharacter(
        prepared.model
    )
    then
        State.Enabled = false
        destroyDino()
        restoreDriver()

        return false,
            "não consegui definir LocalPlayer.Character"
    end

    useDinoCamera()
    startControlLoop()
    startJumpControl()

    return true
end

local function disableMorph()
    if not State.Enabled then
        return
    end

    State.Enabled = false

    local driver =
        currentDriver()

    if driver then
        assignLocalCharacter(driver)
    end

    destroyDino()
    restoreDriver()
    restoreDriverCamera()

    State.DriverCharacter = nil
end

--==============================================================--
-- SERVER CHARACTER CHANGE RECOVERY
--==============================================================--

State.CharacterAddedConn =
    LP.CharacterAdded:
    Connect(function(character)
        if not State.Enabled
        or State.InternalCharacterAssign
        or character == State.DinoCharacter
        then
            return
        end

        if not CONFIG.RECOVER_AFTER_SERVER_CHARACTER_CHANGE then
            return
        end

        -- Server created/replaced the real Character.
        -- Preserve it as the new invisible fallback.
        State.DriverCharacter =
            character

        task.delay(
            0.25,
            function()
                if State.Enabled
                and State.DinoCharacter
                and State.DinoCharacter.Parent
                and character.Parent
                then
                    hideDriver(character)
                    assignLocalCharacter(
                        State.DinoCharacter
                    )
                    useDinoCamera()
                end
            end
        )
    end)

State.CharacterChangedConn =
    LP:GetPropertyChangedSignal("Character"):
    Connect(function()
        if not State.Enabled
        or State.InternalCharacterAssign
        then
            return
        end

        local character =
            LP.Character

        if character
        and character ~= State.DinoCharacter
        and CONFIG.RECOVER_AFTER_SERVER_CHARACTER_CHANGE
        then
            State.DriverCharacter =
                character

            task.defer(function()
                if State.Enabled
                and State.DinoCharacter
                and State.DinoCharacter.Parent
                then
                    hideDriver(character)
                    assignLocalCharacter(
                        State.DinoCharacter
                    )
                    useDinoCamera()
                end
            end)
        end
    end)

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    ACTIVE=Color3.fromRGB(40,105,62),
    RED=Color3.fromRGB(155,45,51),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
}

local guiParent = CoreGui

if type(gethui) == "function" then
    local ok,value =
        pcall(gethui)

    if ok and value then
        guiParent = value
    end
end

pcall(function()
    local old =
        guiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    CONFIG.GUI_NAME

Gui.ResetOnSpawn = false

if not pcall(function()
    Gui.Parent = guiParent
end)
then
    Gui.Parent =
        LP:
        WaitForChild(
            "PlayerGui"
        )
end

State.Gui = Gui

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        300,
        182
    )

Main.AnchorPoint =
    Vector2.new(0.5,0.5)

Main.Position =
    UDim2.fromScale(
        0.5,
        0.44
    )

Main.BackgroundColor3 =
    COLORS.BG

Main.BorderSizePixel = 0
Main.Parent = Gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0,10)

corner.Parent = Main

local stroke =
    Instance.new("UIStroke")

stroke.Color =
    COLORS.STROKE

stroke.Thickness = 1
stroke.Parent = Main

local Title =
    Instance.new("TextLabel")

Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(10,8)
Title.Size = UDim2.new(1,-20,0,24)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • T-REX CHARACTER V5"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Subtitle =
    Instance.new("TextLabel")

Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(10,31)
Subtitle.Size = UDim2.new(1,-20,0,20)
Subtitle.Font = Enum.Font.Gotham
Subtitle.Text = "DIRECT LOCAL CHARACTER • MOBILE"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 8
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Main

local Action =
    Instance.new("TextButton")

Action.Position =
    UDim2.fromOffset(10,58)

Action.Size =
    UDim2.new(1,-20,0,46)

Action.BackgroundColor3 =
    COLORS.BUTTON

Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "VIRAR T-REX"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

State.Action = Action

local ac =
    Instance.new("UICorner")

ac.CornerRadius =
    UDim.new(0,8)

ac.Parent = Action

local Status =
    Instance.new("TextLabel")

Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10,114)
Status.Size = UDim2.new(1,-20,0,50)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • frente já corrigida • sem botão de inverter"
Status.TextColor3 = COLORS.MUTED
Status.TextSize = 9
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

State.Status = Status

-- Mobile drag.
do
    local dragging=false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:
    Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging=true
            dragStart=input.Position
            startPos=Main.Position

            input.Changed:
            Connect(function()
                if input.UserInputState
                    == Enum.UserInputState.End
                then
                    dragging=false
                end
            end)
        end
    end)

    Main.InputChanged:
    Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseMovement
        or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragInput=input
        end
    end)

    UserInputService.InputChanged:
    Connect(function(input)
        if dragging
        and input == dragInput
        then
            local delta =
                input.Position
                - dragStart

            Main.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
        end
    end)
end

Action.Activated:
Connect(function()
    if State.Busy then
        return
    end

    State.Busy = true

    if State.Enabled then
        disableMorph()

        Action.Text =
            "VIRAR T-REX"

        Action.BackgroundColor3 =
            COLORS.BUTTON

        setStatus(
            "Personagem original restaurado"
        )

    else
        Action.Text =
            "CRIANDO CHARACTER..."

        Action.BackgroundColor3 =
            COLORS.RED

        local ok,err =
            enableMorph()

        if ok then
            Action.Text =
                "VOLTAR AO PERSONAGEM"

            Action.BackgroundColor3 =
                COLORS.ACTIVE

            setStatus(
                "T-Rex é seu Character local • joystick + câmera + animações"
            )
        else
            Action.Text =
                "VIRAR T-REX"

            Action.BackgroundColor3 =
                COLORS.BUTTON

            setStatus(
                "Falha • "
                .. tostring(err)
            )
        end
    end

    State.Busy = false
end)

--==============================================================--
-- CONTROLLER
--==============================================================--

env.__CAFEINA_TREX_DIRECT_CHARACTER_V5 = {
    Disable=disableMorph,

    Destroy=function()
        disableMorph()

        disconnect(
            State.CharacterAddedConn
        )

        disconnect(
            State.CharacterChangedConn
        )

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] T-REX DIRECT CHARACTER V5.0 carregado.")
