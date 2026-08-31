--==============================================================--
-- OUROBOROS-STYLE • COMPLETE SAFE / RED-TEAM BUILD
-- Steal An Egg inspired interface
-- Mobile / Android friendly
--
-- PURPOSE
--   • Full compact UI inspired by the analyzed Ouroboros layout
--   • Feature toggles / filters / status
--   • Safe Adapter layer for YOUR OWN game APIs
--   • Studio-only adversarial RemoteEvent/RemoteFunction validation
--   • Logs of accepted/rejected/error outcomes
--
-- SAFETY
--   • No remote discovery
--   • No executor hooks
--   • No anti-cheat bypass
--   • No live exploitation
--   • Remote red-team tests refuse to run outside Roblox Studio
--
-- Recommended placement:
--   StarterPlayer > StarterPlayerScripts > LocalScript
--==============================================================--

--==============================================================--
-- SERVICES
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    Name = "OUROBOROS • COMPLETE",
    Subtitle = "STEAL AN EGG • SAFE RED TEAM",
    GuiName = "OuroborosCompleteSafe",

    StudioOnlyRemoteTests = true,

    MaxLogEntries = 400,
    TestDelay = 0.35,

    WindowSize = Vector2.new(370, 560),

    -- Replace paths below with remotes from YOUR OWN experience.
    RemoteMap = {
        AskCollect = {
            path = {"Packages","Networking","RE","Egg","AskCollect"},
        },

        RequestPlaceEgg = {
            path = {"Packages","Networking","RF","Egg","RequestPlaceEgg"},
        },

        RequestHatchEgg = {
            path = {"Packages","Networking","RF","Egg","RequestHatchEgg"},
        },

        AskWearStill = {
            path = {"Packages","Networking","RF","Treadmill","AskWearStill"},
        },

        AskDoff = {
            path = {"Packages","Networking","RE","Treadmill","AskDoff"},
        },

        AskBaseTierRaise = {
            path = {"Packages","Networking","RF","Base","AskBaseTierRaise"},
        },

        InsertFusePet = {
            path = {"Packages","Networking","RE","Fuse","INSERT_MOB"},
        },

        StartFuse = {
            path = {"Packages","Networking","RF","Fuse","START_FUSE"},
        },

        CompleteFuseReveal = {
            path = {"Packages","Networking","RF","Fuse","COMPLETE_REVEAL"},
        },

        ClaimIndex = {
            path = {"Packages","Networking","RF","Index","Claim"},
        },

        ClaimOfflineEarnings = {
            path = {"Packages","Networking","RF","Profile","ClaimOfflineEarnings"},
        },
    }
}

--==============================================================--
-- STATE
--==============================================================--

local State = {
    -- Egg
    AutoSteal = false,
    AutoReturn = false,
    AutoDropEgg = false,
    AutoPlaceEggs = false,
    AutoHatch = false,
    AutoSellEggs = false,

    -- Pets
    EquipBestPet = false,
    AutoFuse = false,
    ClaimIndex = false,

    -- Progression
    AutoTreadmill = false,
    AutoUpgradeBase = false,
    BuyBestTrail = false,

    -- Misc
    ClaimOfflineEarnings = false,
    MonsterHelper = false,

    -- Filters
    SelectedRarity = "Any",
    SelectedMutation = "Any",
    MinWeight = 0,

    -- Runtime
    Status = "Idle",
    LastAction = "-",
}

--==============================================================--
-- TEST CONTEXT
-- Replace with fixtures in YOUR Studio test place.
--==============================================================--

local TestContext = {
    OwnEggUid = "TEST_OWN_EGG",
    ForeignEggUid = "TEST_FOREIGN_EGG",
    NonexistentEggUid = "TEST_MISSING_EGG",

    OwnPetUid = "TEST_OWN_PET",
    ForeignPetUid = "TEST_FOREIGN_PET",
    NonexistentPetUid = "TEST_MISSING_PET",

    OwnPlotId = "TEST_OWN_PLOT",
    ForeignPlotId = "TEST_FOREIGN_PLOT",

    RequestedBaseTier = 999,
}

--==============================================================--
-- SAFE ADAPTER LAYER
-- Connect these to legitimate APIs in YOUR OWN game.
--==============================================================--

