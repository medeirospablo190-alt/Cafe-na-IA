--[[
    ============================================================
    CAFEÍNA • ITEMS + PLAYERS MOBILE V5
    ============================================================

    FOCO:
    • Android / Mobile
    • Interface compacta
    • Baixo consumo
    • ESP APENAS de itens
    • ESP começa DESLIGADO
    • SEM auto coleta
    • Lista de itens sem distância
    • Lista de players sem distância
    • CHAIN sempre primeiro quando detectado
    • Teleporte do CHAIN afastado
    • Loot Crate sempre teleporta por cima
    • BearTrap não mostra distância no ESP
    • Teleporte seguro contra paredes/chão
    • Scan inicial + eventos em tempo real
    • Sem RenderStepped
    • Pool de botões reutilizável

    CLIENT-VISIBLE ONLY
    ============================================================
]]


--==============================================================
-- SERVICES
--==============================================================

local Players =
    game:GetService("Players")

local Workspace =
    game:GetService("Workspace")

local ReplicatedStorage =
    game:GetService("ReplicatedStorage")

local CollectionService =
    game:GetService("CollectionService")

local UserInputService =
    game:GetService("UserInputService")

local TweenService =
    game:GetService("TweenService")

local CoreGui =
    game:GetService("CoreGui")


local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer =
        Players.PlayerAdded:Wait()
end


local Backpack =
    LocalPlayer:WaitForChild(
        "Backpack"
    )


--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    VERSION =
        "CAFEINA_ITEMS_PLAYERS_V5_MOBILE",

    ----------------------------------------------------------
    -- PERFORMANCE
    ----------------------------------------------------------

    UI_REFRESH_INTERVAL = 0.80,

    ESP_REFRESH_INTERVAL = 0.30,

    RECOVERY_SCAN_INTERVAL = 30,

    EVENT_QUEUE_INTERVAL = 0.15,

    EVENT_QUEUE_BATCH = 30,

    ----------------------------------------------------------
    -- UI
    ----------------------------------------------------------

    WIDTH = 186,

    HEIGHT = 252,

    MAX_LIST_ROWS = 18,

    ----------------------------------------------------------
    -- ESP
    ----------------------------------------------------------

    MAX_ACTIVE_ESP = 16,

    ESP_MAX_DISTANCE = 1200,

    ----------------------------------------------------------
    -- TELEPORT
    ----------------------------------------------------------

    NORMAL_ITEM_HEIGHT = 5.5,

    LOOT_CRATE_HEIGHT = 9,

    PLAYER_DISTANCE = 5.5,

    CHAIN_MIN_DISTANCE = 8,

    CHAIN_MAX_DISTANCE = 12,

    FALLBACK_HEIGHT = 9,

    CLEARANCE_SIZE =
        Vector3.new(
            4.2,
            6.2,
            4.2
        ),

    ----------------------------------------------------------
    -- ITEM CLASSIFICATION
    ----------------------------------------------------------

    MIN_ITEM_SCORE = 75,

    CONFIRMED_ITEMS = {

        AK47 = true,

        Deagle = true,

        DoubleBarrel = true,

        M1911 = true,

        XSaw = true,

        Machete = true,

        MacheteU = true,

        Tablet = true,

        BearTrap = true,

        ["Bear Trap"] = true,

        ["Weapon Parts"] = true,

        ["Loot Crate"] = true,

        LootCrate = true,
    }
}


--==============================================================
-- STATE
--==============================================================

local State = {

    ESP = false,

    MenuOpen = false,

    CurrentPage = "ITEMS",

    Destroyed = false,
}


--==============================================================
-- DATA
--==============================================================

local KnownItemNames = {}

local KnownItemNamesNormalized = {}

local Items = {}

local Visuals = {}

local CandidateQueue = {}

local QueuedCandidates = {}

local RowPool = {}

local Connections = {}

local CurrentRows = {}


--==============================================================
-- STRING HELPERS
--==============================================================

local function lower(value)

    return string.lower(
        tostring(value or "")
    )
end


local function normalize(value)

    local text =
        lower(value)

    text =
        string.gsub(
            text,
            "[%s_%-%.]",
            ""
        )

    return text
end


local function containsPlain(
    text,
    term
)

    return string.find(
        lower(text),
        lower(term),
        1,
        true
    ) ~= nil
end


local function containsAny(
    text,
    terms
)

    text = lower(text)

    for _, term in ipairs(terms) do

        if string.find(
            text,
            term,
            1,
            true
        ) then

            return true
        end
    end

    return false
end


--==============================================================
-- PLAYER HELPERS
--==============================================================

local function getCharacter()

    return LocalPlayer.Character
end


local function getHumanoid()

    local character =
        getCharacter()

    if not character then
        return nil
    end

    return character:FindFirstChildOfClass(
        "Humanoid"
    )
end


local function getMyRoot()

    local character =
        getCharacter()

    if not character then
        return nil
    end

    return character:FindFirstChild(
        "HumanoidRootPart"
    )
        or character.PrimaryPart
end


local function getCharacterRoot(
    character
)

    if not character then
        return nil
    end

    return character:FindFirstChild(
        "HumanoidRootPart"
    )
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA(
            "BasePart"
        )
end


--==============================================================
-- OBJECT PART
--==============================================================

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
            obj:FindFirstChild(
                "Handle"
            )

        if handle
        and handle:IsA("BasePart") then
            return handle
        end
    end


    if obj:IsA("Model")
    and obj.PrimaryPart then

        return obj.PrimaryPart
    end


    return obj:FindFirstChildWhichIsA(
        "BasePart",
        true
    )
end


local function getDistance(obj)

    local myRoot =
        getMyRoot()

    local part =
        getPart(obj)

    if not myRoot
    or not part then

        return math.huge
    end

    return (
        myRoot.Position
        -
        part.Position
    ).Magnitude
end


--==============================================================
-- SPECIAL ITEM IDENTIFICATION
--==============================================================

local function isLootCrate(obj)

    if not obj then
        return false
    end

    local name =
        normalize(
            obj.Name
        )

    return name == "lootcrate"
        or containsPlain(
            name,
            "lootcrate"
        )
end


local function isBearTrap(obj)

    if not obj then
        return false
    end

    local name =
        normalize(
            obj.Name
        )

    return name == "beartrap"
        or containsPlain(
            name,
            "beartrap"
        )
end


--==============================================================
-- GUI PARENT
--==============================================================

local function resolveGuiParent()

    if typeof(gethui) == "function" then

        local ok, result =
            pcall(gethui)

        if ok
        and result then

            return result
        end
    end


    local ok =
        pcall(function()

            return CoreGui.Name
        end)

    if ok then
        return CoreGui
    end


    return LocalPlayer:WaitForChild(
        "PlayerGui"
    )
end


