--==============================================================--
-- CAFEINA • EXECUTOR TRACE COLLECTOR V1.0
-- Passive mapper for executor UI/capabilities.
-- Uses the existing CAFEINA V3 gateway + GitHub mirror confirmation.
-- Does NOT decompile, dump callbacks/functions, read files/clipboard,
-- inspect getgc/debug state, or collect TextBox contents.
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local ENV = (getgenv and getgenv()) or _G

local C = {
    VERSION = "CAFEINA_EXECUTOR_TRACE_V1_3",
    PURPOSE = "executor_ui_mapping",
    BASE = "https://cafe-na-ia.onrender.com/api/inventory-trace-v3",
    HEALTH = "https://cafe-na-ia.onrender.com/api/inventory-trace-v3/health",
    OBSERVE_SECONDS = 24,
    SCAN_INTERVAL = 1.25,
    MAX_RECORDS = 5200,
    MAX_DYNAMIC = 2200,
    MAX_NODES_PER_ROOT = 6500,
    RECORDS_PER_BATCH = 100,
    RETRIES = 4,
    RETRY_BASE = 0.85,
    STATUS_GUI = "CafeinaExecutorTraceV1",
}

local function pick(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
end

local synReq, httpReq
pcall(function() if syn and type(syn.request) == "function" then synReq = syn.request end end)
pcall(function() if http and type(http.request) == "function" then httpReq = http.request end end)

local REQUEST = pick(rawget(ENV, "request"), rawget(ENV, "http_request"), request, http_request, httpReq, synReq)
local WRITEFILE = pick(rawget(ENV, "writefile"), writefile)
local GETHUI = pick(rawget(ENV, "gethui"), gethui)

local function iso()
    local ok, v = pcall(function() return DateTime.now():ToIsoDate() end)
    return ok and v or tostring(os.time())
end

local function prop(x, name)
    local ok, v = pcall(function() return x[name] end)
    return ok and v or nil
end

local function fullName(x)
    local ok, v = pcall(function() return x:GetFullName() end)
    return ok and v or tostring(x)
end

local function text(v, cap)
    local s = tostring(v or "")
    cap = cap or 600
    return #s > cap and (string.sub(s, 1, cap) .. "...[truncated]") or s
end

local function rgb(v)
    if typeof(v) ~= "Color3" then return nil end
    return { r = math.floor(v.R * 255 + 0.5), g = math.floor(v.G * 255 + 0.5), b = math.floor(v.B * 255 + 0.5) }
end

local function v2(v)
    if typeof(v) ~= "Vector2" then return nil end
    return { x = math.floor(v.X + 0.5), y = math.floor(v.Y + 0.5) }
end

local function u1(v)
    if typeof(v) ~= "UDim" then return nil end
    return { scale = v.Scale, offset = v.Offset }
end

local function u2(v)
    if typeof(v) ~= "UDim2" then return nil end
    return { xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset }
end

local function simple(v)
    local t = typeof(v)
    if v == nil or t == "boolean" or t == "number" then return v end
    if t == "string" then return text(v, 220) end
    if t == "Color3" then return rgb(v) end
    if t == "Vector2" then return v2(v) end
    if t == "Vector3" then return { x = v.X, y = v.Y, z = v.Z } end
    if t == "UDim" then return u1(v) end
    if t == "UDim2" then return u2(v) end
    if t == "EnumItem" then return tostring(v) end
    return text(v, 220)
end

local function attrs(x)
    local ok, a = pcall(function() return x:GetAttributes() end)
    if not ok or type(a) ~= "table" then return nil end
    local out, n = {}, 0
    for k, v in pairs(a) do
        n += 1
        if n > 24 then break end
        out[tostring(k)] = simple(v)
    end
    return next(out) and out or nil
end

local function tags(x)
    local ok, a = pcall(CollectionService.GetTags, CollectionService, x)
    if not ok or type(a) ~= "table" or #a == 0 then return nil end
    table.sort(a)
    while #a > 20 do table.remove(a) end
    return a
end

local sensitive = { "key", "chave", "token", "password", "senha", "secret", "auth", "license", "licence" }
local function sensitiveBox(name, placeholder)
    local s = string.lower(tostring(name or "") .. " " .. tostring(placeholder or ""))
    for _, w in ipairs(sensitive) do
        if string.find(s, w, 1, true) then return true end
    end
    return false
end

local uiComponentClasses = {
    UICorner=true, UIStroke=true, UIScale=true, UIGradient=true, UIListLayout=true,
    UIGridLayout=true, UITableLayout=true, UIPageLayout=true, UIPadding=true,
    UIAspectRatioConstraint=true, UISizeConstraint=true, UITextSizeConstraint=true,
}

local function interesting(x)
    return x:IsA("ScreenGui") or x:IsA("GuiObject") or uiComponentClasses[x.ClassName] == true
end

local function snapshot(x, source, rootName, rel, depth)
    local r = {
        kind = "executor_ui_node", source = source, rootName = rootName, path = rel,
        depth = depth, className = x.ClassName, name = x.Name, fullName = fullName(x),
        attrs = attrs(x), tags = tags(x),
    }

    if x:IsA("ScreenGui") then
        r.enabled = prop(x, "Enabled")
        r.displayOrder = prop(x, "DisplayOrder")
        r.ignoreGuiInset = prop(x, "IgnoreGuiInset")
        r.resetOnSpawn = prop(x, "ResetOnSpawn")
        r.zIndexBehavior = tostring(prop(x, "ZIndexBehavior") or "")
        r.screenInsets = tostring(prop(x, "ScreenInsets") or "")
        r.safeAreaCompatibility = tostring(prop(x, "SafeAreaCompatibility") or "")
    end

    if x:IsA("GuiObject") then
        r.visible = prop(x, "Visible")
        r.active = prop(x, "Active")
        r.selectable = prop(x, "Selectable")
        r.interactable = prop(x, "Interactable")
        r.position = u2(prop(x, "Position"))
        r.size = u2(prop(x, "Size"))
        r.anchorPoint = v2(prop(x, "AnchorPoint"))
        r.absolutePosition = v2(prop(x, "AbsolutePosition"))
        r.absoluteSize = v2(prop(x, "AbsoluteSize"))
        r.backgroundColor3 = rgb(prop(x, "BackgroundColor3"))
        r.backgroundTransparency = prop(x, "BackgroundTransparency")
        r.borderSizePixel = prop(x, "BorderSizePixel")
        r.zIndex = prop(x, "ZIndex")
        r.layoutOrder = prop(x, "LayoutOrder")
        r.rotation = prop(x, "Rotation")
        r.clipsDescendants = prop(x, "ClipsDescendants")
        r.automaticSize = tostring(prop(x, "AutomaticSize") or "")
    end

    if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
        if x:IsA("TextBox") then
            local placeholder = prop(x, "PlaceholderText")
            local raw = tostring(prop(x, "Text") or "")
            r.text = sensitiveBox(x.Name, placeholder) and "<redacted_sensitive_textbox>" or "<redacted_textbox>"
            r.textLength = #raw
            r.placeholderText = text(placeholder, 300)
            r.clearTextOnFocus = prop(x, "ClearTextOnFocus")
            r.multiLine = prop(x, "MultiLine")
            r.textEditable = prop(x, "TextEditable")
        else
            r.text = text(prop(x, "Text"), 600)
        end
        r.textSize = prop(x, "TextSize")
        r.font = tostring(prop(x, "Font") or "")
        r.textColor3 = rgb(prop(x, "TextColor3"))
        r.textTransparency = prop(x, "TextTransparency")
        r.textWrapped = prop(x, "TextWrapped")
        r.richText = prop(x, "RichText")
        r.textXAlignment = tostring(prop(x, "TextXAlignment") or "")
        r.textYAlignment = tostring(prop(x, "TextYAlignment") or "")
    end

    if x:IsA("ImageLabel") or x:IsA("ImageButton") then
        r.image = text(prop(x, "Image"), 500)
        r.imageColor3 = rgb(prop(x, "ImageColor3"))
        r.imageTransparency = prop(x, "ImageTransparency")
        r.scaleType = tostring(prop(x, "ScaleType") or "")
    end

    if x:IsA("ScrollingFrame") then
        r.canvasPosition = v2(prop(x, "CanvasPosition"))
        r.canvasSize = u2(prop(x, "CanvasSize"))
        r.automaticCanvasSize = tostring(prop(x, "AutomaticCanvasSize") or "")
        r.scrollBarThickness = prop(x, "ScrollBarThickness")
    end

    if x.ClassName == "UICorner" then r.cornerRadius = u1(prop(x, "CornerRadius")) end
    if x.ClassName == "UIStroke" then
        r.color = rgb(prop(x, "Color")); r.thickness = prop(x, "Thickness"); r.transparency = prop(x, "Transparency")
    end
    if x.ClassName == "UIScale" then r.scale = prop(x, "Scale") end
    if x.ClassName == "UIGradient" then
        r.rotation = prop(x, "Rotation"); r.offset = v2(prop(x, "Offset"))
    end
    if x.ClassName == "UIListLayout" or x.ClassName == "UIGridLayout" or x.ClassName == "UITableLayout" or x.ClassName == "UIPageLayout" then
        r.fillDirection = tostring(prop(x, "FillDirection") or "")
        r.horizontalAlignment = tostring(prop(x, "HorizontalAlignment") or "")
        r.verticalAlignment = tostring(prop(x, "VerticalAlignment") or "")
        r.sortOrder = tostring(prop(x, "SortOrder") or "")
        r.padding = u1(prop(x, "Padding"))
        r.cellSize = u2(prop(x, "CellSize"))
        r.cellPadding = u2(prop(x, "CellPadding"))
    end
    if x.ClassName == "UIPadding" then
        r.paddingTop = u1(prop(x, "PaddingTop")); r.paddingBottom = u1(prop(x, "PaddingBottom"))
        r.paddingLeft = u1(prop(x, "PaddingLeft")); r.paddingRight = u1(prop(x, "PaddingRight"))
    end
    return r
end

local knownSystem = {
    RobloxGui=true, TopBarApp=true, BubbleChat=true, Chat=true, TouchGui=true,
    PurchasePromptApp=true, HeadsetDisconnectedDialog=true, VoiceChatBubbleGui=true,
    PlayerList=true, EmotesMenu=true, Freecam=true, DevConsoleMaster=true,
}
local hints = { "executor","execute","script","editor","console","inject","hub","delta","attach","scripthub","workspace" }

local function scoreRoot(root, source)
    if knownSystem[root.Name] then return -100, {} end
    local score = (source == "gethui" or source == "CoreGui") and 4 or 0
    local samples, buttons, boxes, inspected = {}, 0, 0, 0
    local lowName = string.lower(root.Name)
    for _, h in ipairs(hints) do if string.find(lowName, h, 1, true) then score += 6 break end end
    for _, d in ipairs(root:GetDescendants()) do
        inspected += 1
        if d:IsA("TextButton") or d:IsA("ImageButton") then buttons += 1 end
        if d:IsA("TextBox") then boxes += 1 end
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and #samples < 14 then
            local s = text(prop(d, "Text"), 100)
            if s ~= "" then samples[#samples + 1] = s end
        end
        if inspected >= 700 then break end
    end
    local joined = string.lower(table.concat(samples, " | "))
    for _, h in ipairs(hints) do if string.find(joined, h, 1, true) then score += 4 break end end
    if boxes > 0 then score += 1 end
    if buttons >= 4 then score += 1 end
    return score, samples
end

local function capabilities()
    local names = {
        "request","http_request","gethui","protect_gui","identifyexecutor","getexecutorname",
        "writefile","readfile","isfile","delfile","makefolder","listfiles","queue_on_teleport",
        "setclipboard","getcustomasset","getsynasset","hookmetamethod","getnamecallmethod",
        "newcclosure","getconnections","getgc","decompile",
    }
    local out = {}
    for _, name in ipairs(names) do out[name] = type(rawget(ENV, name)) == "function" end
    pcall(function() out.syn_request = syn and type(syn.request) == "function" or false end)
    pcall(function() out.syn_protect_gui = syn and type(syn.protect_gui) == "function" or false end)
    out.Drawing = type(rawget(ENV, "Drawing")) == "table"
    out.debug = type(rawget(ENV, "debug")) == "table"

    local f = pick(rawget(ENV, "identifyexecutor"), identifyexecutor)
    if f then
        local ok, a, b = pcall(f)
        if ok then out.executorIdentity = text(a, 120); out.executorVersion = text(b, 120) end
    end
    f = pick(rawget(ENV, "getexecutorname"), getexecutorname)
    if f then
        local ok, a, b = pcall(f)
        if ok then out.executorName = text(a, 120); out.executorNameVersion = text(b, 120) end
    end
    return out
end

local records, dynamicCount = {}, 0
local function add(row, dynamic)
    if #records >= C.MAX_RECORDS then return false end
    if dynamic then
        if dynamicCount >= C.MAX_DYNAMIC then return false end
        dynamicCount += 1
    end
    records[#records + 1] = row
    return true
end

local statusGui, statusLabel, statusFill
local function makeStatus()
    pcall(function() local old = CoreGui:FindFirstChild(C.STATUS_GUI); if old then old:Destroy() end end)
    local gui = Instance.new("ScreenGui")
    gui.Name = C.STATUS_GUI; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 100000
    local parent = CoreGui
    if GETHUI then local ok, hui = pcall(GETHUI); if ok and typeof(hui) == "Instance" then parent = hui end end
    gui.Parent = parent

    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(260, 72); f.Position = UDim2.new(0.5, -130, 0, 36)
    f.BackgroundColor3 = Color3.fromRGB(10,10,12); f.BorderSizePixel = 0; f.Parent = gui
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = f
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1; t.Position = UDim2.fromOffset(12,8); t.Size = UDim2.new(1,-24,0,20)
    t.Font = Enum.Font.GothamBold; t.TextSize = 12; t.TextColor3 = Color3.fromRGB(245,245,248)
    t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = "CAFEÍNA • EXECUTOR TRACE • V1.3"; t.Parent = f
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Position = UDim2.fromOffset(12,31); l.Size = UDim2.new(1,-24,0,17)
    l.Font = Enum.Font.Gotham; l.TextSize = 10; l.TextColor3 = Color3.fromRGB(210,210,216)
    l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = "Preparando..."; l.Parent = f
    local bg = Instance.new("Frame")
    bg.Position = UDim2.fromOffset(12,56); bg.Size = UDim2.new(1,-24,0,7)
    bg.BackgroundColor3 = Color3.fromRGB(35,35,40); bg.BorderSizePixel = 0; bg.Parent = f
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1,0); bc.Parent = bg
    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0,1); fill.BackgroundColor3 = Color3.fromRGB(210,210,220)
    fill.BorderSizePixel = 0; fill.Parent = bg
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1,0); fc.Parent = fill
    statusGui, statusLabel, statusFill = gui, l, fill
