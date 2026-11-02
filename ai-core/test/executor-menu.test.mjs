import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const script=readFileSync(
  new URL("../roblox-reference/ExecutorMenu.client.luau",import.meta.url),
  "utf8"
);

test("executor menu is a self-contained, client-only mobile UI",()=>{
  assert.match(script,/Players\.LocalPlayer/);
  assert.match(script,/WaitForChild\("PlayerGui",\s*10\)/);
  assert.match(script,/Instance\.new\(/);
  assert.match(script,/ScreenGui/);
  assert.match(script,/ResetOnSpawn\s*=\s*false/);
  assert.match(script,/FindFirstChild\(GUI_NAME\)/);
  assert.match(script,/gui\.Destroying:Connect/);
  assert.match(script,/UserInputType\.Touch/);
  assert.match(script,/\.Activated:Connect/);
  assert.match(script,/Missões/);
  assert.match(script,/Permissões/);
  assert.match(script,/Diagnóstico/);
  assert.match(script,/activeTab/);
  assert.match(script,/bubble\.Visible\s*=\s*true/);
  assert.match(script,/window\.Visible\s*=\s*true/);
});

test("executor script contains no network, secrets, code loader, or Roblox action APIs",()=>{
  const forbidden=[
    /\b(?:loadstring|require|getgenv|getrenv|setclipboard|writefile|readfile)\s*\(/,
    /\b(?:HttpService|HttpGet|RequestAsync|syn\.request)\s*[:.(]/,
    /\b(?:FireServer|InvokeServer|FireAllClients|Kick|Teleport)\s*\(/,
    /\b(?:gethui|getgc|hookmetamethod|setreadonly|getrawmetatable)\s*\(/,
    /\b(?:RemoteEvent|RemoteFunction|TeleportService|DataStoreService)\b/,
    /(?:https?:\/\/|Bearer\s+|GITHUB_TOKEN|secret[_-]?key|api\.github\.com)/i
  ];
  for(const pattern of forbidden){
    assert.doesNotMatch(script,pattern,
      "Forbidden potentially privileged API in executor demo: "+pattern);
  }
  assert.match(script,/NETWORK_DISABLED/);
  assert.match(script,/AÇÕES NO JOGO:\s*0/);
  assert.match(script,/Executions Roblox: 0|Execuções Roblox: 0/);
});

test("synthetic reviewer has a closed, one-way decision and expiration",()=>{
  assert.match(script,/status\s*=\s*"PENDING_REVIEW"/);
  assert.match(script,/os\.clock\(\)\s*\+\s*120/);
  assert.match(script,/request\.status\s*=\s*"EXPIRED"/);
  assert.match(script,/decision\s*~=\s*"DENIED"\s+and\s+decision\s*~=\s*"SIMULATION_ALLOWED"/);
  assert.match(script,/request\.status\s*=\s*"REVIEWED"/);
  assert.match(script,/if request\.status\s*==\s*"PENDING_REVIEW" then/);
  assert.match(script,/Ações reais habilitadas:\s*NÃO/);
  assert.match(script,/PRÉVIA FICTÍCIA|prévia FICTÍCIA/i);
});
