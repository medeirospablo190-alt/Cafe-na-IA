--==============================================================--
-- CAFEÍNA • EGG FAST SAFE V6 • INSTANT RUN
-- PlaceId observado: 107778070777162
--
-- NÃO coleta ovos automaticamente.
-- Você pega o ovo manualmente.
--
-- Quando o servidor confirmar State="Carried":
-- • NÃO usa noclip
-- • NÃO altera CanCollide / CanTouch / CanQuery
-- • NÃO usa CFrame teleport
-- • NÃO usa AssemblyLinearVelocity para atravessar obstáculos
-- • usa movimento normal do Humanoid
-- • NÃO calcula rotas; desvia de paredes em tempo real por raycast
-- • começa a correr imediatamente no mesmo evento Carried
-- • corre para o ponto interno MAIS PRÓXIMO da região real de redeem
--
-- Região observada em 17 entregas reais:
-- X: 514.77 .. 544.03
-- Y: ~72.09
-- Z: -402.32 .. -318.42
--
-- CLIENT-VISIBLE / EXECUTOR
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    GUI_NAME = "CafeinaEggFastSafeV6InstantRun",

    -- Movimento normal, porém rápido.
    RUN_SPEED = 360,

    -- Perto da zona reduz um pouco para evitar overshoot.
    NEAR_SAFE_SPEED = 200,
    NEAR_SAFE_DISTANCE = 10,

    -- Região real observada nos redeems.
    SAFE_MIN_X = 514.77,
    SAFE_MAX_X = 544.03,
    SAFE_Y = 72.09,
    SAFE_MIN_Z = -402.32,
    SAFE_MAX_Z = -318.42,

    -- Mantém alguns studs para dentro da região.
    SAFE_MARGIN = 4.0,

    -- Considera chegada quando já entrou na região interior.
    ARRIVAL_RADIUS = 6.5,

    -- Pathfinding.
    AGENT_RADIUS = 2,
    AGENT_HEIGHT = 5,
    AGENT_CAN_JUMP = true,
    AGENT_CAN_CLIMB = true,
    WAYPOINT_SPACING = 9,

    -- Recalcula se rota bloquear/stuck.
    STUCK_SECONDS = 0.45,
    STUCK_MIN_PROGRESS = 0.65,
    REPATH_COOLDOWN = 0.08,

    -- Timeout por waypoint.
    WAYPOINT_TIMEOUT = 0.95,

    -- Verificação da linha reta.
    DIRECT_RAY_HEIGHT = 2.0,

    -- Immediate reactive wall avoidance. No PathfindingService route.
    LOOK_AHEAD_DISTANCE = 14,
    SIDE_LOOK_DISTANCE = 11,
    SIDE_BIAS = 0.88,
    STEER_REFRESH = 0.02,

    -- Reassert WalkSpeed constantly because this game may rewrite it.
    SPEED_LOCK = true,
}

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Enabled = false,

    Carrying = false,
    EggUid = nil,
    EggArea = nil,

    BaseWalkSpeed = nil,

    MoveToken = 0,
    CurrentTarget = nil,

    LastRootPosition = nil,
    LastProgressClock = 0,
    LastRepathClock = 0,

    Connections = {},
}

--==============================================================--
-- BASIC HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function getCharacter()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        return nil
    end

    return character, humanoid, root
end

local function saveBaseSpeed(humanoid)
    if State.BaseWalkSpeed == nil then
        State.BaseWalkSpeed = humanoid.WalkSpeed
    end
end

local function restoreSpeed()
    local _, humanoid = getCharacter()

    if humanoid and State.BaseWalkSpeed ~= nil then
        pcall(function()
            humanoid.WalkSpeed = State.BaseWalkSpeed
        end)
    end

    State.BaseWalkSpeed = nil
end

local function stopHumanoid()
    local _, humanoid = getCharacter()

    if humanoid then
        pcall(function()
            humanoid:Move(Vector3.zero, false)
        end)
    end
end

local function restoreMovement()
    restoreSpeed()
    stopHumanoid()
end

--==============================================================--
-- REMOTE DISCOVERY
--==============================================================--

local function findRemote(fragment, className)
    local needle = lower(fragment)

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if
            (not className or inst.ClassName == className)
            and
            (
                string.find(lower(inst.Name), needle, 1, true)
                or
                string.find(lower(inst:GetFullName()), needle, 1, true)
            )
        then
            return inst
        end
    end

    return nil
end

