--==============================================================
-- CAFEÍNA • SMART ITEMS V2
--
-- FOCO:
-- • SOMENTE itens/armas utilizáveis pelo jogador
-- • Lista em tempo real
-- • ESP de itens
-- • Nome + distância
-- • Teleporte até item
-- • Auto coleta
-- • Descoberta dinâmica usando informações do próprio jogo
-- • Deduplicação de Models/Parts
-- • Filtro forte contra cenário / personagens / NPC / acessórios
--
-- CLIENT-VISIBLE ONLY
--==============================================================


--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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

    VERSION = "SMART_ITEMS_V2",

    -- atualização estrutural
    SCAN_INTERVAL = 1.25,

    -- atualização da interface
    LIST_INTERVAL = 0.65,

    -- auto coleta
    AUTO_INTERVAL = 0.45,
    PICKUP_WAIT = 1.7,

    -- altura de teleporte
    TELEPORT_HEIGHT = 2.8,

    -- limite visual
    ESP_MAX_DISTANCE = 3500,

    -- limite de itens no menu
    MAX_UI_ITEMS = 60,

    -- pontuação mínima para um objeto desconhecido
    MIN_SCORE = 75,

    -- nomes confirmados pelas coletas
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

    ESP = true,

    AutoCollect = false,

    Busy = false,
}


--==============================================================
-- DATABASE DINÂMICO
--==============================================================

local KnownItemNames = {}

local Items = {}

local Visuals = {}

local ItemButtons = {}

local DeadObjects = setmetatable({}, {
    __mode = "k"
})


--==============================================================
-- CLEAN OLD GUI
--==============================================================

local old = CoreGui:FindFirstChild("CafeinaSmartItems")

if old then
    old:Destroy()
end


--==============================================================
-- ROOT GUI
--==============================================================

local GUI = Instance.new("ScreenGui")

GUI.Name = "CafeinaSmartItems"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = true
GUI.DisplayOrder = 999999
GUI.Parent = CoreGui


--==============================================================
-- CHARACTER HELPERS
--==============================================================

local function getCharacter()

    return LocalPlayer.Character
end


local function getRoot(model)

    if not model then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model.PrimaryPart
end


local function getMyRoot()

    return getRoot(
        getCharacter()
    )
end


--==============================================================
-- PHYSICAL PART
--==============================================================

local function getPart(obj)

    if not obj or not obj.Parent then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj
    end

    if obj:IsA("Tool") then

        local handle =
            obj:FindFirstChild("Handle")

        if handle and handle:IsA("BasePart") then
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


--==============================================================
-- STRING
--==============================================================

local function lower(text)

    return string.lower(
        tostring(text or "")
    )
end


--==============================================================
-- BLOCKED GENERIC NAMES
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

    Weld = true,
    Motor6D = true,

    Attachment = true,

    ParticleEmitter = true,

    Beam = true,
    Trail = true,
}


--==============================================================
-- NON-ITEM KEYWORDS
--==============================================================

local BLOCKED_KEYWORDS = {

    "humanoid",
    "accessory",
    "attachment",

    "particle",
    "effect",

    "zone",
    "locationnotifier",

    "spawn",
    "camera",

    "npc",
    "chain",

    "door",

    "terrain",

    "animation",

    "keyframe",
    "pose",

    "blood",

    "hitbox",

    "collider",

    "debris",

    "foliage",

    "grass",

    "tree",
}


--==============================================================
-- POSITIVE ITEM KEYWORDS
--==============================================================

local ITEM_KEYWORDS = {

    "weapon",

    "ammo",
    "ammunition",

    "gun",

    "rifle",

    "pistol",

    "shotgun",

    "magazine",

    "mag",

    "medical",

    "medkit",

    "bandage",

    "food",

    "drink",

    "water",

    "fuel",

    "battery",

    "tablet",

    "machete",

    "knife",

    "saw",

    "loot",

    "pickup",

    "item",

    "weapon part",
}


--==============================================================
-- PATH KEYWORDS
--==============================================================

