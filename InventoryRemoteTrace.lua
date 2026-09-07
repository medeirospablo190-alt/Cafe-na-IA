--==============================================================--
-- CAFEINA • INVENTORY REMOTE TRACE V2 LITE
-- MOBILE / EXECUTOR FRIENDLY
--
-- Ao executar: so abre o menu.
-- INICIAR SCAN: procura remotes de item/inventario em lotes pequenos.
-- PARAR + ENVIAR: para, salva backup e envia ao servidor CAFEINA.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local CONFIG = {
    VERSION = "CAFEINA_INVENTORY_REMOTE_TRACE_V2_LITE",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    BATCH_SIZE = 80,
    MAX_RECORDS = 2500,
    CHUNK_RECORDS = 120,
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
pcall(function()
    if syn and type(syn.request) == "function" then synRequest = syn.request end
end)

local httpRequest
pcall(function()
    if http and type(http.request) == "function" then httpRequest = http.request end
end)

local REQUEST = pick(rawget(ENV, "request"), rawget(ENV, "http_request"), httpRequest, synRequest)
local WRITEFILE = pick(rawget(ENV, "writefile"))
local SETCLIPBOARD = pick(rawget(ENV, "setclipboard"))

local State = {
    running = false,
    uploading = false,
    records = {},
    remotes = {},
    connections = {},
    startedAt = nil,
    runId = nil,
    status = "Pronto",
    gui = nil,
}

local function lower(v)
    return string.lower(tostring(v or ""))
end

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
        if #value > 3000 then return string.sub(value, 1, 3000) .. "<truncated>" end
        return value
    elseif t == "number" or t == "boolean" then
        return value
    elseif t == "Instance" then
        return {type="Instance", class=value.ClassName, name=value.Name, path=fullPath(value)}
    elseif t == "Vector3" or t == "Vector2" or t == "CFrame" then
        return tostring(value)
    elseif t == "table" then
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local out, n = {}, 0
        for k, v in pairs(value) do
            n += 1
            if n > 25 then out["<truncated>"] = true break end
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
        State.status = "Limite atingido • pare e envie"
        return
    end
    record.seq = #State.records + 1
    record.clock = os.clock()
    record.unix = os.time()
    State.records[#State.records + 1] = record
end

local function registerRemote(remote, reason)
    if not State.running or State.remotes[remote] then return end

    local path = fullPath(remote)
    State.remotes[remote] = {
        path = path,
        class = remote.ClassName,
        reason = reason,
        events = 0,
    }

    addRecord({
        kind = "remote_found",
        remote = path,
        class = remote.ClassName,
        reason = reason,
        attributes = safeSerialize(remote:GetAttributes()),
    })

    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        local ok, conn = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                if not State.running then return end
                local info = State.remotes[remote]
                if info then info.events += 1 end
                addRecord({
                    kind = "remote_incoming",
                    remote = path,
                    arguments = safeSerialize(table.pack(...)),
                })
            end)
        end)
        if ok and conn then State.connections[#State.connections + 1] = conn end
    end
end

local function disconnectAll()
    for _, conn in ipairs(State.connections) do
        pcall(function() conn:Disconnect() end)
    end
    State.connections = {}
end

local function scanInBatches()
    -- Executa somente depois do botao INICIAR SCAN.
    local objects = ReplicatedStorage:GetDescendants()
    local total = #objects

    for i = 1, total do
        if not State.running then break end

        local obj = objects[i]
        if isRemote(obj) then
            local ok, term = matches(fullPath(obj))
            if ok then registerRemote(obj, "name:" .. term) end
        end

        if i % CONFIG.BATCH_SIZE == 0 then
            State.status = "Escaneando " .. i .. "/" .. total
            RunService.Heartbeat:Wait()
        end
    end

    objects = nil
    collectgarbage("collect")

    if State.running then
        State.status = "SCAN ATIVO • faca os testes no jogo"
    end
end

local function postJson(url, payload)
    if not REQUEST then return false, nil, "request/http_request indisponivel" end

    local okEncode, body = pcall(function() return HttpService:JSONEncode(payload) end)
    if not okEncode then return false, nil, tostring(body) end

    local ok, response = pcall(function()
        return REQUEST({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
            Body = body,
        })
    end)

    if not ok then return false, nil, tostring(response) end

    local status = tonumber(response.StatusCode or response.Status or response.status) or 0
    local responseBody = response.Body or response.body or ""
    local decoded
    if responseBody ~= "" then
        pcall(function() decoded = HttpService:JSONDecode(responseBody) end)
    end

    if status < 200 or status >= 300 then
        return false, decoded, "HTTP " .. tostring(status) .. " • " .. tostring(responseBody)
    end
    return true, decoded, nil
end

local function buildReport()
    local remotes = {}
    for _, info in pairs(State.remotes) do
        remotes[#remotes + 1] = {
            path = info.path,
            class = info.class,
            reason = info.reason,
            events = info.events,
        }
    end
    table.sort(remotes, function(a,b) return a.path < b.path end)

    return {
        kind = "inventory_remote_trace",
        version = CONFIG.VERSION,
        runId = State.runId,
        placeId = game.PlaceId,
        gameId = game.GameId,
        startedAt = State.startedAt,
        finishedAt = os.time(),
        remotes = remotes,
        records = State.records,
    }
end

local function saveBackup(report)
    local ok, json = pcall(function() return HttpService:JSONEncode(report) end)
    if not ok then return nil, nil end

    local filename = "Cafeina_InventoryTrace_" .. tostring(game.PlaceId) .. "_" .. tostring(os.time()) .. ".json"
    if WRITEFILE then pcall(function() WRITEFILE(filename, json) end) end
    return filename, json
end

local function upload(report, json)
    if not REQUEST then return false, "request/http_request indisponivel" end
    State.uploading = true
    State.status = "Upload: iniciando..."

    local filename = "Cafeina_InventoryTrace_" .. tostring(game.PlaceId) .. "_" .. tostring(os.time()) .. ".json"
    local okStart, startData, startErr = postJson(CONFIG.UPLOAD_BASE .. "/start", {
        filename = filename,
        source = CONFIG.VERSION,
        metadata = {
            type = "inventory_remote_trace",
            runId = State.runId,
            placeId = game.PlaceId,
            gameId = game.GameId,
            records = #State.records,
        }
    })

    if not okStart then State.uploading = false return false, "start: " .. tostring(startErr) end
    local uploadId = type(startData) == "table" and (startData.uploadId or startData.id or startData.upload_id) or nil
    if not uploadId then State.uploading = false return false, "start sem uploadId" end

    local objects = {{
        kind = "inventory_remote_trace_header",
        version = report.version,
        runId = report.runId,
        placeId = report.placeId,
        gameId = report.gameId,
        startedAt = report.startedAt,
        finishedAt = report.finishedAt,
        remotes = report.remotes,
    }}
    for _, record in ipairs(report.records) do objects[#objects + 1] = record end

    local totalChunks = math.max(1, math.ceil(#objects / CONFIG.CHUNK_RECORDS))
    for chunkIndex = 1, totalChunks do
        local first = (chunkIndex - 1) * CONFIG.CHUNK_RECORDS + 1
        local last = math.min(#objects, first + CONFIG.CHUNK_RECORDS - 1)
        local chunk = {}
        for i = first, last do chunk[#chunk + 1] = objects[i] end

        State.status = "Upload " .. chunkIndex .. "/" .. totalChunks
        local okChunk, _, chunkErr = postJson(CONFIG.UPLOAD_BASE .. "/chunk", {
            uploadId = uploadId,
            index = chunkIndex,
            objects = chunk,
        })

        if not okChunk then
            pcall(function() postJson(CONFIG.UPLOAD_BASE .. "/cancel", {uploadId=uploadId}) end)
            State.uploading = false
            return false, "chunk " .. chunkIndex .. ": " .. tostring(chunkErr)
        end
    end

    State.status = "Confirmando upload..."
    local okFinish, finishData, finishErr = postJson(CONFIG.UPLOAD_BASE .. "/finish", {
        uploadId = uploadId,
        totalChunks = totalChunks,
        totalBytes = #(json or ""),
        records = #objects,
    })

    State.uploading = false
    if not okFinish then return false, "finish: " .. tostring(finishErr) end

    local link
    if type(finishData) == "table" then
        link = finishData.url or finishData.link or finishData.downloadUrl or finishData.publicUrl
    end
    return true, {uploadId=uploadId, link=link}
end

local function startScan()
    if State.running or State.uploading then return end

    disconnectAll()
    State.records = {}
    State.remotes = {}
    State.startedAt = os.time()
    State.runId = HttpService:GenerateGUID(false)
    State.running = true
    State.status = "Iniciando scan..."

    task.spawn(scanInBatches)
end

local function stopAndSend()
    if not State.running or State.uploading then return end

    -- Para e desconecta ANTES de montar JSON/upload.
    State.running = false
    disconnectAll()
    State.status = "Scan parado • preparando arquivo..."

    local report = buildReport()
    local backupName, json = saveBackup(report)

    task.spawn(function()
        local ok, result = upload(report, json)
        if ok then
            State.status = "ENVIADO ✓ • ID: " .. tostring(result.uploadId)
            print("[CAFEINA TRACE] uploadId:", result.uploadId)
            print("[CAFEINA TRACE] backup:", backupName)
            if result.link then
                print("[CAFEINA TRACE] link:", result.link)
                if SETCLIPBOARD then pcall(SETCLIPBOARD, result.link) end
            elseif SETCLIPBOARD then
                pcall(SETCLIPBOARD, tostring(result.uploadId))
            end
        else
            State.status = "FALHA NO ENVIO • backup preservado"
            warn("[CAFEINA TRACE]", result)
            warn("[CAFEINA TRACE] backup:", backupName)
        end
    end)
end

--==============================================================--
-- GUI
--==============================================================--

pcall(function()
    local old = ENV.__CAFEINA_INVTRACE_GUI
    if old then old:Destroy() end
end)

local parent = CoreGui
pcall(function() if gethui then parent = gethui() end end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaInventoryTraceLite"
gui.ResetOnSpawn = false
gui.Parent = parent
ENV.__CAFEINA_INVTRACE_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(285, 180)
frame.Position = UDim2.new(0.5, -142, 0.56, -90)
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
title.Text = "CAFEINA • INVENTORY TRACE LITE"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-18,0,46)
status.Position = UDim2.fromOffset(9,38)
status.BackgroundTransparency = 1
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(205,205,205)
status.TextSize = 12
status.Font = Enum.Font.Gotham
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local function makeButton(text,y,bg)
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

local startButton = makeButton("INICIAR SCAN", 91, Color3.fromRGB(38,65,43))
local stopButton = makeButton("PARAR + ENVIAR", 136, Color3.fromRGB(110,25,25))

startButton.MouseButton1Click:Connect(function()
    if State.running then
        State.status = "Scan ja esta ativo"
        return
    end
    startButton.Text = "SCAN ATIVO"
    startScan()
end)

stopButton.MouseButton1Click:Connect(function()
    if not State.running then
        if not State.uploading then State.status = "Nenhum scan ativo" end
        return
    end
    startButton.Text = "INICIAR SCAN"
    stopButton.Text = "ENVIANDO..."
    stopAndSend()

    task.spawn(function()
        while State.uploading do task.wait(0.25) end
        if gui.Parent then stopButton.Text = "PARAR + ENVIAR" end
    end)
end)

task.spawn(function()
    while gui.Parent do
        local remoteCount = 0
        for _ in pairs(State.remotes) do remoteCount += 1 end
        status.Text = tostring(State.status)
            .. "\nRegistros: " .. tostring(#State.records)
            .. " • Remotes: " .. tostring(remoteCount)
        task.wait(0.3)
    end
end)

ENV.__CAFEINA_INVTRACE_CONTROLLER = {
    Start = startScan,
    StopAndSend = stopAndSend,
    State = State,
}

print("[CAFEINA TRACE LITE] menu carregado • scan DESLIGADO")
