--==============================================================--
-- CAFEÍNA • OUROBOROS WAYPOINT TELEPORT
-- Mobile / Android • executor-friendly
--
-- Inspirado na arquitetura de movimento reconstruída:
--   Waypoint Teleport
--   Teleport to Waypoint
--   travelTo
--   travelAlong
--   rawTeleport
--   returnToBase
--   getZoneIndex / getZoneModel
--   getEntryPosition / clampToCorridor
--
-- Este menu é apenas de locomoção.
-- Não coleta dados, não usa scanner e não dispara remotes de roubo.
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

--==============================================================--
-- GUI PARENT
--==============================================================--

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

local ROOT = guiParent()

for _, child in ipairs(ROOT:GetChildren()) do
    if child.Name == "CafeinaOuroborosWaypoint" then
        child:Destroy()
    end
end

--==============================================================--
-- MOVEMENT
--==============================================================--

local Movement = {}

Movement.Config = {
    StepDistance = 7,
    StepDelay = 0.025,
    GroundOffset = 3.2,
    ObstacleLift = 5,

    ZoneContainerNames = {
        "StealZones",
        "Zones",
        "Areas",
        "Worlds",
        "Biomes",
        "Regions",
        "MapZones",
    },

    EntryNames = {
        "Entry",
        "Entrance",
        "EntryPart",
        "EntrancePart",
        "Gate",
        "Portal",
        "Spawn",
        "Start",
    },

    CenterNames = {
        "Center",
        "CenterPart",
        "Origin",
        "Anchor",
        "ZoneAnchor",
        "Spawn",
    },

    PlotKeywords = {
        "plot",
        "base",
        "homestead",
        "home",
    },
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
            if ok then
                return cf.Position
            end
        end
    end

    return nil
end

local function getPivotPosition(obj)
    if not obj then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj.Position
    end

    if obj:IsA("Model") then
        local ok, cf = pcall(obj.GetPivot, obj)
        if ok and cf then
            return cf.Position
        end
    end

    local part = obj:FindFirstChildWhichIsA("BasePart", true)

    return part and part.Position or nil
end

local function makeRayParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    if LP.Character then
        params.FilterDescendantsInstances = {LP.Character}
    else
        params.FilterDescendantsInstances = {}
    end

    return params
end

function Movement.getRoot()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function Movement.getHumanoid()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function groundAdjusted(position)
    local result = Workspace:Raycast(
        position + Vector3.new(0, 25, 0),
        Vector3.new(0, -80, 0),
        makeRayParams()
    )

    if result then
        return Vector3.new(
            position.X,
            result.Position.Y + Movement.Config.GroundOffset,
            position.Z
        )
    end

    return position
end

local function obstacleAhead(fromPosition, targetPosition)
    local delta = targetPosition - fromPosition

    if delta.Magnitude < 0.05 then
        return nil
    end

    return Workspace:Raycast(
        fromPosition + Vector3.new(0, 2, 0),
        delta.Unit * math.min(delta.Magnitude, 6),
        makeRayParams()
    )
end

local function safeStep(fromPosition, targetPosition)
    local target = groundAdjusted(targetPosition)
    local obstacle = obstacleAhead(fromPosition, target)

    if obstacle then
        target = Vector3.new(
            target.X,
            math.max(target.Y, obstacle.Position.Y + Movement.Config.ObstacleLift),
            target.Z
        )
    end

    return target
end

local function findPartByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local part = root:FindFirstChild(name, true)

        if part and part:IsA("BasePart") then
            return part
        end
    end

    return nil
end

function Movement.getZoneContainers()
    local result = {}

    for _, name in ipairs(Movement.Config.ZoneContainerNames) do
        local obj = Workspace:FindFirstChild(name)

        if obj then
            table.insert(result, obj)
        end
    end

    return result
end

function Movement.getZones()
    local zones = {}
    local seen = {}

    for _, container in ipairs(Movement.getZoneContainers()) do
        for _, child in ipairs(container:GetChildren()) do
            if not seen[child] then
                if (
                    child:IsA("Model")
                    or child:IsA("Folder")
                    or child:IsA("BasePart")
                ) then
                    seen[child] = true
                    table.insert(zones, child)
                end
            end
        end
    end

    return zones
end

function Movement.getZoneIndex(position)
    position = toPosition(position)

    if not position then
        local root = Movement.getRoot()
        position = root and root.Position
    end

    if not position then
        return nil
    end

    local zones = Movement.getZones()
    local bestIndex
    local bestDistance = math.huge

    for i, zone in ipairs(zones) do
        local center =
            findPartByNames(zone, Movement.Config.CenterNames)

        local p =
            center and center.Position
            or getPivotPosition(zone)

        if p then
            local flatP = Vector3.new(p.X, position.Y, p.Z)
            local distance = (flatP - position).Magnitude

            if distance < bestDistance then
                bestDistance = distance
                bestIndex = i
            end
        end
    end

    return bestIndex
end

function Movement.getZoneModel(index)
    if not index then
        return nil
    end

    return Movement.getZones()[index]
end

function Movement.getCorridorBounds(zoneA, zoneB)
    if typeof(zoneA) == "number" then
        zoneA = Movement.getZoneModel(zoneA)
    end

    if typeof(zoneB) == "number" then
        zoneB = Movement.getZoneModel(zoneB)
    end

    if not zoneA or not zoneB then
        return nil
    end

    local a =
        findPartByNames(zoneA, Movement.Config.EntryNames)
        or findPartByNames(zoneA, Movement.Config.CenterNames)

    local b =
        findPartByNames(zoneB, Movement.Config.EntryNames)
        or findPartByNames(zoneB, Movement.Config.CenterNames)

    local pa = a and a.Position or getPivotPosition(zoneA)
    local pb = b and b.Position or getPivotPosition(zoneB)

    if not pa or not pb then
        return nil
    end

    local padding = 8

    return {
        minX = math.min(pa.X, pb.X) - padding,
        maxX = math.max(pa.X, pb.X) + padding,
        minZ = math.min(pa.Z, pb.Z) - padding,
        maxZ = math.max(pa.Z, pb.Z) + padding,
    }
end

function Movement.getEntryPosition(zoneA, zoneB)
    if typeof(zoneA) == "number" then
        zoneA = Movement.getZoneModel(zoneA)
    end

    if typeof(zoneB) == "number" then
        zoneB = Movement.getZoneModel(zoneB)
    end

    if not zoneB then
        return nil
    end

    local entry =
        findPartByNames(zoneB, Movement.Config.EntryNames)
        or findPartByNames(zoneB, Movement.Config.CenterNames)

    if entry then
        return groundAdjusted(entry.Position)
    end

    local pos = getPivotPosition(zoneB)

    return pos and groundAdjusted(pos) or nil
end

function Movement.clampToCorridor(position, bounds)
    if not position or not bounds then
        return position
    end

    return Vector3.new(
        math.clamp(position.X, bounds.minX, bounds.maxX),
        position.Y,
        math.clamp(position.Z, bounds.minZ, bounds.maxZ)
    )
end

function Movement.rawTeleport(target)
    local root = Movement.getRoot()
    local position = toPosition(target)

    if not root or not position then
        return false, "Destino inválido"
    end

    root.CFrame = CFrame.new(position)
    return true
end

function Movement.travelAlong(target)
    local root = Movement.getRoot()
    local destination = toPosition(target)

    if not root then
        return false, "Personagem não encontrado"
    end

    if not destination then
        return false, "Destino inválido"
    end

    local start = root.Position
    local distance = (destination - start).Magnitude

    if distance < 0.1 then
        return true
    end

    local steps = math.max(
        1,
        math.ceil(distance / Movement.Config.StepDistance)
    )

    for i = 1, steps do
        if not root.Parent then
            return false, "Personagem mudou"
        end

        local alpha = i / steps
        local desired = start:Lerp(destination, alpha)
        local target = safeStep(root.Position, desired)

        local look = root.CFrame.LookVector

        root.CFrame = CFrame.new(
            target,
            target + look
        )

        task.wait(Movement.Config.StepDelay)
    end

    return true
end

function Movement.travelTo(target)
    local root = Movement.getRoot()
    local destination = toPosition(target)

    if not root or not destination then
        return false, "Destino inválido"
    end

    local currentZone = Movement.getZoneIndex(root.Position)
    local targetZone = Movement.getZoneIndex(destination)

    if (
        not currentZone
        or not targetZone
        or currentZone == targetZone
    ) then
        return Movement.travelAlong(destination)
    end

    local zoneA = Movement.getZoneModel(currentZone)
    local zoneB = Movement.getZoneModel(targetZone)

    local entry = Movement.getEntryPosition(zoneA, zoneB)
    local bounds = Movement.getCorridorBounds(zoneA, zoneB)

    if entry then
        if bounds then
            entry = Movement.clampToCorridor(entry, bounds)
        end

        local ok = Movement.travelAlong(entry)

        if not ok then
            return false, "Falha na entrada da área"
        end
    end

    return Movement.travelAlong(destination)
end

--==============================================================--
-- WAYPOINT RESOLUTION
--==============================================================--

local Waypoints = {}
local SelectedIndex = 1
local TeleportMode = "CONTROLADO"

local function ownerMatches(obj)
    local current = obj

    for _ = 1, 5 do
        if not current then
            break
        end

        for _, attr in ipairs({
            "OwnerUserId",
            "OwnerId",
            "UserId",
            "PlayerUserId",
        }) do
            local value = current:GetAttribute(attr)

            if tonumber(value) == LP.UserId then
                return true
            end
        end

        for _, childName in ipairs({"Owner", "Player"}) do
            local value = current:FindFirstChild(childName)

            if value then
                if value:IsA("ObjectValue") and value.Value == LP then
                    return true
                end

                if value:IsA("StringValue") and value.Value == LP.Name then
                    return true
                end

                if (
                    (value:IsA("IntValue") or value:IsA("NumberValue"))
                    and tonumber(value.Value) == LP.UserId
                ) then
                    return true
                end
            end
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

local function findOwnPlot()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local n = lower(obj.Name)

            if (
                string.find(n, "plot", 1, true)
                or string.find(n, "base", 1, true)
                or string.find(n, "homestead", 1, true)
            ) and ownerMatches(obj) then
                return obj
            end
        end
    end

    return nil
end

local function resolvePlotTarget()
    local plot = findOwnPlot()

    if not plot then
        return nil
    end

    return
        findPartByNames(
            plot,
            {
                "Spawn",
                "SpawnPart",
                "Entry",
                "Entrance",
                "Center",
                "Anchor",
            }
        )
        or plot
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

local function addWaypoint(name, resolver, kind)
    table.insert(Waypoints, {
        name = name,
        resolver = resolver,
        kind = kind or "WAYPOINT",
    })
end

local function rebuildWaypoints()
    table.clear(Waypoints)

    -- Waypoints utilitários que aparecem na arquitetura do hub.
    addWaypoint(
        "MINHA BASE / PLOT",
        resolvePlotTarget,
        "BASE"
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
                "Fuse Machine",
                "FuseMachine",
                "Fusery",
                "Fuse",
            })
        end,
        "MACHINE"
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

    -- Nomes de biomas visíveis no código público.
    local commonBiomes = {
        "Desert",
        "Prehistoric",
        "Abyss Ocean",
    }

    local seen = {}

    for _, name in ipairs(commonBiomes) do
        local obj = Workspace:FindFirstChild(name, true)

        if obj then
            seen[obj] = true
            addWaypoint(
                string.upper(name),
                function()
                    return obj
                end,
                "BIOME"
            )
        end
    end

    -- Waypoints/zonas descobertos em StealZones/Zones/Areas/Biomes.
    for _, zone in ipairs(Movement.getZones()) do
        if not seen[zone] then
            seen[zone] = true

            addWaypoint(
                string.upper(zone.Name),
                function()
                    return zone
                end,
                "ZONE"
            )
        end
    end

    -- Objetos literalmente chamados Waypoint.
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (
            obj:IsA("BasePart")
            or obj:IsA("Model")
        ) then
            local n = lower(obj.Name)

            if string.find(n, "waypoint", 1, true) and not seen[obj] then
                seen[obj] = true

                addWaypoint(
                    "WAYPOINT • " .. obj.Name,
                    function()
                        return obj
                    end,
                    "WAYPOINT"
                )
            end
        end
    end

    table.sort(Waypoints, function(a, b)
        local rank = {
            BASE = 1,
            MACHINE = 2,
            AREA = 3,
            BIOME = 4,
            ZONE = 5,
            WAYPOINT = 6,
        }

        local ra = rank[a.kind] or 99
        local rb = rank[b.kind] or 99

        if ra == rb then
            return a.name < b.name
        end

        return ra < rb
    end)

    if SelectedIndex > #Waypoints then
        SelectedIndex = 1
    end
