--==============================================================
-- CAFEÍNA • SMART ITEMS V3 MOBILE
--
-- FOCO:
-- • Mobile
-- • Baixo consumo
-- • Somente itens utilizáveis/coletáveis
-- • ESP de itens
-- • Lista em tempo real
-- • Teleporte seguro
-- • Auto coleta
-- • Todas as funções começam DESLIGADAS
--
-- CLIENT-VISIBLE ONLY
--==============================================================


--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local Backpack = LocalPlayer:WaitForChild("Backpack")


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    VERSION = "SMART_ITEMS_V3_MOBILE",

    ----------------------------------------------------------
    -- PERFORMANCE
    ----------------------------------------------------------

    LIST_INTERVAL = 0.85,

    ESP_INTERVAL = 0.25,

    AUTO_INTERVAL = 0.55,

    -- scan completo apenas para recuperação
    RECOVERY_SCAN_INTERVAL = 25,

    ----------------------------------------------------------
    -- LIMITES
    ----------------------------------------------------------

    MAX_UI_ITEMS = 18,

    MAX_ACTIVE_ESP = 25,

    ESP_MAX_DISTANCE = 1200,

    MIN_SCORE = 75,

    ----------------------------------------------------------
    -- TELEPORT
    ----------------------------------------------------------

    TELEPORT_BASE_HEIGHT = 6,

    TELEPORT_FALLBACK_HEIGHT = 10,

    GROUND_SCAN_HEIGHT = 18,

    GROUND_SCAN_DISTANCE = 40,

    CLEARANCE_SIZE = Vector3.new(
        4.2,
        5.8,
        4.2
    ),

    ----------------------------------------------------------
    -- PICKUP
    ----------------------------------------------------------

    PICKUP_TIMEOUT = 1.4,

    AFTER_TELEPORT_DELAY = 0.12,

    ----------------------------------------------------------
    -- ITENS CONFIRMADOS / OBSERVADOS
    ----------------------------------------------------------

    CONFIRMED_ITEMS = {

        AK47 = true,
        Deagle = true,
        DoubleBarrel = true,
        M1911 = true,
        XSaw = true,

        Machete = true,
        MacheteU = true,

        Tablet = true,

        ["Weapon Parts"] = true,
    }
}


--==============================================================
-- STATE
--==============================================================

local State = {

    MenuOpen = false,

    ESP = false,

    AutoCollect = false,

    Busy = false,

    Destroyed = false,
}


--==============================================================
-- DATABASE
--==============================================================

local KnownItemNames = {}

local Items = {}

local Visuals = {}

local ButtonPool = {}

local Connections = {}


--==============================================================
-- UTIL
--==============================================================

local function lower(value)

    return string.lower(
        tostring(value or "")
    )
end


local function getCharacter()

    return LocalPlayer.Character
end


local function getMyRoot()

    local character = getCharacter()

    if not character then
        return nil
    end

    return character:FindFirstChild(
        "HumanoidRootPart"
    )
        or character.PrimaryPart
end


local function getPart(obj)

    if not obj
    or not obj.Parent then

        return nil
    end

    if obj:IsA("BasePart") then
        return obj
    end

    if obj:IsA("Tool") then

        local handle =
            obj:FindFirstChild("Handle")

        if handle
        and handle:IsA("BasePart") then

            return handle
        end
    end

    if obj:IsA("Model") then

        if obj.PrimaryPart then
            return obj.PrimaryPart
        end
    end

    return obj:FindFirstChildWhichIsA(
        "BasePart",
        true
    )
end


local function getDistance(obj)

    local root = getMyRoot()
    local part = getPart(obj)

    if not root
    or not part then

        return math.huge
    end

    return (
        root.Position -
        part.Position
    ).Magnitude
end


--==============================================================
-- GUI PARENT
--==============================================================

local function getGuiParent()

    if typeof(gethui) == "function" then

        local success, result =
            pcall(gethui)

        if success and result then
            return result
        end
    end

    local success =
        pcall(function()

            return CoreGui.Name
        end)

    if success then
        return CoreGui
    end

    return LocalPlayer:WaitForChild(
        "PlayerGui"
    )
end


local GUI_PARENT = getGuiParent()


--==============================================================
-- REMOVE OLD GUI
--==============================================================

local old =
    GUI_PARENT:FindFirstChild(
        "CafeinaSmartItemsV3"
    )

if old then
    old:Destroy()
end


--==============================================================
-- KNOWN ITEM DATABASE
--==============================================================

local function addKnownName(name)

    if type(name) ~= "string"
    or name == "" then

        return
    end

    KnownItemNames[name] = true
end


for name in pairs(
    CONFIG.CONFIRMED_ITEMS
) do

    addKnownName(name)
end


--==============================================================
-- DISCOVER GAME ITEM NAMES
--==============================================================

local function discoverItemInfo()

    local gameStuff =
        ReplicatedStorage:FindFirstChild(
            "GameStuff"
        )

    if not gameStuff then
        return
    end

    local itemInfo =
        gameStuff:FindFirstChild(
            "ItemInfo"
        )

    if not itemInfo then
        return
    end

    for _, child in ipairs(
        itemInfo:GetChildren()
    ) do

        addKnownName(
            child.Name
        )
    end
