--[[
    GRUPO LUA — LOGIN V11 / DEVICE BINDING + SESSÃO

    Visual:
      • imagem oficial Roblox: rbxassetid://91124214069969
      • painel 520 x 260
      • campo da chave bem transparente
      • botão VERIFICAR quase transparente
      • X vermelho para fechar

    Segurança/acesso:
      • FREE/VIP enviam identificador do aparelho para a Control API
      • o servidor vincula a chave ao primeiro aparelho
      • somente token de sessão é salvo localmente; a chave nunca é salva
      • enquanto a sessão estiver válida, o menu tenta entrar automaticamente
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

-- Imagem oficial Roblox.
source = replaceOnce(
    source,
    'local function loadBackgroundAsset%(%)%s.-%s-end%s-%s-local Parent',
    'local function loadBackgroundAsset()\n    return "' .. IMAGE_ASSET .. '"\nend\n\nlocal Parent',
    "imagem Roblox"
)

-- Mantém proporção 2:1 e tamanho mobile atual.
source = replaceOnce(source, 'WIDTH = 430,', 'WIDTH = 520,', "largura")
source = replaceOnce(source, 'HEIGHT = 215,', 'HEIGHT = 260,', "altura")

-- Identidade do aparelho + token persistente por menu.
source = replaceOnce(
    source,
    'local Request = findRequest%(%)',
    'local Request = findRequest()\n\nlocal DEVICE_FILE = "grupo_lua_device_id_v1.txt"\nlocal SESSION_FILE = "grupo_lua_session_" .. MENU_ID .. ".json"\n\nlocal function safeReadFile(path)\n    if type(readfile) ~= "function" then return nil end\n    local okRead, value = pcall(readfile, path)\n    if okRead and type(value) == "string" and value ~= "" then return value end\n    return nil\nend\n\nlocal function safeWriteFile(path, value)\n    if type(writefile) ~= "function" then return false end\n    local okWrite = pcall(writefile, path, tostring(value or ""))\n    return okWrite\nend\n\nlocal function resolveDeviceId()\n    local forced = tostring(ENV.GRUPO_LUA_DEVICE_ID or "")\n    if forced ~= "" then return forced end\n\n    local okAnalytics, analyticsId = pcall(function()\n        return game:GetService("RbxAnalyticsService"):GetClientId()\n    end)\n    if okAnalytics and type(analyticsId) == "string" and analyticsId ~= "" then\n        ENV.GRUPO_LUA_DEVICE_ID = analyticsId\n        return analyticsId\n    end\n\n    local saved = safeReadFile(DEVICE_FILE)\n    if saved then\n        ENV.GRUPO_LUA_DEVICE_ID = saved\n        return saved\n    end\n\n    local generated = HttpService:GenerateGUID(false)\n    ENV.GRUPO_LUA_DEVICE_ID = generated\n    safeWriteFile(DEVICE_FILE, generated)\n    return generated\nend\n\nlocal DEVICE_ID = resolveDeviceId()\n\nlocal function saveMenuSession(token, expiresAt, keyType)\n    if type(token) ~= "string" or token == "" then return end\n    local okEncode, encoded = pcall(function()\n        return HttpService:JSONEncode({\n            menuId = MENU_ID,\n            token = token,\n            expiresAt = expiresAt,\n            keyType = keyType,\n        })\n    end)\n    if okEncode then safeWriteFile(SESSION_FILE, encoded) end\nend\n\nlocal function readMenuSession()\n    local raw = safeReadFile(SESSION_FILE)\n    if not raw then return nil end\n    local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)\n    if not okDecode or type(data) ~= "table" then return nil end\n    if tostring(data.menuId or "") ~= MENU_ID then return nil end\n    if type(data.token) ~= "string" or data.token == "" then return nil end\n    return data\nend\n\nlocal function clearMenuSession()\n    if type(delfile) == "function" then pcall(delfile, SESSION_FILE) end\nend',
    "device binding"
)

-- Campo da chave.
source = replaceOnce(
    source,
    'InputBorder.Size = UDim2.fromOffset%(220, 40%)',
    'InputBorder.Size = UDim2.fromOffset(260, 43)',
    "tamanho do campo"
)
source = replaceOnce(
    source,
    'InputBorder.BackgroundColor3 = Color3.fromRGB%(125, 125, 128%)',
    'InputBorder.BackgroundColor3 = Color3.fromRGB(235, 235, 240)\nInputBorder.BackgroundTransparency = 0.72',
    "borda transparente do campo"
)
source = replaceOnce(
    source,
    'InputHolder.BackgroundTransparency = 0%.08',
    'InputHolder.BackgroundTransparency = 0.90',
    "transparência do campo"
)
source = replaceOnce(
    source,
    'KeyBox.PlaceholderColor3 = Color3.fromRGB%(120, 120, 125%)',
    'KeyBox.PlaceholderColor3 = Color3.fromRGB(230, 230, 235)',
    "placeholder"
)
source = replaceOnce(
    source,
    'KeyBox.Focused:Connect%(function%(%)%s-tween%(InputBorder,%s-{%s-BackgroundColor3 = COLORS.RED_BRIGHT,%s-}%s-%)%s-end%)',
    'KeyBox.Focused:Connect(function()\n    tween(InputBorder, {\n        BackgroundColor3 = Color3.fromRGB(255, 255, 255),\n        BackgroundTransparency = 0.60,\n    })\nend)',
    "foco transparente"
)
source = replaceOnce(
    source,
    'KeyBox.FocusLost:Connect%(function%(%)%s-tween%(InputBorder,%s-{%s-BackgroundColor3 = Color3.fromRGB%(125, 125, 128%),%s-}%s-%)%s-end%)',
    'KeyBox.FocusLost:Connect(function()\n    tween(InputBorder, {\n        BackgroundColor3 = Color3.fromRGB(235, 235, 240),\n        BackgroundTransparency = 0.72,\n    })\nend)',
    "saída do foco transparente"
)

-- Botão verificar.
source = replaceOnce(
    source,
    'Verify.Size = UDim2.fromOffset%(220, 36%)',
    'Verify.Size = UDim2.fromOffset(260, 39)',
    "tamanho do botão"
)
source = replaceOnce(
    source,
    'Verify.BackgroundColor3 = COLORS.RED%s-Verify.BorderSizePixel = 0',
    'Verify.BackgroundColor3 = Color3.fromRGB(6, 6, 8)\nVerify.BackgroundTransparency = 0.86\nVerify.BorderSizePixel = 0',
    "botão transparente"
)
source = replaceOnce(
    source,
    'corner%(Verify, 9%)',
    'corner(Verify, 9)\n\nlocal VerifyStroke = Instance.new("UIStroke")\nVerifyStroke.Color = Color3.fromRGB(235, 235, 240)\nVerifyStroke.Transparency = 0.42\nVerifyStroke.Thickness = 1\nVerifyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border\nVerifyStroke.Parent = Verify',
    "borda do botão"
)
source = replaceOnce(
    source,
    'BackgroundColor3 = COLORS.RED_HOVER,',
    'BackgroundColor3 = Color3.fromRGB(20, 20, 24),',
    "hover sem vermelho"
)
source = replaceOnce(
    source,
    'BackgroundColor3 = COLORS.RED,%s-}%)%s-end%)%s-%s-local DEFAULT_BUTTON_TEXT',
    'BackgroundColor3 = Color3.fromRGB(6, 6, 8),\n    })\nend)\n\nlocal DEFAULT_BUTTON_TEXT',
    "estado normal sem vermelho"
)

-- X vermelho.
source = replaceOnce(
    source,
    'Background.Parent = Main',
    'Background.Parent = Main\n\nlocal CloseButton = Instance.new("TextButton")\nCloseButton.Name = "CloseButton"\nCloseButton.AnchorPoint = Vector2.new(0.5, 0.5)\nCloseButton.Position = UDim2.new(1, -20, 0, 20)\nCloseButton.Size = UDim2.fromOffset(30, 30)\nCloseButton.BackgroundTransparency = 1\nCloseButton.BorderSizePixel = 0\nCloseButton.Text = "×"\nCloseButton.TextColor3 = Color3.fromRGB(235, 42, 38)\nCloseButton.Font = Enum.Font.GothamBold\nCloseButton.TextSize = 26\nCloseButton.AutoButtonColor = false\nCloseButton.ZIndex = 20\nCloseButton.Parent = Main\n\nCloseButton.MouseButton1Click:Connect(function()\n    GUI:Destroy()\nend)',
    "botão fechar"
)

-- Mensagens dos novos estados do servidor.
source = replaceOnce(
    source,
    'elseif code == "MENU_KEY_EXPIRED" then%s-return "CHAVE EXPIRADA"',
    'elseif code == "MENU_KEY_EXPIRED" or code == "VIP_EXPIRED" then\n        return "CHAVE EXPIRADA"\n    elseif code == "FREE_REQUIRES_ADMIN" then\n        return "AGUARDA LIBERAÇÃO ADM"\n    elseif code == "DEVICE_NOT_AUTHORIZED" then\n        return "CHAVE EM OUTRO CELULAR"\n    elseif code == "DEVICE_ID_REQUIRED" then\n        return "APARELHO NÃO IDENTIFICADO"',
    "mensagens de acesso"
)

-- Validação envia a identidade do aparelho.
source = replaceOnce(
    source,
    'clientLabel = clientLabel%(%),',
    'clientLabel = clientLabel(),\n            deviceId = DEVICE_ID,\n            deviceHint = executorName(),',
    "device na validação"
)

-- Manifest também confirma o mesmo aparelho.
source = replaceOnce(
    source,
    '%["Authorization"%] = "Bearer " %.%. accessToken,',
    '["Authorization"] = "Bearer " .. accessToken,\n            ["X-Menu-Device-Id"] = DEVICE_ID,',
    "device no manifest"
)

-- Mantém o token até o manifest ser confirmado e então salva somente a sessão.
source = replaceOnce(
    source,
    'accessToken = nil%s-%s-if%s-not manifestOK',
    'if\n        not manifestOK',
    "preservar token"
)
source = replaceOnce(
    source,
    'local downloadOK, source = downloadText%(manifest.menu.sourceUrl%)',
    'saveMenuSession(accessToken, validateData.expiresAt, keyType)\n    accessToken = nil\n\n    local downloadOK, source = downloadText(manifest.menu.sourceUrl)',
    "salvar sessão"
)

-- Restauração automática: se existe token válido para este menu e aparelho,
-- carrega sem pedir a chave novamente.
source = replaceOnce(
    source,
    'local Busy = false',
    'local Busy = false\n\nlocal function tryResumeSession()\n    local saved = readMenuSession()\n    if not saved or Busy then return end\n\n    Busy = true\n    Verify.Text = "RESTAURANDO..."\n\n    local manifestOK, manifest, manifestStatus = jsonRequest(\n        "GET",\n        CONFIG.API_BASE .. "/v1/menu-access/" .. MENU_ID .. "/manifest",\n        nil,\n        {\n            ["Authorization"] = "Bearer " .. saved.token,\n            ["X-Menu-Device-Id"] = DEVICE_ID,\n        }\n    )\n\n    if not manifestOK or type(manifest) ~= "table" or manifest.ok ~= true or type(manifest.menu) ~= "table" or type(manifest.menu.sourceUrl) ~= "string" then\n        if manifestStatus == 401 or manifestStatus == 403 then clearMenuSession() end\n        Busy = false\n        Verify.Text = DEFAULT_BUTTON_TEXT\n        return\n    end\n\n    local downloadOK, menuSource = downloadText(manifest.menu.sourceUrl)\n    if not downloadOK or type(menuSource) ~= "string" or menuSource == "" or type(loadstring) ~= "function" then\n        Busy = false\n        Verify.Text = DEFAULT_BUTTON_TEXT\n        return\n    end\n\n    local fn, compileError = loadstring(menuSource)\n    menuSource = nil\n    if not fn then\n        warn("[GRUPO LUA] Falha de compilação na sessão salva:", compileError)\n        Busy = false\n        Verify.Text = DEFAULT_BUTTON_TEXT\n        return\n    end\n\n    Verify.Text = saved.keyType and ("LIBERADO • " .. tostring(saved.keyType)) or "LIBERADO"\n    tween(Verify, { BackgroundColor3 = COLORS.GREEN }, 0.18)\n    task.wait(0.20)\n    if GUI and GUI.Parent then GUI:Destroy() end\n\n    local runtimeOK, runtimeError = xpcall(fn, function(message)\n        local trace = tostring(message)\n        pcall(function()\n            if debug and type(debug.traceback) == "function" then trace = debug.traceback(tostring(message), 2) end\n        end)\n        return trace\n    end)\n    if not runtimeOK then warn("[GRUPO LUA] Erro ao executar menu:", runtimeError) end\nend',
    "restaurar sessão"
)

-- Inicia a restauração depois que toda a UI/drag/scale do core estiver pronta.
source = source .. '\n\ntask.defer(tryResumeSession)\n'

local fn, compileError = loadstring(source)
source = nil

if not fn then
    error("[GRUPO LUA] Falha ao compilar login: " .. tostring(compileError))
end

return fn()