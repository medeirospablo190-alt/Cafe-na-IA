--==============================================================--
-- CAFEINA • CRYSTAL DUPE TEST LAB V2
-- EXECUTOR / MOBILE • PLACE-LOCKED • CONTROLLED REPLAY
--
-- Captura chamadas legitimas:
--   ReplicatedStorage.GemSignals.DropCrystal(id)
--   ReplicatedStorage.PlotRemotes.PlaceCrystal(id, position)
--
-- Botoes:
--   DUPE DROP 1X
--   DUPE DROP 10X
--   REPLAY PLACE 1X
--   REPLAY PLACE 10X
--
-- Limite rigido: 10 repeticoes. Sem loop infinito.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local TARGET_PLACE_ID = 138686218420016
if game.PlaceId ~= TARGET_PLACE_ID then
    warn("[DUPE LAB] PlaceId bloqueado:", game.PlaceId)
    return
end

local GemSignals = ReplicatedStorage:WaitForChild("GemSignals", 15)
local PlotRemotes = ReplicatedStorage:WaitForChild("PlotRemotes", 15)

if not GemSignals or not PlotRemotes then
    warn("[DUPE LAB] Pastas de remotes nao encontradas.")
    return
end

local DropCrystal = GemSignals:WaitForChild("DropCrystal", 15)
local PlaceCrystal = PlotRemotes:WaitForChild("PlaceCrystal", 15)

if not DropCrystal or not PlaceCrystal then
    warn("[DUPE LAB] DropCrystal/PlaceCrystal nao encontrados.")
    return
end

local State = {
    lastDropId = nil,
    lastPlaceId = nil,
    lastPlacePosition = nil,
    dropCapturedAt = nil,
    placeCapturedAt = nil,
    running = false,
    lastResult = "Faca uma acao legitima primeiro.",
}

local function toolSnapshot()
    local result = {
        backpack = {},
        character = {},
        total = 0,
    }

    local backpack = LP:FindFirstChildOfClass("Backpack")
    local character = LP.Character

    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") then
                result.total += 1
                result.backpack[#result.backpack + 1] = obj.Name
            end
        end
    end

    if character then
        for _, obj in ipairs(character:GetChildren()) do
            if obj:IsA("Tool") then
                result.total += 1
                result.character[#result.character + 1] = obj.Name
            end
        end
    end

    table.sort(result.backpack)
    table.sort(result.character)
    return result
end

local function argsToString(...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do
        parts[#parts + 1] = tostring(args[i])
    end
    return table.concat(parts, ", ")
end

--==============================================================--
-- PASSIVE CAPTURE OF THE TWO KNOWN REMOTES ONLY
--==============================================================--

local DISPATCH_KEY = "__CAFEINA_CRYSTAL_DUPE_CAPTURE_V2"
local Dispatch = rawget(ENV, DISPATCH_KEY)

if type(Dispatch) ~= "table" then
    Dispatch = {handler = nil}

    if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
        local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
        local oldNamecall

        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            local handler = Dispatch.handler

            if handler and method == "FireServer" and typeof(self) == "Instance" then
                if self == DropCrystal or self == PlaceCrystal then
                    pcall(handler, self, table.pack(...))
                end
            end

            return oldNamecall(self, ...)
        end))

        ENV[DISPATCH_KEY] = Dispatch
    else
        warn("[DUPE LAB] Executor sem hookmetamethod/getnamecallmethod.")
    end
end

if type(Dispatch) == "table" then
    Dispatch.handler = function(remote, args)
        if remote == DropCrystal then
            local id = tonumber(args[1])
            if id then
                State.lastDropId = id
                State.dropCapturedAt = os.clock()
                State.lastResult = "Drop capturado: ID " .. tostring(id)
                print("[DUPE LAB] DropCrystal capturado:", id)
            end

        elseif remote == PlaceCrystal then
            local id = tonumber(args[1])
            local position = args[2]
            if id and position ~= nil then
                State.lastPlaceId = id
                State.lastPlacePosition = position
                State.placeCapturedAt = os.clock()
                State.lastResult = "Place capturado: ID " .. tostring(id)
                print("[DUPE LAB] PlaceCrystal capturado:", id, tostring(position))
            end
        end
    end
end

--==============================================================--
-- CONTROLLED REPLAY
--==============================================================--

local function runReplay(kind, count)
    if State.running then
        State.lastResult = "Ja existe um teste em andamento."
        return
    end

    count = math.clamp(math.floor(tonumber(count) or 1), 1, 10)

    local remote
    local args

    if kind == "drop" then
        if not State.lastDropId then
            State.lastResult = "Nenhum DropCrystal capturado ainda."
            return
        end

        remote = DropCrystal
        args = {State.lastDropId}

    elseif kind == "place" then
        if not State.lastPlaceId or State.lastPlacePosition == nil then
            State.lastResult = "Nenhum PlaceCrystal capturado ainda."
            return
        end

        remote = PlaceCrystal
        args = {State.lastPlaceId, State.lastPlacePosition}
    else
        return
    end

    State.running = true

    local before = toolSnapshot()
    local success = 0
    local failed = 0

    State.lastResult = string.upper(kind) .. " • executando " .. count .. "x..."

    for i = 1, count do
        local ok, err = pcall(function()
            remote:FireServer(table.unpack(args))
        end)

        if ok then
            success += 1
        else
            failed += 1
            warn("[DUPE LAB] replay erro", i, err)
        end

        task.wait(0.25)
    end

    task.wait(1.0)
    local after = toolSnapshot()

    local delta = after.total - before.total

    State.lastResult = string.format(
        "%s %dx • enviados=%d falhas=%d • Tools %d→%d (Δ%d)",
        string.upper(kind),
        count,
        success,
        failed,
        before.total,
        after.total,
        delta
    )

    print("========== CAFEINA DUPE LAB ==========")
    print("Tipo:", kind)
    print("Tentativas:", count)
    print("Args:", argsToString(table.unpack(args)))
    print("Enviados:", success, "Falhas:", failed)
    print("Tools antes:", before.total)
    print("Tools depois:", after.total)
    print("Delta:", delta)
    print("Backpack antes:", table.concat(before.backpack, " | "))
    print("Backpack depois:", table.concat(after.backpack, " | "))
    print("======================================")

    State.running = false
end

--==============================================================--
-- GUI MOBILE
--==============================================================--

pcall(function()
    local old = rawget(ENV, "__CAFEINA_DUPE_LAB_GUI")
    if old then old:Destroy() end
end)

local parent = CoreGui
pcall(function()
    if gethui then parent = gethui() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaCrystalDupeLabV2"
gui.ResetOnSpawn = false
gui.Parent = parent
ENV.__CAFEINA_DUPE_LAB_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(286, 294)
frame.Position = UDim2.fromOffset(8, 72)
frame.BackgroundColor3 = Color3.fromRGB(16,16,19)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-70,0,30)
title.Position = UDim2.fromOffset(10,6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • CRYSTAL DUPE LAB"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local minButton = Instance.new("TextButton")
minButton.Size = UDim2.fromOffset(52,26)
minButton.Position = UDim2.new(1,-60,0,6)
minButton.BackgroundColor3 = Color3.fromRGB(38,38,44)
minButton.BorderSizePixel = 0
minButton.Text = "MIN"
minButton.TextColor3 = Color3.new(1,1,1)
minButton.TextSize = 11
minButton.Font = Enum.Font.GothamBold
minButton.Parent = frame
Instance.new("UICorner", minButton).CornerRadius = UDim.new(0,7)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-20,0,62)
status.Position = UDim2.fromOffset(10,38)
status.BackgroundTransparency = 1
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(210,210,210)
status.TextSize = 11
status.Font = Enum.Font.Gotham
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local function makeButton(text, y, bg)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1,-20,0,36)
    b.Position = UDim2.fromOffset(10,y)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local drop1 = makeButton("DUPE DROP • 1X", 104, Color3.fromRGB(75,45,25))
local drop10 = makeButton("DUPE DROP • 10X", 146, Color3.fromRGB(125,35,25))
local place1 = makeButton("REPLAY PLACE • 1X", 188, Color3.fromRGB(35,55,85))
local place10 = makeButton("REPLAY PLACE • 10X", 230, Color3.fromRGB(35,45,115))

local clearButton = Instance.new("TextButton")
clearButton.Size = UDim2.fromOffset(90,22)
clearButton.Position = UDim2.new(1,-100,1,-28)
clearButton.BackgroundColor3 = Color3.fromRGB(42,42,47)
clearButton.BorderSizePixel = 0
clearButton.Text = "LIMPAR ID"
clearButton.TextColor3 = Color3.new(1,1,1)
clearButton.TextSize = 10
clearButton.Font = Enum.Font.GothamBold
clearButton.Parent = frame
Instance.new("UICorner", clearButton).CornerRadius = UDim.new(0,6)

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(82,42)
mini.Position = frame.Position
mini.BackgroundColor3 = Color3.fromRGB(18,18,22)
mini.BorderSizePixel = 0
mini.Text = "DUPE LAB"
mini.TextColor3 = Color3.new(1,1,1)
mini.TextSize = 10
mini.Font = Enum.Font.GothamBold
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0,10)