end

local function resolveSelected()
    local item = Waypoints[SelectedIndex]

    if not item then
        return nil, "Nenhum waypoint"
    end

    local ok, result = pcall(item.resolver)

    if not ok then
        return nil, result
    end

    if not result then
        return nil, "Waypoint indisponível agora"
    end

    return result, nil
end

local function teleportSelected()
    local target, err = resolveSelected()

    if not target then
        return false, err
    end

    if TeleportMode == "DIRETO" then
        return Movement.rawTeleport(target)
    end

    return Movement.travelTo(target)
end

function Movement.returnToBase()
    local target = resolvePlotTarget()

    if not target then
        return false, "Base não encontrada"
    end

    return Movement.travelTo(target)
end

--==============================================================--
-- UI
--==============================================================--

rebuildWaypoints()

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaOuroborosWaypoint"
Gui.ResetOnSpawn = false
Gui.Parent = ROOT

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(318, 432)
Main.Position = UDim2.new(0.5, -159, 0.5, -216)
Main.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
Main.BorderSizePixel = 0
Main.Parent = Gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 12)
mc.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -95, 1, 0)
Title.Position = UDim2.fromOffset(14, 0)
Title.BackgroundTransparency = 1
Title.Text = "CAFEÍNA • TELEPORT"
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.Parent = Header