local GOOD_PARENT_KEYWORDS = {

    "item",

    "loot",

    "pickup",

    "drop",

    "weapon",

    "storage",

    "spawneditem",

    "worlditem",
}


--==============================================================
-- CHECK KEYWORD
--==============================================================

local function containsKeyword(
    text,
    list
)

    text = lower(text)

    for _, word in ipairs(list) do

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
-- CHARACTER / NPC DETECTION
--==============================================================

local function belongsToLivingModel(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if current:IsA("Model") then

            if Players:GetPlayerFromCharacter(current) then
                return true
            end

            if current:FindFirstChildOfClass("Humanoid") then
                return true
            end
        end

        current = current.Parent
    end

    return false
end


--==============================================================
-- ACCESSORY FILTER
--==============================================================

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
-- GUI FILTER
--==============================================================

local function invalidWorldObject(obj)

    if not obj then
        return true
    end

    if not obj:IsDescendantOf(Workspace) then
        return true
    end

    if belongsToLivingModel(obj) then
        return true
    end

    if belongsToAccessory(obj) then
        return true
    end

    return false
end


--==============================================================
-- BUILD KNOWN ITEM DATABASE
--==============================================================

local function addKnownName(name)

    if not name
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
-- DISCOVER ItemInfo
--
-- ReplicatedStorage.GameStuff.ItemInfo
-- contém configurações das armas.
--
-- Não tratamos os objetos de ItemInfo como pickups.
-- Apenas usamos seus NOMES para reconhecer versões físicas.
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

    for _, item in ipairs(
        itemInfo:GetChildren()
    ) do

        addKnownName(
            item.Name
        )
    end
end


--==============================================================
-- DISCOVER SAVED ITEMS
--==============================================================

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

    for _, item in ipairs(
        saved:GetChildren()
    ) do

        addKnownName(
            item.Name
        )
    end
end


--==============================================================
-- DISCOVER BACKPACK
--==============================================================

local function discoverBackpack()

    for _, obj in ipairs(
        Backpack:GetChildren()
    ) do

        if obj:IsA("Tool") then

            addKnownName(
                obj.Name
            )
        end
    end

    local character =
        getCharacter()

    if character then

        for _, obj in ipairs(
            character:GetChildren()
        ) do

            if obj:IsA("Tool") then

                addKnownName(
                    obj.Name
                )
            end
        end
    end
end


--==============================================================
-- REFRESH DATABASE
--==============================================================

local function refreshKnownDatabase()

    discoverItemInfo()

    discoverSavedItems()

    discoverBackpack()
end


--==============================================================
-- INTERACTION DETECTION
--==============================================================

local function getPrompt(obj)

    return obj:FindFirstChildWhichIsA(
        "ProximityPrompt",
        true
    )
end


local function getClickDetector(obj)

    return obj:FindFirstChildWhichIsA(
        "ClickDetector",
        true
    )
end


local function getTouchTransmitter(obj)

    return obj:FindFirstChildWhichIsA(
        "TouchTransmitter",
        true
    )
end


--==============================================================
-- TOOL ANCESTOR
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


--==============================================================
-- KNOWN-NAME ANCESTOR
--==============================================================

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


--==============================================================
-- INTERACTION MODEL
--==============================================================

local function findInteractionModel(obj)

    local current = obj

    while current
    and current ~= Workspace do

        if current:IsA("Model") then

            if getPrompt(current)
            or getClickDetector(current)
            or getTouchTransmitter(current) then

                return current
            end
        end

        current = current.Parent
    end

    return nil
end


--==============================================================
-- CANONICAL ITEM ROOT
--
-- Faz toda Part/MeshPart interna apontar para UM único item.
--==============================================================

local function resolveItemRoot(obj)

    if invalidWorldObject(obj) then
        return nil
    end

    ----------------------------------------------------------
    -- Highest confidence:
    -- Tool real no Workspace
    ----------------------------------------------------------

    local tool =
        findToolAncestor(obj)

    if tool then
        return tool
    end

    ----------------------------------------------------------
    -- Known item model
    ----------------------------------------------------------

    local known =
        findKnownAncestor(obj)

    if known then
        return known
    end

    ----------------------------------------------------------
    -- Interaction model
    ----------------------------------------------------------

    local interaction =
        findInteractionModel(obj)

    if interaction then
        return interaction
    end

    ----------------------------------------------------------
    -- Direct model
    ----------------------------------------------------------

    if obj:IsA("Model") then
        return obj
    end

    return nil
end


--==============================================================
-- TAG ANALYSIS
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
        return score
    end

    for _, tag in ipairs(tags) do

        local tagLower =
            lower(tag)

        if containsKeyword(
            tagLower,
            ITEM_KEYWORDS
        ) then

            score += 35
        end
    end

    return score
end


--==============================================================
-- PATH SCORE
--==============================================================

local function scorePath(obj)

    local score = 0

    local current =
        obj.Parent

    local depth = 0

    while current
    and current ~= Workspace
    and depth < 5 do

        if containsKeyword(
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
-- ITEM CLASSIFIER
--
-- Esse é o coração do sistema.
--==============================================================

local function classifyItem(obj)

    if not obj
    or not obj.Parent then

        return false, 0
    end

    local root =
        resolveItemRoot(obj)

    if not root then
        return false, 0
    end

    if invalidWorldObject(root) then
        return false, 0
    end

    if BLOCKED_NAMES[
        root.Name
    ] then

        return false, 0
    end

    local rootName =
        root.Name

    local rootLower =
        lower(rootName)

    ----------------------------------------------------------
    -- Explicit exclusions
    ----------------------------------------------------------

    if containsKeyword(
        rootLower,
        BLOCKED_KEYWORDS
    ) then

        return false, 0
    end

    ----------------------------------------------------------
    -- Need physical representation
    ----------------------------------------------------------

    local part =
        getPart(root)

    if not part then
        return false, 0
    end

    local score = 0

    ----------------------------------------------------------
    -- Actual Tool
    ----------------------------------------------------------

    if root:IsA("Tool") then

        score += 120
    end

    ----------------------------------------------------------
    -- Known game item
    ----------------------------------------------------------

    if KnownItemNames[
        rootName
    ] then

        score += 90
    end

    ----------------------------------------------------------
    -- Confirmed from our mappings
    ----------------------------------------------------------

    if CONFIG.CONFIRMED_ITEMS[
        rootName
    ] then

        score += 35
    end

    ----------------------------------------------------------
    -- Interaction
    ----------------------------------------------------------

    if getPrompt(root) then
        score += 45
    end

    if getClickDetector(root) then
        score += 35
    end

    if getTouchTransmitter(root) then
        score += 35
    end

    ----------------------------------------------------------
    -- Semantic name
    ----------------------------------------------------------

    if containsKeyword(
        rootLower,
        ITEM_KEYWORDS
    ) then

        score += 30
    end

    ----------------------------------------------------------
    -- Tags
    ----------------------------------------------------------

    score += scoreTags(
        root
    )

    ----------------------------------------------------------
    -- Parent structure
    ----------------------------------------------------------

    score += scorePath(
        root
    )

    ----------------------------------------------------------
    -- Generic names receive penalty
    ----------------------------------------------------------

    if rootName == "Model"
    or rootName == "Folder"
    or rootName == "Object" then

        score -= 45
    end

    ----------------------------------------------------------
    -- Huge models are usually map objects
    ----------------------------------------------------------

    if root:IsA("Model") then

        local partCount = 0

        for _, descendant in ipairs(
            root:GetDescendants()
        ) do

            if descendant:IsA("BasePart") then

                partCount += 1

                if partCount > 80 then
                    break
                end
            end
        end

        if partCount > 80 then
            score -= 60
        elseif partCount > 35 then
            score -= 25
        end
    end

    ----------------------------------------------------------
    -- Result
    ----------------------------------------------------------

    if score >= CONFIG.MIN_SCORE then

        return true,
            score,
            root
    end

    return false,
        score,
        root
end


--==============================================================
-- DISPLAY NAME
--==============================================================

local function getDisplayName(obj)

    return obj.Name
end


--==============================================================
-- DISTANCE
--==============================================================

local function getDistance(obj)

    local root =
        getMyRoot()

    local part =
        getPart(obj)

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
-- ALREADY OWNED
--
-- Somente usado pelo AUTO COLLECT.
--
-- O item continua aparecendo no mapa mesmo se você já tiver
-- outro de mesmo nome.
--==============================================================

local function alreadyOwned(name)

    if Backpack:FindFirstChild(name) then
        return true
    end

    local character =
        getCharacter()

    if character
    and character:FindFirstChild(name) then

        return true
    end

    return false
end


--==============================================================
-- VISUAL CLEANUP
--==============================================================

local function destroyVisual(obj)

    local visual =
        Visuals[obj]

    if not visual then
        return
    end

    if visual.Highlight then

        pcall(function()
            visual.Highlight:Destroy()
        end)
    end

    if visual.Billboard then

        pcall(function()
            visual.Billboard:Destroy()
        end)
    end

    Visuals[obj] = nil
end


--==============================================================
-- CREATE ESP
--==============================================================

local function createVisual(obj)

    destroyVisual(obj)

    if not State.ESP then
        return
    end

    if not obj
    or not obj.Parent then
        return
    end

    local part =
        getPart(obj)

    if not part then
        return
    end

    ----------------------------------------------------------
    -- Highlight
    ----------------------------------------------------------

    local highlight =
        Instance.new("Highlight")

    highlight.Name =
        "CafeinaItemHighlight"

    highlight.Adornee =
        obj

    highlight.FillColor =
        Color3.fromRGB(
            255,
            215,
            70
        )

    highlight.FillTransparency =
        0.78

    highlight.OutlineColor =
        Color3.fromRGB(
            255,
            255,
            255
        )

    highlight.OutlineTransparency =
        0

    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    highlight.Parent =
        GUI

    ----------------------------------------------------------
    -- Billboard
    ----------------------------------------------------------

    local billboard =
        Instance.new("BillboardGui")

    billboard.Name =
        "CafeinaItemLabel"

    billboard.Adornee =
        part

    billboard.Size =
        UDim2.fromOffset(
            170,
            42
        )

    billboard.StudsOffset =
        Vector3.new(
            0,
            2.3,
            0
        )

    billboard.AlwaysOnTop =
        true

    billboard.Parent =
        GUI

    local text =
        Instance.new("TextLabel")

    text.Size =
        UDim2.fromScale(
            1,
            1
        )

    text.BackgroundTransparency =
        1

    text.Font =
        Enum.Font.GothamBold

    text.TextSize =
        13

    text.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )

    text.TextStrokeColor3 =
        Color3.fromRGB(
            0,
            0,
            0
        )

    text.TextStrokeTransparency =
        0

    text.TextWrapped =
        true

    text.Parent =
        billboard

    Visuals[obj] = {

        Highlight = highlight,

        Billboard = billboard,

        Label = text,

        Part = part
    }
end


--==============================================================
-- REGISTER
--==============================================================

local function registerItem(obj)

    local valid,
        score,
        root =
        classifyItem(obj)

    if not valid
    or not root then
        return
    end

    if Items[root] then

        Items[root].Score =
            math.max(
                Items[root].Score,
                score
            )

        return
    end

    Items[root] = {

        Object = root,

        Name =
            getDisplayName(root),

        Score = score
    }

    if State.ESP then

        createVisual(
            root
        )
    end
end


--==============================================================
-- UNREGISTER
--==============================================================

local function unregisterItem(obj)

    if not obj then
        return
    end

    Items[obj] = nil

    destroyVisual(obj)

    local button =
        ItemButtons[obj]

    if button then

        button:Destroy()

        ItemButtons[obj] = nil
    end
end


--==============================================================
-- FULL SMART SCAN
--==============================================================

local function scanWorld()

    refreshKnownDatabase()

    local seen = {}

    for _, obj in ipairs(
        Workspace:GetDescendants()
    ) do

        ------------------------------------------------------
        -- We do not deeply classify every tiny Part blindly.
        --
        -- Only interesting classes/names reach classifier.
        ------------------------------------------------------

        local interesting =
            obj:IsA("Tool")
            or obj:IsA("Model")
            or obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")

        if KnownItemNames[
            obj.Name
        ] then

            interesting = true
        end

        if interesting then

            local valid,
                score,
                root =
                classifyItem(obj)

            if valid
            and root then

                seen[root] = true

                if not Items[root] then

                    Items[root] = {

                        Object = root,

                        Name =
                            getDisplayName(root),

                        Score =
                            score
                    }

                    if State.ESP then

                        createVisual(
                            root
                        )
                    end

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

    ----------------------------------------------------------
    -- Remove stale
    ----------------------------------------------------------

    local stale = {}

    for obj in pairs(Items) do

        if not obj.Parent
        or not seen[obj] then

            table.insert(
                stale,
                obj
            )
        end
    end

    for _, obj in ipairs(stale) do

        unregisterItem(
            obj
        )
    end
end


--==============================================================
-- TELEPORT
--==============================================================

local function teleportToItem(obj)

    if not obj
    or not obj.Parent then
        return false
    end

    local character =
        getCharacter()

    local myRoot =
        getMyRoot()

    local itemPart =
        getPart(obj)

    if not character
    or not myRoot
    or not itemPart then

        return false
    end

    ----------------------------------------------------------
    -- Pivot character when possible.
    -- More stable than changing only HRP.
    ----------------------------------------------------------

    local target =
        itemPart.CFrame
        *
        CFrame.new(
            0,
            CONFIG.TELEPORT_HEIGHT,
            0
        )

    local success =
        pcall(function()

            character:PivotTo(
                target
            )
        end)

    if not success then

        pcall(function()

            myRoot.CFrame =
                target
        end)
    end

    return true
end


--==============================================================
-- NORMAL PICKUP INTERACTION
--==============================================================

local function tryPickup(obj)

    if not obj
    or not obj.Parent then
        return false
    end

    ----------------------------------------------------------
    -- ProximityPrompt
    ----------------------------------------------------------

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

    ----------------------------------------------------------
    -- ClickDetector
    ----------------------------------------------------------

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
    -- Touch-based pickup
    ----------------------------------------------------------

    local itemPart =
        getPart(obj)

    local myRoot =
        getMyRoot()

    if itemPart
    and myRoot
    and typeof(firetouchinterest)
        == "function" then

        pcall(function()

            firetouchinterest(
                myRoot,
                itemPart,
                0
            )

            task.wait()

            firetouchinterest(
                myRoot,
                itemPart,
                1
            )
        end)

        return true
    end

    return false
end


--==============================================================
-- WAIT COLLECTION
--==============================================================

local function waitCollected(
    obj,
    name
)

    local start =
        os.clock()

    while
        os.clock() - start
        <
        CONFIG.PICKUP_WAIT
    do

        if not State.AutoCollect then
            return false
        end

        if not obj
        or not obj.Parent then
            return true
        end

        if alreadyOwned(name) then
            return true
        end

        task.wait(0.1)
    end

    return false
end


--==============================================================
-- FIND NEAREST
--==============================================================

local function nearestCollectable()

    local myRoot =
        getMyRoot()

    if not myRoot then
        return nil
    end

    local nearest = nil
    local nearestDistance =
        math.huge

    for obj,data in pairs(Items) do

        if obj
        and obj.Parent then

            --------------------------------------------------
            -- avoid continuously trying same unique item
            --------------------------------------------------

            if not alreadyOwned(
                data.Name
            ) then

                local part =
                    getPart(obj)

                if part then

                    local distance =
                        (
                            myRoot.Position
                            -
                            part.Position
                        ).Magnitude

                    if distance
                    <
                    nearestDistance then

                        nearestDistance =
                            distance

                        nearest =
                            obj
                    end
                end
            end
        end
    end

    return nearest,
        nearestDistance
end


--==============================================================
-- COLLECT
--==============================================================

local function collectItem(obj)

    if State.Busy then
        return
    end

    local data =
        Items[obj]

    if not data then
        return
    end

    State.Busy =
        true

    if teleportToItem(obj) then

        task.wait(0.12)

        tryPickup(obj)

        waitCollected(
            obj,
            data.Name
        )
    end

    State.Busy =
        false
end


--==============================================================
-- MAIN BUTTON
--==============================================================

local MainButton =
    Instance.new("TextButton")

MainButton.Position =
    UDim2.new(
        0,
        14,
        0.40,
        0
    )

MainButton.Size =
    UDim2.fromOffset(
        118,
        36
    )

MainButton.BackgroundColor3 =
    Color3.fromRGB(
        22,
        22,
        26
    )

MainButton.Text =
    "CAFEÍNA ITENS"

MainButton.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

MainButton.Font =
    Enum.Font.GothamBold

MainButton.TextSize =
    12

MainButton.ZIndex =
    100

MainButton.Parent =
    GUI

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

MainCorner.Parent =
    MainButton


--==============================================================
-- PANEL
--==============================================================

local Panel =
    Instance.new("Frame")

Panel.Position =
    UDim2.new(
        0,
        14,
        0.40,
        40
    )

Panel.Size =
    UDim2.fromOffset(
        210,
        0
    )

Panel.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        22
    )