local GUI_PARENT =
    resolveGuiParent()


for _, name in ipairs({

    "CafeinaItemsPlayersV5",
    "CafeinaItemsPlayersV4",
    "CafeinaSmartItemsV3",

}) do

    local old =
        GUI_PARENT:FindFirstChild(
            name
        )

    if old then
        old:Destroy()
    end
end


--==============================================================
-- KNOWN ITEMS
--==============================================================

local function addKnownItemName(name)

    if type(name) ~= "string"
    or name == "" then

        return
    end

    KnownItemNames[name] = true

    KnownItemNamesNormalized[
        normalize(name)
    ] = true
end


for name in pairs(
    CONFIG.CONFIRMED_ITEMS
) do

    addKnownItemName(
        name
    )
end


local function isKnownItemName(name)

    if not name then
        return false
    end

    return
        KnownItemNames[name]
        or
        KnownItemNamesNormalized[
            normalize(name)
        ]
        or false
end


--==============================================================
-- LEARN GAME ITEMS
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

        addKnownItemName(
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

        addKnownItemName(
            child.Name
        )
    end
end


local function discoverOwnedTools()

    for _, child in ipairs(
        Backpack:GetChildren()
    ) do

        if child:IsA("Tool") then

            addKnownItemName(
                child.Name
            )
        end
    end


    local character =
        getCharacter()

    if character then

        for _, child in ipairs(
            character:GetChildren()
        ) do

            if child:IsA("Tool") then

                addKnownItemName(
                    child.Name
                )
            end
        end
    end
end


local function refreshKnownItems()

    discoverItemInfo()

    discoverSavedItems()

    discoverOwnedTools()
end


--==============================================================
-- CLASSIFICATION FILTERS
--==============================================================

local BLOCKED_EXACT = {

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

    Attachment = true,

    Weld = true,
    WeldConstraint = true,

    Motor6D = true,

    Bone = true,
}


local BAD_KEYWORDS = {

    "humanoid",

    "accessory",

    "animation",

    "keyframe",

    "pose",

    "particle",

    "effect",

    "hitbox",

    "collider",

    "camera",

    "terrain",

    "foliage",

    "grass",

    "tree",

    "blood",

    "debris",

    "locationnotifier",

    "spawnpoint",

    "door",

    "window",
}


local STRONG_ITEM_KEYWORDS = {

    "weapon",

    "rifle",

    "pistol",

    "shotgun",

    "gun",

    "ammo",

    "ammunition",

    "magazine",

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

    "loot crate",

    "lootcrate",

    "bear trap",

    "beartrap",

    "weapon part",
}


local GOOD_PARENT_KEYWORDS = {

    "items",

    "loot",

    "pickups",

    "drops",

    "weapons",

    "worlditems",

    "spawneditems",
}


--==============================================================
-- CHARACTER / NPC FILTER
--==============================================================

local function belongsToLivingModel(obj)

    local current =
        obj

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

        current =
            current.Parent
    end

    return false
end


local function belongsToAccessory(obj)

    local current =
        obj

    while current
    and current ~= Workspace do

        if current:IsA("Accessory") then
            return true
        end

        current =
            current.Parent
    end

    return false
end


--==============================================================
-- INTERACTIONS
--==============================================================

local function hasPrompt(obj)

    return obj
        and
        obj:FindFirstChildWhichIsA(
            "ProximityPrompt",
            true
        ) ~= nil
end


local function hasClick(obj)

    return obj
        and
        obj:FindFirstChildWhichIsA(
            "ClickDetector",
            true
        ) ~= nil
end


local function hasTouch(obj)

    return obj
        and
        obj:FindFirstChildWhichIsA(
            "TouchTransmitter",
            true
        ) ~= nil
end


--==============================================================
-- FIND CANONICAL ITEM ROOT
--==============================================================

local function findToolAncestor(obj)

    local current =
        obj

    while current
    and current ~= Workspace do

        if current:IsA("Tool") then
            return current
        end

        current =
            current.Parent
    end

    return nil
end


local function findKnownAncestor(obj)

    local current =
        obj

    while current
    and current ~= Workspace do

        if isKnownItemName(
            current.Name
        ) then

            return current
        end

        current =
            current.Parent
    end

    return nil
end


local function findSemanticInteractionRoot(
    obj
)

    local current =
        obj

    local depth = 0

    while current
    and current ~= Workspace
    and depth <= 5 do

        if current:IsA("Model")
        or current:IsA("BasePart") then

            local interaction =
                hasPrompt(current)
                or hasClick(current)
                or hasTouch(current)

            if interaction
            and containsAny(
                current.Name,
                STRONG_ITEM_KEYWORDS
            ) then

                return current
            end
        end

        current =
            current.Parent

        depth += 1
    end

    return nil
end


local function resolveItemRoot(obj)

    if not obj
    or not obj.Parent then

        return nil
    end


    if not obj:IsDescendantOf(
        Workspace
    ) then

        return nil
    end


    if belongsToLivingModel(obj)
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


    return findSemanticInteractionRoot(
        obj
    )
end


--==============================================================
-- TAG SCORE
--==============================================================

local function getTagScore(obj)

    local score = 0

    local ok, tags =
        pcall(function()

            return CollectionService:GetTags(
                obj
            )
        end)

    if not ok then
        return 0
    end


    for _, tag in ipairs(tags) do

        if containsAny(
            tag,
            STRONG_ITEM_KEYWORDS
        ) then

            score += 25
        end
    end

    return score
end


--==============================================================
-- PARENT SCORE
--==============================================================

local function getParentScore(obj)

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

        current =
            current.Parent

        depth += 1
    end

    return score
end


--==============================================================
-- ITEM CLASSIFIER
--==============================================================

local function classifyItem(obj)

    local root =
        resolveItemRoot(obj)

    if not root
    or not root.Parent then

        return false
    end


    if BLOCKED_EXACT[
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
    -- Tool físico é uma evidência extremamente forte.
    ----------------------------------------------------------

    if root:IsA("Tool") then

        score += 120
    end


    ----------------------------------------------------------
    -- Nome conhecido da estrutura real do jogo.
    ----------------------------------------------------------

    if isKnownItemName(
        root.Name
    ) then

        score += 95
    end


    ----------------------------------------------------------
    -- Confirmado manualmente.
    ----------------------------------------------------------

    if CONFIG.CONFIRMED_ITEMS[
        root.Name
    ] then

        score += 45
    end


    ----------------------------------------------------------
    -- Nome semanticamente forte.
    ----------------------------------------------------------

    if containsAny(
        root.Name,
        STRONG_ITEM_KEYWORDS
    ) then

        score += 40
    end


    ----------------------------------------------------------
    -- Interação.
    --
    -- Sozinha NÃO torna qualquer objeto um item.
    ----------------------------------------------------------

    if hasPrompt(root) then
        score += 25
    end


    if hasClick(root) then
        score += 20
    end


    if hasTouch(root) then
        score += 15
    end


    score +=
        getTagScore(root)

    score +=
        getParentScore(root)


    ----------------------------------------------------------
    -- Penalização para estruturas enormes.
    ----------------------------------------------------------

    if root:IsA("Model") then

        local count = 0

        for _, descendant in ipairs(
            root:GetDescendants()
        ) do

            if descendant:IsA(
                "BasePart"
            ) then

                count += 1

                if count > 50 then
                    break
                end
            end
        end


        if count > 50 then

            score -= 100

        elseif count > 30 then

            score -= 40
        end
    end


    if score >=
        CONFIG.MIN_ITEM_SCORE then

        return true,
            root,
            score
    end


    return false
end


--==============================================================
-- ITEM REGISTRY
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


local function removeItem(obj)

    Items[obj] = nil

    destroyVisual(obj)
end


local function registerCandidate(obj)

    local valid,
        root,
        score =
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

        Name = root.Name,

        Score = score,
    }
end


--==============================================================
-- EVENT QUEUE
--==============================================================

local function queueCandidate(obj)

    if not obj
    or QueuedCandidates[obj] then

        return
    end


    local interesting =
        obj:IsA("Tool")
        or obj:IsA("Model")
        or obj:IsA("ProximityPrompt")
        or obj:IsA("ClickDetector")
        or obj:IsA("TouchTransmitter")
        or isKnownItemName(
            obj.Name
        )


    if not interesting then
        return
    end


    QueuedCandidates[obj] = true


    table.insert(
        CandidateQueue,
        obj
    )
end


task.spawn(function()

    while not State.Destroyed do

        local processed = 0


        while
            #CandidateQueue > 0
            and processed <
                CONFIG.EVENT_QUEUE_BATCH
        do

            local obj =
                table.remove(
                    CandidateQueue,
                    1
                )

            QueuedCandidates[obj] = nil


            if obj
            and obj.Parent then

                pcall(
                    registerCandidate,
                    obj
                )
            end


            processed += 1
        end


        task.wait(
            CONFIG.EVENT_QUEUE_INTERVAL
        )
    end
end)


--==============================================================
-- INITIAL / RECOVERY SCAN
--==============================================================

local function scanWorld()

    refreshKnownItems()


    local descendants =
        Workspace:GetDescendants()


    local seen = {}


    for index, obj in ipairs(
        descendants
    ) do

        local interesting =
            obj:IsA("Tool")
            or obj:IsA("Model")
            or obj:IsA("ProximityPrompt")
            or obj:IsA("ClickDetector")
            or obj:IsA("TouchTransmitter")
            or isKnownItemName(
                obj.Name
            )


        if interesting then

            local valid,
                root,
                score =
                classifyItem(obj)


            if valid
            and root then

                seen[root] = true


                if Items[root] then

                    Items[root].Score =
                        math.max(
                            Items[root].Score,
                            score
                        )

                else

                    Items[root] = {

                        Object = root,

                        Name =
                            root.Name,

                        Score =
                            score,
                    }
                end
            end
        end


        ------------------------------------------------------
        -- Dá pequenos respiros no scan inicial para Android.
        ------------------------------------------------------

        if index % 450 == 0 then
            task.wait()
        end
    end


    local stale = {}


    for root in pairs(
        Items
    ) do

        if not root
        or not root.Parent
        or not root:IsDescendantOf(
            Workspace
        )
        or not seen[root] then

            table.insert(
                stale,
                root
            )
        end
    end


    for _, root in ipairs(
        stale
    ) do

        removeItem(
            root
        )
    end
end


--==============================================================
-- COLLISION HELPERS
--==============================================================

local function createIgnoreList(
    target
)

    local list = {}


    local character =
        getCharacter()


    if character then

        table.insert(
            list,
            character
        )
    end


    if target then

        table.insert(
            list,
            target
        )
    end


    return list
end


local function positionIsFree(
    position,
    target
)

    local params =
        OverlapParams.new()


    params.FilterType =
        Enum.RaycastFilterType.Exclude


    params.FilterDescendantsInstances =
        createIgnoreList(
            target
        )


    local parts =
        Workspace:GetPartBoundsInBox(
            CFrame.new(position),
            CONFIG.CLEARANCE_SIZE,
            params
        )


    for _, part in ipairs(parts) do

        if part
        and part.CanCollide
        and part.Transparency < 0.97 then

            return false
        end
    end


    return true
end


--==============================================================
-- GROUND FINDER
--==============================================================

local function getGroundPosition(
    position,
    target
)

    local params =
        RaycastParams.new()


    params.FilterType =
        Enum.RaycastFilterType.Exclude


    params.FilterDescendantsInstances =
        createIgnoreList(
            target
        )


    local origin =
        position
        +
        Vector3.new(
            0,
            15,
            0
        )


    local result =
        Workspace:Raycast(
            origin,
            Vector3.new(
                0,
                -40,
                0
            ),
            params
        )


    if not result
    or not result.Instance then

        return nil
    end


    if not result.Instance.CanCollide then
        return nil
    end


    return result.Position
        +
        Vector3.new(
            0,
            3.1,
            0
        )
end


--==============================================================
-- LINE / WALL TEST
--==============================================================

local function pathIsClear(
    fromPosition,
    toPosition,
    target
)

    local direction =
        toPosition
        -
        fromPosition


    if direction.Magnitude <= 0.1 then
        return true
    end


    local params =
        RaycastParams.new()


    params.FilterType =
        Enum.RaycastFilterType.Exclude


    params.FilterDescendantsInstances =
        createIgnoreList(
            target
        )


    local hit =
        Workspace:Raycast(
            fromPosition,
            direction,
            params
        )


    if not hit then
        return true
    end


    return false
end


--==============================================================
-- TELEPORT EXECUTION
--==============================================================

local function performTeleport(
    destination
)

    if not destination then
        return false
    end


    local character =
        getCharacter()


    local humanoid =
        getHumanoid()


    if not character
    or not humanoid
    or humanoid.Health <= 0 then

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
-- LOOT CRATE TELEPORT
--
-- REGRA:
-- Sempre acima da crate.
-- Não tenta pontos laterais.
--==============================================================

local function teleportLootCrate(
    crate
)

    local part =
        getPart(crate)


    if not part then
        return false
    end


    local baseHeight =
        CONFIG.LOOT_CRATE_HEIGHT


    ----------------------------------------------------------
    -- Continua subindo até encontrar volume livre.
    ----------------------------------------------------------

    for extra = 0, 10, 2 do

        local position =
            part.Position
            +
            Vector3.new(
                0,
                baseHeight + extra,
                0
            )


        if positionIsFree(
            position,
            crate
        ) then

            return performTeleport(
                CFrame.new(
                    position
                )
            )
        end
    end


    ----------------------------------------------------------
    -- Se não existe posição livre, evita nascer dentro do mapa.
    ----------------------------------------------------------

    return false
end


--==============================================================
-- NORMAL ITEM TELEPORT
--==============================================================

local function teleportNormalItem(
    item
)

    local part =
        getPart(item)


    if not part then
        return false
    end


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
    }


    for _, offset in ipairs(
        offsets
    ) do

        local rawPosition =
            part.Position
            +
            offset


        local grounded =
            getGroundPosition(
                rawPosition,
                item
            )


        if grounded
        and positionIsFree(
            grounded,
            item
        ) then

            return performTeleport(
                CFrame.new(
                    grounded
                )
            )
        end
    end


    ----------------------------------------------------------
    -- Fallback acima.
    ----------------------------------------------------------

    local fallback =
        part.Position
        +
        Vector3.new(
            0,
            CONFIG.FALLBACK_HEIGHT,
            0
        )


    if positionIsFree(
        fallback,
        item
    ) then

        return performTeleport(
            CFrame.new(
                fallback
            )
        )
    end


    return false
