-- CAFEÍNA • MOBILE UTILITY MENU V1.4
-- Mantém o V1.2 original intacto, deixa o menu mais compacto e adiciona CLONES REAIS.
-- Requer Cafeina_CloneServer.lua em ServerScriptService no próprio jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
if not LP then
    return
end

--============================================================
-- CARREGA O MENU ORIGINAL PRESERVADO
--============================================================

local BASE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/Mobile_Utility_Menu_V1_2_BACKUP.lua"

local ok, baseSource = pcall(function()
    return game:HttpGet(BASE_URL)
end)

if not ok or type(baseSource) ~= "string" or baseSource == "" then
    error("Falha ao carregar o Mobile Utility Menu V1.2 preservado")
end

local baseChunk, compileError = loadstring(baseSource)
if not baseChunk then
    error("Falha ao compilar menu base: " .. tostring(compileError))
end

local BaseController = baseChunk()

local playerGui = LP:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MobileUtilityMenuV1", 5)
if not gui then
    error("GUI base não foi encontrada")
end

local main = gui:FindFirstChild("Main")
if not main then
    error("Frame principal não foi encontrado")
end

--============================================================
-- COMPACTAÇÃO SEM MUDAR O LAYOUT ORIGINAL
--============================================================

local mainScale = main:FindFirstChild("_CafeinaCompactScale")
if not mainScale then
    mainScale = Instance.new("UIScale")
    mainScale.Name = "_CafeinaCompactScale"
    mainScale.Parent = main
end
mainScale.Scale = 0.82

local mini = gui:FindFirstChild("Mini", true)
if mini then
    local miniScale = mini:FindFirstChild("_CafeinaCompactScale") or Instance.new("UIScale")
    miniScale.Name = "_CafeinaCompactScale"
    miniScale.Scale = 0.84
    miniScale.Parent = mini
end

local tpPopup
for _, obj in ipairs(gui:GetDescendants()) do
    if obj:IsA("Frame") and obj.ZIndex >= 20 and obj.Size.X.Offset >= 240 and obj.Size.Y.Offset >= 300 then
        tpPopup = obj
        break
    end
end

if tpPopup then
    local popupScale = tpPopup:FindFirstChild("_CafeinaCompactScale") or Instance.new("UIScale")
    popupScale.Name = "_CafeinaCompactScale"
    popupScale.Scale = 0.84
    popupScale.Parent = tpPopup
end

--============================================================
-- LOCALIZA A PÁGINA MENU E STATUS
--============================================================

local mainPage
for _, obj in ipairs(main:GetDescendants()) do
    if obj:IsA("ScrollingFrame") and obj.Visible then
        mainPage = obj
        break
    end
end

if not mainPage then
    error("Página principal do menu não foi encontrada")
end

local statusLabel
for _, obj in ipairs(main:GetChildren()) do
    if obj:IsA("TextLabel") and obj.Position.Y.Scale >= 0.9 then
        statusLabel = obj
        break
    end
end

local function status(text)
    if statusLabel then
        statusLabel.Text = tostring(text)
    end
end

--============================================================
-- UI HELPERS
--============================================================

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
end

local function addSection(text)
    local label = Instance.new("TextLabel")
    label.Name = "CloneSection"
    label.Size = UDim2.new(1, -4, 0, 23)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(165, 165, 165)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = mainPage
    return label
end

local function addButton(text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -4, 0, 34)
    button.BackgroundColor3 = Color3.fromRGB(31, 31, 31)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 11
    button.Parent = mainPage
    corner(button, 8)

    button.MouseButton1Click:Connect(function()
        local success, err = pcall(callback)
        if not success then
            status("Erro clone: " .. tostring(err))
        end
    end)

    return button
end

--============================================================
-- SNAPSHOT DO PERSONAGEM
--============================================================

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function containsAny(text, words)
    text = lower(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local function relativePath(instance, root)
    local path = {}
    local current = instance

    while current and current ~= root do
        table.insert(path, 1, current.Name)
        current = current.Parent
    end

    if current ~= root then
        return nil
    end

    return path
end

local function captureJoints(character)
    local joints = {}

    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("Motor6D") then
            local path = relativePath(obj, character)
            if path then
                joints[#joints + 1] = {
                    path = path,
                    transform = obj.Transform,
                }
            end
        end

        if #joints >= 80 then
            break
        end
    end

    return joints
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

    local moving = humanoid.MoveDirection.Magnitude > 0.05
    local tracks = {}

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local animation
        pcall(function()
            animation = track.Animation
        end)

        if animation and animation.AnimationId and animation.AnimationId ~= "" then
            local nameText = lower(track.Name) .. " " .. lower(animation.Name)
            local expressive = containsAny(nameText, {
                "dance", "emote", "wave", "cheer", "laugh", "point", "pose", "sit"
            })

            local priorityName = tostring(track.Priority):gsub("Enum.AnimationPriority.", "")
            local lowPriorityIdle = priorityName == "Idle" or priorityName == "Core"
            local skip = false

            -- Se o jogador está parado, não copia o idle automático.
            -- Danças/emotes continuam sendo copiadas mesmo sem MoveDirection.
            if not moving and lowPriorityIdle and not expressive then
                skip = true
            end

            if containsAny(nameText, {"idle"}) and not expressive and not moving then
                skip = true
            end

            if not skip then
                local weight = 1
                pcall(function()
                    weight = track.WeightCurrent
                end)

                tracks[#tracks + 1] = {
                    animationId = animation.AnimationId,
                    timePosition = track.TimePosition,
                    speed = track.Speed,
                    weight = weight,
                    looped = track.Looped,
                    priority = priorityName,
                }
            end
        end

        if #tracks >= 8 then
            break
        end
    end

    return tracks
end

local function makeSnapshot()
    local character = LP.Character
    if not character or not character.Parent then
        return nil
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then
        return nil
    end

    return {
        pivot = character:GetPivot(),
        joints = captureJoints(character),
        tracks = captureTracks(character),
    }
end

--============================================================
-- SERVER REMOTE
--============================================================

local function getRemote()
    local remote = ReplicatedStorage:FindFirstChild("CafeinaCloneRemote")
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

addSection("CLONES REAIS")

addButton("CRIAR CLONE REAL", function()
    local remote = getRemote()
    if not remote then
        status("Clone Server não instalado no jogo")
        return
    end

    local snapshot = makeSnapshot()
    if not snapshot then
        status("Personagem indisponível")
        return
    end

    remote:FireServer("Create", snapshot)
    status("Clone real solicitado")
end)

addButton("APAGAR ÚLTIMO CLONE", function()
    local remote = getRemote()
    if not remote then
        status("Clone Server não instalado no jogo")
        return
    end

    remote:FireServer("DeleteLast")
    status("Último clone removido")
end)

addButton("APAGAR TODOS OS CLONES", function()
    local remote = getRemote()
    if not remote then
        status("Clone Server não instalado no jogo")
        return
    end

    remote:FireServer("DeleteAll")
    status("Clones removidos")
end)

status("V1.4 compacto • clones server")

return {
    BaseController = BaseController,
    Destroy = function(self)
        if BaseController and type(BaseController.Destroy) == "function" then
            BaseController:Destroy()
        elseif gui and gui.Parent then
            gui:Destroy()
        end
    end,
}
