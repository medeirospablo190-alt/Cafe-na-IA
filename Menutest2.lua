--==============================================================--
-- CAFEÍNA • MORPH REQUEST TRACE V7.0
-- PASSIVE LEGITIMATE MORPH CAPTURE
--
-- Foco:
--   2s ANTES
--   RequestMorph legítimo
--   MorphApplied / RevealCharacter
--   Character / RootPart / Bones / Welds / Animations
--   5s DEPOIS
--
-- NÃO dispara RequestMorph.
-- NÃO chama RemoteFunction.
-- NÃO tenta burlar unlocks.
-- NÃO faz brute force.
--
-- ÚNICO HOOK:
-- • intercepta SOMENTE o RemoteEvent exato RequestMorph;
-- • chama o __namecall ORIGINAL PRIMEIRO;
-- • só depois agenda a gravação em task.defer;
-- • não serializa argumentos antes do FireServer real acontecer.
--
-- Todo o restante continua passivo.
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
    VERSION = "MORPH_REQUEST_TRACE_V7_0",
    GUI_NAME = "CafeinaMorphRequestTraceV70",

    PRE_WINDOW_SECONDS = 2.0,
    POST_WINDOW_SECONDS = 5.0,
    SAMPLE_INTERVAL = 0.10,

    TARGET_EVENTS = {
        MorphApplied=true,
        RevealCharacter=true,
        MorphUnlocksReady=true,
        MorphdexUpdated=true,
        MorphPurchased=true,
        EquipVariant=true,
        UnequipVariant=true,
        EquipSkin=true,
        UnequipSkin=true,
    },

    ATTRIBUTE_KEYWORDS = {
        "morph","skin","variant","species","character",
        "form","model","creature","animal",
    },

    UPLOAD_BASE = "https://cafe-na-ia.onrender.com/upload",
    CHUNK_TARGET_BYTES = 450000,
    MAX_ARCHIVE_BYTES = 120 * 1024 * 1024,

    ARCHIVE_ROOT = "CafeinaMorphRequestV7",
    ARCHIVE_FOLDER = "CafeinaMorphRequestV7/" .. tostring(game.PlaceId),
    ARCHIVE_FILE = "CafeinaMorphRequestV7/" .. tostring(game.PlaceId) .. "/trace.jsonl",

    HTTP_RETRIES = 3,
    HTTP_RETRY_BASE = 1.0,
}

--==============================================================--
-- EXECUTOR CAPS
--==============================================================--

local env = (getgenv and getgenv()) or _G

pcall(function()
    local old = rawget(env, "__CAFEINA_MORPH_REQUEST_V7")
    if type(old)=="table" and type(old.Destroy)=="function" then
        old.Destroy()
    end
end)

local function pick(...)
    for i=1,select("#",...) do
        local v=select(i,...)
        if type(v)=="function" then return v end
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
local NEWCCLOSURE = pick(rawget(env,"newcclosure"))

--==============================================================--
-- STATE
--==============================================================--

