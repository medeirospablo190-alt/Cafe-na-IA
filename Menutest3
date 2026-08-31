--==============================================================--
-- CAFEÍNA • DINOSAUR MODEL COLLECTOR V1.0
-- CLIENT-VISIBLE MODEL / RIG / ASSET DATA COLLECTOR
--
-- OBJETIVO
-- • Encontrar automaticamente até 10 modelos de dinossauros client-visible.
-- • Procurar em Workspace e ReplicatedStorage.
-- • Coletar a hierarquia completa dos modelos encontrados.
-- • Registrar geometria, MeshId, TextureID, Bones, joints, Attachments,
--   Humanoid/AnimationController/Animator, AnimationIds, Attributes, Values,
--   sons, partículas, prompts e metadados de scripts visíveis.
-- • Gerar fingerprints para comparar variantes/modelos duplicados.
-- • Preservar tudo em archive persistente.
-- • Enviar automaticamente para https://cafe-na-ia.onrender.com
-- • Apagar o archive SOMENTE após confirmação explícita do servidor.
--
-- IMPORTANTE
-- • Este coletor não baixa o conteúdo binário dos assets da Roblox.
--   Ele registra os IDs e toda a estrutura client-visible necessária para
--   analisar/reconstruir a composição do modelo.
-- • Não chama remotes e não altera os modelos.
-- • Execute apenas em experiências que você está autorizado a analisar.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    VERSION = "DINOSAUR_MODEL_COLLECTOR_V1_0",
    GUI_NAME = "CafeinaDinosaurModelCollectorV10",

    TARGET_MODELS = 10,

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    ARCHIVE_ROOT = "CafeinaDinosaurModels",
    ARCHIVE_FOLDER = "CafeinaDinosaurModels/" .. tostring(game.PlaceId),
    MANIFEST_PATH = "CafeinaDinosaurModels/" .. tostring(game.PlaceId) .. "/manifest.json",

    MAX_ARCHIVE_BYTES = 120 * 1024 * 1024,
    BLOCK_TARGET_BYTES = 1024 * 1024,
    UPLOAD_CHUNK_BYTES = 500000,

    FLUSH_INTERVAL = 0.35,
    FLUSH_AT_BYTES = 96 * 1024,

    MAX_SERIALIZE_DEPTH = 7,
    MAX_TABLE_ITEMS = 180,
    MAX_STRING_BYTES = 16000,
    MAX_RECORD_JSON_BYTES = 512 * 1024,

    -- Number of candidate models inspected before final ranking.
    CANDIDATE_SCAN_LIMIT = 14000,

    -- Maximum descendants per dinosaur. This is deliberately high;
    -- the archive byte limit is the real final guard.
    MAX_DESCENDANTS_PER_MODEL = 20000,

    -- Yield frequency so mobile clients do not freeze during large rigs.
    YIELD_EVERY = 120,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.1,

    -- Name/path hints. Species names are included because many game assets
    -- do not literally use "dinosaur" in the model name.
    DINO_KEYWORDS = {
        "dino", "dinosaur", "dinossauro",
        "rex", "trex", "t-rex", "tyrannosaurus",
        "raptor", "velociraptor",
        "triceratops", "stegosaurus", "stego",
        "spinosaurus", "spino",
        "brachiosaurus", "brachio",
        "allosaurus", "allo",
        "ankylosaurus", "ankylo",
        "parasaurolophus", "parasaur",
        "carnotaurus", "carno",
        "dilophosaurus", "dilo",
        "pteranodon", "ptero",
        "mosasaurus", "mosa",
        "giganotosaurus", "giga",
        "therizinosaurus", "theri",
        "deinonychus", "deino",
        "ceratosaurus", "cerato",
        "apatosaurus", "apato",
        "diplodocus", "diplodo",
        "pachycephalosaurus", "pachy",
        "iguanodon", "compy", "compsognathus",
        "sauropod", "theropod", "prehistoric", "jurassic",
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local previous = rawget(env, "__CAFEINA_DINO_COLLECTOR_CONTROLLER")
    if type(previous) == "table" and type(previous.Stop) == "function" then
        previous.Stop("replaced")
    end
end)

local function pickFunction(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then
            return v
        end
    end
    return nil
end

local synRequest
pcall(function()
    if syn and type(syn.request) == "function" then
        synRequest = syn.request
    end
end)

local httpTableRequest
pcall(function()
    if http and type(http.request) == "function" then
        httpTableRequest = http.request
    end
end)

local REQUEST = pickFunction(
    rawget(env, "request"),
    rawget(env, "http_request"),
    httpTableRequest,
    synRequest
)

local WRITEFILE = pickFunction(rawget(env, "writefile"))
local READFILE = pickFunction(rawget(env, "readfile"))
local APPENDFILE = pickFunction(rawget(env, "appendfile"))
local ISFILE = pickFunction(rawget(env, "isfile"))
local DELFILE = pickFunction(rawget(env, "delfile"))
local MAKEFOLDER = pickFunction(rawget(env, "makefolder"))
local ISFOLDER = pickFunction(rawget(env, "isfolder"))

local FILESYSTEM_OK =
    WRITEFILE and READFILE and ISFILE and DELFILE and MAKEFOLDER

--==============================================================--
-- HELPERS
--==============================================================--

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function contains(text, fragment)
    return string.find(lower(text), lower(fragment), 1, true) ~= nil
end

local function containsAny(text, list)
    local low = lower(text)

    for _, fragment in ipairs(list) do
        if string.find(low, lower(fragment), 1, true) then
            return true, fragment
        end
    end

    return false, nil
end

local function safePath(inst)
    local ok, value = pcall(function()
        return inst:GetFullName()
    end)

    return ok and value or tostring(inst)
end

local function mb(bytes)
    return (bytes or 0) / (1024 * 1024)
end

local function isoUTC()
    local t = os.date("!*t")

    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        t.year, t.month, t.day,
        t.hour, t.min, t.sec
    )
end

local function newRunId()
    local ok, value = pcall(function()
        return HttpService:GenerateGUID(false)
    end)

    if ok then
        return value
    end

    return tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
end

local function safeJson(value)
    local ok, result = pcall(HttpService.JSONEncode, HttpService, value)

    if ok then
        return result
    end

    return HttpService:JSONEncode({
        kind="json_encode_error",
        error=tostring(result),
    })
end

