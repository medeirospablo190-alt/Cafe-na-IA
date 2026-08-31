--==============================================================--
-- CAFEÍNA • T-REX EXECUTOR MORPH V3.0
-- 100% EXECUTOR / CLIENT-SIDE
--
-- OBJETIVO
-- • Controlar somente o T-Rex visualmente.
-- • Avatar real fica totalmente invisível localmente.
-- • T-Rex segue o movimento real do personagem.
-- • Alinhamento no chão por raycast.
-- • Câmera no T-Rex.
-- • Idle / Walk / Run automáticos quando o asset tiver animações.
-- • Respawn automático.
-- • Detector PASSIVO de possíveis sistemas legítimos de:
--   morph / pet / mount / skin / dinosaur / transform.
--
-- IMPORTANTE
-- • O T-Rex criado por game:GetObjects é LOCAL.
-- • Outros jogadores normalmente NÃO verão esse modelo.
-- • O detector NÃO dispara remotes arbitrários.
-- • Ele apenas cataloga remotes e observa chamadas reais feitas pelo jogo.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera

local CONFIG = {
    VERSION = "TREX_EXECUTOR_MORPH_V3_0",
    GUI_NAME = "CafeinaTRexExecutorMorphV30",
    ASSET_ID = 135258367627855,

    SCALE = 0.38,
    GROUND_OFFSET = 0.08,

    -- Se o T-Rex ficar olhando ao contrário, use 180.
    YAW_OFFSET_DEGREES = 0,

    GROUND_RAY_UP = 12,
    GROUND_RAY_DOWN = 100,

    TURN_RESPONSE = 12,

    WALK_MIN_SPEED = 0.35,
    RUN_SPEED_THRESHOLD = 17,

    CAMERA_HEIGHT_FACTOR = 0.62,

    -- Detector passivo.
    DETECTOR_ENABLED = true,
    DETECTOR_SCAN_LIMIT = 8000,

    DETECTOR_KEYWORDS = {
        "morph",
        "transform",
        "transformation",
        "dino",
        "dinosaur",
        "trex",
        "rex",
        "pet",
        "mount",
        "ride",
        "skin",
        "character",
        "avatar",
        "disguise",
        "costume",
        "creature",
        "species",
        "selectspecies",
        "setcharacter",
        "setskin",
    },
}

--==============================================================--
-- EXECUTOR CAPS
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_TREX_EXECUTOR_CONTROLLER")
    if type(old) == "table" and type(old.Destroy) == "function" then
        old.Destroy()
    end
end)

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then
            return v
        end
    end
    return nil
end

local HOOKMETAMETHOD = pick(rawget(env, "hookmetamethod"))
local GETNAMECALLMETHOD = pick(rawget(env, "getnamecallmethod"))
local NEWCCLOSURE = pick(rawget(env, "newcclosure"))
local CHECKCALLER = pick(rawget(env, "checkcaller"))
local SETCLIPBOARD = pick(rawget(env, "setclipboard"), rawget(env, "toclipboard"))

--==============================================================--
-- HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function safePath(inst)
    local ok, value = pcall(function()
        return inst:GetFullName()
    end)
    return ok and value or tostring(inst)
end

local function disconnect(c)
    if c then
        pcall(function()
            c:Disconnect()
        end)
    end
end

local function getCharacter()
    local c = LP.Character
    if not c then
        return nil,nil,nil
    end

    return
        c,
        c:FindFirstChildOfClass("Humanoid"),
        c:FindFirstChild("HumanoidRootPart")
end

local function isMorphish(text)
    local low = lower(text)

    for _, kw in ipairs(CONFIG.DETECTOR_KEYWORDS) do
        if string.find(low, kw, 1, true) then
            return true, kw
        end
    end

    return false,nil
end

