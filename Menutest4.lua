--[[
    CAFEÍNA — TYCOON / SHOOTER DEV TEST MENU
    Target PlaceId: 110012028951508

    Uso: ferramenta de teste cliente-side no próprio jogo/ambiente controlado.
    Feito para executor/mobile, sem depender de assinatura inventada de Remote.

    Principais recursos:
      • ESP em players inimigos e NPCs/bots
      • Aura branca (Highlight) + tracer vermelho
      • Nome / HP / distância
      • Aimbot automático com FOV ajustável
      • Força/suavização ajustável
      • Team Check
      • Wall Check com Workspace:Raycast()
      • Distância máxima ajustável
      • Mantém alvo enquanto ele continuar válido
      • Reaquisição automática quando alvo morre/sai do FOV
      • No recoil / camera shake por atributos/values comuns
      • Bloqueio local de animações de arma/reload
      • Infinite ammo cliente-side em atributos/Values comuns
      • Rapid fire / burst contínuo via Tool:Activate()
      • Integração automática com ShootButton mobile
      • Resistente a respawn
      • Cleanup de conexões/GUI/Highlights
      • Sem GetDescendants() a cada frame

    IMPORTANTE:
      Se o servidor validar munição, cadência, recarga ou dano, alterações puramente
      cliente-side não podem garantir o resultado server-side. Este script não tenta
      burlar validações server-side; ele usa somente estados cliente-side e Tool:Activate().
]]

if game.PlaceId ~= 110012028951508 then
    warn("[CAFEÍNA] Este build foi limitado ao PlaceId 110012028951508.")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

local Camera = Workspace.CurrentCamera

-- =========================================================
-- CLEANUP DE INSTÂNCIA ANTERIOR
-- =========================================================

local ENV = (getgenv and getgenv()) or _G

if ENV.CAFEINA_TYCOON_DEV and ENV.CAFEINA_TYCOON_DEV.Destroy then
    pcall(function()
        ENV.CAFEINA_TYCOON_DEV:Destroy()
    end)
end

-- =========================================================
-- CONFIG
-- =========================================================

local Config = {
    Version = "DEV-ESP-AIM-1.0",

    ESP = {
        Enabled = true,
        Players = true,
        Bots = true,
        Tracer = true,
        Aura = true,
        Name = true,
        Health = true,
        Distance = true,
        MaxDistance = 3000,
        TeamCheck = true,
    },

    Aim = {
        Enabled = false,
        TeamCheck = true,
        WallCheck = true,
        TargetBots = true,
        TargetPlayers = true,
        FOV = 180,
        Strength = 55,
        MaxDistance = 1800,
        AimPart = "Head",
        HoldTarget = true,
    },

    Weapon = {
        NoRecoil = false,
        NoWeaponAnimations = false,
        InfiniteAmmo = false,
        RapidFire = false,
        BurstRPM = 1200,
    },

    UI = {
        Minimized = false,
    }
}

-- =========================================================
-- HELPERS
-- =========================================================

local function safeDisconnect(conn)
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function safeDestroy(inst)
    if inst then
        pcall(function()
            inst:Destroy()
        end)
    end
end

local function clamp(v, a, b)
    return math.max(a, math.min(b, v))
end

local function round(v)
    return math.floor(v + 0.5)
end

local function getGuiParent()
    local ok, result = pcall(function()
        if gethui then
            return gethui()
        end
    end)
    if ok and result then
        return result
    end
    return CoreGui
end

local function protectGui(gui)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        elseif protectgui then
            protectgui(gui)
        end
    end)
end

local function isAliveModel(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model.PrimaryPart
end

local function getAimPart(model)
    if not model then return nil end

    local preferred = Config.Aim.AimPart
    if preferred and model:FindFirstChild(preferred) then
        return model[preferred]
    end

    return model:FindFirstChild("Head")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or getRoot(model)
end

local function worldDistance(partA, partB)
    if not partA or not partB then
        return math.huge
    end
    return (partA.Position - partB.Position).Magnitude
end

local function formatDistance(d)
    if d == math.huge then return "?" end
    return tostring(round(d)) .. "m"
end

local function isBasicCharacterAnimationName(name)
    name = string.lower(name or "")
    return name == "idle"
        or name == "walk"
        or name == "run"
        or name == "jump"
        or name == "fall"
        or name == "climb"
        or name == "swim"
end

local WEAPON_ANIMATION_WORDS = {
    "reload", "shoot", "fire", "recoil", "equip", "inspect",
    "weapon", "gun", "aim", "ads", "bolt", "pump", "mag"
}

local function looksLikeWeaponAnimation(track, tool)
    if not track then return false end

    local anim = track.Animation
    if anim and tool and anim:IsDescendantOf(tool) then
        return true
    end

    local trackName = string.lower(track.Name or "")
    local animName = anim and string.lower(anim.Name or "") or ""

    if isBasicCharacterAnimationName(trackName) or isBasicCharacterAnimationName(animName) then
        return false
    end

    for _, word in ipairs(WEAPON_ANIMATION_WORDS) do
        if string.find(trackName, word, 1, true) or string.find(animName, word, 1, true) then
            return true
        end
    end

    return false
end

-- =========================================================
-- CONNECTION MANAGER
-- =========================================================

local ConnectionManager = {
    Connections = {}
}

function ConnectionManager:Add(key, conn)
    self:Remove(key)
    self.Connections[key] = conn
    return conn
end

function ConnectionManager:Remove(key)
    local conn = self.Connections[key]
    if conn then
        safeDisconnect(conn)
        self.Connections[key] = nil
    end
end

function ConnectionManager:ClearPrefix(prefix)
    for key, conn in pairs(self.Connections) do
        if string.sub(key, 1, #prefix) == prefix then
            safeDisconnect(conn)
            self.Connections[key] = nil
        end
    end
end

function ConnectionManager:Clear()
    for key, conn in pairs(self.Connections) do
        safeDisconnect(conn)
        self.Connections[key] = nil
    end
end

-- =========================================================
-- CHARACTER MANAGER
-- =========================================================

local CharacterManager = {
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    Alive = false,
    CharacterVersion = 0,
}

function CharacterManager:Refresh(character)
    self.Character = character
    self.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    self.RootPart = character and getRoot(character) or nil
    self.Alive = self.Humanoid ~= nil and self.Humanoid.Health > 0
    self.CharacterVersion += 1

    ConnectionManager:ClearPrefix("CharacterManager.")

    if character then
        ConnectionManager:Add("CharacterManager.ChildAdded", character.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then
                self.Humanoid = child
                self.Alive = child.Health > 0
            elseif child.Name == "HumanoidRootPart" then
                self.RootPart = child
            end
        end))

        ConnectionManager:Add("CharacterManager.ChildRemoved", character.ChildRemoved:Connect(function(child)
            if child == self.Humanoid then
                self.Humanoid = nil
                self.Alive = false
            elseif child == self.RootPart then
                self.RootPart = nil
            end
        end))

        if self.Humanoid then
            ConnectionManager:Add("CharacterManager.Died", self.Humanoid.Died:Connect(function()
                self.Alive = false
            end))
        end
    end
end

CharacterManager:Refresh(LocalPlayer.Character)

ConnectionManager:Add("CharacterAdded", LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    CharacterManager:Refresh(char)
end))

