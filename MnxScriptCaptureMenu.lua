--==============================================================--
-- CAFEINA • UNIVERSAL SCRIPT CAPTURE V2
-- executor/mobile • pass-through • auto Render/GitHub
--
-- Mantem o pipeline ja validado do projeto:
--   POST /api/inventory-trace -> Render -> mirror GitHub
--
-- Captura fontes que passam por loadstring e, quando suportado,
-- respostas HttpGet que parecem codigo Lua. O codigo original segue
-- normalmente para execucao; a captura acontece em paralelo.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local ORIGINAL_LOADSTRING = loadstring

local C = {
    V = "CAFEINA_UNIVERSAL_CAPTURE_V2",
    POST = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",
    SOURCE_CHUNK = 80000,
    BATCH_CHUNKS = 18,
    RETRIES = 3,
    LOCAL_DIR = "CafeinaCaptures",
}

local function firstfn(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synReq, httpReq, fluxReq
pcall(function() if syn and type(syn.request) == "function" then synReq = syn.request end end)
pcall(function() if http and type(http.request) == "function" then httpReq = http.request end end)
pcall(function() if fluxus and type(fluxus.request) == "function" then fluxReq = fluxus.request end end)

local REQUEST = firstfn(
    rawget(ENV, "request"),
    rawget(ENV, "http_request"),
    httpReq,
    synReq,
    fluxReq
)

local WRITE = firstfn(rawget(ENV, "writefile"), writefile)
local MAKEFOLDER = firstfn(rawget(ENV, "makefolder"), makefolder)
local ISFOLDER = firstfn(rawget(ENV, "isfolder"), isfolder)

pcall(function()
    local old = rawget(ENV, "__CAFEINA_UNIVERSAL_CAPTURE")
    if old and type(old.Stop) == "function" then old.Stop() end
end)

local S = {
    enabled = true,
    hookMode = "none",
    httpHook = false,
    captures = 0,
    duplicates = 0,
    uploaded = 0,
    failed = 0,
    queue = {},
    worker = false,
    seen = {},
    items = {},
    render = false,
    github = false,
    last = "Inicializando...",
}

--==============================================================--
-- UI DE STATUS: sempre visivel, mesmo se o console do executor
-- estiver fechado.
--==============================================================--

pcall(function()
    local oldGui = rawget(ENV, "__CAFEINA_MNX_CAPTURE_GUI")
    if oldGui then oldGui:Destroy() end
end)
pcall(function()
    local oldGui = rawget(ENV, "__CAFEINA_UNIVERSAL_CAPTURE_GUI")
    if oldGui then oldGui:Destroy() end
end)

local parent = CoreGui
pcall(function() if gethui then parent = gethui() end end)

local gui = Instance.new("ScreenGui")
gui.Name = "CafeinaUniversalCaptureV2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = parent
ENV.__CAFEINA_MNX_CAPTURE_GUI = gui
ENV.__CAFEINA_UNIVERSAL_CAPTURE_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(286, 104)
frame.Position = UDim2.fromOffset(10, 72)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 11)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 0, 26)
title.Position = UDim2.fromOffset(10, 5)
title.BackgroundTransparency = 1
title.Text = "CAFEINA • UNIVERSAL CAPTURE"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 11
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local stopButton = Instance.new("TextButton")
stopButton.Size = UDim2.fromOffset(54, 24)
stopButton.Position = UDim2.new(1, -62, 0, 6)
stopButton.BackgroundColor3 = Color3.fromRGB(100, 30, 35)
stopButton.BorderSizePixel = 0
stopButton.Text = "PARAR"
stopButton.TextColor3 = Color3.new(1, 1, 1)
stopButton.TextSize = 9
stopButton.Font = Enum.Font.GothamBold
stopButton.Parent = frame
Instance.new("UICorner", stopButton).CornerRadius = UDim.new(0, 7)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 38)
statusLabel.Position = UDim2.fromOffset(10, 34)
statusLabel.BackgroundTransparency = 1
statusLabel.TextWrapped = true
statusLabel.Text = "Inicializando..."
statusLabel.TextColor3 = Color3.fromRGB(225, 225, 230)
statusLabel.TextSize = 10
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = frame

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, -20, 0, 24)
countLabel.Position = UDim2.fromOffset(10, 75)
countLabel.BackgroundTransparency = 1
countLabel.Text = "capturas 0 • enviados 0 • falhas 0"
countLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
countLabel.TextSize = 9
countLabel.Font = Enum.Font.Code
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = frame

