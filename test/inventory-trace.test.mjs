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

test("inventory trace recebe, salva latest e retorna recibo", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "grupo-lua-inventory-trace-"));
  const port = 41_000 + crypto.randomInt(1_000);
  const internalPort = 43_000 + crypto.randomInt(1_000);

  const child = spawn(process.execPath, ["avatar-gateway.js"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: "test",
      PORT: String(port),
      AVATAR_GATEWAY_INTERNAL_PORT: String(internalPort),
      DOWNLOAD_DIR: dir,
      INVENTORY_TRACE_DIR: path.join(dir, "inventory-traces"),
      AVATAR_DUMP_GITHUB_TOKEN: "",
      AVATAR_DUMP_ALLOWED_USER_IDS: "765329164"
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
  await waitFor(`${base}/api/inventory-trace/health`);

  const payload = {
    schemaVersion: 1,
    userId: "765329164",
    username: "capuccino40",
    capturedAt: "2026-09-07T12:00:00.000Z",
    placeId: 138686218420016,
    gameId: 10532995815,
    runId: "inventory-trace-test-run",
    trace: {
      runId: "inventory-trace-test-run",
      version: "TEST",
      records: [
        { seq: 1, kind: "prompt_triggered", prompt: "Workspace.SpawnedGems.Test.Mesh_0.Pickup" },
        { seq: 2, kind: "tool_added", tool: { name: "1.0 kg", attributes: { BagId: 999 } } }
      ],
      remotes: [
        { path: "ReplicatedStorage.GemSignals.DropCrystal", class: "RemoteEvent", outgoing: 1 }
      ],
      diagnostics: {
        errors: [],
        counters: { records: 2 }
      }
    }
  };

  const upload = await fetch(`${base}/api/inventory-trace`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });

  assert.equal(upload.status, 201, stderr);
  const receipt = await upload.json();
  assert.equal(receipt.ok, true);
  assert.equal(receipt.placeId, 138686218420016);
  assert.equal(receipt.runId, "inventory-trace-test-run");
  assert.equal(receipt.github?.configured, false);
  assert.match(receipt.latestUrl, /138686218420016\/latest$/);

  const latestResponse = await fetch(`${base}${receipt.latestUrl}`, { cache: "no-store" });
  assert.equal(latestResponse.status, 200, stderr);
  const latest = await latestResponse.json();
  assert.equal(latest.placeId, 138686218420016);
  assert.equal(latest.runId, "inventory-trace-test-run");
  assert.equal(latest.trace.records.length, 2);
  assert.equal(latest.trace.records[1].tool.attributes.BagId, 999);
  assert.ok(latest.serverReceivedAt);

  const status = await fetch(`${base}/api/inventory-trace/138686218420016/status`, { cache: "no-store" }).then((r) => r.json());
  assert.equal(status.ok, true);
  assert.equal(status.local, true);
  assert.equal(status.githubMirrorConfigured, false);
});