local Adapter = {
    AutoSteal = nil,
    AutoReturn = nil,
    AutoDropEgg = nil,
    AutoPlaceEggs = nil,
    AutoHatch = nil,
    AutoSellEggs = nil,

    EquipBestPet = nil,
    AutoFuse = nil,
    ClaimIndex = nil,

    AutoTreadmill = nil,
    AutoUpgradeBase = nil,
    BuyBestTrail = nil,

    ClaimOfflineEarnings = nil,
    MonsterHelper = nil,
}

local function callAdapter(name, enabled)
    local fn = Adapter[name]
    if typeof(fn) ~= "function" then
        State.LastAction = name .. " (no adapter)"
        return false, "adapter_not_connected"
    end

    local ok, result = pcall(fn, enabled, State)
    if not ok then
        State.LastAction = name .. " adapter error"
        warn("[OUROBOROS COMPLETE] Adapter error:", name, result)
        return false, tostring(result)
    end

    State.LastAction = name
    return true, result
end

--==============================================================--
-- REMOTE RESOLUTION
-- No discovery: exact configured paths only.
--==============================================================--

local ResolvedRemotes = {}

local function resolvePath(root, path)
    local node = root

    for _, name in ipairs(path) do
        node = node:FindFirstChild(name)
        if not node then
            return nil
        end
    end

    return node
end

local function resolveRemotes()
    table.clear(ResolvedRemotes)

    for name, spec in pairs(CONFIG.RemoteMap) do
        ResolvedRemotes[name] = resolvePath(ReplicatedStorage, spec.path)
    end
end

resolveRemotes()

local function redTeamAllowed()
    if CONFIG.StudioOnlyRemoteTests and not RunService:IsStudio() then
        return false, "Studio-only red-team validation."
    end

    return true
end

--==============================================================--
-- LOG SYSTEM
--==============================================================--

local Logs = {}

local function pushLog(category, name, outcome, detail)
    Logs[#Logs + 1] = {
        time = os.clock(),
        category = tostring(category),
        name = tostring(name),
        outcome = tostring(outcome),
        detail = tostring(detail),
    }

    while #Logs > CONFIG.MaxLogEntries do
        table.remove(Logs, 1)
    end
end

local function clearLogs()
    table.clear(Logs)
end

--==============================================================--
-- REMOTE WRAPPER
-- Studio-only for adversarial tests.
--==============================================================--

local function invokeConfiguredRemote(name, ...)
    local allowed, why = redTeamAllowed()
    if not allowed then
        return false, why
    end

    local remote = ResolvedRemotes[name]
    if not remote then
        return false, "remote_not_found:" .. tostring(name)
    end

    local args = table.pack(...)

    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(function()
            remote:FireServer(table.unpack(args, 1, args.n))
        end)

        if not ok then
            return false, tostring(err)
        end

        return true, "fired"
    end

    if remote:IsA("RemoteFunction") then
        local ok, a, b, c, d = pcall(function()
            return remote:InvokeServer(table.unpack(args, 1, args.n))
        end)

        if not ok then
            return false, tostring(a)
        end

        return true, a, b, c, d
    end

    return false, "unsupported_remote_class:" .. remote.ClassName
end

--==============================================================--
-- RED TEAM CASES
-- These try invalid actions and EXPECT server rejection.
--==============================================================--

local Tests = {}

-- Egg collect

Tests.CollectNonexistentEgg = function()
    return invokeConfiguredRemote(
        "AskCollect",
        TestContext.NonexistentEggUid
    )
end

Tests.CollectForeignEgg = function()
    return invokeConfiguredRemote(
        "AskCollect",
        TestContext.ForeignEggUid
    )
end

Tests.CollectMalformedEgg = function()
    return invokeConfiguredRemote(
        "AskCollect",
        {
            uid = TestContext.ForeignEggUid,
            owner = -1,
            fake = true,
        }
    )
end

-- Place

Tests.PlaceForeignEggInOwnPlot = function()
    return invokeConfiguredRemote(
        "RequestPlaceEgg",
        TestContext.ForeignEggUid,
        TestContext.OwnPlotId
    )
end

Tests.PlaceOwnEggInForeignPlot = function()
    return invokeConfiguredRemote(
        "RequestPlaceEgg",
        TestContext.OwnEggUid,
        TestContext.ForeignPlotId
    )
end

Tests.PlaceNonexistentEgg = function()
    return invokeConfiguredRemote(
        "RequestPlaceEgg",
        TestContext.NonexistentEggUid,
        TestContext.OwnPlotId
    )