ConnectionManager:Add("CharacterRemoving", LocalPlayer.CharacterRemoving:Connect(function()
    CharacterManager.Character = nil
    CharacterManager.Humanoid = nil
    CharacterManager.RootPart = nil
    CharacterManager.Alive = false
end))

-- =========================================================
-- PLAYER / NPC TRACKER
-- =========================================================

local Tracker = {
    Entities = {}, -- [Model] = state
}

local function modelFriendlyAttribute(model)
    if not model then return false end

    local attrs = {
        model:GetAttribute("Friendly"),
        model:GetAttribute("IsFriendly"),
        model:GetAttribute("Ally"),
        model:GetAttribute("IsAlly"),
    }

    for _, v in ipairs(attrs) do
        if v == true then
            return true
        end
    end

    return false
end

function Tracker:IsEnemyPlayer(player, teamCheck)
    if not player or player == LocalPlayer then
        return false
    end

    if teamCheck == false then
        return true
    end

    if LocalPlayer.Team ~= nil and player.Team ~= nil and LocalPlayer.Team == player.Team then
        return false
    end

    return true
end

function Tracker:IsEnemyState(state, teamCheck)
    if not state or not state.Model or not state.Model.Parent then
        return false
    end

    if state.Player then
        return self:IsEnemyPlayer(state.Player, teamCheck)
    end

    if modelFriendlyAttribute(state.Model) then
        return false
    end

    return true
end

function Tracker:RegisterModel(model)
    if not model or not model:IsA("Model") then
        return
    end

    if model == CharacterManager.Character then
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    local root = getRoot(model)
    if not root then
        return
    end

    local player = Players:GetPlayerFromCharacter(model)

    if self.Entities[model] then
        local state = self.Entities[model]
        state.Humanoid = humanoid
        state.Root = root
        state.Player = player
        state.IsBot = player == nil
        return
    end

    local state = {
        Model = model,
        Humanoid = humanoid,
        Root = root,
        Player = player,
        IsBot = player == nil,
        LastSeen = os.clock(),
        Visual = nil,
    }

    self.Entities[model] = state
end

function Tracker:RemoveModel(model)
    local state = self.Entities[model]
    if not state then return end

    if state.Visual then
        safeDestroy(state.Visual.Highlight)
        safeDestroy(state.Visual.Tracer)
        safeDestroy(state.Visual.Info)
        state.Visual = nil
    end

    self.Entities[model] = nil
end

function Tracker:RefreshState(state)
    local model = state.Model
    if not model or not model.Parent then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = getRoot(model)

    if not humanoid or not root then
        return false
    end

    state.Humanoid = humanoid
    state.Root = root
    state.Player = Players:GetPlayerFromCharacter(model)
    state.IsBot = state.Player == nil
    state.LastSeen = os.clock()
    return true
end

function Tracker:InitialScan()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            self:RegisterModel(player.Character)
        end
    end

    -- Uma única varredura inicial para NPCs/bots.
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            self:RegisterModel(obj.Parent)
        end
    end
end

Tracker:InitialScan()

ConnectionManager:Add("Tracker.PlayerAdded", Players.PlayerAdded:Connect(function(player)
    ConnectionManager:Add("Tracker.PlayerCharacter." .. tostring(player.UserId), player.CharacterAdded:Connect(function(char)
        task.wait(0.1)
        Tracker:RegisterModel(char)
    end))

    if player.Character then
        Tracker:RegisterModel(player.Character)
    end
end))

ConnectionManager:Add("Tracker.PlayerRemoving", Players.PlayerRemoving:Connect(function(player)
    if player.Character then
        Tracker:RemoveModel(player.Character)
    end
    ConnectionManager:Remove("Tracker.PlayerCharacter." .. tostring(player.UserId))
end))

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        ConnectionManager:Add("Tracker.PlayerCharacter." .. tostring(player.UserId), player.CharacterAdded:Connect(function(char)
            task.wait(0.1)
            Tracker:RegisterModel(char)
        end))
    end
end

ConnectionManager:Add("Tracker.DescendantAdded", Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
        task.defer(function()
            task.wait()
            Tracker:RegisterModel(obj.Parent)
        end)
    end
end))

ConnectionManager:Add("Tracker.DescendantRemoving", Workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") and Tracker.Entities[obj] then
        Tracker:RemoveModel(obj)
    end
end))

