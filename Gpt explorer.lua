--==============================================================--
--       CAFEÍNA V3 • MOBILE FILE EXPLORER
--==============================================================--
--
-- Explorador mobile em uma coluna, inspirado em gerenciadores
-- de arquivos comuns de celular.
--
-- RECURSOS
-- • Navegação: Voltar / Subir / Home / Atualizar
-- • Caminho atual
-- • Pesquisa com debounce
-- • Pastas primeiro
-- • Linha inteira clicável
-- • Lista otimizada com limite de renderização
-- • Preview de imagem ao tocar
-- • Texto / Lua / Luau / JSON / CSV
-- • HEX para binários
-- • INFO com metadados
-- • PNG / GIF / WAV inspector
-- • Copiar conteúdo / caminho
-- • Salvar cópia de imagem quando writefile existir
-- • CAFEÍNA ASSISTENTE em chat integrado
-- • Perguntas sobre Explorer e arquivo aberto
-- • Contexto automático de pasta + arquivo
-- • Menu e ícone minimizado arrastáveis
-- • Proteção contra clique após arraste
-- • Tratamento de erros / APIs ausentes
--
-- APIs necessárias:
-- listfiles, isfolder, readfile
--
-- APIs opcionais:
-- isfile, writefile, makefolder, setclipboard,
-- getcustomasset, getsynasset
--
--==============================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    INITIAL_VISIBLE_FILES = 300,
    LOAD_MORE_BATCH = 300,
    MAX_RENDERED_FILES = 6000,
    SEARCH_DELAY = 0.16,
    MAX_HISTORY = 60,

    MAX_TEXT_BYTES = 180000,
    MAX_HEX_BYTES = 16000,
    MAX_CSV_ROWS = 180,
    MAX_JSON_PARSE_BYTES = 2 * 1024 * 1024,

    LARGE_FILE_WARNING = 8 * 1024 * 1024,
    HUGE_FILE_WARNING = 32 * 1024 * 1024,

    BINARY_SAMPLE = 4096,

    DOWNLOAD_FOLDER = "Cafeina_Downloads",

    -- CAFEÍNA AI
    AI_ENDPOINT = "https://cafe-na-ia.onrender.com/chat",
    AI_MAX_TEXT_CHARS = 45000,
    AI_MAX_HEX_CHARS = 12000,
}

local COLORS = {
    BG = Color3.fromRGB(12, 12, 15),
    TOP = Color3.fromRGB(20, 20, 24),
    PANEL = Color3.fromRGB(25, 25, 30),
    PANEL2 = Color3.fromRGB(31, 31, 37),

    RED = Color3.fromRGB(238, 38, 52),
    RED_DARK = Color3.fromRGB(108, 20, 28),

    TEXT = Color3.fromRGB(244, 244, 247),
    SUB = Color3.fromRGB(155, 155, 166),
    STROKE = Color3.fromRGB(50, 50, 60),

    GREEN = Color3.fromRGB(72, 214, 121),
    YELLOW = Color3.fromRGB(241, 186, 62),
}

--==============================================================--
-- REMOVE GUI ANTIGA
--==============================================================--

local old = PlayerGui:FindFirstChild("CafeinaMobileExplorerV3")
if old then
    old:Destroy()
end

--==============================================================--
-- APIs
--==============================================================--

local API = {
    listfiles = typeof(listfiles) == "function" and listfiles or nil,
    isfolder = typeof(isfolder) == "function" and isfolder or nil,
    isfile = typeof(isfile) == "function" and isfile or nil,
    readfile = typeof(readfile) == "function" and readfile or nil,
    writefile = typeof(writefile) == "function" and writefile or nil,
    makefolder = typeof(makefolder) == "function" and makefolder or nil,
    setclipboard = typeof(setclipboard) == "function" and setclipboard or nil,

    request =
        typeof(request) == "function" and request
        or typeof(http_request) == "function" and http_request
        or (
            syn
            and typeof(syn.request) == "function"
            and syn.request
        )
        or nil,

    customAsset =
        typeof(getcustomasset) == "function" and getcustomasset
        or typeof(getsynasset) == "function" and getsynasset
        or nil,
}

local FileSystemAvailable =
    API.listfiles ~= nil
    and API.isfolder ~= nil
    and API.readfile ~= nil

--==============================================================--
-- STATE
--==============================================================--

local RootPath = ""
local CurrentPath = ""
local History = {}
local CurrentEntries = {}

local CurrentMode = "LIST" -- LIST / TEXT / IMAGE / HEX / INFO
local CurrentFileType = nil
local CurrentFormat = nil

local SelectedPath = nil
local SelectedData = nil
local SelectedText = ""
local SelectedHex = ""
local SelectedInfo = ""

local CurrentAsset = nil
local DirectoryGeneration = 0
local SearchGeneration = 0
local GuiDestroyed = false

local RenderedCount = 0
local RenderGeneration = 0
local FilteredEntries = {}
local IsAppendingBatch = false

local AIVisible = false
local AIRequestBusy = false
local AIRequestGeneration = 0
local LastAIResponse = ""

--==============================================================--
-- HELPERS
--==============================================================--

local function safeCall(callback, ...)
    if typeof(callback) ~= "function" then
        return false, "API indisponível"
    end

    local args = {...}

    return pcall(function()
        return callback(table.unpack(args))
    end)
end

local function normalizePath(path)
    path = tostring(path or "")
    path = path:gsub("\\", "/")
    path = path:gsub("/+", "/")

    if path ~= "/" then
        path = path:gsub("/$", "")
    end

    if path == "." then
        return ""
    end

    return path
end

local function basename(path)
    path = normalizePath(path)

    if path == "" then
        return "/"
    end

    return path:match("([^/]+)$") or path
end

local function dirname(path)
    path = normalizePath(path)

    if path == "" then
        return ""
    end

    return normalizePath(path:match("^(.*)/[^/]+$") or "")
end

local function extension(path)
    local name = basename(path)
    return (name:match("%.([^%.]+)$") or ""):lower()
end

local function readableSize(bytes)
    bytes = tonumber(bytes) or 0

    if bytes < 1024 then
        return tostring(bytes) .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.2f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.2f MB", bytes / 1024 / 1024)
    else
        return string.format("%.2f GB", bytes / 1024 / 1024 / 1024)
    end
end

local function pathIsFolder(path)
    if not API.isfolder then
        return false
    end

    local ok, result = safeCall(API.isfolder, path)
    return ok and result == true
end

--==============================================================--
-- TYPE DETECTION
--==============================================================--

local IMAGE_EXT = {
    png = true, jpg = true, jpeg = true,
    webp = true, gif = true, bmp = true,
}

local AUDIO_EXT = {
    wav = true, mp3 = true, ogg = true,
}

local TEXT_EXT = {
    txt = true, lua = true, luau = true, json = true,
    csv = true, xml = true, html = true, htm = true,
    css = true, js = true, md = true, log = true,
    cfg = true, conf = true, ini = true, yaml = true,
    yml = true, toml = true, py = true, java = true,
    c = true, cpp = true, h = true, sh = true,
    bat = true,
}

local function detectSignature(data)
    if type(data) ~= "string" or #data < 2 then
        return nil
    end

    local function starts(...)
        local bytes = {...}
        if #data < #bytes then
            return false
        end

        for i, expected in ipairs(bytes) do
            if data:byte(i) ~= expected then
                return false
            end
        end

        return true
    end

    if starts(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) then
        return "PNG"
    end

    if starts(0xFF, 0xD8, 0xFF) then
        return "JPEG"
    end

    if data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then
        return "GIF"
    end

    if data:sub(1, 4) == "RIFF" then
        local subtype = data:sub(9, 12)
        if subtype == "WAVE" then
            return "WAV"
        elseif subtype == "WEBP" then
            return "WEBP"
        end
    end

    if data:sub(1, 4) == "OggS" then
        return "OGG"
    end

    if data:sub(1, 3) == "ID3" then
        return "MP3"
    end

    if #data >= 2 then
        local b1, b2 = data:byte(1, 2)
        if b1 == 0xFF and b2 and bit32.band(b2, 0xE0) == 0xE0 then
            return "MP3"
        end
    end

    if starts(0x50, 0x4B, 0x03, 0x04)
        or starts(0x50, 0x4B, 0x05, 0x06)
        or starts(0x50, 0x4B, 0x07, 0x08)
    then
        return "ZIP"
    end

    if data:sub(1, 5) == "%PDF-" then
        return "PDF"
    end

    if starts(0x1F, 0x8B) then
        return "GZIP"
    end

    if starts(0x7F, 0x45, 0x4C, 0x46) then
        return "ELF"
    end

    if data:sub(1, 2) == "MZ" then
        return "EXE"
    end

    return nil
end

