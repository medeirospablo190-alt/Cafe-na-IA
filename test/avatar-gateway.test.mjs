import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import fs from "fs/promises";
import os from "os";
import path from "path";
import { spawn } from "child_process";

async function waitFor(url) {
  let lastError;
  for (let i = 0; i < 80; i += 1) {
    try {
      const response = await fetch(url, { cache: "no-store" });
      if (response.ok) return response;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw lastError || new Error("Gateway não iniciou a tempo.");
}

test("avatar gateway salva latest e preserva portal por proxy", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "grupo-lua-avatar-gateway-"));
  const port = 35_000 + crypto.randomInt(1_000);
  const internalPort = 37_000 + crypto.randomInt(1_000);

  const child = spawn(process.execPath, ["avatar-gateway.js"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: "test",
      PORT: String(port),
      AVATAR_GATEWAY_INTERNAL_PORT: String(internalPort),
      DOWNLOAD_DIR: dir,
      AVATAR_DUMP_ALLOWED_USER_IDS: "765329164",
      AVATAR_DUMP_GITHUB_TOKEN: "",
      AVATAR_DUMP_KEY: ""
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });

  t.after(async () => {
    child.kill("SIGTERM");
    await new Promise((resolve) => setTimeout(resolve, 150));
    await fs.rm(dir, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${port}`;
  const health = await waitFor(`${base}/api/health`);
  assert.equal(health.status, 200, stderr);

  const payload = {
    schemaVersion: 1,
    userId: "765329164",
    username: "Capuccino40",
    capturedAt: "2026-09-06T22:00:00.000Z",
    placeId: 123,
    gameId: 456,
    avatar: {
      rigType: "Enum.HumanoidRigType.R15",
      objectCount: 2,
      uniqueAssetReferences: ["rbxassetid://123"],
      objects: [
        { name: "Head", className: "MeshPart", meshId: "rbxassetid://1", textureId: "rbxassetid://2" }
      ]
    }
  };

  const upload = await fetch(`${base}/api/avatar-dump`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  assert.equal(upload.status, 201, stderr);
  const receipt = await upload.json();
  assert.equal(receipt.ok, true);
  assert.equal(receipt.userId, "765329164");
  assert.match(receipt.latestUrl, /765329164\/latest$/);

  const latestResponse = await fetch(`${base}${receipt.latestUrl}`, { cache: "no-store" });
  assert.equal(latestResponse.status, 200, stderr);
  const latest = await latestResponse.json();
  assert.equal(latest.userId, "765329164");
  assert.equal(latest.username, "Capuccino40");
  assert.equal(latest.avatar.objectCount, 2);
  assert.equal(latest.avatar.objects[0].meshId, "rbxassetid://1");

  const status = await fetch(`${base}/api/avatar-dump/765329164/status`, { cache: "no-store" }).then((r) => r.json());
  assert.equal(status.ok, true);
  assert.equal(status.local, true);
});
