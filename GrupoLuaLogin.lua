--[[
    GRUPO LUA — LOGIN V8 / GLASS TRANSPARENT

    Visual:
      • imagem oficial Roblox: rbxassetid://91124214069969
      • painel 500 x 250
      • campo da chave bem transparente, deixando a foto visível
      • botão VERIFICAR transparente, sem fundo vermelho
      • bordas claras discretas para os controles continuarem visíveis

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

-- Mantém a proporção 2:1 e o tamanho maior.
source = replaceOnce(source, 'WIDTH = 430,', 'WIDTH = 500,', "largura")
source = replaceOnce(source, 'HEIGHT = 215,', 'HEIGHT = 250,', "altura")

-- Campo da chave maior.
source = replaceOnce(
    source,
    'InputBorder.Size = UDim2.fromOffset%(220, 40%)',
    'InputBorder.Size = UDim2.fromOffset(250, 42)',
    "tamanho do campo"
)

-- Borda do campo discreta/transparente.
source = replaceOnce(
    source,
    'InputBorder.BackgroundColor3 = Color3.fromRGB%(125, 125, 128%)',
    'InputBorder.BackgroundColor3 = Color3.fromRGB(220, 220, 225)\nInputBorder.BackgroundTransparency = 0.42',
    "borda transparente do campo"
)

-- Fundo interno do campo quase transparente: a foto aparece por trás.
source = replaceOnce(
    source,
    'InputHolder.BackgroundTransparency = 0%.08',
    'InputHolder.BackgroundTransparency = 0.78',
    "transparência do campo"
)

-- Botão maior.
source = replaceOnce(
    source,
    'Verify.Size = UDim2.fromOffset%(220, 36%)',
    'Verify.Size = UDim2.fromOffset(250, 38)',
    "tamanho do botão"
)

-- Botão neutro e muito transparente, sem vermelho.
source = replaceOnce(
    source,
    'Verify.BackgroundColor3 = COLORS.RED%s-Verify.BorderSizePixel = 0',
    'Verify.BackgroundColor3 = Color3.fromRGB(8, 8, 10)\nVerify.BackgroundTransparency = 0.78\nVerify.BorderSizePixel = 0',
    "fundo transparente do botão"
)

-- Adiciona uma borda fina para o botão continuar visível sobre a foto.
source = replaceOnce(
    source,
    'corner%(Verify, 9%)',
    'corner(Verify, 9)\n\nlocal VerifyStroke = Instance.new("UIStroke")\nVerifyStroke.Color = Color3.fromRGB(225, 225, 230)\nVerifyStroke.Transparency = 0.38\nVerifyStroke.Thickness = 1\nVerifyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border\nVerifyStroke.Parent = Verify',
    "borda do botão"
)

-- Hover sem vermelho.
source = replaceOnce(
    source,
    'Verify.MouseEnter:Connect%(function%(%)%s-tween%(Verify, {%s-BackgroundColor3 = COLORS.RED_HOVER,%s-}%)%s-end%)',
    'Verify.MouseEnter:Connect(function()\n    tween(Verify, {\n        BackgroundColor3 = Color3.fromRGB(28, 28, 32),\n        BackgroundTransparency = 0.68,\n    })\nend)',
    "hover neutro"
)

source = replaceOnce(
    source,
    'Verify.MouseLeave:Connect%(function%(%)%s-tween%(Verify, {%s-BackgroundColor3 = COLORS.RED,%s-}%)%s-end%)',
    'Verify.MouseLeave:Connect(function()\n    tween(Verify, {\n        BackgroundColor3 = Color3.fromRGB(8, 8, 10),\n        BackgroundTransparency = 0.78,\n    })\nend)',
    "saída do hover"
)

-- Mensagens temporárias mudam só o texto; não pintam o botão de vermelho.
source = replaceOnce(
    source,
    'if color then%s-tween%(Verify, {%s-BackgroundColor3 = color,%s-}%)%s-end',
    '-- fundo permanece transparente durante mensagens de status',
    "status sem cor"
)

-- Ao voltar ao estado normal, mantém o fundo neutro/transparente.
source = replaceOnce(
    source,
    'BackgroundColor3 = COLORS.RED,%s-}%)[%s-]*end[%s-]*end%)',
    'BackgroundColor3 = Color3.fromRGB(8, 8, 10),\n                BackgroundTransparency = 0.78,\n            })\n        end\n    end)',
    "reset transparente"
)

-- Estado VERIFICANDO também não fica vermelho.
source = replaceOnce(
    source,
    'BackgroundColor3 = Color3.fromRGB%(80, 22, 22%)',
    'BackgroundColor3 = Color3.fromRGB(18, 18, 22)\n        ,BackgroundTransparency = 0.72',
    "verificando neutro"
)

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