Panel.ClipsDescendants =
    true

Panel.Visible =
    false

Panel.ZIndex =
    90

Panel.Parent =
    GUI

local PanelCorner =
    Instance.new("UICorner")

PanelCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

PanelCorner.Parent =
    Panel


--==============================================================
-- STATUS
--==============================================================

local Status =
    Instance.new("TextLabel")

Status.Position =
    UDim2.fromOffset(
        8,
        5
    )

Status.Size =
    UDim2.new(
        1,
        -16,
        0,
        23
    )

Status.BackgroundTransparency =
    1

Status.Text =
    "ITENS: 0"

Status.TextColor3 =
    Color3.fromRGB(
        220,
        220,
        220
    )

Status.Font =
    Enum.Font.GothamBold

Status.TextSize =
    11

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.ZIndex =
    100

Status.Parent =
    Panel


--==============================================================
-- ESP BUTTON
--==============================================================

local ESPButton =
    Instance.new("TextButton")

ESPButton.Position =
    UDim2.fromOffset(
        7,
        31
    )

ESPButton.Size =
    UDim2.new(
        0.5,
        -10,
        0,
        31
    )

ESPButton.BackgroundColor3 =
    Color3.fromRGB(
        32,
        32,
        38
    )

ESPButton.Text =
    "ESP : ON"