end


local function teleportToItem(
    item
)

    if not item
    or not item.Parent then

        return false
    end


    if isLootCrate(
        item
    ) then

        return teleportLootCrate(
            item
        )
    end


    return teleportNormalItem(
        item
    )
end


--==============================================================
-- CHAIN DETECTION
--
-- Evita considerar peças internas chamadas "Chain".
-- Procura principalmente entidades/modelos.
--==============================================================

local function chainScore(obj)

    if not obj
    or not obj.Parent
    or not obj:IsDescendantOf(
        Workspace
    ) then

        return -math.huge
    end


    if not obj:IsA("Model")
    and not obj:IsA("BasePart") then

        return -math.huge
    end


    local name =
        normalize(
            obj.Name
        )


    if name ~= "chain" then
        return -math.huge
    end


    local score = 0


    if obj:IsA("Model") then

        score += 100


        if obj:FindFirstChildOfClass(
            "Humanoid"
        ) then

            score += 100
        end


        if obj:FindFirstChild(
            "HumanoidRootPart"
        ) then

            score += 80
        end


        if obj.PrimaryPart then
            score += 25
        end

    elseif obj:IsA("BasePart") then

        score += 10
    end


    ----------------------------------------------------------
    -- Peça enterrada profundamente em outra estrutura tende
    -- a não ser a entidade principal.
    ----------------------------------------------------------

    local depth = 0
    local current = obj.Parent


    while current
    and current ~= Workspace do

        depth += 1

        current =
            current.Parent
    end


    score -=
        depth * 3


    return score