-- =========================================================
-- GUI ROOT
-- =========================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "CAFEINA_TYCOON_DEV"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
protectGui(Gui)
Gui.Parent = getGuiParent()

local Overlay = Instance.new("Frame")
Overlay.Name = "Overlay"
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.BackgroundTransparency = 1
Overlay.BorderSizePixel = 0
Overlay.Active = false
Overlay.Parent = Gui

local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "FOVCircle"
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.BackgroundTransparency = 1
FOVCircle.BorderSizePixel = 0
FOVCircle.ZIndex = 3
FOVCircle.Parent = Overlay

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircle

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 1.5
FOVStroke.Transparency = 0.12
FOVStroke.Color = Color3.fromRGB(255, 255, 255)
FOVStroke.Parent = FOVCircle

local function createTracer()
    local line = Instance.new("Frame")
    line.Name = "Tracer"
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.BackgroundColor3 = Color3.fromRGB(255, 45, 45)
    line.BorderSizePixel = 0
    line.ZIndex = 4
    line.Visible = false
    line.Parent = Overlay
    return line
end

local function setLine(line, x1, y1, x2, y2, thickness)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)

    line.Position = UDim2.fromOffset(x1, y1)
    line.Size = UDim2.fromOffset(length, thickness)
    line.Rotation = math.deg(math.atan2(dy, dx))
end

local function createInfoLabel()
    local label = Instance.new("TextLabel")
    label.Name = "ESPInfo"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Size = UDim2.fromOffset(150, 36)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.45
    label.TextSize = 13
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.ZIndex = 5
    label.Visible = false
    label.Parent = Overlay
    return label
end

local function createHighlight(model)
    local h = Instance.new("Highlight")
    h.Name = "CAFEINA_ESP_AURA"
    h.Adornee = model
    h.FillColor = Color3.fromRGB(255, 255, 255)
    h.OutlineColor = Color3.fromRGB(255, 255, 255)
    h.FillTransparency = 0.82
    h.OutlineTransparency = 0.05
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Enabled = false
    h.Parent = model
    return h
end

local function ensureVisual(state)
    if state.Visual then
        return state.Visual
    end

    state.Visual = {
        Highlight = createHighlight(state.Model),
        Tracer = createTracer(),
        Info = createInfoLabel(),
    }

    return state.Visual
end

-- =========================================================
-- VISIBILITY / TARGET MANAGER
-- =========================================================

local TargetManager = {
    Current = nil,
}

local function isVisibleToCamera(state)
    local part = getAimPart(state.Model)
    if not part or not Camera then
        return false
    end

    local origin = Camera.CFrame.Position
    local direction = part.Position - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local ignore = {}
    if CharacterManager.Character then
        table.insert(ignore, CharacterManager.Character)
    end

    params.FilterDescendantsInstances = ignore

    local result = Workspace:Raycast(origin, direction, params)

    if not result then
        return true
    end

    return result.Instance ~= nil and result.Instance:IsDescendantOf(state.Model)
end

local function screenCenter()
    local viewport = Camera and Camera.ViewportSize or Vector2.new(0, 0)
    return Vector2.new(viewport.X / 2, viewport.Y / 2)
end

local function stateAllowedForAim(state)
    if not Tracker:RefreshState(state) then
        return false
    end

    if state.Humanoid.Health <= 0 then
        return false
    end

    if state.IsBot and not Config.Aim.TargetBots then
        return false
    end

    if (not state.IsBot) and not Config.Aim.TargetPlayers then
        return false
    end

    if not Tracker:IsEnemyState(state, Config.Aim.TeamCheck) then
        return false
    end

    if not CharacterManager.RootPart then
        return false
    end

    local d = worldDistance(CharacterManager.RootPart, state.Root)
    if d > Config.Aim.MaxDistance then
        return false
    end

    local part = getAimPart(state.Model)
    if not part or not Camera then
        return false
    end

    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen or screenPos.Z <= 0 then
        return false
    end

    local center = screenCenter()
    local delta = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude

    if delta > Config.Aim.FOV then
        return false
    end

    if Config.Aim.WallCheck and not isVisibleToCamera(state) then
        return false
    end

    return true, delta
end

function TargetManager:Acquire()
    local bestState = nil
    local bestScore = math.huge

    for model, state in pairs(Tracker.Entities) do
        if model and state then
            local ok, score = stateAllowedForAim(state)
            if ok and score < bestScore then
                bestScore = score
                bestState = state
            end
        end
    end

    self.Current = bestState
    return bestState
end

function TargetManager:ValidateCurrent()
    local state = self.Current
    if not state then
        return false
    end

    local ok = stateAllowedForAim(state)
    if not ok then
        self.Current = nil
        return false
    end

    return true
end

function TargetManager:Get()
    if Config.Aim.HoldTarget and self:ValidateCurrent() then
        return self.Current
    end

    return self:Acquire()
end

-- =========================================================
-- WEAPON TRACKER / TEST MODS
-- =========================================================

local WeaponManager = {
    Tool = nil,
    OriginalAttributes = setmetatable({}, {__mode = "k"}),
    OriginalValues = setmetatable({}, {__mode = "k"}),
    BurstHolding = false,
    BurstThread = nil,
    ShootButtons = setmetatable({}, {__mode = "k"}),
    ShootButtonCounter = 0,
}

local AMMO_ATTRIBUTE_NAMES = {
    "_ammo", "ammo", "Ammo", "CurrentAmmo", "currentAmmo",
    "AmmoInMag", "ammoInMag", "MagazineAmmo", "magazineAmmo"
}

local RELOAD_ATTRIBUTE_NAMES = {
    "_reloading", "Reloading", "reloading", "IsReloading", "isReloading"
}

local RECOIL_WORDS = {
    "recoil", "kick", "camerashake", "camera_shake", "shake",
    "viewkick", "view_kick"
}

