--==============================================================--
-- CAFEINA • INVENTORY REMOTE TRACE V4 SAFE-LITE
-- EXECUTOR / MOBILE • PASSIVE • LOW OVERHEAD
--
-- Objetivo:
-- • não varrer ReplicatedStorage inteiro;
-- • não conectar em centenas de OnClientEvent;
-- • não bloquear FireServer/InvokeServer;
-- • observar chamadas com amostragem leve;
-- • correlacionar Tool entrando/saindo da Backpack/Character;
-- • enviar em uma única POST para /api/inventory-trace;
-- • preservar backup local se o servidor estiver indisponível.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local CONFIG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V4_SAFE_LITE",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",

    MAX_RECORDS = 900,
    MAX_REMOTES = 180,
    BASE_SAMPLES_PER_REMOTE = 4,
    ACTION_SAMPLES_PER_REMOTE = 12,
    ACTION_SECONDS = 6,
    GLOBAL_EVENTS_PER_SECOND = 90,

    TERMS = {
        "item", "items", "inventory", "getitem", "get_item", "itemid",
        "item_amount", "withdraw", "take", "claim", "pickup", "collect",
        "storage", "backpack", "loot", "reward", "redeem", "search_option",
        "laser grid"
    }
}

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synRequest
pcall(function()
    if syn and type(syn.request) == "function" then synRequest = syn.request end
end)

local httpRequest
pcall(function()
    if http and type(http.request) == "function" then httpRequest = http.request end
end)

local fluxusRequest
pcall(function()
    if fluxus and type(fluxus.request) == "function" then fluxusRequest = fluxus.request end
end)

local REQUEST = pick(rawget(ENV, "request"), rawget(ENV, "http_request"), httpRequest, synRequest, fluxusRequest)
local WRITEFILE = pick(rawget(ENV, "writefile"), writefile)
local SETCLIPBOARD = pick(rawget(ENV, "setclipboard"), setclipboard)

pcall(function()
    local old = rawget(ENV, "__CAFEINA_INVTRACE_V4") or rawget(ENV, "__CAFEINA_INVTRACE_V3")
    if type(old) == "table" and type(old.StopLocal) == "function" then
        old.StopLocal()
    end
end)

pcall(function()
    local oldDispatch = rawget(ENV, "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V3")
    if type(oldDispatch) == "table" then oldDispatch.handler = nil end
end)

local State = {
    running = false,
    uploading = false,
    records = {},
    remotes = setmetatable({}, {__mode = "k"}),
    pathCache = setmetatable({}, {__mode = "k"}),
    connections = {},
    startedAt = nil,
    runId = nil,
    actionUntil = 0,
    status = "Verificando servidor...",
    serverOk = false,
    serverMirror = nil,
    lastPayload = nil,
    lastJson = nil,
    lastBackup = nil,
    rateSecond = -1,
    rateCount = 0,
}

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function cachedPath(obj)
    local cached = State.pathCache[obj]
    if cached then return cached end
    local ok, value = pcall(function() return obj:GetFullName() end)
    value = ok and value or tostring(obj)
    State.pathCache[obj] = value
    return value
end

local function isRemote(obj)
    if typeof(obj) ~= "Instance" then return false end
    local c = obj.ClassName
    return c == "RemoteEvent" or c == "RemoteFunction" or c == "UnreliableRemoteEvent"
end

local function containsTerm(text)
    text = lower(text)
    for _, term in ipairs(CONFIG.TERMS) do
        if string.find(text, term, 1, true) then return true, term end
    end
    return false
end