end


local function findChain()

    local best = nil
    local bestScore = -math.huge


    ----------------------------------------------------------
    -- Primeiro tenta filho/modelo de nível superior.
    ----------------------------------------------------------

    for _, obj in ipairs(
        Workspace:GetChildren()
    ) do

        local score =
            chainScore(obj)


        if score >
            bestScore then

            bestScore =
                score

            best =
                obj
        end
    end


    if best
    and bestScore >= 50 then

        return best
    end


    ----------------------------------------------------------
    -- Busca secundária por nome exato.
    -- Executada somente na atualização da lista, não por frame.
    ----------------------------------------------------------

    for _, obj in ipairs(
        Workspace:GetDescendants()
    ) do

        if normalize(
            obj.Name
        ) == "chain" then

            local score =
                chainScore(obj)


            if score >
                bestScore then

                bestScore =
                    score

                best =
                    obj
            end
        end
    end


    if bestScore >= 25 then
        return best
    end


    return nil
end


--==============================================================
-- CHAIN SAFE TELEPORT
--
-- Fica 8–12 studs afastado.
-- Testa várias direções.
-- Não aparece diretamente dentro dele.
--==============================================================

local function teleportToChain(
    chain
)

    if not chain
    or not chain.Parent then

        return false
    end


    local targetPart =
        getPart(chain)


    if not targetPart then
        return false
    end


    local myRoot =
        getMyRoot()


    ----------------------------------------------------------
    -- Primeira direção tenta ficar no lado em que o jogador
    -- já está em relação ao CHAIN.
    ----------------------------------------------------------

    local preferred =
        Vector3.new(
            0,
            0,
            -1
        )


    if myRoot then

        local difference =
            Vector3.new(
                myRoot.Position.X
                    -
                    targetPart.Position.X,

                0,

                myRoot.Position.Z
                    -
                    targetPart.Position.Z
            )


        if difference.Magnitude >
            0.1 then

            preferred =
                difference.Unit
        end
    end


    local directions = {

        preferred,

        -preferred,

        Vector3.new(
            preferred.Z,
            0,
            -preferred.X
        ),

        Vector3.new(
            -preferred.Z,
            0,
            preferred.X
        ),

        Vector3.new(1, 0, 0),

        Vector3.new(-1, 0, 0),

        Vector3.new(0, 0, 1),

        Vector3.new(0, 0, -1),

        Vector3.new(1, 0, 1).Unit,

        Vector3.new(-1, 0, 1).Unit,

        Vector3.new(1, 0, -1).Unit,

        Vector3.new(-1, 0, -1).Unit,
    }


    local distances = {

        CONFIG.CHAIN_MIN_DISTANCE,

        10,

        CONFIG.CHAIN_MAX_DISTANCE,
    }


    for _, distance in ipairs(
        distances
    ) do

        for _, direction in ipairs(
            directions
        ) do

            local rawPosition =
                targetPart.Position
                +
                direction
                *
                distance


            local grounded =
                getGroundPosition(
                    rawPosition,
                    chain
                )


            if grounded
            and positionIsFree(
                grounded,
                chain
            ) then

                --------------------------------------------------
                -- Queremos um local livre ao redor do CHAIN,
                -- não simplesmente dentro de uma parede.
                --------------------------------------------------

                local clear =
                    pathIsClear(
                        grounded
                            +
                            Vector3.new(
                                0,
                                2,
                                0
                            ),

                        targetPart.Position
                            +
                            Vector3.new(
                                0,
                                2,
                                0
                            ),

                        chain
                    )


                --------------------------------------------------
                -- Se há linha direta, excelente.
                -- Se não, ainda testa posições mais afastadas.
                --------------------------------------------------

                if clear
                or distance >=
                    CONFIG.CHAIN_MAX_DISTANCE then

                    local lookAt =
                        Vector3.new(
                            targetPart.Position.X,

                            grounded.Y,

                            targetPart.Position.Z
                        )


                    return performTeleport(
                        CFrame.lookAt(
                            grounded,
                            lookAt
                        )
                    )
                end
            end
        end
    end


    return false
end


