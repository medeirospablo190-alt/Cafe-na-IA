--[[
    ============================================================
    CAFEÍNA • SECURITY / EXPOSURE SCANNER V5
    ============================================================

    OBJETIVO
      Auditoria controlada da superfície disponível ao cliente.

    MODOS
      1. SCAN PASSIVO
      2. OBSERVAÇÃO DE EVENTOS SERVER -> CLIENT
      3. TESTES ATIVOS SOMENTE EM ALLOWLIST
      4. DRY RUN
      5. UPLOAD EM CHUNKS

    IMPORTANTE
      - Não dispara remotes desconhecidos automaticamente.
      - Não tenta adivinhar argumentos.
      - Não executa remotes administrativos/econômicos por padrão.
      - Não tenta burlar validações server-side.
      - CONFIG.ActiveTests começa em false.
    ============================================================
]]

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--==============================================================
-- CONFIG
--==============================================================

local CONFIG = {

    ScannerName = "CAFEINA_EXPOSURE_SCANNER_V5",

    ScanInterval = 0.30,

    MaxRecords = 60000,

    -- Upload
    UploadURL = "",

    UploadChunkBytes = 1500000,

    -- Testes ativos começam DESLIGADOS.
    ActiveTests = false,

    -- Quando true:
    -- não chama o Remote, apenas registra o que seria executado.
    DryRun = true,

    TestDelay = 0.35,

    -- Somente estes remotes poderão ser chamados.
    --
    -- NÃO use remotes administrativos/economia real
    -- aqui sem criar um ambiente de teste no servidor.
    ActiveTestAllowlist = {

        -- Exemplo seguro:
        --
        -- ["ReplicatedStorage.__remotes.TestService.Ping"] = {
        --     kind = "RemoteFunction",
        --     args = {"CAFEINA_TEST"}
        -- },

        -- ["ReplicatedStorage.__remotes.TestService.ClientDiagnostic"] = {
        --     kind = "RemoteEvent",
        --     args = {
        --         scanner = "CAFEINA",
        --         test = true
        --     }
        -- }
    }
}

--==============================================================
-- STATE
--==============================================================

local State = {

    Running = false,
    StopRequested = false,

    ActiveTesting = false,

    Records = {},

    Pass = 0,

    ObjectsSeen = 0,

    RemotesSeen = 0,

    AttributeChanges = 0,

    ClientEvents = 0,

    TestsExecuted = 0,

    TestsBlocked = 0,

    StartClock = 0,

    Connections = {}
}

--==============================================================
-- BASIC HELPERS
--==============================================================

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

local function safePath(instance)

    if not instance then
        return "nil"
    end

    local ok, result = pcall(function()
        return instance:GetFullName()
    end)

    if ok then
        return result
    end

    return tostring(instance)
end

local function sanitize(value, depth)

    depth = depth or 0

    if depth > 4 then
        return "<depth-limit>"
    end

    local t = typeof(value)

    if t == "nil"
        or t == "boolean"
        or t == "number"
        or t == "string" then

        local s = value

        if t == "string" and #s > 800 then
            s = string.sub(s, 1, 800)
            .. "...<truncated>"
        end

        return s
    end

    if t == "Instance" then

        return {
            __type = "Instance",
            class = value.ClassName,
            name = value.Name,
            path = safePath(value)
        }
    end

    if t == "Vector3" then
        return {
            __type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z
        }
    end

    if t == "Vector2" then
        return {
            __type = "Vector2",
            x = value.X,
            y = value.Y
        }
    end

    if t == "CFrame" then
        return {
            __type = "CFrame",
            position = sanitize(value.Position)
        }
    end

    if t == "Color3" then
        return {
            __type = "Color3",
            r = value.R,
            g = value.G,
            b = value.B
        }
    end

    if t == "table" then

        local out = {}
        local count = 0

        for k, v in pairs(value) do

            count += 1

            if count > 80 then
                out["__truncated"] = true
                break
            end

            out[tostring(k)] =
                sanitize(v, depth + 1)
        end

        return out
    end

    return tostring(value)
end

--==============================================================
-- RECORD ENGINE
--==============================================================

local function record(kind, data)

    if #State.Records >= CONFIG.MaxRecords then
        return
    end

    data = data or {}

    data.kind = kind
    data.time = now() - State.StartClock
    data.unix = unix()
    data.pass = State.Pass

    table.insert(State.Records, data)
end

--==============================================================
-- ATTRIBUTES
--==============================================================

