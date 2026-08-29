--==============================================================--
-- CAFEÍNA • SCAMTEST CONTÍNUO V4
-- CLIENT-VISIBLE ONLY
--
-- 3 BOTÕES:
-- 1) SCAM CONTÍNUO
-- 2) PARAR ANÁLISE
-- 3) ENVIAR AO SERVIDOR
--
-- Coleta continuamente até:
-- • usuário parar
-- • atingir o limite seguro de envio
--
-- Diagnóstico:
-- • script = Scamtest.lua
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "V4",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    UPLOAD_TOKEN = "",

    DIAGNOSTIC_SCRIPT = "Scamtest.lua",
    DIAGNOSTIC_VERSION = "4.0",
    DIAGNOSTIC_URL =
        "https://cafe-na-ia.onrender.com/api/runtime-diagnostics",

    -- servidor aceita 300 MB finais; usamos margem segura
    SAFE_UPLOAD_BYTES = 250 * 1024 * 1024,

    TARGET_CHUNK_BYTES = 3200000,
    MAX_OBJECTS_PER_PASS = 40000,

    YIELD_EVERY = 120,
    PASS_DELAY = 0.35,

    RETRIES = 3,
    RETRY_DELAY = 1.25,
    REQUEST_TIMEOUT = 75,

    DIAGNOSTIC_HEARTBEAT = 20,

    SERVICES = {
        "Workspace",
        "ReplicatedStorage",
        "ReplicatedFirst",
        "Players",
        "Lighting",
        "StarterGui",
        "StarterPlayer",
        "Teams",
        "SoundService",
    },
}

--==============================================================--
-- HTTP
--==============================================================--

local ExecutorRequest =
    (typeof(request) == "function" and request)
    or (typeof(http_request) == "function" and http_request)
    or (
        syn
        and typeof(syn.request) == "function"
        and syn.request
    )
    or (
        http
        and typeof(http.request) == "function"
        and http.request
    )
    or nil

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Scanning = false,
    Uploading = false,
    StopRequested = false,

    ScanComplete = false,
    AutoStoppedByLimit = false,

    UploadId = nil,
    LastURL = "",

    Pass = 0,
    ObjectsSeen = 0,
    RecordsStored = 0,

    ApproxBytes = 0,
    ChunksSent = 0,
    BytesSent = 0,

    StartedAtClock = 0,

    Records = {},
}

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {
    BG = Color3.fromRGB(10, 11, 14),
    PANEL = Color3.fromRGB(18, 20, 25),
    PANEL2 = Color3.fromRGB(27, 30, 38),

    TEXT = Color3.fromRGB(246, 247, 250),
    SUB = Color3.fromRGB(155, 160, 175),

    RED = Color3.fromRGB(235, 42, 58),
    RED_DARK = Color3.fromRGB(112, 23, 34),

    GREEN = Color3.fromRGB(65, 210, 118),
    YELLOW = Color3.fromRGB(244, 190, 65),
    ORANGE = Color3.fromRGB(245, 132, 56),

    STROKE = Color3.fromRGB(52, 57, 70),
}

--==============================================================--
-- HELPERS
--==============================================================--

local function safeFullName(inst)
    local ok, value = pcall(function()
        return inst:GetFullName()
    end)

    if ok and value then
        return tostring(value)
    end

    return tostring(inst.Name)
end

local function safeGet(obj, key)
    local ok, value = pcall(function()
        return obj[key]
    end)

    if ok then
        return value
    end

    return nil
end

local function safeAttributes(inst)
    local result = {}

    local ok, attributes = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attributes) ~= "table" then
        return result
    end

    for key, value in pairs(attributes) do
        local kind = typeof(value)

        if
            kind == "string"
            or kind == "number"
            or kind == "boolean"
        then
            result[tostring(key)] = value
        else
            result[tostring(key)] = tostring(value)
        end
    end

    return result
end

local function vector3(value)
    if typeof(value) ~= "Vector3" then
        return tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
    }
end

local function vector2(value)
    if typeof(value) ~= "Vector2" then
        return tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
    }
end

local function udim2(value)
    if typeof(value) ~= "UDim2" then
        return tostring(value)
    end

    return {
        xScale = value.X.Scale,
        xOffset = value.X.Offset,
        yScale = value.Y.Scale,
        yOffset = value.Y.Offset,
    }
end

local function color3(value)
    if typeof(value) ~= "Color3" then
        return tostring(value)
    end

    return {
        r = value.R,
        g = value.G,
        b = value.B,
    }
end

local function cframe(value)
    if typeof(value) ~= "CFrame" then
        return tostring(value)
    end

    return { value:GetComponents() }
end