local function truncateString(s)
    if type(s) ~= "string" then
        return s
    end

    if #s <= CONFIG.MAX_STRING_BYTES then
        return s
    end

    return string.sub(s, 1, CONFIG.MAX_STRING_BYTES)
        .. string.format("<truncated:%d>", #s)
end

--==============================================================--
-- SERIALIZER
--==============================================================--

local function serializeCFrame(cf)
    local c = {cf:GetComponents()}

    return {
        type="CFrame",
        components=c,
        position={
            x=cf.Position.X,
            y=cf.Position.Y,
            z=cf.Position.Z,
        },
    }
end

local function safeSerialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > CONFIG.MAX_SERIALIZE_DEPTH then
        return "<max_depth>"
    end

    local tv = typeof(value)

    if value == nil then
        return nil
    elseif tv == "string" then
        return truncateString(value)
    elseif tv == "boolean" then
        return value
    elseif tv == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    elseif tv == "Vector3" then
        return {
            type="Vector3",
            x=value.X,
            y=value.Y,
            z=value.Z,
        }
    elseif tv == "Vector2" then
        return {
            type="Vector2",
            x=value.X,
            y=value.Y,
        }
    elseif tv == "CFrame" then
        return serializeCFrame(value)
    elseif tv == "Color3" then
        return {
            type="Color3",
            r=value.R,
            g=value.G,
            b=value.B,
        }
    elseif tv == "BrickColor" then
        return tostring(value)
    elseif tv == "PhysicalProperties" then
        return {
            density=value.Density,
            friction=value.Friction,
            elasticity=value.Elasticity,
            frictionWeight=value.FrictionWeight,
            elasticityWeight=value.ElasticityWeight,
        }
    elseif tv == "NumberRange" then
        return {
            min=value.Min,
            max=value.Max,
        }
    elseif tv == "NumberSequence" or tv == "ColorSequence" then
        return tostring(value)
    elseif tv == "EnumItem" then
        return tostring(value)
    elseif tv == "Instance" then
        return {
            type="Instance",
            className=value.ClassName,
            name=value.Name,
            path=safePath(value),
        }
    elseif tv == "table" then
        if seen[value] then
            return "<cycle>"
        end

        seen[value] = true

        local out = {}
        local count = 0

        for k, v in pairs(value) do
            count += 1

            if count > CONFIG.MAX_TABLE_ITEMS then
                out["<truncated>"] = true
                break
            end

            out[tostring(k)] = safeSerialize(v, depth + 1, seen)
        end

        seen[value] = nil
        return out
    end

    return truncateString(tostring(value))
end

--==============================================================--
-- STATE
--==============================================================--

local Session = {
    Running=false,
    StopRequested=false,
    RunId=nil,
    StartedClock=0,
    RecordsThisRun=0,

    Candidates=0,
    Selected=0,
    ModelsCollected=0,
    DescendantsCollected=0,
    AssetIdsCollected=0,
    CurrentModel="idle",

    ErrorCount=0,
    OversizeDrops=0,
}

local Archive = {
    Persistent=FILESYSTEM_OK and true or false,
    Blocks={},
    CurrentBlock=1,
    CurrentBlockBytes=0,
    Bytes=0,
    Records=0,
    PendingLines={},
    PendingBytes=0,
    MemoryLines={},
}

local Upload = {
    Running=false,
    UploadId=nil,
    CurrentChunk=0,
    TotalChunks=0,
    BytesSent=0,
    TotalBytes=0,
    LastURL="",
    LastError=nil,
}

local updateUI
local Status
local Detail
local Action
local BarFill

local function relativeTime()
    if Session.StartedClock == 0 then
        return 0
    end

    return os.clock() - Session.StartedClock
end

--==============================================================--
-- ERROR GUARD
--==============================================================--

local queueRecord

local function recordError(where, err)
    Session.ErrorCount += 1

    if queueRecord and Session.Running then
        queueRecord({
            source="diagnostic",
            kind="caught_error",
            where=where,
            error=truncateString(tostring(err)),
        })
    end
end

local function guarded(where, fn, ...)
    local args = table.pack(...)

    local ok, a, b, c = xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        local message = tostring(err)

        if debug and type(debug.traceback) == "function" then
            local traceOk, trace = pcall(debug.traceback, message, 2)

            if traceOk then
                return trace
            end
        end

        return message
    end)

    if not ok then
        recordError(where, a)
        return false, a
    end

    return true, a, b, c
end

--==============================================================--
-- ARCHIVE
--==============================================================--

local function blockPath(index)
    return string.format(
        "%s/block_%06d.jsonl",
        CONFIG.ARCHIVE_FOLDER,
        index
    )
end

local function ensureFolder(path)
    if not FILESYSTEM_OK then
        return
    end

    pcall(function()
        if not ISFOLDER(path) then
            MAKEFOLDER(path)
        end
    end)
end

local function appendText(path, text)
    if APPENDFILE then
        return pcall(APPENDFILE, path, text)
    end

    local old = ""

    if ISFILE(path) then
        local ok, value = pcall(READFILE, path)

        if ok and type(value) == "string" then
            old = value
        end
    end

    return pcall(WRITEFILE, path, old .. text)
end

local function writeManifest()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    pcall(
        WRITEFILE,
        CONFIG.MANIFEST_PATH,
        safeJson({
            version=CONFIG.VERSION,
            placeId=game.PlaceId,
            gameId=game.GameId,
            runId=Session.RunId,
            blocks=Archive.Blocks,
            currentBlock=Archive.CurrentBlock,
            currentBlockBytes=Archive.CurrentBlockBytes,
            bytes=Archive.Bytes,
            records=Archive.Records,
            updatedAt=os.time(),
        })
    )
end