function WeaponManager:GetTool()
    local char = CharacterManager.Character
    if not char then
        self.Tool = nil
        return nil
    end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            self.Tool = child
            return child
        end
    end

    self.Tool = nil
    return nil
end

function WeaponManager:RememberAttribute(inst, name)
    self.OriginalAttributes[inst] = self.OriginalAttributes[inst] or {}
    local bucket = self.OriginalAttributes[inst]

    if bucket[name] == nil then
        bucket[name] = {
            Exists = inst:GetAttribute(name) ~= nil,
            Value = inst:GetAttribute(name)
        }
    end
end

function WeaponManager:RememberValue(valueObj)
    if self.OriginalValues[valueObj] == nil then
        self.OriginalValues[valueObj] = valueObj.Value
    end
end

function WeaponManager:GetMagazineSize(tool)
    if not tool then return 999 end

    local names = {
        "magazineSize", "MagazineSize", "magSize", "MagSize",
        "capacity", "Capacity"
    }

    for _, name in ipairs(names) do
        local value = tool:GetAttribute(name)
        if typeof(value) == "number" and value > 0 then
            return math.max(value, 999)
        end
    end

    return 999
end

function WeaponManager:SetAttributeSafe(inst, name, value)
    local existing = inst:GetAttribute(name)
    if existing ~= nil then
        self:RememberAttribute(inst, name)
        pcall(function()
            inst:SetAttribute(name, value)
        end)
    end
end

function WeaponManager:SetValueSafe(obj, value)
    if obj and obj:IsA("ValueBase") then
        self:RememberValue(obj)
        pcall(function()
            obj.Value = value
        end)
    end
end

function WeaponManager:ApplyAmmo(tool)
    if not tool then return end
    local fill = self:GetMagazineSize(tool)

    for _, name in ipairs(AMMO_ATTRIBUTE_NAMES) do
        self:SetAttributeSafe(tool, name, fill)
    end

    for _, name in ipairs(RELOAD_ATTRIBUTE_NAMES) do
        self:SetAttributeSafe(tool, name, false)
    end

    for _, obj in ipairs(tool:GetDescendants()) do
        if obj:IsA("IntValue") or obj:IsA("NumberValue") then
            local lname = string.lower(obj.Name)
            if string.find(lname, "ammo", 1, true) or lname == "_ammo" then
                self:SetValueSafe(obj, fill)
            end
        elseif obj:IsA("BoolValue") then
            local lname = string.lower(obj.Name)
            if string.find(lname, "reload", 1, true) then
                self:SetValueSafe(obj, false)
            end
        end
    end
end

function WeaponManager:ApplyNoRecoil(tool)
    if not tool then return end

    local function process(inst)
        for name, value in pairs(inst:GetAttributes()) do
            if typeof(value) == "number" then
                local lname = string.lower(name)
                for _, word in ipairs(RECOIL_WORDS) do
                    if string.find(lname, word, 1, true) then
                        self:SetAttributeSafe(inst, name, 0)
                        break
                    end
                end
            end
        end

        if inst:IsA("NumberValue") then
            local lname = string.lower(inst.Name)
            for _, word in ipairs(RECOIL_WORDS) do
                if string.find(lname, word, 1, true) then
                    self:SetValueSafe(inst, 0)
                    break
                end
            end
        end
    end

    process(tool)
    for _, obj in ipairs(tool:GetDescendants()) do
        process(obj)
    end
end

function WeaponManager:StopWeaponAnimations()
    local hum = CharacterManager.Humanoid
    local tool = self:GetTool()
    if not hum or not tool then return end

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if looksLikeWeaponAnimation(track, tool) then
            pcall(function()
                track:Stop(0.03)
            end)
        end
    end
end

function WeaponManager:RestoreAll()
    for inst, attrs in pairs(self.OriginalAttributes) do
        if inst and inst.Parent then
            for name, saved in pairs(attrs) do
                pcall(function()
                    if saved.Exists then
                        inst:SetAttribute(name, saved.Value)
                    end
                end)
            end
        end
    end

    for valueObj, original in pairs(self.OriginalValues) do
        if valueObj and valueObj.Parent then
            pcall(function()
                valueObj.Value = original
            end)
        end
    end

    self.OriginalAttributes = setmetatable({}, {__mode = "k"})
    self.OriginalValues = setmetatable({}, {__mode = "k"})
end

function WeaponManager:GetBurstInterval()
    local rpm = clamp(Config.Weapon.BurstRPM, 120, 3000)
    return 60 / rpm
end

function WeaponManager:FireOnce()
    local tool = self:GetTool()
    if not tool then return end

    if Config.Weapon.InfiniteAmmo then
        self:ApplyAmmo(tool)
    end

    pcall(function()
        tool:Activate()
    end)
end

function WeaponManager:StartBurst()
    if not Config.Weapon.RapidFire then return end
    if self.BurstHolding then return end

    self.BurstHolding = true

    self.BurstThread = task.spawn(function()
        while self.BurstHolding and Config.Weapon.RapidFire do
            self:FireOnce()
            task.wait(self:GetBurstInterval())
        end
    end)
end

function WeaponManager:StopBurst()
    self.BurstHolding = false
end

function WeaponManager:HookShootButton(button)
    if not button or self.ShootButtons[button] then
        return
    end

    if not button:IsA("GuiButton") then
        return
    end

    self.ShootButtons[button] = true
    self.ShootButtonCounter += 1

    local prefix = "Weapon.ShootButton." .. tostring(self.ShootButtonCounter)

    ConnectionManager:Add(prefix .. ".Began", button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:StartBurst()
        end
    end))

    ConnectionManager:Add(prefix .. ".Ended", button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:StopBurst()
        end
    end))

    ConnectionManager:Add(prefix .. ".Destroying", button.Destroying:Connect(function()
        self.ShootButtons[button] = nil
        self:StopBurst()
    end))