end

local function status(s, p)
    if statusLabel then statusLabel.Text = tostring(s) end
    if statusFill and p then statusFill.Size = UDim2.fromScale(math.clamp(p,0,1),1) end
    print("[EXECUTOR TRACE] " .. tostring(s))
end

local function rawRequest(options)
    if not REQUEST then return false, nil, "executor_request_unavailable" end
    local last = "unknown"
    for attempt = 1, C.RETRIES do
        local ok, response = pcall(REQUEST, options)
        if ok and type(response) == "table" then
            local code = tonumber(response.StatusCode or response.Status or response.status or response.status_code) or 0
            if code >= 200 and code < 300 then return true, response, nil end
            last = "HTTP " .. tostring(code) .. " " .. tostring(response.Body or response.body or "")
            if code == 429 or code >= 500 then
                task.wait(C.RETRY_BASE * attempt)
            else
                break
            end
        else
            last = tostring(response)
            task.wait(C.RETRY_BASE * attempt)
        end
    end
    return false, nil, last
end

local function getJson(url)
    local ok, response, err = rawRequest({ Url = url, Method = "GET", Headers = { Accept = "application/json" } })
    if not ok then return false, nil, err end
    local good, data = pcall(HttpService.JSONDecode, HttpService, response.Body or response.body or "{}")
    if not good then return false, nil, tostring(data) end
    return true, data, nil