local function serializeSimple(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 4 then
        return "<max_depth>"
    end

    local tv = typeof(value)

    if value == nil then
        return nil
    elseif tv == "string" or tv == "boolean" or tv == "number" then
        return value
    elseif tv == "Vector3" then
        return {type="Vector3",x=value.X,y=value.Y,z=value.Z}
    elseif tv == "CFrame" then
        local p = value.Position
        return {type="CFrame",x=p.X,y=p.Y,z=p.Z}
    elseif tv == "Instance" then
        return {
            type="Instance",
            className=value.ClassName,
            name=value.Name,
            path=safePath(value),
        }
    elseif tv == "table" then
        if seen[value] then
            return "<cycle>"
        end

        seen[value] = true

        local out = {}
        local count = 0

        for k,v in pairs(value) do
            count += 1
            if count > 60 then
                out["<truncated>"] = true
                break
            end

            out[tostring(k)] = serializeSimple(v,depth+1,seen)
        end

        seen[value] = nil
        return out
    end

    return tostring(value)
end

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Enabled = false,
    Dino = nil,
    CameraAnchor = nil,

    FollowConn = nil,
    AvatarDescConn = nil,
    CharacterAddedConn = nil,

    SavedParts = setmetatable({}, {__mode="k"}),
    SavedTextures = setmetatable({}, {__mode="k"}),
    SavedEffects = setmetatable({}, {__mode="k"}),
    SavedHumanoid = nil,

    BottomLocalY = 0,
    LastLook = Vector3.new(0,0,-1),

    Animator = nil,
    Tracks = {
        idle=nil,
        walk=nil,
        run=nil,
    },
    CurrentTrack = nil,

    Detector = {
        RemoteCount = 0,
        CandidateCount = 0,
        Candidates = {},
        ObservedCalls = {},
        HookInstalled = false,
        OriginalNamecall = nil,
    },

    UI = {},
}

--==============================================================--
-- AVATAR HIDE / RESTORE
--==============================================================--

local function hideInstance(inst)
    if inst:IsA("BasePart") then
        if not State.SavedParts[inst] then
            State.SavedParts[inst] = {
                transparency = inst.Transparency,
                localTransparency = inst.LocalTransparencyModifier,
                castShadow = inst.CastShadow,
            }
        end

        inst.Transparency = 1
        inst.LocalTransparencyModifier = 1
        inst.CastShadow = false

    elseif inst:IsA("Decal") or inst:IsA("Texture") then
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
        if State.SavedEffects[inst] == nil then
            State.SavedEffects[inst] = inst.Enabled
        end

        inst.Enabled = false
    end
end

local function hideAvatar(character)
    for _, inst in ipairs(character:GetDescendants()) do
        hideInstance(inst)
    end

    local hum = character:FindFirstChildOfClass("Humanoid")

    if hum then
        if not State.SavedHumanoid then
            State.SavedHumanoid = {
                displayDistanceType = hum.DisplayDistanceType,
                healthDisplayType = hum.HealthDisplayType,
                nameDisplayDistance = hum.NameDisplayDistance,
                healthDisplayDistance = hum.HealthDisplayDistance,
            }
        end

        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        hum.NameDisplayDistance = 0
        hum.HealthDisplayDistance = 0
    end

    disconnect(State.AvatarDescConn)

    State.AvatarDescConn = character.DescendantAdded:Connect(function(inst)
        if State.Enabled then
            task.defer(function()
                if inst and inst.Parent then
                    pcall(hideInstance, inst)
                end
            end)
        end
    end)
end

local function enforceHidden(character)
    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.Transparency = 1
            inst.LocalTransparencyModifier = 1
            inst.CastShadow = false

        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            inst.Transparency = 1
        end
    end
end