end


local function discoverSavedItems()

    local stats =
        LocalPlayer:FindFirstChild(
            "PlayerStats"
        )

    if not stats then
        return
    end

    local saved =
        stats:FindFirstChild(
            "SavedItems"
        )

    if not saved then
        return
    end

    for _, child in ipairs(
        saved:GetChildren()
    ) do

        addKnownName(
            child.Name
        )
    end
end


local function discoverBackpack()

    for _, child in ipairs(
        Backpack:GetChildren()
    ) do

        if child:IsA("Tool") then

            addKnownName(
                child.Name
            )
        end
    end

    local character = getCharacter()

    if character then

        for _, child in ipairs(
            character:GetChildren()
        ) do

            if child:IsA("Tool") then

                addKnownName(
                    child.Name
                )
            end
        end
    end
end


local function refreshKnownDatabase()

    discoverItemInfo()

    discoverSavedItems()

    discoverBackpack()
end


--==============================================================
-- FILTERS
--==============================================================

local BLOCKED_NAMES = {

    Part = true,
    MeshPart = true,
    UnionOperation = true,

    Handle = true,

    HumanoidRootPart = true,
    Head = true,

    Torso = true,
    UpperTorso = true,
    LowerTorso = true,

    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,

    LeftUpperArm = true,
    RightUpperArm = true,

    LeftLowerArm = true,
    RightLowerArm = true,

    LeftUpperLeg = true,
    RightUpperLeg = true,

    Attachment = true,
    Weld = true,
    Motor6D = true,
}


local BAD_KEYWORDS = {

    "humanoid",
    "accessory",

    "particle",
    "effect",

    "animation",
    "keyframe",
    "pose",

    "hitbox",
    "collider",

    "camera",

    "terrain",

    "foliage",
    "tree",
    "grass",

    "blood",

    "spawnlocation",

    "locationnotifier",
}


local GOOD_KEYWORDS = {

    "weapon",
    "gun",

    "rifle",
    "pistol",
    "shotgun",

    "ammo",
    "ammunition",

    "magazine",

    "medkit",
    "bandage",

    "food",
    "drink",
    "water",

    "fuel",

    "tablet",

    "machete",
    "knife",

    "saw",

    "loot",

    "pickup",

    "weapon part",
}


local GOOD_PARENT_KEYWORDS = {

    "items",
    "item",

    "loot",

    "pickup",

    "drops",
    "drop",

    "weapons",

    "worlditems",

    "spawneditems",
}


local function containsAny(
    text,
    words
)

    text = lower(text)

    for _, word in ipairs(words) do

        if string.find(
            text,
            word,
            1,
            true
        ) then

            return true
        end
    end

    return false
end


--==============================================================
-- CHARACTER / NPC FILTER
--==============================================================

