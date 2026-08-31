--==============================================================--
-- CAFEÍNA • TREADMILL LEGIT TRACE V2.0
-- Passive trace of a NORMAL treadmill session.
--
-- Flow to record:
-- baseline -> player enters normally -> game's AskWearStill ->
-- AssignedBeltShifted / RenderStateShifted -> SpeedGained ->
-- local ProfileMirror/ProfileDelta -> leaderstats Speed / WalkSpeed ->
-- game's AskDoff -> post-exit -> upload.
--
-- IMPORTANT:
-- * This script DOES NOT invoke AskWearStill or AskDoff itself.
-- * It does not attempt to bypass "Not at treadmill".
-- * It only observes client-visible behavior and the normal calls
--   already made by the game's own client code.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "TREADMILL_LEGIT_TRACE_V2_0",
    GUI_NAME = "CafeinaTreadmillLegitTraceV2",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    START_PATH = "/upload/start",
    CHUNK_PATH = "/upload/chunk",
    FINISH_PATH = "/upload/finish",
    CANCEL_PATH = "/upload/cancel",

    BASELINE_SECONDS = 2.0,
    POST_DOFF_SECONDS = 2.5,
    MAX_SESSION_SECONDS = 90,
    SAMPLE_INTERVAL = 0.10,

    TARGET_CHUNK_BYTES = 500000,
    RETRIES = 3,
    RETRY_DELAY = 1.25,
    HTTP_TIMEOUT = 30,
    UPLOAD_TOKEN = nil,

    SAVE_FOLDER = "CafeinaArchive",
    PLACE_ID = 107778070777162,
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local requestFn
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
local HAS_HOOK = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
local HAS_NEWCLOSURE = type(newcclosure) == "function"
local HAS_CHECKCALLER = type(checkcaller) == "function"

--==============================================================--
-- HELPERS
--==============================================================--

local function mono()
    return os.clock()
end

local function unix()
    return os.time()
end

local function timestampName()
    local ok, s = pcall(function()
        return os.date("!%Y%m%d_%H%M%S")
    end)
    return ok and s or tostring(unix())
end

local function safePath(inst)
    if typeof(inst) ~= "Instance" then return nil end
    local ok, path = pcall(function() return inst:GetFullName() end)
    return ok and path or inst.Name
end

local function round(n, digits)
    if type(n) ~= "number" then return n end
    local p = 10 ^ (digits or 6)
    return math.floor(n * p + 0.5) / p
end

local function encodeValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then return "<max-depth>" end

    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "string" then
        return v
    elseif t == "number" then
        if v ~= v then return "NaN" end
        if v == math.huge then return "Infinity" end
        if v == -math.huge then return "-Infinity" end
        return v
    elseif t == "Instance" then
        return {
            type = "Instance",
            className = v.ClassName,
            name = v.Name,
            path = safePath(v),
            isLocalPlayer = v == LocalPlayer,
        }
    elseif t == "Vector3" then
        return {type="Vector3", x=v.X, y=v.Y, z=v.Z}
    elseif t == "Vector2" then
        return {type="Vector2", x=v.X, y=v.Y}
    elseif t == "CFrame" then
        local p = v.Position
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z}
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n > 100 then
                out["<truncated>"] = true
                break
            end
            out[tostring(k)] = encodeValue(x, depth + 1, seen)
        end
        seen[v] = nil
        return out
    end
    return tostring(v)
end

local function encodePacked(p)
    local out = {}
    for i = 1, p.n do
        out[i] = encodeValue(p[i])
    end
    return {count=p.n, values=out}
end

local function packArgs(...)
    return encodePacked(table.pack(...))
end

local function merge(dst, src)
    if type(src) == "table" then
        for k, v in pairs(src) do dst[k] = v end
    end
    return dst
end

local function jsonEncode(v)
    local ok, res = pcall(function() return HttpService:JSONEncode(v) end)
    return ok and res or nil
end

local function jsonDecode(v)
    if type(v) ~= "string" or v == "" then return nil end
    local ok, res = pcall(function() return HttpService:JSONDecode(v) end)
    return ok and res or nil
end

--==============================================================--
-- NETWORK DISCOVERY
--==============================================================--

local function findNetworkingObject(exactName, className)
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst.Name == exactName and (not className or inst:IsA(className)) then
            return inst
        end
    end
    return nil
end

local REMOTES = {
    AskWearStill = findNetworkingObject("RF/Treadmill/AskWearStill", "RemoteFunction"),
    AskDoff = findNetworkingObject("RF/Treadmill/AskDoff", "RemoteFunction"),
    AssignedBeltShifted = findNetworkingObject("RE/Treadmill/AssignedBeltShifted", "RemoteEvent"),
    SpeedGained = findNetworkingObject("RE/Treadmill/SpeedGained", "RemoteEvent"),
    RenderStateShifted = findNetworkingObject("RE/Treadmill/RenderStateShifted", "RemoteEvent"),
    ProfileDelta = findNetworkingObject("RE/ProfileMirror/ProfileDelta", "RemoteEvent"),
}

