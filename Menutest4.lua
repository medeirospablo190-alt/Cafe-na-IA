--==============================================================--
-- CAFEÍNA • NATIVE MORPH MENU + TRACE V5.0
-- ROBLOX EXECUTOR • MOBILE-FIRST
--
-- OBJETIVO
-- 1) Mostrar MorphConfigs reais do jogo.
-- 2) Consultar GetMorphUnlocks / GetMorphdex.
-- 3) Só solicitar IDs confirmados/desbloqueados.
-- 4) Observar RequestMorph legítimo do próprio jogo.
-- 5) Capturar:
--      2s antes
--      RequestMorph
--      MorphApplied / RevealCharacter
--      Character / rig / bones / welds / animações
--      5s depois
-- 6) Observar outros jogadores para comparar replicação.
-- 7) Archive persistente + upload com barra/MB.
--
-- NÃO:
-- • faz brute force;
-- • tenta burlar unlocks;
-- • dispara IDs derivados não confirmados;
-- • dispara remotes desconhecidos.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera

local CONFIG = {
    VERSION = "NATIVE_MORPH_MENU_TRACE_V5_0",
    GUI_NAME = "CafeinaNativeMorphMenuTraceV50",

    PRE_WINDOW_SECONDS = 2.0,
    POST_WINDOW_SECONDS = 5.0,
    SAMPLE_INTERVAL = 0.10,
    FULL_SNAPSHOT_INTERVAL = 0.50,

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    CHUNK_TARGET_BYTES = 450000,
    MAX_ARCHIVE_BYTES = 120 * 1024 * 1024,

    ARCHIVE_ROOT = "CafeinaNativeMorphV5",
    ARCHIVE_FOLDER = "CafeinaNativeMorphV5/" .. tostring(game.PlaceId),
    ARCHIVE_FILE = "CafeinaNativeMorphV5/" .. tostring(game.PlaceId) .. "/trace.jsonl",

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.0,

    TARGET_EVENTS = {
        "RequestMorph",
        "MorphApplied",
        "RevealCharacter",
        "MorphUnlocksReady",
        "MorphdexUpdated",
        "MorphPurchased",
        "EquipVariant",
        "UnequipVariant",
        "EquipSkin",
        "UnequipSkin",
    },

    TARGET_FUNCTIONS = {
        "GetMorphUnlocks",
        "GetMorphdex",
    },

    REPLICATION_NAMES = {
        RootPart=true,
        HRP_to_RootPart=true,
        MorphRoot=true,
        MorphModel=true,
    },

    ATTRIBUTE_KEYWORDS = {
        "morph",
        "skin",
        "variant",
        "species",
        "character",
        "creature",
        "animal",
        "form",
    },

    -- IDs already observed in legitimate game calls from supplied traces.
    OBSERVED_VALID_IDS = {
        jerboa=true,
        ant=true,
        poisondartfrog=true,
    },
}

--==============================================================--
-- EXECUTOR CAPABILITIES
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_NATIVE_MORPH_V5")
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

local HTTP_TABLE_REQUEST
pcall(function()
    if http and type(http.request)=="function" then
        HTTP_TABLE_REQUEST=http.request
    end
end)

