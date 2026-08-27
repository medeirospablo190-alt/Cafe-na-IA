--==============================================================--
-- CAFEÍNA • SERVER SCAN UPLOADER V2
--
-- Objetivo:
-- Escanear informações replicadas/visíveis ao cliente
-- e enviar automaticamente para o site CAFEÍNA.
--
-- Não acessa conteúdo exclusivamente server-side.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    error("[CAFEÍNA] LocalPlayer não encontrado.")
end

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    BASE_URL = "https://cafe-na-ia.onrender.com",
    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    -- Se você configurar UPLOAD_TOKEN no Render,
    -- coloque o MESMO token aqui.
    UPLOAD_TOKEN = "",

    TARGET_CHUNK_BYTES = 3200000,
    MAX_TOTAL_BYTES = 280 * 1024 * 1024,

    YIELD_EVERY = 100,

    RETRIES = 3,
    RETRY_DELAY = 1.25,

    REQUEST_TIMEOUT = 75,

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
-- HTTP / CLIPBOARD
--==============================================================--

local ExecutorRequest =
    (typeof(request) == "function" and request)
    or (typeof(http_request) == "function" and http_request)
    or (
        syn
        and typeof(syn.request) == "function"
        and syn.request
    )
    or nil

local SetClipboard =
    typeof(setclipboard) == "function"
    and setclipboard
    or nil

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Running = false,
    CancelRequested = false,

    UploadId = nil,
    LastURL = "",

    ObjectsScanned = 0,
    ChunksSent = 0,
    BytesSent = 0,

    ServicesDone = 0,
    ServicesTotal = #CONFIG.SERVICES,

    StartedAt = 0,
}

--==============================================================--
-- SAFE HELPERS
--==============================================================--

local function safeFullName(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    if ok and result then
        return tostring(result)
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

    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return result
    end

    for key, value in pairs(attrs) do
        local valueType = typeof(value)

        if
            valueType == "string"
            or valueType == "number"
            or valueType == "boolean"
        then
            result[tostring(key)] = value
        else
            result[tostring(key)] = tostring(value)
        end
    end

    return result
end

local function countTable(map)
    local count = 0

    for _ in pairs(map) do
        count += 1
    end

    return count
end

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

local function cframeToTable(value)
    if typeof(value) ~= "CFrame" then
        return tostring(value)
    end

    local x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22 =
        value:GetComponents()

    return {
        position = {
            x = x,
            y = y,
            z = z,
        },

        rotation = {
            r00, r01, r02,
            r10, r11, r12,
            r20, r21, r22,
        },
    }
end

local function sanitizeFileName(text)
    local name = tostring(text or "scan")

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

--==============================================================--
-- SERIALIZAÇÃO
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
            and safeFullName(
                inst.Parent
            )
            or nil,

        childCount =
            0,

        attributes =
            attributes,

        attributeCount =
            countTable(
                attributes
            ),
    }

    pcall(function()
        data.childCount =
            #inst:GetChildren()
    end)

    --==========================================================--
    -- VALUE
    --==========================================================--

    if inst:IsA("ValueBase") then
        data.value =
            tostring(
                safeGet(
                    inst,
                    "Value"
                )
            )
    end

    --==========================================================--
    -- PART
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
        local primaryPart =
            safeGet(
                inst,
                "PrimaryPart"
            )

        data.properties =
            data.properties or {}

        data.properties.primaryPart =
            primaryPart
            and safeFullName(
                primaryPart
            )
            or nil
    end

    --==========================================================--
    -- TOOL
    --==========================================================--

    if inst:IsA("Tool") then
        data.properties =
            data.properties or {}

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
        if inst:IsA("UnreliableRemoteEvent") then
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
                safeFullName(
                    inst
                ),
        }
    end

    --==========================================================--
    -- GUI
    --==========================================================--

    if inst:IsA("GuiObject") then
        data.properties =
            data.properties or {}

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
            data.properties or {}

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
            data.properties or {}

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
            data.properties or {}

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
            )
    end

    --==========================================================--
    -- PLAYER
    --==========================================================--

    if inst:IsA("Player") then
        data.properties =
            data.properties or {}

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
            and tostring(
                team.Name
            )
            or nil
    end

    --==========================================================--
    -- SCRIPT METADATA
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
                safeFullName(
                    inst
                ),
        }
    end

    return data