local function shallowValue(value, depth)
    depth = depth or 0
    if depth > 1 then return "<nested>" end

    local t = typeof(value)
    if value == nil then return nil end
    if t == "string" then
        if #value > 300 then return string.sub(value, 1, 300) .. "<truncated>" end
        return value
    end
    if t == "number" or t == "boolean" then
        if t == "number" and (value ~= value or value == math.huge or value == -math.huge) then return tostring(value) end
        return value
    end
    if t == "Instance" then
        return {type="Instance", class=value.ClassName, name=value.Name, path=cachedPath(value)}
    end
    if t == "Vector3" or t == "Vector2" or t == "CFrame" or t == "Color3" then
        return tostring(value)
    end
    if t == "table" then
        local out, count = {}, 0
        for k, v in pairs(value) do
            count += 1
            if count > 8 then
                out["<truncated>"] = true
                break
            end
            out[tostring(k)] = shallowValue(v, depth + 1)
        end
        return out
    end
    return tostring(value)
end

local function shallowArgs(args)
    local out = {}
    local n = math.min(tonumber(args.n) or #args, 6)
    for i = 1, n do
        out[i] = shallowValue(args[i], 0)
    end
    return out
end

local function argsText(args)
    local pieces = {}
    local n = math.min(tonumber(args.n) or #args, 6)
    for i = 1, n do
        local v = args[i]
        local t = typeof(v)
        if t == "string" or t == "number" or t == "boolean" then
            pieces[#pieces + 1] = tostring(v)
        elseif t == "Instance" then
            pieces[#pieces + 1] = v.Name
        end
    end
    return table.concat(pieces, " ")
end

local function addRecord(record)
    if not State.running then return end
    if #State.records >= CONFIG.MAX_RECORDS then
        State.status = "Limite atingido • PARAR + ENVIAR"
        return
    end
    record.seq = #State.records + 1
    record.clock = os.clock()
    record.unix = os.time()
    State.records[#State.records + 1] = record
end

local function allowGlobalSample()
    local sec = math.floor(os.clock())
    if State.rateSecond ~= sec then
        State.rateSecond = sec
        State.rateCount = 0
    end
    if State.rateCount >= CONFIG.GLOBAL_EVENTS_PER_SECOND then return false end
    State.rateCount += 1
    return true
end

local function remoteCount()
    local n = 0
    for _ in pairs(State.remotes) do n += 1 end
    return n
end

local function getRemoteInfo(remote)
    local info = State.remotes[remote]
    if info then return info end
    if remoteCount() >= CONFIG.MAX_REMOTES then return nil end
    info = {
        path = cachedPath(remote),
        class = remote.ClassName,
        outgoing = 0,
        samples = 0,
        firstSeen = os.clock(),
        keyword = nil,
        actionWindow = false,
    }
    State.remotes[remote] = info
    return info
end

local function captureOutgoing(remote, method, args)
    if not State.running then return end
    if not allowGlobalSample() then return end

    local info = getRemoteInfo(remote)
    if not info then return end

    info.outgoing += 1

    local inAction = os.clock() <= State.actionUntil
    local pathHit, pathTerm = containsTerm(info.path)
    local argHit, argTerm = containsTerm(argsText(args))
    local relevant = inAction or pathHit or argHit

    local limit = inAction and CONFIG.ACTION_SAMPLES_PER_REMOTE or CONFIG.BASE_SAMPLES_PER_REMOTE
    if not relevant and info.samples >= 1 then return end
    if info.samples >= limit then return end

    info.samples += 1
    if pathHit then info.keyword = pathTerm end
    if argHit then info.keyword = argTerm end
    if inAction then info.actionWindow = true end

    addRecord({
        kind = "remote_outgoing",
        remote = info.path,
        class = info.class,
        method = method,
        relevant = relevant,
        reason = inAction and "action_window" or (pathHit and ("path:" .. tostring(pathTerm)) or (argHit and ("arg:" .. tostring(argTerm)) or "first_seen")),
        arguments = relevant and shallowArgs(args) or nil,
    })
end

local function disconnectAll()
    for _, conn in ipairs(State.connections) do
        pcall(function() conn:Disconnect() end)
    end
    State.connections = {}
end

local function watchTools()
    disconnectAll()

    local function watchContainer(container, label)
        if not container then return end
        State.connections[#State.connections + 1] = container.ChildAdded:Connect(function(child)
            if State.running and child:IsA("Tool") then
                addRecord({kind="tool_added", container=label, tool=child.Name})
            end
        end)
        State.connections[#State.connections + 1] = container.ChildRemoved:Connect(function(child)
            if State.running and child:IsA("Tool") then
                addRecord({kind="tool_removed", container=label, tool=child.Name})
            end
        end)
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")

    State.connections[#State.connections + 1] = LP.CharacterAdded:Connect(function(character)
        if not State.running then return end
        watchContainer(character, "Character")
    end)
end

local DISPATCH_KEY = "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V3"
local Dispatch = rawget(ENV, DISPATCH_KEY)
if type(Dispatch) ~= "table" and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    Dispatch = {handler=nil}
    local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        local handler = Dispatch.handler
        if handler and (method == "FireServer" or method == "InvokeServer") and isRemote(self) then
            pcall(handler, self, method, table.pack(...))
        end
        return oldNamecall(self, ...)
    end))
    ENV[DISPATCH_KEY] = Dispatch
end

local function enableCapture()
    if type(Dispatch) ~= "table" then
        State.status = "Executor sem hookmetamethod/getnamecallmethod"
        return false
    end
    Dispatch.handler = captureOutgoing
    return true
end

local function disableCapture()
    if type(Dispatch) == "table" then Dispatch.handler = nil end
end

local function isoNow()
    local ok, value = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and value or os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function buildReport()
    local remotes = {}
    for _, info in pairs(State.remotes) do
        remotes[#remotes + 1] = {
            path = info.path,
            class = info.class,
            outgoing = info.outgoing,
            samples = info.samples,
            keyword = info.keyword,
            actionWindow = info.actionWindow,
            firstSeen = info.firstSeen,
        }
    end
    table.sort(remotes, function(a, b) return a.path < b.path end)
    return {
        version = CONFIG.VERSION,
        runId = State.runId,
        startedAt = State.startedAt,
        finishedAt = os.time(),
        remotes = remotes,
        records = State.records,
    }
end

local function makePayload(report)
    return {
        schemaVersion = 1,
        userId = tostring(LP.UserId),
        username = tostring(LP.Name),
        capturedAt = isoNow(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = State.runId,
        trace = report,
    }
end

local function saveBackup(payload)
    local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then return nil, nil end
    local filename = "Cafeina_InventoryTrace_" .. tostring(game.PlaceId) .. "_" .. tostring(os.time()) .. ".json"
    if WRITEFILE then
        pcall(function() WRITEFILE(filename, json) end)
    end
    return filename, json
end

local function requestHttp(options)
    if not REQUEST then return false, nil, "request/http_request indisponivel" end
    local ok, response = pcall(function() return REQUEST(options) end)
    if not ok or not response then return false, nil, tostring(response) end
    local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
    local body = tostring(response.Body or response.body or "")
    return status >= 200 and status < 300, {status=status, body=body, raw=response}, nil
end

local function preflight()
    if not REQUEST then
        State.serverOk = false
        State.status = "Servidor: executor sem HTTP • coleta local funciona"
        return
    end

    local ok, response = requestHttp({
        Url = CONFIG.HEALTH,
        Method = "GET",
        Headers = { ["Accept"] = "application/json", ["Cache-Control"] = "no-cache" },
    })

    if not ok or not response then
        State.serverOk = false
        State.status = "Servidor indisponivel • backup local sera preservado"
        return
    end

    local decoded
    pcall(function() decoded = HttpService:JSONDecode(response.body) end)
    if type(decoded) == "table" and decoded.ok == true then
        State.serverOk = true
        State.serverMirror = decoded.githubMirrorConfigured == true
        State.status = State.serverMirror and "Servidor OK • GitHub mirror OK" or "Servidor OK • GitHub mirror nao configurado"
    else
        State.serverOk = false
        State.status = "Servidor respondeu, mas health invalido"
    end
end

local function sendPayload(payload, json)
    if not REQUEST then return false, "Seu executor nao possui request/http_request." end
    if not json then
        local ok
        ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
        if not ok then return false, "Falha ao gerar JSON." end
    end

    State.uploading = true
    local lastError

    for attempt = 1, 3 do
        State.status = "Enviando... " .. attempt .. "/3"
        local ok, response = requestHttp({
            Url = CONFIG.ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
                ["User-Agent"] = "Cafeina-InventoryTrace-Executor/4.0",
            },
            Body = json,
        })

        if ok and response then
            local decoded
            pcall(function() decoded = HttpService:JSONDecode(response.body) end)
            State.uploading = false
            return true, decoded or {status=response.status, body=response.body}
        end

        lastError = response and ("HTTP " .. tostring(response.status) .. " • " .. tostring(response.body)) or "Falha HTTP"
        task.wait(1.0 * attempt)
    end

    State.uploading = false
    return false, lastError or "Falha desconhecida"
end

local function startScan()
    if State.running or State.uploading then return end

    State.records = {}
    State.remotes = setmetatable({}, {__mode = "k"})
    State.pathCache = setmetatable({}, {__mode = "k"})
    State.startedAt = os.time()
    State.runId = HttpService:GenerateGUID(false)
    State.actionUntil = 0
    State.rateSecond = -1
    State.rateCount = 0
    State.lastPayload = nil
    State.lastJson = nil
    State.lastBackup = nil
    State.running = true

    watchTools()
    local captureOk = enableCapture()
    if captureOk then
        State.status = "SCAN ATIVO • jogue normalmente"
    end
end

local function markAction()
    if not State.running then
        State.status = "Inicie o scan primeiro"
        return
    end
    State.actionUntil = os.clock() + CONFIG.ACTION_SECONDS
    State.status = "ACAO MARCADA 6s • pegue/use o item agora"
    task.delay(CONFIG.ACTION_SECONDS, function()
        if State.running and os.clock() >= State.actionUntil then
            State.status = "SCAN ATIVO • jogue normalmente"
        end
    end)
end

local function stopLocal()
    State.running = false
    State.actionUntil = 0
    disableCapture()
    disconnectAll()
end

local function doSend(payload, backupName, json)
    State.lastPayload = payload
    State.lastJson = json
    State.lastBackup = backupName

    local ok, result = sendPayload(payload, json)
    if not ok then
        State.status = "ENVIO FALHOU • backup preservado • toque ENVIAR NOVAMENTE"
        warn("[CAFEINA TRACE]", result)
        warn("[CAFEINA TRACE] backup:", backupName)
        return
    end

    local traceId = type(result) == "table" and result.traceId or nil
    local latestUrl = type(result) == "table" and result.latestUrl or nil
    local github = type(result) == "table" and result.github or nil
    local mirrored = type(github) == "table" and github.mirrored == true
    local configured = type(github) == "table" and github.configured == true

    if mirrored then
        State.status = "ENVIADO + GITHUB ✓ • " .. tostring(traceId or "OK")
    elseif configured then
        State.status = "ENVIADO AO SERVIDOR • GITHUB FALHOU • pode reenviar"
    else
        State.status = "ENVIADO AO SERVIDOR • mirror GitHub nao configurado"
    end

    print("[CAFEINA TRACE] traceId:", traceId)
    print("[CAFEINA TRACE] backup:", backupName)

    if latestUrl then
        local full = "https://cafe-na-ia.onrender.com" .. latestUrl
        print("[CAFEINA TRACE] latest:", full)
        if SETCLIPBOARD then pcall(SETCLIPBOARD, full) end
    end

    if type(github) == "table" then
        print("[CAFEINA TRACE] github mirrored:", github.mirrored, github.path or github.error)
    end
end

local function stopAndSend()
    if State.uploading then return end

    if not State.running then
        if State.lastPayload and State.lastJson then
            task.spawn(doSend, State.lastPayload, State.lastBackup, State.lastJson)
        else
            State.status = "Nenhuma coleta pronta"
        end
        return
    end

    stopLocal()
    State.status = "Scan parado • gerando arquivo..."

    local report = buildReport()
    local payload = makePayload(report)
    local backupName, json = saveBackup(payload)
    State.lastPayload = payload
    State.lastJson = json
    State.lastBackup = backupName

    task.spawn(doSend, payload, backupName, json)
end

pcall(function()
    local oldGui = rawget(ENV, "__CAFEINA_INVTRACE_GUI")
    if oldGui then oldGui:Destroy() end
end)

local parent = CoreGui
pcall(function()
    if gethui then parent = gethui() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceV4"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = parent
ENV.__CAFEINA_INVTRACE_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(248, 194)
frame.Position = UDim2.fromOffset(8, 72)
frame.BackgroundColor3 = Color3.fromRGB(16,16,19)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-72,0,30)
title.Position = UDim2.fromOffset(10,5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • TRACE V4"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local minButton = Instance.new("TextButton")
minButton.Size = UDim2.fromOffset(52,26)
minButton.Position = UDim2.new(1,-60,0,6)
minButton.BackgroundColor3 = Color3.fromRGB(38,38,44)
minButton.Text = "MIN"
minButton.TextColor3 = Color3.new(1,1,1)
minButton.TextSize = 11
minButton.Font = Enum.Font.GothamBold
minButton.BorderSizePixel = 0
minButton.Parent = frame
Instance.new("UICorner", minButton).CornerRadius = UDim.new(0,7)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1,-20,0,46)
statusLabel.Position = UDim2.fromOffset(10,39)
statusLabel.BackgroundTransparency = 1
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(210,210,210)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = frame

local function makeButton(text, y, bg)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1,-20,0,31)
    b.Position = UDim2.fromOffset(10,y)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local startButton = makeButton("INICIAR SCAN", 90, Color3.fromRGB(35,80,45))
local actionButton = makeButton("MARCAR ACAO • 6s", 126, Color3.fromRGB(45,45,52))
local stopButton = makeButton("PARAR + ENVIAR", 162, Color3.fromRGB(115,28,28))

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(76,42)
mini.Position = UDim2.fromOffset(8,72)
mini.BackgroundColor3 = Color3.fromRGB(18,18,22)
mini.BorderSizePixel = 0
mini.Text = "TRACE"
mini.TextColor3 = Color3.new(1,1,1)
mini.TextSize = 11
mini.Font = Enum.Font.GothamBold
mini.Visible = false
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(0,10)

local function setMinimized(value)
    frame.Visible = not value
    mini.Visible = value
    if value then
        mini.Text = State.running and "TRACE ON" or "TRACE"
    end
end

minButton.MouseButton1Click:Connect(function() setMinimized(true) end)
mini.MouseButton1Click:Connect(function() setMinimized(false) end)

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
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            mini.Position = frame.Position
        end
    end)
end

startButton.MouseButton1Click:Connect(function()
    startScan()
    if State.running then
        task.delay(0.35, function()
            if State.running then setMinimized(true) end
        end)
    end
end)

actionButton.MouseButton1Click:Connect(function()
    markAction()
    if State.running then
        task.delay(0.25, function()
            if State.running then setMinimized(true) end
        end)
    end
end)

stopButton.MouseButton1Click:Connect(stopAndSend)

task.spawn(function()
    while gui.Parent do
        statusLabel.Text = State.status .. "\n" .. tostring(#State.records) .. " registros • " .. tostring(remoteCount()) .. " remotes"
        startButton.Text = State.running and "SCAN ATIVO" or "INICIAR SCAN"
        if State.uploading then
            stopButton.Text = "ENVIANDO..."
        elseif not State.running and State.lastPayload then
            stopButton.Text = "ENVIAR NOVAMENTE"
        else
            stopButton.Text = "PARAR + ENVIAR"
        end
        if mini.Visible then
            mini.Text = State.running and "TRACE ON" or (State.uploading and "UPLOAD" or "TRACE")
        end
        task.wait(0.6)
    end
end)

task.spawn(preflight)

ENV.__CAFEINA_INVTRACE_V4 = {
    Start = startScan,
    MarkAction = markAction,
    Finish = stopAndSend,
    StopLocal = stopLocal,
    Preflight = preflight,
    State = State,
}