local function loadArchive()
    if not FILESYSTEM_OK then
        return
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    if ISFILE(CONFIG.MANIFEST_PATH) then
        local ok, text = pcall(READFILE, CONFIG.MANIFEST_PATH)

        if ok and type(text) == "string" then
            local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, text)

            if decodeOk and type(data) == "table" then
                Archive.Blocks =
                    type(data.blocks) == "table"
                    and data.blocks
                    or {}

                Archive.CurrentBlock =
                    tonumber(data.currentBlock)
                    or math.max(1, #Archive.Blocks)

                Archive.CurrentBlockBytes =
                    tonumber(data.currentBlockBytes)
                    or 0

                Archive.Bytes =
                    tonumber(data.bytes)
                    or 0

                Archive.Records =
                    tonumber(data.records)
                    or 0
            end
        end
    end

    local valid = {}

    for _, path in ipairs(Archive.Blocks) do
        if type(path) == "string" and ISFILE(path) then
            table.insert(valid, path)
        end
    end

    Archive.Blocks = valid

    if #Archive.Blocks == 0 then
        Archive.Blocks = {blockPath(1)}
        Archive.CurrentBlock = 1
        Archive.CurrentBlockBytes = 0
    end
end

local function flushPending(force)
    if #Archive.PendingLines == 0 then
        if force then
            writeManifest()
        end

        return true
    end

    if not force and Archive.PendingBytes < CONFIG.FLUSH_AT_BYTES then
        return true
    end

    local lines = Archive.PendingLines
    Archive.PendingLines = {}
    Archive.PendingBytes = 0

    if not Archive.Persistent then
        for _, line in ipairs(lines) do
            table.insert(
                Archive.MemoryLines,
                string.sub(line, 1, -2)
            )
        end

        return true
    end

    ensureFolder(CONFIG.ARCHIVE_ROOT)
    ensureFolder(CONFIG.ARCHIVE_FOLDER)

    local batch = {}

    local function commit()
        if #batch == 0 then
            return true
        end

        local text = table.concat(batch)
        table.clear(batch)

        local path = blockPath(Archive.CurrentBlock)

        if not table.find(Archive.Blocks, path) then
            table.insert(Archive.Blocks, path)
        end

        local ok = appendText(path, text)

        if ok then
            Archive.CurrentBlockBytes += #text
        end

        return ok
    end

    for _, line in ipairs(lines) do
        local bytes = #line

        if Archive.CurrentBlockBytes > 0
        and Archive.CurrentBlockBytes + bytes > CONFIG.BLOCK_TARGET_BYTES
        then
            if not commit() then
                return false
            end

            Archive.CurrentBlock += 1
            Archive.CurrentBlockBytes = 0
        end

        table.insert(batch, line)

        if #batch >= 80 then
            if not commit() then
                return false
            end
        end
    end

    local ok = commit()

    if ok then
        writeManifest()
    end

    return ok
end

queueRecord = function(record)
    if not Session.Running
    and record.kind ~= "session_finalized"
    then
        return false
    end

    record.version = record.version or CONFIG.VERSION
    record.placeId = record.placeId or game.PlaceId
    record.gameId = record.gameId or game.GameId
    record.runId = record.runId or Session.RunId
    record.time = record.time or relativeTime()
    record.unix = record.unix or os.time()

    local line = safeJson(record) .. "\n"

    if #line > CONFIG.MAX_RECORD_JSON_BYTES then
        Session.OversizeDrops += 1

        line = safeJson({
            version=CONFIG.VERSION,
            placeId=game.PlaceId,
            gameId=game.GameId,
            runId=Session.RunId,
            time=relativeTime(),
            unix=os.time(),
            source="diagnostic",
            kind="oversize_record_dropped",
            originalKind=tostring(record.kind),
            originalSource=tostring(record.source),
            encodedBytes=#line,
        }) .. "\n"
    end

    local bytes = #line

    if Archive.Bytes + bytes > CONFIG.MAX_ARCHIVE_BYTES then
        Session.StopRequested = true

        if Status then
            Status.Text = "Limite de archive atingido • finalizando"
        end

        return false
    end

    table.insert(Archive.PendingLines, line)
    Archive.PendingBytes += bytes

    Archive.Bytes += bytes
    Archive.Records += 1
    Session.RecordsThisRun += 1

    if Archive.PendingBytes >= CONFIG.FLUSH_AT_BYTES then
        task.defer(function()
            guarded("flush_deferred", flushPending, true)
        end)
    end

    if updateUI then
        updateUI(false)
    end

    return true
end

task.spawn(function()
    while true do
        task.wait(CONFIG.FLUSH_INTERVAL)

        if #Archive.PendingLines > 0 then
            guarded("periodic_flush", flushPending, true)
        end
    end
end)

--==============================================================--
-- MODEL CANDIDATE DETECTION
--==============================================================--

local function isPlayerCharacter(model)
    return model:IsA("Model")
        and Players:GetPlayerFromCharacter(model) ~= nil
end

local function descendantStats(model)
    local stats = {
        descendants=0,
        baseParts=0,
        meshParts=0,
        specialMeshes=0,
        bones=0,
        motor6Ds=0,
        welds=0,
        attachments=0,
        animations=0,
        humanoids=0,
        animationControllers=0,
        animators=0,
    }

    for _, inst in ipairs(model:GetDescendants()) do
        stats.descendants += 1

        if inst:IsA("MeshPart") then
            stats.meshParts += 1
            stats.baseParts += 1
        elseif inst:IsA("BasePart") then
            stats.baseParts += 1
        elseif inst:IsA("SpecialMesh") then
            stats.specialMeshes += 1
        elseif inst:IsA("Bone") then
            stats.bones += 1
        elseif inst:IsA("Motor6D") then
            stats.motor6Ds += 1
        elseif inst:IsA("Weld") or inst:IsA("WeldConstraint") then
            stats.welds += 1
        elseif inst:IsA("Attachment") then
            stats.attachments += 1
        elseif inst:IsA("Animation") then
            stats.animations += 1
        elseif inst:IsA("Humanoid") then
            stats.humanoids += 1
        elseif inst:IsA("AnimationController") then
            stats.animationControllers += 1
        elseif inst:IsA("Animator") then
            stats.animators += 1
        end
    end

    return stats
end

local function candidateScore(model)
    if not model:IsA("Model") then
        return -math.huge, nil, nil
    end

    if isPlayerCharacter(model) then
        return -math.huge, nil, nil
    end

    local path = safePath(model)
    local score = 0
    local reasons = {}

    local keywordHit, keyword = containsAny(path, CONFIG.DINO_KEYWORDS)

    if keywordHit then
        score += 1500
        table.insert(reasons, "keyword:" .. tostring(keyword))
    end

    local stats = descendantStats(model)

    if stats.meshParts >= 1 then
        score += math.min(260, stats.meshParts * 18)
        table.insert(reasons, "meshparts")
    end

    if stats.bones >= 4 then
        score += math.min(420, stats.bones * 8)
        table.insert(reasons, "bones")
    end

    if stats.motor6Ds >= 3 then
        score += math.min(260, stats.motor6Ds * 8)
        table.insert(reasons, "motor6d")
    end

    if stats.humanoids > 0 then
        score += 180
        table.insert(reasons, "humanoid")
    end

    if stats.animationControllers > 0 then
        score += 220
        table.insert(reasons, "animation_controller")
    end

    if stats.animators > 0 then
        score += 100
        table.insert(reasons, "animator")
    end

    if stats.animations > 0 then
        score += math.min(180, stats.animations * 18)
        table.insert(reasons, "animations")
    end

    -- Animal-like articulated model bonus.
    if (
        stats.meshParts + stats.baseParts >= 5
        and (
            stats.bones >= 4
            or stats.motor6Ds >= 3
        )
    ) then
        score += 240
        table.insert(reasons, "articulated_creature")
    end

    -- Ignore tiny utility models unless they have a dinosaur keyword.
    if not keywordHit
    and stats.baseParts < 4
    and stats.meshParts < 2
    then
        score -= 500
    end

    return score, reasons, stats
end

local function discoverCandidates()
    local candidates = {}
    local seen = {}
    local inspected = 0

    local roots = {
        {"Workspace", Workspace},
        {"ReplicatedStorage", ReplicatedStorage},
    }

    for _, pair in ipairs(roots) do
        local rootName, root = pair[1], pair[2]

        for _, inst in ipairs(root:GetDescendants()) do
            if not Session.Running or Session.StopRequested then
                break
            end

            if inspected >= CONFIG.CANDIDATE_SCAN_LIMIT then
                break
            end

            if inst:IsA("Model") and not seen[inst] then
                inspected += 1
                seen[inst] = true

                local score, reasons, stats = candidateScore(inst)

                -- Require either explicit dino naming, or a reasonably complex
                -- articulated creature rig.
                local explicitDino = containsAny(safePath(inst), CONFIG.DINO_KEYWORDS)

                if explicitDino or score >= 520 then
                    table.insert(candidates, {
                        instance=inst,
                        path=safePath(inst),
                        name=inst.Name,
                        root=rootName,
                        score=score,
                        reasons=reasons,
                        stats=stats,
                    })
                end

                if inspected % CONFIG.YIELD_EVERY == 0 then
                    task.wait()
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score == b.score then
            return a.path < b.path
        end

        return a.score > b.score
    end)

    Session.Candidates = #candidates

    queueRecord({
        source="discovery",
        kind="dinosaur_candidates",
        inspected=inspected,
        count=#candidates,
        candidates=(function()
            local out = {}

            for i = 1, math.min(#candidates, 80) do
                local c = candidates[i]

                out[i] = {
                    name=c.name,
                    path=c.path,
                    root=c.root,
                    score=c.score,
                    reasons=c.reasons,
                    stats=c.stats,
                }
            end

            return out
        end)(),
    })

    return candidates
end

--==============================================================--
-- MODEL DEDUP / FINGERPRINT
--==============================================================--

local function assetIdFromString(v)
    if type(v) ~= "string" then
        return nil
    end

    local id = string.match(v, "%d+")

    if id then
        return id
    end

    return nil
end

local function modelFingerprint(model)
    local tokens = {}

    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("MeshPart") then
            table.insert(tokens, "M:" .. tostring(inst.MeshId))
            table.insert(tokens, "T:" .. tostring(inst.TextureID))
        elseif inst:IsA("SpecialMesh") then
            table.insert(tokens, "SM:" .. tostring(inst.MeshId))
            table.insert(tokens, "ST:" .. tostring(inst.TextureId))
        elseif inst:IsA("Animation") then
            table.insert(tokens, "A:" .. tostring(inst.AnimationId))
        elseif inst:IsA("Bone") then
            table.insert(tokens, "B:" .. inst.Name)
        elseif inst:IsA("Motor6D") then
            table.insert(tokens, "J:" .. inst.Name)
        end
    end

    table.sort(tokens)

    local joined = table.concat(tokens, "|")

    -- FNV-1a style 32-bit hash for a compact comparison fingerprint.
    local hash = 2166136261

    for i = 1, #joined do
        hash = bit32.bxor(hash, string.byte(joined, i))
        hash = (hash * 16777619) % 4294967296
    end

    return string.format("%08x", hash), #tokens
end

local function selectTen(candidates)
    local selected = {}
    local seenPath = {}

    -- Keep distinct instances/paths. Fingerprints are reported, not used to
    -- reject variants because the user asked for ten dinosaur models.
    for _, c in ipairs(candidates) do
        if #selected >= CONFIG.TARGET_MODELS then
            break
        end

        if c.instance
        and c.instance.Parent
        and not seenPath[c.path]
        then
            seenPath[c.path] = true

            local fingerprint, tokenCount = modelFingerprint(c.instance)

            c.fingerprint = fingerprint
            c.fingerprintTokens = tokenCount

            table.insert(selected, c)
        end
    end

    Session.Selected = #selected

    queueRecord({
        source="discovery",
        kind="dinosaur_selection",
        target=CONFIG.TARGET_MODELS,
        selected=#selected,
        models=(function()
            local out = {}

            for i, c in ipairs(selected) do
                out[i] = {
                    index=i,
                    name=c.name,
                    path=c.path,
                    root=c.root,
                    score=c.score,
                    reasons=c.reasons,
                    stats=c.stats,
                    fingerprint=c.fingerprint,
                    fingerprintTokens=c.fingerprintTokens,
                }
            end

            return out
        end)(),
    })

    return selected
end

--==============================================================--
-- ASSET REGISTRY
--==============================================================--

local AssetRegistry = {}

local function rememberAsset(kind, raw, ownerPath)
    if raw == nil then
        return
    end

    local text = tostring(raw)

    if text == "" then
        return
    end

    local key = kind .. "|" .. text

    if AssetRegistry[key] then
        return
    end

    AssetRegistry[key] = {
        kind=kind,
        raw=text,
        numericId=assetIdFromString(text),
        firstOwner=ownerPath,
    }

    Session.AssetIdsCollected += 1
end

--==============================================================--
-- INSTANCE DESCRIPTION
--==============================================================--

local function safeProperty(inst, prop)
    local ok, value = pcall(function()
        return inst[prop]
    end)

    if ok then
        return safeSerialize(value)
    end

    return nil
end

local function describeInstance(inst, model)
    local path = safePath(inst)
    local data = {
        className=inst.ClassName,
        name=inst.Name,
        path=path,
        parent=inst.Parent and safePath(inst.Parent) or nil,
        attributes=safeSerialize(inst:GetAttributes()),
    }

    if inst:IsA("BasePart") then
        data.basePart = {
            cframe=safeSerialize(inst.CFrame),
            position=safeSerialize(inst.Position),
            orientation=safeSerialize(inst.Orientation),
            size=safeSerialize(inst.Size),
            color=safeSerialize(inst.Color),
            brickColor=tostring(inst.BrickColor),
            material=tostring(inst.Material),
            transparency=inst.Transparency,
            reflectance=inst.Reflectance,
            anchored=inst.Anchored,
            canCollide=inst.CanCollide,
            canTouch=inst.CanTouch,
            canQuery=inst.CanQuery,
            massless=inst.Massless,
            collisionGroup=inst.CollisionGroup,
            customPhysicalProperties=safeSerialize(inst.CustomPhysicalProperties),
            assemblyMass=safeProperty(inst, "AssemblyMass"),
            assemblyLinearVelocity=safeSerialize(inst.AssemblyLinearVelocity),
            assemblyAngularVelocity=safeSerialize(inst.AssemblyAngularVelocity),
        }
    end

    if inst:IsA("MeshPart") then
        data.meshPart = {
            meshId=inst.MeshId,
            textureId=inst.TextureID,
            renderFidelity=tostring(inst.RenderFidelity),
            collisionFidelity=tostring(inst.CollisionFidelity),
            doubleSided=safeProperty(inst, "DoubleSided"),
        }

        rememberAsset("mesh", inst.MeshId, path)
        rememberAsset("texture", inst.TextureID, path)
    end

    if inst:IsA("SpecialMesh") then
        data.specialMesh = {
            meshType=tostring(inst.MeshType),
            meshId=inst.MeshId,
            textureId=inst.TextureId,
            scale=safeSerialize(inst.Scale),
            offset=safeSerialize(inst.Offset),
            vertexColor=safeSerialize(inst.VertexColor),
        }

        rememberAsset("mesh", inst.MeshId, path)
        rememberAsset("texture", inst.TextureId, path)
    end

    if inst:IsA("Bone") then
        data.bone = {
            cframe=safeSerialize(inst.CFrame),
            worldCFrame=safeProperty(inst, "WorldCFrame"),
            transform=safeSerialize(inst.Transform),
            transformedWorldCFrame=safeProperty(inst, "TransformedWorldCFrame"),
        }
    end

    if inst:IsA("Attachment") then
        data.attachment = {
            cframe=safeSerialize(inst.CFrame),
            position=safeSerialize(inst.Position),
            orientation=safeSerialize(inst.Orientation),
            axis=safeSerialize(inst.Axis),
            secondaryAxis=safeSerialize(inst.SecondaryAxis),
            worldCFrame=safeProperty(inst, "WorldCFrame"),
            worldPosition=safeProperty(inst, "WorldPosition"),
        }
    end

    if inst:IsA("Motor6D") then
        data.motor6D = {
            part0=safeSerialize(inst.Part0),
            part1=safeSerialize(inst.Part1),
            c0=safeSerialize(inst.C0),
            c1=safeSerialize(inst.C1),
            transform=safeSerialize(inst.Transform),
            enabled=safeProperty(inst, "Enabled"),
        }
    elseif inst:IsA("Weld") then
        data.weld = {
            part0=safeSerialize(inst.Part0),
            part1=safeSerialize(inst.Part1),
            c0=safeSerialize(inst.C0),
            c1=safeSerialize(inst.C1),
            enabled=safeProperty(inst, "Enabled"),
        }
    elseif inst:IsA("WeldConstraint") then
        data.weldConstraint = {
            part0=safeSerialize(inst.Part0),
            part1=safeSerialize(inst.Part1),
            enabled=inst.Enabled,
        }
    end

    if inst:IsA("Humanoid") then
        data.humanoid = {
            health=inst.Health,
            maxHealth=inst.MaxHealth,
            walkSpeed=inst.WalkSpeed,
            jumpPower=inst.JumpPower,
            jumpHeight=inst.JumpHeight,
            hipHeight=inst.HipHeight,
            rigType=tostring(inst.RigType),
            displayDistanceType=tostring(inst.DisplayDistanceType),
            healthDisplayType=tostring(inst.HealthDisplayType),
            nameDisplayDistance=inst.NameDisplayDistance,
            healthDisplayDistance=inst.HealthDisplayDistance,
            autoRotate=inst.AutoRotate,
            breakJointsOnDeath=inst.BreakJointsOnDeath,
            requiresNeck=inst.RequiresNeck,
        }
    end

    if inst:IsA("Animation") then
        data.animation = {
            animationId=inst.AnimationId,
        }

        rememberAsset("animation", inst.AnimationId, path)
    end

    if inst:IsA("Animator") then
        local tracks = {}

        local ok, playing = pcall(function()
            return inst:GetPlayingAnimationTracks()
        end)

        if ok and type(playing) == "table" then
            for i, track in ipairs(playing) do
                if i > 80 then
                    break
                end

                local animationId

                pcall(function()
                    if track.Animation then
                        animationId = track.Animation.AnimationId
                    end
                end)

                tracks[#tracks + 1] = {
                    name=track.Name,
                    animationId=animationId,
                    speed=safeProperty(track, "Speed"),
                    timePosition=safeProperty(track, "TimePosition"),
                    length=safeProperty(track, "Length"),
                    looped=safeProperty(track, "Looped"),
                    priority=safeProperty(track, "Priority"),
                    isPlaying=safeProperty(track, "IsPlaying"),
                    weightCurrent=safeProperty(track, "WeightCurrent"),
                    weightTarget=safeProperty(track, "WeightTarget"),
                }

                if animationId then
                    rememberAsset("animation", animationId, path)
                end
            end
        end

        data.animator = {
            playingTracks=tracks,
        }
    end

    if inst:IsA("Decal") or inst:IsA("Texture") then
        data.texture = {
            texture=inst.Texture,
            color3=safeProperty(inst, "Color3"),
            transparency=safeProperty(inst, "Transparency"),
        }

        rememberAsset("texture", inst.Texture, path)
    end

    if inst:IsA("SurfaceAppearance") then
        data.surfaceAppearance = {
            colorMap=inst.ColorMap,
            metalnessMap=inst.MetalnessMap,
            normalMap=inst.NormalMap,
            roughnessMap=inst.RoughnessMap,
            alphaMode=tostring(inst.AlphaMode),
            color=safeProperty(inst, "Color"),
        }

        rememberAsset("texture", inst.ColorMap, path)
        rememberAsset("texture", inst.MetalnessMap, path)
        rememberAsset("texture", inst.NormalMap, path)
        rememberAsset("texture", inst.RoughnessMap, path)
    end

    if inst:IsA("Sound") then
        data.sound = {
            soundId=inst.SoundId,
            volume=inst.Volume,
            playbackSpeed=inst.PlaybackSpeed,
            looped=inst.Looped,
            rollOffMaxDistance=inst.RollOffMaxDistance,
            rollOffMinDistance=inst.RollOffMinDistance,
            rollOffMode=tostring(inst.RollOffMode),
        }

        rememberAsset("sound", inst.SoundId, path)
    end

    if inst:IsA("ParticleEmitter") then
        data.particleEmitter = {
            texture=inst.Texture,
            enabled=inst.Enabled,
            rate=inst.Rate,
            lifetime=safeSerialize(inst.Lifetime),
            speed=safeSerialize(inst.Speed),
            acceleration=safeSerialize(inst.Acceleration),
            drag=safeProperty(inst, "Drag"),
            lightEmission=inst.LightEmission,
            lightInfluence=inst.LightInfluence,
            orientation=tostring(inst.Orientation),
            rotation=safeSerialize(inst.Rotation),
            rotSpeed=safeSerialize(inst.RotSpeed),
            spreadAngle=safeSerialize(inst.SpreadAngle),
            zOffset=inst.ZOffset,
        }

        rememberAsset("texture", inst.Texture, path)
    end

    if inst:IsA("Trail") then
        data.trail = {
            attachment0=safeSerialize(inst.Attachment0),
            attachment1=safeSerialize(inst.Attachment1),
            enabled=inst.Enabled,
            lifetime=inst.Lifetime,
            texture=inst.Texture,
            textureLength=inst.TextureLength,
            textureMode=tostring(inst.TextureMode),
            faceCamera=inst.FaceCamera,
            lightEmission=inst.LightEmission,
            lightInfluence=inst.LightInfluence,
        }

        rememberAsset("texture", inst.Texture, path)
    end

    if inst:IsA("Beam") then
        data.beam = {
            attachment0=safeSerialize(inst.Attachment0),
            attachment1=safeSerialize(inst.Attachment1),
            enabled=inst.Enabled,
            texture=inst.Texture,
            textureLength=inst.TextureLength,
            textureMode=tostring(inst.TextureMode),
            faceCamera=inst.FaceCamera,
            width0=inst.Width0,
            width1=inst.Width1,
            curveSize0=inst.CurveSize0,
            curveSize1=inst.CurveSize1,
            segments=inst.Segments,
        }

        rememberAsset("texture", inst.Texture, path)
    end

    if inst:IsA("ProximityPrompt") then
        data.prompt = {
            actionText=inst.ActionText,
            objectText=inst.ObjectText,
            enabled=inst.Enabled,
            holdDuration=inst.HoldDuration,
            maxActivationDistance=inst.MaxActivationDistance,
            requiresLineOfSight=inst.RequiresLineOfSight,
            keyboardKeyCode=tostring(inst.KeyboardKeyCode),
            gamepadKeyCode=tostring(inst.GamepadKeyCode),
        }
    end

    if inst:IsA("ValueBase") then
        data.valueBase = {
            value=safeSerialize(inst.Value),
        }
    end

    if inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("ModuleScript") then
        data.scriptMetadata = {
            className=inst.ClassName,
            disabled=safeProperty(inst, "Disabled"),
            enabled=safeProperty(inst, "Enabled"),
            runContext=safeProperty(inst, "RunContext"),
        }
    end

    return data
end

--==============================================================--
-- MODEL COLLECTION
--==============================================================--

local function modelHeader(model, candidate, index)
    local pivot

    pcall(function()
        pivot = model:GetPivot()
    end)

    local boundingCFrame
    local boundingSize

    pcall(function()
        boundingCFrame, boundingSize = model:GetBoundingBox()
    end)

    local primary = model.PrimaryPart

    return {
        source="dinosaur_model",
        kind="model_begin",
        modelIndex=index,
        name=model.Name,
        path=safePath(model),
        root=candidate.root,
        candidateScore=candidate.score,
        candidateReasons=candidate.reasons,
        candidateStats=candidate.stats,
        fingerprint=candidate.fingerprint,
        fingerprintTokens=candidate.fingerprintTokens,
        attributes=safeSerialize(model:GetAttributes()),
        primaryPart=primary and safeSerialize(primary) or nil,
        pivot=pivot and safeSerialize(pivot) or nil,
        boundingBox={
            cframe=boundingCFrame and safeSerialize(boundingCFrame) or nil,
            size=boundingSize and safeSerialize(boundingSize) or nil,
        },
        scale=safeProperty(model, "Scale"),
        descendantCount=#model:GetDescendants(),
    }
end

local function collectModel(candidate, index)
    local model = candidate.instance

    if not model or not model.Parent then
        queueRecord({
            source="dinosaur_model",
            kind="model_missing_before_collection",
            modelIndex=index,
            name=candidate.name,
            path=candidate.path,
        })

        return false
    end

    Session.CurrentModel =
        string.format(
            "%d/%d • %s",
            index,
            CONFIG.TARGET_MODELS,
            model.Name
        )

    updateUI(true)

    queueRecord(
        modelHeader(
            model,
            candidate,
            index
        )
    )

    local descendants = model:GetDescendants()
    local count = 0
    local classCounts = {}

    for _, inst in ipairs(descendants) do
        if not Session.Running or Session.StopRequested then
            break
        end

        if count >= CONFIG.MAX_DESCENDANTS_PER_MODEL then
            queueRecord({
                source="dinosaur_model",
                kind="model_descendant_limit",
                modelIndex=index,
                modelPath=safePath(model),
                limit=CONFIG.MAX_DESCENDANTS_PER_MODEL,
                actual=#descendants,
            })

            break
        end

        count += 1
        Session.DescendantsCollected += 1

        classCounts[inst.ClassName] =
            (classCounts[inst.ClassName] or 0)
            + 1

        local objectData
        local descOk, descResult = guarded(
            "describeInstance:" .. safePath(inst),
            describeInstance,
            inst,
            model
        )

        if descOk then
            objectData = descResult
        else
            objectData = {
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
                collectionError=true,
            }
        end

        queueRecord({
            source="dinosaur_model",
            kind="model_descendant",
            modelIndex=index,
            modelName=model.Name,
            modelPath=safePath(model),
            descendantIndex=count,
            object=objectData,
        })

        if count % CONFIG.YIELD_EVERY == 0 then
            task.wait()
        end
    end

    local assets = {}

    for _, item in pairs(AssetRegistry) do
        if contains(item.firstOwner or "", safePath(model)) then
            table.insert(assets, item)
        end
    end

    table.sort(assets, function(a, b)
        if a.kind == b.kind then
            return a.raw < b.raw
        end

        return a.kind < b.kind
    end)

    queueRecord({
        source="dinosaur_model",
        kind="model_complete",
        modelIndex=index,
        modelName=model.Name,
        modelPath=safePath(model),
        descendantsRecorded=count,
        classCounts=classCounts,
        fingerprint=candidate.fingerprint,
        assets=assets,
    })

    Session.ModelsCollected += 1
    updateUI(true)

    return true
end

--==============================================================--
-- HTTP / UPLOAD
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false, nil, "request indisponível"
    end

    local lastError

    for attempt = 1, CONFIG.HTTP_RETRIES do
        local ok, response = pcall(REQUEST, options)

        if ok and type(response) == "table" then
            local status = tonumber(
                response.StatusCode
                or response.Status
                or response.status
            )

            local body =
                response.Body
                or response.body
                or ""

            local success = response.Success

            if success == nil and status then
                success =
                    status >= 200
                    and status < 300
            end

            if success == true then
                return true, status, body
            end

            lastError =
                "HTTP "
                .. tostring(status)
                .. " "
                .. truncateString(tostring(body))
        else
            lastError = tostring(response)
        end

        task.wait(
            CONFIG.HTTP_RETRY_BASE
            * attempt
        )
    end

    return false, nil, lastError
end

local function postJson(url, data)
    local ok, _, body = requestRaw({
        Url=url,
        Method="POST",
        Headers={
            ["Content-Type"]="application/json",
        },
        Body=safeJson(data),
    })

    if not ok then
        return false, nil, body
    end

    local decodeOk, decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            body
        )

    if decodeOk then
        return true, decoded, nil
    end

    return true, {raw=body}, nil
