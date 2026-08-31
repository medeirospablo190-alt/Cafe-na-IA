--==============================================================--
-- CAFEÍNA • MORPH TRACE V1.0
-- STEAL AN EGG • EXECUTOR / MOBILE
--
-- OBJETIVO
-- Descobrir o pipeline nativo/replicado de pets/morph:
--   • Workspace.ClientRenderedAssets
--   • ReplicatedStorage.AssetModels
--   • AssetRoster / AssetInventory
--   • LoadPet
--   • SlotKey / GetSlotOwner
--   • Equip / Unequip / Wear
--   • Character swap / HumanoidDescription
--   • remotes legítimos relacionados
--
-- IMPORTANTE
-- • Coleta PASSIVA.
-- • NÃO faz fuzzing.
-- • NÃO dispara remotes desconhecidos.
-- • Observa somente dados client-visible e chamadas reais do jogo.
-- • Archive persistente.
-- • Dados só são apagados após /upload/finish confirmado.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()

local CONFIG = {
    VERSION = "MORPH_TRACE_V2_0",
    GUI_NAME = "CafeinaMorphTraceV20",

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",

    ARCHIVE_ROOT = "CafeinaMorphTrace",
    ARCHIVE_FOLDER = "CafeinaMorphTrace/" .. tostring(game.PlaceId),
    ARCHIVE_FILE = "CafeinaMorphTrace/" .. tostring(game.PlaceId) .. "/morph_trace.jsonl",

    MAX_ARCHIVE_BYTES = 80 * 1024 * 1024,
    CHUNK_TARGET_BYTES = 450000,

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.0,

    HEARTBEAT_SECONDS = 2.0,
    REMOTE_SAMPLE_LIMIT = 30000,
    OBJECT_SAMPLE_LIMIT = 40000,

    KEYWORDS = {
        "clientrenderedassets",
        "assetmodels",
        "assetroster",
        "assetinventory",
        "loadpet",
        "pet",
        "pets",
        "slotkey",
        "getslotowner",
        "equip",
        "unequip",
        "wear",
        "doff",
        "mount",
        "ride",
        "morph",
        "transform",
        "species",
        "setcharacter",
        "setskin",
        "character",
        "humanoiddescription",
        "applydescription",
        "loadcharacter",
        "animationcontroller",
        "animator",
        "rootpart",
    },

    HIGH_VALUE_EXACT = {
        ClientRenderedAssets=true,
        AssetModels=true,
        AssetRoster=true,
        AssetInventory=true,
        LoadPet=true,
        SlotKey=true,
        GetSlotOwner=true,
        HumanoidDescription=true,
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_MORPH_TRACE_V1")
    if type(old) == "table" and type(old.Destroy) == "function" then
        old.Destroy()
    end
end)

local function pick(...)
    for i=1,select("#",...) do
        local v=select(i,...)
        if type(v)=="function" then
            return v
        end
    end
end

local SYN_REQUEST
pcall(function()
    if syn and type(syn.request)=="function" then
        SYN_REQUEST=syn.request
    end
end)

local HTTP_REQUEST_TABLE
pcall(function()
    if http and type(http.request)=="function" then
        HTTP_REQUEST_TABLE=http.request
    end
end)

local REQUEST = pick(
    rawget(env,"request"),
    rawget(env,"http_request"),
    SYN_REQUEST,
    HTTP_REQUEST_TABLE
)

local WRITEFILE = pick(rawget(env,"writefile"))
local READFILE = pick(rawget(env,"readfile"))
local APPENDFILE = pick(rawget(env,"appendfile"))
local ISFILE = pick(rawget(env,"isfile"))
local DELFILE = pick(rawget(env,"delfile"))
local MAKEFOLDER = pick(rawget(env,"makefolder"))
local ISFOLDER = pick(rawget(env,"isfolder"))

local HOOKMETAMETHOD = pick(rawget(env,"hookmetamethod"))
local GETNAMECALLMETHOD = pick(rawget(env,"getnamecallmethod"))
local CHECKCALLER = pick(rawget(env,"checkcaller"))
local NEWCCLOSURE = pick(rawget(env,"newcclosure"))

--==============================================================--
-- STATE
--==============================================================--

local S = {
    Running=false,
    Busy=false,

    Connections={},
    WatchedInstances=setmetatable({}, {__mode="k"}),

    Records={},
    RecordCount=0,
    ArchiveBytes=0,
    Persistent=false,

    Counters={
        snapshots=0,
        objectAdded=0,
        objectRemoving=0,
        valueChanged=0,
        attributeChanged=0,
        remoteReceived=0,
        remoteOutgoing=0,
        characterChanged=0,
        heartbeat=0,
    },

    Upload={
        Running=false,
        UploadId=nil,
        CurrentChunk=0,
        TotalChunks=0,
        BytesSent=0,
        TotalBytes=0,
        LastError=nil,
        LastURL="",
    },

    HookInstalled=false,
    OriginalNamecall=nil,

    Morph={
        Models={},
        Index=1,
        Active=false,
        Clone=nil,
        RenderConn=nil,
        DriverDescConn=nil,
        SavedParts=setmetatable({}, {__mode="k"}),
        SavedTextures=setmetatable({}, {__mode="k"}),
        SavedFx=setmetatable({}, {__mode="k"}),
        BottomOffset=0,
    },

    UI={},
}

--==============================================================--
-- HELPERS
--==============================================================--

local function disconnect(conn)
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function disconnectAll()
    for _,conn in ipairs(S.Connections) do
        disconnect(conn)
    end
    table.clear(S.Connections)
end

local function connect(signal,fn)
    local conn=signal:Connect(fn)
    table.insert(S.Connections,conn)
    return conn
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function safePath(inst)
    if typeof(inst)~="Instance" then
        return tostring(inst)
    end

    local ok,path=pcall(function()
        return inst:GetFullName()
    end)

    return ok and path or inst.Name
end

local function safeAttrs(inst)
    local ok,attrs=pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs)~="table" then
        return {}
    end

    local out={}
    local n=0

    for k,v in pairs(attrs) do
        n+=1
        if n>100 then
            out.__truncated=true
            break
        end

        local tv=typeof(v)

        if tv=="string"
        or tv=="boolean"
        or tv=="number"
        then
            out[tostring(k)]=v
        else
            out[tostring(k)]=tostring(v)
        end
    end

    return out
end