ESPButton.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

ESPButton.Font =
    Enum.Font.GothamMedium

ESPButton.TextSize =
    11

ESPButton.ZIndex =
    100

ESPButton.Parent =
    Panel

local espCorner =
    Instance.new("UICorner")

espCorner.CornerRadius =
    UDim.new(
        0,
        6
    )

espCorner.Parent =
    ESPButton


--==============================================================
-- AUTO BUTTON
--==============================================================

local AutoButton =
    Instance.new("TextButton")

AutoButton.Position =
    UDim2.new(
        0.5,
        3,
        0,
        31
    )

AutoButton.Size =
    UDim2.new(
        0.5,
        -10,
        0,
        31
    )

AutoButton.BackgroundColor3 =
    Color3.fromRGB(
        32,
        32,
        38
    )

AutoButton.Text =
    "AUTO : OFF"

AutoButton.TextColor3 =
    Color3.fromRGB(
        190,
        190,
        190
    )

AutoButton.Font =
    Enum.Font.GothamMedium

AutoButton.TextSize =
    11

AutoButton.ZIndex =
    100

AutoButton.Parent =
    Panel

local autoCorner =
    Instance.new("UICorner")

autoCorner.CornerRadius =
    UDim.new(
        0,
        6
    )

autoCorner.Parent =
    AutoButton


