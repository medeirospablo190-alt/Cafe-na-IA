--[[
    GRUPO LUA — LOGIN BOOTSTRAP V2

    Correção da imagem:
    • remove o cache antigo do JPEG progressivo;
    • usa a nova imagem JPEG baseline hospedada no GitHub;
    • adiciona aliases extras de custom asset para executores mobile;
    • mantém o login/validação FREE/VIP da versão estável.
]]

-- Compatibilidade extra para executores que usam outros nomes
-- para transformar um arquivo local em asset de GUI.
pcall(function()
    if type(getcustomasset) ~= "function" then
        if type(getasset) == "function" then
            getcustomasset = getasset
        elseif type(customasset) == "function" then
            getcustomasset = customasset
        elseif type(syn) == "table" and type(syn.getcustomasset) == "function" then
            getcustomasset = syn.getcustomasset
        end
    end
end)

-- A primeira versão podia deixar um JPEG progressivo salvo no cache.
-- Alguns executores mobile não conseguem renderizar esse formato.
pcall(function()
    if type(isfile) == "function" and type(delfile) == "function" then
        if isfile("grupo_lua_login_v1.jpg") then
            delfile("grupo_lua_login_v1.jpg")
        end
    end
end)

-- Core estável do login. A URL da imagem dentro dele aponta para /main/,
-- então agora recebe automaticamente a imagem baseline corrigida.
local CORE_URL = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/f4bbc939ae0311d1691eaa41ddee4e9351ed3afd/GrupoLuaLogin.lua"

local ok, source = pcall(function()
    return game:HttpGet(CORE_URL, true)
end)

if not ok or type(source) ~= "string" or source == "" then
    error("[GRUPO LUA] Não foi possível baixar o login.")
end

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