end

function WeaponManager:ScanShootButtons()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end

    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("GuiButton") then
            local lname = string.lower(obj.Name)
            if lname == "shootbutton"
                or lname == "firebutton"
                or string.find(lname, "shoot", 1, true) then
                self:HookShootButton(obj)
            end
        end
    end
end

WeaponManager:ScanShootButtons()

local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if PlayerGui then
    ConnectionManager:Add("Weapon.PlayerGuiAdded", PlayerGui.DescendantAdded:Connect(function(obj)
        if obj:IsA("GuiButton") then
            local lname = string.lower(obj.Name)
            if lname == "shootbutton"
                or lname == "firebutton"
                or string.find(lname, "shoot", 1, true) then
                WeaponManager:HookShootButton(obj)
            end
        end
    end))
end

ConnectionManager:Add("Weapon.MouseBegan", UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        WeaponManager:StartBurst()
    end
end))

ConnectionManager:Add("Weapon.MouseEnded", UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        WeaponManager:StopBurst()
    end
end))

-- =========================================================
-- ESP UPDATE
-- =========================================================

local function espAllowed(state)
    if not Config.ESP.Enabled then
        return false
    end

    if not Tracker:RefreshState(state) then
        return false
    end

    if state.Humanoid.Health <= 0 then
        return false
    end

    if state.IsBot and not Config.ESP.Bots then
        return false
    end

    if (not state.IsBot) and not Config.ESP.Players then
        return false
    end

    if not Tracker:IsEnemyState(state, Config.ESP.TeamCheck) then
        return false
    end

    if not CharacterManager.RootPart then
        return false
    end

    local d = worldDistance(CharacterManager.RootPart, state.Root)
    if d > Config.ESP.MaxDistance then
        return false
    end

    return true, d
end

local function updateESP()
    if not Camera then return end

    local viewport = Camera.ViewportSize
    local bottomCenterX = viewport.X / 2
    local bottomCenterY = viewport.Y - 12

    for model, state in pairs(Tracker.Entities) do
        if not model or not model.Parent then
            Tracker:RemoveModel(model)
        else
            local visual = ensureVisual(state)
            local allowed, dist = espAllowed(state)

            if not allowed then
                visual.Highlight.Enabled = false
                visual.Tracer.Visible = false
                visual.Info.Visible = false
            else
                visual.Highlight.Enabled = Config.ESP.Aura

                local root = state.Root
                local head = getAimPart(model)

                if root and head then
                    local rootScreen, rootVisible = Camera:WorldToViewportPoint(root.Position)
                    local headScreen, headVisible = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.2, 0))
                    local onScreen = rootVisible and headVisible and rootScreen.Z > 0

                    if onScreen then
                        if Config.ESP.Tracer then
                            setLine(
                                visual.Tracer,
                                bottomCenterX,
                                bottomCenterY,
                                rootScreen.X,
                                rootScreen.Y,
                                2
                            )
                            visual.Tracer.Visible = true
                        else
                            visual.Tracer.Visible = false
                        end

                        local chunks = {}

                        if Config.ESP.Name then
                            local name = state.Player and state.Player.Name or model.Name
                            table.insert(chunks, name)
                        end

                        if Config.ESP.Health then
                            table.insert(chunks, tostring(round(state.Humanoid.Health)) .. " HP")
                        end

                        if Config.ESP.Distance then
                            table.insert(chunks, formatDistance(dist))
                        end

                        visual.Info.Text = table.concat(chunks, "  |  ")
                        visual.Info.Position = UDim2.fromOffset(headScreen.X, headScreen.Y - 4)
                        visual.Info.Visible = #chunks > 0
                    else
                        visual.Tracer.Visible = false
                        visual.Info.Visible = false
                    end
                else
                    visual.Tracer.Visible = false
                    visual.Info.Visible = false
                end
            end
        end
    end
end

-- =========================================================
-- AIM UPDATE
-- =========================================================