end

--==============================================================--
-- METADATA
--==============================================================--

local function buildGameMetadata()
    return {
        generatedBy =
            "CAFEÍNA SERVER SCAN UPLOADER",

        scannerVersion =
            "V2",

        generatedAtUnix =
            os.time(),

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

        client = {
            userId =
                LocalPlayer.UserId,

            username =
                LocalPlayer.Name,

            displayName =
                LocalPlayer.DisplayName,
        },

        scanner = {
            mode =
                "client-visible-only",

            services =
                CONFIG.SERVICES,

            maxTotalBytes =
                CONFIG.MAX_TOTAL_BYTES,

            targetChunkBytes =
                CONFIG.TARGET_CHUNK_BYTES,
        },
    }
end

--==============================================================--
-- HTTP
--==============================================================--

local function decodeResponse(
    response
)
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
        or response.responseBody

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
                tostring(
                    response
                )
        end

        local statusCode =
            nil

        if type(response) == "table" then
            statusCode =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or response.status
                    or response.status_code
                )
        end

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
            "Nenhuma API HTTP disponível: "
            .. tostring(
                response
            )
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

    if not decoded then
        return false,
            "Resposta inválida do servidor"
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

    local okResult =
        false

    local result =
        nil

    task.spawn(function()
        okResult, result =
            rawRequest(
                url,
                payload
            )

        finished =
            true
    end)

    local started =
        os.clock()

    while not finished do
        if State.CancelRequested then
            return false,
                "Cancelado"
        end

        if
            os.clock()
            - started
            >= CONFIG.REQUEST_TIMEOUT
        then
            return false,
                "Tempo limite de "
                .. tostring(
                    CONFIG.REQUEST_TIMEOUT
                )
                .. "s"
        end

        task.wait(0.1)
    end

    return okResult,
        result
end

--==============================================================--
-- GUI COLORS
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
            105,
            18,
            27
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
}

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function create(
    className,
    props
)
    local obj =
        Instance.new(
            className
        )

    for key, value
        in pairs(
            props or {}
        )
    do
        obj[key] =
            value
    end

    return obj
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
-- ROBUST GUI PARENT
--==============================================================--

local GuiParent = nil

if typeof(gethui) == "function" then
    local ok, result =
        pcall(
            gethui
        )

    if ok and result then
        GuiParent =
            result
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
                "CafeinaServerScanUploader",

            ResetOnSpawn =
                false,

            IgnoreGuiInset =
                true,

            ZIndexBehavior =
                Enum.ZIndexBehavior.Sibling,
        }
    )

local parented =
    false

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

local old = nil

pcall(function()
    old =
        Gui.Parent:FindFirstChild(
            "CafeinaServerScanUploader"
        )
end)

if old and old ~= Gui then
    old:Destroy()
end

--==============================================================--
-- MAIN
--==============================================================--