local function serialize(value,depth,seen)
    depth=depth or 0
    seen=seen or {}

    if depth>4 then
        return "<max_depth>"
    end

    local tv=typeof(value)

    if value==nil
    or tv=="string"
    or tv=="number"
    or tv=="boolean"
    then
        return value
    end

    if tv=="Instance" then
        return {
            type="Instance",
            className=value.ClassName,
            name=value.Name,
            path=safePath(value),
            attributes=safeAttrs(value),
        }
    end

    if tv=="Vector3" then
        return {
            type="Vector3",
            x=value.X,y=value.Y,z=value.Z,
        }
    end

    if tv=="Vector2" then
        return {
            type="Vector2",
            x=value.X,y=value.Y,
        }
    end

    if tv=="CFrame" then
        local p=value.Position
        return {
            type="CFrame",
            x=p.X,y=p.Y,z=p.Z,
        }
    end

    if tv=="Color3" then
        return {
            type="Color3",
            r=value.R,g=value.G,b=value.B,
        }
    end

    if tv=="table" then
        if seen[value] then
            return "<cycle>"
        end

        seen[value]=true

        local out={}
        local count=0

        for k,v in pairs(value) do
            count+=1
            if count>80 then
                out.__truncated=true
                break
            end

            out[tostring(k)] =
                serialize(v,depth+1,seen)
        end

        seen[value]=nil
        return out
    end

    return tostring(value)
end

local function isInterestingText(text)
    local l=lower(text)

    for _,kw in ipairs(CONFIG.KEYWORDS) do
        if string.find(l,kw,1,true) then
            return true,kw
        end
    end

    return false,nil
end

local function isInterestingInstance(inst)
    if CONFIG.HIGH_VALUE_EXACT[inst.Name] then
        return true,"exact_name"
    end

    local hit,kw =
        isInterestingText(
            inst.Name.." "..safePath(inst)
        )

    if hit then
        return true,kw
    end

    if inst:IsA("AnimationController")
    or inst:IsA("Animator")
    or inst:IsA("Motor6D")
    or inst:IsA("Bone")
    or inst:IsA("HumanoidDescription")
    then
        local p=inst.Parent
        if p then
            local parentHit,parentKw =
                isInterestingText(
                    p.Name.." "..safePath(p)
                )

            if parentHit then
                return true,parentKw
            end
        end
    end

    return false,nil
end

local function jsonEncode(value)
    local ok,result =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            value
        )

    return ok and result or "{}"
end

local function mb(bytes)
    return (tonumber(bytes) or 0)/(1024*1024)
end

--==============================================================--
-- ARCHIVE
--==============================================================--

local function ensureArchive()
    if not (
        WRITEFILE
        and READFILE
        and ISFILE
    ) then
        S.Persistent=false
        return false
    end

    if MAKEFOLDER then
        pcall(function()
            if ISFOLDER then
                if not ISFOLDER(CONFIG.ARCHIVE_ROOT) then
                    MAKEFOLDER(CONFIG.ARCHIVE_ROOT)
                end

                if not ISFOLDER(CONFIG.ARCHIVE_FOLDER) then
                    MAKEFOLDER(CONFIG.ARCHIVE_FOLDER)
                end
            else
                MAKEFOLDER(CONFIG.ARCHIVE_ROOT)
                MAKEFOLDER(CONFIG.ARCHIVE_FOLDER)
            end
        end)
    end

    S.Persistent=true
    return true
end

local function appendRecord(record)
    if type(record)~="table" then
        return false
    end

    record._traceVersion=CONFIG.VERSION
    record._placeId=game.PlaceId
    record._gameId=game.GameId
    record._placeVersion=game.PlaceVersion
    record._unix=os.time()
    record._clock=os.clock()

    local encoded=jsonEncode(record)
    local bytes=#encoded+1

    if S.ArchiveBytes+bytes
        > CONFIG.MAX_ARCHIVE_BYTES
    then
        return false
    end

    table.insert(S.Records,record)
    S.RecordCount+=1
    S.ArchiveBytes+=bytes

    if S.Persistent then
        local line=encoded.."\n"
        local wrote=false

        if APPENDFILE then
            wrote=pcall(
                APPENDFILE,
                CONFIG.ARCHIVE_FILE,
                line
            )
        end

        if not wrote then
            local prior=""

            if ISFILE(CONFIG.ARCHIVE_FILE) then
                pcall(function()
                    prior=READFILE(CONFIG.ARCHIVE_FILE) or ""
                end)
            end

            pcall(
                WRITEFILE,
                CONFIG.ARCHIVE_FILE,
                prior..line
            )
        end
    end

    return true
end

local function loadArchive()
    ensureArchive()

    table.clear(S.Records)
    S.RecordCount=0
    S.ArchiveBytes=0

    if S.Persistent
    and ISFILE(CONFIG.ARCHIVE_FILE)
    then
        local ok,content =
            pcall(
                READFILE,
                CONFIG.ARCHIVE_FILE
            )

        if ok and type(content)=="string" then
            for line in string.gmatch(content,"[^\r\n]+") do
                local decodedOK,obj =
                    pcall(
                        HttpService.JSONDecode,
                        HttpService,
                        line
                    )

                if decodedOK and type(obj)=="table" then
                    table.insert(S.Records,obj)
                    S.RecordCount+=1
                    S.ArchiveBytes+=#line+1
                end
            end
        end
    end
end

local function clearArchive()
    table.clear(S.Records)
    S.RecordCount=0
    S.ArchiveBytes=0

    if S.Persistent
    and DELFILE
    and ISFILE(CONFIG.ARCHIVE_FILE)
    then
        pcall(
            DELFILE,
            CONFIG.ARCHIVE_FILE
        )
    end
end

--==============================================================--
-- UI STATUS
--==============================================================--

local function updateUI()
    local ui=S.UI

    if ui.CollectButton then
        if S.Running then
            ui.CollectButton.Text="ENCERRAR COLETA"
            ui.CollectButton.BackgroundColor3=
                Color3.fromRGB(155,45,51)
        else
            ui.CollectButton.Text="INICIAR COLETA"
            ui.CollectButton.BackgroundColor3=
                Color3.fromRGB(31,31,37)
        end
    end

    if ui.SendButton then
        if S.Upload.Running then
            ui.SendButton.Text="ENVIANDO..."
            ui.SendButton.BackgroundColor3=
                Color3.fromRGB(170,46,52)
        elseif S.RecordCount>0 then
            ui.SendButton.Text="ENVIAR DADOS"
            ui.SendButton.BackgroundColor3=
                Color3.fromRGB(24,190,72)
        else
            ui.SendButton.Text="SEM DADOS"
            ui.SendButton.BackgroundColor3=
                Color3.fromRGB(31,31,37)
        end
    end

    if ui.DataLabel then
        ui.DataLabel.Text=
            string.format(
                "Arquivado: %.2f MB • %d registros",
                mb(S.ArchiveBytes),
                S.RecordCount
            )
    end

    if ui.CountLabel then
        local c=S.Counters
        ui.CountLabel.Text=
            string.format(
                "Criados %d • Remotes ↑%d ↓%d • Values %d",
                c.objectAdded,
                c.remoteOutgoing,
                c.remoteReceived,
                c.valueChanged
            )
    end

    if ui.UploadLabel then
        if S.Upload.Running then
            ui.UploadLabel.Text=
                string.format(
                    "Enviado: %.2f / %.2f MB • %d/%d",
                    mb(S.Upload.BytesSent),
                    mb(S.Upload.TotalBytes),
                    S.Upload.CurrentChunk,
                    S.Upload.TotalChunks
                )
        elseif S.Upload.LastError then
            ui.UploadLabel.Text=
                "Upload: erro • dados preservados"
        elseif S.Upload.LastURL~="" then
            ui.UploadLabel.Text=
                "Upload confirmado ✓"
        else
            ui.UploadLabel.Text=
                string.format(
                    "Enviado: %.2f MB",
                    mb(S.Upload.BytesSent)
                )
        end
    end

    if ui.BarFill then
        local ratio=0

        if S.Upload.TotalBytes>0 then
            ratio=
                math.clamp(
                    S.Upload.BytesSent
                    / S.Upload.TotalBytes,
                    0,
                    1
                )
        end

        ui.BarFill.Size=
            UDim2.new(
                ratio,
                0,
                1,
                0
            )
    end