--==============================================================
-- NORMAL PLAYER TELEPORT
--==============================================================

local function teleportToPlayer(
    player
)

    if not player
    or player == LocalPlayer then

        return false
    end


    local character =
        player.Character


    local targetRoot =
        getCharacterRoot(
            character
        )


    if not character
    or not targetRoot then

        return false
    end


    local look =
        targetRoot.CFrame.LookVector


    local right =
        targetRoot.CFrame.RightVector


    local directions = {

        -look,

        right,

        -right,

        look,

        (
            -look
            +
            right
        ).Unit,

        (
            -look
            -
            right
        ).Unit,
    }


    for _, direction in ipairs(
        directions
    ) do

        local rawPosition =
            targetRoot.Position
            +
            direction
            *
            CONFIG.PLAYER_DISTANCE


        local grounded =
            getGroundPosition(
                rawPosition,
                character
            )


        if grounded
        and positionIsFree(
            grounded,
            character
        ) then

            local facePosition =
                Vector3.new(
                    targetRoot.Position.X,

                    grounded.Y,

                    targetRoot.Position.Z
                )


            return performTeleport(
                CFrame.lookAt(
                    grounded,
                    facePosition
                )
            )
        end
    end


    ----------------------------------------------------------
    -- Fallback um pouco acima e atrás.
    ----------------------------------------------------------

    local fallback =
        targetRoot.Position
        -
        targetRoot.CFrame.LookVector
        *
        CONFIG.PLAYER_DISTANCE
        +
        Vector3.new(
            0,
            5,
            0
        )


    if positionIsFree(
        fallback,
        character
    ) then

        return performTeleport(
            CFrame.lookAt(
                fallback,
                targetRoot.Position
            )
        )
    end


    return false
end


--==============================================================
-- SORT ITEMS
--==============================================================

local function getSortedItems()

    local result = {}


    for root, data in pairs(
        Items
    ) do

        if root
        and root.Parent
        and root:IsDescendantOf(
            Workspace
        ) then

            table.insert(
                result,
                {

                    Type = "ITEM",

                    Object = root,

                    Name =
                        data.Name,

                    Distance =
                        getDistance(root),
                }
            )
        end
    end


    ----------------------------------------------------------
    -- Distância é usada internamente apenas para ordenar.
    -- Ela NÃO aparece na lista.
    ----------------------------------------------------------

    table.sort(
        result,
        function(a, b)

            if a.Name == b.Name then

                return
                    a.Distance
                    <
                    b.Distance
            end


            return
                a.Distance
                <
                b.Distance
        end
    )


    return result
end


--==============================================================
-- PLAYER LIST
--==============================================================

local function getPlayerDestinations()

    local result = {}


    ----------------------------------------------------------
    -- CHAIN SEMPRE PRIMEIRO.
    ----------------------------------------------------------

    local chain =
        findChain()


    if chain then

        table.insert(
            result,
            {

                Type = "CHAIN",

                Name = "CHAIN",

                Object = chain,
            }
        )
    end


    ----------------------------------------------------------
    -- Players normais.
    ----------------------------------------------------------

    local playerList = {}


    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player ~= LocalPlayer then

            local character =
                player.Character


            local root =
                getCharacterRoot(
                    character
                )


            if character
            and root then

                table.insert(
                    playerList,
                    player
                )
            end
        end
    end


    table.sort(
        playerList,
        function(a, b)

            local an =
                lower(
                    a.DisplayName
                    or a.Name
                )

            local bn =
                lower(
                    b.DisplayName
                    or b.Name
                )


            return an < bn
        end
    )


    for _, player in ipairs(
        playerList
    ) do

        table.insert(
            result,
            {

                Type =
                    "PLAYER",

                Name =
                    player.DisplayName
                    or player.Name,

                Username =
                    player.Name,

                Object =
                    player,
            }
        )
    end


    return result
end


--==============================================================
-- GUI
--==============================================================

local GUI =
    Instance.new(
        "ScreenGui"
    )


GUI.Name =
    "CafeinaItemsPlayersV5"


GUI.ResetOnSpawn =
    false


GUI.IgnoreGuiInset =
    false


GUI.DisplayOrder =
    999999


GUI.Parent =
    GUI_PARENT


--==============================================================
-- MOBILE SCALE
--==============================================================

local Scale =
    Instance.new(
        "UIScale"
    )


Scale.Scale = 1


Scale.Parent =
    GUI


local function updateScale()

    local camera =
        Workspace.CurrentCamera


    if not camera then
        return
    end


    local width =
        camera.ViewportSize.X


    if width < 360 then

        Scale.Scale = 0.88

    elseif width < 430 then

        Scale.Scale = 0.94

    else

        Scale.Scale = 1
    end
end


updateScale()


if Workspace.CurrentCamera then

    table.insert(
        Connections,

        Workspace.CurrentCamera
            :GetPropertyChangedSignal(
                "ViewportSize"
            )
            :Connect(
                updateScale
            )
    )
end


--==============================================================
-- FLOAT BUTTON
--==============================================================

local OpenButton =
    Instance.new(
        "TextButton"
    )


OpenButton.Name =
    "Open"


OpenButton.Size =
    UDim2.fromOffset(
        108,
        34
    )


OpenButton.Position =
    UDim2.new(
        0,
        12,
        0.42,
        0
    )


OpenButton.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        22
    )


OpenButton.BorderSizePixel = 0


OpenButton.Text =
    "☕ CAFEÍNA"


OpenButton.TextColor3 =
    Color3.fromRGB(
        240,
        240,
        244
    )


OpenButton.TextSize = 11


OpenButton.Font =
    Enum.Font.GothamBold


OpenButton.AutoButtonColor =
    false


OpenButton.Parent =
    GUI


local OpenCorner =
    Instance.new(
        "UICorner",
        OpenButton
    )


OpenCorner.CornerRadius =
    UDim.new(
        0,
        8
    )


local OpenStroke =
    Instance.new(
        "UIStroke",
        OpenButton
    )


OpenStroke.Thickness = 1


OpenStroke.Transparency =
    0.65


OpenStroke.Color =
    Color3.fromRGB(
        145,
        115,
        65
    )


--==============================================================
-- PANEL
--==============================================================

local Panel =
    Instance.new(
        "Frame"
    )


Panel.Size =
    UDim2.fromOffset(
        CONFIG.WIDTH,
        CONFIG.HEIGHT
    )


Panel.Position =
    UDim2.new(
        0,
        12,
        0.42,
        40
    )


Panel.BackgroundColor3 =
    Color3.fromRGB(
        16,
        16,
        20
    )


Panel.BorderSizePixel =
    0


Panel.Visible =
    false


Panel.ClipsDescendants =
    true


Panel.Parent =
    GUI


local PanelCorner =
    Instance.new(
        "UICorner",
        Panel
    )