local Main =
    create(
        "Frame",
        {
            Name =
                "Main",

            Size =
                UDim2.fromOffset(
                    340,
                    390
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

corner(
    Main,
    15
)

stroke(
    Main,
    COLORS.STROKE,
    1
)

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

corner(
    Header,
    15
)

create(
    "Frame",
    {
        Position =
            UDim2.new(
                0,
                0,
                1,
                -15
            ),

        Size =
            UDim2.new(
                1,
                0,
                0,
                15
            ),

        BackgroundColor3 =
            COLORS.PANEL,

        BorderSizePixel =
            0,

        Parent =
            Header,
    }
)

create(
    "TextLabel",
    {
        Position =
            UDim2.fromOffset(
                16,
                9
            ),

        Size =
            UDim2.new(
                1,
                -100,
                0,
                22
            ),

        BackgroundTransparency =
            1,

        Font =
            Enum.Font.GothamBold,

        Text =
            "CAFEÍNA • SCANNER",

        TextSize =
            17,

        TextColor3 =
            COLORS.TEXT,

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
                16,
                31
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

        Font =
            Enum.Font.Gotham,

        Text =
            "Escanear → enviar para o site",

        TextSize =
            11,

        TextColor3 =
            COLORS.SUB,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

--==============================================================--
-- HEADER BUTTONS
--==============================================================--

local Minimize =
    create(
        "TextButton",
        {
            Size =
                UDim2.fromOffset(
                    32,
                    32
                ),

            Position =
                UDim2.new(
                    1,
                    -74,
                    0,
                    13
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Text =
                "—",

            TextSize =
                18,

            Font =
                Enum.Font.GothamBold,

            TextColor3 =
                COLORS.TEXT,

            Parent =
                Header,
        }
    )

corner(
    Minimize,
    9
)

local Close =
    create(
        "TextButton",
        {
            Size =
                UDim2.fromOffset(
                    32,
                    32
                ),

            Position =
                UDim2.new(
                    1,
                    -38,
                    0,
                    13
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            BorderSizePixel =
                0,

            Text =
                "×",

            TextSize =
                20,

            Font =
                Enum.Font.GothamBold,

            TextColor3 =
                COLORS.TEXT,

            Parent =
                Header,
        }
    )

corner(
    Close,
    9
)

--==============================================================--
-- CONTENT
--==============================================================--

local Content =
    create(
        "Frame",
        {
            Position =
                UDim2.fromOffset(
                    12,
                    70
                ),

            Size =
                UDim2.new(
                    1,
                    -24,
                    1,
                    -82
                ),

            BackgroundTransparency =
                1,

            Parent =
                Main,
        }
    )

--==============================================================--
-- STATUS CARD
--==============================================================--

local StatusCard =
    create(
        "Frame",
        {
            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    96
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Content,
        }
    )

corner(
    StatusCard,
    12
)

stroke(
    StatusCard,
    COLORS.STROKE,
    1
)

local StatusDot =
    create(
        "Frame",
        {
            Size =
                UDim2.fromOffset(
                    9,
                    9
                ),

            Position =
                UDim2.fromOffset(
                    14,
                    17
                ),

            BackgroundColor3 =
                COLORS.GREEN,

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
        }
    )

corner(
    StatusDot,
    99
)

local StatusText =
    create(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    31,
                    10
                ),

            Size =
                UDim2.new(
                    1,
                    -44,
                    0,
                    25
                ),

            BackgroundTransparency =
                1,

            Font =
                Enum.Font.GothamBold,

            Text =
                "Pronto",

            TextSize =
                13,

            TextColor3 =
                COLORS.TEXT,

            TextWrapped =
                true,

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
                    14,
                    38
                ),

            Size =
                UDim2.new(
                    1,
                    -28,
                    0,
                    28
                ),

            BackgroundTransparency =
                1,

            Font =
                Enum.Font.Gotham,

            Text =
                "0 objetos • 0 partes • 0 B",

            TextSize =
                11,

            TextColor3 =
                COLORS.SUB,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusCard,
        }
    )

--==============================================================--
-- PROGRESS
--==============================================================--

local ProgressBG =
    create(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    14,
                    1,
                    -20
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

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
        }
    )

corner(
    ProgressBG,
    99
)

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

corner(
    ProgressFill,
    99
)

--==============================================================--
-- MAIN BUTTON
--==============================================================--

local ScanSend =
    create(
        "TextButton",
        {
            Position =
                UDim2.fromOffset(
                    0,
                    108
                ),

            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    58
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "ESCANEAR E ENVIAR",

            TextSize =
                15,

            Font =
                Enum.Font.GothamBold,

            TextColor3 =
                Color3.new(
                    1,
                    1,
                    1
                ),

            Parent =
                Content,
        }
    )

corner(
    ScanSend,
    12
)

--==============================================================--
-- CANCEL
--==============================================================--

local Cancel =
    create(
        "TextButton",
        {
            Position =
                UDim2.fromOffset(
                    0,
                    177
                ),

            Size =
                UDim2.new(
                    0.48,
                    0,
                    0,
                    44
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Text =
                "CANCELAR",

            TextSize =
                12,

            Font =
                Enum.Font.GothamBold,

            TextColor3 =
                COLORS.TEXT,

            Parent =
                Content,
        }
    )

corner(
    Cancel,
    10
)

--==============================================================--
-- COPY LINK
--==============================================================--

local CopyLink =
    create(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0.52,
                    0,
                    0,
                    177
                ),

            Size =
                UDim2.new(
                    0.48,
                    0,
                    0,
                    44
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Text =
                "COPIAR LINK",

            TextSize =
                12,

            Font =
                Enum.Font.GothamBold,

            TextColor3 =
                COLORS.TEXT,

            Parent =
                Content,
        }
    )

corner(
    CopyLink,
    10
)

--==============================================================--
-- LINK BOX
--==============================================================--

local LinkBox =
    create(
        "TextBox",
        {
            Position =
                UDim2.fromOffset(
                    0,
                    232
                ),

            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    48
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            ClearTextOnFocus =
                false,

            MultiLine =
                true,

            TextEditable =
                false,

            Font =
                Enum.Font.Code,

            Text =
                "O link aparecerá aqui após o upload.",

            TextSize =
                10,

            TextColor3 =
                COLORS.SUB,

            TextWrapped =
                true,

            Parent =
                Content,
        }
    )

corner(
    LinkBox,
    10
)

stroke(
    LinkBox,
    COLORS.STROKE,
    1
)

--==============================================================--
-- MINI ICON
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

            TextSize =
                20,

            Font =
                Enum.Font.GothamBlack,

            TextColor3 =
                Color3.new(
                    1,
                    1,
                    1
                ),

            Parent =
                Gui,
        }
    )

corner(
    Mini,
    99
)

stroke(
    Mini,
    COLORS.RED_DARK,
    2
)

--==============================================================--
-- UI STATE HELPERS
--==============================================================--

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
            bytes /
            (
                1024
                * 1024
                * 1024
            )
        )

    elseif
        bytes
        >= 1024 * 1024
    then
        return string.format(
            "%.2f MB",
            bytes /
            (
                1024
                * 1024
            )
        )

    elseif
        bytes
        >= 1024
    then
        return string.format(
            "%.1f KB",
            bytes / 1024
        )
    end

    return tostring(bytes)
        .. " B"
