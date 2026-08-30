--==============================================================--
-- CAFEÍNA • COMPACT UTILITY V2
-- Mobile / Executor / Client-side
--
-- • PEGAR SUCATA
-- • IR PARA LOJA
-- • TELEPORTAR AO CHAIN
-- • FUGIR DO CHAIN
--
-- Otimizado para:
-- • Workspace.Misc.Zones.LootingItems.Scrap
-- • Workspace.Misc.NPCS.SHOPKEEPER
-- • Workspace.Misc.AI.CHAIN
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    GUI_NAME = "CafeinaCompactUtilityV2",

    ITEM_OFFSET = 3.4,
    INTERACT_WAIT = 0.18,

    -- distância ao teleportar perto do Chain
    CHAIN_TELEPORT_DISTANCE = 7,

    -- ~20 metros usando aproximação de 3.5 studs por metro
    CHAIN_ESCAPE_TRIGGER = 70,

    -- destinos já ficam além do limite de alerta
    ESCAPE_DISTANCES = {
        95,
        120,
        145,
    },

    SHOP_SEARCH_RADIUS = {
        5,
        7,
        10,
        13,
    },

    CHAIN_UPDATE_RATE = 0.35,
    CHAIN_DEEP_SCAN_RATE = 3,

    -- evita escolher imediatamente a mesma sucata
    SCRAP_RETRY_DELAY = 8,
}

--==============================================================--
-- CORES
--==============================================================--

local BLACK = Color3.fromRGB(7, 7, 8)
local PANEL = Color3.fromRGB(14, 14, 16)
local BUTTON = Color3.fromRGB(22, 22, 25)
local BORDER = Color3.fromRGB(43, 43, 47)

local TEXT = Color3.fromRGB(245, 245, 247)
local MUTED = Color3.fromRGB(150, 150, 157)

local RED_OFF = Color3.fromRGB(66, 21, 24)
local RED_ON = Color3.fromRGB(205, 37, 47)

local GREEN_OFF = Color3.fromRGB(22, 70, 39)
local GREEN_ON = Color3.fromRGB(40, 176, 82)

--==============================================================--
-- ESTADO
--==============================================================--

local Busy = false
local GuiAlive = true

local ChainAvailable = false
local ChainCloseEnough = false

local ChainCache = nil
local LastChainDeepScan = 0

-- sucatas sem estado Available são descartadas após uso
local ProcessedScraps = setmetatable({}, {
    __mode = "k"
})

-- sucatas com Available ganham apenas cooldown curto
local ScrapSkipUntil = setmetatable({}, {
    __mode = "k"
})

--==============================================================--
-- PERSONAGEM
--==============================================================--

local function getCharacter()

    local character = LocalPlayer.Character

    if not character then
        return nil, nil, nil
    end

    local root =
        character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    return character, root, humanoid
end

local function getBackpack()

    return LocalPlayer:FindFirstChildOfClass("Backpack")
        or LocalPlayer:FindFirstChild("Backpack")
end

--==============================================================--
-- UTIL
--==============================================================--

local function normalize(value)
    return string.lower(tostring(value or ""))
end

local function getBasePart(object)

    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object
    end

    if object:IsA("Tool") then

        return object:FindFirstChild("Handle")
            or object:FindFirstChildWhichIsA(
                "BasePart",
                true
            )
    end

    if object:IsA("Model") then

        return object:FindFirstChild("HumanoidRootPart")
            or object:FindFirstChild("UpperTorso")
            or object:FindFirstChild("Torso")
            or object.PrimaryPart
            or object:FindFirstChildWhichIsA(
                "BasePart",
                true
            )
    end

    local current = object.Parent

    while current and current ~= Workspace do

        if current:IsA("BasePart") then
            return current
        end

        if current:IsA("Model") then

            local part =
                current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChild("UpperTorso")
                or current:FindFirstChild("Torso")
                or current.PrimaryPart

            if part then
                return part
            end
        end

        current = current.Parent
    end

    return object:FindFirstChildWhichIsA(
        "BasePart",
        true
    )
end

--==============================================================--
-- CAMINHOS CONHECIDOS
--==============================================================--

local function getMisc()

    return Workspace:FindFirstChild("Misc")
end

local function getDirectScrapFolder()

    local misc = getMisc()
    if not misc then
        return nil
    end

    local zones = misc:FindFirstChild("Zones")
    if not zones then
        return nil
    end

    local looting =
        zones:FindFirstChild("LootingItems")

    if not looting then
        return nil
    end

    return looting:FindFirstChild("Scrap")
        or looting:FindFirstChild("SCRAP")
