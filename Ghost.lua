--==============================================================--
-- CAFEÍNA • GHOST FLY COMPACT
-- Um único botão:
-- OFF -> ativa Ghost + Voo 3D
-- ON  -> desativa e leva o corpo para a posição virtual
--==============================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local CONFIG = {
    GUI_NAME = "CafeinaGhostFlyCompact",
    FLY_SPEED = 48,
}

local GhostFlyEnabled = false
local RealCharacter
local RealRoot
local RealHumanoid
local Anchor
local Controls
local RenderConnection

local Saved = {
    cameraSubject = nil,
    cameraType = nil,
    rootAnchored = nil,
    autoRotate = nil,
    walkSpeed = nil,
    jumpPower = nil,
    jumpHeight = nil,
    useJumpPower = nil,
}

pcall(function()
    local PlayerModule = require(
        LocalPlayer.PlayerScripts:WaitForChild("PlayerModule")
    )
    Controls = PlayerModule:GetControls()
end)

local function getMoveVector()
    if Controls then
        local ok, value = pcall(function()
            return Controls:GetMoveVector()
        end)

        if ok and typeof(value) == "Vector3" then
            return value
        end
    end

    return Vector3.zero
end

local function refreshCharacter()
    RealCharacter = LocalPlayer.Character
    if not RealCharacter then
        return false
    end

    RealRoot =
        RealCharacter:FindFirstChild("HumanoidRootPart")
        or RealCharacter:FindFirstChild("UpperTorso")
        or RealCharacter:FindFirstChild("Torso")

    RealHumanoid =
        RealCharacter:FindFirstChildOfClass("Humanoid")

    return RealRoot ~= nil and RealHumanoid ~= nil
end

local function zeroVelocity(root)
    if not root then
        return
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function createAnchor(cf)
    if Anchor then
        Anchor:Destroy()
    end

    Anchor = Instance.new("Part")
    Anchor.Name = "CafeinaGhostAnchor"
    Anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    Anchor.Transparency = 1
    Anchor.Anchored = true
    Anchor.CanCollide = false
    Anchor.CanTouch = false
    Anchor.CanQuery = false
    Anchor.CastShadow = false
    Anchor.CFrame = cf
    Anchor.Parent = Workspace
end

local function saveAndFreeze()
    Saved.rootAnchored = RealRoot.Anchored
    Saved.autoRotate = RealHumanoid.AutoRotate
    Saved.walkSpeed = RealHumanoid.WalkSpeed
    Saved.useJumpPower = RealHumanoid.UseJumpPower

    if Saved.useJumpPower then
        Saved.jumpPower = RealHumanoid.JumpPower
    else
        Saved.jumpHeight = RealHumanoid.JumpHeight
    end

    zeroVelocity(RealRoot)

    RealRoot.Anchored = true
    RealHumanoid.AutoRotate = false
    RealHumanoid.WalkSpeed = 0

    pcall(function()
        if RealHumanoid.UseJumpPower then
            RealHumanoid.JumpPower = 0
        else
            RealHumanoid.JumpHeight = 0
        end
    end)
end

local function restoreCharacter()
    if not refreshCharacter() then
        return
    end

    pcall(function()
        RealRoot.Anchored = Saved.rootAnchored == true
    end)

    if Saved.autoRotate ~= nil then
        RealHumanoid.AutoRotate = Saved.autoRotate
    end

    if Saved.walkSpeed ~= nil then
        RealHumanoid.WalkSpeed = Saved.walkSpeed
    end

    pcall(function()
        if Saved.useJumpPower then
            RealHumanoid.JumpPower = Saved.jumpPower or 50
        else
            RealHumanoid.JumpHeight = Saved.jumpHeight or 7.2
        end
    end)

    zeroVelocity(RealRoot)
end

local function getFlyDirection()
    local move = getMoveVector()

    local direction =
        Camera.CFrame.RightVector * move.X
        + Camera.CFrame.LookVector * (-move.Z)

    if direction.Magnitude > 1 then
        direction = direction.Unit
    end

    return direction
end

local function updateGhost(dt)
    if not GhostFlyEnabled or not Anchor then
        return
    end

    if RealRoot and RealRoot.Parent then
        zeroVelocity(RealRoot)
    end

    local direction = getFlyDirection()

    if direction.Magnitude > 0.001 then
        Anchor.CFrame =
            CFrame.new(
                Anchor.Position
                + direction
                * CONFIG.FLY_SPEED
                * dt
            )
    end
end