local function restoreAvatar()
    disconnect(State.AvatarDescConn)
    State.AvatarDescConn = nil

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

    for inst,value in pairs(State.SavedEffects) do
        if inst and inst.Parent then
            pcall(function()
                inst.Enabled = value
            end)
        end
    end

    local _,hum = getCharacter()

    if hum and State.SavedHumanoid then
        local d = State.SavedHumanoid

        pcall(function()
            hum.DisplayDistanceType = d.displayDistanceType
            hum.HealthDisplayType = d.healthDisplayType
            hum.NameDisplayDistance = d.nameDisplayDistance
            hum.HealthDisplayDistance = d.healthDisplayDistance
        end)
    end

    table.clear(State.SavedParts)
    table.clear(State.SavedTextures)
    table.clear(State.SavedEffects)

    State.SavedHumanoid = nil
end

--==============================================================--
-- ASSET LOAD / MODEL PREP
--==============================================================--

local function scoreModel(model)
    local score = 0
    local lowName = lower(model.Name)

    if contains(lowName,"rex")
    or contains(lowName,"dino")
    or contains(lowName,"tyr") then
        score += 800
    end

    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("MeshPart") then
            score += 15
        elseif inst:IsA("BasePart") then
            score += 1
        elseif inst:IsA("Bone") then
            score += 3
        elseif inst:IsA("Motor6D") then
            score += 4
        elseif inst:IsA("Animation") then
            score += 5
        end
    end

    return score
end

local function findBestModel(objects)
    local best
    local bestScore = -math.huge

    for _, obj in ipairs(objects) do
        if obj:IsA("Model") then
            local s = scoreModel(obj)

            if s > bestScore then
                best,bestScore = obj,s
            end

        else
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("Model") then
                    local s = scoreModel(child)

                    if s > bestScore then
                        best,bestScore = child,s
                    end
                end
            end
        end
    end

    return best
end

local function loadDino()
    local ok, objects = pcall(function()
        return game:GetObjects(
            "rbxassetid://" .. tostring(CONFIG.ASSET_ID)
        )
    end)

    if not ok
    or type(objects) ~= "table"
    or #objects == 0
    then
        return nil, "game:GetObjects falhou"
    end

    local model = findBestModel(objects)

    if not model then
        for _, obj in ipairs(objects) do
            pcall(function()
                obj:Destroy()
            end)
        end

        return nil, "nenhum Model utilizável encontrado"
    end

    model.Parent = nil

    for _, obj in ipairs(objects) do
        if obj ~= model then
            pcall(function()
                obj:Destroy()
            end)
        end
    end

    return model
end

local function cleanDino(model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Script")
        or inst:IsA("LocalScript")
        or inst:IsA("ModuleScript")
        or inst:IsA("ProximityPrompt")
        or inst:IsA("ClickDetector")
        then
            pcall(function()
                inst:Destroy()
            end)

        elseif inst:IsA("BasePart") then
            inst.Anchored = true
            inst.CanCollide = false
            inst.CanTouch = false
            inst.CanQuery = false
            inst.Massless = true

        elseif inst:IsA("Humanoid") then
            pcall(function()
                inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                inst.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                inst.NameDisplayDistance = 0
                inst.HealthDisplayDistance = 0
            end)
        end
    end

    pcall(function()
        model:ScaleTo(CONFIG.SCALE)
    end)
end

--==============================================================--
-- ANIMATION FIND / PLAY
--==============================================================--

local function animationScore(anim, kind)
    local n = lower(anim.Name)

    local positives = {
        idle={"idle","stand","breath","rest"},
        walk={"walk","walking","step"},
        run={"run","running","sprint","charge"},
    }

    local negative = {
        "attack","bite","roar","death","die",
        "hurt","eat","sleep","sit","jump","fall",
    }

    local score = 0

    for _, term in ipairs(positives[kind]) do
        if contains(n,term) then
            score += 100
        end
    end

    for _, term in ipairs(negative) do
        if contains(n,term) then
            score -= 150
        end
    end

    return score
end

local function findAnimation(model, kind)
    local best
    local bestScore = -math.huge

    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Animation")
        and inst.AnimationId ~= ""
        then
            local s = animationScore(inst,kind)

            if s > bestScore then
                best,bestScore = inst,s
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

local function loadTracks(model)
    State.Animator = ensureAnimator(model)

    for _, kind in ipairs({"idle","walk","run"}) do
        local anim = findAnimation(model,kind)

        if anim then
            local ok,track = pcall(function()
                return State.Animator:LoadAnimation(anim)
            end)

            if ok and track then
                track.Looped = true
                State.Tracks[kind] = track
            end
        end
    end
end

local function stopTracks()
    for _, track in pairs(State.Tracks) do
        if track then
            pcall(function()
                track:Stop(0.12)
            end)
        end
    end

    State.CurrentTrack = nil
end

local function playTrack(kind, speedScale)
    local track = State.Tracks[kind]
    local actual = kind

    if not track then
        if kind == "run" and State.Tracks.walk then
            track = State.Tracks.walk
            actual = "walk"

        elseif kind == "walk" and State.Tracks.run then
            track = State.Tracks.run
            actual = "run"

        elseif kind == "idle" then
            track =
                State.Tracks.idle
                or State.Tracks.walk
                or State.Tracks.run

            if track == State.Tracks.walk then
                actual = "walk"
                speedScale = 0.22
            elseif track == State.Tracks.run then
                actual = "run"
                speedScale = 0.18
            end
        end
    end

    if not track then
        return
    end

    if State.CurrentTrack ~= actual then
        for _, other in pairs(State.Tracks) do
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
                2.2
            )
        )
    end)
