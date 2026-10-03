--============================================================
-- MOBILE UTILITY MENU V1.3 • COMPACT + ANIMATED CLONES
--
-- Base: V1.2 preservado sem alterações.
-- Esta versão carrega o V1.2 e aplica apenas:
--   • layout mais compacto
--   • clones animados do personagem atual
--   • apagar último clone / apagar todos
--
-- O clone nasce na posição atual, copia a pose atual e tenta reproduzir
-- as animações que estavam realmente ativas naquele instante.
-- Se o jogador estiver parado, animações básicas de idle/movimento são
-- ignoradas para o clone ficar parado. Emotes/ações como dança continuam.
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
if not LP then
    LP = Players.PlayerAdded:Wait()
end

local PlayerGui = LP:WaitForChild("PlayerGui")

--============================================================
-- CARREGA V1.2 ORIGINAL
--============================================================

local BASE_URL =
    "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/Mobile_Utility_Menu_V1_2.lua"

local okSource, source = pcall(function()
    return game:HttpGet(BASE_URL)
end)

if not okSource or type(source) ~= "string" or source == "" then
    error("Falha ao carregar a base V1.2")
end

local chunk, compileError = loadstring(source)
if not chunk then
    error("Falha ao compilar a base V1.2: " .. tostring(compileError))
end

local Controller = chunk()

--============================================================
-- ENCONTRA GUI DA BASE
--============================================================

local Gui = PlayerGui:FindFirstChild("MobileUtilityMenuV1")
if not Gui then
    error("GUI base MobileUtilityMenuV1 não encontrada")
end

local Main = Gui:FindFirstChild("Main")
if not Main then
    error("Main da GUI base não encontrado")
end

local Mini = Gui:FindFirstChild("Mini")

