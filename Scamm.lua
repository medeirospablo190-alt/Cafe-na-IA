--============================================================
-- CAFEINA SERVER SCANNER V3.1
-- CLIENT VISIBLE ONLY / MOBILE COMPATIBILITY
--============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

local Services = {}

local ServiceNames = {
    "Workspace",
    "ReplicatedStorage",
    "ReplicatedFirst",
    "Players",
    "Lighting",
    "StarterGui",
    "StarterPlayer",
    "Teams",
    "SoundService"
}

for _, name in ipairs(ServiceNames) do
    local ok, service = pcall(function()
        return game:GetService(name)
    end)

    if ok and service then
        table.insert(Services, service)
    end
end

--============================================================
-- CONFIG
--============================================================

local MAX_OBJECTS = 35000
local YIELD_EVERY = 150
local MAX_VIEW_CHARS = 120000

--============================================================
-- STATE
--============================================================

local State = {
    running = false,
    cancel = false,

    scanned = 0,

    remotes = {},
    scripts = {},
    modules = {},
    values = {},
    classes = {},
    serviceCounts = {},

    reports = {}
}

--============================================================
-- HELPERS
--============================================================

local function safeCall(fn, fallback)
    local ok, result = pcall(fn)

    if ok then
        return result
    end

    return fallback
end

local function safeName(obj)
    return safeCall(function()
        return obj:GetFullName()
    end, obj.Name)
end

local function copyText(text)
    if type(setclipboard) == "function" then
        return pcall(function()
            setclipboard(text)
        end)
    end

    if type(toclipboard) == "function" then
        return pcall(function()
            toclipboard(text)
        end)
    end

    return false
end

local function safeValue(obj)
    return safeCall(function()

        if obj:IsA("StringValue")
        or obj:IsA("NumberValue")
        or obj:IsA("IntValue")
        or obj:IsA("BoolValue") then

            return tostring(obj.Value)
        end

        if obj:IsA("ObjectValue") then

            if obj.Value then
                return safeName(obj.Value)
            end

            return "nil"
        end

        return nil

    end, nil)
end

local function limitText(text)

    if #text > MAX_VIEW_CHARS then
        return string.sub(
            text,
            1,
            MAX_VIEW_CHARS
        )
        .. "\n\n[VIEWER LIMIT REACHED]\nUse COPY REPORT for complete text."
    end

    return text
end

--============================================================
-- REMOTE CLASSIFICATION
--============================================================

local HIGH = {
    "buy",
    "purchase",
    "upgrade",
    "reward",
    "cash",
    "currency",
    "case",
    "gift",
    "admin",
    "developer",
    "inventory",
    "weaponprogression",
    "classsystem"
}

local MEDIUM = {
    "equip",
    "skin",
    "attachment",
    "loadout",
    "lobby",
    "wheel",
    "setting"
}

local LOW = {
    "sound",
    "particle",
    "camera",
    "notification",
    "interface"
}

local function findKeyword(text, list)

    text = string.lower(text)

    for _, keyword in ipairs(list) do

        if string.find(
            text,
            keyword,
            1,
            true
        ) then

            return keyword
        end
    end

    return nil
end

local function classifyRemote(path)

    local keyword = findKeyword(path, HIGH)

    if keyword then
        return "HIGH", keyword
    end

    keyword = findKeyword(path, MEDIUM)

    if keyword then
        return "MEDIUM", keyword
    end

    keyword = findKeyword(path, LOW)

    if keyword then
        return "LOW", keyword
    end

    return "UNKNOWN", ""
end

--============================================================
-- GUI PARENT
--============================================================

local GuiParent

if type(gethui) == "function" then

    local ok, result = pcall(gethui)

    if ok and result then
        GuiParent = result
    end
end

if not GuiParent then

    local ok, result = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and result then
        GuiParent = result
    end
end

