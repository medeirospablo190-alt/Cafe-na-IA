-- Mobile Utility Menu V1.2 BACKUP loader
-- Backup do ponto de entrada original. Os arquivos-fonte V1.2 permanecem
-- preservados em mobile-menu-v1_2/part01.txt ... part08.txt.

local base = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/mobile-menu-v1_2/"
local source = {}

for i = 1, 8 do
    local url = base .. string.format("part%02d.txt", i)
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok or type(body) ~= "string" or body == "" then
        error("Falha ao carregar parte " .. tostring(i) .. " do Mobile Utility Menu V1.2 BACKUP")
    end

    source[#source + 1] = body
end

local chunk, compileError = loadstring(table.concat(source, ""))
if not chunk then
    error("Falha ao compilar Mobile Utility Menu V1.2 BACKUP: " .. tostring(compileError))
end

return chunk()