end

local function getDirectShopkeeper()

    local misc = getMisc()
    if not misc then
        return nil
    end

    local npcs =
        misc:FindFirstChild("NPCS")
        or misc:FindFirstChild("NPCs")

    if not npcs then
        return nil
    end

    return npcs:FindFirstChild("SHOPKEEPER")
        or npcs:FindFirstChild("Shopkeeper")
end

local function getDirectChain()

    local misc = getMisc()
    if not misc then
        return nil
    end

    local ai =
        misc:FindFirstChild("AI")

    if not ai then
        return nil
    end

    return ai:FindFirstChild("CHAIN")
        or ai:FindFirstChild("Chain")
        or ai:FindFirstChild("CHEN")
        or ai:FindFirstChild("Chen")
end

--==============================================================--
-- ESPAÇO SEGURO
--==============================================================--

local function isPositionClear(position, character)

    local params = OverlapParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character
    }

    local ok, parts = pcall(function()

        return Workspace:GetPartBoundsInBox(
            CFrame.new(
                position + Vector3.new(0, 2.7, 0)
            ),
            Vector3.new(3.7, 5.3, 3.7),
            params
        )
    end)

    if not ok then
        return true
    end

    for _, part in ipairs(parts) do

        if part
        and part.Parent
        and part.CanCollide then

            return false
        end
    end

    return true
end

local function groundAt(
    horizontalPosition,
    character,
    referenceY
)

    referenceY =
        referenceY
        or horizontalPosition.Y

    local params = RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character
    }

    params.IgnoreWater = false

    local origin =
        Vector3.new(
            horizontalPosition.X,
            referenceY + 18,
            horizontalPosition.Z
        )

    local result =
        Workspace:Raycast(
            origin,
            Vector3.new(0, -90, 0),
            params
        )

    if not result then
        return nil
    end

    if not result.Instance
    or not result.Instance.CanCollide then
        return nil
    end

    -- evita paredes / superfícies muito inclinadas
    if result.Normal.Y < 0.58 then
        return nil
    end

    local position =
        result.Position
        + Vector3.new(
            0,
            CONFIG.ITEM_OFFSET,
            0
        )

    if not isPositionClear(
        position,
        character
    ) then
        return nil
    end

    return position
end

--==============================================================--
-- TELEPORTE
--==============================================================--

local function teleportCharacter(
    position,
    lookPosition
)

    local character, root =
        getCharacter()

    if not character or not root then
        return false
    end

    local destination

    if lookPosition then

        local look =
            Vector3.new(
                lookPosition.X,
                position.Y,
                lookPosition.Z
            )

        if (look - position).Magnitude > 0.1 then

            destination =
                CFrame.lookAt(
                    position,
                    look
                )

        else
            destination =
                CFrame.new(position)
        end

    else

        destination =
            CFrame.new(position)
    end

    local success =
        pcall(function()
            character:PivotTo(destination)
        end)

    if not success then

        success =
            pcall(function()
                root.CFrame = destination
            end)
    end

    if not success then
        return false
    end

    pcall(function()

        root.AssemblyLinearVelocity =
            Vector3.zero

        root.AssemblyAngularVelocity =
            Vector3.zero
    end)

    return true
end

--==============================================================--
-- SUCATA
--==============================================================--

local SCRAP_WORDS = {
    "scrap",
    "sucata",
    "metal scrap",
    "scrap metal",
}

local function hasScrapWord(text)

    text = normalize(text)

    for _, word in ipairs(SCRAP_WORDS) do

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

local function getScrapContainer(object)

    local current = object

    for _ = 1, 7 do

        if not current then
            break
        end

        local scrapAttribute = nil

        pcall(function()
            scrapAttribute =
                current:GetAttribute("Scrap")
        end)

        if scrapAttribute == true
        or hasScrapWord(current.Name) then

            return current
        end

        current = current.Parent
    end

    return object
end

local function isScrap(object)

    if not object then
        return false
    end

    local current = object

    for _ = 1, 7 do

        if not current then
            break
        end

        local scrapAttribute

        pcall(function()
            scrapAttribute =
                current:GetAttribute("Scrap")
        end)

        if scrapAttribute == true then
            return true
        end

        if hasScrapWord(current.Name) then
            return true
        end

        current = current.Parent
    end

    return false
end