local function formatBytes(bytes)
    bytes = tonumber(bytes) or 0

    if bytes >= 1024 * 1024 * 1024 then
        return string.format(
            "%.2f GB",
            bytes / (1024 * 1024 * 1024)
        )
    end

    if bytes >= 1024 * 1024 then
        return string.format(
            "%.2f MB",
            bytes / (1024 * 1024)
        )
    end

    if bytes >= 1024 then
        return string.format(
            "%.1f KB",
            bytes / 1024
        )
    end

    return tostring(bytes) .. " B"
end

local function sanitizeFileName(text)
    local name = tostring(text or "scan")

    name = name:gsub("[\\/:*?\"<>|]", "_")
    name = name:gsub("%s+", "_")

    if name == "" then
        name = "scan"
    end

    return name
end

local function withToken(payload)
    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token = CONFIG.UPLOAD_TOKEN
    end

    return payload
end

--==============================================================--
-- DIAGNOSTIC
--==============================================================--

local Diagnostic = {
    RunId = nil,
    Heartbeat = false,

    Report = {
        script = CONFIG.DIAGNOSTIC_SCRIPT,
        version = CONFIG.DIAGNOSTIC_VERSION,

        runId = nil,
        status = "idle",
        phase = "idle",

        startedAt = nil,
        finishedAt = nil,

        message = "",

        steps = {},
        errors = {},
        counters = {},

        environment = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
            placeVersion = game.PlaceVersion,
        },
    },
}

local function diagnosticRunId()
    local ok, value = pcall(function()
        return HttpService:GenerateGUID(false)
    end)

    if ok and value then
        return value
    end

    return
        "run_"
        .. tostring(os.time())
        .. "_"
        .. tostring(math.random(100000, 999999))
end

local function diagnosticCopy(value, depth)
    depth = tonumber(depth) or 0

    if depth > 7 then
        return "[depth-limit]"
    end

    if type(value) ~= "table" then
        local kind = typeof(value)

        if
            kind == "string"
            or kind == "number"
            or kind == "boolean"
        then
            return value
        end

        return tostring(value)
    end

    local output = {}

    for key, child in pairs(value) do
        output[tostring(key)] =
            diagnosticCopy(child, depth + 1)
    end

    return output
end

function Diagnostic.sync()
    local c = Diagnostic.Report.counters

    c.pass = State.Pass
    c.objectsSeen = State.ObjectsSeen
    c.recordsStored = State.RecordsStored
    c.approxBytes = State.ApproxBytes
    c.safeLimitBytes = CONFIG.SAFE_UPLOAD_BYTES
    c.chunksSent = State.ChunksSent
    c.bytesSent = State.BytesSent
end

function Diagnostic.send()
    if not ExecutorRequest or not Diagnostic.RunId then
        return
    end

    Diagnostic.sync()

    local payload = {
        script = CONFIG.DIAGNOSTIC_SCRIPT,
        runId = Diagnostic.RunId,
        report = diagnosticCopy(Diagnostic.Report),
    }

    task.spawn(function()
        pcall(function()
            ExecutorRequest({
                Url = CONFIG.DIAGNOSTIC_URL,
                Method = "POST",

                Headers = {
                    ["Content-Type"] =
                        "application/json",
                    ["Accept"] =
                        "application/json",
                },

                Body =
                    HttpService:JSONEncode(payload),
            })
        end)
    end)
end

function Diagnostic.start()
    Diagnostic.RunId =
        diagnosticRunId()

    Diagnostic.Report.runId =
        Diagnostic.RunId

    Diagnostic.Report.status =
        "running"

    Diagnostic.Report.phase =
        "menu_ready"

    Diagnostic.Report.startedAt =
        os.time()

    Diagnostic.Report.message =
        "Scamtest.lua iniciado"

    Diagnostic.send()

    if Diagnostic.Heartbeat then
        return
    end

    Diagnostic.Heartbeat = true

    task.spawn(function()
        while Diagnostic.Heartbeat do
            task.wait(CONFIG.DIAGNOSTIC_HEARTBEAT)

            if
                Diagnostic.Report.status
                ~= "running"
            then
                break
            end

            Diagnostic.send()
        end
    end)
end

