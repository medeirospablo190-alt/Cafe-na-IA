--==============================================================--
-- CAFEÍNA • COMPACT UTILITY
-- Mobile / Executor / Client-side
--
-- FUNÇÕES:
-- • PEGAR SUCATA       -> pega 1 sucata por clique
-- • IR PARA LOJA       -> procura chão seguro próximo
-- • IR AO CHAIN        -> ativo somente se Chain/Chen existir
-- • BOTÃO DE FUGA      -> mostra botão verde flutuante
--
-- Não existe auto-coleta.
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

    GUI_NAME = "CafeinaCompactUtility",

    ITEM_OFFSET = 3.2,

    INTERACT_WAIT = 0.20,

    CHAIN_DISTANCE = 6,

    ESCAPE_DISTANCES = {
        90,
        75,
        110,
        60,
    },

    SHOP_SEARCH_RADIUS = {
        4,
        6,
        8,
        10,
        13,
    },
}

--==============================================================--
-- ESTADO
--==============================================================--

local Busy = false
local EscapeEnabled = false
local GuiAlive = true

--==============================================================--
-- CORES
--==============================================================--

local BLACK = Color3.fromRGB(8, 8, 9)

local PANEL = Color3.fromRGB(15, 15, 17)

local BUTTON = Color3.fromRGB(23, 23, 26)

local BUTTON_PRESS = Color3.fromRGB(31, 31, 35)

local BORDER = Color3.fromRGB(43, 43, 47)

local TEXT = Color3.fromRGB(244, 244, 246)

local MUTED = Color3.fromRGB(145, 145, 151)

local RED_OFF = Color3.fromRGB(68, 21, 25)

local RED_ON = Color3.fromRGB(205, 37, 47)

local GREEN = Color3.fromRGB(42, 174, 84)

local GREEN_DARK = Color3.fromRGB(25, 105, 51)

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
-- TEXTO
--==============================================================--

local function normalize(value)

    return string.lower(
        tostring(value or "")
    )
end

local function safeFullName(object)

    local ok, value = pcall(function()
        return object:GetFullName()
    end)

    if ok then
        return value
    end

    return object and object.Name or "?"
end

--==============================================================--
-- BASEPART
--==============================================================--

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

    local current = object.Parent

    while current
    and current ~= Workspace do

        if current:IsA("BasePart") then
            return current
        end

        if current:IsA("Model") then

            local part =
                current.PrimaryPart
                or current:FindFirstChild(
                    "HumanoidRootPart"
                )
                or current:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )

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
-- VERIFICAÇÃO DE ESPAÇO
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
                position
                + Vector3.new(0, 2.6, 0)
            ),
            Vector3.new(3.6, 5.2, 3.6),
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

--==============================================================--
-- PROCURA CHÃO
--==============================================================--

local function groundAt(
    horizontalPosition,
    character,
    referenceY
)

    local params = RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {
        character
    }

    params.IgnoreWater = false

    referenceY =
        referenceY
        or horizontalPosition.Y

    local origin =
        Vector3.new(
            horizontalPosition.X,
            referenceY + 7,
            horizontalPosition.Z
        )

    local result =
        Workspace:Raycast(
            origin,
            Vector3.new(0, -35, 0),
            params
        )

    if not result then
        return nil
    end

    if not result.Instance
    or not result.Instance.CanCollide then
        return nil
    end

    -- evita parede/rampa extremamente inclinada
    if result.Normal.Y < 0.55 then
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

    return position, result
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

        if (
            look - position
        ).Magnitude > 0.1 then

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

    local ok =
        pcall(function()
            character:PivotTo(destination)
        end)

    if not ok then

        ok =
            pcall(function()
                root.CFrame =
                    destination
            end)
    end

    if not ok then
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

