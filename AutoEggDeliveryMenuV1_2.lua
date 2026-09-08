--==============================================================--
-- CAFEINA • AUTO EGG DELIVERY • V1.2
-- Mobile/executor
-- Regra fixa:
-- MELHOR OVO -> COLETA -> CARRY CONFIRMADO -> SAFE
-- -> ENTREGA CONFIRMADA -> SOMENTE ENTAO PROXIMO OVO
--
-- Prioridade de escolha:
-- 1) raridade explicita (Divine > ... > Common)
-- 2) RareAreaEggHighlight / spawn raro
-- 3) bioma mais avancado
-- 4) qualidade visual / tamanho
-- 5) distancia SOMENTE como ultimo desempate
--==============================================================--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

local RARITIES = {
    {name="Divine",    key="divine",    rank=10},
    {name="Eternal",   key="eternal",   rank=9},
    {name="Secret",    key="secret",    rank=8},
    {name="Cosmic",    key="cosmic",    rank=7},
    {name="Mythic",    key="mythic",    rank=6},
    {name="Legendary", key="legendary", rank=5},
    {name="Epic",      key="epic",      rank=4},
    {name="Rare",      key="rare",      rank=3},
    {name="Uncommon",  key="uncommon",  rank=2},
    {name="Common",    key="common",    rank=1},
}

local ZONES = {
    {key="titantemple",    name="Titan Temple",    rank=9},
    {key="cherryblossom",  name="Cherry Blossom",  rank=8},
    {key="cosmic",         name="Cosmic",          rank=7},
    {key="prehistoric",    name="Prehistoric",     rank=6},
    {key="abyssocean",     name="Abyss Ocean",     rank=5},
    {key="volcano",        name="Volcano",         rank=4},
    {key="snow",           name="Snow",            rank=3},
    {key="desert",         name="Desert",          rank=2},
    {key="forest",         name="Forest",          rank=1},
}

pcall(function()
    local old = rawget(ENV, "__CAFEINA_AUTO_EGG_DELIVERY")
    if type(old) == "table" and type(old.Cleanup) == "function" then
        old.Cleanup()
    end
end)

pcall(function()
    local oldGui = rawget(ENV, "__CAFEINA_AUTO_EGG_DELIVERY_GUI")
    if typeof(oldGui) == "Instance" then oldGui:Destroy() end
end)