local TARGET_OUTBOUND = {}
if REMOTES.AskWearStill then TARGET_OUTBOUND[REMOTES.AskWearStill] = "AskWearStill" end
if REMOTES.AskDoff then TARGET_OUTBOUND[REMOTES.AskDoff] = "AskDoff" end

--==============================================================--
-- CHARACTER / TREADMILL STATE
--==============================================================--

local treadmillParts = {}

local function refreshTreadmills()
    table.clear(treadmillParts)
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") then
            local path = safePath(inst)
            if path and string.find(string.lower(path), "treadmill", 1, true) then
                treadmillParts[#treadmillParts + 1] = inst
            end
        end
    end
end

local function charBits()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    return char, char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart, char:FindFirstChildOfClass("Humanoid")
end

local function nearestTreadmill()
    local _, root = charBits()
    if not root then return nil, nil end
    local best, bestD = nil, math.huge
    for i = #treadmillParts, 1, -1 do
        local p = treadmillParts[i]
        if not p or not p.Parent then
            table.remove(treadmillParts, i)
        else
            local ok, d = pcall(function() return (root.Position - p.Position).Magnitude end)
            if ok and d < bestD then
                best, bestD = p, d
            end
        end
    end
    if bestD == math.huge then bestD = nil end
    return best, bestD
end

local function findLeaderSpeed()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local direct = ls:FindFirstChild("Speed")
    if direct and direct:IsA("ValueBase") then return direct end
    for _, v in ipairs(ls:GetDescendants()) do
        if v:IsA("ValueBase") and string.lower(v.Name) == "speed" then
            return v
        end
    end
    return nil
end

local function leaderSpeedValue()
    local v = findLeaderSpeed()
    if not v then return nil end
    local ok, x = pcall(function() return v.Value end)
    return ok and x or nil
end

local function snapshot()
    local char, root, hum = charBits()
    local tread, d = nearestTreadmill()
    local s = {
        character = char ~= nil,
        leaderSpeed = leaderSpeedValue(),
        treadmill = {
            path = tread and safePath(tread) or nil,
            distance = d and round(d, 4) or nil,
        },
    }

    if root then
        s.position = encodeValue(root.Position)
        s.cframe = encodeValue(root.CFrame)
        s.linearVelocity = encodeValue(root.AssemblyLinearVelocity)
        s.horizontalVelocity = math.sqrt(
            root.AssemblyLinearVelocity.X^2 + root.AssemblyLinearVelocity.Z^2
        )
    end
    if hum then
        s.walkSpeed = hum.WalkSpeed
        s.moveDirection = encodeValue(hum.MoveDirection)
        s.humanoidState = tostring(hum:GetState())
    end
    return s
end

--==============================================================--
-- RUN STATE / TIMELINE
--==============================================================--

local run = {
    active = false,
    uploading = false,
    stopRequested = false,
    phase = "idle",
    startedClock = 0,
    startedUnix = 0,
    seq = 0,
    records = {},
    connections = {},
    localArchivePath = nil,
    uploadUrl = nil,

    firstAskWear = nil,
    askWearReturn = nil,
    firstAssigned = nil,
    firstRenderTrue = nil,
    firstSpeedGained = nil,
    firstLocalProfileDelta = nil,
    firstLeaderChange = nil,
    firstWalkSpeedChange = nil,
    firstAskDoff = nil,
    firstRenderFalse = nil,

    speedGainedCount = 0,
    speedGainedTotal = 0,
    localProfileCount = 0,
    localSpeedPowerInitial = nil,
    localSpeedPowerFinal = nil,

    initialLeaderSpeed = nil,
    finalLeaderSpeed = nil,
    initialWalkSpeed = nil,
    finalWalkSpeed = nil,

    lastSpeedGainAmount = nil,
    lastSpeedGainTime = nil,
    minTreadmillDistance = math.huge,
    summary = nil,
}

local function elapsed()
    return mono() - run.startedClock
end

local function addConnection(c)
    run.connections[#run.connections + 1] = c
    return c
end

local function clearConnections()
    for _, c in ipairs(run.connections) do pcall(function() c:Disconnect() end) end
    table.clear(run.connections)
end

local function log(kind, data, forcedTime)
    if not run.active and kind ~= "trace_summary" then return end
    run.seq += 1
    local row = {
        seq = run.seq,
        kind = kind,
        t = round(forcedTime or elapsed(), 6),
        unix = unix(),
        phase = run.phase,
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = game.PlaceVersion,
    }
    merge(row, encodeValue(data or {}))
    run.records[#run.records + 1] = row
end

local function mark(field, t)
    if run[field] == nil then run[field] = t end
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

local parented = false
if type(gethui) == "function" then parented = pcall(function() Gui.Parent = gethui() end) end
if not parented then parented = pcall(function() Gui.Parent = CoreGui end) end
if not parented then Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(348, 282)
Main.Position = UDim2.new(0.5, -174, 0.5, -141)
Main.BackgroundColor3 = Color3.fromRGB(14,14,14)
Main.BorderSizePixel = 0
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,12)
local st = Instance.new("UIStroke", Main)
st.Color = Color3.fromRGB(55,55,55)
st.Thickness = 1

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(14,9)
Title.Size = UDim2.new(1,-28,0,27)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextColor3 = Color3.fromRGB(245,245,245)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "CAFEÍNA • TREADMILL TRACE V2"
Title.Parent = Main

local Sub = Instance.new("TextLabel")
Sub.BackgroundTransparency = 1
Sub.Position = UDim2.fromOffset(14,35)
Sub.Size = UDim2.new(1,-28,0,22)
Sub.Font = Enum.Font.Gotham
Sub.TextSize = 11
Sub.TextColor3 = Color3.fromRGB(155,155,155)
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Text = "SESSÃO REAL • ENTRAR → CORRER → SAIR"
Sub.Parent = Main

local Status = Instance.new("TextLabel")
Status.BackgroundColor3 = Color3.fromRGB(24,24,24)
Status.BorderSizePixel = 0
Status.Position = UDim2.fromOffset(14,66)
Status.Size = UDim2.new(1,-28,0,72)
Status.Font = Enum.Font.Gotham
Status.TextWrapped = true
Status.TextSize = 12
Status.TextColor3 = Color3.fromRGB(232,232,232)
Status.Text = "Pronto. Inicie antes de subir na esteira."
Status.Parent = Main
Instance.new("UICorner", Status).CornerRadius = UDim.new(0,8)

local ProgressBack = Instance.new("Frame")
ProgressBack.BackgroundColor3 = Color3.fromRGB(30,30,30)
ProgressBack.BorderSizePixel = 0
ProgressBack.Position = UDim2.fromOffset(14,148)
ProgressBack.Size = UDim2.new(1,-28,0,10)
ProgressBack.Parent = Main
Instance.new("UICorner", ProgressBack).CornerRadius = UDim.new(1,0)

local Progress = Instance.new("Frame")
Progress.BackgroundColor3 = Color3.fromRGB(235,235,235)
Progress.BorderSizePixel = 0
Progress.Size = UDim2.new(0,0,1,0)
Progress.Parent = ProgressBack
Instance.new("UICorner", Progress).CornerRadius = UDim.new(1,0)

local Info = Instance.new("TextLabel")
Info.BackgroundTransparency = 1
Info.Position = UDim2.fromOffset(14,165)
Info.Size = UDim2.new(1,-28,0,42)
Info.Font = Enum.Font.Gotham
Info.TextSize = 11
Info.TextColor3 = Color3.fromRGB(170,170,170)
Info.TextWrapped = true
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.Text = "Registros: 0 • Ganho: 0 • Fase: idle"
Info.Parent = Main

local Start = Instance.new("TextButton")
Start.BackgroundColor3 = Color3.fromRGB(238,238,238)
Start.BorderSizePixel = 0
Start.Position = UDim2.fromOffset(14,220)
Start.Size = UDim2.new(0.58,-7,0,47)
Start.Font = Enum.Font.GothamBold
Start.TextSize = 12
Start.TextColor3 = Color3.fromRGB(14,14,14)
Start.Text = "INICIAR COLETA"
Start.Parent = Main
Instance.new("UICorner", Start).CornerRadius = UDim.new(0,9)

local Stop = Instance.new("TextButton")
Stop.BackgroundColor3 = Color3.fromRGB(45,45,45)
Stop.BorderSizePixel = 0
Stop.Position = UDim2.new(0.58,7,0,220)
Stop.Size = UDim2.new(0.42,-21,0,47)
Stop.Font = Enum.Font.GothamBold
Stop.TextSize = 11
Stop.TextColor3 = Color3.fromRGB(240,240,240)
Stop.Text = "ENCERRAR + ENVIAR"
Stop.Parent = Main
Instance.new("UICorner", Stop).CornerRadius = UDim.new(0,9)

local function setStatus(s) Status.Text = s end
local function setProgress(x) Progress.Size = UDim2.new(math.clamp(x or 0,0,1),0,1,0) end
local function refreshInfo(uploadText)
    Info.Text = string.format(
        "Registros: %d • SpeedGained: %d (%s) • Fase: %s%s",
        #run.records,
        run.speedGainedCount,
        tostring(run.speedGainedTotal),
        tostring(run.phase),
        uploadText and (" • " .. uploadText) or ""
    )
end

-- draggable
local dragging, dragStart, mainStart = false, nil, nil
Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, mainStart = true, input.Position, Main.Position
    end
end)
Main.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local d = input.Position - dragStart
    Main.Position = UDim2.new(mainStart.X.Scale, mainStart.X.Offset+d.X, mainStart.Y.Scale, mainStart.Y.Offset+d.Y)
end)

