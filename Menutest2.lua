--==============================================================--
-- CAFEÍNA • TREADMILL OUTSIDE TEST V1.0
-- Controlled client-visible test for the user's own game.
--
-- Goal:
-- 1) Confirm the normal baseline while away from every treadmill.
-- 2) Invoke RF/Treadmill/AskWearStill once, with no arguments.
-- 3) Observe AssignedBeltShifted, RenderStateShifted, SpeedGained,
--    local ProfileDelta/SpeedPower, leaderstats Speed and WalkSpeed.
-- 4) Mark the test inconclusive if the player approaches a treadmill.
-- 5) Upload the collected records using the Cafeina chunk uploader.
--
-- It does not bypass server validation. It only records whether the
-- server accepts or rejects the same normal request away from the belt.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "TREADMILL_OUTSIDE_TEST_V1_0",
    GUI_NAME = "CafeinaTreadmillOutsideTestV1",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    START_PATH = "/upload/start",
    CHUNK_PATH = "/upload/chunk",
    FINISH_PATH = "/upload/finish",
    CANCEL_PATH = "/upload/cancel",

    MIN_OUTSIDE_DISTANCE = 35,
    BASELINE_SECONDS = 2.0,
    OBSERVE_SECONDS = 8.0,
    SAMPLE_INTERVAL = 0.25,

    TARGET_CHUNK_BYTES = 500000,
    RETRIES = 3,
    RETRY_DELAY = 1.25,
    HTTP_TIMEOUT = 30,
    UPLOAD_TOKEN = nil, -- optional; leave nil when the backend does not require it

    SAVE_FOLDER = "CafeinaArchive",
    PLACE_ID = 107778070777162,
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local requestFn = nil
if type(syn) == "table" and type(syn.request) == "function" then
    requestFn = syn.request
elseif type(http) == "table" and type(http.request) == "function" then
    requestFn = http.request
elseif type(http_request) == "function" then
    requestFn = http_request
elseif type(request) == "function" then
    requestFn = request
elseif type(fluxus) == "table" and type(fluxus.request) == "function" then
    requestFn = fluxus.request
end

local HAS_FS = type(writefile) == "function" and type(readfile) == "function"
local HAS_DELETE = type(delfile) == "function"
local HAS_FOLDER = type(makefolder) == "function" and type(isfolder) == "function"

--==============================================================--
-- HELPERS
--==============================================================--

local function nowUnix()
    return os.time()
end

local function clock()
    return os.clock()
end

local function timestampName()
    local ok, value = pcall(function()
        return os.date("!%Y%m%d_%H%M%S")
    end)
    if ok and value then
        return value
    end
    return tostring(nowUnix())
end

local function safePath(inst)
    if typeof(inst) ~= "Instance" then
        return nil
    end
    local ok, path = pcall(function()
        return inst:GetFullName()
    end)
    return ok and path or inst.Name
end

local function round(n, digits)
    if type(n) ~= "number" then
        return n
    end
    local p = 10 ^ (digits or 3)
    return math.floor(n * p + 0.5) / p
end