local S = {
    running=false,
    token=0,
    state="PARADO",
    status="Pronto • prioridade: MELHOR, nao mais perto",
    delivered=0,
    failed=0,
    current=nil,
    currentQuality=nil,
    blacklist=setmetatable({}, {__mode="k"}),
    conns={},
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(S.conns, c)
    return c
end

local function character()
    local c = LP.Character
    if not c then return nil,nil end
    return c, c:FindFirstChild("HumanoidRootPart")
end

local function tp(cf)
    local c,root = character()
    if not c or not root then return false,"root indisponivel" end
    local ok,err = pcall(function() c:PivotTo(cf) end)
    if not ok then ok,err = pcall(function() root.CFrame=cf end) end
    return ok,err
end

local function pivotOf(inst)
    if not inst or not inst.Parent then return nil end
    if inst:IsA("Model") then
        local ok,cf = pcall(function() return inst:GetPivot() end)
        if ok then return cf end
    elseif inst:IsA("BasePart") then
        return inst.CFrame
    end
    return nil
end

local function textRarity(value)
    local text = string.lower(tostring(value or ""))
    if text == "" then return 0,"Unknown" end
    for _,r in ipairs(RARITIES) do
        if text:find(r.key,1,true) then return r.rank,r.name end
    end
    return 0,"Unknown"
end

local function zoneOf(egg)
    local text = string.lower(egg.Name)
    for _,z in ipairs(ZONES) do
        if text:find(z.key,1,true) then return z.rank,z.name end
    end
    if egg.Name:sub(1,13) == "FirstAreaEgg_" then return 1,"Forest" end
    return 0,"Unknown"
end

local function explicitRarityOf(egg)
    local bestRank,bestName = 0,"Unknown"

    local function consider(v)
        local rank,name = textRarity(v)
        if rank > bestRank then bestRank,bestName = rank,name end
    end

    local function inspect(inst)
        local lowName = string.lower(inst.Name)
        -- Esse highlight e um marcador de spawn raro, nao deve ser lido
        -- como tier "Rare". Ele e tratado separadamente abaixo.
        if not lowName:find("rareareaegghighlight",1,true) then
            consider(inst.Name)
        end

        local ok,attrs = pcall(function() return inst:GetAttributes() end)
        if ok and type(attrs)=="table" then
            for k,v in pairs(attrs) do
                local kl = string.lower(tostring(k))
                if kl:find("rarity",1,true) or kl:find("tier",1,true)
                    or kl:find("quality",1,true) or kl:find("grade",1,true) then
                    consider(v)
                end
            end
        end

        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            consider(inst.Text)
        elseif inst:IsA("ProximityPrompt") then
            consider(inst.ObjectText)
            consider(inst.ActionText)
        end
    end

    inspect(egg)
    for _,d in ipairs(egg:GetDescendants()) do
        inspect(d)
        if bestRank >= 10 then break end
    end

    return bestRank,bestName
end

local function hasRareSpawnHighlight(egg)
    for _,d in ipairs(egg:GetDescendants()) do
        if string.lower(d.Name):find("rareareaegghighlight",1,true) then
            return true
        end
    end
    return false
end

local function visualScoreOf(egg)
    local score = 0
    local fx = 0

    for _,d in ipairs(egg:GetDescendants()) do
        if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
            or d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
            fx += 1
        elseif d:IsA("Highlight") then
            fx += 2
        end
    end

    score += math.min(fx,50) * 1000

    local ok,size = pcall(function() return egg:GetExtentsSize() end)
    if ok and typeof(size)=="Vector3" then
        local volume = math.max(0.001, size.X * size.Y * size.Z)
        -- log evita ovo gigante dominar de forma absurda.
        score += math.log(volume + 1) * 100
    end

    return score
end

local function isEggCandidate(inst)
    if not inst or not inst.Parent or not inst:IsA("Model") then return false end
    local slots = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not slots or not inst:IsDescendantOf(slots) then return false end

    local n = inst.Name
    if n:sub(1,15) == "CarriedAreaEgg_" then return false end
    if n:sub(1,8) == "AreaEgg_" then return true end
    if n:sub(1,13) == "FirstAreaEgg_" then return true end
    if inst:GetAttribute("AreaEggUid") ~= nil then return true end
    return false
end

local function qualityLabel(e)
    local parts = {}
    if e.rarityRank > 0 then parts[#parts+1] = e.rarity end
    if e.rareSpawn then parts[#parts+1] = "RARE SPAWN" end
    if e.zoneRank > 0 then parts[#parts+1] = e.zone end
    if #parts == 0 then parts[1] = "qualidade desconhecida" end
    return table.concat(parts," • ")
end

local function getEggCandidates()
    local slots = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not slots then return {} end

    local now = os.clock()
    local out = {}
    local _,root = character()
    local origin = root and root.Position or SAFE_CF.Position

    for _,d in ipairs(slots:GetDescendants()) do
        if isEggCandidate(d) then
            local blockedUntil = S.blacklist[d]
            if not blockedUntil or blockedUntil <= now then
                local cf = pivotOf(d)
                if cf then
                    local rarityRank,rarity = explicitRarityOf(d)
                    local zoneRank,zone = zoneOf(d)
                    local rareSpawn = hasRareSpawnHighlight(d)
                    local visualScore = visualScoreOf(d)
                    out[#out+1] = {
                        obj=d,
                        cf=cf,
                        rarityRank=rarityRank,
                        rarity=rarity,
                        rareSpawn=rareSpawn,
                        zoneRank=zoneRank,
                        zone=zone,
                        visualScore=visualScore,
                        dist=(cf.Position-origin).Magnitude,
                    }
                end
            end
        end
    end

    table.sort(out,function(a,b)
        -- 1) tier real, se estiver exposto
        if a.rarityRank ~= b.rarityRank then
            return a.rarityRank > b.rarityRank
        end
        -- 2) spawn raro confirmado pelo proprio modelo
        if a.rareSpawn ~= b.rareSpawn then
            return a.rareSpawn == true
        end
        -- 3) bioma mais avancado
        if a.zoneRank ~= b.zoneRank then
            return a.zoneRank > b.zoneRank
        end
        -- 4) qualidade visual/tamanho
        if math.abs(a.visualScore-b.visualScore) > 0.01 then
            return a.visualScore > b.visualScore
        end
        -- 5) SOMENTE AGORA distancia
        if math.abs(a.dist-b.dist) > 0.01 then
            return a.dist < b.dist
        end
        return a.obj.Name < b.obj.Name
    end)

    return out