local function headerButton(text, offset)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(36, 34)
    b.Position = UDim2.new(1, offset, 0, 8)
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 35)
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

local Minimize = headerButton("—", -80)
local Close = headerButton("×", -40)

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -28, 0, 22)
Subtitle.Position = UDim2.fromOffset(14, 48)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "WAYPOINT TELEPORT • MOBILE"
Subtitle.TextColor3 = Color3.fromRGB(150, 150, 155)
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 10
Subtitle.Parent = Main

local SelectedBox = Instance.new("Frame")
SelectedBox.Size = UDim2.new(1, -28, 0, 58)
SelectedBox.Position = UDim2.fromOffset(14, 78)
SelectedBox.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
SelectedBox.Parent = Main

local sbc = Instance.new("UICorner")
sbc.CornerRadius = UDim.new(0, 9)
sbc.Parent = SelectedBox

local SelectedLabel = Instance.new("TextLabel")
SelectedLabel.Size = UDim2.new(1, -16, 0, 24)
SelectedLabel.Position = UDim2.fromOffset(8, 5)
SelectedLabel.BackgroundTransparency = 1
SelectedLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
SelectedLabel.Font = Enum.Font.GothamBold
SelectedLabel.TextSize = 12
SelectedLabel.Parent = SelectedBox

