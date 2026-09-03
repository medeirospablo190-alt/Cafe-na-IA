import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import fs from "fs/promises";
import os from "os";
import path from "path";
import { spawn } from "child_process";

function verifier(password) {
  const N = 16_384;
  const r = 8;
  const p = 1;
  const salt = crypto.randomBytes(24);
  const derived = crypto.scryptSync(password, salt, 32, { N, r, p, maxmem: 64 * 1024 * 1024 });
  return `scrypt$${N}$${r}$${p}$${salt.toString("base64url")}$${derived.toString("base64url")}`;
}

async function waitFor(url) {
  let lastError;
  for (let i = 0; i < 60; i += 1) {
    try {
      const response = await fetch(url, { cache: "no-store" });
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw lastError || new Error("Servidor não iniciou a tempo.");
}

test("portal autoriza somente o artefato correto e consome token uma vez", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "grupo-lua-portal-"));
  const apkName = "app1-test.apk";
  const apkBytes = Buffer.from("GRUPO LUA TEST APK\n", "utf8");
  await fs.writeFile(path.join(dir, apkName), apkBytes);

  const password = "ADM-TESTE-SEGREDO-160";
  const port = 32_000 + crypto.randomInt(2_000);
  const child = spawn(process.execPath, ["server.js"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: "test",
      PORT: String(port),
      DOWNLOAD_DIR: dir,
      DOWNLOAD_APP1_ANDROID_HASH: verifier(password),
      DOWNLOAD_APP1_ANDROID_FILE: apkName,
      DOWNLOAD_APP1_ANDROID_VERSION: "test-1"
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
  t.after(async () => {
    child.kill("SIGTERM");
    await fs.rm(dir, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${port}`;
  await waitFor(`${base}/api/health`);

  const catalog = await fetch(`${base}/api/downloads/catalog`, { cache: "no-store" }).then((r) => r.json());
  const app1Android = catalog.items.find((item) => item.id === "APP1_ANDROID");
  const keymasterAndroid = catalog.items.find((item) => item.id === "KEYMASTER_ANDROID");
  assert.equal(app1Android.available, true);
  assert.equal(keymasterAndroid.available, false);

  const invalid = await fetch(`${base}/api/downloads/APP1_ANDROID/authorize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ password: "errada" })
  });
  assert.equal(invalid.status, 401);

  const valid = await fetch(`${base}/api/downloads/APP1_ANDROID/authorize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ password })
  });
  assert.equal(valid.status, 200, stderr);
  const grant = await valid.json();
  assert.equal(grant.oneTime, true);
  assert.match(grant.downloadUrl, /^\/api\/downloads\/t\//);

  const first = await fetch(`${base}${grant.downloadUrl}`);
  assert.equal(first.status, 200, stderr);
  assert.deepEqual(Buffer.from(await first.arrayBuffer()), apkBytes);
  assert.match(first.headers.get("content-disposition") || "", /attachment/i);

  const second = await fetch(`${base}${grant.downloadUrl}`);
  assert.ok([404, 410].includes(second.status));

  const wrongArtifact = await fetch(`${base}/api/downloads/KEYMASTER_ANDROID/authorize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ password })
  });
  assert.equal(wrongArtifact.status, 503);
});
