--==============================================================--
-- CAFEÍNA • T-REX EXECUTOR MORPH V4.0 STABLE
-- 100% EXECUTOR / VISUAL LOCAL
--
-- CORREÇÕES PRINCIPAIS
-- • T-Rex NÃO segue mais HumanoidRootPart depois de ativado.
-- • X/Z mudam SOMENTE com input real do joystick/WASD.
-- • Y usa o último chão válido; nunca acompanha o avatar para baixo.
-- • Sem input = ZERO deslocamento visual.
-- • Frente do asset corrigida em 180° por padrão.
-- • Movimento do modelo é feito por ControllerRoot, preservando Motor6D/Bones.
-- • Câmera acompanha o próprio T-Rex.
-- • Idle / Walk / Run dependem somente do input real.
--
-- IMPORTANTE
-- Este morph é local. O Character server-side continua existindo.
--==============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera

local CONFIG = {
    GUI_NAME = "CafeinaTRexExecutorMorphV40Stable",
    ASSET_ID = 135258367627855,

    SCALE = 0.38,

    -- Este asset está invertido em relação ao eixo de avanço.
    -- Se no seu executor/modelo ficar ao contrário, use o botão "INVERTER FRENTE".
    YAW_DEGREES = 180,

    INPUT_DEADZONE = 0.08,

    WALK_SPEED = 10,
    RUN_SPEED = 19,
    RUN_INPUT_THRESHOLD = 0.72,

    TURN_RESPONSE = 14,

    -- O chão é sondado em torno do último chão válido.
    GROUND_OFFSET = 0.10,
    GROUND_PROBE_UP = 12,
    GROUND_PROBE_DOWN = 30,
    INITIAL_PROBE_UP = 50,
    INITIAL_PROBE_DOWN = 160,
    MAX_GROUND_CHANGE = 7,

    -- Se não houver chão válido à frente, não anda para lá.
    BLOCK_VOID = true,

    -- Parede simples para não atravessar tudo.
    WALL_COLLISION = true,
    WALL_PROBE_HEIGHT = 1.8,
    WALL_PADDING = 0.45,

    CAMERA_HEIGHT_FACTOR = 0.62,

    -- Limita delta de frame para evitar saltos após lag.
    MAX_DT = 0.05,
}

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_TREX_V4_STABLE")
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

    Dino = nil,
    ControllerRoot = nil,
    CameraAnchor = nil,

    RenderConn = nil,
    DescConn = nil,
    CharacterAddedConn = nil,

    Controls = nil,
    ControlsAvailable = false,

    VirtualX = 0,
    VirtualZ = 0,
    GroundY = nil,

    BottomFromController = 0,
    VisualHeight = 8,

    LastLook = Vector3.new(0,0,-1),

    SavedParts = setmetatable({}, {__mode="k"}),
    SavedTextures = setmetatable({}, {__mode="k"}),
    SavedFx = setmetatable({}, {__mode="k"}),
    SavedHumanoids = setmetatable({}, {__mode="k"}),

    Animator = nil,
    Tracks = {
        idle=nil,
        walk=nil,
        run=nil,
    },
    CurrentTrack = nil,

    YawDegrees = CONFIG.YAW_DEGREES,

    Gui = nil,
    Status = nil,
    Action = nil,
    Flip = nil,
}

--==============================================================--
-- BASIC HELPERS
--==============================================================--

local function disconnect(c)
    if c then
        pcall(function()
            c:Disconnect()
        end)
    end
end

local function getCharacter()
    local character = LP.Character

    if not character then
        return nil,nil,nil
    end

    return
        character,
        character:FindFirstChildOfClass("Humanoid"),
        character:FindFirstChild("HumanoidRootPart")
end

local function setStatus(text)
    if State.Status and State.Status.Parent then
        State.Status.Text = tostring(text)
    end
end

local function safeDestroy(inst)
    if inst then
        pcall(function()
            inst:Destroy()
        end)
    end
