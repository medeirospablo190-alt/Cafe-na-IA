--==============================================================--
-- CAFEÍNA • SERVER SCANNER + AREA UPLOADER V3
--
-- CLIENT-VISIBLE ONLY
--
-- FUNÇÕES:
-- • Escanear primeiro, sem enviar automaticamente
-- • Navegação por áreas
-- • Visualizar conteúdo coletado
-- • Enviar somente a área aberta
-- • Enviar tudo
-- • Copiar conteúdo da área
-- • Copiar link
-- • Upload dividido em chunks
-- • Cancelamento
-- • Suporte mobile
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "V3",

    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    -- Se você configurar UPLOAD_TOKEN no Render,
    -- coloque o mesmo token aqui.
    UPLOAD_TOKEN = "",

    TARGET_CHUNK_BYTES = 3200000,

    MAX_TOTAL_BYTES =
        280 * 1024 * 1024,

    MAX_VIEW_CHARS =
        120000,

    MAX_OBJECTS =
        40000,

    YIELD_EVERY =
        120,

    RETRIES =
        3,

    RETRY_DELAY =
        1.25,

    REQUEST_TIMEOUT =
        75,

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

    AREAS = {
        "Resumo",
        "Objetos",
        "Remotes",
        "Scripts",
        "Valores",
        "Players",
        "GUI",
        "Midia",
    },
}

--==============================================================--
-- HTTP
--==============================================================--

local ExecutorRequest =
    (typeof(request) == "function" and request)
    or
    (typeof(http_request) == "function" and http_request)
    or
    (
        syn
        and typeof(syn.request) == "function"
        and syn.request
    )
    or nil

local SetClipboard =
    typeof(setclipboard) == "function"
    and setclipboard
    or
    (
        typeof(toclipboard) == "function"
        and toclipboard
        or nil
    )

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Scanning = false,
    Uploading = false,

    CancelRequested = false,

    Scanned = false,

    UploadId = nil,

    LastURL = "",

    CurrentArea = "Resumo",

    ObjectsScanned = 0,

    ServicesDone = 0,
    ServicesTotal = #CONFIG.SERVICES,

    ChunksSent = 0,
    BytesSent = 0,

    StartedAt = 0,

    AllRecords = {},

    Areas = {
        Resumo = {},
        Objetos = {},
        Remotes = {},
        Scripts = {},
        Valores = {},
        Players = {},
        GUI = {},
        Midia = {},
    },
}

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {
    BG =
        Color3.fromRGB(
            12,
            12,
            15
        ),

    PANEL =
        Color3.fromRGB(
            20,
            20,
            24
        ),

    PANEL2 =
        Color3.fromRGB(
            29,
            29,
            35
        ),

    CARD =
        Color3.fromRGB(
            25,
            25,
            30
        ),

    STROKE =
        Color3.fromRGB(
            55,
            55,
            65
        ),

    RED =
        Color3.fromRGB(
            235,
            38,
            52
        ),

    RED_DARK =
        Color3.fromRGB(
            110,
            20,
            30
        ),

    TEXT =
        Color3.fromRGB(
            245,
            245,
            248
        ),

    SUB =
        Color3.fromRGB(
            160,
            160,
            172
        ),

    GREEN =
        Color3.fromRGB(
            65,
            210,
            118
        ),

    YELLOW =
        Color3.fromRGB(
            242,
            184,
            57
        ),

    ORANGE =
        Color3.fromRGB(
            245,
            130,
            55
        ),
}

--==============================================================--
-- SAFE HELPERS
--==============================================================--

local function safeFullName(inst)
    local ok, result =
        pcall(function()
            return inst:GetFullName()
        end)

    if ok and result then
        return tostring(result)
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

    if not ok
        or type(attributes) ~= "table"
    then
        return result
    end

    for key, value in pairs(attributes) do
        local valueType =
            typeof(value)

        if
            valueType == "string"
            or valueType == "number"
            or valueType == "boolean"
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

local function countTable(map)
    local amount = 0

    for _ in pairs(map) do
        amount += 1
    end

    return amount
end

local function copyText(text)
    if not SetClipboard then
        return false
    end

    return pcall(
        SetClipboard,
        tostring(text or "")
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

local function formatBytes(bytes)
    bytes =
        tonumber(bytes)
        or 0

    if
        bytes >=
        1024 * 1024 * 1024
    then
        return string.format(
            "%.2f GB",
            bytes /
            (
                1024 * 1024 * 1024
            )
        )
    end

    if bytes >= 1024 * 1024 then
        return string.format(
            "%.2f MB",
            bytes /
            (
                1024 * 1024
            )
        )
    end

    if bytes >= 1024 then
        return string.format(
            "%.1f KB",
            bytes / 1024
        )
    end

    return tostring(bytes)
        .. " B"
end

--==============================================================--
-- TYPE CONVERTERS
--==============================================================--

local function vector3ToTable(value)
    if typeof(value) ~= "Vector3" then
        return tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
    }
