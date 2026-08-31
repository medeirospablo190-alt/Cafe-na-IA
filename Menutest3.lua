--==============================================================--
-- CAFEÍNA • OUROBOROS FAITHFUL MOBILE V2
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
    TreadmillMounted = false,
    TreadmillBusy = false,

    EggESP = false,
    MachineESP = false,

    WalkSpeedEnabled = false,
    WalkSpeed = 30,
    Noclip = false,
    InfiniteJump = false,

    TeleportMode = "TRAVEL", -- TRAVEL / RAW / PROGRESSIVE
    SelectedWaypoint = 1,
    MoveToken = 0,
    TeleportBusy = false,

    Status = "Pronto",
}

local Connections = {}
local Highlights = {}
local ToggleRefreshers = {}
local NoclipOriginal = setmetatable({}, {__mode = "k"})
local WalkSpeedBaseline = setmetatable({}, {__mode = "k"})

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

    -- Some builds expose the full "RF/X/Y" name as one Instance.
    local direct = root:FindFirstChild(path)
    if direct and (direct:IsA("RemoteFunction") or direct:IsA("RemoteEvent")) then
        return direct
    end

    -- Other builds expose RF -> subsystem -> endpoint as folders.
    local current = root
    local nestedOk = true

    for segment in string.gmatch(path, "[^/]+") do
        current = current and current:FindFirstChild(segment)
        if not current then
            nestedOk = false
            break
        end
    end

    if nestedOk and current
        and (current:IsA("RemoteFunction") or current:IsA("RemoteEvent")) then
        return current
    end

    -- Last compatible form: descendants whose Name is the full path,
    -- or whose reconstructed ancestry ends with the requested path.
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent") then
            if obj.Name == path then
                return obj
            end

            local parts = {}
            local p = obj

            while p and p ~= root do
                table.insert(parts, 1, p.Name)
                p = p.Parent
            end

            local joined = table.concat(parts, "/")

            if joined == path or string.sub(joined, -#path) == path then
                return obj
            end
        end
    end

    return nil
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
    local seenUID = {}
    local seenObject = {}

    local function consider(obj, trustedOwnedContainer)
        if not obj or seenObject[obj] then
            return
        end

        seenObject[obj] = true

        local n = string.lower(obj.Name)
        local looksEggish =
            string.find(n, "egg", 1, true)
            or obj:IsA("Tool")

        if not looksEggish then
            return
        end

        local uid = readUID(obj)
        if uid == nil then
            return
        end

        local owner = readOwner(obj)

        -- Backpack/Character and the player's own plot are trusted local-owned
        -- containers. World objects still require explicit owner == LocalPlayer.
        if not trustedOwnedContainer and owner ~= LP.UserId then
            return
        end

        local key = tostring(uid)
        if seenUID[key] then
            return
        end

        seenUID[key] = true
        result[#result + 1] = {
            object = obj,
            uid = uid,
        }
    end

    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetDescendants()) do
            consider(obj, true)
        end
    end

    local char = getCharacter()
    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            consider(obj, true)
        end
    end

    -- Avoid scanning the entire Workspace every Auto-Hatch cycle.
    -- Only inspect the replicated egg slot container here; the player's own
    -- plot is added later by hatchOwnedEggsOnce().
    local areaEggs = Workspace:FindFirstChild("AreaEggSlotsClient")

    if areaEggs then
        for _, obj in ipairs(areaEggs:GetDescendants()) do
            consider(obj, false)
        end
    end

    return result
end

--==============================================================--
-- MOVEMENT ENGINE
--==============================================================--

local Movement = {}

Movement.Cache = {
    ZoneContainers = nil,
    Zones = nil,
    LaneY = nil,
    LaneZ = nil,
    CorridorBounds = nil,
}

function Movement.invalidateCache()
    Movement.Cache.ZoneContainers = nil
    Movement.Cache.Zones = nil
    Movement.Cache.LaneY = nil
    Movement.Cache.LaneZ = nil
    Movement.Cache.CorridorBounds = nil