--==============================================================--
-- PASSIVE OUTBOUND HOOK
--==============================================================--

local hookInstalled = false
local originalNamecall

local function installHook()
    if hookInstalled then return true end
    if not HAS_HOOK then return false end

    local wrapper = function(self, ...)
        local method = getnamecallmethod()
        local label = TARGET_OUTBOUND[self]

        if run.active and label and method == "InvokeServer" then
            local callT = elapsed()
            local before = snapshot()
            local argsPacked = table.pack(...)
            local fromExecutor = HAS_CHECKCALLER and checkcaller() or nil

            if label == "AskWearStill" then
                mark("firstAskWear", callT)
                run.phase = "askwear"
            elseif label == "AskDoff" then
                mark("firstAskDoff", callT)
                run.phase = "doff"
            end

            log("remote_invoke_begin", {
                label = label,
                remote = safePath(self),
                method = method,
                payload = encodePacked(argsPacked),
                callerIsExecutor = fromExecutor,
                snapshot = before,
            }, callT)

            local started = mono()
            local ret = table.pack(originalNamecall(self, ...))
            local duration = mono() - started
            local endT = elapsed()

            if label == "AskWearStill" then
                run.askWearReturn = encodePacked(ret)
            end

            log("remote_invoke_end", {
                label = label,
                remote = safePath(self),
                method = method,
                returns = encodePacked(ret),
                duration = duration,
                callerIsExecutor = fromExecutor,
                snapshot = snapshot(),
            }, endT)

            return table.unpack(ret, 1, ret.n)
        end

        return originalNamecall(self, ...)
    end

    if HAS_NEWCLOSURE then wrapper = newcclosure(wrapper) end

    local ok, old = pcall(function()
        return hookmetamethod(game, "__namecall", wrapper)
    end)

    if ok and old then
        originalNamecall = old
        hookInstalled = true
        return true
    end
    return false