local FieldEggCarry =
    findRemote("FieldEggCarry", "RemoteEvent")

local FieldEggShifted =
    findRemote("FieldEggShifted", "RemoteEvent")

local FieldEggGone =
    findRemote("FieldEggGone", "RemoteEvent")

local FieldEggRedeemVerdict =
    findRemote("FieldEggRedeemVerdict", "RemoteEvent")

--==============================================================--
-- EVENT DATA PARSING
--==============================================================--

local INTERESTING_KEYS = {
    Uid=true, UID=true, uid=true,
    State=true, state=true,
    CarrierUserId=true, carrierUserId=true,
    AreaId=true, areaId=true,
    IsCarrying=true, isCarrying=true,
}

local function collectInteresting(value, out, seen, depth)
    depth = depth or 0

    if depth > 5 or type(value) ~= "table" then
        return
    end

    seen = seen or {}

    if seen[value] then
        return
    end

    seen[value] = true

    for k, v in pairs(value) do
        local key = tostring(k)

        if INTERESTING_KEYS[key] then
            out[key] = v
        end

        if type(v) == "table" then
            collectInteresting(v, out, seen, depth + 1)
        end
    end
end

local function parseArgs(...)
    local out = {}

    for _, value in ipairs({...}) do
        if type(value) == "table" then
            collectInteresting(value, out, {}, 0)
        end
    end

    return out
end

local function field(data, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)

        if data[key] ~= nil then
            return data[key]
        end
    end

    return nil
end

local function dataUid(data)
    local value = field(data, "Uid", "UID", "uid")
    return value ~= nil and tostring(value) or nil
end

local function dataState(data)
    return tostring(field(data, "State", "state") or "")
end

local function dataCarrier(data)
    return tonumber(
        field(
            data,
            "CarrierUserId",
            "carrierUserId"
        )
    )
end

--==============================================================--
-- SAFE ZONE GEOMETRY
--==============================================================--

local function safeBounds()
    local margin = CONFIG.SAFE_MARGIN

    return
        CONFIG.SAFE_MIN_X + margin,
        CONFIG.SAFE_MAX_X - margin,
        CONFIG.SAFE_MIN_Z + margin,
        CONFIG.SAFE_MAX_Z - margin
end

local function isInsideSafeRegion(position)
    local minX, maxX, minZ, maxZ = safeBounds()

    return
        position.X >= minX
        and position.X <= maxX
        and position.Z >= minZ
        and position.Z <= maxZ
        and math.abs(position.Y - CONFIG.SAFE_Y) <= 12
end

local function nearestSafePoint(position)
    local minX, maxX, minZ, maxZ = safeBounds()

    local x = math.clamp(position.X, minX, maxX)
    local z = math.clamp(position.Z, minZ, maxZ)

    return Vector3.new(
        x,
        CONFIG.SAFE_Y,
        z
    )
end

local function centerSafePoint()
    return Vector3.new(
        (CONFIG.SAFE_MIN_X + CONFIG.SAFE_MAX_X) * 0.5,
        CONFIG.SAFE_Y,
        (CONFIG.SAFE_MIN_Z + CONFIG.SAFE_MAX_Z) * 0.5
    )
end

local function safeCandidates(position)
    local nearest = nearestSafePoint(position)
    local center = centerSafePoint()

    local minX, maxX, minZ, maxZ = safeBounds()

    local candidates = {
        nearest,
        center,

        Vector3.new(nearest.X, CONFIG.SAFE_Y, minZ),
        Vector3.new(nearest.X, CONFIG.SAFE_Y, maxZ),
        Vector3.new(minX, CONFIG.SAFE_Y, nearest.Z),
        Vector3.new(maxX, CONFIG.SAFE_Y, nearest.Z),
    }

    -- Remove near-duplicates.
    local unique = {}

    for _, point in ipairs(candidates) do
        local duplicate = false

        for _, existing in ipairs(unique) do
            if (existing - point).Magnitude < 2 then
                duplicate = true
                break
            end
        end

        if not duplicate then
            table.insert(unique, point)
        end
    end

    return unique
end

--==============================================================--
-- DIRECT-LINE TEST
--==============================================================--

local function directLineClear(fromPosition, targetPosition, character)
    local origin =
        fromPosition
        + Vector3.new(
            0,
            CONFIG.DIRECT_RAY_HEIGHT,
            0
        )

    local target =
        targetPosition
        + Vector3.new(
            0,
            CONFIG.DIRECT_RAY_HEIGHT,
            0
        )

    local direction = target - origin

    if direction.Magnitude < 2 then
        return true
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = false

    local result = Workspace:Raycast(
        origin,
        direction,
        params
    )

    return result == nil