--==============================================================
-- SCROLL
--==============================================================

local Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(
        7,
        68
    )

Scroll.Size =
    UDim2.new(
        1,
        -14,
        1,
        -75
    )

Scroll.BackgroundColor3 =
    Color3.fromRGB(
        24,
        24,
        29
    )

Scroll.BorderSizePixel =
    0

Scroll.ScrollBarThickness =
    3

Scroll.CanvasSize =
    UDim2.new()

Scroll.ZIndex =
    95

Scroll.Parent =
    Panel

local scrollCorner =
    Instance.new("UICorner")

scrollCorner.CornerRadius =
    UDim.new(
        0,
        6
    )

scrollCorner.Parent =
    Scroll


local Layout =
    Instance.new("UIListLayout")

Layout.Padding =
    UDim.new(
        0,
        4
    )

Layout.SortOrder =
    Enum.SortOrder.LayoutOrder

Layout.Parent =
    Scroll


local Padding =
    Instance.new("UIPadding")

Padding.PaddingTop =
    UDim.new(
        0,
        5
    )

Padding.PaddingBottom =
    UDim.new(
        0,
        5
    )

Padding.PaddingLeft =
    UDim.new(
        0,
        5
    )

Padding.PaddingRight =
    UDim.new(
        0,
        5
    )