PanelCorner.CornerRadius =
    UDim.new(
        0,
        9
    )


local PanelStroke =
    Instance.new(
        "UIStroke",
        Panel
    )


PanelStroke.Thickness = 1


PanelStroke.Transparency =
    0.72


PanelStroke.Color =
    Color3.fromRGB(
        120,
        100,
        70
    )


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
        31
    )


Header.BackgroundTransparency =
    1


Header.Parent =
    Panel


local HeaderTitle =
    Instance.new(
        "TextLabel"
    )


HeaderTitle.Position =
    UDim2.fromOffset(
        9,
        0
    )


HeaderTitle.Size =
    UDim2.new(
        1,
        -42,
        1,
        0
    )


HeaderTitle.BackgroundTransparency =
    1


HeaderTitle.Text =
    "CAFEÍNA"


HeaderTitle.TextColor3 =
    Color3.fromRGB(
        235,
        235,
        238
    )


HeaderTitle.TextSize =
    11


HeaderTitle.Font =
    Enum.Font.GothamBold


HeaderTitle.TextXAlignment =
    Enum.TextXAlignment.Left


HeaderTitle.Parent =
    Header


local Close =
    Instance.new(
        "TextButton"
    )


Close.AnchorPoint =
    Vector2.new(
        1,
        0
    )


Close.Position =
    UDim2.new(
        1,
        -6,
        0,
        5
    )


Close.Size =
    UDim2.fromOffset(
        22,
        21
    )


Close.BackgroundColor3 =
    Color3.fromRGB(
        28,
        28,
        33
    )


Close.BorderSizePixel = 0


Close.Text =
    "×"


Close.TextColor3 =
    Color3.fromRGB(
        190,
        190,
        195
    )


Close.TextSize = 14


Close.Font =
    Enum.Font.GothamBold


Close.Parent =
    Header


local CloseCorner =
    Instance.new(
        "UICorner",
        Close
    )


CloseCorner.CornerRadius =
    UDim.new(
        0,
        5
    )


--==============================================================
-- TABS
--==============================================================

local Tabs =
    Instance.new(
        "Frame"
    )


Tabs.Position =
    UDim2.fromOffset(
        7,
        32
    )


Tabs.Size =
    UDim2.new(
        1,
        -14,
        0,
        31
    )


Tabs.BackgroundTransparency = 1


Tabs.Parent =
    Panel


local function createTab(
    text,
    xScale
)

    local button =
        Instance.new(
            "TextButton"
        )


    button.Position =
        UDim2.new(
            xScale,
            xScale == 0
                and 0
                or 3,
            0,
            0
        )


    button.Size =
        UDim2.new(
            0.5,
            -3,
            1,
            0
        )


    button.BackgroundColor3 =
        Color3.fromRGB(
            29,
            29,
            34
        )


    button.BorderSizePixel = 0


    button.Text =
        text


    button.TextColor3 =
        Color3.fromRGB(
            160,
            160,
            166
        )


    button.TextSize = 10


    button.Font =
        Enum.Font.GothamBold


    button.AutoButtonColor =
        false


    button.Parent =
        Tabs


    local corner =
        Instance.new(
            "UICorner",
            button
        )


    corner.CornerRadius =
        UDim.new(
            0,
            6
        )


    return button
end


local ItemsTab =
    createTab(
        "ITENS",
        0
    )


local PlayersTab =
    createTab(
        "PLAYERS",
        0.5
    )


--==============================================================
-- CONTROL ROW
--==============================================================

local Control =
    Instance.new(
        "Frame"
    )


Control.Position =
    UDim2.fromOffset(
        7,
        68
    )


Control.Size =
    UDim2.new(
        1,
        -14,
        0,
        30
    )


Control.BackgroundTransparency = 1


Control.Parent =
    Panel


local ESPButton =
    Instance.new(
        "TextButton"
    )


ESPButton.Size =
    UDim2.new(
        1,
        0,
        1,
        0
    )


ESPButton.BackgroundColor3 =
    Color3.fromRGB(
        27,
        27,
        32
    )


ESPButton.BorderSizePixel =
    0


ESPButton.Text =
    "ESP DE ITENS  •  OFF"


ESPButton.TextColor3 =
    Color3.fromRGB(
        155,
        155,
        160
    )


ESPButton.TextSize = 10


ESPButton.Font =
    Enum.Font.GothamMedium


ESPButton.AutoButtonColor =
    false


ESPButton.Parent =
    Control


local ESPCorner =
    Instance.new(
        "UICorner",
        ESPButton
    )


ESPCorner.CornerRadius =
    UDim.new(
        0,
        6
    )


--==============================================================
-- LIST
--==============================================================

local Scroll =
    Instance.new(
        "ScrollingFrame"
    )


Scroll.Position =
    UDim2.fromOffset(
        7,
        103
    )


Scroll.Size =
    UDim2.new(
        1,
        -14,
        1,
        -110
    )


Scroll.BackgroundColor3 =
    Color3.fromRGB(
        20,
        20,
        25
    )


Scroll.BorderSizePixel = 0


Scroll.ScrollBarThickness = 2


Scroll.ScrollBarImageTransparency =
    0.35


Scroll.CanvasSize =
    UDim2.new()


Scroll.Parent =
    Panel


local ScrollCorner =
    Instance.new(
        "UICorner",
        Scroll
    )


ScrollCorner.CornerRadius =
    UDim.new(
        0,
        7
    )


local Layout =
    Instance.new(
        "UIListLayout"
    )


Layout.Padding =
    UDim.new(
        0,
        3
    )


Layout.SortOrder =
    Enum.SortOrder.LayoutOrder


Layout.Parent =
    Scroll


local ListPadding =
    Instance.new(
        "UIPadding"
    )


ListPadding.PaddingTop =
    UDim.new(
        0,
        4
    )


ListPadding.PaddingBottom =
    UDim.new(
        0,
        4
    )


ListPadding.PaddingLeft =
    UDim.new(
        0,
        4
    )


ListPadding.PaddingRight =
    UDim.new(
        0,
        4
    )


ListPadding.Parent =
    Scroll


--==============================================================
-- ROW POOL
--==============================================================