end

local function setStatus(text)
    if S.UI.Status then
        S.UI.Status.Text=tostring(text)
    end
end

--==============================================================--
-- OBJECT SNAPSHOT
--==============================================================--

local function snapshotInstance(inst,reason,keyword)
    local record={
        recordType="morph_object_snapshot",
        reason=reason,
        keyword=keyword,
        className=inst.ClassName,
        name=inst.Name,
        path=safePath(inst),
        parent=inst.Parent and safePath(inst.Parent) or nil,
        attributes=safeAttrs(inst),
    }

    if inst:IsA("ValueBase") then
        record.value=serialize(inst.Value)
    end

    if inst:IsA("ObjectValue") then
        record.objectValue=
            inst.Value
            and serialize(inst.Value)
            or nil
    end

    if inst:IsA("BasePart") then
        record.position=serialize(inst.Position)
        record.size=serialize(inst.Size)
        record.anchored=inst.Anchored
        record.canCollide=inst.CanCollide
        record.transparency=inst.Transparency
    end

    if inst:IsA("MeshPart") then
        record.meshId=inst.MeshId
        record.textureId=inst.TextureID
    elseif inst:IsA("SpecialMesh") then
        record.meshId=inst.MeshId
        record.textureId=inst.TextureId
    elseif inst:IsA("Motor6D") then
        record.part0=inst.Part0 and safePath(inst.Part0) or nil
        record.part1=inst.Part1 and safePath(inst.Part1) or nil
        record.c0=tostring(inst.C0)
        record.c1=tostring(inst.C1)
    elseif inst:IsA("Weld")
        or inst:IsA("WeldConstraint")
    then
        record.part0=inst.Part0 and safePath(inst.Part0) or nil
        record.part1=inst.Part1 and safePath(inst.Part1) or nil
    elseif inst:IsA("Animation") then
        record.animationId=inst.AnimationId
    elseif inst:IsA("HumanoidDescription") then
        record.description=true
    elseif inst:IsA("RemoteEvent")
        or inst:IsA("RemoteFunction")
        or inst:IsA("UnreliableRemoteEvent")
    then
        record.remote=true
    end

    appendRecord(record)
    S.Counters.snapshots+=1
end

--==============================================================--
-- INSTANCE WATCHERS
--==============================================================--

local function watchValue(inst)
    if S.WatchedInstances[inst] then
        return
    end

    S.WatchedInstances[inst]=true

    if inst:IsA("ValueBase") then
        connect(
            inst.Changed,
            function(value)
                if not S.Running then
                    return
                end

                appendRecord({
                    recordType="morph_value_changed",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                    value=serialize(value),
                    attributes=safeAttrs(inst),
                })

                S.Counters.valueChanged+=1
                updateUI()
            end
        )
    end

    connect(
        inst.AttributeChanged,
        function(attribute)
            if not S.Running then
                return
            end

            local hit,kw=
                isInterestingText(
                    tostring(attribute)
                    .." "
                    ..inst.Name
                    .." "
                    ..safePath(inst)
                )

            if hit then
                local ok,value =
                    pcall(function()
                        return inst:GetAttribute(attribute)
                    end)

                appendRecord({
                    recordType="morph_attribute_changed",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                    attribute=attribute,
                    value=ok and serialize(value) or "<read_error>",
                    keyword=kw,
                })

                S.Counters.attributeChanged+=1
                updateUI()
            end
        end
    )
end

local function watchRemoteReceived(remote)
    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("UnreliableRemoteEvent")
    ) then
        return
    end

    local interesting,kw=
        isInterestingInstance(remote)

    if not interesting then
        return
    end

    connect(
        remote.OnClientEvent,
        function(...)
            if not S.Running then
                return
            end

            if S.Counters.remoteReceived
                >= CONFIG.REMOTE_SAMPLE_LIMIT
            then
                return
            end

            S.Counters.remoteReceived+=1

            appendRecord({
                recordType="morph_remote_received",
                remote=safePath(remote),
                remoteName=remote.Name,
                className=remote.ClassName,
                keyword=kw,
                args=serialize(table.pack(...)),
            })

            updateUI()
        end
    )
end

local function watchInteresting(inst,reason)
    local interesting,kw=
        isInterestingInstance(inst)

    if not interesting then
        return
    end

    if S.Counters.objectAdded
        + S.Counters.snapshots
        < CONFIG.OBJECT_SAMPLE_LIMIT
    then
        snapshotInstance(
            inst,
            reason,
            kw
        )
    end

    watchValue(inst)
    watchRemoteReceived(inst)
end

local function scanInitial()
    appendRecord({
        recordType="morph_trace_header",
        version=CONFIG.VERSION,
        player=LP.Name,
        userId=LP.UserId,
        jobId=game.JobId,
        targets={
            "ClientRenderedAssets",
            "AssetModels",
            "AssetRoster",
            "AssetInventory",
            "LoadPet",
            "SlotKey",
            "GetSlotOwner",
            "Equip/Unequip/Wear",
            "Mount/Ride",
            "Character swap",
            "HumanoidDescription",
        },
        passiveOnly=true,
    })

    local roots={
        ReplicatedStorage,
        Workspace,
        LP,
    }

    for _,root in ipairs(roots) do
        watchInteresting(root,"initial_root")

        local descendants=root:GetDescendants()

        for i,inst in ipairs(descendants) do
            if not S.Running then
                return
            end

            watchInteresting(
                inst,
                "initial_scan"
            )

            if i%400==0 then
                task.wait()
            end
        end
    end

    -- Explicit Character baseline.
    if LP.Character then
        appendRecord({
            recordType="morph_character_baseline",
            character=safePath(LP.Character),
            characterName=LP.Character.Name,
            pivot=serialize(LP.Character:GetPivot()),
            humanoid=
                LP.Character:FindFirstChildOfClass("Humanoid")
                and serialize(
                    LP.Character:FindFirstChildOfClass("Humanoid")
                )
                or nil,
        })
    end
end

--==============================================================--
-- OUTGOING REMOTE OBSERVER
--==============================================================--

