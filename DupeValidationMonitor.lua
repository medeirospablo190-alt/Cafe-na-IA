--==============================================================--
-- CAFEINA • CRYSTAL DUPE VALIDATION MONITOR V1
-- EXECUTOR / MOBILE • PASSIVE • PLACE-LOCKED
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local TARGET_PLACE_ID = 138686218420016
if game.PlaceId ~= TARGET_PLACE_ID then
    warn("[DUPE MONITOR] PlaceId bloqueado:", game.PlaceId)
    return
end

local GemSignals = ReplicatedStorage:WaitForChild("GemSignals", 15)
local PlotRemotes = ReplicatedStorage:WaitForChild("PlotRemotes", 15)
if not GemSignals or not PlotRemotes then return end

local DropCrystal = GemSignals:WaitForChild("DropCrystal", 15)
local PlaceCrystal = PlotRemotes:WaitForChild("PlaceCrystal", 15)
if not DropCrystal or not PlaceCrystal then return end

pcall(function()
    local old = rawget(ENV, "__CAFEINA_DUPE_MONITOR_GUI")
    if old then old:Destroy() end
end)

local State = {
    lastDropId = nil,
    lastPlaceId = nil,
    lastPlaceArg = nil,
    dropSeen = {},
    placeSeen = {},
    duplicateIdHits = 0,
    logs = {},
}

local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end
    local s = table.concat(p, " ")
    State.logs[#State.logs+1] = s
    if #State.logs > 80 then table.remove(State.logs, 1) end
    print("[DUPE MONITOR]", s)
end

local function snapshot()
    local data = { total = 0, backpack = {}, character = {} }
    local backpack = LP:FindFirstChildOfClass("Backpack")
    local character = LP.Character

    if backpack then
        for _, v in ipairs(backpack:GetChildren()) do
            if v:IsA("Tool") then
                data.total += 1
                data.backpack[#data.backpack+1] = v.Name
            end
        end
    end

    if character then
        for _, v in ipairs(character:GetChildren()) do
            if v:IsA("Tool") then
                data.total += 1
                data.character[#data.character+1] = v.Name
            end
        end
    end

    table.sort(data.backpack)
    table.sort(data.character)
    return data
end

local function equipped()
    local c = LP.Character
    if not c then return "nenhum" end
    local t = c:FindFirstChildOfClass("Tool")
    return t and t.Name or "nenhum"
end

local DISPATCH_KEY = "__CAFEINA_DUPE_MONITOR_DISPATCH_V1"
local Dispatch = rawget(ENV, DISPATCH_KEY)

if type(Dispatch) ~= "table" then
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        warn("[DUPE MONITOR] Executor sem hookmetamethod/getnamecallmethod")
        return
    end

    Dispatch = { handler = nil }
    local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
    local old

    old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        local h = Dispatch.handler
        if h and method == "FireServer" and typeof(self) == "Instance" then
            pcall(h, self, table.pack(...))
        end
        return old(self, ...)
    end))

    ENV[DISPATCH_KEY] = Dispatch
end

Dispatch.handler = function(remote, args)
    if remote == DropCrystal then
        local id = tonumber(args[1])
        if not id then return end

        if State.dropSeen[id] then
            State.duplicateIdHits += 1
            log("ID DROP repetido:", id, "vezes:", State.dropSeen[id] + 1)
        end

        State.dropSeen[id] = (State.dropSeen[id] or 0) + 1
        State.lastDropId = id
        log("DropCrystal", id, "tool=", equipped(), "tools=", snapshot().total)

    elseif remote == PlaceCrystal then
        local id = tonumber(args[1])
        if not id then return end

        if State.placeSeen[id] then
            State.duplicateIdHits += 1
            log("ID PLACE repetido:", id, "vezes:", State.placeSeen[id] + 1)
        end

        State.placeSeen[id] = (State.placeSeen[id] or 0) + 1
        State.lastPlaceId = id
        State.lastPlaceArg = args[2]
        log("PlaceCrystal", id, "pos=", tostring(args[2]), "tools=", snapshot().total)
    end
end

local parent = CoreGui
pcall(function() if gethui then parent = gethui() end end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaDupeValidationMonitor"
gui.ResetOnSpawn = false
gui.Parent = parent
ENV.__CAFEINA_DUPE_MONITOR_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(260, 195)
frame.Position = UDim2.fromOffset(8, 90)
frame.BackgroundColor3 = Color3.fromRGB(15,15,18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-70,0,30)
title.Position = UDim2.fromOffset(10,5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • DUPE MONITOR"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local min = Instance.new("TextButton")
min.Size = UDim2.fromOffset(52,26)
min.Position = UDim2.new(1,-60,0,6)
min.BackgroundColor3 = Color3.fromRGB(38,38,44)
min.Text = "MIN"
min.TextColor3 = Color3.new(1,1,1)
min.TextSize = 11
min.Font = Enum.Font.GothamBold
min.BorderSizePixel = 0
min.Parent = frame
Instance.new("UICorner", min).CornerRadius = UDim.new(0,7)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-20,0,112)
status.Position = UDim2.fromOffset(10,42)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(210,210,210)
status.TextSize = 11
status.Font = Enum.Font.Gotham
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local reset = Instance.new("TextButton")
reset.Size = UDim2.new(1,-20,0,30)
reset.Position = UDim2.fromOffset(10,158)
reset.BackgroundColor3 = Color3.fromRGB(70,35,35)
reset.BorderSizePixel = 0
reset.Text = "ZERAR CONTADORES"
reset.TextColor3 = Color3.new(1,1,1)
reset.TextSize = 11
reset.Font = Enum.Font.GothamBold
reset.Parent = frame
Instance.new("UICorner", reset).CornerRadius = UDim.new(0,8)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(80,42)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18,18,22)
mini.BorderSizePixel = 0
mini.Text = "DUPE MON"
mini.TextColor3 = Color3.new(1,1,1)
mini.TextSize = 10
mini.Font = Enum.Font.GothamBold
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0,10)

min.MouseButton1Click:Connect(function()
    frame.Visible = false
    mini.Visible = true
end)

mini.MouseButton1Click:Connect(function()
    mini.Visible = false
    frame.Visible = true
end)

reset.MouseButton1Click:Connect(function()
    State.lastDropId = nil
    State.lastPlaceId = nil
    State.lastPlaceArg = nil
    State.dropSeen = {}
    State.placeSeen = {}
    State.duplicateIdHits = 0
    State.logs = {}
    log("contadores zerados")
end)

do
    local dragging = false
    local dragStart, startPos
    title.Active = true

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            mini.Position = frame.Position
        end
    end)
end

task.spawn(function()
    while gui.Parent do
        local s = snapshot()
        status.Text = table.concat({
            "Drop ID: " .. tostring(State.lastDropId or "--"),
            "Place ID: " .. tostring(State.lastPlaceId or "--"),
            "Pos: " .. tostring(State.lastPlaceArg or "--"),
            "Equipado: " .. equipped(),
            "Tools: " .. tostring(s.total),
            "IDs repetidos: " .. tostring(State.duplicateIdHits),
        }, "\n")
        task.wait(0.5)
    end
end)

ENV.__CAFEINA_DUPE_MONITOR_V1 = {
    State = State,
    Snapshot = snapshot,
    Logs = function() return State.logs end,
    Stop = function()
        Dispatch.handler = nil
        if gui then gui:Destroy() end
    end,
}

log("carregado | observando DropCrystal e PlaceCrystal")