local function collectAttributes(instance)

    local ok, attrs = pcall(function()
        return instance:GetAttributes()
    end)

    if not ok then
        return
    end

    if next(attrs) then

        record("attributes", {

            path = safePath(instance),

            class = instance.ClassName,

            attributes = sanitize(attrs)
        })
    end
end

--==============================================================
-- REMOTE CLASSIFICATION
--==============================================================

local function isRemote(instance)

    return instance:IsA("RemoteEvent")
        or instance:IsA("RemoteFunction")
        or instance.ClassName == "UnreliableRemoteEvent"
end

local function remoteKind(instance)

    if instance:IsA("RemoteFunction") then
        return "RemoteFunction"
    end

    if instance.ClassName == "UnreliableRemoteEvent" then
        return "UnreliableRemoteEvent"
    end

    return "RemoteEvent"
end

--==============================================================
-- PASSIVE REMOTE LISTENER
--==============================================================

local ObservedRemotes = {}

local function observeRemote(remote)

    if ObservedRemotes[remote] then
        return
    end

    ObservedRemotes[remote] = true

    State.RemotesSeen += 1

    record("remote_discovered", {

        path = safePath(remote),

        class = remote.ClassName,

        name = remote.Name
    })

    ----------------------------------------------------------
    -- SERVER -> CLIENT RemoteEvent observation
    ----------------------------------------------------------

    if remote:IsA("RemoteEvent")
        or remote.ClassName == "UnreliableRemoteEvent" then

        local ok, connection = pcall(function()

            return remote.OnClientEvent:Connect(function(...)

                State.ClientEvents += 1

                record("server_to_client_event", {

                    path = safePath(remote),

                    args = sanitize({...})
                })

            end)

        end)

        if ok and connection then
            table.insert(
                State.Connections,
                connection
            )
        end
    end
end

--==============================================================
-- OBJECT SCANNER
--==============================================================

local SeenObjects = {}

local INTERESTING_CLASSES = {

    Tool = true,

    LocalScript = true,

    ModuleScript = true,

    RemoteEvent = true,

    RemoteFunction = true,

    UnreliableRemoteEvent = true,

    ProximityPrompt = true,

    ClickDetector = true,

    TouchTransmitter = true,

    StringValue = true,

    NumberValue = true,

    BoolValue = true,

    IntValue = true
}

local function inspectObject(instance)

    if SeenObjects[instance] then
        return
    end

    SeenObjects[instance] = true

    State.ObjectsSeen += 1

    if isRemote(instance) then
        observeRemote(instance)
    end

    if INTERESTING_CLASSES[instance.ClassName] then

        record("interesting_object", {

            name = instance.Name,

            class = instance.ClassName,

            path = safePath(instance)
        })
    end

    collectAttributes(instance)

    ----------------------------------------------------------
    -- ATTRIBUTE CHANGE MONITOR
    ----------------------------------------------------------

    local ok, connection = pcall(function()

        return instance.AttributeChanged:Connect(
            function(attributeName)

                local value = nil

                pcall(function()
                    value =
                        instance:GetAttribute(
                            attributeName
                        )
                end)

                State.AttributeChanges += 1

                record("attribute_change", {

                    path = safePath(instance),

                    attribute =
                        attributeName,

                    value =
                        sanitize(value)
                })
            end
        )

    end)

    if ok and connection then

        table.insert(
            State.Connections,
            connection
        )
    end
end

--==============================================================
-- CONTAINER SCAN
--==============================================================

local function scanContainer(container)

    if not container then
        return
    end

    inspectObject(container)

    local descendants = {}

    local ok = pcall(function()
        descendants =
            container:GetDescendants()
    end)

    if not ok then
        return
    end

    for index, object in ipairs(descendants) do

        if State.StopRequested then
            return
        end

        inspectObject(object)

        if index % 400 == 0 then
            task.wait()
        end
    end
end

--==============================================================
-- TYCOON SPECIAL SCANNER
--==============================================================

local TYCOON_ATTRIBUTES = {

    "Price",
    "Owner",
    "Dependency",
    "Gamepass",
    "NonPurchase",
    "Rebirths"
}

local function scanTycoonObjects()

    for _, object in ipairs(
        Workspace:GetDescendants()
    ) do

        if State.StopRequested then
            return
        end

        local values = {}
        local found = false

        for _, attributeName
            in ipairs(TYCOON_ATTRIBUTES) do

            local value = nil

            local ok = pcall(function()
                value =
                    object:GetAttribute(
                        attributeName
                    )
            end)

            if ok and value ~= nil then

                values[attributeName] =
                    sanitize(value)

                found = true
            end
        end

        if found then

            record(
                "tycoon_candidate",
                {

                    path =
                        safePath(object),

                    class =
                        object.ClassName,

                    attributes =
                        values
                }
            )
        end
    end