end

-- Hatch

Tests.HatchForeignEgg = function()
    return invokeConfiguredRemote(
        "RequestHatchEgg",
        TestContext.ForeignEggUid
    )
end

Tests.HatchNonexistentEgg = function()
    return invokeConfiguredRemote(
        "RequestHatchEgg",
        TestContext.NonexistentEggUid
    )
end

Tests.HatchMalformedPayload = function()
    return invokeConfiguredRemote(
        "RequestHatchEgg",
        {
            uid = TestContext.ForeignEggUid,
            ready = true,
            fakeReady = true,
        }
    )
end

-- Treadmill

Tests.TreadmillAskWearStillOffBelt = function()
    return invokeConfiguredRemote("AskWearStill")
end

Tests.TreadmillAskDoffWithoutMount = function()
    return invokeConfiguredRemote("AskDoff")
end

-- Base

Tests.BaseTierHugeJump = function()
    return invokeConfiguredRemote(
        "AskBaseTierRaise",
        TestContext.RequestedBaseTier
    )
end

Tests.BaseTierMalformed = function()
    return invokeConfiguredRemote(
        "AskBaseTierRaise",
        {
            tier = math.huge,
            cost = 0,
            fake = true,
        }
    )
end

-- Fuse

Tests.FuseForeignPet = function()
    return invokeConfiguredRemote(
        "InsertFusePet",
        TestContext.ForeignPetUid
    )
end

Tests.FuseNonexistentPet = function()
    return invokeConfiguredRemote(
        "InsertFusePet",
        TestContext.NonexistentPetUid
    )
end

Tests.StartEmptyFuse = function()
    return invokeConfiguredRemote("StartFuse")
end

Tests.CompleteRevealWithoutFuse = function()
    return invokeConfiguredRemote("CompleteFuseReveal")
end

-- Rewards

Tests.ClaimIndexInvalid = function()
    return invokeConfiguredRemote(
        "ClaimIndex",
        "TEST_NOT_DISCOVERED"
    )
end

Tests.ClaimOfflineEarningsTwice = function()
    local ok1, a1 = invokeConfiguredRemote("ClaimOfflineEarnings")
    local ok2, a2 = invokeConfiguredRemote("ClaimOfflineEarnings")

    if not ok1 then
        return false, a1
    end

    return ok2, a2
end

local TestOrder = {
    "CollectNonexistentEgg",
    "CollectForeignEgg",
    "CollectMalformedEgg",

    "PlaceForeignEggInOwnPlot",
    "PlaceOwnEggInForeignPlot",
    "PlaceNonexistentEgg",

    "HatchForeignEgg",
    "HatchNonexistentEgg",
    "HatchMalformedPayload",

    "TreadmillAskWearStillOffBelt",
    "TreadmillAskDoffWithoutMount",

    "BaseTierHugeJump",
    "BaseTierMalformed",

    "FuseForeignPet",
    "FuseNonexistentPet",
    "StartEmptyFuse",
    "CompleteRevealWithoutFuse",

    "ClaimIndexInvalid",
    "ClaimOfflineEarningsTwice",
}

--==============================================================--
-- RUNNER
--==============================================================--

local Runner = {
    Running = false,
    Delay = CONFIG.TestDelay,
    Completed = 0,
    Total = #TestOrder,
}

local function runOneTest(testName)
    local fn = Tests[testName]

    if typeof(fn) ~= "function" then
        pushLog("TEST", testName, "SKIP", "missing_test")
        return false
    end

    local ok, a, b, c = pcall(fn)

    if not ok then
        pushLog("TEST", testName, "ERROR", tostring(a))
        return false
    end

    if a == true then
        pushLog("TEST", testName, "SENT", tostring(b))
    else
        pushLog("TEST", testName, "BLOCKED", tostring(b))
    end

    return a, b, c
end

function Runner.RunAll()
    local allowed, why = redTeamAllowed()

    if not allowed then
        pushLog("SYSTEM", "RunAll", "BLOCKED", why)
        State.Status = why
        return
    end

    if Runner.Running then
        return
    end

    Runner.Running = true
    Runner.Completed = 0
    State.Status = "Running validation tests..."

    task.spawn(function()
        for _, testName in ipairs(TestOrder) do
            if not Runner.Running then
                break
            end

            runOneTest(testName)

            Runner.Completed += 1

            task.wait(Runner.Delay)
        end

        Runner.Running = false
        State.Status = "Validation complete"
    end)