end

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
    if Movement.Cache.ZoneContainers then
        return Movement.Cache.ZoneContainers
    end

    local result = {}
    local seen = {}
    local wanted = {}

    for _, name in ipairs(ZONE_CONTAINER_NAMES) do
        wanted[name] = true
    end

    local function add(obj)
        if obj and not seen[obj] then
            seen[obj] = true
            result[#result + 1] = obj
        end
    end

    for _, name in ipairs(ZONE_CONTAINER_NAMES) do
        add(Workspace:FindFirstChild(name))
    end

    -- One descendant pass only. The previous V2 draft did one pass per name,
    -- which is needlessly expensive on large mobile maps.
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if wanted[obj.Name]
            and (obj:IsA("Folder") or obj:IsA("Model")) then
            add(obj)
        end
    end

    table.sort(result, function(a, b)
        local ap = string.find(a:GetFullName(), "__OBJECTS.Areas", 1, true) and 0 or 1
        local bp = string.find(b:GetFullName(), "__OBJECTS.Areas", 1, true) and 0 or 1

        if ap ~= bp then
            return ap < bp
        end

        return a:GetFullName() < b:GetFullName()
    end)

    Movement.Cache.ZoneContainers = result
    return result
end

function Movement.getZones()
    if Movement.Cache.Zones then
        return Movement.Cache.Zones
    end

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

    Movement.Cache.Zones = result
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

    local function sample(obj)
        local p = toPosition(obj)
        if p then
            ys[#ys + 1] = p.Y
            zs[#zs + 1] = p.Z
            return p
        end
        return nil
    end

    -- These names were present in the observed map and are stronger lane
    -- anchors than arbitrary descendants of every zone.
    local gameplayZ = Workspace:FindFirstChild("GameplayZ", true)
    local startArea = Workspace:FindFirstChild("StartArea", true)

    local anchor =
        sample(gameplayZ)
        or sample(startArea)

    if not anchor then
        anchor = sample(startArea)
    end

    for _, zone in ipairs(Movement.getZones()) do
        local entry = findNamedPart(zone, ENTRY_NAMES)
        local p = toPosition(entry or zone)

        if p then
            -- Ignore far-off decorative models when a strong lane anchor exists.
            if not anchor or math.abs(p.Z - anchor.Z) <= 180 then
                ys[#ys + 1] = p.Y
                zs[#zs + 1] = p.Z
            end
        end
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
    if Movement.Cache.LaneY ~= nil then
        return Movement.Cache.LaneY
    end

    local ys = collectLaneSamples()
    Movement.Cache.LaneY =
        median(ys)
        or Movement.Config.LaneFallbackY

    return Movement.Cache.LaneY
end

-- V7–V12:
--   FN1091 ~= getLaneZ, zero arg.
function Movement.getLaneZ()
    if Movement.Cache.LaneZ ~= nil then
        return Movement.Cache.LaneZ
    end

    local _, zs = collectLaneSamples()
    Movement.Cache.LaneZ =
        median(zs)
        or Movement.Config.LaneFallbackZ

    return Movement.Cache.LaneZ
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
    if Movement.Cache.CorridorBounds then
        return Movement.Cache.CorridorBounds
    end

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

        Movement.Cache.CorridorBounds = {
            minX = p.X - 10000,
            maxX = p.X + 10000,
            minZ = p.Z - 10000,
            maxZ = p.Z + 10000,
        }

        return Movement.Cache.CorridorBounds
    end

    local padding = Movement.Config.CorridorPadding

    Movement.Cache.CorridorBounds = {
        minX = minX - padding,
        maxX = maxX + padding,
        minZ = minZ - padding,
        maxZ = maxZ + padding,
    }

    return Movement.Cache.CorridorBounds
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
function Movement.travelTo(argument, externalAbort)
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
        if not State.Alive then
            return false
        end

        if externalAbort and externalAbort() == false then
            return false
        end

        return true
    end

    -- Route points use the lane. The exact target is applied afterwards,
    -- un-clamped, so a machine/base outside the corridor is not truncated.
    if not Movement.travelAlong(
        route,
        callback,
        false
    ) then
        return false
    end

    if callback() == false then
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

    for _ = 1, 6 do
        if not current then
            break
        end

        if readOwner(current) == LP.UserId then
            return true
        end

        local lname = lower(current.Name)

        if string.find(lname, lower(LP.Name), 1, true)
            or string.find(lname, lower(LP.DisplayName), 1, true) then
            return true
        end

        current = current.Parent
    end

    return false
end

local function plotSignMatchesPlayer(plot)
    if not plot then
        return false
    end

    local playerName = plot:FindFirstChild("PlayerName", true)

    if playerName and playerName:IsA("TextLabel") then
        local text = string.lower(playerName.Text or "")

        if text == string.lower(LP.Name)
            or text == string.lower(LP.DisplayName) then
            return true
        end
    end

    local icon = plot:FindFirstChild("PlayerIcon", true)

    if icon and icon:IsA("ImageLabel") then
        local image = tostring(icon.Image)

        if string.find(image, "id=" .. tostring(LP.UserId), 1, true) then
            return true
        end
    end

    return ownerMatches(plot)
end

local function findOwnPlot()
    local plots = Workspace:FindFirstChild("Plots")

    if not plots then
        return nil
    end

    for _, plot in ipairs(plots:GetChildren()) do
        if plotSignMatchesPlayer(plot) then
            return plot
        end
    end

    -- Fallback: nearest plot SpawnPoint/CenterPoint to the player.
    -- This is only used when the sign has not replicated yet.
    local root = getRoot()
    if not root then
        return nil
    end

    local best
    local bestDistance = math.huge

    for _, plot in ipairs(plots:GetChildren()) do
        local point =
            plot:FindFirstChild("SpawnPoint")
            or plot:FindFirstChild("CenterPoint")
            or plot:FindFirstChild("CenterPoint", true)

        local p = toPosition(point)

        if p then
            local d = (Vector3.new(root.Position.X, 0, root.Position.Z)
                - Vector3.new(p.X, 0, p.Z)).Magnitude

            if d < bestDistance then
                bestDistance = d
                best = plot
            end
        end
    end

    -- Avoid accidentally selecting a remote plot when the player is out
    -- exploring the map.
    if best and bestDistance <= 150 then
        return best
    end

    return nil
end

local function findOwnBase()
    local plot = findOwnPlot()
    if plot then
        return plot
    end

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

local function findOwnTreadmillPart()
    local plot = findOwnPlot()

    if plot then
        local bottom = plot:FindFirstChild("TreadmillBottom", true)
        if bottom and bottom:IsA("BasePart") then
            return bottom
        end

        local treadmill = plot:FindFirstChild("Treadmill", true)
        if treadmill then
            local part =
                treadmill:IsA("BasePart")
                and treadmill
                or treadmill:FindFirstChildWhichIsA("BasePart", true)

            if part then
                return part
            end
        end
    end

    return nil
end

local function findOwnTreadmillTarget()
    local bottom = findOwnTreadmillPart()
    if not bottom then
        return nil
    end

    -- Prefer the replicated client render closest to this plot's treadmill,
    -- because the legit traces measured the character against that render.
    local renders = Workspace:FindFirstChild("__ClientTreadmillRenders")
    local bestRender
    local bestDistance = math.huge

    if renders then
        for _, obj in ipairs(renders:GetDescendants()) do
            if obj:IsA("BasePart") then
                local d =
                    (Vector3.new(obj.Position.X, 0, obj.Position.Z)
                    - Vector3.new(bottom.Position.X, 0, bottom.Position.Z)).Magnitude

                if d < bestDistance then
                    bestDistance = d
                    bestRender = obj
                end
            end
        end
    end

    local p =
        bestRender and bestDistance <= 90
        and bestRender.Position
        or bottom.Position

    return Vector3.new(
        p.X,
        Movement.groundedY(p.X, p.Z, p.Y + 5),
        p.Z
    )
end

-- V14:
--   FN399 ~= getBasePosition
function Movement.getBasePosition()
    local base = findOwnBase()

    if not base then
        return nil
    end

    local preferred =
        base:FindFirstChild("SpawnPoint")
        or base:FindFirstChild("CenterPoint")
        or findNamedPart(
            base,
            {
                "SpawnPoint",
                "CenterPoint",
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

    local ownPlot = findOwnPlot()

    if ownPlot then
        local spawn = ownPlot:FindFirstChild("SpawnPoint")
        if spawn and spawn:IsA("BasePart") then
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

function Movement.progressiveTo(argument, externalAbort)
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
            if not State.Alive then
                return false
            end

            if externalAbort and externalAbort() == false then
                return false
            end

            return true
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
    Movement.invalidateCache()
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
        "MINHA ESTEIRA",
        function()
            return findOwnTreadmillTarget()
                or firstWorldObject({
                    "TreadmillBottom",
                    "Treadmill",
                    "Treadmills",
                })
        end,
        "MACHINE"
    )

    if game.PlaceId == 107778070777162 then
        addWaypoint(
            "SAFE ZONE • OBSERVADA",
            function()
                -- Center of the previously observed safe-zone region.
                -- It is intentionally labeled OBSERVED rather than exact.
                return Vector3.new(
                    529.4,
                    72.1,
                    -360.4
                )
            end,
            "AREA"
        )
    end

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

    local genericCount = 0

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if genericCount >= 60 then
            break
        end

        if (
            obj:IsA("BasePart")
            or obj:IsA("Model")
        ) and not seen[obj] then
            local n = lower(obj.Name)

            if string.find(n, "waypoint", 1, true) then
                seen[obj] = true
                genericCount += 1
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

local function stopMovement()
    State.MoveToken += 1
    State.TeleportBusy = false
end

local function runSelectedTeleport()
    local target, err =
        resolveSelectedWaypoint()

    if not target then
        return false, err
    end

    stopMovement()
    local token = State.MoveToken
    State.TeleportBusy = true

    local function stillCurrent()
        return State.Alive and token == State.MoveToken
    end

    local ok

    if State.TeleportMode == "RAW" then
        ok = Movement.rawTeleport(target)

    elseif State.TeleportMode == "PROGRESSIVE" then
        ok = Movement.progressiveTo(
            target,
            stillCurrent
        )

    else
        ok = Movement.travelTo(
            target,
            stillCurrent
        )
    end

    if token == State.MoveToken then
        State.TeleportBusy = false
    end

    return ok
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
    local ok, accepted, reason =
        netCall(
            "RF/Treadmill/AskWearStill"
        )

    if not ok then
        State.TreadmillMounted = false
        setStatus(accepted)
        return false
    end

    if accepted == false then
        State.TreadmillMounted = false
        setStatus("Esteira: " .. tostring(reason or "servidor recusou"))
        return false, reason
    end

    State.TreadmillMounted = true
    setStatus("Esteira conectada")
    return true, accepted
end

local function askTreadmillDoff()
    local ok, result =
        netCall(
            "RF/Treadmill/AskDoff"
        )

    State.TreadmillMounted = false
    State.TreadmillBusy = false

    if ok then
        setStatus("Esteira encerrada")
    else
        setStatus(result)
    end
end

local function ensureTreadmillMounted()
    if not State.AutoTreadmill
        or State.TreadmillMounted
        or State.TreadmillBusy then
        return
    end

    State.TreadmillBusy = true

    local target = findOwnTreadmillTarget()

    if not target then
        State.TreadmillBusy = false
        setStatus("Minha esteira não foi identificada")
        return
    end

    setStatus("Indo para minha esteira...")

    local token = State.MoveToken + 1
    State.MoveToken = token

    local moved =
        Movement.travelTo(
            target,
            function()
                return State.Alive
                    and State.AutoTreadmill
                    and State.MoveToken == token
            end
        )

    if not moved then
        State.TreadmillBusy = false
        setStatus("Não consegui chegar na esteira")
        return
    end

    task.wait(0.25)

    if State.AutoTreadmill then
        askTreadmillWear()
    end

    State.TreadmillBusy = false
end

local function hatchOwnedEggsOnce()
    local candidates =
        ownedEggCandidates()

    -- The player's plot is a stronger ownership container than arbitrary
    -- Workspace objects. Add UID-bearing egg-like descendants there even
    -- when the model itself does not expose OwnerUserId.
    local plot = findOwnPlot()

    if plot then
        local known = {}
        for _, item in ipairs(candidates) do
            known[tostring(item.uid)] = true
        end

        for _, obj in ipairs(plot:GetDescendants()) do
            local uid = readUID(obj)
            local n = lower(obj.Name)

            if uid ~= nil
                and string.find(n, "egg", 1, true)
                and not known[tostring(uid)] then
                known[tostring(uid)] = true

                candidates[#candidates + 1] = {
                    object = obj,
                    uid = uid,
                }
            end
        end
    end

    if #candidates == 0 then
        setStatus("Nenhum ovo próprio identificável")
        return 0
    end

    local count = 0

    for _, egg in ipairs(candidates) do
        local ok, accepted =
            netCall(
                "RF/EggWorld/AskHatch",
                egg.uid
            )

        if ok and accepted ~= false then
            task.wait(0.12)

            netCall(
                "RF/EggWorld/AskFinishHatch",
                egg.uid
            )

            count += 1
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

    local roots = {
        Workspace:FindFirstChild("AreaEggSlotsClient"),
        findOwnPlot(),
    }

    local count = 0

    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if count >= 220 then
                    break
                end

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
                    count += 1
                end
            end
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

    local roots = {
        Workspace:FindFirstChild("Plots"),
        Workspace:FindFirstChild("__ClientTreadmillRenders"),
        ReplicatedStorage:FindFirstChild("Assets"),
    }

    local count = 0

    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if count >= 100 then
                    break
                end

                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local n = lower(obj.Name)

                    for _, keyword in ipairs(keywords) do
                        if string.find(n, keyword, 1, true) then
                            addHighlight(obj, "MACHINE")
                            count += 1
                            break
                        end
                    end
                end
            end
        end
    end
end

--==============================================================--
-- LOCAL MOVEMENT LOOPS
--==============================================================--

local function restoreNoclip()
    for part, original in pairs(NoclipOriginal) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = original
            end)
        end
        NoclipOriginal[part] = nil
    end
end

local function restoreWalkSpeed()
    local hum = getHumanoid()

    if hum then
        local baseline = WalkSpeedBaseline[hum]

        if baseline ~= nil then
            hum.WalkSpeed = baseline
            WalkSpeedBaseline[hum] = nil
        end
    end
end

remember(
    RunService.Stepped:Connect(function()
        if not State.Alive then
            return
        end

        local hum = getHumanoid()

        if hum and State.WalkSpeedEnabled then
            if WalkSpeedBaseline[hum] == nil then
                WalkSpeedBaseline[hum] = hum.WalkSpeed
            end

            hum.WalkSpeed = State.WalkSpeed
        end

        if State.Noclip then
            local char = getCharacter()

            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if NoclipOriginal[part] == nil then
                            NoclipOriginal[part] = part.CanCollide
                        end

                        part.CanCollide = false
                    end
                end
            end
        end
    end)
)

remember(
    LP.CharacterAdded:Connect(function()
        restoreNoclip()
        table.clear(WalkSpeedBaseline)
        State.TreadmillMounted = false
        State.TreadmillBusy = false
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
            if State.TreadmillMounted then
                local target = findOwnTreadmillTarget()
                local root = getRoot()

                if target and root then
                    local horizontal =
                        (Vector3.new(root.Position.X, 0, root.Position.Z)
                        - Vector3.new(target.X, 0, target.Z)).Magnitude

                    if horizontal > 18 then
                        State.TreadmillMounted = false
                    end
                end

                task.wait(1.0)
            else
                ensureTreadmillMounted()
                task.wait(2.5)
            end
        else
            task.wait(0.35)
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

        task.wait(5)
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

local function preferredMainSize()
    local viewport =
        Workspace.CurrentCamera
        and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(360, 640)

    local width = math.clamp(viewport.X - 14, 304, 370)
    local height = math.clamp(viewport.Y - 72, 430, 540)

    return Vector2.new(width, height)
end

local initialSize = preferredMainSize()

Main.Size = UDim2.fromOffset(initialSize.X, initialSize.Y)
Main.Position = UDim2.new(0.5, -initialSize.X * 0.5, 0.5, -initialSize.Y * 0.5)
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
SubTitle.Text = "FAITHFUL V2 • MOBILE"
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
    b.Size = UDim2.fromOffset(82, 34)
    b.BackgroundColor3 = Color3.fromRGB(29, 29, 33)
    b.TextColor3 = Color3.fromRGB(238, 238, 240)
    b.Text = text
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 11
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
    lbl.TextSize = 11
    lbl.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = lbl

    return lbl
end

local function actionButton(parent, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, 44)
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
    b.TextColor3 = Color3.fromRGB(242, 242, 244)
    b.Text = text
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
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

    ToggleRefreshers[#ToggleRefreshers + 1] = repaint
    repaint()
    return b
end

local function refreshAllToggles()
    for _, fn in ipairs(ToggleRefreshers) do
        pcall(fn)
    end
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
    "V2 mobile: destinos tocáveis + prévia, base/esteira pelo PlotSign, movimento cancelável e restauração segura de WalkSpeed/Noclip.",
    48
)

local DiagnosticsLabel =
    makeLabel(
        HomePage,
        "DIAGNÓSTICO: ainda não verificado",
        42
    )

local function refreshDiagnostics()
    local checks = {
        {"OFFLINE", "RF/AwayEarnings/AskCollect"},
        {"CODEX", "RF/Codex/AskRedeemAll"},
        {"GRUPO", "RF/GroupPerk/RedeemPerk"},
        {"BASE", "RE/Homestead/AskBaseTierRaise"},
        {"TREAD", "RF/Treadmill/AskWearStill"},
        {"DOFF", "RF/Treadmill/AskDoff"},
        {"HATCH", "RF/EggWorld/AskHatch"},
        {"FINISH", "RF/EggWorld/AskFinishHatch"},
    }

    local found = 0

    for _, check in ipairs(checks) do
        if resolveRemote(check[2]) then
            found += 1
        end
    end

    local plotOk = findOwnPlot() ~= nil
    local treadmillOk = findOwnTreadmillTarget() ~= nil

    DiagnosticsLabel.Text =
        "  DIAGNÓSTICO: "
        .. tostring(found)
        .. "/"
        .. tostring(#checks)
        .. " remotes • plot "
        .. (plotOk and "OK" or "?")
        .. " • esteira "
        .. (treadmillOk and "OK" or "?")

    return found, #checks
end

actionButton(HomePage, "VERIFICAR FUNÇÕES", function()
    local found, total = refreshDiagnostics()

    setStatus(
        "Diagnóstico: "
        .. tostring(found)
        .. "/"
        .. tostring(total)
        .. " remotes"
    )
end)

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

local TeleportHeader =
    makeLabel(
        TeleportPage,
        "DESTINO • toque em um item da lista",
        34
    )

local PreviewCard = Instance.new("Frame")
PreviewCard.Size = UDim2.new(1, -4, 0, 128)
PreviewCard.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
PreviewCard.Parent = TeleportPage

local previewCorner = Instance.new("UICorner")
previewCorner.CornerRadius = UDim.new(0, 10)
previewCorner.Parent = PreviewCard

local PreviewText = Instance.new("TextLabel")
PreviewText.Size = UDim2.new(1, -134, 1, -12)
PreviewText.Position = UDim2.fromOffset(10, 6)
PreviewText.BackgroundTransparency = 1
PreviewText.TextColor3 = Color3.fromRGB(226, 226, 230)
PreviewText.TextXAlignment = Enum.TextXAlignment.Left
PreviewText.TextYAlignment = Enum.TextYAlignment.Top
PreviewText.TextWrapped = true
PreviewText.Font = Enum.Font.Gotham
PreviewText.TextSize = 11
PreviewText.Text = "Carregando destino..."
PreviewText.Parent = PreviewCard

-- Small top-down schematic radar: player is centered, target dot shows
-- relative direction/distance. This is a visual preview, not a map of walls.
local Radar = Instance.new("Frame")
Radar.Size = UDim2.fromOffset(112, 112)
Radar.Position = UDim2.new(1, -120, 0, 8)
Radar.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
Radar.ClipsDescendants = true
Radar.Parent = PreviewCard

local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(0, 10)
radarCorner.Parent = Radar

local AxisX = Instance.new("Frame")
AxisX.Size = UDim2.new(1, -12, 0, 1)
AxisX.Position = UDim2.new(0, 6, 0.5, 0)
AxisX.BackgroundColor3 = Color3.fromRGB(55, 55, 62)
AxisX.BorderSizePixel = 0
AxisX.Parent = Radar

local AxisZ = Instance.new("Frame")
AxisZ.Size = UDim2.new(0, 1, 1, -12)
AxisZ.Position = UDim2.new(0.5, 0, 0, 6)
AxisZ.BackgroundColor3 = Color3.fromRGB(55, 55, 62)
AxisZ.BorderSizePixel = 0
AxisZ.Parent = Radar

local PlayerDot = Instance.new("Frame")
PlayerDot.Size = UDim2.fromOffset(10, 10)
PlayerDot.AnchorPoint = Vector2.new(0.5, 0.5)
PlayerDot.Position = UDim2.fromScale(0.5, 0.5)
PlayerDot.BackgroundColor3 = Color3.fromRGB(235, 235, 238)
PlayerDot.BorderSizePixel = 0
PlayerDot.Parent = Radar

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(1, 0)
pc.Parent = PlayerDot

local TargetDot = Instance.new("Frame")
TargetDot.Size = UDim2.fromOffset(11, 11)
TargetDot.AnchorPoint = Vector2.new(0.5, 0.5)
TargetDot.Position = UDim2.fromScale(0.5, 0.5)
TargetDot.BackgroundColor3 = Color3.fromRGB(105, 105, 118)
TargetDot.BorderSizePixel = 0
TargetDot.Parent = Radar

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(1, 0)
tc.Parent = TargetDot

local ModeBar = Instance.new("Frame")
ModeBar.Size = UDim2.new(1, -4, 0, 44)
ModeBar.BackgroundTransparency = 1
ModeBar.Parent = TeleportPage

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
modeLayout.Padding = UDim.new(0, 6)
modeLayout.Parent = ModeBar

local ModeButtons = {}

local function repaintModes()
    for mode, b in pairs(ModeButtons) do
        local selected = State.TeleportMode == mode

        b.BackgroundColor3 =
            selected
            and Color3.fromRGB(63, 63, 74)
            or Color3.fromRGB(29, 29, 34)

        b.Text =
            (selected and "● " or "")
            .. mode
    end
end

for _, mode in ipairs({"TRAVEL", "RAW", "PROGRESSIVE"}) do
    local captured = mode
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(mode == "PROGRESSIVE" and 112 or 82, 42)
    b.BackgroundColor3 = Color3.fromRGB(29, 29, 34)
    b.TextColor3 = Color3.fromRGB(242, 242, 244)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 11
    b.Text = mode
    b.Parent = ModeBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b

    b.Activated:Connect(function()
        State.TeleportMode = captured
        repaintModes()
    end)

    ModeButtons[captured] = b
end

local DestinationList = Instance.new("ScrollingFrame")
DestinationList.Size = UDim2.new(1, -4, 0, 178)
DestinationList.BackgroundColor3 = Color3.fromRGB(17, 17, 20)
DestinationList.BorderSizePixel = 0
DestinationList.ScrollBarThickness = 4
DestinationList.AutomaticCanvasSize = Enum.AutomaticSize.Y
DestinationList.CanvasSize = UDim2.new()
DestinationList.Parent = TeleportPage

local dlc = Instance.new("UICorner")
dlc.CornerRadius = UDim.new(0, 10)
dlc.Parent = DestinationList

local dlp = Instance.new("UIPadding")
dlp.PaddingTop = UDim.new(0, 6)
dlp.PaddingBottom = UDim.new(0, 6)
dlp.PaddingLeft = UDim.new(0, 6)
dlp.PaddingRight = UDim.new(0, 6)
dlp.Parent = DestinationList

local dll = Instance.new("UIListLayout")
dll.Padding = UDim.new(0, 5)
dll.Parent = DestinationList

local DestinationButtons = {}

local function selectedTargetInfo()
    local item = selectedWaypoint()
    local target = nil

    if item then
        local ok, value = pcall(item.Resolver)
        if ok then
            target = toPosition(value)
        end
    end

    return item, target
end

local function routePointCount(target)
    local root = getRoot()
    if not root or not target then
        return 0
    end

    if State.TeleportMode == "RAW" then
        return 1
    elseif State.TeleportMode == "PROGRESSIVE" then
        local zi = Movement.getZoneIndexByX(target.X)
        if zi then
            return #Movement.buildLaneWaypoints(root.Position, zi) + 1
        end
        return 1
    end

    return #Movement.buildStealPath(root.Position, target)
end

local function refreshTeleportPreview()
    local item, target = selectedTargetInfo()
    local root = getRoot()

    if not item then
        PreviewText.Text = "Nenhum destino selecionado."
        TargetDot.Visible = false
        return
    end

    if not target then
        PreviewText.Text =
            item.Name
            .. "\nMODO: "
            .. State.TeleportMode
            .. "\nDestino indisponível agora."
        TargetDot.Visible = false
        return
    end

    local distance = 0
    local dx, dz = 0, 0

    if root then
        dx = target.X - root.Position.X
        dz = target.Z - root.Position.Z
        distance =
            Vector3.new(dx, 0, dz).Magnitude
    end

    local zoneIndex = Movement.getZoneIndexByX(target.X)
    local points = routePointCount(target)

    PreviewText.Text =
        item.Name
        .. "\nMODO: "
        .. State.TeleportMode
        .. (State.TeleportBusy and " • MOVENDO" or "")
        .. "\nX "
        .. string.format("%.1f", target.X)
        .. "  Y "
        .. string.format("%.1f", target.Y)
        .. "  Z "
        .. string.format("%.1f", target.Z)
        .. "\nDIST "
        .. string.format("%.0f", distance)
        .. " • ZONA "
        .. tostring(zoneIndex or "-")
        .. " • "
        .. tostring(points)
        .. " ponto(s)"

    if root then
        TargetDot.Visible = true

        local scale =
            math.max(
                math.abs(dx),
                math.abs(dz),
                1
            )

        local nx =
            math.clamp(
                dx / scale,
                -1,
                1
            )

        local nz =
            math.clamp(
                dz / scale,
                -1,
                1
            )

        TargetDot.Position =
            UDim2.fromScale(
                0.5 + nx * 0.40,
                0.5 + nz * 0.40
            )
    else
        TargetDot.Visible = false
    end
end

local function repaintDestinationButtons()
    for index, b in pairs(DestinationButtons) do
        local selected = index == State.SelectedWaypoint

        b.BackgroundColor3 =
            selected
            and Color3.fromRGB(57, 57, 67)
            or Color3.fromRGB(27, 27, 31)

        local item = Waypoints[index]

        if item then
            b.Text =
                (selected and "●  " or "○  ")
                .. item.Name
                .. "   · "
                .. item.Kind
        end
    end

    refreshTeleportPreview()
end

local function rebuildDestinationButtons()
    for _, b in pairs(DestinationButtons) do
        pcall(function()
            b:Destroy()
        end)
    end

    table.clear(DestinationButtons)

    for index, item in ipairs(Waypoints) do
        local capturedIndex = index

        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -2, 0, 42)
        b.BackgroundColor3 = Color3.fromRGB(27, 27, 31)
        b.TextColor3 = Color3.fromRGB(235, 235, 238)
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Font = Enum.Font.GothamSemibold
        b.TextSize = 11
        b.Text = "○  " .. item.Name .. "   · " .. item.Kind
        b.Parent = DestinationList

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = b

        b.Activated:Connect(function()
            State.SelectedWaypoint = capturedIndex
            repaintDestinationButtons()
        end)

        DestinationButtons[capturedIndex] = b
    end

    repaintDestinationButtons()
end

actionButton(TeleportPage, "TELEPORTAR PARA O SELECIONADO", function()
    if State.TeleportBusy then
        setStatus("Movimento já em andamento")
        return
    end

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
            setStatus(err or "Movimento cancelado/falhou")
        end

        refreshTeleportPreview()
    end)
end)

actionButton(TeleportPage, "PARAR MOVIMENTO", function()
    stopMovement()
    setStatus("Movimento interrompido")
    refreshTeleportPreview()
end)

actionButton(TeleportPage, "ATUALIZAR DESTINOS", function()
    rebuildWaypoints()
    rebuildDestinationButtons()
    setStatus("Destinos atualizados")
end)

makeLabel(
    TeleportPage,
    "TRAVEL = rota por lane • RAW = direto • PROGRESSIVE = movimento por frames",
    42
)

repaintModes()
rebuildDestinationButtons()

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
        if v then
            State.TreadmillMounted = false
            task.spawn(ensureTreadmillMounted)
        else
            stopMovement()
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

        local hum = getHumanoid()

        if v and hum and WalkSpeedBaseline[hum] == nil then
            WalkSpeedBaseline[hum] = hum.WalkSpeed
        elseif not v then
            restoreWalkSpeed()
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

        if not v then
            restoreNoclip()
        end
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

    stopMovement()
    askTreadmillDoff()
    clearESP()
    restoreNoclip()
    restoreWalkSpeed()
    refreshAllToggles()

    setStatus("Tudo desligado")
end)

makeLabel(
    ServerPage,
    "Guess layer: números de velocidade/timeout e alguns nomes internos ainda não foram provados no V15.",
    48
)

--==============================================================--
-- RESPONSIVE / LIVE PREVIEW
--==============================================================--

local function applyResponsiveSize()
    if not Main or not Main.Parent then
        return
    end

    local size = preferredMainSize()
    Main.Size = UDim2.fromOffset(size.X, size.Y)

    -- Only recenter when the menu has not been dragged far away.
    if math.abs(Main.Position.X.Scale - 0.5) < 0.1
        and math.abs(Main.Position.Y.Scale - 0.5) < 0.1 then
        Main.Position =
            UDim2.new(
                0.5,
                -size.X * 0.5,
                0.5,
                -size.Y * 0.5
            )
    end
end

if Workspace.CurrentCamera then
    remember(
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(
            applyResponsiveSize
        )
    )
end

task.spawn(function()
    while State.Alive and Gui.Parent do
        if TeleportPage.Visible then
            pcall(refreshTeleportPreview)
        end

        task.wait(0.25)
    end
end)

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
    local startAbsolute

    remember(
        handle.InputBegan:Connect(function(input)
            if (
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            ) then
                dragging = true
                dragStart = input.Position
                startAbsolute = target.AbsolutePosition
                dragInput = input
            end
        end)
    )

    remember(
        handle.InputChanged:Connect(function(input)
            if (
                input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch
            ) then
                dragInput = input
            end
        end)
    )

    remember(
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input == dragInput and dragStart and startAbsolute then
                local delta = input.Position - dragStart

                local viewport =
                    Workspace.CurrentCamera
                    and Workspace.CurrentCamera.ViewportSize
                    or Vector2.new(360, 640)

                local size = target.AbsoluteSize

                local x =
                    math.clamp(
                        startAbsolute.X + delta.X,
                        4,
                        math.max(4, viewport.X - size.X - 4)
                    )

                local y =
                    math.clamp(
                        startAbsolute.Y + delta.Y,
                        4,
                        math.max(4, viewport.Y - size.Y - 4)
                    )

                target.Position =
                    UDim2.fromOffset(
                        x,
                        y
                    )
            end
        end)
    )

    remember(
        UserInputService.InputEnded:Connect(function(input)
            if (
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            ) then
                dragging = false
                dragInput = nil
                dragStart = nil
                startAbsolute = nil
            end
        end)
    )
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

    stopMovement()
    pcall(askTreadmillDoff)
    clearESP()
    restoreNoclip()
    restoreWalkSpeed()

    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
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

rebuildDestinationButtons()
repaintModes()
showPage("HOME")

pcall(refreshDiagnostics)

local startupPlot = findOwnPlot()
local startupTreadmill = findOwnTreadmillTarget()

setStatus(
    "Pronto • "
    .. tostring(#Waypoints)
    .. " destinos"
    .. (startupPlot and " • plot OK" or " • plot ?")
    .. (startupTreadmill and " • esteira OK" or " • esteira ?")
)

--==============================================================--
-- END
--==============================================================--
