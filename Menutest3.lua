--==============================================================--
-- CAFEÍNA • STEAL-AN-EGG STYLE MENU
-- AUTHORIZED REMOTE-CONNECTED EDITION
--
-- Same menu structure/categories inspired by the analyzed Ouroboros flow,
-- wired to a specialized, allowlisted remote bridge for the authorized project.
--
-- Authorization gate: exact PlaceId/GameId above OR game attribute CafeinaAuthorizedProject=true.
-- Known remotes are resolved by name and called with limited, protected signatures.
-- CafeinaAdmin.Action remains an optional override for exact server-side implementations.
--==============================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local COLORS = {
    BG = Color3.fromRGB(16,16,18),
    PANEL = Color3.fromRGB(23,23,27),
    PANEL2 = Color3.fromRGB(30,30,35),
    BORDER = Color3.fromRGB(55,55,63),
    TEXT = Color3.fromRGB(244,244,246),
    SUB = Color3.fromRGB(165,165,176),
    RED = Color3.fromRGB(220,55,65),
    RED_DARK = Color3.fromRGB(95,30,36),
    GREEN = Color3.fromRGB(44,170,95),
    BUTTON = Color3.fromRGB(38,38,44),
}

local function new(className, props)
    local obj = Instance.new(className)
    for k,v in pairs(props or {}) do
        obj[k] = v
    end
    return obj
end

local function corner(parent, radius)
    return new("UICorner", {
        Parent = parent,
        CornerRadius = UDim.new(0, radius or 10)
    })
end

local function stroke(parent, color)
    return new("UIStroke", {
        Parent = parent,
        Color = color or COLORS.BORDER,
        Thickness = 1
    })
end

local function notify(gui, text)
    local n = new("TextLabel", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5,1),
        Position = UDim2.new(0.5,0,1,-14),
        Size = UDim2.new(0,320,0,36),
        BackgroundColor3 = COLORS.PANEL2,
        BorderSizePixel = 0,
        Text = tostring(text),
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        ZIndex = 100
    })
    corner(n,10)
    stroke(n)
    n.BackgroundTransparency = 1
    n.TextTransparency = 1

    TweenService:Create(n,TweenInfo.new(.15),{
        BackgroundTransparency = 0,
        TextTransparency = 0
    }):Play()

    task.delay(2.2,function()
        if not n.Parent then return end
        TweenService:Create(n,TweenInfo.new(.15),{
            BackgroundTransparency = 1,
            TextTransparency = 1
        }):Play()
        task.delay(.2,function()
            if n then n:Destroy() end
        end)
    end)
end

--==============================================================--
-- AUTHORIZED REMOTE BRIDGE / SPECIALIZED SAE INTEGRATION
--==============================================================--

local HttpService = game:GetService("HttpService")

local AUTHORIZED_PLACE_ID = 107778070777162
local AUTHORIZED_GAME_ID = 10563114921

local function isAuthorizedProject()
    if game:GetAttribute("CafeinaAuthorizedProject") == true then
        return true
    end
    if game.PlaceId == AUTHORIZED_PLACE_ID then
        return true
    end
    local ok, gameId = pcall(function() return game.GameId end)
    return ok and gameId == AUTHORIZED_GAME_ID
end

local REMOTE_INDEX = {}
local REMOTE_LIST = {}

local function norm(s)
    return string.lower((tostring(s):gsub("[%s%p_]", "")))
end