end

function Runner.Stop()
    Runner.Running = false
    State.Status = "Stopped"
end

--==============================================================--
-- UI CLEANUP
--==============================================================--

pcall(function()
    local old = PlayerGui:FindFirstChild(CONFIG.GuiName)
    if old then
        old:Destroy()
    end
end)

--==============================================================--
-- UI ROOT
--==============================================================--

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GuiName
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(
    CONFIG.WindowSize.X,
    CONFIG.WindowSize.Y
)
Main.Position = UDim2.new(
    0.5,
    -CONFIG.WindowSize.X / 2,
    0.5,
    -CONFIG.WindowSize.Y / 2
)
Main.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
Main.BorderSizePixel = 0
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(58, 58, 68)
MainStroke.Thickness = 1
MainStroke.Transparency = 0.1
MainStroke.Parent = Main

--==============================================================--
-- HEADER
--==============================================================--

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 62)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(15, 8)
Title.Size = UDim2.new(1, -105, 0, 24)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 17
Title.TextColor3 = Color3.fromRGB(242, 242, 246)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = CONFIG.Name
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(15, 32)
Subtitle.Size = UDim2.new(1, -105, 0, 18)
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 10
Subtitle.TextColor3 = Color3.fromRGB(135, 135, 147)
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Text = CONFIG.Subtitle
Subtitle.Parent = Header

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.fromOffset(34, 34)
MinimizeButton.Position = UDim2.new(1, -82, 0, 13)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(27, 27, 32)
MinimizeButton.BorderSizePixel = 0
MinimizeButton.Text = "—"
MinimizeButton.TextColor3 = Color3.fromRGB(235, 235, 240)
MinimizeButton.TextSize = 17
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.AutoButtonColor = false
MinimizeButton.Parent = Header
Instance.new("UICorner", MinimizeButton).CornerRadius = UDim.new(0, 8)

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.fromOffset(34, 34)
CloseButton.Position = UDim2.new(1, -42, 0, 13)
CloseButton.BackgroundColor3 = Color3.fromRGB(66, 23, 28)
CloseButton.BorderSizePixel = 0
CloseButton.Text = "×"
CloseButton.TextColor3 = Color3.fromRGB(255, 220, 224)
CloseButton.TextSize = 18
CloseButton.Font = Enum.Font.GothamBold
CloseButton.AutoButtonColor = false
CloseButton.Parent = Header
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 8)

local Divider = Instance.new("Frame")
Divider.Position = UDim2.fromOffset(12, 60)
Divider.Size = UDim2.new(1, -24, 0, 1)
Divider.BackgroundColor3 = Color3.fromRGB(44, 44, 52)
Divider.BorderSizePixel = 0
Divider.Parent = Main

--==============================================================--
-- STATUS
--==============================================================--

local StatusBar = Instance.new("Frame")
StatusBar.Position = UDim2.fromOffset(12, 68)
StatusBar.Size = UDim2.new(1, -24, 0, 44)
StatusBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
StatusBar.BorderSizePixel = 0
StatusBar.Parent = Main
Instance.new("UICorner", StatusBar).CornerRadius = UDim.new(0, 9)

local StatusText = Instance.new("TextLabel")
StatusText.BackgroundTransparency = 1
StatusText.Position = UDim2.fromOffset(10, 3)
StatusText.Size = UDim2.new(1, -20, 0, 19)
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextColor3 = Color3.fromRGB(220, 220, 227)
StatusText.Font = Enum.Font.GothamSemibold
StatusText.TextSize = 10
StatusText.Text = "STATUS: Idle"
StatusText.Parent = StatusBar

local StatusDetail = Instance.new("TextLabel")
StatusDetail.BackgroundTransparency = 1
StatusDetail.Position = UDim2.fromOffset(10, 21)
StatusDetail.Size = UDim2.new(1, -20, 0, 18)
StatusDetail.TextXAlignment = Enum.TextXAlignment.Left
StatusDetail.TextColor3 = Color3.fromRGB(130, 130, 140)
StatusDetail.Font = Enum.Font.Gotham
StatusDetail.TextSize = 9
StatusDetail.Text = RunService:IsStudio()
    and "Studio red-team: enabled"
    or "Remote tests disabled outside Studio"