end

--==============================================================--
-- GROUND / CAMERA
--==============================================================--

local function computeModelGeometry(model)
    local pivot = model:GetPivot()
    local boxCF,boxSize = model:GetBoundingBox()
    local relative = pivot:ToObjectSpace(boxCF)

    State.BottomLocalY =
        relative.Position.Y
        - boxSize.Y * 0.5

    local anchor =
        Instance.new("Part")

    anchor.Name =
        "CafeinaTRexCameraAnchor"

    anchor.Size =
        Vector3.new(0.2,0.2,0.2)

    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.Parent = model

    local cameraY =
        relative.Position.Y
        - boxSize.Y * 0.5
        + boxSize.Y
            * CONFIG.CAMERA_HEIGHT_FACTOR

    anchor.CFrame =
        pivot
        * CFrame.new(
            relative.Position.X,
            cameraY,
            relative.Position.Z
        )

    State.CameraAnchor = anchor
end

local function groundY(position, character, dino)
    local params = RaycastParams.new()
    params.FilterType =
        Enum.RaycastFilterType.Exclude

    local filter = {}

    if character then
        table.insert(filter,character)
    end

    if dino then
        table.insert(filter,dino)
    end

    params.FilterDescendantsInstances =
        filter

    local origin =
        position
        + Vector3.new(
            0,
            CONFIG.GROUND_RAY_UP,
            0
        )

    local direction =
        Vector3.new(
            0,
            -(
                CONFIG.GROUND_RAY_UP
                + CONFIG.GROUND_RAY_DOWN
            ),
            0
        )

    local result =
        Workspace:Raycast(
            origin,
            direction,
            params
        )

    if result then
        return result.Position.Y
    end

    return position.Y - 3
end

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

    local _,hum = getCharacter()

    if hum then
        pcall(function()
            Camera.CameraSubject = hum
            Camera.CameraType =
                Enum.CameraType.Custom
        end)
    end
end

--==============================================================--
-- MAIN CONTROL LOOP
--==============================================================--

