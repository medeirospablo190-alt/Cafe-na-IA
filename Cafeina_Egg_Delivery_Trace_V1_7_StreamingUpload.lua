--==============================================================--
-- CAFEINA • EGG DELIVERY TRACE V1.7 • STREAMING UPLOAD (PASSIVE)
-- Observes client-visible egg flow and uploads collected records.
-- It does NOT call FireServer/InvokeServer, move the character, or collect eggs.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local VERSION = "EGG_DELIVERY_TRACE_V1_7_STREAMING_UPLOAD"
local UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload"
local MAX_RECORDS = 12000
local CHUNK_TARGET_BYTES = 500000
local STATIC_MAX_RECORDS = 900
local STATIC_YIELD_EVERY = 25
local TRAJECTORY_INTERVAL = 0.15
local POST_ACTIVITY_SECONDS = 3.0

local KEYWORDS = {
    "eggworld", "fieldegg", "askplaceegg", "askfieldeggcarry",
    "askfieldeggdrop", "askhatch", "askfinishhatch", "redeem",
    "ownerdropped", "ownershifted", "zoneprobe", "anchorforzone",
    "profiledelta", "carryareaegg", "areaeggslotsclient", "safezone",
    "safe zone", "eggslot", "egginventory"
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

local function lower(v) return string.lower(tostring(v or "")) end
local function safePath(inst)
    local ok, result = pcall(function() return inst:GetFullName() end)
    return ok and result or tostring(inst)
end
local function relevant(text)
    local s = lower(text)
    for _, word in ipairs(KEYWORDS) do
        if string.find(s, word, 1, true) then return true end
    end
    return false
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then return "<max_depth>" end
    local tv = typeof(value)
    if value == nil or tv == "string" or tv == "boolean" then return value end
    if tv == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    end
    if tv == "Vector3" then return {type="Vector3", x=value.X, y=value.Y, z=value.Z} end
    if tv == "Vector2" then return {type="Vector2", x=value.X, y=value.Y} end
    if tv == "CFrame" then
        local p = value.Position
        local rx, ry, rz = value:ToOrientation()
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z, rx=rx, ry=ry, rz=rz}
    end
    if tv == "Color3" then return {type="Color3", r=value.R, g=value.G, b=value.B} end
    if tv == "EnumItem" then return tostring(value) end
    if tv == "Instance" then return {type="Instance", className=value.ClassName, name=value.Name, path=safePath(value)} end
    if tv == "table" then
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local out, count = {}, 0
        for k, v in pairs(value) do
            count += 1
            if count > 100 then out["<truncated>"] = true break end
            out[tostring(k)] = serialize(v, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end
    return tostring(value)
end

local function serializePacked(packed)
    local out = {count=packed.n, values={}}
    for i = 1, packed.n do out.values[i] = serialize(packed[i]) end
    return out
end

local state = {
    running=false, stop=false, uploadRunning=false, runId=nil, startedAt=0,
    records={}, connections={}, observed=setmetatable({}, {__mode="k"}),
    carrying=false, lastActivity=0, lastTrajectory=0,
}

local function playerSnapshot()
    local char = LP.Character
    if not char then return {character=false} end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local result = {character=true}
    if root then
        result.position = serialize(root.Position)
        result.cframe = serialize(root.CFrame)
        result.linearVelocity = serialize(root.AssemblyLinearVelocity)
    end
    if hum then
        result.health = hum.Health
        result.walkSpeed = hum.WalkSpeed
        result.state = tostring(hum:GetState())
    end
    return result
end

local function queueRecord(kind, data)
    if not state.running or state.stop then return end
    if #state.records >= MAX_RECORDS then state.stop = true return end
    local record = data or {}
    record.kind = kind
    record.version = VERSION
    record.placeId = game.PlaceId
    record.gameId = game.GameId
    record.placeVersion = game.PlaceVersion
    record.runId = state.runId
    record.time = os.clock() - state.startedAt
    record.unix = os.time()
    state.records[#state.records + 1] = record
end

local function updateCarryFrom(remotePath, packed)
    local p = lower(remotePath)
    if string.find(p, "fieldeggcarry", 1, true) then
        state.carrying = true
    elseif string.find(p, "redeem", 1, true) or string.find(p, "ownerdropped", 1, true) then
        state.carrying = false
    elseif string.find(p, "fieldeggshifted", 1, true) then
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, serializePacked(packed))
        encoded = ok and lower(encoded) or ""
        if string.find(encoded, "carried", 1, true) then state.carrying = true end
        if string.find(encoded, "dropped", 1, true) or string.find(encoded, "slot", 1, true) then state.carrying = false end
    end
end

local function attachInbound(remote)
    if state.observed[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
    local path = safePath(remote)
    if not relevant(path) then return end
    state.observed[remote] = true
    local connection = remote.OnClientEvent:Connect(function(...)
        if not state.running or state.stop then return end
        local packed = table.pack(...)
        task.defer(function()
            if not state.running or state.stop then return end
            state.lastActivity = os.clock()
            updateCarryFrom(path, packed)
            queueRecord("remote_received", {
                source="network_in",
                remote={name=remote.Name, className=remote.ClassName, path=path},
                payload=serializePacked(packed),
                carry={active=state.carrying},
                player=playerSnapshot(),
            })
        end)
    end)
    state.connections[#state.connections + 1] = connection
end

local function installInboundObservers()
    local count = 0
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) and relevant(safePath(inst)) then
            attachInbound(inst)
            count += 1
        end
    end
    local added = ReplicatedStorage.DescendantAdded:Connect(function(inst)
        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then task.defer(attachInbound, inst) end
    end)
    state.connections[#state.connections + 1] = added
    queueRecord("inbound_observers_ready", {source="session", count=count})
end

local function installPromptObservers()
    local seen = setmetatable({}, {__mode="k"})
    local function attach(prompt)
        if seen[prompt] or not prompt:IsA("ProximityPrompt") then return end
        local descriptor = table.concat({prompt.Name, prompt.ActionText, prompt.ObjectText, safePath(prompt)}, " ")
        if not relevant(descriptor) then return end
        seen[prompt] = true
        local c = prompt.Triggered:Connect(function(player)
            if player and player ~= LP then return end
            state.lastActivity = os.clock()
            queueRecord("egg_prompt_triggered", {
                source="interaction",
                prompt={path=safePath(prompt), actionText=prompt.ActionText, objectText=prompt.ObjectText},
                player=playerSnapshot(),
            })
        end)
        state.connections[#state.connections + 1] = c
    end
    for _, inst in ipairs(Workspace:GetDescendants()) do attach(inst) end
    local c = Workspace.DescendantAdded:Connect(function(inst)
        if inst:IsA("ProximityPrompt") then task.defer(attach, inst) end
    end)
    state.connections[#state.connections + 1] = c
end

local function staticSnapshot()
    local recorded, scanned = 0, 0
    local function maybe(inst, source)
        if recorded >= STATIC_MAX_RECORDS then return false end
        scanned += 1
        local path = safePath(inst)
        if relevant(path) then
            local record = {source=source, path=path, name=inst.Name, className=inst.ClassName}
            if inst:IsA("BasePart") then
                record.position = serialize(inst.Position)
                record.cframe = serialize(inst.CFrame)
                record.canCollide = inst.CanCollide
                record.canTouch = inst.CanTouch
                record.canQuery = inst.CanQuery
            elseif inst:IsA("ProximityPrompt") then
                record.prompt = {actionText=inst.ActionText, objectText=inst.ObjectText, holdDuration=inst.HoldDuration, enabled=inst.Enabled}
            end
            queueRecord("egg_world_candidate", record)
            recorded += 1
        end
        if scanned % STATIC_YIELD_EVERY == 0 then task.wait() end
        return true
    end
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if not state.running or state.stop or not maybe(inst, "target_scan_replicated") then break end
    end
    if recorded < STATIC_MAX_RECORDS then
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if not state.running or state.stop or not maybe(inst, "target_scan_workspace") then break end
        end
    end
    queueRecord("target_snapshot_complete", {source="target_scan", recorded=recorded, scanned=scanned, capped=recorded >= STATIC_MAX_RECORDS})
end

local function disconnectAll()
    for _, c in ipairs(state.connections) do pcall(function() c:Disconnect() end) end
    table.clear(state.connections)
    state.observed = setmetatable({}, {__mode="k"})
end

local function postJson(url, body)
    if not REQUEST then return false, nil, "executor HTTP request unavailable" end
    local encoded = HttpService:JSONEncode(body)
    local lastError = "unknown"
    for attempt = 1, 3 do
        local ok, res = pcall(REQUEST, {Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=encoded})
        if ok and type(res) == "table" then
            local statusCode = tonumber(res.StatusCode or res.Status or res.status)
            local success = res.Success
            if success == nil and statusCode then success = statusCode >= 200 and statusCode < 300 end
            if success == true then
                local text = res.Body or res.body or "{}"
                local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
                return true, decodeOk and data or {raw=text}, nil
            end
            lastError = "HTTP " .. tostring(statusCode) .. " " .. tostring(res.Body or res.body or "")
        else
            lastError = tostring(res)
        end
        task.wait(0.75 * attempt)
    end
    return false, nil, lastError
end

local function uploadAll(statusCallback)
    if state.uploadRunning then return false, "upload already running" end
    if #state.records == 0 then return false, "no records" end
    state.uploadRunning = true
    local filename = string.format("Cafeina_EggTrace_%s_%s.json", tostring(game.PlaceId), os.date("!%Y%m%d_%H%M%S"))
    local ok, startData, err = postJson(UPLOAD_BASE .. "/start", {
        filename=filename,
        source=VERSION,
        metadata={scanner=VERSION, placeId=game.PlaceId, gameId=game.GameId, placeVersion=game.PlaceVersion, records=#state.records, passive=true, outboundHook=false}
    })
    if not ok then state.uploadRunning=false return false, err end
    local uploadId = startData and (startData.uploadId or startData.id or startData.upload_id)
    if not uploadId then state.uploadRunning=false return false, "invalid /start response" end

    local chunkIndex, current, currentBytes, totalBytes = 0, {}, 2, 0
    local function flushChunk()
        if #current == 0 then return true end
        chunkIndex += 1
        if statusCallback then statusCallback(string.format("Enviando chunk %d...", chunkIndex)) end
        totalBytes += #HttpService:JSONEncode(current)
        local chunkOk, _, chunkErr = postJson(UPLOAD_BASE .. "/chunk", {uploadId=uploadId, index=chunkIndex, objects=current})
        if not chunkOk then return false, chunkErr end
        current, currentBytes = {}, 2
        task.wait()
        return true
    end

    for _, record in ipairs(state.records) do
        local itemBytes = #HttpService:JSONEncode(record) + 1
        if #current > 0 and currentBytes + itemBytes > CHUNK_TARGET_BYTES then
            local flushOk, flushErr = flushChunk()
            if not flushOk then state.uploadRunning=false return false, flushErr end
        end
        current[#current + 1] = record
        currentBytes += itemBytes
    end
    local flushOk, flushErr = flushChunk()
    if not flushOk then state.uploadRunning=false return false, flushErr end

    if statusCallback then statusCallback("Confirmando upload...") end
    local finishOk, finishData, finishErr = postJson(UPLOAD_BASE .. "/finish", {uploadId=uploadId, totalChunks=chunkIndex, totalBytes=totalBytes, records=#state.records})
    if not finishOk then state.uploadRunning=false return false, finishErr end
    local confirmed = finishData and (finishData.confirmed == true or finishData.success == true or finishData.ok == true)
    if not confirmed then state.uploadRunning=false return false, "server did not confirm /finish" end
    state.uploadRunning = false
    return true, tostring(finishData.url or finishData.link or finishData.fileUrl or "")
end

local heartbeat = RunService.Heartbeat:Connect(function()
    if not state.running or state.stop then return end
    local now = os.clock()
    local active = state.carrying or (state.lastActivity > 0 and now - state.lastActivity <= POST_ACTIVITY_SECONDS)
    if active and now - state.lastTrajectory >= TRAJECTORY_INTERVAL then
        state.lastTrajectory = now
        queueRecord("egg_player_trajectory", {source="trajectory", carry={active=state.carrying}, player=playerSnapshot()})
    end
end)

local GUI_NAME = "CafeinaEggDeliveryTraceV17"
local guiParent = CoreGui
pcall(function() if gethui then guiParent = gethui() end end)
pcall(function() local old = guiParent:FindFirstChild(GUI_NAME); if old then old:Destroy() end end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
local parentOk = pcall(function() gui.Parent = guiParent end)
if not parentOk then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(248, 150)
frame.Position = UDim2.new(0.5, -124, 0.4, -75)
frame.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
frame.BorderSizePixel = 0
frame.Parent = gui
local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 9); corner.Parent = frame
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(48,48,55); stroke.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(9,7); title.Size=UDim2.new(1,-18,0,20)
title.Font=Enum.Font.GothamBold; title.TextSize=12; title.TextColor3=Color3.new(1,1,1); title.TextXAlignment=Enum.TextXAlignment.Left
title.Text="CAFEINA • EGG TRACE V1.7"; title.Parent=frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency=1; status.Position=UDim2.fromOffset(9,33); status.Size=UDim2.new(1,-18,0,42)
status.Font=Enum.Font.Gotham; status.TextSize=10; status.TextWrapped=true; status.TextColor3=Color3.fromRGB(185,185,195); status.TextXAlignment=Enum.TextXAlignment.Left
status.Text="Pronto • observação passiva"; status.Parent=frame

local button = Instance.new("TextButton")
button.Position=UDim2.fromOffset(9,89); button.Size=UDim2.new(1,-18,0,40); button.BackgroundColor3=Color3.fromRGB(31,31,36)
button.BorderSizePixel=0; button.Font=Enum.Font.GothamBold; button.TextSize=11; button.TextColor3=Color3.new(1,1,1); button.Text="INICIAR COLETA"; button.Parent=frame
local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,7); bc.Parent=button

local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging=true; dragStart=input.Position; startPos=frame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging=false end end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput=input end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local function beginSession()
    if state.running or state.uploadRunning then return end
    state.running=true; state.stop=false; state.records={}; state.runId=HttpService:GenerateGUID(false)
    state.startedAt=os.clock(); state.lastActivity=0; state.lastTrajectory=0; state.carrying=false
    installInboundObservers(); task.spawn(installPromptObservers); task.spawn(staticSnapshot)
    queueRecord("session_started", {source="session", capabilities={request=REQUEST ~= nil, outboundHook=false}, player=playerSnapshot()})
    button.Text="ENCERRAR + ENVIAR"; button.BackgroundColor3=Color3.fromRGB(165,42,48)
    status.Text="Coletando passivamente • jogue normalmente"
end

local function finishSession()
    if not state.running or state.uploadRunning then return end
    queueRecord("session_finalized", {source="session", records=#state.records, player=playerSnapshot()})
    state.stop=true; state.running=false; disconnectAll()
    button.Text="ENVIANDO..."; status.Text="Finalizando arquivo..."
    task.spawn(function()
        local ok, result = uploadAll(function(text) status.Text=text end)
        if ok then
            status.Text = result ~= "" and ("Upload confirmado ✓\n" .. string.sub(result,1,90)) or "Upload confirmado ✓"
            button.Text="INICIAR COLETA"; button.BackgroundColor3=Color3.fromRGB(31,31,36); state.records={}
        else
            status.Text="Falha no upload • dados mantidos\n" .. tostring(result)
            button.Text="REENVIAR"; button.BackgroundColor3=Color3.fromRGB(31,31,36)
        end
    end)
end

button.Activated:Connect(function()
    if state.uploadRunning then return end
    if button.Text == "REENVIAR" then
        button.Text="ENVIANDO..."
        task.spawn(function()
            local ok, result = uploadAll(function(text) status.Text=text end)
            if ok then status.Text="Upload confirmado ✓"; button.Text="INICIAR COLETA"; state.records={}
            else status.Text="Falha • " .. tostring(result); button.Text="REENVIAR" end
        end)
    elseif state.running then finishSession() else beginSession() end
end)

ENV.__CAFEINA_EGG_TRACE_V17_CONTROLLER = {
    Gui=gui,
    Stop=function(reason)
        if state.running then queueRecord("controller_stop", {source="session", reason=reason or "external_stop"}) end
        state.stop=true; state.running=false; disconnectAll(); pcall(function() heartbeat:Disconnect() end); pcall(function() gui:Destroy() end)
    end,
}

gui.Destroying:Connect(function()
    state.stop=true; state.running=false; disconnectAll(); pcall(function() heartbeat:Disconnect() end)
end)

print("[CAFEINA] EGG DELIVERY TRACE V1.7 STREAMING UPLOAD (PASSIVE) carregado.")