local function updateFOV()
    if not Camera then return end

    local diameter = Config.Aim.FOV * 2
    FOVCircle.Size = UDim2.fromOffset(diameter, diameter)
    FOVCircle.Position = UDim2.fromOffset(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    FOVCircle.Visible = Config.Aim.Enabled
end

local function updateAim()
    if not Config.Aim.Enabled or not Camera then
        TargetManager.Current = nil
        return
    end

    local state = TargetManager:Get()
    if not state then
        return
    end

    local part = getAimPart(state.Model)
    if not part then
        TargetManager.Current = nil
        return
    end

    local cameraPosition = Camera.CFrame.Position
    local desired = CFrame.new(cameraPosition, part.Position)

    local alpha = clamp(Config.Aim.Strength / 100, 0.01, 1)
    Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
end

-- =========================================================
-- MAIN LOOPS
-- =========================================================

local accumulatorWeapon = 0
local accumulatorCleanup = 0

ConnectionManager:Add("Main.Render", RunService.RenderStepped:Connect(function(dt)
    Camera = Workspace.CurrentCamera or Camera

    updateFOV()
    updateESP()
    updateAim()

    accumulatorWeapon += dt
    accumulatorCleanup += dt

    if accumulatorWeapon >= 0.08 then
        accumulatorWeapon = 0

        local tool = WeaponManager:GetTool()

        if tool then
            if Config.Weapon.InfiniteAmmo then
                WeaponManager:ApplyAmmo(tool)
            end

            if Config.Weapon.NoRecoil then
                WeaponManager:ApplyNoRecoil(tool)
            end

            if Config.Weapon.NoWeaponAnimations then
                WeaponManager:StopWeaponAnimations()
            end
        end
    end

    if accumulatorCleanup >= 2.5 then
        accumulatorCleanup = 0

        for model in pairs(Tracker.Entities) do
            if not model or not model.Parent then
                Tracker:RemoveModel(model)
            end
        end
    end
end))

-- =========================================================
-- MENU UI
-- =========================================================

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(360, 505)
Main.Position = UDim2.new(0, 18, 0.5, -252)
Main.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.ZIndex = 20
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(235, 235, 235)
MainStroke.Transparency = 0.78
MainStroke.Thickness = 1
MainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 48)
Header.BackgroundColor3 = Color3.fromRGB(22, 22, 25)
Header.BorderSizePixel = 0
Header.ZIndex = 21
Header.Parent = Main

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -100, 1, 0)
HeaderTitle.Position = UDim2.fromOffset(14, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Text = "CAFEÍNA  •  TYCOON DEV"
HeaderTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
HeaderTitle.TextSize = 15
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.ZIndex = 22
HeaderTitle.Parent = Header

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.fromOffset(8, 8)
StatusDot.Position = UDim2.new(1, -79, 0.5, -4)
StatusDot.BackgroundColor3 = Color3.fromRGB(90, 220, 120)
StatusDot.BorderSizePixel = 0
StatusDot.ZIndex = 23
StatusDot.Parent = Header
local StatusDotCorner = Instance.new("UICorner")
StatusDotCorner.CornerRadius = UDim.new(1, 0)
StatusDotCorner.Parent = StatusDot

local MinButton = Instance.new("TextButton")
MinButton.Size = UDim2.fromOffset(34, 34)
MinButton.Position = UDim2.new(1, -74, 0, 7)
MinButton.BackgroundColor3 = Color3.fromRGB(35, 35, 39)
MinButton.Text = "—"
MinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinButton.TextSize = 17
MinButton.Font = Enum.Font.GothamBold
MinButton.ZIndex = 23
MinButton.Parent = Header
local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 8)
MinCorner.Parent = MinButton

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.fromOffset(34, 34)
CloseButton.Position = UDim2.new(1, -38, 0, 7)
CloseButton.BackgroundColor3 = Color3.fromRGB(120, 34, 34)
CloseButton.Text = "×"
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.TextSize = 20
CloseButton.Font = Enum.Font.GothamBold
CloseButton.ZIndex = 23
CloseButton.Parent = Header
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseButton

local Tabs = Instance.new("Frame")
Tabs.Size = UDim2.new(1, -16, 0, 42)
Tabs.Position = UDim2.fromOffset(8, 54)
Tabs.BackgroundTransparency = 1
Tabs.ZIndex = 21
Tabs.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabLayout.Padding = UDim.new(0, 6)
TabLayout.Parent = Tabs

local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -16, 1, -106)
Content.Position = UDim2.fromOffset(8, 100)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.ScrollBarImageColor3 = Color3.fromRGB(190, 190, 190)
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.CanvasSize = UDim2.new()
Content.ZIndex = 21
Content.Parent = Main

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 8)
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Parent = Content

local MiniIcon = Instance.new("TextButton")
MiniIcon.Name = "MiniIcon"
MiniIcon.Size = UDim2.fromOffset(54, 54)
MiniIcon.Position = UDim2.fromOffset(18, 180)
MiniIcon.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
MiniIcon.Text = "C"
MiniIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
MiniIcon.TextSize = 22
MiniIcon.Font = Enum.Font.GothamBlack
MiniIcon.Visible = false
MiniIcon.ZIndex = 30
MiniIcon.Parent = Gui

local MiniCorner = Instance.new("UICorner")
MiniCorner.CornerRadius = UDim.new(1, 0)
MiniCorner.Parent = MiniIcon

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Color3.fromRGB(255, 255, 255)
MiniStroke.Transparency = 0.35
MiniStroke.Parent = MiniIcon

local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local dragInput = nil

    ConnectionManager:Add("UI.DragBegan." .. frame.Name, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then

            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            dragInput = input
        end
    end))

    ConnectionManager:Add("UI.DragEnded." .. frame.Name, handle.InputEnded:Connect(function(input)
        if input == dragInput then
            dragging = false
            dragInput = nil
        end
    end))

    ConnectionManager:Add("UI.DragChanged." .. frame.Name, UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement
        ) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end

makeDraggable(Main, Header)
makeDraggable(MiniIcon, MiniIcon)

local Pages = {}
local TabButtons = {}

local function clearContent()
    for _, child in ipairs(Content:GetChildren()) do
        if child ~= ContentLayout then
            child.Parent = nil
        end
    end
end

local function createPage(name)
    local holder = Instance.new("Frame")
    holder.Name = name
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = holder

    Pages[name] = holder
    return holder
end

local function section(parent, text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -4, 0, 26)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(190, 190, 195)
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.LayoutOrder = 1
    label.Parent = parent
    return label
end

local function rowBase(parent, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -2, 0, height or 46)
    row.BackgroundColor3 = Color3.fromRGB(27, 27, 30)
    row.BorderSizePixel = 0
    row.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = row

    return row
end

