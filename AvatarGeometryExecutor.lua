--==============================================================--
-- CAFEINA • AVATAR GEOMETRY EXECUTOR
-- Capuccino40 / UserId 765329164
-- Um unico coletor, atualizado in-place.
--
-- Coleta: malhas reais, UV/normais, MeshSize/CFrame, SurfaceAppearance,
-- WrapLayer + WrapTarget (cages fonte e runtime quando acessiveis),
-- skinning/ossos e texturas que faltavam (incluindo roupa classica).
-- Nao coleta cookies, tokens, senhas ou credenciais.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local StarterGui = game:GetService("StarterGui")
local EncodingService = game:GetService("EncodingService")

local USER_ID = 765329164
local USERNAME = "Capuccino40"
local ENV = (getgenv and getgenv()) or _G
local BASE = ENV.GRUPO_LUA_AVATAR_BASE or "https://cafe-na-ia.onrender.com"
local KEY = ENV.GRUPO_LUA_AVATAR_KEY or ""
local CHUNK = 320000
local MAX_RECORDS = 60
local MAX_MESH_VERTS = 120000
local MAX_MESH_FACES = 180000
local MAX_CAGE_VERTS = 16000
local MAX_CAGE_ENTRIES = 96000
local MAX_SESSION_TRIES = 3

local IMAGE_IDS = {
    "18711605978","18711607797","18711609689","18711640761",
    "80293630295826","82530105988237","83091105722329","88515799809882",
    "96472780768407","110426848175524","117649354311112","124249945746431",
    "127025880258976","137182279278426",
    "10930362485","137990545486494","18544009756",
}
local IMAGE_SET = {}
for _, id in ipairs(IMAGE_IDS) do IMAGE_SET[id] = true end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function notify(text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title="Avatar Geometry",Text=text,Duration=duration or 4})
    end)
end

local function v3(v) return {v.X,v.Y,v.Z} end
local function v2(v) return {v.X,v.Y} end
local function c3(v) return {v.R,v.G,v.B} end
local function cframe(v) return {v:GetComponents()} end
local function div3(a,b)
    return Vector3.new(
        math.abs(b.X)>1e-7 and a.X/b.X or 1,
        math.abs(b.Y)>1e-7 and a.Y/b.Y or 1,
        math.abs(b.Z)>1e-7 and a.Z/b.Z or 1
    )
end
local function assetId(v) return tostring(v or ""):match("(%d+)") or "" end

local function plain(v, depth)
    depth = depth or 0
    if depth > 5 then return tostring(v) end
    local t = typeof(v)
    if t == "Vector3" then return v3(v) end
    if t == "Vector2" then return v2(v) end
    if t == "CFrame" then return cframe(v) end
    if t == "Color3" then return c3(v) end
    if type(v) == "number" or type(v) == "string" or type(v) == "boolean" or v == nil then return v end
    if type(v) == "table" then
        local out = {}
        for k,x in pairs(v) do out[k] = plain(x, depth+1) end
        return out
    end
    return tostring(v)
end

local function requestFunction()
    for _, fn in ipairs({ENV.request,ENV.http_request,syn and syn.request,http and http.request,fluxus and fluxus.request}) do
        if type(fn) == "function" then return fn end
    end
end
local request = requestFunction()
if not request then error("Executor sem request/http_request") end

local function headers()
    local h = {["Content-Type"]="application/json",["Accept"]="application/json",["User-Agent"]="Cafeina-AvatarGeometry-Executor/3.0"}
    if KEY ~= "" then h["x-avatar-dump-key"] = KEY end
    return h
end

local function jsonRequest(method, url, data, tries)
    tries = tries or 3
    local body = data and HttpService:JSONEncode(data) or nil
    local last = "falha desconhecida"
    for i=1,tries do
        local ok,res = pcall(function()
            return request({Url=url,Method=method,Headers=headers(),Body=body})
        end)
        if ok and res then
            local status = tonumber(res.StatusCode or res.Status or res.status_code) or 0
            local txt = tostring(res.Body or res.body or "")
            if status >= 200 and status < 300 then
                return safe(function() return HttpService:JSONDecode(txt) end, {}), status, txt
            end
            last = "HTTP "..status.." - "..txt
        else
            last = tostring(res)
        end
        task.wait(0.7*i)
    end
    error(last)