end

--==============================================================
-- PLAYER SNAPSHOT
--==============================================================

local function playerSnapshot()

    local output = {}

    for _, player
        in ipairs(Players:GetPlayers()) do

        local entry = {

            name =
                player.Name,

            displayName =
                player.DisplayName,

            userId =
                player.UserId
        }

        if player.Character then

            entry.character =
                safePath(
                    player.Character
                )
        end

        table.insert(output, entry)
    end

    record(
        "players_snapshot",
        {
            players = output
        }
    )
end

--==============================================================
-- ACTIVE TEST RESOLUTION
--==============================================================

local function resolvePath(path)

    local parts = {}

    for part in string.gmatch(
        path,
        "[^%.]+"
    ) do

        table.insert(parts, part)
    end

    if #parts == 0 then
        return nil
    end

    local current

    if parts[1] == "ReplicatedStorage" then
        current = ReplicatedStorage

    elseif parts[1] == "Workspace" then
        current = Workspace

    elseif parts[1] == "ReplicatedFirst" then
        current = ReplicatedFirst

    else
        return nil
    end

    for i = 2, #parts do

        current =
            current:FindFirstChild(
                parts[i]
            )

        if not current then
            return nil
        end
    end

    return current
end

--==============================================================
-- ACTIVE TEST ENGINE
--==============================================================

local function executeTest(
    remotePath,
    definition
)

    if State.StopRequested then
        return
    end

    local remote =
        resolvePath(remotePath)

    if not remote then

        record(
            "active_test_error",
            {

                path = remotePath,

                error =
                    "Remote not found"
            }
        )

        return
    end

    if not isRemote(remote) then

        record(
            "active_test_blocked",
            {

                path = remotePath,

                reason =
                    "Object is not a Remote"
            }
        )

        State.TestsBlocked += 1

        return
    end

    local args =
        definition.args or {}

    ----------------------------------------------------------
    -- DRY RUN
    ----------------------------------------------------------

    if CONFIG.DryRun then

        record(
            "active_test_dry_run",
            {

                path = remotePath,

                remoteClass =
                    remote.ClassName,

                args =
                    sanitize(args)
            }
        )

        return
    end

    ----------------------------------------------------------
    -- ACTIVE TESTS MUST BE ENABLED
    ----------------------------------------------------------

    if not CONFIG.ActiveTests then

        State.TestsBlocked += 1

        record(
            "active_test_blocked",
            {

                path = remotePath,

                reason =
                    "ActiveTests disabled"
            }
        )

        return
    end

    ----------------------------------------------------------
    -- EXECUTION
    ----------------------------------------------------------

    local started = now()

    if remote:IsA("RemoteFunction") then

        local ok, result =
            pcall(function()

                return remote:InvokeServer(
                    table.unpack(args)
                )

            end)

        local elapsed =
            now() - started

        State.TestsExecuted += 1

        record(
            "remote_function_test",
            {

                path =
                    remotePath,

                success =
                    ok,

                latency =
                    elapsed,

                args =
                    sanitize(args),

                response =
                    ok
                    and sanitize(result)
                    or nil,

                error =
                    not ok
                    and tostring(result)
                    or nil
            }
        )

    else

        local ok, err =
            pcall(function()

                remote:FireServer(
                    table.unpack(args)
                )

            end)

        local elapsed =
            now() - started

        State.TestsExecuted += 1

        record(
            "remote_event_test",
            {

                path =
                    remotePath,

                success =
                    ok,

                latency =
                    elapsed,

                args =
                    sanitize(args),

                error =
                    not ok
                    and tostring(err)
                    or nil
            }
        )
    end
end

local function runActiveTests()

    if State.ActiveTesting then
        return
    end

    State.ActiveTesting = true

    record(
        "active_tests_started",
        {
            dryRun =
                CONFIG.DryRun,

            enabled =
                CONFIG.ActiveTests
        }
    )

    for remotePath, definition
        in pairs(
            CONFIG.ActiveTestAllowlist
        ) do

        if State.StopRequested then
            break
        end

        executeTest(
            remotePath,
            definition
        )

        task.wait(
            CONFIG.TestDelay
        )
    end

    State.ActiveTesting = false

    record(
        "active_tests_finished",
        {

            executed =
                State.TestsExecuted,

            blocked =
                State.TestsBlocked
        }
    )
end

--==============================================================
-- SCAN LOOP
--==============================================================