end

--==============================================================--
-- PATHFINDING
--==============================================================--

local function createPath()
    return PathfindingService:CreatePath({
        AgentRadius = CONFIG.AGENT_RADIUS,
        AgentHeight = CONFIG.AGENT_HEIGHT,
        AgentCanJump = CONFIG.AGENT_CAN_JUMP,
        AgentCanClimb = CONFIG.AGENT_CAN_CLIMB,
        WaypointSpacing = CONFIG.WAYPOINT_SPACING,
    })
end

local function computePath(fromPosition, targetPosition)
    local path = createPath()

    local ok = pcall(function()
        path:ComputeAsync(
            fromPosition,
            targetPosition
        )
    end)

    if not ok
    or path.Status ~= Enum.PathStatus.Success
    then
        return nil
    end

    local waypoints = path:GetWaypoints()

    if #waypoints == 0 then
        return nil
    end

    return path, waypoints
end

local function pathLength(fromPosition, waypoints)
    local total = 0
    local previous = fromPosition

    for _, waypoint in ipairs(waypoints) do
        total += (waypoint.Position - previous).Magnitude
        previous = waypoint.Position
    end

    return total
end

local function chooseRoute(rootPosition)
    local character = LocalPlayer.Character

    if not character then
        return nil
    end

    -- First choice: closest point inside Safe Zone.
    local nearest = nearestSafePoint(rootPosition)

    -- If the straight corridor is completely clear, direct normal movement
    -- is the fastest possible route.
    if directLineClear(
        rootPosition,
        nearest,
        character
    ) then
        return {
            mode = "direct",
            target = nearest,
            length = (nearest - rootPosition).Magnitude,
        }
    end

    -- Obstacle found: evaluate a few points inside the Safe Zone and
    -- choose the shortest valid normal walking path.
    local best

    for _, candidate in ipairs(
        safeCandidates(rootPosition)
    ) do
        local path, waypoints =
            computePath(
                rootPosition,
                candidate
            )

        if path and waypoints then
            local length =
                pathLength(
                    rootPosition,
                    waypoints
                )

            if not best
            or length < best.length
            then
                best = {
                    mode = "path",
                    target = candidate,
                    path = path,
                    waypoints = waypoints,
                    length = length,
                }
            end
        end

        task.wait(0.01)
    end

    -- Last fallback: normal MoveTo to center.
    if not best then
        best = {
            mode = "direct",
            target = centerSafePoint(),
            length =
                (centerSafePoint() - rootPosition).Magnitude,
            fallback = true,
        }
    end

    return best
end

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG = Color3.fromRGB(8, 8, 10),
    STROKE = Color3.fromRGB(45, 45, 52),
    BUTTON = Color3.fromRGB(31, 31, 36),
    GREEN = Color3.fromRGB(27, 112, 57),
    TEXT = Color3.fromRGB(245, 245, 247),
    MUTED = Color3.fromRGB(157, 157, 168),
}

local GuiParent = CoreGui

if type(gethui) == "function" then
    local ok, result = pcall(gethui)

    if ok and result then
        GuiParent = result
    end
end

pcall(function()
    local old = GuiParent:FindFirstChild(CONFIG.GUI_NAME)

    if old then
        old:Destroy()
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

local parentOk = pcall(function()
    Gui.Parent = GuiParent
end)

if not parentOk then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(296, 142)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.46)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = COLORS.STROKE
MainStroke.Thickness = 1
MainStroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(12, 8)
Title.Size = UDim2.new(1, -24, 0, 22)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • EGG FAST SAFE V6"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(12, 34)
Status.Size = UDim2.new(1, -24, 0, 40)
Status.Font = Enum.Font.Gotham
Status.Text = "Desligado"
Status.TextColor3 = COLORS.MUTED
Status.TextSize = 10
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

local Toggle = Instance.new("TextButton")
Toggle.Position = UDim2.fromOffset(12, 84)
Toggle.Size = UDim2.new(1, -24, 0, 43)
Toggle.BackgroundColor3 = COLORS.BUTTON
Toggle.BorderSizePixel = 0
Toggle.AutoButtonColor = false
Toggle.Font = Enum.Font.GothamBold
Toggle.Text = "ATIVAR"
Toggle.TextColor3 = COLORS.TEXT
Toggle.TextSize = 12
Toggle.Parent = Main

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = Toggle