end

--==============================================================--
-- INBOUND / PROPERTY OBSERVERS
--==============================================================--

local function connectObservers()
    clearConnections()

    if REMOTES.AssignedBeltShifted then
        addConnection(REMOTES.AssignedBeltShifted.OnClientEvent:Connect(function(...)
            local t = elapsed()
            mark("firstAssigned", t)
            run.phase = "assigned"
            log("remote_received_assigned_belt", {
                remote=safePath(REMOTES.AssignedBeltShifted),
                payload=packArgs(...),
                snapshot=snapshot(),
            }, t)
            refreshInfo()
        end))
    end

    if REMOTES.RenderStateShifted then
        addConnection(REMOTES.RenderStateShifted.OnClientEvent:Connect(function(...)
            local p = table.pack(...)
            local target, state = p[1], p[2]
            local localTarget = target == LocalPlayer
            local t = elapsed()

            if localTarget and state == true then
                mark("firstRenderTrue", t)
                run.phase = "render_on"
            elseif localTarget and state == false then
                mark("firstRenderFalse", t)
                run.phase = "render_off"
            end

            log("remote_received_render_state", {
                remote=safePath(REMOTES.RenderStateShifted),
                localTarget=localTarget,
                state=state,
                payload=encodePacked(p),
                snapshot=snapshot(),
            }, t)
            refreshInfo()
        end))
    end

    if REMOTES.SpeedGained then
        addConnection(REMOTES.SpeedGained.OnClientEvent:Connect(function(...)
            local p = table.pack(...)
            local amount = tonumber(p[1]) or 0
            local t = elapsed()

            mark("firstSpeedGained", t)
            run.phase = "training"
            run.speedGainedCount += 1
            run.speedGainedTotal += amount
            run.lastSpeedGainAmount = amount
            run.lastSpeedGainTime = t

            log("remote_received_speed_gained", {
                remote=safePath(REMOTES.SpeedGained),
                amount=amount,
                payload=encodePacked(p),
                snapshot=snapshot(),
            }, t)
            refreshInfo()
        end))
    end

    if REMOTES.ProfileDelta then
        addConnection(REMOTES.ProfileDelta.OnClientEvent:Connect(function(...)
            local p = table.pack(...)
            local delta, target = p[1], p[3]
            local speedPower = type(delta) == "table" and tonumber(delta.SpeedPower) or nil
            local localTarget = target == LocalPlayer
            local t = elapsed()

            if localTarget and speedPower ~= nil then
                mark("firstLocalProfileDelta", t)
                run.localProfileCount += 1
                if run.localSpeedPowerInitial == nil then run.localSpeedPowerInitial = speedPower end
                run.localSpeedPowerFinal = speedPower

                log("local_profile_speedpower_delta", {
                    remote=safePath(REMOTES.ProfileDelta),
                    speedPower=speedPower,
                    localTarget=true,
                    payload=encodePacked(p),
                    sinceLastSpeedGained=run.lastSpeedGainTime and round(t-run.lastSpeedGainTime,6) or nil,
                    snapshot=snapshot(),
                }, t)
            else
                log("profile_delta_observed", {
                    remote=safePath(REMOTES.ProfileDelta),
                    speedPower=speedPower,
                    localTarget=localTarget,
                    target=encodeValue(target),
                }, t)
            end
            refreshInfo()
        end))
    end

    local leader = findLeaderSpeed()
    if leader then
        addConnection(leader:GetPropertyChangedSignal("Value"):Connect(function()
            local t = elapsed()
            mark("firstLeaderChange", t)
            log("leader_speed_changed", {
                value=leader.Value,
                sinceLastSpeedGained=run.lastSpeedGainTime and round(t-run.lastSpeedGainTime,6) or nil,
                snapshot=snapshot(),
            }, t)
            refreshInfo()
        end))
    end

    local _, _, hum = charBits()
    if hum then
        addConnection(hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            local t = elapsed()
            mark("firstWalkSpeedChange", t)
            log("walkspeed_changed", {
                walkSpeed=hum.WalkSpeed,
                sinceLastSpeedGained=run.lastSpeedGainTime and round(t-run.lastSpeedGainTime,6) or nil,
                snapshot=snapshot(),
            }, t)
            refreshInfo()
        end))
    end