local function getScrapAvailability(container)

    if not container
    or not container.Parent then

        return false, false
    end

    ------------------------------------------------------------
    -- Cooldown
    ------------------------------------------------------------

    local cooldown

    pcall(function()
        cooldown =
            container:GetAttribute("Cooldown")
    end)

    if cooldown == true then
        return false, true
    end

    ------------------------------------------------------------
    -- Values.Available
    ------------------------------------------------------------

    local values =
        container:FindFirstChild("Values")

    local available =
        values
        and values:FindFirstChild("Available")

    if not available then

        available =
            container:FindFirstChild(
                "Available",
                true
            )
    end

    if available
    and available:IsA("BoolValue") then

        return available.Value, true
    end

    ------------------------------------------------------------
    -- atributo Available
    ------------------------------------------------------------

    local attribute

    pcall(function()
        attribute =
            container:GetAttribute("Available")
    end)

    if attribute ~= nil then
        return attribute == true, true
    end

    return true, false
end

local function scrapReady(object)

    if not object
    or not object.Parent then
        return false, nil
    end

    local container =
        getScrapContainer(object)

    if ProcessedScraps[container] then
        return false, container
    end

    local skip =
        ScrapSkipUntil[container]

    if skip and os.clock() < skip then
        return false, container
    end

    local available =
        getScrapAvailability(container)

    if not available then
        return false, container
    end

    return true, container
end

local function markScrapUsed(object)

    if not object then
        return
    end

    local container =
        getScrapContainer(object)

    local _, authoritative =
        getScrapAvailability(container)

    ScrapSkipUntil[container] =
        os.clock()
        + CONFIG.SCRAP_RETRY_DELAY

    -- Sem Available/Cooldown confiável:
    -- nunca volta para esse mesmo objeto na sessão.
    if not authoritative then
        ProcessedScraps[container] = true
    end
end

local function scanScrapRoot(searchRoot)

    if not searchRoot then
        return nil
    end

    local _, playerRoot =
        getCharacter()

    local descendants

    local ok =
        pcall(function()
            descendants =
                searchRoot:GetDescendants()
        end)

    if not ok or not descendants then
        return nil
    end

    local bestObject = nil
    local bestDistance = math.huge

    local checkedContainers = {}

    for _, object in ipairs(descendants) do

        local validType =
            object:IsA("Tool")
            or object:IsA("ProximityPrompt")
            or object:IsA("ClickDetector")

        if validType
        and isScrap(object) then

            local ready, container =
                scrapReady(object)

            if ready
            and not checkedContainers[container] then

                checkedContainers[container] = true

                local part =
                    getBasePart(object)

                if part then

                    local distance = 0

                    if playerRoot then

                        distance =
                            (
                                playerRoot.Position
                                - part.Position
                            ).Magnitude
                    end

                    -- pequena preferência para Prompt
                    if object:IsA("ProximityPrompt") then
                        distance -= 2
                    end

                    if distance < bestDistance then

                        bestDistance = distance
                        bestObject = object
                    end
                end
            end
        end
    end

    return bestObject
end

local function findScrap()

    ------------------------------------------------------------
    -- PRIMEIRO: pasta real conhecida
    ------------------------------------------------------------

    local scrapFolder =
        getDirectScrapFolder()

    if scrapFolder then

        local found =
            scanScrapRoot(scrapFolder)

        if found then
            return found
        end
    end

    ------------------------------------------------------------
    -- FALLBACK GLOBAL
    -- Só acontece quando o jogador toca no botão.
    ------------------------------------------------------------

    return scanScrapRoot(Workspace)
end

--==============================================================--
-- MOVIMENTO PARA INTERAÇÃO
--==============================================================--

local function moveNearObject(object)

    local character =
        LocalPlayer.Character

    if not character then
        return false
    end

    local part =
        getBasePart(object)

    if not part then
        return false
    end

    local offsets = {
        Vector3.new(0, 0, 0),
        Vector3.new(2.5, 0, 0),
        Vector3.new(-2.5, 0, 0),
        Vector3.new(0, 0, 2.5),
        Vector3.new(0, 0, -2.5),
    }

    for _, offset in ipairs(offsets) do

        local test =
            part.Position + offset

        local safe =
            groundAt(
                test,
                character,
                part.Position.Y
            )

        if safe then

            return teleportCharacter(
                safe,
                part.Position
            )
        end
    end

    return teleportCharacter(
        part.Position
            + Vector3.new(0, 3.8, 0),
        part.Position
    )
end

--==============================================================--
-- COLETAR
--==============================================================--