local function refreshCounts()
    pcall(function()
        countLabel.Text = string.format(
            "capturas %d • enviados %d • falhas %d • dup %d",
            S.captures, S.uploaded, S.failed, S.duplicates
        )
    end)
end

local function setStatus(text, toast)
    S.last = tostring(text)
    pcall(function() statusLabel.Text = S.last end)
    refreshCounts()
    print("[UNIVERSAL CAPTURE] " .. S.last)
    if toast then
        task.spawn(function()
            for _ = 1, 3 do
                local ok = pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "UNIVERSAL CAPTURE",
                        Text = S.last,
                        Duration = 5,
                    })
                end)
                if ok then break end
                task.wait(0.5)
            end
        end)
    end
end

--==============================================================--
-- HTTP / SERVIDOR
--==============================================================--

local function req(o)
    if not REQUEST then return false, nil, "request/http_request indisponivel" end
    local ok, r = pcall(REQUEST, o)
    if not ok or not r then return false, nil, tostring(r) end
    local code = tonumber(r.StatusCode or r.Status or r.status_code or r.status) or 0
    local body = tostring(r.Body or r.body or "")
    return code >= 200 and code < 300, {status = code, body = body}, nil
end

local function health()
    local ok, r, e = req({
        Url = C.HEALTH,
        Method = "GET",
        Headers = {Accept = "application/json", ["Cache-Control"] = "no-cache"},
    })
    if not ok then
        S.render = false
        S.github = false
        return false, e or (r and "HTTP " .. tostring(r.status)) or "health falhou"
    end
    local d
    pcall(function() d = HttpService:JSONDecode(r.body) end)
    S.render = type(d) == "table" and d.ok == true
    S.github = S.render and d.githubMirrorConfigured == true
    if not S.render then return false, "health invalido" end
    if not S.github then return false, "Render OK, mirror GitHub nao configurado" end
    return true
end

local function iso()
    local ok, v = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and v or os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--==============================================================--
-- CAPTURA / BACKUP
--==============================================================--