if not GuiParent then
    GuiParent = LocalPlayer:WaitForChild("PlayerGui")
end

--============================================================
-- DESTROY OLD GUI
--============================================================

pcall(function()

    local old =
        GuiParent:FindFirstChild(
            "CafeinaScannerV31"
        )

    if old then
        old:Destroy()
    end

end)

--============================================================
-- GUI
--============================================================

local Gui = Instance.new("ScreenGui")

Gui.Name = "CafeinaScannerV31"
Gui.ResetOnSpawn = false

pcall(function()
    Gui.IgnoreGuiInset = true
end)

if syn and type(syn.protect_gui) == "function" then

    pcall(function()
        syn.protect_gui(Gui)
    end)

end

Gui.Parent = GuiParent

--============================================================
-- MAIN
--============================================================

local Main = Instance.new("Frame")

Main.Name = "Main"

Main.AnchorPoint =
    Vector2.new(0.5, 0.5)

Main.Position =
    UDim2.fromScale(0.5, 0.5)

Main.Size =
    UDim2.fromScale(0.88, 0.76)

Main.BackgroundColor3 =
    Color3.fromRGB(12, 12, 15)

Main.BorderSizePixel = 0

Main.Parent = Gui

local MainCorner = Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(0, 12)

MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")

Stroke.Color =
    Color3.fromRGB(150, 28, 38)

Stroke.Thickness = 1

Stroke.Parent = Main

--============================================================
-- HEADER
--============================================================

local Header = Instance.new("Frame")

Header.Size =
    UDim2.new(1, 0, 0, 52)

Header.BackgroundColor3 =
    Color3.fromRGB(21, 21, 25)

Header.BorderSizePixel = 0

Header.Parent = Main

local HeaderCorner =
    Instance.new("UICorner")

HeaderCorner.CornerRadius =
    UDim.new(0, 12)

HeaderCorner.Parent = Header

local Title =
    Instance.new("TextLabel")

Title.BackgroundTransparency = 1

Title.Position =
    UDim2.new(0, 14, 0, 4)

Title.Size =
    UDim2.new(1, -105, 0, 25)

Title.Text =
    "CAFEINA SERVER SCANNER"

Title.TextColor3 =
    Color3.fromRGB(245,245,245)

Title.TextSize = 17

Title.Font =
    Enum.Font.GothamBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent = Header

local Subtitle =
    Instance.new("TextLabel")

Subtitle.BackgroundTransparency = 1

Subtitle.Position =
    UDim2.new(0, 14, 0, 28)

Subtitle.Size =
    UDim2.new(1, -110, 0, 17)

Subtitle.Text =
    "V3.1 - CLIENT VISIBLE ONLY"

Subtitle.TextColor3 =
    Color3.fromRGB(220, 55, 65)

Subtitle.TextSize = 10

Subtitle.Font =
    Enum.Font.Gotham

Subtitle.TextXAlignment =
    Enum.TextXAlignment.Left

Subtitle.Parent = Header

local Minimize =
    Instance.new("TextButton")

Minimize.Size =
    UDim2.new(0, 36, 0, 32)

Minimize.Position =
    UDim2.new(1, -78, 0, 9)

Minimize.Text = "-"

Minimize.TextColor3 =
    Color3.new(1,1,1)

Minimize.TextSize = 20

Minimize.Font =
    Enum.Font.GothamBold

Minimize.BackgroundColor3 =
    Color3.fromRGB(35,35,40)

Minimize.Parent = Header

Instance.new(
    "UICorner",
    Minimize
).CornerRadius =
    UDim.new(0,8)

local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.new(0,36,0,32)

Close.Position =
    UDim2.new(1,-39,0,9)

Close.Text = "X"

Close.TextColor3 =
    Color3.new(1,1,1)

Close.TextSize = 14

Close.Font =
    Enum.Font.GothamBold

Close.BackgroundColor3 =
    Color3.fromRGB(130,25,35)