end

local function iterateObjects(callback)
    local header = {
        recordType="dinosaur_models_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        clientVisibleOnly=true,
        generatedAt=os.time(),
        targetModels=CONFIG.TARGET_MODELS,
        modelsCollected=Session.ModelsCollected,
        descendantsCollected=Session.DescendantsCollected,
        assetIdsCollected=Session.AssetIdsCollected,
        archiveRecords=Archive.Records,
        archiveBytes=Archive.Bytes,
    }

    if callback(header) == false then
        return false
    end

    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            if ISFILE(path) then
                local ok, text = pcall(READFILE, path)

                if ok and type(text) == "string" then
                    for line in string.gmatch(text, "[^\r\n]+") do
                        local decodeOk, object =
                            pcall(
                                HttpService.JSONDecode,
                                HttpService,
                                line
                            )

                        if decodeOk and type(object) == "table" then
                            if callback(object) == false then
                                return false
                            end
                        end
                    end
                end
            end
        end
    else
        for _, line in ipairs(Archive.MemoryLines) do
            local decodeOk, object =
                pcall(
                    HttpService.JSONDecode,
                    HttpService,
                    line
                )

            if decodeOk and type(object) == "table" then
                if callback(object) == false then
                    return false
                end
            end
        end
    end

    return true
end

