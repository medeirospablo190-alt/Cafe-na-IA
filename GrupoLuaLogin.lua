--[[
    GRUPO LUA — LOGIN PROTECTED RUNTIME WRAPPER
    Hotfix mobile: impede chaves longas de vazarem para fora do campo de login.

    O build principal continua ofuscado e é carregado por commit imutável.
]]

local BUILD_COMMIT = "8b891060ec7919b1093c686f2286c8b88dd7b9a5"
local BUILD_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/" .. BUILD_COMMIT .. "/GrupoLuaLogin.lua"

local function guiRoots()
    local roots = {}

    pcall(function()
        if type(gethui) == "function" then
            local hui = gethui()
            if hui then
                roots[#roots + 1] = hui
            end
        end
    end)

    pcall(function()
        local core = game:GetService("CoreGui")
        if core then
            roots[#roots + 1] = core
        end
    end)

    pcall(function()
        local players = game:GetService("Players")
        local player = players.LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            roots[#roots + 1] = playerGui
        end
    end)

    return roots
end

local function patchKeyBox(keyBox)
    if not keyBox or not keyBox:IsA("TextBox") then
        return false
    end

    local holder = keyBox.Parent
    local border = holder and holder.Parent

    pcall(function()
        if holder and holder:IsA("GuiObject") then
            holder.ClipsDescendants = true
        end
        if border and border:IsA("GuiObject") then
            border.ClipsDescendants = true
        end

        keyBox.ClipsDescendants = true
        keyBox.TextWrapped = false
        keyBox.MultiLine = false
        keyBox.TextTruncate = Enum.TextTruncate.AtEnd
    end)

    keyBox.Focused:Connect(function()
        pcall(function()
            keyBox.TextTruncate = Enum.TextTruncate.None
        end)
    end)

    keyBox.FocusLost:Connect(function()
        pcall(function()
            keyBox.TextTruncate = Enum.TextTruncate.AtEnd
        end)
    end)

    return true
end

local function tryPatchLogin()
    for _, root in ipairs(guiRoots()) do
        local login = root:FindFirstChild("GrupoLuaAccess")
        if login then
            local keyBox = login:FindFirstChildWhichIsA("TextBox", true)
            if keyBox then
                return patchKeyBox(keyBox)
            end
        end
    end
    return false
end

-- O login cria a interface logo ao iniciar. A pequena janela de observação abaixo
-- também cobre executores/celulares em que o PlayerGui ou gethui aparece alguns
-- frames depois do script.
task.spawn(function()
    for _ = 1, 120 do
        if tryPatchLogin() then
            return
        end
        task.wait(0.05)
    end
end)

local ok, source = pcall(function()
    return game:HttpGet(BUILD_URL, true)
end)

if not ok or type(source) ~= "string" or source == "" then
    warn("[GRUPO LUA] Não foi possível carregar o build protegido do login.")
    return
end

local compiled, compileError = loadstring(source)
if not compiled then
    warn("[GRUPO LUA] Falha ao preparar o build protegido: " .. tostring(compileError))
    return
end

return compiled()