for index = 1,
    CONFIG.MAX_LIST_ROWS do

    local button =
        Instance.new(
            "TextButton"
        )


    button.Name =
        "Row" ..
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
            29,
            29,
            35
        )


    button.BorderSizePixel = 0


    button.Text = ""


    button.TextColor3 =
        Color3.fromRGB(
            230,
            230,
            234
        )


    button.TextSize = 10


    button.Font =
        Enum.Font.GothamMedium


    button.TextXAlignment =
        Enum.TextXAlignment.Left


    button.AutoButtonColor =
        false


    button.Visible =
        false


    button.Parent =
        Scroll


    local corner =
        Instance.new(
            "UICorner",
            button
        )


    corner.CornerRadius =
        UDim.new(
            0,
            5
        )


    local padding =
        Instance.new(
            "UIPadding",
            button
        )


    padding.PaddingLeft =
        UDim.new(
            0,
            8
        )


    RowPool[index] = {

        Button = button,

        Entry = nil,
    }


    button.Activated:Connect(
        function()

            local slot =
                RowPool[index]


            if not slot
            or not slot.Entry then

                return
            end


            local entry =
                slot.Entry


            if entry.Type ==
                "ITEM" then

                teleportToItem(
                    entry.Object
                )


            elseif entry.Type ==
                "CHAIN" then

                teleportToChain(
                    entry.Object
                )


            elseif entry.Type ==
                "PLAYER" then

                teleportToPlayer(
                    entry.Object
                )
            end
        end
    )
end


--==============================================================
-- TAB VISUAL
--==============================================================

local function updateTabVisual()

    local itemsActive =
        State.CurrentPage ==
        "ITEMS"


    ItemsTab.BackgroundColor3 =
        itemsActive
        and Color3.fromRGB(
            44,
            39,
            30
        )
        or Color3.fromRGB(
            29,
            29,
            34
        )


    PlayersTab.BackgroundColor3 =
        not itemsActive
        and Color3.fromRGB(
            44,
            39,
            30
        )
        or Color3.fromRGB(
            29,
            29,
            34
        )


    ItemsTab.TextColor3 =
        itemsActive
        and Color3.fromRGB(
            245,
            225,
            180
        )
        or Color3.fromRGB(
            155,
            155,
            160
        )


    PlayersTab.TextColor3 =
        not itemsActive
        and Color3.fromRGB(
            245,
            225,
            180
        )
        or Color3.fromRGB(
            155,
            155,
            160
        )


    ----------------------------------------------------------
    -- ESP só existe para página de itens.
    ----------------------------------------------------------

    Control.Visible =
        itemsActive


    if itemsActive then

        Scroll.Position =
            UDim2.fromOffset(
                7,
                103
            )


        Scroll.Size =
            UDim2.new(
                1,
                -14,
                1,
                -110
            )

    else

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
    end
end


--==============================================================
-- LIST REFRESH
--==============================================================

local function refreshList()

    local rows


    if State.CurrentPage ==
        "ITEMS" then

        rows =
            getSortedItems()

    else

        rows =
            getPlayerDestinations()
    end


    CurrentRows =
        rows


    for index = 1,
        CONFIG.MAX_LIST_ROWS do

        local slot =
            RowPool[index]


        local entry =
            rows[index]


        if entry then

            slot.Entry =
                entry


            slot.Button.Visible =
                true


            --------------------------------------------------
            -- SEM DISTÂNCIA NAS DUAS LISTAS.
            --------------------------------------------------

            if entry.Type ==
                "CHAIN" then

                slot.Button.Text =
                    "⚠  CHAIN"


                slot.Button.TextColor3 =
                    Color3.fromRGB(
                        245,
                        205,
                        120
                    )


                slot.Button.Font =
                    Enum.Font.GothamBold


                slot.Button.BackgroundColor3 =
                    Color3.fromRGB(
                        44,
                        37,
                        29
                    )


            elseif entry.Type ==
                "PLAYER" then

                if entry.Username
                and entry.Username
                    ~= entry.Name then

                    slot.Button.Text =
                        entry.Name
                        ..
                        "  @"
                        ..
                        entry.Username

                else

                    slot.Button.Text =
                        entry.Name
                end


                slot.Button.TextColor3 =
                    Color3.fromRGB(
                        230,
                        230,
                        234
                    )


                slot.Button.Font =
                    Enum.Font.GothamMedium


                slot.Button.BackgroundColor3 =
                    Color3.fromRGB(
                        29,
                        29,
                        35
                    )


            else

                slot.Button.Text =
                    entry.Name


                slot.Button.TextColor3 =
                    Color3.fromRGB(
                        230,
                        230,
                        234
                    )


                slot.Button.Font =
                    Enum.Font.GothamMedium


                slot.Button.BackgroundColor3 =
                    Color3.fromRGB(
                        29,
                        29,
                        35
                    )
            end


        else

            slot.Entry = nil

            slot.Button.Visible =
                false
        end
    end


    local visible =
        math.min(
            #rows,
            CONFIG.MAX_LIST_ROWS
        )


    Scroll.CanvasSize =
        UDim2.new(
            0,
            0,
            0,
            visible * 34 + 8
        )


    if State.CurrentPage ==
        "ITEMS" then

        HeaderTitle.Text =
            "ITENS • "
            ..
            tostring(
                #rows
            )

    else

        HeaderTitle.Text =
            "PLAYERS • "
            ..
            tostring(
                #rows
            )
    end
end


ItemsTab.Activated:Connect(
    function()

        State.CurrentPage =
            "ITEMS"

        updateTabVisual()

        refreshList()
    end
)


PlayersTab.Activated:Connect(
    function()

        State.CurrentPage =
            "PLAYERS"

        updateTabVisual()

        refreshList()
    end
)


--==============================================================
-- ESP
--==============================================================

local function createVisual(
    item
)

    if Visuals[item]
    or not item
    or not item.Parent then

        return
    end


    local part =
        getPart(item)


    if not part then
        return
    end


    local Highlight =
        Instance.new(
            "Highlight"
        )


    Highlight.Name =
        "CafeinaItemHighlight"


    Highlight.Adornee =
        item


    Highlight.FillColor =
        Color3.fromRGB(
            220,
            185,
            90
        )


    Highlight.FillTransparency =
        0.84


    Highlight.OutlineColor =
        Color3.fromRGB(
            255,
            245,
            210
        )


    Highlight.OutlineTransparency =
        0.08


    Highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop


    Highlight.Parent =
        GUI


    local Billboard =
        Instance.new(
            "BillboardGui"
        )


    Billboard.Name =
        "CafeinaItemLabel"


    Billboard.Adornee =
        part


    Billboard.Size =
        UDim2.fromOffset(
            130,
            32
        )


    Billboard.StudsOffset =
        Vector3.new(
            0,
            2.3,
            0
        )


    Billboard.AlwaysOnTop =
        true


    Billboard.Parent =
        GUI


    local Label =
        Instance.new(
            "TextLabel"
        )


    Label.Size =
        UDim2.fromScale(
            1,
            1
        )


    Label.BackgroundTransparency =
        1


    Label.TextColor3 =
        Color3.fromRGB(
            255,
            250,
            235
        )


    Label.TextStrokeColor3 =
        Color3.new(
            0,
            0,
            0
        )


    Label.TextStrokeTransparency =
        0.20


    Label.TextSize =
        10


    Label.Font =
        Enum.Font.GothamBold


    Label.Parent =
        Billboard


    Visuals[item] = {

        Highlight =
            Highlight,

        Billboard =
            Billboard,

        Label =
            Label,

        Part =
            part,
    }