local function streamChunks(onChunk)
    flushPending(true)

    local current = {}
    local currentBytes = 2
    local index = 0
    local totalBytes = 0
    local streamError

    local function flush()
        if #current == 0 then
            return true
        end

        index += 1

        local objects = current
        local payloadBytes =
            math.max(
                2,
                currentBytes - 1
            )

        current = {}
        currentBytes = 2

        local ok, err =
            onChunk(
                index,
                objects,
                payloadBytes
            )

        table.clear(objects)
        objects = nil

        if not ok then
            streamError = err
            return false
        end

        totalBytes += payloadBytes

        task.wait()

        pcall(function()
            collectgarbage("step", 180)
        end)

        return true
    end

    local iterOk =
        iterateObjects(function(object)
            local encoded =
                safeJson(object)

            local add =
                #encoded + 1

            if #current > 0
            and currentBytes + add
                > CONFIG.UPLOAD_CHUNK_BYTES
            then
                if not flush() then
                    return false
                end
            end

            table.insert(
                current,
                object
            )

            currentBytes += add

            return true
        end)

    if not iterOk and streamError then
        return false, index, totalBytes, streamError
    end

    if #current > 0
    and not flush()
    then
        return false, index, totalBytes, streamError
    end

    return true, index, totalBytes, nil
