--==============================================================--
-- CAFEÍNA • SCAMTEST CONTÍNUO V5
-- CLIENT-VISIBLE ONLY
--
-- 3 BOTÕES:
-- 1) SCAM CONTÍNUO
-- 2) PARAR ANÁLISE
-- 3) ENVIAR AO SERVIDOR
--
-- MELHORIAS V6:
-- • coleta contínua
-- • filtro de registros repetidos
-- • preserva TODO estado diferente do mesmo objeto
-- • nunca substitui alterações anteriores
-- • duas barras: COLETA e ENVIO AO SERVIDOR
-- • serviço atual + progresso do serviço
-- • detalhes de upload: sessão, chunk, registros, bytes, %
-- • margem segura abaixo do limite final do servidor
-- • diagnóstico identificado como Scamtest.lua
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer =
    Players.LocalPlayer
    or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "V10",

    BASE_URL =
        "https://cafe-na-ia.onrender.com",

    UPLOAD_BASE =
        "https://cafe-na-ia.onrender.com/upload",

    UPLOAD_TOKEN = "",

    DIAGNOSTIC_SCRIPT =
        "Scamtest.lua",

    DIAGNOSTIC_VERSION =
        "10.0",

    DIAGNOSTIC_URL =
        "https://cafe-na-ia.onrender.com/api/runtime-diagnostics",

    -- O backend final aceita mais, mas deixamos margem
    -- para header/chunks/JSON/finalização.
    SAFE_UPLOAD_BYTES = 225 * 1024 * 1024,

    TARGET_CHUNK_BYTES =
        3200000,

    MAX_OBJECTS_PER_PASS =
        40000,

    YIELD_EVERY =
        120,

    PASS_DELAY =
        0.35,

    RETRIES =
        3,

    RETRY_DELAY =
        1.25,

    REQUEST_TIMEOUT =
        75,

    DIAGNOSTIC_HEARTBEAT =
        20,

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
    or
    (
        typeof(http_request) == "function"
        and http_request
    )
    or
    (
        syn
        and typeof(syn.request) == "function"
        and syn.request
    )
    or
    (
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

    Pass = 0,

    CurrentService = "-",
    CurrentServiceIndex = 0,
    CurrentServiceObjects = 0,
    CurrentServiceProcessed = 0,

    ObjectsSeen = 0,

    RecordsStored = 0,
    NewRecords = 0,
    UpdatedRecords = 0,
    DuplicatesFiltered = 0,

    ApproxBytes = 0,
    RealEncodedBytes = 0,

    UploadInProgress = false,
    UploadCompleted = false,

    DiagnosticFinished = false,
    DiagnosticFinishedAt = nil,
    ScanStoppedReported = false,

    Records = {},

    -- Estado mais recente conhecido por objeto.
    -- key -> fingerprint
    LastFingerprintByObject = {},

    -- Estatísticas do histórico preservado.
    HistoryRecords = 0,

    UploadId = nil,
    LastURL = "",

    UploadStage = "Aguardando",
    UploadChunkCurrent = 0,
    UploadChunksSent = 0,
    UploadEstimatedChunks = 0,

    UploadRecordsProcessed = 0,
    UploadRecordsTotal = 0,

    UploadBytesSent = 0,
    UploadBytesTotal = 0,

    UploadAttempt = 0,

    StartedAtClock = 0,
}

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {
    BG =
        Color3.fromRGB(
            10, 11, 14
        ),

    PANEL =
        Color3.fromRGB(
            18, 20, 25
        ),

    PANEL2 =
        Color3.fromRGB(
            27, 30, 38
        ),

    TEXT =
        Color3.fromRGB(
            246, 247, 250
        ),

    SUB =
        Color3.fromRGB(
            155, 160, 175
        ),

    RED =
        Color3.fromRGB(
            235, 42, 58
        ),

    RED_DARK =
        Color3.fromRGB(
            112, 23, 34
        ),

    GREEN =
        Color3.fromRGB(
            65, 210, 118
        ),

    YELLOW =
        Color3.fromRGB(
            244, 190, 65
        ),

    ORANGE =
        Color3.fromRGB(
            245, 132, 56
        ),

    BLUE =
        Color3.fromRGB(
            68, 145, 255
        ),

    STROKE =
        Color3.fromRGB(
            52, 57, 70
        ),
}

--==============================================================--
-- HELPERS
--==============================================================--

local function safeFullName(inst)
    local ok, value =
        pcall(function()
            return inst:GetFullName()
        end)

    if ok and value then
        return tostring(value)
    end

    return tostring(inst.Name)
end

local function safeGet(obj, key)
    local ok, value =
        pcall(function()
            return obj[key]
        end)

    if ok then
        return value
    end

    return nil
end

local function safeAttributes(inst)
    local result = {}

    local ok, attributes =
        pcall(function()
            return inst:GetAttributes()
        end)

    if
        not ok
        or type(attributes) ~= "table"
    then
        return result
    end

    for key, value
        in pairs(attributes)
    do
        local kind =
            typeof(value)

        if
            kind == "string"
            or kind == "number"
            or kind == "boolean"
        then
            result[tostring(key)] =
                value
        else
            result[tostring(key)] =
                tostring(value)
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

    return {
        value:GetComponents()
    }
end

