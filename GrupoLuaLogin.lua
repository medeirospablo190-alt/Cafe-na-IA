--[[
    GRUPO LUA — LOGIN V6 / ROBLOX ASSET

    A imagem do login agora usa diretamente o asset oficial do Roblox:
        rbxassetid://91124214069969

    Isso remove a dependência de request/writefile/getcustomasset para a FOTO.
    A validação FREE/VIP e o carregamento do menu continuam no core estável.
]]

local IMAGE_ASSET = "rbxassetid://91124214069969"

local CORE_URL =
    "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/f4bbc939ae0311d1691eaa41ddee4e9351ed3afd/GrupoLuaLogin.lua"

local ok, source = pcall(function()
    return game:HttpGet(CORE_URL, true)
end)

if not ok or type(source) ~= "string" or source == "" then
    error("[GRUPO LUA] Não foi possível baixar o login.")
end

local patched, count = source:gsub(
    'local function loadBackgroundAsset%(%)%s.-%s-end%s-%s-local Parent',
    'local function loadBackgroundAsset()\n    return "' .. IMAGE_ASSET .. '"\nend\n\nlocal Parent',
    1
)

source = nil

if count ~= 1 then
    error("[GRUPO LUA] Não foi possível aplicar a imagem Roblox ao login.")
end

local fn, compileError = loadstring(patched)
patched = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
