--==============================================================--
-- CAFEÍNA • OUROBOROS FAITHFUL MOBILE V1
-- Steal An Egg • Android / executor-friendly
--
-- Reconstruído a partir da desofuscação estática V1–V15.
--
-- PRINCÍPIO:
--   CONFIRMED/HIGH  -> implementação baseada nos corpos/callsites recuperados
--   INFERRED/GUESS  -> comportamento aproximado, marcado no comentário
--
-- Inclui:
--   • Waypoint Teleport
--   • travelTo / travelAlong
--   • rawTeleport / tryTeleportTo
--   • buildLaneWaypoints
--   • buildStealPath (INFERRED literal; comportamento forte)
--   • stealAlong / stealMoveTo progressivo
--   • getZoneIndexByX / getEntryPosition
--   • getLaneY / getLaneZ / groundedY
--   • getBasePosition / FindRespawnCFrame / returnToBase
--   • Claim Offline Earnings
--   • Claim Codex
--   • Group Reward
--   • Base Tier Raise
--   • Auto Treadmill
--   • Auto Hatch SOMENTE ovos confirmados como próprios
--   • Egg ESP / Machine ESP
--   • WalkSpeed / Noclip / Infinite Jump
--   • Rejoin / Server Hop
--
-- Não contém:
--   • roubo de ovos/pets pertencentes a outros jogadores
--   • spoof de ownership
--   • bypass server-side / anti-cheat
--   • spam/fuzz de remotes desconhecidos
--   • manipulação de voto/autoridade
--==============================================================--

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")

local LP = Players.LocalPlayer

--==============================================================--
-- EXECUTOR COMPAT
--==============================================================--

local REQUEST =
    (syn and syn.request)
    or http_request
    or request
    or (http and http.request)

local function guiParent()
    if gethui then
        local ok, result = pcall(gethui)
        if ok and result then
            return result
        end
    end

    local ok, core = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and core then
        return core
    end

    return LP:WaitForChild("PlayerGui")
end

local ROOT_GUI = guiParent()

for _, child in ipairs(ROOT_GUI:GetChildren()) do
    if child.Name == "CafeinaOuroborosFaithful" then
        child:Destroy()
    end
end

--==============================================================--
-- GLOBAL STATE
--==============================================================--

local State = {
    Alive = true,
    Minimized = false,

    AutoTreadmill = false,
    AutoHatchOwned = false,

    EggESP = false,
    MachineESP = false,

    WalkSpeedEnabled = false,
    WalkSpeed = 30,
    Noclip = false,
    InfiniteJump = false,

    TeleportMode = "TRAVEL", -- TRAVEL / RAW / PROGRESSIVE
    SelectedWaypoint = 1,

    Status = "Pronto",
}

local Connections = {}
local Highlights = {}

local function remember(conn)
    table.insert(Connections, conn)
    return conn
end

local function setStatus(text)
    State.Status = tostring(text)
end

--==============================================================--
-- BASIC CHARACTER HELPERS
--
-- V14:
--   FN[adv592]  ~= getRoot
--   FN[adv1581] ~= getHumanoid
--==============================================================--

local function getCharacter()
    return LP.Character
end

local function getRoot()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

--==============================================================--
-- NETWORKING
--
-- V1–V15:
--   netInvoke / netCall behavior reconstructed.
--==============================================================--

local function networkingRoot()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if not packages then
        return nil
    end

    return packages:FindFirstChild("Networking")
end

local function resolveRemote(path)
    local root = networkingRoot()
    if not root then
        return nil
    end

    local direct = root:FindFirstChild(path)
    if direct then
        return direct
    end

    local current = root

    for segment in string.gmatch(path, "[^/]+") do
        current = current and current:FindFirstChild(segment)
        if not current then
            return nil
        end
    end

    return current
end

local function netCall(path, ...)
    local remote = resolveRemote(path)

    if not remote then
        return false, "Remote não encontrado: " .. tostring(path)
    end

    if remote:IsA("RemoteFunction") then
        local ok, a, b, c, d = pcall(remote.InvokeServer, remote, ...)
        if not ok then
            return false, a
        end
        return true, a, b, c, d
    end

    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(remote.FireServer, remote, ...)
        if not ok then
            return false, err
        end
        return true
    end

    return false, "Objeto encontrado não é RemoteFunction/RemoteEvent"
end

--==============================================================--
-- OWNERSHIP / UID
--==============================================================--

local OWNER_ATTRIBUTES = {
    "OwnerUserId",
    "OwnerId",
    "UserId",
    "PlayerUserId",
}

local UID_ATTRIBUTES = {
    "UID",
    "Uid",
    "uid",
    "EggUID",
    "AssetUID",
}

local function readOwner(obj)
    local current = obj

    for _ = 1, 5 do
        if not current then
            break
        end

        for _, name in ipairs(OWNER_ATTRIBUTES) do
            local value = current:GetAttribute(name)
            if tonumber(value) then
                return tonumber(value)
            end
        end

        for _, name in ipairs({"Owner", "Player", "User"}) do
            local child = current:FindFirstChild(name)

            if child then
                if child:IsA("ObjectValue") and child.Value == LP then
                    return LP.UserId
                end

                if child:IsA("IntValue") or child:IsA("NumberValue") then
                    return tonumber(child.Value)
                end

                if child:IsA("StringValue") then
                    if child.Value == LP.Name then
                        return LP.UserId
                    end

                    if tonumber(child.Value) then
                        return tonumber(child.Value)
                    end
                end
            end
        end

        current = current.Parent
    end

    return nil
end

local function readUID(obj)
    local current = obj

    for _ = 1, 5 do
        if not current then
            break
        end

        for _, name in ipairs(UID_ATTRIBUTES) do
            local attr = current:GetAttribute(name)

            if attr ~= nil then
                return attr
            end

            local child = current:FindFirstChild(name)

            if child and child:IsA("ValueBase") then
                return child.Value
            end
        end

        current = current.Parent
    end

    return nil
end

local function isOwnedEgg(obj)
    if not obj then
        return false
    end

    if not string.find(string.lower(obj.Name), "egg", 1, true) then
        return false
    end

    return readOwner(obj) == LP.UserId and readUID(obj) ~= nil
end

local function ownedEggCandidates()
    local result = {}
    local seen = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if not seen[obj] and isOwnedEgg(obj) then
            seen[obj] = true

            result[#result + 1] = {
                object = obj,
                uid = readUID(obj),
            }
        end
    end

    return result