StatusDetail.Parent = StatusBar

--==============================================================--
-- TABS
--==============================================================--

local TabBar = Instance.new("Frame")
TabBar.Position = UDim2.fromOffset(12, 120)
TabBar.Size = UDim2.new(1, -24, 0, 38)
TabBar.BackgroundTransparency = 1
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.Padding = UDim.new(0, 5)
TabLayout.Parent = TabBar

local Content = Instance.new("Frame")
Content.Position = UDim2.fromOffset(12, 166)
Content.Size = UDim2.new(1, -24, 1, -178)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Pages = {}
local TabButtons = {}

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 92)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.Visible = false
    page.Parent = Content

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.Parent = page

    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = page

    Pages[name] = page
    return page
end

local function selectPage(name)
    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end

    for tabName, button in pairs(TabButtons) do
        local active = tabName == name

        button.BackgroundColor3 =
            active and Color3.fromRGB(45, 45, 54)
            or Color3.fromRGB(25, 25, 30)

        button.TextColor3 =
            active and Color3.fromRGB(245, 245, 248)
            or Color3.fromRGB(165, 165, 176)
    end
end

local function createTab(text, pageName)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.2, -4, 1, 0)
    button.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(165, 165, 176)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.AutoButtonColor = false
    button.Parent = TabBar

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

    button.MouseButton1Click:Connect(function()
        selectPage(pageName)
    end)

    TabButtons[pageName] = button
    return button
end

--==============================================================--
-- UI COMPONENTS
--==============================================================--

local function createSection(parent, text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 24)
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(120, 120, 132)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.Text = string.upper(text)
    label.Parent = parent
    return label
end

local function createToggle(parent, label, stateKey)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundColor3 = Color3.fromRGB(21, 21, 26)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Position = UDim2.fromOffset(12, 0)
    text.Size = UDim2.new(1, -75, 1, 0)
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextColor3 = Color3.fromRGB(228, 228, 234)
    text.Font = Enum.Font.GothamMedium
    text.TextSize = 12
    text.Text = label
    text.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.fromOffset(46, 24)
    toggle.Position = UDim2.new(1, -58, 0.5, -12)
    toggle.BorderSizePixel = 0
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = row
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(18, 18)
    dot.BorderSizePixel = 0
    dot.Parent = toggle
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local function render()
        local enabled = State[stateKey] == true

        toggle.BackgroundColor3 =
            enabled and Color3.fromRGB(55, 126, 79)
            or Color3.fromRGB(48, 48, 56)

        dot.BackgroundColor3 =
            enabled and Color3.fromRGB(238, 255, 242)
            or Color3.fromRGB(178, 178, 188)

        TweenService:Create(
            dot,
            TweenInfo.new(0.12),
            {
                Position = enabled
                    and UDim2.fromOffset(25, 3)
                    or UDim2.fromOffset(3, 3)
            }
        ):Play()
    end

    toggle.MouseButton1Click:Connect(function()
        State[stateKey] = not State[stateKey]
        render()

        pushLog(
            "UI",
            stateKey,
            State[stateKey] and "ON" or "OFF",
            "adapter toggle"
        )

        callAdapter(stateKey, State[stateKey])
    end)

    render()

    return row
end

local function createButton(parent, label, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 42)
    button.BackgroundColor3 = Color3.fromRGB(29, 29, 35)
    button.BorderSizePixel = 0
    button.Text = label
    button.TextColor3 = Color3.fromRGB(235, 235, 240)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.AutoButtonColor = false
    button.Parent = parent
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)

    button.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)

        if not ok then
            pushLog("UI", label, "ERROR", err)
        end
    end)

    return button
end

local function createDropdown(parent, label, stateKey, values)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 68)
    box.BackgroundColor3 = Color3.fromRGB(21, 21, 26)
    box.BorderSizePixel = 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 9)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(11, 3)
    title.Size = UDim2.new(1, -22, 0, 22)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = label
    title.TextColor3 = Color3.fromRGB(160, 160, 170)
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 10
    title.Parent = box

    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(10, 29)
    button.Size = UDim2.new(1, -20, 0, 30)
    button.BackgroundColor3 = Color3.fromRGB(31, 31, 37)
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.fromRGB(238, 238, 243)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 11
    button.AutoButtonColor = false
    button.Parent = box
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)

    local index = 1

    for i, value in ipairs(values) do
        if value == State[stateKey] then
            index = i
            break
        end
    end

    local function render()
        State[stateKey] = values[index]
        button.Text = tostring(values[index])
    end

    button.MouseButton1Click:Connect(function()
        index += 1

        if index > #values then
            index = 1
        end

        render()

        pushLog(
            "FILTER",
            stateKey,
            "SET",
            State[stateKey]
        )
    end)

    render()

    return box
