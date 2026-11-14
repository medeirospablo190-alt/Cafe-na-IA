--[[
  CAFEINA AI / authorised Roblox experience server bridge (v0.1).
  Install ONLY in ServerScriptService of a game you own or may administer.
  INACTIVE until ENABLED, HTTPS gateway, owner allow-list and session values
  are configured. No arbitrary actions, remotes discovery or Lua execution.
  GitHub secrets and credentials NEVER reach client/executor.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ENABLED = false
local GATEWAY_URL = "" -- e.g. https://your-owned-gateway.example
local RUN_ID = "" -- pre-authorized session in gateway configuration
local MISSION_ID = "" -- exact mission already queued on GitHub
local OWNER_USER_IDS = {} -- [123456789] = true (set your own Roblox UserId)

local REMOTE_NAME = "CAFEINA_MENU_REMOTE"
local ALLOWED_OPERATIONS = {
    POLL = true, ACK = true, DECLINE = true, NO_EXECUTION = true,
}
local nextRequest = {}
local busy = {}
local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote then
    assert(remote:IsA("RemoteFunction"), "CAFEINA: conflicting remote.")
else
    remote = Instance.new("RemoteFunction")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
end

local function configured()
    return ENABLED
        and type(GATEWAY_URL) == "string"
        and string.match(GATEWAY_URL, "^https://[%w%.%-]+[:%d]*$") ~= nil
        and type(RUN_ID) == "string"
        and string.match(RUN_ID, "^[%w_%-]+$") ~= nil
        and #RUN_ID >= 6 and #RUN_ID <= 128
        and type(MISSION_ID) == "string"
        and string.match(MISSION_ID, "^mission%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
        and game.JobId ~= ""
end

local function safeResponse(result)
    if type(result) ~= "table" or type(result.ok) ~= "boolean" then
        return {ok = false, error = "BAD_GATEWAY_REPLY"}
    end
    if not result.ok then
        return {ok = false, error = "GATEWAY_REJECTED"}
    end
    if type(result.status) ~= "string"
        or not ({
            DELIVERED = true, ACKNOWLEDGED = true,
            CLOSED_NO_EXECUTION = true
        })[result.status] then
        return {ok = false, error = "BAD_GATEWAY_STATUS"}
    end
    local reply = {
        ok = true, status = result.status,
        hasProposal = result.hasProposal == true,
        approved = false, executed = false,
    }
    if reply.hasProposal and type(result.proposal) == "table" then
        local p = result.proposal
        if type(p.missionId) == "string" and p.missionId == MISSION_ID
            and (p.toolId == "watch_state" or p.toolId == "observe_gui")
            and type(p.durationSeconds) == "number"
            and p.durationSeconds == 10
            and type(p.expiresAtMs) == "number"
            and p.approved == false and p.executable == false then
            reply.proposal = {
                missionId = p.missionId, toolId = p.toolId,
                durationSeconds = p.durationSeconds, expiresAtMs = p.expiresAtMs,
            }
        else
            return {ok = false, error = "BAD_PROPOSAL"}
        end
    end
    return reply
end

remote.OnServerInvoke = function(player, operation, payload)
    if not player or OWNER_USER_IDS[player.UserId] ~= true then
        return {ok = false, error = "NOT_AUTHORIZED"}
    end
    if operation == "STATUS" and payload == nil then
        return {ok = true, status = configured() and "SERVER_READY" or "NOT_CONFIGURED"}
    end
    if payload ~= nil or not ALLOWED_OPERATIONS[operation] then
        return {ok = false, error = "INVALID_OPERATION"}
    end
    if not configured() then
        return {ok = false, error = "NOT_CONFIGURED"}
    end
    if busy[player.UserId] then
        return {ok = false, error = "BUSY"}
    end
    local now = os.clock()
    if now < (nextRequest[player.UserId] or 0) then
        return {ok = false, error = "RATE_LIMIT"}
    end
    nextRequest[player.UserId] = now + 2
    busy[player.UserId] = true
    local ok, result = pcall(function()
        local secret = HttpService:GetSecret("CAFEINA_ROBLOX_SERVER_KEY")
        local requestBody = HttpService:JSONEncode({
            schemaVersion = 1,
            operation = operation,
            gameId = tostring(game.GameId),
            placeId = tostring(game.PlaceId),
            runId = RUN_ID,
            missionId = MISSION_ID,
            jobId = tostring(game.JobId),
        })
        local response = HttpService:RequestAsync({
            Url = GATEWAY_URL .. "/v1/roblox/menu",
            Method = "POST",
            Headers = {
                ["content-type"] = "application/json",
                ["x-cafeina-server-key"] = secret,
            },
            Body = requestBody,
        })
        if not response.Success or type(response.Body) ~= "string"
            or #response.Body > 2048 then
            return {ok = false, error = "GATEWAY_UNAVAILABLE"}
        end
        return safeResponse(HttpService:JSONDecode(response.Body))
    end)
    busy[player.UserId] = nil
    if not ok then
        warn("CAFEINA bridge: request failed without exposing credentials.")
        return {ok = false, error = "SERVER_REQUEST_FAILED"}
    end
    return result
end

Players.PlayerRemoving:Connect(function(player)
    nextRequest[player.UserId] = nil
    busy[player.UserId] = nil
end)

print("[CAFEINA] Server menu bridge mounted; configured:", configured())