end

local function carriedModels()
    local out = {}
    for _,d in ipairs(Workspace:GetChildren()) do
        if d:IsA("Model") and tonumber(d:GetAttribute("CarrierUserId")) == LP.UserId then
            local uid = tostring(d:GetAttribute("AreaEggUid") or "")
            if d.Name:find("CarriedAreaEgg_",1,true) or uid ~= "" then
                out[#out+1] = d
            end
        end
    end

    local c = LP.Character
    if c then
        for _,d in ipairs(c:GetDescendants()) do
            if d:IsA("Model") and tonumber(d:GetAttribute("CarrierUserId")) == LP.UserId then
                local uid = tostring(d:GetAttribute("AreaEggUid") or "")
                if d.Name:find("CarriedAreaEgg_",1,true) or uid ~= "" then
                    out[#out+1] = d
                end
            end
        end
    end
    return out
end

local function firstLocalCarry()
    local all = carriedModels()
    return all[1]
end

local function carrySnapshot()
    local set = setmetatable({}, {__mode="k"})
    for _,d in ipairs(carriedModels()) do set[d]=true end
    return set
end

local function waitNewCarry(before,token,timeout)
    local deadline = os.clock() + (timeout or 4)
    while S.running and S.token==token and os.clock()<deadline do
        for _,d in ipairs(carriedModels()) do
            if not before[d] then return d end
        end
        task.wait(0.04)
    end
    return nil
end

local function carryUid(carried)
    if not carried then return "" end
    return tostring(carried:GetAttribute("AreaEggUid") or carried.Name)
end

local function hasCarryUid(uid)
    uid = tostring(uid or "")
    for _,d in ipairs(carriedModels()) do
        local duid = tostring(d:GetAttribute("AreaEggUid") or "")
        if uid=="" or duid==uid or d.Name:find(uid,1,true) then return true end
    end
    return false
end

local function findCarryPromptNear(pos)
    local best,bestDist

    local smart = Workspace:FindFirstChild("SmartPromptPart")
    if smart then
        for _,d in ipairs(smart:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Name=="CarryAreaEgg" and d.Enabled then
                local parent=d.Parent
                local dist=0
                if parent and parent:IsA("BasePart") then dist=(parent.Position-pos).Magnitude end
                if not best or dist<(bestDist or math.huge) then best,bestDist=d,dist end
            end
        end
    end

    if best then return best end

    for _,d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Name=="CarryAreaEgg" and d.Enabled then
            return d
        end
    end
    return nil
end

local function waitCarryPrompt(pos,token,timeout)
    local deadline=os.clock()+(timeout or 2.4)
    while S.running and S.token==token and os.clock()<deadline do
        local p=findCarryPromptNear(pos)
        if p then return p end
        task.wait(0.04)
    end
    return nil
end

local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false,"prompt sumiu" end
    if fireproximityprompt then
        local ok=pcall(function() fireproximityprompt(prompt) end)
        if ok then return true end
    end

    local ok,err=pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.05,tonumber(prompt.HoldDuration) or 0)+0.05)
        prompt:InputHoldEnd()
    end)
    return ok,err
end

