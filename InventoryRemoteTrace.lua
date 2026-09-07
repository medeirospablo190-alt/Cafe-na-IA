--==============================================================--
-- CAFEINA • INVENTORY REMOTE TRACE V3 LITE
-- EXECUTOR / MOBILE
--
-- Ao executar: apenas abre o menu.
-- INICIAR SCAN: faz busca leve por remotes de item/inventario.
-- CAPTURAR ACAO 4s: registra remotes usados na proxima acao legitima.
-- PARAR + ENVIAR: para tudo e envia em UMA requisicao.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local CONFIG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V3_LITE",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    MAX_RECORDS = 1500,
    MAX_REMOTES = 300,
    YIELD_EVERY = 40,
    CAPTURE_SECONDS = 4,
    TERMS = {
        "laser grid", "item", "items", "inventory", "getitem", "get_item",
        "itemid", "item_amount", "withdraw", "take", "claim", "pickup",
        "collect", "storage", "backpack", "loot", "reward", "redeem",
        "search_option"
    }
}

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synRequest
pcall(function() if syn and type(syn.request) == "function" then synRequest = syn.request end end)
local httpRequest
pcall(function() if http and type(http.request) == "function" then httpRequest = http.request end end)
local fluxusRequest
pcall(function() if fluxus and type(fluxus.request) == "function" then fluxusRequest = fluxus.request end end)

local REQUEST = pick(rawget(ENV, "request"), rawget(ENV, "http_request"), httpRequest, synRequest, fluxusRequest)
local WRITEFILE = pick(rawget(ENV, "writefile"), writefile)
local SETCLIPBOARD = pick(rawget(ENV, "setclipboard"), setclipboard)

local State = {
    running = false,
    uploading = false,
    records = {},
    remotes = {},
    connections = {},
    startedAt = nil,
    runId = nil,
    captureUntil = 0,
    status = "Pronto • toque em INICIAR SCAN",
    lastPayload = nil,
    lastBackup = nil,
}

local function lower(v) return string.lower(tostring(v or "")) end
local function fullPath(obj)
    local ok, result = pcall(function() return obj:GetFullName() end)
    return ok and result or tostring(obj)
end
local function isRemote(obj)
    return obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("UnreliableRemoteEvent")
end
local function matches(text)
    text = lower(text)
    for _, term in ipairs(CONFIG.TERMS) do
        if string.find(text, term, 1, true) then return true, term end
    end
    return false
end

local function safeSerialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 3 then return "<depth>" end
    local t = typeof(value)
    if value == nil then return nil end
    if t == "string" then
        if #value > 2000 then return string.sub(value, 1, 2000) .. "<truncated>" end
        return value
    elseif t == "number" or t == "boolean" then
        if t == "number" and (value ~= value or value == math.huge or value == -math.huge) then return tostring(value) end
        return value
    elseif t == "Instance" then
        return {type="Instance", class=value.ClassName, name=value.Name, path=fullPath(value)}
    elseif t == "Vector3" or t == "Vector2" or t == "CFrame" or t == "Color3" then
        return tostring(value)
    elseif t == "table" then
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local out, count = {}, 0
        for k, v in pairs(value) do
            count += 1
            if count > 30 then out["<truncated>"] = true break end
            out[tostring(k)] = safeSerialize(v, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end
    return tostring(value)
end

local function addRecord(record)
    if not State.running then return end
    if #State.records >= CONFIG.MAX_RECORDS then
        State.status = "Limite de registros atingido • PARAR + ENVIAR"
        return
    end
    record.seq = #State.records + 1
    record.clock = os.clock()
    record.unix = os.time()
    State.records[#State.records + 1] = record
end

local function disconnectAll()
    for _, conn in ipairs(State.connections) do pcall(function() conn:Disconnect() end) end
    State.connections = {}
end

local function remoteCount()
    local n = 0
    for _ in pairs(State.remotes) do n += 1 end
    return n
end

local function registerRemote(remote, reason)
    if not State.running or State.remotes[remote] then return end
    if remoteCount() >= CONFIG.MAX_REMOTES then return end

    local path = fullPath(remote)
    State.remotes[remote] = {path=path, class=remote.ClassName, reason=reason, incoming=0, outgoing=0}

    local attrs = {}
    pcall(function() attrs = safeSerialize(remote:GetAttributes()) or {} end)
    addRecord({kind="remote_found", remote=path, class=remote.ClassName, reason=reason, attributes=attrs})

    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        local ok, conn = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                if not State.running then return end
                local info = State.remotes[remote]
                if info then info.incoming += 1 end
                addRecord({kind="remote_incoming", remote=path, arguments=safeSerialize(table.pack(...))})
            end)
        end)
        if ok and conn then State.connections[#State.connections + 1] = conn end
    end
end

local function processOutgoing(remote, method, args, reason)
    if not State.running or not remote or not remote.Parent then return end
    if not State.remotes[remote] then registerRemote(remote, reason) end
    local info = State.remotes[remote]
    if info then info.outgoing += 1 end
    addRecord({
        kind = "remote_outgoing",
        remote = fullPath(remote),
        class = remote.ClassName,
        method = method,
        reason = reason,
        arguments = safeSerialize(args),
    })
end

-- Um unico dispatcher global impede empilhar hooks ao reexecutar o loader.
local DISPATCH_KEY = "__CAFEINA_INVTRACE_NAMECALL_DISPATCH_V3"
local Dispatch = rawget(ENV, DISPATCH_KEY)
if type(Dispatch) ~= "table" and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    Dispatch = {handler=nil}
    local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        local handler = Dispatch.handler
        if handler and (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and isRemote(self) then
            pcall(handler, self, method, table.pack(...))
        end
        return oldNamecall(self, ...)
    end))
    ENV[DISPATCH_KEY] = Dispatch
