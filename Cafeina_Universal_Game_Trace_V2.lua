--==============================================================--
-- CAFEINA • UNIVERSAL GAME TRACE V2
-- Universal passive mapper for Roblox executor/mobile use.
-- No game-specific keyword filters. It catalogs client-visible
-- structure, remotes, prompts, values, tags, inventory, movement,
-- inbound remote payloads and the real outbound remote calls made
-- by the game itself when hook support is available.
--
-- IMPORTANT: this collector does NOT blindly FireServer/InvokeServer
-- unknown remotes. It observes real traffic and normal interactions.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local CONFIG = {
    VERSION = "CAFEINA_UNIVERSAL_GAME_TRACE_V2_0",
    PURPOSE = "universal_game_mapping",
    ENDPOINT = "https://cafe-na-ia.onrender.com/api/inventory-trace",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace/health",

    MAX_RECORDS = 18000,
    MAX_REMOTE_CATALOG = 1200,
    MAX_INBOUND_LISTENERS = 1000,
    MAX_VALUE_WATCHERS = 700,
    MAX_STRING = 1200,
    MAX_TABLE_ITEMS = 60,
    MAX_DEPTH = 4,

    STATIC_PATH_SAMPLES = 4500,
    NEARBY_PART_RADIUS = 140,
    NEARBY_PART_MAX = 1400,
    GUI_TEXT_MAX = 800,
    TAG_INSTANCE_MAX = 25,

    TRAJECTORY_INTERVAL = 0.50,
    COUNTER_REFRESH = 0.25,

    UPLOAD_RECORDS_PER_BATCH = 850,
    UPLOAD_REMOTES_PER_BATCH = 500,
    UPLOAD_MAX_BATCHES = 27,
    HTTP_RETRIES = 4,
    HTTP_RETRY_BASE = 0.8,

    CACHE_FILE = "CafeinaUniversalTrace_pending.json",
}