local S = {
    Running=false,
    Armed=false,
    Busy=false,

    Connections={},
    CharacterConnections={},

    Records={},
    RecordCount=0,
    ArchiveBytes=0,
    Persistent=false,

    PreBuffer={},
    PreBufferMax=math.max(10, math.ceil(CONFIG.PRE_WINDOW_SECONDS / CONFIG.SAMPLE_INTERVAL) + 4),

    ActiveWindow=nil,
    WindowCounter=0,

    LastCharacter=LP.Character,
    LastCharacterName=LP.Character and LP.Character.Name or nil,

    RequestHookInstalled=false,
    RequestHookAvailable=false,
    RequestCaptureEnabled=true,
    OriginalNamecall=nil,
    RequestMorphRemote=nil,

    LastRequest=nil,
    LastMorphIdValue=LP:GetAttribute("LastMorphId"),

    Counters={
        preSamples=0,
        windows=0,
        guiTap=0,
        requestMorph=0,
        morphAttrChanged=0,
        morphApplied=0,
        revealCharacter=0,
        characterChanged=0,
        objectAdded=0,
        objectRemoved=0,
        attributeChanged=0,
        valueChanged=0,
        remoteReceived=0,
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

--==============================================================--
-- HELPERS
--==============================================================--

local function disconnect(c)
    if c then pcall(function() c:Disconnect() end) end
end

local function connect(signal,fn,bucket)
    local c=signal:Connect(fn)
    table.insert(bucket or S.Connections,c)
    return c
end

local function disconnectBucket(bucket)
    for _,c in ipairs(bucket) do disconnect(c) end
    table.clear(bucket)
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function safePath(inst)
    if typeof(inst)~="Instance" then return tostring(inst) end
    local ok,v=pcall(function() return inst:GetFullName() end)
    return ok and v or inst.Name
end

local function safeAttrs(inst)
    local ok,attrs=pcall(function() return inst:GetAttributes() end)
    if not ok or type(attrs)~="table" then return {} end

    local out={}
    local n=0
    for k,v in pairs(attrs) do
        n+=1
        if n>120 then out.__truncated=true break end

        local tv=typeof(v)
        if tv=="string" or tv=="number" or tv=="boolean" then
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

    if depth>5 then return "<max_depth>" end

    local tv=typeof(v)

    if v==nil or tv=="string" or tv=="number" or tv=="boolean" then
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
        return {type="Vector3",x=v.X,y=v.Y,z=v.Z}
    end

    if tv=="Vector2" then
        return {type="Vector2",x=v.X,y=v.Y}
    end

    if tv=="CFrame" then
        local p=v.Position
        return {type="CFrame",x=p.X,y=p.Y,z=p.Z}
    end

    if tv=="table" then
        if seen[v] then return "<cycle>" end
        seen[v]=true

        local out={}
        local count=0

        for k,val in pairs(v) do
            count+=1
            if count>120 then out.__truncated=true break end
            out[tostring(k)] = serialize(val,depth+1,seen)
        end

        seen[v]=nil
        return out
    end

    return tostring(v)
end

local function encode(v)
    local ok,r=pcall(HttpService.JSONEncode,HttpService,v)
    return ok and r or "{}"
end

local function mb(bytes)
    return (tonumber(bytes) or 0)/(1024*1024)
end

local function keywordMatch(text)
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
    if not (WRITEFILE and READFILE and ISFILE) then
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
    if type(record)~="table" then return false end

    record._version=CONFIG.VERSION
    record._placeId=game.PlaceId
    record._gameId=game.GameId
    record._placeVersion=game.PlaceVersion
    record._unix=os.time()
    record._clock=os.clock()

    local line=encode(record)
    local bytes=#line+1

    if S.ArchiveBytes+bytes>CONFIG.MAX_ARCHIVE_BYTES then
        return false
    end

    table.insert(S.Records,record)
    S.RecordCount+=1
    S.ArchiveBytes+=bytes

    if S.Persistent then
        local full=line.."\n"
        local wrote=false

        if APPENDFILE then
            wrote=pcall(APPENDFILE,CONFIG.ARCHIVE_FILE,full)
        end

        if not wrote then
            local old=""
            if ISFILE(CONFIG.ARCHIVE_FILE) then
                pcall(function() old=READFILE(CONFIG.ARCHIVE_FILE) or "" end)
            end
            pcall(WRITEFILE,CONFIG.ARCHIVE_FILE,old..full)
        end
    end

    return true
end

local function loadArchive()
    ensureArchive()

    table.clear(S.Records)
    S.RecordCount=0
    S.ArchiveBytes=0

    if S.Persistent and ISFILE(CONFIG.ARCHIVE_FILE) then
        local ok,content=pcall(READFILE,CONFIG.ARCHIVE_FILE)

        if ok and type(content)=="string" then
            for line in string.gmatch(content,"[^\r\n]+") do
                local dOK,obj=pcall(HttpService.JSONDecode,HttpService,line)
                if dOK and type(obj)=="table" then
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

    if S.Persistent and DELFILE and ISFILE(CONFIG.ARCHIVE_FILE) then
        pcall(DELFILE,CONFIG.ARCHIVE_FILE)
    end
end

--==============================================================--
-- CHARACTER SNAPSHOT
--==============================================================--

local function describePlayingTracks(animator)
    if not animator then return {} end

    local out={}
    local ok,tracks=pcall(function() return animator:GetPlayingAnimationTracks() end)

    if ok and type(tracks)=="table" then
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
    end

    return out
end

local function describeCharacter(character,full)
    if not character then return nil end

    local hum=character:FindFirstChildOfClass("Humanoid")
    local animator=character:FindFirstChildWhichIsA("Animator",true)
    local controller=character:FindFirstChildWhichIsA("AnimationController",true)

    local root=character:FindFirstChild("HumanoidRootPart")
    local morphRoot=character:FindFirstChild("RootPart")

    local summary={
        name=character.Name,
        path=safePath(character),
        parent=character.Parent and safePath(character.Parent) or nil,
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

        humanoidRootPart=root and {
            path=safePath(root),
            position=serialize(root.Position),
            size=serialize(root.Size),
            attributes=safeAttrs(root),
        } or nil,

        rootPart=morphRoot and {
            path=safePath(morphRoot),
            position=serialize(morphRoot.Position),
            size=serialize(morphRoot.Size),
            attributes=safeAttrs(morphRoot),
        } or nil,

        animator=animator and safePath(animator) or nil,
        animationController=controller and safePath(controller) or nil,
        playingTracks=describePlayingTracks(animator),
    }

    if not full then
        return summary
    end

    local descendants=character:GetDescendants()
    local classCounts={}
    local important={}

    for _,inst in ipairs(descendants) do
        classCounts[inst.ClassName]=(classCounts[inst.ClassName] or 0)+1

        if inst:IsA("Motor6D") then
            table.insert(important,{
                className="Motor6D",
                name=inst.Name,
                path=safePath(inst),
                part0=inst.Part0 and safePath(inst.Part0) or nil,
                part1=inst.Part1 and safePath(inst.Part1) or nil,
                c0=tostring(inst.C0),
                c1=tostring(inst.C1),
            })
        elseif inst:IsA("WeldConstraint") or inst:IsA("Weld") then
            table.insert(important,{
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
                part0=inst.Part0 and safePath(inst.Part0) or nil,
                part1=inst.Part1 and safePath(inst.Part1) or nil,
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

    summary.descendantCount=#descendants
    summary.classCounts=classCounts
    summary.important=important

    return summary
end

local function describeOtherMorphCharacters()
    local out={}

    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LP and player.Character then
            local character=player.Character
            local rootPart=character:FindFirstChild("RootPart")
            local hrp=character:FindFirstChild("HumanoidRootPart")

            local weld=
                hrp
                and hrp:FindFirstChild("HRP_to_RootPart")

            if rootPart
            or weld
            or character:FindFirstChildWhichIsA("Bone",true)
            then
                table.insert(out,{
                    player=player.Name,
                    userId=player.UserId,
                    character=describeCharacter(character,false),
                    hasRootPart=rootPart~=nil,
                    hasHRPToRootPart=weld~=nil,
                    weld=weld and {
                        path=safePath(weld),
                        part0=weld.Part0 and safePath(weld.Part0) or nil,
                        part1=weld.Part1 and safePath(weld.Part1) or nil,
                    } or nil,
                })
            end
        end
    end

    return out
end

local function currentSample(label,full)
    Camera=Workspace.CurrentCamera

    return {
        label=label,
        character=describeCharacter(LP.Character,full),
        camera={
            subject=Camera.CameraSubject and safePath(Camera.CameraSubject) or nil,
            type=tostring(Camera.CameraType),
            cframe=serialize(Camera.CFrame),
        },
        otherMorphCharacters=describeOtherMorphCharacters(),
    }
end

--==============================================================--
-- PRE-BUFFER + CAPTURE WINDOW
--==============================================================--

local function pushPreSample()
    local sample={
        t=os.clock(),
        state=currentSample("pre_buffer",false),
    }

    table.insert(S.PreBuffer,sample)

    while #S.PreBuffer>S.PreBufferMax do
        table.remove(S.PreBuffer,1)
    end

    S.Counters.preSamples+=1
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

local function captureWindowSample(windowId,trigger,relative,full)
    appendRecord({
        recordType="morph_window_sample",
        windowId=windowId,
        trigger=trigger,
        relative=relative,
        full=full==true,
        state=currentSample("window",full),
    })
end

local function startCaptureWindow(trigger,triggerData)
    local now=os.clock()

    if S.ActiveWindow
    and now < S.ActiveWindow.endsAt
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
        "morph_window_"
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
        characterBefore=describeCharacter(LP.Character,true),
    })

    flushPreBuffer(id,trigger)

    captureWindowSample(id,trigger,0,true)

    task.spawn(function()
        local start=os.clock()
        local nextFull=0.5

        while S.Running
        and S.ActiveWindow
        and S.ActiveWindow.id==id
        and os.clock()<=S.ActiveWindow.endsAt
        do
            local relative=os.clock()-start
            local full=relative>=nextFull

            if full then
                nextFull+=0.5
            end

            captureWindowSample(id,trigger,relative,full)
            task.wait(CONFIG.SAMPLE_INTERVAL)
        end

        if S.ActiveWindow and S.ActiveWindow.id==id then
            appendRecord({
                recordType="morph_window_end",
                windowId=id,
                trigger=trigger,
                duration=os.clock()-start,
                characterAfter=describeCharacter(LP.Character,true),
            })

            S.ActiveWindow=nil
        end
    end)

    return id
end

--==============================================================--
-- REMOTE DISCOVERY + LISTENERS
--==============================================================--

local function findRemote(name)
    local events=ReplicatedStorage:FindFirstChild("Events")

    if events then
        local direct=events:FindFirstChild(name,true)
        if direct then return direct end
    end

    return ReplicatedStorage:FindFirstChild(name,true)
end

local function attachIncomingRemoteListeners()
    for name,_ in pairs(CONFIG.TARGET_EVENTS) do
        local remote=findRemote(name)

        if remote
        and (
            remote:IsA("RemoteEvent")
            or remote:IsA("UnreliableRemoteEvent")
        )
        then
            connect(remote.OnClientEvent,function(...)
                if not S.Running then return end

                S.Counters.remoteReceived+=1

                if name=="MorphApplied" then
                    S.Counters.morphApplied+=1
                elseif name=="RevealCharacter" then
                    S.Counters.revealCharacter+=1
                end

                local args=table.pack(...)

                local requestCorrelation=nil

                if S.LastRequest then
                    requestCorrelation={
                        id=S.LastRequest.id,
                        argc=S.LastRequest.argc,
                        argTypes=S.LastRequest.argTypes,
                        deltaMs=
                            (os.clock()-S.LastRequest.clock)
                            *1000,
                    }
                end

                appendRecord({
                    recordType="morph_remote_received",
                    remote=name,
                    path=safePath(remote),
                    args=serialize(args),
                    requestCorrelation=requestCorrelation,
                    character=describeCharacter(LP.Character,false),
                })

                if name=="MorphApplied"
                or name=="RevealCharacter"
                then
                    startCaptureWindow(
                        "remote_received_"..name,
                        {
                            remote=name,
                            args=serialize(args),
                        }
                    )
                end
            end)
        end
    end
end

--==============================================================--
-- ZERO-HOOK PASSIVE TRIGGERS
--==============================================================--

local MORPH_ATTRS = {
    currentmorphid=true,
    morphtype=true,
    isflyingmorph=true,
    flyspeed=true,
    currentskin=true,
    currentvariant=true,
    morphid=true,
    species=true,
    form=true,
}

local MorphNames = {}

local function normalizeText(v)
    local s=lower(v)
    s=string.gsub(s,"%s+","")
    s=string.gsub(s,"[_%-]","")
    return s
end

local function discoverMorphNames()
    table.clear(MorphNames)

    local folder=ReplicatedStorage:FindFirstChild("MorphConfigs")
    if not folder then
        return
    end

    local list={}

    for _,inst in ipairs(folder:GetChildren()) do
        if inst:IsA("ModuleScript") then
            local n=normalizeText(inst.Name)
            MorphNames[n]=inst.Name

            table.insert(list,{
                name=inst.Name,
                normalized=n,
                path=safePath(inst),
                attributes=safeAttrs(inst),
            })
        end
    end

    table.sort(list,function(a,b)
        return lower(a.name)<lower(b.name)
    end)

    appendRecord({
        recordType="morph_config_catalog_passive",
        count=#list,
        morphs=list,
    })
end

local function isMorphAttribute(attribute)
    local n=normalizeText(attribute)

    if MORPH_ATTRS[n] then
        return true
    end

    return string.find(n,"morph",1,true)~=nil
        or string.find(n,"skin",1,true)~=nil
        or string.find(n,"variant",1,true)~=nil
        or string.find(n,"species",1,true)~=nil
end

local function attachMorphAttributeObserver(inst,label,bucket)
    if not inst then
        return
    end

    connect(inst.AttributeChanged,function(attribute)
        if not S.Running or not isMorphAttribute(attribute) then
            return
        end

        local ok,value=pcall(function()
            return inst:GetAttribute(attribute)
        end)

        S.Counters.morphAttrChanged+=1

        local normalizedAttribute=normalizeText(attribute)
        local previousLastMorphId=nil
        local requestDeltaMs=nil
        local correlatedRequest=nil

        if normalizedAttribute=="lastmorphid" then
            previousLastMorphId=S.LastMorphIdValue

            if ok then
                S.LastMorphIdValue=value
            end

            if S.LastRequest then
                requestDeltaMs=
                    (os.clock()-S.LastRequest.clock)*1000

                correlatedRequest={
                    id=S.LastRequest.id,
                    argc=S.LastRequest.argc,
                    argTypes=S.LastRequest.argTypes,
                    deltaMs=requestDeltaMs,
                }
            end
        end

        appendRecord({
            recordType="morph_attribute_changed_passive",
            ownerLabel=label,
            ownerClass=inst.ClassName,
            ownerName=inst.Name,
            ownerPath=safePath(inst),
            attribute=attribute,
            value=ok and serialize(value) or "<read_error>",
            previousLastMorphId=previousLastMorphId,
            requestCorrelation=correlatedRequest,
            allAttributes=safeAttrs(inst),
        })

        startCaptureWindow(
            "attribute_"..tostring(attribute),
            {
                owner=label,
                value=ok and serialize(value) or nil,
            }
        )
    end,bucket)
end

local function guiObjectsAt(position)
    local playerGui=LP:FindFirstChild("PlayerGui")
    if not playerGui then
        return {}
    end

    local ok,objects=pcall(function()
        return playerGui:GetGuiObjectsAtPosition(position.X,position.Y)
    end)

    return ok and type(objects)=="table" and objects or {}
end

local function describeGuiObject(obj)
    local out={
        className=obj.ClassName,
        name=obj.Name,
        path=safePath(obj),
    }

    if obj:IsA("TextButton")
    or obj:IsA("TextLabel")
    or obj:IsA("TextBox")
    then
        out.text=obj.Text
    end

    return out
end

local function isMorphGuiObjects(objects)
    for _,obj in ipairs(objects) do
        local text=obj.Name.." "..safePath(obj)

        if obj:IsA("TextButton")
        or obj:IsA("TextLabel")
        or obj:IsA("TextBox")
        then
            text=text.." "..obj.Text
        end

        local normalized=normalizeText(text)

        if string.find(normalized,"morph",1,true)
        or string.find(normalized,"transform",1,true)
        then
            return true
        end

        for morphName,_ in pairs(MorphNames) do
            if #morphName>=3
            and string.find(normalized,morphName,1,true)
            then
                return true
            end
        end
    end

    return false
end

local function attachOriginalMorphUiObserver()
    connect(UserInputService.InputBegan,function(input)
        if not S.Running then
            return
        end

        if input.UserInputType~=Enum.UserInputType.Touch
        and input.UserInputType~=Enum.UserInputType.MouseButton1
        then
            return
        end

        local objects=guiObjectsAt(input.Position)

        if #objects==0
        or not isMorphGuiObjects(objects)
        then
            return
        end

        local described={}

        for i,obj in ipairs(objects) do
            if i>12 then break end
            table.insert(described,describeGuiObject(obj))
        end

        S.Counters.guiTap+=1

        appendRecord({
            recordType="morph_original_gui_tap",
            position={
                x=input.Position.X,
                y=input.Position.Y,
            },
            objects=described,
        })

        startCaptureWindow(
            "morph_original_gui_tap",
            {objects=described}
        )
    end)
end

--==============================================================--
-- TARGETED RequestMorph POST-CALL OBSERVER
--==============================================================--

local function findRequestMorphRemote()
    local events=
        ReplicatedStorage:
        FindFirstChild("Events")

    if events then
        local direct=
            events:
            FindFirstChild(
                "RequestMorph",
                true
            )

        if direct
        and direct:IsA("RemoteEvent")
        then
            return direct
        end
    end

    local fallback=
        ReplicatedStorage:
        FindFirstChild(
            "RequestMorph",
            true
        )

    if fallback
    and fallback:IsA("RemoteEvent")
    then
        return fallback
    end

    return nil
end

local function requestArgTypes(args)
    local out={}

    for i=1,args.n do
        out[i]=typeof(args[i])
    end

    return out
end

local function installTargetedRequestHook()
    if S.RequestHookInstalled then
        return true
    end

    S.RequestMorphRemote=
        findRequestMorphRemote()

    if not S.RequestMorphRemote
    or not HOOKMETAMETHOD
    or not GETNAMECALLMETHOD
    then
        S.RequestHookAvailable=false

        appendRecord({
            recordType="request_hook_status",
            available=false,
            remote=
                S.RequestMorphRemote
                and safePath(S.RequestMorphRemote)
                or nil,
            hookmetamethod=
                HOOKMETAMETHOD~=nil,
            getnamecallmethod=
                GETNAMECALLMETHOD~=nil,
        })

        return false
    end

    local oldNamecall

    local wrapper=function(self,...)
        local method=
            GETNAMECALLMETHOD()

        if S.Running
        and S.RequestCaptureEnabled
        and self==S.RequestMorphRemote
        and method=="FireServer"
        then
            -- CRITICAL:
            -- Do not inspect/serialize arguments before forwarding.
            -- The real game's FireServer is executed immediately.
            local requestClock=os.clock()
            local lastMorphBefore=
                S.LastMorphIdValue

            local returns=
                table.pack(
                    oldNamecall(
                        self,
                        ...
                    )
                )

            local returnClock=os.clock()

            -- Only after the original call has completed do we copy args.
            local args=table.pack(...)
            local types=
                requestArgTypes(args)

            task.defer(function()
                local firstArg=args[1]

                S.Counters.requestMorph+=1

                S.LastRequest={
                    clock=requestClock,
                    returnClock=returnClock,
                    id=
                        type(firstArg)=="string"
                        and firstArg
                        or nil,
                    argc=args.n,
                    argTypes=types,
                    args=serialize(args),
                    lastMorphBefore=
                        lastMorphBefore,
                }

                appendRecord({
                    recordType="request_morph_outgoing_postcall",
                    remote=
                        safePath(
                            S.RequestMorphRemote
                        ),
                    method="FireServer",

                    requestClock=requestClock,
                    returnClock=returnClock,
                    callDurationMs=
                        (returnClock-requestClock)
                        *1000,

                    argc=args.n,
                    argTypes=types,
                    args=serialize(args),

                    morphId=
                        type(firstArg)=="string"
                        and firstArg
                        or nil,

                    lastMorphIdBefore=
                        lastMorphBefore,

                    lastMorphIdImmediateAfter=
                        LP:GetAttribute(
                            "LastMorphId"
                        ),

                    note=
                        "Original __namecall executed before logging/serialization.",
                })

                startCaptureWindow(
                    "RequestMorph_postcall",
                    {
                        argc=args.n,
                        argTypes=types,
                        morphId=
                            type(firstArg)=="string"
                            and firstArg
                            or nil,
                    }
                )
            end)

            return table.unpack(
                returns,
                1,
                returns.n
            )
        end

        return oldNamecall(
            self,
            ...
        )
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

    if ok
    and type(old)=="function"
    then
        oldNamecall=old
        S.OriginalNamecall=old
        S.RequestHookInstalled=true
        S.RequestHookAvailable=true

        appendRecord({
            recordType="request_hook_status",
            available=true,
            installed=true,
            remote=
                safePath(
                    S.RequestMorphRemote
                ),
            strategy=
                "exact_remote_identity_original_first_postcall_deferred_logging",
        })

        return true
    end

    S.RequestHookAvailable=false

    appendRecord({
        recordType="request_hook_status",
        available=false,
        installed=false,
        error=tostring(old),
        remote=
            S.RequestMorphRemote
            and safePath(S.RequestMorphRemote)
            or nil,
    })

    return false
end

local function removeTargetedRequestHook()
    if not S.RequestHookInstalled then
        return
    end

    if HOOKMETAMETHOD
    and type(S.OriginalNamecall)=="function"
    then
        pcall(
            HOOKMETAMETHOD,
            game,
            "__namecall",
            S.OriginalNamecall
        )
    end

    S.RequestHookInstalled=false
end

--==============================================================--
-- CHARACTER WATCHERS
--==============================================================--

local function attachCharacterObjectWatchers(character)
    disconnectBucket(S.CharacterConnections)

    if not character then return end

    attachMorphAttributeObserver(
        character,
        "LocalCharacter",
        S.CharacterConnections
    )

    local hum=character:FindFirstChildOfClass("Humanoid")
    local hrp=character:FindFirstChild("HumanoidRootPart")

    if hum then
        attachMorphAttributeObserver(
            hum,
            "LocalHumanoid",
            S.CharacterConnections
        )
    end

    if hrp then
        attachMorphAttributeObserver(
            hrp,
            "LocalHumanoidRootPart",
            S.CharacterConnections
        )
    end

    connect(character.DescendantAdded,function(inst)
        if not S.Running then return end

        if inst.Name=="RootPart"
        or inst:IsA("WeldConstraint")
        or inst:IsA("Weld")
        or inst:IsA("Motor6D")
        or inst:IsA("Bone")
        or inst:IsA("MeshPart")
        or inst:IsA("Animation")
        or inst:IsA("Animator")
        or inst:IsA("AnimationController")
        or inst:IsA("HumanoidDescription")
        or inst:IsA("ValueBase")
        then
            S.Counters.objectAdded+=1

            attachMorphAttributeObserver(
                inst,
                "LocalDescendant:"..inst.Name,
                S.CharacterConnections
            )

            appendRecord({
                recordType="character_descendant_added",
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
                parent=inst.Parent and safePath(inst.Parent) or nil,
                attributes=safeAttrs(inst),
                detail=
                    inst:IsA("MeshPart")
                    and {
                        meshId=inst.MeshId,
                        textureId=inst.TextureID,
                        size=serialize(inst.Size),
                    }
                    or (
                        inst:IsA("Animation")
                        and {animationId=inst.AnimationId}
                        or nil
                    ),
            })
        end

        connect(inst.AttributeChanged,function(attribute)
            if not S.Running then return end

            local hit,kw=keywordMatch(attribute.." "..inst.Name.." "..safePath(inst))

            if hit then
                local ok,val=pcall(function() return inst:GetAttribute(attribute) end)

                S.Counters.attributeChanged+=1

                appendRecord({
                    recordType="character_attribute_changed",
                    className=inst.ClassName,
                    name=inst.Name,
                    path=safePath(inst),
                    attribute=attribute,
                    keyword=kw,
                    value=ok and serialize(val) or "<read_error>",
                })
            end
        end,S.CharacterConnections)

        if inst:IsA("ValueBase") then
            connect(inst.Changed,function(v)
                if not S.Running then return end

                local hit=keywordMatch(inst.Name.." "..safePath(inst))
                if hit then
                    S.Counters.valueChanged+=1
                    appendRecord({
                        recordType="character_value_changed",
                        className=inst.ClassName,
                        name=inst.Name,
                        path=safePath(inst),
                        value=serialize(v),
                    })
                end
            end,S.CharacterConnections)
        end
    end,S.CharacterConnections)

    connect(character.DescendantRemoving,function(inst)
        if not S.Running then return end

        if inst:IsA("WeldConstraint")
        or inst:IsA("Weld")
        or inst:IsA("Motor6D")
        or inst:IsA("Bone")
        or inst:IsA("MeshPart")
        or inst:IsA("Animation")
        or inst:IsA("Animator")
        or inst:IsA("AnimationController")
        or inst:IsA("HumanoidDescription")
        then
            S.Counters.objectRemoved+=1

            appendRecord({
                recordType="character_descendant_removing",
                className=inst.ClassName,
                name=inst.Name,
                path=safePath(inst),
            })
        end
    end,S.CharacterConnections)
end

local function attachCharacterChangeWatchers()
    attachCharacterObjectWatchers(LP.Character)

    connect(LP:GetPropertyChangedSignal("Character"),function()
        if not S.Running then return end

        local old=S.LastCharacter
        local new=LP.Character

        S.Counters.characterChanged+=1

        appendRecord({
            recordType="player_character_property_changed",
            oldCharacter=describeCharacter(old,true),
            newCharacter=describeCharacter(new,true),
        })

        S.LastCharacter=new
        S.LastCharacterName=new and new.Name or nil

        attachCharacterObjectWatchers(new)

        startCaptureWindow(
            "Player.Character_changed",
            {
                old=old and safePath(old) or nil,
                new=new and safePath(new) or nil,
            }
        )
    end)

    connect(LP.CharacterAdded,function(character)
        if not S.Running then return end

        appendRecord({
            recordType="player_character_added",
            character=describeCharacter(character,true),
        })
    end)
end

--==============================================================--
-- START / STOP
--==============================================================--

local function startTrace()
    if S.Running then return end

    S.Running=true
    S.Armed=true
    S.LastCharacter=LP.Character
    S.LastCharacterName=LP.Character and LP.Character.Name or nil

    appendRecord({
        recordType="morph_success_trace_start",
        preWindow=CONFIG.PRE_WINDOW_SECONDS,
        postWindow=CONFIG.POST_WINDOW_SECONDS,
        sampleInterval=CONFIG.SAMPLE_INTERVAL,
        characterBaseline=describeCharacter(LP.Character,true),
        passiveOnlyExceptTargetedRequestObserver=true,
        targetedRequestHook=true,
        originalCallFirst=true,
        deferredPostCallLogging=true,
        zeroRemoteCalls=true,
        purpose="capture exact RequestMorph args while preserving the legitimate native call order",
    })

    discoverMorphNames()
    attachIncomingRemoteListeners()
    attachCharacterChangeWatchers()
    attachMorphAttributeObserver(
        LP,
        "LocalPlayer",
        S.Connections
    )
    attachOriginalMorphUiObserver()

    local hookOK=
        installTargetedRequestHook()

    appendRecord({
        recordType="request_capture_mode",
        hookOK=hookOK,
        remote=
            S.RequestMorphRemote
            and safePath(S.RequestMorphRemote)
            or nil,
    })

    task.spawn(function()
        while S.Running do
            pushPreSample()
            task.wait(CONFIG.SAMPLE_INTERVAL)
        end
    end)

    if S.UI.Status then
        S.UI.Status.Text=
            S.RequestHookAvailable
            and "OBSERVANDO • RequestMorph capturado pós-call • transforme normalmente"
            or "OBSERVANDO PASSIVO • hook RequestMorph indisponível"
    end
end

local function stopTrace()
    if not S.Running then return end

    appendRecord({
        recordType="morph_success_trace_stop",
        counters=serialize(S.Counters),
        characterFinal=describeCharacter(LP.Character,true),
    })

    S.Running=false
    S.Armed=false
    S.ActiveWindow=nil

    disconnectBucket(S.Connections)
    disconnectBucket(S.CharacterConnections)

    removeTargetedRequestHook()

    if S.UI.Status then
        S.UI.Status.Text="Trace encerrado • dados preservados"
    end
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
        local ok,response=pcall(REQUEST,options)

        if ok and type(response)=="table" then
            local status=tonumber(
                response.StatusCode
                or response.Status
                or response.status
            )

            local body=response.Body or response.body or ""
            local success=response.Success

            if success==nil and status then
                success=status>=200 and status<300
            end

            if success==true then
                return true,status,body
            end

            lastErr="HTTP "..tostring(status).." "..tostring(body)
        else
            lastErr=tostring(response)
        end

        task.wait(CONFIG.HTTP_RETRY_BASE*attempt)
    end

    return false,nil,lastErr
end

local function postJson(url,data)
    local ok,_,body=requestRaw({
        Url=url,
        Method="POST",
        Headers={["Content-Type"]="application/json"},
        Body=encode(data),
    })

    if not ok then
        return false,nil,body
    end

    local dOK,d=pcall(HttpService.JSONDecode,HttpService,body)
    return true,(dOK and d or {raw=body}),nil
end

local function buildChunks()
    local chunks={}
    local current={}
    local bytes=2

    local function flush()
        if #current==0 then return end

        table.insert(chunks,{
            objects=current,
            bytes=math.max(2,bytes-1),
        })

        current={}
        bytes=2
    end

    local header={
        recordType="mapping_header",
        scanner=CONFIG.VERSION,
        placeId=game.PlaceId,
        gameId=game.GameId,
        placeVersion=game.PlaceVersion,
        focus="legitimate_morph_success_replication",
        preWindowSeconds=CONFIG.PRE_WINDOW_SECONDS,
        postWindowSeconds=CONFIG.POST_WINDOW_SECONDS,
        records=S.RecordCount,
        archiveBytes=S.ArchiveBytes,
        passiveOnlyExceptTargetedRequestObserver=true,
        targetedRequestHook=true,
        originalCallFirst=true,
        deferredPostCallLogging=true,
        zeroRemoteCalls=true,
    }

    local all={header}
    for _,r in ipairs(S.Records) do table.insert(all,r) end

    for _,obj in ipairs(all) do
        local e=encode(obj)
        local add=#e+1

        if #current>0 and bytes+add>CONFIG.CHUNK_TARGET_BYTES then
            flush()
        end

        table.insert(current,obj)
        bytes+=add
    end

    flush()
    return chunks
end

local function uploadAll()
    if S.Upload.Running or S.RecordCount<=0 then return end

    if S.Running then
        stopTrace()
    end

    if not REQUEST then
        S.Upload.LastError="request indisponível"
        if S.UI.Status then S.UI.Status.Text="Executor sem request/http_request" end
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
    for _,c in ipairs(chunks) do S.Upload.TotalBytes+=c.bytes end

    local stamp=os.date("!%Y%m%d_%H%M%S")

    local sOK,sData,sErr=postJson(
        CONFIG.UPLOAD_BASE.."/start",
        {
            filename=string.format(
                "Cafeina_MorphRequestV7_%s_%s.json",
                tostring(game.PlaceId),
                stamp
            ),
            source=CONFIG.VERSION,
            metadata={
                scanner=CONFIG.VERSION,
                placeId=game.PlaceId,
                gameId=game.GameId,
                placeVersion=game.PlaceVersion,
                focus="successful_legit_morph",
                records=S.RecordCount,
                archiveBytes=S.ArchiveBytes,
                persistent=S.Persistent,
            },
        }
    )

    if not sOK then
        S.Upload.Running=false
        S.Upload.LastError=sErr
        return
    end

    S.Upload.UploadId=sData.uploadId or sData.id or sData.upload_id

    if not S.Upload.UploadId then
        S.Upload.Running=false
        S.Upload.LastError="uploadId ausente"
        return
    end

    for i,c in ipairs(chunks) do
        S.Upload.CurrentChunk=i

        local ok,_,err=postJson(
            CONFIG.UPLOAD_BASE.."/chunk",
            {
                uploadId=S.Upload.UploadId,
                index=i,
                objects=c.objects,
            }
        )

        if not ok then
            S.Upload.Running=false
            S.Upload.LastError=err
            return
        end

        S.Upload.BytesSent+=c.bytes
        task.wait()
    end

    local fOK,fData,fErr=postJson(
        CONFIG.UPLOAD_BASE.."/finish",
        {
            uploadId=S.Upload.UploadId,
            totalChunks=#chunks,
            totalBytes=S.Upload.TotalBytes,
            records=S.RecordCount,
        }
    )

    if not fOK then
        S.Upload.Running=false
        S.Upload.LastError=fErr
        return
    end

    local confirmed=
        fData.confirmed==true
        or fData.success==true
        or fData.ok==true

    if not confirmed then
        S.Upload.Running=false
        S.Upload.LastError="sem confirmação"
        return
    end

    S.Upload.LastURL=tostring(
        fData.url
        or fData.link
        or fData.fileUrl
        or ""
    )

    S.Upload.BytesSent=S.Upload.TotalBytes
    S.Upload.Running=false

    clearArchive()
end

--==============================================================--
-- UI
--==============================================================--

local COLORS={
    BG=Color3.fromRGB(8,8,10),
    STROKE=Color3.fromRGB(46,46,53),
    BUTTON=Color3.fromRGB(31,31,37),
    ACTIVE=Color3.fromRGB(40,105,62),
    RED=Color3.fromRGB(155,45,51),
    GREEN=Color3.fromRGB(24,190,72),
    TEXT=Color3.fromRGB(245,245,247),
    MUTED=Color3.fromRGB(157,157,168),
}

local guiParent=CoreGui

if type(gethui)=="function" then
    local ok,v=pcall(gethui)
    if ok and v then guiParent=v end
end

pcall(function()
    local old=guiParent:FindFirstChild(CONFIG.GUI_NAME)
    if old then old:Destroy() end
end)

local Gui=Instance.new("ScreenGui")
Gui.Name=CONFIG.GUI_NAME
Gui.ResetOnSpawn=false

if not pcall(function() Gui.Parent=guiParent end) then
    Gui.Parent=LP:WaitForChild("PlayerGui")
end

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(326,330)
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
Title.Text="CAFEÍNA • MORPH REQUEST TRACE V7"
Title.TextColor3=COLORS.TEXT
Title.TextSize=13
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Parent=Main

local Sub=Instance.new("TextLabel")
Sub.BackgroundTransparency=1
Sub.Position=UDim2.fromOffset(10,31)
Sub.Size=UDim2.new(1,-20,0,28)
Sub.Font=Enum.Font.Gotham
Sub.Text="REQUEST POST-CALL • 2s ANTES • 5s DEPOIS"
Sub.TextColor3=COLORS.MUTED
Sub.TextSize=8
Sub.TextXAlignment=Enum.TextXAlignment.Left
Sub.Parent=Main

local Start=Instance.new("TextButton")
Start.Position=UDim2.fromOffset(10,65)
Start.Size=UDim2.new(1,-20,0,46)
Start.BackgroundColor3=COLORS.BUTTON
Start.BorderSizePixel=0
Start.Font=Enum.Font.GothamBold
Start.Text="INICIAR OBSERVAÇÃO"
Start.TextColor3=COLORS.TEXT
Start.TextSize=11
Start.AutoButtonColor=false
Start.Parent=Main

local sc=Instance.new("UICorner")
sc.CornerRadius=UDim.new(0,8)
sc.Parent=Start

local Status=Instance.new("TextLabel")
Status.BackgroundTransparency=1
Status.Position=UDim2.fromOffset(10,120)
Status.Size=UDim2.new(1,-20,0,44)
Status.Font=Enum.Font.Gotham
Status.Text="Pronto • transforme pelo menu original do jogo"
Status.TextColor3=COLORS.TEXT
Status.TextSize=9
Status.TextWrapped=true
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Parent=Main
S.UI.Status=Status

local Data=Instance.new("TextLabel")
Data.BackgroundTransparency=1
Data.Position=UDim2.fromOffset(10,169)
Data.Size=UDim2.new(1,-20,0,18)
Data.Font=Enum.Font.Gotham
Data.Text="Arquivado: 0.00 MB • 0 registros"
Data.TextColor3=COLORS.MUTED
Data.TextSize=8
Data.TextXAlignment=Enum.TextXAlignment.Left
Data.Parent=Main

local Counts=Instance.new("TextLabel")
Counts.BackgroundTransparency=1
Counts.Position=UDim2.fromOffset(10,189)
Counts.Size=UDim2.new(1,-20,0,18)
Counts.Font=Enum.Font.Gotham
Counts.Text="Request 0 • Applied 0 • Character 0"
Counts.TextColor3=COLORS.MUTED
Counts.TextSize=8
Counts.TextXAlignment=Enum.TextXAlignment.Left
Counts.Parent=Main

local Send=Instance.new("TextButton")
Send.Position=UDim2.fromOffset(10,216)
Send.Size=UDim2.new(1,-20,0,42)
Send.BackgroundColor3=COLORS.BUTTON
Send.BorderSizePixel=0
Send.Font=Enum.Font.GothamBold
Send.Text="SEM DADOS"
Send.TextColor3=COLORS.TEXT
Send.TextSize=10
Send.AutoButtonColor=false
Send.Parent=Main

local sendc=Instance.new("UICorner")
sendc.CornerRadius=UDim.new(0,8)
sendc.Parent=Send

local Upload=Instance.new("TextLabel")
Upload.BackgroundTransparency=1
Upload.Position=UDim2.fromOffset(10,264)
Upload.Size=UDim2.new(1,-20,0,18)
Upload.Font=Enum.Font.Gotham
Upload.Text="Enviado: 0.00 MB"
Upload.TextColor3=COLORS.MUTED
Upload.TextSize=8
Upload.TextXAlignment=Enum.TextXAlignment.Left
Upload.Parent=Main

local Bar=Instance.new("Frame")
Bar.Position=UDim2.fromOffset(10,292)
Bar.Size=UDim2.new(1,-20,0,11)
Bar.BackgroundColor3=Color3.fromRGB(25,25,30)
Bar.BorderSizePixel=0
Bar.ClipsDescendants=true
Bar.Parent=Main

local bc=Instance.new("UICorner")
bc.CornerRadius=UDim.new(1,0)
bc.Parent=Bar

local Fill=Instance.new("Frame")
Fill.Size=UDim2.new(0,0,1,0)
Fill.BackgroundColor3=COLORS.GREEN
Fill.BorderSizePixel=0
Fill.Parent=Bar

local fc=Instance.new("UICorner")
fc.CornerRadius=UDim.new(1,0)
fc.Parent=Fill

S.UI.Start=Start
S.UI.Data=Data
S.UI.Counts=Counts
S.UI.Send=Send
S.UI.Upload=Upload
S.UI.Fill=Fill

-- drag mobile
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
            Main.Position=UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset+delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset+delta.Y
            )
        end
    end)