local function looksBinary(data)
    if type(data) ~= "string" then
        return false
    end

    local amount = math.min(#data, CONFIG.BINARY_SAMPLE)
    if amount == 0 then
        return false
    end

    local suspicious = 0

    for i = 1, amount do
        local byte = data:byte(i)

        if byte == 0 then
            return true
        end

        local valid =
            byte == 9
            or byte == 10
            or byte == 13
            or byte >= 32

        if not valid then
            suspicious += 1
        end
    end

    return (suspicious / amount) > 0.10
end

local function getType(path, data)
    local ext = extension(path)
    local signature = detectSignature(data)

    if signature == "PNG"
        or signature == "JPEG"
        or signature == "GIF"
        or signature == "WEBP"
    then
        return "IMAGE", signature
    end

    if signature == "WAV"
        or signature == "OGG"
        or signature == "MP3"
    then
        return "AUDIO", signature
    end

    if IMAGE_EXT[ext] then
        return "IMAGE", signature or ext:upper()
    end

    if AUDIO_EXT[ext] then
        return "AUDIO", signature or ext:upper()
    end

    if ext == "json" then
        return "JSON", "JSON"
    end

    if ext == "csv" then
        return "CSV", "CSV"
    end

    if ext == "lua" or ext == "luau" then
        return "LUA", ext:upper()
    end

    if TEXT_EXT[ext] then
        return "TEXT", ext:upper()
    end

    if looksBinary(data) then
        return "BINARY", signature or "BINÁRIO"
    end

    return "TEXT", ext ~= "" and ext:upper() or "TEXTO"
end

local function extensionLabel(path)
    local ext = extension(path)

    local labels = {
        lua = "LUA",
        luau = "LUAU",
        json = "JSON",
        csv = "CSV",
        png = "PNG",
        jpg = "JPEG",
        jpeg = "JPEG",
        webp = "WEBP",
        gif = "GIF",
        bmp = "BMP",
        wav = "WAV",
        mp3 = "MP3",
        ogg = "OGG",
        txt = "TXT",
        zip = "ZIP",
        pdf = "PDF",
    }

    return labels[ext] or (ext ~= "" and ext:upper() or "ARQUIVO")
end

--==============================================================--
-- BYTE READERS / INSPECTORS
--==============================================================--

local function readU16LE(data, pos)
    if #data < pos + 1 then
        return nil
    end

    local a, b = data:byte(pos, pos + 1)
    return a + b * 256
end

local function readU32LE(data, pos)
    if #data < pos + 3 then
        return nil
    end

    local a, b, c, d = data:byte(pos, pos + 3)

    return a
        + b * 256
        + c * 65536
        + d * 16777216
end

local function readU32BE(data, pos)
    if #data < pos + 3 then
        return nil
    end

    local a, b, c, d = data:byte(pos, pos + 3)

    return a * 16777216
        + b * 65536
        + c * 256
        + d
end

local PNG_COLOR_TYPES = {
    [0] = "Grayscale",
    [2] = "RGB",
    [3] = "Indexed",
    [4] = "Grayscale + Alpha",
    [6] = "RGBA",
}

local function inspectPNG(data)
    if detectSignature(data) ~= "PNG" or #data < 29 then
        return nil
    end

    local colorType = data:byte(26)

    return {
        width = readU32BE(data, 17),
        height = readU32BE(data, 21),
        bitDepth = data:byte(25),
        colorType = colorType,
        colorName = PNG_COLOR_TYPES[colorType] or ("Tipo " .. tostring(colorType)),
        alpha = colorType == 4 or colorType == 6,
    }
end

local function inspectGIF(data)
    if detectSignature(data) ~= "GIF" or #data < 10 then
        return nil
    end

    return {
        width = readU16LE(data, 7),
        height = readU16LE(data, 9),
        version = data:sub(1, 6),
    }
end

local function inspectWAV(data)
    if detectSignature(data) ~= "WAV" or #data < 36 then
        return nil
    end

    return {
        channels = readU16LE(data, 23),
        sampleRate = readU32LE(data, 25),
        bits = readU16LE(data, 35),
    }
end

--==============================================================--
-- HEX
--==============================================================--

local function hexDump(data)
    if type(data) ~= "string" then
        return ""
    end

    local limit = math.min(#data, CONFIG.MAX_HEX_BYTES)
    local lines = {
        "OFFSET    HEX                                             ASCII",
        "---------------------------------------------------------------",
    }

    for offset = 1, limit, 16 do
        local hex = {}
        local ascii = {}

        for rel = 0, 15 do
            local index = offset + rel

            if index <= limit then
                local byte = data:byte(index)
                hex[#hex + 1] = string.format("%02X", byte)
                ascii[#ascii + 1] =
                    (byte >= 32 and byte <= 126)
                    and string.char(byte)
                    or "."
            else
                hex[#hex + 1] = "  "
                ascii[#ascii + 1] = " "
            end
        end

        lines[#lines + 1] = string.format(
            "%08X  %-47s  %s",
            offset - 1,
            table.concat(hex, " "),
            table.concat(ascii)
        )
    end

    if #data > limit then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format(
            "[Mostrando %s de %s]",
            readableSize(limit),
            readableSize(#data)
        )
    end

    return table.concat(lines, "\n")
end

--==============================================================--
-- JSON
--==============================================================--

local function formatJSON(content)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)

    if not ok then
        return nil, tostring(decoded)
    end

    local encodeOk, compact = pcall(function()
        return HttpService:JSONEncode(decoded)
    end)

    if not encodeOk then
        return content
    end

    local result = {}
    local indent = 0
    local insideString = false
    local escaped = false

    for i = 1, #compact do
        local char = compact:sub(i, i)

        if char == '"' and not escaped then
            insideString = not insideString
        end

        if insideString then
            result[#result + 1] = char
        else
            if char == "{" or char == "[" then
                result[#result + 1] = char
                indent += 1
                result[#result + 1] = "\n" .. string.rep("    ", indent)

            elseif char == "}" or char == "]" then
                indent = math.max(0, indent - 1)
                result[#result + 1] =
                    "\n" .. string.rep("    ", indent) .. char

            elseif char == "," then
                result[#result + 1] =
                    ",\n" .. string.rep("    ", indent)

            elseif char == ":" then
                result[#result + 1] = ": "

            else
                result[#result + 1] = char
            end
        end

        if char == "\\" and not escaped then
            escaped = true
        else
            escaped = false
        end
    end

    return table.concat(result)
end

--==============================================================--
-- CSV
--==============================================================--

local function parseCSVLine(line)
    local out = {}
    local value = {}
    local quoted = false
    local i = 1

    while i <= #line do
        local char = line:sub(i, i)

        if quoted then
            if char == '"' then
                if line:sub(i + 1, i + 1) == '"' then
                    value[#value + 1] = '"'
                    i += 1
                else
                    quoted = false
                end
            else
                value[#value + 1] = char
            end
        else
            if char == '"' then
                quoted = true
            elseif char == "," then
                out[#out + 1] = table.concat(value)
                value = {}
            else
                value[#value + 1] = char
            end
        end

        i += 1
    end

    out[#out + 1] = table.concat(value)

    return out
end

local function formatCSV(content)
    local rawLines = {}

    for line in content:gmatch("[^\r\n]+") do
        rawLines[#rawLines + 1] = line

        if #rawLines >= CONFIG.MAX_CSV_ROWS then
            break
        end
    end

    if #rawLines == 0 then
        return "[CSV vazio]"
    end

    local rows = {}
    local widths = {}

    for _, line in ipairs(rawLines) do
        local row = parseCSVLine(line)

        for col, value in ipairs(row) do
            value = value:gsub("^%s+", ""):gsub("%s+$", "")
            row[col] = value
            widths[col] = math.min(math.max(widths[col] or 0, #value), 30)
        end

        rows[#rows + 1] = row
    end

    local output = {}

    for rowIndex, row in ipairs(rows) do
        local cells = {}

        for col, value in ipairs(row) do
            if #value > 30 then
                value = value:sub(1, 27) .. "..."
            end

            cells[#cells + 1] = string.format(
                "%-" .. tostring(widths[col] or 5) .. "s",
                value
            )
        end

        output[#output + 1] = table.concat(cells, " | ")

        if rowIndex == 1 then
            local separators = {}

            for col in ipairs(row) do
                separators[#separators + 1] =
                    string.rep("-", widths[col] or 5)
            end

            output[#output + 1] =
                table.concat(separators, "-+-")
        end
    end

    if #rawLines >= CONFIG.MAX_CSV_ROWS then
        output[#output + 1] = ""
        output[#output + 1] =
            "[Tabela limitada a "
            .. tostring(CONFIG.MAX_CSV_ROWS)
            .. " linhas]"
    end

    return table.concat(output, "\n")
end

local function lineNumberText(content)
    local output = {}
    local lineNumber = 1

    for line in ((content or "") .. "\n"):gmatch("(.-)\n") do
        output[#output + 1] =
            string.format("%04d │ %s", lineNumber, line)
        lineNumber += 1
    end

    return table.concat(output, "\n")
end

--==============================================================--
-- INFO
--==============================================================--

local function buildInfo(path, data, fileType, format)
    local lines = {
        "CAFEÍNA FILE INFO",
        "",
        "Nome: " .. basename(path),
        "Caminho: " .. path,
        "",
        "Tipo: " .. tostring(fileType),
        "Formato: " .. tostring(format),
        "Tamanho: " .. readableSize(#data),
        "Bytes: " .. tostring(#data),
        "Extensão: " .. (extension(path) ~= "" and "." .. extension(path) or "nenhuma"),
        "Assinatura: " .. tostring(detectSignature(data) or "não identificada"),
    }

    local signature = detectSignature(data)

    if signature == "PNG" then
        local info = inspectPNG(data)

        if info then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "PNG"
            lines[#lines + 1] =
                "Dimensões: " .. tostring(info.width) .. " × " .. tostring(info.height)
            lines[#lines + 1] =
                "Bit depth: " .. tostring(info.bitDepth)
            lines[#lines + 1] =
                "Cor: " .. tostring(info.colorName)
            lines[#lines + 1] =
                "Alpha: " .. (info.alpha and "Sim" or "Não")
            lines[#lines + 1] =
                "Compressão: DEFLATE"
        end

    elseif signature == "GIF" then
        local info = inspectGIF(data)

        if info then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "GIF"
            lines[#lines + 1] = "Versão: " .. tostring(info.version)
            lines[#lines + 1] =
                "Dimensões: " .. tostring(info.width) .. " × " .. tostring(info.height)
        end

    elseif signature == "WAV" then
        local info = inspectWAV(data)

        if info then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "WAV"
            lines[#lines + 1] =
                "Canais: " .. tostring(info.channels)
            lines[#lines + 1] =
                "Sample rate: " .. tostring(info.sampleRate) .. " Hz"
            lines[#lines + 1] =
                "Bit depth: " .. tostring(info.bits) .. "-bit"
        end
    end

    if #data > CONFIG.HUGE_FILE_WARNING then
        lines[#lines + 1] = ""
        lines[#lines + 1] =
            "⚠ Arquivo muito grande. O visualizador limita o conteúdo exibido."
    elseif #data > CONFIG.LARGE_FILE_WARNING then
        lines[#lines + 1] = ""
        lines[#lines + 1] =
            "⚠ Arquivo grande. Algumas visualizações são limitadas."
    end

    return table.concat(lines, "\n")
end

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function corner(object, radius)
    local ui = Instance.new("UICorner")
    ui.CornerRadius = UDim.new(0, radius or 8)
    ui.Parent = object
    return ui
end

local function stroke(object, color, thickness)
    local ui = Instance.new("UIStroke")
    ui.Color = color or COLORS.STROKE
    ui.Thickness = thickness or 1
    ui.Parent = object
    return ui
end

local function label(parent, text, size, color)
    local object = Instance.new("TextLabel")

    object.BackgroundTransparency = 1
    object.Text = text or ""
    object.TextSize = size or 12
    object.TextColor3 = color or COLORS.TEXT
    object.Font = Enum.Font.Gotham

    object.TextXAlignment = Enum.TextXAlignment.Left
    object.TextYAlignment = Enum.TextYAlignment.Center

    object.Parent = parent

    return object
end

local function button(parent, text)
    local object = Instance.new("TextButton")

    object.AutoButtonColor = false
    object.BackgroundColor3 = COLORS.PANEL2
    object.BorderSizePixel = 0

    object.Text = text or ""
    object.TextSize = 12
    object.TextColor3 = COLORS.TEXT
    object.Font = Enum.Font.GothamMedium

    corner(object, 9)
    stroke(object)

    object.Parent = parent

    return object
end

--==============================================================--
-- GUI
--==============================================================--

local Gui = Instance.new("ScreenGui")

Gui.Name = "CafeinaMobileExplorerV3"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")

Main.Size = UDim2.new(0.94, 0, 0.86, 0)
Main.Position = UDim2.new(0.03, 0, 0.07, 0)

Main.BackgroundColor3 = COLORS.BG
Main.BorderSizePixel = 0

corner(Main, 14)
stroke(Main)

Main.Parent = Gui

local SizeConstraint = Instance.new("UISizeConstraint")

SizeConstraint.MinSize = Vector2.new(305, 430)
SizeConstraint.MaxSize = Vector2.new(700, 790)

SizeConstraint.Parent = Main

--==============================================================--
-- TOP BAR
--==============================================================--

local Top = Instance.new("Frame")

Top.Size = UDim2.new(1, 0, 0, 55)
Top.BackgroundColor3 = COLORS.TOP
Top.BorderSizePixel = 0

corner(Top, 14)

Top.Parent = Main

local Back = button(Top, "‹")
Back.Size = UDim2.fromOffset(36, 36)
Back.Position = UDim2.fromOffset(7, 9)

local Up = button(Top, "↑")
Up.Size = UDim2.fromOffset(36, 36)
Up.Position = UDim2.fromOffset(47, 9)

local Home = button(Top, "⌂")
Home.Size = UDim2.fromOffset(36, 36)
Home.Position = UDim2.fromOffset(87, 9)

local HeaderTitle = label(
    Top,
    "CAFEÍNA",
    15,
    COLORS.TEXT
)

HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.Size = UDim2.new(1, -214, 0, 23)
HeaderTitle.Position = UDim2.fromOffset(132, 5)
HeaderTitle.TextTruncate = Enum.TextTruncate.AtEnd

local HeaderSub = label(
    Top,
    "FILE EXPLORER V3",
    9,
    COLORS.RED
)

HeaderSub.Font = Enum.Font.GothamBold
HeaderSub.Size = UDim2.new(1, -214, 0, 17)
HeaderSub.Position = UDim2.fromOffset(132, 29)

local Minimize = button(Top, "−")
Minimize.Size = UDim2.fromOffset(34, 34)
Minimize.Position = UDim2.new(1, -76, 0, 10)

local Close = button(Top, "×")
Close.Size = UDim2.fromOffset(34, 34)
Close.Position = UDim2.new(1, -39, 0, 10)
Close.BackgroundColor3 = COLORS.RED_DARK

--==============================================================--
-- CAFEÍNA ASSISTENTE • SMALL FLOATING BUTTON
--==============================================================--

local AssistantLauncher = Instance.new("TextButton")

AssistantLauncher.Size = UDim2.fromOffset(128, 34)
AssistantLauncher.Position = UDim2.new(1, -142, 0, 62)

AssistantLauncher.BackgroundColor3 = COLORS.PANEL
AssistantLauncher.BorderSizePixel = 0
AssistantLauncher.AutoButtonColor = false

AssistantLauncher.Text = "✦  CAFEÍNA IA"
AssistantLauncher.TextColor3 = COLORS.TEXT
AssistantLauncher.TextSize = 10
AssistantLauncher.Font = Enum.Font.GothamBold

corner(AssistantLauncher, 9)
stroke(AssistantLauncher, COLORS.RED_DARK, 1)

AssistantLauncher.Parent = Main

--==============================================================--
-- PATH / REFRESH--==============================================================--
-- PATH / REFRESH
--==============================================================--

local PathBar = Instance.new("Frame")

PathBar.Size = UDim2.new(1, -14, 0, 38)
PathBar.Position = UDim2.fromOffset(7, 62)

PathBar.BackgroundColor3 = COLORS.PANEL
PathBar.BorderSizePixel = 0

corner(PathBar, 9)
stroke(PathBar)

PathBar.Parent = Main

local PathLabel = label(
    PathBar,
    "/",
    9,
    COLORS.SUB
)

PathLabel.Size = UDim2.new(1, -48, 1, 0)
PathLabel.Position = UDim2.fromOffset(10, 0)
PathLabel.TextTruncate = Enum.TextTruncate.AtEnd

local Refresh = button(PathBar, "↻")
Refresh.Size = UDim2.fromOffset(32, 28)
Refresh.Position = UDim2.new(1, -37, 0, 5)

--==============================================================--
-- SEARCH
--==============================================================--

local Search = Instance.new("TextBox")

Search.Size = UDim2.new(1, -14, 0, 38)
Search.Position = UDim2.fromOffset(7, 106)

Search.BackgroundColor3 = COLORS.PANEL
Search.BorderSizePixel = 0

Search.Text = ""
Search.PlaceholderText = "Pesquisar arquivos e pastas..."
Search.ClearTextOnFocus = false

Search.TextSize = 12
Search.TextColor3 = COLORS.TEXT
Search.PlaceholderColor3 = COLORS.SUB
Search.Font = Enum.Font.Gotham

corner(Search, 9)
stroke(Search)

Search.Parent = Main

--==============================================================--
-- MAIN CONTENT
--==============================================================--

local Content = Instance.new("Frame")

Content.Size = UDim2.new(1, -14, 1, -205)
Content.Position = UDim2.fromOffset(7, 151)

Content.BackgroundColor3 = COLORS.PANEL
Content.BorderSizePixel = 0

corner(Content, 10)
stroke(Content)

Content.Parent = Main

-- LIST
local List = Instance.new("ScrollingFrame")

List.Size = UDim2.new(1, -8, 1, -8)
List.Position = UDim2.fromOffset(4, 4)

List.BackgroundTransparency = 1
List.BorderSizePixel = 0

List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = COLORS.RED

List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.CanvasSize = UDim2.new()

List.Parent = Content

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 4)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

-- VIEWER
local Viewer = Instance.new("Frame")

Viewer.Size = UDim2.new(1, -8, 1, -8)
Viewer.Position = UDim2.fromOffset(4, 4)

Viewer.BackgroundTransparency = 1
Viewer.Visible = false
Viewer.Parent = Content

local ViewerHeader = Instance.new("Frame")

ViewerHeader.Size = UDim2.new(1, 0, 0, 47)
ViewerHeader.BackgroundTransparency = 1
ViewerHeader.Parent = Viewer

local ViewerName = label(
    ViewerHeader,
    "",
    13,
    COLORS.TEXT
)

ViewerName.Font = Enum.Font.GothamBold
ViewerName.Size = UDim2.new(1, -15, 0, 24)
ViewerName.Position = UDim2.fromOffset(5, 0)
ViewerName.TextTruncate = Enum.TextTruncate.AtEnd

local ViewerMeta = label(
    ViewerHeader,
    "",
    9,
    COLORS.SUB
)

ViewerMeta.Size = UDim2.new(1, -15, 0, 18)
ViewerMeta.Position = UDim2.fromOffset(5, 25)
ViewerMeta.TextTruncate = Enum.TextTruncate.AtEnd

local TextScroll = Instance.new("ScrollingFrame")

TextScroll.Size = UDim2.new(1, 0, 1, -47)
TextScroll.Position = UDim2.fromOffset(0, 47)

TextScroll.BackgroundColor3 = COLORS.PANEL2
TextScroll.BorderSizePixel = 0

TextScroll.ScrollBarThickness = 3
TextScroll.ScrollBarImageColor3 = COLORS.RED

TextScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
TextScroll.CanvasSize = UDim2.new()

corner(TextScroll, 8)
stroke(TextScroll)

TextScroll.Parent = Viewer

local ViewerText = Instance.new("TextLabel")

ViewerText.BackgroundTransparency = 1
ViewerText.Position = UDim2.fromOffset(8, 8)

ViewerText.Size = UDim2.new(1, -16, 0, 0)
ViewerText.AutomaticSize = Enum.AutomaticSize.XY

ViewerText.Text = ""
ViewerText.TextColor3 = Color3.fromRGB(220, 220, 226)

ViewerText.Font = Enum.Font.Code
ViewerText.TextSize = 11

ViewerText.TextXAlignment = Enum.TextXAlignment.Left
ViewerText.TextYAlignment = Enum.TextYAlignment.Top
ViewerText.TextWrapped = false

ViewerText.Parent = TextScroll

local ImagePreview = Instance.new("ImageLabel")

ImagePreview.Size = UDim2.new(1, 0, 1, -47)
ImagePreview.Position = UDim2.fromOffset(0, 47)

ImagePreview.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
ImagePreview.BorderSizePixel = 0

ImagePreview.ScaleType = Enum.ScaleType.Fit
ImagePreview.Visible = false

corner(ImagePreview, 8)
stroke(ImagePreview)

ImagePreview.Parent = Viewer

--==============================================================--
-- CAFEÍNA ASSISTENTE • CHAT
--==============================================================--

local AIPanel = Instance.new("Frame")
AIPanel.Size = UDim2.new(1, -14, 1, -109)
AIPanel.Position = UDim2.fromOffset(7, 62)
AIPanel.BackgroundColor3 = COLORS.BG
AIPanel.BorderSizePixel = 0
AIPanel.Visible = false
corner(AIPanel, 11)
stroke(AIPanel, COLORS.RED_DARK, 1)
AIPanel.Parent = Main

local AIHeader = Instance.new("Frame")
AIHeader.Size = UDim2.new(1, 0, 0, 46)
AIHeader.BackgroundColor3 = COLORS.TOP
AIHeader.BorderSizePixel = 0
corner(AIHeader, 11)
AIHeader.Parent = AIPanel

local AIBack = button(AIHeader, "‹")
AIBack.Size = UDim2.fromOffset(32, 32)
AIBack.Position = UDim2.fromOffset(7, 7)

local AIHeaderIcon = label(AIHeader, "✦", 16, COLORS.RED)
AIHeaderIcon.Font = Enum.Font.GothamBold
AIHeaderIcon.Size = UDim2.fromOffset(28, 46)
AIHeaderIcon.Position = UDim2.fromOffset(43, 0)
AIHeaderIcon.TextXAlignment = Enum.TextXAlignment.Center

local AITitle = label(AIHeader, "CAFEÍNA ASSISTENTE", 13, COLORS.TEXT)
AITitle.Font = Enum.Font.GothamBold
AITitle.Size = UDim2.new(1, -120, 0, 21)
AITitle.Position = UDim2.fromOffset(72, 3)

local AISubtitle = label(AIHeader, "Especialista no Explorer", 8, COLORS.SUB)
AISubtitle.Size = UDim2.new(1, -120, 0, 16)
AISubtitle.Position = UDim2.fromOffset(72, 23)
AISubtitle.TextTruncate = Enum.TextTruncate.AtEnd

local AIClear = button(AIHeader, "LIMPAR")
AIClear.Size = UDim2.fromOffset(55, 28)
AIClear.Position = UDim2.new(1, -61, 0, 9)
AIClear.TextSize = 9

local AIChat = Instance.new("ScrollingFrame")
AIChat.Size = UDim2.new(1, -10, 1, -113)
AIChat.Position = UDim2.fromOffset(5, 51)
AIChat.BackgroundColor3 = COLORS.PANEL
AIChat.BorderSizePixel = 0
AIChat.ScrollBarThickness = 3
AIChat.ScrollBarImageColor3 = COLORS.RED
AIChat.AutomaticCanvasSize = Enum.AutomaticSize.Y
AIChat.CanvasSize = UDim2.new()
corner(AIChat, 9)
stroke(AIChat)
AIChat.Parent = AIPanel

local AIChatPadding = Instance.new("UIPadding")
AIChatPadding.PaddingTop = UDim.new(0, 8)
AIChatPadding.PaddingBottom = UDim.new(0, 8)
AIChatPadding.PaddingLeft = UDim.new(0, 7)
AIChatPadding.PaddingRight = UDim.new(0, 7)
AIChatPadding.Parent = AIChat

local AIChatLayout = Instance.new("UIListLayout")
AIChatLayout.Padding = UDim.new(0, 8)
AIChatLayout.SortOrder = Enum.SortOrder.LayoutOrder
AIChatLayout.Parent = AIChat

local AIComposer = Instance.new("Frame")
AIComposer.Size = UDim2.new(1, -10, 0, 52)
AIComposer.Position = UDim2.new(0, 5, 1, -56)
AIComposer.BackgroundColor3 = COLORS.PANEL
AIComposer.BorderSizePixel = 0
corner(AIComposer, 10)
stroke(AIComposer)
AIComposer.Parent = AIPanel

local AIPrompt = Instance.new("TextBox")
AIPrompt.Size = UDim2.new(1, -56, 1, -10)
AIPrompt.Position = UDim2.fromOffset(5, 5)
AIPrompt.BackgroundColor3 = COLORS.PANEL2
AIPrompt.BorderSizePixel = 0
AIPrompt.Text = ""
AIPrompt.PlaceholderText = "Pergunte sobre o Explorer..."
AIPrompt.ClearTextOnFocus = false
AIPrompt.MultiLine = true
AIPrompt.TextSize = 12
AIPrompt.TextColor3 = COLORS.TEXT
AIPrompt.PlaceholderColor3 = COLORS.SUB
AIPrompt.Font = Enum.Font.Gotham
AIPrompt.TextXAlignment = Enum.TextXAlignment.Left
AIPrompt.TextYAlignment = Enum.TextYAlignment.Top
corner(AIPrompt, 8)
stroke(AIPrompt)
AIPrompt.Parent = AIComposer

local AISend = button(AIComposer, "➤")
AISend.Size = UDim2.fromOffset(41, 41)
AISend.Position = UDim2.new(1, -46, 0.5, -20)
AISend.BackgroundColor3 = COLORS.RED_DARK
AISend.TextSize = 17

--==============================================================--
-- BOTTOM ACTION BAR
--==============================================================--

local Bottom = Instance.new("Frame")

Bottom.Size = UDim2.new(1, -14, 0, 45)
Bottom.Position = UDim2.new(0, 7, 1, -48)

Bottom.BackgroundColor3 = COLORS.PANEL
Bottom.BorderSizePixel = 0

corner(Bottom, 9)
stroke(Bottom)

Bottom.Parent = Main

local StatusDot = Instance.new("Frame")

StatusDot.Size = UDim2.fromOffset(8, 8)
StatusDot.Position = UDim2.new(0, 10, 0.5, -4)

StatusDot.BackgroundColor3 = COLORS.GREEN
StatusDot.BorderSizePixel = 0

corner(StatusDot, 20)

StatusDot.Parent = Bottom

local StatusText = label(
    Bottom,
    "Pronto",
    9,
    COLORS.SUB
)

StatusText.Size = UDim2.new(1, -220, 1, 0)
StatusText.Position = UDim2.fromOffset(25, 0)
StatusText.TextTruncate = Enum.TextTruncate.AtEnd

local Copy = button(Bottom, "COPIAR")
Copy.Size = UDim2.fromOffset(74, 31)
Copy.Position = UDim2.new(1, -162, 0.5, -15)
Copy.Visible = false

local Save = button(Bottom, "SALVAR")
Save.Size = UDim2.fromOffset(74, 31)
Save.Position = UDim2.new(1, -83, 0.5, -15)
Save.BackgroundColor3 = COLORS.RED_DARK
Save.Visible = false

--==============================================================--
-- STATUS
--==============================================================--

local function setStatus(text, color)
    if GuiDestroyed then
        return
    end

    StatusText.Text = tostring(text or "")

    if color then
        StatusDot.BackgroundColor3 = color
    end
end

--==============================================================--
-- MEDIA / MODE
--==============================================================--

local function clearMedia()
    ImagePreview.Visible = false
    ImagePreview.Image = ""
    CurrentAsset = nil
    TextScroll.Visible = true
end

local function clearSelectedData()
    SelectedPath = nil
    SelectedData = nil
    SelectedText = ""
    SelectedHex = ""
    SelectedInfo = ""
    CurrentFileType = nil
    CurrentFormat = nil
end

local function showList()
    CurrentMode = "LIST"

    clearMedia()

    Viewer.Visible = false
    List.Visible = true

    Search.Visible = true
    Copy.Visible = false
    Save.Visible = false

    HeaderTitle.Text = "CAFEÍNA"
    HeaderSub.Text = "FILE EXPLORER V3"

    clearSelectedData()

    if #CurrentEntries == 0 then
        setStatus(
            "Pasta vazia ou sem itens acessíveis",
            COLORS.YELLOW
        )
    else
        setStatus(
            tostring(#CurrentEntries) .. " item(ns)",
            COLORS.GREEN
        )
    end
end

local function showTextMode(mode, text, meta)
    CurrentMode = mode

    List.Visible = false
    Viewer.Visible = true
    Search.Visible = false

    clearMedia()

    TextScroll.Visible = true
    ViewerText.Text = text or ""
    TextScroll.CanvasPosition = Vector2.new(0, 0)

    ViewerName.Text = basename(SelectedPath or "")
    ViewerMeta.Text = meta or ""
    Copy.Visible = true
    Save.Visible = CurrentFileType == "IMAGE" and API.writefile ~= nil
end

local function showImageMode()
    CurrentMode = "IMAGE"

    List.Visible = false
    Viewer.Visible = true
    Search.Visible = false

    clearMedia()

    ViewerName.Text = basename(SelectedPath or "")
    ViewerMeta.Text =
        tostring(CurrentFormat or "IMAGE")
        .. " • "
        .. readableSize(SelectedData and #SelectedData or 0)
    Copy.Visible = true
    Save.Visible = API.writefile ~= nil

    if not API.customAsset then
        showTextMode(
            "INFO",
            "Preview de imagem indisponível neste ambiente.\n\n"
            .. SelectedInfo,
            ViewerMeta.Text
        )

        setStatus(
            "getcustomasset/getsynasset indisponível",
            COLORS.YELLOW
        )

        return
    end

    local ok, asset = safeCall(
        API.customAsset,
        SelectedPath
    )

    if not ok or not asset then
        showTextMode(
            "INFO",
            "Não foi possível carregar a imagem.\n\n"
            .. SelectedInfo,
            ViewerMeta.Text
        )

        setStatus(
            "Falha ao abrir imagem",
            COLORS.RED
        )

        return
    end

    CurrentAsset = asset

    TextScroll.Visible = false
    ImagePreview.Image = asset
    ImagePreview.Visible = true

    setStatus(
        tostring(CurrentFormat)
        .. " • "
        .. readableSize(#SelectedData),
        COLORS.GREEN
    )
end

--==============================================================--
-- PREPARE FILE
--==============================================================--

local function prepareFile(path)
    setStatus(
        "Lendo arquivo...",
        COLORS.YELLOW
    )

    local ok, data = safeCall(
        API.readfile,
        path
    )

    if not ok then
        setStatus(
            "Erro ao ler arquivo",
            COLORS.RED
        )

        return false, tostring(data)
    end

    data = type(data) == "string"
        and data
        or tostring(data or "")

    SelectedPath = path
    SelectedData = data

    CurrentFileType, CurrentFormat =
        getType(path, data)

    SelectedInfo = buildInfo(
        path,
        data,
        CurrentFileType,
        CurrentFormat
    )

    SelectedHex = hexDump(data)

    local textSample = data:sub(
        1,
        math.min(#data, CONFIG.MAX_TEXT_BYTES)
    )

    local truncated =
        #data > CONFIG.MAX_TEXT_BYTES

    if CurrentFileType == "LUA" then
        SelectedText = lineNumberText(textSample)

    elseif CurrentFileType == "JSON" then
        if #data <= CONFIG.MAX_JSON_PARSE_BYTES then
            local formatted, err = formatJSON(data)

            SelectedText =
                formatted
                or (
                    "JSON inválido\n\n"
                    .. tostring(err)
                    .. "\n\n"
                    .. textSample
                )
        else
            SelectedText =
                "JSON muito grande para formatação completa.\n\n"
                .. textSample
        end

    elseif CurrentFileType == "CSV" then
        SelectedText = formatCSV(textSample)

    elseif CurrentFileType == "TEXT" then
        SelectedText = textSample

    else
        SelectedText =
            "[Conteúdo binário]\n\n"
            .. "Use a visualização HEX."
    end

    if truncated
        and (
            CurrentFileType == "TEXT"
            or CurrentFileType == "LUA"
            or CurrentFileType == "JSON"
            or CurrentFileType == "CSV"
        )
    then
        SelectedText =
            SelectedText
            .. "\n\n"
            .. string.format(
                "[PREVIEW LIMITADO • mostrando %s de %s]",
                readableSize(CONFIG.MAX_TEXT_BYTES),
                readableSize(#data)
            )
    end

    return true
end

local function openFile(path)
    local ok, err = prepareFile(path)

    if not ok then
        showTextMode(
            "INFO",
            "Erro ao abrir arquivo:\n\n"
            .. tostring(err),
            "ERRO"
        )

        return
    end

    HeaderTitle.Text = basename(path)
    HeaderSub.Text =
        tostring(CurrentFormat or CurrentFileType or "ARQUIVO")

    if CurrentFileType == "IMAGE" then
        showImageMode()

    elseif CurrentFileType == "TEXT"
        or CurrentFileType == "LUA"
        or CurrentFileType == "JSON"
        or CurrentFileType == "CSV"
    then
        showTextMode(
            "TEXT",
            SelectedText,
            tostring(CurrentFormat)
            .. " • "
            .. readableSize(#SelectedData)
        )

        setStatus(
            tostring(CurrentFormat)
            .. " • "
            .. readableSize(#SelectedData),
            COLORS.GREEN
        )

    else
        showTextMode(
            "HEX",
            SelectedHex,
            tostring(CurrentFormat)
            .. " • "
            .. readableSize(#SelectedData)
        )

        setStatus(
            tostring(CurrentFormat)
            .. " • "
            .. readableSize(#SelectedData),
            COLORS.GREEN
        )
    end
end

--==============================================================--
-- FILE ROWS
--==============================================================--

local function clearList()
    for _, child in ipairs(List:GetChildren()) do
        if child:IsA("GuiObject")
            and child ~= ListLayout
        then
            child:Destroy()
        end
    end
end

local openDirectory

local function createRow(entry, order)
    local Row = Instance.new("TextButton")

    Row.Size = UDim2.new(1, -4, 0, 58)
    Row.BackgroundColor3 = COLORS.PANEL2
    Row.BorderSizePixel = 0

    Row.AutoButtonColor = false
    Row.Text = ""
    Row.LayoutOrder = order

    corner(Row, 9)
    stroke(Row)

    Row.Parent = List

    local Icon = label(
        Row,
        entry.folder and "▣" or "•",
        16,
        entry.folder and COLORS.RED or COLORS.SUB
    )

    Icon.Size = UDim2.fromOffset(42, 58)
    Icon.Position = UDim2.fromOffset(3, 0)
    Icon.TextXAlignment = Enum.TextXAlignment.Center

    local Name = label(
        Row,
        basename(entry.path),
        12,
        COLORS.TEXT
    )

    Name.Font = Enum.Font.GothamMedium
    Name.Size = UDim2.new(1, -92, 0, 27)
    Name.Position = UDim2.fromOffset(45, 5)
    Name.TextTruncate = Enum.TextTruncate.AtEnd

    local Meta = label(
        Row,
        entry.folder
            and "Pasta"
            or extensionLabel(entry.path),
        9,
        COLORS.SUB
    )

    Meta.Size = UDim2.new(1, -92, 0, 18)
    Meta.Position = UDim2.fromOffset(45, 32)

    local Arrow = label(
        Row,
        "›",
        18,
        COLORS.SUB
    )

    Arrow.Size = UDim2.fromOffset(30, 58)
    Arrow.Position = UDim2.new(1, -34, 0, 0)
    Arrow.TextXAlignment = Enum.TextXAlignment.Center

    Row.Activated:Connect(function()
        if entry.folder then
            openDirectory(entry.path, true)
        else
            openFile(entry.path)
        end
    end)
end

--==============================================================--
-- RENDER • PROGRESSIVE / LARGE FOLDER SAFE
--==============================================================--

local function rebuildFilteredEntries()
    FilteredEntries = {}

    local query = Search.Text:lower()

    for _, entry in ipairs(CurrentEntries) do
        local name = basename(entry.path):lower()

        if query == ""
            or name:find(query, 1, true)
        then
            FilteredEntries[#FilteredEntries + 1] = entry
        end
    end
end

local function appendRenderBatch(amount)
    if GuiDestroyed or IsAppendingBatch then
        return
    end

    IsAppendingBatch = true

    local generation = RenderGeneration
    local target = math.min(
        #FilteredEntries,
        RenderedCount + (amount or CONFIG.LOAD_MORE_BATCH),
        CONFIG.MAX_RENDERED_FILES
    )

    local startAt = RenderedCount + 1

    for index = startAt, target do
        if generation ~= RenderGeneration or GuiDestroyed then
            IsAppendingBatch = false
            return
        end

        local entry = FilteredEntries[index]

        if entry and entry.path then
            RenderedCount += 1

            local rowOk, rowError = pcall(function()
                createRow(entry, RenderedCount)
            end)

            if not rowOk then
                warn("[CAFEÍNA Explorer] Falha ao renderizar item:", rowError)
            end
        end

        -- Entrega tempo ao mobile em lotes grandes.
        if RenderedCount > 0 and RenderedCount % 60 == 0 then
            task.wait()
        end
    end

    IsAppendingBatch = false

    if #FilteredEntries > CONFIG.MAX_RENDERED_FILES
        and RenderedCount >= CONFIG.MAX_RENDERED_FILES
    then
        setStatus(
            tostring(#FilteredEntries)
            .. " resultado(s) • limite visual "
            .. tostring(CONFIG.MAX_RENDERED_FILES),
            COLORS.YELLOW
        )

    elseif RenderedCount < #FilteredEntries then
        setStatus(
            tostring(RenderedCount)
            .. " de "
            .. tostring(#FilteredEntries)
            .. " • role para carregar mais",
            COLORS.GREEN
        )
    else
        setStatus(
            tostring(#FilteredEntries) .. " item(ns)",
            COLORS.GREEN
        )
    end
end

local function render()
    if GuiDestroyed then
        return
    end

    RenderGeneration += 1
    clearList()

    rebuildFilteredEntries()
    RenderedCount = 0
    List.CanvasPosition = Vector2.new(0, 0)

    appendRenderBatch(CONFIG.INITIAL_VISIBLE_FILES)
end

-- Auto-carregamento quando o scroll se aproxima do final
List:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    if GuiDestroyed
        or CurrentMode ~= "LIST"
        or IsAppendingBatch
        or RenderedCount >= #FilteredEntries
        or RenderedCount >= CONFIG.MAX_RENDERED_FILES
    then
        return
    end

    local remaining =
        List.AbsoluteCanvasSize.Y
        - (
            List.CanvasPosition.Y
            + List.AbsoluteWindowSize.Y
        )

    if remaining < 420 then
        appendRenderBatch(CONFIG.LOAD_MORE_BATCH)
    end
end)

--==============================================================--
-- OPEN DIRECTORY
--==============================================================--

openDirectory = function(path, saveHistory)
    if GuiDestroyed then
        return
    end

    path = normalizePath(path)

    DirectoryGeneration += 1
    local generation = DirectoryGeneration

    setStatus(
        "Abrindo pasta...",
        COLORS.YELLOW
    )

    local ok, files = safeCall(
        API.listfiles,
        path
    )

    if generation ~= DirectoryGeneration then
        return
    end

    if not ok or typeof(files) ~= "table" then
        setStatus(
            "Erro ao abrir pasta",
            COLORS.RED
        )

        return
    end

    if saveHistory
        and CurrentPath ~= path
    then
        History[#History + 1] = CurrentPath

        while #History > CONFIG.MAX_HISTORY do
            table.remove(History, 1)
        end
    end

    CurrentPath = path
    PathLabel.Text = path == "" and "/" or path

    CurrentEntries = {}

    for _, filePath in ipairs(files) do
        if type(filePath) == "string" then
            filePath = normalizePath(filePath)

            if filePath ~= "" then
                CurrentEntries[#CurrentEntries + 1] = {
                    path = filePath,
                    folder = pathIsFolder(filePath),
                }
            end
        end
    end

    table.sort(
        CurrentEntries,
        function(a, b)
            if a.folder ~= b.folder then
                return a.folder
            end

            return
                basename(a.path):lower()
                < basename(b.path):lower()
        end
    )

    if Search.Text ~= "" then
        Search.Text = ""
    end

    showList()
    render()
end

--==============================================================--
-- ROOT DETECTION
--==============================================================--

local function detectRoot()
    local candidates = {
        "",
        ".",
        "/",
        "workspace",
        "Workspace",
        "scripts",
        "Scripts",
    }

    for _, candidate in ipairs(candidates) do
        local ok, result = safeCall(
            API.listfiles,
            candidate
        )

        if ok and typeof(result) == "table" then
            return candidate
        end
    end

    return nil
end

--==============================================================--
-- SEARCH
--==============================================================--

Search:GetPropertyChangedSignal("Text"):Connect(function()
    SearchGeneration += 1

    local generation = SearchGeneration

    task.delay(CONFIG.SEARCH_DELAY, function()
        if GuiDestroyed then
            return
        end

        if generation ~= SearchGeneration then
            return
        end

        if CurrentMode == "LIST" then
            render()
        end
    end)
end)

--==============================================================--
-- NAVIGATION
--==============================================================--

Back.Activated:Connect(function()
    if AIVisible then
        setAIVisible(false)
        return
    end

    if CurrentMode ~= "LIST" then
        showList()
        render()
        return
    end

    if #History <= 0 then
        setStatus(
            "Sem histórico anterior",
            COLORS.YELLOW
        )

        return
    end

    local previous = table.remove(History)

    openDirectory(
        previous,
        false
    )
end)

Up.Activated:Connect(function()
    if CurrentMode ~= "LIST" then
        showList()
        render()
        return
    end

    if CurrentPath == RootPath then
        setStatus(
            "Você já está na raiz",
            COLORS.YELLOW
        )

        return
    end

    local parent = dirname(CurrentPath)

    if RootPath ~= ""
        and parent == ""
    then
        parent = RootPath
    end

    if parent == CurrentPath then
        return
    end

    openDirectory(
        parent,
        true
    )
end)

Home.Activated:Connect(function()
    if AIVisible then
        setAIVisible(false)
    end

    History = {}

    openDirectory(
        RootPath,
        false
    )
end)

Refresh.Activated:Connect(function()
    if AIVisible then
        setAIVisible(false)
    end

    if CurrentMode ~= "LIST" then
        if SelectedPath then
            openFile(SelectedPath)
        end
        return
    end

    openDirectory(
        CurrentPath,
        false
    )
end)

--==============================================================--
-- CAFEÍNA ASSISTENTE • LOGIC
--==============================================================--

local AIMessageOrder = 0
local AIConversation = {}

local function scrollChatToBottom()
    task.defer(function()
        if GuiDestroyed or not AIChat.Parent then
            return
        end

        local y = math.max(
            0,
            AIChat.AbsoluteCanvasSize.Y - AIChat.AbsoluteWindowSize.Y
        )

        AIChat.CanvasPosition = Vector2.new(0, y)
    end)
end

local function clearChatMessages()
    for _, child in ipairs(AIChat:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    AIMessageOrder = 0
    AIConversation = {}
    LastAIResponse = ""
end

local function addChatMessage(role, text)
    text = tostring(text or "")
    AIMessageOrder += 1

    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.LayoutOrder = AIMessageOrder
    holder.Parent = AIChat

    local isUser = role == "user"

    local bubble = Instance.new("Frame")
    bubble.Size = UDim2.new(0.88, 0, 0, 0)
    bubble.AutomaticSize = Enum.AutomaticSize.Y
    bubble.AnchorPoint = Vector2.new(isUser and 1 or 0, 0)
    bubble.Position = UDim2.new(isUser and 1 or 0, 0, 0, 0)
    bubble.BackgroundColor3 = isUser and COLORS.RED_DARK or COLORS.PANEL2
    bubble.BorderSizePixel = 0
    corner(bubble, 10)
    stroke(bubble, isUser and COLORS.RED_DARK or COLORS.STROKE, 1)
    bubble.Parent = holder

    local roleLabel = label(
        bubble,
        isUser and "VOCÊ" or "CAFEÍNA",
        8,
        isUser and Color3.fromRGB(255, 205, 210) or COLORS.RED
    )
    roleLabel.Font = Enum.Font.GothamBold
    roleLabel.Size = UDim2.new(1, -18, 0, 17)
    roleLabel.Position = UDim2.fromOffset(9, 5)

    local message = Instance.new("TextLabel")
    message.BackgroundTransparency = 1
    message.Size = UDim2.new(1, -18, 0, 0)
    message.Position = UDim2.fromOffset(9, 23)
    message.AutomaticSize = Enum.AutomaticSize.Y
    message.Text = text
    message.TextColor3 = COLORS.TEXT
    message.TextSize = 11
    message.Font = Enum.Font.Gotham
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.TextYAlignment = Enum.TextYAlignment.Top
    message.Parent = bubble

    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 9)
    pad.Parent = bubble

    AIConversation[#AIConversation + 1] = {
        role = role,
        content = text,
    }

    scrollChatToBottom()
    return bubble
end

local function addWelcomeMessage()
    addChatMessage(
        "assistant",
        "Olá! Eu sou a CAFEÍNA ASSISTENTE.\n\n"
        .. "Posso tirar dúvidas sobre o Explorer, explicar o arquivo aberto, "
        .. "analisar JSON, Lua/Luau, texto, HEX e metadados.\n\n"
        .. "Exemplos:\n"
        .. "• O que é este arquivo?\n"
        .. "• Explique esse JSON.\n"
        .. "• O que significa esse HEX?\n"
        .. "• Qual arquivo desta pasta parece configuração?\n"
        .. "• Pesquisar config\n"
        .. "• Abrir settings.json\n"
        .. "• Atualizar pasta\n"
        .. "• Ir para raiz"
    )
end

local function setAIVisible(visible)
    AIVisible = visible == true
    AIPanel.Visible = AIVisible

    -- O assistente sobrepõe o Explorer sem esconder o conteúdo.
    -- Isso permite consultar e também agir sobre o estado atual.
    if AIVisible then
        AISubtitle.Text =
            SelectedPath
            and ("Arquivo: " .. basename(SelectedPath))
            or ("Pasta: " .. (CurrentPath == "" and "/" or CurrentPath))

        if #AIConversation == 0 then
            addWelcomeMessage()
        end

        AIPanel.ZIndex = 50
    end
end

local function buildExplorerSummary()
    local lines = {
        "CONTEXTO DO CAFEÍNA EXPLORER",
        "",
        "Pasta atual: " .. (CurrentPath == "" and "/" or CurrentPath),
        "Itens carregados: " .. tostring(#CurrentEntries),
    }

    if #CurrentEntries > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Itens da pasta (amostra):"

        local limit = math.min(#CurrentEntries, 60)

        for i = 1, limit do
            local entry = CurrentEntries[i]

            lines[#lines + 1] =
                (entry.folder and "[PASTA] " or "[ARQUIVO] ")
                .. basename(entry.path)
                .. (
                    entry.folder
                    and ""
                    or (" • " .. extensionLabel(entry.path))
                )
        end

        if #CurrentEntries > limit then
            lines[#lines + 1] =
                "[... "
                .. tostring(#CurrentEntries - limit)
                .. " item(ns) adicionais não incluídos]"
        end
    end

    return table.concat(lines, "\n")
end

local function buildSelectedFileContext()
    if not SelectedPath then
        return "Nenhum arquivo está aberto no momento."
    end

    local lines = {
        "ARQUIVO ABERTO",
        "Nome: " .. basename(SelectedPath),
        "Caminho: " .. SelectedPath,
        "Tipo: " .. tostring(CurrentFileType or "desconhecido"),
        "Formato: " .. tostring(CurrentFormat or "desconhecido"),
        "",
    }

    if CurrentFileType == "IMAGE" then
        lines[#lines + 1] =
            "A imagem não está sendo enviada como conteúdo visual."
        lines[#lines + 1] =
            "Use os metadados abaixo:"
        lines[#lines + 1] = ""
        lines[#lines + 1] =
            SelectedInfo:sub(1, CONFIG.AI_MAX_TEXT_CHARS)

    elseif CurrentFileType == "BINARY" then
        lines[#lines + 1] = "Amostra HEX:"
        lines[#lines + 1] = ""
        lines[#lines + 1] =
            SelectedHex:sub(1, CONFIG.AI_MAX_HEX_CHARS)

    else
        lines[#lines + 1] = "Conteúdo do arquivo:"
        lines[#lines + 1] = ""

        local body =
            SelectedText ~= ""
            and SelectedText
            or tostring(SelectedData or "")

        lines[#lines + 1] =
            body:sub(1, CONFIG.AI_MAX_TEXT_CHARS)

        if #body > CONFIG.AI_MAX_TEXT_CHARS then
            lines[#lines + 1] = ""
            lines[#lines + 1] =
                "[Conteúdo truncado para proteger desempenho]"
        end
    end

    return table.concat(lines, "\n")
end

local function buildConversationContext()
    local lines = {}
    local startIndex = math.max(1, #AIConversation - 8)

    for i = startIndex, #AIConversation do
        local item = AIConversation[i]

        if item then
            lines[#lines + 1] =
                (item.role == "user" and "Usuário: " or "Assistente: ")
                .. item.content
        end
    end

    return table.concat(lines, "\n\n")
end

local function extractAIResponse(response)
    if type(response) == "string" then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(response)
        end)

        if ok and type(decoded) == "table" then
            response = {Body = response}
        else
            return response
        end
    end

    if type(response) ~= "table" then
        return nil
    end

    local body =
        response.Body
        or response.body
        or response.ResponseBody
        or response.responseBody

    if type(body) ~= "string" then
        return nil
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not ok or type(decoded) ~= "table" then
        return body
    end

    local result =
        decoded.response
        or decoded.reply
        or decoded.message
        or decoded.content
        or decoded.answer
        or decoded.text

    if type(result) == "table" then
        return result.content or result.text or result.message
    end

    if type(result) == "string" then
        return result
    end

    if decoded.error then
        if type(decoded.error) == "table" then
            return
                decoded.error.message
                or HttpService:JSONEncode(decoded.error)
        end

        return tostring(decoded.error)
    end

    return body
end

local function normalizeCommand(textValue)
    return tostring(textValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function tryExplorerAction(question)
    local q = normalizeCommand(question)

    -- Voltar para lista
    if q == "voltar"
        or q:find("voltar para lista", 1, true)
        or q:find("mostrar arquivos", 1, true)
    then
        showList()
        render()
        return true, "Voltei para a lista de arquivos."

    -- Home
    elseif q == "home"
        or q:find("ir para raiz", 1, true)
        or q:find("abrir raiz", 1, true)
    then
        History = {}
        openDirectory(RootPath, false)
        return true, "Abri a pasta raiz do Explorer."

    -- Subir pasta
    elseif q:find("subir uma pasta", 1, true)
        or q:find("pasta pai", 1, true)
    then
        local parent = dirname(CurrentPath)

        if parent == CurrentPath then
            return true, "Você já está no nível mais alto disponível."
        end

        if RootPath ~= "" and parent == "" then
            parent = RootPath
        end

        openDirectory(parent, true)
        return true, "Subi para a pasta pai."

    -- Atualizar
    elseif q:find("atualizar pasta", 1, true)
        or q == "atualizar"
        or q == "refresh"
    then
        openDirectory(CurrentPath, false)
        return true, "Atualizei a pasta atual."

    -- Limpar busca
    elseif q:find("limpar busca", 1, true)
        or q:find("limpar pesquisa", 1, true)
    then
        Search.Text = ""
        render()
        return true, "Limpei a busca do Explorer."
    end

    -- Pesquisar "termo"
    local searchTerm =
        q:match('pesquisar%s+["“](.-)["”]')
        or q:match('buscar%s+["“](.-)["”]')
        or q:match("pesquisar%s+(.+)")
        or q:match("buscar%s+(.+)")

    if searchTerm and #searchTerm > 0 and #searchTerm < 120 then
        Search.Text = searchTerm
        render()
        return true, 'Pesquisei por "' .. searchTerm .. '".'
    end

    -- Abrir arquivo/pasta por nome exato ou parcial
    local openName =
        q:match('abrir%s+["“](.-)["”]')
        or q:match("abrir arquivo%s+(.+)")
        or q:match("abrir pasta%s+(.+)")

    if openName and #openName > 0 and #openName < 180 then
        local lowerName = openName:lower()
        local partial = nil

        for _, entry in ipairs(CurrentEntries) do
            local entryName = basename(entry.path):lower()

            if entryName == lowerName then
                if entry.folder then
                    openDirectory(entry.path, true)
                else
                    openFile(entry.path)
                end

                return true, 'Abri "' .. basename(entry.path) .. '".'
            end

            if not partial and entryName:find(lowerName, 1, true) then
                partial = entry
            end
        end

        if partial then
            if partial.folder then
                openDirectory(partial.path, true)
            else
                openFile(partial.path)
            end

            return true, 'Abri o resultado mais próximo: "' .. basename(partial.path) .. '".'
        end

        return true, 'Não encontrei "' .. openName .. '" na pasta atual.'
    end

    return false
end

local API_ERROR_MESSAGES = {
    NETWORK = {
        "Não consegui alcançar o servidor da CAFEÍNA AI. O Explorer continua funcionando normalmente.",
        "A conexão com a IA falhou. Você ainda pode navegar, pesquisar e abrir arquivos pelo Explorer.",
        "O backend da IA não respondeu. Tente novamente depois; nenhuma alteração foi feita no Explorer.",
    },

    RATE_LIMIT = {
        "A API está recebendo muitas solicitações agora. Aguarde um pouco antes de enviar outra pergunta.",
        "A CAFEÍNA AI atingiu um limite temporário de uso. O Explorer segue disponível normalmente.",
    },

    CREDITS = {
        "A API parece estar sem saldo/créditos disponíveis. A assinatura do ChatGPT e os créditos da API são separados.",
        "O backend respondeu com um erro de limite financeiro da API. O Explorer não depende disso e continua funcionando.",
    },

    SERVER = {
        "O servidor da CAFEÍNA AI encontrou um erro interno. O Explorer não foi afetado.",
        "A IA teve um erro no servidor. Tente novamente mais tarde; seus arquivos continuam apenas no Explorer.",
    },

    BAD_RESPONSE = {
        "Recebi uma resposta do backend, mas ela veio em um formato que o menu não reconheceu.",
        "A API respondeu, porém não encontrei um texto de resposta válido.",
    },
}

local function pickAPIMessage(group)
    local list = API_ERROR_MESSAGES[group] or API_ERROR_MESSAGES.SERVER
    return list[math.random(1, #list)]
end

local function sendAI(question)
    if AIRequestBusy then
        return
    end

    question =
        tostring(question or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if question == "" then
        setStatus("Digite uma pergunta", COLORS.YELLOW)
        return
    end

    local acted, localReply = tryExplorerAction(question)

    if acted then
        addChatMessage("user", question)
        addChatMessage("assistant", localReply)
        return
    end

    if not API.request then
        addChatMessage("user", question)
        addChatMessage(
            "assistant",
            pickAPIMessage("NETWORK")
            .. "\n\nComandos locais como pesquisar, abrir, voltar, atualizar e ir para a raiz ainda funcionam."
        )
        return
    end

    addChatMessage("user", question)
    AIPrompt.Text = ""

    AIRequestBusy = true
    AIRequestGeneration += 1
    local generation = AIRequestGeneration

    AISend.Text = "…"
    AISend.Active = false

    local thinkingBubble =
        addChatMessage("assistant", "Analisando o contexto do Explorer...")

    local systemGuidance =
        "Você é a CAFEÍNA ASSISTENTE, integrada a um explorador de arquivos mobile em Lua. "
        .. "Sua função é tirar dúvidas sobre o Explorer e explicar arquivos abertos. "
        .. "Responda em português, de forma clara e prática. "
        .. "Não invente conteúdo que não esteja no contexto fornecido."

    local combinedMessage =
        systemGuidance
        .. "\n\n"
        .. buildExplorerSummary()
        .. "\n\n"
        .. buildSelectedFileContext()
        .. "\n\nCONVERSA RECENTE\n"
        .. buildConversationContext()
        .. "\n\nPERGUNTA ATUAL\n"
        .. question

    task.spawn(function()
        local body = HttpService:JSONEncode({
            message = combinedMessage,
            prompt = question,
            source = "cafeina-explorer-assistant",
            filename = SelectedPath and basename(SelectedPath) or nil,
            currentPath = CurrentPath,
            fileType = CurrentFileType,
            format = CurrentFormat,
        })

        local ok, response = safeCall(
            API.request,
            {
                Url = CONFIG.AI_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json",
                },
                Body = body,
            }
        )

        if GuiDestroyed
            or generation ~= AIRequestGeneration
        then
            return
        end

        AIRequestBusy = false
        AISend.Text = "➤"
        AISend.Active = true

        if thinkingBubble and thinkingBubble.Parent then
            thinkingBubble:Destroy()
        end

        if not ok then
            addChatMessage(
                "assistant",
                pickAPIMessage("NETWORK")
                .. "\n\nDetalhes: "
                .. tostring(response)
            )
            return
        end

        if type(response) == "table" then
            local code = tonumber(
                response.StatusCode
                or response.Status
                or response.status_code
                or response.status
            )

            if code and code >= 400 then
                local details =
                    tostring(extractAIResponse(response) or "Sem detalhes.")

                local lowerDetails = details:lower()
                local group = "SERVER"

                if code == 429 then
                    group = "RATE_LIMIT"
                elseif lowerDetails:find("quota", 1, true)
                    or lowerDetails:find("credit", 1, true)
                    or lowerDetails:find("billing", 1, true)
                    or lowerDetails:find("insufficient", 1, true)
                then
                    group = "CREDITS"
                elseif code >= 500 then
                    group = "SERVER"
                end

                addChatMessage(
                    "assistant",
                    pickAPIMessage(group)
                    .. "\n\nHTTP "
                    .. tostring(code)
                    .. " • "
                    .. details
                )
                return
            end
        end

        local answer = extractAIResponse(response)

        if not answer or answer == "" then
            addChatMessage(
                "assistant",
                pickAPIMessage("BAD_RESPONSE")
            )
            return
        end

        LastAIResponse = answer
        addChatMessage("assistant", answer)
    end)
end

AssistantLauncher.Activated:Connect(function()
    if AssistantLauncherWasDragged
        and AssistantLauncherWasDragged()
    then
        return
    end

    setAIVisible(true)
end)

AIBack.Activated:Connect(function()
    setAIVisible(false)
end)

AIClear.Activated:Connect(function()
    if AIRequestBusy then
        return
    end

    clearChatMessages()
    addWelcomeMessage()
end)

AISend.Activated:Connect(function()
    sendAI(AIPrompt.Text)
end)

--==============================================================--
-- COPY
--==============================================================--
--==============================================================--
-- COPY
--==============================================================--

local function copyText(text)
    if not API.setclipboard then
        setStatus(
            "Clipboard não disponível",
            COLORS.YELLOW
        )

        return
    end

    local ok = safeCall(
        API.setclipboard,
        tostring(text or "")
    )

    setStatus(
        ok and "Copiado" or "Erro ao copiar",
        ok and COLORS.GREEN or COLORS.RED
    )
end

Copy.Activated:Connect(function()
    if CurrentMode == "IMAGE" then
        copyText(SelectedPath or "")

    elseif CurrentMode == "TEXT" then
        copyText(SelectedText)

    elseif CurrentMode == "HEX" then
        copyText(SelectedHex)

    elseif CurrentMode == "INFO" then
        copyText(SelectedInfo)

    else
        copyText(SelectedPath or "")
    end
end)

--==============================================================--
-- SAVE IMAGE COPY
--==============================================================--

local function ensureDownloadFolder()
    if not API.makefolder then
        return true
    end

    pcall(function()
        API.makefolder(CONFIG.DOWNLOAD_FOLDER)
    end)

    return true
end

local function saveImageCopy()
    if not SelectedPath
        or not SelectedData
        or CurrentFileType ~= "IMAGE"
    then
        setStatus(
            "Nenhuma imagem selecionada",
            COLORS.YELLOW
        )
        return
    end

    if not API.writefile then
        setStatus(
            "writefile não disponível",
            COLORS.YELLOW
        )
        return
    end

    ensureDownloadFolder()

    local fileName = basename(SelectedPath)

    if fileName == ""
        or fileName == "/"
    then
        fileName = "image.png"
    end

    local destination =
        CONFIG.DOWNLOAD_FOLDER
        .. "/"
        .. fileName

    local ok, result = safeCall(
        API.writefile,
        destination,
        SelectedData
    )

    if ok then
        setStatus(
            "Imagem salva em "
            .. destination,
            COLORS.GREEN
        )
    else
        setStatus(
            "Erro ao salvar imagem: "
            .. tostring(result),
            COLORS.RED
        )
    end
end

Save.Activated:Connect(
    saveImageCopy
)

--==============================================================--
-- DRAG / CLAMP
--==============================================================--

local function clampFrame(frame)
    task.defer(function()
        if GuiDestroyed
            or not frame
            or not frame.Parent
        then
            return
        end

        local camera = workspace.CurrentCamera

        if not camera then
            return
        end

        local viewport = camera.ViewportSize
        local size = frame.AbsoluteSize
        local pos = frame.AbsolutePosition

        local x = math.clamp(
            pos.X,
            0,
            math.max(0, viewport.X - size.X)
        )

        local y = math.clamp(
            pos.Y,
            0,
            math.max(0, viewport.Y - size.Y)
        )

        frame.Position = UDim2.fromOffset(x, y)
    end)
end

local function makeDraggable(frame, handle, clampAfter)
    local dragging = false
    local moved = false
    local startInput = nil
    local startFrame = nil
    local activeInput = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1
        then
            return
        end

        dragging = true
        moved = false
        startInput = input.Position
        startFrame = frame.Position
        activeInput = input
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging
            or not startInput
            or not startFrame
        then
            return
        end

        if activeInput
            and activeInput.UserInputType == Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement
        then
            return
        end

        local delta = input.Position - startInput

        if delta.Magnitude > 7 then
            moved = true
        end

        frame.Position = UDim2.new(
            startFrame.X.Scale,
            startFrame.X.Offset + delta.X,
            startFrame.Y.Scale,
            startFrame.Y.Offset + delta.Y
        )
    end)

    UIS.InputEnded:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1
        then
            return
        end

        dragging = false
        activeInput = nil
        startInput = nil
        startFrame = nil

        if clampAfter then
            clampFrame(frame)
        end
    end)

    return function()
        return moved
    end
end

makeDraggable(
    Main,
    Top,
    true
)

local AssistantLauncherWasDragged =
    makeDraggable(
        AssistantLauncher,
        AssistantLauncher,
        true
    )

local AIPanelWasDragged =
    makeDraggable(
        AIPanel,
        AIHeader,
        true
    )

--==============================================================--
-- MINIMIZED ICON
--==============================================================--

local Floating = Instance.new("TextButton")

Floating.Size = UDim2.fromOffset(56, 56)
Floating.Position = UDim2.new(0.5, -28, 0.5, -28)

Floating.BackgroundColor3 = COLORS.TOP
Floating.BorderSizePixel = 0

Floating.Text = "☕"
Floating.TextSize = 23
Floating.TextColor3 = COLORS.RED
Floating.Font = Enum.Font.GothamBold

Floating.Visible = false

corner(Floating, 16)
stroke(Floating, COLORS.RED_DARK, 2)

Floating.Parent = Gui

local FloatingWasDragged = makeDraggable(
    Floating,
    Floating,
    true
)

Minimize.Activated:Connect(function()
    Main.Visible = false
    Floating.Visible = true
end)

Floating.Activated:Connect(function()
    if FloatingWasDragged() then
        return
    end

    Floating.Visible = false
    Main.Visible = true

    clampFrame(Main)
end)

Close.Activated:Connect(function()
    GuiDestroyed = true
    AIRequestGeneration += 1
    AIRequestBusy = false
    AIRequestGeneration += 1
    AIRequestBusy = false
    clearMedia()

    if Gui then
        Gui:Destroy()
    end
end)

--==============================================================--
-- START
--==============================================================--

if not FileSystemAvailable then
    List.Visible = false
    Viewer.Visible = true

    ViewerName.Text = "CAFEÍNA V3"
    ViewerMeta.Text = "FILESYSTEM INDISPONÍVEL"

    ViewerText.Text =
[[
O ambiente precisa oferecer:

listfiles
isfolder
readfile

APIs opcionais:

setclipboard
writefile
makefolder
getcustomasset
getsynasset

Sem listfiles/isfolder/readfile,
o explorador não consegue acessar
os arquivos locais.
]]
    Copy.Visible = false
    Save.Visible = false

    setStatus(
        "Filesystem incompatível",
        COLORS.RED
    )

    return
end

local detectedRoot = detectRoot()

if detectedRoot == nil then
    List.Visible = false
    Viewer.Visible = true

    ViewerName.Text = "CAFEÍNA V3"
    ViewerMeta.Text = "RAIZ NÃO ENCONTRADA"

    ViewerText.Text =
[[
As APIs de filesystem existem,
mas nenhuma raiz acessível foi
detectada automaticamente.

Tentativas:

""
"."
"workspace"
"Workspace"
]]

    setStatus(
        "Raiz não encontrada",
        COLORS.RED
    )

    return
end

RootPath = normalizePath(detectedRoot)
CurrentPath = RootPath

openDirectory(
    RootPath,
    false
)

--==============================================================--
-- END
--==============================================================--