end

local function postRaw(url, body)
    local ok, response, err = rawRequest({
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
        Body = body,
    })
    if not ok then return false, nil, err end
    local good, data = pcall(HttpService.JSONDecode, HttpService, response.Body or response.body or "{}")
    if not good or type(data) ~= "table" then return false, nil, "invalid_api_response" end
    if data.ok ~= true then return false, data, tostring(data.message or "api_not_ok") end
    if type(data.github) ~= "table" or data.github.configured ~= true or data.github.mirrored ~= true then
        return false, data, tostring((data.github and data.github.error) or "github_not_confirmed")
    end
    return true, data, nil
end

local function health()
    local ok, data, err = getJson(C.HEALTH)
    if not ok then return false, err end
    if type(data) ~= "table" or data.ok ~= true or data.githubMirrorConfigured ~= true then
        return false, "github_mirror_not_ready"
    end
    return true, data
end

local function sourceRoots()
    local out, seen = {}, {}
    local function take(source, container)
        if typeof(container) ~= "Instance" or seen[container] then return end
        seen[container] = true
        for _, child in ipairs(container:GetChildren()) do out[#out + 1] = {source=source, root=child} end
    end
    if GETHUI then local ok, hui = pcall(GETHUI); if ok then take("gethui", hui) end end
    take("CoreGui", CoreGui)
    local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:FindFirstChild("PlayerGui")
    if pg then take("PlayerGui", pg) end
    return out
end

local function selectedRoots(recordSummary)
    local out = {}
    for _, item in ipairs(sourceRoots()) do
        local root = item.root
        if root.Name ~= C.STATUS_GUI then
            local score, samples = scoreRoot(root, item.source)
            local selected = score >= 4
            if recordSummary then
                add({kind="executor_ui_root_summary",source=item.source,name=root.Name,className=root.ClassName,
                    fullName=fullName(root),score=score,selected=selected,descendantCount=#root:GetDescendants(),textSamples=samples})
            end
            if selected then out[#out + 1] = item end
        end
    end
    return out
end

local function walk(item, callback)
    local n = 0
    local function visit(x, rel, depth)
        if n >= C.MAX_NODES_PER_ROOT then return end
        if interesting(x) then n += 1; callback(x, item.source, item.root.Name, rel, depth) end
        if n >= C.MAX_NODES_PER_ROOT then return end
        for _, child in ipairs(x:GetChildren()) do
            visit(child, rel .. "/" .. child.Name, depth + 1)
            if n >= C.MAX_NODES_PER_ROOT then break end
        end
    end
    visit(item.root, item.root.Name, 0)
    return n
end

local function sig(r)
    local p = {r.className,r.name,r.path,tostring(r.visible),tostring(r.enabled),tostring(r.text),
        tostring(r.textLength),tostring(r.image),tostring(r.zIndex),tostring(r.layoutOrder),
        tostring(r.backgroundTransparency),tostring(r.rotation)}
    if r.position then p[#p+1] = table.concat({r.position.xs,r.position.xo,r.position.ys,r.position.yo},",") end
    if r.size then p[#p+1] = table.concat({r.size.xs,r.size.xo,r.size.ys,r.size.yo},",") end
    if r.absolutePosition then p[#p+1] = r.absolutePosition.x .. "," .. r.absolutePosition.y end
    if r.absoluteSize then p[#p+1] = r.absoluteSize.x .. "," .. r.absoluteSize.y end
    return table.concat(p,"\31")
end

local last = setmetatable({}, {__mode="k"})
local function firstScan()
    local roots, total = selectedRoots(true), 0
    for _, item in ipairs(roots) do
        total += walk(item, function(x,source,root,rel,depth)
            local r = snapshot(x,source,root,rel,depth)
            if add(r) then last[x] = {sig=sig(r),row=r} end
        end)
    end
    return #roots, total
end

local function rescan(index)
    local now = setmetatable({}, {__mode="k"})
    local roots, total = selectedRoots(false), 0
    for _, item in ipairs(roots) do
        total += walk(item, function(x,source,root,rel,depth)
            local r, old = snapshot(x,source,root,rel,depth), last[x]
            local s = sig(r); now[x] = {sig=s,row=r}
            if not old then local e=table.clone(r); e.kind="executor_ui_added"; e.scanIndex=index; add(e,true)
            elseif old.sig ~= s then local e=table.clone(r); e.kind="executor_ui_changed"; e.scanIndex=index; add(e,true) end
        end)
    end
    for x, old in pairs(last) do
        if now[x] == nil then add({kind="executor_ui_removed",source=old.row.source,rootName=old.row.rootName,
            path=old.row.path,className=old.row.className,name=old.row.name,scanIndex=index},true) end
    end
    last = now
    return #roots, total
end

local runId, capturedAt = HttpService:GenerateGUID(false), iso()
local caps = capabilities()
local cam = Workspace.CurrentCamera
local viewport = cam and cam.ViewportSize or Vector2.zero
add({kind="executor_trace_session",version=C.VERSION,purpose=C.PURPOSE,runId=runId,capturedAt=capturedAt,
    gameId=game.GameId,placeId=game.PlaceId,placeVersion=game.PlaceVersion,userId=LP.UserId,username=LP.Name,
    device={touchEnabled=UserInputService.TouchEnabled,keyboardEnabled=UserInputService.KeyboardEnabled,
        mouseEnabled=UserInputService.MouseEnabled,gamepadEnabled=UserInputService.GamepadEnabled,viewport=v2(viewport)}})
add({kind="executor_capabilities",capabilities=caps})

local function postExact(bodyText, batchIndex)
    local ok, data, err = postRaw(C.BASE .. "/batch", bodyText)
    if not ok then return false, err end
    if tonumber(data.batchIndex) ~= batchIndex then
        return false, "batch_ack_mismatch"
    end
    return true, data
end

local function safeString(value)
    local s = tostring(value or "")
    local ok = pcall(HttpService.JSONEncode, HttpService, s)
    if ok then return s end
    local out = table.create(#s)
    for i = 1, #s do
        local b = string.byte(s, i)
        if b >= 32 and b <= 126 then
            out[#out + 1] = string.char(b)
        elseif b == 9 then
            out[#out + 1] = "\\t"
        elseif b == 10 then
            out[#out + 1] = "\\n"
        elseif b == 13 then
            out[#out + 1] = "\\r"
        else
            out[#out + 1] = "?"
        end
    end
    return table.concat(out)
end

local function jsonSafe(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 10 then return "<max_depth>" end

    local t = typeof(value)
    if value == nil or t == "boolean" then return value end
    if t == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge then return "<inf>" end
        if value == -math.huge then return "<-inf>" end
        return value
    end
    if t == "string" then return safeString(value) end

    if t == "table" then
        if seen[value] then return "<cycle>" end
        seen[value] = true

        local count, maxIndex, arrayLike = 0, 0, true
        for k in pairs(value) do
            count += 1
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                arrayLike = false
            else
                maxIndex = math.max(maxIndex, k)
            end
            if count > 12000 then break end
        end
        if arrayLike and maxIndex ~= count then arrayLike = false end

        local out
        if arrayLike then
            out = table.create(count)
            for i = 1, count do
                out[i] = jsonSafe(value[i], depth + 1, seen)
            end
        else
            out = {}
            local n = 0
            for k, v in pairs(value) do
                n += 1
                if n > 12000 then
                    out["<truncated>"] = true
                    break
                end
                out[safeString(k)] = jsonSafe(v, depth + 1, seen)
            end
        end

        seen[value] = nil
        return out
    end

    if t == "Instance" then
        return { type = "Instance", className = value.ClassName, name = safeString(value.Name), path = safeString(fullName(value)) }
    end

    if t == "Vector2" then return { x = value.X, y = value.Y } end
    if t == "Vector3" then return { x = value.X, y = value.Y, z = value.Z } end
    if t == "Color3" then return rgb(value) end
    if t == "UDim" then return u1(value) end
    if t == "UDim2" then return u2(value) end
    if t == "EnumItem" then return tostring(value) end

    return safeString(value)
end

local function encodeBody(body)
    local safeOk, sanitized = pcall(jsonSafe, body)
    if not safeOk then return nil, "json_safe: " .. tostring(sanitized) end
    local ok, raw = pcall(HttpService.JSONEncode, HttpService, sanitized)
    if not ok then return nil, "json_encode_1: " .. tostring(raw) end
    sanitized.payloadBytes = #raw
    ok, raw = pcall(HttpService.JSONEncode, HttpService, sanitized)
    if not ok then return nil, "json_encode_2: " .. tostring(raw) end
    return raw, nil
end

local function cacheFailure(data)
    if not WRITEFILE then return end
    local ok, raw = pcall(HttpService.JSONEncode,HttpService,data)
    if ok then pcall(WRITEFILE,"CafeinaExecutorTraceV1_pending.json",raw) end
end

local function upload(summary)
    local idx, pos, paths = 1, 1, {}
    while pos <= #records do
        local chunk = {}
        for _ = 1, C.RECORDS_PER_BATCH do
            if pos > #records then break end
            chunk[#chunk+1] = records[pos]; pos += 1
        end
        status(string.format("Enviando lote %d...",idx),0.70 + math.min(0.22,idx*0.025))
        local body={schemaVersion=3,collector={version=C.VERSION,purpose=C.PURPOSE},
            userId=tostring(LP.UserId),username=LP.Name,capturedAt=capturedAt,gameId=game.GameId,
            placeId=game.PlaceId,placeVersion=game.PlaceVersion,runId=runId,batchIndex=idx,batchKind="data",
            payloadBytes=0,records=chunk,remotes={},stats=summary}
        local raw, encodeErr=encodeBody(body); if not raw then return false,encodeErr or "encode_unknown" end
        local ok,data=postExact(raw,idx)
        if not ok then cacheFailure({runId=runId,failedBatch=idx,error=data,body=body}); return false,data end
        if data.github and data.github.path then paths[#paths+1]=data.github.path end
        idx += 1
    end

    local manifest={
        profileDelta={knownLowValueHashes={},knownShapeHashes={},knownSemanticHashes={},knownRemoteHashes={},investigationKnowledge={},frontier={}},
        strategyDelta={},
        coverage={executorUiNodes=summary.maxNodesSeen or 0,executorDynamicRecords=dynamicCount,
            executorCandidateRoots=summary.candidateRoots or 0,executorNativeOverlayPossiblyInvisible=summary.nativeOverlayPossiblyInvisible==true},
        executorTrace={version=C.VERSION,purpose=C.PURPOSE,capabilities=caps,summary=summary,mirroredDataPaths=paths,
            privacy={textBoxContents="redacted",functionBodies="not_collected",nativeCode="not_collected",
                files="not_read",clipboard="not_read",getgc="not_called",decompile="not_called"}}
    }
    local body={schemaVersion=3,collector={version=C.VERSION,purpose=C.PURPOSE},userId=tostring(LP.UserId),
        username=LP.Name,capturedAt=capturedAt,gameId=game.GameId,placeId=game.PlaceId,placeVersion=game.PlaceVersion,
        runId=runId,batchIndex=idx,batchTotal=idx,batchKind="manifest",payloadBytes=0,records={},remotes={},
        manifest=manifest,stats=summary}
    local raw, encodeErr=encodeBody(body); if not raw then return false,encodeErr or "manifest_encode_unknown" end
    local ok,data=postExact(raw,idx)
    if not ok then cacheFailure({runId=runId,failedBatch=idx,error=data,body=body}); return false,data end
    return true,data
end

makeStatus()
status("V1.3 • Checando gateway/GitHub...",0.03)
if not REQUEST then status("ERRO: request/http_request indisponível",1); warn("[EXECUTOR TRACE] nada enviado"); return end
local preOk, preErr = health()
if not preOk then status("ERRO no preflight: "..tostring(preErr),1); warn("[EXECUTOR TRACE] preflight falhou"); return end

status("Mapeando interface do executor...",0.10)
local candidateRoots, initialNodes = firstScan()
local scans, maxRoots, maxNodes, started = 0, candidateRoots, initialNodes, os.clock()
while os.clock()-started < C.OBSERVE_SECONDS and #records < C.MAX_RECORDS do
    scans += 1
    local elapsed = os.clock()-started
    status(string.format("Observando UI... %ds/%ds",math.floor(elapsed),C.OBSERVE_SECONDS),0.12+0.53*(elapsed/C.OBSERVE_SECONDS))
    local roots,nodes = rescan(scans)
    maxRoots=math.max(maxRoots,roots); maxNodes=math.max(maxNodes,nodes)
    task.wait(C.SCAN_INTERVAL)
end

local summary={candidateRoots=maxRoots,initialNodes=initialNodes,maxNodesSeen=maxNodes,scans=scans,records=#records,
    dynamicRecords=dynamicCount,observeSeconds=math.floor(os.clock()-started+0.5),nativeOverlayPossiblyInvisible=maxRoots==0}
add({kind="executor_trace_summary",summary=summary}); summary.records=#records
status(string.format("Coleta pronta: %d registros",#records),0.68)

local ok,result=upload(summary)
if ok then
    status("UPLOAD CONFIRMADO NO GITHUB ✓",1)
    print("[EXECUTOR TRACE] runId="..runId)
    if type(result)=="table" and result.github then print("[EXECUTOR TRACE] GitHub path="..tostring(result.github.path)) end
    task.delay(10,function() pcall(function() if statusGui then statusGui:Destroy() end end) end)
else
    status("FALHA: " .. text(result, 120),1)
    warn("[EXECUTOR TRACE] upload falhou: "..tostring(result))
end

ENV.__CAFEINA_EXECUTOR_TRACE_V1={Version=C.VERSION,RunId=runId,Summary=summary,Records=records}
