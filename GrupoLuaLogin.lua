--[[
    GRUPO LUA — LOGIN V7 / ROBLOX ASSET

    Visual:
      • imagem oficial Roblox: rbxassetid://91124214069969
      • painel maior: 500 x 250
      • campo de chave translúcido
      • botão VERIFICAR translúcido, mantendo contraste do texto
      • imagem continua totalmente visível ao redor dos controles

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

local function replaceOnce(text, pattern, replacement, label)
    local patched, count = text:gsub(pattern, replacement, 1)
    if count ~= 1 then
        error("[GRUPO LUA] Falha ao aplicar ajuste: " .. tostring(label))
    end
    return patched
end

-- Imagem oficial do Roblox.
source = replaceOnce(
    source,
    'local function loadBackgroundAsset%(%)%s.-%s-end%s-%s-local Parent',
    'local function loadBackgroundAsset()\n    return "' .. IMAGE_ASSET .. '"\nend\n\nlocal Parent',
    "imagem Roblox"
)

-- Mantém proporção 2:1, mas aumenta o painel.
source = replaceOnce(source, 'WIDTH = 430,', 'WIDTH = 500,', "largura")
source = replaceOnce(source, 'HEIGHT = 215,', 'HEIGHT = 250,', "altura")

-- Campo da chave um pouco maior e translúcido.
source = replaceOnce(
    source,
    'InputBorder.Size = UDim2.fromOffset%(220, 40%)',
    'InputBorder.Size = UDim2.fromOffset(250, 42)',
    "tamanho do campo"
)
source = replaceOnce(
    source,
    'InputHolder.BackgroundTransparency = 0%.08',
    'InputHolder.BackgroundTransparency = 0.42',
    "transparência do campo"
)

-- Botão maior e translúcido.
source = replaceOnce(
    source,
    'Verify.Size = UDim2.fromOffset%(220, 36%)',
    'Verify.Size = UDim2.fromOffset(250, 38)',
    "tamanho do botão"
)
source = replaceOnce(
    source,
    'Verify.BackgroundColor3 = COLORS.RED%s-Verify.BorderSizePixel = 0',
    'Verify.BackgroundColor3 = COLORS.RED\nVerify.BackgroundTransparency = 0.38\nVerify.BorderSizePixel = 0',
    "transparência do botão"
)

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