end

--==============================================================--
-- MOVEMENT ENGINE
--==============================================================--

local Movement = {}

-- GUESS values:
-- The names/roles ArriveDistance and MoveTimeout are strong semantic matches,
-- but exact numeric values were not recovered.
Movement.Config = {
    ArriveDistance = 2.5,       -- GUESSED
    MoveTimeout = 14,           -- GUESSED
    StealSpeed = 78,            -- GUESSED default scalar
    LaneFallbackY = 74,         -- GUESSED based on observed map altitude
    LaneFallbackZ = -363,       -- GUESSED based on observed StartArea
    CorridorPadding = 8,        -- GUESSED
    TravelPause = 0.035,        -- GUESSED
    FinalYOffset = 3.0,         -- GUESSED
}

local ENTRY_NAMES = {
    "Entry",
    "Entrance",
    "EntryPart",
    "EntrancePart",
    "Gate",
    "Portal",
    "Spawn",
    "Start",
}

local ZONE_CONTAINER_NAMES = {
    "StealZones",
    "Zones",
    "Areas",
    "Worlds",
    "Biomes",
    "Regions",
    "MapZones",
}

local function lower(v)
    return string.lower(tostring(v))
end

local function toPosition(value)
    if typeof(value) == "Vector3" then
        return value
    end

    if typeof(value) == "CFrame" then
        return value.Position
    end

    if typeof(value) == "Instance" then
        if value:IsA("BasePart") then
            return value.Position
        end

        if value:IsA("Model") then
            local ok, cf = pcall(value.GetPivot, value)
            if ok and cf then
                return cf.Position
            end
        end

        local part = value:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end

    return nil
end

local function rayParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local char = getCharacter()

    if char then
        params.FilterDescendantsInstances = {char}
    else
        params.FilterDescendantsInstances = {}
    end

    return params
end

-- V12/V13:
--   FN[adv2006] ~= groundedY(x,z,fallbackY)
function Movement.groundedY(x, z, fallbackY)
    local startY = tonumber(fallbackY) or Movement.Config.LaneFallbackY

    local origin =
        Vector3.new(
            x,
            math.max(startY + 80, Movement.Config.LaneFallbackY + 80),
            z
        )

    local result =
        Workspace:Raycast(
            origin,
            Vector3.new(0, -220, 0),
            rayParams()
        )

    if result then
        return result.Position.Y + Movement.Config.FinalYOffset
    end

    return startY
end