local function installRemoteHook()
    if S.HookInstalled
    or not HOOKMETAMETHOD
    or not GETNAMECALLMETHOD
    then
        return false
    end

    local oldNamecall

    local wrapper=function(self,...)
        local method=GETNAMECALLMETHOD()

        if S.Running
        and (
            method=="FireServer"
            or method=="InvokeServer"
        )
        and typeof(self)=="Instance"
        and (
            self:IsA("RemoteEvent")
            or self:IsA("RemoteFunction")
            or self:IsA("UnreliableRemoteEvent")
        )
        then
            local callerIsExecutor=false

            if CHECKCALLER then
                local ok,value=pcall(CHECKCALLER)
                callerIsExecutor=
                    ok and value==true
            end

            -- Only real game calls, not this collector/executor.
            if not callerIsExecutor
            and S.Counters.remoteOutgoing
                < CONFIG.REMOTE_SAMPLE_LIMIT
            then
                local args=table.pack(...)
                local searchText=
                    self.Name.." "..safePath(self)

                for i=1,args.n do
                    if type(args[i])=="string" then
                        searchText=
                            searchText
                            .." "
                            ..args[i]
                    end
                end

                local hit,kw=
                    isInterestingText(searchText)

                if hit then
                    S.Counters.remoteOutgoing+=1

                    appendRecord({
                        recordType="morph_remote_outgoing_legit",
                        method=method,
                        remote=self.Name,
                        path=safePath(self),
                        className=self.ClassName,
                        keyword=kw,
                        args=serialize(args),
                    })

                    updateUI()
                end
            end
        end

        return oldNamecall(self,...)
    end

    if NEWCCLOSURE then
        wrapper=NEWCCLOSURE(wrapper)
    end

    local ok,old=
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            wrapper
        )

    if ok and type(old)=="function" then
        oldNamecall=old
        S.OriginalNamecall=old
        S.HookInstalled=true
        return true
    end

    return false
end

local function restoreRemoteHook()
    if S.HookInstalled
    and HOOKMETAMETHOD
    and type(S.OriginalNamecall)=="function"
    then
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            S.OriginalNamecall
        )
    end

    S.HookInstalled=false
end

--==============================================================--
-- LOCAL CHARACTER PICKER / MORPH
--==============================================================--

local function morphModelScore(model)
    local parts=0
    local anim=0
    local motors=0

    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            parts+=1
        elseif inst:IsA("AnimationController")
            or inst:IsA("Animator")
            or inst:IsA("Animation")
        then
            anim+=1
        elseif inst:IsA("Motor6D")
            or inst:IsA("Bone")
        then
            motors+=1
        end
    end

    if parts<1 then
        return -1
    end

    return parts + anim*2 + motors*2
end

local function rebuildMorphModels()
    local found={}
    local seen={}

    local function consider(model,source)
        if not model:IsA("Model") or seen[model] then
            return
        end

        local score=morphModelScore(model)

        if score<1 then
            return
        end

        seen[model]=true

        table.insert(found,{
            model=model,
            name=model.Name,
            path=safePath(model),
            source=source,
            score=score,
        })
    end

    local assetModels=
        ReplicatedStorage:
        FindFirstChild("AssetModels")

    if assetModels then
        for _,inst in ipairs(assetModels:GetDescendants()) do
            if inst:IsA("Model") then
                consider(inst,"AssetModels")
            end
        end
    end

    local cutscene=
        ReplicatedStorage:
        FindFirstChild("CutsceneAssets")

    if cutscene then
        for _,inst in ipairs(cutscene:GetDescendants()) do
            if inst:IsA("Model") then
                local l=lower(inst.Name)
                if string.find(l,"dragon",1,true)
                or string.find(l,"dino",1,true)
                or string.find(l,"prehistoric",1,true)
                or string.find(l,"rex",1,true)
                then
                    consider(inst,"CutsceneAssets")
                end
            end
        end
    end

    table.sort(found,function(a,b)
        if a.source~=b.source then
            return a.source<b.source
        end

        if a.name~=b.name then
            return a.name<b.name
        end

        return a.path<b.path
    end)

    S.Morph.Models=found

    if #found==0 then
        S.Morph.Index=0
    else
        S.Morph.Index=
            math.clamp(
                S.Morph.Index,
                1,
                #found
            )
    end

    if S.UI.CharacterLabel then
        if #found==0 then
            S.UI.CharacterLabel.Text=
                "Nenhum modelo encontrado"
        else
            local item=
                found[S.Morph.Index]

            S.UI.CharacterLabel.Text=
                string.format(
                    "%d/%d • %s",
                    S.Morph.Index,
                    #found,
                    item.name
                )
        end
    end
end

local function currentMorphChoice()
    if S.Morph.Index<1 then
        return nil
    end

    return S.Morph.Models[S.Morph.Index]
end

local function hideRealAvatarForMorph()
    local character=LP.Character

    if not character then
        return
    end

    for _,inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            if not S.Morph.SavedParts[inst] then
                S.Morph.SavedParts[inst]={
                    transparency=inst.Transparency,
                    localTransparency=inst.LocalTransparencyModifier,
                    castShadow=inst.CastShadow,
                }
            end

            inst.Transparency=1
            inst.LocalTransparencyModifier=1
            inst.CastShadow=false

        elseif inst:IsA("Decal")
            or inst:IsA("Texture")
        then
            if S.Morph.SavedTextures[inst]==nil then
                S.Morph.SavedTextures[inst]=inst.Transparency
            end

            inst.Transparency=1

        elseif inst:IsA("ParticleEmitter")
            or inst:IsA("Trail")
            or inst:IsA("Beam")
            or inst:IsA("Smoke")
            or inst:IsA("Fire")
            or inst:IsA("Sparkles")
        then
            if S.Morph.SavedFx[inst]==nil then
                S.Morph.SavedFx[inst]=inst.Enabled
            end

            inst.Enabled=false
        end
    end
end

local function restoreRealAvatarFromMorph()
    for inst,data in pairs(S.Morph.SavedParts) do
        if inst and inst.Parent then
            pcall(function()
                inst.Transparency=data.transparency
                inst.LocalTransparencyModifier=data.localTransparency
                inst.CastShadow=data.castShadow
            end)
        end
    end

    for inst,value in pairs(S.Morph.SavedTextures) do
        if inst and inst.Parent then
            pcall(function()
                inst.Transparency=value
            end)
        end
    end

    for inst,value in pairs(S.Morph.SavedFx) do
        if inst and inst.Parent then
            pcall(function()
                inst.Enabled=value
            end)
        end
    end

    table.clear(S.Morph.SavedParts)
    table.clear(S.Morph.SavedTextures)
    table.clear(S.Morph.SavedFx)
end