local function enableGhostFly()
    if GhostFlyEnabled then
        return true
    end

    if not refreshCharacter() then
        return false
    end

    Saved.cameraSubject = Camera.CameraSubject
    Saved.cameraType = Camera.CameraType

    local startCF = RealRoot.CFrame

    saveAndFreeze()
    createAnchor(startCF)

    Camera.CameraType = Enum.CameraType.Custom
    Camera.CameraSubject = Anchor

    GhostFlyEnabled = true

    if RenderConnection then
        RenderConnection:Disconnect()
    end

    RenderConnection =
        RunService.RenderStepped:Connect(updateGhost)

    return true
end

local function disableGhostFly(moveReal)
    if not GhostFlyEnabled then
        return
    end

    local destination =
        Anchor and CFrame.new(Anchor.Position) or nil

    GhostFlyEnabled = false

    if RenderConnection then
        RenderConnection:Disconnect()
        RenderConnection = nil
    end

    restoreCharacter()

    if moveReal and destination and refreshCharacter() then
        zeroVelocity(RealRoot)

        local ok = pcall(function()
            RealCharacter:PivotTo(destination)
        end)

        if not ok then
            pcall(function()
                RealRoot.CFrame = destination
            end)
        end

        zeroVelocity(RealRoot)
    end

    Camera.CameraType =
        Saved.cameraType or Enum.CameraType.Custom

    if RealHumanoid then
        Camera.CameraSubject = RealHumanoid
    elseif Saved.cameraSubject then
        Camera.CameraSubject = Saved.cameraSubject
    end

    if Anchor then
        Anchor:Destroy()
        Anchor = nil
    end
end

pcall(function()
    local old = CoreGui:FindFirstChild(CONFIG.GUI_NAME)
    if old then
        old:Destroy()
    end
end)

pcall(function()
    if gethui then
        local old = gethui():FindFirstChild(CONFIG.GUI_NAME)
        if old then
            old:Destroy()
        end
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

local parent = CoreGui
pcall(function()
    if gethui then
        parent = gethui()
    end
end)
Gui.Parent = parent

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(180, 78)
Main.Position = UDim2.new(0.5, -90, 0.72, -39)
Main.BackgroundColor3 = Color3.fromRGB(8, 8, 9)
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(44, 44, 48)
MainStroke.Parent = Main

local Header = Instance.new("TextLabel")
Header.Size = UDim2.new(1, -12, 0, 22)
Header.Position = UDim2.fromOffset(6, 4)
Header.BackgroundTransparency = 1
Header.Text = "CAFEÍNA"
Header.TextColor3 = Color3.fromRGB(210, 210, 214)
Header.TextSize = 10
Header.Font = Enum.Font.GothamBold
Header.Parent = Main

local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(1, -16, 0, 42)
Toggle.Position = UDim2.fromOffset(8, 29)
Toggle.BackgroundColor3 = Color3.fromRGB(23, 23, 26)
Toggle.BorderSizePixel = 0
Toggle.Text = "GHOST FLY: OFF"
Toggle.TextColor3 = Color3.fromRGB(244, 244, 246)
Toggle.TextSize = 12
Toggle.Font = Enum.Font.GothamBold
Toggle.AutoButtonColor = false
Toggle.Parent = Main

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = Toggle

local function updateButton()
    if GhostFlyEnabled then
        Toggle.Text = "GHOST FLY: ON"
        Toggle.BackgroundColor3 = Color3.fromRGB(50, 175, 92)
    else
        Toggle.Text = "GHOST FLY: OFF"
        Toggle.BackgroundColor3 = Color3.fromRGB(23, 23, 26)
    end
end

Toggle.Activated:Connect(function()
    if not GhostFlyEnabled then
        enableGhostFly()
    else
        disableGhostFly(true)
    end

    updateButton()
end)

local dragging = false
local dragStart
local startPosition
local dragInput

Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
    end
end)

Main.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart

        Main.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    if GhostFlyEnabled then
        GhostFlyEnabled = false

        if RenderConnection then
            RenderConnection:Disconnect()
            RenderConnection = nil
        end

        if Anchor then
            Anchor:Destroy()
            Anchor = nil
        end

        task.wait(0.5)
        refreshCharacter()

        Camera.CameraType = Enum.CameraType.Custom

        if RealHumanoid then
            Camera.CameraSubject = RealHumanoid
        end

        updateButton()
    end
end)

refreshCharacter()
updateButton()

print("[CAFEÍNA] Ghost Fly Compact carregado.")