local function setStatus(text)
    if Status and Status.Parent then
        Status.Text = tostring(text)
    end
end

local function updateButton()
    if State.Enabled then
        Toggle.Text = "ATIVO • AGUARDANDO OVO"
        Toggle.BackgroundColor3 = COLORS.GREEN
    else
        Toggle.Text = "ATIVAR"
        Toggle.BackgroundColor3 = COLORS.BUTTON
    end
end

--==============================================================--
-- DRAG MOBILE / PC
--==============================================================--

do
    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    Main.InputBegan:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    Main.InputChanged:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart

            Main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

--==============================================================--
-- MOVE ENGINE • INSTANT + REACTIVE
--==============================================================--

local function desiredSpeed(root, target)
    local distance =
        (root.Position - target).Magnitude

    return
        distance <= CONFIG.NEAR_SAFE_DISTANCE
        and CONFIG.NEAR_SAFE_SPEED
        or CONFIG.RUN_SPEED
end

local function forceRunSpeed(humanoid, root, target)
    saveBaseSpeed(humanoid)

    local speed =
        desiredSpeed(
            root,
            target
        )

    if humanoid.WalkSpeed ~= speed then
        humanoid.WalkSpeed = speed
    end

    return speed
end

local function reachedSafe(root)
    return isInsideSafeRegion(root.Position)
end

local function horizontalUnit(vector)
    local flat =
        Vector3.new(
            vector.X,
            0,
            vector.Z
        )

    if flat.Magnitude <= 0.001 then
        return Vector3.zero
    end

    return flat.Unit
end

local function rayBlocked(
    rootPosition,
    direction,
    distance,
    character
)
    if direction.Magnitude <= 0.001 then
        return false, nil
    end

    local origin =
        rootPosition
        + Vector3.new(
            0,
            CONFIG.DIRECT_RAY_HEIGHT,
            0
        )

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances =
        {character}

    params.IgnoreWater = false

    local result =
        Workspace:Raycast(
            origin,
            direction.Unit * distance,
            params
        )

    return result ~= nil, result
end

local function chooseInstantDirection(
    character,
    root,
    target
)
    local direct =
        horizontalUnit(
            target - root.Position
        )

    if direct.Magnitude <= 0 then
        return Vector3.zero
    end

    local blocked =
        rayBlocked(
            root.Position,
            direct,
            CONFIG.LOOK_AHEAD_DISTANCE,
            character
        )

    if not blocked then
        return direct
    end

    -- No route computation. Just react instantly to the wall:
    -- test both sides and choose the clearer steering direction.
    local left =
        horizontalUnit(
            Vector3.new(
                -direct.Z,
                0,
                direct.X
            )
        )

    local right = -left

    local leftBlocked =
        rayBlocked(
            root.Position,
            left,
            CONFIG.SIDE_LOOK_DISTANCE,
            character
        )

    local rightBlocked =
        rayBlocked(
            root.Position,
            right,
            CONFIG.SIDE_LOOK_DISTANCE,
            character
        )

    if not leftBlocked and rightBlocked then
        return horizontalUnit(
            direct
            + left * CONFIG.SIDE_BIAS
        )
    end

    if not rightBlocked and leftBlocked then
        return horizontalUnit(
            direct
            + right * CONFIG.SIDE_BIAS
        )
    end

    if not leftBlocked and not rightBlocked then
        -- Pick the side that aims closer toward Safe Zone after steering.
        local leftAim =
            horizontalUnit(
                direct
                + left * CONFIG.SIDE_BIAS
            )

        local rightAim =
            horizontalUnit(
                direct
                + right * CONFIG.SIDE_BIAS
            )

        local futureLeft =
            root.Position
            + leftAim * 8

        local futureRight =
            root.Position
            + rightAim * 8

        if
            (futureLeft - target).Magnitude
            <=
            (futureRight - target).Magnitude
        then
            return leftAim
        end

        return rightAim
    end

    -- Both immediate sides blocked: bias harder sideways and keep moving.
    -- Collision stays enabled, so it will not cross the wall.
    return horizontalUnit(
        direct + left * 1.35
    )
end