local function formatBytes(bytes)
    bytes =
        tonumber(bytes)
        or 0

    if
        bytes
        >= 1024 * 1024 * 1024
    then
        return string.format(
            "%.2f GB",
            bytes
            / (1024 * 1024 * 1024)
        )
    end

    if bytes >= 1024 * 1024 then
        return string.format(
            "%.2f MB",
            bytes
            / (1024 * 1024)
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

local function formatPercent(value)
    value =
        math.clamp(
            tonumber(value) or 0,
            0,
            1
        )

    return string.format(
        "%.1f%%",
        value * 100
    )
end

local function sanitizeFileName(text)
    local name =
        tostring(text or "scan")

    name =
        name:gsub(
            "[\\/:*?\"<>|]",
            "_"
        )

    name =
        name:gsub(
            "%s+",
            "_"
        )

    if name == "" then
        name = "scan"
    end

    return name
end

local function withToken(payload)
    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token =
            CONFIG.UPLOAD_TOKEN
    end

    return payload
end

--==============================================================--
-- STABLE RECORD / DEDUP
--==============================================================--

local function makeRecordKey(record)
    return table.concat({
        tostring(record.service or ""),
        tostring(record.className or ""),
        tostring(record.path or record.name or ""),
    }, "|")
end

local function copyWithoutVolatileFields(record)
    local stable = {}

    for key, value
        in pairs(record)
    do
        if
            key ~= "pass"
            and key ~= "capturedAtUnix"
            and key ~= "lastSeenUnix"
        then
            stable[key] = value
        end
    end

    return stable
end

local function encodeStable(record)
    local stable =
        copyWithoutVolatileFields(
            record
        )

    local ok, encoded =
        pcall(function()
            return HttpService:JSONEncode(
                stable
            )
        end)

    if not ok then
        return nil
    end

    return encoded
end

-- Hash leve e determinístico.
-- Não é usado para segurança, apenas para deduplicação.
local function simpleHash(text)
    local hash = 2166136261

    for index = 1, #text do
        hash =
            bit32.bxor(
                hash,
                string.byte(text, index)
            )

        hash =
            (
                hash * 16777619
            ) % 4294967296
    end

    return string.format(
        "%08x",
        hash
    )
end

--==============================================================--
-- SERIALIZE
--==============================================================--

local function serializeInstance(
    inst,
    serviceName,
    passNumber
)
    local attributes =
        safeAttributes(inst)

    local data = {
        recordType =
            "instance_snapshot",

        pass =
            passNumber,

        capturedAtUnix =
            os.time(),

        lastSeenUnix =
            os.time(),

        service =
            serviceName,

        name =
            tostring(inst.Name),

        className =
            tostring(inst.ClassName),

        path =
            safeFullName(inst),

        parentPath =
            inst.Parent
            and safeFullName(inst.Parent)
            or nil,

        attributes =
            attributes,
    }

    pcall(function()
        data.childCount =
            #inst:GetChildren()
    end)

    if inst:IsA("ValueBase") then
        local value =
            safeGet(
                inst,
                "Value"
            )

        local kind =
            typeof(value)

        if
            kind == "string"
            or kind == "number"
            or kind == "boolean"
        then
            data.value =
                value
        else
            data.value =
                tostring(value)
        end
    end

    if inst:IsA("BasePart") then
        data.properties = {
            anchored =
                safeGet(
                    inst,
                    "Anchored"
                ),

            canCollide =
                safeGet(
                    inst,
                    "CanCollide"
                ),

            canTouch =
                safeGet(
                    inst,
                    "CanTouch"
                ),

            canQuery =
                safeGet(
                    inst,
                    "CanQuery"
                ),

            transparency =
                safeGet(
                    inst,
                    "Transparency"
                ),

            reflectance =
                safeGet(
                    inst,
                    "Reflectance"
                ),

            position =
                vector3(
                    safeGet(
                        inst,
                        "Position"
                    )
                ),

            size =
                vector3(
                    safeGet(
                        inst,
                        "Size"
                    )
                ),

            cframe =
                cframe(
                    safeGet(
                        inst,
                        "CFrame"
                    )
                ),

            material =
                tostring(
                    safeGet(
                        inst,
                        "Material"
                    )
                    or ""
                ),

            color =
                color3(
                    safeGet(
                        inst,
                        "Color"
                    )
                ),
        }
    end

    if inst:IsA("Model") then
        local primary =
            safeGet(
                inst,
                "PrimaryPart"
            )

        data.model = {
            primaryPart =
                primary
                and safeFullName(primary)
                or nil,
        }
    end

    if inst:IsA("Tool") then
        data.tool = {
            requiresHandle =
                safeGet(
                    inst,
                    "RequiresHandle"
                ),

            canBeDropped =
                safeGet(
                    inst,
                    "CanBeDropped"
                ),

            toolTip =
                tostring(
                    safeGet(
                        inst,
                        "ToolTip"
                    )
                    or ""
                ),
        }
    end

    local isRemote =
        inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")

    pcall(function()
        if
            inst:IsA(
                "UnreliableRemoteEvent"
            )
        then
            isRemote = true
        end
    end)

    if isRemote then
        data.remote = {
            type =
                tostring(inst.ClassName),

            path =
                safeFullName(inst),
        }
    end

    if
        inst:IsA(
            "LuaSourceContainer"
        )
    then
        data.script = {
            type =
                tostring(inst.ClassName),

            path =
                safeFullName(inst),

            disabled =
                safeGet(
                    inst,
                    "Disabled"
                ),
        }
    end

    if inst:IsA("GuiObject") then
        data.gui = {
            visible =
                safeGet(
                    inst,
                    "Visible"
                ),

            active =
                safeGet(
                    inst,
                    "Active"
                ),

            position =
                udim2(
                    safeGet(
                        inst,
                        "Position"
                    )
                ),

            size =
                udim2(
                    safeGet(
                        inst,
                        "Size"
                    )
                ),

            anchorPoint =
                vector2(
                    safeGet(
                        inst,
                        "AnchorPoint"
                    )
                ),
        }

        if
            inst:IsA("TextLabel")
            or inst:IsA("TextButton")
            or inst:IsA("TextBox")
        then
            data.gui.text =
                tostring(
                    safeGet(
                        inst,
                        "Text"
                    )
                    or ""
                )
        end

        if
            inst:IsA("ImageLabel")
            or inst:IsA("ImageButton")
        then
            data.gui.image =
                tostring(
                    safeGet(
                        inst,
                        "Image"
                    )
                    or ""
                )
        end
    end

    if
        inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        data.media = {
            texture =
                tostring(
                    safeGet(
                        inst,
                        "Texture"
                    )
                    or ""
                ),
        }
    end

    if inst:IsA("Sound") then
        data.media = {
            soundId =
                tostring(
                    safeGet(
                        inst,
                        "SoundId"
                    )
                    or ""
                ),

            volume =
                safeGet(
                    inst,
                    "Volume"
                ),

            looped =
                safeGet(
                    inst,
                    "Looped"
                ),

            playbackSpeed =
                safeGet(
                    inst,
                    "PlaybackSpeed"
                ),
        }
    end

    if inst:IsA("Humanoid") then
        data.humanoid = {
            health =
                safeGet(
                    inst,
                    "Health"
                ),

            maxHealth =
                safeGet(
                    inst,
                    "MaxHealth"
                ),

            walkSpeed =
                safeGet(
                    inst,
                    "WalkSpeed"
                ),

            jumpPower =
                safeGet(
                    inst,
                    "JumpPower"
                ),
        }
    end

    if inst:IsA("Player") then
        local team =
            safeGet(
                inst,
                "Team"
            )

        data.player = {
            displayName =
                tostring(
                    safeGet(
                        inst,
                        "DisplayName"
                    )
                    or ""
                ),

            userId =
                safeGet(
                    inst,
                    "UserId"
                ),

            accountAge =
                safeGet(
                    inst,
                    "AccountAge"
                ),

            team =
                team
                and tostring(team.Name)
                or nil,
        }
    end

    return data
end

--==============================================================--
-- SMART STORAGE • HISTÓRICO COMPLETO + LIMITE REAL
--==============================================================--

local function encodeFinalRecord(record)
    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            record
        )

    if not ok then
        return nil
    end

    return encoded