Padding.Parent =
    Scroll


--==============================================================
-- CLEAR BUTTONS
--==============================================================

local function clearButtons()

    for obj,button in pairs(
        ItemButtons
    ) do

        if button then
            button:Destroy()
        end

        ItemButtons[obj] = nil
    end
end


--==============================================================
-- REFRESH ITEM LIST
--==============================================================

local function refreshList()

    clearButtons()

    local list = {}

    for obj,data in pairs(
        Items
    ) do

        if obj
        and obj.Parent then

            table.insert(
                list,
                {
                    Object =
                        obj,

                    Name =
                        data.Name,

                    Score =
                        data.Score,

                    Distance =
                        getDistance(obj)
                }
            )
        end
    end

    table.sort(
        list,
        function(a,b)

            return a.Distance
                <
                b.Distance
        end
    )

    Status.Text =
        "ITENS: "
        ..
        tostring(
            #list
        )

    local shown = 0

    for _,entry in ipairs(
        list
    ) do

        shown += 1

        if shown >
        CONFIG.MAX_UI_ITEMS then
            break
        end

        local obj =
            entry.Object

        local button =
            Instance.new("TextButton")

        button.Size =
            UDim2.new(
                1,
                0,
                0,
                34
            )

        button.BackgroundColor3 =
            Color3.fromRGB(
                32,
                32,
                38
            )

        button.TextColor3 =
            Color3.fromRGB(
                240,
                240,
                240
            )

        button.Font =
            Enum.Font.GothamMedium

        button.TextSize =
            11

        button.Text =
            entry.Name
            ..
            "   "
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

        button.ZIndex =
            100

        button.Parent =
            Scroll

        local corner =
            Instance.new(
                "UICorner"
            )

        corner.CornerRadius =
            UDim.new(
                0,
                5
            )

        corner.Parent =
            button

        ItemButtons[obj] =
            button

        button.MouseButton1Click:Connect(
            function()

                if obj
                and obj.Parent then

                    teleportToItem(
                        obj
                    )
                end
            end
        )
    end

    task.defer(function()

        Scroll.CanvasSize =
            UDim2.new(
                0,
                0,
                0,
                Layout.AbsoluteContentSize.Y
                +
                10
            )
    end)