end

local function deleteArchive()
    if Archive.Persistent then
        for _, path in ipairs(Archive.Blocks) do
            if ISFILE(path) then
                pcall(DELFILE, path)
            end
        end

        if ISFILE(CONFIG.MANIFEST_PATH) then
            pcall(DELFILE, CONFIG.MANIFEST_PATH)
        end
    else
        table.clear(Archive.MemoryLines)
    end

    Archive.Blocks = {blockPath(1)}
    Archive.CurrentBlock = 1
    Archive.CurrentBlockBytes = 0
    Archive.Bytes = 0
    Archive.Records = 0
    Archive.PendingLines = {}
    Archive.PendingBytes = 0
end

local function uploadAll()
    if Upload.Running
    or Archive.Records <= 0
    then
        return
    end

    Upload.Running = true
    Upload.LastError = nil
    Upload.CurrentChunk = 0
    Upload.TotalChunks = 0
    Upload.BytesSent = 0
    Upload.TotalBytes =
        math.max(
            Archive.Bytes,
            1
        )

    Action.Text = "ENVIANDO..."
    Action.BackgroundColor3 =
        Color3.fromRGB(169,42,49)

    Status.Text =
        "Iniciando upload dos modelos..."

    updateUI(true)

    flushPending(true)
    writeManifest()

    local filename = string.format(
        "Cafeina_DinosaurModels_%s_%s.json",
        tostring(game.PlaceId),
        isoUTC()
    )

    local startOk,
        startData,
        startErr =
        postJson(
            CONFIG.UPLOAD_BASE
                .. "/start",
            {
                filename=filename,
                source=CONFIG.VERSION,
                metadata={
                    scanner=CONFIG.VERSION,
                    placeId=game.PlaceId,
                    gameId=game.GameId,
                    placeVersion=game.PlaceVersion,
                    clientVisibleOnly=true,
                    focus="ten_complete_dinosaur_models",
                    targetModels=CONFIG.TARGET_MODELS,
                    modelsCollected=Session.ModelsCollected,
                    descendantsCollected=Session.DescendantsCollected,
                    assetIdsCollected=Session.AssetIdsCollected,
                    persistentArchive=Archive.Persistent,
                    streamingUpload=true,
                    targetChunkBytes=CONFIG.UPLOAD_CHUNK_BYTES,
                },
            }
        )

    if not startOk then
        Upload.Running = false
        Upload.LastError = startErr

        Status.Text =
            "Erro /start • dados preservados"

        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.UploadId =
        type(startData) == "table"
        and (
            startData.uploadId
            or startData.id
            or startData.upload_id
        )
        or nil

    if not Upload.UploadId then
        Upload.Running = false

        Status.Text =
            "/start inválido • dados preservados"

        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    local streamOk,
        chunkCount,
        payloadBytes,
        streamErr =
        streamChunks(function(index, objects, bytes)
            Upload.CurrentChunk = index

            updateUI(true)

            local ok, _, err =
                postJson(
                    CONFIG.UPLOAD_BASE
                        .. "/chunk",
                    {
                        uploadId=Upload.UploadId,
                        index=index,
                        objects=objects,
                    }
                )

            if not ok then
                return false, err
            end

            Upload.BytesSent += bytes
            updateUI(true)

            return true
        end)

    if not streamOk then
        Upload.Running = false
        Upload.LastError = streamErr

        Status.Text =
            "Erro chunk • dados preservados"

        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.TotalChunks = chunkCount
    Upload.TotalBytes = math.max(payloadBytes,1)
    Upload.BytesSent = payloadBytes

    updateUI(true)

    local finishOk,
        finishData,
        finishErr =
        postJson(
            CONFIG.UPLOAD_BASE
                .. "/finish",
            {
                uploadId=Upload.UploadId,
                totalChunks=chunkCount,
                totalBytes=payloadBytes,
                records=Archive.Records,
            }
        )

    if not finishOk then
        Upload.Running = false
        Upload.LastError = finishErr

        Status.Text =
            "/finish falhou • dados preservados"

        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    local confirmed =
        type(finishData) == "table"
        and (
            finishData.confirmed == true
            or finishData.success == true
            or finishData.ok == true
        )

    if not confirmed then
        Upload.Running = false

        Status.Text =
            "Servidor não confirmou • preservado"

        Action.Text = "REENVIAR"
        updateUI(true)
        return
    end

    Upload.LastURL = tostring(
        finishData.url
        or finishData.link
        or finishData.fileUrl
        or ""
    )

    deleteArchive()

    Upload.Running = false

    Status.Text =
        "Upload confirmado ✓"

    Detail.Text =
        Upload.LastURL ~= ""
        and (
            "Link recebido • "
            .. string.sub(
                Upload.LastURL,
                1,
                68
            )
        )
        or "Servidor confirmou • archive limpo"

    Action.Text =
        "COLETAR 10 DINOS"

    Action.BackgroundColor3 =
        Color3.fromRGB(31,31,37)

    BarFill.Size =
        UDim2.new(1,0,1,0)