Close.Parent = Header

Instance.new(
    "UICorner",
    Close
).CornerRadius =
    UDim.new(0,8)

--============================================================
-- STATUS
--============================================================

local StatusBox =
    Instance.new("Frame")

StatusBox.Position =
    UDim2.new(0,8,0,59)

StatusBox.Size =
    UDim2.new(1,-16,0,46)

StatusBox.BackgroundColor3 =
    Color3.fromRGB(27,27,32)

StatusBox.BorderSizePixel = 0

StatusBox.Parent = Main

Instance.new(
    "UICorner",
    StatusBox
).CornerRadius =
    UDim.new(0,9)

local Status =
    Instance.new("TextLabel")

Status.BackgroundTransparency = 1

Status.Position =
    UDim2.new(0,12,0,4)

Status.Size =
    UDim2.new(1,-24,0,21)

Status.Text =
    "Ready"

Status.TextColor3 =
    Color3.new(1,1,1)

Status.TextSize = 11

Status.Font =
    Enum.Font.GothamMedium

Status.TextXAlignment =
    Enum.TextXAlignment.Left

Status.Parent = StatusBox

local ProgressBack =
    Instance.new("Frame")

ProgressBack.Position =
    UDim2.new(0,12,0,31)

ProgressBack.Size =
    UDim2.new(1,-24,0,5)

ProgressBack.BackgroundColor3 =
    Color3.fromRGB(12,12,15)

ProgressBack.BorderSizePixel = 0

ProgressBack.Parent = StatusBox

local Progress =
    Instance.new("Frame")

Progress.Size =
    UDim2.new(0,0,1,0)

Progress.BackgroundColor3 =
    Color3.fromRGB(225,45,55)

Progress.BorderSizePixel = 0

Progress.Parent = ProgressBack

--============================================================
-- SIDEBAR
--============================================================

local Sidebar =
    Instance.new("Frame")

Sidebar.Position =
    UDim2.new(0,8,0,112)

Sidebar.Size =
    UDim2.new(0.31,-10,1,-120)

Sidebar.BackgroundColor3 =
    Color3.fromRGB(21,21,25)

Sidebar.BorderSizePixel = 0

Sidebar.Parent = Main

Instance.new(
    "UICorner",
    Sidebar
).CornerRadius =
    UDim.new(0,9)

local Start =
    Instance.new("TextButton")

Start.Position =
    UDim2.new(0,7,0,7)

Start.Size =
    UDim2.new(1,-14,0,40)

Start.Text =
    "START SCANNER"

Start.BackgroundColor3 =
    Color3.fromRGB(220,42,52)

Start.TextColor3 =
    Color3.new(1,1,1)

Start.TextSize = 11

Start.Font =
    Enum.Font.GothamBold

Start.Parent = Sidebar

Instance.new(
    "UICorner",
    Start
).CornerRadius =
    UDim.new(0,8)

local ButtonsHolder =
    Instance.new("ScrollingFrame")

ButtonsHolder.Position =
    UDim2.new(0,7,0,53)

ButtonsHolder.Size =
    UDim2.new(1,-14,1,-60)

ButtonsHolder.BackgroundTransparency = 1

ButtonsHolder.BorderSizePixel = 0

ButtonsHolder.ScrollBarThickness = 3

ButtonsHolder.CanvasSize =
    UDim2.new()

ButtonsHolder.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

ButtonsHolder.Parent = Sidebar

local ButtonLayout =
    Instance.new("UIListLayout")

ButtonLayout.Padding =
    UDim.new(0,5)

ButtonLayout.Parent =
    ButtonsHolder

--============================================================
-- CONTENT
--============================================================

local Content =
    Instance.new("Frame")

Content.Position =
    UDim2.new(0.31,5,0,112)

Content.Size =
    UDim2.new(0.69,-13,1,-120)

Content.BackgroundColor3 =
    Color3.fromRGB(21,21,25)