local function waitDeliveryConfirmed(uid,token)
    local absentSince=nil
    local lastTp=0
    while S.running and S.token==token do
        if not hasCarryUid(uid) then
            absentSince=absentSince or os.clock()
            if os.clock()-absentSince>=0.45 then return true end
        else
            absentSince=nil
        end

        if os.clock()-lastTp>=0.70 then
            lastTp=os.clock()
            tp(SAFE_CF)
        end
        task.wait(0.05)
    end
    return false
end

local function deliverExistingCarry(token)
    local carried=firstLocalCarry()
    if not carried then return false end

    local uid=carryUid(carried)
    S.current=uid
    S.currentQuality="ja carregado"
    S.state="INDO_SAFE"
    S.status="Ovo ja carregado • indo Safe"
    tp(SAFE_CF)

    S.state="CONFIRMANDO_ENTREGA"
    S.status="Safe • aguardando entrega confirmada"
    if waitDeliveryConfirmed(uid,token) then
        S.delivered+=1
        S.current=nil
        S.currentQuality=nil
        S.status="Entrega confirmada • recalculando MELHOR ovo"
        task.wait(0.12)
    end
    return true
end

local function run(token)
    while S.running and S.token==token do
        if not deliverExistingCarry(token) then
            S.state="BUSCANDO_MELHOR"
            local eggs=getEggCandidates()

            if #eggs==0 then
                S.current=nil
                S.currentQuality=nil
                S.status="Nenhum ovo coletavel visivel • aguardando"
                task.wait(0.30)
            else
                local entry=eggs[1]
                local egg=entry.obj
                S.current=egg.Name
                S.currentQuality=qualityLabel(entry)

                S.state="INDO_MELHOR_OVO"
                S.status="MELHOR: "..S.currentQuality

                local approach=entry.cf*CFrame.new(0,3.2,2.5)
                local moved=tp(approach)
                if not moved then
                    S.failed+=1
                    S.blacklist[egg]=os.clock()+1.5
                    S.status="Falha TP no melhor ovo • recalculando"
                    task.wait(0.15)
                else
                    task.wait(0.08)
                    local prompt=waitCarryPrompt(entry.cf.Position,token,2.4)
                    if not prompt then
                        S.failed+=1
                        S.blacklist[egg]=os.clock()+1.5
                        S.status="Melhor ovo sem prompt • recalculando"
                        task.wait(0.12)
                    else
                        local before=carrySnapshot()
                        S.state="COLETANDO"
                        S.status="Coletando MELHOR: "..S.currentQuality
                        local fired=triggerPrompt(prompt)
                        if not fired then
                            S.failed+=1
                            S.blacklist[egg]=os.clock()+1.8
                            S.status="Falha ao acionar coleta"
                            task.wait(0.12)
                        else
                            S.state="CONFIRMANDO_CARRY"
                            S.status="Esperando CarrierUserId confirmar"
                            local carried=waitNewCarry(before,token,4.5)
                            if not carried then
                                S.failed+=1
                                if egg and egg.Parent then S.blacklist[egg]=os.clock()+2.0 end
                                S.status="Carry nao confirmado • recalculando MELHOR"
                                task.wait(0.18)
                            else
                                local uid=carryUid(carried)
                                S.current=uid
                                S.state="INDO_SAFE"
                                S.status="Carry confirmado • indo Safe"
                                tp(SAFE_CF)

                                S.state="CONFIRMANDO_ENTREGA"
                                S.status="Safe • esperando ENTREGA confirmar"
                                if waitDeliveryConfirmed(uid,token) then
                                    S.delivered+=1
                                    S.current=nil
                                    S.currentQuality=nil
                                    S.status="Entrega OK • escolhendo MELHOR restante"
                                    task.wait(0.12)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if S.token==token then
        S.state="PARADO"
        S.current=nil
        S.currentQuality=nil
    end
end

--=============================== GUI ================================--
local parent
pcall(function() if gethui then parent=gethui() end end)
if not parent then pcall(function() parent=CoreGui end) end
if not parent then parent=LP:WaitForChild("PlayerGui") end