end

--==============================================================--
-- ARCHIVE / UPLOAD
--==============================================================--

local function responseCode(r)
    if type(r) ~= "table" then return nil end
    return tonumber(r.StatusCode or r.Status or r.status_code or r.status)
end

local function responseBody(r)
    if type(r) ~= "table" then return nil end
    return r.Body or r.body or r.ResponseBody
end

local function tokenBody(body)
    if CONFIG.UPLOAD_TOKEN and tostring(CONFIG.UPLOAD_TOKEN) ~= "" then
        body.token = CONFIG.UPLOAD_TOKEN
    end
    return body
end

local function httpJson(method, url, bodyTable)
    if not requestFn then return false, "executor_sem_request" end
    local body = bodyTable and jsonEncode(bodyTable) or nil
    if bodyTable and not body then return false, "json_encode_failed" end

    local last = "unknown"
    for attempt = 1, CONFIG.RETRIES do
        local ok, res = pcall(requestFn, {
            Url=url,
            Method=method,
            Headers={["Content-Type"]="application/json",["Accept"]="application/json"},
            Body=body,
            Timeout=CONFIG.HTTP_TIMEOUT,
        })
        if ok and type(res) == "table" then
            local code, raw = responseCode(res), responseBody(res)
            if code and code >= 200 and code < 300 then
                return true, jsonDecode(raw) or {}, res
            end
            last = "HTTP "..tostring(code)..": "..tostring(raw)
        else
            last = tostring(res)
        end
        task.wait(CONFIG.RETRY_DELAY * attempt)
    end
    return false, last
end

local function ensureFolder()
    if not HAS_FS then return false end
    if HAS_FOLDER then
        local ok, exists = pcall(isfolder, CONFIG.SAVE_FOLDER)
        if not ok or not exists then pcall(makefolder, CONFIG.SAVE_FOLDER) end
    end
    return true
end

local function archiveObject()
    return {
        cafeinaTrace = {
            source=CONFIG.VERSION,
            generatedAt=unix(),
            placeId=game.PlaceId,
            gameId=game.GameId,
            placeVersion=game.PlaceVersion,
            clientVisibleOnly=true,
            passiveNormalSession=true,
            activeRemoteCallsByCollector=false,
            outboundHook=hookInstalled,
        },
        summary=run.summary,
        records=run.records,
    }
end

local function saveArchive()
    if not HAS_FS then return nil, "filesystem_indisponivel" end
    ensureFolder()
    local name = string.format("Cafeina_TreadmillLegitTrace_%s_%s.json", game.PlaceId, timestampName())
    local path = CONFIG.SAVE_FOLDER.."/"..name
    local encoded = jsonEncode(archiveObject())
    if not encoded then return nil, "json_encode_failed" end
    local ok, err = pcall(writefile, path, encoded)
    if not ok then return nil, tostring(err) end
    run.localArchivePath = path
    return path
end

