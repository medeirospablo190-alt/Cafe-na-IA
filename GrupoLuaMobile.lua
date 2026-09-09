-- GRUPO LUA MOBILE • LOADER COMPACTO
-- Mantem o menu completo e restaura o tamanho original 275x365.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local ok, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaMobileCore.lua"))()
end)

if not ok then
    warn("GRUPO LUA: falha ao carregar o menu: " .. tostring(err))
    return
end

task.wait()

local gui

pcall(function()
    if gethui then
        local hui = gethui()
        gui = hui and hui:FindFirstChild("GrupoLuaMobile")
    end
end)

if not gui then
    pcall(function()
        gui = game:GetService("CoreGui"):FindFirstChild("GrupoLuaMobile")
    end)
end

if not gui then
    gui = LP:WaitForChild("PlayerGui"):FindFirstChild("GrupoLuaMobile")
end

if gui then
    local main = gui:FindFirstChild("Main")

    if main then
        main.Size = UDim2.fromOffset(275, 365)
        main.Position = UDim2.new(0, 15, 0.5, -182)
    end
end