local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(1, -16, 0, 18)
ModeLabel.Position = UDim2.fromOffset(8, 32)
ModeLabel.BackgroundTransparency = 1
ModeLabel.TextColor3 = Color3.fromRGB(170, 170, 175)
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Font = Enum.Font.Gotham
ModeLabel.TextSize = 10
ModeLabel.Parent = SelectedBox

local Buttons = Instance.new("Frame")
Buttons.Size = UDim2.new(1, -28, 0, 92)
Buttons.Position = UDim2.fromOffset(14, 145)
Buttons.BackgroundTransparency = 1
Buttons.Parent = Main

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -4, 0, 42)
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.Parent = Buttons

local function action(parent, text, callback)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(31, 31, 36)
    b.TextColor3 = Color3.fromRGB(245, 245, 245)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 11
    b.Text = text
    b.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b

    b.Activated:Connect(function()
        local ok, err = pcall(callback)

        if not ok then
            warn("[CAFEINA TELEPORT]", err)
        end
    end)

    return b
end

local StatusText = "Pronto"

local function setStatus(text)
    StatusText = tostring(text)
end

local function updateSelectedDisplay()
    local item = Waypoints[SelectedIndex]

    SelectedLabel.Text =
        item
        and ("DESTINO: " .. item.name)
        or "DESTINO: NENHUM"

    ModeLabel.Text =
        "MODO: "
        .. TeleportMode
        .. " • "
        .. tostring(#Waypoints)
        .. " waypoint(s)"
end

action(Buttons, "◀ ANTERIOR", function()
    if #Waypoints == 0 then
        return
    end

    SelectedIndex -= 1

    if SelectedIndex < 1 then
        SelectedIndex = #Waypoints
    end

    updateSelectedDisplay()
end)

action(Buttons, "PRÓXIMO ▶", function()
    if #Waypoints == 0 then
        return
    end

    SelectedIndex += 1

    if SelectedIndex > #Waypoints then
        SelectedIndex = 1
    end

    updateSelectedDisplay()
end)

action(Buttons, "TELEPORTAR", function()
    setStatus("Indo para waypoint...")

    task.spawn(function()
        local ok, err = teleportSelected()

        if ok then
            setStatus("Waypoint alcançado")
        else
            setStatus(err or "Falha no teleporte")
        end
    end)
end)

local ModeButton
ModeButton = action(Buttons, "MODO: CONTROLADO", function()
    if TeleportMode == "CONTROLADO" then
        TeleportMode = "DIRETO"
    else
        TeleportMode = "CONTROLADO"
    end

    ModeButton.Text = "MODO: " .. TeleportMode
    updateSelectedDisplay()
end)

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -28, 0, 130)
List.Position = UDim2.fromOffset(14, 247)
List.BackgroundColor3 = Color3.fromRGB(20, 20, 23)
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.CanvasSize = UDim2.new()
List.Parent = Main