local function hashSource(src)
    local h = 5381
    for i = 1, #src do
        h = (h * 33 + string.byte(src, i)) % 4294967296
        if i % 250000 == 0 then task.wait() end
    end
    return string.format("%08x-%d", h, #src)
end

local function saveLocal(item)
    if not WRITE then return end
    if MAKEFOLDER then
        pcall(function()
            if not ISFOLDER or not ISFOLDER(C.LOCAL_DIR) then MAKEFOLDER(C.LOCAL_DIR) end
        end)
    end
    local file = string.format(
        "%s/Capture_%04d_%s.lua",
        C.LOCAL_DIR,
        item.index,
        item.hash:sub(1, 8)
    )
    pcall(WRITE, file, item.source)
end

local function looksLikeLua(src, url)
    if type(src) ~= "string" or #src < 20 then return false end
    local u = string.lower(tostring(url or ""))
    if u:find("%.lua", 1, false) or u:find("raw%.githubusercontent%.com", 1, false) then
        return true
    end
    local markers = {
        "loadstring", "function", "local ", "game:GetService",
        "FireServer", "InvokeServer", "CreateWindow", "getgenv",
    }
    local n = 0
    for _, marker in ipairs(markers) do
        if string.find(src, marker, 1, true) then
            n = n + 1
            if n >= 2 then return true end
        end
    end
    return false
end

--==============================================================--
-- ENVIO EM LOTES. Cada lote preserva index/total globais para
-- reconstruir exatamente a fonte, inclusive scripts grandes.
--==============================================================--

local function sendBatch(item, records, batchIndex, batchTotal, totalChunks)
    local rid = string.format(
        "SCRIPT_CAPTURE_%d_%s_B%d_%d",
        item.index,
        item.hash:sub(1, 8),
        batchIndex,
        os.time()
    )

    local payload = {
        schemaVersion = 1,
        userId = tostring(LP.UserId),
        username = tostring(LP.Name),
        capturedAt = iso(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        runId = rid,
        trace = {
            version = C.V,
            runId = rid,
            captureId = item.captureId,
            stage = "universal_pass_through",
            origin = item.origin,
            detail = item.detail,
            sourceChars = #item.source,
            sourceHash = item.hash,
            sourceIndex = item.index,
            chunkCount = totalChunks,
            batchIndex = batchIndex,
            batchTotal = batchTotal,
            remotes = {},
            records = records,
        },
    }

    local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then return false, "JSONEncode falhou" end

    local last = "falha HTTP"
    for attempt = 1, C.RETRIES do
        local yes, r, e = req({
            Url = C.POST,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                Accept = "application/json",
                ["User-Agent"] = "Cafeina-Universal-Capture/2.0",
            },
            Body = encoded,
        })

        if yes and r then
            local d
            pcall(function() d = HttpService:JSONDecode(r.body) end)
            if type(d) == "table" and d.ok == true then
                if type(d.github) == "table" and d.github.mirrored == true then
                    return true
                end
                last = "Render recebeu, GitHub nao confirmou mirror"
            else
                last = "resposta do Render sem confirmacao"
            end
        else
            last = e or (r and "HTTP " .. tostring(r.status)) or last
        end

        if attempt < C.RETRIES then task.wait(1.25 * attempt) end
    end

    return false, last
end

local function uploadItem(item)
    local totalChunks = math.max(1, math.ceil(#item.source / C.SOURCE_CHUNK))
    local batchTotal = math.max(1, math.ceil(totalChunks / C.BATCH_CHUNKS))

    for batchIndex = 1, batchTotal do
        if not S.enabled then return false, "captura parada" end

        local firstChunk = (batchIndex - 1) * C.BATCH_CHUNKS + 1
        local lastChunk = math.min(totalChunks, batchIndex * C.BATCH_CHUNKS)
        local records = {}

        for chunkIndex = firstChunk, lastChunk do
            local a = (chunkIndex - 1) * C.SOURCE_CHUNK + 1
            local b = math.min(#item.source, chunkIndex * C.SOURCE_CHUNK)
            records[#records + 1] = {
                kind = "script_source_chunk",
                stage = "universal_pass_through",
                origin = item.origin,
                index = chunkIndex,
                total = totalChunks,
                data = item.source:sub(a, b),
            }
        end

        setStatus(string.format(
            "Enviando captura #%d • lote %d/%d...",
            item.index, batchIndex, batchTotal
        ))

        local ok, err = sendBatch(item, records, batchIndex, batchTotal, totalChunks)
        if not ok then return false, err end
    end

    return true
end

local function startWorker()
    if S.worker then return end
    S.worker = true
    task.spawn(function()
        while S.enabled and #S.queue > 0 do
            local item = table.remove(S.queue, 1)
            local ok, err = uploadItem(item)
            if ok then
                S.uploaded = S.uploaded + 1
                setStatus(string.format(
                    "CAPTURA #%d NO GITHUB ✓ • %d bytes",
                    item.index, #item.source
                ), true)
            else
                S.failed = S.failed + 1
                setStatus(string.format(
                    "CAPTURA #%d PRESERVADA • envio falhou: %s",
                    item.index, tostring(err)
                ), true)
            end
            refreshCounts()
        end
        S.worker = false
    end)
end

local function processSource(src, origin, detail)
    if not S.enabled or type(src) ~= "string" or src == "" then return end

    local hash = hashSource(src)
    if S.seen[hash] then
        S.duplicates = S.duplicates + 1
        refreshCounts()
        return
    end
    S.seen[hash] = true

    S.captures = S.captures + 1
    local index = S.captures
    local item = {
        index = index,
        source = src,
        hash = hash,
        origin = tostring(origin or "unknown"),
        detail = tostring(detail or ""):sub(1, 500),
        captureId = string.format(
            "CAP_%s_%d_%d_%d",
            tostring(game.PlaceId),
            LP.UserId,
            os.time(),
            index
        ),
    }

    S.items[#S.items + 1] = item
    saveLocal(item)
    S.queue[#S.queue + 1] = item

    setStatus(string.format(
        "CAPTURADO #%d • %d bytes • %s",
        index, #src, item.origin
    ), true)

    startWorker()
end

local function observe(src, origin, detail)
    if not S.enabled or type(src) ~= "string" then return end
    task.defer(processSource, src, origin, detail)
end

--==============================================================--
-- HOOK 1: loadstring. Pass-through: captura e chama o compilador
-- original sem alterar a fonte.
--==============================================================--

local loadHookInstalled = false

if type(ORIGINAL_LOADSTRING) == "function" and type(hookfunction) == "function" then
    local oldLoadstring
    local wrapper = function(src, chunkName)
        observe(src, "loadstring", chunkName)
        return oldLoadstring(src, chunkName)
    end

    if type(newcclosure) == "function" then
        local ok, wrapped = pcall(newcclosure, wrapper)
        if ok and type(wrapped) == "function" then wrapper = wrapped end
    end

    local ok, old = pcall(function()
        return hookfunction(ORIGINAL_LOADSTRING, wrapper)
    end)

    if ok and type(old) == "function" then
        oldLoadstring = old
        loadHookInstalled = true
        S.hookMode = "hookfunction"
    end
end

if not loadHookInstalled and type(ORIGINAL_LOADSTRING) == "function" then
    local replacement = function(src, chunkName)
        observe(src, "loadstring", chunkName)
        return ORIGINAL_LOADSTRING(src, chunkName)
    end

    local ok = pcall(function()
        ENV.loadstring = replacement
        _G.loadstring = replacement
    end)

    if ok and ENV.loadstring == replacement then
        loadHookInstalled = true
        S.hookMode = "environment"
    end
end

--==============================================================--
-- HOOK 2: HttpGet/HttpGetAsync, quando o executor suporta.
-- Isso pega loaders que baixam Lua antes de um segundo estagio.
-- A resposta original e devolvida intacta.
--==============================================================--

if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    local hook = function(self, ...)
        local method = getnamecallmethod()
        if method == "HttpGet" or method == "HttpGetAsync" then
            local args = {...}
            local result = oldNamecall(self, ...)
            if type(result) == "string" and looksLikeLua(result, args[1]) then
                observe(result, "httpget", tostring(args[1] or ""))
            end
            return result
        end
        return oldNamecall(self, ...)
    end

    if type(newcclosure) == "function" then
        local ok, wrapped = pcall(newcclosure, hook)
        if ok and type(wrapped) == "function" then hook = wrapped end
    end

    local ok, old = pcall(function()
        return hookmetamethod(game, "__namecall", hook)
    end)

    if ok and type(old) == "function" then
        oldNamecall = old
        S.httpHook = true
    end
end

local function stop()
    S.enabled = false
    setStatus("PARADO • hooks ficam em pass-through sem coletar", true)
    stopButton.Text = "PARADO"
    stopButton.AutoButtonColor = false
end

stopButton.MouseButton1Click:Connect(function()
    if S.enabled then stop() end
end)

ENV.__CAFEINA_UNIVERSAL_CAPTURE = {
    State = S,
    Stop = stop,
    GetCaptures = function() return S.items end,
}

--==============================================================--
-- ARRANQUE / DIAGNOSTICO VISIVEL
--==============================================================--

if not loadHookInstalled and not S.httpHook then
    setStatus("ERRO • executor nao permitiu instalar nenhum hook", true)
else
    setStatus(string.format(
        "ARMADO ✓ • loadstring=%s • HttpGet=%s • verificando servidor...",
        S.hookMode,
        S.httpHook and "ON" or "OFF"
    ), true)

    task.spawn(function()
        local ok, err = health()
        if ok then
            setStatus(string.format(
                "ARMADO ✓ • SERVIDOR OK • GITHUB OK • %s / HttpGet %s",
                S.hookMode,
                S.httpHook and "ON" or "OFF"
            ), true)
        else
            setStatus("ARMADO LOCALMENTE • servidor: " .. tostring(err), true)
        end
    end)
end