local function startFollowLoop()
    disconnect(State.FollowConn)

    State.FollowConn =
        RunService.RenderStepped:
        Connect(function(dt)
            if not State.Enabled
            or not State.Dino
            or not State.Dino.Parent
            then
                return
            end

            local character,hum,root =
                getCharacter()

            if not character
            or not hum
            or not root
            then
                return
            end

            enforceHidden(character)

            local move = hum.MoveDirection

            local flatMove =
                Vector3.new(
                    move.X,
                    0,
                    move.Z
                )

            local velocity =
                Vector3.new(
                    root.AssemblyLinearVelocity.X,
                    0,
                    root.AssemblyLinearVelocity.Z
                )

            local speed =
                velocity.Magnitude

            if flatMove.Magnitude > 0.05 then
                local desired =
                    flatMove.Unit

                local alpha =
                    1 - math.exp(
                        -CONFIG.TURN_RESPONSE
                        * math.max(dt,0)
                    )

                local blended =
                    State.LastLook:
                    Lerp(
                        desired,
                        math.clamp(
                            alpha,
                            0,
                            1
                        )
                    )

                if blended.Magnitude > 0.001 then
                    State.LastLook =
                        blended.Unit
                end
            end

            local floorY =
                groundY(
                    root.Position,
                    character,
                    State.Dino
                )

            local pivotY =
                floorY
                - State.BottomLocalY
                + CONFIG.GROUND_OFFSET

            local pos =
                Vector3.new(
                    root.Position.X,
                    pivotY,
                    root.Position.Z
                )

            local target =
                CFrame.lookAt(
                    pos,
                    pos + State.LastLook,
                    Vector3.yAxis
                )
                * CFrame.Angles(
                    0,
                    math.rad(
                        CONFIG.YAW_OFFSET_DEGREES
                    ),
                    0
                )

            pcall(function()
                State.Dino:PivotTo(target)
            end)

            if flatMove.Magnitude <= 0.05
            or speed < CONFIG.WALK_MIN_SPEED
            then
                playTrack("idle",1)

            elseif speed >= CONFIG.RUN_SPEED_THRESHOLD then
                playTrack(
                    "run",
                    speed
                    / CONFIG.RUN_SPEED_THRESHOLD
                )

            else
                playTrack(
                    "walk",
                    math.clamp(
                        speed
                        / math.max(
                            hum.WalkSpeed,
                            1
                        ),
                        0.5,
                        1.6
                    )
                )
            end

            if Camera.CameraSubject
            ~= State.CameraAnchor
            then
                useDinoCamera()
            end
        end)
end

--==============================================================--
-- PASSIVE SERVER-MORPH DETECTOR
--==============================================================--

local function registerCandidate(remote, source, keyword)
    local path = safePath(remote)

    if State.Detector.Candidates[path] then
        return
    end

    State.Detector.Candidates[path] = {
        path=path,
        name=remote.Name,
        className=remote.ClassName,
        source=source,
        keyword=keyword,
    }

    State.Detector.CandidateCount += 1
end

local function scanRemotes()
    if not CONFIG.DETECTOR_ENABLED then
        return
    end

    local inspected = 0

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inspected >= CONFIG.DETECTOR_SCAN_LIMIT then
            break
        end

        if inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
        then
            inspected += 1
            State.Detector.RemoteCount += 1

            local hit,keyword =
                isMorphish(
                    safePath(inst)
                    .. " "
                    .. inst.Name
                )

            if hit then
                registerCandidate(
                    inst,
                    "name_scan",
                    keyword
                )
            end
        end

        if inspected > 0
        and inspected % 180 == 0
        then
            task.wait()
        end
    end
end