local function allZoneContainers()
    local result = {}

    for _, name in ipairs(ZONE_CONTAINER_NAMES) do
        local direct = Workspace:FindFirstChild(name)
        if direct then
            result[#result + 1] = direct
        end
    end

    return result
end

function Movement.getZones()
    local result = {}
    local seen = {}

    for _, container in ipairs(allZoneContainers()) do
        for _, child in ipairs(container:GetChildren()) do
            if (
                child:IsA("Model")
                or child:IsA("Folder")
                or child:IsA("BasePart")
            ) and not seen[child] then
                seen[child] = true
                result[#result + 1] = child
            end
        end
    end

    table.sort(result, function(a, b)
        local pa = toPosition(a)
        local pb = toPosition(b)

        if pa and pb then
            return pa.X < pb.X
        end

        return a.Name < b.Name
    end)

    return result
end

-- V9:
--   getZoneModel behavior HIGH.
function Movement.getZoneModel(zone)
    if typeof(zone) == "number" then
        zone = Movement.getZones()[zone]
    end

    if not zone then
        return nil
    end

    if zone:IsA("BasePart") or zone:IsA("Model") then
        return zone
    end

    local model = zone:FindFirstChildWhichIsA("Model")
    if model then
        return model
    end

    local part = zone:FindFirstChildWhichIsA("BasePart", true)
    return part or zone
end

local function findNamedPart(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local obj = root:FindFirstChild(name, true)
        if obj and obj:IsA("BasePart") then
            return obj
        end
    end

    return nil
end

local function collectLaneSamples()
    local ys = {}
    local zs = {}

    for _, zone in ipairs(Movement.getZones()) do
        local entry = findNamedPart(zone, ENTRY_NAMES)

        if entry then
            ys[#ys + 1] = entry.Position.Y
            zs[#zs + 1] = entry.Position.Z
        else
            local p = toPosition(zone)
            if p then
                ys[#ys + 1] = p.Y
                zs[#zs + 1] = p.Z
            end
        end
    end

    local startArea = Workspace:FindFirstChild("StartArea", true)
    local startPos = toPosition(startArea)

    if startPos then
        ys[#ys + 1] = startPos.Y
        zs[#zs + 1] = startPos.Z
    end

    return ys, zs
end

local function median(numbers)
    if #numbers == 0 then
        return nil
    end

    table.sort(numbers)

    local mid = math.floor((#numbers + 1) / 2)

    if #numbers % 2 == 1 then
        return numbers[mid]
    end

    return (numbers[mid] + numbers[mid + 1]) / 2
end

-- V12:
--   FN1055 ~= getLaneY, zero arg.
function Movement.getLaneY()
    local ys = collectLaneSamples()
    return median(ys) or Movement.Config.LaneFallbackY
end

-- V7–V12:
--   FN1091 ~= getLaneZ, zero arg.
function Movement.getLaneZ()
    local _, zs = collectLaneSamples()
    return median(zs) or Movement.Config.LaneFallbackZ
end

-- V8–V14:
--   getEntryPosition(zone)
--   preserves entry X and places Y/Z on navigation lane.
function Movement.getEntryPosition(zone)
    zone = Movement.getZoneModel(zone)

    if not zone then
        return nil
    end

    local entry = findNamedPart(zone, ENTRY_NAMES)

    if entry then
        return Vector3.new(
            entry.Position.X,
            Movement.getLaneY(),
            Movement.getLaneZ()
        )
    end

    local p = toPosition(zone)

    if not p then
        return nil
    end

    return Vector3.new(
        p.X,
        Movement.getLaneY(),
        Movement.getLaneZ()
    )
end

-- V8/V10:
--   FN1866 ~= getZoneIndexByX
function Movement.getZoneIndexByX(x)
    local zones = Movement.getZones()

    if #zones == 0 then
        return nil
    end

    local bestIndex = 1
    local bestDistance = math.huge

    for index, zone in ipairs(zones) do
        local entry = Movement.getEntryPosition(zone)

        if entry then
            local distance = math.abs(entry.X - x)

            if distance < bestDistance then
                bestDistance = distance
                bestIndex = index
            end
        end
    end

    return bestIndex
end

-- V8/V9:
--   getCorridorBounds derived from zone geometry.
function Movement.getCorridorBounds()
    local minX = math.huge
    local maxX = -math.huge
    local minZ = math.huge
    local maxZ = -math.huge

    local found = false

    for _, zone in ipairs(Movement.getZones()) do
        local model = Movement.getZoneModel(zone)

        if model then
            if model:IsA("BasePart") then
                found = true

                local half = model.Size * 0.5

                minX = math.min(minX, model.Position.X - half.X)
                maxX = math.max(maxX, model.Position.X + half.X)
                minZ = math.min(minZ, model.Position.Z - half.Z)
                maxZ = math.max(maxZ, model.Position.Z + half.Z)

            elseif model:IsA("Model") then
                local ok, cf, size = pcall(model.GetBoundingBox, model)

                if ok and cf and size then
                    found = true

                    minX = math.min(minX, cf.Position.X - size.X * 0.5)
                    maxX = math.max(maxX, cf.Position.X + size.X * 0.5)
                    minZ = math.min(minZ, cf.Position.Z - size.Z * 0.5)
                    maxZ = math.max(maxZ, cf.Position.Z + size.Z * 0.5)
                end
            end
        end
    end

    if not found then
        local root = getRoot()
        local p = root and root.Position or Vector3.new(0, 0, 0)

        return {
            minX = p.X - 10000,
            maxX = p.X + 10000,
            minZ = p.Z - 10000,
            maxZ = p.Z + 10000,
        }
    end

    local padding = Movement.Config.CorridorPadding

    return {
        minX = minX - padding,
        maxX = maxX + padding,
        minZ = minZ - padding,
        maxZ = maxZ + padding,
    }
end

-- V8/V10:
--   FN96 ~= clampToCorridor
function Movement.clampToCorridor(position, enabled)
    if enabled ~= true then
        return position
    end

    local bounds = Movement.getCorridorBounds()

    return Vector3.new(
        math.clamp(position.X, bounds.minX, bounds.maxX),
        position.Y,
        math.clamp(position.Z, bounds.minZ, bounds.maxZ)
    )
end

-- V13:
--   FN1010 ~= rootCFrameWriter
function Movement.rootCFrameWriter(root, cf)
    if not root or not root.Parent then
        return false
    end

    root.CFrame = cf
    return true
end

-- V13:
--   FN1452 ~= movementSpeedProvider
function Movement.movementSpeedProvider()
    return Movement.Config.StealSpeed
end

-- V8–V14:
--   FN1177 ~= rawTeleport
function Movement.rawTeleport(target)
    local root = getRoot()
    local p = toPosition(target)

    if not root or not p then
        return false
    end

    return Movement.rootCFrameWriter(
        root,
        CFrame.new(p)
    )
end

-- V8–V14:
--   FN2004 ~= tryTeleportTo
function Movement.tryTeleportTo(target, shouldClamp)
    local p = toPosition(target)

    if not p then
        return false
    end

    p = Movement.clampToCorridor(
        p,
        shouldClamp == true
    )

    return Movement.rawTeleport(p)
end

-- V11:
--   FN307 ~= buildLaneWaypoints
--
-- HIGH behavior:
-- walks zone indexes using getZoneIndexByX/getEntryPosition.
function Movement.buildLaneWaypoints(currentPosition, targetZoneIndex)
    local path = {}

    if typeof(currentPosition) ~= "Vector3" or not targetZoneIndex then
        return path
    end

    local laneY = Movement.getLaneY()
    local laneZ = Movement.getLaneZ()

    if math.abs(currentPosition.Z - laneZ) > 2 then
        path[#path + 1] =
            Vector3.new(
                currentPosition.X,
                laneY,
                laneZ
            )
    end

    local zones = Movement.getZones()
    local currentIndex =
        Movement.getZoneIndexByX(
            currentPosition.X
        )

    if not currentIndex or #zones == 0 then
        return path
    end

    targetZoneIndex =
        math.clamp(
            targetZoneIndex,
            1,
            #zones
        )

    local direction =
        currentIndex <= targetZoneIndex
        and 1
        or -1

    local index = currentIndex

    while true do
        local zone = zones[index]

        if zone then
            local entry =
                Movement.getEntryPosition(zone)

            if entry then
                path[#path + 1] = entry
            end
        end

        if index == targetZoneIndex then
            break
        end

        index += direction

        if index < 1 or index > #zones then
            break
        end
    end

    return path
end

-- V12–V14:
--   FN1859 = adv1186
--   behavior: point-to-point lane path builder
--   likely plaintext = buildStealPath
--
-- INFERRED name, HIGH behavior.
function Movement.buildStealPath(startPosition, targetPosition)
    local startPos = toPosition(startPosition)
    local targetPos = toPosition(targetPosition)

    if not startPos or not targetPos then
        return {}
    end

    local laneY = Movement.getLaneY()
    local laneZ = Movement.getLaneZ()
    local points = {}

    if math.abs(startPos.Z - laneZ) > 2 then
        points[#points + 1] =
            Vector3.new(
                startPos.X,
                laneY,
                laneZ
            )
    end

    if math.abs(startPos.X - targetPos.X) > 2 then
        points[#points + 1] =
            Vector3.new(
                targetPos.X,
                laneY,
                laneZ
            )
    end

    points[#points + 1] =
        Vector3.new(
            targetPos.X,
            Movement.groundedY(
                targetPos.X,
                targetPos.Z,
                targetPos.Y
            ),
            targetPos.Z
        )

    return points
end

-- V12–V14:
--   FN46 ~= travelAlong
function Movement.travelAlong(points, abortCallback, option)
    for index, point in ipairs(points or {}) do
        if abortCallback and abortCallback() == false then
            return false
        end

        local isLast = index == #points

        -- Recovered body uses final-point information as clamp flag.
        local clampFlag = isLast

        if option == false then
            clampFlag = false
        end

        if not Movement.tryTeleportTo(point, clampFlag) then
            return false
        end

        task.wait(Movement.Config.TravelPause)
    end

    return true
end

-- V12/V13:
--   FN1061 ~= stealMoveTo
--   progressive movement using speed*RenderStepped dt.
function Movement.stealMoveTo(x, z, abortCallback)
    local root = getRoot()

    if not root then
        return false
    end

    local deadline =
        os.clock()
        + Movement.Config.MoveTimeout

    while State.Alive do
        root = getRoot()

        if not root then
            return false
        end

        if abortCallback and abortCallback() == false then
            return false
        end

        if os.clock() >= deadline then
            return false
        end

        local current = root.Position

        local targetY =
            Movement.groundedY(
                x,
                z,
                current.Y
            )

        local target =
            Vector3.new(
                x,
                targetY,
                z
            )

        local delta =
            target - current

        local distance =
            delta.Magnitude

        if distance <= Movement.Config.ArriveDistance then
            Movement.rootCFrameWriter(
                root,
                CFrame.new(target)
            )

            return true
        end

        local dt =
            RunService.RenderStepped:Wait()

        if type(dt) ~= "number" or dt <= 0 then
            dt = 1 / 60
        end

        local step =
            math.min(
                distance,
                Movement.movementSpeedProvider()
                * dt
            )

        local nextPosition =
            current
            + delta.Unit * step

        nextPosition =
            Vector3.new(
                nextPosition.X,
                Movement.groundedY(
                    nextPosition.X,
                    nextPosition.Z,
                    nextPosition.Y
                ),
                nextPosition.Z
            )

        Movement.rootCFrameWriter(
            root,
            CFrame.new(nextPosition)
        )
    end

    return false
end

-- V12/V13:
--   body HIGH, exact FN key unresolved.
function Movement.stealAlong(points, abortCallback)
    for _, point in ipairs(points or {}) do
        if abortCallback and abortCallback() == false then
            return false
        end

        if not Movement.stealMoveTo(
            point.X,
            point.Z,
            abortCallback
        ) then
            return false
        end
    end

    return true
end

-- V13/V14:
--   FN2134 ~= targetPositionResolver
function Movement.targetPositionResolver(argument)
    return toPosition(argument)
end

-- V9:
--   FN1231 ~= resolveWaypoint
function Movement.resolveWaypoint(selector)
    if typeof(selector) == "Vector3" then
        return selector
    end

    if typeof(selector) == "CFrame" then
        return selector.Position
    end

    if typeof(selector) == "Instance" then
        return toPosition(selector)
    end

    if typeof(selector) == "string" then
        local found = Workspace:FindFirstChild(selector, true)
        return found and toPosition(found) or nil
    end

    return nil
end

-- V14:
--   FN1783 ~= travelTo
function Movement.travelTo(argument)
    local target =
        Movement.targetPositionResolver(argument)

    local root =
        getRoot()

    if not target or not root then
        return false
    end

    local route =
        Movement.buildStealPath(
            root.Position,
            target
        )

    local callback = function()
        return State.Alive
    end

    if not Movement.travelAlong(
        route,
        callback,
        true
    ) then
        return false
    end

    root = getRoot()

    if root then
        local finalY =
            Movement.groundedY(
                target.X,
                target.Z,
                target.Y
            )

        Movement.rootCFrameWriter(
            root,
            CFrame.new(
                target.X,
                finalY,
                target.Z
            )
        )
    end

    return true
end

--==============================================================--
-- BASE / RESPAWN
--==============================================================--

local function ownerMatches(obj)
    local current = obj

    for _ = 1, 5 do
        if not current then
            break
        end

        if readOwner(current) == LP.UserId then
            return true
        end

        if string.find(
            lower(current.Name),
            lower(LP.Name),
            1,
            true
        ) then
            return true
        end

        current = current.Parent
    end

    return false
end

local function findOwnBase()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local n = lower(obj.Name)

            local looksLikeBase =
                string.find(n, "plot", 1, true)
                or string.find(n, "base", 1, true)
                or string.find(n, "homestead", 1, true)
                or string.find(n, "home", 1, true)

            if looksLikeBase and ownerMatches(obj) then
                return obj
            end
        end
    end

    return nil
end

-- V14:
--   FN399 ~= getBasePosition
function Movement.getBasePosition()
    local base = findOwnBase()

    if not base then
        return nil
    end

    local preferred =
        findNamedPart(
            base,
            {
                "Spawn",
                "SpawnPart",
                "Entry",
                "Entrance",
                "Center",
                "Anchor",
                "Main",
            }
        )

    return toPosition(preferred or base)
end

-- V14:
--   FN678 ~= FindRespawnCFrame
function Movement.FindRespawnCFrame()
    local char = getCharacter()

    if char then
        local attr = char:GetAttribute("RespawnCFrame")

        if typeof(attr) == "CFrame" then
            local p = attr.Position

            return Vector3.new(
                p.X,
                Movement.getLaneY(),
                Movement.getLaneZ()
            )
        end
    end

    for _, spawn in ipairs(Workspace:GetDescendants()) do
        if spawn:IsA("SpawnLocation") then
            local p = spawn.Position

            return Vector3.new(
                p.X,
                Movement.getLaneY(),
                Movement.getLaneZ()
            )
        end
    end

    local base = Movement.getBasePosition()

    if base then
        return Vector3.new(
            base.X,
            Movement.getLaneY(),
            Movement.getLaneZ()
        )
    end

    return nil
end

-- V14:
--   body behavior HIGH, exact FN key unresolved.
function Movement.returnToBase()
    local base = Movement.getBasePosition()

    if not base then
        return false, "Base própria não encontrada"
    end

    return Movement.travelTo(base)
end

function Movement.progressiveTo(argument)
    local target =
        Movement.targetPositionResolver(argument)

    local root =
        getRoot()

    if not target or not root then
        return false
    end

    local targetZone =
        Movement.getZoneIndexByX(
            target.X
        )

    local path = {}

    if targetZone then
        path =
            Movement.buildLaneWaypoints(
                root.Position,
                targetZone
            )
    end

    path[#path + 1] = target

    return Movement.stealAlong(
        path,
        function()
            return State.Alive
        end
    )
end

--==============================================================--
-- WAYPOINTS
--==============================================================--

local Waypoints = {}

local function addWaypoint(name, resolver, kind)
    Waypoints[#Waypoints + 1] = {
        Name = name,
        Resolver = resolver,
        Kind = kind or "WAYPOINT",
    }
end

local function firstWorldObject(names)
    for _, name in ipairs(names) do
        local obj = Workspace:FindFirstChild(name, true)
        if obj then
            return obj
        end
    end

    return nil
end

local function rebuildWaypoints()
    table.clear(Waypoints)

    addWaypoint(
        "MINHA BASE",
        function()
            return Movement.getBasePosition()
        end,
        "BASE"
    )

    addWaypoint(
        "RESPAWN",
        function()
            return Movement.FindRespawnCFrame()
        end,
        "BASE"
    )

    addWaypoint(
        "START AREA",
        function()
            return firstWorldObject({
                "StartArea",
                "Start Area",
                "Spawn",
            })
        end,
        "AREA"
    )

    addWaypoint(
        "TREADMILL",
        function()
            return firstWorldObject({
                "TreadmillBottom",
                "Treadmill",
                "Treadmills",
            })
        end,
        "MACHINE"
    )

    addWaypoint(
        "FUSE MACHINE",
        function()
            return firstWorldObject({
                "Fusery",
                "FuseMachine",
                "Fuse Machine",
                "Fuse",
            })
        end,
        "MACHINE"
    )

    local seen = {}

    for _, zone in ipairs(Movement.getZones()) do
        if not seen[zone] then
            seen[zone] = true
            local captured = zone

            addWaypoint(
                string.upper(captured.Name),
                function()
                    return Movement.getEntryPosition(captured) or captured
                end,
                "ZONE"
            )
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (
            obj:IsA("BasePart")
            or obj:IsA("Model")
        ) and not seen[obj] then
            local n = lower(obj.Name)

            if string.find(n, "waypoint", 1, true) then
                seen[obj] = true
                local captured = obj

                addWaypoint(
                    "WAYPOINT • " .. captured.Name,
                    function()
                        return captured
                    end,
                    "WAYPOINT"
                )
            end
        end
    end

    table.sort(Waypoints, function(a, b)
        local rank = {
            BASE = 1,
            AREA = 2,
            MACHINE = 3,
            ZONE = 4,
            WAYPOINT = 5,
        }

        local ra = rank[a.Kind] or 99
        local rb = rank[b.Kind] or 99

        if ra == rb then
            return a.Name < b.Name
        end

        return ra < rb
    end)

    if State.SelectedWaypoint > #Waypoints then
        State.SelectedWaypoint = 1
    end
end

local function selectedWaypoint()
    return Waypoints[State.SelectedWaypoint]
end

local function resolveSelectedWaypoint()
    local item = selectedWaypoint()

    if not item then
        return nil, "Nenhum waypoint"
    end

    local ok, value = pcall(item.Resolver)

    if not ok then
        return nil, value
    end

    local p = toPosition(value)

    if not p then
        return nil, "Destino indisponível agora"
    end

    return p
end

local function runSelectedTeleport()
    local target, err =
        resolveSelectedWaypoint()

    if not target then
        return false, err
    end

    if State.TeleportMode == "RAW" then
        return Movement.rawTeleport(target)
    end

    if State.TeleportMode == "PROGRESSIVE" then
        return Movement.progressiveTo(target)
    end

    return Movement.travelTo(target)
end

--==============================================================--
-- GAME FUNCTIONS
--==============================================================--

local function claimOffline()
    local ok, result =
        netCall(
            "RF/AwayEarnings/AskCollect"
        )

    if ok then
        setStatus("Offline Earnings solicitado")
    else
        setStatus(result)
    end
end

local function claimCodex()
    local ok, result =
        netCall(
            "RF/Codex/AskRedeemAll"
        )

    if ok then
        setStatus("Codex solicitado")
    else
        setStatus(result)
    end
end

local function claimGroupReward()
    local ok, result =
        netCall(
            "RF/GroupPerk/RedeemPerk"
        )

    if ok then
        setStatus("Group Reward solicitado")
    else
        setStatus(result)
    end
end

local function raiseBaseTier()
    local ok, result =
        netCall(
            "RE/Homestead/AskBaseTierRaise"
        )

    if ok then
        setStatus("Base Tier solicitado")
    else
        setStatus(result)
    end
end

local function askTreadmillWear()
    local ok, result =
        netCall(
            "RF/Treadmill/AskWearStill"
        )

    if not ok then
        setStatus(result)
        return false
    end

    setStatus("Treadmill solicitado")
    return true, result
end

local function askTreadmillDoff()
    local ok, result =
        netCall(
            "RF/Treadmill/AskDoff"
        )

    if ok then
        setStatus("Treadmill encerrado")
    else
        setStatus(result)
    end
end

local function hatchOwnedEggsOnce()
    local candidates =
        ownedEggCandidates()

    if #candidates == 0 then
        setStatus("Nenhum ovo próprio identificável")
        return 0
    end

    local count = 0

    for _, egg in ipairs(candidates) do
        if readOwner(egg.object) == LP.UserId then
            local ok =
                netCall(
                    "RF/EggWorld/AskHatch",
                    egg.uid
                )

            if ok then
                task.wait(0.12)

                netCall(
                    "RF/EggWorld/AskFinishHatch",
                    egg.uid
                )

                count += 1
            end
        end
    end

    setStatus(
        "Hatch próprio: "
        .. tostring(count)
    )

    return count
end

--==============================================================--
-- ESP
--==============================================================--

local function clearESP(kind)
    for obj, info in pairs(Highlights) do
        if not kind or info.Kind == kind then
            if info.Highlight then
                info.Highlight:Destroy()
            end

            Highlights[obj] = nil
        end
    end
end

local function addHighlight(obj, kind)
    if not obj or Highlights[obj] then
        return
    end

    local target = obj

    if not target:IsA("Model") and not target:IsA("BasePart") then
        target =
            target:FindFirstChildWhichIsA("Model")
            or target:FindFirstChildWhichIsA("BasePart", true)
    end

    if not target then
        return
    end

    local h = Instance.new("Highlight")
    h.Name = "Cafeina_" .. kind
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillTransparency = 0.75
    h.OutlineTransparency = 0.1
    h.Adornee = target
    h.Parent = ROOT_GUI

    Highlights[obj] = {
        Highlight = h,
        Kind = kind,
    }
end

local function refreshEggESP()
    clearESP("EGG")

    if not State.EggESP then
        return
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (
            obj:IsA("Model")
            or obj:IsA("BasePart")
        ) and string.find(
            lower(obj.Name),
            "egg",
            1,
            true
        ) then
            addHighlight(obj, "EGG")
        end
    end
end

local function refreshMachineESP()
    clearESP("MACHINE")

    if not State.MachineESP then
        return
    end

    local keywords = {
        "treadmill",
        "fuse",
        "fusery",
        "incubator",
        "machine",
    }

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local n = lower(obj.Name)

            for _, keyword in ipairs(keywords) do
                if string.find(n, keyword, 1, true) then
                    addHighlight(obj, "MACHINE")
                    break
                end
            end
        end
    end
end

--==============================================================--
-- LOCAL MOVEMENT LOOPS
--==============================================================--

remember(
    RunService.Stepped:Connect(function()
        if not State.Alive then
            return
        end

        local hum = getHumanoid()

        if hum and State.WalkSpeedEnabled then
            hum.WalkSpeed = State.WalkSpeed
        end

        if State.Noclip then
            local char = getCharacter()

            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end
    end)
)

remember(
    UserInputService.JumpRequest:Connect(function()
        if not State.InfiniteJump then
            return
        end

        local hum = getHumanoid()

        if hum then
            hum:ChangeState(
                Enum.HumanoidStateType.Jumping
            )
        end
    end)
)

task.spawn(function()
    while State.Alive do
        if State.AutoTreadmill then
            askTreadmillWear()
            task.wait(1.0)
        else
            task.wait(0.25)
        end
    end
end)

task.spawn(function()
    while State.Alive do
        if State.AutoHatchOwned then
            hatchOwnedEggsOnce()
            task.wait(1.5)
        else
            task.wait(0.35)
        end
    end
end)

task.spawn(function()
    while State.Alive do
        if State.EggESP then
            refreshEggESP()
        end

        if State.MachineESP then
            refreshMachineESP()
        end

        task.wait(3)
    end
end)

--==============================================================--
-- SERVER
--==============================================================--

local function rejoin()
    setStatus("Reentrando...")

    TeleportService:Teleport(
        game.PlaceId,
        LP
    )
end

local function serverHop()
    if not REQUEST then
        setStatus("Executor sem request/http")
        return
    end

    setStatus("Buscando servidor...")

    local url =
        "https://games.roblox.com/v1/games/"
        .. tostring(game.PlaceId)
        .. "/servers/Public?sortOrder=Asc&limit=100"

    local ok, response =
        pcall(REQUEST, {
            Url = url,
            Method = "GET",
        })

    if not ok or not response then
        setStatus("Falha no HTTP")
        return
    end

    local body =
        response.Body
        or response.body

    if type(body) ~= "string" then
        setStatus("Resposta HTTP inválida")
        return
    end

    local decodedOk, decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            body
        )

    if not decodedOk or not decoded or not decoded.data then
        setStatus("Lista de servidores inválida")
        return
    end

    local candidates = {}

    for _, server in ipairs(decoded.data) do
        if (
            server.id ~= game.JobId
            and tonumber(server.playing)
            and tonumber(server.maxPlayers)
            and server.playing < server.maxPlayers
        ) then
            candidates[#candidates + 1] = server
        end
    end

    if #candidates == 0 then
        setStatus("Nenhum servidor disponível")
        return
    end

    local pick =
        candidates[
            math.random(
                1,
                #candidates
            )
        ]

    setStatus("Trocando servidor...")

    TeleportService:TeleportToPlaceInstance(
        game.PlaceId,
        pick.id,
        LP
    )
end

--==============================================================--
-- UI
--==============================================================--

rebuildWaypoints()

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaOuroborosFaithful"
Gui.ResetOnSpawn = false
Gui.Parent = ROOT_GUI

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(334, 478)
Main.Position = UDim2.new(0.5, -167, 0.5, -239)
Main.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
Main.BorderSizePixel = 0
Main.Parent = Gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 52)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 0, 28)
Title.Position = UDim2.fromOffset(14, 6)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA • OUROBOROS"
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = Header

local SubTitle = Instance.new("TextLabel")
SubTitle.Size = UDim2.new(1, -100, 0, 18)
SubTitle.Position = UDim2.fromOffset(14, 30)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "FAITHFUL V1 • MOBILE"
SubTitle.TextColor3 = Color3.fromRGB(145, 145, 150)
SubTitle.TextXAlignment = Enum.TextXAlignment.Left
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 9
SubTitle.Parent = Header

local function headerButton(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(36, 34)
    b.Position = UDim2.new(1, x, 0, 9)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    b.TextColor3 = Color3.fromRGB(245, 245, 245)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.Text = text
    b.Parent = Header

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    return b
end

local MinButton = headerButton("—", -80)
local CloseButton = headerButton("×", -40)

local Tabs = Instance.new("ScrollingFrame")
Tabs.Size = UDim2.new(1, -20, 0, 38)
Tabs.Position = UDim2.fromOffset(10, 55)
Tabs.BackgroundTransparency = 1
Tabs.BorderSizePixel = 0
Tabs.ScrollBarThickness = 0
Tabs.ScrollingDirection = Enum.ScrollingDirection.X
Tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
Tabs.CanvasSize = UDim2.new()
Tabs.Parent = Main

local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 6)
tabsLayout.Parent = Tabs

local Pages = Instance.new("Frame")
Pages.Size = UDim2.new(1, -20, 1, -137)
Pages.Position = UDim2.fromOffset(10, 98)
Pages.BackgroundTransparency = 1
Pages.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 28)
Status.Position = UDim2.new(0, 10, 1, -34)
Status.BackgroundColor3 = Color3.fromRGB(22, 22, 25)
Status.TextColor3 = Color3.fromRGB(165, 165, 170)
Status.Font = Enum.Font.Gotham
Status.TextSize = 9
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "  Pronto"
Status.Parent = Main

local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0, 8)
sc.Parent = Status

local PageMap = {}
local TabMap = {}

local function makePage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new()
    page.Visible = false
    page.Parent = Pages

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.Parent = page

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 2)
    padding.PaddingRight = UDim.new(0, 2)
    padding.Parent = page

    PageMap[name] = page
    return page
end

local function showPage(name)
    for pageName, page in pairs(PageMap) do
        page.Visible = pageName == name
    end

    for tabName, tab in pairs(TabMap) do
        tab.BackgroundColor3 =
            tabName == name
            and Color3.fromRGB(55, 55, 63)
            or Color3.fromRGB(29, 29, 33)
    end
end

local function makeTab(text, pageName)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(76, 32)
    b.BackgroundColor3 = Color3.fromRGB(29, 29, 33)
    b.TextColor3 = Color3.fromRGB(238, 238, 240)
    b.Text = text
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 10
    b.Parent = Tabs

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b

    b.Activated:Connect(function()
        showPage(pageName)
    end)

    TabMap[pageName] = b
end

local function makeLabel(parent, text, size)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -4, 0, size or 28)
    lbl.BackgroundColor3 = Color3.fromRGB(21, 21, 24)
    lbl.TextColor3 = Color3.fromRGB(210, 210, 214)
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = "  " .. text
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = lbl

    return lbl
end

local function actionButton(parent, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, 38)
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
    b.TextColor3 = Color3.fromRGB(242, 242, 244)
    b.Text = text
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 11
    b.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b

    b.Activated:Connect(function()
        local ok, err = pcall(callback)

        if not ok then
            setStatus("Erro: " .. tostring(err))
        end
    end)

    return b
end

local function toggleButton(parent, label, getter, setter, changed)
    local b

    local function repaint()
        local on = getter()

        b.Text =
            label
            .. "  •  "
            .. (on and "ON" or "OFF")

        b.BackgroundColor3 =
            on
            and Color3.fromRGB(47, 47, 56)
            or Color3.fromRGB(29, 29, 34)
    end

    b = actionButton(parent, "", function()
        local newValue = not getter()
        setter(newValue)

        if changed then
            changed(newValue)
        end

        repaint()
    end)

    repaint()
    return b
end

--==============================================================--
-- PAGES
--==============================================================--

local HomePage = makePage("HOME")
local TeleportPage = makePage("TELEPORT")
local AutoPage = makePage("AUTO")
local VisualPage = makePage("VISUAL")
local MovePage = makePage("MOVE")
local ServerPage = makePage("SERVER")

makeTab("HOME", "HOME")
makeTab("TELEPORT", "TELEPORT")
makeTab("AUTO", "AUTO")
makeTab("VISUAL", "VISUAL")
makeTab("MOVE", "MOVE")
makeTab("SERVER", "SERVER")

-- HOME

makeLabel(
    HomePage,
    "Reconstrução V15: travelTo, travelAlong, rawTeleport, buildLaneWaypoints, getZoneIndexByX e movimento progressivo.",
    48
)

actionButton(HomePage, "CLAIM OFFLINE EARNINGS", claimOffline)
actionButton(HomePage, "CLAIM CODEX", claimCodex)
actionButton(HomePage, "GROUP REWARD", claimGroupReward)
actionButton(HomePage, "BASE TIER RAISE", raiseBaseTier)

actionButton(HomePage, "VOLTAR À BASE", function()
    setStatus("Voltando à base...")

    task.spawn(function()
        local ok, err =
            Movement.returnToBase()

        if ok then
            setStatus("Base alcançada")
        else
            setStatus(err or "Falha ao voltar")
        end
    end)
end)

-- TELEPORT

local SelectedLabel =
    makeLabel(
        TeleportPage,
        "DESTINO: carregando...",
        34
    )

local ModeLabel =
    makeLabel(
        TeleportPage,
        "MODO: TRAVEL",
        30
    )

local function refreshTeleportLabels()
    local item = selectedWaypoint()

    SelectedLabel.Text =
        "  DESTINO: "
        .. (
            item
            and item.Name
            or "NENHUM"
        )

    ModeLabel.Text =
        "  MODO: "
        .. State.TeleportMode
        .. " • "
        .. tostring(#Waypoints)
        .. " waypoint(s)"
end

actionButton(TeleportPage, "◀ WAYPOINT ANTERIOR", function()
    if #Waypoints == 0 then
        return
    end

    State.SelectedWaypoint -= 1

    if State.SelectedWaypoint < 1 then
        State.SelectedWaypoint = #Waypoints
    end

    refreshTeleportLabels()
end)

actionButton(TeleportPage, "PRÓXIMO WAYPOINT ▶", function()
    if #Waypoints == 0 then
        return
    end

    State.SelectedWaypoint += 1

    if State.SelectedWaypoint > #Waypoints then
        State.SelectedWaypoint = 1
    end

    refreshTeleportLabels()
end)

actionButton(TeleportPage, "MUDAR MODO", function()
    local order = {
        TRAVEL = "RAW",
        RAW = "PROGRESSIVE",
        PROGRESSIVE = "TRAVEL",
    }

    State.TeleportMode =
        order[State.TeleportMode]
        or "TRAVEL"

    refreshTeleportLabels()
end)

actionButton(TeleportPage, "TELEPORTAR AO WAYPOINT", function()
    setStatus(
        "Movendo via "
        .. State.TeleportMode
        .. "..."
    )

    task.spawn(function()
        local ok, err =
            runSelectedTeleport()

        if ok then
            setStatus("Destino alcançado")
        else
            setStatus(err or "Movimento falhou")
        end
    end)
end)

actionButton(TeleportPage, "ATUALIZAR WAYPOINTS", function()
    rebuildWaypoints()
    refreshTeleportLabels()
    setStatus("Waypoints atualizados")
end)

actionButton(TeleportPage, "RAW → MINHA BASE", function()
    local base = Movement.getBasePosition()

    if not base then
        setStatus("Base não encontrada")
        return
    end

    if Movement.rawTeleport(base) then
        setStatus("Raw teleport concluído")
    end
end)

actionButton(TeleportPage, "PROGRESSIVO → MINHA BASE", function()
    local base = Movement.getBasePosition()

    if not base then
        setStatus("Base não encontrada")
        return
    end

    task.spawn(function()
        if Movement.progressiveTo(base) then
            setStatus("Movimento progressivo concluído")
        else
            setStatus("Movimento progressivo falhou")
        end
    end)
end)

-- AUTO

toggleButton(
    AutoPage,
    "AUTO TREADMILL",
    function()
        return State.AutoTreadmill
    end,
    function(v)
        State.AutoTreadmill = v
    end,
    function(v)
        if not v then
            askTreadmillDoff()
        end
    end
)

toggleButton(
    AutoPage,
    "AUTO HATCH • MEUS OVOS",
    function()
        return State.AutoHatchOwned
    end,
    function(v)
        State.AutoHatchOwned = v
    end
)

actionButton(AutoPage, "HATCH MEUS OVOS AGORA", hatchOwnedEggsOnce)
actionButton(AutoPage, "CLAIM OFFLINE", claimOffline)
actionButton(AutoPage, "CLAIM CODEX", claimCodex)
actionButton(AutoPage, "GROUP REWARD", claimGroupReward)
actionButton(AutoPage, "BASE TIER RAISE", raiseBaseTier)

-- VISUAL

toggleButton(
    VisualPage,
    "EGG ESP",
    function()
        return State.EggESP
    end,
    function(v)
        State.EggESP = v
    end,
    function()
        refreshEggESP()
    end
)

toggleButton(
    VisualPage,
    "MACHINE ESP",
    function()
        return State.MachineESP
    end,
    function(v)
        State.MachineESP = v
    end,
    function()
        refreshMachineESP()
    end
)

actionButton(VisualPage, "REFRESH ESP", function()
    refreshEggESP()
    refreshMachineESP()
    setStatus("ESP atualizado")
end)

actionButton(VisualPage, "LIMPAR ESP", function()
    State.EggESP = false
    State.MachineESP = false
    clearESP()
    setStatus("ESP removido")
end)

-- MOVE

local SpeedLabel =
    makeLabel(
        MovePage,
        "WALKSPEED: "
        .. tostring(State.WalkSpeed),
        30
    )

toggleButton(
    MovePage,
    "WALKSPEED",
    function()
        return State.WalkSpeedEnabled
    end,
    function(v)
        State.WalkSpeedEnabled = v

        if not v then
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = 16
            end
        end
    end
)

actionButton(MovePage, "WALKSPEED +10", function()
    State.WalkSpeed =
        math.clamp(
            State.WalkSpeed + 10,
            16,
            200
        )

    SpeedLabel.Text =
        "  WALKSPEED: "
        .. tostring(State.WalkSpeed)
end)

actionButton(MovePage, "WALKSPEED -10", function()
    State.WalkSpeed =
        math.clamp(
            State.WalkSpeed - 10,
            16,
            200
        )

    SpeedLabel.Text =
        "  WALKSPEED: "
        .. tostring(State.WalkSpeed)
end)

toggleButton(
    MovePage,
    "NOCLIP",
    function()
        return State.Noclip
    end,
    function(v)
        State.Noclip = v
    end
)

toggleButton(
    MovePage,
    "INFINITE JUMP",
    function()
        return State.InfiniteJump
    end,
    function(v)
        State.InfiniteJump = v
    end
)

local StealSpeedLabel =
    makeLabel(
        MovePage,
        "PROGRESSIVE SPEED: "
        .. tostring(Movement.Config.StealSpeed),
        30
    )

actionButton(MovePage, "PROGRESSIVE SPEED +10", function()
    Movement.Config.StealSpeed =
        math.clamp(
            Movement.Config.StealSpeed + 10,
            20,
            250
        )

    StealSpeedLabel.Text =
        "  PROGRESSIVE SPEED: "
        .. tostring(Movement.Config.StealSpeed)
end)

actionButton(MovePage, "PROGRESSIVE SPEED -10", function()
    Movement.Config.StealSpeed =
        math.clamp(
            Movement.Config.StealSpeed - 10,
            20,
            250
        )

    StealSpeedLabel.Text =
        "  PROGRESSIVE SPEED: "
        .. tostring(Movement.Config.StealSpeed)
end)

-- SERVER

actionButton(ServerPage, "REJOIN", rejoin)
actionButton(ServerPage, "SERVER HOP", serverHop)

actionButton(ServerPage, "DESLIGAR TODAS AS FUNÇÕES", function()
    State.AutoTreadmill = false
    State.AutoHatchOwned = false
    State.EggESP = false
    State.MachineESP = false
    State.WalkSpeedEnabled = false
    State.Noclip = false
    State.InfiniteJump = false

    askTreadmillDoff()
    clearESP()

    setStatus("Tudo desligado")
end)

makeLabel(
    ServerPage,
    "Guess layer: números de velocidade/timeout e alguns nomes internos ainda não foram provados no V15.",
    48
)

--==============================================================--
-- MINIMIZED BUTTON
--==============================================================--

local Mini = Instance.new("TextButton")
Mini.Size = UDim2.fromOffset(54, 54)
Mini.Position = UDim2.new(0.5, -27, 0.5, -27)
Mini.BackgroundColor3 = Color3.fromRGB(17, 17, 20)
Mini.TextColor3 = Color3.fromRGB(245, 245, 245)
Mini.Text = "C"
Mini.Font = Enum.Font.GothamBold
Mini.TextSize = 18
Mini.Visible = false
Mini.Parent = Gui

local miniCorner = Instance.new("UICorner")
miniCorner.CornerRadius = UDim.new(1, 0)
miniCorner.Parent = Mini

MinButton.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

--==============================================================--
-- DRAG
--==============================================================--

local function makeDraggable(handle, target)
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    handle.InputBegan:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            dragInput = input
        end
    end)

    handle.InputChanged:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta =
                input.Position
                - dragStart

            target.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            dragging = false
        end
    end)
end

makeDraggable(Header, Main)
makeDraggable(Mini, Mini)

--==============================================================--
-- CLOSE / CLEANUP
--==============================================================--

local function shutdown()
    if not State.Alive then
        return
    end

    State.Alive = false

    State.AutoTreadmill = false
    State.AutoHatchOwned = false
    State.EggESP = false
    State.MachineESP = false
    State.WalkSpeedEnabled = false
    State.Noclip = false
    State.InfiniteJump = false

    pcall(askTreadmillDoff)
    clearESP()

    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    local hum = getHumanoid()

    if hum then
        pcall(function()
            hum.WalkSpeed = 16
        end)
    end

    Gui:Destroy()
end

CloseButton.Activated:Connect(shutdown)

--==============================================================--
-- STATUS LOOP
--==============================================================--

task.spawn(function()
    while State.Alive and Gui.Parent do
        Status.Text =
            "  "
            .. State.Status
            .. " • TP:"
            .. State.TeleportMode

        task.wait(0.15)
    end
end)

refreshTeleportLabels()
showPage("HOME")

setStatus(
    "Pronto • "
    .. tostring(#Waypoints)
    .. " waypoint(s)"
)

--==============================================================--
-- END
--==============================================================--
