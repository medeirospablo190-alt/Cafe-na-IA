--==============================================================--
-- CAFEINA • STEAL AN EGG • CLIENT MENU V6.1
-- Mobile/executor • CLIENT-SIDE ONLY
--==============================================================--

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G
local SAFE_CF = CFrame.new(529.4, 75.1, -360.4)

for _, key in ipairs({"__CAFEINA_EGG_V61", "__CAFEINA_EGG_V6", "__CAFEINA_EGG_V5"}) do
    pcall(function()
        local old = rawget(ENV, key)
        if type(old) == "table" and type(old.Cleanup) == "function" then old.Cleanup() end
    end)
end
for _, key in ipairs({"__CAFEINA_EGG_V61_GUI", "__CAFEINA_EGG_V6_GUI", "__CAFEINA_EGG_V5_GUI"}) do
    pcall(function()
        local old = rawget(ENV, key)
        if typeof(old) == "Instance" then old:Destroy() end
    end)
end

local S = {
    autoSafe = true,
    god = false,
    isolate = false,
    selected = nil,
    status = "AUTO SAFE ON • aguardando carry",
    lastEggTp = 0,
    lastMoneySync = 0,
    conns = {},
    isolateConns = {},
    savedParts = setmetatable({}, {__mode="k"}),
    hookedEggRemotes = setmetatable({}, {__mode="k"}),
    observedMoney = {},
    visualMoney = {},
    savedMoneyText = setmetatable({}, {__mode="k"}),
    rows = {},
}

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or S.conns, c)
    return c
end

local function status(text)
    S.status = tostring(text or "")
end

local function char(plr)
    plr = plr or LP
    local c = plr.Character
    if not c then return nil,nil,nil end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function moveModel(c, root, cf)
    if not c or not root then return false,"root indisponivel" end
    local ok,err = pcall(function() c:PivotTo(cf) end)
    if not ok then ok,err = pcall(function() root.CFrame=cf end) end
    return ok,err
end

local function tpSelf(cf)
    local c,root = char(LP)
    return moveModel(c,root,cf)
end

local function fmt(n)
    n=tonumber(n) or 0
    local a,sign=math.abs(n),n<0 and "-" or ""
    if a>=1e12 then return sign..string.format("%.2fT",a/1e12) end
    if a>=1e9 then return sign..string.format("%.2fB",a/1e9) end
    if a>=1e6 then return sign..string.format("%.2fM",a/1e6) end
    if a>=1e3 then return sign..string.format("%.2fK",a/1e3) end
    return sign..tostring(math.floor(a+0.5))
end

local function net(name)
    local p=RS:FindFirstChild("Packages")
    local n=p and p:FindFirstChild("Networking")
    return n and n:FindFirstChild(name)
end

--============================ AUTO SAFE ============================--
local function autoSafe(reason)
    if not S.autoSafe then return end
    local now=os.clock()
    if now-S.lastEggTp<0.75 then return end
    S.lastEggTp=now
    task.defer(function()
        task.wait(0.03)
        local ok,e=tpSelf(SAFE_CF)
        status(ok and ("OVO > SAFE ✓ • "..tostring(reason)) or ("AUTO SAFE falhou: "..tostring(e)))
    end)
end

local function hasLocalCarry(t,depth,targeted)
    if type(t)~="table" or (depth or 0)>4 then return false end
    depth=depth or 0
    local carrier=tonumber(t.CarrierUserId or t.CarrierId or t.UserId)
    local state=tostring(t.State or t.state or "")
    if carrier==LP.UserId and (state=="Carried" or t.IsCarrying==true) then return true end
    if targeted and t.IsCarrying==true and (carrier==nil or carrier==LP.UserId) then return true end
    for _,v in pairs(t) do
        if type(v)=="table" and hasLocalCarry(v,depth+1,targeted) then return true end
    end
    return false
end