local function addToggle(parent, labelText, getter, setter)
    local row = rowBase(parent, 46)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -96, 1, 0)
    label.Position = UDim2.fromOffset(12, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(242, 242, 245)
    label.TextSize = 14
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(72, 30)
    button.Position = UDim2.new(1, -82, 0.5, -15)
    button.BorderSizePixel = 0
    button.TextSize = 12
    button.Font = Enum.Font.GothamBold
    button.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local function refresh()
        local on = getter()
        button.Text = on and "ON" or "OFF"
        button.BackgroundColor3 = on and Color3.fromRGB(54, 115, 72) or Color3.fromRGB(72, 72, 78)
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    button.Activated:Connect(function()
        setter(not getter())
        refresh()
    end)

    refresh()
    return row
end

local SliderCounter = 0

local function addSlider(parent, labelText, minVal, maxVal, step, getter, setter, suffix)
    SliderCounter += 1
    local sliderId = SliderCounter
    local row = rowBase(parent, 66)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -100, 0, 28)
    label.Position = UDim2.fromOffset(12, 3)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(242, 242, 245)
    label.TextSize = 13
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.fromOffset(86, 28)
    valueLabel.Position = UDim2.new(1, -96, 0, 3)
    valueLabel.BackgroundTransparency = 1
    valueLabel.TextColor3 = Color3.fromRGB(210, 210, 215)
    valueLabel.TextSize = 12
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 8)
    bar.Position = UDim2.fromOffset(12, 46)
    bar.BackgroundColor3 = Color3.fromRGB(55, 55, 61)
    bar.BorderSizePixel = 0
    bar.Parent = row

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(225, 225, 230)
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = bar

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local dragging = false

    local function snap(v)
        if step <= 0 then return v end
        return math.floor((v - minVal) / step + 0.5) * step + minVal
    end

    local function refresh()
        local value = clamp(getter(), minVal, maxVal)
        local alpha = (value - minVal) / (maxVal - minVal)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)

        local display
        if math.abs(value - math.floor(value)) < 0.001 then
            display = tostring(math.floor(value))
        else
            display = string.format("%.1f", value)
        end

        valueLabel.Text = display .. (suffix or "")
    end

    local function updateFromX(x)
        local absX = bar.AbsolutePosition.X
        local width = bar.AbsoluteSize.X
        if width <= 0 then return end

        local alpha = clamp((x - absX) / width, 0, 1)
        local value = minVal + (maxVal - minVal) * alpha
        value = snap(value)
        value = clamp(value, minVal, maxVal)

        setter(value)
        refresh()
    end

    row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateFromX(input.Position.X)
        end
    end)

    row.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    ConnectionManager:Add("UI.SliderInput." .. tostring(sliderId), UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement
        ) then
            updateFromX(input.Position.X)
        end
    end))

    refresh()
    return row
end

local function addInfo(parent, textFn)
    local row = rowBase(parent, 54)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, -10)
    label.Position = UDim2.fromOffset(10, 5)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(210, 210, 215)
    label.TextSize = 12
    label.Font = Enum.Font.Gotham
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = row

    task.spawn(function()
        while label.Parent and Gui.Parent do
            pcall(function()
                label.Text = textFn()
            end)
            task.wait(0.35)
        end
    end)

    return row
end

local AimPage = createPage("AIM")
local ESPPage = createPage("ESP")
local WeaponPage = createPage("WEAPON")
local SystemPage = createPage("SYSTEM")

section(AimPage, "AIMBOT INTELIGENTE")
addToggle(AimPage, "Aimbot", function() return Config.Aim.Enabled end, function(v)
    Config.Aim.Enabled = v
    if not v then
        TargetManager.Current = nil
    end
end)

addToggle(AimPage, "Não mirar através de parede", function() return Config.Aim.WallCheck end, function(v)
    Config.Aim.WallCheck = v
    TargetManager.Current = nil
end)

addToggle(AimPage, "Team Check", function() return Config.Aim.TeamCheck end, function(v)
    Config.Aim.TeamCheck = v
    TargetManager.Current = nil
end)

addToggle(AimPage, "Focar jogadores", function() return Config.Aim.TargetPlayers end, function(v)
    Config.Aim.TargetPlayers = v
    TargetManager.Current = nil
end)

addToggle(AimPage, "Focar bots / NPCs", function() return Config.Aim.TargetBots end, function(v)
    Config.Aim.TargetBots = v
    TargetManager.Current = nil
end)

addSlider(AimPage, "FOV", 40, 500, 5,
    function() return Config.Aim.FOV end,
    function(v) Config.Aim.FOV = v end,
    " px"
)

addSlider(AimPage, "Força da mira", 1, 100, 1,
    function() return Config.Aim.Strength end,
    function(v) Config.Aim.Strength = v end,
    "%"
)

addSlider(AimPage, "Distância máxima", 100, 4000, 50,
    function() return Config.Aim.MaxDistance end,
    function(v) Config.Aim.MaxDistance = v end,
    "m"
)

addInfo(AimPage, function()
    local state = TargetManager.Current
    if state and state.Model and state.Model.Parent then
        local name = state.Player and state.Player.Name or state.Model.Name
        local d = CharacterManager.RootPart and worldDistance(CharacterManager.RootPart, state.Root) or math.huge
        return "Alvo atual: " .. name .. "  •  " .. formatDistance(d)
    end
    return "Alvo atual: nenhum"
end)

section(ESPPage, "ESP INIMIGOS + BOTS")
addToggle(ESPPage, "ESP Master", function() return Config.ESP.Enabled end, function(v)
    Config.ESP.Enabled = v
end)

addToggle(ESPPage, "Players", function() return Config.ESP.Players end, function(v)
    Config.ESP.Players = v
end)

addToggle(ESPPage, "Bots / NPCs", function() return Config.ESP.Bots end, function(v)
    Config.ESP.Bots = v
end)

addToggle(ESPPage, "Team Check do ESP", function() return Config.ESP.TeamCheck end, function(v)
    Config.ESP.TeamCheck = v
end)

addToggle(ESPPage, "Aura branca", function() return Config.ESP.Aura end, function(v)
    Config.ESP.Aura = v
end)

addToggle(ESPPage, "Linha vermelha", function() return Config.ESP.Tracer end, function(v)
    Config.ESP.Tracer = v
end)

addToggle(ESPPage, "Nome", function() return Config.ESP.Name end, function(v)
    Config.ESP.Name = v
end)

addToggle(ESPPage, "HP", function() return Config.ESP.Health end, function(v)
    Config.ESP.Health = v
end)

addToggle(ESPPage, "Distância", function() return Config.ESP.Distance end, function(v)
    Config.ESP.Distance = v
end)