local REQUEST = pick(
    rawget(env,"request"),
    rawget(env,"http_request"),
    SYN_REQUEST,
    HTTP_TABLE_REQUEST
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
    CharacterConnections={},
    OtherPlayerConnections={},

    Records={},
    RecordCount=0,
    ArchiveBytes=0,
    Persistent=false,

    PreBuffer={},
    PreBufferMax=math.max(
        10,
        math.ceil(CONFIG.PRE_WINDOW_SECONDS / CONFIG.SAMPLE_INTERVAL) + 5
    ),

    ActiveWindow=nil,
    WindowCounter=0,

    Morphs={},
    FilteredMorphs={},
    SelectedMorph=nil,

    UnlocksReady=false,
    UnlockRaw=nil,
    MorphdexRaw=nil,

    UnlockedIds={},
    ConfirmedIds={},
    ObservedRequestIds={},

    TargetRemotes={},
    IncomingAttached=setmetatable({}, {__mode="k"}),

    HookInstalled=false,
    OriginalNamecall=nil,

    Counters={
        morphConfigs=0,
        unlocked=0,
        confirmed=0,

        requestObserved=0,
        requestMenu=0,

        morphApplied=0,
        revealCharacter=0,
        remoteReceived=0,

        characterChanged=0,
        localObjectAdded=0,
        localObjectRemoved=0,
        otherMorphEvents=0,

        windows=0,
        snapshots=0,
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

    UI={},
}

for id,_ in pairs(CONFIG.OBSERVED_VALID_IDS) do
    S.ConfirmedIds[id]=true
end

--==============================================================--
-- GENERIC HELPERS
--==============================================================--

local function disconnect(c)
    if c then
        pcall(function()
            c:Disconnect()
        end)
    end
end

local function connect(signal,fn,bucket)
    local c=signal:Connect(fn)
    table.insert(bucket or S.Connections,c)
    return c
end

local function disconnectBucket(bucket)
    for _,c in ipairs(bucket) do
        disconnect(c)
    end
    table.clear(bucket)
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function normalizeId(v)
    local s=lower(v)
    s=string.gsub(s,"%s+","")
    s=string.gsub(s,"[_%-]","")
    return s
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
    local count=0

    for k,v in pairs(attrs) do
        count+=1
        if count>120 then
            out.__truncated=true
            break
        end

        local tv=typeof(v)

        if tv=="string"
        or tv=="number"
        or tv=="boolean"
        then
            out[tostring(k)]=v
        else
            out[tostring(k)]=tostring(v)
        end
    end

    return out
end

local function serialize(v,depth,seen)
    depth=depth or 0
    seen=seen or {}

    if depth>5 then
        return "<max_depth>"
    end

    local tv=typeof(v)

    if v==nil
    or tv=="string"
    or tv=="number"
    or tv=="boolean"
    then
        return v
    end

    if tv=="Instance" then
        return {
            type="Instance",
            className=v.ClassName,
            name=v.Name,
            path=safePath(v),
            attributes=safeAttrs(v),
        }
    end

    if tv=="Vector3" then
        return {
            type="Vector3",
            x=v.X,y=v.Y,z=v.Z,
        }
    end

    if tv=="Vector2" then
        return {
            type="Vector2",
            x=v.X,y=v.Y,
        }
    end

    if tv=="CFrame" then
        local p=v.Position
        return {
            type="CFrame",
            x=p.X,y=p.Y,z=p.Z,
        }
    end

    if tv=="Color3" then
        return {
            type="Color3",
            r=v.R,g=v.G,b=v.B,
        }
    end

    if tv=="table" then
        if seen[v] then
            return "<cycle>"
        end

        seen[v]=true

        local out={}
        local count=0

        for k,val in pairs(v) do
            count+=1
            if count>160 then
                out.__truncated=true
                break
            end

            out[tostring(k)] =
                serialize(
                    val,
                    depth+1,
                    seen
                )
        end

        seen[v]=nil
        return out
    end

    return tostring(v)
end

local function encode(v)
    local ok,result=
        pcall(
            HttpService.JSONEncode,
            HttpService,
            v
        )

    return ok and result or "{}"
end

local function mb(bytes)
    return (tonumber(bytes) or 0)/(1024*1024)
end

local function hasKeyword(text)
    local l=lower(text)

    for _,kw in ipairs(CONFIG.ATTRIBUTE_KEYWORDS) do
        if string.find(l,kw,1,true) then
            return true,kw
        end
    end

    return false,nil
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

    record._version=CONFIG.VERSION
    record._placeId=game.PlaceId
    record._gameId=game.GameId
    record._placeVersion=game.PlaceVersion
    record._unix=os.time()
    record._clock=os.clock()

    local line=encode(record)
    local bytes=#line+1

    if S.ArchiveBytes+bytes
        > CONFIG.MAX_ARCHIVE_BYTES
    then
        return false
    end

    table.insert(S.Records,record)
    S.RecordCount+=1
    S.ArchiveBytes+=bytes

    if S.Persistent then
        local full=line.."\n"
        local wrote=false

        if APPENDFILE then
            wrote=
                pcall(
                    APPENDFILE,
                    CONFIG.ARCHIVE_FILE,
                    full
                )
        end

        if not wrote then
            local old=""

            if ISFILE(CONFIG.ARCHIVE_FILE) then
                pcall(function()
                    old=
                        READFILE(CONFIG.ARCHIVE_FILE)
                        or ""
                end)
            end

            pcall(
                WRITEFILE,
                CONFIG.ARCHIVE_FILE,
                old..full
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
        local ok,content=
            pcall(
                READFILE,
                CONFIG.ARCHIVE_FILE
            )

        if ok and type(content)=="string" then
            for line in string.gmatch(content,"[^\r\n]+") do
                local decodeOK,obj=
                    pcall(
                        HttpService.JSONDecode,
                        HttpService,
                        line
                    )

                if decodeOK
                and type(obj)=="table"
                then
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
-- CHARACTER / RIG DESCRIPTION
--==============================================================--

local function describeTracks(animator)
    if not animator then
        return {}
    end

    local ok,tracks=
        pcall(function()
            return animator:
                GetPlayingAnimationTracks()
        end)

    if not ok or type(tracks)~="table" then
        return {}
    end

    local out={}

    for i,track in ipairs(tracks) do
        if i>40 then break end

        table.insert(out,{
            name=track.Name,
            animationId=
                track.Animation
                and track.Animation.AnimationId
                or nil,
            timePosition=track.TimePosition,
            speed=track.Speed,
            weight=track.WeightCurrent,
            priority=tostring(track.Priority),
        })
    end

    return out
end

local function describeCharacter(character,full)
    if not character then
        return nil
    end

    local hum=
        character:
        FindFirstChildOfClass("Humanoid")

    local animator=
        character:
        FindFirstChildWhichIsA(
            "Animator",
            true
        )

    local animationController=
        character:
        FindFirstChildWhichIsA(
            "AnimationController",
            true
        )

    local hrp=
        character:
        FindFirstChild("HumanoidRootPart")

    local rootPart=
        character:
        FindFirstChild("RootPart")

    local hrpWeld=
        hrp
        and hrp:
            FindFirstChild("HRP_to_RootPart")
        or nil

    local out={
        name=character.Name,
        path=safePath(character),
        parent=
            character.Parent
            and safePath(character.Parent)
            or nil,

        attributes=safeAttrs(character),
        pivot=serialize(character:GetPivot()),

        humanoid=hum and {
            path=safePath(hum),
            health=hum.Health,
            maxHealth=hum.MaxHealth,
            walkSpeed=hum.WalkSpeed,
            jumpPower=hum.JumpPower,
            hipHeight=hum.HipHeight,
            rigType=tostring(hum.RigType),
            attributes=safeAttrs(hum),
        } or nil,

        humanoidRootPart=hrp and {
            path=safePath(hrp),
            position=serialize(hrp.Position),
            size=serialize(hrp.Size),
            attributes=safeAttrs(hrp),
        } or nil,

        rootPart=rootPart and {
            path=safePath(rootPart),
            position=serialize(rootPart.Position),
            size=serialize(rootPart.Size),
            attributes=safeAttrs(rootPart),
        } or nil,

        hrpToRootPart=hrpWeld and {
            className=hrpWeld.ClassName,
            path=safePath(hrpWeld),
            part0=
                hrpWeld.Part0
                and safePath(hrpWeld.Part0)
                or nil,
            part1=
                hrpWeld.Part1
                and safePath(hrpWeld.Part1)
                or nil,
        } or nil,

        animator=
            animator
            and safePath(animator)
            or nil,

        animationController=
            animationController
            and safePath(animationController)
            or nil,

        playingTracks=
            describeTracks(animator),
    }

    if not full then
        return out
    end

    local descendants=
        character:GetDescendants()

    local classCounts={}
    local important={}

    for _,inst in ipairs(descendants) do
        classCounts[inst.ClassName]=
            (classCounts[inst.ClassName] or 0)+1

        if inst:IsA("Motor6D") then
            table.insert(important,{
                className="Motor6D",
                name=inst.Name,
                path=safePath(inst),
                part0=
                    inst.Part0
                    and safePath(inst.Part0)
                    or nil,
                part1=
                    inst.Part1
                    and safePath(inst.Part1)
                    or nil,
                c0=tostring(inst.C0),
                c1=tostring(inst.C1),
            })

        elseif inst:IsA("WeldConstraint")
            or inst:IsA("Weld")
        then
            table.insert(important,{
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
                part0=
                    inst.Part0
                    and safePath(inst.Part0)
                    or nil,
                part1=
                    inst.Part1
                    and safePath(inst.Part1)
                    or nil,
            })

        elseif inst:IsA("Bone") then
            table.insert(important,{
                className="Bone",
                name=inst.Name,
                path=safePath(inst),
                transform=tostring(inst.Transform),
            })

        elseif inst:IsA("MeshPart") then
            table.insert(important,{
                className="MeshPart",
                name=inst.Name,
                path=safePath(inst),
                meshId=inst.MeshId,
                textureId=inst.TextureID,
                size=serialize(inst.Size),
            })

        elseif inst:IsA("Animation") then
            table.insert(important,{
                className="Animation",
                name=inst.Name,
                path=safePath(inst),
                animationId=inst.AnimationId,
            })

        elseif inst:IsA("HumanoidDescription") then
            table.insert(important,{
                className="HumanoidDescription",
                name=inst.Name,
                path=safePath(inst),
                attributes=safeAttrs(inst),
            })
        end
    end

    out.descendantCount=#descendants
    out.classCounts=classCounts
    out.important=important

    return out
end

local function describeOtherMorphCharacters()
    local out={}

    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LP
        and player.Character
        then
            local character=player.Character
            local rootPart=
                character:
                FindFirstChild("RootPart")

            local hrp=
                character:
                FindFirstChild("HumanoidRootPart")

            local weld=
                hrp
                and hrp:
                    FindFirstChild("HRP_to_RootPart")
                or nil

            local bone=
                character:
                FindFirstChildWhichIsA(
                    "Bone",
                    true
                )

            if rootPart or weld or bone then
                table.insert(out,{
                    player=player.Name,
                    userId=player.UserId,
                    hasRootPart=rootPart~=nil,
                    hasHRPToRootPart=weld~=nil,
                    hasBone=bone~=nil,
                    character=
                        describeCharacter(
                            character,
                            false
                        ),
                })
            end
        end
    end

    return out
end

local function currentState(label,full)
    Camera=Workspace.CurrentCamera

    return {
        label=label,

        localCharacter=
            describeCharacter(
                LP.Character,
                full
            ),

        camera={
            subject=
                Camera.CameraSubject
                and safePath(Camera.CameraSubject)
                or nil,
            type=tostring(Camera.CameraType),
            cframe=serialize(Camera.CFrame),
        },

        otherMorphCharacters=
            describeOtherMorphCharacters(),
    }
end

--==============================================================--
-- PRE BUFFER / INTENSIVE CAPTURE WINDOW
--==============================================================--

local function pushPreSample()
    table.insert(
        S.PreBuffer,
        {
            t=os.clock(),
            state=currentState(
                "pre_buffer",
                false
            ),
        }
    )

    while #S.PreBuffer>S.PreBufferMax do
        table.remove(S.PreBuffer,1)
    end
end

local function flushPreBuffer(windowId,trigger)
    for _,sample in ipairs(S.PreBuffer) do
        appendRecord({
            recordType="morph_pre_window_sample",
            windowId=windowId,
            trigger=trigger,
            sampleClock=sample.t,
            state=sample.state,
        })
    end
end

local function captureWindowSample(
    windowId,
    trigger,
    relative,
    full
)
    S.Counters.snapshots+=1

    appendRecord({
        recordType="morph_window_sample",
        windowId=windowId,
        trigger=trigger,
        relative=relative,
        full=full==true,
        state=currentState(
            "capture_window",
            full==true
        ),
    })
end

local function startCaptureWindow(trigger,triggerData)
    local now=os.clock()

    if S.ActiveWindow
    and now<S.ActiveWindow.endsAt
    then
        appendRecord({
            recordType="morph_window_trigger_merged",
            windowId=S.ActiveWindow.id,
            trigger=trigger,
            triggerData=triggerData,
        })

        S.ActiveWindow.endsAt=
            math.max(
                S.ActiveWindow.endsAt,
                now+CONFIG.POST_WINDOW_SECONDS
            )

        return S.ActiveWindow.id
    end

    S.WindowCounter+=1

    local id=
        "morph_"
        ..tostring(S.WindowCounter)
        .."_"
        ..tostring(now)

    S.ActiveWindow={
        id=id,
        trigger=trigger,
        startedAt=now,
        endsAt=now+CONFIG.POST_WINDOW_SECONDS,
    }

    S.Counters.windows+=1

    appendRecord({
        recordType="morph_window_start",
        windowId=id,
        trigger=trigger,
        triggerData=triggerData,
        characterBefore=
            describeCharacter(
                LP.Character,
                true
            ),
    })

    flushPreBuffer(id,trigger)
    captureWindowSample(id,trigger,0,true)

    task.spawn(function()
        local start=os.clock()
        local nextFull=
            CONFIG.FULL_SNAPSHOT_INTERVAL

        while S.Running
        and S.ActiveWindow
        and S.ActiveWindow.id==id
        and os.clock()<=S.ActiveWindow.endsAt
        do
            local relative=
                os.clock()-start

            local full=false

            if relative>=nextFull then
                full=true
                nextFull+=
                    CONFIG.FULL_SNAPSHOT_INTERVAL
            end

            captureWindowSample(
                id,
                trigger,
                relative,
                full
            )

            task.wait(
                CONFIG.SAMPLE_INTERVAL
            )
        end

        if S.ActiveWindow
        and S.ActiveWindow.id==id
        then
            appendRecord({
                recordType="morph_window_end",
                windowId=id,
                trigger=trigger,
                duration=os.clock()-start,
                characterAfter=
                    describeCharacter(
                        LP.Character,
                        true
                    ),
            })

            S.ActiveWindow=nil
        end
    end)

    return id
end

--==============================================================--
-- MORPH CONFIG DISCOVERY
--==============================================================--

local function rebuildConfirmedCount()
    local n=0

    for _,m in ipairs(S.Morphs) do
        if m.confirmed then
            n+=1
        end
    end

    S.Counters.confirmed=n
end

local function rebuildUnlockCount()
    local n=0

    for _,m in ipairs(S.Morphs) do
        if m.unlocked then
            n+=1
        end
    end

    S.Counters.unlocked=n
end

local function resolveMorphStates()
    for _,m in ipairs(S.Morphs) do
        local normalized=
            normalizeId(m.idCandidate)

        m.confirmed=
            S.ConfirmedIds[normalized]==true

        m.unlocked=
            S.UnlockedIds[normalized]==true

        if m.unlocked then
            m.confirmed=true
        end

        if m.explicitId then
            m.confirmed=true
        end
    end

    rebuildConfirmedCount()
    rebuildUnlockCount()
end

local function discoverMorphConfigs()
    local folder=
        ReplicatedStorage:
        FindFirstChild("MorphConfigs")

    local list={}

    if folder then
        for _,module in ipairs(folder:GetChildren()) do
            if module:IsA("ModuleScript") then
                local attrs=safeAttrs(module)

                local explicit=
                    attrs.MorphId
                    or attrs.MorphID
                    or attrs.Id
                    or attrs.ID
                    or attrs.Key
                    or attrs.Morph

                local explicitId=
                    type(explicit)=="string"
                    and explicit~=""

                local candidate=
                    explicitId
                    and tostring(explicit)
                    or normalizeId(module.Name)

                table.insert(list,{
                    module=module,
                    name=module.Name,
                    path=safePath(module),
                    attributes=attrs,

                    idCandidate=candidate,
                    explicitId=explicitId,

                    confirmed=false,
                    unlocked=false,
                })
            end
        end
    end

    table.sort(list,function(a,b)
        return lower(a.name)<lower(b.name)
    end)

    S.Morphs=list
    S.Counters.morphConfigs=#list

    resolveMorphStates()

    appendRecord({
        recordType="morph_config_catalog",
        count=#list,
        morphs=serialize(list),
    })
end

--==============================================================--
-- UNLOCK PARSING
--==============================================================--

local function buildKnownNormMap()
    local map={}

    for _,m in ipairs(S.Morphs) do
        map[normalizeId(m.name)]=m
        map[normalizeId(m.idCandidate)]=m
    end

    return map
end

local function markUnlocked(rawId)
    if type(rawId)~="string" then
        return
    end

    local n=normalizeId(rawId)

    if n=="" then
        return
    end

    S.UnlockedIds[n]=true
    S.ConfirmedIds[n]=true
end

local function parseUnlockTable(value)
    local known=buildKnownNormMap()
    local visited={}

    local function visit(v,depth)
        if depth>7 then
            return
        end

        local tv=type(v)

        if tv=="string" then
            local n=normalizeId(v)

            if known[n] then
                markUnlocked(v)
            end

            return
        end

        if tv~="table" then
            return
        end

        if visited[v] then
            return
        end

        visited[v]=true

        for k,val in pairs(v) do
            if type(k)=="string" then
                local kn=normalizeId(k)

                if known[kn]
                and (
                    val==true
                    or type(val)=="string"
                    or type(val)=="table"
                    or type(val)=="number"
                )
                then
                    -- Conservative:
                    -- false is never treated as unlocked.
                    if val~=false and val~=0 then
                        markUnlocked(k)
                    end
                end
            end

            visit(val,depth+1)
        end
    end

    visit(value,0)

    resolveMorphStates()
end

--==============================================================--
-- REMOTE DISCOVERY
--==============================================================--

local function findRemote(name)
    local events=
        ReplicatedStorage:
        FindFirstChild("Events")

    if events then
        local direct=
            events:
            FindFirstChild(name,true)

        if direct then
            return direct
        end
    end

    return
        ReplicatedStorage:
        FindFirstChild(name,true)
end

local function discoverRemotes()
    table.clear(S.TargetRemotes)

    for _,name in ipairs(CONFIG.TARGET_EVENTS) do
        local remote=findRemote(name)

        if remote then
            S.TargetRemotes[name]=remote

            appendRecord({
                recordType="morph_remote_discovered",
                name=name,
                className=remote.ClassName,
                path=safePath(remote),
            })
        end
    end

    for _,name in ipairs(CONFIG.TARGET_FUNCTIONS) do
        local remote=findRemote(name)

        if remote then
            S.TargetRemotes[name]=remote

            appendRecord({
                recordType="morph_remote_discovered",
                name=name,
                className=remote.ClassName,
                path=safePath(remote),
            })
        end
    end
end

--==============================================================--
-- INCOMING REMOTE CAPTURE
--==============================================================--

local function attachIncoming(remote,name)
    if S.IncomingAttached[remote] then
        return
    end

    if not (
        remote:IsA("RemoteEvent")
        or remote:IsA("UnreliableRemoteEvent")
    ) then
        return
    end

    S.IncomingAttached[remote]=true

    connect(
        remote.OnClientEvent,
        function(...)
            if not S.Running then
                return
            end

            S.Counters.remoteReceived+=1

            if name=="MorphApplied" then
                S.Counters.morphApplied+=1
            elseif name=="RevealCharacter" then
                S.Counters.revealCharacter+=1
            end

            local args=table.pack(...)

            appendRecord({
                recordType="morph_remote_received",
                remote=name,
                path=safePath(remote),
                args=serialize(args),
                character=
                    describeCharacter(
                        LP.Character,
                        false
                    ),
            })

            if name=="MorphApplied"
            or name=="RevealCharacter"
            then
                startCaptureWindow(
                    "remote_"..name,
                    {
                        args=serialize(args),
                    }
                )
            end
        end
    )
end

local function attachAllIncoming()
    for name,remote in pairs(S.TargetRemotes) do
        attachIncoming(remote,name)
    end

    connect(
        ReplicatedStorage.DescendantAdded,
        function(inst)
            if not S.Running then
                return
            end

            if CONFIG.TARGET_EVENTS[inst.Name] then
                -- This branch is unreachable because TARGET_EVENTS is array.
                -- Kept harmlessly for compatibility.
            end

            for _,targetName in ipairs(CONFIG.TARGET_EVENTS) do
                if inst.Name==targetName then
                    S.TargetRemotes[targetName]=inst

                    appendRecord({
                        recordType="morph_remote_late_discovered",
                        name=targetName,
                        className=inst.ClassName,
                        path=safePath(inst),
                    })

                    attachIncoming(inst,targetName)
                    break
                end
            end
        end
    )
end

--==============================================================--
-- OUTGOING LEGITIMATE RequestMorph OBSERVER
--==============================================================--

local function learnObservedId(id)
    if type(id)~="string" then
        return
    end

    local n=normalizeId(id)

    if n=="" then
        return
    end

    S.ObservedRequestIds[n]=true
    S.ConfirmedIds[n]=true

    for _,m in ipairs(S.Morphs) do
        if normalizeId(m.name)==n
        or normalizeId(m.idCandidate)==n
        then
            m.idCandidate=id
            m.confirmed=true
        end
    end

    resolveMorphStates()
end

local function installNamecallHook()
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
        and typeof(self)=="Instance"
        and (
            method=="FireServer"
            or method=="InvokeServer"
        )
        and (
            self:IsA("RemoteEvent")
            or self:IsA("RemoteFunction")
            or self:IsA("UnreliableRemoteEvent")
        )
        then
            local callerIsExecutor=false

            if CHECKCALLER then
                local ok,val=pcall(CHECKCALLER)
                callerIsExecutor=
                    ok and val==true
            end

            if not callerIsExecutor
            and self.Name=="RequestMorph"
            then
                local args=table.pack(...)
                local id=args[1]

                learnObservedId(id)

                S.Counters.requestObserved+=1

                appendRecord({
                    recordType="request_morph_legit_observed",
                    method=method,
                    remote=safePath(self),
                    args=serialize(args),
                    characterBefore=
                        describeCharacter(
                            LP.Character,
                            true
                        ),
                })

                startCaptureWindow(
                    "RequestMorph_legit",
                    {
                        args=serialize(args),
                    }
                )
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

local function restoreNamecallHook()
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
-- GET UNLOCKS / MORPHDEX
--==============================================================--

local function refreshServerMorphState()
    local unlockRemote=
        S.TargetRemotes.GetMorphUnlocks
        or findRemote("GetMorphUnlocks")

    local dexRemote=
        S.TargetRemotes.GetMorphdex
        or findRemote("GetMorphdex")

    S.UnlocksReady=false

    if unlockRemote
    and unlockRemote:IsA("RemoteFunction")
    then
        task.spawn(function()
            local ok,result=
                pcall(function()
                    return unlockRemote:
                        InvokeServer()
                end)

            appendRecord({
                recordType="get_morph_unlocks_result",
                ok=ok,
                path=safePath(unlockRemote),
                result=
                    ok
                    and serialize(result)
                    or tostring(result),
            })

            if ok then
                S.UnlockRaw=result
                parseUnlockTable(result)
                S.UnlocksReady=true
            end
        end)
    end

    if dexRemote
    and dexRemote:IsA("RemoteFunction")
    then
        task.spawn(function()
            local ok,result=
                pcall(function()
                    return dexRemote:
                        InvokeServer()
                end)

            appendRecord({
                recordType="get_morphdex_result",
                ok=ok,
                path=safePath(dexRemote),
                result=
                    ok
                    and serialize(result)
                    or tostring(result),
            })

            if ok then
                S.MorphdexRaw=result
            end
        end)
    end
end

--==============================================================--
-- LOCAL CHARACTER WATCH
--==============================================================--

local function isImportantDescendant(inst)
    if CONFIG.REPLICATION_NAMES[inst.Name] then
        return true
    end

    return
        inst:IsA("WeldConstraint")
        or inst:IsA("Weld")
        or inst:IsA("Motor6D")
        or inst:IsA("Bone")
        or inst:IsA("MeshPart")
        or inst:IsA("Animation")
        or inst:IsA("Animator")
        or inst:IsA("AnimationController")
        or inst:IsA("HumanoidDescription")
end

local function attachLocalCharacter(character)
    disconnectBucket(S.CharacterConnections)

    if not character then
        return
    end

    connect(
        character.DescendantAdded,
        function(inst)
            if not S.Running then
                return
            end

            if isImportantDescendant(inst) then
                S.Counters.localObjectAdded+=1

                local detail=nil

                if inst:IsA("MeshPart") then
                    detail={
                        meshId=inst.MeshId,
                        textureId=inst.TextureID,
                        size=serialize(inst.Size),
                    }

                elseif inst:IsA("Animation") then
                    detail={
                        animationId=inst.AnimationId,
                    }

                elseif inst:IsA("WeldConstraint")
                    or inst:IsA("Weld")
                    or inst:IsA("Motor6D")
                then
                    detail={
                        part0=
                            inst.Part0
                            and safePath(inst.Part0)
                            or nil,
                        part1=
                            inst.Part1
                            and safePath(inst.Part1)
                            or nil,
                    }
                end

                appendRecord({
                    recordType="local_character_descendant_added",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                    parent=
                        inst.Parent
                        and safePath(inst.Parent)
                        or nil,
                    attributes=safeAttrs(inst),
                    detail=detail,
                })
            end
        end,
        S.CharacterConnections
    )

    connect(
        character.DescendantRemoving,
        function(inst)
            if not S.Running then
                return
            end

            if isImportantDescendant(inst) then
                S.Counters.localObjectRemoved+=1

                appendRecord({
                    recordType="local_character_descendant_removing",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                })
            end
        end,
        S.CharacterConnections
    )

    -- Watch current descendants attributes too.
    for _,inst in ipairs(character:GetDescendants()) do
        connect(
            inst.AttributeChanged,
            function(attribute)
                if not S.Running then
                    return
                end

                local hit,kw=
                    hasKeyword(
                        attribute
                        .." "
                        ..inst.Name
                        .." "
                        ..safePath(inst)
                    )

                if hit then
                    local ok,value=
                        pcall(function()
                            return inst:
                                GetAttribute(attribute)
                        end)

                    appendRecord({
                        recordType="local_character_attribute_changed",
                        path=safePath(inst),
                        className=inst.ClassName,
                        name=inst.Name,
                        attribute=attribute,
                        keyword=kw,
                        value=
                            ok
                            and serialize(value)
                            or "<read_error>",
                    })
                end
            end,
            S.CharacterConnections
        )
    end
end

local function attachCharacterPropertyWatch()
    attachLocalCharacter(LP.Character)

    connect(
        LP:GetPropertyChangedSignal("Character"),
        function()
            if not S.Running then
                return
            end

            S.Counters.characterChanged+=1

            appendRecord({
                recordType="player_character_changed",
                character=
                    describeCharacter(
                        LP.Character,
                        true
                    ),
            })

            attachLocalCharacter(LP.Character)

            startCaptureWindow(
                "Player.Character_changed",
                {
                    character=
                        LP.Character
                        and safePath(LP.Character)
                        or nil,
                }
            )
        end
    )

    connect(
        LP.CharacterAdded,
        function(character)
            if not S.Running then
                return
            end

            appendRecord({
                recordType="player_character_added",
                character=
                    describeCharacter(
                        character,
                        true
                    ),
            })
        end
    )
end

--==============================================================--
-- OTHER PLAYER MORPH WATCH
--==============================================================--

local function attachOtherCharacter(player,character)
    if player==LP or not character then
        return
    end

    connect(
        character.DescendantAdded,
        function(inst)
            if not S.Running then
                return
            end

            if CONFIG.REPLICATION_NAMES[inst.Name]
            or inst:IsA("Bone")
            or inst:IsA("Motor6D")
            or inst:IsA("WeldConstraint")
            or inst:IsA("Animation")
            then
                S.Counters.otherMorphEvents+=1

                appendRecord({
                    recordType="other_player_morph_descendant_added",
                    player=player.Name,
                    userId=player.UserId,
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                    character=
                        describeCharacter(
                            character,
                            false
                        ),
                })
            end
        end,
        S.OtherPlayerConnections
    )

    connect(
        character.DescendantRemoving,
        function(inst)
            if not S.Running then
                return
            end

            if CONFIG.REPLICATION_NAMES[inst.Name]
            or inst:IsA("Bone")
            or inst:IsA("Motor6D")
            or inst:IsA("WeldConstraint")
            or inst:IsA("Animation")
            then
                S.Counters.otherMorphEvents+=1

                appendRecord({
                    recordType="other_player_morph_descendant_removing",
                    player=player.Name,
                    userId=player.UserId,
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                })
            end
        end,
        S.OtherPlayerConnections
    )
end

local function attachOtherPlayers()
    disconnectBucket(S.OtherPlayerConnections)

    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LP then
            if player.Character then
                attachOtherCharacter(
                    player,
                    player.Character
                )
            end

            connect(
                player.CharacterAdded,
                function(character)
                    if S.Running then
                        attachOtherCharacter(
                            player,
                            character
                        )
                    end
                end,
                S.OtherPlayerConnections
            )
        end
    end

    connect(
        Players.PlayerAdded,
        function(player)
            if player==LP then
                return
            end

            connect(
                player.CharacterAdded,
                function(character)
                    if S.Running then
                        attachOtherCharacter(
                            player,
                            character
                        )
                    end
                end,
                S.OtherPlayerConnections
            )
        end,
        S.OtherPlayerConnections
    )
end

--==============================================================--
-- TRACE START / STOP
--==============================================================--

local function startTrace()
    if S.Running then
        return
    end

    S.Running=true
    S.Busy=true

    discoverMorphConfigs()
    discoverRemotes()

    appendRecord({
        recordType="native_morph_v5_start",
        passiveTrace=true,
        menuRequestPolicy=
            "Only confirmed or unlocked morph IDs can be requested once per tap.",
        preWindowSeconds=
            CONFIG.PRE_WINDOW_SECONDS,
        postWindowSeconds=
            CONFIG.POST_WINDOW_SECONDS,
        sampleInterval=
            CONFIG.SAMPLE_INTERVAL,
        localCharacterBaseline=
            describeCharacter(
                LP.Character,
                true
            ),
    })

    attachAllIncoming()
    installNamecallHook()
    attachCharacterPropertyWatch()
    attachOtherPlayers()

    refreshServerMorphState()

    task.spawn(function()
        while S.Running do
            pushPreSample()
            task.wait(CONFIG.SAMPLE_INTERVAL)
        end
    end)

    S.Busy=false
end

local function stopTrace()
    if not S.Running then
        return
    end

    appendRecord({
        recordType="native_morph_v5_stop",
        counters=serialize(S.Counters),
        localCharacterFinal=
            describeCharacter(
                LP.Character,
                true
            ),
    })

    S.Running=false
    S.Busy=false
    S.ActiveWindow=nil

    disconnectBucket(S.Connections)
    disconnectBucket(S.CharacterConnections)
    disconnectBucket(S.OtherPlayerConnections)
end

--==============================================================--
-- MENU NATIVE MORPH REQUEST
--==============================================================--

local function canRequestMorph(morph)
    if not morph then
        return false,"nenhum morph selecionado"
    end

    if morph.unlocked then
        return true,"unlocked"
    end

    if morph.confirmed then
        return true,"confirmed_id"
    end

    return false,"id_not_confirmed"
end

local function requestSelectedMorph()
    if not S.Running then
        return false,"inicie o TRACE primeiro"
    end

    local morph=S.SelectedMorph

    local allowed,reason=
        canRequestMorph(morph)

    if not allowed then
        return false,
            "ID não confirmado/desbloqueado"
    end

    local remote=
        S.TargetRemotes.RequestMorph
        or findRemote("RequestMorph")

    if not remote
    or not remote:IsA("RemoteEvent")
    then
        return false,
            "RequestMorph não encontrado"
    end

    local requestId=
        "menu_"
        ..tostring(morph.idCandidate)
        .."_"
        ..tostring(os.clock())

    appendRecord({
        recordType="request_morph_menu",
        requestId=requestId,
        morphName=morph.name,
        morphId=morph.idCandidate,
        allowedBy=reason,
        unlocked=morph.unlocked,
        confirmed=morph.confirmed,
        characterBefore=
            describeCharacter(
                LP.Character,
                true
            ),
    })

    S.Counters.requestMenu+=1

    startCaptureWindow(
        "RequestMorph_menu",
        {
            morphName=morph.name,
            morphId=morph.idCandidate,
            allowedBy=reason,
        }
    )

    local ok,err=
        pcall(function()
            remote:
                FireServer(
                    morph.idCandidate
                )
        end)

    appendRecord({
        recordType="request_morph_menu_call_result",
        requestId=requestId,
        ok=ok,
        error=
            ok
            and nil
            or tostring(err),
    })

    return ok,
        ok
        and (
            "RequestMorph(\""
            ..morph.idCandidate
            .."\") enviado"
        )
        or tostring(err)
end

--==============================================================--
-- UPLOAD
--==============================================================--

local function requestRaw(options)
    if not REQUEST then
        return false,nil,
            "request/http_request indisponível"
    end

    local lastErr

    for attempt=1,CONFIG.HTTP_RETRIES do
        local ok,response=
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
    local ok,_,body=
        requestRaw({
            Url=url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
            },
            Body=encode(data),
        })

    if not ok then
        return false,nil,body
    end

    local decodeOK,decoded=
        pcall(
            HttpService.JSONDecode,
            HttpService,
            body
        )

    return true,
        (
            decodeOK
            and decoded
            or {raw=body}
        ),
        nil
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
            bytes=math.max(
                2,
                currentBytes-1
            ),
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
        focus="native_morph_request_morphapplied_character_replication",
        records=S.RecordCount,
        archiveBytes=S.ArchiveBytes,
        preWindowSeconds=CONFIG.PRE_WINDOW_SECONDS,
        postWindowSeconds=CONFIG.POST_WINDOW_SECONDS,
        unlockedCount=S.Counters.unlocked,
        confirmedCount=S.Counters.confirmed,
    }

    local all={header}

    for _,record in ipairs(S.Records) do
        table.insert(all,record)
    end

    for _,obj in ipairs(all) do
        local encoded=encode(obj)
        local add=#encoded+1

        if #current>0
        and currentBytes+add
            > CONFIG.CHUNK_TARGET_BYTES
        then
            flush()
        end

        table.insert(current,obj)
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
        stopTrace()
    end

    if not REQUEST then
        S.Upload.LastError=
            "request indisponível"
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

    local stamp=
        os.date("!%Y%m%d_%H%M%S")

    local startOK,startData,startErr=
        postJson(
            CONFIG.UPLOAD_BASE.."/start",
            {
                filename=
                    string.format(
                        "Cafeina_NativeMorphV5_%s_%s.json",
                        tostring(game.PlaceId),
                        stamp
                    ),

                source=CONFIG.VERSION,

                metadata={
                    scanner=CONFIG.VERSION,
                    placeId=game.PlaceId,
                    gameId=game.GameId,
                    placeVersion=game.PlaceVersion,
                    focus="native_morph_replication",
                    records=S.RecordCount,
                    archiveBytes=S.ArchiveBytes,
                    persistent=S.Persistent,
                },
            }
        )

    if not startOK then
        S.Upload.Running=false
        S.Upload.LastError=startErr
        return
    end

    S.Upload.UploadId=
        startData.uploadId
        or startData.id
        or startData.upload_id

    if not S.Upload.UploadId then
        S.Upload.Running=false
        S.Upload.LastError=
            "uploadId ausente"
        return
    end

    for index,chunk in ipairs(chunks) do
        S.Upload.CurrentChunk=index

        local ok,_,err=
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
            return
        end

        S.Upload.BytesSent+=chunk.bytes
        task.wait()
    end

    local finishOK,finishData,finishErr=
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
        return
    end

    local confirmed=
        finishData.confirmed==true
        or finishData.success==true
        or finishData.ok==true

    if not confirmed then
        S.Upload.Running=false
        S.Upload.LastError=
            "servidor sem confirmação"
        return
    end

    S.Upload.LastURL=
        tostring(
            finishData.url
            or finishData.link
            or finishData.fileUrl
            or ""
        )

    S.Upload.BytesSent=
        S.Upload.TotalBytes

    S.Upload.Running=false
    S.Upload.LastError=nil

    clearArchive()