local function stopLocalMorph()
    S.Morph.Active=false

    disconnect(S.Morph.RenderConn)
    S.Morph.RenderConn=nil

    if S.Morph.Clone then
        pcall(function()
            S.Morph.Clone:Destroy()
        end)
    end

    S.Morph.Clone=nil
    S.Morph.BottomOffset=0

    restoreRealAvatarFromMorph()

    if S.Running then
        appendRecord({
            recordType="local_morph_stop",
        })
    end

    if S.UI.MorphStatus then
        S.UI.MorphStatus.Text="VISIBILIDADE: LOCAL • inativo"
    end
end

local function prepareLocalMorphClone(model)
    local clone=model:Clone()

    for _,inst in ipairs(clone:GetDescendants()) do
        if inst:IsA("Script")
        or inst:IsA("LocalScript")
        or inst:IsA("ModuleScript")
        or inst:IsA("ProximityPrompt")
        or inst:IsA("ClickDetector")
        then
            pcall(function()
                inst:Destroy()
            end)

        elseif inst:IsA("BasePart") then
            inst.Anchored=true
            inst.CanCollide=false
            inst.CanTouch=false
            inst.CanQuery=false
        end
    end

    return clone
end

local function computeMorphBottom(model)
    local pivot=model:GetPivot()
    local minY=math.huge
    local found=0

    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart")
        and part.Transparency<0.98
        then
            found+=1
            local half=part.Size*0.5

            for _,x in ipairs({-half.X,half.X}) do
                for _,y in ipairs({-half.Y,half.Y}) do
                    for _,z in ipairs({-half.Z,half.Z}) do
                        local wp=
                            part.CFrame:
                            PointToWorldSpace(
                                Vector3.new(x,y,z)
                            )

                        local lp=
                            pivot:
                            PointToObjectSpace(wp)

                        minY=
                            math.min(
                                minY,
                                lp.Y
                            )
                    end
                end
            end
        end
    end

    if found==0 then
        local boxCF,boxSize=
            model:GetBoundingBox()

        local rel=
            pivot:
            ToObjectSpace(boxCF)

        minY=
            rel.Position.Y
            - boxSize.Y*0.5
    end

    return minY
end

local function localMorphGround(root,clone)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={
        LP.Character,
        clone,
    }

    local result=
        Workspace:Raycast(
            root.Position+Vector3.new(0,18,0),
            Vector3.new(0,-100,0),
            params
        )

    return result
        and result.Position.Y
        or (
            root.Position.Y-3
        )
end

local function startLocalMorph()
    local choice=currentMorphChoice()

    if not choice then
        setStatus("Nenhum character disponível")
        return
    end

    stopLocalMorph()

    local character=LP.Character
    local root=
        character
        and character:
        FindFirstChild("HumanoidRootPart")

    if not root then
        setStatus("HumanoidRootPart não encontrado")
        return
    end

    local clone=
        prepareLocalMorphClone(
            choice.model
        )

    clone.Name=
        "Cafeina_LocalMorph_"
        ..choice.name

    clone.Parent=Workspace

    S.Morph.Clone=clone
    S.Morph.BottomOffset=
        computeMorphBottom(clone)

    hideRealAvatarForMorph()

    S.Morph.Active=true

    if S.Running then
        appendRecord({
            recordType="local_morph_start",
            selectedName=choice.name,
            selectedPath=choice.path,
            source=choice.source,
            visibility="LOCAL",
        })
    end

    S.Morph.RenderConn=
        RunService.RenderStepped:
        Connect(function()
            if not S.Morph.Active
            or not S.Morph.Clone
            or not S.Morph.Clone.Parent
            then
                return
            end

            local c=LP.Character
            local r=
                c
                and c:
                FindFirstChild(
                    "HumanoidRootPart"
                )

            if not r then
                return
            end

            hideRealAvatarForMorph()

            local ground=
                localMorphGround(
                    r,
                    S.Morph.Clone
                )

            local look=
                Vector3.new(
                    r.CFrame.LookVector.X,
                    0,
                    r.CFrame.LookVector.Z
                )

            if look.Magnitude<=0.001 then
                look=Vector3.new(0,0,-1)
            else
                look=look.Unit
            end

            local pos=
                Vector3.new(
                    r.Position.X,
                    ground-S.Morph.BottomOffset+0.08,
                    r.Position.Z
                )

            pcall(function()
                S.Morph.Clone:
                PivotTo(
                    CFrame.lookAt(
                        pos,
                        pos+look,
                        Vector3.yAxis
                    )
                )
            end)
        end)

    if S.UI.MorphStatus then
        S.UI.MorphStatus.Text=
            "VISIBILIDADE: LOCAL • "
            ..choice.name
    end

    setStatus(
        "Morph LOCAL ativo • coleta continua rodando"
    )
end

local function selectMorphDelta(delta)
    local count=#S.Morph.Models

    if count==0 then
        rebuildMorphModels()
        count=#S.Morph.Models
    end

    if count==0 then
        return
    end

    S.Morph.Index=
        (
            (S.Morph.Index-1+delta)
            % count
        )+1

    local item=S.Morph.Models[S.Morph.Index]

    if S.UI.CharacterLabel then
        S.UI.CharacterLabel.Text=
            string.format(
                "%d/%d • %s",
                S.Morph.Index,
                count,
                item.name
            )
    end

    if S.Running then
        appendRecord({
            recordType="local_morph_selection_changed",
            name=item.name,
            path=item.path,
            source=item.source,
        })
    end
end

--==============================================================--
-- START / STOP
--==============================================================--