end


--==============================================================
-- ESP TOGGLE
--==============================================================

ESPButton.MouseButton1Click:Connect(
    function()

        State.ESP =
            not State.ESP

        ESPButton.Text =
            State.ESP
            and "ESP : ON"
            or "ESP : OFF"

        if State.ESP then

            ESPButton.TextColor3 =
                Color3.fromRGB(
                    255,
                    255,
                    255
                )

            for obj in pairs(
                Items
            ) do

                createVisual(
                    obj
                )
            end

        else

            ESPButton.TextColor3 =
                Color3.fromRGB(
                    190,
                    190,
                    190
                )

            local destroy = {}

            for obj in pairs(
                Visuals
            ) do

                table.insert(
                    destroy,
                    obj
                )
            end

            for _,obj in ipairs(
                destroy
            ) do

                destroyVisual(
                    obj
                )
            end
        end
    end
)


--==============================================================
-- AUTO TOGGLE
--==============================================================

AutoButton.MouseButton1Click:Connect(
    function()

        State.AutoCollect =
            not State.AutoCollect

        AutoButton.Text =
            State.AutoCollect
            and "AUTO : ON"
            or "AUTO : OFF"

        AutoButton.TextColor3 =
            State.AutoCollect
            and Color3.fromRGB(
                255,
                255,
                255
            )
            or Color3.fromRGB(
                190,
                190,
                190
            )
    end
)