end

local function isoNow()
    return safe(function() return DateTime.now():ToIsoDate() end, os.date("!%Y-%m-%dT%H:%M:%SZ"))
end

local function accessoryOf(part)
    local p = part.Parent
    while p do
        if p:IsA("Accessory") then return p end
        p = p.Parent
    end
end

local function surface(part)
    local s = part:FindFirstChildOfClass("SurfaceAppearance")
    if not s then return nil end
    return {
        colorMap=safe(function() return tostring(s.ColorMap) end,""),
        normalMap=safe(function() return tostring(s.NormalMap) end,""),
        roughnessMap=safe(function() return tostring(s.RoughnessMap) end,""),
        metalnessMap=safe(function() return tostring(s.MetalnessMap) end,""),
        alphaMode=safe(function() return tostring(s.AlphaMode) end,""),
    }
end

local function addCandidate(out, seen, value)
    if value == nil then return end
    local key = tostring(value)
    if key == "" or seen[key] then return end
    seen[key] = true
    out[#out+1] = value
end

local function contentCandidates(primary, fallback)
    local out,seen = {},{}
    for _, value in ipairs({primary,fallback}) do
        if value ~= nil then
            addCandidate(out,seen,value)
            local s = tostring(value)
            local id = s:match("(%d+)")
            if Content then
                if s ~= "" and type(Content.fromUri)=="function" then
                    addCandidate(out,seen,safe(function() return Content.fromUri(s) end,nil))
                end
                if id and type(Content.fromAssetId)=="function" then
                    addCandidate(out,seen,safe(function() return Content.fromAssetId(tonumber(id)) end,nil))
                end
            end
        end
    end
    return out
end

local function editableFrom(primary, fallback)
    local errors = {}
    for _, content in ipairs(contentCandidates(primary,fallback)) do
        local ok,e = pcall(function() return AssetService:CreateEditableMeshAsync(content,{FixedSize=true}) end)
        if ok and e then return e end
        errors[#errors+1] = tostring(e)
    end
    return nil, table.concat(errors," | "):sub(1,1200)
end

local function sourceCage(primary, fallback)
    local e,err = editableFrom(primary,fallback)
    if not e then return {available=false,error=err} end
    local ok,data = pcall(function()
        local vids, fids = e:GetVertices(), e:GetFaces()
        if #vids > MAX_CAGE_VERTS then error("cage vertices acima do limite: "..#vids) end
        if #fids > MAX_CAGE_ENTRIES then error("cage faces acima do limite: "..#fids) end
        local map,pos = {},table.create(#vids)
        for i,id in ipairs(vids) do map[tostring(id)]=i; pos[i]=v3(e:GetPosition(id)) end
        local uvMap,uvs = {},{}
        local function uvIndex(id)
            if id==nil then return 0 end
            local k=tostring(id)
            if uvMap[k] then return uvMap[k] end
            local uv=safe(function() return e:GetUV(id) end,nil)
            if not uv then return 0 end
            local n=#uvs+1; uvMap[k]=n; uvs[n]=v2(uv); return n
        end
        local faces={}
        for _,fid in ipairs(fids) do
            local vs=e:GetFaceVertices(fid)
            if #vs>=3 then
                local f={v={map[tostring(vs[1])] or 0,map[tostring(vs[2])] or 0,map[tostring(vs[3])] or 0}}
                local us=safe(function() return e:GetFaceUVs(fid) end,nil)
                if type(us)=="table" and #us>=3 then f.uv={uvIndex(us[1]),uvIndex(us[2]),uvIndex(us[3])} end
                faces[#faces+1]=f
            end
        end
        return {available=true,vertexCount=#vids,faceCount=#faces,positions=pos,uvs=uvs,faces=faces}
    end)
    pcall(function() e:Destroy() end)
    if ok then return data end
    return {available=false,error=tostring(data):sub(1,1200)}
end

local CAGE_INNER = safe(function() return Enum.CageType.Inner end,nil)
local CAGE_OUTER = safe(function() return Enum.CageType.Outer end,nil)
local function runtimeCage(wrap, cageType)
    if cageType==nil then return {available=false,error="Enum.CageType indisponivel"} end
    local out={available=false}
    local okV,verts=pcall(function() return wrap:GetVertices(cageType) end)
    if okV and type(verts)=="table" then
        if #verts <= MAX_CAGE_VERTS then out.available=true; out.positions=plain(verts); out.vertexCount=#verts
        else out.error="runtime cage grande demais: "..#verts end
    else out.vertexError=tostring(verts):sub(1,500) end
    local okF,faces=pcall(function() return wrap:GetFaces(cageType) end)
    if okF and type(faces)=="table" and #faces<=MAX_CAGE_ENTRIES then out.faces=plain(faces); out.faceEntryCount=#faces
    else out.faceError=tostring(faces):sub(1,500) end
    local okU,uvs=pcall(function() return wrap:GetUVs(cageType) end)
    if okU and type(uvs)=="table" and #uvs<=MAX_CAGE_ENTRIES then out.uvs=plain(uvs); out.uvEntryCount=#uvs
    else out.uvError=tostring(uvs):sub(1,500) end
    return out
end

local function wrapLayer(part)
    local w=part:FindFirstChildOfClass("WrapLayer")
    if not w then return nil end
    local refContent=safe(function() return w.ReferenceMeshContent end,nil)
    local cageContent=safe(function() return w.CageMeshContent end,nil)
    local refId=safe(function() return tostring(w.ReferenceMeshId) end,"")
    local cageId=safe(function() return tostring(w.CageMeshId) end,"")
    return {
        referenceMeshId=refId,cageMeshId=cageId,
        order=safe(function() return w.Order end,nil),puffiness=safe(function() return w.Puffiness end,nil),enabled=safe(function() return w.Enabled end,nil),
        autoSkin=safe(function() return tostring(w.AutoSkin) end,""),bindOffset=safe(function() return cframe(w.BindOffset) end,nil),
        referenceOrigin=safe(function() return cframe(w.ReferenceOrigin) end,nil),referenceOriginWorld=safe(function() return cframe(w.ReferenceOriginWorld) end,nil),
        cageOrigin=safe(function() return cframe(w.CageOrigin) end,nil),cageOriginWorld=safe(function() return cframe(w.CageOriginWorld) end,nil),
        importOrigin=safe(function() return cframe(w.ImportOrigin) end,nil),importOriginWorld=safe(function() return cframe(w.ImportOriginWorld) end,nil),
        cageOffset=safe(function() return v3(w:GetCageOffset()) end,nil),
        sourceInner=sourceCage(refContent,refId),sourceOuter=sourceCage(cageContent,cageId),
        runtimeInner=runtimeCage(w,CAGE_INNER),runtimeOuter=runtimeCage(w,CAGE_OUTER),
    }
end

local function wrapTarget(part)
    local w=part:FindFirstChildOfClass("WrapTarget")
    if not w then return nil end
    local content=safe(function() return w.CageMeshContent end,nil)
    local id=safe(function() return tostring(w.CageMeshId) end,"")
    return {
        cageMeshId=id,stiffness=safe(function() return w.Stiffness end,nil),
        cageOrigin=safe(function() return cframe(w.CageOrigin) end,nil),cageOriginWorld=safe(function() return cframe(w.CageOriginWorld) end,nil),
        importOrigin=safe(function() return cframe(w.ImportOrigin) end,nil),importOriginWorld=safe(function() return cframe(w.ImportOriginWorld) end,nil),
        cageOffset=safe(function() return v3(w:GetCageOffset()) end,nil),
        sourceOuter=sourceCage(content,id),runtimeOuter=runtimeCage(w,CAGE_OUTER),
    }
end

local function skinning(e, vertexIds)
    local boneIds=safe(function() return e:GetBones() end,nil)
    if type(boneIds)~="table" or #boneIds==0 then return nil end
    local map,bones={},{}
    for i,id in ipairs(boneIds) do
        map[tostring(id)]=i
        bones[i]={
            id=tostring(id),name=safe(function() return e:GetBoneName(id) end,""),
            parentId=safe(function() return tostring(e:GetBoneParent(id)) end,"0"),
            bindCFrame=safe(function() return cframe(e:GetBoneCFrame(id)) end,nil),
            virtual=safe(function() return e:GetBoneIsVirtual(id) end,false),
        }
    end
    local weighted={}
    for vi,vid in ipairs(vertexIds) do
        local bs=safe(function() return e:GetVertexBones(vid) end,nil)
        local ws=safe(function() return e:GetVertexBoneWeights(vid) end,nil)
        if type(bs)=="table" and type(ws)=="table" and #bs>0 then
            local bi,w={},{}
            for j=1,math.min(#bs,#ws) do bi[j]=map[tostring(bs[j])] or 0; w[j]=ws[j] end
            weighted[#weighted+1]={vertex=vi,bones=bi,weights=w}
        end
        if vi%2500==0 then task.wait() end
    end
    return {boneCount=#bones,weightedVertexCount=#weighted,bones=bones,weighted=weighted}
end

local function partEditable(part)
    return editableFrom(safe(function() return part.MeshContent end,nil),safe(function() return tostring(part.MeshId) end,""))
end

local function extractMesh(part,index)
    local e,err=partEditable(part)
    if not e then return nil,"CreateEditableMeshAsync: "..tostring(err) end
    local ok,record=pcall(function()
        local vids,fids=e:GetVertices(),e:GetFaces()
        if #vids>MAX_MESH_VERTS then error("vertices acima do limite") end
        if #fids>MAX_MESH_FACES then error("faces acima do limite") end
        local editableSize=e:GetSize()
        local meshSize=safe(function() return part.MeshSize end,editableSize)
        local scale=div3(part.Size,meshSize)
        local map,pos={},table.create(#vids)
        for i,id in ipairs(vids) do map[tostring(id)]=i; pos[i]=v3(e:GetPosition(id)); if i%2500==0 then task.wait() end end
        local uvMap,uvs,nMap,normals={}, {}, {}, {}
        local function U(id)
            if id==nil then return 0 end; local k=tostring(id); if uvMap[k] then return uvMap[k] end
            local u=safe(function() return e:GetUV(id) end,nil); if not u then return 0 end
            local n=#uvs+1; uvMap[k]=n; uvs[n]=v2(u); return n
        end
        local function N(id)
            if id==nil then return 0 end; local k=tostring(id); if nMap[k] then return nMap[k] end
            local nrm=safe(function() return e:GetNormal(id) end,nil); if not nrm then return 0 end
            local n=#normals+1; nMap[k]=n; normals[n]=v3(nrm); return n
        end
        local faces={}
        for i,fid in ipairs(fids) do
            local vs=e:GetFaceVertices(fid)
            if #vs>=3 then
                local f={v={map[tostring(vs[1])] or 0,map[tostring(vs[2])] or 0,map[tostring(vs[3])] or 0}}
                local us=safe(function() return e:GetFaceUVs(fid) end,nil); if type(us)=="table" and #us>=3 then f.uv={U(us[1]),U(us[2]),U(us[3])} end
                local ns=safe(function() return e:GetFaceNormals(fid) end,nil); if type(ns)=="table" and #ns>=3 then f.n={N(ns[1]),N(ns[2]),N(ns[3])} end
                faces[#faces+1]=f
            end
            if i%1500==0 then task.wait() end
        end
        local a=accessoryOf(part)
        local wl=wrapLayer(part)
        return {
            schemaVersion=3,kind="mesh",meshIndex=index,partName=part.Name,fullName=part:GetFullName(),
            meshId=safe(function() return tostring(part.MeshId) end,""),textureId=safe(function() return tostring(part.TextureID) end,""),sourceAssetId=safe(function() return part.SourceAssetId end,-1),
            partSize=v3(part.Size),partCFrame=cframe(part.CFrame),editableSize=v3(editableSize),meshSize=v3(meshSize),renderScale=v3(scale),renderScaleBasis="MeshPart.Size / MeshPart.MeshSize",
            color=c3(part.Color),transparency=part.Transparency,material=tostring(part.Material),doubleSided=safe(function() return part.DoubleSided end,false),
            accessory=a and {name=a.Name,accessoryType=safe(function() return tostring(a.AccessoryType) end,"")} or nil,
            surfaceAppearance=surface(part),wrapLayer=wl,wrapTarget=wrapTarget(part),skinning=wl and skinning(e,vids) or nil,
            vertexCount=#vids,faceCount=#faces,uvCount=#uvs,normalCount=#normals,positions=pos,uvs=uvs,normals=normals,faces=faces,
        }
    end)
    pcall(function() e:Destroy() end)
    if not ok then return nil,tostring(record) end
    return record
end

local function cleanAvatar()
    local model=safe(function() return Players:CreateHumanoidModelFromUserId(USER_ID) end,nil)
    if model then
        model.Name="AvatarGeometry_TemporaryModel"
        model.Parent=workspace
        safe(function() model:PivotTo(CFrame.new(0,50,0)) end,nil)
        local root=model:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then root.Anchored=true end
        task.wait(5)
        return model
    end
    local lp=Players.LocalPlayer
    if lp and lp.UserId==USER_ID then task.wait(2); return lp.Character or lp.CharacterAdded:Wait() end
end

local imageCandidates={}
local function imageCandidate(id, content)
    if not IMAGE_SET[id] or content==nil then return end
    imageCandidates[id]=imageCandidates[id] or {}
    imageCandidates[id][#imageCandidates[id]+1]=content
end
local function collectImages(parts)
    for _,id in ipairs(IMAGE_IDS) do
        if Content then
            if type(Content.fromAssetId)=="function" then imageCandidate(id,safe(function() return Content.fromAssetId(tonumber(id)) end,nil)) end
            if type(Content.fromUri)=="function" then imageCandidate(id,safe(function() return Content.fromUri("rbxassetid://"..id) end,nil)) end
        end
    end
    for _,part in ipairs(parts) do
        local id=assetId(safe(function() return part.TextureID end,"")); if IMAGE_SET[id] then imageCandidate(id,safe(function() return part.TextureContent end,nil)) end
        local s=part:FindFirstChildOfClass("SurfaceAppearance")
        if s then
            for _,pair in ipairs({{"ColorMap","ColorMapContent"},{"NormalMap","NormalMapContent"},{"RoughnessMap","RoughnessMapContent"},{"MetalnessMap","MetalnessMapContent"}}) do
                local mid=assetId(safe(function() return s[pair[1]] end,""))
                if IMAGE_SET[mid] then imageCandidate(mid,safe(function() return s[pair[2]] end,nil)) end
            end
        end
    end
end

local function extractImage(id,index)
    local errors={}
    for _,content in ipairs(imageCandidates[id] or {}) do
        local ok,img=pcall(function() return AssetService:CreateEditableImageAsync(content) end)
        if ok and img then
            local ok2,rec=pcall(function()
                local size=img.Size; local w,h=math.floor(size.X+0.5),math.floor(size.Y+0.5)
                if w<1 or h<1 or w>4096 or h>4096 then error("dimensao invalida") end
                local pixels=img:ReadPixelsBuffer(Vector2.zero,Vector2.new(w,h))
                local z=EncodingService:CompressBuffer(pixels,Enum.CompressionAlgorithm.Zstd,9)
                local b64=EncodingService:Base64Encode(z)
                return {schemaVersion=3,kind="image",meshIndex=index,partName="__image_"..id,meshId="",assetId=id,width=w,height=h,pixelFormat="RGBA8",origin="top-left",compression="zstd",uncompressedBytes=w*h*4,compressedBytes=buffer.len(z),dataBase64=buffer.tostring(b64),positions={},faces={},uvs={},normals={}}
            end)
            pcall(function() img:Destroy() end)
            if ok2 then return rec end
            errors[#errors+1]=tostring(rec)
        else errors[#errors+1]=tostring(img) end
    end
    return nil,table.concat(errors," | "):sub(1,1000)
end

local function uploadRecord(uploadId,index,record)
    local text=HttpService:JSONEncode(record)
    local total=math.max(1,math.ceil(#text/CHUNK))
    for ci=1,total do
        jsonRequest("POST",BASE.."/api/avatar-geometry/"..uploadId.."/chunk",{meshIndex=index,chunkIndex=ci,totalChunks=total,partName=record.partName or "",meshId=record.meshId or "",data=text:sub((ci-1)*CHUNK+1,math.min(#text,ci*CHUNK))},4)
        if ci%3==0 then task.wait() end
    end
    return #text
end
local function openSession(n)
    local r=jsonRequest("POST",BASE.."/api/avatar-geometry/start",{userId=tostring(USER_ID),username=USERNAME,capturedAt=isoNow(),expectedMeshes=n},4)
    if type(r.uploadId)~="string" or r.uploadId=="" then error("Servidor sem uploadId") end
    return r.uploadId
end
local function send(records, failed)
    local last
    for attempt=1,MAX_SESSION_TRIES do
        local ok,res=pcall(function()
            local id=openSession(#records); local bytes=0
            for i,r in ipairs(records) do
                notify(r.kind=="image" and ("Enviando imagem "..r.assetId) or ("Enviando "..i.."/"..#records..": "..r.partName),2)
                bytes=bytes+uploadRecord(id,i,r); task.wait()
            end
            local finish=jsonRequest("POST",BASE.."/api/avatar-geometry/"..id.."/finish",{failed=failed},4)
            return {uploadId=id,bytes=bytes,finish=finish,attempt=attempt}
        end)
        if ok then return res end
        last=tostring(res); if attempt<MAX_SESSION_TRIES then notify("Sessao caiu. Reabrindo...",4); task.wait(1.5*attempt) end
    end
    error(last or "Falha de upload")
end

local function main()
    notify("Preparando malhas, cages, skinning e texturas...",5)
    local char=cleanAvatar(); if not char then error("Nao foi possivel criar o avatar") end
    local parts={}
    for _,o in ipairs(char:GetDescendants()) do if o:IsA("MeshPart") then parts[#parts+1]=o end end
    if #parts>MAX_RECORDS then error("MeshParts acima do limite") end
    collectImages(parts)
    local records,failed={},{}
    for i,p in ipairs(parts) do
        notify(string.format("Extraindo malha %d/%d: %s",i,#parts,p.Name),2)
        local r,e=extractMesh(p,i)
        if r then records[#records+1]=r else failed[#failed+1]={meshIndex=i,partName=p.Name,meshId=safe(function() return tostring(p.MeshId) end,""),error=tostring(e):sub(1,800)} end
        task.wait()
    end
    local imageFails={}
    for _,id in ipairs(IMAGE_IDS) do
        if #records>=MAX_RECORDS then break end
        notify("Tentando textura "..id,2)
        local r,e=extractImage(id,#records+1)
        if r then records[#records+1]=r else imageFails[#imageFails+1]={assetId=id,error=tostring(e):sub(1,700)} end
        task.wait()
    end
    local layers,targets,cages,skinned=0,0,0,0
    for _,r in ipairs(records) do if r.kind=="mesh" then
        if r.wrapLayer then layers=layers+1; if r.wrapLayer.runtimeInner.available then cages=cages+1 end; if r.wrapLayer.runtimeOuter.available then cages=cages+1 end end
        if r.wrapTarget then targets=targets+1; if r.wrapTarget.runtimeOuter.available then cages=cages+1 end end
        if r.skinning and r.skinning.weightedVertexCount>0 then skinned=skinned+1 end
    end end
    notify(string.format("Extraido: %d malhas, %d imagens, %d cages runtime. Enviando...",#parts,#records-#parts,cages),5)
    local sent=send(records,failed)
    local summary={userId=USER_ID,extractedMeshes=#parts-#failed,geometryFailed=#failed,extractedImages=#records-(#parts-#failed),imageFailed=#imageFails,imageFailures=imageFails,wrapLayerCount=layers,wrapTargetCount=targets,runtimeCageCount=cages,skinnedMeshCount=skinned,totalRecords=#records,approximateUploadedJsonBytes=sent.bytes,uploadId=sent.uploadId,sessionAttempt=sent.attempt,server=sent.finish}
    if type(writefile)=="function" then safe(function() writefile("Capuccino40_AvatarGeometry_Result.json",HttpService:JSONEncode(summary)) end,nil) end
    notify(string.format("Concluido: %d malhas, %d imagens, %d cages; falhas de imagem: %d.",summary.extractedMeshes,summary.extractedImages,cages,#imageFails),10)
    print("[Avatar Geometry]",HttpService:JSONEncode(summary))
    return summary
end
local ok,result=pcall(main)
if not ok then notify("Falhou: "..tostring(result),10); warn("[Avatar Geometry]",result); return nil end
return result