local function startCollection()
    if S.Running then
        return
    end

    S.Running=true
    S.Busy=true

    setStatus("Iniciando coleta focada em morph/pets...")
    updateUI()

    -- Initial snapshot first.
    task.spawn(function()
        scanInitial()
        S.Busy=false

        if S.Running then
            setStatus("Coletando • use pets/equip normalmente no jogo")
        end

        updateUI()
    end)

    -- New objects in major replicated areas.
    connect(
        ReplicatedStorage.DescendantAdded,
        function(inst)
            if not S.Running then return end

            local hit,kw=isInterestingInstance(inst)

            if hit then
                S.Counters.objectAdded+=1
                snapshotInstance(inst,"replicated_added",kw)
                watchValue(inst)
                watchRemoteReceived(inst)
                updateUI()
            end
        end
    )

    connect(
        Workspace.DescendantAdded,
        function(inst)
            if not S.Running then return end

            local path=safePath(inst)
            local hit,kw=isInterestingText(
                inst.Name.." "..path
            )

            if hit
            or string.find(
                lower(path),
                "clientrenderedassets",
                1,
                true
            )
            then
                S.Counters.objectAdded+=1
                snapshotInstance(inst,"workspace_added",kw or "clientrenderedassets")
                watchValue(inst)
                updateUI()
            end
        end
    )

    connect(
        Workspace.DescendantRemoving,
        function(inst)
            if not S.Running then return end

            local path=safePath(inst)

            if string.find(
                lower(path),
                "clientrenderedassets",
                1,
                true
            )
            then
                S.Counters.objectRemoving+=1

                appendRecord({
                    recordType="morph_rendered_asset_removing",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=path,
                    attributes=safeAttrs(inst),
                })

                updateUI()
            end
        end
    )

    -- Character replacement evidence.
    connect(
        LP:GetPropertyChangedSignal("Character"),
        function()
            if not S.Running then return end

            S.Counters.characterChanged+=1

            local character=LP.Character

            appendRecord({
                recordType="morph_character_changed",
                character=
                    character
                    and safePath(character)
                    or nil,
                name=
                    character
                    and character.Name
                    or nil,
                pivot=
                    character
                    and serialize(character:GetPivot())
                    or nil,
            })

            updateUI()
        end
    )

    connect(
        LP.CharacterAdded,
        function(character)
            if not S.Running then return end

            appendRecord({
                recordType="morph_character_added",
                character=safePath(character),
                name=character.Name,
                pivot=serialize(character:GetPivot()),
            })
        end
    )

    installRemoteHook()

    -- Periodic state heartbeat.
    task.spawn(function()
        while S.Running do
            task.wait(CONFIG.HEARTBEAT_SECONDS)

            if not S.Running then
                break
            end

            S.Counters.heartbeat+=1

            local rendered =
                Workspace:
                FindFirstChild("ClientRenderedAssets")

            local assetModels =
                ReplicatedStorage:
                FindFirstChild("AssetModels")

            appendRecord({
                recordType="morph_trace_heartbeat",
                heartbeat=S.Counters.heartbeat,
                renderedAssetsPresent=rendered~=nil,
                renderedChildren=
                    rendered
                    and #rendered:GetChildren()
                    or 0,
                assetModelsPresent=assetModels~=nil,
                assetModelChildren=
                    assetModels
                    and #assetModels:GetChildren()
                    or 0,
                character=
                    LP.Character
                    and safePath(LP.Character)
                    or nil,
            })

            updateUI()
        end
    end)
end

local function stopCollection()
    if not S.Running then
        return
    end

    S.Running=false
    S.Busy=false

    appendRecord({
        recordType="morph_trace_stop",
        counters=serialize(S.Counters),
        archiveBytes=S.ArchiveBytes,
        records=S.RecordCount,
    })

    disconnectAll()

    setStatus("Coleta encerrada • dados preservados")
    updateUI()
end

--==============================================================--
-- UPLOAD
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false,nil,"request/http_request indisponível"
    end

    local lastErr

    for attempt=1,CONFIG.HTTP_RETRIES do
        local ok,response =
            pcall(REQUEST,options)

        if ok and type(response)=="table" then
            local status=
                tonumber(
                    response.StatusCode
                    or response.Status
                    or response.status
                )

            local body=
                response.Body
                or response.body
                or ""

            local success=response.Success

            if success==nil and status then
                success=
                    status>=200
                    and status<300
            end

            if success==true then
                return true,status,body
            end

            lastErr=
                "HTTP "
                ..tostring(status)
                .." "
                ..tostring(body)
        else
            lastErr=tostring(response)
        end

        task.wait(
            CONFIG.HTTP_RETRY_BASE
            * attempt
        )
    end

    return false,nil,lastErr
end

local function postJson(url,data)
    local ok,_,body =
        requestRaw({
            Url=url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
            },
            Body=jsonEncode(data),
        })

    if not ok then
        return false,nil,body
    end

    local decodedOK,decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            body
        )

    if decodedOK and type(decoded)=="table" then
        return true,decoded,nil
    end

    return true,{raw=body},nil
end

local function buildChunks()
    local chunks={}
    local current={}
    local currentBytes=2

    local function flush()
        if #current==0 then
            return
        end

        table.insert(chunks,{
            objects=current,
            bytes=math.max(2,currentBytes-1),
        })

        current={}
        currentBytes=2
    end

    local header={
        recordType="mapping_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        focus="steal_an_egg_morph_pet_replication_trace",
        records=S.RecordCount,
        archiveBytes=S.ArchiveBytes,
        passiveOnly=true,
    }

    local all={header}

    for _,record in ipairs(S.Records) do
        table.insert(all,record)
    end

    for _,object in ipairs(all) do
        local encoded=jsonEncode(object)
        local add=#encoded+1

        if #current>0
        and currentBytes+add
            > CONFIG.CHUNK_TARGET_BYTES
        then
            flush()
        end

        table.insert(current,object)
        currentBytes+=add
    end

    flush()

    return chunks
end

local function uploadAll()
    if S.Upload.Running
    or S.RecordCount<=0
    then
        return
    end

    if S.Running then
        stopCollection()
    end

    if not REQUEST then
        S.Upload.LastError="request indisponível"
        setStatus("Executor sem request/http_request")
        updateUI()
        return
    end

    S.Upload.Running=true
    S.Upload.LastError=nil
    S.Upload.LastURL=""
    S.Upload.BytesSent=0
    S.Upload.CurrentChunk=0

    local chunks=buildChunks()

    S.Upload.TotalChunks=#chunks
    S.Upload.TotalBytes=0

    for _,chunk in ipairs(chunks) do
        S.Upload.TotalBytes+=chunk.bytes
    end

    setStatus("Preparando envio...")
    updateUI()

    local stamp=os.date("!%Y%m%d_%H%M%S")

    local startOK,startData,startErr =
        postJson(
            CONFIG.UPLOAD_BASE.."/start",
            {
                filename=string.format(
                    "Cafeina_MorphTrace_%s_%s.json",
                    tostring(game.PlaceId),
                    stamp
                ),
                source=CONFIG.VERSION,
                metadata={
                    scanner=CONFIG.VERSION,
                    placeId=game.PlaceId,
                    gameId=game.GameId,
                    placeVersion=game.PlaceVersion,
                    focus="morph_pet_replication",
                    records=S.RecordCount,
                    archiveBytes=S.ArchiveBytes,
                    persistent=S.Persistent,
                },
            }
        )

    if not startOK then
        S.Upload.Running=false
        S.Upload.LastError=startErr
        setStatus("/upload/start falhou • dados preservados")
        updateUI()
        return
    end

    S.Upload.UploadId=
        startData.uploadId
        or startData.id
        or startData.upload_id

    if not S.Upload.UploadId then
        S.Upload.Running=false
        S.Upload.LastError="uploadId ausente"
        setStatus("Servidor não retornou uploadId")
        updateUI()
        return
    end

    for index,chunk in ipairs(chunks) do
        S.Upload.CurrentChunk=index
        updateUI()

        local ok,_,err =
            postJson(
                CONFIG.UPLOAD_BASE.."/chunk",
                {
                    uploadId=S.Upload.UploadId,
                    index=index,
                    objects=chunk.objects,
                }
            )

        if not ok then
            S.Upload.Running=false
            S.Upload.LastError=err
            setStatus("Falha no chunk "..tostring(index).." • dados preservados")
            updateUI()
            return
        end

        S.Upload.BytesSent+=chunk.bytes
        updateUI()
        task.wait()
    end

    local finishOK,finishData,finishErr =
        postJson(
            CONFIG.UPLOAD_BASE.."/finish",
            {
                uploadId=S.Upload.UploadId,
                totalChunks=#chunks,
                totalBytes=S.Upload.TotalBytes,
                records=S.RecordCount,
            }
        )

    if not finishOK then
        S.Upload.Running=false
        S.Upload.LastError=finishErr
        setStatus("/upload/finish falhou • dados preservados")
        updateUI()
        return
    end

    local confirmed=
        finishData.confirmed==true
        or finishData.success==true
        or finishData.ok==true

    if not confirmed then
        S.Upload.Running=false
        S.Upload.LastError="sem confirmação"
        setStatus("Servidor não confirmou • dados preservados")
        updateUI()
        return
    end

    S.Upload.LastURL=tostring(
        finishData.url
        or finishData.link
        or finishData.fileUrl
        or ""
    )

    S.Upload.Running=false
    S.Upload.BytesSent=S.Upload.TotalBytes

    clearArchive()

    setStatus("Upload confirmado ✓ • archive limpo")
    updateUI()