end


local function clearESP()

    local list = {}


    for obj in pairs(
        Visuals
    ) do

        table.insert(
            list,
            obj
        )
    end


    for _, obj in ipairs(
        list
    ) do

        destroyVisual(
            obj
        )
    end
end


local function refreshESP()

    if not State.ESP then
        return
    end


    local items =
        getSortedItems()


    local allowed = {}


    local count = 0


    for _, entry in ipairs(
        items
    ) do

        if count >=
            CONFIG.MAX_ACTIVE_ESP then

            break
        end


        if entry.Distance <=
            CONFIG.ESP_MAX_DISTANCE then

            allowed[
                entry.Object
            ] = entry


            count += 1
        end
    end


    ----------------------------------------------------------
    -- Remove ESP que saiu do grupo ativo.
    ----------------------------------------------------------

    local remove = {}


    for obj in pairs(
        Visuals
    ) do

        if not allowed[obj] then

            table.insert(
                remove,
                obj
            )
        end
    end


    for _, obj in ipairs(
        remove
    ) do

        destroyVisual(
            obj
        )
    end


    ----------------------------------------------------------
    -- Atualiza ativos.
    ----------------------------------------------------------

    for obj, entry in pairs(
        allowed
    ) do

        if not Visuals[obj] then

            createVisual(
                obj
            )
        end


        local visual =
            Visuals[obj]


        if visual then

            local currentPart =
                getPart(obj)


            if currentPart
            and currentPart
                ~= visual.Part then

                visual.Part =
                    currentPart


                visual.Billboard.Adornee =
                    currentPart
            end


            --------------------------------------------------
            -- BearTrap: SEM DISTÂNCIA.
            --------------------------------------------------

            if isBearTrap(
                obj
            ) then

                visual.Label.Text =
                    entry.Name

            else

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
-- ESP BUTTON
--==============================================================

local function updateESPButton()

    if State.ESP then

        ESPButton.Text =
            "ESP DE ITENS  •  ON"


        ESPButton.TextColor3 =
            Color3.fromRGB(
                245,
                225,
                180
            )


        ESPButton.BackgroundColor3 =
            Color3.fromRGB(
                44,
                39,
                30
            )

    else

        ESPButton.Text =
            "ESP DE ITENS  •  OFF"


        ESPButton.TextColor3 =
            Color3.fromRGB(
                155,
                155,
                160
            )


        ESPButton.BackgroundColor3 =
            Color3.fromRGB(
                27,
                27,
                32
            )
    end
end


ESPButton.Activated:Connect(
    function()

        State.ESP =
            not State.ESP


        updateESPButton()


        if State.ESP then

            refreshESP()

        else

            clearESP()
        end
    end
)


--==============================================================
-- OPEN / CLOSE
--==============================================================

local function setMenuOpen(
    open
)

    State.MenuOpen =
        open


    Panel.Visible =
        open


    if open then

        refreshList()
    end
end


OpenButton.Activated:Connect(
    function()

        setMenuOpen(
            not State.MenuOpen
        )
    end
)


Close.Activated:Connect(
    function()

        setMenuOpen(
            false
        )
    end
)


--==============================================================
-- MOBILE DRAG
--==============================================================

local Dragging = false

local DragStart = nil

local StartPosition = nil

local DragInput = nil


local function updatePanelFromButton()

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


OpenButton.InputBegan:Connect(
    function(input)

        if input.UserInputType
            ==
            Enum.UserInputType.Touch

        or input.UserInputType
            ==
            Enum.UserInputType.MouseButton1 then

            Dragging = true

            DragStart =
                input.Position

            StartPosition =
                OpenButton.Position


            input.Changed:Connect(
                function()

                    if input.UserInputState
                        ==
                        Enum.UserInputState.End then

                        Dragging =
                            false
                    end
                end
            )
        end
    end
)


OpenButton.InputChanged:Connect(
    function(input)

        if input.UserInputType
            ==
            Enum.UserInputType.Touch

        or input.UserInputType
            ==
            Enum.UserInputType.MouseMovement then

            DragInput =
                input
        end
    end
)


UserInputService.InputChanged:Connect(
    function(input)

        if not Dragging
        or input ~= DragInput
        or not DragStart
        or not StartPosition then

            return
        end


        local delta =
            input.Position
            -
            DragStart


        OpenButton.Position =
            UDim2.new(
                StartPosition.X.Scale,

                StartPosition.X.Offset
                    +
                    delta.X,

                StartPosition.Y.Scale,

                StartPosition.Y.Offset
                    +
                    delta.Y
            )


        updatePanelFromButton()
    end
)


--==============================================================
-- WORLD EVENTS
--==============================================================

table.insert(
    Connections,

    Workspace.DescendantAdded:Connect(
        function(obj)

            queueCandidate(
                obj
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
-- PLAYER / INVENTORY EVENTS
--==============================================================

table.insert(
    Connections,

    Backpack.ChildAdded:Connect(
        function(obj)

            if obj:IsA("Tool") then

                addKnownItemName(
                    obj.Name
                )
            end
        end
    )
)


table.insert(
    Connections,

    LocalPlayer.CharacterAdded:Connect(
        function()

            task.wait(0.8)

            discoverOwnedTools()
        end
    )
)


table.insert(
    Connections,

    Players.PlayerAdded:Connect(
        function()

            if State.MenuOpen
            and State.CurrentPage
                ==
                "PLAYERS" then

                task.delay(
                    0.5,
                    refreshList
                )
            end
        end
    )
)


table.insert(
    Connections,

    Players.PlayerRemoving:Connect(
        function()

            if State.MenuOpen
            and State.CurrentPage
                ==
                "PLAYERS" then

                task.defer(
                    refreshList
                )
            end
        end
    )
)


--==============================================================
-- UI UPDATE LOOP
--==============================================================

task.spawn(function()

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
            CONFIG.UI_REFRESH_INTERVAL
        )
    end
end)


--==============================================================
-- ESP LOOP
--==============================================================

task.spawn(function()

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
            CONFIG.ESP_REFRESH_INTERVAL
        )
    end
end)


--==============================================================
-- RECOVERY SCAN
--==============================================================

task.spawn(function()

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
end)


--==============================================================
-- INITIALIZATION
--==============================================================

updateESPButton()

updateTabVisual()


task.spawn(function()

    refreshKnownItems()

    scanWorld()

    refreshList()
end)


print(
    "[CAFEÍNA] "
    ..
    CONFIG.VERSION
    ..
    " carregado."
)


print(
    "[CAFEÍNA] ESP DE ITENS: OFF"
)