local function belongsToCharacter(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if current:IsA("Model") then

            if Players:GetPlayerFromCharacter(
                current
            ) then

                return true
            end

            if current:FindFirstChildOfClass(
                "Humanoid"
            ) then

                return true
            end
        end

        current = current.Parent
    end

    return false
end


local function belongsToAccessory(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if current:IsA("Accessory") then
            return true
        end

        current = current.Parent
    end

    return false
end


--==============================================================
-- INTERACTIONS
--==============================================================

local function getPrompt(obj)

    if not obj then
        return nil
    end

    return obj:FindFirstChildWhichIsA(
        "ProximityPrompt",
        true
    )
end


local function getClickDetector(obj)

    if not obj then
        return nil
    end

    return obj:FindFirstChildWhichIsA(
        "ClickDetector",
        true
    )
end


local function getTouchTransmitter(obj)

    if not obj then
        return nil
    end

    return obj:FindFirstChildWhichIsA(
        "TouchTransmitter",
        true
    )
end


--==============================================================
-- ROOT RESOLUTION
--==============================================================

local function findToolAncestor(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if current:IsA("Tool") then
            return current
        end

        current = current.Parent
    end

    return nil
end


local function findKnownAncestor(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if KnownItemNames[
            current.Name
        ] then

            return current
        end

        current = current.Parent
    end

    return nil
end


local function findInteractionRoot(obj)

    local current = obj

    local depth = 0

    while current
    and current ~= Workspace
    and depth < 5 do

        if current:IsA("Tool") then
            return current
        end

        if current:IsA("Model") then

            if getPrompt(current)
            or getClickDetector(current)
            or getTouchTransmitter(current) then

                return current
            end
        end

        current = current.Parent

        depth += 1
    end

    return nil
end


local function resolveItemRoot(obj)

    if not obj
    or not obj.Parent
    or not obj:IsDescendantOf(Workspace) then

        return nil
    end

    if belongsToCharacter(obj)
    or belongsToAccessory(obj) then

        return nil
    end

    local tool =
        findToolAncestor(obj)

    if tool then
        return tool
    end

    local known =
        findKnownAncestor(obj)

    if known then
        return known
    end

    return findInteractionRoot(obj)
end


--==============================================================
-- SCORE TAGS
--==============================================================

local function scoreTags(obj)

    local score = 0

    local success, tags =
        pcall(function()

            return CollectionService:GetTags(
                obj
            )
        end)

    if not success then
        return 0
    end

    for _, tag in ipairs(tags) do

        if containsAny(
            tag,
            GOOD_KEYWORDS
        ) then

            score += 30
        end
    end

    return score
end


local function scoreParents(obj)

    local score = 0

    local current =
        obj.Parent

    local depth = 0

    while current
    and current ~= Workspace
    and depth < 4 do

        if containsAny(
            current.Name,
            GOOD_PARENT_KEYWORDS
        ) then

            score += 15
        end

        current = current.Parent

        depth += 1
    end

    return score
end


--==============================================================
-- CLASSIFIER
--==============================================================

local function classifyItem(obj)

    local root =
        resolveItemRoot(obj)

    if not root
    or not root.Parent then

        return false
    end

    if BLOCKED_NAMES[
        root.Name
    ] then

        return false
    end

    if containsAny(
        root.Name,
        BAD_KEYWORDS
    ) then

        return false
    end

    local part =
        getPart(root)

    if not part then
        return false
    end

    local score = 0

    ----------------------------------------------------------
    -- Tool físico
    ----------------------------------------------------------

    if root:IsA("Tool") then
        score += 120
    end

    ----------------------------------------------------------
    -- Nome encontrado na própria estrutura de itens do jogo
    ----------------------------------------------------------

    if KnownItemNames[
        root.Name
    ] then

        score += 90
    end

    ----------------------------------------------------------
    -- Observações já confirmadas
    ----------------------------------------------------------

    if CONFIG.CONFIRMED_ITEMS[
        root.Name
    ] then

        score += 40
    end

    ----------------------------------------------------------
    -- Interação
    ----------------------------------------------------------

    if getPrompt(root) then
        score += 45
    end

    if getClickDetector(root) then
        score += 35
    end

    if getTouchTransmitter(root) then
        score += 25
    end

    ----------------------------------------------------------
    -- Nome
    ----------------------------------------------------------

    if containsAny(
        root.Name,
        GOOD_KEYWORDS
    ) then

        score += 30
    end

    ----------------------------------------------------------
    -- Tags
    ----------------------------------------------------------

    score += scoreTags(root)

    ----------------------------------------------------------
    -- Estrutura pai
    ----------------------------------------------------------

    score += scoreParents(root)

    ----------------------------------------------------------
    -- Evita modelos gigantes de mapa
    ----------------------------------------------------------

    if root:IsA("Model") then

        local partCount = 0

        for _, descendant in ipairs(
            root:GetDescendants()
        ) do

            if descendant:IsA("BasePart") then

                partCount += 1

                if partCount > 50 then
                    break
                end
            end
        end

        if partCount > 50 then
            score -= 80

        elseif partCount > 25 then
            score -= 35
        end
    end

    if score >= CONFIG.MIN_SCORE then

        return true,
            root,
            score
    end

    return false
end


--==============================================================
-- ITEM REGISTRY
--==============================================================

local function registerCandidate(obj)

    local valid,
        root,
        score =
        classifyItem(obj)

    if not valid
    or not root then

        return
    end

    local existing =
        Items[root]

    if existing then

        existing.Score =
            math.max(
                existing.Score,
                score
            )

        return
    end

    Items[root] = {

        Name = root.Name,

        Object = root,

        Score = score,
    }
end


local function removeItem(obj)

    if not obj then
        return
    end

    Items[obj] = nil

    local visual =
        Visuals[obj]

    if visual then

        if visual.Highlight then
            visual.Highlight:Destroy()
        end

        if visual.Billboard then
            visual.Billboard:Destroy()
        end

        Visuals[obj] = nil
    end
end


--==============================================================
-- INITIAL / RECOVERY SCAN
--==============================================================

local function scanWorld()

    refreshKnownDatabase()

    local descendants =
        Workspace:GetDescendants()

    local seenRoots = {}

    for _, obj in ipairs(descendants) do

        local interesting =
            obj:IsA("Tool")
            or obj:IsA("Model")
            or obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")
            or KnownItemNames[obj.Name]

        if interesting then

            local valid,
                root,
                score =
                classifyItem(obj)

            if valid and root then

                seenRoots[root] = true

                if not Items[root] then

                    Items[root] = {

                        Name = root.Name,

                        Object = root,

                        Score = score,
                    }

                else

                    Items[root].Score =
                        math.max(
                            Items[root].Score,
                            score
                        )
                end
            end
        end
    end

    local stale = {}

    for obj in pairs(Items) do

        if not obj.Parent
        or not obj:IsDescendantOf(Workspace)
        or not seenRoots[obj] then

            table.insert(
                stale,
                obj
            )
        end
    end

    for _, obj in ipairs(stale) do
        removeItem(obj)
    end
end


--==============================================================
-- SAFE TELEPORT
--==============================================================

local function makeIgnoreList(
    character,
    item
)

    local list = {}

    if character then
        table.insert(
            list,
            character
        )
    end

    if item then
        table.insert(
            list,
            item
        )
    end

    return list
end


local function positionIsFree(
    position,
    character,
    item
)

    local overlap =
        OverlapParams.new()

    overlap.FilterType =
        Enum.RaycastFilterType.Exclude

    overlap.FilterDescendantsInstances =
        makeIgnoreList(
            character,
            item
        )

    local parts =
        Workspace:GetPartBoundsInBox(
            CFrame.new(position),
            CONFIG.CLEARANCE_SIZE,
            overlap
        )

    for _, part in ipairs(parts) do

        if part.CanCollide
        and part.Transparency < 1 then

            return false
        end
    end

    return true
end


--==============================================================
-- WALL / BODY CLEARANCE
--==============================================================

local function hasSideClearance(
    position,
    character,
    item
)

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances =
        makeIgnoreList(
            character,
            item
        )

    local directions = {

        Vector3.new(2.2, 0, 0),

        Vector3.new(-2.2, 0, 0),

        Vector3.new(0, 0, 2.2),

        Vector3.new(0, 0, -2.2),

        Vector3.new(0, 3, 0),
    }

    for _, direction in ipairs(
        directions
    ) do

        local hit =
            Workspace:Raycast(
                position,
                direction,
                params
            )

        if hit
        and hit.Instance
        and hit.Instance.CanCollide then

            return false
        end
    end

    return true
end


--==============================================================
-- FIND GROUND
--==============================================================

local function findGroundPosition(
    testPosition,
    character,
    item
)

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances =
        makeIgnoreList(
            character,
            item
        )

    local start =
        testPosition
        +
        Vector3.new(
            0,
            CONFIG.GROUND_SCAN_HEIGHT,
            0
        )

    local direction =
        Vector3.new(
            0,
            -CONFIG.GROUND_SCAN_DISTANCE,
            0
        )

    local result =
        Workspace:Raycast(
            start,
            direction,
            params
        )

    if not result then
        return nil
    end

    if not result.Instance
    or not result.Instance.CanCollide then

        return nil
    end

    return result.Position
        +
        Vector3.new(
            0,
            3.2,
            0
        )
end


--==============================================================
-- SAFE POSITION SEARCH
--==============================================================

local function findSafeTeleportPosition(
    item
)

    local character =
        getCharacter()

    local itemPart =
        getPart(item)

    if not character
    or not itemPart then

        return nil
    end

    ----------------------------------------------------------
    -- Primeiro testa acima.
    -- Depois testa ao redor.
    ----------------------------------------------------------

    local offsets = {

        Vector3.new(0, 6, 0),

        Vector3.new(0, 8, 0),

        Vector3.new(4, 6, 0),

        Vector3.new(-4, 6, 0),

        Vector3.new(0, 6, 4),

        Vector3.new(0, 6, -4),

        Vector3.new(5, 7, 5),

        Vector3.new(-5, 7, 5),

        Vector3.new(5, 7, -5),

        Vector3.new(-5, 7, -5),

        Vector3.new(7, 7, 0),

        Vector3.new(-7, 7, 0),

        Vector3.new(0, 7, 7),

        Vector3.new(0, 7, -7),
    }

    for _, offset in ipairs(
        offsets
    ) do

        local candidate =
            itemPart.Position
            +
            offset

        local grounded =
            findGroundPosition(
                candidate,
                character,
                item
            )

        if grounded then

            if positionIsFree(
                grounded,
                character,
                item
            )
            and hasSideClearance(
                grounded,
                character,
                item
            ) then

                return CFrame.new(
                    grounded
                )
            end
        end
    end

    ----------------------------------------------------------
    -- Fallback mais alto.
    --
    -- Melhor ficar acima do objeto do que nascer
    -- atravessando uma parede.
    ----------------------------------------------------------

    local fallback =
        itemPart.Position
        +
        Vector3.new(
            0,
            CONFIG.TELEPORT_FALLBACK_HEIGHT,
            0
        )

    if positionIsFree(
        fallback,
        character,
        item
    ) then

        return CFrame.new(
            fallback
        )
    end

    return nil
end


local function teleportToItem(obj)

    if not obj
    or not obj.Parent then

        return false
    end

    local character =
        getCharacter()

    if not character then
        return false
    end

    local destination =
        findSafeTeleportPosition(
            obj
        )

    if not destination then
        return false
    end

    local success =
        pcall(function()

            character:PivotTo(
                destination
            )
        end)

    return success
end


--==============================================================
-- PICKUP
--==============================================================

local function tryPickup(obj)

    if not obj
    or not obj.Parent then

        return false
    end

    local prompt =
        getPrompt(obj)

    if prompt
    and typeof(fireproximityprompt)
        == "function" then

        local success =
            pcall(function()

                fireproximityprompt(
                    prompt
                )
            end)

        if success then
            return true
        end
    end

    local click =
        getClickDetector(obj)

    if click
    and typeof(fireclickdetector)
        == "function" then

        local success =
            pcall(function()

                fireclickdetector(
                    click
                )
            end)

        if success then
            return true
        end
    end

    ----------------------------------------------------------
    -- Para objetos coletados por contato.
    ----------------------------------------------------------

    local part =
        getPart(obj)

    local root =
        getMyRoot()

    if part
    and root
    and typeof(firetouchinterest)
        == "function" then

        pcall(function()

            firetouchinterest(
                root,
                part,
                0
            )

            task.wait(0.03)

            firetouchinterest(
                root,
                part,
                1
            )
        end)

        return true
    end

    return false
end


--==============================================================
-- WAIT ITEM CHANGE
--==============================================================

local function waitPickup(
    obj,
    originalParent
)

    local start = os.clock()

    while
        os.clock() - start
        <
        CONFIG.PICKUP_TIMEOUT
    do

        if not State.AutoCollect then
            break
        end

        if not obj
        or not obj.Parent then

            return true
        end

        if obj.Parent ~= originalParent then

            if not obj:IsDescendantOf(
                Workspace
            ) then

                return true
            end
        end

        task.wait(0.1)
    end

    return false
end


--==============================================================
-- NEAREST ITEM
--==============================================================

local function getNearestItem()

    local root =
        getMyRoot()

    if not root then
        return nil
    end

    local nearest = nil

    local bestDistance =
        math.huge

    for obj in pairs(Items) do

        if obj
        and obj.Parent then

            local part =
                getPart(obj)

            if part then

                local distance =
                    (
                        root.Position
                        -
                        part.Position
                    ).Magnitude

                if distance
                <
                bestDistance then

                    bestDistance =
                        distance

                    nearest =
                        obj
                end
            end
        end
    end

    return nearest
end


local function collectItem(obj)

    if State.Busy
    or not State.AutoCollect then

        return
    end

    if not obj
    or not obj.Parent then

        return
    end

    State.Busy = true

    local originalParent =
        obj.Parent

    local teleported =
        teleportToItem(obj)

    if teleported then

        task.wait(
            CONFIG.AFTER_TELEPORT_DELAY
        )

        if State.AutoCollect then

            tryPickup(obj)

            waitPickup(
                obj,
                originalParent
            )
        end
    end

    State.Busy = false
end


--==============================================================
-- GUI
--==============================================================

local GUI =
    Instance.new("ScreenGui")

GUI.Name =
    "CafeinaSmartItemsV3"

GUI.ResetOnSpawn = false

GUI.IgnoreGuiInset = false

GUI.DisplayOrder = 999999

GUI.Parent = GUI_PARENT


--==============================================================
-- FLOATING BUTTON
--==============================================================

local OpenButton =
    Instance.new("TextButton")

OpenButton.Name =
    "OpenButton"

OpenButton.Size =
    UDim2.fromOffset(
        106,
        34
    )

OpenButton.Position =
    UDim2.new(
        0,
        12,
        0.48,
        0
    )

OpenButton.BackgroundColor3 =
    Color3.fromRGB(
        21,
        21,
        25
    )

OpenButton.BorderSizePixel = 0

OpenButton.Text =
    "CAFEÍNA"

OpenButton.TextColor3 =
    Color3.fromRGB(
        245,
        245,
        245
    )

OpenButton.TextSize = 12

OpenButton.Font =
    Enum.Font.GothamBold

OpenButton.AutoButtonColor = true

OpenButton.Parent = GUI


local openCorner =
    Instance.new("UICorner")

openCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

openCorner.Parent =
    OpenButton


local openStroke =
    Instance.new("UIStroke")

openStroke.Transparency = 0.55

openStroke.Thickness = 1

openStroke.Parent =
    OpenButton


--==============================================================
-- PANEL
--==============================================================

local Panel =
    Instance.new("Frame")

Panel.Name = "Panel"

Panel.Position =
    UDim2.new(
        0,
        12,
        0.48,
        40
    )

Panel.Size =
    UDim2.fromOffset(
        182,
        0
    )

Panel.BackgroundColor3 =
    Color3.fromRGB(
        17,
        17,
        21
    )

Panel.BorderSizePixel = 0

Panel.ClipsDescendants = true

Panel.Visible = false

Panel.Parent = GUI


local panelCorner =
    Instance.new("UICorner")

panelCorner.CornerRadius =
    UDim.new(
        0,
        9
    )

panelCorner.Parent = Panel


local panelStroke =
    Instance.new("UIStroke")

panelStroke.Transparency = 0.65

panelStroke.Thickness = 1

panelStroke.Parent = Panel


--==============================================================
-- TITLE
--==============================================================

local Title =
    Instance.new("TextLabel")

Title.Position =
    UDim2.fromOffset(
        9,
        5
    )

Title.Size =
    UDim2.new(
        1,
        -18,
        0,
        22
    )

Title.BackgroundTransparency = 1

Title.Text =
    "ITENS • 0"

Title.TextColor3 =
    Color3.fromRGB(
        235,
        235,
        235
    )

Title.TextSize = 11

Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent = Panel


--==============================================================
-- TOGGLE CREATOR
--==============================================================

local function makeToggle(
    text,
    x
)

    local button =
        Instance.new("TextButton")

    button.Position =
        UDim2.new(
            x,
            x == 0 and 7 or 3,
            0,
            31
        )

    button.Size =
        UDim2.new(
            0.5,
            -10,
            0,
            29
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            29,
            29,
            34
        )

    button.BorderSizePixel = 0

    button.Text =
        text .. " OFF"

    button.TextColor3 =
        Color3.fromRGB(
            160,
            160,
            165
        )

    button.TextSize = 10

    button.Font =
        Enum.Font.GothamMedium

    button.Parent = Panel

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(
            0,
            6
        )

    corner.Parent = button

    return button
end


local ESPButton =
    makeToggle(
        "ESP",
        0
    )


local AutoButton =
    makeToggle(
        "AUTO",
        0.5
    )


--==============================================================
-- ITEM LIST
--==============================================================

local Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(
        7,
        66
    )

Scroll.Size =
    UDim2.new(
        1,
        -14,
        1,
        -73
    )

Scroll.BackgroundColor3 =
    Color3.fromRGB(
        22,
        22,
        27
    )

Scroll.BorderSizePixel = 0

Scroll.ScrollBarThickness = 2

Scroll.CanvasSize =
    UDim2.new()

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.None

Scroll.Parent = Panel


local scrollCorner =
    Instance.new("UICorner")

scrollCorner.CornerRadius =
    UDim.new(
        0,
        7
    )

scrollCorner.Parent = Scroll


local ListLayout =
    Instance.new("UIListLayout")

ListLayout.Padding =
    UDim.new(
        0,
        3
    )

ListLayout.SortOrder =
    Enum.SortOrder.LayoutOrder

ListLayout.Parent = Scroll


local Padding =
    Instance.new("UIPadding")

Padding.PaddingTop =
    UDim.new(
        0,
        4
    )

Padding.PaddingBottom =
    UDim.new(
        0,
        4
    )

Padding.PaddingLeft =
    UDim.new(
        0,
        4
    )

Padding.PaddingRight =
    UDim.new(
        0,
        4
    )

Padding.Parent = Scroll


--==============================================================
-- BUTTON POOL
--
-- Não destrói/recria a lista continuamente.
--==============================================================

local function createPooledButton(index)

    local button =
        Instance.new("TextButton")

    button.Name =
        "Item_" ..
        tostring(index)

    button.Size =
        UDim2.new(
            1,
            0,
            0,
            31
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            31,
            31,
            37
        )

    button.BorderSizePixel = 0

    button.TextColor3 =
        Color3.fromRGB(
            235,
            235,
            235
        )

    button.TextSize = 10

    button.Font =
        Enum.Font.GothamMedium

    button.TextXAlignment =
        Enum.TextXAlignment.Left

    button.Visible = false

    button.Parent = Scroll

    local padding =
        Instance.new("UIPadding")

    padding.PaddingLeft =
        UDim.new(
            0,
            8
        )

    padding.Parent = button

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(
            0,
            5
        )

    corner.Parent = button

    ButtonPool[index] = {

        Button = button,

        Object = nil
    }

    button.Activated:Connect(
        function()

            local slot =
                ButtonPool[index]

            if slot
            and slot.Object
            and slot.Object.Parent then

                teleportToItem(
                    slot.Object
                )
            end
        end
    )
end


for i = 1,
CONFIG.MAX_UI_ITEMS do

    createPooledButton(i)
end


--==============================================================
-- SORT ITEMS
--==============================================================

local function getSortedItems()

    local list = {}

    for obj, data in pairs(Items) do

        if obj
        and obj.Parent
        and obj:IsDescendantOf(
            Workspace
        ) then

            table.insert(
                list,
                {
                    Object = obj,

                    Name = data.Name,

                    Distance =
                        getDistance(obj),

                    Score =
                        data.Score
                }
            )
        end
    end

    table.sort(
        list,
        function(a, b)

            return a.Distance
                <
                b.Distance
        end
    )

    return list
end


--==============================================================
-- UPDATE LIST
--==============================================================

local CurrentSortedItems = {}


local function refreshList()

    CurrentSortedItems =
        getSortedItems()

    Title.Text =
        "ITENS • "
        ..
        tostring(
            #CurrentSortedItems
        )

    for index = 1,
    CONFIG.MAX_UI_ITEMS do

        local slot =
            ButtonPool[index]

        local entry =
            CurrentSortedItems[index]

        if entry then

            slot.Object =
                entry.Object

            slot.Button.Visible =
                true

            local distance =
                entry.Distance

            local distanceText

            if distance == math.huge then

                distanceText = "?"

            else

                distanceText =
                    tostring(
                        math.floor(
                            distance + 0.5
                        )
                    )
                    ..
                    "m"
            end

            slot.Button.Text =
                entry.Name
                ..
                "   •   "
                ..
                distanceText

        else

            slot.Object = nil

            slot.Button.Visible =
                false
        end
    end

    Scroll.CanvasSize =
        UDim2.new(
            0,
            0,
            0,
            math.min(
                #CurrentSortedItems,
                CONFIG.MAX_UI_ITEMS
            )
            *
            34
            +
            8
        )
end


--==============================================================
-- ESP
--==============================================================

local function destroyVisual(obj)

    local visual =
        Visuals[obj]

    if not visual then
        return
    end

    if visual.Highlight then

        visual.Highlight:Destroy()
    end

    if visual.Billboard then

        visual.Billboard:Destroy()
    end

    Visuals[obj] = nil
end


local function destroyAllVisuals()

    local toDestroy = {}

    for obj in pairs(Visuals) do

        table.insert(
            toDestroy,
            obj
        )
    end

    for _, obj in ipairs(
        toDestroy
    ) do

        destroyVisual(obj)
    end
end


local function createVisual(obj)

    if not State.ESP
    or Visuals[obj]
    or not obj
    or not obj.Parent then

        return
    end

    local part =
        getPart(obj)

    if not part then
        return
    end

    local highlight =
        Instance.new("Highlight")

    highlight.Name =
        "CafeinaItem"

    highlight.Adornee = obj

    highlight.FillColor =
        Color3.fromRGB(
            255,
            210,
            65
        )

    highlight.FillTransparency =
        0.82

    highlight.OutlineColor =
        Color3.fromRGB(
            255,
            255,
            255
        )

    highlight.OutlineTransparency =
        0.1

    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    highlight.Parent = GUI


    local billboard =
        Instance.new("BillboardGui")

    billboard.Name =
        "CafeinaItemLabel"

    billboard.Adornee = part

    billboard.Size =
        UDim2.fromOffset(
            120,
            30
        )

    billboard.StudsOffset =
        Vector3.new(
            0,
            2.2,
            0
        )

    billboard.AlwaysOnTop = true

    billboard.Parent = GUI


    local label =
        Instance.new("TextLabel")

    label.Size =
        UDim2.fromScale(
            1,
            1
        )

    label.BackgroundTransparency = 1

    label.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )

    label.TextStrokeColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )

    label.TextStrokeTransparency =
        0.15

    label.TextSize = 11

    label.Font =
        Enum.Font.GothamBold

    label.Parent =
        billboard


    Visuals[obj] = {

        Highlight =
            highlight,

        Billboard =
            billboard,

        Label =
            label,

        Part =
            part,
    }
end


--==============================================================
-- ESP UPDATE
--
-- Não usa RenderStepped.
--==============================================================

local function refreshESP()

    if not State.ESP then
        return
    end

    local sorted =
        getSortedItems()

    local allowed = {}

    local amount = 0

    for _, entry in ipairs(sorted) do

        if amount >=
        CONFIG.MAX_ACTIVE_ESP then

            break
        end

        if entry.Distance
        <=
        CONFIG.ESP_MAX_DISTANCE then

            allowed[
                entry.Object
            ] = entry

            amount += 1
        end
    end

    ----------------------------------------------------------
    -- remove ESP distante
    ----------------------------------------------------------

    local remove = {}

    for obj in pairs(Visuals) do

        if not allowed[obj] then

            table.insert(
                remove,
                obj
            )
        end
    end

    for _, obj in ipairs(remove) do

        destroyVisual(obj)
    end

    ----------------------------------------------------------
    -- atualiza somente os próximos
    ----------------------------------------------------------

    for obj, entry in pairs(
        allowed
    ) do

        if not Visuals[obj] then

            createVisual(obj)
        end

        local visual =
            Visuals[obj]

        if visual then

            local part =
                getPart(obj)

            if part then

                if visual.Part ~= part then

                    visual.Part = part

                    visual.Billboard.Adornee =
                        part
                end

                visual.Label.Text =
                    entry.Name
                    ..
                    "\n"
                    ..
                    tostring(
                        math.floor(
                            entry.Distance
                            +
                            0.5
                        )
                    )
                    ..
                    "m"
            end
        end
    end
end


--==============================================================
-- TOGGLE VISUAL
--==============================================================

local function updateToggleVisuals()

    ESPButton.Text =
        State.ESP
        and "ESP ON"
        or "ESP OFF"

    ESPButton.TextColor3 =
        State.ESP
        and Color3.fromRGB(
            245,
            245,
            245
        )
        or Color3.fromRGB(
            155,
            155,
            160
        )


    AutoButton.Text =
        State.AutoCollect
        and "AUTO ON"
        or "AUTO OFF"

    AutoButton.TextColor3 =
        State.AutoCollect
        and Color3.fromRGB(
            245,
            245,
            245
        )
        or Color3.fromRGB(
            155,
            155,
            160
        )
end


updateToggleVisuals()


ESPButton.Activated:Connect(
    function()

        State.ESP =
            not State.ESP

        updateToggleVisuals()

        if State.ESP then

            refreshESP()

        else

            destroyAllVisuals()
        end
    end
)


AutoButton.Activated:Connect(
    function()

        State.AutoCollect =
            not State.AutoCollect

        updateToggleVisuals()
    end
)


--==============================================================
-- OPEN / CLOSE
--==============================================================

local OPEN_SIZE =
    UDim2.fromOffset(
        182,
        235
    )


local CLOSED_SIZE =
    UDim2.fromOffset(
        182,
        0
    )


OpenButton.Activated:Connect(
    function()

        State.MenuOpen =
            not State.MenuOpen

        if State.MenuOpen then

            Panel.Visible = true

            TweenService:Create(
                Panel,
                TweenInfo.new(
                    0.13,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out
                ),
                {
                    Size =
                        OPEN_SIZE
                }
            ):Play()

            refreshList()

        else

            local tween =
                TweenService:Create(
                    Panel,
                    TweenInfo.new(
                        0.13,
                        Enum.EasingStyle.Quad,
                        Enum.EasingDirection.Out
                    ),
                    {
                        Size =
                            CLOSED_SIZE
                    }
                )

            tween:Play()

            tween.Completed:Once(
                function()

                    if not State.MenuOpen then
                        Panel.Visible = false
                    end
                end
            )
        end
    end
)


--==============================================================
-- MOBILE DRAG
--==============================================================

local dragging = false
local dragStart
local buttonStart


OpenButton.InputBegan:Connect(
    function(input)

        if input.UserInputType
            ==
            Enum.UserInputType.Touch

        or input.UserInputType
            ==
            Enum.UserInputType.MouseButton1 then

            dragging = true

            dragStart =
                input.Position

            buttonStart =
                OpenButton.Position
        end
    end
)


UserInputService.InputChanged:Connect(
    function(input)

        if not dragging then
            return
        end

        if input.UserInputType
            ~= Enum.UserInputType.Touch

        and input.UserInputType
            ~= Enum.UserInputType.MouseMovement then

            return
        end

        local delta =
            input.Position
            -
            dragStart

        OpenButton.Position =
            UDim2.new(
                buttonStart.X.Scale,
                buttonStart.X.Offset
                +
                delta.X,

                buttonStart.Y.Scale,
                buttonStart.Y.Offset
                +
                delta.Y
            )

        Panel.Position =
            UDim2.new(
                OpenButton.Position.X.Scale,
                OpenButton.Position.X.Offset,

                OpenButton.Position.Y.Scale,
                OpenButton.Position.Y.Offset
                +
                40
            )
    end
)


UserInputService.InputEnded:Connect(
    function(input)

        if input.UserInputType
            ==
            Enum.UserInputType.Touch

        or input.UserInputType
            ==
            Enum.UserInputType.MouseButton1 then

            dragging = false
        end
    end
)


--==============================================================
-- REAL-TIME WORLD OBSERVER
--==============================================================

table.insert(
    Connections,

    Workspace.DescendantAdded:Connect(
        function(obj)

            task.defer(
                function()

                    if State.Destroyed
                    or not obj
                    or not obj.Parent then

                        return
                    end

                    if obj:IsA("Tool")
                    or obj:IsA("Model")
                    or obj:IsA("ProximityPrompt")
                    or obj:IsA("ClickDetector")
                    or KnownItemNames[
                        obj.Name
                    ] then

                        registerCandidate(
                            obj
                        )
                    end
                end
            )
        end
    )
)


table.insert(
    Connections,

    Workspace.DescendantRemoving:Connect(
        function(obj)

            if Items[obj] then

                removeItem(
                    obj
                )
            end
        end
    )
)


--==============================================================
-- LEARN NEW TOOLS
--==============================================================

table.insert(
    Connections,

    Backpack.ChildAdded:Connect(
        function(obj)

            if obj:IsA("Tool") then

                addKnownName(
                    obj.Name
                )
            end
        end
    )
)


--==============================================================
-- CHARACTER RESPAWN
--==============================================================

table.insert(
    Connections,

    LocalPlayer.CharacterAdded:Connect(
        function()

            State.Busy = false

            task.wait(1)

            discoverBackpack()
        end
    )
)


--==============================================================
-- LIST LOOP
--==============================================================

task.spawn(
    function()

        while
            not State.Destroyed
            and GUI.Parent
        do

            if State.MenuOpen then

                pcall(
                    refreshList
                )
            end

            task.wait(
                CONFIG.LIST_INTERVAL
            )
        end
    end
)


--==============================================================
-- ESP LOOP
--==============================================================

task.spawn(
    function()

        while
            not State.Destroyed
            and GUI.Parent
        do

            if State.ESP then

                pcall(
                    refreshESP
                )
            end

            task.wait(
                CONFIG.ESP_INTERVAL
            )
        end
    end
)


--==============================================================
-- AUTO COLLECT LOOP
--==============================================================

task.spawn(
    function()

        while
            not State.Destroyed
            and GUI.Parent
        do

            if State.AutoCollect
            and not State.Busy then

                local item =
                    getNearestItem()

                if item then

                    pcall(
                        collectItem,
                        item
                    )
                end
            end

            task.wait(
                CONFIG.AUTO_INTERVAL
            )
        end
    end
)


--==============================================================
-- SLOW RECOVERY SCAN
--
-- Evita GetDescendants em loop rápido.
--==============================================================

task.spawn(
    function()

        while
            not State.Destroyed
            and GUI.Parent
        do

            task.wait(
                CONFIG.RECOVERY_SCAN_INTERVAL
            )

            if State.Destroyed
            or not GUI.Parent then

                break
            end

            pcall(
                scanWorld
            )
        end
    end
)


--==============================================================
-- INITIAL SCAN
--==============================================================

task.spawn(
    function()

        refreshKnownDatabase()

        scanWorld()

        refreshList()
    end
)


--==============================================================
-- READY
--==============================================================

print(
    "[CAFEÍNA] "
    ..
    CONFIG.VERSION
    ..
    " carregado."
)

print(
    "[CAFEÍNA] ESP: OFF | AUTO: OFF"
)