end

--==============================================================--
-- UI
--==============================================================--

local COLORS={
    BG=Color3.fromRGB(8,8,10),
    PANEL=Color3.fromRGB(16,16,20),
    CARD=Color3.fromRGB(22,22,27),
    BUTTON=Color3.fromRGB(31,31,37),
    STROKE=Color3.fromRGB(49,49,57),

    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(160,160,171),

    GREEN=Color3.fromRGB(24,190,72),
    GREEN_DARK=Color3.fromRGB(30,91,50),
    RED=Color3.fromRGB(155,45,51),
    AMBER=Color3.fromRGB(146,104,35),
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
        LP:WaitForChild(
            "PlayerGui"
        )
end

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(350,590)
Main.AnchorPoint=Vector2.new(0.5,0.5)
Main.Position=UDim2.fromScale(0.5,0.48)
Main.BackgroundColor3=COLORS.BG
Main.BorderSizePixel=0
Main.Parent=Gui

local mainCorner=Instance.new("UICorner")
mainCorner.CornerRadius=UDim.new(0,11)
mainCorner.Parent=Main

local mainStroke=Instance.new("UIStroke")
mainStroke.Color=COLORS.STROKE
mainStroke.Thickness=1
mainStroke.Parent=Main

local Header=Instance.new("Frame")
Header.Size=UDim2.new(1,0,0,56)
Header.BackgroundTransparency=1
Header.Parent=Main

local Title=Instance.new("TextLabel")
Title.BackgroundTransparency=1
Title.Position=UDim2.fromOffset(12,8)
Title.Size=UDim2.new(1,-58,0,22)
Title.Font=Enum.Font.GothamBold
Title.Text="CAFEÍNA • MORPH V5"
Title.TextColor3=COLORS.TEXT
Title.TextSize=13
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Parent=Header

local Subtitle=Instance.new("TextLabel")
Subtitle.BackgroundTransparency=1
Subtitle.Position=UDim2.fromOffset(12,30)
Subtitle.Size=UDim2.new(1,-58,0,18)
Subtitle.Font=Enum.Font.Gotham
Subtitle.Text="NATIVE MORPH + SUCCESS TRACE"
Subtitle.TextColor3=COLORS.MUTED
Subtitle.TextSize=8
Subtitle.TextXAlignment=Enum.TextXAlignment.Left
Subtitle.Parent=Header

local Close=Instance.new("TextButton")
Close.AnchorPoint=Vector2.new(1,0)
Close.Position=UDim2.new(1,-8,0,8)
Close.Size=UDim2.fromOffset(36,36)
Close.BackgroundColor3=COLORS.BUTTON
Close.BorderSizePixel=0
Close.Font=Enum.Font.GothamBold
Close.Text="×"
Close.TextColor3=COLORS.TEXT
Close.TextSize=16
Close.Parent=Header

local closeCorner=Instance.new("UICorner")
closeCorner.CornerRadius=UDim.new(0,8)
closeCorner.Parent=Close

local TraceButton=Instance.new("TextButton")
TraceButton.Position=UDim2.fromOffset(10,58)
TraceButton.Size=UDim2.new(1,-20,0,42)
TraceButton.BackgroundColor3=COLORS.BUTTON
TraceButton.BorderSizePixel=0
TraceButton.Font=Enum.Font.GothamBold
TraceButton.Text="INICIAR TRACE"
TraceButton.TextColor3=COLORS.TEXT
TraceButton.TextSize=10
TraceButton.AutoButtonColor=false
TraceButton.Parent=Main
S.UI.TraceButton=TraceButton

local traceCorner=Instance.new("UICorner")
traceCorner.CornerRadius=UDim.new(0,8)
traceCorner.Parent=TraceButton

local Search=Instance.new("TextBox")
Search.Position=UDim2.fromOffset(10,108)
Search.Size=UDim2.new(1,-20,0,38)
Search.BackgroundColor3=COLORS.CARD
Search.BorderSizePixel=0
Search.ClearTextOnFocus=false
Search.Font=Enum.Font.Gotham
Search.PlaceholderText="Buscar morph... ex: TRex"
Search.PlaceholderColor3=COLORS.MUTED
Search.Text=""
Search.TextColor3=COLORS.TEXT
Search.TextSize=10
Search.Parent=Main

local searchCorner=Instance.new("UICorner")
searchCorner.CornerRadius=UDim.new(0,8)
searchCorner.Parent=Search

local List=Instance.new("ScrollingFrame")
List.Position=UDim2.fromOffset(10,153)
List.Size=UDim2.new(1,-20,0,218)
List.BackgroundColor3=COLORS.PANEL
List.BorderSizePixel=0
List.ScrollBarThickness=3
List.AutomaticCanvasSize=Enum.AutomaticSize.Y
List.CanvasSize=UDim2.new()
List.Parent=Main

local listCorner=Instance.new("UICorner")
listCorner.CornerRadius=UDim.new(0,8)
listCorner.Parent=List

local Padding=Instance.new("UIPadding")
Padding.PaddingTop=UDim.new(0,6)
Padding.PaddingBottom=UDim.new(0,6)
Padding.PaddingLeft=UDim.new(0,6)
Padding.PaddingRight=UDim.new(0,6)
Padding.Parent=List

local Layout=Instance.new("UIListLayout")
Layout.Padding=UDim.new(0,5)
Layout.SortOrder=Enum.SortOrder.LayoutOrder
Layout.Parent=List

local Selected=Instance.new("TextLabel")
Selected.Position=UDim2.fromOffset(10,379)
Selected.Size=UDim2.new(1,-20,0,42)
Selected.BackgroundColor3=COLORS.CARD
Selected.BorderSizePixel=0
Selected.Font=Enum.Font.Gotham
Selected.Text="Selecione um morph"
Selected.TextColor3=COLORS.TEXT
Selected.TextSize=9
Selected.TextWrapped=true
Selected.Parent=Main
S.UI.Selected=Selected

local selectedCorner=Instance.new("UICorner")
selectedCorner.CornerRadius=UDim.new(0,8)
selectedCorner.Parent=Selected

local RequestButton=Instance.new("TextButton")
RequestButton.Position=UDim2.fromOffset(10,428)
RequestButton.Size=UDim2.new(1,-20,0,42)
RequestButton.BackgroundColor3=COLORS.BUTTON
RequestButton.BorderSizePixel=0
RequestButton.Font=Enum.Font.GothamBold
RequestButton.Text="VIRAR NATIVO"
RequestButton.TextColor3=COLORS.TEXT
RequestButton.TextSize=10
RequestButton.AutoButtonColor=false
RequestButton.Parent=Main
S.UI.RequestButton=RequestButton

local requestCorner=Instance.new("UICorner")
requestCorner.CornerRadius=UDim.new(0,8)
requestCorner.Parent=RequestButton

local Status=Instance.new("TextLabel")
Status.Position=UDim2.fromOffset(10,477)
Status.Size=UDim2.new(1,-20,0,32)
Status.BackgroundTransparency=1
Status.Font=Enum.Font.Gotham
Status.Text="Pronto • atualizando MorphConfigs..."
Status.TextColor3=COLORS.TEXT
Status.TextSize=8
Status.TextWrapped=true
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Parent=Main
S.UI.Status=Status

local Data=Instance.new("TextLabel")
Data.Position=UDim2.fromOffset(10,510)
Data.Size=UDim2.new(1,-20,0,17)
Data.BackgroundTransparency=1
Data.Font=Enum.Font.Gotham
Data.Text="0.00 MB • 0 registros"
Data.TextColor3=COLORS.MUTED
Data.TextSize=8
Data.TextXAlignment=Enum.TextXAlignment.Left
Data.Parent=Main
S.UI.Data=Data

local Send=Instance.new("TextButton")
Send.Position=UDim2.fromOffset(10,534)
Send.Size=UDim2.new(1,-20,0,34)
Send.BackgroundColor3=COLORS.BUTTON
Send.BorderSizePixel=0
Send.Font=Enum.Font.GothamBold
Send.Text="SEM DADOS"
Send.TextColor3=COLORS.TEXT
Send.TextSize=9
Send.AutoButtonColor=false
Send.Parent=Main
S.UI.Send=Send

local sendCorner=Instance.new("UICorner")
sendCorner.CornerRadius=UDim.new(0,8)
sendCorner.Parent=Send

local Bar=Instance.new("Frame")
Bar.Position=UDim2.fromOffset(10,574)
Bar.Size=UDim2.new(1,-20,0,7)
Bar.BackgroundColor3=Color3.fromRGB(25,25,30)
Bar.BorderSizePixel=0
Bar.ClipsDescendants=true
Bar.Parent=Main

local barCorner=Instance.new("UICorner")
barCorner.CornerRadius=UDim.new(1,0)
barCorner.Parent=Bar

local Fill=Instance.new("Frame")
Fill.Size=UDim2.new(0,0,1,0)
Fill.BackgroundColor3=COLORS.GREEN
Fill.BorderSizePixel=0
Fill.Parent=Bar
S.UI.Fill=Fill

local fillCorner=Instance.new("UICorner")
fillCorner.CornerRadius=UDim.new(1,0)
fillCorner.Parent=Fill

--==============================================================--
-- UI LOGIC
--==============================================================--

local function setStatus(text)
    Status.Text=tostring(text)
end

local function morphStatusText(m)
    if m.unlocked then
        return "LIBERADO"
    end

    if m.confirmed then
        return "ID CONFIRMADO"
    end

    return "ID NÃO CONFIRMADO"
end

local function morphStatusColor(m)
    if m.unlocked then
        return COLORS.GREEN_DARK
    end

    if m.confirmed then
        return COLORS.AMBER
    end

    return COLORS.BUTTON
end

local function refreshSelectedUI()
    local m=S.SelectedMorph

    if not m then
        Selected.Text="Selecione um morph"
        RequestButton.Text="VIRAR NATIVO"
        RequestButton.BackgroundColor3=COLORS.BUTTON
        return
    end

    Selected.Text=
        m.name
        .." • id: "
        ..m.idCandidate
        .."\n"
        ..morphStatusText(m)

    local allowed=
        m.unlocked
        or m.confirmed

    if allowed and S.Running then
        RequestButton.BackgroundColor3=
            COLORS.GREEN_DARK
        RequestButton.Text=
            "VIRAR NATIVO • "
            ..m.idCandidate

    elseif allowed then
        RequestButton.BackgroundColor3=
            COLORS.AMBER
        RequestButton.Text=
            "INICIE TRACE PARA VIRAR"

    else
        RequestButton.BackgroundColor3=
            COLORS.BUTTON
        RequestButton.Text=
            "ID NÃO CONFIRMADO"
    end
end

local function clearMorphRows()
    for _,child in ipairs(List:GetChildren()) do
        if child:IsA("TextButton")
        and child.Name=="MorphRow"
        then
            child:Destroy()
        end
    end
end

local function rebuildMorphList()
    clearMorphRows()

    local query=
        lower(Search.Text)

    S.FilteredMorphs={}

    for _,m in ipairs(S.Morphs) do
        local matches=
            query==""
            or string.find(
                lower(m.name),
                query,
                1,
                true
            )
            or string.find(
                lower(m.idCandidate),
                query,
                1,
                true
            )

        if matches then
            table.insert(
                S.FilteredMorphs,
                m
            )
        end
    end

    for i,m in ipairs(S.FilteredMorphs) do
        local row=Instance.new("TextButton")
        row.Name="MorphRow"
        row.LayoutOrder=i
        row.Size=UDim2.new(1,0,0,38)
        row.BackgroundColor3=morphStatusColor(m)
        row.BorderSizePixel=0
        row.AutoButtonColor=false
        row.Font=Enum.Font.Gotham
        row.Text=
            m.name
            .."   •   "
            ..morphStatusText(m)
        row.TextColor3=COLORS.TEXT
        row.TextSize=8
        row.TextXAlignment=Enum.TextXAlignment.Left
        row.Parent=List

        local rp=Instance.new("UIPadding")
        rp.PaddingLeft=UDim.new(0,10)
        rp.PaddingRight=UDim.new(0,8)
        rp.Parent=row

        local rc=Instance.new("UICorner")
        rc.CornerRadius=UDim.new(0,7)
        rc.Parent=row

        row.Activated:Connect(function()
            S.SelectedMorph=m

            appendRecord({
                recordType="morph_menu_selected",
                name=m.name,
                id=m.idCandidate,
                unlocked=m.unlocked,
                confirmed=m.confirmed,
                path=m.path,
            })

            refreshSelectedUI()
        end)
    end

    if #S.FilteredMorphs==0 then
        local empty=Instance.new("TextLabel")
        empty.Name="MorphRowEmpty"
        empty.LayoutOrder=1
        empty.Size=UDim2.new(1,0,0,40)
        empty.BackgroundTransparency=1
        empty.Font=Enum.Font.Gotham
        empty.Text="Nenhum MorphConfig encontrado"
        empty.TextColor3=COLORS.MUTED
        empty.TextSize=9
        empty.Parent=List
    end
end

local function refreshMainUI()
    if S.Running then
        TraceButton.Text="ENCERRAR TRACE"
        TraceButton.BackgroundColor3=COLORS.RED
    else
        TraceButton.Text="INICIAR TRACE"
        TraceButton.BackgroundColor3=COLORS.BUTTON
    end

    Data.Text=
        string.format(
            "%.2f MB • %d registros • MorphApplied %d",
            mb(S.ArchiveBytes),
            S.RecordCount,
            S.Counters.morphApplied
        )

    if S.Upload.Running then
        Send.Text=
            string.format(
                "ENVIANDO %.2f / %.2f MB • %d/%d",
                mb(S.Upload.BytesSent),
                mb(S.Upload.TotalBytes),
                S.Upload.CurrentChunk,
                S.Upload.TotalChunks
            )
        Send.BackgroundColor3=COLORS.RED

    elseif S.RecordCount>0 then
        Send.Text="ENVIAR DADOS"
        Send.BackgroundColor3=COLORS.GREEN

    else
        Send.Text="SEM DADOS"
        Send.BackgroundColor3=COLORS.BUTTON
    end

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

    Fill.Size=
        UDim2.new(
            ratio,
            0,
            1,
            0
        )

    refreshSelectedUI()
end

--==============================================================--
-- MOBILE DRAG
--==============================================================--

do
    local dragging=false
    local dragInput
    local dragStart
    local startPos

    Header.InputBegan:
    Connect(function(input)
        if input.UserInputType
            ==Enum.UserInputType.MouseButton1
        or input.UserInputType
            ==Enum.UserInputType.Touch
        then
            dragging=true
            dragStart=input.Position
            startPos=Main.Position

            input.Changed:
            Connect(function()
                if input.UserInputState
                    ==Enum.UserInputState.End
                then
                    dragging=false
                end
            end)
        end
    end)

    Header.InputChanged:
    Connect(function(input)
        if input.UserInputType
            ==Enum.UserInputType.MouseMovement
        or input.UserInputType
            ==Enum.UserInputType.Touch
        then
            dragInput=input
        end
    end)

    UserInputService.InputChanged:
    Connect(function(input)
        if dragging
        and input==dragInput
        then
            local delta=
                input.Position
                -dragStart

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

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

Search:GetPropertyChangedSignal("Text"):
Connect(function()
    rebuildMorphList()
end)

TraceButton.Activated:
Connect(function()
    if S.Upload.Running then
        return
    end

    if S.Running then
        stopTrace()
        setStatus(
            "Trace encerrado • dados preservados"
        )
    else
        startTrace()

        setStatus(
            "TRACE ativo • use morph normal ou selecione um liberado"
        )

        task.delay(0.4,function()
            resolveMorphStates()
            rebuildMorphList()
            refreshMainUI()
        end)
    end

    refreshMainUI()
end)

RequestButton.Activated:
Connect(function()
    local ok,message=
        requestSelectedMorph()

    setStatus(message)

    if ok then
        refreshMainUI()
    end
end)

Send.Activated:
Connect(function()
    if S.RecordCount<=0
    or S.Upload.Running
    then
        return
    end

    setStatus("Enviando dados...")

    task.spawn(function()
        uploadAll()

        if S.Upload.LastError then
            setStatus(
                "Erro no upload • dados preservados"
            )

        elseif S.Upload.LastURL~="" then
            setStatus(
                "Upload confirmado ✓ • archive limpo"
            )
        end

        refreshMainUI()
    end)
end)

Close.Activated:
Connect(function()
    stopTrace()
    restoreNamecallHook()

    pcall(function()
        Gui:Destroy()
    end)
end)

--==============================================================--
-- STARTUP
--==============================================================--

loadArchive()
discoverMorphConfigs()
discoverRemotes()

-- Query once at startup as well, because the list should already
-- know which morphs the current server reports as unlocked.
refreshServerMorphState()

rebuildMorphList()

if S.RecordCount>0 then
    setStatus(
        "Dados anteriores recuperados • "
        ..string.format("%.2f MB",mb(S.ArchiveBytes))
    )
else
    setStatus(
        "Pronto • "
        ..tostring(S.Counters.morphConfigs)
        .." MorphConfigs encontrados"
    )
end

task.spawn(function()
    while Gui.Parent do
        resolveMorphStates()
        refreshMainUI()

        -- Rebuild list less often so mobile scrolling remains smooth.
        task.wait(0.40)
    end
end)

-- Rebuild when unlock query has had time to return.
task.spawn(function()
    local lastUnlocked=-1
    local lastConfirmed=-1

    while Gui.Parent do
        local u=S.Counters.unlocked
        local c=S.Counters.confirmed

        if u~=lastUnlocked
        or c~=lastConfirmed
        then
            lastUnlocked=u
            lastConfirmed=c
            rebuildMorphList()
        end

        task.wait(0.50)
    end
end)

env.__CAFEINA_NATIVE_MORPH_V5={
    StartTrace=startTrace,
    StopTrace=stopTrace,
    RefreshMorphState=refreshServerMorphState,
    RequestSelected=requestSelectedMorph,
    Upload=uploadAll,

    GetState=function()
        return {
            running=S.Running,
            records=S.RecordCount,
            bytes=S.ArchiveBytes,

            morphConfigs=S.Counters.morphConfigs,
            unlocked=S.Counters.unlocked,
            confirmed=S.Counters.confirmed,

            requestObserved=S.Counters.requestObserved,
            requestMenu=S.Counters.requestMenu,
            morphApplied=S.Counters.morphApplied,
            revealCharacter=S.Counters.revealCharacter,
            characterChanged=S.Counters.characterChanged,
            otherMorphEvents=S.Counters.otherMorphEvents,

            selected=
                S.SelectedMorph
                and {
                    name=S.SelectedMorph.name,
                    id=S.SelectedMorph.idCandidate,
                    unlocked=S.SelectedMorph.unlocked,
                    confirmed=S.SelectedMorph.confirmed,
                }
                or nil,

            upload=S.Upload,
        }
    end,

    Destroy=function()
        stopTrace()
        restoreNamecallHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] NATIVE MORPH MENU + TRACE V5.0 carregado.")