function Diagnostic.step(phase, message, extra)
    Diagnostic.Report.status = "running"
    Diagnostic.Report.phase = tostring(phase or "unknown")
    Diagnostic.Report.message = tostring(message or "")

    local item = {
        phase = Diagnostic.Report.phase,
        message = Diagnostic.Report.message,
        time = os.time(),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            item[tostring(key)] =
                diagnosticCopy(value)
        end
    end

    table.insert(
        Diagnostic.Report.steps,
        item
    )

    Diagnostic.send()
end

function Diagnostic.error(phase, err)
    local message =
        tostring(err or "Erro desconhecido")

    local trace = nil

    pcall(function()
        if
            debug
            and typeof(debug.traceback)
            == "function"
        then
            trace = debug.traceback(
                message,
                2
            )
        end
    end)

    Diagnostic.Report.status = "error"
    Diagnostic.Report.phase = tostring(phase or "unknown")
    Diagnostic.Report.message = message
    Diagnostic.Report.finishedAt = os.time()

    table.insert(
        Diagnostic.Report.errors,
        {
            phase = Diagnostic.Report.phase,
            message = message,
            traceback = trace,
            time = os.time(),
        }
    )

    Diagnostic.send()
end

function Diagnostic.interrupted(message)
    Diagnostic.Report.status =
        "interrupted"

    Diagnostic.Report.phase =
        "interrupted"

    Diagnostic.Report.message =
        tostring(message or "Interrompido")

    Diagnostic.Report.finishedAt =
        os.time()

    Diagnostic.send()
end

--==============================================================--
-- SERIALIZE
--==============================================================--

local function serializeInstance(
    inst,
    serviceName,
    passNumber
)
    local attributes = safeAttributes(inst)

    local data = {
        recordType = "instance_snapshot",

        pass = passNumber,
        capturedAtUnix = os.time(),

        service = serviceName,

        name = tostring(inst.Name),
        className = tostring(inst.ClassName),
        path = safeFullName(inst),

        parentPath =
            inst.Parent
            and safeFullName(inst.Parent)
            or nil,

        attributes = attributes,
    }

    pcall(function()
        data.childCount =
            #inst:GetChildren()
    end)

    if inst:IsA("ValueBase") then
        local value = safeGet(inst, "Value")
        local kind = typeof(value)

        if
            kind == "string"
            or kind == "number"
            or kind == "boolean"
        then
            data.value = value
        else
            data.value = tostring(value)
        end
    end

    if inst:IsA("BasePart") then
        data.properties = {
            anchored =
                safeGet(inst, "Anchored"),

            canCollide =
                safeGet(inst, "CanCollide"),

            canTouch =
                safeGet(inst, "CanTouch"),

            canQuery =
                safeGet(inst, "CanQuery"),

            transparency =
                safeGet(inst, "Transparency"),

            position =
                vector3(
                    safeGet(inst, "Position")
                ),

            size =
                vector3(
                    safeGet(inst, "Size")
                ),

            cframe =
                cframe(
                    safeGet(inst, "CFrame")
                ),

            material =
                tostring(
                    safeGet(inst, "Material")
                    or ""
                ),

            color =
                color3(
                    safeGet(inst, "Color")
                ),
        }
    end

    if inst:IsA("GuiObject") then
        data.gui = {
            visible =
                safeGet(inst, "Visible"),

            active =
                safeGet(inst, "Active"),

            position =
                udim2(
                    safeGet(inst, "Position")
                ),

            size =
                udim2(
                    safeGet(inst, "Size")
                ),

            anchorPoint =
                vector2(
                    safeGet(inst, "AnchorPoint")
                ),
        }

        if
            inst:IsA("TextLabel")
            or inst:IsA("TextButton")
            or inst:IsA("TextBox")
        then
            data.gui.text =
                tostring(
                    safeGet(inst, "Text")
                    or ""
                )
        end
    end

    local isRemote =
        inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")

    pcall(function()
        if inst:IsA("UnreliableRemoteEvent") then
            isRemote = true
        end
    end)

    if isRemote then
        data.remote = {
            type = tostring(inst.ClassName),
            path = safeFullName(inst),
        }
    end

    if inst:IsA("LuaSourceContainer") then
        data.script = {
            type = tostring(inst.ClassName),
            path = safeFullName(inst),
            disabled =
                safeGet(inst, "Disabled"),
        }
    end

    if inst:IsA("Player") then
        local team = safeGet(inst, "Team")

        data.player = {
            displayName =
                tostring(
                    safeGet(inst, "DisplayName")
                    or ""
                ),

            userId =
                safeGet(inst, "UserId"),

            accountAge =
                safeGet(inst, "AccountAge"),

            team =
                team
                and tostring(team.Name)
                or nil,
        }
    end

    if inst:IsA("Sound") then
        data.media = {
            soundId =
                tostring(
                    safeGet(inst, "SoundId")
                    or ""
                ),

            volume =
                safeGet(inst, "Volume"),

            looped =
                safeGet(inst, "Looped"),
        }
    end

    if
        inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        data.media = {
            texture =
                tostring(
                    safeGet(inst, "Texture")
                    or ""
                ),
        }
    end

    return data
end

--==============================================================--
-- RECORD STORAGE
--==============================================================--

local function appendRecord(record)
    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            record
        )

    if not ok then
        return false
    end

    local size =
        #encoded + 1

    -- Não deixa passar do teto seguro.
    if
        State.ApproxBytes + size
        >= CONFIG.SAFE_UPLOAD_BYTES
    then
        State.AutoStoppedByLimit = true
        State.StopRequested = true
        return false
    end

    State.Records[
        #State.Records + 1
    ] = record

    State.RecordsStored += 1
    State.ApproxBytes += size

    return true