end

local function vector2ToTable(value)
    if typeof(value) ~= "Vector2" then
        return tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
    }
end

local function color3ToTable(value)
    if typeof(value) ~= "Color3" then
        return tostring(value)
    end

    return {
        r = value.R,
        g = value.G,
        b = value.B,
    }
end

local function udim2ToTable(value)
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

local function cframeToTable(value)
    if typeof(value) ~= "CFrame" then
        return tostring(value)
    end

    local components =
        {
            value:GetComponents()
        }

    return components
end

--==============================================================--
-- SERIALIZE INSTANCE
--==============================================================--

local function serializeInstance(
    inst,
    serviceName
)
    local attributes =
        safeAttributes(inst)

    local data = {
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

        childCount =
            0,

        attributeCount =
            countTable(attributes),

        attributes =
            attributes,
    }

    pcall(function()
        data.childCount =
            #inst:GetChildren()
    end)

    --==========================================================--
    -- VALUES
    --==========================================================--

    if inst:IsA("ValueBase") then
        local value =
            safeGet(
                inst,
                "Value"
            )

        local valueType =
            typeof(value)

        if
            valueType == "string"
            or valueType == "number"
            or valueType == "boolean"
        then
            data.value =
                value
        else
            data.value =
                tostring(value)
        end
    end

    --==========================================================--
    -- PARTS
    --==========================================================--

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
                vector3ToTable(
                    safeGet(
                        inst,
                        "Position"
                    )
                ),

            size =
                vector3ToTable(
                    safeGet(
                        inst,
                        "Size"
                    )
                ),

            cframe =
                cframeToTable(
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
                color3ToTable(
                    safeGet(
                        inst,
                        "Color"
                    )
                ),
        }
    end

    --==========================================================--
    -- MODEL
    --==========================================================--

    if inst:IsA("Model") then
        data.properties =
            data.properties
            or {}

        local primary =
            safeGet(
                inst,
                "PrimaryPart"
            )

        data.properties.primaryPart =
            primary
            and safeFullName(primary)
            or nil
    end

    --==========================================================--
    -- TOOL
    --==========================================================--

    if inst:IsA("Tool") then
        data.properties =
            data.properties
            or {}

        data.properties.requiresHandle =
            safeGet(
                inst,
                "RequiresHandle"
            )

        data.properties.canBeDropped =
            safeGet(
                inst,
                "CanBeDropped"
            )

        data.properties.toolTip =
            tostring(
                safeGet(
                    inst,
                    "ToolTip"
                )
                or ""
            )
    end

    --==========================================================--
    -- REMOTES
    --==========================================================--

    local isRemote =
        inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")

    pcall(function()
        if inst:IsA(
            "UnreliableRemoteEvent"
        ) then
            isRemote = true
        end
    end)

    if isRemote then
        data.remote = {
            type =
                tostring(
                    inst.ClassName
                ),

            path =
                safeFullName(inst),
        }
    end

    --==========================================================--
    -- GUI
    --==========================================================--

    if inst:IsA("GuiObject") then
        data.properties =
            data.properties
            or {}

        data.properties.visible =
            safeGet(
                inst,
                "Visible"
            )

        data.properties.active =
            safeGet(
                inst,
                "Active"
            )

        data.properties.position =
            udim2ToTable(
                safeGet(
                    inst,
                    "Position"
                )
            )

        data.properties.size =
            udim2ToTable(
                safeGet(
                    inst,
                    "Size"
                )
            )

        data.properties.anchorPoint =
            vector2ToTable(
                safeGet(
                    inst,
                    "AnchorPoint"
                )
            )

        data.properties.backgroundTransparency =
            safeGet(
                inst,
                "BackgroundTransparency"
            )

        if
            inst:IsA("TextLabel")
            or inst:IsA("TextButton")
            or inst:IsA("TextBox")
        then
            data.properties.text =
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
            data.properties.image =
                tostring(
                    safeGet(
                        inst,
                        "Image"
                    )
                    or ""
                )
        end
    end

    --==========================================================--
    -- TEXTURES
    --==========================================================--

    if
        inst:IsA("Decal")
        or inst:IsA("Texture")
    then
        data.properties =
            data.properties
            or {}

        data.properties.texture =
            tostring(
                safeGet(
                    inst,
                    "Texture"
                )
                or ""
            )

        data.properties.transparency =
            safeGet(
                inst,
                "Transparency"
            )
    end

    --==========================================================--
    -- SOUND
    --==========================================================--

    if inst:IsA("Sound") then
        data.properties =
            data.properties
            or {}

        data.properties.soundId =
            tostring(
                safeGet(
                    inst,
                    "SoundId"
                )
                or ""
            )

        data.properties.volume =
            safeGet(
                inst,
                "Volume"
            )

        data.properties.looped =
            safeGet(
                inst,
                "Looped"
            )

        data.properties.playbackSpeed =
            safeGet(
                inst,
                "PlaybackSpeed"
            )
    end

    --==========================================================--
    -- HUMANOID
    --==========================================================--

    if inst:IsA("Humanoid") then
        data.properties =
            data.properties
            or {}

        data.properties.health =
            safeGet(
                inst,
                "Health"
            )

        data.properties.maxHealth =
            safeGet(
                inst,
                "MaxHealth"
            )

        data.properties.walkSpeed =
            safeGet(
                inst,
                "WalkSpeed"
            )

        data.properties.jumpPower =
            safeGet(
                inst,
                "JumpPower"
            )

        data.properties.rigType =
            tostring(
                safeGet(
                    inst,
                    "RigType"
                )
                or ""
            )
    end

    --==========================================================--
    -- PLAYER
    --==========================================================--

    if inst:IsA("Player") then
        data.properties =
            data.properties
            or {}

        data.properties.displayName =
            tostring(
                safeGet(
                    inst,
                    "DisplayName"
                )
                or ""
            )

        data.properties.userId =
            safeGet(
                inst,
                "UserId"
            )

        data.properties.accountAge =
            safeGet(
                inst,
                "AccountAge"
            )

        local team =
            safeGet(
                inst,
                "Team"
            )

        data.properties.team =
            team
            and tostring(team.Name)
            or nil
    end

    --==========================================================--
    -- SCRIPT
    --==========================================================--

    if inst:IsA("LuaSourceContainer") then
        data.script = {
            type =
                tostring(
                    inst.ClassName
                ),

            disabled =
                safeGet(
                    inst,
                    "Disabled"
                ),

            path =
                safeFullName(inst),
        }
    end

    return data