end

local function createNumberField(parent, label, stateKey)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 60)
    box.BackgroundColor3 = Color3.fromRGB(21, 21, 26)
    box.BorderSizePixel = 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 9)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(11, 0)
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = label
    title.TextColor3 = Color3.fromRGB(175, 175, 184)
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 11
    title.Parent = box

    local input = Instance.new("TextBox")
    input.Position = UDim2.new(1, -108, 0.5, -17)
    input.Size = UDim2.fromOffset(96, 34)
    input.BackgroundColor3 = Color3.fromRGB(31, 31, 37)
    input.BorderSizePixel = 0
    input.TextColor3 = Color3.fromRGB(240, 240, 244)
    input.PlaceholderText = "0"
    input.Text = tostring(State[stateKey] or 0)
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.GothamSemibold
    input.TextSize = 12
    input.Parent = box
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 7)

    input.FocusLost:Connect(function()
        local value = tonumber(input.Text)

        if not value then
            input.Text = tostring(State[stateKey] or 0)
            return
        end

        value = math.max(0, value)
        State[stateKey] = value
        input.Text = tostring(value)

        pushLog(
            "FILTER",
            stateKey,
            "SET",
            tostring(value)
        )
    end)

    return box
end

--==============================================================--
-- PAGES
--==============================================================--

local EggPage = createPage("Egg")
local PetsPage = createPage("Pets")
local ProgressPage = createPage("Progress")
local RedTeamPage = createPage("RedTeam")
local LogsPage = createPage("Logs")

createTab("EGG", "Egg")
createTab("PETS", "Pets")
createTab("PROGRESS", "Progress")
createTab("RED TEAM", "RedTeam")
createTab("LOGS", "Logs")

-- Egg page

createSection(EggPage, "Egg Automation")
createToggle(EggPage, "Auto Steal Egg", "AutoSteal")
createToggle(EggPage, "Auto Return to Base", "AutoReturn")
createToggle(EggPage, "Auto Drop Egg", "AutoDropEgg")
createToggle(EggPage, "Auto Place Eggs", "AutoPlaceEggs")
createToggle(EggPage, "Auto Hatch Ready", "AutoHatch")
createToggle(EggPage, "Auto Sell Eggs", "AutoSellEggs")

createSection(EggPage, "Filters")

createDropdown(
    EggPage,
    "Rarity",
    "SelectedRarity",
    {
        "Any",
        "Rare",
        "Legendary",
        "Mythic",
        "Cosmic",
        "Secret",
        "Eternal",
        "Divine",
    }
)

createDropdown(
    EggPage,
    "Mutation",
    "SelectedMutation",
    {
        "Any",
        "None",
        "Golden",
        "Silver",
        "Rainbow",
        "Mutated",
    }
)

createNumberField(
    EggPage,
    "Minimum Weight / KG",
    "MinWeight"
)

-- Pets

createSection(PetsPage, "Pets")
createToggle(PetsPage, "Equip Best Pet", "EquipBestPet")
createToggle(PetsPage, "Auto Fuse", "AutoFuse")
createToggle(PetsPage, "Claim Pet Index", "ClaimIndex")

createSection(PetsPage, "Misc")
createToggle(
    PetsPage,
    "Claim Offline Earnings",
    "ClaimOfflineEarnings"
)
createToggle(
    PetsPage,
    "Monster Helper",
    "MonsterHelper"
)

-- Progress

createSection(ProgressPage, "Progression")
createToggle(
    ProgressPage,
    "Auto Treadmill",
    "AutoTreadmill"
)
createToggle(
    ProgressPage,
    "Auto Upgrade Base",
    "AutoUpgradeBase"
)
createToggle(
    ProgressPage,
    "Buy Best Trail",
    "BuyBestTrail"
)

