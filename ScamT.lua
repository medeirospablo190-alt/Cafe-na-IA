--==============================================================--
-- CAFEÍNA • SCAN CONTÍNUO + UPLOAD • COMPAT
-- Menu mínimo para mobile
--
-- Fluxo:
--   SCAN -> coleta contínua -> estabiliza/atinge limite -> ENVIA AO SITE
--
-- Observa somente informações visíveis ao cliente.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    API_BASE = "https://cafe-na-ia.onrender.com",
    UPLOAD_TOKEN = "",

    -- Compatibilidade com o backend/menu atual: 250 MiB por sessão.
    -- Backend antigo aceita até ~6 MB por request; mantemos margem segura.
    MAX_TOTAL_BYTES = 250 * 1024 * 1024,
    CHUNK_TARGET_BYTES = 3500000,
    CHUNK_HARD_BYTES = 5500000,

    -- Scanner contínuo.
    PASS_INTERVAL = 2.0,
    STABLE_PASSES_REQUIRED = 3,
    YIELD_EVERY = 120,
    MAX_OBJECTS_PER_PASS = 1000000,

    -- Proteção para ambientes sem arquivo local.
    MEMORY_FALLBACK_LIMIT = 64 * 1024 * 1024,

    -- Upload.
    UPLOAD_RETRIES = 4,
    RETRY_DELAY = 1.25,
}

--==============================================================--
-- APIs DO EXECUTOR
--==============================================================--

local requestFn =
    (syn and syn.request)
    or http_request
    or request
    or (http and http.request)

local writefileFn = writefile
local readfileFn = readfile
local isfileFn = isfile
local delfileFn = delfile
local makefolderFn = makefolder
local isfolderFn = isfolder

local CAN_SPOOL_TO_DISK =
    type(writefileFn) == "function"
    and type(readfileFn) == "function"

--==============================================================--
-- ESTADO
--==============================================================--

local ScanRunning = false
local ScanComplete = false
local UploadRunning = false
local CancelGeneration = 0

local SeenSignatures = {}
local TotalRecordedBytes = 0
local TotalRecords = 0
local TotalPasses = 0
local StablePasses = 0

local CurrentChunk = {}
local CurrentChunkBytes = 2
local StoredChunks = {}
local MemoryChunks = {}
local SessionFolder = "CafeinaScan_" .. tostring(os.time())

--==============================================================--
-- HELPERS
--==============================================================--

local function readableSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    return tostring(bytes) .. " B"
end

local function safeString(value, maxLen)
    local text = tostring(value or "")
    maxLen = maxLen or 1000
    if #text > maxLen then
        return text:sub(1, maxLen)
    end
    return text
end

local function fullName(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    return ok and result or inst.Name
end

local function valueSnapshot(inst)
    if not inst:IsA("ValueBase") then
        return nil
    end

    local ok, value = pcall(function()
        return inst.Value
    end)

    if ok then
        return safeString(value, 1200)
    end
    return nil
end

local function attributesSnapshot(inst)
    local output = {}
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return output
    end

    local count = 0
    for key, value in pairs(attrs) do
        count += 1
        if count > 60 then
            break
        end
        output[safeString(key, 120)] = safeString(value, 600)
    end

    return output
end

local function compactProperties(inst)
    local p = {}

    if inst:IsA("BasePart") then
        p.anchored = inst.Anchored
        p.canCollide = inst.CanCollide
        p.canTouch = inst.CanTouch
        p.canQuery = inst.CanQuery
        p.transparency = inst.Transparency
        p.material = tostring(inst.Material)
        p.position = {x = inst.Position.X, y = inst.Position.Y, z = inst.Position.Z}
        p.size = {x = inst.Size.X, y = inst.Size.Y, z = inst.Size.Z}
    elseif inst:IsA("Tool") then
        p.requiresHandle = inst.RequiresHandle
        p.canBeDropped = inst.CanBeDropped
    elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        p.remoteType = inst.ClassName
    elseif inst:IsA("Player") then
        p.displayName = inst.DisplayName
        p.userId = inst.UserId
    elseif inst:IsA("GuiObject") then
        p.visible = inst.Visible
    end

    return p
end

local function snapshot(inst, passNumber)
    local parentPath = ""
    if inst.Parent then
        parentPath = fullName(inst.Parent)
    end

    local record = {
        path = fullName(inst),
        parentPath = parentPath,
        name = inst.Name,
        className = inst.ClassName,
        childCount = #inst:GetChildren(),
        attributes = attributesSnapshot(inst),
        properties = compactProperties(inst),
        value = valueSnapshot(inst),
        pass = passNumber,
        observedAt = os.time(),
    }

    return record
end

local function signatureFor(record)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            record.path,
            record.className,
            record.childCount,
            record.attributes,
            record.properties,
            record.value,
        })
    end)

    if ok then
        return encoded
    end

    return record.path .. "|" .. record.className .. "|" .. tostring(record.childCount)