addSlider(ESPPage, "Alcance ESP", 100, 5000, 50,
    function() return Config.ESP.MaxDistance end,
    function(v) Config.ESP.MaxDistance = v end,
    "m"
)

section(WeaponPage, "TESTE DE ARMAS — CLIENTE")
addToggle(WeaponPage, "Sem recoil / camera shake", function() return Config.Weapon.NoRecoil end, function(v)
    Config.Weapon.NoRecoil = v
    if not v then
        WeaponManager:RestoreAll()
    end
end)

addToggle(WeaponPage, "Remover animações da arma", function() return Config.Weapon.NoWeaponAnimations end, function(v)
    Config.Weapon.NoWeaponAnimations = v
end)

addToggle(WeaponPage, "Munição infinita cliente-side", function() return Config.Weapon.InfiniteAmmo end, function(v)
    Config.Weapon.InfiniteAmmo = v
    if not v and not Config.Weapon.NoRecoil then
        WeaponManager:RestoreAll()
    end
end)

addToggle(WeaponPage, "Rajada / rapid fire", function() return Config.Weapon.RapidFire end, function(v)
    Config.Weapon.RapidFire = v
    if not v then
        WeaponManager:StopBurst()
    end
end)

addSlider(WeaponPage, "RPM da rajada", 120, 3000, 20,
    function() return Config.Weapon.BurstRPM end,
    function(v) Config.Weapon.BurstRPM = v end,
    " RPM"
)

addInfo(WeaponPage, function()
    local tool = WeaponManager:GetTool()
    if not tool then
        return "Arma atual: nenhuma"
    end

    local ammo = tool:GetAttribute("_ammo")
        or tool:GetAttribute("Ammo")
        or tool:GetAttribute("ammo")
        or "?"

    local rpm = tool:GetAttribute("rateOfFire")
        or tool:GetAttribute("RateOfFire")
        or "?"

    return "Arma: " .. tool.Name .. "  •  Ammo: " .. tostring(ammo) .. "  •  RPM original: " .. tostring(rpm)
end)

section(SystemPage, "SISTEMA")
addInfo(SystemPage, function()
    local entityCount = 0
    local botCount = 0
    local playerCount = 0

    for _, state in pairs(Tracker.Entities) do
        entityCount += 1
        if state.IsBot then
            botCount += 1
        else
            playerCount += 1
        end
    end

    return "Entidades: " .. entityCount
        .. "  •  Players: " .. playerCount
        .. "  •  Bots: " .. botCount
end)

addInfo(SystemPage, function()
    return "PlaceId: " .. tostring(game.PlaceId)
        .. "  •  CAFEÍNA " .. Config.Version
end)

local UnloadRow = rowBase(SystemPage, 48)
local UnloadButton = Instance.new("TextButton")
UnloadButton.Size = UDim2.new(1, -12, 1, -12)
UnloadButton.Position = UDim2.fromOffset(6, 6)
UnloadButton.BackgroundColor3 = Color3.fromRGB(126, 39, 39)
UnloadButton.BorderSizePixel = 0
UnloadButton.Text = "DESCARREGAR MENU / CLEANUP"
UnloadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadButton.TextSize = 13
UnloadButton.Font = Enum.Font.GothamBold
UnloadButton.Parent = UnloadRow
local UnloadCorner = Instance.new("UICorner")
UnloadCorner.CornerRadius = UDim.new(0, 8)
UnloadCorner.Parent = UnloadButton

local function showPage(name)
    clearContent()

    local page = Pages[name]
    if not page then return end

    page.Parent = Content

    for tabName, btn in pairs(TabButtons) do
        btn.BackgroundColor3 = tabName == name
            and Color3.fromRGB(235, 235, 238)
            or Color3.fromRGB(35, 35, 39)

        btn.TextColor3 = tabName == name
            and Color3.fromRGB(20, 20, 22)
            or Color3.fromRGB(230, 230, 233)
    end
end

local function addTab(name, text)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(79, 36)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 39)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(230, 230, 233)
    button.TextSize = 11
    button.Font = Enum.Font.GothamBold
    button.ZIndex = 22
    button.Parent = Tabs

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    button.Activated:Connect(function()
        showPage(name)
    end)

    TabButtons[name] = button
end

addTab("AIM", "AIM")
addTab("ESP", "ESP")
addTab("WEAPON", "ARMA")
addTab("SYSTEM", "SISTEMA")

showPage("AIM")

local function minimize()
    Config.UI.Minimized = true
    Main.Visible = false
    MiniIcon.Visible = true
end

local function restore()
    Config.UI.Minimized = false
    Main.Visible = true
    MiniIcon.Visible = false
end

MinButton.Activated:Connect(minimize)
MiniIcon.Activated:Connect(restore)

-- =========================================================
-- PUBLIC OBJECT / DESTROY
-- =========================================================

local App = {}

function App:Destroy()
    WeaponManager:StopBurst()
    WeaponManager:RestoreAll()
    TargetManager.Current = nil

    for model, state in pairs(Tracker.Entities) do
        if state.Visual then
            safeDestroy(state.Visual.Highlight)
            safeDestroy(state.Visual.Tracer)
            safeDestroy(state.Visual.Info)
            state.Visual = nil
        end
        Tracker.Entities[model] = nil
    end

    ConnectionManager:Clear()
    safeDestroy(Gui)

    if ENV.CAFEINA_TYCOON_DEV == self then
        ENV.CAFEINA_TYCOON_DEV = nil
    end
end

ENV.CAFEINA_TYCOON_DEV = App

CloseButton.Activated:Connect(function()
    App:Destroy()
end)

UnloadButton.Activated:Connect(function()
    App:Destroy()
end)

print("[CAFEÍNA] Menu TYCOON DEV carregado. Build: " .. Config.Version)