end

local function storeRecord(record)
    local stableEncoded =
        encodeStable(record)

    if not stableEncoded then
        return false, "encode_error"
    end

    local objectKey =
        makeRecordKey(record)

    local fingerprint =
        simpleHash(
            stableEncoded
        )

    local lastFingerprint =
        State.LastFingerprintByObject[
            objectKey
        ]

    -- Descarta somente repetição idêntica CONSECUTIVA.
    -- A -> B -> A é preservado, pois representa uma alteração real.
    if
        lastFingerprint
        and lastFingerprint
        == fingerprint
    then
        State.DuplicatesFiltered += 1

        return false, "duplicate"
    end

    record.objectKey =
        objectKey

    if lastFingerprint then
        record.changeType =
            "updated"

        State.UpdatedRecords += 1
    else
        record.changeType =
            "new"

        State.NewRecords += 1
    end

    record.previousFingerprint =
        lastFingerprint

    record.fingerprint =
        fingerprint

    local finalEncoded =
        encodeFinalRecord(record)

    if not finalEncoded then
        return false, "encode_error"
    end

    -- Usa o tamanho do registro FINAL, já com os campos extras.
    -- Soma pequena margem para vírgulas/estrutura do array.
    local finalSize =
        #finalEncoded + 2

    if
        State.RealEncodedBytes
        + finalSize
        >= CONFIG.SAFE_UPLOAD_BYTES
    then
        State.AutoStoppedByLimit =
            true

        State.StopRequested =
            true

        return false, "limit"
    end

    State.Records[
        #State.Records + 1
    ] = record

    State.LastFingerprintByObject[
        objectKey
    ] = fingerprint

    State.RecordsStored += 1
    State.HistoryRecords += 1
    State.ApproxBytes += #stableEncoded + 1
    State.RealEncodedBytes += finalSize

    return true,
        lastFingerprint
        and "updated"
        or "new"
end

local function endUploadState(success)
    State.UploadInProgress =
        false

    State.UploadCompleted =
        success == true
end

local function finalizeDiagnosticSuccess()
    if State.DiagnosticFinished then
        return
    end

    local finishedAt =
        os.time()

    State.DiagnosticFinished =
        true

    State.DiagnosticFinishedAt =
        finishedAt

    State.UploadInProgress =
        false

    State.Uploading =
        false

    State.UploadCompleted =
        true

    -- Encerra o heartbeat ANTES do último POST.
    Diagnostic.Heartbeat =
        false

    if Diagnostic then
        Diagnostic.sync()

        Diagnostic.Report.status =
            "success"

        Diagnostic.Report.phase =
            "upload_complete"

        Diagnostic.Report.message =
            "Servidor confirmou upload"

        Diagnostic.Report.finishedAt =
            finishedAt

        Diagnostic.LastEventAt =
            os.clock()

        -- Último envio contém status success + finishedAt.
        Diagnostic.send()
    end

    setStatus(
        "PRONTO PARA NOVO SCAM"
    )

    setUploadStatus(
        "concluído • pronto para novo SCAM",
        COLORS.GREEN
    )

    tweenBar(
        UploadBar,
        1
    )
end

--==============================================================--
-- HTTP HELPERS
--==============================================================--

local function decodeResponse(response)
    if type(response) == "string" then
        local ok, decoded =
            pcall(function()
                return HttpService:JSONDecode(
                    response
                )
            end)

        return
            ok
            and decoded
            or nil
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

    local ok, decoded =
        pcall(function()
            return HttpService:JSONDecode(
                body
            )
        end)

    return
        ok
        and decoded
        or nil
end

local function rawRequest(
    url,
    payload
)
    local body =
        HttpService:JSONEncode(
            payload
        )

    if ExecutorRequest then
        local ok, response =
            pcall(function()
                return ExecutorRequest({
                    Url = url,

                    Method =
                        "POST",

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
            return false,
                tostring(response)
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
            decodeResponse(
                response
            )

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
                    .. tostring(
                        statusCode
                    )
                )
        end

        if not decoded then
            return false,
                "Resposta inválida do servidor"
        end

        return true, decoded
    end

    local ok, response =
        pcall(function()
            return HttpService:RequestAsync({
                Url = url,

                Method =
                    "POST",

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
        return false,
            tostring(response)
    end

    local decoded =
        decodeResponse(
            response
        )

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
        requestOk,
        requestResult =
            rawRequest(
                url,
                payload
            )

        finished = true
    end)

    local started =
        os.clock()

    while not finished do
        if
            os.clock() - started
            >= CONFIG.REQUEST_TIMEOUT
        then
            return false,
                "Tempo limite excedido"
        end

        task.wait(0.1)
    end

    return requestOk,
        requestResult
end

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function create(
    className,
    props
)
    local object =
        Instance.new(className)

    for key, value
        in pairs(props or {})
    do
        object[key] = value
    end

    return object
end

local function corner(
    parent,
    radius
)
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
            Color =
                COLORS.STROKE,

            Thickness = 1,

            Parent = parent,
        }
    )
end

--==============================================================--
-- GUI ROOT
--==============================================================--

local GuiParent = nil

if typeof(gethui) == "function" then
    local ok, result =
        pcall(gethui)

    if ok then
        GuiParent = result
    end
end

local Gui =
    create(
        "ScreenGui",
        {
            Name =
                "CafeinaScamContinuoV5",

            ResetOnSpawn =
                false,

            IgnoreGuiInset =
                true,

            ZIndexBehavior =
                Enum.ZIndexBehavior.Sibling,
        }
    )

local parented = false

if GuiParent then
    parented =
        pcall(function()
            Gui.Parent =
                GuiParent
        end)
end

if not parented then
    parented =
        pcall(function()
            Gui.Parent =
                CoreGui
        end)
end

if not parented then
    Gui.Parent =
        LocalPlayer:WaitForChild(
            "PlayerGui"
        )
end

for _, child
    in ipairs(
        Gui.Parent:GetChildren()
    )
do
    if
        child ~= Gui
        and child.Name
        == "CafeinaScamContinuoV5"
    then
        child:Destroy()
    end
end

--==============================================================--
-- MAIN
--==============================================================--

local Main =
    create(
        "Frame",
        {
            Size =
                UDim2.fromOffset(
                    350,
                    415
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

            BorderSizePixel =
                0,

            Parent =
                Gui,
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

            BorderSizePixel =
                0,

            Parent =
                Main,
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

        BackgroundTransparency =
            1,

        Text =
            "CAFEÍNA • SCAM CONTÍNUO",

        TextColor3 =
            COLORS.TEXT,

        Font =
            Enum.Font.GothamBold,

        TextSize =
            15,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
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

        BackgroundTransparency =
            1,

        Text =
            "Scamtest.lua • V10 • fluxo sincronizado",

        TextColor3 =
            COLORS.SUB,

        Font =
            Enum.Font.Gotham,

        TextSize =
            9,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

--==============================================================--
-- SCAN STATUS
--==============================================================--

local ScanCard =
    create(
        "Frame",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    68
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    110
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(ScanCard, 10)

local ScanStatus =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    7
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    20
                ),

            BackgroundTransparency =
                1,

            Text =
                "COLETA • aguardando",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                ScanCard,
        }
    )

local ScanDetails =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    28
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    56
                ),

            BackgroundTransparency =
                1,

            Text =
                "Passe 0 • Serviço: -\n"
                .. "0 históricos • 0 repetidos filtrados\n"
                .. "0 B / "
                .. formatBytes(
                    CONFIG.SAFE_UPLOAD_BYTES
                ),

            TextColor3 =
                COLORS.SUB,

            Font =
                Enum.Font.Gotham,

            TextSize =
                9,

            TextWrapped =
                true,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent =
                ScanCard,
        }
    )