local function installDetectorHook()
    if not CONFIG.DETECTOR_ENABLED
    or State.Detector.HookInstalled
    then
        return
    end

    if not HOOKMETAMETHOD
    or not GETNAMECALLMETHOD
    then
        return
    end

    local oldNamecall

    local wrapper = function(self,...)
        local method =
            GETNAMECALLMETHOD()

        if (
            method == "FireServer"
            or method == "InvokeServer"
        )
        and typeof(self) == "Instance"
        and (
            self:IsA("RemoteEvent")
            or self:IsA("RemoteFunction")
            or self:IsA("UnreliableRemoteEvent")
        )
        then
            local callerIsExecutor = false

            if CHECKCALLER then
                local ok,value =
                    pcall(CHECKCALLER)

                callerIsExecutor =
                    ok
                    and value == true
            end

            -- We only care about calls made by the real game.
            if not callerIsExecutor then
                local args = table.pack(...)

                local searchText =
                    safePath(self)
                    .. " "
                    .. self.Name

                for i=1,args.n do
                    local v=args[i]

                    if type(v)=="string" then
                        searchText =
                            searchText
                            .. " "
                            .. v
                    end
                end

                local hit,keyword =
                    isMorphish(searchText)

                if hit then
                    registerCandidate(
                        self,
                        "observed_legit_call",
                        keyword
                    )

                    table.insert(
                        State.Detector.ObservedCalls,
                        {
                            time=os.clock(),
                            remote=safePath(self),
                            method=method,
                            keyword=keyword,
                            args=serializeSimple(args),
                        }
                    )

                    while
                        #State.Detector.ObservedCalls
                        > 40
                    do
                        table.remove(
                            State.Detector.ObservedCalls,
                            1
                        )
                    end
                end
            end
        end

        return oldNamecall(self,...)
    end

    if NEWCCLOSURE then
        wrapper =
            NEWCCLOSURE(wrapper)
    end

    local ok,old =
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            wrapper
        )

    if ok
    and type(old)=="function"
    then
        oldNamecall=old
        State.Detector.OriginalNamecall=old
        State.Detector.HookInstalled=true
    end
end

local function restoreDetectorHook()
    if State.Detector.HookInstalled
    and HOOKMETAMETHOD
    and type(
        State.Detector.OriginalNamecall
    )=="function"
    then
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            State.Detector.OriginalNamecall
        )
    end

    State.Detector.HookInstalled=false
end

local function detectorReport()
    local list = {}

    for _, item in pairs(
        State.Detector.Candidates
    ) do
        table.insert(list,item)
    end

    table.sort(list,function(a,b)
        return a.path<b.path
    end)

    local report = {
        version=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        remoteCount=State.Detector.RemoteCount,
        candidateCount=
            State.Detector.CandidateCount,
        candidates=list,
        observedLegitCalls=
            State.Detector.ObservedCalls,
        note=
            "Passive detector only. No arbitrary remotes were fired.",
    }

    local ok,json =
        pcall(
            game:GetService(
                "HttpService"
            ).JSONEncode,
            game:GetService(
                "HttpService"
            ),
            report
        )

    if ok then
        return json
    end

    return tostring(report)
end

--==============================================================--
-- ENABLE / DISABLE MORPH
--==============================================================--

local function destroyDino()
    disconnect(State.FollowConn)
    State.FollowConn=nil

    stopTracks()

    if State.Dino then
        pcall(function()
            State.Dino:Destroy()
        end)
    end

    State.Dino=nil
    State.CameraAnchor=nil
    State.Animator=nil

    State.Tracks={
        idle=nil,
        walk=nil,
        run=nil,
    }
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
            "personagem não carregado"
    end

    local model,err =
        loadDino()

    if not model then
        return false,err
    end

    cleanDino(model)

    model.Name =
        "Cafeina_Local_Controlled_TRex"

    model.Parent =
        Workspace

    State.Dino=model
    State.Enabled=true

    hideAvatar(character)

    local look =
        Vector3.new(
            root.CFrame.LookVector.X,
            0,
            root.CFrame.LookVector.Z
        )

    if look.Magnitude>0.001 then
        State.LastLook=look.Unit
    end

    computeModelGeometry(model)
    loadTracks(model)
    useDinoCamera()
    startFollowLoop()

    return true
end

local function disableMorph()
    State.Enabled=false

    destroyDino()
    restoreAvatar()
    restoreCamera()
end