local function transportLoop(token)
    local lastStatus = ""

    while
        State.Enabled
        and State.Carrying
        and State.MoveToken == token
    do
        local character,
            humanoid,
            root =
            getCharacter()

        if not character
        or not humanoid
        or not root
        then
            setStatus(
                "Aguardando personagem..."
            )

            task.wait(0.03)
            continue
        end

        local target =
            nearestSafePoint(
                root.Position
            )

        State.CurrentTarget =
            target

        if reachedSafe(root) then
            humanoid:Move(
                Vector3.zero,
                false
            )

            setStatus(
                "Safe Zone alcançada • aguardando redeem..."
            )

            task.wait(0.03)
            continue
        end

        humanoid.Sit = false

        -- Lock the high speed before issuing movement.
        forceRunSpeed(
            humanoid,
            root,
            target
        )

        local direction =
            chooseInstantDirection(
                character,
                root,
                target
            )

        -- Immediate normal Humanoid movement. No MoveTo wait,
        -- no route calculation, no waypoint preparation.
        humanoid:Move(
            direction,
            false
        )

        local blocked =
            rayBlocked(
                root.Position,
                horizontalUnit(
                    target - root.Position
                ),
                CONFIG.LOOK_AHEAD_DISTANCE,
                character
            )

        local statusText =
            blocked
            and "MAX SPEED • desviando da parede"
            or "MAX SPEED • corrida direta"

        if statusText ~= lastStatus then
            lastStatus = statusText
            setStatus(statusText)
        end

        task.wait(
            CONFIG.STEER_REFRESH
        )
    end
end

--==============================================================--
-- CARRY CONTROL
--==============================================================--

local function beginCarry(uid, area)
    if not State.Enabled then
        return
    end

    if uid then
        State.EggUid = tostring(uid)
    end

    if area then
        State.EggArea = tostring(area)
    end

    if State.Carrying then
        return
    end

    State.Carrying = true
    State.MoveToken += 1

    State.CurrentTarget = nil
    State.LastRootPosition = nil
    State.LastProgressClock = os.clock()
    State.LastRepathClock = 0

    local token = State.MoveToken

    -- Start in the SAME callback that confirmed Carried.
    -- Do not wait for any route computation.
    local character, humanoid, root =
        getCharacter()

    if character and humanoid and root then
        local target =
            nearestSafePoint(
                root.Position
            )

        State.CurrentTarget =
            target

        forceRunSpeed(
            humanoid,
            root,
            target
        )

        humanoid:Move(
            chooseInstantDirection(
                character,
                root,
                target
            ),
            false
        )
    end

    setStatus(
        "Ovo confirmado ✓ • corrida instantânea"
    )

    task.spawn(
        transportLoop,
        token
    )
end

local function clearCarry(message)
    State.Carrying = false
    State.EggUid = nil
    State.EggArea = nil

    State.MoveToken += 1
    State.CurrentTarget = nil

    restoreMovement()

    if State.Enabled and message then
        setStatus(
            tostring(message)
            .. " • aguardando próximo ovo"
        )
    end
end

--==============================================================--
-- HARD SPEED LOCK WHILE CARRYING
--==============================================================--

local function reinforceSpeed()
    if
        not State.Enabled
        or not State.Carrying
        or not CONFIG.SPEED_LOCK
    then
        return
    end

    local character,
        humanoid,
        root =
        getCharacter()

    if not character
    or not humanoid
    or not root
    then
        return
    end

    local target =
        State.CurrentTarget
        or nearestSafePoint(
            root.Position
        )

    forceRunSpeed(
        humanoid,
        root,
        target
    )
end

-- Use both Stepped and Heartbeat because some local movement scripts
-- rewrite WalkSpeed during frame updates.
RunService.Stepped:
Connect(function()
    reinforceSpeed()
end)

RunService.Heartbeat:
Connect(function()
    reinforceSpeed()
end)

-- Also restore immediately if another LocalScript changes WalkSpeed.
local watchedHumanoid = nil
local speedChangedConnection = nil

local function watchHumanoidSpeed()
    if speedChangedConnection then
        speedChangedConnection:Disconnect()
        speedChangedConnection = nil
    end

    local _, humanoid =
        getCharacter()

    watchedHumanoid = humanoid

    if not humanoid then
        return
    end

    speedChangedConnection =
        humanoid:
        GetPropertyChangedSignal(
            "WalkSpeed"
        ):
        Connect(function()
            if
                State.Enabled
                and State.Carrying
                and watchedHumanoid
            then
                local _, currentHumanoid, root =
                    getCharacter()

                if
                    currentHumanoid == watchedHumanoid
                    and root
                then
                    local target =
                        State.CurrentTarget
                        or nearestSafePoint(
                            root.Position
                        )

                    task.defer(
                        forceRunSpeed,
                        currentHumanoid,
                        root,
                        target
                    )
                end
            end
        end)