local lc = Instance.new("UICorner")
lc.CornerRadius = UDim.new(0, 9)
lc.Parent = List

local ll = Instance.new("UIListLayout")
ll.Padding = UDim.new(0, 5)
ll.Parent = List

local lp = Instance.new("UIPadding")
lp.PaddingTop = UDim.new(0, 6)
lp.PaddingBottom = UDim.new(0, 6)
lp.PaddingLeft = UDim.new(0, 6)
lp.PaddingRight = UDim.new(0, 6)
lp.Parent = List

local function renderList()
    for _, child in ipairs(List:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    for index, item in ipairs(Waypoints) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -2, 0, 34)
        b.BackgroundColor3 =
            index == SelectedIndex
            and Color3.fromRGB(52, 52, 61)
            or Color3.fromRGB(29, 29, 34)
        b.TextColor3 = Color3.fromRGB(240, 240, 240)
        b.Font = Enum.Font.Gotham
        b.TextSize = 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = "   " .. item.name
        b.Parent = List

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 7)
        c.Parent = b

        b.Activated:Connect(function()
            SelectedIndex = index
            updateSelectedDisplay()
            renderList()
        end)
    end
end

local FooterButtons = Instance.new("Frame")
FooterButtons.Size = UDim2.new(1, -28, 0, 38)
FooterButtons.Position = UDim2.fromOffset(14, 383)
FooterButtons.BackgroundTransparency = 1
FooterButtons.Parent = Main

local fg = Instance.new("UIGridLayout")
fg.CellSize = UDim2.new(0.5, -4, 1, 0)
fg.CellPadding = UDim2.fromOffset(8, 0)
fg.Parent = FooterButtons

action(FooterButtons, "ATUALIZAR", function()
    rebuildWaypoints()
    renderList()
    updateSelectedDisplay()
    setStatus("Waypoints atualizados")
end)

action(FooterButtons, "VOLTAR À BASE", function()
    setStatus("Voltando para base...")

    task.spawn(function()
        local ok, err = Movement.returnToBase()

        if ok then
            setStatus("Base alcançada")
        else
            setStatus(err or "Base indisponível")
        end
    end)
end)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -28, 0, 16)
Status.Position = UDim2.fromOffset(14, 414)
Status.BackgroundTransparency = 1
Status.TextColor3 = Color3.fromRGB(145, 145, 150)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Font = Enum.Font.Gotham
Status.TextSize = 9
Status.Parent = Main

--==============================================================--
-- MINIMIZED ICON
--==============================================================--

local Mini = Instance.new("TextButton")
Mini.Size = UDim2.fromOffset(52, 52)
Mini.Position = UDim2.new(0.5, -26, 0.5, -26)
Mini.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
Mini.TextColor3 = Color3.fromRGB(245, 245, 245)
Mini.Font = Enum.Font.GothamBold
Mini.TextSize = 17
Mini.Text = "TP"
Mini.Visible = false
Mini.Parent = Gui

local mic = Instance.new("UICorner")
mic.CornerRadius = UDim.new(1, 0)
mic.Parent = Mini

Minimize.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

Close.Activated:Connect(function()
    Gui:Destroy()
end)

--==============================================================--
-- MOBILE DRAG
--==============================================================--

local function draggable(handle, target)
    local dragging = false
    local startInput
    local startPosition
    local currentInput

    handle.InputBegan:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        ) then
            dragging = true
            startInput = input.Position
            startPosition = target.Position
            currentInput = input
        end
    end)

    handle.InputChanged:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement
        ) then
            currentInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == currentInput then
            local delta = input.Position - startInput

            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        ) then
            dragging = false
        end
    end)
end

draggable(Header, Main)
draggable(Mini, Mini)

--==============================================================--
-- STATUS / REFRESH
--==============================================================--

task.spawn(function()
    while Gui.Parent do
        Status.Text = StatusText
        task.wait(0.2)
    end
end)

updateSelectedDisplay()
renderList()