local function hookEggRemote(r)
    if S.hookedEggRemotes[r] or not r:IsA("RemoteEvent") then return end
    local n=r.Name
    if n~="RE/EggWorld/FieldEggCarry" and n~="RE/EggWorld/FieldEggShifted" then return end
    S.hookedEggRemotes[r]=true
    connect(r.OnClientEvent,function(...)
        if not S.autoSafe then return end
        local targeted=n=="RE/EggWorld/FieldEggCarry"
        for i=1,select("#",...) do
            local v=select(i,...)
            if type(v)=="table" and hasLocalCarry(v,0,targeted) then
                autoSafe(targeted and "FieldEggCarry" or "FieldEggShifted")
                return
            end
        end
    end)
end

for _,r in ipairs(RS:GetDescendants()) do hookEggRemote(r) end
connect(RS.DescendantAdded,hookEggRemote)

connect(PPS.PromptTriggered,function(prompt,player)
    if not S.autoSafe or (player and player~=LP) then return end
    local name=string.lower(prompt.Name)
    local action=string.lower(tostring(prompt.ActionText or ""))
    local object=string.lower(tostring(prompt.ObjectText or ""))
    local match=name:find("carryareaegg",1,true)
        or ((action:find("steal",1,true) or action:find("carry",1,true) or action:find("take",1,true))
        and (object:find("egg",1,true) or object:find("ovo",1,true)))
    if match then task.delay(0.18,function() autoSafe("CarryAreaEgg") end) end
end)

--========================== DINHEIRO VISUAL =========================--
local function deepMoney(t,depth)
    if type(t)~="table" or (depth or 0)>4 then return nil end
    depth=depth or 0
    if type(t.Money)=="number" then return t.Money end
    for _,v in pairs(t) do
        if type(v)=="table" then
            local m=deepMoney(v,depth+1)
            if m~=nil then return m end
        end
    end
end

local function totalMoney(plr)
    if not plr then return 0 end
    return (S.observedMoney[plr.UserId] or 0)+(S.visualMoney[plr.UserId] or 0)
end

local MONEY_WORDS={"money","cash","currency","balance","wallet","coin","coins"}
local BAD_WORDS={"shop","store","price","cost","purchase","product","upgrade","button"}
local function hasWord(text,words)
    text=string.lower(tostring(text or ""))
    for _,w in ipairs(words) do if text:find(w,1,true) then return true end end
    return false
end

local function moneyScore(label)
    if not label:IsA("TextLabel") then return -999 end
    local g=rawget(ENV,"__CAFEINA_EGG_V61_GUI")
    if typeof(g)=="Instance" and label:IsDescendantOf(g) then return -999 end
    local path=""; pcall(function() path=label:GetFullName() end)
    if hasWord(path,BAD_WORDS) then return -999 end
    local score=0
    if hasWord(label.Name,MONEY_WORDS) then score+=6 end
    if hasWord(path,MONEY_WORDS) then score+=4 end
    local text=tostring(label.Text or "")
    if text:find("%$") then score+=4 end
    if text:match("^[%s%$]*[%d%.,]+[KMBTkmbt]?[%s]*$") then score+=2 end
    if label.Visible then score+=1 end
    return score
end