local function toolOwned(tool)

    if not tool then
        return false
    end

    local backpack = getBackpack()
    local character = LocalPlayer.Character

    if backpack
    and tool:IsDescendantOf(backpack) then

        return true
    end

    if character
    and tool:IsDescendantOf(character) then

        return true
    end

    return false
end

local function collectObject(object)

    if not object
    or not object.Parent then

        return false, "Sucata não existe mais"
    end

    ------------------------------------------------------------
    -- TOOL
    ------------------------------------------------------------

    if object:IsA("Tool") then

        if toolOwned(object) then

            return true, "Sucata já coletada"
        end

        local handle =
            getBasePart(object)

        if not handle then

            return false, "Sucata sem Handle"
        end

        if not moveNearObject(object) then

            return false, "Não consegui chegar na sucata"
        end

        task.wait(0.06)

        local _, root =
            getCharacter()

        if not root then

            return false, "Personagem indisponível"
        end

        if typeof(firetouchinterest)
            == "function" then

            pcall(function()

                firetouchinterest(
                    root,
                    handle,
                    0
                )

                task.wait(0.035)

                firetouchinterest(
                    root,
                    handle,
                    1
                )
            end)
        end

        task.wait(CONFIG.INTERACT_WAIT)

        if toolOwned(object) then

            return true, "Sucata coletada"
        end

        return true, "Interação enviada"
    end

    ------------------------------------------------------------
    -- PROXIMITY PROMPT
    ------------------------------------------------------------

    if object:IsA("ProximityPrompt") then

        if not moveNearObject(object) then

            return false, "Não consegui chegar na sucata"
        end

        task.wait(0.06)

        if typeof(fireproximityprompt)
            ~= "function" then

            return false,
                "Executor sem fireproximityprompt"
        end

        local success =
            pcall(function()

                fireproximityprompt(object)
            end)

        task.wait(CONFIG.INTERACT_WAIT)

        return success,
            success
            and "Sucata coletada"
            or "Falha no Prompt"
    end

    ------------------------------------------------------------
    -- CLICK DETECTOR
    ------------------------------------------------------------

    if object:IsA("ClickDetector") then

        if not moveNearObject(object) then

            return false, "Não consegui chegar na sucata"
        end

        task.wait(0.06)

        if typeof(fireclickdetector)
            ~= "function" then

            return false,
                "Executor sem fireclickdetector"
        end

        local success =
            pcall(function()

                fireclickdetector(object)
            end)

        task.wait(CONFIG.INTERACT_WAIT)

        return success,
            success
            and "Sucata coletada"
            or "Falha no ClickDetector"
    end

    return false, "Tipo incompatível"
end

--==============================================================--
-- LOJA
--==============================================================--

local SHOP_WORDS = {
    "shop",
    "store",
    "loja",
    "vendor",
    "merchant",
    "trader",
    "buy",
    "purchase",
    "comprar",
}

local function containsShopWord(text)

    text = normalize(text)

    for _, word in ipairs(SHOP_WORDS) do

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