local gui=Instance.new("ScreenGui")
gui.Name="CafeinaAutoEggDeliveryV12"
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
if not pcall(function() gui.Parent=parent end) then gui.Parent=LP:WaitForChild("PlayerGui") end
ENV.__CAFEINA_AUTO_EGG_DELIVERY_GUI=gui

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(286,168)
frame.Position=UDim2.new(0,10,.5,-84)
frame.BackgroundColor3=Color3.fromRGB(15,15,18)
frame.BorderSizePixel=0
frame.Active=true
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,10)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-16,0,24)
title.Position=UDim2.fromOffset(8,6)
title.BackgroundTransparency=1
title.Text="CAFEINA • MELHOR OVO V1.2"
title.TextColor3=Color3.fromRGB(245,245,248)
title.Font=Enum.Font.GothamBold
title.TextSize=10
title.TextXAlignment=Enum.TextXAlignment.Left
title.Active=true
title.Parent=frame

local stateLabel=Instance.new("TextLabel")
stateLabel.Size=UDim2.new(1,-16,0,48)
stateLabel.Position=UDim2.fromOffset(8,34)
stateLabel.BackgroundTransparency=1
stateLabel.TextColor3=Color3.fromRGB(190,190,200)
stateLabel.Font=Enum.Font.Gotham
stateLabel.TextSize=8
stateLabel.TextWrapped=true
stateLabel.TextXAlignment=Enum.TextXAlignment.Left
stateLabel.TextYAlignment=Enum.TextYAlignment.Top
stateLabel.Parent=frame

local counters=Instance.new("TextLabel")
counters.Size=UDim2.new(1,-16,0,18)
counters.Position=UDim2.fromOffset(8,84)
counters.BackgroundTransparency=1
counters.TextColor3=Color3.fromRGB(160,160,172)
counters.Font=Enum.Font.Code
counters.TextSize=8
counters.TextXAlignment=Enum.TextXAlignment.Left
counters.Parent=frame

local toggle=Instance.new("TextButton")
toggle.Size=UDim2.new(1,-16,0,48)
toggle.Position=UDim2.fromOffset(8,110)
toggle.BackgroundColor3=Color3.fromRGB(105,30,35)
toggle.BorderSizePixel=0
toggle.Text="INICIAR • MELHOR OVO"
toggle.TextColor3=Color3.new(1,1,1)
toggle.Font=Enum.Font.GothamBold
toggle.TextSize=10
toggle.Parent=frame
Instance.new("UICorner",toggle).CornerRadius=UDim.new(0,8)

local dragging=false
local dragStart,startPos
connect(title.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=i.Position; startPos=frame.Position
    end
end)
connect(title.InputEnded,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
connect(UIS.InputChanged,function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

local function start()
    if S.running then return end
    S.running=true
    S.token+=1
    local token=S.token
    S.state="INICIANDO"
    S.status="Prioridade: raridade > rare spawn > bioma > visual > distancia"
    task.spawn(function() run(token) end)
end

local function stop()
    if not S.running then return end
    S.running=false
    S.token+=1
    S.state="PARADO"
    S.current=nil
    S.currentQuality=nil
    S.status="Parado pelo usuario"
end

toggle.MouseButton1Click:Connect(function()
    if S.running then stop() else start() end
end)

connect(RunService.RenderStepped,function()
    toggle.Text=S.running and "PARAR AUTO OVOS" or "INICIAR • MELHOR OVO"
    local q=S.currentQuality and ("\nEscolha: "..S.currentQuality) or ""
    stateLabel.Text=S.state.."\n"..S.status..q
    counters.Text="entregues: "..S.delivered.."   falhas: "..S.failed
end)

local function cleanup()
    stop()
    for _,c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end

S.Start=start
S.Stop=stop
S.Cleanup=cleanup
S.GetEggCandidates=getEggCandidates
ENV.__CAFEINA_AUTO_EGG_DELIVERY=S

print("[CAFEINA] AUTO EGG DELIVERY V1.2 carregado • MELHOR > PERTO")