end

--==============================================================--
-- UI
--==============================================================--

local COLORS = {
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    RED=Color3.fromRGB(169,42,49),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
    BAR=Color3.fromRGB(232,232,235),
}

local GuiParent = CoreGui

if type(gethui) == "function" then
    local ok, value = pcall(gethui)

    if ok and value then
        GuiParent = value
    end
end

pcall(function()
    local old =
        GuiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui = Instance.new("ScreenGui")
Gui.Name = CONFIG.GUI_NAME
Gui.ResetOnSpawn = false

local parentOk = pcall(function()
    Gui.Parent = GuiParent
end)

if not parentOk then
    Gui.Parent =
        LocalPlayer:
        WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(304,210)
Main.AnchorPoint = Vector2.new(0.5,0.5)
Main.Position = UDim2.fromScale(0.5,0.44)
Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0
Main.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.STROKE
stroke.Thickness = 1
stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(10,7)
Title.Size = UDim2.new(1,-20,0,23)
Title.Font = Enum.Font.GothamBold
Title.Text = "CAFEÍNA • DINO MODEL COLLECTOR"
Title.TextColor3 = COLORS.TEXT
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.fromOffset(10,27)
Subtitle.Size = UDim2.new(1,-20,0,18)
Subtitle.Font = Enum.Font.Gotham
Subtitle.Text = "10 MODELOS • RIG + MESH + ASSETS + ANIMAÇÕES"
Subtitle.TextColor3 = COLORS.MUTED
Subtitle.TextSize = 8
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Main

Action = Instance.new("TextButton")
Action.Position = UDim2.fromOffset(10,50)
Action.Size = UDim2.new(1,-20,0,42)
Action.BackgroundColor3 = COLORS.BUTTON
Action.BorderSizePixel = 0
Action.Font = Enum.Font.GothamBold
Action.Text = "COLETAR 10 DINOS"
Action.TextColor3 = COLORS.TEXT
Action.TextSize = 11
Action.AutoButtonColor = false
Action.Parent = Main

local ac = Instance.new("UICorner")
ac.CornerRadius = UDim.new(0,8)
ac.Parent = Action

Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(10,99)
Status.Size = UDim2.new(1,-20,0,39)
Status.Font = Enum.Font.Gotham
Status.Text = "Pronto • procura Workspace + ReplicatedStorage"
Status.TextColor3 = COLORS.TEXT
Status.TextSize = 10
Status.TextWrapped = true
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Parent = Main

Detail = Instance.new("TextLabel")
Detail.BackgroundTransparency = 1
Detail.Position = UDim2.fromOffset(10,141)
Detail.Size = UDim2.new(1,-20,0,39)
Detail.Font = Enum.Font.Gotham
Detail.Text = "0.00 MB • 0 modelos • 0 objetos"
Detail.TextColor3 = COLORS.MUTED
Detail.TextSize = 9
Detail.TextWrapped = true
Detail.TextXAlignment = Enum.TextXAlignment.Left
Detail.TextYAlignment = Enum.TextYAlignment.Top
Detail.Parent = Main

local BarBack = Instance.new("Frame")
BarBack.Position = UDim2.fromOffset(10,191)
BarBack.Size = UDim2.new(1,-20,0,7)
BarBack.BackgroundColor3 = Color3.fromRGB(27,27,31)
BarBack.BorderSizePixel = 0
BarBack.Parent = Main

local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(1,0)
bc.Parent = BarBack

BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = COLORS.BAR
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBack

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(1,0)
fc.Parent = BarFill

-- Mobile drag.
do
    local dragging=false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging=true
            dragStart=input.Position
            startPos=Main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging=false
                end
            end)
        end
    end)

    Main.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
        then
            dragInput=input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta =
                input.Position
                - dragStart

            Main.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
        end
    end)
end

local lastUiClock=0

