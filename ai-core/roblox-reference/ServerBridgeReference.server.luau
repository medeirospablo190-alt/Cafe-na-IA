--[[
  CAFEINA AI / Roblox server-only reference (DO NOT DEPLOY UNREVIEWED).
  Place this Script under ServerScriptService in an experience you own.
  Entire integration is DISABLED by default.

  Requires explicit owner configuration in Experience Settings:
  - Allow HTTP Requests
  - A secret named CAFEINA_BRIDGE_SERVER_KEY in Roblox Secret Store
  - HTTPS endpoint controlled by the experience owner
  - Trusted gateway-side registration of this server's game.JobId -> runId

  No GitHub token, admin key, arbitrary Luau or client-supplied commands.
]]
local HttpService = game:GetService("HttpService")

local ENABLED = false -- DO NOT ENABLE until gateway verification is deployed.
local GATEWAY_URL = "" -- Must be owner-approved HTTPS; no default service URL.
local SERVER_MISSION_ID = "" -- Registered on trusted server, never from a LocalScript.

local function validMissionId(value)
  return type(value) == "string"
    and string.match(value, "^mission%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function buildServerCheckin()
  assert(game.JobId ~= "", "Only a live server with an assigned JobId can check in.")
  assert(validMissionId(SERVER_MISSION_ID), "Missing server-provisioned mission ID.")
  return {
    schemaVersion = 1,
    aud = "CAFEINA_ROBLOX_SERVER_CHECKIN_V1",
    gameId = tostring(game.GameId),
    placeId = tostring(game.PlaceId),
    jobId = tostring(game.JobId),
    missionId = SERVER_MISSION_ID,
    issuedAtMs = DateTime.now().UnixTimestampMillis,
    nonce = HttpService:GenerateGUID(false),
  }
end

if ENABLED then
  assert(string.sub(GATEWAY_URL, 1, 8) == "https://", "HTTPS only.")
  assert(not string.find(GATEWAY_URL, "@", 1, true), "No URL credentials.")
  local ok, result = pcall(function()
    local credentials = HttpService:GetSecret("CAFEINA_BRIDGE_SERVER_KEY")
    local checkin = buildServerCheckin()
    return HttpService:RequestAsync({
      Url = GATEWAY_URL .. "/v1/server/checkin",
      Method = "POST",
      Headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = credentials,
      },
      Body = HttpService:JSONEncode(checkin),
      Timeout = 10,
    })
  end)
  if not ok then
    warn("CAFEINA server bridge request failed; no mission executed.")
  elseif not result.Success then
    warn("CAFEINA server bridge rejected check-in; no mission executed.")
  end
  -- Deliberately does NOT forward response tokens to LocalScripts or run tools.
end