end

--==============================================================--
-- CLASSIFY
--==============================================================--

local function addArea(
    area,
    record
)
    if not State.Areas[area] then
        return
    end

    State.Areas[area][
        #State.Areas[area] + 1
    ] = record
end

local function classifyRecord(
    inst,
    record
)
    State.AllRecords[
        #State.AllRecords + 1
    ] = record

    addArea(
        "Objetos",
        record
    )

    local remote =
        inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")

    pcall(function()
        if inst:IsA(
            "UnreliableRemoteEvent"
        ) then
            remote = true
        end
    end)

    if remote then
        addArea(
            "Remotes",
            record
        )
    end

    if inst:IsA(
        "LuaSourceContainer"
    ) then
        addArea(
            "Scripts",
            record
        )
    end

    if inst:IsA(
        "ValueBase"
    ) then
        addArea(
            "Valores",
            record
        )
    end

    if inst:IsA("Player") then
        addArea(
            "Players",
            record
        )
    end

    if inst:IsA(
        "GuiObject"
    ) then
        addArea(
            "GUI",
            record
        )
    end

    if
        inst:IsA("Sound")
        or inst:IsA("Decal")
        or inst:IsA("Texture")
        or inst:IsA("ImageLabel")
        or inst:IsA("ImageButton")
    then
        addArea(
            "Midia",
            record
        )
    end
end

--==============================================================--
-- METADATA
--==============================================================--

local function buildMetadata()
    return {
        generatedBy =
            "CAFEINA SERVER SCANNER",

        scannerVersion =
            CONFIG.VERSION,

        generatedAtUnix =
            os.time(),

        clientVisibleOnly =
            true,

        game = {
            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId,

            creatorId =
                game.CreatorId,

            placeVersion =
                game.PlaceVersion,
        },

        scanner = {
            services =
                CONFIG.SERVICES,

            maxObjects =
                CONFIG.MAX_OBJECTS,

            targetChunkBytes =
                CONFIG.TARGET_CHUNK_BYTES,
        },
    }
end

--==============================================================--
-- SUMMARY
--==============================================================--