end

local function setStatus(
    text,
    color
)
    StatusText.Text =
        tostring(
            text or ""
        )

    if color then
        StatusDot.BackgroundColor3 =
            color
    end
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
        .. " partes • "
        .. formatBytes(
            State.BytesSent
        )
end

local function setProgress(
    value
)
    value =
        math.clamp(
            tonumber(value)
            or 0,
            0,
            1
        )

    TweenService:Create(
        ProgressFill,

        TweenInfo.new(
            0.15
        ),

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

--==============================================================--
-- DRAG
--==============================================================--

local function makeDraggable(
    target,
    handle
)
    local dragging =
        false

    local dragStart =
        nil

    local startPos =
        nil

    local activeInput =
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

                activeInput =
                    input

                dragStart =
                    input.Position

                startPos =
                    target.Position
            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)
            if
                not dragging
                or not dragStart
                or not startPos
            then
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

            local delta =
                input.Position
                - dragStart

            target.Position =
                UDim2.new(
                    startPos.X.Scale,

                    startPos.X.Offset
                    + delta.X,

                    startPos.Y.Scale,

                    startPos.Y.Offset
                    + delta.Y
                )
        end
    )

    UserInputService.InputEnded:Connect(
        function(input)
            if not dragging then
                return
            end

            if
                input == activeInput
                or input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging =
                    false

                activeInput =
                    nil
            end
        end
    )
end

makeDraggable(
    Main,
    Header
)

makeDraggable(
    Mini,
    Mini
)