local function isScrap(object)

    if not object then
        return false
    end

    local pieces = {
        object.Name
    }

    local current = object.Parent

    for _ = 1, 5 do

        if not current then
            break
        end

        pieces[#pieces + 1] =
            current.Name

        current = current.Parent
    end

    return hasScrapWord(
        table.concat(
            pieces,
            " "
        )
    )
end

local function findScrap()

    local descendants

    local ok =
        pcall(function()

            descendants =
                Workspace:GetDescendants()
        end)

    if not ok
    or not descendants then
        return nil
    end

    for _, object in ipairs(descendants) do

        if object:IsA("Tool")
        or object:IsA("ProximityPrompt")
        or object:IsA("ClickDetector") then

            if isScrap(object) then
                return object
            end
        end
    end

    return nil
end

--==============================================================--
-- INTERAÇÃO
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

    ------------------------------------------------------------
    -- primeiro tenta achar chão perto
    ------------------------------------------------------------

    local offsets = {

        Vector3.new(0,0,0),

        Vector3.new(2.5,0,0),
        Vector3.new(-2.5,0,0),

        Vector3.new(0,0,2.5),
        Vector3.new(0,0,-2.5),
    }

    for _, offset in ipairs(offsets) do

        local test =
            part.Position + offset

        local ground =
            groundAt(
                test,
                character,
                part.Position.Y
            )

        if ground then

            return teleportCharacter(
                ground,
                part.Position
            )
        end
    end

    ------------------------------------------------------------
    -- fallback simples
    ------------------------------------------------------------

    return teleportCharacter(
        part.Position
        + Vector3.new(0,3.5,0),
        part.Position
    )
end

local function toolOwned(tool)

    if not tool then
        return false
    end

    local backpack =
        getBackpack()

    local character =
        LocalPlayer.Character

    if backpack
    and tool:IsDescendantOf(
        backpack
    ) then
        return true
    end

    if character
    and tool:IsDescendantOf(
        character
    ) then
        return true
    end

    return false
end

local function collectObject(object)

    if not object
    or not object.Parent then

        return false,
            "Sucata removida"
    end

    ------------------------------------------------------------
    -- TOOL
    ------------------------------------------------------------

    if object:IsA("Tool") then

        if toolOwned(object) then

            return true,
                "Já coletada"
        end

        local handle =
            getBasePart(object)

        if not handle then

            return false,
                "Sucata sem Handle"
        end

        moveNearObject(object)

        task.wait(0.08)

        local _, root =
            getCharacter()

        if not root then

            return false,
                "Personagem indisponível"
        end

        if typeof(
            firetouchinterest
        ) == "function" then

            pcall(function()

                firetouchinterest(
                    root,
                    handle,
                    0
                )

                task.wait(0.04)

                firetouchinterest(
                    root,
                    handle,
                    1
                )
            end)
        end

        task.wait(
            CONFIG.INTERACT_WAIT
        )

        if toolOwned(object) then

            return true,
                "Sucata coletada"
        end

        return true,
            "Interação realizada"
    end

    ------------------------------------------------------------
    -- PROMPT
    ------------------------------------------------------------

    if object:IsA(
        "ProximityPrompt"
    ) then

        moveNearObject(object)

        task.wait(0.08)

        if typeof(
            fireproximityprompt
        ) ~= "function" then

            return false,
                "Executor sem suporte a Prompt"
        end

        local ok =
            pcall(function()

                fireproximityprompt(
                    object
                )
            end)

        task.wait(
            CONFIG.INTERACT_WAIT
        )

        return ok,
            ok
            and "Sucata coletada"
            or "Falha no Prompt"
    end

    ------------------------------------------------------------
    -- CLICK
    ------------------------------------------------------------

    if object:IsA(
        "ClickDetector"
    ) then

        moveNearObject(object)

        task.wait(0.08)

        if typeof(
            fireclickdetector
        ) ~= "function" then

            return false,
                "Executor sem suporte a ClickDetector"
        end

        local ok =
            pcall(function()

                fireclickdetector(
                    object
                )
            end)

        task.wait(
            CONFIG.INTERACT_WAIT
        )

        return ok,
            ok
            and "Sucata coletada"
            or "Falha no ClickDetector"
    end

    return false,
        "Tipo incompatível"
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

    "weaponshop",
    "gunshop",
    "itemshop",

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

    if object:IsA(
        "ProximityPrompt"
    ) then

        pieces[#pieces + 1] =
            object.ActionText or ""

        pieces[#pieces + 1] =
            object.ObjectText or ""
    end

    local parent =
        object.Parent

    for _ = 1, 4 do

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

    local _, root =
        getCharacter()

    local best = nil
    local bestScore = -math.huge

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

        if object:IsA(
            "ProximityPrompt"
        )
        or object:IsA(
            "ClickDetector"
        ) then

            local text =
                getShopText(object)

            if containsShopWord(
                text
            ) then

                local part =
                    getBasePart(object)

                if part then

                    local score = 0

                    if object:IsA(
                        "ProximityPrompt"
                    ) then
                        score += 100
                    else
                        score += 40
                    end

                    if containsShopWord(
                        object.Name
                    ) then
                        score += 30
                    end

                    if root then

                        local distance =
                            (
                                root.Position
                                - part.Position
                            ).Magnitude

                        score -=
                            math.min(
                                distance / 200,
                                30
                            )
                    end

                    if score > bestScore then

                        bestScore =
                            score

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

    ------------------------------------------------------------
    -- procura pontos ao redor, não exatamente dentro da loja
    ------------------------------------------------------------

    local candidates = {}

    for _, radius
    in ipairs(CONFIG.SHOP_SEARCH_RADIUS) do

        candidates[#candidates + 1] =
            Vector3.new(radius,0,0)

        candidates[#candidates + 1] =
            Vector3.new(-radius,0,0)

        candidates[#candidates + 1] =
            Vector3.new(0,0,radius)

        candidates[#candidates + 1] =
            Vector3.new(0,0,-radius)

        candidates[#candidates + 1] =
            Vector3.new(radius,0,radius)

        candidates[#candidates + 1] =
            Vector3.new(-radius,0,radius)

        candidates[#candidates + 1] =
            Vector3.new(radius,0,-radius)

        candidates[#candidates + 1] =
            Vector3.new(-radius,0,-radius)
    end

    for _, offset in ipairs(candidates) do

        local position =
            center + offset

        local safe =
            groundAt(
                position,
                character,
                center.Y
            )

        if safe then

            local ok =
                teleportCharacter(
                    safe,
                    center
                )

            if ok then

                return true,
                    "Loja encontrada"
            end
        end
    end

    return false,
        "Sem chão seguro perto da loja"
end

--==============================================================--
-- CHAIN / CHEN
--==============================================================--

local CHAIN_NAMES = {

    "chain",
    "chen",
}

local function matchesChainName(name)

    name = normalize(name)

    for _, word
    in ipairs(CHAIN_NAMES) do

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

local function getModelRoot(model)

    if not model then
        return nil
    end

    if model:IsA("BasePart") then
        return model
    end

    if model:IsA("Model") then

        return model:FindFirstChild(
            "HumanoidRootPart"
        )
        or model:FindFirstChild(
            "UpperTorso"
        )
        or model:FindFirstChild(
            "Torso"
        )
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA(
            "BasePart",
            true
        )
    end

    return nil
end

local function findChain()

    ------------------------------------------------------------
    -- PLAYER
    ------------------------------------------------------------

    for _, player
    in ipairs(Players:GetPlayers()) do

        if player ~= LocalPlayer then

            if matchesChainName(
                player.Name
            )
            or matchesChainName(
                player.DisplayName
            ) then

                local root =
                    getModelRoot(
                        player.Character
                    )

                if root then

                    return {
                        Root = root,
                        Character =
                            player.Character,

                        Name =
                            player.DisplayName
                            or player.Name,
                    }
                end
            end
        end
    end

    ------------------------------------------------------------
    -- NPC / MODEL
    ------------------------------------------------------------

    for _, object
    in ipairs(
        Workspace:GetChildren()
    ) do

        if matchesChainName(
            object.Name
        ) then

            local root =
                getModelRoot(object)

            if root then

                return {
                    Root = root,
                    Character = object,
                    Name = object.Name,
                }
            end
        end
    end

    ------------------------------------------------------------
    -- procura modelos mais profundamente
    ------------------------------------------------------------

    for _, object
    in ipairs(
        Workspace:GetDescendants()
    ) do

        if object:IsA("Model")
        and matchesChainName(
            object.Name
        ) then

            local root =
                getModelRoot(object)

            if root then

                return {
                    Root = root,
                    Character = object,
                    Name = object.Name,
                }
            end
        end
    end

    return nil
end

--==============================================================--
-- IR AO CHAIN
--==============================================================--

local function teleportToChain()

    local target =
        findChain()

    if not target
    or not target.Root then

        return false,
            "Chain não está disponível"
    end

    local character =
        LocalPlayer.Character

    if not character then

        return false,
            "Personagem não carregado"
    end

    local chainRoot =
        target.Root

    local backward =
        chainRoot.CFrame.LookVector

    backward =
        Vector3.new(
            backward.X,
            0,
            backward.Z
        )

    if backward.Magnitude < 0.1 then

        backward =
            Vector3.new(
                0,
                0,
                1
            )
    end

    backward =
        backward.Unit

    ------------------------------------------------------------
    -- tenta atrás e nas laterais
    ------------------------------------------------------------

    local directions = {

        -backward,

        Vector3.new(
            -backward.Z,
            0,
            backward.X
        ),

        Vector3.new(
            backward.Z,
            0,
            -backward.X
        ),

        backward,
    }

    for _, direction
    in ipairs(directions) do

        local test =
            chainRoot.Position
            + direction
            * CONFIG.CHAIN_DISTANCE

        local safe =
            groundAt(
                test,
                character,
                chainRoot.Position.Y
            )

        if safe then

            local ok =
                teleportCharacter(
                    safe,
                    chainRoot.Position
                )

            if ok then

                return true,
                    "Teleportado ao Chain"
            end
        end
    end

    ------------------------------------------------------------
    -- fallback
    ------------------------------------------------------------

    local fallback =
        chainRoot.Position
        - backward
        * CONFIG.CHAIN_DISTANCE
        + Vector3.new(0,3,0)

    if teleportCharacter(
        fallback,
        chainRoot.Position
    ) then

        return true,
            "Teleportado ao Chain"
    end

    return false,
        "Falha no teleporte"
end

--==============================================================--
-- FUGIR DO CHAIN
--==============================================================--

local function rotateVector(
    vector,
    angle
)

    return CFrame.Angles(
        0,
        math.rad(angle),
        0
    ):VectorToWorldSpace(
        vector
    )
end

local function teleportAwayFromChain()

    local chain =
        findChain()

    if not chain
    or not chain.Root then

        return false,
            "Chain não está disponível"
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
            Vector3.new(
                1,
                0,
                0
            )
    end

    direction =
        direction.Unit

    local angles = {

        0,
        20,
        -20,

        40,
        -40,

        65,
        -65,

        90,
        -90,

        130,
        -130,

        180,
    }

    for _, distance
    in ipairs(
        CONFIG.ESCAPE_DISTANCES
    ) do

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
                    root.Position.Y
                )

            if safe then

                local ok =
                    teleportCharacter(
                        safe,
                        chainPosition
                    )

                if ok then

                    return true,
                        "Distância criada do Chain"
                end
            end
        end
    end

    return false,
        "Nenhum local seguro encontrado"
end

--==============================================================--
-- LIMPEZA GUI ANTIGA
--==============================================================--

pcall(function()

    local old =
        CoreGui:FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

pcall(function()

    if gethui then

        local old =
            gethui():FindFirstChild(
                CONFIG.GUI_NAME
            )

        if old then
            old:Destroy()
        end
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

local GuiParent =
    CoreGui

pcall(function()

    if gethui then
        GuiParent = gethui()
    end
end)

Gui.Parent =
    GuiParent

--==============================================================--
-- MENU
--==============================================================--

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        200,
        228
    )

Main.Position =
    UDim2.new(
        0.5,
        -100,
        0.53,
        -114
    )

Main.BackgroundColor3 =
    BLACK

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(0,9)

MainCorner.Parent =
    Main

local MainStroke =
    Instance.new("UIStroke")

MainStroke.Color =
    BORDER

MainStroke.Thickness =
    1

MainStroke.Parent =
    Main

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
        27
    )

Header.Position =
    UDim2.fromOffset(
        5,
        0
    )

Header.BackgroundTransparency =
    1

Header.Text =
    "CAFEÍNA"

Header.TextColor3 =
    TEXT

Header.TextSize =
    11

Header.Font =
    Enum.Font.GothamBold

Header.Parent =
    Main

--==============================================================--
-- FUNÇÃO BOTÃO
--==============================================================--

local function createButton(
    text,
    y,
    color
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.new(
            1,
            -14,
            0,
            36
        )

    button.Position =
        UDim2.fromOffset(
            7,
            y
        )

    button.BackgroundColor3 =
        color or BUTTON

    button.BorderSizePixel =
        0

    button.AutoButtonColor =
        false

    button.Text =
        text

    button.TextColor3 =
        TEXT

    button.TextSize =
        10

    button.Font =
        Enum.Font.GothamBold

    button.Parent =
        Main

    local corner =
        Instance.new(
            "UICorner"
        )

    corner.CornerRadius =
        UDim.new(0,7)

    corner.Parent =
        button

    return button
end

local ScrapButton =
    createButton(
        "PEGAR SUCATA",
        28,
        BUTTON
    )

local ShopButton =
    createButton(
        "IR PARA LOJA",
        68,
        BUTTON
    )

local ChainButton =
    createButton(
        "CHAIN INDISPONÍVEL",
        108,
        RED_OFF
    )

local EscapeToggle =
    createButton(
        "BOTÃO DE FUGA: OFF",
        148,
        BUTTON
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
        29
    )

Status.Position =
    UDim2.fromOffset(
        7,
        190
    )

Status.BackgroundColor3 =
    PANEL

Status.BorderSizePixel =
    0

Status.Text =
    "Pronto"

Status.TextColor3 =
    MUTED

Status.TextSize =
    8

Status.Font =
    Enum.Font.Gotham

Status.TextWrapped =
    true

Status.TextTruncate =
    Enum.TextTruncate.AtEnd

Status.Parent =
    Main

local StatusCorner =
    Instance.new("UICorner")

StatusCorner.CornerRadius =
    UDim.new(0,6)

StatusCorner.Parent =
    Status

--==============================================================--
-- BOTÃO FLUTUANTE
--==============================================================--

local EscapeFloat =
    Instance.new("Frame")

EscapeFloat.Size =
    UDim2.fromOffset(
        105,
        44
    )

EscapeFloat.Position =
    UDim2.new(
        0.68,
        0,
        0.65,
        0
    )

EscapeFloat.BackgroundColor3 =
    GREEN

EscapeFloat.BorderSizePixel =
    0

EscapeFloat.Visible =
    false

EscapeFloat.Parent =
    Gui

local FloatCorner =
    Instance.new("UICorner")

FloatCorner.CornerRadius =
    UDim.new(0,9)

FloatCorner.Parent =
    EscapeFloat

local FloatStroke =
    Instance.new("UIStroke")

FloatStroke.Color =
    Color3.fromRGB(
        75,
        215,
        115
    )

FloatStroke.Thickness =
    1

FloatStroke.Parent =
    EscapeFloat

local EscapeButton =
    Instance.new("TextButton")

EscapeButton.Size =
    UDim2.new(
        1,
        -29,
        1,
        0
    )

EscapeButton.BackgroundTransparency =
    1

EscapeButton.Text =
    "FUGIR"

EscapeButton.TextColor3 =
    TEXT

EscapeButton.TextSize =
    11

EscapeButton.Font =
    Enum.Font.GothamBold

EscapeButton.Parent =
    EscapeFloat

local EscapeClose =
    Instance.new("TextButton")

EscapeClose.Size =
    UDim2.fromOffset(
        27,
        27
    )

EscapeClose.Position =
    UDim2.new(
        1,
        -29,
        0,
        2
    )

EscapeClose.BackgroundTransparency =
    1

EscapeClose.Text =
    "×"

EscapeClose.TextColor3 =
    TEXT

EscapeClose.TextSize =
    17

EscapeClose.Font =
    Enum.Font.GothamBold

EscapeClose.Parent =
    EscapeFloat

--==============================================================--
-- ESTADO CHAIN
--==============================================================--

local ChainAvailable = false

local function updateChainButton()

    local chain =
        findChain()

    ChainAvailable =
        chain ~= nil
        and chain.Root ~= nil
        and chain.Root.Parent ~= nil

    if ChainAvailable then

        ChainButton.BackgroundColor3 =
            RED_ON

        ChainButton.Text =
            "TELEPORTAR AO CHAIN"

        ChainButton.Active =
            true

    else

        ChainButton.BackgroundColor3 =
            RED_OFF

        ChainButton.Text =
            "CHAIN INDISPONÍVEL"

        ChainButton.Active =
            false
    end
end

--==============================================================--
-- ESCAPE VISUAL
--==============================================================--

local function updateEscapeVisual()

    if EscapeEnabled then

        EscapeToggle.Text =
            "BOTÃO DE FUGA: ON"

        EscapeToggle.BackgroundColor3 =
            GREEN_DARK

        EscapeFloat.Visible =
            true

    else

        EscapeToggle.Text =
            "BOTÃO DE FUGA: OFF"

        EscapeToggle.BackgroundColor3 =
            BUTTON

        EscapeFloat.Visible =
            false
    end
end

--==============================================================--
-- SUCATA
--==============================================================--

ScrapButton.Activated:Connect(function()

    if Busy then
        return
    end

    Busy = true

    ScrapButton.Text =
        "BUSCANDO..."

    Status.Text =
        "Procurando sucata"

    local scrap =
        findScrap()

    if not scrap then

        Status.Text =
            "Nenhuma sucata disponível"

        ScrapButton.Text =
            "PEGAR SUCATA"

        Busy = false

        return
    end

    ScrapButton.Text =
        "COLETANDO..."

    local ok, message =
        collectObject(scrap)

    if ok then

        Status.Text =
            "Sucata coletada"

    else

        Status.Text =
            tostring(message)
    end

    ScrapButton.Text =
        "PEGAR SUCATA"

    Busy = false
end)

--==============================================================--
-- LOJA
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

    local ok, message =
        teleportToShop()

    Status.Text =
        tostring(message)

    ShopButton.Text =
        "IR PARA LOJA"

    Busy = false
end)

--==============================================================--
-- CHAIN
--==============================================================--

ChainButton.Activated:Connect(function()

    if Busy then
        return
    end

    updateChainButton()

    if not ChainAvailable then

        Status.Text =
            "Chain não está disponível"

        return
    end

    Busy = true

    ChainButton.Text =
        "TELEPORTANDO..."

    local ok, message =
        teleportToChain()

    Status.Text =
        tostring(message)

    Busy = false

    updateChainButton()
end)

--==============================================================--
-- TOGGLE FUGA
--==============================================================--

EscapeToggle.Activated:Connect(function()

    EscapeEnabled =
        not EscapeEnabled

    updateEscapeVisual()

    Status.Text =
        EscapeEnabled
        and "Botão de fuga ativado"
        or "Botão de fuga desligado"
end)

EscapeClose.Activated:Connect(function()

    EscapeEnabled =
        false

    updateEscapeVisual()

    Status.Text =
        "Botão de fuga fechado"
end)

EscapeButton.Activated:Connect(function()

    if Busy
    or not EscapeEnabled then
        return
    end

    Busy = true

    EscapeButton.Text =
        "..."

    local ok, message =
        teleportAwayFromChain()

    Status.Text =
        tostring(message)

    EscapeButton.Text =
        "FUGIR"

    Busy = false
end)

--==============================================================--
-- DRAG GENÉRICO MOBILE
--==============================================================--

local function makeDraggable(
    target,
    handle
)

    local dragging = false
    local dragStart = nil
    local startPosition = nil
    local activeInput = nil

    handle.Active = true

    handle.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = true

            dragStart =
                input.Position

            startPosition =
                target.Position

            activeInput =
                input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)

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
    end)

    UserInputService.InputEnded:Connect(function(input)

        if input == activeInput
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            dragging = false
            activeInput = nil
        end
    end)
end

makeDraggable(
    Main,
    Header
)

makeDraggable(
    EscapeFloat,
    EscapeFloat
)

--==============================================================--
-- FEEDBACK DE TOQUE
--==============================================================--

local function addPressEffect(
    button,
    normalColor
)

    button.InputBegan:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            if button == ChainButton then
                return
            end

            button.BackgroundColor3 =
                BUTTON_PRESS
        end
    end)

    button.InputEnded:Connect(function(input)

        if input.UserInputType
            == Enum.UserInputType.Touch
        or input.UserInputType
            == Enum.UserInputType.MouseButton1 then

            if button
                == EscapeToggle then

                updateEscapeVisual()

            elseif button
                ~= ChainButton then

                button.BackgroundColor3 =
                    normalColor
            end
        end
    end)
end

addPressEffect(
    ScrapButton,
    BUTTON
)

addPressEffect(
    ShopButton,
    BUTTON
)

--==============================================================--
-- MONITOR CHAIN
--==============================================================--

task.spawn(function()

    while GuiAlive
    and Gui.Parent do

        pcall(
            updateChainButton
        )

        task.wait(0.8)
    end
end)

Gui.AncestryChanged:Connect(function(
    _,
    parent
)

    if not parent then
        GuiAlive = false
    end
end)

--==============================================================--
-- INICIALIZAÇÃO
--==============================================================--

updateEscapeVisual()
updateChainButton()

Status.Text =
    "Pronto"

print(
    "[CAFEÍNA] Compact Utility carregado."
)