local function getShopText(object)

    local pieces = {
        object.Name
    }

    if object:IsA("ProximityPrompt") then

        pieces[#pieces + 1] =
            object.ActionText or ""

        pieces[#pieces + 1] =
            object.ObjectText or ""
    end

    local parent = object.Parent

    for _ = 1, 5 do

        if not parent then
            break
        end

        pieces[#pieces + 1] =
            parent.Name

        parent = parent.Parent
    end

    return table.concat(
        pieces,
        " "
    )
end

local function findShopTarget()

    ------------------------------------------------------------
    -- PRIMEIRO: SHOPKEEPER conhecido
    ------------------------------------------------------------

    local shopkeeper =
        getDirectShopkeeper()

    if shopkeeper then

        local prompt =
            shopkeeper:FindFirstChildWhichIsA(
                "ProximityPrompt",
                true
            )

        if prompt then

            local part =
                getBasePart(prompt)

            if part then

                return {
                    Object = prompt,
                    Part = part,
                }
            end
        end

        local part =
            getBasePart(shopkeeper)

        if part then

            return {
                Object = shopkeeper,
                Part = part,
            }
        end
    end

    ------------------------------------------------------------
    -- FALLBACK
    ------------------------------------------------------------

    local descendants

    local ok =
        pcall(function()

            descendants =
                Workspace:GetDescendants()
        end)

    if not ok then
        return nil
    end

    local _, root =
        getCharacter()

    local best
    local bestScore = -math.huge

    for _, object in ipairs(descendants) do

        if object:IsA("ProximityPrompt")
        or object:IsA("ClickDetector") then

            local text =
                getShopText(object)

            if containsShopWord(text) then

                local part =
                    getBasePart(object)

                if part then

                    local score =
                        object:IsA("ProximityPrompt")
                        and 100
                        or 50

                    if root then

                        local distance =
                            (
                                root.Position
                                - part.Position
                            ).Magnitude

                        score -= math.min(
                            distance / 200,
                            30
                        )
                    end

                    if score > bestScore then

                        bestScore = score

                        best = {
                            Object = object,
                            Part = part,
                        }
                    end
                end
            end
        end
    end

    return best
end

local function teleportToShop()

    local character =
        LocalPlayer.Character

    if not character then

        return false,
            "Personagem não carregado"
    end

    local shop =
        findShopTarget()

    if not shop
    or not shop.Part
    or not shop.Part.Parent then

        return false,
            "Loja não encontrada"
    end

    local center =
        shop.Part.Position

    local candidates = {}

    for _, radius
    in ipairs(CONFIG.SHOP_SEARCH_RADIUS) do

        candidates[#candidates + 1] =
            Vector3.new(radius, 0, 0)

        candidates[#candidates + 1] =
            Vector3.new(-radius, 0, 0)

        candidates[#candidates + 1] =
            Vector3.new(0, 0, radius)

        candidates[#candidates + 1] =
            Vector3.new(0, 0, -radius)

        candidates[#candidates + 1] =
            Vector3.new(radius, 0, radius)

        candidates[#candidates + 1] =
            Vector3.new(-radius, 0, radius)

        candidates[#candidates + 1] =
            Vector3.new(radius, 0, -radius)

        candidates[#candidates + 1] =
            Vector3.new(-radius, 0, -radius)
    end

    for _, offset in ipairs(candidates) do

        local safe =
            groundAt(
                center + offset,
                character,
                center.Y
            )

        if safe then

            if teleportCharacter(
                safe,
                center
            ) then

                return true,
                    "Teleportado para loja"
            end
        end
    end

    return false,
        "Sem chão seguro perto da loja"
end

--==============================================================--
-- CHAIN
--==============================================================--

local CHAIN_NAMES = {
    "chain",
    "chen",
}

local function matchesChainName(name)

    name = normalize(name)

    for _, word in ipairs(CHAIN_NAMES) do

        if name == word
        or string.find(
            name,
            word,
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function makeChainResult(object)

    if not object
    or not object.Parent then
        return nil
    end

    local root =
        getBasePart(object)

    if not root then
        return nil
    end

    return {
        Character = object,
        Root = root,
        Name = object.Name,
    }
end

local function findChain()

    ------------------------------------------------------------
    -- CAMINHO DIRETO
    ------------------------------------------------------------

    local direct =
        getDirectChain()

    if direct then

        ChainCache = direct

        local result =
            makeChainResult(direct)

        if result then
            return result
        end
    end

    ------------------------------------------------------------
    -- PLAYER
    ------------------------------------------------------------

    for _, player
    in ipairs(Players:GetPlayers()) do

        if player ~= LocalPlayer
        and (
            matchesChainName(player.Name)
            or matchesChainName(
                player.DisplayName
            )
        ) then

            local character =
                player.Character

            local root =
                getBasePart(character)

            if root then

                return {
                    Character = character,
                    Root = root,
                    Name =
                        player.DisplayName
                        or player.Name,
                }
            end
        end
    end

    ------------------------------------------------------------
    -- CACHE
    ------------------------------------------------------------

    if ChainCache
    and ChainCache.Parent then

        local result =
            makeChainResult(ChainCache)

        if result then
            return result
        end
    end

    ------------------------------------------------------------
    -- DEEP SCAN LIMITADO
    ------------------------------------------------------------

    if os.clock() - LastChainDeepScan
        < CONFIG.CHAIN_DEEP_SCAN_RATE then

        return nil
    end

    LastChainDeepScan = os.clock()

    local descendants

    local ok =
        pcall(function()

            descendants =
                Workspace:GetDescendants()
        end)

    if not ok then
        return nil
    end

    for _, object in ipairs(descendants) do

        if object:IsA("Model")
        and matchesChainName(object.Name) then

            ChainCache = object

            local result =
                makeChainResult(object)

            if result then
                return result
            end
        end
    end

    return nil
end

--==============================================================--
-- TELEPORTAR AO CHAIN
--==============================================================--

local function teleportToChain()

    local target =
        findChain()

    if not target
    or not target.Root then

        return false,
            "Chain indisponível"
    end

    local character =
        LocalPlayer.Character

    if not character then

        return false,
            "Personagem não carregado"
    end

    local chainRoot =
        target.Root

    local forward =
        chainRoot.CFrame.LookVector

    forward =
        Vector3.new(
            forward.X,
            0,
            forward.Z
        )

    if forward.Magnitude < 0.1 then

        forward =
            Vector3.new(0, 0, 1)
    end

    forward = forward.Unit

    local left =
        Vector3.new(
            -forward.Z,
            0,
            forward.X
        )

    local right = -left

    -- primeiro atrás do Chain
    local directions = {
        -forward,
        left,
        right,
        forward,
    }

    for _, direction
    in ipairs(directions) do

        local test =
            chainRoot.Position
            + direction
            * CONFIG.CHAIN_TELEPORT_DISTANCE

        local safe =
            groundAt(
                test,
                character,
                chainRoot.Position.Y
            )

        if safe then

            if teleportCharacter(
                safe,
                chainRoot.Position
            ) then

                return true,
                    "Teleportado ao Chain"
            end
        end
    end

    return false,
        "Sem posição segura perto do Chain"
end

--==============================================================--
-- FUGA
--==============================================================--

local function rotateVector(vector, degrees)

    return CFrame.Angles(
        0,
        math.rad(degrees),
        0
    ):VectorToWorldSpace(vector)
end

local function teleportAwayFromChain()

    local chain =
        findChain()

    if not chain
    or not chain.Root then

        return false,
            "Chain indisponível"
    end

    local character, root =
        getCharacter()

    if not character
    or not root then

        return false,
            "Personagem não carregado"
    end

    local chainPosition =
        chain.Root.Position

    local direction =
        root.Position
        - chainPosition

    direction =
        Vector3.new(
            direction.X,
            0,
            direction.Z
        )

    if direction.Magnitude < 1 then

        direction =
            -chain.Root.CFrame.LookVector

        direction =
            Vector3.new(
                direction.X,
                0,
                direction.Z
            )
    end

    if direction.Magnitude < 0.1 then

        direction =
            Vector3.new(1, 0, 0)
    end

    direction = direction.Unit

    local angles = {
        0,
        25,
        -25,
        50,
        -50,
        80,
        -80,
        120,
        -120,
        180,
    }

    for _, distance
    in ipairs(CONFIG.ESCAPE_DISTANCES) do

        for _, angle
        in ipairs(angles) do

            local vector =
                rotateVector(
                    direction,
                    angle
                )

            local test =
                chainPosition
                + vector * distance

            local safe =
                groundAt(
                    test,
                    character,
                    math.max(
                        root.Position.Y,
                        chainPosition.Y
                    )
                )

            if safe then

                local finalDistance =
                    (
                        safe
                        - chainPosition
                    ).Magnitude

                if finalDistance
                    >= CONFIG.CHAIN_ESCAPE_TRIGGER
                then

                    if teleportCharacter(
                        safe,
                        chainPosition
                    ) then

                        return true,
                            "Você se afastou do Chain"
                    end
                end
            end
        end
    end

    return false,
        "Nenhum local seguro encontrado"
end

--==============================================================--
-- LIMPAR GUI ANTIGA
--==============================================================--

local function destroyOldGui(parent)

    if not parent then
        return
    end

    local old =
        parent:FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end

pcall(function()
    destroyOldGui(CoreGui)
end)

pcall(function()

    local playerGui =
        LocalPlayer:FindFirstChildOfClass(
            "PlayerGui"
        )

    destroyOldGui(playerGui)
end)

pcall(function()

    if gethui then
        destroyOldGui(gethui())
    end
end)

--==============================================================--
-- GUI
--==============================================================--

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    CONFIG.GUI_NAME

Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false

local parented = false

pcall(function()

    if gethui then

        Gui.Parent = gethui()
        parented = true
    end
end)

if not parented then

    pcall(function()

        Gui.Parent = CoreGui
        parented = true
    end)
end

if not parented then

    Gui.Parent =
        LocalPlayer:WaitForChild(
            "PlayerGui"
        )
end

--==============================================================--
-- MENU
--==============================================================--

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        190,
        198
    )

Main.Position =
    UDim2.new(
        0.5,
        -95,
        0.52,
        -99
    )

Main.BackgroundColor3 = BLACK
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(0, 9)

MainCorner.Parent = Main

local MainStroke =
    Instance.new("UIStroke")

MainStroke.Color = BORDER
MainStroke.Thickness = 1
MainStroke.Parent = Main

--==============================================================--
-- HEADER
--==============================================================--

local Header =
    Instance.new("TextLabel")

Header.Size =
    UDim2.new(
        1,
        -10,
        0,
        25
    )

Header.Position =
    UDim2.fromOffset(5, 0)

Header.BackgroundTransparency = 1

Header.Text =
    "CAFEÍNA"

Header.TextColor3 = TEXT
Header.TextSize = 11
Header.Font = Enum.Font.GothamBold

Header.Parent = Main

--==============================================================--
-- BOTÕES
--==============================================================--

local function createButton(
    text,
    y,
    color
)

    local button =
        Instance.new("TextButton")

    button.Size =
        UDim2.new(
            1,
            -14,
            0,
            30
        )

    button.Position =
        UDim2.fromOffset(
            7,
            y
        )

    button.BackgroundColor3 =
        color or BUTTON

    button.BorderSizePixel = 0
    button.AutoButtonColor = false

    button.Text = text
    button.TextColor3 = TEXT
    button.TextSize = 10
    button.Font = Enum.Font.GothamBold

    button.Parent = Main

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(0, 6)

    corner.Parent = button

    return button
end

local ScrapButton =
    createButton(
        "PEGAR SUCATA",
        26,
        BUTTON
    )

local ShopButton =
    createButton(
        "IR PARA LOJA",
        59,
        BUTTON
    )

local ChainButton =
    createButton(
        "CHAIN INDISPONÍVEL",
        92,
        RED_OFF
    )

local EscapeButton =
    createButton(
        "CHAIN INDISPONÍVEL",
        125,
        GREEN_OFF
    )

--==============================================================--
-- STATUS
--==============================================================--

local Status =
    Instance.new("TextLabel")

Status.Size =
    UDim2.new(
        1,
        -14,
        0,
        27
    )

Status.Position =
    UDim2.fromOffset(
        7,
        163
    )

Status.BackgroundColor3 = PANEL
Status.BorderSizePixel = 0

Status.Text = "Pronto"
Status.TextColor3 = MUTED
Status.TextSize = 9
Status.Font = Enum.Font.Gotham

Status.TextWrapped = true
Status.TextTruncate =
    Enum.TextTruncate.AtEnd

Status.Parent = Main

local StatusCorner =
    Instance.new("UICorner")

StatusCorner.CornerRadius =
    UDim.new(0, 6)

StatusCorner.Parent = Status

--==============================================================--
-- ATUALIZAR CHAIN / FUGA
--==============================================================--

local function updateChainVisual()

    local chain =
        findChain()

    ChainAvailable =
        chain ~= nil
        and chain.Root ~= nil
        and chain.Root.Parent ~= nil

    if not ChainAvailable then

        ChainCloseEnough = false

        ChainButton.BackgroundColor3 =
            RED_OFF

        ChainButton.Text =
            "CHAIN INDISPONÍVEL"

        EscapeButton.BackgroundColor3 =
            GREEN_OFF

        EscapeButton.Text =
            "CHAIN INDISPONÍVEL"

        return
    end

    ChainButton.BackgroundColor3 =
        RED_ON

    ChainButton.Text =
        "TELEPORTAR AO CHAIN"

    local _, root =
        getCharacter()

    if not root then

        ChainCloseEnough = false

        EscapeButton.BackgroundColor3 =
            GREEN_OFF

        EscapeButton.Text =
            "FUGIR DO CHAIN"

        return
    end

    local distance =
        (
            root.Position
            - chain.Root.Position
        ).Magnitude

    ChainCloseEnough =
        distance
        <= CONFIG.CHAIN_ESCAPE_TRIGGER

    if ChainCloseEnough then

        EscapeButton.BackgroundColor3 =
            GREEN_ON

        EscapeButton.Text =
            "FUGIR DO CHAIN"

    else

        EscapeButton.BackgroundColor3 =
            GREEN_OFF

        EscapeButton.Text =
            "CHAIN LONGE"
    end
end

--==============================================================--
-- AÇÃO: SUCATA
--==============================================================--

ScrapButton.Activated:Connect(function()

    if Busy then
        return
    end

    Busy = true

    ScrapButton.Text =
        "BUSCANDO..."

    Status.Text =
        "Procurando próxima sucata"

    local callOk, scrap =
        pcall(findScrap)

    if not callOk or not scrap then

        Status.Text =
            "Nenhuma sucata disponível"

        ScrapButton.Text =
            "PEGAR SUCATA"

        Busy = false
        return
    end

    ScrapButton.Text =
        "COLETANDO..."

    local successCall,
        success,
        message =
        pcall(
            collectObject,
            scrap
        )

    if not successCall then

        Status.Text =
            "Erro ao coletar"

    elseif success then

        markScrapUsed(scrap)

        Status.Text =
            message
            or "Sucata coletada"

    else

        Status.Text =
            tostring(
                message
                or "Falha ao coletar"
            )
    end

    ScrapButton.Text =
        "PEGAR SUCATA"

    Busy = false
end)

--==============================================================--
-- AÇÃO: LOJA
--==============================================================--

ShopButton.Activated:Connect(function()

    if Busy then
        return
    end

    Busy = true

    ShopButton.Text =
        "BUSCANDO..."

    Status.Text =
        "Procurando loja"

    local callOk,
        success,
        message =
        pcall(teleportToShop)

    if callOk then

        Status.Text =
            tostring(message)

    else

        Status.Text =
            "Erro ao procurar loja"
    end

    ShopButton.Text =
        "IR PARA LOJA"

    Busy = false
end)

--==============================================================--
-- AÇÃO: CHAIN
--==============================================================--

ChainButton.Activated:Connect(function()

    if Busy then
        return
    end

    updateChainVisual()

    if not ChainAvailable then

        Status.Text =
            "Chain não está disponível"

        return
    end

    Busy = true

    ChainButton.Text =
        "TELEPORTANDO..."

    local callOk,
        success,
        message =
        pcall(teleportToChain)

    if callOk then

        Status.Text =
            tostring(message)

    else

        Status.Text =
            "Erro no teleporte"
    end

    Busy = false

    updateChainVisual()
end)

--==============================================================--
-- AÇÃO: FUGIR
--==============================================================--

EscapeButton.Activated:Connect(function()

    if Busy then
        return
    end

    updateChainVisual()

    if not ChainAvailable then

        Status.Text =
            "Chain não está disponível"

        return
    end

    if not ChainCloseEnough then

        Status.Text =
            "Chain ainda está longe"

        return
    end

    Busy = true

    EscapeButton.Text =
        "FUGINDO..."

    local callOk,
        success,
        message =
        pcall(
            teleportAwayFromChain
        )

    if callOk then

        Status.Text =
            tostring(message)

    else

        Status.Text =
            "Erro ao procurar rota de fuga"
    end

    Busy = false

    task.wait(0.1)

    updateChainVisual()
end)

--==============================================================--
-- DRAG MOBILE
--==============================================================--

local function makeDraggable(
    target,
    handle
)

    local dragging = false
    local dragStart
    local startPosition
    local activeInput

    handle.Active = true

    handle.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1
        then

            dragging = true

            dragStart =
                input.Position

            startPosition =
                target.Position

            activeInput = input
        end
    end)

    UserInputService.InputChanged:Connect(
        function(input)

            if not dragging
            or not dragStart
            or not startPosition then

                return
            end

            if input.UserInputType
                ~= Enum.UserInputType.Touch
            and input.UserInputType
                ~= Enum.UserInputType.MouseMovement
            then

                return
            end

            local delta =
                input.Position
                - dragStart

            target.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )
        end
    )

    UserInputService.InputEnded:Connect(
        function(input)

            if input == activeInput
            or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then

                dragging = false
                activeInput = nil
            end
        end
    )
end

makeDraggable(
    Main,
    Header
)

--==============================================================--
-- MONITOR LEVE DO CHAIN
--==============================================================--

task.spawn(function()

    while GuiAlive
    and Gui.Parent do

        pcall(updateChainVisual)

        task.wait(
            CONFIG.CHAIN_UPDATE_RATE
        )
    end
end)

--==============================================================--
-- RESPAWN
--==============================================================--

LocalPlayer.CharacterAdded:Connect(function()

    Busy = false

    task.wait(1)

    if GuiAlive
    and Gui.Parent then

        pcall(updateChainVisual)

        Status.Text =
            "Pronto"
    end
end)

--==============================================================--
-- ENCERRAMENTO
--==============================================================--

Gui.AncestryChanged:Connect(function(
    _,
    parent
)

    if not parent then
        GuiAlive = false
    end
end)

--==============================================================--
-- START
--==============================================================--

updateChainVisual()

Status.Text =
    "Pronto"

print(
    "[CAFEÍNA] Compact Utility V2 carregado."
)
