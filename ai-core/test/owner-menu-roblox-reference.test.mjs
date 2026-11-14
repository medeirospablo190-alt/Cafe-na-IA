import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const script=readFileSync(
  new URL("../roblox-reference/OwnerMenuBridge.server.luau",import.meta.url),"utf8"
);
test("Roblox server bridge is owner-scoped, inactive and has only typed mission actions",()=>{
  assert.match(script,/local ENABLED = false/);
  assert.match(script,/local OWNER_USER_IDS = \{\}/);
  assert.match(script,/OWNER_USER_IDS\[player\.UserId\] ~= true/);
  assert.match(script,/RemoteFunction/);
  assert.match(script,/OnServerInvoke/);
  assert.match(script,/ALLOWED_OPERATIONS\[operation\]/);
  for(const op of ["POLL","ACK","DECLINE","NO_EXECUTION"])
    assert.match(script,new RegExp(op+" = true"));
  assert.match(script,/game\.JobId/);
  assert.match(script,/HttpService:GetSecret\("CAFEINA_ROBLOX_SERVER_KEY"\)/);
  assert.match(script,/HttpService:RequestAsync/);
  assert.match(script,/https:\/\//);
  assert.match(script,/RequestAsync\(\{/);
  assert.match(script,/busy\[player\.UserId\]/);
  assert.match(script,/nextRequest\[player\.UserId\]/);
  assert.doesNotMatch(script,/loadstring\s*\(|require\s*\(|FireServer\s*\(/);
  assert.doesNotMatch(script,/GITHUB_TOKEN|github_pat_|api\.github\.com/);
  assert.doesNotMatch(script,/game:GetDescendants\(\)|getgc\s*\(|hookmetamethod\s*\(/);
});