--==============================================================
-- MENU OPEN/CLOSE
--==============================================================

MainButton.MouseButton1Click:Connect(
    function()

        State.MenuOpen =
            not State.MenuOpen

        if State.MenuOpen then

            Panel.Visible =
                true

            Panel:TweenSize(
                UDim2.fromOffset(
                    210,
                    300
                ),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.15,
                true
            )

        else

            Panel:TweenSize(
                UDim2.fromOffset(
                    210,
                    0
                ),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.15,
                true,
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
-- REAL-TIME DISCOVERY
--==============================================================

Workspace.DescendantAdded:Connect(
    function(obj)

        task.defer(function()

            if not obj
            or not obj.Parent then
                return
            end

            --------------------------------------------------
            -- Only inspect plausible candidates
            --------------------------------------------------

            if obj:IsA("Tool")
            or obj:IsA("Model")
            or obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")
            or KnownItemNames[obj.Name] then

                registerItem(
                    obj
                )
            end
        end)
    end
)


Workspace.DescendantRemoving:Connect(
    function(obj)

        if Items[obj] then

            unregisterItem(
                obj
            )
        end
    end
)


--==============================================================
-- BACKPACK DISCOVERY
--==============================================================

Backpack.ChildAdded:Connect(
    function(obj)

        if obj:IsA("Tool") then

            addKnownName(
                obj.Name
            )
        end
    end
)


--==============================================================
-- ESP UPDATE
--==============================================================

RunService.RenderStepped:Connect(
    function()

        if not State.ESP then
            return
        end

        local stale = {}

        for obj,visual in pairs(
            Visuals
        ) do

            if not obj
            or not obj.Parent then

                table.insert(
                    stale,
                    obj
                )

            else

                local part =
                    getPart(obj)

                if not part then

                    table.insert(
                        stale,
                        obj
                    )

                else

                    if visual.Part
                    ~= part then

                        createVisual(
                            obj
                        )

                    else

                        local distance =
                            getDistance(obj)

                        local visible =
                            distance
                            <=
                            CONFIG.ESP_MAX_DISTANCE

                        visual.Billboard.Enabled =
                            visible

                        visual.Highlight.Enabled =
                            visible

                        if visible then

                            visual.Label.Text =
                                obj.Name
                                ..
                                "\n"
                                ..
                                tostring(
                                    math.floor(
                                        distance
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
        end

        for _,obj in ipairs(
            stale
        ) do

            unregisterItem(
                obj
            )
        end
    end
)


--==============================================================
-- PERIODIC SMART SCAN
--==============================================================

task.spawn(function()

    while GUI.Parent do

        pcall(
            scanWorld
        )

        task.wait(
            CONFIG.SCAN_INTERVAL
        )
    end
end)


--==============================================================
-- LIST UPDATE
--==============================================================

task.spawn(function()

    while GUI.Parent do

        if State.MenuOpen then

            refreshList()
        end

        task.wait(
            CONFIG.LIST_INTERVAL
        )
    end
end)


--==============================================================
-- AUTO COLLECT
--==============================================================

task.spawn(function()

    while GUI.Parent do

        if State.AutoCollect
        and not State.Busy then

            local item =
                nearestCollectable()

            if item then

                collectItem(
                    item
                )
            end
        end

        task.wait(
            CONFIG.AUTO_INTERVAL
        )
    end
end)


--==============================================================
-- INITIAL
--==============================================================

refreshKnownDatabase()

scanWorld()

refreshList()