--==============================================================--
-- RESPAWN
--==============================================================--

State.CharacterAddedConn =
    LP.CharacterAdded:
    Connect(function(character)
        task.wait(0.8)

        if State.Enabled then
            hideAvatar(character)

            if State.Dino
            and State.Dino.Parent
            then
                startFollowLoop()
                useDinoCamera()
            end
        end
    end)

--==============================================================--
-- UI
--==============================================================--

local COLORS={
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    ACTIVE=Color3.fromRGB(40,105,62),
    RED=Color3.fromRGB(155,45,51),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
}

local GuiParent=CoreGui

if type(gethui)=="function" then
    local ok,value=pcall(gethui)

    if ok and value then
        GuiParent=value
    end
end

pcall(function()
    local old=
        GuiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui=
    Instance.new("ScreenGui")

Gui.Name=CONFIG.GUI_NAME
Gui.ResetOnSpawn=false

if not pcall(function()
    Gui.Parent=GuiParent
end)
then
    Gui.Parent=
        LP:
        WaitForChild(
            "PlayerGui"
        )
end

local Main=
    Instance.new("Frame")

Main.Size=
    UDim2.fromOffset(
        310,
        250
    )

Main.AnchorPoint=
    Vector2.new(
        0.5,
        0.5
    )

Main.Position=
    UDim2.fromScale(
        0.5,
        0.44
    )

Main.BackgroundColor3=
    COLORS.BG

Main.BorderSizePixel=0
Main.Parent=Gui

local corner=
    Instance.new("UICorner")

corner.CornerRadius=
    UDim.new(0,10)

corner.Parent=Main

local stroke=
    Instance.new("UIStroke")

stroke.Color=
    COLORS.STROKE

stroke.Thickness=1
stroke.Parent=Main

local Title=
    Instance.new("TextLabel")

Title.BackgroundTransparency=1
Title.Position=UDim2.fromOffset(10,8)
Title.Size=UDim2.new(1,-20,0,24)
Title.Font=Enum.Font.GothamBold
Title.Text="CAFEÍNA • T-REX EXECUTOR V3"
Title.TextColor3=COLORS.TEXT
Title.TextSize=13
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Parent=Main

local Subtitle=
    Instance.new("TextLabel")

Subtitle.BackgroundTransparency=1
Subtitle.Position=UDim2.fromOffset(10,31)
Subtitle.Size=UDim2.new(1,-20,0,20)
Subtitle.Font=Enum.Font.Gotham
Subtitle.Text="GROUND + CAMERA + ANIM + MORPH DETECTOR"
Subtitle.TextColor3=COLORS.MUTED
Subtitle.TextSize=8
Subtitle.TextXAlignment=Enum.TextXAlignment.Left
Subtitle.Parent=Main

local MorphButton=
    Instance.new("TextButton")

MorphButton.Position=UDim2.fromOffset(10,58)
MorphButton.Size=UDim2.new(1,-20,0,42)
MorphButton.BackgroundColor3=COLORS.BUTTON
MorphButton.BorderSizePixel=0
MorphButton.Font=Enum.Font.GothamBold
MorphButton.Text="CONTROLAR T-REX"
MorphButton.TextColor3=COLORS.TEXT
MorphButton.TextSize=11
MorphButton.AutoButtonColor=false
MorphButton.Parent=Main

local mc=
    Instance.new("UICorner")

mc.CornerRadius=UDim.new(0,8)
mc.Parent=MorphButton

local CopyButton=
    Instance.new("TextButton")

CopyButton.Position=UDim2.fromOffset(10,108)
CopyButton.Size=UDim2.new(1,-20,0,38)
CopyButton.BackgroundColor3=COLORS.BUTTON
CopyButton.BorderSizePixel=0
CopyButton.Font=Enum.Font.GothamBold
CopyButton.Text="COPIAR DETECTOR DE MORPH"
CopyButton.TextColor3=COLORS.TEXT
CopyButton.TextSize=10
CopyButton.AutoButtonColor=false
CopyButton.Parent=Main

local cc=
    Instance.new("UICorner")

cc.CornerRadius=UDim.new(0,8)
cc.Parent=CopyButton

local Status=
    Instance.new("TextLabel")

Status.BackgroundTransparency=1
Status.Position=UDim2.fromOffset(10,155)
Status.Size=UDim2.new(1,-20,0,50)
Status.Font=Enum.Font.Gotham
Status.Text="Pronto • T-Rex é local • detector passivo ligado"
Status.TextColor3=COLORS.TEXT
Status.TextSize=9
Status.TextWrapped=true
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Parent=Main

local Detail=
    Instance.new("TextLabel")

Detail.BackgroundTransparency=1
Detail.Position=UDim2.fromOffset(10,207)
Detail.Size=UDim2.new(1,-20,0,32)
Detail.Font=Enum.Font.Gotham
Detail.Text="Remotes: 0 • candidatos morph: 0"
Detail.TextColor3=COLORS.MUTED
Detail.TextSize=9
Detail.TextWrapped=true
Detail.TextXAlignment=Enum.TextXAlignment.Left
Detail.TextYAlignment=Enum.TextYAlignment.Top
Detail.Parent=Main

State.UI.Status=Status
State.UI.Detail=Detail

-- Drag mobile.
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
        and input==dragInput
        then
            local delta=
                input.Position
                - dragStart

            Main.Position=
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset+delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset+delta.Y
                )
        end
    end)
