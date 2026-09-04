--[[
    GRUPO LUA — LOGIN V9 / FOTO LIVRE

    Visual:
      • imagem oficial Roblox: rbxassetid://91124214069969
      • painel 520 x 260
      • campo da chave bem transparente
      • ao tocar/digitar, o campo continua transparente
      • botão VERIFICAR quase transparente e sem vermelho no estado normal
      • bordas discretas para manter boa leitura no celular

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

-- Usa o asset oficial do Roblox diretamente.
source = replaceOnce(
    source,
    'local function loadBackgroundAsset%(%)%s.-%s-end%s-%s-local Parent',
    'local function loadBackgroundAsset()\n    return "' .. IMAGE_ASSET .. '"\nend\n\nlocal Parent',
    "imagem Roblox"
)

-- Aumenta só um pouco, mantendo proporção 2:1.
source = replaceOnce(source, 'WIDTH = 430,', 'WIDTH = 520,', "largura")
source = replaceOnce(source, 'HEIGHT = 215,', 'HEIGHT = 260,', "altura")

-- Campo da chave levemente maior.
source = replaceOnce(
    source,
    'InputBorder.Size = UDim2.fromOffset%(220, 40%)',
    'InputBorder.Size = UDim2.fromOffset(260, 43)',
    "tamanho do campo"
)

-- Moldura quase transparente: serve só para mostrar onde tocar.
source = replaceOnce(
    source,
    'InputBorder.BackgroundColor3 = Color3.fromRGB%(125, 125, 128%)',
    'InputBorder.BackgroundColor3 = Color3.fromRGB(235, 235, 240)\nInputBorder.BackgroundTransparency = 0.72',
    "borda transparente do campo"
)

-- Fundo do campo muito transparente, deixando a foto claramente visível.
source = replaceOnce(
    source,
    'InputHolder.BackgroundTransparency = 0%.08',
    'InputHolder.BackgroundTransparency = 0.90',
    "transparência do campo"
)

-- Placeholder claro para continuar legível sem precisar escurecer o fundo.
source = replaceOnce(
    source,
    'KeyBox.PlaceholderColor3 = Color3.fromRGB%(120, 120, 125%)',
    'KeyBox.PlaceholderColor3 = Color3.fromRGB(230, 230, 235)',
    "placeholder"
)

-- Quando toca no campo, NÃO fica vermelho nem opaco.
source = replaceOnce(
    source,
    'KeyBox.Focused:Connect%(function%(%)%s-tween%(InputBorder,%s-{%s-BackgroundColor3 = COLORS.RED_BRIGHT,%s-}%s-%)%s-end%)',
    'KeyBox.Focused:Connect(function()\n    tween(InputBorder, {\n        BackgroundColor3 = Color3.fromRGB(255, 255, 255),\n        BackgroundTransparency = 0.60,\n    })\nend)',
    "foco transparente"
)

-- Ao sair do campo, volta para o transparente normal.
source = replaceOnce(
    source,
    'KeyBox.FocusLost:Connect%(function%(%)%s-tween%(InputBorder,%s-{%s-BackgroundColor3 = Color3.fromRGB%(125, 125, 128%),%s-}%s-%)%s-end%)',
    'KeyBox.FocusLost:Connect(function()\n    tween(InputBorder, {\n        BackgroundColor3 = Color3.fromRGB(235, 235, 240),\n        BackgroundTransparency = 0.72,\n    })\nend)',
    "saída do foco transparente"
)

-- Botão maior, porém ainda discreto.
source = replaceOnce(
    source,
    'Verify.Size = UDim2.fromOffset%(220, 36%)',
    'Verify.Size = UDim2.fromOffset(260, 39)',
    "tamanho do botão"
)

-- Botão normal quase transparente e sem vermelho.
source = replaceOnce(
    source,
    'Verify.BackgroundColor3 = COLORS.RED%s-Verify.BorderSizePixel = 0',
    'Verify.BackgroundColor3 = Color3.fromRGB(6, 6, 8)\nVerify.BackgroundTransparency = 0.86\nVerify.BorderSizePixel = 0',
    "botão transparente"
)

-- Borda fina para manter a área do botão visível.
source = replaceOnce(
    source,
    'corner%(Verify, 9%)',
    'corner(Verify, 9)\n\nlocal VerifyStroke = Instance.new("UIStroke")\nVerifyStroke.Color = Color3.fromRGB(235, 235, 240)\nVerifyStroke.Transparency = 0.42\nVerifyStroke.Thickness = 1\nVerifyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border\nVerifyStroke.Parent = Verify',
    "borda do botão"
)

-- Hover neutro.
source = replaceOnce(
    source,
    'BackgroundColor3 = COLORS.RED_HOVER,',
    'BackgroundColor3 = Color3.fromRGB(20, 20, 24),',
    "hover sem vermelho"
)

-- Estado normal neutro após hover.
source = replaceOnce(
    source,
    'BackgroundColor3 = COLORS.RED,%s-}%)%s-end%)%s-%s-local DEFAULT_BUTTON_TEXT',
    'BackgroundColor3 = Color3.fromRGB(6, 6, 8),\n    })\nend)\n\nlocal DEFAULT_BUTTON_TEXT',
    "estado normal sem vermelho"
)

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()