local safetyInfo = Instance.new("TextLabel")
safetyInfo.Size = UDim2.new(1, 0, 0, 115)
safetyInfo.BackgroundColor3 = Color3.fromRGB(21, 21, 26)
safetyInfo.BorderSizePixel = 0
safetyInfo.TextWrapped = true
safetyInfo.TextXAlignment = Enum.TextXAlignment.Left
safetyInfo.TextYAlignment = Enum.TextYAlignment.Top
safetyInfo.TextColor3 = Color3.fromRGB(155, 155, 168)
safetyInfo.Font = Enum.Font.Gotham
safetyInfo.TextSize = 10
safetyInfo.Text =
    "Adapter mode\n\n"
    .. "The feature toggles above are UI/state hooks. "
    .. "Connect Adapter callbacks to legitimate client/server APIs in your own experience."
safetyInfo.Parent = ProgressPage
Instance.new("UICorner", safetyInfo).CornerRadius = UDim.new(0, 9)

local safetyPad = Instance.new("UIPadding")
safetyPad.PaddingTop = UDim.new(0, 10)
safetyPad.PaddingLeft = UDim.new(0, 11)
safetyPad.PaddingRight = UDim.new(0, 11)
safetyPad.Parent = safetyInfo

-- Red Team

createSection(RedTeamPage, "Validation Harness")

createButton(
    RedTeamPage,
    "RESOLVE CONFIGURED REMOTES",
    function()
        resolveRemotes()

        local found = 0
        local total = 0

        for _, remote in pairs(ResolvedRemotes) do
            total += 1
            if remote then
                found += 1
            end
        end

        pushLog(
            "SYSTEM",
            "ResolveRemotes",
            "DONE",
            ("%d/%d found"):format(found, total)
        )

        State.Status =
            ("%d/%d configured remotes found"):format(found, total)
    end
)

createButton(
    RedTeamPage,
    "RUN ALL VALIDATION TESTS",
    function()
        resolveRemotes()
        Runner.RunAll()
    end
)

createButton(
    RedTeamPage,
    "STOP TESTS",
    function()
        Runner.Stop()
    end
)

createSection(RedTeamPage, "Individual Cases")

for _, testName in ipairs(TestOrder) do
    createButton(
        RedTeamPage,
        testName,
        function()
            resolveRemotes()
            runOneTest(testName)
        end
    )
end

-- Logs page

createSection(LogsPage, "Logs")

local LogContainer = Instance.new("Frame")
LogContainer.Size = UDim2.new(1, 0, 0, 310)
LogContainer.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
LogContainer.BorderSizePixel = 0
LogContainer.Parent = LogsPage
Instance.new("UICorner", LogContainer).CornerRadius = UDim.new(0, 9)

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Position = UDim2.fromOffset(6, 6)
LogScroll.Size = UDim2.new(1, -12, 1, -12)
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = 3
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.CanvasSize = UDim2.fromOffset(0, 0)
LogScroll.Parent = LogContainer

local LogLayout = Instance.new("UIListLayout")
LogLayout.Padding = UDim.new(0, 3)
LogLayout.Parent = LogScroll

local function refreshLogUI()
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local startIndex = math.max(1, #Logs - 80)

    for i = startIndex, #Logs do
        local item = Logs[i]

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -4, 0, 31)
        label.BackgroundTransparency = 1
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Font = Enum.Font.Code
        label.TextSize = 9
        label.TextColor3 = Color3.fromRGB(205, 205, 214)
        label.Text =
            ("[%s] %s/%s • %s")
            :format(
                item.outcome,
                item.category,
                item.name,
                item.detail
            )
        label.Parent = LogScroll
    end
end

createButton(
    LogsPage,
    "CLEAR LOGS",
    function()
        clearLogs()
        refreshLogUI()
        State.Status = "Logs cleared"
    end
)

createButton(
    LogsPage,
    "PRINT JSON LOG",
    function()
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(Logs)
        end)

        if ok then
            print("[OUROBOROS COMPLETE LOG]")
            print(encoded)

            pushLog(
                "SYSTEM",
                "PrintLog",
                "DONE",
                "JSON printed to output"
            )
        else
            pushLog(
                "SYSTEM",
                "PrintLog",
                "ERROR",
                encoded
            )
        end
    end
)

--==============================================================--
-- MINI BUTTON
--==============================================================--