end

--==============================================================--
-- UI
--==============================================================--

local COLORS={
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    RED=Color3.fromRGB(155,45,51),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
}

local guiParent=CoreGui

if type(gethui)=="function" then
    local ok,value=pcall(gethui)

    if ok and value then
        guiParent=value
    end
end

pcall(function()
    local old=
        guiParent:
        FindFirstChild(
            CONFIG.GUI_NAME
        )

    if old then
        old:Destroy()
    end
end)

local Gui=Instance.new("ScreenGui")
Gui.Name=CONFIG.GUI_NAME
Gui.ResetOnSpawn=false

if not pcall(function()
    Gui.Parent=guiParent
end)
then
    Gui.Parent=
        LP:WaitForChild("PlayerGui")
end

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(322,458)
Main.AnchorPoint=Vector2.new(0.5,0.5)
Main.Position=UDim2.fromScale(0.5,0.44)
Main.BackgroundColor3=COLORS.BG
Main.BorderSizePixel=0
Main.Parent=Gui

local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,10)
corner.Parent=Main

local stroke=Instance.new("UIStroke")
stroke.Color=COLORS.STROKE
stroke.Thickness=1
stroke.Parent=Main

local Title=Instance.new("TextLabel")
Title.BackgroundTransparency=1
Title.Position=UDim2.fromOffset(10,8)
Title.Size=UDim2.new(1,-20,0,24)
Title.Font=Enum.Font.GothamBold
Title.Text="CAFEÍNA • MORPH TRACE V1"
Title.TextColor3=COLORS.TEXT
Title.TextSize=13
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Parent=Main

local Subtitle=Instance.new("TextLabel")
Subtitle.BackgroundTransparency=1
Subtitle.Position=UDim2.fromOffset(10,31)
Subtitle.Size=UDim2.new(1,-20,0,28)
Subtitle.Font=Enum.Font.Gotham
Subtitle.Text="PET RENDERER • LOADPET • EQUIP • CHARACTER"
Subtitle.TextColor3=COLORS.MUTED
Subtitle.TextSize=8
Subtitle.TextXAlignment=Enum.TextXAlignment.Left
Subtitle.Parent=Main

local Collect=Instance.new("TextButton")
Collect.Position=UDim2.fromOffset(10,64)
Collect.Size=UDim2.new(1,-20,0,44)
Collect.BackgroundColor3=COLORS.BUTTON
Collect.BorderSizePixel=0
Collect.Font=Enum.Font.GothamBold
Collect.Text="INICIAR COLETA"
Collect.TextColor3=COLORS.TEXT
Collect.TextSize=11
Collect.AutoButtonColor=false
Collect.Parent=Main
S.UI.CollectButton=Collect

local cc=Instance.new("UICorner")
cc.CornerRadius=UDim.new(0,8)
cc.Parent=Collect

local CharacterHeader=Instance.new("TextLabel")
CharacterHeader.BackgroundTransparency=1
CharacterHeader.Position=UDim2.fromOffset(10,115)
CharacterHeader.Size=UDim2.new(1,-20,0,18)
CharacterHeader.Font=Enum.Font.GothamBold
CharacterHeader.Text="PERSONAGEM LOCAL"
CharacterHeader.TextColor3=COLORS.TEXT
CharacterHeader.TextSize=9
CharacterHeader.TextXAlignment=Enum.TextXAlignment.Left
CharacterHeader.Parent=Main

local Prev=Instance.new("TextButton")
Prev.Position=UDim2.fromOffset(10,137)
Prev.Size=UDim2.fromOffset(38,36)
Prev.BackgroundColor3=COLORS.BUTTON
Prev.BorderSizePixel=0
Prev.Font=Enum.Font.GothamBold
Prev.Text="<"
Prev.TextColor3=COLORS.TEXT
Prev.TextSize=14
Prev.Parent=Main

local pc=Instance.new("UICorner")
pc.CornerRadius=UDim.new(0,8)
pc.Parent=Prev

local CharacterLabel=Instance.new("TextLabel")
CharacterLabel.Position=UDim2.fromOffset(53,137)
CharacterLabel.Size=UDim2.new(1,-106,0,36)
CharacterLabel.BackgroundColor3=Color3.fromRGB(20,20,24)
CharacterLabel.BorderSizePixel=0
CharacterLabel.Font=Enum.Font.Gotham
CharacterLabel.Text="Buscando modelos..."
CharacterLabel.TextColor3=COLORS.TEXT
CharacterLabel.TextSize=9
CharacterLabel.TextWrapped=true
CharacterLabel.Parent=Main
S.UI.CharacterLabel=CharacterLabel

local clc=Instance.new("UICorner")
clc.CornerRadius=UDim.new(0,8)
clc.Parent=CharacterLabel

local Next=Instance.new("TextButton")
Next.Position=UDim2.new(1,-48,0,137)
Next.Size=UDim2.fromOffset(38,36)
Next.BackgroundColor3=COLORS.BUTTON
Next.BorderSizePixel=0
Next.Font=Enum.Font.GothamBold
Next.Text=">"
Next.TextColor3=COLORS.TEXT
Next.TextSize=14
Next.Parent=Main

local nc=Instance.new("UICorner")
nc.CornerRadius=UDim.new(0,8)
nc.Parent=Next

local Morph=Instance.new("TextButton")
Morph.Position=UDim2.fromOffset(10,180)
Morph.Size=UDim2.new(0.5,-15,0,38)
Morph.BackgroundColor3=COLORS.BUTTON
Morph.BorderSizePixel=0
Morph.Font=Enum.Font.GothamBold
Morph.Text="VIRAR LOCAL"
Morph.TextColor3=COLORS.TEXT
Morph.TextSize=9
Morph.Parent=Main