updateUI=function(force)
    local now=os.clock()

    if not force
    and now-lastUiClock<0.16
    then
        return
    end

    lastUiClock=now

    if Upload.Running then
        Status.Text=string.format(
            "Enviando chunk %d%s",
            Upload.CurrentChunk,
            Upload.TotalChunks>0
                and (
                    "/"
                    .. tostring(
                        Upload.TotalChunks
                    )
                )
                or " • streaming"
        )

        local ratio=
            Upload.TotalBytes>0
            and math.clamp(
                Upload.BytesSent
                    / Upload.TotalBytes,
                0,
                1
            )
            or 0

        BarFill.Size=
            UDim2.new(
                ratio,
                0,
                1,
                0
            )

        Detail.Text=string.format(
            "%.2f / %.2f MB",
            mb(Upload.BytesSent),
            mb(Upload.TotalBytes)
        )

        return
    end

    local progress=
        CONFIG.TARGET_MODELS>0
        and math.clamp(
            Session.ModelsCollected
                / CONFIG.TARGET_MODELS,
            0,
            1
        )
        or 0

    BarFill.Size=
        UDim2.new(
            progress,
            0,
            1,
            0
        )

    if Session.Running then
        Status.Text=
            "Coletando • "
            .. tostring(
                Session.CurrentModel
            )

        Detail.Text=string.format(
            "%.2f MB • %d/%d modelos • %d objetos\n%d assets • %d candidatos • Err:%d",
            mb(Archive.Bytes),
            Session.ModelsCollected,
            CONFIG.TARGET_MODELS,
            Session.DescendantsCollected,
            Session.AssetIdsCollected,
            Session.Candidates,
            Session.ErrorCount
        )
    else
        Detail.Text=string.format(
            "%.2f MB • %d registros preservados",
            mb(Archive.Bytes),
            Archive.Records
        )
    end
end

--==============================================================--
-- RUNNER
--==============================================================--

local function finishAndUpload()
    if not Session.Running
    or Upload.Running
    then
        return
    end

    Session.StopRequested=true

    local allAssets={}

    for _, item in pairs(AssetRegistry) do
        table.insert(allAssets,item)
    end

    table.sort(allAssets,function(a,b)
        if a.kind==b.kind then
            return a.raw<b.raw
        end

        return a.kind<b.kind
    end)

    queueRecord({
        source="session",
        kind="session_finalized",
        targetModels=CONFIG.TARGET_MODELS,
        modelsCollected=Session.ModelsCollected,
        descendantsCollected=Session.DescendantsCollected,
        assetIdsCollected=Session.AssetIdsCollected,
        candidates=Session.Candidates,
        selected=Session.Selected,
        errors=Session.ErrorCount,
        oversizeDrops=Session.OversizeDrops,
        archivedRecords=Archive.Records,
        archivedBytes=Archive.Bytes,
        assetRegistry=allAssets,
    })

    guarded(
        "final_flush",
        flushPending,
        true
    )

    guarded(
        "final_manifest",
        writeManifest
    )

    Session.Running=false

    Action.Text="ENVIANDO..."
    Action.BackgroundColor3=COLORS.RED

    Status.Text=
        "Finalizando modelos..."

    updateUI(true)

    task.spawn(function()
        task.wait(0.1)
        guarded(
            "uploadAll",
            uploadAll
        )
    end)
end

local function runCollector()
    Session.CurrentModel="descobrindo candidatos"
    updateUI(true)

    local candidates=discoverCandidates()

    if not Session.Running
    or Session.StopRequested
    then
        finishAndUpload()
        return
    end

    local selected=selectTen(candidates)

    if #selected == 0 then
        queueRecord({
            source="discovery",
            kind="no_dinosaur_models_found",
            note="No suitable client-visible dinosaur candidates were found in Workspace or ReplicatedStorage.",
        })

        Session.CurrentModel=
            "nenhum candidato encontrado"

        finishAndUpload()
        return
    end

    for index,candidate in ipairs(selected) do
        if not Session.Running
        or Session.StopRequested
        then
            break
        end

        guarded(
            "collectModel:"
                .. tostring(candidate.path),
            collectModel,
            candidate,
            index
        )
    end

    if #selected<CONFIG.TARGET_MODELS then
        queueRecord({
            source="discovery",
            kind="target_not_fully_reached",
            target=CONFIG.TARGET_MODELS,
            selected=#selected,
            collected=Session.ModelsCollected,
            note="Fewer than ten suitable client-visible dinosaur models were available in the scanned roots.",
        })
    end

    Session.CurrentModel="concluído"

    finishAndUpload()
end

local function begin()
    if Session.Running
    or Upload.Running
    then
        return
    end

    Session.Running=true
    Session.StopRequested=false
    Session.RunId=newRunId()
    Session.StartedClock=os.clock()
    Session.RecordsThisRun=0

    Session.Candidates=0
    Session.Selected=0
    Session.ModelsCollected=0
    Session.DescendantsCollected=0
    Session.AssetIdsCollected=0
    Session.CurrentModel="inicializando"
    Session.ErrorCount=0
    Session.OversizeDrops=0

    table.clear(AssetRegistry)

    Action.Text="PARAR + ENVIAR"
    Action.BackgroundColor3=COLORS.RED

    queueRecord({
        source="session",
        kind="session_started",
        targetModels=CONFIG.TARGET_MODELS,
        searchRoots={
            "Workspace",
            "ReplicatedStorage",
        },
        capabilities={
            filesystem=FILESYSTEM_OK and true or false,
            request=REQUEST~=nil,
        },
        collectionScope={
            hierarchy=true,
            meshParts=true,
            meshIds=true,
            textures=true,
            surfaceAppearance=true,
            bones=true,
            attachments=true,
            motor6D=true,
            welds=true,
            humanoid=true,
            animationController=true,
            animator=true,
            animationIds=true,
            sounds=true,
            particles=true,
            trails=true,
            beams=true,
            prompts=true,
            values=true,
            attributes=true,
            scriptMetadata=true,
        },
        note="Asset binary contents are not downloaded; asset IDs and client-visible model structure are recorded.",
    })

    updateUI(true)

    task.spawn(function()
        guarded(
            "runCollector",
            runCollector
        )
    end)
end

Action.Activated:Connect(function()
    guarded(
        "Action.Activated",
        function()
            if Upload.Running then
                return
            end

            if Action.Text=="REENVIAR" then
                task.spawn(function()
                    guarded(
                        "retry_upload",
                        uploadAll
                    )
                end)

                return
            end

            if Session.Running then
                finishAndUpload()
            else
                begin()
            end
        end
    )
end)

-- Archive size guard.
task.spawn(function()
    while Gui.Parent do
        task.wait(0.5)

        if Session.Running
        and Session.StopRequested
        and not Upload.Running
        then
            guarded(
                "auto_finish",
                finishAndUpload
            )
        end
    end
end)

--==============================================================--
-- LOAD / CONTROLLER
--==============================================================--

loadArchive()
updateUI(true)

env.__CAFEINA_DINO_COLLECTOR_CONTROLLER={
    Stop=function(reason)
        guarded(
            "external_stop",
            function()
                Session.StopRequested=true

                if Session.Running then
                    queueRecord({
                        source="session",
                        kind="controller_stop",
                        reason=reason
                            or "external_stop",
                    })
                end

                flushPending(true)
                writeManifest()

                Session.Running=false

                pcall(function()
                    Gui:Destroy()
                end)
            end
        )
    end,
}

print("[CAFEÍNA] DINOSAUR MODEL COLLECTOR V1.0 carregado.")