local function chunksOf(records)
    local out, cur, bytes = {}, {}, 2
    for _, row in ipairs(records) do
        local enc = jsonEncode(row) or "{}"
        local b = #enc + 1
        if #cur > 0 and bytes + b > CONFIG.TARGET_CHUNK_BYTES then
            out[#out+1], cur, bytes = cur, {}, 2
        end
        cur[#cur+1] = row
        bytes += b
    end
    if #cur > 0 then out[#out+1] = cur end
    return out
end

local function uploadArchive()
    if run.uploading then return false, "upload_em_andamento" end
    if not requestFn then
        setStatus("Coleta salva, mas este executor não possui função HTTP request.")
        refreshInfo("upload indisponível")
        return false, "executor_sem_request"
    end
    if #run.records == 0 then return false, "sem_registros" end

    run.uploading = true
    setProgress(0.84)
    refreshInfo("iniciando upload")

    local chunks = chunksOf(run.records)
    local filename = string.format("Cafeina_TreadmillLegitTrace_%s_%s.json", game.PlaceId, timestampName())

    local meta = {
        scanner=CONFIG.VERSION,
        source=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        recordCount=#run.records,
        totalChunks=#chunks,
        targetChunkBytes=CONFIG.TARGET_CHUNK_BYTES,
        focus="treadmill_legitimate_session_sequence",
        clientVisibleOnly=true,
        passiveNormalSession=true,
        activeRemoteCallsByCollector=false,
        outboundHook=hookInstalled,
        summary=run.summary,
    }

    local okStart, startData = httpJson("POST", CONFIG.BASE_URL..CONFIG.START_PATH, tokenBody({
        filename=filename,
        source=CONFIG.VERSION,
        metadata=meta,
    }))

    if not okStart then
        run.uploading = false
        setStatus("Falha em /upload/start: "..tostring(startData))
        refreshInfo("falhou")
        return false, startData
    end

    local uploadId = startData.uploadId or startData.id or startData.upload_id
    if not uploadId then
        run.uploading = false
        setStatus("/upload/start não retornou uploadId.")
        return false, "uploadId_ausente"
    end

    for i, chunk in ipairs(chunks) do
        setStatus(string.format("Enviando dados %d/%d...", i, #chunks))
        setProgress(0.84 + 0.12*((i-1)/math.max(#chunks,1)))
        refreshInfo(string.format("chunk %d/%d", i, #chunks))

        local okChunk, chunkData = httpJson("POST", CONFIG.BASE_URL..CONFIG.CHUNK_PATH, tokenBody({
            uploadId=uploadId,
            index=i,
            objects=chunk,
        }))

        if not okChunk then
            pcall(function()
                httpJson("POST", CONFIG.BASE_URL..CONFIG.CANCEL_PATH, tokenBody({uploadId=uploadId}))
            end)
            run.uploading = false
            setStatus("Falha no chunk "..i..": "..tostring(chunkData))
            refreshInfo("falhou")
            return false, chunkData
        end
    end

    setStatus("Finalizando upload...")
    setProgress(0.97)
    local okFinish, finishData = httpJson("POST", CONFIG.BASE_URL..CONFIG.FINISH_PATH, tokenBody({
        uploadId=uploadId,
        totalChunks=#chunks,
        summary=run.summary,
    }))

    if not okFinish then
        run.uploading = false
        setStatus("Chunks enviados, mas /upload/finish falhou: "..tostring(finishData))
        refreshInfo("finish falhou")
        return false, finishData
    end

    run.uploadUrl = finishData.url or finishData.downloadUrl or finishData.fileUrl or finishData.link
    run.uploading = false
    setProgress(1)
    setStatus("Coleta enviada e confirmada pelo servidor.")
    refreshInfo("concluído")

    if run.localArchivePath and HAS_DELETE then
        pcall(delfile, run.localArchivePath)
        run.localArchivePath = nil
    end

    return true, finishData
end

--==============================================================--
-- SUMMARY
--==============================================================--

local function delta(a,b)
    if type(a)=="number" and type(b)=="number" then return b-a end
end

local function eventDelay(a,b)
    if type(a)=="number" and type(b)=="number" then return round(b-a,6) end
end

local function buildSummary(reason)
    local _, _, hum = charBits()
    run.finalLeaderSpeed = leaderSpeedValue()
    run.finalWalkSpeed = hum and hum.WalkSpeed or nil

    local ordered = {}
    local function push(name,t)
        if type(t)=="number" then ordered[#ordered+1] = {name=name,t=round(t,6)} end
    end
    push("AskWearStill",run.firstAskWear)
    push("AssignedBeltShifted",run.firstAssigned)
    push("RenderStateTrue",run.firstRenderTrue)
    push("SpeedGained",run.firstSpeedGained)
    push("LocalProfileDelta",run.firstLocalProfileDelta)
    push("LeaderSpeedChanged",run.firstLeaderChange)
    push("WalkSpeedChanged",run.firstWalkSpeedChange)
    push("AskDoff",run.firstAskDoff)
    push("RenderStateFalse",run.firstRenderFalse)
    table.sort(ordered,function(a,b) return a.t < b.t end)

    local verdict
    if run.firstAskWear and run.firstSpeedGained and run.speedGainedTotal > 0 then
        verdict = "LEGIT_TREADMILL_GAIN_CAPTURED"
    elseif run.firstAskWear and not run.firstSpeedGained then
        verdict = "ASKWEAR_SEEN_NO_SPEEDGAIN_CAPTURED"
    elseif run.speedGainedTotal > 0 and not run.firstAskWear then
        verdict = hookInstalled and "SPEEDGAIN_WITHOUT_CAPTURED_ASKWEAR" or "SPEEDGAIN_CAPTURED_OUTBOUND_HOOK_UNAVAILABLE"
    else
        verdict = "NO_TRAINING_SEQUENCE_CAPTURED"
    end

    run.summary = {
        verdict=verdict,
        finishReason=reason,
        passiveNormalSession=true,
        activeRemoteCallsByCollector=false,
        outboundHook=hookInstalled,
        askWearReturn=run.askWearReturn,

        firstEvents={
            AskWearStill=run.firstAskWear,
            AssignedBeltShifted=run.firstAssigned,
            RenderStateTrue=run.firstRenderTrue,
            SpeedGained=run.firstSpeedGained,
            LocalProfileDelta=run.firstLocalProfileDelta,
            LeaderSpeedChanged=run.firstLeaderChange,
            WalkSpeedChanged=run.firstWalkSpeedChange,
            AskDoff=run.firstAskDoff,
            RenderStateFalse=run.firstRenderFalse,
        },
        orderedFirstEvents=ordered,

        delays={
            AskWear_to_Assigned=eventDelay(run.firstAskWear,run.firstAssigned),
            AskWear_to_RenderTrue=eventDelay(run.firstAskWear,run.firstRenderTrue),
            AskWear_to_FirstSpeedGained=eventDelay(run.firstAskWear,run.firstSpeedGained),
            FirstSpeedGained_to_LocalProfileDelta=eventDelay(run.firstSpeedGained,run.firstLocalProfileDelta),
            FirstSpeedGained_to_LeaderChange=eventDelay(run.firstSpeedGained,run.firstLeaderChange),
            FirstSpeedGained_to_WalkSpeedChange=eventDelay(run.firstSpeedGained,run.firstWalkSpeedChange),
            AskDoff_to_RenderFalse=eventDelay(run.firstAskDoff,run.firstRenderFalse),
        },

        speedGainedCount=run.speedGainedCount,
        speedGainedTotal=run.speedGainedTotal,
        localProfileDeltaCount=run.localProfileCount,
        localSpeedPowerInitial=run.localSpeedPowerInitial,
        localSpeedPowerFinal=run.localSpeedPowerFinal,
        localSpeedPowerObservedDelta=delta(run.localSpeedPowerInitial,run.localSpeedPowerFinal),

        initialLeaderSpeed=run.initialLeaderSpeed,
        finalLeaderSpeed=run.finalLeaderSpeed,
        leaderSpeedDelta=delta(run.initialLeaderSpeed,run.finalLeaderSpeed),

        initialWalkSpeed=run.initialWalkSpeed,
        finalWalkSpeed=run.finalWalkSpeed,
        walkSpeedDelta=delta(run.initialWalkSpeed,run.finalWalkSpeed),

        minTreadmillDistance=run.minTreadmillDistance ~= math.huge and run.minTreadmillDistance or nil,
        totalDuration=round(elapsed(),6),
        records=#run.records,
    }

    log("trace_summary", run.summary)
    return verdict
end

--==============================================================--
-- RUN LOGIC
--==============================================================--

local function resetRun()
    clearConnections()
    run.active=false
    run.uploading=false
    run.stopRequested=false
    run.phase="idle"
    run.startedClock=mono()
    run.startedUnix=unix()
    run.seq=0
    run.records={}
    run.localArchivePath=nil
    run.uploadUrl=nil

    run.firstAskWear=nil
    run.askWearReturn=nil
    run.firstAssigned=nil
    run.firstRenderTrue=nil
    run.firstSpeedGained=nil
    run.firstLocalProfileDelta=nil
    run.firstLeaderChange=nil
    run.firstWalkSpeedChange=nil
    run.firstAskDoff=nil
    run.firstRenderFalse=nil

    run.speedGainedCount=0
    run.speedGainedTotal=0
    run.localProfileCount=0
    run.localSpeedPowerInitial=nil
    run.localSpeedPowerFinal=nil

    run.initialLeaderSpeed=nil
    run.finalLeaderSpeed=nil
    run.initialWalkSpeed=nil
    run.finalWalkSpeed=nil

    run.lastSpeedGainAmount=nil
    run.lastSpeedGainTime=nil
    run.minTreadmillDistance=math.huge
    run.summary=nil

    setProgress(0)
    refreshInfo()
end

local function finishAndUpload(reason)
    if not run.active then return end
    run.phase = "finalizing"
    log("collection_stopping",{reason=reason,snapshot=snapshot()})

    local verdict = buildSummary(reason)
    run.active = false
    clearConnections()

    setProgress(0.80)
    setStatus("Coleta encerrada: "..verdict..". Salvando...")
    refreshInfo("salvando")

    local path, err = saveArchive()
    if not path and err then
        log("local_save_error",{error=err})
    end

    setProgress(0.83)
    setStatus("Coleta pronta. Enviando ao site...")
    uploadArchive()

    Start.Text = "NOVA COLETA"
    Stop.Text = "REENVIAR"
end

local function runCollection()
    if run.active or run.uploading then return end
    if game.PlaceId ~= CONFIG.PLACE_ID then
        setStatus("PlaceId diferente do jogo esperado. Coleta cancelada.")
        return
    end

    refreshTreadmills()
    resetRun()

    run.active = true
    run.startedClock = mono()
    run.startedUnix = unix()

    local _, _, hum = charBits()
    run.initialLeaderSpeed = leaderSpeedValue()
    run.initialWalkSpeed = hum and hum.WalkSpeed or nil

    installHook()
    connectObservers()

    run.phase = "baseline"
    log("trace_started",{
        scanner=CONFIG.VERSION,
        passiveNormalSession=true,
        activeRemoteCallsByCollector=false,
        capabilities={
            request=requestFn~=nil,
            filesystem=HAS_FS,
            hookmetamethod=HAS_HOOK,
            hookInstalled=hookInstalled,
            checkcaller=HAS_CHECKCALLER,
        },
        remotes={
            AskWearStill=safePath(REMOTES.AskWearStill),
            AskDoff=safePath(REMOTES.AskDoff),
            AssignedBeltShifted=safePath(REMOTES.AssignedBeltShifted),
            SpeedGained=safePath(REMOTES.SpeedGained),
            RenderStateShifted=safePath(REMOTES.RenderStateShifted),
            ProfileDelta=safePath(REMOTES.ProfileDelta),
        },
        snapshot=snapshot(),
    })

    Start.Text = "COLETANDO..."
    Stop.Text = "ENCERRAR + ENVIAR"
    setStatus("Baseline por 2s. NÃO suba na esteira ainda.")
    setProgress(0.03)

    local baselineEnd = mono() + CONFIG.BASELINE_SECONDS
    while run.active and mono() < baselineEnd do
        local s = snapshot()
        local d = s.treadmill and s.treadmill.distance
        if type(d)=="number" then run.minTreadmillDistance=math.min(run.minTreadmillDistance,d) end
        log("sample",{snapshot=s})
        refreshInfo()
        task.wait(CONFIG.SAMPLE_INTERVAL)
    end

    if not run.active then return end

    run.phase = "waiting_entry"
    setStatus("AGORA suba normalmente na esteira, corra alguns segundos e depois saia. O coletor não chama nenhum remote.")
    setProgress(0.15)

    local startedWait = mono()
    local doffSeenAt = nil

    while run.active and not run.stopRequested do
        local s = snapshot()
        local d = s.treadmill and s.treadmill.distance
        if type(d)=="number" then run.minTreadmillDistance=math.min(run.minTreadmillDistance,d) end
        log("sample",{snapshot=s})
        refreshInfo()

        if run.firstAskWear and not run.firstSpeedGained then
            setStatus("Entrada detectada. Aguardando confirmação de treino / SpeedGained...")
            setProgress(0.30)
        elseif run.firstSpeedGained and not run.firstAskDoff then
            setStatus(string.format("Treinando: %d eventos • +%s Speed. Corra alguns segundos e saia normalmente.",
                run.speedGainedCount,tostring(run.speedGainedTotal)))
            setProgress(0.50)
        end

        if run.firstAskDoff and not doffSeenAt then
            doffSeenAt = mono()
            setStatus("Saída detectada. Gravando o estado pós-esteira...")
            setProgress(0.68)
        end

        if doffSeenAt and mono()-doffSeenAt >= CONFIG.POST_DOFF_SECONDS then
            finishAndUpload("askdoff_detected_postwindow_complete")
            return
        end

        if mono()-startedWait >= CONFIG.MAX_SESSION_SECONDS then
            finishAndUpload("max_session_timeout")
            return
        end

        task.wait(CONFIG.SAMPLE_INTERVAL)
    end

    if run.active then
        finishAndUpload("manual_stop")
    end
end

Start.MouseButton1Click:Connect(function()
    if not run.active and not run.uploading then
        task.spawn(runCollection)
    end
end)

Stop.MouseButton1Click:Connect(function()
    if run.active then
        run.stopRequested = true
        setStatus("Encerrando coleta e preparando envio...")
    elseif not run.uploading and #run.records > 0 then
        task.spawn(uploadArchive)
    end
end)

task.spawn(function()
    refreshTreadmills()
    local missing = {}
    for _, key in ipairs({"AskWearStill","AskDoff","AssignedBeltShifted","SpeedGained","RenderStateShifted","ProfileDelta"}) do
        if not REMOTES[key] then missing[#missing+1]=key end
    end

    if #missing > 0 then
        setStatus("Pronto, mas não encontrei: "..table.concat(missing,", "))
    elseif not HAS_HOOK then
        setStatus("Pronto. Sem hookmetamethod: ainda coleta eventos recebidos, SpeedPower e WalkSpeed, mas pode não capturar AskWearStill/AskDoff enviados.")
    elseif not requestFn then
        setStatus("Pronto. Aviso: executor sem HTTP request; a coleta será salva localmente.")
    else
        setStatus("Pronto. Toque INICIAR ainda fora da esteira; após o baseline, suba, corra e saia normalmente.")
    end
end)
