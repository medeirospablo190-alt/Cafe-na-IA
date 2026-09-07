-- CAFEINA • UNIVERSAL LOADSTRING CAPTURE V1
-- Captura qualquer fonte passada a loadstring e deixa executar normalmente.

local ENV = (getgenv and getgenv()) or _G
local ORIGINAL_LOADSTRING = loadstring

if type(ORIGINAL_LOADSTRING) ~= "function" then
    warn("[UNIVERSAL CAPTURE] loadstring indisponivel")
    return
end

pcall(function()
    local old = ENV.__CAFEINA_UNIVERSAL_CAPTURE
    if old and type(old.Stop) == "function" then old.Stop() end
end)

local state = {
    enabled = true,
    count = 0,
    duplicateCount = 0,
    seen = {},
    captures = {},
    hookMode = "none",
}

local function hashSource(src)
    local h = 5381
    for i = 1, #src do
        h = (h * 33 + string.byte(src, i)) % 4294967296
    end
    return string.format("%08x-%d", h, #src)
end

local function classify(src)
    local lower = string.lower(src)
    if string.find(lower, "protected by", 1, true)
        or string.find(lower, "obfuscator", 1, true)
        or string.find(lower, "obfuscated", 1, true) then
        return "obfuscated"
    end
    if string.find(src, "FireServer", 1, true)
        or string.find(src, "InvokeServer", 1, true) then
        return "remote_logic"
    end
    if string.find(src, "CreateWindow", 1, true)
        or string.find(src, "AddTab", 1, true) then
        return "ui_or_menu"
    end
    return "source"
end

local function saveCapture(src, chunkName, index)
    if not state.enabled or type(src) ~= "string" then return end

    local hash = hashSource(src)
    if state.seen[hash] then
        state.duplicateCount = state.duplicateCount + 1
        return
    end
    state.seen[hash] = true

    local item = {
        index = index,
        hash = hash,
        bytes = #src,
        chunkName = tostring(chunkName or ""),
        kind = classify(src),
        source = src,
    }

    state.captures[#state.captures + 1] = item
    state.count = state.count + 1

    if type(writefile) == "function" then
        local name = string.format("CafeinaCapture_%04d.lua", index)
        pcall(function() writefile(name, src) end)
    end

    print(string.format(
        "[UNIVERSAL CAPTURE] #%d • %d bytes • %s",
        index, #src, item.kind
    ))
end

local nextIndex = 0
local function observe(src, chunkName)
    if not state.enabled or type(src) ~= "string" then return end
    nextIndex = nextIndex + 1
    local index = nextIndex
    task.spawn(function()
        saveCapture(src, chunkName, index)
    end)
end

local installed = false

if type(hookfunction) == "function" then
    local oldLoadstring
    local wrapper = function(src, chunkName)
        observe(src, chunkName)
        return oldLoadstring(src, chunkName)
    end

    if type(newcclosure) == "function" then
        local ok, wrapped = pcall(newcclosure, wrapper)
        if ok and type(wrapped) == "function" then wrapper = wrapped end
    end

    local ok, old = pcall(function()
        return hookfunction(ORIGINAL_LOADSTRING, wrapper)
    end)

    if ok and type(old) == "function" then
        oldLoadstring = old
        installed = true
        state.hookMode = "hookfunction"
    end
end

if not installed then
    local replacement = function(src, chunkName)
        observe(src, chunkName)
        return ORIGINAL_LOADSTRING(src, chunkName)
    end

    local ok = pcall(function()
        ENV.loadstring = replacement
    end)

    if ok and ENV.loadstring == replacement then
        installed = true
        state.hookMode = "environment"
    end
end

if not installed then
    warn("[UNIVERSAL CAPTURE] executor nao permitiu interceptar loadstring")
    return
end

local function exportCombined()
    local parts = {}
    table.sort(state.captures, function(a, b) return a.index < b.index end)

    for _, item in ipairs(state.captures) do
        parts[#parts + 1] = string.format(
            "\n--[[ CAPTURE #%d | %d bytes | %s | %s ]]\n",
            item.index, item.bytes, item.kind, item.hash
        )
        parts[#parts + 1] = item.source
        parts[#parts + 1] = "\n"
    end

    local text = table.concat(parts)
    if type(writefile) == "function" then
        pcall(function() writefile("CafeinaCapture_ALL.lua", text) end)
    end
    return text
end

local function stop()
    state.enabled = false
    print(string.format(
        "[UNIVERSAL CAPTURE] parado • capturas=%d • duplicadas=%d",
        state.count, state.duplicateCount
    ))
end

ENV.__CAFEINA_UNIVERSAL_CAPTURE = {
    State = state,
    Stop = stop,
    ExportCombined = exportCombined,
    GetCaptures = function() return state.captures end,
}

print("[UNIVERSAL CAPTURE] ARMADO ✓ • PASS-THROUGH")
print("[UNIVERSAL CAPTURE] modo:", state.hookMode)
print("[UNIVERSAL CAPTURE] rode qualquer menu normalmente")
print("[UNIVERSAL CAPTURE] o codigo capturado continua sendo executado")