end

--==============================================================--
-- REAL JOYSTICK / KEYBOARD INPUT
--==============================================================--

local function setupControls()
    State.Controls = nil
    State.ControlsAvailable = false

    local scripts =
        LP:FindFirstChild("PlayerScripts")
        or LP:WaitForChild("PlayerScripts", 8)

    if not scripts then
        return false
    end

    local playerModule =
        scripts:FindFirstChild("PlayerModule")

    if not playerModule then
        return false
    end

    local ok,module =
        pcall(require, playerModule)

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

local function getMoveInput()
    -- Preferred path: actual Roblox mobile/keyboard controller.
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

            return flat,flat.Magnitude,false
        end
    end

    -- Fallback only when PlayerModule is unavailable.
    local _,hum = getCharacter()

    if hum then
        local v = hum.MoveDirection

        local flat =
            Vector3.new(
                v.X,
                0,
                v.Z
            )

        return flat,flat.Magnitude,true
    end

    return Vector3.zero,0,false
end

local function moveInputToWorld(raw,alreadyWorld)
    if raw.Magnitude <= 0.001 then
        return Vector3.zero
    end

    if alreadyWorld then
        return raw.Unit
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
        look = State.LastLook
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

    -- PlayerModule convention: forward is negative Z.
    local world =
        right * raw.X
        + look * (-raw.Z)

    if world.Magnitude <= 0.001 then
        return Vector3.zero
    end

    return world.Unit
end

--==============================================================--
-- HIDE REAL AVATAR LOCALLY
--==============================================================--

local function hideOne(inst)
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

