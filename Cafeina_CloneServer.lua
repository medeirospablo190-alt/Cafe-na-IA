-- CAFEÍNA • SERVER CLONES V1.0
-- Coloque este Script em ServerScriptService no seu próprio jogo.
-- Ele cria clones reais/replicados para todos os jogadores a partir de pedidos do menu cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local REMOTE_NAME = "CafeinaCloneRemote"
local FOLDER_NAME = "CafeinaServerClones"
local MAX_CLONES_PER_PLAYER = 20
local CREATE_COOLDOWN = 0.20
local MAX_TRACKS = 8
local MAX_JOINTS = 80

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteEvent") then
    remote:Destroy()
    remote = nil
end

if not remote then
    remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
end

local clonesFolder = Workspace:FindFirstChild(FOLDER_NAME)
if not clonesFolder then
    clonesFolder = Instance.new("Folder")
    clonesFolder.Name = FOLDER_NAME
    clonesFolder.Parent = Workspace
end

local lastCreate = {}
local cloneLists = {}
local sequence = 0

local function finiteNumber(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    if minValue then value = math.max(minValue, value) end
    if maxValue then value = math.min(maxValue, value) end
    return value
end

local function getList(player)
    local list = cloneLists[player]
    if not list then
        list = {}
        cloneLists[player] = list
    end
    return list
end

local function pruneList(player)
    local list = getList(player)
    local newList = {}
    for _, clone in ipairs(list) do
        if clone and clone.Parent then
            table.insert(newList, clone)
        end
    end
    cloneLists[player] = newList
    return newList
end

local function destroyLast(player)
    local list = pruneList(player)
    local clone = table.remove(list)
    if clone and clone.Parent then
        clone:Destroy()
    end
end

local function destroyAll(player)
    local list = pruneList(player)
    for _, clone in ipairs(list) do
        if clone and clone.Parent then
            clone:Destroy()
        end
    end
    cloneLists[player] = {}
end

local function resolveRelativePath(root, path)
    if typeof(path) ~= "table" then
        return nil
    end

    local current = root
    for index, segment in ipairs(path) do
        if index > 12 or type(segment) ~= "string" or #segment > 100 then
            return nil
        end
        current = current and current:FindFirstChild(segment)
        if not current then
            return nil
        end
    end
    return current
end

local function sanitizeClone(clone)
    for _, obj in ipairs(clone:GetDescendants()) do
        if obj:IsA("Script") or obj:IsA("LocalScript") then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.CanCollide = false
            obj.CanTouch = false
            obj.CanQuery = true
            obj.Massless = obj.Name ~= "HumanoidRootPart"
        end
    end

    local humanoid = clone:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.AutoRotate = false
        humanoid.Jump = false
        pcall(function() humanoid.JumpPower = 0 end)
        pcall(function() humanoid.JumpHeight = 0 end)
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end

    local root = clone:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    return humanoid, root
end

local function applyJointSnapshot(clone, joints)
    if typeof(joints) ~= "table" then
        return
    end

    for index, item in ipairs(joints) do
        if index > MAX_JOINTS then
            break
        end

        if typeof(item) == "table" and typeof(item.transform) == "CFrame" then
            local joint = resolveRelativePath(clone, item.path)
            if joint and joint:IsA("Motor6D") then
                joint.Transform = item.transform
            end
        end
    end
end

local function playTrackSnapshot(humanoid, tracks)
    if not humanoid or typeof(tracks) ~= "table" then
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    for index, item in ipairs(tracks) do
        if index > MAX_TRACKS then
            break
        end

        if typeof(item) == "table" and type(item.animationId) == "string" then
            local digits = string.match(item.animationId, "%d+")
            if digits then
                local animation = Instance.new("Animation")
                animation.AnimationId = "rbxassetid://" .. digits

                local ok, track = pcall(function()
                    return animator:LoadAnimation(animation)
                end)

                if ok and track then
                    pcall(function()
                        if type(item.priority) == "string" then
                            local enumValue = Enum.AnimationPriority[item.priority]
                            if enumValue then
                                track.Priority = enumValue
                            end
                        end
                    end)

                    pcall(function()
                        track.Looped = item.looped == true
                    end)

                    local speed = finiteNumber(item.speed, 1, -4, 4)
                    local timePosition = finiteNumber(item.timePosition, 0, 0, 3600)
                    local weight = finiteNumber(item.weight, 1, 0, 1)

                    pcall(function()
                        track:Play(0, weight, speed)
                    end)

                    task.defer(function()
                        pcall(function()
                            if track.Length > 0 then
                                track.TimePosition = math.clamp(timePosition, 0, math.max(0, track.Length - 0.001))
                            else
                                track.TimePosition = timePosition
                            end
                        end)
                    end)
                end

                animation:Destroy()
            end
        end
    end
end

local function createClone(player, snapshot)
    local now = os.clock()
    if now - (lastCreate[player] or 0) < CREATE_COOLDOWN then
        return
    end
    lastCreate[player] = now

    local character = player.Character
    if not character or not character.Parent then
        return
    end

    snapshot = typeof(snapshot) == "table" and snapshot or {}

    character.Archivable = true
    local ok, clone = pcall(function()
        return character:Clone()
    end)
    if not ok or not clone then
        return
    end

    sequence += 1
    clone.Name = string.format("%s_Clone_%03d", player.Name, sequence)

    local humanoid, root = sanitizeClone(clone)
    clone.Parent = clonesFolder

    local pivot = typeof(snapshot.pivot) == "CFrame" and snapshot.pivot or character:GetPivot()
    pcall(function()
        clone:PivotTo(pivot)
    end)

    applyJointSnapshot(clone, snapshot.joints)
    playTrackSnapshot(humanoid, snapshot.tracks)

    if root then
        root.Anchored = true
    end

    local list = pruneList(player)
    table.insert(list, clone)

    while #list > MAX_CLONES_PER_PLAYER do
        local oldest = table.remove(list, 1)
        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end
end

remote.OnServerEvent:Connect(function(player, action, payload)
    if action == "Create" then
        createClone(player, payload)
    elseif action == "DeleteLast" then
        destroyLast(player)
    elseif action == "DeleteAll" then
        destroyAll(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    destroyAll(player)
    cloneLists[player] = nil
    lastCreate[player] = nil
end)