local function pickFunction(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "function" then return value end
    end
    return nil
end

local synRequest
pcall(function()
    if syn and type(syn.request) == "function" then synRequest = syn.request end
end)

local httpRequest
pcall(function()
    if http and type(http.request) == "function" then httpRequest = http.request end
end)

local REQUEST = pickFunction(
    rawget(ENV, "request"),
    rawget(ENV, "http_request"),
    request,
    http_request,
    httpRequest,
    synRequest
)

local WRITEFILE = pickFunction(rawget(ENV, "writefile"), writefile)
local READFILE = pickFunction(rawget(ENV, "readfile"), readfile)
local ISFILE = pickFunction(rawget(ENV, "isfile"), isfile)
local DELFILE = pickFunction(rawget(ENV, "delfile"), delfile)

local function safePath(inst)
    if typeof(inst) ~= "Instance" then return tostring(inst) end
    local ok, result = pcall(function() return inst:GetFullName() end)
    return ok and result or (inst.ClassName .. ":" .. inst.Name)
end

local function safeAttributes(inst)
    local result = {}
    if typeof(inst) ~= "Instance" then return result end
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if not ok or type(attrs) ~= "table" then return result end
    local count = 0
    for key, value in pairs(attrs) do
        count = count + 1
        if count > 40 then
            result["<truncated>"] = true
            break
        end
        result[tostring(key)] = value
    end
    return result
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > CONFIG.MAX_DEPTH then return "<max_depth>" end

    local tv = typeof(value)
    if value == nil or tv == "boolean" then return value end
    if tv == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    end
    if tv == "string" then
        if #value > CONFIG.MAX_STRING then
            return string.sub(value, 1, CONFIG.MAX_STRING) .. "...[truncated]"
        end
        return value
    end
    if tv == "Vector2" then return {type="Vector2", x=value.X, y=value.Y} end
    if tv == "Vector3" then return {type="Vector3", x=value.X, y=value.Y, z=value.Z} end
    if tv == "CFrame" then
        local p = value.Position
        local rx, ry, rz = value:ToOrientation()
        return {type="CFrame", x=p.X, y=p.Y, z=p.Z, rx=rx, ry=ry, rz=rz}
    end
    if tv == "Color3" then return {type="Color3", r=value.R, g=value.G, b=value.B} end
    if tv == "UDim" then return {type="UDim", scale=value.Scale, offset=value.Offset} end
    if tv == "UDim2" then
        return {
            type="UDim2",
            xScale=value.X.Scale, xOffset=value.X.Offset,
            yScale=value.Y.Scale, yOffset=value.Y.Offset,
        }
    end
    if tv == "EnumItem" then return tostring(value) end
    if tv == "Instance" then
        return {
            type="Instance",
            className=value.ClassName,
            name=value.Name,
            path=safePath(value),
        }
    end
    if tv == "table" then
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local result, count = {}, 0
        for key, item in pairs(value) do
            count = count + 1
            if count > CONFIG.MAX_TABLE_ITEMS then
                result["<truncated>"] = true
                break
            end
            result[tostring(key)] = serialize(item, depth + 1, seen)
        end
        seen[value] = nil
        return result
    end
    return tostring(value)
end

local function serializePacked(packed)
    local result = {count = tonumber(packed and packed.n) or 0, values = {}}
    local limit = math.min(result.count, 30)
    for i = 1, limit do
        result.values[i] = serialize(packed[i])
    end
    if result.count > limit then result.truncated = result.count - limit end
    return result
end

local STATE = {
    running = false,
    stopping = false,
    uploading = false,
    runId = nil,
    startedClock = 0,
    startedIso = nil,
    records = {},
    remotes = {},
    remoteSeen = {},
    connections = {},
    inboundAttached = setmetatable({}, {__mode="k"}),
    valueAttached = setmetatable({}, {__mode="k"}),
    dropped = 0,
    inboundListeners = 0,
    valueWatchers = 0,
    outboundHookInstalled = false,
    lastTrajectory = 0,
    staticDone = false,
    status = "idle",
}

local function nowIso()
    local ok, value = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and value or tostring(os.time())
end

local function record(kind, data)
    if not STATE.running or STATE.stopping then return nil end
    if #STATE.records >= CONFIG.MAX_RECORDS then
        STATE.dropped = STATE.dropped + 1
        return nil
    end
    local item = data or {}
    item.seq = #STATE.records + 1
    item.kind = tostring(kind)
    item.clock = os.clock() - STATE.startedClock
    item.unix = os.time()
    item.runId = STATE.runId
    STATE.records[#STATE.records + 1] = item
    return item
end

local function playerSnapshot()
    local character = LP.Character
    local result = {
        userId = LP.UserId,
        username = LP.Name,
        displayName = LP.DisplayName,
        character = character ~= nil,
    }
    if not character then return result end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if root then
        result.position = serialize(root.Position)
        result.cframe = serialize(root.CFrame)
        result.linearVelocity = serialize(root.AssemblyLinearVelocity)
        result.angularVelocity = serialize(root.AssemblyAngularVelocity)
    end
    if humanoid then
        result.health = humanoid.Health
        result.maxHealth = humanoid.MaxHealth
        result.walkSpeed = humanoid.WalkSpeed
        result.jumpPower = humanoid.JumpPower
        result.hipHeight = humanoid.HipHeight
        result.state = tostring(humanoid:GetState())
        result.moveDirection = serialize(humanoid.MoveDirection)
        result.floorMaterial = tostring(humanoid.FloorMaterial)
    end
    return result
end

local function remoteDescriptor(remote)
    return {
        path = safePath(remote),
        name = remote.Name,
        className = remote.ClassName,
        parent = remote.Parent and safePath(remote.Parent) or nil,
        attributes = serialize(safeAttributes(remote)),
    }
end

local function registerRemote(remote, source)
    if typeof(remote) ~= "Instance" then return end
    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("RemoteFunction")
        or remote:IsA("UnreliableRemoteEvent")
    ) then return end

    local path = safePath(remote)
    if STATE.remoteSeen[path] then return end
    STATE.remoteSeen[path] = true

    if #STATE.remotes < CONFIG.MAX_REMOTE_CATALOG then
        local descriptor = remoteDescriptor(remote)
        descriptor.source = source or "scan"
        STATE.remotes[#STATE.remotes + 1] = descriptor
    end
end

local function attachInbound(remote)
    if STATE.inboundAttached[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
    if STATE.inboundListeners >= CONFIG.MAX_INBOUND_LISTENERS then return end

    STATE.inboundAttached[remote] = true
    STATE.inboundListeners = STATE.inboundListeners + 1
    registerRemote(remote, "inbound_listener")

    local path = safePath(remote)
    local conn = remote.OnClientEvent:Connect(function(...)
        if not STATE.running or STATE.stopping then return end
        local packed = table.pack(...)
        record("remote_inbound", {
            remote = remoteDescriptor(remote),
            payload = serializePacked(packed),
            player = playerSnapshot(),
        })
    end)
    STATE.connections[#STATE.connections + 1] = conn
end

local function installOutboundObserver()
    if STATE.outboundHookInstalled then return true end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false
    end

    local oldNamecall
    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if STATE.running and not STATE.stopping and typeof(self) == "Instance" then
                if method == "FireServer" or method == "InvokeServer" then
                    local isRemote = self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")
                    if isRemote then
                        registerRemote(self, "outbound_observed")
                        local packed = table.pack(...)
                        record("remote_outbound", {
                            method = method,
                            remote = remoteDescriptor(self),
                            payload = serializePacked(packed),
                            player = playerSnapshot(),
                        })
                    end
                end
            end
            return oldNamecall(self, ...)
        end))
    end)

    if ok then
        STATE.outboundHookInstalled = true
        return true
    end
    record("collector_warning", {phase="outbound_hook", error=tostring(err)})
    return false
end

local function valueSnapshot(valueObj)
    local result = {
        path = safePath(valueObj),
        name = valueObj.Name,
        className = valueObj.ClassName,
        attributes = serialize(safeAttributes(valueObj)),
    }
    pcall(function() result.value = serialize(valueObj.Value) end)
    return result
end

local function attachValue(valueObj)
    if STATE.valueAttached[valueObj] then return end
    if not valueObj:IsA("ValueBase") then return end
    if STATE.valueWatchers >= CONFIG.MAX_VALUE_WATCHERS then return end
    STATE.valueAttached[valueObj] = true
    STATE.valueWatchers = STATE.valueWatchers + 1

    local conn = valueObj.Changed:Connect(function(value)
        if not STATE.running or STATE.stopping then return end
        record("value_changed", {
            valueObject = valueSnapshot(valueObj),
            changedValue = serialize(value),
        })
    end)
    STATE.connections[#STATE.connections + 1] = conn
end

local function importantInstanceSnapshot(inst, source)
    local result = {
        source = source,
        path = safePath(inst),
        name = inst.Name,
        className = inst.ClassName,
        parent = inst.Parent and safePath(inst.Parent) or nil,
        attributes = serialize(safeAttributes(inst)),
    }

    if inst:IsA("ValueBase") then
        pcall(function() result.value = serialize(inst.Value) end)
    elseif inst:IsA("ProximityPrompt") then
        result.prompt = {
            actionText = inst.ActionText,
            objectText = inst.ObjectText,
            enabled = inst.Enabled,
            holdDuration = inst.HoldDuration,
            maxActivationDistance = inst.MaxActivationDistance,
            requiresLineOfSight = inst.RequiresLineOfSight,
        }
    elseif inst:IsA("ClickDetector") then
        result.clickDetector = {
            maxActivationDistance = inst.MaxActivationDistance,
        }
    elseif inst:IsA("BasePart") then
        result.position = serialize(inst.Position)
        result.size = serialize(inst.Size)
        result.material = tostring(inst.Material)
        result.anchored = inst.Anchored
        result.canCollide = inst.CanCollide
        result.canTouch = inst.CanTouch
        result.canQuery = inst.CanQuery
        result.transparency = inst.Transparency
    elseif inst:IsA("Tool") then
        result.tool = {
            requiresHandle = inst.RequiresHandle,
            canBeDropped = inst.CanBeDropped,
        }
    elseif inst:IsA("GuiObject") then
        result.gui = {
            visible = inst.Visible,
            position = serialize(inst.Position),
            size = serialize(inst.Size),
        }
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            result.gui.text = serialize(inst.Text)
        end
    end

    return result
end

local function classHistogram(descendants)
    local histogram = {}
    for _, inst in ipairs(descendants) do
        histogram[inst.ClassName] = (histogram[inst.ClassName] or 0) + 1
    end
    return histogram
end

local function staticScanContainer(root, label)
    local descendants = root:GetDescendants()
    record("container_summary", {
        container = label,
        path = safePath(root),
        descendants = #descendants,
        classHistogram = classHistogram(descendants),
    })

    local pathSamples = 0
    for index, inst in ipairs(descendants) do
        if not STATE.running or STATE.stopping then return end

        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
            registerRemote(inst, label)
            if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then attachInbound(inst) end
            record("remote_catalog_entry", remoteDescriptor(inst))
        elseif inst:IsA("ProximityPrompt")
            or inst:IsA("ClickDetector")
            or inst:IsA("Tool")
            or inst:IsA("ValueBase")
            or inst:IsA("ModuleScript")
            or inst:IsA("LocalScript")
            or inst:IsA("Script")
            or inst:IsA("BindableEvent")
            or inst:IsA("BindableFunction")
            or inst:IsA("Configuration") then
            record("important_instance", importantInstanceSnapshot(inst, label))
            if inst:IsA("ValueBase") then attachValue(inst) end
        elseif pathSamples < CONFIG.STATIC_PATH_SAMPLES and (
            inst:IsA("Folder") or inst:IsA("Model") or inst:IsA("Accessory")
        ) then
            pathSamples = pathSamples + 1
            record("structure_path", {
                source = label,
                path = safePath(inst),
                className = inst.ClassName,
                children = #inst:GetChildren(),
                attributes = serialize(safeAttributes(inst)),
            })
        end

        if index % 120 == 0 then task.wait() end
    end
end

local function nearbyPartScan()
    local character = LP.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        record("nearby_scan", {ok=false, reason="no_root"})
        return
    end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.MaxParts = CONFIG.NEARBY_PART_MAX

    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInRadius(root.Position, CONFIG.NEARBY_PART_RADIUS, params)
    end)
    if not ok then
        record("nearby_scan", {ok=false, error=tostring(parts)})
        return
    end

    record("nearby_scan", {
        ok=true,
        radius=CONFIG.NEARBY_PART_RADIUS,
        parts=#parts,
        origin=serialize(root.Position),
    })

    for index, part in ipairs(parts) do
        if not STATE.running or STATE.stopping then return end
        if index <= CONFIG.NEARBY_PART_MAX then
            record("nearby_part", importantInstanceSnapshot(part, "workspace_nearby"))
        end
        if index % 100 == 0 then task.wait() end
    end
end

local function scanTags()
    local ok, tags = pcall(function() return CollectionService:GetAllTags() end)
    if not ok or type(tags) ~= "table" then
        record("tag_scan", {ok=false, error=tostring(tags)})
        return
    end

    table.sort(tags)
    record("tag_scan", {ok=true, tagCount=#tags, tags=serialize(tags)})
    for _, tag in ipairs(tags) do
        if not STATE.running or STATE.stopping then return end
        local tagged = CollectionService:GetTagged(tag)
        local samples = {}
        local limit = math.min(#tagged, CONFIG.TAG_INSTANCE_MAX)
        for i = 1, limit do samples[i] = safePath(tagged[i]) end
        record("tag_entry", {tag=tag, count=#tagged, samples=samples})
    end
end

local function scanPlayerState()
    record("player_snapshot", {
        player = playerSnapshot(),
        attributes = serialize(safeAttributes(LP)),
    })

    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                record("inventory_tool", importantInstanceSnapshot(child, "backpack"))
            end
        end
    end

    local leaderstats = LP:FindFirstChild("leaderstats")
    if leaderstats then
        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("ValueBase") then
                record("leaderstat", valueSnapshot(child))
                attachValue(child)
            end
        end
    end
end

local function scanGui()
    local playerGui = LP:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end
    local count = 0
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if not STATE.running or STATE.stopping then return end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            count = count + 1
            if count > CONFIG.GUI_TEXT_MAX then break end
            record("gui_text", importantInstanceSnapshot(inst, "player_gui"))
        elseif inst:IsA("ScreenGui") then
            record("gui_screen", {
                path=safePath(inst),
                name=inst.Name,
                enabled=inst.Enabled,
                displayOrder=inst.DisplayOrder,
                attributes=serialize(safeAttributes(inst)),
            })
        end
        if count % 80 == 0 then task.wait() end
    end
end

local function installRuntimeWatchers()
    local rsAdded = ReplicatedStorage.DescendantAdded:Connect(function(inst)
        if not STATE.running or STATE.stopping then return end
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
            registerRemote(inst, "replicated_added")
            if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then attachInbound(inst) end
            record("replicated_added", importantInstanceSnapshot(inst, "replicated_added"))
        elseif inst:IsA("ValueBase") or inst:IsA("Tool") or inst:IsA("ProximityPrompt") then
            record("replicated_added", importantInstanceSnapshot(inst, "replicated_added"))
            if inst:IsA("ValueBase") then attachValue(inst) end
        end
    end)
    STATE.connections[#STATE.connections + 1] = rsAdded

    local rsRemoving = ReplicatedStorage.DescendantRemoving:Connect(function(inst)
        if not STATE.running or STATE.stopping then return end
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent")
            or inst:IsA("ValueBase") or inst:IsA("Tool") or inst:IsA("ProximityPrompt") then
            record("replicated_removing", {
                path=safePath(inst), name=inst.Name, className=inst.ClassName,
            })
        end
    end)
    STATE.connections[#STATE.connections + 1] = rsRemoving

    local worldAdded = Workspace.DescendantAdded:Connect(function(inst)
        if not STATE.running or STATE.stopping then return end
        if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") or inst:IsA("Tool") or inst:IsA("ValueBase") then
            record("workspace_added", importantInstanceSnapshot(inst, "workspace_added"))
            if inst:IsA("ValueBase") then attachValue(inst) end
        end
    end)
    STATE.connections[#STATE.connections + 1] = worldAdded

    local worldRemoving = Workspace.DescendantRemoving:Connect(function(inst)
        if not STATE.running or STATE.stopping then return end
        if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") or inst:IsA("Tool") or inst:IsA("ValueBase") then
            record("workspace_removing", {
                path=safePath(inst), name=inst.Name, className=inst.ClassName,
                attributes=serialize(safeAttributes(inst)),
            })
        end
    end)
    STATE.connections[#STATE.connections + 1] = worldRemoving

    local promptTriggered = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not STATE.running or STATE.stopping then return end
        if player and player ~= LP then return end
        record("proximity_prompt_triggered", {
            prompt=importantInstanceSnapshot(prompt, "prompt_triggered"),
            player=playerSnapshot(),
        })
    end)
    STATE.connections[#STATE.connections + 1] = promptTriggered

    local attrChanged = LP.AttributeChanged:Connect(function(name)
        if not STATE.running or STATE.stopping then return end
        record("player_attribute_changed", {
            name=tostring(name),
            value=serialize(LP:GetAttribute(name)),
        })
    end)
    STATE.connections[#STATE.connections + 1] = attrChanged

    local function watchContainer(container, label)
        if not container then return end
        local added = container.ChildAdded:Connect(function(child)
            if not STATE.running or STATE.stopping then return end
            if child:IsA("Tool") then
                record("tool_added", {container=label, tool=importantInstanceSnapshot(child, label), player=playerSnapshot()})
            end
        end)
        STATE.connections[#STATE.connections + 1] = added
        local removed = container.ChildRemoved:Connect(function(child)
            if not STATE.running or STATE.stopping then return end
            if child:IsA("Tool") then
                record("tool_removed", {container=label, tool={name=child.Name, path=safePath(child)}, player=playerSnapshot()})
            end
        end)
        STATE.connections[#STATE.connections + 1] = removed
    end

    watchContainer(LP:FindFirstChildOfClass("Backpack"), "Backpack")
    watchContainer(LP.Character, "Character")

    local charAdded = LP.CharacterAdded:Connect(function(character)
        if not STATE.running or STATE.stopping then return end
        record("character_added", {path=safePath(character)})
        watchContainer(character, "Character")
    end)
    STATE.connections[#STATE.connections + 1] = charAdded
end

local function disconnectAll()
    for _, connection in ipairs(STATE.connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(STATE.connections)
    STATE.inboundAttached = setmetatable({}, {__mode="k"})
    STATE.valueAttached = setmetatable({}, {__mode="k"})
    STATE.inboundListeners = 0
    STATE.valueWatchers = 0
end

local function requestRaw(options)
    if not REQUEST then return false, nil, "executor_request_unavailable" end
    local lastError = "unknown"
    for attempt = 1, CONFIG.HTTP_RETRIES do
        local ok, result = pcall(REQUEST, options)
        if ok and type(result) == "table" then
            local status = tonumber(result.StatusCode or result.Status or result.status) or 0
            local body = result.Body or result.body or ""
            if status >= 200 and status < 300 then return true, result, nil end
            lastError = "HTTP " .. tostring(status) .. " " .. tostring(body)
        else
            lastError = tostring(result)
        end
        task.wait(CONFIG.HTTP_RETRY_BASE * attempt)
    end
    return false, nil, lastError
end

local function getJson(url)
    local ok, response, err = requestRaw({
        Url=url,
        Method="GET",
        Headers={Accept="application/json"},
    })
    if not ok then return false, nil, err end
    local text = response.Body or response.body or "{}"
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
    if not decodeOk then return false, nil, "invalid_json: " .. tostring(text) end
    return true, data, nil
end

local function postJson(url, body)
    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, body)
    if not okEncode then return false, nil, "json_encode_failed: " .. tostring(encoded) end

    local ok, response, err = requestRaw({
        Url=url,
        Method="POST",
        Headers={
            ["Content-Type"]="application/json",
            Accept="application/json",
        },
        Body=encoded,
    })
    if not ok then return false, nil, err end

    local text = response.Body or response.body or "{}"
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)
    if not decodeOk or type(data) ~= "table" then
        return false, nil, "invalid_api_response: " .. tostring(text)
    end
    if data.ok ~= true then
        return false, data, tostring(data.message or "api_not_ok")
    end
    if type(data.github) ~= "table" then
        return false, data, "github_status_missing"
    end
    if data.github.configured ~= true then
        return false, data, "github_mirror_not_configured"
    end
    if data.github.mirrored ~= true then
        return false, data, tostring(data.github.error or "github_mirror_failed")
    end
    return true, data, nil
end

local function cachePath()
    return tostring(game.PlaceId) .. "_" .. CONFIG.CACHE_FILE
end

local function saveCache(snapshot)
    if not WRITEFILE then return false, "writefile_unavailable" end
    local okEncode, text = pcall(HttpService.JSONEncode, HttpService, snapshot)
    if not okEncode then return false, tostring(text) end
    local ok, err = pcall(WRITEFILE, cachePath(), text)
    return ok, ok and nil or tostring(err)
end

local function loadCache()
    if not READFILE or not ISFILE then return nil end
    local okFile, exists = pcall(ISFILE, cachePath())
    if not okFile or not exists then return nil end
    local okRead, text = pcall(READFILE, cachePath())
    if not okRead or type(text) ~= "string" then return nil end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, text)
    if not okDecode or type(data) ~= "table" then return nil end
    return data
end

local function clearCache()
    if not DELFILE or not ISFILE then return end
    local okFile, exists = pcall(ISFILE, cachePath())
    if okFile and exists then pcall(DELFILE, cachePath()) end
end

local function makeSnapshot()
    return {
        schemaVersion = 2,
        version = CONFIG.VERSION,
        purpose = CONFIG.PURPOSE,
        runId = STATE.runId,
        capturedAt = nowIso(),
        placeId = game.PlaceId,
        gameId = game.GameId,
        placeVersion = game.PlaceVersion,
        userId = LP.UserId,
        username = LP.Name,
        startedAt = STATE.startedIso,
        finishedAt = nowIso(),
        records = STATE.records,
        remotes = STATE.remotes,
        stats = {
            records=#STATE.records,
            remotes=#STATE.remotes,
            dropped=STATE.dropped,
            inboundListeners=STATE.inboundListeners,
            valueWatchers=STATE.valueWatchers,
            outboundHook=STATE.outboundHookInstalled,
            staticDone=STATE.staticDone,
        },
    }
end

local function buildRecordBatches(records)
    local batches = {}
    local index = 1
    while index <= #records do
        local batch = {}
        local stopAt = math.min(#records, index + CONFIG.UPLOAD_RECORDS_PER_BATCH - 1)
        for i = index, stopAt do batch[#batch + 1] = records[i] end
        batches[#batches + 1] = batch
        index = stopAt + 1
    end
    return batches
end

local function buildRemoteBatches(remotes)
    local batches = {}
    local index = 1
    while index <= #remotes do
        local batch = {}
        local stopAt = math.min(#remotes, index + CONFIG.UPLOAD_REMOTES_PER_BATCH - 1)
        for i = index, stopAt do batch[#batch + 1] = remotes[i] end
        batches[#batches + 1] = batch
        index = stopAt + 1
    end
    return batches
end

local function uploadSnapshot(snapshot, statusCallback)
    if STATE.uploading then return false, "upload_already_running" end
    STATE.uploading = true

    local healthOk, health, healthErr = getJson(CONFIG.HEALTH)
    if not healthOk then
        STATE.uploading = false
        return false, "health_failed: " .. tostring(healthErr)
    end
    if type(health) ~= "table" or health.ok ~= true then
        STATE.uploading = false
        return false, "health_not_ok"
    end
    if health.githubMirrorConfigured ~= true then
        STATE.uploading = false
        return false, "github_mirror_not_configured"
    end

    local recordBatches = buildRecordBatches(snapshot.records or {})
    local remoteBatches = buildRemoteBatches(snapshot.remotes or {})
    local planned = #recordBatches + #remoteBatches + 1
    if planned > CONFIG.UPLOAD_MAX_BATCHES then
        STATE.uploading = false
        return false, "too_many_batches: " .. tostring(planned)
    end

    local batchNumber = 0
    local totalPlanned = planned

    local function sendBatch(kind, records, remotes)
        batchNumber = batchNumber + 1
        if statusCallback then
            statusCallback(string.format("Enviando %d/%d • %s", batchNumber, totalPlanned, kind))
        end

        local payload = {
            schemaVersion = 2,
            userId = tostring(snapshot.userId or LP.UserId),
            username = tostring(snapshot.username or LP.Name),
            capturedAt = snapshot.capturedAt or nowIso(),
            placeId = snapshot.placeId or game.PlaceId,
            gameId = snapshot.gameId or game.GameId,
            runId = tostring(snapshot.runId or ""),
            trace = {
                version = CONFIG.VERSION,
                purpose = CONFIG.PURPOSE,
                runId = tostring(snapshot.runId or ""),
                batchIndex = batchNumber,
                batchTotal = totalPlanned,
                batchKind = kind,
                placeVersion = snapshot.placeVersion,
                startedAt = snapshot.startedAt,
                finishedAt = snapshot.finishedAt,
                stats = snapshot.stats,
                records = records or {},
                remotes = remotes or {},
            },
        }

        local ok, data, err = postJson(CONFIG.ENDPOINT, payload)
        if not ok then return false, err end
        return true, data
    end

    for _, remotes in ipairs(remoteBatches) do
        local ok, err = sendBatch("remote_catalog", {}, remotes)
        if not ok then STATE.uploading=false return false, err end
        task.wait(0.15)
    end

    for _, records in ipairs(recordBatches) do
        local ok, err = sendBatch("records", records, {})
        if not ok then STATE.uploading=false return false, err end
        task.wait(0.15)
    end

    local manifest = {
        {
            kind="upload_manifest",
            version=CONFIG.VERSION,
            purpose=CONFIG.PURPOSE,
            runId=snapshot.runId,
            placeId=snapshot.placeId,
            gameId=snapshot.gameId,
            placeVersion=snapshot.placeVersion,
            recordsTotal=#(snapshot.records or {}),
            remotesTotal=#(snapshot.remotes or {}),
            dropped=snapshot.stats and snapshot.stats.dropped or 0,
            recordBatches=#recordBatches,
            remoteBatches=#remoteBatches,
            finishedAt=snapshot.finishedAt,
            githubMirrorRequired=true,
        }
    }

    local finalOk, finalDataOrErr = sendBatch("manifest", manifest, {})
    if not finalOk then STATE.uploading=false return false, finalDataOrErr end

    STATE.uploading = false
    clearCache()
    local latest = type(finalDataOrErr) == "table" and finalDataOrErr.latestUrl or nil
    return true, latest or "confirmed"
end

local function startStaticScans()
    task.spawn(function()
        record("scan_started", {
            placeId=game.PlaceId,
            gameId=game.GameId,
            placeVersion=game.PlaceVersion,
            services={},
        })

        local services = {}
        for _, child in ipairs(game:GetChildren()) do
            services[#services + 1] = {name=child.Name, className=child.ClassName}
        end
        record("game_services", {services=services})

        staticScanContainer(ReplicatedStorage, "ReplicatedStorage")
        if STATE.running and not STATE.stopping then staticScanContainer(Workspace, "Workspace") end
        if STATE.running and not STATE.stopping then nearbyPartScan() end
        if STATE.running and not STATE.stopping then scanTags() end
        if STATE.running and not STATE.stopping then scanPlayerState() end
        if STATE.running and not STATE.stopping then scanGui() end

        STATE.staticDone = true
        record("scan_completed", {
            records=#STATE.records,
            remotes=#STATE.remotes,
            inboundListeners=STATE.inboundListeners,
            valueWatchers=STATE.valueWatchers,
        })
    end)
end

local heartbeat = RunService.Heartbeat:Connect(function()
    if not STATE.running or STATE.stopping then return end
    local now = os.clock()
    if now - STATE.lastTrajectory >= CONFIG.TRAJECTORY_INTERVAL then
        STATE.lastTrajectory = now
        record("trajectory", {player=playerSnapshot()})
    end
end)

--==============================================================--
-- UI
--==============================================================--

local GUI_NAME = "CafeinaUniversalGameTraceV2"
local guiParent = CoreGui
pcall(function() if type(gethui) == "function" then guiParent = gethui() end end)
pcall(function()
    local old = guiParent:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
local parentOk = pcall(function() gui.Parent = guiParent end)
if not parentOk then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(286, 210)
frame.Position = UDim2.new(0.5, -143, 0.34, -105)
frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
frame.BorderSizePixel = 0
frame.Parent = gui
local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = frame
local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(54, 54, 62)
frameStroke.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(10, 8)
title.Size = UDim2.new(1, -20, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextColor3 = Color3.new(1,1,1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "CAFEINA • UNIVERSAL TRACE V2"
title.Parent = frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(10, 34)
status.Size = UDim2.new(1, -20, 0, 63)
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(195,195,204)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Text = REQUEST and "Pronto • verificando servidor..." or "Executor sem request/http_request"
status.Parent = frame

local counter = Instance.new("TextLabel")
counter.BackgroundTransparency = 1
counter.Position = UDim2.fromOffset(10, 98)
counter.Size = UDim2.new(1, -20, 0, 20)
counter.Font = Enum.Font.Code
counter.TextSize = 10
counter.TextColor3 = Color3.fromRGB(145,145,158)
counter.TextXAlignment = Enum.TextXAlignment.Left
counter.Text = "R:0  REM:0  DROP:0"
counter.Parent = frame

local mainButton = Instance.new("TextButton")
mainButton.Position = UDim2.fromOffset(10, 124)
mainButton.Size = UDim2.new(1, -20, 0, 36)
mainButton.BackgroundColor3 = Color3.fromRGB(31,31,36)
mainButton.BorderSizePixel = 0
mainButton.Font = Enum.Font.GothamBold
mainButton.TextSize = 11
mainButton.TextColor3 = Color3.new(1,1,1)
mainButton.Text = "INICIAR COLETA UNIVERSAL"
mainButton.Parent = frame
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 7)
mainCorner.Parent = mainButton

local markButton = Instance.new("TextButton")
markButton.Position = UDim2.fromOffset(10, 166)
markButton.Size = UDim2.new(1, -20, 0, 30)
markButton.BackgroundColor3 = Color3.fromRGB(22,22,27)
markButton.BorderSizePixel = 0
markButton.Font = Enum.Font.GothamBold
markButton.TextSize = 10
markButton.TextColor3 = Color3.fromRGB(210,210,218)
markButton.Text = "MARCAR AÇÃO AGORA"
markButton.Parent = frame
local markCorner = Instance.new("UICorner")
markCorner.CornerRadius = UDim.new(0, 7)
markCorner.Parent = markButton

local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

local function setStatus(text)
    status.Text = tostring(text or "")
end

local function updateCounter()
    counter.Text = string.format(
        "R:%d  REM:%d  DROP:%d",
        #STATE.records,
        #STATE.remotes,
        STATE.dropped
    )
end

task.spawn(function()
    while gui.Parent do
        updateCounter()
        task.wait(CONFIG.COUNTER_REFRESH)
    end
end)

local function resetStateForRun()
    STATE.running = true
    STATE.stopping = false
    STATE.uploading = false
    STATE.runId = HttpService:GenerateGUID(false)
    STATE.startedClock = os.clock()
    STATE.startedIso = nowIso()
    STATE.records = {}
    STATE.remotes = {}
    STATE.remoteSeen = {}
    STATE.dropped = 0
    STATE.staticDone = false
    STATE.lastTrajectory = 0
end

local function beginSession()
    if STATE.running or STATE.uploading then return end
    if not REQUEST then
        setStatus("Falha: executor sem request/http_request")
        return
    end

    resetStateForRun()
    local hookAvailable = installOutboundObserver()
    installRuntimeWatchers()

    record("session_started", {
        version=CONFIG.VERSION,
        purpose=CONFIG.PURPOSE,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        capabilities={
            request=REQUEST ~= nil,
            writefile=WRITEFILE ~= nil,
            readfile=READFILE ~= nil,
            outboundObserver=hookAvailable,
        },
        player=playerSnapshot(),
    })

    startStaticScans()
    mainButton.Text = "ENCERRAR + ENVIAR"
    mainButton.BackgroundColor3 = Color3.fromRGB(157,42,48)
    setStatus("Coletando universalmente • jogue e use as funções normalmente")
end

local function finishAndUpload()
    if not STATE.running or STATE.uploading then return end

    record("session_finalized", {
        records=#STATE.records,
        remotes=#STATE.remotes,
        dropped=STATE.dropped,
        staticDone=STATE.staticDone,
        player=playerSnapshot(),
    })

    STATE.stopping = true
    STATE.running = false
    disconnectAll()

    local snapshot = makeSnapshot()
    saveCache(snapshot)

    mainButton.Text = "ENVIANDO..."
    mainButton.BackgroundColor3 = Color3.fromRGB(31,31,36)
    setStatus("Dados preservados localmente • verificando servidor...")

    task.spawn(function()
        local ok, result = uploadSnapshot(snapshot, setStatus)
        if ok then
            setStatus("GitHub confirmado ✓\nrunId: " .. tostring(snapshot.runId))
            mainButton.Text = "INICIAR NOVA COLETA"
            STATE.records = {}
            STATE.remotes = {}
        else
            setStatus("Falha no envio • dados mantidos\n" .. tostring(result))
            mainButton.Text = "REENVIAR DADOS"
        end
    end)
end

local function retryPending()
    if STATE.uploading then return end
    local cached = loadCache()
    if not cached then
        setStatus("Nenhuma coleta pendente encontrada")
        mainButton.Text = "INICIAR COLETA UNIVERSAL"
        return
    end

    mainButton.Text = "REENVIANDO..."
    setStatus("Reenviando coleta preservada...")
    task.spawn(function()
        local ok, result = uploadSnapshot(cached, setStatus)
        if ok then
            setStatus("GitHub confirmado ✓\nrunId: " .. tostring(cached.runId))
            mainButton.Text = "INICIAR NOVA COLETA"
        else
            setStatus("Falha no reenvio • dados continuam salvos\n" .. tostring(result))
            mainButton.Text = "REENVIAR DADOS"
        end
    end)
end

markButton.Activated:Connect(function()
    if not STATE.running or STATE.stopping then
        setStatus("Inicie a coleta antes de marcar uma ação")
        return
    end
    record("manual_action_marker", {
        player=playerSnapshot(),
        note="user_pressed_marker",
        recordsBefore=#STATE.records,
    })
    setStatus("Ação marcada ✓ • faça a ação no jogo agora")
end)

mainButton.Activated:Connect(function()
    if STATE.uploading then return end
    if mainButton.Text == "REENVIAR DADOS" then
        retryPending()
    elseif STATE.running then
        finishAndUpload()
    else
        beginSession()
    end
end)

local cachedAtBoot = loadCache()
if cachedAtBoot then
    mainButton.Text = "REENVIAR DADOS"
    setStatus("Existe uma coleta pendente salva • toque para reenviar")
else
    task.spawn(function()
        if not REQUEST then return end
        local ok, data, err = getJson(CONFIG.HEALTH)
        if ok and type(data) == "table" and data.ok == true then
            if data.githubMirrorConfigured == true then
                setStatus("Servidor + GitHub prontos ✓\nInicie a coleta e jogue normalmente")
            else
                setStatus("Servidor online • GitHub mirror não configurado")
            end
        else
            setStatus("Servidor indisponível agora\n" .. tostring(err))
        end
    end)
end

ENV.__CAFEINA_UNIVERSAL_TRACE_V2 = {
    Gui = gui,
    State = STATE,
    Config = CONFIG,
    Mark = function(label)
        if STATE.running and not STATE.stopping then
            record("external_marker", {label=tostring(label or "marker"), player=playerSnapshot()})
        end
    end,
    Stop = function()
        STATE.stopping = true
        STATE.running = false
        disconnectAll()
        pcall(function() heartbeat:Disconnect() end)
        pcall(function() gui:Destroy() end)
    end,
}

gui.Destroying:Connect(function()
    STATE.stopping = true
    STATE.running = false
    disconnectAll()
    pcall(function() heartbeat:Disconnect() end)
end)

print("[CAFEINA] UNIVERSAL GAME TRACE V2 carregado • sem filtro por palavras-chave")