local function rebuildSummary()
    State.Areas.Resumo = {
        {
            recordType =
                "summary",

            metadata =
                buildMetadata(),

            scan = {
                objects =
                    State.ObjectsScanned,

                services =
                    State.ServicesDone,

                remotes =
                    #State.Areas.Remotes,

                scripts =
                    #State.Areas.Scripts,

                values =
                    #State.Areas.Valores,

                players =
                    #State.Areas.Players,

                gui =
                    #State.Areas.GUI,

                media =
                    #State.Areas.Midia,
            }
        }
    }
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

        if ok then
            return decoded
        end

        return nil
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

    if ok then
        return decoded
    end

    return nil
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

                    Body =
                        body,
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
                or
                (
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

        return true,
            decoded
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

                Body =
                    body,
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
            or
            (
                "HTTP "
                .. tostring(
                    response.StatusCode
                )
            )
    end

    return true,
        decoded
end

local function requestWithTimeout(
    url,
    payload
)
    local finished =
        false

    local requestOk =
        false

    local requestResult =
        nil

    task.spawn(function()
        requestOk,
        requestResult =
            rawRequest(
                url,
                payload
            )

        finished = true
    end)

    local start =
        os.clock()

    while not finished do
        if State.CancelRequested then
            return false,
                "Cancelado"
        end

        if
            os.clock() - start
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

local function withToken(payload)
    if CONFIG.UPLOAD_TOKEN ~= "" then
        payload.token =
            CONFIG.UPLOAD_TOKEN
    end

    return payload
end

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function create(
    className,
    props
)
    local object =
        Instance.new(
            className
        )

    for key, value
        in pairs(props or {})
    do
        object[key] =
            value
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

            Parent =
                parent,
        }
    )
end

local function stroke(
    parent,
    color,
    thickness
)
    return create(
        "UIStroke",
        {
            Color =
                color
                or COLORS.STROKE,

            Thickness =
                thickness
                or 1,

            Parent =
                parent,
        }
    )
end

--==============================================================--
-- GUI PARENT
--==============================================================--

local GuiParent = nil

if typeof(gethui) == "function" then
    local ok, parent =
        pcall(gethui)

    if ok then
        GuiParent = parent
    end
end

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui"
    )

local Gui =
    create(
        "ScreenGui",
        {
            Name =
                "CafeinaScannerAreaV3",

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
        PlayerGui
end

--==============================================================--
-- REMOVE OLD
--==============================================================--

for _, object in ipairs(
    Gui.Parent:GetChildren()
) do
    if
        object ~= Gui
        and object.Name
        == "CafeinaScannerAreaV3"
    then
        object:Destroy()
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
                UDim2.fromScale(
                    0.9,
                    0.78
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

--==============================================================--
-- HEADER
--==============================================================--

local Header =
    create(
        "Frame",
        {
            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    56
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
                -100,
                0,
                24
            ),

        BackgroundTransparency =
            1,

        Text =
            "CAFEÍNA • SERVER SCANNER",

        TextColor3 =
            COLORS.TEXT,

        Font =
            Enum.Font.GothamBold,

        TextSize =
            16,

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
                30
            ),

        Size =
            UDim2.new(
                1,
                -100,
                0,
                16
            ),

        BackgroundTransparency =
            1,

        Text =
            "V3 • CLIENT-VISIBLE • ENVIO POR ÁREA",

        TextColor3 =
            COLORS.SUB,

        Font =
            Enum.Font.Gotham,

        TextSize =
            10,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

local Minimize =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    1,
                    -76,
                    0,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    30,
                    30
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            Text =
                "—",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                17,

            BorderSizePixel =
                0,

            Parent =
                Header,
        }
    )

corner(Minimize, 8)

local Close =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    1,
                    -40,
                    0,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    30,
                    30
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            Text =
                "×",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                19,

            BorderSizePixel =
                0,

            Parent =
                Header,
        }
    )

corner(Close, 8)

--==============================================================--
-- STATUS
--==============================================================--

local StatusCard =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    0,
                    64
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
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

corner(StatusCard, 10)

local StatusDot =
    create(
        "Frame",
        {
            Position =
                UDim2.fromOffset(
                    11,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    9,
                    9
                ),

            BackgroundColor3 =
                COLORS.GREEN,

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
        }
    )

corner(StatusDot, 99)

local StatusText =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    28,
                    5
                ),

            Size =
                UDim2.new(
                    1,
                    -38,
                    0,
                    22
                ),

            BackgroundTransparency =
                1,

            Text =
                "Pronto",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                11,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusCard,
        }
    )

local DetailText =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    11,
                    27
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    18
                ),

            BackgroundTransparency =
                1,

            Text =
                "0 objetos • 0 chunks • 0 B",

            TextColor3 =
                COLORS.SUB,

            Font =
                Enum.Font.Gotham,

            TextSize =
                9,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusCard,
        }
    )

local ProgressBG =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    11,
                    1,
                    -9
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    5
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
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

            BorderSizePixel =
                0,

            Parent =
                ProgressBG,
        }
    )

corner(ProgressFill, 99)

--==============================================================--
-- BODY
--==============================================================--