Content.BorderSizePixel = 0

Content.Parent = Main

Instance.new(
    "UICorner",
    Content
).CornerRadius =
    UDim.new(0,9)

local PageTitle =
    Instance.new("TextLabel")

PageTitle.BackgroundTransparency = 1

PageTitle.Position =
    UDim2.new(0,10,0,5)

PageTitle.Size =
    UDim2.new(1,-20,0,25)

PageTitle.Text =
    "SUMMARY"

PageTitle.TextColor3 =
    Color3.new(1,1,1)

PageTitle.TextSize = 14

PageTitle.Font =
    Enum.Font.GothamBold

PageTitle.TextXAlignment =
    Enum.TextXAlignment.Left

PageTitle.Parent =
    Content

local Viewer =
    Instance.new("TextBox")

Viewer.Position =
    UDim2.new(0,8,0,34)

Viewer.Size =
    UDim2.new(1,-16,1,-80)

Viewer.BackgroundColor3 =
    Color3.fromRGB(12,12,15)

Viewer.BorderSizePixel = 0

Viewer.Text =
    "Press START SCANNER."

Viewer.TextColor3 =
    Color3.fromRGB(235,235,240)

Viewer.TextSize = 11

Viewer.Font =
    Enum.Font.Code

Viewer.TextXAlignment =
    Enum.TextXAlignment.Left

Viewer.TextYAlignment =
    Enum.TextYAlignment.Top

Viewer.TextWrapped = true

Viewer.ClearTextOnFocus = false

Viewer.Parent = Content

pcall(function()
    Viewer.MultiLine = true
end)

local Copy =
    Instance.new("TextButton")

Copy.Position =
    UDim2.new(0,8,1,-40)

Copy.Size =
    UDim2.new(0.49,-4,0,32)

Copy.Text =
    "COPY PAGE"

Copy.TextColor3 =
    Color3.new(1,1,1)

Copy.TextSize = 10

Copy.Font =
    Enum.Font.GothamBold

Copy.BackgroundColor3 =
    Color3.fromRGB(35,35,40)

Copy.Parent = Content

Instance.new(
    "UICorner",
    Copy
).CornerRadius =
    UDim.new(0,7)

local CopyAll =
    Instance.new("TextButton")

CopyAll.Position =
    UDim2.new(0.51,4,1,-40)

CopyAll.Size =
    UDim2.new(0.49,-12,0,32)

CopyAll.Text =
    "COPY REPORT"

CopyAll.TextColor3 =
    Color3.new(1,1,1)

CopyAll.TextSize = 10

CopyAll.Font =
    Enum.Font.GothamBold

CopyAll.BackgroundColor3 =
    Color3.fromRGB(120,25,35)

CopyAll.Parent = Content

Instance.new(
    "UICorner",
    CopyAll
).CornerRadius =
    UDim.new(0,7)

--============================================================
-- STATUS FUNCTIONS
--============================================================

local function setStatus(text)
    Status.Text = tostring(text)
end

local function setProgress(value)

    value = math.clamp(
        tonumber(value) or 0,
        0,
        1
    )

    Progress.Size =
        UDim2.new(value,0,1,0)
end

--============================================================
-- PAGES
--============================================================

local currentPage = "Summary"

local Pages = {
    "Summary",
    "Remotes",
    "Economy",
    "Weapons",
    "Scripts",
    "Architecture"
}

local pageButtons = {}

local function refresh()

    PageTitle.Text =
        string.upper(currentPage)

    Viewer.Text =
        limitText(
            State.reports[currentPage]
            or
            "Run the scanner first."
        )

    for name, button in pairs(pageButtons) do

        if name == currentPage then

            button.BackgroundColor3 =
                Color3.fromRGB(
                    110,
                    24,
                    32
                )

        else

            button.BackgroundColor3 =
                Color3.fromRGB(
                    31,
                    31,
                    36
                )
        end
    end