local Mini = Instance.new("TextButton")
Mini.Name = "Mini"
Mini.Size = UDim2.fromOffset(56, 56)
Mini.Position = UDim2.new(0.5, -28, 0.72, -28)
Mini.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
Mini.BorderSizePixel = 0
Mini.Text = "O"
Mini.TextColor3 = Color3.fromRGB(240, 240, 245)
Mini.TextSize = 20
Mini.Font = Enum.Font.GothamBold
Mini.Visible = false
Mini.AutoButtonColor = false
Mini.Parent = Gui
Instance.new("UICorner", Mini).CornerRadius = UDim.new(1, 0)

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Color3.fromRGB(68, 68, 80)
MiniStroke.Thickness = 1
MiniStroke.Parent = Mini

local function minimize()
    Main.Visible = false
    Mini.Visible = true
end

local function restore()
    Mini.Visible = false
    Main.Visible = true
end

MinimizeButton.MouseButton1Click:Connect(minimize)
Mini.MouseButton1Click:Connect(restore)

CloseButton.MouseButton1Click:Connect(function()
    Runner.Stop()
    Gui:Destroy()
end)

--==============================================================--
-- DRAGGING
--==============================================================--

local function makeDraggable(guiObject, handle)
    local dragging = false
    local dragStart
    local startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        local delta = input.Position - dragStart

        guiObject.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

makeDraggable(Main, Header)
makeDraggable(Mini, Mini)

--==============================================================--
-- LIVE UI UPDATE
--==============================================================--

task.spawn(function()
    local previousLogCount = -1

    while Gui.Parent do
        StatusText.Text =
            "STATUS: "
            .. tostring(State.Status)

        StatusDetail.Text =
            (
                "Tests %d/%d • Last: %s • %s"
            ):format(
                Runner.Completed,
                Runner.Total,
                tostring(State.LastAction),
                RunService:IsStudio()
                    and "Studio"
                    or "Live-safe"
            )

        if #Logs ~= previousLogCount then
            previousLogCount = #Logs
            refreshLogUI()
        end

        task.wait(0.2)
    end
end)

--==============================================================--
-- DEFAULT PAGE
--==============================================================--

selectPage("Egg")

--==============================================================--
-- EXAMPLE ADAPTERS FOR YOUR OWN GAME
-- Replace with legitimate APIs that YOU control.
--==============================================================--

--[[
Adapter.AutoTreadmill = function(enabled, state)
    -- Example:
    -- YourClientController:SetAutoTreadmill(enabled)
end

Adapter.AutoPlaceEggs = function(enabled, state)
    -- Example:
    -- YourEggController:SetAutoPlace(enabled)
end

Adapter.AutoHatch = function(enabled, state)
    -- Example:
    -- YourEggController:SetAutoHatch(enabled)
end

Adapter.AutoFuse = function(enabled, state)
    -- Example:
    -- YourPetController:SetAutoFuse(enabled)
end
]]

--==============================================================--
-- SERVER-SIDE VALIDATION CHECKLIST
--==============================================================--
--[[
Your server should recompute / verify:

EGG
- Egg UID exists
- Egg is currently collectible
- Player is within legal interaction range
- Player is allowed to collect that egg
- Carry state belongs to caller
- Egg cannot be duplicated/redeemed twice

PLACE
- Caller owns/carries the egg
- Destination plot belongs to caller
- Slot exists and is free
- Position/slot is server-approved

HATCH
- Caller owns egg
- Egg exists
- Growth timer is complete server-side
- Reward is derived server-side
- Client cannot provide rarity/mutation/value

TREADMILL
- Caller is physically on assigned treadmill
- Session is active
- Gain rate is server computed
- Repeated calls do not duplicate gain

BASE
- Requested tier is exactly next legal tier
- Server calculates cost
- Server checks funds
- No arbitrary tier jump

FUSE
- Every UID exists
- Caller owns every pet
- Inputs are not already consumed
- Fuse recipe and reward are server computed
- Start/complete order is validated

REWARDS
- Index unlock is server verified
- Offline earnings are one-time per snapshot
- Group membership/reward claim is server verified

NEVER TRUST CLIENT-SUPPLIED:
- owner
- cost
- currency amount
- rarity
- mutation
- weight
- hatch-ready flag
- plot ownership
- treadmill presence
- pet ownership
- reward amount
]]

print("[OUROBOROS COMPLETE] Loaded.")