local function runScan()

    if State.Running then
        return
    end

    State.Running = true
    State.StopRequested = false

    State.StartClock = now()

    record(
        "scan_started",
        {

            scanner =
                CONFIG.ScannerName,

            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId
        }
    )

    ----------------------------------------------------------
    -- FIRST COMPLETE PASS
    ----------------------------------------------------------

    State.Pass += 1

    scanContainer(
        ReplicatedStorage
    )

    scanContainer(
        ReplicatedFirst
    )

    scanContainer(
        Workspace
    )

    scanContainer(
        Players
    )

    playerSnapshot()

    scanTycoonObjects()

    ----------------------------------------------------------
    -- CONTINUOUS PASSES
    ----------------------------------------------------------

    while not State.StopRequested do

        State.Pass += 1

        record(
            "scan_pass",
            {

                objects =
                    State.ObjectsSeen,

                remotes =
                    State.RemotesSeen,

                attributeChanges =
                    State.AttributeChanges,

                clientEvents =
                    State.ClientEvents
            }
        )

        scanTycoonObjects()

        playerSnapshot()

        task.wait(
            CONFIG.ScanInterval
        )
    end

    State.Running = false

    record(
        "scan_finished",
        {

            passes =
                State.Pass,

            records =
                #State.Records,

            objects =
                State.ObjectsSeen,

            remotes =
                State.RemotesSeen,

            attributeChanges =
                State.AttributeChanges,

            events =
                State.ClientEvents,

            tests =
                State.TestsExecuted
        }
    )
end

--==============================================================
-- STOP
--==============================================================

local function stopScanner()

    State.StopRequested = true

    record(
        "stop_requested",
        {}
    )
end

--==============================================================
-- HTTP
--==============================================================

local function getRequestFunction()

    return
        request
        or http_request
        or (
            syn
            and syn.request
        )
end

--==============================================================
-- ENCODE REPORT
--==============================================================

local function buildReport()

    return {

        schemaVersion = 5,

        scanner =
            CONFIG.ScannerName,

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        jobId =
            game.JobId,

        generatedAt =
            unix(),

        summary = {

            records =
                #State.Records,

            passes =
                State.Pass,

            objects =
                State.ObjectsSeen,

            remotes =
                State.RemotesSeen,

            attributeChanges =
                State.AttributeChanges,

            clientEvents =
                State.ClientEvents,

            testsExecuted =
                State.TestsExecuted,

            testsBlocked =
                State.TestsBlocked
        },

        records =
            State.Records
    }
end

--==============================================================
-- UPLOAD
--==============================================================

local function uploadReport()

    if CONFIG.UploadURL == "" then

        warn(
            "[CAFEÍNA] Configure CONFIG.UploadURL"
        )

        return false
    end

    local req =
        getRequestFunction()

    if not req then

        warn(
            "[CAFEÍNA] Executor sem request/http_request"
        )

        return false
    end

    local report =
        buildReport()

    local encoded

    local ok, err =
        pcall(function()

            encoded =
                HttpService:JSONEncode(
                    report
                )

        end)

    if not ok then

        warn(
            "[CAFEÍNA] JSON encode:",
            err
        )

        return false
    end

    local uploadId =
        HttpService:GenerateGUID(
            false
        )

    local chunkSize =
        CONFIG.UploadChunkBytes

    local totalChunks =
        math.ceil(
            #encoded / chunkSize
        )

    record(
        "upload_started",
        {

            bytes =
                #encoded,

            chunks =
                totalChunks,

            uploadId =
                uploadId
        }
    )

    for index = 1, totalChunks do

        if State.StopRequested then
            break
        end

        local first =
            ((index - 1)
            * chunkSize)
            + 1

        local last =
            math.min(
                index * chunkSize,
                #encoded
            )

        local chunk =
            string.sub(
                encoded,
                first,
                last
            )

        local payload =
            HttpService:JSONEncode({

                scanner =
                    CONFIG.ScannerName,

                uploadId =
                    uploadId,

                chunkIndex =
                    index,

                totalChunks =
                    totalChunks,

                data =
                    chunk
            })

        local success, response =
            pcall(function()

                return req({

                    Url =
                        CONFIG.UploadURL,

                    Method =
                        "POST",

                    Headers = {
                        ["Content-Type"] =
                            "application/json"
                    },

                    Body =
                        payload
                })

            end)

        record(
            "upload_chunk",
            {

                uploadId =
                    uploadId,

                index =
                    index,

                total =
                    totalChunks,

                success =
                    success,

                response =
                    success
                    and sanitize(response)
                    or tostring(response)
            }
        )

        if not success then

            warn(
                "[CAFEÍNA] Upload falhou no chunk",
                index
            )

            return false
        end

        task.wait(0.05)
    end

    record(
        "upload_complete",
        {
            uploadId =
                uploadId
        }
    )

    return true