local function getMoneyLabels()
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return {} end
    local out={}
    for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local s=moneyScore(d)
            if s>=5 then out[#out+1]={obj=d,score=s} end
        end
    end
    table.sort(out,function(a,b) return a.score>b.score end)
    return out
end

local function displayMoney(label,value)
    local old=tostring(label.Text or "")
    local low=string.lower(old)
    if old:find("%$") then return "$"..fmt(value) end
    if low:find("money",1,true) then return "Money: "..fmt(value) end
    if low:find("cash",1,true) then return "Cash: "..fmt(value) end
    return fmt(value)
end

local function syncMoneyHud()
    if S.visualMoney[LP.UserId]==nil then return 0 end
    local labels=getMoneyLabels()
    local value=totalMoney(LP)
    local changed=0
    for i=1,math.min(#labels,2) do
        local label=labels[i].obj
        if S.savedMoneyText[label]==nil then S.savedMoneyText[label]=label.Text end
        pcall(function() label.Text=displayMoney(label,value) end)
        changed+=1
    end
    return changed
end

local function updateRow(plr)
    local row=plr and S.rows[plr.UserId]
    if not row then return end
    local suffix=""
    if S.observedMoney[plr.UserId]~=nil or S.visualMoney[plr.UserId]~=nil then
        suffix=" • V$"..fmt(totalMoney(plr))
    end
    row.Text=plr.DisplayName.." (@"..plr.Name..")"..suffix
end

local profileDelta=net("RE/ProfileMirror/ProfileDelta")
if profileDelta and profileDelta:IsA("RemoteEvent") then
    connect(profileDelta.OnClientEvent,function(...)
        local target,money
        for i=1,select("#",...) do
            local v=select(i,...)
            if typeof(v)=="Instance" and v:IsA("Player") then target=v end
            if money==nil and type(v)=="table" then money=deepMoney(v,0) end
        end
        if money~=nil then
            target=target or LP
            S.observedMoney[target.UserId]=money
            updateRow(target)
            if target==LP then syncMoneyHud() end
        end
    end)
end

local function addVisualMoney(plr,raw)
    if not plr then return false,"selecione um jogador" end
    local text=tostring(raw or "")
    text=text:gsub(",", ".")
    local amount=tonumber(text)
    if not amount then return false,"quantidade invalida" end
    amount=math.clamp(amount,-1e12,1e12)
    S.visualMoney[plr.UserId]=(S.visualMoney[plr.UserId] or 0)+amount
    updateRow(plr)
    if plr==LP then
        local n=syncMoneyHud()
        if n>0 then return true,"$"..fmt(totalMoney(plr)).." na HUD local" end
        return true,"$"..fmt(totalMoney(plr)).." local • HUD nao encontrada"
    end
    return true,"$"..fmt(totalMoney(plr)).." visual no menu"
end

local pg=LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui",5)
if pg then
    connect(pg.DescendantAdded,function(d)
        if S.visualMoney[LP.UserId]~=nil and d:IsA("TextLabel") then task.delay(.1,syncMoneyHud) end
    end)
end

--========================== GOD / ISOLAR ============================--
local function blockPart(p)
    if not p:IsA("BasePart") then return end
    if not S.savedParts[p] then S.savedParts[p]={p.CanCollide,p.CanTouch,p.CanQuery} end
    pcall(function() p.CanCollide=false; p.CanTouch=false; p.CanQuery=false end)
end

local function isolateChar(c)
    if not S.isolate or not c or c==LP.Character then return end
    for _,d in ipairs(c:GetDescendants()) do blockPart(d) end
    local x=c.DescendantAdded:Connect(function(d) if S.isolate then blockPart(d) end end)
    table.insert(S.isolateConns,x)
end

local function restoreIsolation()
    for _,c in ipairs(S.isolateConns) do pcall(function() c:Disconnect() end) end
    table.clear(S.isolateConns)
    for p,old in pairs(S.savedParts) do
        if p and p.Parent then pcall(function() p.CanCollide,p.CanTouch,p.CanQuery=old[1],old[2],old[3] end) end
    end
    table.clear(S.savedParts)
end

local function setIsolation(on)
    S.isolate=on==true
    restoreIsolation()
    if S.isolate then for _,p in ipairs(Players:GetPlayers()) do if p~=LP then isolateChar(p.Character) end end end
    status(S.isolate and "ISOLAR LOCAL ON" or "ISOLAR LOCAL OFF")
end

connect(RunService.Heartbeat,function()
    local _,root,hum=char(LP)
    if hum and (S.god or S.isolate) then
        pcall(function()
            hum.BreakJointsOnDeath=false
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead,false)
            if hum.Health<hum.MaxHealth then hum.Health=hum.MaxHealth end
        end)
    end
    if S.isolate and root then
        local v=root.AssemblyLinearVelocity
        if Vector3.new(v.X,0,v.Z).Magnitude>130 then pcall(function() root.AssemblyLinearVelocity=Vector3.new(0,math.clamp(v.Y,-80,80),0) end) end
        if root.AssemblyAngularVelocity.Magnitude>40 then pcall(function() root.AssemblyAngularVelocity=Vector3.zero end) end
    end
end)

--========================== PLAYER ACTIONS ==========================--
local function tpTo(plr)
    if not plr or plr==LP then return false,"selecione outro jogador" end
    local _,root=char(plr)
    if not root then return false,"alvo sem root" end
    return tpSelf(root.CFrame*CFrame.new(0,0,3))
end

local function pullOne(plr,offset)
    if not plr or plr==LP then return false,"selecione outro jogador" end
    local c,root=char(plr)
    local _,myRoot=char(LP)
    if not c or not root or not myRoot then return false,"personagem indisponivel" end
    return moveModel(c,root,myRoot.CFrame*(offset or CFrame.new(0,0,-3)))
end

local function pullAll()
    local _,myRoot=char(LP)
    if not myRoot then return 0,"seu root indisponivel" end
    local targets={}
    for _,p in ipairs(Players:GetPlayers()) do if p~=LP then targets[#targets+1]=p end end
    local moved=0
    for i,p in ipairs(targets) do
        local a=((i-1)/math.max(1,#targets))*math.pi*2
        local ok=pullOne(p,CFrame.new(math.cos(a)*4,0,math.sin(a)*4))
        if ok then moved+=1 end
    end
    return moved,nil
end

local function killLocal(plr)
    if not plr or plr==LP then return false,"selecione outro jogador" end
    local _,_,hum=char(plr)
    if not hum then return false,"alvo sem Humanoid" end
    return pcall(function() hum.Health=0; hum:ChangeState(Enum.HumanoidStateType.Dead) end)
end

--================================ GUI ================================--
local parent
pcall(function() if gethui then parent=gethui() end end)
if not parent then pcall(function() parent=CoreGui end) end
if not parent then parent=LP:WaitForChild("PlayerGui") end

local gui=Instance.new("ScreenGui")
gui.Name="CafeinaEggV61"
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local pok=pcall(function() gui.Parent=parent end)
if not pok then gui.Parent=LP:WaitForChild("PlayerGui") end
ENV.__CAFEINA_EGG_V61_GUI=gui

local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(300,368)
frame.Position=UDim2.new(0,10,.5,-184)
frame.BackgroundColor3=Color3.fromRGB(15,15,18)
frame.BorderSizePixel=0
frame.Active=true
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,10)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-62,0,25)
title.Position=UDim2.fromOffset(8,5)
title.BackgroundTransparency=1
title.Text="CAFEINA • EGG V6.1"
title.TextColor3=Color3.fromRGB(245,245,248)
title.Font=Enum.Font.GothamBold
title.TextSize=11
title.TextXAlignment=Enum.TextXAlignment.Left
title.Active=true
title.Parent=frame

local min=Instance.new("TextButton")
min.Size=UDim2.fromOffset(48,22)
min.Position=UDim2.new(1,-56,0,6)
min.BackgroundColor3=Color3.fromRGB(42,42,48)
min.BorderSizePixel=0
min.Text="MIN"
min.TextColor3=Color3.new(1,1,1)
min.Font=Enum.Font.GothamBold
min.TextSize=8
min.Parent=frame
Instance.new("UICorner",min).CornerRadius=UDim.new(0,6)

local stat=Instance.new("TextLabel")
stat.Size=UDim2.new(1,-16,0,24)
stat.Position=UDim2.fromOffset(8,32)
stat.BackgroundTransparency=1
stat.TextWrapped=true
stat.TextColor3=Color3.fromRGB(180,180,190)
stat.Font=Enum.Font.Gotham
stat.TextSize=8
stat.TextXAlignment=Enum.TextXAlignment.Left
stat.Parent=frame

local function button(text,xs,xo,y,ws,wo,color)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(ws,wo,0,28)
    b.Position=UDim2.new(xs,xo,0,y)
    b.BackgroundColor3=color or Color3.fromRGB(43,43,50)
    b.BorderSizePixel=0
    b.Text=text
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=8
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    return b
end

local autoBtn=button("AUTO SAFE: ON",0,8,60,1/3,-9,Color3.fromRGB(100,30,34))
local godBtn=button("GOD: OFF",1/3,3,60,1/3,-6)
local isoBtn=button("ISOLAR: OFF",2/3,1,60,1/3,-9)
local safeBtn=button("IR SAFE AGORA",0,8,92,1,-16,Color3.fromRGB(90,30,34))

local list=Instance.new("ScrollingFrame")
list.Size=UDim2.new(1,-16,0,112)
list.Position=UDim2.fromOffset(8,124)
list.BackgroundColor3=Color3.fromRGB(23,23,27)
list.BorderSizePixel=0
list.ScrollBarThickness=3
list.CanvasSize=UDim2.fromOffset(0,0)
list.Parent=frame
Instance.new("UICorner",list).CornerRadius=UDim.new(0,7)
local layout=Instance.new("UIListLayout",list); layout.Padding=UDim.new(0,3)
local pad=Instance.new("UIPadding",list); pad.PaddingTop=UDim.new(0,4); pad.PaddingBottom=UDim.new(0,4); pad.PaddingLeft=UDim.new(0,4); pad.PaddingRight=UDim.new(0,4)

local selectedLabel=Instance.new("TextLabel")
selectedLabel.Size=UDim2.new(1,-16,0,22)
selectedLabel.Position=UDim2.fromOffset(8,240)
selectedLabel.BackgroundTransparency=1
selectedLabel.Text="Alvo: nenhum"
selectedLabel.TextColor3=Color3.fromRGB(205,205,215)
selectedLabel.Font=Enum.Font.Gotham
selectedLabel.TextSize=8
selectedLabel.TextXAlignment=Enum.TextXAlignment.Left
selectedLabel.Parent=frame

local amount=Instance.new("TextBox")
amount.Size=UDim2.new(1,-16,0,28)
amount.Position=UDim2.fromOffset(8,266)
amount.BackgroundColor3=Color3.fromRGB(28,28,33)
amount.BorderSizePixel=0
amount.ClearTextOnFocus=false
amount.Text="1000"
amount.PlaceholderText="Quantidade de dinheiro visual"
amount.TextColor3=Color3.fromRGB(240,240,245)
amount.Font=Enum.Font.Code
amount.TextSize=9
amount.Parent=frame
Instance.new("UICorner",amount).CornerRadius=UDim.new(0,6)

local tpBtn=button("TP > ALVO",0,8,298,1/3,-9)
local pullBtn=button("ALVO > MIM",1/3,3,298,1/3,-6)
local allBtn=button("TODOS > MIM",2/3,1,298,1/3,-9)
local killBtn=button("KILL LOCAL",0,8,330,1/3,-9,Color3.fromRGB(112,28,32))
local moneyTargetBtn=button("$ ALVO",1/3,3,330,1/3,-6)
local moneySelfBtn=button("$ EU",2/3,1,330,1/3,-9)

local mini=Instance.new("TextButton")
mini.Size=UDim2.fromOffset(82,36)
mini.Position=frame.Position
mini.BackgroundColor3=Color3.fromRGB(18,18,22)
mini.BorderSizePixel=0
mini.Text="EGG V6.1"
mini.TextColor3=Color3.new(1,1,1)
mini.Font=Enum.Font.GothamBold
mini.TextSize=8
mini.Visible=false
mini.Parent=gui
Instance.new("UICorner",mini).CornerRadius=UDim.new(0,8)

local function clearRows()
    S.rows={}
    for _,c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
end

local function rebuild()
    clearRows()
    local count=0
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LP then
            count+=1
            local row=Instance.new("TextButton")
            row.Size=UDim2.new(1,0,0,27)
            row.BackgroundColor3=Color3.fromRGB(36,36,42)
            row.BorderSizePixel=0
            row.TextColor3=Color3.fromRGB(235,235,240)
            row.Font=Enum.Font.Gotham
            row.TextSize=8
            row.TextXAlignment=Enum.TextXAlignment.Left
            row.Parent=list
            Instance.new("UICorner",row).CornerRadius=UDim.new(0,5)
            local rp=Instance.new("UIPadding",row); rp.PaddingLeft=UDim.new(0,7)
            S.rows[plr.UserId]=row
            updateRow(plr)
            row.MouseButton1Click:Connect(function()
                S.selected=plr
                selectedLabel.Text="Alvo: "..plr.DisplayName.." (@"..plr.Name..")"
                status("Selecionado: "..plr.DisplayName)
            end)
        end
    end
    task.wait()
    list.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+8)
    if count==0 then status("Nenhum outro jogador online") end
end

autoBtn.MouseButton1Click:Connect(function() S.autoSafe=not S.autoSafe; status(S.autoSafe and "AUTO SAFE ON" or "AUTO SAFE OFF") end)
godBtn.MouseButton1Click:Connect(function() S.god=not S.god; status(S.god and "GOD LOCAL ON" or "GOD LOCAL OFF") end)
isoBtn.MouseButton1Click:Connect(function() setIsolation(not S.isolate) end)
safeBtn.MouseButton1Click:Connect(function() local ok,e=tpSelf(SAFE_CF); status(ok and "SAFE ZONE ✓" or ("Safe falhou: "..tostring(e))) end)
tpBtn.MouseButton1Click:Connect(function() local ok,e=tpTo(S.selected); status(ok and "Voce > alvo ✓" or ("TP falhou: "..tostring(e))) end)
pullBtn.MouseButton1Click:Connect(function() local ok,e=pullOne(S.selected,CFrame.new(0,0,-3)); status(ok and "Alvo > voce LOCAL ✓" or ("Puxar falhou: "..tostring(e))) end)
allBtn.MouseButton1Click:Connect(function() local n,e=pullAll(); status(e and ("Puxar todos: "..e) or ("Todos > voce LOCAL: "..n)) end)
killBtn.MouseButton1Click:Connect(function() local ok,e=killLocal(S.selected); status(ok and "Kill LOCAL aplicado" or ("Kill falhou: "..tostring(e))) end)
moneyTargetBtn.MouseButton1Click:Connect(function() local ok,e=addVisualMoney(S.selected,amount.Text); status(ok and ("Alvo: "..e) or e) end)
moneySelfBtn.MouseButton1Click:Connect(function() local ok,e=addVisualMoney(LP,amount.Text); status(ok and ("Voce: "..e) or e) end)
min.MouseButton1Click:Connect(function() mini.Position=frame.Position; frame.Visible=false; mini.Visible=true end)
mini.MouseButton1Click:Connect(function() frame.Position=mini.Position; mini.Visible=false; frame.Visible=true end)

for _,p in ipairs(Players:GetPlayers()) do if p~=LP then connect(p.CharacterAdded,function(c) task.wait(.1); isolateChar(c) end) end end
connect(Players.PlayerAdded,function(p) connect(p.CharacterAdded,function(c) task.wait(.1); isolateChar(c) end); task.defer(rebuild) end)
connect(Players.PlayerRemoving,function(p) if S.selected==p then S.selected=nil; selectedLabel.Text="Alvo: nenhum" end; task.defer(rebuild) end)

local dragging,dragStart,startPos=false,nil,nil
connect(title.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end
end)
connect(title.InputEnded,function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
connect(UIS.InputChanged,function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

connect(RunService.RenderStepped,function()
    stat.Text=S.status
    autoBtn.Text=S.autoSafe and "AUTO SAFE: ON" or "AUTO SAFE: OFF"
    godBtn.Text=S.god and "GOD: ON" or "GOD: OFF"
    isoBtn.Text=S.isolate and "ISOLAR: ON" or "ISOLAR: OFF"
    if S.visualMoney[LP.UserId]~=nil and os.clock()-S.lastMoneySync>.35 then
        S.lastMoneySync=os.clock()
        syncMoneyHud()
    end
end)

local function cleanup()
    restoreIsolation()
    for _,c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    for label,old in pairs(S.savedMoneyText) do if label and label.Parent then pcall(function() label.Text=old end) end end
    pcall(function() gui:Destroy() end)
end

S.Cleanup=cleanup
ENV.__CAFEINA_EGG_V61=S

task.defer(rebuild)
print("[CAFEINA EGG] V6.1 carregado ✓")