end

watchHumanoidSpeed()

LocalPlayer.CharacterAdded:
Connect(function()
    task.wait(0.15)
    watchHumanoidSpeed()
end)

--==============================================================--
-- EGG EVENTS
--==============================================================--

if FieldEggCarry then
    table.insert(
        State.Connections,
        FieldEggCarry.OnClientEvent:
        Connect(function(...)
            if not State.Enabled then
                return
            end

            local data = parseArgs(...)

            local isCarrying =
                field(
                    data,
                    "IsCarrying",
                    "isCarrying"
                )

            local uid =
                dataUid(data)

            local area =
                field(
                    data,
                    "AreaId",
                    "areaId"
                )

            if isCarrying == true then
                beginCarry(
                    uid,
                    area
                )
            end

            -- IsCarrying=false alone is intentionally ignored.
            -- Delivery and drop are distinguished by definitive events.
        end)
    )
end

if FieldEggShifted then
    table.insert(
        State.Connections,
        FieldEggShifted.OnClientEvent:
        Connect(function(...)
            if not State.Enabled then
                return
            end

            local data = parseArgs(...)

            local uid =
                dataUid(data)

            local state =
                dataState(data)

            local carrier =
                dataCarrier(data)

            local area =
                field(
                    data,
                    "AreaId",
                    "areaId"
                )

            if
                state == "Carried"
                and (
                    carrier == nil
                    or carrier == LocalPlayer.UserId
                )
            then
                beginCarry(
                    uid,
                    area
                )
                return
            end

            local sameEgg =
                State.EggUid == nil
                or uid == nil
                or tostring(uid)
                    == tostring(State.EggUid)

            if not sameEgg then
                return
            end

            if state == "Dropped" then
                clearCarry(
                    "Ovo caiu"
                )

            elseif state == "GuardCarried" then
                clearCarry(
                    "Guarda recuperou o ovo"
                )

            elseif state == "Slot" then
                -- Slot can also mean guard return, so don't call it
                -- a successful redeem unless RedeemVerdict arrives.
                clearCarry(
                    "Ovo voltou para Slot"
                )
            end
        end)
    )
end

if FieldEggRedeemVerdict then
    table.insert(
        State.Connections,
        FieldEggRedeemVerdict.OnClientEvent:
        Connect(function(...)
            if not State.Enabled then
                return
            end

            clearCarry(
                "Entrega confirmada ✓"
            )
        end)
    )
end

if FieldEggGone then
    table.insert(
        State.Connections,
        FieldEggGone.OnClientEvent:
        Connect(function(...)
            if
                State.Enabled
                and State.Carrying
            then
                -- Gone commonly occurs immediately before RedeemVerdict.
                setStatus(
                    "Ovo removido do campo • aguardando confirmação..."
                )
            end
        end)
    )
end

--==============================================================--
-- TOGGLE
--==============================================================--

local function enable()
    State.Enabled = true
    State.Carrying = false
    State.EggUid = nil
    State.EggArea = nil
    State.CurrentTarget = nil

    restoreMovement()

    updateButton()

    setStatus(
        "Ativo • pegue um ovo manualmente"
    )
end

local function disable()
    State.Enabled = false
    State.Carrying = false

    State.MoveToken += 1

    State.EggUid = nil
    State.EggArea = nil
    State.CurrentTarget = nil

    restoreMovement()

    updateButton()
    setStatus("Desligado")
end

Toggle.Activated:
Connect(function()
    if State.Enabled then
        disable()
    else
        enable()
    end
end)

--==============================================================--
-- RESPAWN
--==============================================================--

LocalPlayer.CharacterAdded:
Connect(function()
    State.Carrying = false
    State.MoveToken += 1
    State.EggUid = nil
    State.EggArea = nil
    State.CurrentTarget = nil
    State.BaseWalkSpeed = nil

    if State.Enabled then
        setStatus(
            "Ativo • pegue um ovo manualmente"
        )
    end
end)

--==============================================================--
-- INITIAL
--==============================================================--

updateButton()

if FieldEggCarry or FieldEggShifted then
    setStatus(
        "Pronto • corrida instantânea + desvio reativo"
    )
else
    setStatus(
        "EggWorld não encontrado nesta sessão"
    )
end

print(
    "[CAFEÍNA] EGG FAST SAFE V6 INSTANT RUN carregado."
)