end

local busy=false

MorphButton.Activated:
Connect(function()
    if busy then
        return
    end

    busy=true

    if State.Enabled then
        disableMorph()

        MorphButton.Text=
            "CONTROLAR T-REX"

        MorphButton.BackgroundColor3=
            COLORS.BUTTON

        Status.Text=
            "Avatar restaurado"

    else
        MorphButton.Text=
            "CARREGANDO..."

        MorphButton.BackgroundColor3=
            COLORS.RED

        local ok,err=
            enableMorph()

        if ok then
            MorphButton.Text=
                "VOLTAR AO PERSONAGEM"

            MorphButton.BackgroundColor3=
                COLORS.ACTIVE

            Status.Text=
                "T-Rex ativo • chão/câmera/animações"

        else
            MorphButton.Text=
                "CONTROLAR T-REX"

            MorphButton.BackgroundColor3=
                COLORS.BUTTON

            Status.Text=
                "Falha • "
                .. tostring(err)
        end
    end

    busy=false
end)

CopyButton.Activated:
Connect(function()
    local report=
        detectorReport()

    if SETCLIPBOARD then
        local ok=
            pcall(
                SETCLIPBOARD,
                report
            )

        if ok then
            Status.Text=
                "Detector copiado • "
                .. tostring(
                    State.Detector.CandidateCount
                )
                .. " candidatos"
            return
        end
    end

    print(
        "[CAFEÍNA DETECTOR]",
        report
    )

    Status.Text=
        "Clipboard indisponível • relatório enviado ao console"
end)

task.spawn(function()
    scanRemotes()
    installDetectorHook()

    while Gui.Parent do
        task.wait(0.5)

        Detail.Text=
            string.format(
                "Remotes: %d • candidatos morph: %d • chamadas reais: %d",
                State.Detector.RemoteCount,
                State.Detector.CandidateCount,
                #State.Detector.ObservedCalls
            )
    end
end)

--==============================================================--
-- CONTROLLER
--==============================================================--

env.__CAFEINA_TREX_EXECUTOR_CONTROLLER={
    Disable=disableMorph,

    DetectorReport=detectorReport,

    Destroy=function()
        disableMorph()

        restoreDetectorHook()

        disconnect(
            State.CharacterAddedConn
        )

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] T-REX EXECUTOR MORPH V3.0 carregado.")