local Sidebar =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    0,
                    130
                ),

            Size =
                UDim2.new(
                    0.29,
                    -5,
                    1,
                    -138
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(Sidebar, 10)

local Content =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0.29,
                    7,
                    0,
                    130
                ),

            Size =
                UDim2.new(
                    0.71,
                    -15,
                    1,
                    -138
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(Content, 10)

--==============================================================--
-- SIDEBAR BUTTONS
--==============================================================--

local ScanButton =
    create(
        "TextButton",
        {
            Position =
                UDim2.fromOffset(
                    7,
                    7
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    0,
                    40
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "ESCANEAR",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                11,

            Parent =
                Sidebar,
        }
    )

corner(ScanButton, 8)

local AreaList =
    create(
        "ScrollingFrame",
        {
            Position =
                UDim2.fromOffset(
                    7,
                    54
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    1,
                    -108
                ),

            BackgroundTransparency =
                1,

            BorderSizePixel =
                0,

            ScrollBarThickness =
                3,

            CanvasSize =
                UDim2.new(),

            AutomaticCanvasSize =
                Enum.AutomaticSize.Y,

            Parent =
                Sidebar,
        }
    )

local AreaLayout =
    create(
        "UIListLayout",
        {
            Padding =
                UDim.new(
                    0,
                    5
                ),

            Parent =
                AreaList,
        }
    )

local SendAllButton =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0,
                    7,
                    1,
                    -47
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    0,
                    40
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            BorderSizePixel =
                0,

            Text =
                "ENVIAR TUDO",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            Parent =
                Sidebar,
        }
    )

corner(SendAllButton, 8)

--==============================================================--
-- CONTENT
--==============================================================--

local AreaTitle =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    10,
                    6
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    24
                ),

            BackgroundTransparency =
                1,

            Text =
                "RESUMO",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                13,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                Content,
        }
    )

local Viewer =
    create(
        "TextBox",
        {
            Position =
                UDim2.fromOffset(
                    8,
                    35
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    1,
                    -125
                ),

            BackgroundColor3 =
                COLORS.BG,

            BorderSizePixel =
                0,

            Text =
                "Execute o scanner para visualizar os dados.",

            TextColor3 =
                COLORS.TEXT,

            TextSize =
                10,

            Font =
                Enum.Font.Code,

            TextWrapped =
                false,

            MultiLine =
                true,

            ClearTextOnFocus =
                false,

            TextEditable =
                false,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent =
                Content,
        }
    )

corner(Viewer, 8)

local SendAreaButton =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    1,
                    -82
                ),

            Size =
                UDim2.new(
                    0.49,
                    -4,
                    0,
                    34
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "ENVIAR ESTA ÁREA",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Content,
        }
    )

corner(SendAreaButton, 8)

local CopyAreaButton =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0.51,
                    4,
                    1,
                    -82
                ),

            Size =
                UDim2.new(
                    0.49,
                    -12,
                    0,
                    34
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Text =
                "COPIAR CONTEÚDO",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Content,
        }
    )

corner(CopyAreaButton, 8)

local LinkBox =
    create(
        "TextBox",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    1,
                    -41
                ),

            Size =
                UDim2.new(
                    1,
                    -93,
                    0,
                    32
                ),

            BackgroundColor3 =
                COLORS.BG,

            BorderSizePixel =
                0,

            Text =
                "Link aparecerá aqui.",

            TextColor3 =
                COLORS.SUB,

            Font =
                Enum.Font.Code,

            TextSize =
                9,

            ClearTextOnFocus =
                false,

            TextEditable =
                false,

            Parent =
                Content,
        }
    )

corner(LinkBox, 7)

local CopyLinkButton =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    1,
                    -79,
                    1,
                    -41
                ),

            Size =
                UDim2.fromOffset(
                    71,
                    32
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            BorderSizePixel =
                0,

            Text =
                "COPIAR LINK",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                8,

            Parent =
                Content,
        }
    )

corner(CopyLinkButton, 7)

--==============================================================--
-- MINI
--==============================================================--