end

--==============================================================--
-- HTTP HELPERS
--==============================================================--

local function decodeResponse(response)
    if type(response) == "string" then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(
                response
            )
        end)

        return ok and decoded or nil
    end

    if type(response) ~= "table" then
        return nil
    end

    local body =
        response.Body
        or response.body
        or response.ResponseBody

    if type(body) ~= "string" then
        return nil
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    return ok and decoded or nil
end

local function rawRequest(url, payload)
    local body =
        HttpService:JSONEncode(payload)

    if ExecutorRequest then
        local ok, response = pcall(function()
            return ExecutorRequest({
                Url = url,
                Method = "POST",

                Headers = {
                    ["Content-Type"] =
                        "application/json",

                    ["Accept"] =
                        "application/json",
                },

                Body = body,
            })
        end)

        if not ok then
            return false, tostring(response)
        end

        local statusCode =
            type(response) == "table"
            and tonumber(
                response.StatusCode
                or response.Status
                or response.status
            )
            or nil

        local decoded =
            decodeResponse(response)

        if
            statusCode
            and statusCode >= 400
        then
            return false,
                decoded
                and (
                    decoded.message
                    or decoded.error
                )
                or (
                    "HTTP "
                    .. tostring(statusCode)
                )
        end

        if not decoded then
            return false,
                "Resposta inválida do servidor"
        end

        return true, decoded
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",

            Headers = {
                ["Content-Type"] =
                    "application/json",

                ["Accept"] =
                    "application/json",
            },

            Body = body,
        })
    end)

    if not ok then
        return false, tostring(response)
    end

    local decoded =
        decodeResponse(response)

    if not response.Success then
        return false,
            decoded
            and (
                decoded.message
                or decoded.error
            )
            or (
                "HTTP "
                .. tostring(
                    response.StatusCode
                )
            )
    end

    return true, decoded
end

local function requestWithTimeout(
    url,
    payload
)
    local finished = false
    local requestOk = false
    local requestResult = nil

    task.spawn(function()
        requestOk, requestResult =
            rawRequest(
                url,
                payload
            )

        finished = true
    end)

    local started = os.clock()

    while not finished do
        if
            State.StopRequested
            and not State.Uploading
        then
            return false, "Cancelado"
        end

        if
            os.clock() - started
            >= CONFIG.REQUEST_TIMEOUT
        then
            return false,
                "Tempo limite excedido"
        end

        task.wait(0.1)
    end

    return requestOk, requestResult
end

local function requestRetry(
    url,
    payload,
    label,
    statusFn
)
    local lastError =
        "Falha desconhecida"

    for attempt = 1, CONFIG.RETRIES do
        local ok, result =
            requestWithTimeout(
                url,
                payload
            )

        if ok then
            return true, result
        end

        lastError = tostring(result)

        if attempt < CONFIG.RETRIES then
            if statusFn then
                statusFn(
                    label
                    .. " • tentativa "
                    .. tostring(attempt + 1),
                    COLORS.YELLOW
                )
            end

            task.wait(
                CONFIG.RETRY_DELAY
                * attempt
            )
        end
    end

    return false, lastError
end

--==============================================================--
-- GUI
--==============================================================--

local function create(className, props)
    local object =
        Instance.new(className)

    for key, value
        in pairs(props or {})
    do
        object[key] = value
    end

    return object
end

local function corner(parent, radius)
    return create(
        "UICorner",
        {
            CornerRadius =
                UDim.new(
                    0,
                    radius or 10
                ),

            Parent = parent,
        }
    )
end

local function stroke(parent)
    return create(
        "UIStroke",
        {
            Color = COLORS.STROKE,
            Thickness = 1,
            Parent = parent,
        }
    )
end

local GuiParent = nil

if typeof(gethui) == "function" then
    local ok, result = pcall(gethui)

    if ok then
        GuiParent = result
    end
end

local Gui =
    create(
        "ScreenGui",
        {
            Name =
                "CafeinaScamContinuoV4",

            ResetOnSpawn = false,
            IgnoreGuiInset = true,

            ZIndexBehavior =
                Enum.ZIndexBehavior.Sibling,
        }
    )

local parented = false

if GuiParent then
    parented = pcall(function()
        Gui.Parent = GuiParent
    end)
end

if not parented then
    parented = pcall(function()
        Gui.Parent = CoreGui
    end)
end

if not parented then
    Gui.Parent =
        LocalPlayer:WaitForChild(
            "PlayerGui"
        )