end

for _, page in ipairs(Pages) do

    local button =
        Instance.new("TextButton")

    button.Size =
        UDim2.new(1,0,0,34)

    button.Text =
        string.upper(page)

    button.BackgroundColor3 =
        Color3.fromRGB(31,31,36)

    button.TextColor3 =
        Color3.new(1,1,1)

    button.TextSize = 10

    button.Font =
        Enum.Font.GothamMedium

    button.Parent =
        ButtonsHolder

    Instance.new(
        "UICorner",
        button
    ).CornerRadius =
        UDim.new(0,7)

    button.MouseButton1Click:Connect(function()

        currentPage = page

        refresh()

    end)

    pageButtons[page] = button
end

--============================================================
-- RESET
--============================================================

local function resetState()

    State.scanned = 0

    State.remotes = {}
    State.scripts = {}
    State.modules = {}
    State.values = {}
    State.classes = {}
    State.serviceCounts = {}

    State.reports = {}

end

--============================================================
-- SCANNER
--============================================================

local function scanInstance(obj)

    State.scanned =
        State.scanned + 1

    local className =
        obj.ClassName

    State.classes[className] =
        (State.classes[className] or 0) + 1

    local path =
        safeName(obj)

    if obj:IsA("RemoteEvent")
    or obj:IsA("RemoteFunction") then

        local risk, reason =
            classifyRemote(path)

        table.insert(
            State.remotes,
            {
                path = path,
                name = obj.Name,
                className = className,
                risk = risk,
                reason = reason
            }
        )

    elseif obj:IsA("LocalScript")
    or obj:IsA("Script") then

        table.insert(
            State.scripts,
            {
                path = path,
                className = className
            }
        )

    elseif obj:IsA("ModuleScript") then

        table.insert(
            State.modules,
            {
                path = path
            }
        )

    end

    local value =
        safeValue(obj)

    if value ~= nil then

        table.insert(
            State.values,
            {
                path = path,
                value = value
            }
        )

    end
end

--============================================================
-- REPORTS
--============================================================