local mc=Instance.new("UICorner")
mc.CornerRadius=UDim.new(0,8)
mc.Parent=Morph

local Normal=Instance.new("TextButton")
Normal.Position=UDim2.new(0.5,5,0,180)
Normal.Size=UDim2.new(0.5,-15,0,38)
Normal.BackgroundColor3=COLORS.BUTTON
Normal.BorderSizePixel=0
Normal.Font=Enum.Font.GothamBold
Normal.Text="VOLTAR NORMAL"
Normal.TextColor3=COLORS.TEXT
Normal.TextSize=9
Normal.Parent=Main

local nmc=Instance.new("UICorner")
nmc.CornerRadius=UDim.new(0,8)
nmc.Parent=Normal

local MorphStatus=Instance.new("TextLabel")
MorphStatus.BackgroundTransparency=1
MorphStatus.Position=UDim2.fromOffset(10,222)
MorphStatus.Size=UDim2.new(1,-20,0,22)
MorphStatus.Font=Enum.Font.Gotham
MorphStatus.Text="VISIBILIDADE: LOCAL • inativo"
MorphStatus.TextColor3=COLORS.MUTED
MorphStatus.TextSize=8
MorphStatus.TextXAlignment=Enum.TextXAlignment.Left
MorphStatus.Parent=Main
S.UI.MorphStatus=MorphStatus

Prev.Activated:Connect(function()
    selectMorphDelta(-1)
end)

Next.Activated:Connect(function()
    selectMorphDelta(1)
end)

Morph.Activated:Connect(function()
    startLocalMorph()
end)

Normal.Activated:Connect(function()
    stopLocalMorph()
    setStatus("Morph local desligado • coleta pode continuar")
end)

local Send=Instance.new("TextButton")
Send.Position=UDim2.fromOffset(10,253)
Send.Size=UDim2.new(1,-20,0,42)
Send.BackgroundColor3=COLORS.BUTTON
Send.BorderSizePixel=0
Send.Font=Enum.Font.GothamBold
Send.Text="SEM DADOS"
Send.TextColor3=COLORS.TEXT
Send.TextSize=10
Send.AutoButtonColor=false
Send.Parent=Main
S.UI.SendButton=Send

local sc=Instance.new("UICorner")
sc.CornerRadius=UDim.new(0,8)
sc.Parent=Send

local Status=Instance.new("TextLabel")
Status.BackgroundTransparency=1
Status.Position=UDim2.fromOffset(10,303)
Status.Size=UDim2.new(1,-20,0,34)
Status.Font=Enum.Font.Gotham
Status.Text="Pronto • coleta passiva focada em morph"
Status.TextColor3=COLORS.TEXT
Status.TextSize=9
Status.TextWrapped=true
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Parent=Main
S.UI.Status=Status

local DataLabel=Instance.new("TextLabel")
DataLabel.BackgroundTransparency=1
DataLabel.Position=UDim2.fromOffset(10,343)
DataLabel.Size=UDim2.new(1,-20,0,18)
DataLabel.Font=Enum.Font.Gotham
DataLabel.Text="Arquivado: 0.00 MB • 0 registros"
DataLabel.TextColor3=COLORS.MUTED
DataLabel.TextSize=8
DataLabel.TextXAlignment=Enum.TextXAlignment.Left
DataLabel.Parent=Main
S.UI.DataLabel=DataLabel

local CountLabel=Instance.new("TextLabel")
CountLabel.BackgroundTransparency=1
CountLabel.Position=UDim2.fromOffset(10,363)
CountLabel.Size=UDim2.new(1,-20,0,18)
CountLabel.Font=Enum.Font.Gotham
CountLabel.Text="Criados 0 • Remotes ↑0 ↓0 • Values 0"
CountLabel.TextColor3=COLORS.MUTED
CountLabel.TextSize=8
CountLabel.TextXAlignment=Enum.TextXAlignment.Left
CountLabel.Parent=Main
S.UI.CountLabel=CountLabel

local UploadLabel=Instance.new("TextLabel")
UploadLabel.BackgroundTransparency=1
UploadLabel.Position=UDim2.fromOffset(10,384)
UploadLabel.Size=UDim2.new(1,-20,0,18)
UploadLabel.Font=Enum.Font.Gotham
UploadLabel.Text="Enviado: 0.00 MB"
UploadLabel.TextColor3=COLORS.MUTED
UploadLabel.TextSize=8
UploadLabel.TextXAlignment=Enum.TextXAlignment.Left
UploadLabel.Parent=Main
S.UI.UploadLabel=UploadLabel

local Bar=Instance.new("Frame")
Bar.Position=UDim2.fromOffset(10,412)
Bar.Size=UDim2.new(1,-20,0,12)
Bar.BackgroundColor3=Color3.fromRGB(25,25,30)
Bar.BorderSizePixel=0
Bar.ClipsDescendants=true
Bar.Parent=Main

local bc=Instance.new("UICorner")
bc.CornerRadius=UDim.new(1,0)
bc.Parent=Bar

local Fill=Instance.new("Frame")
Fill.Size=UDim2.new(0,0,1,0)
Fill.BackgroundColor3=Color3.fromRGB(24,190,72)
Fill.BorderSizePixel=0
Fill.Parent=Bar
S.UI.BarFill=Fill

local fc=Instance.new("UICorner")
fc.CornerRadius=UDim.new(1,0)
fc.Parent=Fill

-- Mobile drag.
do
    local dragging=false
    local dragInput
    local dragStart
    local startPos

    Main.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch
        then
            dragging=true
            dragStart=input.Position
            startPos=Main.Position

            input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then
                    dragging=false
                end
            end)
        end
    end)

    Main.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement
        or input.UserInputType==Enum.UserInputType.Touch
        then
            dragInput=input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input==dragInput then
            local delta=input.Position-dragStart

            Main.Position=
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset+delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset+delta.Y
                )
        end
    end)
end

Collect.Activated:Connect(function()
    if S.Upload.Running then
        return
    end

    if S.Running then
        stopCollection()
    else
        startCollection()
    end

    updateUI()
end)

Send.Activated:Connect(function()
    if S.Upload.Running
    or S.RecordCount<=0
    then
        return
    end

    task.spawn(uploadAll)
end)

--==============================================================--
-- STARTUP
--==============================================================--

loadArchive()
rebuildMorphModels()

if S.RecordCount>0 then
    setStatus("Dados anteriores recuperados • prontos para enviar")
end

updateUI()

env.__CAFEINA_MORPH_TRACE_V1={
    Start=startCollection,
    Stop=stopCollection,
    Upload=uploadAll,

    GetState=function()
        return {
            running=S.Running,
            records=S.RecordCount,
            bytes=S.ArchiveBytes,
            counters=S.Counters,
            upload=S.Upload,
        }
    end,

    Destroy=function()
        stopLocalMorph()
        stopCollection()
        restoreRemoteHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] MORPH TRACE V2.0 + CHARACTER PICKER carregado.")