end

for _, child
    in ipairs(Gui.Parent:GetChildren())
do
    if
        child ~= Gui
        and child.Name
        == "CafeinaScamContinuoV4"
    then
        child:Destroy()
    end
end

local Main =
    create(
        "Frame",
        {
            Size =
                UDim2.fromOffset(
                    330,
                    285
                ),

            AnchorPoint =
                Vector2.new(
                    0.5,
                    0.5
                ),

            Position =
                UDim2.fromScale(
                    0.5,
                    0.5
                ),

            BackgroundColor3 =
                COLORS.BG,

            BorderSizePixel = 0,
            Parent = Gui,
        }
    )

corner(Main, 14)
stroke(Main)

local Header =
    create(
        "Frame",
        {
            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    58
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel = 0,
            Parent = Main,
        }
    )

corner(Header, 14)

create(
    "TextLabel",
    {
        Position =
            UDim2.fromOffset(
                14,
                7
            ),

        Size =
            UDim2.new(
                1,
                -28,
                0,
                24
            ),

        BackgroundTransparency = 1,

        Text =
            "CAFEÍNA • SCAM CONTÍNUO",

        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamBold,
        TextSize = 15,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent = Header,
    }
)

create(
    "TextLabel",
    {
        Position =
            UDim2.fromOffset(
                14,
                31
            ),

        Size =
            UDim2.new(
                1,
                -28,
                0,
                17
            ),

        BackgroundTransparency = 1,

        Text =
            "Scamtest.lua • coleta até o limite seguro",

        TextColor3 = COLORS.SUB,
        Font = Enum.Font.Gotham,
        TextSize = 9,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent = Header,
    }
)

local Status =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    14,
                    72
                ),

            Size =
                UDim2.new(
                    1,
                    -28,
                    0,
                    22
                ),

            BackgroundTransparency = 1,

            Text =
                "Pronto para iniciar",

            TextColor3 = COLORS.TEXT,
            Font = Enum.Font.GothamBold,
            TextSize = 11,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent = Main,
        }
    )

local Details =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    14,
                    96
                ),

            Size =
                UDim2.new(
                    1,
                    -28,
                    0,
                    38
                ),

            BackgroundTransparency = 1,

            Text =
                "0 registros • 0 B / "
                .. formatBytes(
                    CONFIG.SAFE_UPLOAD_BYTES
                ),

            TextWrapped = true,
            TextColor3 = COLORS.SUB,

            Font = Enum.Font.Gotham,
            TextSize = 9,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent = Main,
        }
    )