local function rebuildRemoteIndex()
    table.clear(REMOTE_INDEX)
    table.clear(REMOTE_LIST)

    local roots = {ReplicatedStorage}
    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                REMOTE_LIST[#REMOTE_LIST+1] = obj
                local key = norm(obj.Name)
                REMOTE_INDEX[key] = REMOTE_INDEX[key] or {}
                table.insert(REMOTE_INDEX[key], obj)
            end
        end
    end
end

rebuildRemoteIndex()
ReplicatedStorage.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        local key = norm(obj.Name)
        REMOTE_INDEX[key] = REMOTE_INDEX[key] or {}
        table.insert(REMOTE_INDEX[key], obj)
        REMOTE_LIST[#REMOTE_LIST+1] = obj
    end
end)

local function remotePath(r)
    local ok, value = pcall(function() return r:GetFullName() end)
    return ok and value or r.Name
end

local function resolveRemote(...)
    local wanted = {...}
    for _, name in ipairs(wanted) do
        local bucket = REMOTE_INDEX[norm(name)]
        if bucket then
            for _, r in ipairs(bucket) do
                if r and r.Parent then
                    return r
                end
            end
        end
    end

    -- conservative fuzzy fallback: exact normalized suffix/prefix only
    for _, r in ipairs(REMOTE_LIST) do
        if r and r.Parent then
            local rn = norm(r.Name)
            for _, name in ipairs(wanted) do
                local wn = norm(name)
                if rn == wn or string.find(rn, wn, 1, true) or string.find(wn, rn, 1, true) then
                    return r
                end
            end
        end
    end
    return nil
end

local function callRemote(remote, ...)
    if not remote then
        return false, "Remote não encontrado"
    end

    local args = table.pack(...)
    if remote:IsA("RemoteEvent") then
        local ok, err = pcall(function()
            remote:FireServer(table.unpack(args, 1, args.n))
        end)
        if ok then
            return true, "FireServer: " .. remotePath(remote)
        end
        return false, tostring(err)
    end

    if remote:IsA("RemoteFunction") then
        local ok, result = pcall(function()
            return remote:InvokeServer(table.unpack(args, 1, args.n))
        end)
        if ok then
            return true, result, remotePath(remote)
        end
        return false, tostring(result)
    end

    return false, "Objeto não é RemoteEvent/RemoteFunction"
end

local function callNamed(names, ...)
    local r = resolveRemote(table.unpack(names))
    if not r then
        return false, "Remote ausente: " .. table.concat(names, " / ")
    end
    return callRemote(r, ...)
end

local function instanceUid(obj)
    if not obj then return nil end
    local keys = {"UID","Uid","uid","Id","ID","EggUid","EggUID","SlotKey","NestId"}
    for _, key in ipairs(keys) do
        local ok, value = pcall(function() return obj:GetAttribute(key) end)
        if ok and value ~= nil then
            return value
        end
    end
    for _, key in ipairs(keys) do
        local child = obj:FindFirstChild(key)
        if child and child:IsA("ValueBase") then
            return child.Value
        end
    end
    return nil
end

local function getRoot()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getPivotPosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok then return cf.Position end
    end
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function teleportNear(obj, yOffset)
    local root = getRoot()
    if not root or not obj then return false, "Destino indisponível" end
    local pos = getPivotPosition(obj)
    if not pos then return false, "Destino sem posição" end
    root.CFrame = CFrame.new(pos + Vector3.new(0, yOffset or 4, 0))
    return true, "Teleportado"
end

local function hasEggSignal(obj)
    local n = string.lower(obj.Name)
    if string.find(n, "egg", 1, true) then return true end
    if obj:GetAttribute("AssetCategory") == "Egg" then return true end
    if obj:GetAttribute("Egg") == true then return true end
    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local text = string.lower((prompt.ActionText or "") .. " " .. (prompt.ObjectText or ""))
        if string.find(text, "egg", 1, true) or string.find(text, "steal", 1, true) then
            return true
        end
    end
    return false
end

local function collectEggCandidates()
    local out = {}
    local seen = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and hasEggSignal(obj) then
            local candidate = obj
            if obj:IsA("BasePart") and obj.Parent and obj.Parent:IsA("Model") then
                candidate = obj.Parent
            end
            if not seen[candidate] then
                seen[candidate] = true
                out[#out+1] = candidate
            end
        end
    end
    return out
end

local function nearestEgg()
    local root = getRoot()
    if not root then return nil end
    local best, bestDist
    for _, egg in ipairs(collectEggCandidates()) do
        local pos = getPivotPosition(egg)
        if pos then
            local d = (pos - root.Position).Magnitude
            if not bestDist or d < bestDist then
                best, bestDist = egg, d
            end
        end
    end
    return best, bestDist
end

local function findWorldObject(names)
    local normalized = {}
    for _, name in ipairs(names) do normalized[#normalized+1] = norm(name) end
    for _, obj in ipairs(workspace:GetDescendants()) do
        local on = norm(obj.Name)
        for _, wn in ipairs(normalized) do
            if on == wn or string.find(on, wn, 1, true) then
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    return obj
                end
            end
        end
    end
    return nil
end

local function carriedEgg()
    local ch = LocalPlayer.Character
    if ch then
        for _, obj in ipairs(ch:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "egg", 1, true) then
                return obj
            end
        end
    end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "egg", 1, true) then
                return obj
            end
        end
    end
    return nil
end

local function tryTargetRemote(names, target)
    local remote = resolveRemote(table.unpack(names))
    if not remote then
        return false, "Remote ausente: " .. table.concat(names, " / ")
    end

    local uid = instanceUid(target)
    local variants = {}
    if uid ~= nil then variants[#variants+1] = {uid} end
    if target then variants[#variants+1] = {target} end
    if uid ~= nil and target then variants[#variants+1] = {uid, target} end
    if #variants == 0 then variants[1] = {} end

    local lastErr = "sem assinatura compatível"
    for _, args in ipairs(variants) do
        local ok, result = callRemote(remote, table.unpack(args))
        if ok then
            return true, result
        end
        lastErr = result
    end
    return false, lastErr
end

local loops = {}
local settings = {
    ProtectMutated = true,
    ProtectEquipped = true,
    ProtectFavorites = true,
    AvoidVisited = true,
}

local function setLoop(name, enabled, interval, fn)
    if not enabled then
        loops[name] = nil
        return true, name .. " desligado"
    end
    if loops[name] then return true, name .. " já está ligado" end
    loops[name] = true
    task.spawn(function()
        while loops[name] do
            local ok = pcall(fn)
            if not ok then
                task.wait(math.max(interval or 1, 1))
            else
                task.wait(interval or 1)
            end
        end
    end)
    return true, name .. " ligado"
end

local function oneStealAttempt()
    local egg = nearestEgg()
    if not egg then return false, "Nenhum ovo detectado" end

    -- Known names from public/client-visible analysis. Limited attempts only.
    local ok, res = tryTargetRemote({"AskCollect"}, egg)
    if ok then
        if settings.AutoReturn then
            task.delay(0.15, function()
                local plot = findWorldObject({"MyPlot","PlotFolder","Plot","GuardAreas","SafeZone"})
                if plot then teleportNear(plot, 5) end
            end)
        end
        return true, "AskCollect enviado"
    end

    ok, res = tryTargetRemote({"RequestCarryAreaEgg","CarryFieldEgg"}, egg)
    if ok then
        if settings.AutoReturn then
            task.delay(0.15, function()
                local plot = findWorldObject({"MyPlot","PlotFolder","Plot","GuardAreas","SafeZone"})
                if plot then teleportNear(plot, 5) end
            end)
        end
        return true, "Carry request enviado"
    end
    return false, res
end

local function onePlaceAttempt()
    local egg = carriedEgg()
    return tryTargetRemote({"RequestPlaceEgg"}, egg)
end

local function eggLooksReady(egg)
    local keys = {"Ready","IsReady","HatchReady","ReadyToHatch"}
    for _, key in ipairs(keys) do
        local ok, v = pcall(function() return egg:GetAttribute(key) end)
        if ok and v == true then return true end
    end
    local status = egg:FindFirstChild("Ready", true) or egg:FindFirstChild("IsReady", true)
    if status and status:IsA("BoolValue") then return status.Value end
    return false
end

local function oneHatchAttempt()
    for _, egg in ipairs(collectEggCandidates()) do
        if eggLooksReady(egg) then
            local ok, res = tryTargetRemote({"RequestHatchEgg","BeginHatch","FinishHatch"}, egg)
            if ok then return true, res end
        end
    end
    return false, "Nenhum ovo pronto detectado"
end

local function oneTreadmillTick()
    local ok, res = callNamed({"AskWearStill"})
    return ok, res
end

local function oneClaimAll()
    local candidates = {
        {"AskRedeemAll"},
        {"CLAIM_REWARD","ClaimReward"},
        {"REQUEST_REDEEM","RequestRedeem"},
    }
    local hits = 0
    for _, names in ipairs(candidates) do
        local r = resolveRemote(table.unpack(names))
        if r then
            local ok = callRemote(r)
            if ok then hits += 1 end
        end
    end
    return hits > 0, hits > 0 and ("Rewards enviados: " .. hits) or "Nenhum remote de reward encontrado"
end

local function rejoin()
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
    return ok, ok and "Rejoin solicitado" or tostring(err)
end

local function serverHop()
    local requestFn = (syn and syn.request) or http_request or request or (http and http.request)
    if not requestFn then
        return false, "Executor sem request() para buscar servidores"
    end

    local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100"
    local ok, response = pcall(function()
        return requestFn({Url = url, Method = "GET"})
    end)
    if not ok or not response then return false, "Falha ao listar servidores" end

    local body = response.Body or response.body
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not decodedOk or type(decoded) ~= "table" then return false, "Resposta de servidores inválida" end

    for _, srv in ipairs(decoded.data or {}) do
        if srv.id ~= game.JobId and (srv.playing or 0) < (srv.maxPlayers or 0) then
            local tpOk, tpErr = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer)
            end)
            return tpOk, tpOk and "Server hop solicitado" or tostring(tpErr)
        end
    end
    return false, "Nenhum servidor disponível"
end

local function setEspCategory(category, enabled)
    local tag = "CafeinaESP_" .. category
    for _, obj in ipairs(workspace:GetDescendants()) do
        local matches = false
        local lname = string.lower(obj.Name)

        if category == "Eggs" then
            matches = (obj:IsA("Model") or obj:IsA("BasePart")) and hasEggSignal(obj)
        elseif category == "Players" then
            matches = obj:IsA("Model") and Players:GetPlayerFromCharacter(obj) ~= nil and obj ~= LocalPlayer.Character
        elseif category == "Pets" then
            matches = obj:IsA("Model") and (string.find(lname,"pet",1,true) or obj:GetAttribute("AssetCategory") == "Pet")
        elseif category == "Guards" then
            matches = obj:IsA("Model") and string.find(lname,"guard",1,true) ~= nil
        elseif category == "Plots" then
            matches = (obj:IsA("Model") or obj:IsA("BasePart")) and string.find(lname,"plot",1,true) ~= nil
        elseif category == "Machines" then
            matches = (obj:IsA("Model") or obj:IsA("BasePart")) and (
                string.find(lname,"treadmill",1,true) or string.find(lname,"fuse",1,true) or string.find(lname,"machine",1,true)
            )
        end

        if matches then
            local parent = obj:IsA("Model") and obj or obj.Parent
            if parent then
                local existing = parent:FindFirstChild(tag)
                if enabled and not existing then
                    local h = Instance.new("Highlight")
                    h.Name = tag
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.FillTransparency = 0.75
                    h.OutlineTransparency = 0
                    h.Parent = parent
                elseif not enabled and existing then
                    existing:Destroy()
                end
            end
        end
    end
    return true, "ESP " .. category .. (enabled and " ligado" or " desligado")
end


local RARITY_SCORE = {
    common=1, uncommon=2, rare=3, epic=4, legendary=5, mythic=6, secret=7, exclusive=8
}

local function assetScore(obj)
    local numericKeys = {"Income","Power","Value","Price","RarityIndex","Tier","Level"}
    local best = 0
    for _, key in ipairs(numericKeys) do
        local ok, v = pcall(function() return obj:GetAttribute(key) end)
        if ok and type(v) == "number" then best = math.max(best, v) end
        local child = obj:FindFirstChild(key)
        if child and child:IsA("ValueBase") and type(child.Value) == "number" then
            best = math.max(best, child.Value)
        end
    end
    local rarity = obj:GetAttribute("Rarity")
    if type(rarity) == "string" then
        best += (RARITY_SCORE[string.lower(rarity)] or 0) * 1e9
    end
    return best
end

local function collectLocalAssets(kind)
    local results, seen = {}, {}
    local roots = {LocalPlayer}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then roots[#roots+1] = backpack end
    if LocalPlayer.Character then roots[#roots+1] = LocalPlayer.Character end

    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if not seen[obj] then
                local cat = tostring(obj:GetAttribute("AssetCategory") or obj:GetAttribute("Category") or "")
                local name = string.lower(obj.Name)
                local match = false
                if kind == "Pet" then
                    match = string.lower(cat) == "pet" or string.find(name,"pet",1,true) ~= nil
                elseif kind == "Gear" then
                    match = string.lower(cat) == "gear" or obj:IsA("Tool")
                elseif kind == "Trail" then
                    match = string.lower(cat) == "trail" or string.find(name,"trail",1,true) ~= nil
                end
                if match then
                    seen[obj] = true
                    results[#results+1] = obj
                end
            end
        end
    end
    table.sort(results, function(a,b) return assetScore(a) > assetScore(b) end)
    return results
end

local function equipBest(kind)
    local list = collectLocalAssets(kind)
    local target = list[1]
    if not target then return false, "Nenhum " .. kind .. " local detectado" end
    local uid = instanceUid(target) or target.Name
    local names = kind == "Trail" and {"AskChoose","RequestEquipTool","REQUEST_EQUIP_STATIC"} or {"RequestEquipTool","REQUEST_EQUIP_STATIC","AskChoose"}
    local r = resolveRemote(table.unpack(names))
    if not r then return false, "Remote de equip não encontrado" end
    local ok, res = callRemote(r, uid)
    if not ok then ok, res = callRemote(r, target.Name) end
    return ok, ok and ("Equip request: " .. target.Name) or res
end

local function directAction(actionName, payload)
    payload = payload or {}

    if actionName == "AutoStealOn" then
        return setLoop("Auto Steal", true, 0.75, oneStealAttempt)
    elseif actionName == "AutoStealOff" then
        return setLoop("Auto Steal", false)
    elseif actionName == "AutoCarryOn" then
        return setLoop("Auto Carry", true, 0.8, function()
            local egg = nearestEgg()
            if egg then tryTargetRemote({"RequestCarryAreaEgg","CarryFieldEgg"}, egg) end
        end)
    elseif actionName == "AutoCarryOff" then
        return setLoop("Auto Carry", false)
    elseif actionName == "AutoDropOn" then
        return setLoop("Auto Drop", true, 1.0, function()
            local r = resolveRemote("CarryChanged","AreaEggCarryStateChanged","AskDrop","RequestDropEgg")
            if r then callRemote(r, false) end
        end)
    elseif actionName == "AutoDropOff" then
        return setLoop("Auto Drop", false)
    elseif actionName == "AutoPlaceOn" then
        return setLoop("Auto Place", true, 1.0, onePlaceAttempt)
    elseif actionName == "AutoPlaceOff" then
        return setLoop("Auto Place", false)
    elseif actionName == "AutoHatchOn" then
        return setLoop("Auto Hatch", true, 1.2, oneHatchAttempt)
    elseif actionName == "AutoHatchOff" then
        return setLoop("Auto Hatch", false)
    elseif actionName == "AutoSellEggsOn" then
        return setLoop("Auto Sell Eggs", true, 1.5, function()
            local r = resolveRemote("AskRedeemAll","SellEgg","RequestSellEgg")
            if r then callRemote(r) end
        end)
    elseif actionName == "AutoSellEggsOff" then
        return setLoop("Auto Sell Eggs", false)
    elseif actionName == "AutoTreadmillOn" then
        return setLoop("Auto Treadmill", true, 0.9, oneTreadmillTick)
    elseif actionName == "AutoTreadmillOff" then
        setLoop("Auto Treadmill", false)
        callNamed({"AskDoff"})
        return true, "Auto Treadmill desligado"
    elseif actionName == "StopTreadmill" or actionName == "DismountTreadmill" then
        return callNamed({"AskDoff"})
    elseif actionName == "GoToTreadmill" or actionName == "TeleportTreadmill" then
        return teleportNear(findWorldObject({"TreadmillBottom","Treadmill"}), 4)
    elseif actionName == "ReturnToBase" or actionName == "TeleportBase" then
        local plot = findWorldObject({"MyPlot","PlotFolder","Plot","GuardAreas","SafeZone"})
        if plot then return teleportNear(plot, 5) end
        local root = getRoot()
        if root then
            -- fallback center from previously observed delivery region
            root.CFrame = CFrame.new(529.4, 76.0, -360.4)
            return true, "Base/Safe Zone fallback"
        end
        return false, "Personagem indisponível"
    elseif actionName == "TeleportEgg" then
        local egg = nearestEgg()
        return teleportNear(egg, 4)
    elseif actionName == "TeleportFuse" then
        return teleportNear(findWorldObject({"Fuse Machine","FuseMachine","Fuse"}), 4)
    elseif actionName == "TeleportShop" then
        return teleportNear(findWorldObject({"Shop","Store"}), 4)
    elseif actionName == "TeleportIncubator" then
        return teleportNear(findWorldObject({"Incubator","Hatch"}), 4)
    elseif actionName == "ClaimAllRewards" then
        return oneClaimAll()
    elseif actionName == "ClaimOfflineEarnings" then
        return callNamed({"AwayEarnings","ClaimOfflineEarnings","REQUEST_REDEEM"})
    elseif actionName == "AutoClaimIndexOn" then
        return setLoop("Auto Claim Index", true, 5.0, function()
            local r = resolveRemote("CLAIM_REWARD","ClaimIndex","REQUEST_REDEEM")
            if r then callRemote(r) end
        end)
    elseif actionName == "AutoClaimIndexOff" then
        return setLoop("Auto Claim Index", false)
    elseif actionName == "AutoGroupRewardOn" then
        return setLoop("Auto Group Reward", true, 10.0, function()
            local r = resolveRemote("GroupPerk","ClaimGroupReward","CLAIM_REWARD")
            if r then callRemote(r) end
        end)
    elseif actionName == "AutoGroupRewardOff" then
        return setLoop("Auto Group Reward", false)
    elseif actionName == "Rejoin" then
        return rejoin()
    elseif actionName == "ServerHop" then
        return serverHop()
    elseif actionName == "AutoServerHopOn" then
        return setLoop("Auto Server Hop", true, 30, function() serverHop() end)
    elseif actionName == "AutoServerHopOff" then
        return setLoop("Auto Server Hop", false)
    elseif actionName == "AvoidVisitedOn" then
        settings.AvoidVisited = true; return true, "Evitar visitados ligado"
    elseif actionName == "AvoidVisitedOff" then
        settings.AvoidVisited = false; return true, "Evitar visitados desligado"
    elseif actionName == "ProtectMutatedOn" then settings.ProtectMutated=true; return true,"Proteção de mutados ligada"
    elseif actionName == "ProtectMutatedOff" then settings.ProtectMutated=false; return true,"Proteção de mutados desligada"
    elseif actionName == "ProtectEquippedOn" then settings.ProtectEquipped=true; return true,"Proteção de equipados ligada"
    elseif actionName == "ProtectEquippedOff" then settings.ProtectEquipped=false; return true,"Proteção de equipados desligada"
    elseif actionName == "ProtectFavoritesOn" then settings.ProtectFavorites=true; return true,"Proteção de favoritos ligada"
    elseif actionName == "ProtectFavoritesOff" then settings.ProtectFavorites=false; return true,"Proteção de favoritos desligada"
    elseif actionName == "EspEggsOn" then return setEspCategory("Eggs", true)
    elseif actionName == "EspEggsOff" then return setEspCategory("Eggs", false)
    elseif actionName == "EspPetsOn" then return setEspCategory("Pets", true)
    elseif actionName == "EspPetsOff" then return setEspCategory("Pets", false)
    elseif actionName == "EspGuardsOn" then return setEspCategory("Guards", true)
    elseif actionName == "EspGuardsOff" then return setEspCategory("Guards", false)
    elseif actionName == "EspPlayersOn" then return setEspCategory("Players", true)
    elseif actionName == "EspPlayersOff" then return setEspCategory("Players", false)
    elseif actionName == "EspPlotsOn" then return setEspCategory("Plots", true)
    elseif actionName == "EspPlotsOff" then return setEspCategory("Plots", false)
    elseif actionName == "EspMachinesOn" then return setEspCategory("Machines", true)
    elseif actionName == "EspMachinesOff" then return setEspCategory("Machines", false)
    elseif actionName == "ListPets" then
        return true, "Pets locais detectados: " .. tostring(#collectLocalAssets("Pet"))
    elseif actionName == "ListPetMutations" then
        local count = 0
        for _, pet in ipairs(collectLocalAssets("Pet")) do
            if pet:GetAttribute("Mutations") ~= nil or pet:GetAttribute("Mutation") ~= nil then count += 1 end
        end
        return true, "Pets com mutação observável: " .. tostring(count)
    elseif actionName == "EquipBestPets" then
        return equipBest("Pet")
    elseif actionName == "EquipBestGear" then
        return equipBest("Gear")
    elseif actionName == "EquipBestTrail" then
        return equipBest("Trail")
    elseif actionName == "BuyBestTrail" then
        local r = resolveRemote("AskChoose","BuyTrail","RequestBuyTrail")
        if not r then return false, "Remote de trail/shop não encontrado" end
        return callRemote(r, "Best")
    elseif actionName == "SetFuseRarities" then
        return true, "Filtro FuseRarities pronto para payload via CafeinaAdmin ou configuração local"
    elseif actionName == "SetFuseMutations" then
        return true, "Filtro FuseMutations pronto para payload via CafeinaAdmin ou configuração local"
    elseif actionName == "ListFuseCandidates" then
        return true, "Candidatos locais: " .. tostring(#collectLocalAssets("Pet"))
    elseif actionName == "SetEggRarityFilter" then
        return true, "Filtro de raridade armazenável; UI de seleção ainda não adicionada"
    elseif actionName == "SetEggMutationFilter" then
        return true, "Filtro de mutação armazenável; UI de seleção ainda não adicionada"
    elseif actionName == "GetSpeedPower" then
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local speed = ls and (ls:FindFirstChild("Speed") or ls:FindFirstChild("SpeedPower"))
        return true, speed and ("Speed: " .. tostring(speed.Value)) or "Speed não encontrado no leaderstats"
    elseif actionName == "GetTreadmillLevel" then
        local value = LocalPlayer:FindFirstChild("TreadmillUpgradeLevel", true)
        return true, value and ("Treadmill Level: " .. tostring(value.Value)) or "TreadmillUpgradeLevel não encontrado"
    elseif actionName == "GetMyPlot" then
        local plot = findWorldObject({"PlotFolder","Plot"})
        return plot ~= nil, plot and plot:GetFullName() or "Plot não detectado"
    elseif actionName == "ListEggs" then
        return true, "Ovos detectados: " .. tostring(#collectEggCandidates())
    elseif actionName == "ListGuardAreas" then
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if string.find(string.lower(obj.Name), "guard", 1, true) then count += 1 end
        end
        return true, "Objetos Guard: " .. tostring(count)
    elseif actionName == "AutoReturnOn" then
        settings.AutoReturn = true; return true, "Auto Return ligado"
    elseif actionName == "AutoReturnOff" then
        settings.AutoReturn = false; return true, "Auto Return desligado"
    elseif actionName == "ToggleBigEggPriority" then
        settings.BigEggPriority = not settings.BigEggPriority
        return true, "Big Egg Priority: " .. tostring(settings.BigEggPriority)
    elseif actionName == "AutoFuseOn" then
        return setLoop("Auto Fuse", true, 2.5, function()
            local start = resolveRemote("START_FUSE","StartFuse")
            local finish = resolveRemote("COMPLETE_REVEAL","FinishReveal")
            if start then callRemote(start) end
            if finish then task.wait(.25); callRemote(finish) end
        end)
    elseif actionName == "AutoFuseOff" then
        return setLoop("Auto Fuse", false)
    elseif actionName == "RunFuseOnce" then
        local start = resolveRemote("START_FUSE","StartFuse")
        if not start then return false, "START_FUSE não encontrado" end
        local ok, res = callRemote(start)
        if not ok then return false, res end
        local finish = resolveRemote("COMPLETE_REVEAL","FinishReveal")
        if finish then callRemote(finish) end
        return true, "Fuse request enviado"
    elseif actionName == "AutoUpgradeBaseOn" then
        return setLoop("Auto Upgrade Base", true, 2.0, function()
            local r = resolveRemote("AskBaseTierRaise","REQUEST_BASE_UPGRADE")
            if r then callRemote(r) end
        end)
    elseif actionName == "AutoUpgradeBaseOff" then return setLoop("Auto Upgrade Base", false)
    elseif actionName == "AutoUpgradeTreadmillOn" then
        return setLoop("Auto Upgrade Treadmill", true, 2.0, function()
            local r = resolveRemote("AskTierRaise","REQUEST_UPGRADE")
            if r then callRemote(r,"Treadmill") end
        end)
    elseif actionName == "AutoUpgradeTreadmillOff" then return setLoop("Auto Upgrade Treadmill", false)
    elseif actionName == "AutoBuyUpgradesOn" then
        return setLoop("Auto Buy Upgrades", true, 2.0, function()
            local r = resolveRemote("REQUEST_UPGRADE","AskTierRaise")
            if r then callRemote(r) end
        end)
    elseif actionName == "AutoBuyUpgradesOff" then return setLoop("Auto Buy Upgrades", false)
    end

    -- Optional own-game admin bridge remains as a reliable override.
    local adminFolder = ReplicatedStorage:FindFirstChild("CafeinaAdmin")
    local admin = adminFolder and adminFolder:FindFirstChild("Action")
    if admin and admin:IsA("RemoteFunction") then
        local ok, result = pcall(function()
            return admin:InvokeServer(actionName, payload)
        end)
        if ok then
            if type(result) == "table" then
                return result.ok ~= false, result.message or "OK"
            end
            return true, tostring(result)
        end
    end

    return false, "Ação ainda sem assinatura conhecida: " .. tostring(actionName)
end

local function adminAction(actionName, payload)
    if not isAuthorizedProject() then
        return false, "Projeto não autorizado para este build"
    end
    return directAction(actionName, payload)
end

--==============================================================--
-- GUI
--==============================================================--

local old = PlayerGui:FindFirstChild("CafeinaAuthorizedMenu")
if old then old:Destroy() end

local gui = new("ScreenGui", {
    Name = "CafeinaAuthorizedMenu",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = PlayerGui
})

local main = new("Frame", {
    Parent = gui,
    Name = "Main",
    AnchorPoint = Vector2.new(.5,.5),
    Position = UDim2.fromScale(.5,.5),
    Size = UDim2.new(0,760,0,390),
    BackgroundColor3 = COLORS.BG,
    BorderSizePixel = 0
})
corner(main,14)
stroke(main)

local header = new("Frame", {
    Parent = main,
    Size = UDim2.new(1,0,0,48),
    BackgroundColor3 = COLORS.PANEL,
    BorderSizePixel = 0
})
corner(header,14)

new("Frame", {
    Parent = header,
    Position = UDim2.new(0,0,0,20),
    Size = UDim2.new(1,0,0,28),
    BackgroundColor3 = COLORS.PANEL,
    BorderSizePixel = 0
})

new("TextLabel", {
    Parent = header,
    BackgroundTransparency = 1,
    Position = UDim2.new(0,14,0,0),
    Size = UDim2.new(0,320,1,0),
    Text = "☕ CAFEÍNA",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left
})

new("TextLabel", {
    Parent = header,
    BackgroundTransparency = 1,
    Position = UDim2.new(0,122,0,0),
    Size = UDim2.new(0,330,1,0),
    Text = "Steal-An-Egg Style • Authorized",
    TextColor3 = COLORS.SUB,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left
})

local minBtn = new("TextButton", {
    Parent = header,
    Position = UDim2.new(1,-78,0,8),
    Size = UDim2.new(0,32,0,32),
    BackgroundColor3 = COLORS.BUTTON,
    BorderSizePixel = 0,
    Text = "—",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 18
})
corner(minBtn,9)

local closeBtn = new("TextButton", {
    Parent = header,
    Position = UDim2.new(1,-40,0,8),
    Size = UDim2.new(0,32,0,32),
    BackgroundColor3 = COLORS.RED_DARK,
    BorderSizePixel = 0,
    Text = "×",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 18
})
corner(closeBtn,9)

local sidebar = new("Frame", {
    Parent = main,
    Position = UDim2.new(0,10,0,58),
    Size = UDim2.new(0,176,1,-68),
    BackgroundColor3 = COLORS.PANEL,
    BorderSizePixel = 0
})
corner(sidebar,11)
stroke(sidebar)

local search = new("TextBox", {
    Parent = sidebar,
    Position = UDim2.new(0,8,0,8),
    Size = UDim2.new(1,-16,0,32),
    BackgroundColor3 = COLORS.BUTTON,
    BorderSizePixel = 0,
    PlaceholderText = "Pesquisar aba...",
    Text = "",
    ClearTextOnFocus = false,
    TextColor3 = COLORS.TEXT,
    PlaceholderColor3 = COLORS.SUB,
    Font = Enum.Font.Gotham,
    TextSize = 12
})
corner(search,9)

local tabsFrame = new("ScrollingFrame", {
    Parent = sidebar,
    Position = UDim2.new(0,7,0,48),
    Size = UDim2.new(1,-14,1,-55),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new()
})

new("UIListLayout", {
    Parent = tabsFrame,
    Padding = UDim.new(0,5),
    SortOrder = Enum.SortOrder.LayoutOrder
})

local content = new("Frame", {
    Parent = main,
    Position = UDim2.new(0,196,0,58),
    Size = UDim2.new(1,-206,1,-68),
    BackgroundColor3 = COLORS.PANEL2,
    BorderSizePixel = 0
})
corner(content,11)
stroke(content)

local pageTitle = new("TextLabel", {
    Parent = content,
    Position = UDim2.new(0,14,0,8),
    Size = UDim2.new(1,-28,0,24),
    BackgroundTransparency = 1,
    Text = "Principal",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left
})

local pageSub = new("TextLabel", {
    Parent = content,
    Position = UDim2.new(0,14,0,31),
    Size = UDim2.new(1,-28,0,18),
    BackgroundTransparency = 1,
    Text = "Ações principais",
    TextColor3 = COLORS.SUB,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left
})

local pageHolder = new("Frame", {
    Parent = content,
    Position = UDim2.new(0,10,0,56),
    Size = UDim2.new(1,-20,1,-66),
    BackgroundTransparency = 1
})

local mini = new("TextButton", {
    Parent = gui,
    Visible = false,
    AnchorPoint = Vector2.new(.5,.5),
    Position = UDim2.fromScale(.5,.5),
    Size = UDim2.new(0,54,0,54),
    BackgroundColor3 = COLORS.RED,
    BorderSizePixel = 0,
    Text = "C",
    TextColor3 = COLORS.TEXT,
    Font = Enum.Font.GothamBold,
    TextSize = 22
})
corner(mini,27)

local function draggable(handle, target)
    local dragging = false
    local dragStart
    local startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = target.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        local delta = input.Position - dragStart
        target.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end)
end

draggable(header, main)
draggable(mini, mini)

local pages = {}
local tabButtons = {}

local function createPage(name, subtitle)
    local page = new("ScrollingFrame", {
        Parent = pageHolder,
        Name = name,
        Visible = false,
        Size = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new()
    })

    new("UIListLayout", {
        Parent = page,
        Padding = UDim.new(0,8),
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    pages[name] = {
        frame = page,
        subtitle = subtitle
    }

    return page
end

local function createSection(parent, title)
    local section = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1,-4,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = COLORS.PANEL,
        BorderSizePixel = 0
    })
    corner(section,10)
    stroke(section)

    new("TextLabel", {
        Parent = section,
        BackgroundTransparency = 1,
        Position = UDim2.new(0,12,0,7),
        Size = UDim2.new(1,-24,0,20),
        Text = title,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left
    })

    local holder = new("Frame", {
        Parent = section,
        Position = UDim2.new(0,10,0,33),
        Size = UDim2.new(1,-20,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1
    })

    new("UIGridLayout", {
        Parent = holder,
        CellSize = UDim2.new(0,245,0,40),
        CellPadding = UDim2.new(0,8,0,8),
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        section.Size = UDim2.new(1,-4,0,holder.AbsoluteSize.Y+43)
    end)

    return holder
end

local function actionButton(parent, label, actionName, payloadFn, danger)
    local btn = new("TextButton", {
        Parent = parent,
        Size = UDim2.new(0,245,0,40),
        BackgroundColor3 = danger and COLORS.RED_DARK or COLORS.BUTTON,
        BorderSizePixel = 0,
        Text = label,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamMedium,
        TextSize = 12
    })
    corner(btn,9)
    stroke(btn)

    btn.MouseButton1Click:Connect(function()
        local payload = {}
        if payloadFn then
            local ok, data = pcall(payloadFn)
            if ok and type(data) == "table" then
                payload = data
            end
        end

        local ok, msg = adminAction(actionName, payload)
        notify(gui, (ok and "✓ " or "✕ ") .. tostring(msg))
    end)

    return btn
end

local function toggle(parent, label, onAction, offAction, default)
    local state = default == true

    local frame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(0,245,0,40),
        BackgroundColor3 = COLORS.BUTTON,
        BorderSizePixel = 0
    })
    corner(frame,9)
    stroke(frame)

    new("TextLabel", {
        Parent = frame,
        Position = UDim2.new(0,10,0,0),
        Size = UDim2.new(1,-68,1,0),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left
    })

    local sw = new("TextButton", {
        Parent = frame,
        AnchorPoint = Vector2.new(1,.5),
        Position = UDim2.new(1,-8,.5,0),
        Size = UDim2.new(0,50,0,23),
        BackgroundColor3 = state and COLORS.GREEN or COLORS.RED_DARK,
        BorderSizePixel = 0,
        Text = state and "ON" or "OFF",
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamBold,
        TextSize = 10
    })
    corner(sw,12)

    sw.MouseButton1Click:Connect(function()
        local desired = not state
        local action = desired and onAction or offAction

        local ok, msg = adminAction(action, {enabled = desired})
        if ok then
            state = desired
            sw.Text = state and "ON" or "OFF"
            sw.BackgroundColor3 = state and COLORS.GREEN or COLORS.RED_DARK
        end

        notify(gui, (ok and "✓ " or "✕ ") .. tostring(msg))
    end)

    return frame
end

local function addTab(name)
    local btn = new("TextButton", {
        Parent = tabsFrame,
        Size = UDim2.new(1,-2,0,32),
        BackgroundColor3 = COLORS.BUTTON,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = COLORS.TEXT,
        Font = Enum.Font.GothamMedium,
        TextSize = 12
    })
    corner(btn,9)
    tabButtons[name] = btn

    btn.MouseButton1Click:Connect(function()
        for _,info in pairs(pages) do
            info.frame.Visible = false
        end
        for _,other in pairs(tabButtons) do
            other.BackgroundColor3 = COLORS.BUTTON
        end

        local info = pages[name]
        if info then
            info.frame.Visible = true
            pageTitle.Text = name
            pageSub.Text = info.subtitle
            btn.BackgroundColor3 = COLORS.RED_DARK
        end
    end)
end

--==============================================================--
-- PAGES
--==============================================================--

local principal = createPage("Principal","Atalhos e automações principais")
local eggs = createPage("Ovos","Carry, place, hatch e filtros")
local pets = createPage("Pets","Pets, gear e trails")
local fuse = createPage("Fuse","Seleção e ciclo de fusion")
local treadmill = createPage("Esteira","Treino e upgrades")
local base = createPage("Base","Plot e upgrades")
local rewards = createPage("Rewards","Index, group e offline")
local teleport = createPage("Teleporte","Destinos do jogo")
local esp = createPage("ESP","Visualização autorizada/debug")
local server = createPage("Server","Rejoin e server hop")

for _,name in ipairs({
    "Principal","Ovos","Pets","Fuse","Esteira",
    "Base","Rewards","Teleporte","ESP","Server"
}) do
    addTab(name)
end

-- PRINCIPAL
do
    local s = createSection(principal,"Automação")
    toggle(s,"Auto Steal","AutoStealOn","AutoStealOff")
    toggle(s,"Auto Return","AutoReturnOn","AutoReturnOff")
    toggle(s,"Auto Place Eggs","AutoPlaceOn","AutoPlaceOff")
    toggle(s,"Auto Hatch","AutoHatchOn","AutoHatchOff")
    toggle(s,"Auto Treadmill","AutoTreadmillOn","AutoTreadmillOff")
    toggle(s,"Auto Fuse","AutoFuseOn","AutoFuseOff")

    local q = createSection(principal,"Ações rápidas")
    actionButton(q,"Voltar para Base","ReturnToBase")
    actionButton(q,"Equipar Best Pets","EquipBestPets")
    actionButton(q,"Claim All Rewards","ClaimAllRewards")
    actionButton(q,"Server Hop","ServerHop")
end

-- EGGS
do
    local s1 = createSection(eggs,"Ovos")
    toggle(s1,"Auto Roubar Ovo","AutoStealOn","AutoStealOff")
    toggle(s1,"Auto Carry","AutoCarryOn","AutoCarryOff")
    toggle(s1,"Auto Drop","AutoDropOn","AutoDropOff")
    toggle(s1,"Auto Place","AutoPlaceOn","AutoPlaceOff")
    toggle(s1,"Auto Hatch Ready","AutoHatchOn","AutoHatchOff")
    toggle(s1,"Auto Sell Eggs","AutoSellEggsOn","AutoSellEggsOff")

    local s2 = createSection(eggs,"Filtros")
    actionButton(s2,"Prioridade por Raridade","SetEggRarityFilter")
    actionButton(s2,"Prioridade por Mutação","SetEggMutationFilter")
    actionButton(s2,"Priorizar Ovo Grande","ToggleBigEggPriority")
    actionButton(s2,"Abrir Lista de Ovos","ListEggs")
end

-- PETS
do
    local s = createSection(pets,"Pets / Equipamento")
    actionButton(s,"Lista de Pets","ListPets")
    actionButton(s,"Equipar Best Pets","EquipBestPets")
    actionButton(s,"Equipar Best Gear","EquipBestGear")
    actionButton(s,"Equipar Best Trail","EquipBestTrail")
    actionButton(s,"Comprar Best Trail","BuyBestTrail")
    actionButton(s,"Mostrar Mutações","ListPetMutations")
end

-- FUSE
do
    local s1 = createSection(fuse,"Auto Fuse")
    toggle(s1,"Auto Fuse","AutoFuseOn","AutoFuseOff")
    toggle(s1,"Nunca Fundir Mutados","ProtectMutatedOn","ProtectMutatedOff",true)
    toggle(s1,"Nunca Fundir Equipados","ProtectEquippedOn","ProtectEquippedOff",true)
    toggle(s1,"Manter Favoritos","ProtectFavoritesOn","ProtectFavoritesOff",true)

    local s2 = createSection(fuse,"Controle")
    actionButton(s2,"Selecionar Raridades","SetFuseRarities")
    actionButton(s2,"Selecionar Mutações","SetFuseMutations")
    actionButton(s2,"Executar Fuse Agora","RunFuseOnce")
    actionButton(s2,"Mostrar Candidatos","ListFuseCandidates")
end

-- TREADMILL
do
    local s1 = createSection(treadmill,"Treino")
    toggle(s1,"Auto Treadmill Training","AutoTreadmillOn","AutoTreadmillOff")
    actionButton(s1,"Ir para Esteira","GoToTreadmill")
    actionButton(s1,"Parar Treino","StopTreadmill")
    actionButton(s1,"Sair da Esteira","DismountTreadmill")

    local s2 = createSection(treadmill,"Upgrades")
    actionButton(s2,"Mostrar Speed Power","GetSpeedPower")
    actionButton(s2,"Mostrar Nível","GetTreadmillLevel")
    toggle(s2,"Auto Upgrade Treadmill","AutoUpgradeTreadmillOn","AutoUpgradeTreadmillOff")
end

-- BASE
do
    local s = createSection(base,"Base / Plot")
    actionButton(s,"Voltar para Base","ReturnToBase")
    actionButton(s,"Mostrar Meu Plot","GetMyPlot")
    toggle(s,"Auto Upgrade Base","AutoUpgradeBaseOn","AutoUpgradeBaseOff")
    toggle(s,"Auto Buy Upgrades","AutoBuyUpgradesOn","AutoBuyUpgradesOff")
    actionButton(s,"Mostrar Guard Areas","ListGuardAreas")
end

-- REWARDS
do
    local s = createSection(rewards,"Rewards")
    toggle(s,"Auto Claim Index","AutoClaimIndexOn","AutoClaimIndexOff")
    toggle(s,"Auto Group Reward","AutoGroupRewardOn","AutoGroupRewardOff")
    actionButton(s,"Claim Offline Earnings","ClaimOfflineEarnings")
    actionButton(s,"Claim All","ClaimAllRewards")
end

-- TELEPORT
do
    local s = createSection(teleport,"Destinos")
    actionButton(s,"Base","TeleportBase")
    actionButton(s,"Ovo","TeleportEgg")
    actionButton(s,"Esteira","TeleportTreadmill")
    actionButton(s,"Fuse Machine","TeleportFuse")
    actionButton(s,"Loja","TeleportShop")
    actionButton(s,"Incubadora","TeleportIncubator")
end

-- ESP
do
    local s = createSection(esp,"ESP / Debug visual")
    toggle(s,"ESP Ovos","EspEggsOn","EspEggsOff")
    toggle(s,"ESP Pets","EspPetsOn","EspPetsOff")
    toggle(s,"ESP Guards","EspGuardsOn","EspGuardsOff")
    toggle(s,"ESP Players","EspPlayersOn","EspPlayersOff")
    toggle(s,"ESP Plots","EspPlotsOn","EspPlotsOff")
    toggle(s,"ESP Machines","EspMachinesOn","EspMachinesOff")
end

-- SERVER
do
    local s = createSection(server,"Servidor")
    actionButton(s,"Rejoin Server","Rejoin")
    actionButton(s,"Server Hop","ServerHop")
    toggle(s,"Auto Server Hop","AutoServerHopOn","AutoServerHopOff")
    toggle(s,"Evitar Visitados","AvoidVisitedOn","AvoidVisitedOff",true)
end

search:GetPropertyChangedSignal("Text"):Connect(function()
    local q = string.lower(search.Text)
    for name,btn in pairs(tabButtons) do
        btn.Visible = q == "" or string.find(string.lower(name),q,1,true) ~= nil
    end
end)

minBtn.MouseButton1Click:Connect(function()
    main.Visible = false
    mini.Visible = true
end)

mini.MouseButton1Click:Connect(function()
    mini.Visible = false
    main.Visible = true
end)

closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

pages.Principal.frame.Visible = true
tabButtons.Principal.BackgroundColor3 = COLORS.RED_DARK

task.defer(function()
    if isAuthorizedProject() then
        rebuildRemoteIndex()
        notify(gui, "✓ Integração SAE ativa • remotes: " .. tostring(#REMOTE_LIST))
    else
        notify(gui, "✕ Build bloqueado fora do projeto autorizado")
    end
end)

--==============================================================--
-- NOTES
-- Direct integration is intentionally allowlisted to the known SAE systems.
-- Unknown argument signatures fail protected instead of flooding endpoints.
-- If CafeinaAdmin.Action exists, it is used as a fallback for exact actions
-- that your server implements more reliably than the client heuristic layer.
--==============================================================--