end

local function encodedSize(value)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    if not ok then
        return 0, nil
    end
    return #encoded, encoded
end

local function ensureFolder()
    if not CAN_SPOOL_TO_DISK then
        return false
    end

    if type(isfolderFn) == "function" and isfolderFn(SessionFolder) then
        return true
    end

    if type(makefolderFn) == "function" then
        pcall(makefolderFn, SessionFolder)
    end

    if type(isfolderFn) == "function" then
        return isfolderFn(SessionFolder)
    end

    return true
end

local function storeChunk(chunk, encoded)
    local index = #StoredChunks + #MemoryChunks + 1

    if CAN_SPOOL_TO_DISK and ensureFolder() then
        local path = SessionFolder .. "/chunk_" .. string.format("%05d", index) .. ".json"
        local ok = pcall(writefileFn, path, encoded)
        if ok then
            StoredChunks[#StoredChunks + 1] = path
            return true
        end
    end

    local projected = 0
    for _, item in ipairs(MemoryChunks) do
        projected += item.bytes
    end
    projected += #encoded

    if projected > CONFIG.MEMORY_FALLBACK_LIMIT then
        return false, "Sem armazenamento local; limite de memória atingido"
    end

    MemoryChunks[#MemoryChunks + 1] = {
        objects = chunk,
        bytes = #encoded,
    }

    return true
end

local function flushChunk()
    if #CurrentChunk == 0 then
        return true
    end

    local _, encoded = encodedSize(CurrentChunk)
    if not encoded then
        return false, "Falha ao codificar bloco do Scan"
    end

    if #encoded > CONFIG.CHUNK_HARD_BYTES then
        return false, "Bloco excedeu 2 MB"
    end

    local ok, err = storeChunk(CurrentChunk, encoded)
    if not ok then
        return false, err
    end

    CurrentChunk = {}
    CurrentChunkBytes = 2
    return true
end

local function addRecord(record)
    local bytes = encodedSize(record)
    if bytes <= 0 then
        return true, false
    end

    local signature = signatureFor(record)
    local previous = SeenSignatures[record.path]

    if previous == signature then
        return true, false
    end

    local projected = TotalRecordedBytes + CurrentChunkBytes + bytes
    if projected > CONFIG.MAX_TOTAL_BYTES then
        return false, "LIMIT_REACHED"
    end

    if CurrentChunkBytes + bytes > CONFIG.CHUNK_TARGET_BYTES and #CurrentChunk > 0 then
        local ok, err = flushChunk()
        if not ok then
            return false, err
        end
    end

    SeenSignatures[record.path] = signature
    CurrentChunk[#CurrentChunk + 1] = record
    CurrentChunkBytes += bytes
    TotalRecordedBytes += bytes
    TotalRecords += 1

    return true, true
end

local function roots()
    local list = {}
    local candidates = {
        workspace,
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        game:GetService("Players"),
        game:GetService("Lighting"),
        game:GetService("StarterGui"),
        game:GetService("StarterPack"),
    }

    for _, item in ipairs(candidates) do
        list[#list + 1] = item
    end

    return list
end

local function enumerateVisibleObjects()
    local all = {}

    for _, root in ipairs(roots()) do
        all[#all + 1] = root

        local ok, descendants = pcall(function()
            return root:GetDescendants()
        end)

        if ok then
            for _, inst in ipairs(descendants) do
                all[#all + 1] = inst
                if #all >= CONFIG.MAX_OBJECTS_PER_PASS then
                    return all
                end
            end
        end
    end

    return all
end

--==============================================================--
-- UI MÍNIMA
--==============================================================--

local old = PlayerGui:FindFirstChild("CafeinaScanMinimal")
if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaScanMinimal"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(292, 104)
Main.Position = UDim2.new(0.5, -146, 0.14, 0)
Main.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
Main.BorderSizePixel = 0
Main.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(55, 55, 60)
Stroke.Thickness = 1
Stroke.Parent = Main

local function makeButton(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(132, 34)
    b.Position = UDim2.fromOffset(x, 8)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    b.TextColor3 = Color3.fromRGB(245, 245, 245)
    b.Text = text
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = Main
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b
    return b
end

local ScanButton = makeButton("SCAN", 8)
local SendButton = makeButton("ENVIAR AO SITE", 152)

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -16, 0, 20)
StatusText.Position = UDim2.fromOffset(8, 47)
StatusText.BackgroundTransparency = 1
StatusText.TextColor3 = Color3.fromRGB(175, 175, 185)
StatusText.Text = "Pronto para iniciar o Scan"
StatusText.TextSize = 9
StatusText.Font = Enum.Font.Gotham
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextTruncate = Enum.TextTruncate.AtEnd
StatusText.Parent = Main

local ProgressBG = Instance.new("Frame")
ProgressBG.Size = UDim2.new(1, -16, 0, 12)
ProgressBG.Position = UDim2.fromOffset(8, 76)
ProgressBG.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
ProgressBG.BorderSizePixel = 0
ProgressBG.Parent = Main
local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(1, 0)
pc.Parent = ProgressBG

local Progress = Instance.new("Frame")
Progress.Size = UDim2.new(0, 0, 1, 0)
Progress.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
Progress.BorderSizePixel = 0
Progress.Parent = ProgressBG
local pfc = Instance.new("UICorner")
pfc.CornerRadius = UDim.new(1, 0)
pfc.Parent = Progress

local PercentText = Instance.new("TextLabel")
PercentText.Size = UDim2.new(1, -16, 0, 12)
PercentText.Position = UDim2.fromOffset(8, 89)
PercentText.BackgroundTransparency = 1
PercentText.TextColor3 = Color3.fromRGB(110, 110, 120)
PercentText.Text = "0%"
PercentText.TextSize = 8
PercentText.Font = Enum.Font.Gotham
PercentText.TextXAlignment = Enum.TextXAlignment.Right
PercentText.Parent = Main

local function setProgress(text, fraction)
    fraction = math.clamp(tonumber(fraction) or 0, 0, 1)
    StatusText.Text = tostring(text or "")
    Progress.Size = UDim2.new(fraction, 0, 1, 0)
    PercentText.Text = tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function setSendEnabled(enabled)
    SendButton.Active = enabled
    SendButton.AutoButtonColor = enabled
    if enabled then
        SendButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
        SendButton.TextColor3 = Color3.fromRGB(20, 20, 22)
    else
        SendButton.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
        SendButton.TextColor3 = Color3.fromRGB(90, 90, 98)
    end
end

setSendEnabled(false)

-- Arrastar pelo fundo do menu.
local dragging = false
local dragStart
local startPos

Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement
    then
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

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
    then
        dragging = false
    end
end)

--==============================================================--
-- SCAN CONTÍNUO
--==============================================================--

local function resetScan()
    CancelGeneration += 1
    ScanRunning = false
    ScanComplete = false
    UploadRunning = false

    SeenSignatures = {}
    TotalRecordedBytes = 0
    TotalRecords = 0
    TotalPasses = 0
    StablePasses = 0
    CurrentChunk = {}
    CurrentChunkBytes = 2
    StoredChunks = {}
    MemoryChunks = {}
    SessionFolder = "CafeinaScan_" .. tostring(os.time())

    setSendEnabled(false)
end

local function finishScan(reason)
    local ok, err = flushChunk()
    ScanRunning = false

    if not ok then
        ScanComplete = false
        setSendEnabled(false)
        setProgress("Erro ao fechar Scan: " .. tostring(err), 0)
        ScanButton.Text = "SCAN"
        ScanButton.Active = true
        return
    end

    ScanComplete = true
    setSendEnabled(true)
    ScanButton.Text = "NOVO SCAN"
    ScanButton.Active = true

    local reasonText = reason == "LIMIT_REACHED"
        and "limite atingido"
        or "coleta estabilizada"

    setProgress(
        "Scan completo • " .. reasonText .. " • "
        .. tostring(TotalRecords) .. " registros • "
        .. readableSize(TotalRecordedBytes),
        1
    )
end

local function runContinuousScan()
    if ScanRunning or UploadRunning then
        return
    end

    resetScan()
    ScanRunning = true
    ScanButton.Text = "COLETANDO..."
    ScanButton.Active = false

    local generation = CancelGeneration

    task.spawn(function()
        while generation == CancelGeneration and ScanRunning do
            TotalPasses += 1
            local passNumber = TotalPasses
            local objects = enumerateVisibleObjects()
            local changedThisPass = 0
            local total = math.max(#objects, 1)

            for i, inst in ipairs(objects) do
                if generation ~= CancelGeneration or not ScanRunning then
                    return
                end

                local okSnapshot, record = pcall(snapshot, inst, passNumber)
                if okSnapshot and record then
                    local okAdd, result = addRecord(record)

                    if not okAdd then
                        if result == "LIMIT_REACHED" then
                            finishScan("LIMIT_REACHED")
                            return
                        end

                        ScanRunning = false
                        ScanComplete = false
                        ScanButton.Text = "SCAN"
                        ScanButton.Active = true
                        setSendEnabled(false)
                        setProgress("Erro: " .. tostring(result), 0)
                        return
                    end

                    if result then
                        changedThisPass += 1
                    end
                end

                if i % CONFIG.YIELD_EVERY == 0 then
                    local passProgress = i / total
                    local capacityProgress = math.min(
                        TotalRecordedBytes / CONFIG.MAX_TOTAL_BYTES,
                        0.95
                    )

                    local visual = math.max(capacityProgress, passProgress * 0.85)

                    setProgress(
                        "Scan " .. tostring(passNumber)
                        .. " • " .. tostring(i) .. "/" .. tostring(#objects)
                        .. " • " .. readableSize(TotalRecordedBytes),
                        visual
                    )
                    task.wait()
                end
            end

            if changedThisPass == 0 then
                StablePasses += 1
            else
                StablePasses = 0
            end

            if StablePasses >= CONFIG.STABLE_PASSES_REQUIRED then
                finishScan("STABLE")
                return
            end

            setProgress(
                "Passagem " .. tostring(passNumber)
                .. " concluída • " .. tostring(changedThisPass)
                .. " novo(s)/alterado(s) • confirmando estabilidade "
                .. tostring(StablePasses) .. "/"
                .. tostring(CONFIG.STABLE_PASSES_REQUIRED),
                math.min(TotalRecordedBytes / CONFIG.MAX_TOTAL_BYTES, 0.95)
            )

            task.wait(CONFIG.PASS_INTERVAL)
        end
    end)
end

--==============================================================--
-- UPLOAD EM CHUNKS COMPATÍVEIS COM BACKEND ATUAL (~6 MB)
--==============================================================--

local function doRequest(method, path, body)
    if type(requestFn) ~= "function" then
        return false, "request/http_request não disponível"
    end

    local payload = HttpService:JSONEncode(body or {})
    local lastError = "Falha desconhecida"

    for attempt = 1, CONFIG.UPLOAD_RETRIES do
        local ok, response = pcall(requestFn, {
            Url = CONFIG.API_BASE .. path,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = payload,
        })

        if ok and response then
            local status = tonumber(response.StatusCode or response.Status or 0) or 0
            local bodyText = tostring(response.Body or "")
            local decoded = nil

            pcall(function()
                decoded = HttpService:JSONDecode(bodyText)
            end)

            if status >= 200 and status < 300 then
                return true, decoded or bodyText
            end

            lastError =
                (type(decoded) == "table" and (decoded.message or decoded.error))
                or ("HTTP " .. tostring(status) .. " • " .. bodyText:sub(1, 300))
        else
            lastError = tostring(response)
        end

        if attempt < CONFIG.UPLOAD_RETRIES then
            task.wait(CONFIG.RETRY_DELAY * attempt)
        end
    end

    return false, lastError
end

local function loadChunk(index)
    local path = StoredChunks[index]
    if path then
        local ok, text = pcall(readfileFn, path)
        if not ok then
            return nil, "Não foi possível ler " .. tostring(path)
        end

        local okDecode, objects = pcall(function()
            return HttpService:JSONDecode(text)
        end)

        if not okDecode or type(objects) ~= "table" then
            return nil, "Chunk local inválido"
        end

        return objects
    end

    local memoryIndex = index - #StoredChunks
    local item = MemoryChunks[memoryIndex]
    if item then
        return item.objects
    end

    return nil, "Chunk não encontrado"
end

local function cleanupLocalChunks()
    if type(delfileFn) ~= "function" then
        return
    end

    for _, path in ipairs(StoredChunks) do
        pcall(function()
            if type(isfileFn) ~= "function" or isfileFn(path) then
                delfileFn(path)
            end
        end)
    end
end

local function uploadCompletedScan()
    if not ScanComplete or ScanRunning or UploadRunning then
        return
    end

    UploadRunning = true
    setSendEnabled(false)
    ScanButton.Active = false

    task.spawn(function()
        local okStart, startResult = doRequest("POST", "/upload/start", {
            token = CONFIG.UPLOAD_TOKEN,
            filename = "Cafeina_Scan_Continuo.json",
            source = "cafeina-continuous-scan",
            metadata = {
                placeId = game.PlaceId,
                gameId = game.GameId,
                jobId = game.JobId,
                passes = TotalPasses,
                records = TotalRecords,
                approximateBytes = TotalRecordedBytes,
            },
        })

        if not okStart or type(startResult) ~= "table" or not startResult.uploadId then
            UploadRunning = false
            ScanButton.Active = true
            setSendEnabled(true)
            setProgress("Falha ao iniciar envio: " .. tostring(startResult), 0)
            return
        end

        local uploadId = tostring(startResult.uploadId)
        local totalChunks = #StoredChunks + #MemoryChunks

        if totalChunks < 1 then
            UploadRunning = false
            ScanButton.Active = true
            setSendEnabled(true)
            setProgress("Nenhum bloco para enviar", 0)
            return
        end

        for index = 1, totalChunks do
            local objects, loadErr = loadChunk(index)
            if not objects then
                UploadRunning = false
                ScanButton.Active = true
                setSendEnabled(true)
                setProgress("Falha: " .. tostring(loadErr), (index - 1) / totalChunks)
                return
            end

            setProgress(
                "Enviando ao site • parte " .. tostring(index)
                .. "/" .. tostring(totalChunks),
                (index - 1) / totalChunks
            )

            local okChunk, chunkResult = doRequest("POST", "/upload/chunk", {
                token = CONFIG.UPLOAD_TOKEN,
                uploadId = uploadId,
                index = index,
                objects = objects,
            })

            if not okChunk then
                UploadRunning = false
                ScanButton.Active = true
                setSendEnabled(true)
                setProgress(
                    "Falha na parte " .. tostring(index) .. ": " .. tostring(chunkResult),
                    (index - 1) / totalChunks
                )
                return
            end

            task.wait()
        end

        setProgress("Finalizando arquivo no site...", 0.98)

        local okFinish, finishResult = doRequest("POST", "/upload/finish", {
            token = CONFIG.UPLOAD_TOKEN,
            uploadId = uploadId,
            totalChunks = totalChunks,
            summary = {
                objectCount = TotalRecords,
                approximateBytes = TotalRecordedBytes,
                passes = TotalPasses,
                scanComplete = true,
            },
        })

        UploadRunning = false
        ScanButton.Active = true

        if not okFinish then
            setSendEnabled(true)
            setProgress("Falha ao finalizar: " .. tostring(finishResult), 0.98)
            return
        end

        cleanupLocalChunks()

        local link = ""
        if type(finishResult) == "table" then
            link = tostring(
                finishResult.url
                or finishResult.downloadUrl
                or finishResult.download_url
                or finishResult.link
                or ""
            )
        end

        if link ~= "" and type(setclipboard) == "function" then
            pcall(setclipboard, link)
        end

        setProgress(
            link ~= ""
                and "Envio concluído • link copiado"
                or "Envio concluído",
            1
        )
    end)
end

ScanButton.Activated:Connect(function()
    if ScanComplete and not ScanRunning and not UploadRunning then
        runContinuousScan()
        return
    end
    runContinuousScan()
end)

SendButton.Activated:Connect(uploadCompletedScan)