local ProgressBG =
    create(
        "Frame",
        {
            Position =
                UDim2.fromOffset(
                    14,
                    137
                ),

            Size =
                UDim2.new(
                    1,
                    -28,
                    0,
                    7
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel = 0,
            Parent = Main,
        }
    )

corner(ProgressBG, 99)

local ProgressFill =
    create(
        "Frame",
        {
            Size =
                UDim2.new(
                    0,
                    0,
                    1,
                    0
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel = 0,
            Parent = ProgressBG,
        }
    )

corner(ProgressFill, 99)

local function makeButton(
    text,
    y,
    color
)
    local button =
        create(
            "TextButton",
            {
                Position =
                    UDim2.fromOffset(
                        14,
                        y
                    ),

                Size =
                    UDim2.new(
                        1,
                        -28,
                        0,
                        36
                    ),

                BackgroundColor3 =
                    color,

                BorderSizePixel = 0,

                Text = text,
                TextColor3 = COLORS.TEXT,

                Font =
                    Enum.Font.GothamBold,

                TextSize = 10,

                Parent = Main,
            }
        )

    corner(button, 9)

    return button
end

local ScanButton =
    makeButton(
        "SCAM CONTÍNUO",
        160,
        COLORS.RED
    )

local StopButton =
    makeButton(
        "PARAR ANÁLISE",
        202,
        COLORS.RED_DARK
    )

local UploadButton =
    makeButton(
        "ENVIAR AO SERVIDOR",
        244,
        COLORS.PANEL2
    )

--==============================================================--
-- UI UPDATE
--==============================================================--

local function setStatus(text, color)
    Status.Text = tostring(text or "")

    if color then
        Status.TextColor3 = color
    else
        Status.TextColor3 = COLORS.TEXT
    end
end

local function setProgress(value)
    value =
        math.clamp(
            tonumber(value) or 0,
            0,
            1
        )

    TweenService:Create(
        ProgressFill,
        TweenInfo.new(0.12),
        {
            Size =
                UDim2.new(
                    value,
                    0,
                    1,
                    0
                )
        }
    ):Play()
end

local function updateDetails()
    local percent =
        CONFIG.SAFE_UPLOAD_BYTES > 0
        and (
            State.ApproxBytes
            / CONFIG.SAFE_UPLOAD_BYTES
        )
        or 0

    Details.Text =
        tostring(State.RecordsStored)
        .. " registros • passe "
        .. tostring(State.Pass)
        .. "\n"
        .. formatBytes(State.ApproxBytes)
        .. " / "
        .. formatBytes(
            CONFIG.SAFE_UPLOAD_BYTES
        )

    setProgress(percent)
end

--==============================================================--
-- CONTINUOUS SCAN
--==============================================================--

local function resetScan()
    State.StopRequested = false
    State.ScanComplete = false
    State.AutoStoppedByLimit = false

    State.Pass = 0
    State.ObjectsSeen = 0
    State.RecordsStored = 0

    State.ApproxBytes = 0

    State.ChunksSent = 0
    State.BytesSent = 0

    State.UploadId = nil
    State.LastURL = ""

    State.Records = {}

    updateDetails()
end

local function runContinuousScan()
    if State.Scanning or State.Uploading then
        return
    end

    resetScan()

    State.Scanning = true
    State.StartedAtClock = os.clock()

    Diagnostic.step(
        "scan_start",
        "Coleta contínua iniciada"
    )

    ScanButton.Text =
        "SCAM EM EXECUÇÃO..."

    setStatus(
        "Coletando continuamente...",
        COLORS.YELLOW
    )

    while
        not State.StopRequested
        and State.ApproxBytes
        < CONFIG.SAFE_UPLOAD_BYTES
    do
        State.Pass += 1

        Diagnostic.step(
            "scan_pass",
            "Iniciando passe "
            .. tostring(State.Pass),
            {
                pass = State.Pass,
            }
        )

        local objectsThisPass = 0

        for _, serviceName
            in ipairs(CONFIG.SERVICES)
        do
            if State.StopRequested then
                break
            end

            if
                State.ApproxBytes
                >= CONFIG.SAFE_UPLOAD_BYTES
            then
                break
            end

            setStatus(
                "Passe "
                .. tostring(State.Pass)
                .. " • "
                .. serviceName,
                COLORS.YELLOW
            )

            local okService, service =
                pcall(function()
                    return game:GetService(
                        serviceName
                    )
                end)

            if okService and service then
                local descendants = {}

                pcall(function()
                    descendants =
                        service:GetDescendants()
                end)

                for index, inst
                    in ipairs(descendants)
                do
                    if State.StopRequested then
                        break
                    end

                    if
                        State.ApproxBytes
                        >= CONFIG.SAFE_UPLOAD_BYTES
                    then
                        State.AutoStoppedByLimit = true
                        State.StopRequested = true
                        break
                    end

                    if
                        objectsThisPass
                        >= CONFIG.MAX_OBJECTS_PER_PASS
                    then
                        break
                    end

                    State.ObjectsSeen += 1
                    objectsThisPass += 1

                    local okRecord, record =
                        pcall(
                            serializeInstance,
                            inst,
                            serviceName,
                            State.Pass
                        )

                    if
                        okRecord
                        and type(record)
                        == "table"
                    then
                        local stored =
                            appendRecord(record)

                        if not stored
                            and State.AutoStoppedByLimit
                        then
                            break
                        end
                    end

                    if
                        index
                        % CONFIG.YIELD_EVERY
                        == 0
                    then
                        updateDetails()
                        task.wait()
                    end
                end
            end

            updateDetails()
            task.wait()
        end

        Diagnostic.step(
            "scan_pass_complete",
            "Passe concluído",
            {
                pass = State.Pass,
                objectsThisPass =
                    objectsThisPass,
                recordsStored =
                    State.RecordsStored,
                approxBytes =
                    State.ApproxBytes,
            }
        )

        updateDetails()

        if
            not State.StopRequested
            and State.ApproxBytes
            < CONFIG.SAFE_UPLOAD_BYTES
        then
            task.wait(CONFIG.PASS_DELAY)
        end
    end

    State.Scanning = false
    State.ScanComplete = true

    ScanButton.Text =
        "SCAM CONTÍNUO"

    updateDetails()

    if State.AutoStoppedByLimit then
        setStatus(
            "Limite seguro atingido • pronto para enviar",
            COLORS.GREEN
        )

        Diagnostic.step(
            "scan_limit_reached",
            "Limite seguro de coleta atingido",
            {
                bytes =
                    State.ApproxBytes,

                records =
                    State.RecordsStored,
            }
        )
    else
        setStatus(
            "Análise parada • pronto para enviar",
            COLORS.ORANGE
        )

        Diagnostic.step(
            "scan_stopped",
            "Análise interrompida pelo usuário",
            {
                bytes =
                    State.ApproxBytes,

                records =
                    State.RecordsStored,
            }
        )
    end
end

--==============================================================--
-- UPLOAD
--==============================================================--

local function cancelRemoteUpload()
    if not State.UploadId then
        return
    end

    task.spawn(function()
        pcall(function()
            rawRequest(
                CONFIG.UPLOAD_BASE
                .. "/cancel",

                withToken({
                    uploadId =
                        State.UploadId,
                })
            )
        end)
    end)
end

local function uploadAll()
    if State.Scanning then
        return false,
            "Pare a análise antes de enviar"
    end

    if State.Uploading then
        return false,
            "Upload já está em andamento"
    end

    if
        type(State.Records)
        ~= "table"
        or #State.Records < 1
    then
        return false,
            "Nenhum dado coletado"
    end

    State.Uploading = true
    State.StopRequested = false

    State.UploadId = nil
    State.ChunksSent = 0
    State.BytesSent = 0

    setStatus(
        "Preparando envio...",
        COLORS.YELLOW
    )

    Diagnostic.step(
        "upload_start",
        "Upload iniciado",
        {
            records =
                #State.Records,

            approxBytes =
                State.ApproxBytes,
        }
    )

    local timestamp =
        os.date(
            "!%Y%m%d_%H%M%S"
        )

    local filename =
        sanitizeFileName(
            "Cafeina_Completo_"
            .. tostring(game.PlaceId)
            .. "_"
            .. timestamp
            .. ".json"
        )

    local startOk, startResult =
        requestRetry(
            CONFIG.UPLOAD_BASE
            .. "/start",

            withToken({
                filename = filename,

                source =
                    "cafeina-continuous-scam",

                metadata = {
                    area = "Completo",

                    recordCount =
                        #State.Records,

                    clientVisibleOnly =
                        true,

                    scannerVersion =
                        CONFIG.VERSION,

                    passes =
                        State.Pass,

                    approxBytes =
                        State.ApproxBytes,
                }
            }),

            "Abrindo upload",
            setStatus
        )

    if
        not startOk
        or type(startResult)
        ~= "table"
        or not startResult.uploadId
    then
        State.Uploading = false

        Diagnostic.error(
            "upload_start",
            startResult
            or "uploadId não retornado"
        )

        return false,
            startResult
            or "uploadId não retornado"
    end

    State.UploadId =
        tostring(
            startResult.uploadId
        )

    local chunk = {}
    local chunkBytes = 2

    local function flushChunk()
        if #chunk == 0 then
            return true
        end

        local chunkIndex =
            State.ChunksSent + 1

        setStatus(
            "Enviando parte "
            .. tostring(chunkIndex)
            .. "...",
            COLORS.YELLOW
        )

        local encodeOk, encoded =
            pcall(function()
                return HttpService:JSONEncode(
                    chunk
                )
            end)

        if not encodeOk then
            return false,
                "Erro ao codificar chunk"
        end

        local ok, result =
            requestRetry(
                CONFIG.UPLOAD_BASE
                .. "/chunk",

                withToken({
                    uploadId =
                        State.UploadId,

                    index =
                        chunkIndex,

                    objects =
                        chunk,
                }),

                "Enviando parte "
                .. tostring(chunkIndex),

                setStatus
            )

        if not ok then
            return false, result
        end

        State.ChunksSent =
            chunkIndex

        State.BytesSent +=
            #encoded

        Diagnostic.step(
            "upload_chunk",
            "Chunk enviado",
            {
                chunk =
                    chunkIndex,

                bytes =
                    #encoded,
            }
        )

        chunk = {}
        chunkBytes = 2

        return true
    end

    -- Header
    chunk[1] = {
        recordType =
            "continuous_scan_header",

        scanner =
            "CAFEINA",

        version =
            CONFIG.VERSION,

        clientVisibleOnly =
            true,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        jobId =
            game.JobId,

        passes =
            State.Pass,

        records =
            State.RecordsStored,

        approxBytes =
            State.ApproxBytes,

        generatedAtUnix =
            os.time(),
    }

    for index, record
        in ipairs(State.Records)
    do
        local encodeOk, encoded =
            pcall(function()
                return HttpService:JSONEncode(
                    record
                )
            end)

        if encodeOk then
            local recordBytes =
                #encoded + 1

            if
                chunkBytes
                + recordBytes
                > CONFIG.TARGET_CHUNK_BYTES
                and #chunk > 0
            then
                local ok, err =
                    flushChunk()

                if not ok then
                    cancelRemoteUpload()

                    State.Uploading =
                        false

                    Diagnostic.error(
                        "upload_chunk",
                        err
                    )

                    return false, err
                end
            end

            chunk[
                #chunk + 1
            ] = record

            chunkBytes +=
                recordBytes
        end

        if index % 100 == 0 then
            local pct =
                0.05
                + (
                    index
                    / #State.Records
                )
                * 0.88

            setProgress(pct)
            updateDetails()

            task.wait()
        end
    end

    local flushOk, flushErr =
        flushChunk()

    if not flushOk then
        cancelRemoteUpload()

        State.Uploading = false

        Diagnostic.error(
            "upload_chunk",
            flushErr
        )

        return false, flushErr
    end

    setStatus(
        "Finalizando upload...",
        COLORS.YELLOW
    )

    setProgress(0.96)

    local finishOk, finishResult =
        requestRetry(
            CONFIG.UPLOAD_BASE
            .. "/finish",

            withToken({
                uploadId =
                    State.UploadId,

                totalChunks =
                    State.ChunksSent,

                summary = {
                    area = "Completo",

                    records =
                        State.RecordsStored,

                    chunks =
                        State.ChunksSent,

                    bytesApprox =
                        State.BytesSent,

                    passes =
                        State.Pass,

                    clientVisibleOnly =
                        true,
                }
            }),

            "Finalizando",
            setStatus
        )

    State.Uploading = false

    if not finishOk then
        cancelRemoteUpload()

        Diagnostic.error(
            "upload_finish",
            finishResult
        )

        return false, finishResult
    end

    local url =
        type(finishResult)
        == "table"
        and (
            finishResult.downloadUrl
            or finishResult.url
        )
        or nil

    State.LastURL =
        url and tostring(url) or ""

    setProgress(1)

    Diagnostic.step(
        "upload_complete",
        "Upload finalizado",
        {
            records =
                State.RecordsStored,

            chunks =
                State.ChunksSent,

            bytesSent =
                State.BytesSent,

            hasDownloadUrl =
                url ~= nil,
        }
    )

    return true, url
end

--==============================================================--
-- BUTTONS
--==============================================================--

ScanButton.Activated:Connect(function()
    if State.Scanning or State.Uploading then
        return
    end

    task.spawn(function()
        local ok, err =
            xpcall(
                runContinuousScan,
                function(errorMessage)
                    local trace =
                        tostring(errorMessage)

                    pcall(function()
                        if
                            debug
                            and typeof(
                                debug.traceback
                            ) == "function"
                        then
                            trace =
                                debug.traceback(
                                    tostring(
                                        errorMessage
                                    ),
                                    2
                                )
                        end
                    end)

                    return trace
                end
            )

        if not ok then
            State.Scanning = false

            ScanButton.Text =
                "SCAM CONTÍNUO"

            setStatus(
                "Erro durante análise",
                COLORS.RED
            )

            Diagnostic.error(
                "continuous_scan",
                err
            )
        end
    end)
end)

StopButton.Activated:Connect(function()
    if not State.Scanning then
        setStatus(
            "Nenhuma análise em andamento",
            COLORS.ORANGE
        )

        return
    end

    State.StopRequested = true

    setStatus(
        "Parando análise...",
        COLORS.YELLOW
    )

    Diagnostic.step(
        "stop_requested",
        "Usuário solicitou parada"
    )
end)

UploadButton.Activated:Connect(function()
    if State.Scanning then
        setStatus(
            "Pare a análise antes de enviar",
            COLORS.ORANGE
        )

        return
    end

    if State.Uploading then
        return
    end

    task.spawn(function()
        local ok, result =
            uploadAll()

        if ok then
            setStatus(
                "Arquivo enviado ao servidor",
                COLORS.GREEN
            )
        else
            setStatus(
                "Erro no envio: "
                .. tostring(result),
                COLORS.RED
            )
        end
    end)
end)

--==============================================================--
-- DRAG MOBILE
--==============================================================--

do
    local dragging = false
    local dragStart = nil
    local startPosition = nil

    Header.InputBegan:Connect(function(input)
        if
            input.UserInputType
            == Enum.UserInputType.Touch
            or input.UserInputType
            == Enum.UserInputType.MouseButton1
        then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if
            input.UserInputType
            ~= Enum.UserInputType.Touch
            and input.UserInputType
            ~= Enum.UserInputType.MouseMovement
        then
            return
        end

        if
            not dragStart
            or not startPosition
        then
            return
        end

        local delta =
            input.Position - dragStart

        Main.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset
                    + delta.X,

                startPosition.Y.Scale,
                startPosition.Y.Offset
                    + delta.Y
            )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if
            input.UserInputType
            == Enum.UserInputType.Touch
            or input.UserInputType
            == Enum.UserInputType.MouseButton1
        then
            dragging = false
        end
    end)
end

--==============================================================--
-- READY
--==============================================================--

Diagnostic.start()

updateDetails()
setProgress(0)

setStatus(
    "Pronto para iniciar",
    COLORS.GREEN
)

print(
    "[CAFEINA] Scamtest.lua V4 contínuo carregado."
)