local Mini =
    create(
        "TextButton",
        {
            Visible =
                false,

            Size =
                UDim2.fromOffset(
                    52,
                    52
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
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "C",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBlack,

            TextSize =
                19,

            Parent =
                Gui,
        }
    )

corner(Mini, 99)

--==============================================================--
-- UI FUNCTIONS
--==============================================================--

local function setStatus(
    text,
    color
)
    StatusText.Text =
        tostring(text or "")

    if color then
        StatusDot.BackgroundColor3 =
            color
    end
end

local function setProgress(value)
    value =
        math.clamp(
            tonumber(value)
            or 0,
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
    DetailText.Text =
        tostring(
            State.ObjectsScanned
        )
        .. " objetos • "
        .. tostring(
            State.ChunksSent
        )
        .. " chunks • "
        .. formatBytes(
            State.BytesSent
        )
end

--==============================================================--
-- PREVIEW
--==============================================================--

local function buildAreaPreview(areaName)
    local records =
        State.Areas[areaName]
        or {}

    local output = {
        "CAFEINA • "
        .. string.upper(areaName),

        "",

        "Registros: "
        .. tostring(#records),

        "",
    }

    local totalChars =
        0

    for index, record
        in ipairs(records)
    do
        local line

        if areaName == "Resumo" then
            local ok, encoded =
                pcall(function()
                    return HttpService:JSONEncode(
                        record
                    )
                end)

            line =
                ok
                and encoded
                or "[erro]"
        else
            line =
                "["
                .. tostring(
                    record.className
                    or record.recordType
                    or "?"
                )
                .. "] "
                .. tostring(
                    record.path
                    or record.name
                    or ""
                )

            if record.value ~= nil then
                line =
                    line
                    .. " = "
                    .. tostring(
                        record.value
                    )
            end
        end

        totalChars +=
            #line + 1

        if
            totalChars
            > CONFIG.MAX_VIEW_CHARS
        then
            output[
                #output + 1
            ] =
                ""

            output[
                #output + 1
            ] =
                "[VISUALIZAÇÃO LIMITADA]"

            output[
                #output + 1
            ] =
                "O envio ainda inclui todos os registros."

            break
        end

        output[
            #output + 1
        ] =
            line

        if index % 200 == 0 then
            task.wait()
        end
    end

    return table.concat(
        output,
        "\n"
    )
end

local AreaButtons = {}

local function openArea(areaName)
    if not State.Areas[areaName] then
        return
    end

    State.CurrentArea =
        areaName

    AreaTitle.Text =
        string.upper(
            areaName
        )

    Viewer.Text =
        buildAreaPreview(
            areaName
        )

    for name, button
        in pairs(AreaButtons)
    do
        button.BackgroundColor3 =
            name == areaName
            and COLORS.RED_DARK
            or COLORS.PANEL2
    end

    setStatus(
        areaName
        .. " • "
        .. tostring(
            #State.Areas[areaName]
        )
        .. " registros",

        COLORS.GREEN
    )
end

--==============================================================--
-- AREA BUTTON CREATION
--==============================================================--

for _, areaName
    in ipairs(CONFIG.AREAS)
do
    local button =
        create(
            "TextButton",
            {
                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        34
                    ),

                BackgroundColor3 =
                    COLORS.PANEL2,

                BorderSizePixel =
                    0,

                Text =
                    string.upper(
                        areaName
                    ),

                TextColor3 =
                    COLORS.TEXT,

                Font =
                    Enum.Font.GothamMedium,

                TextSize =
                    9,

                Parent =
                    AreaList,
            }
        )

    corner(button, 7)

    button.Activated:Connect(
        function()
            openArea(
                areaName
            )
        end
    )

    AreaButtons[areaName] =
        button
end

--==============================================================--
-- RESET SCAN
--==============================================================--

local function resetScan()
    State.AllRecords =
        {}

    for areaName in pairs(
        State.Areas
    ) do
        State.Areas[areaName] =
            {}
    end

    State.ObjectsScanned =
        0

    State.ServicesDone =
        0

    State.Scanned =
        false

    State.LastURL =
        ""

    State.ChunksSent =
        0

    State.BytesSent =
        0

    LinkBox.Text =
        "Link aparecerá aqui."

    Viewer.Text =
        "Escaneando..."
end

--==============================================================--
-- SCAN
--==============================================================--

local function runScanner()
    if State.Scanning
        or State.Uploading
    then
        return
    end

    State.Scanning =
        true

    State.CancelRequested =
        false

    State.StartedAt =
        os.clock()

    resetScan()

    ScanButton.Text =
        "ESCANEANDO..."

    setProgress(0)

    for serviceIndex, serviceName
        in ipairs(CONFIG.SERVICES)
    do
        if State.CancelRequested then
            break
        end

        if
            State.ObjectsScanned
            >= CONFIG.MAX_OBJECTS
        then
            break
        end

        local serviceOk, service =
            pcall(function()
                return game:GetService(
                    serviceName
                )
            end)

        if serviceOk
            and service
        then
            setStatus(
                "Escaneando "
                .. serviceName
                .. "...",

                COLORS.YELLOW
            )

            local descendants =
                {}

            pcall(function()
                descendants =
                    service:GetDescendants()
            end)

            for index, inst
                in ipairs(descendants)
            do
                if State.CancelRequested then
                    break
                end

                if
                    State.ObjectsScanned
                    >= CONFIG.MAX_OBJECTS
                then
                    break
                end

                local ok, record =
                    pcall(
                        serializeInstance,
                        inst,
                        serviceName
                    )

                if
                    ok
                    and type(record)
                    == "table"
                then
                    classifyRecord(
                        inst,
                        record
                    )

                    State.ObjectsScanned +=
                        1
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

        State.ServicesDone =
            serviceIndex

        setProgress(
            serviceIndex
            / State.ServicesTotal
        )

        updateDetails()

        task.wait()
    end

    rebuildSummary()

    State.Scanning =
        false

    ScanButton.Text =
        "ESCANEAR"

    if State.CancelRequested then
        setStatus(
            "Scanner cancelado",
            COLORS.ORANGE
        )

        return
    end

    State.Scanned =
        true

    setProgress(1)

    updateDetails()

    setStatus(
        "Scan pronto • "
        .. tostring(
            State.ObjectsScanned
        )
        .. " objetos",

        COLORS.GREEN
    )

    openArea(
        "Resumo"
    )
end

--==============================================================--
-- REQUEST RETRY
--==============================================================--

local function requestRetry(
    url,
    payload,
    label
)
    local lastError =
        "Falha desconhecida"

    for attempt = 1,
        CONFIG.RETRIES
    do
        if State.CancelRequested then
            return false,
                "Cancelado"
        end

        local ok, result =
            requestWithTimeout(
                url,
                payload
            )

        if ok then
            return true,
                result
        end

        lastError =
            tostring(result)

        if attempt < CONFIG.RETRIES then
            setStatus(
                label
                .. " • tentativa "
                .. tostring(
                    attempt + 1
                ),

                COLORS.YELLOW
            )

            task.wait(
                CONFIG.RETRY_DELAY
                * attempt
            )
        end
    end

    return false,
        lastError
end

--==============================================================--
-- UPLOAD CANCEL
--==============================================================--

local function cancelUpload()
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
-- UPLOAD RECORDS
--==============================================================--

local function uploadRecords(
    records,
    areaName
)
    if State.Uploading
        or State.Scanning
    then
        return false,
            "Outra operação está em andamento"
    end

    if not State.Scanned then
        return false,
            "Execute o scanner primeiro"
    end

    if
        type(records) ~= "table"
        or #records < 1
    then
        return false,
            "Área vazia"
    end

    State.Uploading =
        true

    State.CancelRequested =
        false

    State.UploadId =
        nil

    State.ChunksSent =
        0

    State.BytesSent =
        0

    setProgress(0)

    updateDetails()

    --==========================================================--
    -- START
    --==========================================================--

    setStatus(
        "Abrindo upload de "
        .. areaName
        .. "...",

        COLORS.YELLOW
    )

    local timestamp =
        os.date(
            "!%Y%m%d_%H%M%S"
        )

    local filename =
        sanitizeFileName(
            "Cafeina_"
            .. areaName
            .. "_"
            .. tostring(
                game.PlaceId
            )
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
                    "cafeina-area-upload",

                metadata = {
                    area =
                        areaName,

                    recordCount =
                        #records,

                    clientVisibleOnly =
                        true,

                    scanner =
                        buildMetadata(),
                }
            }),

            "Abrindo upload"
        )

    if
        not startOk
        or type(startResult)
        ~= "table"
        or not startResult.uploadId
    then
        State.Uploading =
            false

        return false,
            startResult
            or "uploadId não retornado"
    end

    State.UploadId =
        tostring(
            startResult.uploadId
        )

    --==========================================================--
    -- LOCAL CHUNK
    --==========================================================--

    local chunk =
        {}

    local chunkBytes =
        2

    local function flushChunk()
        if #chunk == 0 then
            return true
        end

        if State.CancelRequested then
            return false,
                "Cancelado"
        end

        local chunkIndex =
            State.ChunksSent
            + 1

        setStatus(
            "Enviando "
            .. areaName
            .. " • parte "
            .. tostring(
                chunkIndex
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

        local uploadOk,
        uploadResult =
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
                .. tostring(
                    chunkIndex
                )
            )

        if not uploadOk then
            return false,
                uploadResult
        end

        State.ChunksSent =
            chunkIndex

        State.BytesSent +=
            #encoded

        updateDetails()

        chunk = {}
        chunkBytes = 2

        return true
    end

    --==========================================================--
    -- HEADER
    --==========================================================--

    chunk[
        #chunk + 1
    ] = {
        recordType =
            "area_header",

        area =
            areaName,

        metadata =
            buildMetadata(),

        recordCount =
            #records,
    }

    --==========================================================--
    -- RECORDS
    --==========================================================--

    for index, record
        in ipairs(records)
    do
        if State.CancelRequested then
            cancelUpload()

            State.Uploading =
                false

            return false,
                "Cancelado"
        end

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
                State.BytesSent
                + chunkBytes
                + recordBytes
                >= CONFIG.MAX_TOTAL_BYTES
            then
                cancelUpload()

                State.Uploading =
                    false

                return false,
                    "Limite máximo de upload atingido"
            end

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
                    cancelUpload()

                    State.Uploading =
                        false

                    return false,
                        flushError
                end
            end

            chunk[
                #chunk + 1
            ] =
                record

            chunkBytes +=
                recordBytes
        end

        if index % 100 == 0 then
            setProgress(
                (index / #records)
                * 0.9
            )

            task.wait()
        end
    end

    local flushOk,
    flushError =
        flushChunk()

    if not flushOk then
        cancelUpload()

        State.Uploading =
            false

        return false,
            flushError
    end

    --==========================================================--
    -- FINISH
    --==========================================================--

    setProgress(0.95)

    setStatus(
        "Finalizando "
        .. areaName
        .. "...",

        COLORS.YELLOW
    )

    local finishOk,
    finishResult =
        requestRetry(
            CONFIG.UPLOAD_BASE
            .. "/finish",

            withToken({
                uploadId =
                    State.UploadId,

                totalChunks =
                    State.ChunksSent,

                summary = {
                    area =
                        areaName,

                    records =
                        #records,

                    chunks =
                        State.ChunksSent,

                    bytesApprox =
                        State.BytesSent,

                    clientVisibleOnly =
                        true,
                }
            }),

            "Finalizando"
        )

    State.Uploading =
        false

    if not finishOk then
        cancelUpload()

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

    if url then
        State.LastURL =
            tostring(url)

        LinkBox.Text =
            State.LastURL

        copyText(
            State.LastURL
        )
    else
        LinkBox.Text =
            "Upload concluído, mas nenhum link foi retornado."
    end

    setProgress(1)

    updateDetails()

    return true,
        url
end

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

ScanButton.Activated:Connect(
    function()
        if State.Scanning then
            State.CancelRequested =
                true

            setStatus(
                "Cancelando scanner...",
                COLORS.YELLOW
            )

            return
        end

        if State.Uploading then
            return
        end

        task.spawn(function()
            local ok, err =
                pcall(
                    runScanner
                )

            if not ok then
                State.Scanning =
                    false

                ScanButton.Text =
                    "ESCANEAR"

                setStatus(
                    "Erro no scanner",
                    COLORS.RED
                )

                Viewer.Text =
                    tostring(err)
            end
        end)
    end
)

SendAreaButton.Activated:Connect(
    function()
        if State.Uploading
            or State.Scanning
        then
            return
        end

        local areaName =
            State.CurrentArea

        local records =
            State.Areas[
                areaName
            ]

        task.spawn(function()
            local ok, result =
                uploadRecords(
                    records,
                    areaName
                )

            if ok then
                setStatus(
                    areaName
                    .. " enviada com sucesso",

                    COLORS.GREEN
                )
            else
                setStatus(
                    "Erro ao enviar "
                    .. areaName,

                    COLORS.RED
                )

                LinkBox.Text =
                    tostring(result)
            end
        end)
    end
)

SendAllButton.Activated:Connect(
    function()
        if State.Uploading
            or State.Scanning
        then
            return
        end

        task.spawn(function()
            local ok, result =
                uploadRecords(
                    State.AllRecords,
                    "Completo"
                )

            if ok then
                setStatus(
                    "Scan completo enviado",
                    COLORS.GREEN
                )
            else
                setStatus(
                    "Erro no envio completo",
                    COLORS.RED
                )

                LinkBox.Text =
                    tostring(result)
            end
        end)
    end
)

CopyAreaButton.Activated:Connect(
    function()
        local text =
            buildAreaPreview(
                State.CurrentArea
            )

        local ok =
            copyText(text)

        setStatus(
            ok
            and "Conteúdo copiado"
            or "Clipboard indisponível",

            ok
            and COLORS.GREEN
            or COLORS.YELLOW
        )
    end
)

CopyLinkButton.Activated:Connect(
    function()
        if State.LastURL == "" then
            setStatus(
                "Nenhum link pronto",
                COLORS.YELLOW
            )

            return
        end

        local ok =
            copyText(
                State.LastURL
            )

        setStatus(
            ok
            and "Link copiado"
            or "Erro ao copiar",

            ok
            and COLORS.GREEN
            or COLORS.RED
        )
    end
)

--==============================================================--
-- MINIMIZE / CLOSE
--==============================================================--

Minimize.Activated:Connect(
    function()
        Main.Visible =
            false

        Mini.Visible =
            true
    end
)

Mini.Activated:Connect(
    function()
        Mini.Visible =
            false

        Main.Visible =
            true
    end
)

Close.Activated:Connect(
    function()
        State.CancelRequested =
            true

        if State.Uploading then
            cancelUpload()
        end

        Gui:Destroy()
    end
)

--==============================================================--
-- DRAG MOBILE
--==============================================================--

local function makeDraggable(
    target,
    handle
)
    local dragging =
        false

    local dragStart =
        nil

    local startPosition =
        nil

    handle.InputBegan:Connect(
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
                    target.Position
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

            target.Position =
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

makeDraggable(
    Main,
    Header
)

--==============================================================--
-- READY
--==============================================================--

rebuildSummary()

openArea(
    "Resumo"
)

setProgress(0)

updateDetails()

setStatus(
    "Pronto para escanear",
    COLORS.GREEN
)

print(
    "[CAFEINA V3] Scanner por área carregado."
)