local function startsWith(text, prefix)
    text = tostring(text or "")
    return string.sub(text, 1, #prefix) == prefix
end

local StatusLabel
local MainPage
local TPPage
local TPPopup

for _, obj in ipairs(Main:GetDescendants()) do
    if obj:IsA("TextLabel") and obj.Text == "Menu carregado" then
        StatusLabel = obj
    elseif obj:IsA("TextButton") and startsWith(obj.Text, "ESP AMIGOS ROBLOX") then
        if obj.Parent and obj.Parent:IsA("ScrollingFrame") then
            MainPage = obj.Parent
        end
    elseif obj:IsA("TextBox") and obj.PlaceholderText == "Pesquisar jogador..." then
        if obj.Parent and obj.Parent:IsA("ScrollingFrame") then
            TPPage = obj.Parent
        end
    end
end

for _, child in ipairs(Gui:GetChildren()) do
    if child:IsA("Frame") and child ~= Main then
        for _, sub in ipairs(child:GetDescendants()) do
            if sub:IsA("TextLabel") and startsWith(sub.Text, "TP+") then
                TPPopup = child
                break
            end
        end
    end

    if TPPopup then
        break
    end
end

--============================================================
-- COMPACT MODE V1.3
--============================================================

Main.Size = UDim2.fromOffset(260, 380)
Main.Position = UDim2.new(0.5, -130, 0.5, -190)

if Mini then
    Mini.Size = UDim2.fromOffset(42, 42)
    Mini.Position = UDim2.new(0.5, -21, 0.25, 0)
    Mini.TextSize = 15
end

if TPPopup then
    TPPopup.Size = UDim2.fromOffset(230, 295)
    TPPopup.Position = UDim2.new(0.5, -115, 0.5, -148)
end

local function compactDirectChildren(container)
    if not container then
        return
    end

    local layout = container:FindFirstChildOfClass("UIListLayout")
    if layout then
        layout.Padding = UDim.new(0, 4)
    end

    for _, obj in ipairs(container:GetChildren()) do
        if obj:IsA("TextButton") then
            local h = obj.Size.Y.Offset
            if h >= 34 then
                obj.Size = UDim2.new(obj.Size.X.Scale, obj.Size.X.Offset, 0, 30)
                obj.TextSize = math.min(obj.TextSize, 10)
            end
        elseif obj:IsA("TextLabel") then
            local h = obj.Size.Y.Offset
            if h > 0 and h <= 25 then
                obj.Size = UDim2.new(obj.Size.X.Scale, obj.Size.X.Offset, 0, 18)
                obj.TextSize = math.min(obj.TextSize, 9)
            end
        elseif obj:IsA("Frame") then
            local h = obj.Size.Y.Offset
            if h == 36 then
                obj.Size = UDim2.new(obj.Size.X.Scale, obj.Size.X.Offset, 0, 32)
            elseif h == 40 then
                obj.Size = UDim2.new(obj.Size.X.Scale, obj.Size.X.Offset, 0, 34)
            elseif h == 42 then
                obj.Size = UDim2.new(obj.Size.X.Scale, obj.Size.X.Offset, 0, 36)
            end
        end
    end
end

compactDirectChildren(MainPage)
compactDirectChildren(TPPage)

if TPPopup then
    for _, obj in ipairs(TPPopup:GetDescendants()) do
        if obj:IsA("Frame") and obj:FindFirstChildOfClass("UIListLayout") then
            compactDirectChildren(obj)
        end
    end
end

--============================================================
-- CLONES
--============================================================

local CloneFolder = Workspace:FindFirstChild("_CafeinaAnimatedClones")
if CloneFolder then
    CloneFolder:Destroy()
end

CloneFolder = Instance.new("Folder")
CloneFolder.Name = "_CafeinaAnimatedClones"
CloneFolder.Parent = Workspace

local Clones = {}
local CloneCounter = 0

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function isExpressiveTrack(track, animation)
    local text = lower(track and track.Name)
        .. " "
        .. lower(animation and animation.Name)

    local words = {
        "dance",
        "emote",
        "wave",
        "cheer",
        "laugh",
        "point",
        "pose",
        "sit",
    }

    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end

    return false
end

local function isActionPriority(priority)
    return priority == Enum.AnimationPriority.Action
        or priority == Enum.AnimationPriority.Action2
        or priority == Enum.AnimationPriority.Action3
        or priority == Enum.AnimationPriority.Action4
end

local function characterHasBodyMotion(humanoid)
    if not humanoid then
        return false
    end

    if humanoid.MoveDirection.Magnitude > 0.05 then
        return true
    end

    local state = humanoid:GetState()

    return state == Enum.HumanoidStateType.Jumping
        or state == Enum.HumanoidStateType.Freefall
        or state == Enum.HumanoidStateType.Climbing
        or state == Enum.HumanoidStateType.Swimming
        or state == Enum.HumanoidStateType.SwimmingPhysics
end

local function captureTracks(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return {}
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return {}
    end

    local bodyMotion = characterHasBodyMotion(humanoid)
    local captured = {}

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local animation
        pcall(function()
            animation = track.Animation
        end)

        if animation and animation.AnimationId ~= "" then
            local expressive = isExpressiveTrack(track, animation)
            local priority = track.Priority

            local shouldCopy = bodyMotion
                or expressive
                or isActionPriority(priority)

            -- Se estiver totalmente parado, não copiamos idle/movement/core.
            -- Assim o clone mantém a pose capturada sem começar um idle novo.
            if shouldCopy then
                table.insert(captured, {
                    animationId = animation.AnimationId,
                    animationName = animation.Name,
                    trackName = track.Name,
                    timePosition = track.TimePosition,
                    speed = track.Speed,
                    weight = track.WeightCurrent,
                    looped = track.Looped,
                    priority = priority,
                })
            end
        end
    end

    return captured
end

local function motorKey(motor)
    local part0 = motor.Part0 and motor.Part0.Name or ""
    local part1 = motor.Part1 and motor.Part1.Name or ""
    return motor.Name .. "|" .. part0 .. "|" .. part1
end

local function copyCurrentPose(original, clone)
    local cloneMotors = {}

    for _, obj in ipairs(clone:GetDescendants()) do
        if obj:IsA("Motor6D") then
            cloneMotors[motorKey(obj)] = obj
        end
    end

    for _, obj in ipairs(original:GetDescendants()) do
        if obj:IsA("Motor6D") then
            local target = cloneMotors[motorKey(obj)]
            if target then
                pcall(function()
                    target.Transform = obj.Transform
                end)
            end
        end
    end
end

local function prepareClonePhysics(clone)
    local humanoid = clone:FindFirstChildOfClass("Humanoid")
    local root = clone:FindFirstChild("HumanoidRootPart")
        or clone.PrimaryPart

    for _, obj in ipairs(clone:GetDescendants()) do
        if obj:IsA("LuaSourceContainer") then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.CanCollide = false
            obj.CanTouch = false
            obj.CanQuery = true

            if obj ~= root then
                obj.Anchored = false
                obj.Massless = true
            end
        end
    end

    if root and root:IsA("BasePart") then
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    if humanoid then
        humanoid.AutoRotate = false
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.JumpHeight = 0
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end

    return humanoid, root
end

local function playCapturedTracks(clone, humanoid, captured)
    if not humanoid then
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local pending = {}

    for index, info in ipairs(captured) do
        local animation = Instance.new("Animation")
        animation.Name = info.animationName ~= ""
            and info.animationName
            or ("CloneAnimation_" .. tostring(index))
        animation.AnimationId = info.animationId
        animation.Parent = clone

        local ok, track = pcall(function()
            return animator:LoadAnimation(animation)
        end)

        if ok and track then
            pcall(function()
                track.Looped = info.looped
                track.Priority = info.priority
            end)

            pcall(function()
                track:Play(
                    0,
                    math.max(tonumber(info.weight) or 1, 0.01),
                    tonumber(info.speed) or 1
                )
            end)

            table.insert(pending, {
                track = track,
                timePosition = tonumber(info.timePosition) or 0,
            })
        end
    end

    if #pending > 0 then
        RunService.Heartbeat:Wait()

        for _, data in ipairs(pending) do
            pcall(function()
                data.track.TimePosition = math.max(0, data.timePosition)
            end)
        end
    end
end

local function createAnimatedClone()
    local character = LP.Character
    if not character or not character.Parent then
        return nil, "personagem indisponível"
    end

    local tracks = captureTracks(character)
    local pivot = character:GetPivot()

    local oldArchivable = character.Archivable
    character.Archivable = true

    local ok, clone = pcall(function()
        return character:Clone()
    end)

    character.Archivable = oldArchivable

    if not ok or not clone then
        return nil, "não foi possível clonar o personagem"
    end

    CloneCounter += 1
    clone.Name = "CafeinaClone_" .. tostring(CloneCounter)
    clone.Parent = CloneFolder
    clone:PivotTo(pivot)

    local humanoid = prepareClonePhysics(clone)

    -- Primeiro preserva exatamente a pose do instante.
    copyCurrentPose(character, clone)

    -- Depois continua apenas as animações que faz sentido manter.
    playCapturedTracks(clone, humanoid, tracks)

    table.insert(Clones, clone)

    return clone
end

local function removeLastClone()
    local clone = table.remove(Clones)

    if clone and clone.Parent then
        clone:Destroy()
        return true
    end

    return false
end

local function clearClones()
    for _, clone in ipairs(Clones) do
        if clone and clone.Parent then
            clone:Destroy()
        end
    end

    table.clear(Clones)

    if CloneFolder and CloneFolder.Parent then
        for _, child in ipairs(CloneFolder:GetChildren()) do
            child:Destroy()
        end
    end
end

--============================================================
-- UI CLONES
--============================================================

local function rounded(obj, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 7)
    corner.Parent = obj
end

local function addCloneButton(parent, text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -4, 0, 30)
    button.BackgroundColor3 = Color3.fromRGB(31, 31, 31)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 10
    button.Parent = parent
    rounded(button, 7)

    button.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback, button)
        if not ok and StatusLabel then
            StatusLabel.Text = "Erro clone: " .. tostring(err)
        end
    end)

    return button