end

local function enableOutgoingCapture()
    if type(Dispatch) ~= "table" then return false end
    Dispatch.handler = function(remote, method, args)
        if not State.running then return end
        local known = State.remotes[remote] ~= nil
        local window = os.clock() <= State.captureUntil
        local nameHit, term = matches(remote.Name)
        if known or window or nameHit then
            local reason = known and "known_remote" or (window and "capture_window" or ("name:" .. tostring(term)))
            task.defer(processOutgoing, remote, method, args, reason)
        end
    end
    return true
end

local function disableOutgoingCapture()
    if type(Dispatch) == "table" then Dispatch.handler = nil end
end

local function scanLight()
    local stack = {ReplicatedStorage}
    local visited = 0

    while State.running and #stack > 0 do
        local current = stack[#stack]
        stack[#stack] = nil

        local children = {}
        pcall(function() children = current:GetChildren() end)
        for _, child in ipairs(children) do
            if not State.running then break end
            visited += 1

            if isRemote(child) then
                local ok, term = matches(fullPath(child))
                if ok then registerRemote(child, "name:" .. term) end
            end

            local hasChildren = false
            pcall(function() hasChildren = #child:GetChildren() > 0 end)
            if hasChildren then stack[#stack + 1] = child end

            if visited % CONFIG.YIELD_EVERY == 0 then
                State.status = "Escaneando... " .. visited .. " objetos • " .. remoteCount() .. " remotes"
                task.wait()
            end
        end
    end

    if State.running then
        State.status = "SCAN ATIVO • " .. remoteCount() .. " remotes • faca os testes"
    end
end

local function buildReport()
    local remotes = {}
    for _, info in pairs(State.remotes) do
        remotes[#remotes + 1] = {
            path=info.path, class=info.class, reason=info.reason,
            incoming=info.incoming, outgoing=info.outgoing,
        }
    end
    table.sort(remotes, function(a,b) return a.path < b.path end)
    return {
        version = CONFIG.VERSION,
        runId = State.runId,
        startedAt = State.startedAt,
        finishedAt = os.time(),
        remotes = remotes,
        records = State.records,
    }
end

local function isoNow()
    local ok, value = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and value or os.date("!%Y-%m-%dT%H:%M:%SZ")
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
    if WRITEFILE then pcall(function() WRITEFILE(filename, json) end) end
    return filename, json
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
    for attempt = 1, 4 do
        State.status = "Enviando... tentativa " .. attempt .. "/4"
        local ok, response = pcall(function()
            return REQUEST({
                Url = CONFIG.ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json",
                    ["User-Agent"] = "Cafeina-InventoryTrace-Executor/3.0",
                },
                Body = json,
            })
        end)

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0
            local body = tostring(response.Body or response.body or "")
            local decoded
            if body ~= "" then pcall(function() decoded = HttpService:JSONDecode(body) end) end

            if status >= 200 and status < 300 then
                State.uploading = false
                return true, decoded or {status=status, body=body}
            end

            lastError = "HTTP " .. tostring(status) .. " • " .. body
            if status == 404 then
                lastError = lastError .. " • rota /api/inventory-trace ainda nao esta ativa no Render"
            end
        else
            lastError = tostring(response)
        end

        task.wait(attempt * 1.25)
    end

    State.uploading = false
    return false, lastError or "Falha desconhecida"
end

local function startScan()
    if State.running or State.uploading then return end
    disconnectAll()
    disableOutgoingCapture()
    State.records = {}
    State.remotes = {}
    State.startedAt = os.time()
    State.runId = HttpService:GenerateGUID(false)
    State.captureUntil = 0
    State.lastPayload = nil
    State.lastBackup = nil
    State.running = true
    State.status = "SCAN INICIADO • busca leve..."
    enableOutgoingCapture()
    task.spawn(scanLight)
end

local function captureAction()
    if not State.running then
        State.status = "Inicie o scan primeiro."
        return
    end
    State.captureUntil = os.clock() + CONFIG.CAPTURE_SECONDS
    State.status = "CAPTURA 4s • faca a acao legitima AGORA"
    task.delay(CONFIG.CAPTURE_SECONDS, function()
        if State.running and os.clock() >= State.captureUntil then
            State.status = "SCAN ATIVO • captura da acao encerrada"
        end
    end)
end

local function doSend(payload, backupName, json)
    State.lastPayload = {payload=payload, json=json}
    State.lastBackup = backupName
    local ok, result = sendPayload(payload, json)
    if ok then
        local traceId = type(result) == "table" and result.traceId or nil
        local latestUrl = type(result) == "table" and result.latestUrl or nil
        local githubPath = type(result) == "table" and type(result.github) == "table" and result.github.path or nil
        State.status = "ENVIADO ✓ • TRACE: " .. tostring(traceId or "OK")
        print("[CAFEINA TRACE] traceId:", traceId)
        print("[CAFEINA TRACE] backup:", backupName)
        if latestUrl then
            local full = "https://cafe-na-ia.onrender.com" .. latestUrl
            print("[CAFEINA TRACE] latest:", full)
            if SETCLIPBOARD then pcall(SETCLIPBOARD, full) end
        end
        if githubPath then print("[CAFEINA TRACE] github:", githubPath) end
    else
        State.status = "FALHA NO ENVIO • toque PARAR + ENVIAR para tentar de novo"
        warn("[CAFEINA TRACE]", result)
        warn("[CAFEINA TRACE] backup preservado:", backupName)
    end
end

local function stopAndSend()
    if State.uploading then return end

    if not State.running then
        if State.lastPayload then
            task.spawn(doSend, State.lastPayload.payload, State.lastBackup, State.lastPayload.json)
        else
            State.status = "Nenhuma coleta pronta para enviar."
        end
        return
    end

    State.running = false
    disableOutgoingCapture()
    disconnectAll()
    State.status = "Scan parado • preparando JSON..."

    local report = buildReport()
    local payload = makePayload(report)
    local backupName, json = saveBackup(payload)
    State.lastPayload = {payload=payload, json=json}
    State.lastBackup = backupName
    task.spawn(doSend, payload, backupName, json)
end

--==============================================================--
-- GUI MOBILE
--==============================================================--
pcall(function()
    local old = rawget(ENV, "__CAFEINA_INVTRACE_GUI")
    if old then old:Destroy() end
end)

local parent = CoreGui
pcall(function() if gethui then parent = gethui() end end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceV3"
gui.ResetOnSpawn = false
gui.Parent = parent
ENV.__CAFEINA_INVTRACE_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(295, 226)
frame.Position = UDim2.new(0.5, -147, 0.55, -113)
frame.BackgroundColor3 = Color3.fromRGB(16,16,19)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-18,0,28)
title.Position = UDim2.fromOffset(9,6)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • INVENTORY TRACE V3"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1,-18,0,52)
statusLabel.Position = UDim2.fromOffset(9,38)
statusLabel.BackgroundTransparency = 1
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(205,205,205)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = frame

local function makeButton(text, y, bg)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1,-18,0,38)
    b.Position = UDim2.fromOffset(9,y)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.TextSize = 13
    b.Font = Enum.Font.GothamBold
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local startButton = makeButton("INICIAR SCAN", 94, Color3.fromRGB(35,80,45))
local captureButton = makeButton("CAPTURAR PROXIMA ACAO • 4s", 138, Color3.fromRGB(45,45,52))
local stopButton = makeButton("PARAR + ENVIAR", 182, Color3.fromRGB(115,28,28))

startButton.MouseButton1Click:Connect(startScan)
captureButton.MouseButton1Click:Connect(captureAction)
stopButton.MouseButton1Click:Connect(stopAndSend)

task.spawn(function()
    while gui.Parent do
        statusLabel.Text = State.status .. "\n" .. tostring(#State.records) .. " registros • " .. tostring(remoteCount()) .. " remotes"
        if State.running then
            startButton.Text = "SCAN ATIVO"
        else
            startButton.Text = "INICIAR SCAN"
        end
        if State.uploading then
            stopButton.Text = "ENVIANDO..."
        elseif not State.running and State.lastPayload then
            stopButton.Text = "ENVIAR NOVAMENTE"
        else
            stopButton.Text = "PARAR + ENVIAR"
        end
        task.wait(0.2)
    end
end)

ENV.__CAFEINA_INVTRACE_V3 = {
    Start = startScan,
    Capture = captureAction,
    Finish = stopAndSend,
    State = State,
}

print("[CAFEINA TRACE V3] menu carregado; scan NAO iniciado automaticamente.")
