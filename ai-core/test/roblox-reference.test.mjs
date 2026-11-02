import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const file=new URL("../roblox-reference/ServerBridgeReference.server.luau",import.meta.url);
test("Roblox example is disabled and uses server secret, never GitHub",()=>{
  const s=readFileSync(file,"utf8");
  assert.match(s,/local ENABLED = false/);
  assert.match(s,/ServerScriptService/);
  assert.match(s,/HttpService:GetSecret\("CAFEINA_BRIDGE_SERVER_KEY"\)/);
  assert.match(s,/HttpService:RequestAsync/);
  assert.match(s,/game\.JobId/);
  assert.match(s,/CAFEINA_ROBLOX_SERVER_CHECKIN_V1/);
  assert.match(s,/https:\/\//);
  assert.doesNotMatch(s,/loadstring\s*\(/);
  assert.doesNotMatch(s,/getfenv\s*\(/);
  assert.doesNotMatch(s,/github\.com|api\.github\.com/i);
});