local function encodeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 5 then
        return "<max-depth>"
    end

    local t = typeof(value)

    if t == "nil" or t == "boolean" or t == "string" then
        return value
    elseif t == "number" then
        if value ~= value then return "NaN" end
        if value == math.huge then return "Infinity" end
        if value == -math.huge then return "-Infinity" end
        return value
    elseif t == "Instance" then
        return {
            type = "Instance",
            className = value.ClassName,
            name = value.Name,
            path = safePath(value),
        }
    elseif t == "Vector3" then
        return {type = "Vector3", x = value.X, y = value.Y, z = value.Z}
    elseif t == "Vector2" then
        return {type = "Vector2", x = value.X, y = value.Y}
    elseif t == "CFrame" then
        local p = value.Position
        return {type = "CFrame", x = p.X, y = p.Y, z = p.Z}
    elseif t == "Color3" then
        return {type = "Color3", r = value.R, g = value.G, b = value.B}
    elseif t == "EnumItem" then
        return tostring(value)
    elseif t == "table" then
        if seen[value] then
            return "<cycle>"
        end
        seen[value] = true

        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count += 1
            if count > 80 then
                out["<truncated>"] = true
                break
            end
            local key = tostring(k)
            out[key] = encodeValue(v, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end

    return tostring(value)
end

local function encodePackedArgs(packed)
    local values = {}
    for i = 1, packed.n do
        values[i] = encodeValue(packed[i])
    end
    return {count = packed.n, values = values}
end

local function packArgs(...)
    return encodePackedArgs(table.pack(...))
end

local function merge(dst, src)
    if type(src) ~= "table" then
        return dst
    end
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

--==============================================================--
-- NETWORK OBJECT DISCOVERY
--==============================================================--

local function findNetworkingObject(exactName, className)
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")

    local function match(inst)
        if inst.Name ~= exactName then
            return false
        end
        if className and not inst:IsA(className) then
            return false
        end
        return true
    end

    if networking then
        local direct = networking:FindFirstChild(exactName)
        if direct and match(direct) then
            return direct
        end
        for _, inst in ipairs(networking:GetDescendants()) do
            if match(inst) then
                return inst
            end
        end
    end

    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if match(inst) then
            return inst
        end
    end

    return nil
end

local REMOTES = {
    AskWearStill = findNetworkingObject("RF/Treadmill/AskWearStill", "RemoteFunction"),
    AskDoff = findNetworkingObject("RF/Treadmill/AskDoff", "RemoteFunction"),
    SpeedGained = findNetworkingObject("RE/Treadmill/SpeedGained", "RemoteEvent"),
    AssignedBeltShifted = findNetworkingObject("RE/Treadmill/AssignedBeltShifted", "RemoteEvent"),
    RenderStateShifted = findNetworkingObject("RE/Treadmill/RenderStateShifted", "RemoteEvent"),
    ProfileDelta = findNetworkingObject("RE/ProfileMirror/ProfileDelta", "RemoteEvent"),
}

--==============================================================--
-- TREADMILL DISCOVERY / SNAPSHOTS
--==============================================================--

local treadmillParts = {}

local function refreshTreadmillParts()
    table.clear(treadmillParts)

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") then
            local ok, full = pcall(function() return inst:GetFullName() end)
            if ok and string.find(string.lower(full), "treadmill", 1, true) then
                treadmillParts[#treadmillParts + 1] = inst
            end
        end
    end
end

local function getCharacterBits()
    local char = LocalPlayer.Character
    if not char then
        return nil, nil, nil
    end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function nearestTreadmill()
    local _, root = getCharacterBits()
    if not root then
        return nil, math.huge
    end

    local best, bestDist = nil, math.huge
    for i = #treadmillParts, 1, -1 do
        local part = treadmillParts[i]
        if not part or not part.Parent then
            table.remove(treadmillParts, i)
        else
            local ok, dist = pcall(function()
                return (root.Position - part.Position).Magnitude
            end)
            if ok and dist < bestDist then
                best = part
                bestDist = dist
            end
        end
    end

    return best, bestDist
end

local function findLeaderSpeedObject()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if not leaderstats then
        return nil
    end

    local direct = leaderstats:FindFirstChild("Speed")
    if direct and direct:IsA("ValueBase") then
        return direct
    end

    for _, inst in ipairs(leaderstats:GetDescendants()) do
        if inst:IsA("ValueBase") and string.lower(inst.Name) == "speed" then
            return inst
        end
    end
    return nil
end

local function leaderSpeedValue()
    local obj = findLeaderSpeedObject()
    if obj then
        local ok, value = pcall(function() return obj.Value end)
        if ok then return value end
    end
    return nil
end

local function makeSnapshot()
    local char, root, hum = getCharacterBits()
    local nearest, dist = nearestTreadmill()

    local snap = {
        character = char ~= nil,
        leaderSpeed = leaderSpeedValue(),
        treadmill = {
            near = dist < CONFIG.MIN_OUTSIDE_DISTANCE,
            distance = dist ~= math.huge and round(dist, 3) or nil,
            path = nearest and safePath(nearest) or nil,
        },
    }

    if root then
        snap.position = encodeValue(root.Position)
        snap.linearVelocity = encodeValue(root.AssemblyLinearVelocity)
        snap.horizontalVelocity = math.sqrt(
            root.AssemblyLinearVelocity.X ^ 2 + root.AssemblyLinearVelocity.Z ^ 2
        )
    end

    if hum then
        snap.walkSpeed = hum.WalkSpeed
        snap.moveDirection = encodeValue(hum.MoveDirection)
        snap.humanoidState = tostring(hum:GetState())
    end

    return snap
end

--==============================================================--
-- RUN STATE / LOGGING
--==============================================================--

local run = {
    active = false,
    uploading = false,
    records = {},
    seq = 0,
    startedClock = 0,
    startedUnix = 0,
    connections = {},
    lastLocalSpeedPower = nil,
    baselineSpeedGainedCount = 0,
    testSpeedGainedCount = 0,
    testSpeedGainedTotal = 0,
    localProfileDeltaCount = 0,
    assignedCount = 0,
    localRenderTrueCount = 0,
    localRenderFalseCount = 0,
    contaminated = false,
    minDistanceDuringTest = math.huge,
    askWearResult = nil,
    askWearError = nil,
    askWearDuration = nil,
    phase = "idle",
    summary = nil,
    localArchivePath = nil,
    uploadUrl = nil,
}

local function clearConnections()
    for _, c in ipairs(run.connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(run.connections)
end

local function addConnection(c)
    run.connections[#run.connections + 1] = c
    return c
end

local function log(kind, extra)
    run.seq += 1
    local row = {
        seq = run.seq,
        kind = kind,
        time = round(clock() - run.startedClock, 6),
        unix = nowUnix(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = game.PlaceVersion,
        phase = run.phase,
    }
    merge(row, encodeValue(extra or {}))
    run.records[#run.records + 1] = row
    return row
end

--==============================================================--
-- UI
--==============================================================--

pcall(function()
    local old = CoreGui:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)
pcall(function()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local old = pg and pg:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parentOk = false
if type(gethui) == "function" then
    parentOk = pcall(function() Gui.Parent = gethui() end)
end
if not parentOk then
    parentOk = pcall(function() Gui.Parent = CoreGui end)
end
if not parentOk then
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(330, 248)
Main.Position = UDim2.new(0.5, -165, 0.5, -124)
Main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(58, 58, 58)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(14, 10)
Title.Size = UDim2.new(1, -28, 0, 28)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "CAFEÍNA • TESTE DE ESTEIRA"
Title.Parent = Main

local Sub = Instance.new("TextLabel")
Sub.BackgroundTransparency = 1
Sub.Position = UDim2.fromOffset(14, 37)
Sub.Size = UDim2.new(1, -28, 0, 22)
Sub.Font = Enum.Font.Gotham
Sub.TextSize = 11
Sub.TextColor3 = Color3.fromRGB(155, 155, 155)
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Text = "TESTA AskWearStill FORA DA ESTEIRA"
Sub.Parent = Main

local Status = Instance.new("TextLabel")
Status.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
Status.BorderSizePixel = 0
Status.Position = UDim2.fromOffset(14, 68)
Status.Size = UDim2.new(1, -28, 0, 58)
Status.Font = Enum.Font.Gotham
Status.TextWrapped = true
Status.TextSize = 12
Status.TextColor3 = Color3.fromRGB(230, 230, 230)
Status.Text = "Pronto. Afaste-se pelo menos 35 studs de qualquer esteira."
Status.Parent = Main
Instance.new("UICorner", Status).CornerRadius = UDim.new(0, 8)

local ProgressBack = Instance.new("Frame")
ProgressBack.BackgroundColor3 = Color3.fromRGB(31, 31, 31)
ProgressBack.BorderSizePixel = 0
ProgressBack.Position = UDim2.fromOffset(14, 136)
ProgressBack.Size = UDim2.new(1, -28, 0, 10)
ProgressBack.Parent = Main
Instance.new("UICorner", ProgressBack).CornerRadius = UDim.new(1, 0)

local Progress = Instance.new("Frame")
Progress.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
Progress.BorderSizePixel = 0
Progress.Size = UDim2.new(0, 0, 1, 0)
Progress.Parent = ProgressBack
Instance.new("UICorner", Progress).CornerRadius = UDim.new(1, 0)

local Info = Instance.new("TextLabel")
Info.BackgroundTransparency = 1
Info.Position = UDim2.fromOffset(14, 151)
Info.Size = UDim2.new(1, -28, 0, 24)
Info.Font = Enum.Font.Gotham
Info.TextSize = 11
Info.TextColor3 = Color3.fromRGB(165, 165, 165)
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.Text = "Registros: 0 • Upload: aguardando"
Info.Parent = Main

local Start = Instance.new("TextButton")
Start.BackgroundColor3 = Color3.fromRGB(238, 238, 238)
Start.BorderSizePixel = 0
Start.Position = UDim2.fromOffset(14, 184)
Start.Size = UDim2.new(0.62, -7, 0, 46)
Start.Font = Enum.Font.GothamBold
Start.TextSize = 13
Start.TextColor3 = Color3.fromRGB(15, 15, 15)
Start.Text = "INICIAR TESTE"
Start.AutoButtonColor = true
Start.Parent = Main
Instance.new("UICorner", Start).CornerRadius = UDim.new(0, 9)

local RetryUpload = Instance.new("TextButton")
RetryUpload.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
RetryUpload.BorderSizePixel = 0
RetryUpload.Position = UDim2.new(0.62, 7, 0, 184)
RetryUpload.Size = UDim2.new(0.38, -21, 0, 46)
RetryUpload.Font = Enum.Font.GothamBold
RetryUpload.TextSize = 11
RetryUpload.TextColor3 = Color3.fromRGB(235, 235, 235)
RetryUpload.Text = "REENVIAR"
RetryUpload.AutoButtonColor = true
RetryUpload.Parent = Main
Instance.new("UICorner", RetryUpload).CornerRadius = UDim.new(0, 9)

local function setStatus(text)
    Status.Text = text
end

local function setProgress(frac)
    frac = math.clamp(frac or 0, 0, 1)
    Progress.Size = UDim2.new(frac, 0, 1, 0)
end

local function refreshInfo(uploadText)
    Info.Text = string.format(
        "Registros: %d • Upload: %s",
        #run.records,
        uploadText or (run.uploading and "enviando" or "aguardando")
    )
end

-- drag mobile/desktop
local dragging, dragStart, startPos = false, nil, nil
Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
Main.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

--==============================================================--
-- OBSERVERS
--==============================================================--

local function connectObservers()
    clearConnections()

    if REMOTES.SpeedGained then
        addConnection(REMOTES.SpeedGained.OnClientEvent:Connect(function(...)
            local args = table.pack(...)
            local amount = tonumber(args[1]) or 0
            if run.phase == "baseline" then
                run.baselineSpeedGainedCount += 1
            elseif run.phase == "test" then
                run.testSpeedGainedCount += 1
                run.testSpeedGainedTotal += amount
            end
            log("remote_received_speedgained", {
                remote = safePath(REMOTES.SpeedGained),
                payload = packArgs(...),
                snapshot = makeSnapshot(),
            })
            refreshInfo()
        end))
    end

    if REMOTES.AssignedBeltShifted then
        addConnection(REMOTES.AssignedBeltShifted.OnClientEvent:Connect(function(...)
            if run.phase == "test" then
                run.assignedCount += 1
            end
            log("remote_received_assigned_belt", {
                remote = safePath(REMOTES.AssignedBeltShifted),
                payload = packArgs(...),
                snapshot = makeSnapshot(),
            })
            refreshInfo()
        end))
    end

    if REMOTES.RenderStateShifted then
        addConnection(REMOTES.RenderStateShifted.OnClientEvent:Connect(function(...)
            local args = table.pack(...)
            local target = args[1]
            local state = args[2]
            local localTarget = target == LocalPlayer

            if run.phase == "test" and localTarget then
                if state == true then
                    run.localRenderTrueCount += 1
                elseif state == false then
                    run.localRenderFalseCount += 1
                end
            end

            log("remote_received_render_state", {
                remote = safePath(REMOTES.RenderStateShifted),
                localTarget = localTarget,
                state = state,
                payload = packArgs(...),
                snapshot = makeSnapshot(),
            })
            refreshInfo()
        end))
    end

    if REMOTES.ProfileDelta then
        addConnection(REMOTES.ProfileDelta.OnClientEvent:Connect(function(...)
            local args = table.pack(...)
            local delta = args[1]
            local target = args[3]
            local speedPower = nil
            if type(delta) == "table" then
                speedPower = tonumber(delta.SpeedPower)
            end

            if speedPower ~= nil and target == LocalPlayer then
                run.lastLocalSpeedPower = speedPower
                run.localProfileDeltaCount += 1
                log("local_speedpower_profile_delta", {
                    speedPower = speedPower,
                    remote = safePath(REMOTES.ProfileDelta),
                    payload = packArgs(...),
                    snapshot = makeSnapshot(),
                })
                refreshInfo()
            end
        end))
    end

    local leader = findLeaderSpeedObject()
    if leader then
        addConnection(leader:GetPropertyChangedSignal("Value"):Connect(function()
            log("leader_speed_changed", {
                value = leader.Value,
                path = safePath(leader),
                snapshot = makeSnapshot(),
            })
            refreshInfo()
        end))
    end

    local _, _, hum = getCharacterBits()
    if hum then
        addConnection(hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            log("walkspeed_changed", {
                walkSpeed = hum.WalkSpeed,
                snapshot = makeSnapshot(),
            })
            refreshInfo()
        end))
    end
end

--==============================================================--
-- HTTP / ARCHIVE
--==============================================================--

local function jsonEncode(value)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    return ok and result or nil
end

local function jsonDecode(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local ok, result = pcall(function()
        return HttpService:JSONDecode(value)
    end)
    return ok and result or nil
end

local function responseCode(res)
    if type(res) ~= "table" then return nil end
    return tonumber(res.StatusCode or res.Status or res.status_code or res.status)
end

local function responseBody(res)
    if type(res) ~= "table" then return nil end
    return res.Body or res.body or res.ResponseBody
end

local function withUploadToken(body)
    if CONFIG.UPLOAD_TOKEN ~= nil and tostring(CONFIG.UPLOAD_TOKEN) ~= "" then
        body.token = CONFIG.UPLOAD_TOKEN
    end
    return body
end

local function httpJson(method, url, bodyTable)
    if not requestFn then
        return false, "executor_sem_request"
    end

    local body = bodyTable and jsonEncode(bodyTable) or nil
    if bodyTable and not body then
        return false, "json_encode_failed"
    end

    local lastError = "unknown"
    for attempt = 1, CONFIG.RETRIES do
        local ok, res = pcall(requestFn, {
            Url = url,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
            },
            Body = body,
            Timeout = CONFIG.HTTP_TIMEOUT,
        })

        if ok and type(res) == "table" then
            local code = responseCode(res)
            local raw = responseBody(res)
            if code and code >= 200 and code < 300 then
                return true, jsonDecode(raw) or {}, res
            end
            lastError = string.format("HTTP %s: %s", tostring(code), tostring(raw))
        else
            lastError = tostring(res)
        end

        task.wait(CONFIG.RETRY_DELAY * attempt)
    end

    return false, lastError
end

local function ensureFolder()
    if not HAS_FS then return false end
    if HAS_FOLDER then
        local ok, exists = pcall(isfolder, CONFIG.SAVE_FOLDER)
        if not ok or not exists then
            pcall(makefolder, CONFIG.SAVE_FOLDER)
        end
    end
    return true
end

local function archiveObject()
    return {
        cafeinaTest = {
            source = CONFIG.VERSION,
            generatedAt = nowUnix(),
            placeId = game.PlaceId,
            gameId = game.GameId,
            placeVersion = game.PlaceVersion,
            clientVisibleOnly = true,
            activeControlledTest = true,
            minOutsideDistance = CONFIG.MIN_OUTSIDE_DISTANCE,
        },
        summary = run.summary,
        records = run.records,
    }
end

local function saveArchive()
    if not HAS_FS then
        return nil, "filesystem_indisponivel"
    end

    ensureFolder()
    local filename = string.format(
        "Cafeina_TreadmillOutsideTest_%s_%s.json",
        tostring(game.PlaceId),
        timestampName()
    )
    local path = CONFIG.SAVE_FOLDER .. "/" .. filename
    local encoded = jsonEncode(archiveObject())
    if not encoded then
        return nil, "json_encode_failed"
    end

    local ok, err = pcall(writefile, path, encoded)
    if not ok then
        return nil, tostring(err)
    end

    run.localArchivePath = path
    return path, nil
end

local function makeChunks(records)
    local chunks = {}
    local current = {}
    local currentBytes = 2

    for _, row in ipairs(records) do
        local encoded = jsonEncode(row) or "{}"
        local rowBytes = #encoded + 1

        if #current > 0 and currentBytes + rowBytes > CONFIG.TARGET_CHUNK_BYTES then
            chunks[#chunks + 1] = current
            current = {}
            currentBytes = 2
        end

        current[#current + 1] = row
        currentBytes += rowBytes
    end

    if #current > 0 then
        chunks[#chunks + 1] = current
    end

    return chunks
end

local function uploadArchive()
    if run.uploading then
        return false, "upload_em_andamento"
    end
    if not requestFn then
        setStatus("Teste salvo, mas este executor não oferece função HTTP request.")
        refreshInfo("sem request")
        return false, "executor_sem_request"
    end
    if #run.records == 0 then
        return false, "sem_registros"
    end

    run.uploading = true
    refreshInfo("iniciando")
    setProgress(0.05)

    local filename = string.format(
        "Cafeina_TreadmillOutsideTest_%s_%s.json",
        tostring(game.PlaceId),
        timestampName()
    )

    local chunks = makeChunks(run.records)
    local metadata = {
        scanner = CONFIG.VERSION,
        source = CONFIG.VERSION,
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = game.PlaceVersion,
        recordCount = #run.records,
        totalChunks = #chunks,
        targetChunkBytes = CONFIG.TARGET_CHUNK_BYTES,
        focus = "treadmill_askwearstill_outside",
        clientVisibleOnly = true,
        activeControlledTest = true,
        summary = run.summary,
    }

    local okStart, startData = httpJson("POST", CONFIG.BASE_URL .. CONFIG.START_PATH, withUploadToken({
        filename = filename,
        source = CONFIG.VERSION,
        metadata = metadata,
    }))

    if not okStart then
        run.uploading = false
        setStatus("Falha ao iniciar upload: " .. tostring(startData))
        refreshInfo("falhou")
        return false, startData
    end

    local uploadId = startData.uploadId or startData.id or startData.upload_id
    if not uploadId then
        run.uploading = false
        setStatus("Servidor respondeu ao /upload/start, mas não devolveu uploadId.")
        refreshInfo("falhou")
        return false, "uploadId_ausente"
    end

    for i, chunk in ipairs(chunks) do
        setStatus(string.format("Enviando chunk %d/%d...", i, #chunks))
        setProgress(0.08 + 0.82 * ((i - 1) / math.max(#chunks, 1)))
        refreshInfo(string.format("%d/%d", i - 1, #chunks))

        local okChunk, chunkData = httpJson("POST", CONFIG.BASE_URL .. CONFIG.CHUNK_PATH, withUploadToken({
            uploadId = uploadId,
            index = i,
            objects = chunk,
        }))

        if not okChunk then
            pcall(function()
                httpJson("POST", CONFIG.BASE_URL .. CONFIG.CANCEL_PATH, withUploadToken({
                    uploadId = uploadId,
                }))
            end)
            run.uploading = false
            setStatus(string.format("Falha no chunk %d: %s", i, tostring(chunkData)))
            refreshInfo("falhou")
            return false, chunkData
        end
    end

    setProgress(0.93)
    setStatus("Finalizando upload no servidor...")
    refreshInfo("finalizando")

    local okFinish, finishData = httpJson("POST", CONFIG.BASE_URL .. CONFIG.FINISH_PATH, withUploadToken({
        uploadId = uploadId,
        totalChunks = #chunks,
        summary = run.summary,
    }))

    if not okFinish then
        run.uploading = false
        setStatus("Chunks enviados, mas /upload/finish falhou: " .. tostring(finishData))
        refreshInfo("finish falhou")
        return false, finishData
    end

    run.uploadUrl = finishData.url or finishData.downloadUrl or finishData.fileUrl or finishData.link
    run.uploading = false
    setProgress(1)
    setStatus("Upload confirmado. Coleta enviada com sucesso.")
    refreshInfo("concluído")

    -- Delete the local temporary archive only after server confirmation.
    if run.localArchivePath and HAS_DELETE then
        pcall(delfile, run.localArchivePath)
        run.localArchivePath = nil
    end

    return true, finishData
end

--==============================================================--
-- TEST LOGIC
--==============================================================--

local function requiredRemotesPresent()
    local missing = {}
    for _, name in ipairs({"AskWearStill", "SpeedGained", "AssignedBeltShifted", "RenderStateShifted", "ProfileDelta"}) do
        if not REMOTES[name] then
            missing[#missing + 1] = name
        end
    end
    return #missing == 0, missing
end

local function invokeRemoteFunction(label, remote)
    if not remote then
        log("remote_invoke_missing", {label = label})
        return false, "missing"
    end

    local before = makeSnapshot()
    local started = clock()
    local returned = nil
    local ok, err = pcall(function()
        returned = table.pack(remote:InvokeServer())
    end)
    local duration = clock() - started

    if ok then
        returned = returned or table.pack()
        log("remote_invoke", {
            label = label,
            remote = safePath(remote),
            payload = {count = 0, values = {}},
            returns = encodePackedArgs(returned),
            duration = duration,
            before = before,
            after = makeSnapshot(),
        })
        return true, returned[1], duration, returned
    else
        log("remote_invoke_error", {
            label = label,
            remote = safePath(remote),
            error = tostring(err),
            duration = duration,
            before = before,
            after = makeSnapshot(),
        })
        return false, tostring(err), duration, nil
    end
end

local function sampleFor(seconds, progressFrom, progressTo)
    local started = clock()
    while run.active and clock() - started < seconds do
        local snap = makeSnapshot()
        local dist = snap.treadmill and snap.treadmill.distance

        if run.phase == "test" and type(dist) == "number" then
            run.minDistanceDuringTest = math.min(run.minDistanceDuringTest, dist)
            if dist < CONFIG.MIN_OUTSIDE_DISTANCE then
                run.contaminated = true
            end
        end

        log("sample", {snapshot = snap})
        refreshInfo()

        local frac = math.clamp((clock() - started) / seconds, 0, 1)
        setProgress(progressFrom + (progressTo - progressFrom) * frac)
        task.wait(CONFIG.SAMPLE_INTERVAL)
    end
end

local function resetRun()
    clearConnections()
    run.active = false
    run.uploading = false
    run.records = {}
    run.seq = 0
    run.startedClock = clock()
    run.startedUnix = nowUnix()
    run.connections = {}
    run.lastLocalSpeedPower = nil
    run.baselineSpeedGainedCount = 0
    run.testSpeedGainedCount = 0
    run.testSpeedGainedTotal = 0
    run.localProfileDeltaCount = 0
    run.assignedCount = 0
    run.localRenderTrueCount = 0
    run.localRenderFalseCount = 0
    run.contaminated = false
    run.minDistanceDuringTest = math.huge
    run.askWearResult = nil
    run.askWearError = nil
    run.askWearDuration = nil
    run.phase = "idle"
    run.summary = nil
    run.localArchivePath = nil
    run.uploadUrl = nil
    setProgress(0)
    refreshInfo("aguardando")
end

local function finalizeSummary(initialLeaderSpeed, finalLeaderSpeed, initialWalkSpeed, finalWalkSpeed)
    local leaderDelta = nil
    if type(initialLeaderSpeed) == "number" and type(finalLeaderSpeed) == "number" then
        leaderDelta = finalLeaderSpeed - initialLeaderSpeed
    end

    local walkDelta = nil
    if type(initialWalkSpeed) == "number" and type(finalWalkSpeed) == "number" then
        walkDelta = finalWalkSpeed - initialWalkSpeed
    end

    local verdict
    if run.contaminated then
        verdict = "INCONCLUSIVE_APPROACHED_TREADMILL"
    elseif run.testSpeedGainedTotal > 0 or (type(leaderDelta) == "number" and leaderDelta > 0) then
        verdict = "CONFIRMED_TRAINING_OUTSIDE_TREADMILL"
    elseif run.askWearError then
        verdict = "ASKWEAR_CALL_ERROR"
    elseif run.askWearResult == false then
        verdict = "SERVER_REJECTED_OUTSIDE_REQUEST"
    elseif run.askWearResult == true and (run.assignedCount > 0 or run.localRenderTrueCount > 0) then
        verdict = "SERVER_ASSIGNED_BUT_NO_SPEED_GAIN_OBSERVED"
    elseif run.askWearResult == true then
        verdict = "ASKWEAR_RETURNED_TRUE_BUT_NO_TRAINING_EVIDENCE"
    else
        verdict = "NO_CONFIRMATION"
    end

    run.summary = {
        verdict = verdict,
        askWearReturn = encodeValue(run.askWearResult),
        askWearError = run.askWearError,
        askWearDuration = run.askWearDuration,
        minOutsideDistanceRequired = CONFIG.MIN_OUTSIDE_DISTANCE,
        minDistanceDuringTest = run.minDistanceDuringTest ~= math.huge and run.minDistanceDuringTest or nil,
        contaminatedByApproachingTreadmill = run.contaminated,
        baselineSpeedGainedCount = run.baselineSpeedGainedCount,
        testSpeedGainedCount = run.testSpeedGainedCount,
        testSpeedGainedTotal = run.testSpeedGainedTotal,
        localProfileDeltaCount = run.localProfileDeltaCount,
        assignedBeltEvents = run.assignedCount,
        localRenderTrueEvents = run.localRenderTrueCount,
        localRenderFalseEvents = run.localRenderFalseCount,
        initialLeaderSpeed = initialLeaderSpeed,
        finalLeaderSpeed = finalLeaderSpeed,
        leaderSpeedDelta = leaderDelta,
        initialWalkSpeed = initialWalkSpeed,
        finalWalkSpeed = finalWalkSpeed,
        walkSpeedDelta = walkDelta,
        finalLocalSpeedPower = run.lastLocalSpeedPower,
        records = #run.records,
    }

    log("test_summary", run.summary)
    return verdict
end

local function runTest()
    if run.active or run.uploading then
        return
    end

    if game.PlaceId ~= CONFIG.PLACE_ID then
        setStatus("PlaceId diferente do jogo esperado. Teste cancelado por segurança.")
        return
    end

    refreshTreadmillParts()
    local remotesOk, missing = requiredRemotesPresent()
    if not remotesOk then
        setStatus("Remotes ausentes: " .. table.concat(missing, ", "))
        return
    end

    local _, initialDistance = nearestTreadmill()
    if initialDistance < CONFIG.MIN_OUTSIDE_DISTANCE then
        setStatus(string.format(
            "Você está a %.1f studs de uma esteira. Afaste-se para > %d e toque novamente.",
            initialDistance,
            CONFIG.MIN_OUTSIDE_DISTANCE
        ))
        return
    end

    resetRun()
    run.active = true
    run.phase = "setup"
    Start.Text = "TESTANDO..."
    Start.AutoButtonColor = false

    local _, _, hum = getCharacterBits()
    local initialLeaderSpeed = leaderSpeedValue()
    local initialWalkSpeed = hum and hum.WalkSpeed or nil

    log("session_started", {
        scanner = CONFIG.VERSION,
        clientVisibleOnly = true,
        controlledTest = true,
        expectedAskWearArgs = 0,
        requiredOutsideDistance = CONFIG.MIN_OUTSIDE_DISTANCE,
        remotes = {
            AskWearStill = safePath(REMOTES.AskWearStill),
            AskDoff = safePath(REMOTES.AskDoff),
            SpeedGained = safePath(REMOTES.SpeedGained),
            AssignedBeltShifted = safePath(REMOTES.AssignedBeltShifted),
            RenderStateShifted = safePath(REMOTES.RenderStateShifted),
            ProfileDelta = safePath(REMOTES.ProfileDelta),
        },
        snapshot = makeSnapshot(),
    })

    connectObservers()

    -- Baseline: verify no pre-existing treadmill gain is already running.
    run.phase = "baseline"
    setStatus("Baseline: observando sem chamar a esteira...")
    sampleFor(CONFIG.BASELINE_SECONDS, 0.02, 0.22)

    if run.baselineSpeedGainedCount > 0 and REMOTES.AskDoff then
        setStatus("Havia ganho ativo. Encerrando estado anterior antes do teste...")
        run.phase = "cleanup_pretest"
        invokeRemoteFunction("AskDoff_pretest", REMOTES.AskDoff)
        task.wait(1.5)
        run.baselineSpeedGainedCount = 0
        run.phase = "baseline"
        sampleFor(1.5, 0.22, 0.30)
    end

    local _, distBefore = nearestTreadmill()
    if distBefore < CONFIG.MIN_OUTSIDE_DISTANCE then
        run.contaminated = true
        run.phase = "finalizing"
        setStatus("Teste cancelado: você se aproximou de uma esteira durante o baseline.")
    else
        -- Controlled active test: exactly one normal InvokeServer() with zero args.
        run.phase = "test"
        setStatus("Chamando AskWearStill UMA vez, fora da esteira...")
        setProgress(0.32)

        local ok, ret, duration = invokeRemoteFunction("AskWearStill_outside", REMOTES.AskWearStill)
        run.askWearDuration = duration
        if ok then
            run.askWearResult = ret
        else
            run.askWearError = tostring(ret)
        end

        setStatus("Observando resposta do servidor e possíveis ganhos por 8 segundos...")
        sampleFor(CONFIG.OBSERVE_SECONDS, 0.36, 0.78)
    end

    -- Clean up only if the server appears to have assigned/started the treadmill.
    if REMOTES.AskDoff and (run.testSpeedGainedCount > 0 or run.localRenderTrueCount > 0 or run.assignedCount > 0) then
        run.phase = "cleanup"
        setStatus("Encerrando estado de esteira após o teste...")
        invokeRemoteFunction("AskDoff_cleanup", REMOTES.AskDoff)
        task.wait(0.75)
    end

    run.phase = "finalizing"
    local _, _, finalHum = getCharacterBits()
    local finalLeaderSpeed = leaderSpeedValue()
    local finalWalkSpeed = finalHum and finalHum.WalkSpeed or nil
    local verdict = finalizeSummary(initialLeaderSpeed, finalLeaderSpeed, initialWalkSpeed, finalWalkSpeed)

    run.active = false
    clearConnections()

    setProgress(0.82)
    refreshInfo("salvando")
    local savedPath = saveArchive()

    if verdict == "CONFIRMED_TRAINING_OUTSIDE_TREADMILL" then
        setStatus("RESULTADO: servidor concedeu ganho fora da esteira. Enviando coleta...")
    elseif verdict == "SERVER_REJECTED_OUTSIDE_REQUEST" then
        setStatus("RESULTADO: servidor rejeitou o pedido fora da esteira. Enviando coleta...")
    elseif verdict == "INCONCLUSIVE_APPROACHED_TREADMILL" then
        setStatus("RESULTADO INCONCLUSIVO: houve aproximação de esteira. Enviando mesmo assim...")
    else
        setStatus("RESULTADO: " .. verdict .. ". Enviando coleta...")
    end

    setProgress(0.85)
    refreshInfo(savedPath and "salvo" or "memória")

    uploadArchive()

    Start.Text = "NOVO TESTE"
    Start.AutoButtonColor = true
end

Start.MouseButton1Click:Connect(function()
    task.spawn(runTest)
end)

RetryUpload.MouseButton1Click:Connect(function()
    if run.uploading or run.active then return end
    if #run.records == 0 then
        setStatus("Ainda não existe uma coleta para reenviar.")
        return
    end
    task.spawn(uploadArchive)
end)

-- Initial capability/status report in UI only.
task.spawn(function()
    refreshTreadmillParts()
    local remotesOk, missing = requiredRemotesPresent()
    local _, dist = nearestTreadmill()

    if not remotesOk then
        setStatus("Scanner pronto, mas faltam remotes: " .. table.concat(missing, ", "))
    elseif dist < CONFIG.MIN_OUTSIDE_DISTANCE then
        setStatus(string.format("Afaste-se da esteira: distância atual %.1f; mínimo %d studs.", dist, CONFIG.MIN_OUTSIDE_DISTANCE))
    elseif not requestFn then
        setStatus("Pronto para testar. Aviso: executor sem HTTP request; coleta será salva localmente se possível.")
    else
        setStatus(string.format("Pronto. Distância da esteira: %.1f studs. Pode iniciar o teste.", dist))
    end
end)