local ScanBarBG =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    10,
                    1,
                    -17
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    7
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Parent =
                ScanCard,
        }
    )

corner(ScanBarBG, 99)

local ScanBar =
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

            BorderSizePixel =
                0,

            Parent =
                ScanBarBG,
        }
    )

corner(ScanBar, 99)

--==============================================================--
-- UPLOAD STATUS
--==============================================================--

local UploadCard =
    create(
        "Frame",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    186
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    118
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(UploadCard, 10)

local UploadStatus =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    7
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    20
                ),

            BackgroundTransparency =
                1,

            Text =
                "SERVIDOR • aguardando envio",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                UploadCard,
        }
    )

local UploadDetails =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    28
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    63
                ),

            BackgroundTransparency =
                1,

            Text =
                "Sessão: nenhuma\n"
                .. "Chunk: 0 • Registros: 0/0\n"
                .. "Enviado: 0 B • 0.0%",

            TextColor3 =
                COLORS.SUB,

            Font =
                Enum.Font.Gotham,

            TextSize =
                9,

            TextWrapped =
                true,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent =
                UploadCard,
        }
    )

local UploadBarBG =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    10,
                    1,
                    -17
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    7
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Parent =
                UploadCard,
        }
    )

corner(UploadBarBG, 99)

local UploadBar =
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
                COLORS.BLUE,

            BorderSizePixel =
                0,

            Parent =
                UploadBarBG,
        }
    )

corner(UploadBar, 99)

--==============================================================--
-- BUTTONS
--==============================================================--

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
                        10,
                        y
                    ),

                Size =
                    UDim2.new(
                        1,
                        -20,
                        0,
                        30
                    ),

                BackgroundColor3 =
                    color,

                BorderSizePixel =
                    0,

                Text =
                    text,

                TextColor3 =
                    COLORS.TEXT,

                Font =
                    Enum.Font.GothamBold,

                TextSize =
                    10,

                Parent =
                    Main,
            }
        )

    corner(button, 8)

    return button
end

local ScanButton =
    makeButton(
        "SCAM CONTÍNUO",
        314,
        COLORS.RED
    )

local StopButton =
    makeButton(
        "PARAR ANÁLISE",
        349,
        COLORS.RED_DARK
    )

local UploadButton =
    makeButton(
        "ENVIAR AO SERVIDOR",
        384,
        COLORS.PANEL2
    )




local function canStartNewScan()
    if State.UploadInProgress then
        setStatus(
            "Envio em andamento • novo SCAM bloqueado"
        )
        return false
    end

    return true
end


--==============================================================--
-- UI UPDATE
--==============================================================--