local function buildReports()

    -- SUMMARY

    local summary = {
        "CAFEINA SERVER SCANNER V3.1",
        "",
        "CLIENT VISIBLE ONLY",
        "",
        "PlaceId: "
            .. tostring(game.PlaceId),

        "GameId: "
            .. tostring(game.GameId),

        "",
        "Objects: "
            .. tostring(State.scanned),

        "Remotes: "
            .. tostring(#State.remotes),

        "Scripts: "
            .. tostring(#State.scripts),

        "Modules: "
            .. tostring(#State.modules),

        "Values: "
            .. tostring(#State.values),

        "",
        "SERVICES:"
    }

    for _, service in ipairs(Services) do

        table.insert(
            summary,
            service.Name
            .. ": "
            .. tostring(
                State.serviceCounts[
                    service.Name
                ] or 0
            )
        )
    end

    State.reports.Summary =
        table.concat(summary,"\n")

    -- REMOTES

    local remotes = {
        "REMOTE MAP",
        "",
        "Classification is based only on names.",
        "It does not prove a vulnerability.",
        ""
    }

    table.sort(
        State.remotes,
        function(a,b)

            return a.path < b.path

        end
    )

    for _, remote in ipairs(State.remotes) do

        table.insert(
            remotes,

            "["
            .. remote.risk
            .. "] ["
            .. remote.className
            .. "] "
            .. remote.path
        )

    end

    State.reports.Remotes =
        table.concat(remotes,"\n")

    -- ECONOMY

    local economy = {
        "ECONOMY / PROGRESSION",
        ""
    }

    for _, item in ipairs(State.values) do

        local lower =
            string.lower(item.path)

        if string.find(lower,"cash",1,true)
        or string.find(lower,"zombux",1,true)
        or string.find(lower,"level",1,true)
        or string.find(lower,"exp",1,true)
        or string.find(lower,"prestige",1,true)
        or string.find(lower,"reward",1,true) then

            table.insert(
                economy,
                item.path
                .. " = "
                .. tostring(item.value)
            )

        end
    end

    State.reports.Economy =
        table.concat(economy,"\n")

    -- WEAPONS

    local weapons = {
        "WEAPONS / LOADOUT",
        ""
    }

    for _, item in ipairs(State.values) do

        local lower =
            string.lower(item.path)

        if string.find(lower,"weapon",1,true)
        or string.find(lower,"loadout",1,true)
        or string.find(lower,"attachment",1,true)
        or string.find(lower,"gun",1,true) then

            table.insert(
                weapons,
                item.path
                .. " = "
                .. tostring(item.value)
            )

        end
    end

    State.reports.Weapons =
        table.concat(weapons,"\n")

    -- SCRIPTS

    local scripts = {
        "VISIBLE SCRIPTS / MODULES",
        "",
        "MODULES:",
        ""
    }

    for _, item in ipairs(State.modules) do

        table.insert(
            scripts,
            item.path
        )

    end

    table.insert(
        scripts,
        ""
    )

    table.insert(
        scripts,
        "SCRIPTS:"
    )

    table.insert(
        scripts,
        ""
    )

    for _, item in ipairs(State.scripts) do

        table.insert(
            scripts,

            "["
            .. item.className
            .. "] "
            .. item.path
        )

    end

    State.reports.Scripts =
        table.concat(scripts,"\n")

    -- ARCHITECTURE

    local architecture = {
        "ARCHITECTURE / SECURITY MAP",
        "",
        "Important remote trust boundaries:",
        ""
    }

    for _, remote in ipairs(State.remotes) do

        if remote.risk == "HIGH"
        or remote.risk == "MEDIUM" then

            table.insert(
                architecture,

                "["
                .. remote.risk
                .. "] "
                .. remote.path
            )

        end
    end

    table.insert(
        architecture,
        ""
    )

    table.insert(
        architecture,
        "The scanner does not inspect private server handlers."
    )

    State.reports.Architecture =
        table.concat(
            architecture,
            "\n"
        )
end

--============================================================
-- RUN
--============================================================

local function runScanner()

    if State.running then

        State.cancel = true

        setStatus(
            "Cancelling..."
        )

        return
    end

    State.running = true
    State.cancel = false

    resetState()

    Start.Text =
        "CANCEL"

    setProgress(0)

    setStatus(
        "Starting scanner..."
    )

    task.spawn(function()

        local totalServices =
            #Services

        for serviceIndex, service
            in ipairs(Services) do

            if State.cancel then
                break
            end

            setStatus(
                "Scanning "
                .. service.Name
                .. "..."
            )

            local objects =
                safeCall(function()

                    return service:GetDescendants()

                end, {})

            State.serviceCounts[
                service.Name
            ] = 0

            for index, obj
                in ipairs(objects) do

                if State.cancel then
                    break
                end

                if State.scanned >= MAX_OBJECTS then
                    break
                end

                scanInstance(obj)

                State.serviceCounts[
                    service.Name
                ] =
                State.serviceCounts[
                    service.Name
                ] + 1

                if index % YIELD_EVERY == 0 then

                    setStatus(
                        "Scanning "
                        .. service.Name
                        .. " | "
                        .. tostring(
                            State.scanned
                        )
                    )

                    task.wait()

                end
            end

            setProgress(
                serviceIndex
                /
                totalServices
            )

            if State.scanned >= MAX_OBJECTS then
                break
            end
        end

        if State.cancel then

            setStatus(
                "Scanner cancelled."
            )

        else

            setStatus(
                "Building reports..."
            )

            local ok, err =
                pcall(buildReports)

            if not ok then

                setStatus(
                    "Report error: "
                    .. tostring(err)
                )

            else

                setProgress(1)

                setStatus(
                    "Ready | "
                    .. State.scanned
                    .. " objects | "
                    .. #State.remotes
                    .. " remotes"
                )

                currentPage =
                    "Summary"

                refresh()

            end
        end

        Start.Text =
            "START SCANNER"

        State.running =
            false

    end)
end

Start.MouseButton1Click:Connect(
    runScanner
)

--============================================================
-- COPY
--============================================================

Copy.MouseButton1Click:Connect(function()

    local text =
        State.reports[currentPage]

    if not text then

        setStatus(
            "No report available."
        )

        return
    end

    if copyText(text) then

        setStatus(
            "Page copied."
        )

    else

        setStatus(
            "Clipboard unavailable."
        )

    end
end)

CopyAll.MouseButton1Click:Connect(function()

    local output = {}

    for _, page in ipairs(Pages) do

        if State.reports[page] then

            table.insert(
                output,
                "\n====================\n"
                .. page
                .. "\n====================\n"
                .. State.reports[page]
            )

        end
    end

    local text =
        table.concat(
            output,
            "\n"
        )

    if copyText(text) then

        setStatus(
            "Complete report copied."
        )

    else

        setStatus(
            "Clipboard unavailable."
        )

    end
end)

--============================================================
-- DRAG
--============================================================

local dragging = false
local dragStart
local startPos
local activeInput

Header.InputBegan:Connect(function(input)

    if input.UserInputType
        == Enum.UserInputType.Touch
    or input.UserInputType
        == Enum.UserInputType.MouseButton1 then

        dragging = true

        dragStart =
            input.Position

        startPos =
            Main.Position

    end

end)

Header.InputChanged:Connect(function(input)

    if input.UserInputType
        == Enum.UserInputType.Touch
    or input.UserInputType
        == Enum.UserInputType.MouseMovement then

        activeInput =
            input

    end

end)

UserInputService.InputChanged:Connect(function(input)

    if dragging
    and input == activeInput then

        local delta =
            input.Position
            - dragStart

        Main.Position =
            UDim2.new(

                startPos.X.Scale,
                startPos.X.Offset
                + delta.X,

                startPos.Y.Scale,
                startPos.Y.Offset
                + delta.Y
            )

    end
end)

UserInputService.InputEnded:Connect(function(input)

    if input.UserInputType
        == Enum.UserInputType.Touch
    or input.UserInputType
        == Enum.UserInputType.MouseButton1 then

        dragging = false

    end
end)

--============================================================
-- FLOATING BUTTON
--============================================================

local Floating =
    Instance.new("TextButton")

Floating.AnchorPoint =
    Vector2.new(0.5,0.5)

Floating.Position =
    UDim2.fromScale(
        0.5,
        0.5
    )

Floating.Size =
    UDim2.new(
        0,
        54,
        0,
        54
    )

Floating.BackgroundColor3 =
    Color3.fromRGB(
        125,
        25,
        35
    )

Floating.Text =
    "C"

Floating.TextColor3 =
    Color3.new(1,1,1)

Floating.TextSize = 20

Floating.Font =
    Enum.Font.GothamBold

Floating.Visible = false

Floating.Parent =
    Gui

Instance.new(
    "UICorner",
    Floating
).CornerRadius =
    UDim.new(1,0)

Minimize.MouseButton1Click:Connect(function()

    Main.Visible =
        false

    Floating.Visible =
        true

end)

Floating.MouseButton1Click:Connect(function()

    Floating.Visible =
        false

    Main.Visible =
        true

end)

Close.MouseButton1Click:Connect(function()

    State.cancel = true

    Gui:Destroy()

end)

--============================================================
-- BOOT
--============================================================

refresh()

setStatus(
    "Loaded successfully. Press START SCANNER."
)

print(
    "[CAFEINA V3.1] Loaded successfully"
)