end

if MainPage then
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -4, 0, 18)
    title.BackgroundTransparency = 1
    title.Text = "CLONES"
    title.TextColor3 = Color3.fromRGB(165, 165, 165)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 9
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = MainPage

    addCloneButton(MainPage, "CRIAR CLONE ANIMADO", function()
        local clone, err = createAnimatedClone()

        if StatusLabel then
            if clone then
                StatusLabel.Text = "Clone criado: " .. clone.Name
            else
                StatusLabel.Text = "Clone falhou: " .. tostring(err)
            end
        end
    end)

    addCloneButton(MainPage, "APAGAR ÚLTIMO CLONE", function()
        local removed = removeLastClone()

        if StatusLabel then
            StatusLabel.Text = removed
                and "Último clone apagado"
                or "Nenhum clone para apagar"
        end
    end)

    addCloneButton(MainPage, "APAGAR TODOS OS CLONES", function()
        clearClones()

        if StatusLabel then
            StatusLabel.Text = "Todos os clones foram apagados"
        end
    end)
end

--============================================================
-- EXTENSÃO DO CONTROLLER / CLEANUP
--============================================================

if type(Controller) == "table" then
    Controller.CreateAnimatedClone = createAnimatedClone
    Controller.RemoveLastClone = removeLastClone
    Controller.ClearClones = clearClones

    local originalDestroy = Controller.Destroy

    Controller.Destroy = function(self)
        clearClones()

        if CloneFolder and CloneFolder.Parent then
            CloneFolder:Destroy()
        end

        if type(originalDestroy) == "function" then
            return originalDestroy(self)
        end
    end
end

if getgenv then
    getgenv().__MOBILE_UTILITY_MENU_V1_3 = Controller
end

if StatusLabel then
    StatusLabel.Text = "V1.3 compact + clones carregado"
end

return Controller