--==============================================================--
-- API HELPERS
--==============================================================--

local function withToken(
    payload
)
    if
        CONFIG.UPLOAD_TOKEN
        ~= ""
    then
        payload.token =
            CONFIG.UPLOAD_TOKEN
    end

    return payload
end

local function requestRetry(
    url,
    payload,
    label
)
    local lastError =
        "Falha desconhecida"

    for attempt = 1, CONFIG.RETRIES do
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
            tostring(
                result
            )

        if
            attempt
            < CONFIG.RETRIES
        then
            setStatus(
                tostring(label)
                .. " • tentativa "
                .. tostring(
                    attempt + 1
                )
                .. "/"
                .. tostring(
                    CONFIG.RETRIES
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
-- UPLOAD START
--==============================================================--

local function uploadStart()
    local timestamp =
        os.date(
            "!%Y%m%d_%H%M%S"
        )

    local fileName =
        sanitizeFileName(
            "Cafeina_ServerScan_"
            .. tostring(
                game.PlaceId
            )
            .. "_"
            .. timestamp
            .. ".json"
        )

    return requestRetry(
        CONFIG.UPLOAD_BASE
        .. "/start",

        withToken({
            filename =
                fileName,

            source =
                "cafeina-server-scan-client-visible",

            metadata =
                buildGameMetadata(),
        }),

        "Abrindo upload"
    )
end

--==============================================================--
-- UPLOAD CHUNK
--==============================================================--

local function uploadChunk(
    index,
    objects
)
    return requestRetry(
        CONFIG.UPLOAD_BASE
        .. "/chunk",

        withToken({
            uploadId =
                State.UploadId,

            index =
                index,

            objects =
                objects,
        }),

        "Enviando parte "
        .. tostring(
            index
        )
    )
end

--==============================================================--
-- UPLOAD FINISH
--==============================================================--

local function uploadFinish()
    return requestRetry(
        CONFIG.UPLOAD_BASE
        .. "/finish",

        withToken({
            uploadId =
                State.UploadId,

            totalChunks =
                State.ChunksSent,

            summary = {
                objectsScanned =
                    State.ObjectsScanned,

                chunksSent =
                    State.ChunksSent,

                bytesApprox =
                    State.BytesSent,

                servicesScanned =
                    State.ServicesDone,

                servicesRequested =
                    State.ServicesTotal,

                elapsedSeconds =
                    math.max(
                        0,

                        os.clock()
                        - State.StartedAt
                    ),

                clientVisibleOnly =
                    true,

                cancelled =
                    false,
            },
        }),

        "Finalizando"
    )
end

--==============================================================--
-- UPLOAD CANCEL
--==============================================================--

local function uploadCancel()
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
-- SCAN + STREAMING UPLOAD
--==============================================================--

local function scanAndUpload()
    if State.Running then
        return
    end

    State.Running =
        true

    State.CancelRequested =
        false

    State.UploadId =
        nil

    State.LastURL =
        ""

    State.ObjectsScanned =
        0

    State.ChunksSent =
        0

    State.BytesSent =
        0

    State.ServicesDone =
        0

    State.StartedAt =
        os.clock()

    LinkBox.Text =
        "Preparando..."

    ScanSend.Text =
        "TRABALHANDO..."

    ScanSend.AutoButtonColor =
        false

    setProgress(0)
    updateDetails()

    setStatus(
        "Conectando ao site...",
        COLORS.YELLOW
    )

    --==========================================================--
    -- START
    --==========================================================--

    local startOk, startResult =
        uploadStart()

    if not startOk then
        setStatus(
            "Erro ao iniciar: "
            .. tostring(
                startResult
            ),

            COLORS.RED
        )

        LinkBox.Text =
            tostring(
                startResult
            )

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    if
        type(startResult)
        ~= "table"
        or not startResult.uploadId
    then
        setStatus(
            "Resposta inválida do site",
            COLORS.RED
        )

        LinkBox.Text =
            "O servidor não retornou uploadId."

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    State.UploadId =
        tostring(
            startResult.uploadId
        )

    --==========================================================--
    -- CHUNK STATE
    --==========================================================--

    local chunk =
        {}

    local chunkBytes =
        2

    --==========================================================--
    -- FLUSH
    --==========================================================--

    local function flushChunk()
        if #chunk == 0 then
            return true
        end

        if State.CancelRequested then
            return false,
                "Cancelado"
        end

        local nextIndex =
            State.ChunksSent
            + 1

        setStatus(
            "Enviando parte "
            .. tostring(
                nextIndex
            )
            .. "...",

            COLORS.YELLOW
        )

        local encodedOk, encoded =
            pcall(function()
                return HttpService:JSONEncode(
                    chunk
                )
            end)

        if not encodedOk then
            return false,
                "Não foi possível codificar o chunk"
        end

        local bytes =
            #encoded

        local ok, result =
            uploadChunk(
                nextIndex,
                chunk
            )

        if not ok then
            return false,
                result
        end

        State.ChunksSent =
            nextIndex

        State.BytesSent +=
            bytes

        updateDetails()

        chunk =
            {}

        chunkBytes =
            2

        return true
    end

    --==========================================================--
    -- PUSH OBJECT
    --==========================================================--

    local function pushObject(
        object
    )
        local okEncode, encoded =
            pcall(function()
                return HttpService:JSONEncode(
                    object
                )
            end)

        if not okEncode then
            return true
        end

        local objectBytes =
            #encoded
            + 1

        if
            State.BytesSent
            + chunkBytes
            + objectBytes
            >= CONFIG.MAX_TOTAL_BYTES
        then
            return false,
                "Limite total do scan atingido"
        end

        if
            chunkBytes
            + objectBytes
            > CONFIG.TARGET_CHUNK_BYTES
            and #chunk > 0
        then
            local okFlush, err =
                flushChunk()

            if not okFlush then
                return false,
                    err
            end
        end

        chunk[
            #chunk + 1
        ] =
            object

        chunkBytes +=
            objectBytes

        return true
    end

    --==========================================================--
    -- HEADER RECORD
    --==========================================================--

    local okHeader, headerErr =
        pushObject({
            recordType =
                "scan_header",

            metadata =
                buildGameMetadata(),
        })

    if not okHeader then
        uploadCancel()

        setStatus(
            tostring(
                headerErr
            ),

            COLORS.RED
        )

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    --==========================================================--
    -- SERVICES
    --==========================================================--

    for serviceIndex, serviceName
        in ipairs(
            CONFIG.SERVICES
        )
    do
        if State.CancelRequested then
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

            local serviceHeader = {
                recordType =
                    "service",

                service =
                    serviceName,

                path =
                    safeFullName(
                        service
                    ),

                childCount =
                    0,
            }

            pcall(function()
                serviceHeader.childCount =
                    #service:GetChildren()
            end)

            local okPush, pushErr =
                pushObject(
                    serviceHeader
                )

            if not okPush then
                State.CancelRequested =
                    true

                LinkBox.Text =
                    tostring(
                        pushErr
                    )

                break
            end

            local descendants =
                {}

            local okDesc =
                pcall(function()
                    descendants =
                        service:GetDescendants()
                end)

            if okDesc then
                for index, inst
                    in ipairs(
                        descendants
                    )
                do
                    if State.CancelRequested then
                        break
                    end

                    local okSerialize, object =
                        pcall(
                            serializeInstance,
                            inst,
                            serviceName
                        )

                    if
                        okSerialize
                        and type(object)
                        == "table"
                    then
                        local okObject, objectErr =
                            pushObject(
                                object
                            )

                        if not okObject then
                            State.CancelRequested =
                                true

                            LinkBox.Text =
                                tostring(
                                    objectErr
                                )

                            break
                        end

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
        end

        State.ServicesDone =
            serviceIndex

        local serviceProgress =
            State.ServicesDone
            / math.max(
                1,
                State.ServicesTotal
            )

        setProgress(
            serviceProgress
            * 0.90
        )

        updateDetails()
        task.wait()
    end

    --==========================================================--
    -- CANCELLED
    --==========================================================--

    if State.CancelRequested then
        uploadCancel()

        setStatus(
            "Cancelado",
            COLORS.RED
        )

        if
            LinkBox.Text == ""
            or LinkBox.Text
            == "Preparando..."
        then
            LinkBox.Text =
                "Operação cancelada."
        end

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    --==========================================================--
    -- FLUSH FINAL
    --==========================================================--

    local lastOk, lastErr =
        flushChunk()

    if not lastOk then
        uploadCancel()

        setStatus(
            "Erro no upload",
            COLORS.RED
        )

        LinkBox.Text =
            tostring(
                lastErr
            )

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    if State.ChunksSent < 1 then
        uploadCancel()

        setStatus(
            "Nenhum dado coletado",
            COLORS.RED
        )

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    --==========================================================--
    -- FINALIZE
    --==========================================================--

    setProgress(
        0.95
    )

    setStatus(
        "Montando arquivo no site...",
        COLORS.YELLOW
    )

    local finishOk, finishResult =
        uploadFinish()

    if not finishOk then
        uploadCancel()

        setStatus(
            "Erro ao finalizar",
            COLORS.RED
        )

        LinkBox.Text =
            tostring(
                finishResult
            )

        State.Running =
            false

        ScanSend.Text =
            "ESCANEAR E ENVIAR"

        ScanSend.AutoButtonColor =
            true

        return
    end

    --==========================================================--
    -- RESULT
    --==========================================================--

    local url =
        type(finishResult)
        == "table"
        and (
            finishResult.downloadUrl
            or finishResult.url
        )
        or nil

    if
        not url
        or tostring(url) == ""
    then
        setStatus(
            "Arquivo criado, sem link retornado",
            COLORS.YELLOW
        )

        LinkBox.Text =
            CONFIG.BASE_URL
            .. "/api/files"
    else
        State.LastURL =
            tostring(
                url
            )

        LinkBox.Text =
            State.LastURL

        setStatus(
            "Pronto • enviado com sucesso",
            COLORS.GREEN
        )

        if SetClipboard then
            pcall(
                SetClipboard,
                State.LastURL
            )
        end
    end

    setProgress(1)
    updateDetails()

    State.Running =
        false

    ScanSend.Text =
        "ESCANEAR E ENVIAR"

    ScanSend.AutoButtonColor =
        true
end

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

ScanSend.Activated:Connect(
    function()
        if State.Running then
            return
        end

        task.spawn(function()
            local ok, err =
                pcall(
                    scanAndUpload
                )

            if not ok then
                uploadCancel()

                setStatus(
                    "Erro interno do scanner",
                    COLORS.RED
                )

                LinkBox.Text =
                    tostring(
                        err
                    )

                State.Running =
                    false

                ScanSend.Text =
                    "ESCANEAR E ENVIAR"

                ScanSend.AutoButtonColor =
                    true
            end
        end)
    end
)

Cancel.Activated:Connect(
    function()
        if not State.Running then
            setStatus(
                "Nada para cancelar",
                COLORS.YELLOW
            )

            return
        end

        State.CancelRequested =
            true

        setStatus(
            "Cancelando...",
            COLORS.YELLOW
        )
    end
)

CopyLink.Activated:Connect(
    function()
        if State.LastURL == "" then
            setStatus(
                "Nenhum link pronto ainda",
                COLORS.YELLOW
            )

            return
        end

        if not SetClipboard then
            LinkBox:CaptureFocus()

            setStatus(
                "Selecione e copie o link",
                COLORS.YELLOW
            )

            return
        end

        local ok =
            pcall(
                SetClipboard,
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
        if State.Running then
            State.CancelRequested =
                true

            uploadCancel()
        end

        Gui:Destroy()
    end
)

--==============================================================--
-- READY
--==============================================================--

setStatus(
    "Pronto para escanear",
    COLORS.GREEN
)

updateDetails()
setProgress(0)