local function hideAvatar(character)
    for _,inst in ipairs(character:GetDescendants()) do
        pcall(hideOne,inst)
    end

    local hum =
        character:
        FindFirstChildOfClass("Humanoid")

    if hum then
        if not State.SavedHumanoids[hum] then
            State.SavedHumanoids[hum] = {
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

    disconnect(State.DescConn)

    State.DescConn =
        character.DescendantAdded:
        Connect(function(inst)
            if State.Enabled then
                task.defer(function()
                    if inst and inst.Parent then
                        pcall(hideOne,inst)
                    end
                end)
            end
        end)
end

local function enforceHidden(character)
    -- Some games/camera scripts rewrite transparency.
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

local function restoreAvatar()
    disconnect(State.DescConn)
    State.DescConn = nil

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

    for hum,data in pairs(State.SavedHumanoids) do
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
    table.clear(State.SavedHumanoids)
end

--==============================================================--
-- LOAD MODEL
--==============================================================--

local function scoreModel(model)
    local score = 0
    local low = string.lower(model.Name)

    if string.find(low,"rex",1,true)
    or string.find(low,"dino",1,true)
    or string.find(low,"tyr",1,true)
    then
        score += 800
    end

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("MeshPart") then
            score += 15
        elseif inst:IsA("BasePart") then
            score += 1
        elseif inst:IsA("Bone") then
            score += 3
        elseif inst:IsA("Motor6D") then
            score += 4
        elseif inst:IsA("Animation") then
            score += 4
        end
    end

    return score
end

local function chooseModel(objects)
    local best
    local bestScore = -math.huge

    for _,obj in ipairs(objects) do
        if obj:IsA("Model") then
            local score = scoreModel(obj)

            if score > bestScore then
                best = obj
                bestScore = score
            end
        else
            for _,candidate in ipairs(obj:GetDescendants()) do
                if candidate:IsA("Model") then
                    local score = scoreModel(candidate)

                    if score > bestScore then
                        best = candidate
                        bestScore = score
                    end
                end
            end
        end
    end

    return best
end

local function loadDino()
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
            "game:GetObjects não carregou o asset"
    end

    local model =
        chooseModel(objects)

    if not model then
        for _,obj in ipairs(objects) do
            safeDestroy(obj)
        end

        return nil,
            "nenhum Model de T-Rex encontrado"
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
-- PREPARE PHYSICAL VISUAL RIG
--==============================================================--

local function allParts(model)
    local result = {}

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            table.insert(result,inst)
        end
    end

    return result
end

local function prepareDino(model)
    -- Never execute code shipped inside a public model.
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

    local parts = allParts(model)

    if #parts == 0 then
        return false,
            "modelo sem BasePart"
    end

    for _,part in ipairs(parts) do
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
        part.Anchored = false
    end

    local rigRoot =
        model:FindFirstChild("HumanoidRootPart",true)

    if not rigRoot
    or not rigRoot:IsA("BasePart")
    then
        rigRoot = model.PrimaryPart
    end

    if not rigRoot
    or not rigRoot:IsA("BasePart")
    then
        rigRoot = parts[1]
    end

    -- Independent invisible controller. We move THIS part only.
    local controller =
        Instance.new("Part")

    controller.Name =
        "CafeinaTRexControllerRoot"

    controller.Size =
        Vector3.new(0.3,0.3,0.3)

    controller.Transparency = 1
    controller.CastShadow = false
    controller.Anchored = true
    controller.CanCollide = false
    controller.CanTouch = false
    controller.CanQuery = false
    controller.Massless = true
    controller.CFrame = rigRoot.CFrame
    controller.Parent = model

    local rootWeld =
        Instance.new("WeldConstraint")

    rootWeld.Name =
        "CafeinaTRexRootWeld"

    rootWeld.Part0 = controller
    rootWeld.Part1 = rigRoot
    rootWeld.Parent = controller

    -- Connect only physically disconnected assemblies. Existing Motor6D/Bones
    -- remain untouched so animations can still move the dinosaur.
    local connected = {
        [controller]=true,
    }

    local function markConnected(part)
        connected[part] = true

        local ok,list =
            pcall(function()
                return part:GetConnectedParts(true)
            end)

        if ok and type(list) == "table" then
            for _,p in ipairs(list) do
                connected[p] = true
            end
        end
    end

    markConnected(rigRoot)

    for _,part in ipairs(parts) do
        if not connected[part] then
            local weld =
                Instance.new("WeldConstraint")

            weld.Name =
                "CafeinaDisconnectedAssemblyWeld"

            weld.Part0 = controller
            weld.Part1 = part
            weld.Parent = controller

            markConnected(part)
        end
    end

    State.ControllerRoot = controller

    return true
end

--==============================================================--
-- VISUAL EXTENTS / CAMERA
--==============================================================--

local function computeExtents(model,controller)
    local minY = math.huge
    local maxY = -math.huge
    local found = 0

    for _,part in ipairs(allParts(model)) do
        if part ~= controller
        and part.Transparency < 0.98
        then
            found += 1

            local sx = part.Size.X * 0.5
            local sy = part.Size.Y * 0.5
            local sz = part.Size.Z * 0.5

            for _,x in ipairs({-sx,sx}) do
                for _,y in ipairs({-sy,sy}) do
                    for _,z in ipairs({-sz,sz}) do
                        local wp =
                            part.CFrame:
                            PointToWorldSpace(
                                Vector3.new(x,y,z)
                            )

                        local lp =
                            controller.CFrame:
                            PointToObjectSpace(wp)

                        minY =
                            math.min(
                                minY,
                                lp.Y
                            )

                        maxY =
                            math.max(
                                maxY,
                                lp.Y
                            )
                    end
                end
            end
        end
    end

    if found == 0 then
        local boxCF,boxSize =
            model:GetBoundingBox()

        local rel =
            controller.CFrame:
            ToObjectSpace(boxCF)

        minY =
            rel.Position.Y
            - boxSize.Y * 0.5

        maxY =
            rel.Position.Y
            + boxSize.Y * 0.5
    end

    State.BottomFromController = minY
    State.VisualHeight =
        math.max(
            1,
            maxY - minY
        )

    local cameraAnchor =
        Instance.new("Part")

    cameraAnchor.Name =
        "CafeinaTRexCameraAnchor"

    cameraAnchor.Size =
        Vector3.new(0.2,0.2,0.2)

    cameraAnchor.Transparency = 1
    cameraAnchor.Anchored = false
    cameraAnchor.CanCollide = false
    cameraAnchor.CanTouch = false
    cameraAnchor.CanQuery = false
    cameraAnchor.Massless = true

    cameraAnchor.CFrame =
        controller.CFrame
        * CFrame.new(
            0,
            minY
                + State.VisualHeight
                    * CONFIG.CAMERA_HEIGHT_FACTOR,
            0
        )

    cameraAnchor.Parent = model

    local weld =
        Instance.new("WeldConstraint")

    weld.Name =
        "CafeinaCameraWeld"

    weld.Part0 = controller
    weld.Part1 = cameraAnchor
    weld.Parent = controller

    State.CameraAnchor =
        cameraAnchor
end

--==============================================================--
-- GROUND / WALL PROBES
--==============================================================--

local function rayParams(character)
    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    local ignore = {}

    if character then
        table.insert(ignore,character)
    end

    if State.Dino then
        table.insert(ignore,State.Dino)
    end

    params.FilterDescendantsInstances =
        ignore

    params.IgnoreWater = false

    pcall(function()
        params.RespectCanCollide = true
    end)

    return params
end

local function groundRay(x,z,referenceY,up,down,character)
    local result =
        Workspace:Raycast(
            Vector3.new(
                x,
                referenceY + up,
                z
            ),
            Vector3.new(
                0,
                -(up + down),
                0
            ),
            rayParams(character)
        )

    if result then
        return result.Position.Y,result
    end

    return nil,nil
end

local function initialGround(root,character)
    local y,result =
        groundRay(
            root.Position.X,
            root.Position.Z,
            root.Position.Y,
            CONFIG.INITIAL_PROBE_UP,
            CONFIG.INITIAL_PROBE_DOWN,
            character
        )

    if y then
        return y,result
    end

    -- Driver may already be under the map. Use camera altitude as fallback.
    Camera = Workspace.CurrentCamera

    local reference =
        math.max(
            root.Position.Y,
            Camera.CFrame.Position.Y
        )

    return groundRay(
        root.Position.X,
        root.Position.Z,
        reference,
        CONFIG.INITIAL_PROBE_UP,
        CONFIG.INITIAL_PROBE_DOWN * 2,
        character
    )
end

local function stableGround(x,z,character)
    if not State.GroundY then
        return nil,nil
    end

    -- Critical fix: probe relative to LAST VALID FLOOR.
    local y,result =
        groundRay(
            x,
            z,
            State.GroundY,
            CONFIG.GROUND_PROBE_UP,
            CONFIG.GROUND_PROBE_DOWN,
            character
        )

    if not y then
        return nil,nil
    end

    if math.abs(y - State.GroundY)
        > CONFIG.MAX_GROUND_CHANGE
    then
        return nil,nil
    end

    return y,result
end

local function wallBlocked(fromX,fromZ,toX,toZ,character)
    if not CONFIG.WALL_COLLISION
    or not State.GroundY
    then
        return false
    end

    local delta =
        Vector3.new(
            toX-fromX,
            0,
            toZ-fromZ
        )

    if delta.Magnitude <= 0.001 then
        return false
    end

    local result =
        Workspace:Raycast(
            Vector3.new(
                fromX,
                State.GroundY
                    + CONFIG.WALL_PROBE_HEIGHT,
                fromZ
            ),
            delta.Unit
                * (
                    delta.Magnitude
                    + CONFIG.WALL_PADDING
                ),
            rayParams(character)
        )

    return result ~= nil
end

--==============================================================--
-- ANIMATIONS
--==============================================================--

local function animationScore(anim,kind)
    local n =
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
        if string.find(n,term,1,true) then
            score += 100
        end
    end

    for _,term in ipairs(negative) do
        if string.find(n,term,1,true) then
            score -= 150
        end
    end

    return score
end

local function bestAnimation(model,kind)
    local best
    local bestScore = -math.huge

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Animation")
        and inst.AnimationId ~= ""
        then
            local score =
                animationScore(
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

local function ensureAnimator(model)
    local animator =
        model:
        FindFirstChildWhichIsA(
            "Animator",
            true
        )

    if animator then
        return animator
    end

    local controller =
        model:
        FindFirstChildWhichIsA(
            "AnimationController",
            true
        )

    if not controller then
        controller =
            Instance.new(
                "AnimationController"
            )

        controller.Name =
            "CafeinaAnimationController"

        controller.Parent =
            model
    end

    animator =
        Instance.new("Animator")

    animator.Name =
        "CafeinaAnimator"

    animator.Parent =
        controller

    return animator
end

local function loadAnimations(model)
    State.Animator =
        ensureAnimator(model)

    for _,kind in ipairs({"idle","walk","run"}) do
        local animation =
            bestAnimation(
                model,
                kind
            )

        if animation then
            local ok,track =
                pcall(function()
                    return State.Animator:
                        LoadAnimation(animation)
                end)

            if ok and track then
                track.Looped = true
                State.Tracks[kind] = track
            end
        end
    end
end

local function stopAnimations()
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

local function playAnimation(kind,speedScale)
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
                speedScale = 0.18

            elseif track == State.Tracks.run then
                actual = "run"
                speedScale = 0.15
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
                    other:Stop(0.16)
                end)
            end
        end

        pcall(function()
            if not track.IsPlaying then
                track:Play(0.16,1,1)
            end
        end)

        State.CurrentTrack = actual
    end

    pcall(function()
        track:AdjustSpeed(
            math.clamp(
                speedScale or 1,
                0.15,
                2
            )
        )
    end)
end

--==============================================================--
-- CAMERA
--==============================================================--

local function useDinoCamera()
    Camera = Workspace.CurrentCamera

    if State.CameraAnchor then
        pcall(function()
            Camera.CameraSubject =
                State.CameraAnchor

            Camera.CameraType =
                Enum.CameraType.Custom
        end)
    end
end

local function restoreCamera()
    Camera = Workspace.CurrentCamera

    local _,hum =
        getCharacter()

    if hum then
        pcall(function()
            Camera.CameraSubject = hum
            Camera.CameraType =
                Enum.CameraType.Custom
        end)
    end
end

--==============================================================--
-- VIRTUAL CONTROLLER
--==============================================================--

local function placeController()
    if not State.ControllerRoot
    or not State.GroundY
    then
        return
    end

    local rootY =
        State.GroundY
        - State.BottomFromController
        + CONFIG.GROUND_OFFSET

    local pos =
        Vector3.new(
            State.VirtualX,
            rootY,
            State.VirtualZ
        )

    local facing =
        CFrame.lookAt(
            pos,
            pos + State.LastLook,
            Vector3.yAxis
        )

    State.ControllerRoot.CFrame =
        facing
        * CFrame.Angles(
            0,
            math.rad(
                State.YawDegrees
            ),
            0
        )
end

local function startController()
    disconnect(State.RenderConn)

    State.RenderConn =
        RunService.RenderStepped:
        Connect(function(dt)
            if not State.Enabled
            or not State.Dino
            or not State.ControllerRoot
            then
                return
            end

            local character,hum =
                getCharacter()

            if not character or not hum then
                return
            end

            enforceHidden(character)

            local raw,
                magnitude,
                alreadyWorld =
                getMoveInput()

            local active =
                magnitude
                > CONFIG.INPUT_DEADZONE

            local worldMove =
                active
                and moveInputToWorld(
                    raw,
                    alreadyWorld
                )
                or Vector3.zero

            -- Absolute guarantee:
            -- no real input -> VirtualX/VirtualZ are never changed.
            if active
            and worldMove.Magnitude > 0.001
            then
                local desired =
                    worldMove.Unit

                local frameDt =
                    math.min(
                        math.max(dt,0),
                        CONFIG.MAX_DT
                    )

                local alpha =
                    1
                    - math.exp(
                        -CONFIG.TURN_RESPONSE
                        * frameDt
                    )

                local look =
                    State.LastLook:
                    Lerp(
                        desired,
                        math.clamp(
                            alpha,
                            0,
                            1
                        )
                    )

                if look.Magnitude > 0.001 then
                    State.LastLook =
                        look.Unit
                end

                local normalized =
                    math.clamp(
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

                local speed

                if normalized
                    >= CONFIG.RUN_INPUT_THRESHOLD
                then
                    speed =
                        CONFIG.RUN_SPEED
                else
                    speed =
                        CONFIG.WALK_SPEED
                        * math.clamp(
                            normalized
                            / CONFIG.RUN_INPUT_THRESHOLD,
                            0.40,
                            1
                        )
                end

                local distance =
                    speed * frameDt

                local nextX =
                    State.VirtualX
                    + desired.X
                        * distance

                local nextZ =
                    State.VirtualZ
                    + desired.Z
                        * distance

                local floor =
                    stableGround(
                        nextX,
                        nextZ,
                        character
                    )

                local allowMove =
                    floor ~= nil
                    or not CONFIG.BLOCK_VOID

                if allowMove
                and not wallBlocked(
                    State.VirtualX,
                    State.VirtualZ,
                    nextX,
                    nextZ,
                    character
                )
                then
                    State.VirtualX =
                        nextX

                    State.VirtualZ =
                        nextZ

                    if floor then
                        State.GroundY =
                            floor
                    end
                end

                if normalized
                    >= CONFIG.RUN_INPUT_THRESHOLD
                then
                    playAnimation(
                        "run",
                        CONFIG.RUN_SPEED / 16
                    )
                else
                    playAnimation(
                        "walk",
                        CONFIG.WALK_SPEED / 10
                    )
                end

            else
                -- No joystick/WASD input = no translation.
                -- We may only refine Y against the SAME floor.
                local floor =
                    stableGround(
                        State.VirtualX,
                        State.VirtualZ,
                        character
                    )

                if floor then
                    State.GroundY =
                        floor
                end

                playAnimation("idle",1)
            end

            placeController()

            if Camera.CameraSubject
                ~= State.CameraAnchor
            then
                useDinoCamera()
            end
        end)
end

--==============================================================--
-- ENABLE / DISABLE
--==============================================================--

local function destroyDino()
    disconnect(State.RenderConn)
    State.RenderConn = nil

    stopAnimations()

    if State.Dino then
        safeDestroy(State.Dino)
    end

    State.Dino = nil
    State.ControllerRoot = nil
    State.CameraAnchor = nil
    State.Animator = nil
    State.GroundY = nil
end

local function enableMorph()
    if State.Enabled then
        return true
    end

    local character,hum,root =
        getCharacter()

    if not character
    or not hum
    or not root
    then
        return false,
            "personagem ainda não carregou"
    end

    setupControls()

    local model,loadError =
        loadDino()

    if not model then
        return false,loadError
    end

    model.Name =
        "Cafeina_Local_TRex_V4"

    model.Parent =
        Workspace

    State.Dino = model

    local prepared,prepareError =
        prepareDino(model)

    if not prepared then
        destroyDino()
        return false,prepareError
    end

    computeExtents(
        model,
        State.ControllerRoot
    )

    State.VirtualX =
        root.Position.X

    State.VirtualZ =
        root.Position.Z

    local floor =
        initialGround(
            root,
            character
        )

    if not floor then
        destroyDino()

        return false,
            "não encontrei um chão válido para iniciar"
    end

    State.GroundY = floor

    local initialLook =
        Vector3.new(
            root.CFrame.LookVector.X,
            0,
            root.CFrame.LookVector.Z
        )

    if initialLook.Magnitude > 0.001 then
        State.LastLook =
            initialLook.Unit
    end

    State.Enabled = true

    hideAvatar(character)
    loadAnimations(model)
    placeController()
    useDinoCamera()
    startController()

    return true
end

local function disableMorph()
    State.Enabled = false

    destroyDino()
    restoreAvatar()
    restoreCamera()
end

-- Respawn only changes the invisible driver.
State.CharacterAddedConn =
    LP.CharacterAdded:
    Connect(function(character)
        task.wait(0.7)

        if State.Enabled then
            hideAvatar(character)
            useDinoCamera()
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

Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

if not pcall(function()
    Gui.Parent = guiParent
end)
then
    Gui.Parent =
        LP:WaitForChild(
            "PlayerGui"
        )
end

State.Gui = Gui

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        300,
        218
    )

Main.AnchorPoint =
    Vector2.new(0.5,0.5)

Main.Position =
    UDim2.fromScale(0.5,0.44)

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
Title.Text = "CAFEÍNA • T-REX V4 STABLE"
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
Subtitle.Text = "VIRTUAL CONTROL • GROUND LOCK • MOBILE"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 8
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Main

local Action =
    Instance.new("TextButton")

Action.Position =
    UDim2.fromOffset(10,58)

Action.Size =
    UDim2.new(1,-20,0,44)

Action.BackgroundColor3 =
    COLORS.BUTTON

Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "CONTROLAR T-REX"
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

local Flip =
    Instance.new("TextButton")

Flip.Position =
    UDim2.fromOffset(10,109)

Flip.Size =
    UDim2.new(1,-20,0,36)

Flip.BackgroundColor3 =
    COLORS.BUTTON

Flip.BorderSizePixel = 0
Flip.Font = Enum.Font.GothamBold
Flip.Text = "INVERTER FRENTE"
Flip.TextColor3 = COLORS.TEXT
Flip.TextSize = 9
Flip.AutoButtonColor = false
Flip.Parent = Main

State.Flip = Flip

local fc =
    Instance.new("UICorner")

fc.CornerRadius =
    UDim.new(0,8)

fc.Parent = Flip

local Status =
    Instance.new("TextLabel")

Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10,153)
Status.Size = UDim2.new(1,-20,0,50)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • parado significa ZERO movimento do T-Rex"
Status.TextColor3 = COLORS.MUTED
Status.TextSize = 9
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

State.Status = Status

-- Mobile drag.
do
    local dragging = false
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
            dragging = true
            dragStart = input.Position
            startPos = Main.Position

            input.Changed:
            Connect(function()
                if input.UserInputState
                    == Enum.UserInputState.End
                then
                    dragging = false
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
            dragInput = input
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
            "CONTROLAR T-REX"

        Action.BackgroundColor3 =
            COLORS.BUTTON

        setStatus(
            "Avatar restaurado"
        )

    else
        Action.Text =
            "CARREGANDO..."

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
                State.ControlsAvailable
                and "T-Rex ativo • joystick controla posição virtual"
                or "T-Rex ativo • PlayerModule indisponível, usando fallback"
            )
        else
            Action.Text =
                "CONTROLAR T-REX"

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

Flip.Activated:
Connect(function()
    State.YawDegrees =
        State.YawDegrees == 180
        and 0
        or 180

    if State.Enabled then
        placeController()
    end

    setStatus(
        "Frente invertida • yaw "
        .. tostring(
            State.YawDegrees
        )
        .. "°"
    )
end)

--==============================================================--
-- EXTERNAL CONTROLLER
--==============================================================--

env.__CAFEINA_TREX_V4_STABLE = {
    Disable = disableMorph,

    Destroy = function()
        disableMorph()

        disconnect(
            State.CharacterAddedConn
        )

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] T-REX EXECUTOR MORPH V4.0 STABLE carregado.")
