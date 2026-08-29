--[[
CAFEÍNA • IGNORE WALLS RESEARCH V4
Cliente contínuo • coleta passiva • upload em chunks

Foco:
- arquitetura de raycast/cast/pierce
- atributos de armas, munição e reload
- módulos relevantes e assinaturas via debug.info
- remotes relacionados (somente catalogados)
- geometria/partes encontradas na direção da câmera
- materiais, CanQuery, CanCollide, CollisionGroup
- efeitos de tiro/impacto
- correlação com redução de munição

NÃO executa FireServer/InvokeServer.
NÃO altera armas/mapa.
Raycasts próprios são apenas observacionais.

Upload:
https://cafe-na-ia.onrender.com
/upload/start -> /upload/chunk -> /upload/finish
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CONFIG = {
    Scanner = "CAFEINA_IGNORE_WALLS_RESEARCH_V4",
    Version = "4.0",
    SchemaVersion = 5,

    BaseURL = "https://cafe-na-ia.onrender.com",
    UploadToken = "",

    MaxRecords = 400000,
    MaxApproxBytes = 150 * 1024 * 1024,
    UploadChunkTargetBytes = 1.4 * 1024 * 1024,
    UploadRetries = 3,

    FastInterval = 0.15,
    SlowInterval = 1.0,
    GeometryInterval = 0.30,
    UIInterval = 0.15,

    ObservationRayLength = 2500,
    ObservationMaxHits = 10,
    ObservationAdvance = 0.10,

    MaxModuleDepth = 7,
    MaxTableEntries = 350,

    ModuleTargets = {
        castrays = true,
        getraydirections = true,
        canpierce = true,
        candamagetarget = true,
        canplayerdamagetarget = true,
        caster = true,
        fastcastredux = true,
        activecast = true,
        blastercontroller = true,
        blasterextension = true,
        shotreplication = true,
        soundreplication = true,
        serialization = true,
        constants = true,
    },

    Terms = {
        "ray","cast","pierce","penetr","wall",
        "shoot","shot","bullet","projectile",
        "impact","hit","damage","muzzle","barrel",
        "beam","trail","tracer","reload","ammo",
        "weapon","blaster","fastcast",
    },
}

local State = {
    Running = false,
    Interrupted = false,
    Uploading = false,
    BaselineDone = false,
    SiteChecked = false,
    SiteOK = false,
    SiteMessage = "não testado",

    StartClock = 0,
    Records = {},
    ApproxBytes = 0,
    Passes = 0,

    LastFast = 0,
    LastSlow = 0,
    LastGeometry = 0,
    LastShotClock = 0,

    CurrentTool = nil,
    LastAmmo = nil,
    LastReloading = nil,

    Shots = 0,
    GeometryScans = 0,
    Modules = 0,
    Functions = 0,
    Remotes = 0,
    Effects = 0,
    Errors = 0,

    ToolConnections = {},
    GlobalConnections = {},
    LastUploadLink = nil,
}

local function clock() return os.clock() end
local function elapsed()
    if State.StartClock == 0 then return 0 end
    return clock() - State.StartClock
end

local function safeString(v)
    local ok, out = pcall(tostring, v)
    return ok and out or "<tostring-error>"
end

local function fullPath(obj)
    if not obj then return nil end
    local ok, out = pcall(function() return obj:GetFullName() end)
    return ok and out or obj.Name
end

local function bytesText(bytes)
    if bytes < 1024 then return tostring(bytes).." B" end
    if bytes < 1024*1024 then return string.format("%.1f KB", bytes/1024) end
    return string.format("%.2f MB", bytes/1024/1024)
end

local function serialize(v)
    local t = typeof(v)
    if t == "Vector3" then
        return {type="Vector3",x=v.X,y=v.Y,z=v.Z}
    elseif t == "Vector2" then
        return {type="Vector2",x=v.X,y=v.Y}
    elseif t == "CFrame" then
        return {
            type="CFrame",
            position={x=v.Position.X,y=v.Position.Y,z=v.Position.Z},
            look={x=v.LookVector.X,y=v.LookVector.Y,z=v.LookVector.Z},
        }
    elseif t == "Color3" then
        return {type="Color3",r=v.R,g=v.G,b=v.B}
    elseif t == "Instance" then
        return {type="Instance",class=v.ClassName,path=fullPath(v)}
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "number" or t == "string" or t == "boolean" or v == nil then
        return v
    end
    return safeString(v)
end

local function getAttributes(obj)
    local out = {}
    local ok, attrs = pcall(function() return obj:GetAttributes() end)
    if not ok then return out end
    for k,v in pairs(attrs) do out[k] = serialize(v) end
    return out
end

local function approxRecordBytes(record)
    local n = 24
    for k,v in pairs(record) do
        n += #safeString(k) + #safeString(v) + 8
    end
    return n
end

local function addRecord(record)
    if not State.Running or State.Interrupted then return false end
    if #State.Records >= CONFIG.MaxRecords then
        State.Interrupted = true
        return false
    end
    record.time = elapsed()
    local size = approxRecordBytes(record)
    if State.ApproxBytes + size >= CONFIG.MaxApproxBytes then
        State.Interrupted = true
        return false
    end
    State.ApproxBytes += size
    State.Records[#State.Records+1] = record
    return true
end

local function interesting(name)
    local lower = string.lower(tostring(name or ""))
    for _,term in ipairs(CONFIG.Terms) do
        if string.find(lower, term, 1, true) then return true, term end
    end
    return false, nil
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getEquippedTool()
    local char = getCharacter()
    if not char then return nil end
    for _,child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then return child end
    end
    return nil
end

local function findMuzzle(tool)
    if not tool then return nil end
    local names = {"Muzzle","MuzzleAttachment","FirePoint","FireAttachment","Barrel","GunMuzzle"}
    for _,name in ipairs(names) do
        local found = tool:FindFirstChild(name, true)
        if found then return found end
    end
    return nil
end

local function worldCFrame(obj)
    if not obj then return nil end
    if obj:IsA("Attachment") then return obj.WorldCFrame end
    if obj:IsA("BasePart") then return obj.CFrame end
    return nil
end

local function cameraInfo()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    return {cframe=serialize(cam.CFrame),fov=cam.FieldOfView,cameraType=cam.CameraType.Name}
end

local function partInfo(part)
    if not part or not part:IsA("BasePart") then return nil end
    return {
        name=part.Name,
        path=fullPath(part),
        class=part.ClassName,
        material=tostring(part.Material),
        transparency=part.Transparency,
        canCollide=part.CanCollide,
        canTouch=part.CanTouch,
        canQuery=part.CanQuery,
        collisionGroup=part.CollisionGroup,
        anchored=part.Anchored,
        size=serialize(part.Size),
        position=serialize(part.Position),
        attributes=getAttributes(part),
    }
end

local function recentShot(window)
    if State.LastShotClock == 0 then return false end
    return (clock() - State.LastShotClock) <= (window or 0.65)
end

local function markShot(tool, oldAmmo, newAmmo, reason)
    State.Shots += 1
    State.LastShotClock = clock()
    local muzzle = findMuzzle(tool)
    local mcf = worldCFrame(muzzle)
    addRecord({
        kind="shot_candidate",
        shotId=State.Shots,
        reason=reason,
        weapon=tool and tool.Name or nil,
        oldAmmo=oldAmmo,
        newAmmo=newAmmo,
        weaponAttributes=tool and getAttributes(tool) or nil,
        muzzle=muzzle and {
            name=muzzle.Name,
            class=muzzle.ClassName,
            path=fullPath(muzzle),
            cframe=mcf and serialize(mcf) or nil,
        } or nil,
        camera=cameraInfo(),
    })
end

local function disconnectList(list)
    for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end
    table.clear(list)
end

local function recordEffect(obj, action)
    local matched, term = interesting(obj.Name)
    local classRelevant =
        obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Attachment") or
        obj:IsA("ParticleEmitter") or obj:IsA("Sound") or obj:IsA("BasePart")
    if not matched and not (classRelevant and recentShot()) then return end

    State.Effects += 1
    addRecord({
        kind="effect",
        action=action,
        id=State.Effects,
        name=obj.Name,
        class=obj.ClassName,
        path=fullPath(obj),
        match=term,
        nearShot=recentShot(),
        part=obj:IsA("BasePart") and partInfo(obj) or nil,
        attributes=getAttributes(obj),
    })
end

local function watchTool(tool)
    disconnectList(State.ToolConnections)
    State.CurrentTool = tool
    State.LastAmmo = nil
    State.LastReloading = nil
    if not tool then
        addRecord({kind="tool_unequipped"})
        return
    end

    State.LastAmmo = tool:GetAttribute("_ammo")
    State.LastReloading = tool:GetAttribute("_reloading")

    addRecord({
        kind="tool_equipped",
        name=tool.Name,
        path=fullPath(tool),
        attributes=getAttributes(tool),
    })

    State.ToolConnections[#State.ToolConnections+1] =
        tool.AttributeChanged:Connect(function(name)
            if not State.Running then return end
            local value = tool:GetAttribute(name)
            addRecord({
                kind="weapon_attribute_change",
                weapon=tool.Name,
                attribute=name,
                value=serialize(value),
            })
            if name == "_ammo" then
                local old = State.LastAmmo
                State.LastAmmo = value
                if type(old)=="number" and type(value)=="number" and value < old then
                    markShot(tool, old, value, "attribute_ammo_decrease")
                end
            elseif name == "_reloading" then
                addRecord({
                    kind="reload_state",
                    weapon=tool.Name,
                    old=State.LastReloading,
                    new=value,
                    ammo=tool:GetAttribute("_ammo"),
                })
                State.LastReloading = value
            end
        end)

    State.ToolConnections[#State.ToolConnections+1] =
        tool.DescendantAdded:Connect(function(obj) recordEffect(obj, "tool_added") end)

    State.ToolConnections[#State.ToolConnections+1] =
        tool.DescendantRemoving:Connect(function(obj) recordEffect(obj, "tool_removing") end)
end

local function refreshTool()
    local tool = getEquippedTool()
    if tool ~= State.CurrentTool then watchTool(tool) end
end

local function isRemote(obj)
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then return true end
    local ok, value = pcall(function() return obj:IsA("UnreliableRemoteEvent") end)
    return ok and value
end

local function inspectRemote(obj, reason)
    if not isRemote(obj) then return end
    local matched, term = interesting(obj.Name)
    if not matched then return end
    State.Remotes += 1
    addRecord({
        kind="remote_structure",
        reason=reason,
        id=State.Remotes,
        name=obj.Name,
        class=obj.ClassName,
        path=fullPath(obj),
        match=term,
        attributes=getAttributes(obj),
    })
end

local function inspectFunction(fn, modulePath, exportPath)
    if typeof(fn) ~= "function" then return end
    State.Functions += 1
    local record = {
        kind="function_signature",
        id=State.Functions,
        module=modulePath,
        export=exportPath,
    }

    if type(debug)=="table" and type(debug.info)=="function" then
        pcall(function() record.debugName = debug.info(fn, "n") end)
        pcall(function()
            local count,vararg = debug.info(fn, "a")
            record.numParams = count
            record.isVararg = vararg
        end)
        pcall(function() record.source = debug.info(fn, "s") end)
        pcall(function() record.line = debug.info(fn, "l") end)
    end

    addRecord(record)
end

local function walkExport(value, modulePath, exportPath, seen, depth)
    if depth > CONFIG.MaxModuleDepth or State.Interrupted then return end
    local t = typeof(value)
    if t == "function" then
        inspectFunction(value,modulePath,exportPath)
        return
    end
    if t ~= "table" or seen[value] then return end
    seen[value] = true

    local count = 0
    for key,child in pairs(value) do
        count += 1
        if count > CONFIG.MaxTableEntries then break end
        local childPath = exportPath.."."..safeString(key)
        local matched,term = interesting(key)
        addRecord({
            kind="module_export_member",
            module=modulePath,
            export=childPath,
            valueType=typeof(child),
            interesting=matched,
            match=term,
        })
        walkExport(child,modulePath,childPath,seen,depth+1)
    end
end

local function moduleRelevant(module)
    if not module:IsA("ModuleScript") then return false end
    local lower = string.lower(module.Name)
    if CONFIG.ModuleTargets[lower] then return true end
    local matched = interesting(lower)
    return matched
end

local function inspectModule(module)
    State.Modules += 1
    local path = fullPath(module)
    addRecord({kind="module",id=State.Modules,name=module.Name,path=path})

    local ok, exported = pcall(function() return require(module) end)
    if not ok then
        State.Errors += 1
        addRecord({kind="module_require_error",module=path,error=safeString(exported)})
        return
    end

    addRecord({kind="module_export",module=path,exportType=typeof(exported)})
    if typeof(exported)=="function" then
        inspectFunction(exported,path,module.Name)
    elseif typeof(exported)=="table" then
        walkExport(exported,path,module.Name,{},0)
    end
end

local function observeForwardGeometry()
    local cam = Workspace.CurrentCamera
    if not cam then return end

    State.GeometryScans += 1
    local origin = cam.CFrame.Position
    local direction = cam.CFrame.LookVector
    local remaining = CONFIG.ObservationRayLength
    local excluded = {}

    local char = getCharacter()
    if char then excluded[#excluded+1] = char end

    local hits = {}

    for index=1,CONFIG.ObservationMaxHits do
        if remaining <= 0 then break end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = excluded
        params.IgnoreWater = false

        local result = Workspace:Raycast(origin, direction * remaining, params)
        if not result then break end

        local inst = result.Instance
        local distance = (result.Position-origin).Magnitude

        hits[#hits+1] = {
            index=index,
            instance=inst and partInfo(inst) or nil,
            position=serialize(result.Position),
            normal=serialize(result.Normal),
            material=tostring(result.Material),
            distance=distance,
        }

        if inst then excluded[#excluded+1] = inst end
        origin = result.Position + direction * CONFIG.ObservationAdvance
        remaining -= distance + CONFIG.ObservationAdvance
    end

    addRecord({
        kind="wall_geometry_probe",
        scanId=State.GeometryScans,
        camera=cameraInfo(),
        hitCount=#hits,
        hits=hits,
        nearShot=recentShot(),
    })
end

local function scanCollisionSample()
    local count = 0
    for _,obj in ipairs(Workspace:GetDescendants()) do
        if not State.Running or State.Interrupted then return end
        if obj:IsA("BasePart") then
            local matched = interesting(obj.Name)
            if matched or obj.CanQuery == false or obj.CanCollide == false then
                addRecord({kind="collision_object",data=partInfo(obj)})
                count += 1
                if count >= 1800 then break end
            end
        end
        if count > 0 and count % 100 == 0 then task.wait() end
    end
    addRecord({kind="collision_scan_summary",objects=count})
end

local function baselineScan()
    addRecord({kind="baseline_start"})

    local root = ReplicatedStorage:FindFirstChild("BlasterSystem") or ReplicatedStorage
    local inspected = 0
    for _,obj in ipairs(root:GetDescendants()) do
        if not State.Running or State.Interrupted then return end
        if moduleRelevant(obj) then
            inspectModule(obj)
            inspected += 1
            if inspected % 5 == 0 then task.wait() end
        end
    end

    for _,obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if not State.Running or State.Interrupted then return end
        inspectRemote(obj,"baseline")
    end

    scanCollisionSample()
    State.BaselineDone = true
    addRecord({
        kind="baseline_complete",
        modules=State.Modules,
        functions=State.Functions,
        remotes=State.Remotes,
    })
end

local function fastPass()
    refreshTool()
    local tool = State.CurrentTool
    if not tool then return end
    local ammo = tool:GetAttribute("_ammo")
    if type(State.LastAmmo)=="number" and type(ammo)=="number" and ammo < State.LastAmmo then
        markShot(tool,State.LastAmmo,ammo,"poll_ammo_decrease")
    end
    State.LastAmmo = ammo
end

local function slowPass()
    State.Passes += 1
    local tool = State.CurrentTool
    addRecord({
        kind="pass_summary",
        pass=State.Passes,
        records=#State.Records,
        approxBytes=State.ApproxBytes,
        shots=State.Shots,
        geometryScans=State.GeometryScans,
        weapon=tool and tool.Name or nil,
        weaponAttributes=tool and getAttributes(tool) or nil,
        camera=cameraInfo(),
    })
end

local function installObservers()
    disconnectList(State.GlobalConnections)

    State.GlobalConnections[#State.GlobalConnections+1] =
        Workspace.DescendantAdded:Connect(function(obj)
            recordEffect(obj,"workspace_added")
        end)

    State.GlobalConnections[#State.GlobalConnections+1] =
        ReplicatedStorage.DescendantAdded:Connect(function(obj)
            inspectRemote(obj,"added")
        end)

    State.GlobalConnections[#State.GlobalConnections+1] =
        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            refreshTool()
        end)
end

local function runLoop()
    while State.Running and not State.Interrupted do
        local t = clock()
        if t-State.LastFast >= CONFIG.FastInterval then
            State.LastFast=t
            fastPass()
        end
        if t-State.LastGeometry >= CONFIG.GeometryInterval then
            State.LastGeometry=t
            observeForwardGeometry()
        end
        if t-State.LastSlow >= CONFIG.SlowInterval then
            State.LastSlow=t
            slowPass()
        end
        task.wait(0.03)
    end
end

local function startScanner()
    if State.Running then return end

    State.Running=true
    State.Interrupted=false
    State.BaselineDone=false
    State.StartClock=clock()
    State.Records={}
    State.ApproxBytes=0
    State.Passes=0
    State.Shots=0
    State.GeometryScans=0
    State.Modules=0
    State.Functions=0
    State.Remotes=0
    State.Effects=0
    State.Errors=0
    State.LastShotClock=0
    State.LastFast=0
    State.LastSlow=0
    State.LastGeometry=0

    addRecord({
        kind="session_start",
        scanner=CONFIG.Scanner,
        version=CONFIG.Version,
        placeId=game.PlaceId,
        gameId=game.GameId,
        clientVisibleOnly=true,
        focus="ignore_walls_research",
        safety={
            firesRemotes=false,
            invokesRemoteFunctions=false,
            mutatesGameObjects=false,
            observationalRaycastsOnly=true,
        },
    })

    installObservers()
    refreshTool()
    task.spawn(baselineScan)
    task.spawn(runLoop)
end

local function stopScanner()
    if not State.Running then return end
    addRecord({
        kind="session_end",
        reason="manual_interrupt",
        records=#State.Records,
        passes=State.Passes,
        shots=State.Shots,
        geometryScans=State.GeometryScans,
    })
    State.Running=false
    State.Interrupted=true
    disconnectList(State.ToolConnections)
    disconnectList(State.GlobalConnections)
end

--==============================================================
-- HTTP / SITE CHECK / UPLOAD
--==============================================================

local function getRequestFunction()
    if type(request)=="function" then return request end
    if type(http_request)=="function" then return http_request end
    if syn and type(syn.request)=="function" then return syn.request end
    if http and type(http.request)=="function" then return http.request end
    return nil
end

local function normalizeBase(url)
    return tostring(url or ""):gsub("/+$","")
end

local function responseStatus(r)
    if type(r)~="table" then return 0 end
    return tonumber(r.StatusCode or r.Status or r.status or r.status_code or 0) or 0
end

local function responseBody(r)
    if type(r)~="table" then return "" end
    return tostring(r.Body or r.body or r.Response or r.response or "")
end

local function decodeJSON(text)
    if type(text)~="string" or text=="" then return nil end
    local ok,out=pcall(function() return HttpService:JSONDecode(text) end)
    return ok and out or nil
end

local function httpCall(method,path,body)
    local rf=getRequestFunction()
    if not rf then return false,nil,"HTTP request indisponível" end

    local base=normalizeBase(CONFIG.BaseURL)
    if base=="" then return false,nil,"BaseURL vazia" end

    local headers={["Accept"]="application/json"}
    local encoded=nil

    if body ~= nil then
        if CONFIG.UploadToken ~= "" then body.token=CONFIG.UploadToken end
        headers["Content-Type"]="application/json"
        local ok,out=pcall(function() return HttpService:JSONEncode(body) end)
        if not ok then return false,nil,"JSONEncode: "..safeString(out) end
        encoded=out
    end

    local lastError=nil
    for attempt=1,CONFIG.UploadRetries do
        local ok,res=pcall(function()
            return rf({
                Url=base..path,
                Method=method,
                Headers=headers,
                Body=encoded,
            })
        end)

        if ok then
            local status=responseStatus(res)
            local raw=responseBody(res)
            local decoded=decodeJSON(raw)
            if status>=200 and status<300 then
                return true,decoded or raw,raw
            end
            local msg=type(decoded)=="table" and (decoded.message or decoded.error) or raw
            lastError="HTTP "..tostring(status)..(msg~="" and (" • "..safeString(msg)) or "")
        else
            lastError=safeString(res)
        end
        if attempt<CONFIG.UploadRetries then task.wait(0.8*attempt) end
    end
    return false,nil,lastError or "falha HTTP"
end

local function checkSite()
    State.SiteChecked=true
    local ok,data,err=httpCall("GET","/api/health",nil)
    State.SiteOK=ok
    if ok then
        if type(data)=="table" then
            State.SiteMessage = (data.service or "CAFEINA").." online"
        else
            State.SiteMessage = "site online"
        end
        return true,State.SiteMessage
    end
    State.SiteMessage=safeString(err)
    return false,State.SiteMessage
end

local function encodedSize(value)
    local ok,out=pcall(function() return HttpService:JSONEncode(value) end)
    return ok and #out or math.huge
end

local function makeChunks(records)
    local chunks={}
    local current={}
    local currentBytes=2

    for i,record in ipairs(records) do
        local size=encodedSize(record)+1
        if #current>0 and currentBytes+size>CONFIG.UploadChunkTargetBytes then
            chunks[#chunks+1]=current
            current={}
            currentBytes=2
        end
        current[#current+1]=record
        currentBytes += size
        if i%150==0 then task.wait() end
    end

    if #current>0 then chunks[#chunks+1]=current end
    if #chunks==0 then chunks[1]={} end
    return chunks
end

local Status

local function uploadReport()
    if State.Uploading then return false,"upload em andamento" end
    if State.Running then return false,"interrompa o scan primeiro" end

    State.Uploading=true

    if Status then Status.Text="Verificando site..." end
    local siteOK,siteErr=checkSite()
    if not siteOK then
        State.Uploading=false
        return false,"Health check: "..safeString(siteErr)
    end

    local filename=string.format(
        "Cafeina_IgnoreWalls_%d_%s.json",
        game.PlaceId,
        os.date("%Y%m%d_%H%M%S")
    )

    if Status then Status.Text="Iniciando upload..." end

    local ok,startData,startErr=httpCall("POST","/upload/start",{
        filename=filename,
        source="cafeina-ignore-walls-research-v4",
        metadata={
            scanner=CONFIG.Scanner,
            version=CONFIG.Version,
            area="WallPenetration",
            placeId=game.PlaceId,
            gameId=game.GameId,
            records=#State.Records,
            approxBytes=State.ApproxBytes,
            passes=State.Passes,
            shots=State.Shots,
            geometryScans=State.GeometryScans,
            modules=State.Modules,
            functions=State.Functions,
            remotes=State.Remotes,
            errors=State.Errors,
        },
    })

    if not ok or type(startData)~="table" or not startData.uploadId then
        State.Uploading=false
        return false,"START: "..safeString(startErr or "uploadId ausente")
    end

    local uploadId=startData.uploadId
    local chunks=makeChunks(State.Records)

    for index,objects in ipairs(chunks) do
        if Status then
            local pct=math.floor(index/#chunks*100)
            Status.Text=string.format("Enviando %d/%d • %d%%",index,#chunks,pct)
        end

        local chunkOK,_,chunkErr=httpCall("POST","/upload/chunk",{
            uploadId=uploadId,
            index=index,
            objects=objects,
        })

        if not chunkOK then
            pcall(function()
                httpCall("POST","/upload/cancel",{uploadId=uploadId})
            end)
            State.Uploading=false
            return false,"CHUNK "..index..": "..safeString(chunkErr)
        end

        chunks[index]=nil
        task.wait(0.03)
    end

    if Status then Status.Text="Finalizando upload..." end

    local finishOK,finishData,finishErr=httpCall("POST","/upload/finish",{
        uploadId=uploadId,
        totalChunks=#makeChunks(State.Records),
    })

    if not finishOK or type(finishData)~="table" then
        State.Uploading=false
        return false,"FINISH: "..safeString(finishErr)
    end

    local link=finishData.downloadUrl or finishData.url or finishData.link
    if not link then
        State.Uploading=false
        return false,"Servidor finalizou sem retornar URL"
    end

    State.LastUploadLink=link
    if type(setclipboard)=="function" then pcall(setclipboard,link) end
    State.Uploading=false
    return true,link
end

--==============================================================
-- GUI
--==============================================================

local GUI_NAME="CafeinaIgnoreWallsResearchV4"
local old=PlayerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local Gui=Instance.new("ScreenGui")
Gui.Name=GUI_NAME
Gui.ResetOnSpawn=false
Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
Gui.Parent=PlayerGui

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(330,225)
Main.Position=UDim2.new(0.5,-165,0.40,-112)
Main.BackgroundColor3=Color3.fromRGB(16,17,20)
Main.BorderSizePixel=0
Main.Parent=Gui

local Corner=Instance.new("UICorner")
Corner.CornerRadius=UDim.new(0,12)
Corner.Parent=Main

local Stroke=Instance.new("UIStroke")
Stroke.Color=Color3.fromRGB(58,60,68)
Stroke.Thickness=1
Stroke.Parent=Main

local Header=Instance.new("Frame")
Header.Size=UDim2.new(1,0,0,46)
Header.BackgroundColor3=Color3.fromRGB(21,22,26)
Header.BorderSizePixel=0
Header.Parent=Main

local Title=Instance.new("TextLabel")
Title.Size=UDim2.new(1,-20,0,25)
Title.Position=UDim2.fromOffset(12,5)
Title.BackgroundTransparency=1
Title.Text="CAFEÍNA • WALL RESEARCH"
Title.TextColor3=Color3.fromRGB(245,245,247)
Title.Font=Enum.Font.GothamBold
Title.TextSize=13
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Parent=Header

local Subtitle=Instance.new("TextLabel")
Subtitle.Size=UDim2.new(1,-20,0,15)
Subtitle.Position=UDim2.fromOffset(12,27)
Subtitle.BackgroundTransparency=1
Subtitle.Text="RAYCAST • PIERCE • IGNORE WALLS"
Subtitle.TextColor3=Color3.fromRGB(105,108,118)
Subtitle.Font=Enum.Font.Gotham
Subtitle.TextSize=8
Subtitle.TextXAlignment=Enum.TextXAlignment.Left
Subtitle.Parent=Header

Status=Instance.new("TextLabel")
Status.Size=UDim2.new(1,-20,0,30)
Status.Position=UDim2.fromOffset(10,53)
Status.BackgroundTransparency=1
Status.Text="Verificando site..."
Status.TextColor3=Color3.fromRGB(200,202,210)
Status.Font=Enum.Font.GothamMedium
Status.TextSize=11
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.Parent=Main

local function makeButton(text,x)
    local b=Instance.new("TextButton")
    b.Size=UDim2.fromOffset(98,44)
    b.Position=UDim2.fromOffset(x,89)
    b.BackgroundColor3=Color3.fromRGB(33,34,40)
    b.BorderSizePixel=0
    b.Text=text
    b.TextColor3=Color3.fromRGB(240,240,243)
    b.Font=Enum.Font.GothamBold
    b.TextSize=10
    b.AutoButtonColor=false
    b.Parent=Main
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,8)
    c.Parent=b
    return b
end

local StartButton=makeButton("INICIAR",10)
local StopButton=makeButton("INTERROMPER",116)
local SendButton=makeButton("ENVIAR",222)

local Info=Instance.new("TextLabel")
Info.Size=UDim2.new(1,-20,0,62)
Info.Position=UDim2.fromOffset(10,141)
Info.BackgroundTransparency=1
Info.Text="0 MB • 0 registros"
Info.TextWrapped=true
Info.TextColor3=Color3.fromRGB(135,138,148)
Info.Font=Enum.Font.Gotham
Info.TextSize=10
Info.Parent=Main

local Footer=Instance.new("TextLabel")
Footer.Size=UDim2.new(1,-20,0,15)
Footer.Position=UDim2.fromOffset(10,204)
Footer.BackgroundTransparency=1
Footer.Text="CLIENT-VISIBLE • PASSIVE RESEARCH"
Footer.TextColor3=Color3.fromRGB(85,88,98)
Footer.Font=Enum.Font.Gotham
Footer.TextSize=8
Footer.Parent=Main

StartButton.Activated:Connect(function()
    if State.Running then return end
    Status.Text="Iniciando..."
    startScanner()
end)

StopButton.Activated:Connect(function()
    if not State.Running then return end
    stopScanner()
    Status.Text="Interrompido • pronto para enviar"
end)

SendButton.Activated:Connect(function()
    if State.Running then
        Status.Text="Interrompa antes de enviar"
        return
    end
    if State.Uploading then return end

    task.spawn(function()
        local ok,result=uploadReport()
        if ok then
            Status.Text="Enviado • link copiado"
            print("[CAFEÍNA] Upload:",result)
        else
            Status.Text="Erro no envio"
            warn("[CAFEÍNA UPLOAD]",result)
        end
    end)
end)

task.spawn(function()
    local ok,msg=checkSite()
    Status.Text=ok and ("Site OK • "..msg) or ("Site não confirmado • "..msg)

    while Gui.Parent do
        if State.Running then
            if State.Interrupted then
                Status.Text="Limite atingido • pronto para enviar"
            elseif not State.BaselineDone then
                Status.Text="Analisando cast/raycast/pierce..."
            elseif recentShot() then
                Status.Text="Correlacionando tiro e parede..."
            else
                Status.Text="Monitorando penetração..."
            end
        end

        local tool=State.CurrentTool
        Info.Text=string.format(
            "%s • %d registros • %d passes\nTiros %d • Rays %d • Funções %d\nArma: %s",
            bytesText(State.ApproxBytes),
            #State.Records,
            State.Passes,
            State.Shots,
            State.GeometryScans,
            State.Functions,
            tool and tool.Name or "nenhuma"
        )

        task.wait(CONFIG.UIInterval)
    end
end)

-- Drag mobile/PC
local dragging=false
local dragInput
local dragStart
local startPosition

Header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then

        dragging=true
        dragStart=input.Position
        startPosition=Main.Position

        input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement
        or input.UserInputType==Enum.UserInputType.Touch then
        dragInput=input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging or input~=dragInput then return end
    local delta=input.Position-dragStart
    Main.Position=UDim2.new(
        startPosition.X.Scale,startPosition.X.Offset+delta.X,
        startPosition.Y.Scale,startPosition.Y.Offset+delta.Y
    )
end)

print("[CAFEÍNA] Ignore Walls Research V4 carregado")
print("[CAFEÍNA] Site:",CONFIG.BaseURL)
print("[CAFEÍNA] FireServer/InvokeServer: DESATIVADOS")