end

--==============================================================
-- SIMPLE MOBILE UI
--==============================================================

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui"
    )

local old =
    PlayerGui:FindFirstChild(
        "CafeinaScannerV5"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "CafeinaScannerV5"

Gui.ResetOnSpawn =
    false

Gui.Parent =
    PlayerGui

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        300,
        255
    )

Main.Position =
    UDim2.new(
        0.5,
        -150,
        0.5,
        -127
    )

Main.BackgroundColor3 =
    Color3.fromRGB(
        18,
        18,
        21
    )

Main.BorderSizePixel =
    0

Main.Active =
    true

Main.Draggable =
    true

Main.Parent =
    Gui

local Corner =
    Instance.new("UICorner")

Corner.CornerRadius =
    UDim.new(
        0,
        12
    )

Corner.Parent =
    Main

local Title =
    Instance.new("TextLabel")

Title.Size =
    UDim2.new(
        1,
        -20,
        0,
        38
    )

Title.Position =
    UDim2.fromOffset(
        10,
        5
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "CAFEÍNA • SCANNER V5"

Title.TextColor3 =
    Color3.new(
        1,
        1,
        1
    )

Title.Font =
    Enum.Font.GothamBold

Title.TextSize =
    16

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Main

local Status =
    Instance.new("TextLabel")

Status.Size =
    UDim2.new(
        1,
        -20,
        0,
        58
    )

Status.Position =
    UDim2.fromOffset(
        10,
        42
    )

Status.BackgroundTransparency =
    1

Status.TextColor3 =
    Color3.fromRGB(
        205,
        205,
        205
    )

Status.Font =
    Enum.Font.Gotham

Status.TextSize =
    12

Status.TextWrapped =
    true

Status.Text =
    "Pronto"

Status.Parent =
    Main

local function makeButton(
    text,
    y
)

    local button =
        Instance.new(
            "TextButton"
        )

    button.Size =
        UDim2.new(
            1,
            -20,
            0,
            32
        )

    button.Position =
        UDim2.fromOffset(
            10,
            y
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            32,
            32,
            37
        )

    button.TextColor3 =
        Color3.new(
            1,
            1,
            1
        )

    button.BorderSizePixel =
        0

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        12

    button.Text =
        text

    button.Parent =
        Main

    local corner =
        Instance.new(
            "UICorner"
        )

    corner.CornerRadius =
        UDim.new(
            0,
            7
        )

    corner.Parent =
        button

    return button
end

local ScanButton =
    makeButton(
        "INICIAR SCAN",
        102
    )

local TestButton =
    makeButton(
        "TESTES CONTROLADOS",
        138
    )

local StopButton =
    makeButton(
        "INTERROMPER",
        174
    )

local UploadButton =
    makeButton(
        "ENVIAR AO SERVIDOR",
        210
    )

--==============================================================
-- UI ACTIONS
--==============================================================

ScanButton.MouseButton1Click:Connect(
    function()

        if State.Running then
            return
        end

        task.spawn(
            runScan
        )
    end
)

TestButton.MouseButton1Click:Connect(
    function()

        if State.ActiveTesting then
            return
        end

        task.spawn(
            runActiveTests
        )
    end
)

StopButton.MouseButton1Click:Connect(
    function()

        stopScanner()

    end
)

UploadButton.MouseButton1Click:Connect(
    function()

        task.spawn(function()

            local ok =
                uploadReport()

            if ok then

                Status.Text =
                    "Upload concluído"

            else

                Status.Text =
                    "Falha no upload"
            end

        end)

    end
)

--==============================================================
-- LIVE STATUS
--==============================================================

task.spawn(function()

    while Gui.Parent do

        local bytes = 0

        pcall(function()

            bytes =
                #HttpService:JSONEncode(
                    State.Records
                )
        end)

        local mb =
            bytes
            / 1024
            / 1024

        Status.Text =
            string.format(
                "Dados: %.2f MB\nPasses: %d | Remotes: %d | Eventos: %d | Testes: %d",
                mb,
                State.Pass,
                State.RemotesSeen,
                State.ClientEvents,
                State.TestsExecuted
            )

        task.wait(0.6)
    end

end)

print(
    "[CAFEÍNA] Security Scanner V5 iniciado"
)