end

local function refreshUI()
    if S.Running then
        Start.Text="ENCERRAR OBSERVAÇÃO"
        Start.BackgroundColor3=COLORS.RED
    else
        Start.Text="INICIAR OBSERVAÇÃO"
        Start.BackgroundColor3=COLORS.BUTTON
    end

    Data.Text=string.format(
        "Arquivado: %.2f MB • %d registros",
        mb(S.ArchiveBytes),
        S.RecordCount
    )

    Counts.Text=string.format(
        "Request %d • Applied %d • Character %d",
        S.Counters.requestMorph,
        S.Counters.morphApplied,
        S.Counters.characterChanged
    )

    if S.Upload.Running then
        Send.Text="ENVIANDO..."
        Send.BackgroundColor3=COLORS.RED
    elseif S.RecordCount>0 then
        Send.Text="ENVIAR DADOS"
        Send.BackgroundColor3=COLORS.GREEN
    else
        Send.Text="SEM DADOS"
        Send.BackgroundColor3=COLORS.BUTTON
    end

    if S.Upload.Running then
        Upload.Text=string.format(
            "Enviado: %.2f / %.2f MB • %d/%d",
            mb(S.Upload.BytesSent),
            mb(S.Upload.TotalBytes),
            S.Upload.CurrentChunk,
            S.Upload.TotalChunks
        )
    elseif S.Upload.LastError then
        Upload.Text="Upload: erro • dados preservados"
    elseif S.Upload.LastURL~="" then
        Upload.Text="Upload confirmado ✓"
    else
        Upload.Text=string.format(
            "Enviado: %.2f MB",
            mb(S.Upload.BytesSent)
        )
    end

    local ratio=0
    if S.Upload.TotalBytes>0 then
        ratio=math.clamp(
            S.Upload.BytesSent/S.Upload.TotalBytes,
            0,1
        )
    end
    Fill.Size=UDim2.new(ratio,0,1,0)