local function setMinimized(value)
    frame.Visible = not value
    mini.Visible = value
end

minButton.MouseButton1Click:Connect(function() setMinimized(true) end)
mini.MouseButton1Click:Connect(function() setMinimized(false) end)

drop1.MouseButton1Click:Connect(function() task.spawn(runReplay, "drop", 1) end)
drop10.MouseButton1Click:Connect(function() task.spawn(runReplay, "drop", 10) end)
place1.MouseButton1Click:Connect(function() task.spawn(runReplay, "place", 1) end)
place10.MouseButton1Click:Connect(function() task.spawn(runReplay, "place", 10) end)

clearButton.MouseButton1Click:Connect(function()
    State.lastDropId = nil
    State.lastPlaceId = nil
    State.lastPlacePosition = nil
    State.dropCapturedAt = nil
    State.placeCapturedAt = nil
    State.lastResult = "IDs limpos. Faca nova acao legitima."
end)

-- drag only by title area so gameplay touch is not swallowed
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
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
        mini.Position = frame.Position
    end
end)

task.spawn(function()
    while gui.Parent do
        status.Text = string.format(
            "Drop ID: %s\nPlace ID: %s\n%s",
            tostring(State.lastDropId or "nenhum"),
            tostring(State.lastPlaceId or "nenhum"),
            State.lastResult
        )

        local busyText = State.running and " • TESTANDO" or ""
        mini.Text = "DUPE LAB" .. busyText
        task.wait(0.25)
    end
end)

ENV.__CAFEINA_CRYSTAL_DUPE_LAB_V2 = {
    State = State,
    Dupe1 = function() runReplay("drop", 1) end,
    Dupe10 = function() runReplay("drop", 10) end,
    Place1 = function() runReplay("place", 1) end,
    Place10 = function() runReplay("place", 10) end,
}

print("[DUPE LAB] V2 carregado.")
print("[DUPE LAB] Faca um DropCrystal/PlaceCrystal legitimo para capturar o ID.")
