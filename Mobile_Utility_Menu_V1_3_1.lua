-- Mobile Utility Menu V1.3.1 loader
-- Hotfix de compatibilidade da V1.3 Compact + Animated Clones.
-- Mantém a V1.2 original e o backup intactos.

local url = "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/Mobile_Utility_Menu_V1_3.lua"

local ok, source = pcall(function()
    return game:HttpGet(url)
end)

if not ok or type(source) ~= "string" or source == "" then
    error("Falha ao carregar Mobile Utility Menu V1.3")
end

-- Compatibilidade: HumanoidStateType não possui SwimmingPhysics.
source = source:gsub(
    "%s*or state == Enum%.HumanoidStateType%.SwimmingPhysics",
    ""
)

local chunk, compileError = loadstring(source)
if not chunk then
    error("Falha ao compilar Mobile Utility Menu V1.3.1: " .. tostring(compileError))
end

return chunk()