end

Start.Activated:Connect(function()
    if S.Upload.Running then return end

    if S.Running then
        stopTrace()
    else
        startTrace()
    end

    refreshUI()
end)

Send.Activated:Connect(function()
    if S.RecordCount<=0 or S.Upload.Running then return end

    task.spawn(function()
        uploadAll()
        refreshUI()
    end)
end)

task.spawn(function()
    while Gui.Parent do
        refreshUI()
        task.wait(0.20)
    end
end)

--==============================================================--
-- STARTUP
--==============================================================--

loadArchive()

if S.RecordCount>0 then
    Status.Text="Dados anteriores recuperados • prontos para enviar"
end

refreshUI()

env.__CAFEINA_MORPH_REQUEST_V7={
    Start=startTrace,
    Stop=stopTrace,
    Upload=uploadAll,

    GetState=function()
        return {
            running=S.Running,
            armed=S.Armed,
            records=S.RecordCount,
            bytes=S.ArchiveBytes,
            activeWindow=S.ActiveWindow,
            counters=S.Counters,
            requestHook={
                installed=S.RequestHookInstalled,
                available=S.RequestHookAvailable,
                remote=
                    S.RequestMorphRemote
                    and safePath(S.RequestMorphRemote)
                    or nil,
                lastRequest=S.LastRequest,
            },
            upload=S.Upload,
        }
    end,

    Destroy=function()
        stopTrace()
        removeTargetedRequestHook()

        pcall(function()
            Gui:Destroy()
        end)
    end,
}

print("[CAFEÍNA] MORPH REQUEST TRACE V7.0 ZERO-HOOK carregado.")