local function tweenBar(
    bar,
    value
)
    value =
        math.clamp(
            tonumber(value) or 0,
            0,
            1
        )

    TweenService:Create(
        bar,
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

local function updateScanUI()
    local totalProgress =
        CONFIG.SAFE_UPLOAD_BYTES > 0
        and (
            State.ApproxBytes
            / CONFIG.SAFE_UPLOAD_BYTES
        )
        or 0

    local serviceProgress = 0

    if State.CurrentServiceObjects > 0 then
        serviceProgress =
            State.CurrentServiceProcessed
            / State.CurrentServiceObjects
    end

    ScanDetails.Text =
        "Passe "
        .. tostring(State.Pass)
        .. " • Serviço: "
        .. tostring(
            State.CurrentService
        )
        .. " ("
        .. formatPercent(
            serviceProgress
        )
        .. ")\n"
        .. tostring(
            State.HistoryRecords
        )
        .. " históricos • "
        .. tostring(
            State.UpdatedRecords
        )
        .. " alterações • "
        .. tostring(
            State.DuplicatesFiltered
        )
        .. " repetidos filtrados\n"
        .. formatBytes(
            State.ApproxBytes
        )
        .. " / "
        .. formatBytes(
            CONFIG.SAFE_UPLOAD_BYTES
        )
        .. " • "
        .. formatPercent(
            totalProgress
        )

    tweenBar(
        ScanBar,
        totalProgress
    )
end

local function uploadProgress()
    if State.UploadBytesTotal > 0 then
        return math.clamp(
            State.UploadBytesSent
            / State.UploadBytesTotal,
            0,
            1
        )
    end

    if State.UploadRecordsTotal > 0 then
        return math.clamp(
            State.UploadRecordsProcessed
            / State.UploadRecordsTotal,
            0,
            1
        )
    end

    return 0
end

local function updateUploadUI()
    local progress =
        uploadProgress()

    local session =
        State.UploadId
        and tostring(State.UploadId)
        or "nenhuma"

    if #session > 24 then
        session =
            string.sub(
                session,
                1,
                24
            )
            .. "..."
    end

    UploadDetails.Text =
        "Sessão: "
        .. session
        .. "\n"
        .. "Chunk: "
        .. tostring(
            State.UploadChunkCurrent
        )
        .. "/"
        .. tostring(
            State.UploadEstimatedChunks
        )
        .. " • Registros: "
        .. tostring(
            State.UploadRecordsProcessed
        )
        .. "/"
        .. tostring(
            State.UploadRecordsTotal
        )
        .. "\n"
        .. "Enviado: "
        .. formatBytes(
            State.UploadBytesSent
        )
        .. " / "
        .. formatBytes(
            State.UploadBytesTotal
        )
        .. " • "
        .. formatPercent(progress)

    tweenBar(
        UploadBar,
        progress
    )
end

local function setScanStatus(
    text,
    color
)
    ScanStatus.Text =
        "COLETA • "
        .. tostring(text or "")

    ScanStatus.TextColor3 =
        color or COLORS.TEXT
end

local function setUploadStatus(
    text,
    color
)
    State.UploadStage =
        tostring(text or "")

    UploadStatus.Text =
        "SERVIDOR • "
        .. State.UploadStage

    UploadStatus.TextColor3 =
        color or COLORS.TEXT
end

--==============================================================--
-- DIAGNOSTIC
--==============================================================--

local Diagnostic = {
    RunId = nil,
    LastEventAt = 0,
    Heartbeat = false,

    Report = {
        script =
            CONFIG.DIAGNOSTIC_SCRIPT,

        version =
            CONFIG.DIAGNOSTIC_VERSION,

        runId = nil,

        status =
            "idle",

        phase =
            "idle",

        startedAt =
            nil,

        finishedAt =
            nil,

        message =
            "",

        steps =
            {},

        errors =
            {},

        counters =
            {},

        environment = {
            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId,

            placeVersion =
                game.PlaceVersion,
        },
    },
}

local function diagnosticRunId()
    local ok, value =
        pcall(function()
            return HttpService:GenerateGUID(
                false
            )
        end)

    if ok and value then
        return value
    end

    return
        "run_"
        .. tostring(os.time())
        .. "_"
        .. tostring(
            math.random(
                100000,
                999999
            )
        )
end

local function diagnosticCopy(
    value,
    depth
)
    depth =
        tonumber(depth)
        or 0

    if depth > 7 then
        return "[depth-limit]"
    end

    if type(value) ~= "table" then
        local kind =
            typeof(value)

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

    for key, child
        in pairs(value)
    do
        output[tostring(key)] =
            diagnosticCopy(
                child,
                depth + 1
            )
    end

    return output
end

function Diagnostic.sync()
    local c =
        Diagnostic.Report.counters

    c.pass =
        State.Pass

    c.currentService =
        State.CurrentService

    c.objectsSeen =
        State.ObjectsSeen

    c.recordsStored =
        State.RecordsStored

    c.historyRecords =
        State.HistoryRecords

    c.newRecords =
        State.NewRecords

    c.updatedRecords =
        State.UpdatedRecords

    c.duplicatesFiltered =
        State.DuplicatesFiltered

    c.approxBytes =
        State.ApproxBytes

    c.realEncodedBytes =
        State.RealEncodedBytes

    c.diagnosticFinished =
        State.DiagnosticFinished == true

    c.diagnosticFinishedAt =
        State.DiagnosticFinishedAt

    c.safeLimitBytes =
        CONFIG.SAFE_UPLOAD_BYTES

    c.uploadStage =
        State.UploadStage

    c.uploadChunk =
        State.UploadChunkCurrent

    c.uploadChunksSent =
        State.UploadChunksSent

    c.uploadRecordsProcessed =
        State.UploadRecordsProcessed

    c.uploadRecordsTotal =
        State.UploadRecordsTotal

    c.uploadBytesSent =
        State.UploadBytesSent

    c.uploadBytesTotal =
        State.UploadBytesTotal
end

function Diagnostic.send()
    if
        not ExecutorRequest
        or not Diagnostic.RunId
    then
        return
    end

    Diagnostic.sync()

    local payload = {
        script =
            CONFIG.DIAGNOSTIC_SCRIPT,

        runId =
            Diagnostic.RunId,

        report =
            diagnosticCopy(
                Diagnostic.Report
            ),
    }

    task.spawn(function()
        pcall(function()
            ExecutorRequest({
                Url =
                    CONFIG.DIAGNOSTIC_URL,

                Method =
                    "POST",

                Headers = {
                    ["Content-Type"] =
                        "application/json",

                    ["Accept"] =
                        "application/json",
                },

                Body =
                    HttpService:JSONEncode(
                        payload
                    ),
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
        "Scamtest.lua V10 iniciado"

    Diagnostic.LastEventAt =
        os.clock()

    Diagnostic.send()

    if Diagnostic.Heartbeat then
        return
    end

    Diagnostic.Heartbeat =
        true

    task.spawn(function()
        while Diagnostic.Heartbeat do
            task.wait(
                CONFIG.DIAGNOSTIC_HEARTBEAT
            )

            if
                not Diagnostic.Heartbeat
                or Diagnostic.Report.status
                ~= "running"
            then
                break
            end

            -- Evita duplicar no servidor a mesma fase que acabou
            -- de ser enviada por Diagnostic.step().
            local idleFor =
                os.clock()
                - (
                    Diagnostic.LastEventAt
                    or 0
                )

            if
                idleFor
                >= CONFIG.DIAGNOSTIC_HEARTBEAT
            then
                Diagnostic.send()
            end
        end
    end)
end

function Diagnostic.step(
    phase,
    message,
    extra
)
    Diagnostic.LastEventAt =
        os.clock()

    Diagnostic.Report.status =
        "running"

    Diagnostic.Report.phase =
        tostring(
            phase or "unknown"
        )

    Diagnostic.Report.message =
        tostring(
            message or ""
        )

    local item = {
        phase =
            Diagnostic.Report.phase,

        message =
            Diagnostic.Report.message,

        time =
            os.time(),
    }

    if type(extra) == "table" then
        for key, value
            in pairs(extra)
        do
            item[tostring(key)] =
                diagnosticCopy(value)
        end
    end

    table.insert(
        Diagnostic.Report.steps,
        item
    )

    -- Evita crescimento infinito do diagnóstico.
    while
        #Diagnostic.Report.steps > 120
    do
        table.remove(
            Diagnostic.Report.steps,
            1
        )
    end

    Diagnostic.send()
end

function Diagnostic.error(
    phase,
    err
)
    local message =
        tostring(
            err
            or "Erro desconhecido"
        )

    local trace = nil

    pcall(function()
        if
            debug
            and typeof(
                debug.traceback
            ) == "function"
        then
            trace =
                debug.traceback(
                    message,
                    2
                )
        end
    end)

    Diagnostic.Report.status =
        "error"

    Diagnostic.Report.phase =
        tostring(
            phase or "unknown"
        )

    Diagnostic.Report.message =
        message

    Diagnostic.Report.finishedAt =
        os.time()

    table.insert(
        Diagnostic.Report.errors,
        {
            phase =
                Diagnostic.Report.phase,

            message =
                message,

            traceback =
                trace,

            time =
                os.time(),
        }
    )

    while
        #Diagnostic.Report.errors > 30
    do
        table.remove(
            Diagnostic.Report.errors,
            1
        )
    end

    Diagnostic.send()
end

--==============================================================--
-- RETRY
--==============================================================--

local function requestRetry(
    url,
    payload,
    label
)
    local lastError =
        "Falha desconhecida"

    for attempt = 1, CONFIG.RETRIES do
        State.UploadAttempt =
            attempt

        setUploadStatus(
            label
            .. " • tentativa "
            .. tostring(attempt)
            .. "/"
            .. tostring(CONFIG.RETRIES),
            COLORS.YELLOW
        )

        updateUploadUI()

        local ok, result =
            requestWithTimeout(
                url,
                payload
            )

        if ok then
            return true, result
        end

        lastError =
            tostring(result)

        if attempt < CONFIG.RETRIES then
            task.wait(
                CONFIG.RETRY_DELAY
                * attempt
            )
        end
    end

    return false, lastError
end

--==============================================================--
-- RESET
--==============================================================--

local function resetScan()
    State.StopRequested =
        false

    State.ScanComplete =
        false

    State.AutoStoppedByLimit =
        false

    State.Pass =
        0

    State.CurrentService =
        "-"

    State.CurrentServiceIndex =
        0

    State.CurrentServiceObjects =
        0

    State.CurrentServiceProcessed =
        0

    State.ObjectsSeen =
        0

    State.RecordsStored =
        0

    State.NewRecords =
        0

    State.UpdatedRecords =
        0

    State.DuplicatesFiltered =
        0

    State.ApproxBytes =
        0

    State.Records =
        {}

    State.LastFingerprintByObject =
        {}

    State.HistoryRecords =
        0

    State.RealEncodedBytes =
        0

    State.UploadCompleted =
        false

    State.UploadId =
        nil

    State.LastURL =
        ""

    State.UploadStage =
        "Aguardando"

    State.UploadChunkCurrent =
        0

    State.UploadChunksSent =
        0

    State.UploadEstimatedChunks =
        0

    State.UploadRecordsProcessed =
        0

    State.UploadRecordsTotal =
        0

    State.UploadBytesSent =
        0

    State.UploadBytesTotal =
        0

    State.UploadAttempt =
        0

    updateScanUI()
    updateUploadUI()
end

--==============================================================--
-- CONTINUOUS SCAN
--==============================================================--

local function runContinuousScan()
    State.DiagnosticFinished =
        false

    State.DiagnosticFinishedAt =
        nil

    State.UploadCompleted =
        false

    if
        Diagnostic
        and Diagnostic.Report
        and Diagnostic.Report.status
        ~= "running"
    then
        Diagnostic.RunId =
            diagnosticRunId()

        Diagnostic.Report.runId =
            Diagnostic.RunId

        Diagnostic.Report.status =
            "running"

        Diagnostic.Report.phase =
            "scan_start"

        Diagnostic.Report.finishedAt =
            nil

        Diagnostic.Heartbeat =
            true
    end

    if
        State.Scanning
        or State.Uploading
    then
        return
    end

    resetScan()

    State.Scanning =
        true

    State.StartedAtClock =
        os.clock()

    ScanButton.Text =
        "SCAM EM EXECUÇÃO..."

    setScanStatus(
        "iniciando...",
        COLORS.YELLOW
    )

    Diagnostic.step(
        "scan_start",
        "Coleta contínua iniciada"
    )

    while
        not State.StopRequested
        and State.ApproxBytes
        < CONFIG.SAFE_UPLOAD_BYTES
    do
        State.Pass += 1

        local objectsThisPass =
            0

        for serviceIndex, serviceName
            in ipairs(CONFIG.SERVICES)
        do
            if State.StopRequested then
                break
            end

            if
                State.ApproxBytes
                >= CONFIG.SAFE_UPLOAD_BYTES
            then
                State.AutoStoppedByLimit =
                    true

                State.StopRequested =
                    true

                break
            end

            State.CurrentService =
                serviceName

            State.CurrentServiceIndex =
                serviceIndex

            State.CurrentServiceProcessed =
                0

            setScanStatus(
                "lendo "
                .. serviceName
                .. " • passe "
                .. tostring(State.Pass),
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

                State.CurrentServiceObjects =
                    #descendants

                for index, inst
                    in ipairs(descendants)
                do
                    if State.StopRequested then
                        break
                    end

                    if
                        objectsThisPass
                        >= CONFIG.MAX_OBJECTS_PER_PASS
                    then
                        break
                    end

                    State.CurrentServiceProcessed =
                        index

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
                        local _, reason =
                            storeRecord(
                                record
                            )

                        if reason == "limit" then
                            break
                        end
                    end

                    if
                        index
                        % CONFIG.YIELD_EVERY
                        == 0
                    then
                        updateScanUI()
                        task.wait()
                    end
                end
            end

            updateScanUI()

            Diagnostic.step(
                "service_complete",
                "Serviço analisado",
                {
                    pass =
                        State.Pass,

                    service =
                        serviceName,

                    unique =
                        State.RecordsStored,

                    updated =
                        State.UpdatedRecords,

                    duplicates =
                        State.DuplicatesFiltered,

                    bytes =
                        State.ApproxBytes,
                }
            )

            task.wait()
        end

        updateScanUI()

        Diagnostic.step(
            "scan_pass_complete",
            "Passe concluído",
            {
                pass =
                    State.Pass,

                objects =
                    objectsThisPass,

                unique =
                    State.RecordsStored,

                duplicatesFiltered =
                    State.DuplicatesFiltered,
            }
        )

        if
            not State.StopRequested
            and State.ApproxBytes
            < CONFIG.SAFE_UPLOAD_BYTES
        then
            State.CurrentService =
                "aguardando próximo passe"

            State.CurrentServiceObjects =
                0

            State.CurrentServiceProcessed =
                0

            updateScanUI()

            task.wait(
                CONFIG.PASS_DELAY
            )
        end
    end

    State.Scanning =
        false

    State.ScanComplete =
        true

    ScanButton.Text =
        "SCAM CONTÍNUO"

    updateScanUI()

    if State.AutoStoppedByLimit then
        setScanStatus(
            "limite seguro atingido • pronto para enviar",
            COLORS.GREEN
        )

        Diagnostic.step(
            "scan_limit_reached",
            "Limite seguro atingido",
            {
                bytes =
                    State.ApproxBytes,

                records =
                    State.RecordsStored,
            }
        )
    else
        setScanStatus(
            "parado • conteúdo preservado",
            COLORS.ORANGE
        )

        Diagnostic.step(
            "scan_stopped",
            "Análise parada pelo usuário",
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
-- CANCEL REMOTE UPLOAD
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

--==============================================================--
-- UPLOAD
--==============================================================--

local function uploadAll()
    if
        State.UploadInProgress
        or State.Uploading
    then
        setStatus(
            "Envio já está em andamento"
        )

        return false,
            "Upload já está em andamento"
    end

    if State.Scanning then
        return false,
            "Pare a análise antes de enviar"
    end

    if #State.Records < 1 then
        return false,
            "Nenhum dado coletado"
    end

    -- Só trava um novo SCAM depois que todas
    -- as validações do upload passaram.
    State.UploadInProgress =
        true

    State.UploadCompleted =
        false

    State.Uploading =
        true

    State.UploadId =
        nil

    State.UploadStage =
        "Preparando"

    State.UploadChunkCurrent =
        0

    State.UploadChunksSent =
        0

    State.UploadRecordsProcessed =
        0

    State.UploadRecordsTotal =
        #State.Records

    -- Usa o tamanho deduplicado como estimativa inicial.
    State.UploadBytesTotal =
        math.max(
            State.ApproxBytes,
            1
        )

    State.UploadBytesSent =
        0

    State.UploadEstimatedChunks =
        math.max(
            1,
            math.ceil(
                State.UploadBytesTotal
                / CONFIG.TARGET_CHUNK_BYTES
            )
        )

    updateUploadUI()

    setUploadStatus(
        "abrindo sessão...",
        COLORS.YELLOW
    )

    Diagnostic.step(
        "upload_start",
        "Upload deduplicado iniciado",
        {
            records =
                #State.Records,

            bytesApprox =
                State.ApproxBytes,

            duplicatesFiltered =
                State.DuplicatesFiltered,
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
                filename =
                    filename,

                source =
                    "cafeina-continuous-deduplicated",

                metadata = {
                    area =
                        "Completo",

                    recordCount =
                        #State.Records,

                    historyRecords =
                        State.HistoryRecords,

                    updatedRecords =
                        State.UpdatedRecords,

                    duplicatesFiltered =
                        State.DuplicatesFiltered,

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

            "abrindo sessão"
        )

    if
        not startOk
        or type(startResult)
        ~= "table"
        or not startResult.uploadId
    then
        State.Uploading =
            false

        State.UploadInProgress =
            false

        setUploadStatus(
            "erro ao abrir sessão",
            COLORS.RED
        )

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

    setUploadStatus(
        "sessão criada • preparando chunks",
        COLORS.YELLOW
    )

    updateUploadUI()

    Diagnostic.step(
        "upload_session_ready",
        "Sessão criada",
        {
            uploadId =
                State.UploadId,
        }
    )

    local chunk = {}
    local chunkBytes = 2

    local function flushChunk()
        if #chunk == 0 then
            return true
        end

        local chunkIndex =
            State.UploadChunksSent
            + 1

        State.UploadChunkCurrent =
            chunkIndex

        setUploadStatus(
            "enviando chunk "
            .. tostring(chunkIndex)
            .. "/"
            .. tostring(
                State.UploadEstimatedChunks
            ),
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

                "enviando chunk "
                .. tostring(chunkIndex)
        )

        if not ok then
            return false, result
        end

        State.UploadChunksSent =
            chunkIndex

        State.UploadBytesSent +=
            #encoded

        -- Pode haver pequena diferença do JSON real.
        if
            State.UploadBytesSent
            > State.UploadBytesTotal
        then
            State.UploadBytesTotal =
                State.UploadBytesSent
        end

        updateUploadUI()

        Diagnostic.step(
            "upload_chunk_complete",
            "Chunk enviado",
            {
                chunk =
                    chunkIndex,

                bytes =
                    #encoded,

                totalBytesSent =
                    State.UploadBytesSent,
            }
        )

        chunk = {}
        chunkBytes = 2

        return true
    end

    -- Header do arquivo
    chunk[1] = {
        recordType =
            "continuous_scan_header",

        scanner =
            "CAFEINA",

        version =
            CONFIG.VERSION,

        clientVisibleOnly =
            true,

        deduplicated =
            true,

        historyMode =
            "preserve_all_changes",

        sizeAccounting =
            "final_record_json",

        operationalLimitBytes =
            CONFIG.SAFE_UPLOAD_BYTES,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        jobId =
            game.JobId,

        passes =
            State.Pass,

        uniqueRecords =
            State.RecordsStored,

        newRecords =
            State.NewRecords,

        updatedRecords =
            State.UpdatedRecords,

        duplicatesFiltered =
            State.DuplicatesFiltered,

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
                local flushOk,
                flushError =
                    flushChunk()

                if not flushOk then
                    cancelRemoteUpload()

                    State.Uploading =
                        false

                    State.UploadInProgress =
                        false

                    setUploadStatus(
                        "erro no envio",
                        COLORS.RED
                    )

                    Diagnostic.error(
                        "upload_chunk",
                        flushError
                    )

                    return false,
                        flushError
                end
            end

            chunk[
                #chunk + 1
            ] = record

            chunkBytes +=
                recordBytes
        end

        State.UploadRecordsProcessed =
            index

        if index % 50 == 0 then
            updateUploadUI()
            task.wait()
        end
    end

    local flushOk,
    flushError =
        flushChunk()

    if not flushOk then
        cancelRemoteUpload()

        State.Uploading =
            false

        State.UploadInProgress =
            false

        setUploadStatus(
            "erro no último chunk",
            COLORS.RED
        )

        Diagnostic.error(
            "upload_chunk",
            flushError
        )

        return false,
            flushError
    end

    -- Finalização tem etapa própria para o usuário
    -- saber que chunks acabaram mas servidor ainda está fechando arquivo.
    State.UploadRecordsProcessed =
        State.UploadRecordsTotal

    setUploadStatus(
        "todos chunks enviados • finalizando arquivo...",
        COLORS.YELLOW
    )

    updateUploadUI()

    Diagnostic.step(
        "upload_finish_start",
        "Finalizando arquivo no servidor",
        {
            chunks =
                State.UploadChunksSent,

            bytesSent =
                State.UploadBytesSent,
        }
    )

    local finishOk, finishResult =
        requestRetry(
            CONFIG.UPLOAD_BASE
            .. "/finish",

            withToken({
                uploadId =
                    State.UploadId,

                totalChunks =
                    State.UploadChunksSent,

                summary = {
                    area =
                        "Completo",

                    records =
                        State.RecordsStored,

                    historyRecords =
                        State.HistoryRecords,

                    newRecords =
                        State.NewRecords,

                    updatedRecords =
                        State.UpdatedRecords,

                    duplicatesFiltered =
                        State.DuplicatesFiltered,

                    chunks =
                        State.UploadChunksSent,

                    bytesApprox =
                        State.UploadBytesSent,

                    passes =
                        State.Pass,

                    clientVisibleOnly =
                        true,

                    deduplicated =
                        true,
                }
            }),

            "finalizando arquivo"
        )

    State.Uploading =
        false

    if not finishOk then
        State.UploadInProgress =
            false
        cancelRemoteUpload()

        setUploadStatus(
            "falha na finalização",
            COLORS.RED
        )

        Diagnostic.error(
            "upload_finish",
            finishResult
        )

        return false,
            finishResult
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
        url
        and tostring(url)
        or ""

    -- Força visual em 100% após /finish responder.
    State.UploadBytesSent =
        math.max(
            State.UploadBytesSent,
            State.UploadBytesTotal
        )

    State.UploadChunkCurrent =
        State.UploadChunksSent

    updateUploadUI()

    tweenBar(
        UploadBar,
        1
    )

    setUploadStatus(
        "concluído • arquivo recebido pelo servidor",
        COLORS.GREEN
    )

    -- Registra a etapa final sem enviar um POST intermediário
    -- com status "running". O finalizer faz o único envio final.
    do
        local step = {
            phase =
                "upload_complete",

            message =
                "Servidor confirmou upload",

            time =
                os.time(),

            records =
                State.RecordsStored,

            chunks =
                State.UploadChunksSent,

            bytes =
                State.UploadBytesSent,

            duplicatesFiltered =
                State.DuplicatesFiltered,

            hasDownloadUrl =
                url ~= nil,
        }

        local steps =
            Diagnostic.Report.steps

        local nextIndex =
            1

        while
            steps[
                tostring(nextIndex)
            ]
            ~= nil
        do
            nextIndex += 1
        end

        steps[
            tostring(nextIndex)
        ] = step
    end

    finalizeDiagnosticSuccess()

    return true, url
end

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

ScanButton.Activated:Connect(
    function()
        if
            State.Scanning
            or State.Uploading
            or State.UploadInProgress
        then
            setScanStatus(
                "envio em andamento • aguarde concluir",
                COLORS.ORANGE
            )

            return
        end

        task.spawn(function()
            local ok, err =
                xpcall(
                    runContinuousScan,
                    function(errorMessage)
                        local trace =
                            tostring(
                                errorMessage
                            )

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
                State.Scanning =
                    false

                ScanButton.Text =
                    "SCAM CONTÍNUO"

                setScanStatus(
                    "erro durante análise",
                    COLORS.RED
                )

                Diagnostic.error(
                    "continuous_scan",
                    err
                )
            end
        end)
    end
)

StopButton.Activated:Connect(
    function()
        if not State.Scanning then
            setScanStatus(
                "nenhuma análise em andamento",
                COLORS.ORANGE
            )

            return
        end

        State.StopRequested =
            true

        -- Ao parar a coleta, a área do servidor volta ao estado limpo.
        -- O envio só começa quando o usuário tocar em ENVIAR AO SERVIDOR.
        State.UploadId =
            nil

        State.UploadChunkCurrent =
            0

        State.UploadChunksSent =
            0

        State.UploadRecordsProcessed =
            0

        State.UploadBytesSent =
            0

        State.UploadStage =
            "Aguardando envio"

        tweenBar(
            UploadBar,
            0
        )

        setUploadStatus(
            "aguardando envio",
            COLORS.MUTED
        )

        setScanStatus(
            "parando... conteúdo será preservado",
            COLORS.YELLOW
        )

        Diagnostic.step(
            "stop_requested",
            "Parada solicitada pelo usuário"
        )
    end
)

UploadButton.Activated:Connect(
    function()
        if State.Scanning then
            setUploadStatus(
                "pare a análise antes de enviar",
                COLORS.ORANGE
            )

            return
        end

        if
            State.Uploading
            or State.UploadInProgress
        then
            setUploadStatus(
                "envio já está em andamento",
                COLORS.ORANGE
            )

            return
        end

        task.spawn(function()
            local ok, result =
                uploadAll()

            if not ok then
                setUploadStatus(
                    "erro • "
                    .. tostring(result),
                    COLORS.RED
                )
            end
        end)
    end
)

--==============================================================--
-- DRAG MOBILE
--==============================================================--

do
    local dragging =
        false

    local dragStart =
        nil

    local startPosition =
        nil

    Header.InputBegan:Connect(
        function(input)
            if
                input.UserInputType
                == Enum.UserInputType.Touch
                or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    Main.Position
            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)
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
                input.Position
                - dragStart

            Main.Position =
                UDim2.new(
                    startPosition.X.Scale,

                    startPosition.X.Offset
                    + delta.X,

                    startPosition.Y.Scale,

                    startPosition.Y.Offset
                    + delta.Y
                )
        end
    )

    UserInputService.InputEnded:Connect(
        function(input)
            if
                input.UserInputType
                == Enum.UserInputType.Touch
                or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging =
                    false
            end
        end
    )
end

--==============================================================--
-- READY
--==============================================================--

resetScan()
Diagnostic.start()

setScanStatus(
    "pronto para iniciar",
    COLORS.GREEN
)

setUploadStatus(
    "aguardando envio",
    COLORS.SUB
)

print(
    "[CAFEINA] Scamtest.lua V10 carregado."
)
