import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import fs from "fs/promises";
import http from "http";
import os from "os";
import path from "path";
import express from "express";

function randomPort() {
  return 38_000 + crypto.randomInt(2_000);
}

function sha(text) {
  return crypto.createHash("sha1").update(text).digest("hex");
}

async function startFakeGitHub(port) {
  const files = new Map();
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    const prefix = "/repos/test/repo/contents/";
    if (!url.pathname.startsWith(prefix)) {
      res.writeHead(404).end();
      return;
    }
    const repoPath = decodeURIComponent(url.pathname.slice(prefix.length));
    const current = files.get(repoPath);

    if (req.method === "GET") {
      if (!current) {
        res.writeHead(404, { "content-type": "application/json" });
        res.end(JSON.stringify({ message: "Not Found" }));
        return;
      }
      const accept = String(req.headers.accept || "");
      if (accept.includes("application/vnd.github.raw+json")) {
        res.writeHead(200, { "content-type": "application/octet-stream" });
        res.end(current.text);
        return;
      }
      const large = Buffer.byteLength(current.text) > 1024 * 1024;
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({
        sha: current.sha,
        content: large ? "" : Buffer.from(current.text).toString("base64"),
        encoding: large ? "none" : "base64",
      }));
      return;
    }

    if (req.method === "PUT") {
      let raw = "";
      for await (const chunk of req) raw += chunk;
      const body = JSON.parse(raw || "{}");
      if (current && body.sha !== current.sha) {
        res.writeHead(409, { "content-type": "application/json" });
        res.end(JSON.stringify({ message: "sha mismatch" }));
        return;
      }
      const text = Buffer.from(String(body.content || ""), "base64").toString("utf8");
      const next = { text, sha: sha(text) };
      files.set(repoPath, next);
      res.writeHead(current ? 200 : 201, { "content-type": "application/json" });
      res.end(JSON.stringify({ content: { sha: next.sha } }));
      return;
    }

    res.writeHead(405).end();
  });
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  return { server, files };
}

async function listen(app, port) {
  return new Promise((resolve) => {
    const server = app.listen(port, "127.0.0.1", () => resolve(server));
  });
}

test("Trace V3 is idempotent, rejects conflicts, and reads GitHub files above 1 MB as raw", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "cafeina-trace-v3-"));
  const githubPort = randomPort();
  const apiPort = randomPort();
  const fake = await startFakeGitHub(githubPort);

  process.env.AVATAR_DUMP_GITHUB_TOKEN = "test-token";
  process.env.AVATAR_DUMP_GITHUB_REPO = "test/repo";
  process.env.AVATAR_DUMP_GITHUB_BRANCH = "main";
  process.env.INVENTORY_TRACE_V3_GITHUB_API_BASE = `http://127.0.0.1:${githubPort}`;
  process.env.INVENTORY_TRACE_V3_DIR = dir;
  process.env.INVENTORY_TRACE_V3_GITHUB_PATH = "inventory-traces-v3";
  process.env.INVENTORY_TRACE_V3_BODY_LIMIT = "3mb";

  const { installCollectorV3Routes } = await import(`../collector-v3-routes.js?test=${Date.now()}`);
  const app = express();
  app.set("trust proxy", 1);
  installCollectorV3Routes(app);
  const server = await listen(app, apiPort);

  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await new Promise((resolve) => fake.server.close(resolve));
    await fs.rm(dir, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${apiPort}/api/inventory-trace-v3`;
  const health = await fetch(`${base}/health`).then((r) => r.json());
  assert.equal(health.ok, true);
  assert.equal(health.githubMirrorConfigured, true);
  assert.equal(health.hardSessionBytes, 150 * 1024 * 1024);
  assert.equal(health.maxBatches, 260);
  assert.equal(health.profileCaps.semanticHashes, 12000);
  assert.equal(health.profileCaps.investigationKnowledge, 800);

  const common = {
    schemaVersion: 3,
    collector: { version: "CAFEINA_UNIVERSAL_GAME_TRACE_V3_2_0" },
    userId: "765329164",
    username: "tester",
    capturedAt: "2026-09-19T04:00:00.000Z",
    gameId: 10563114921,
    placeId: 107778070777162,
    placeVersion: 445,
    runId: "11111111-2222-3333-4444-555555555555",
  };

  const post = (body) => fetch(`${base}/batch`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  const firstBody = {
    ...common,
    batchIndex: 1,
    batchKind: "data",
    payloadBytes: 50,
    records: [{ kind: "session_started", value: 1 }],
    remotes: [],
  };
  assert.equal((await post(firstBody)).status, 201);
  assert.equal((await post(firstBody)).status, 201, "retry idêntico deve ser idempotente");

  const conflict = await post({ ...firstBody, records: [{ kind: "session_started", value: 2 }] });
  assert.equal(conflict.status, 409, "mesmo índice com conteúdo diferente deve ser rejeitado");
  const conflictBody = await conflict.json();
  assert.equal(conflictBody.runId, common.runId);
  assert.equal(conflictBody.batchIndex, 1);
  assert.equal(conflictBody.existing.batchIndex, 1);
  assert.equal(conflictBody.existing.batchKind, "data");
  assert.equal(conflictBody.existing.payloadBytes, 50);
  assert.equal(conflictBody.existing.recordCount, 1);
  assert.equal(conflictBody.existing.remoteCount, 0);
  assert.match(conflictBody.existing.recordsHash, /^[a-f0-9]{12}$/);
  assert.match(conflictBody.existing.remotesHash, /^[a-f0-9]{12}$/);

  const largeRecords = Array.from({ length: 1050 }, (_, i) => ({
    kind: "remote_inbound",
    i,
    payload: "x".repeat(1120),
  }));
  const largeBody = {
    ...common,
    batchIndex: 2,
    batchKind: "data",
    payloadBytes: 1_300_000,
    records: largeRecords,
    remotes: [],
  };
  assert.equal((await post(largeBody)).status, 201);

  const largeConflictRecords = largeRecords.slice();
  largeConflictRecords[0] = { ...largeConflictRecords[0], payload: "y".repeat(1120) };
  const largeConflict = await post({ ...largeBody, records: largeConflictRecords });
  assert.equal(
    largeConflict.status,
    409,
    "arquivo >1 MB deve ser lido via raw para detectar conflito sem sobrescrever",
  );
  const largeConflictBody = await largeConflict.json();
  assert.equal(largeConflictBody.existing.batchIndex, 2);
  assert.equal(largeConflictBody.existing.payloadBytes, 1_300_000);
  assert.equal(largeConflictBody.existing.recordCount, 1050);
  assert.equal(largeConflictBody.existing.remoteCount, 0);
  assert.match(largeConflictBody.existing.recordsHash, /^[a-f0-9]{12}$/);

  const manifest = {
    ...common,
    batchIndex: 3,
    batchTotal: 3,
    batchKind: "manifest",
    payloadBytes: 0,
    records: [],
    remotes: [],
    manifest: {
      profileDelta: {
        knownLowValueHashes: ["abcdef123456"],
        knownShapeHashes: ["abcdef654321"],
        knownSemanticHashes: ["fedcba123456"],
        knownRemoteHashes: ["123456abcdef"],
        investigationKnowledge: [{
          key: "aa11bb22cc33",
          observations: 2,
          activeTests: 1,
          completed: 1,
          passiveOnly: 0,
          cancelled: 0,
          status: "tested",
          lastReason: "active_test_complete",
          lastImpact: 42.35,
          lastOutcome: "bb22cc33dd44",
        }],
        frontier: ["Workspace.Test"],
      },
      strategyDelta: {
        remote_inbound: { observed: 100, accepted: 20, novel: 5, suppressed: 80, sampleN: 2 },
      },
      coverage: { staticComplete: true, newRemotes: 1 },
    },
  };
  assert.equal((await post(manifest)).status, 201);
  assert.equal((await post(manifest)).status, 201, "manifesto repetido não deve reaplicar perfil");

  const profileResponse = await fetch(`${base}/profile/${common.gameId}`);
  assert.equal(profileResponse.status, 200);
  const profile = (await profileResponse.json()).profile;
  assert.equal(profile.revision, 1);
  assert.equal(profile.sessions, 1);
  assert.deepEqual(profile.knownRemoteHashes, ["123456abcdef"]);
  assert.deepEqual(profile.knownSemanticHashes, ["fedcba123456"]);
  assert.equal(profile.investigationKnowledge.length, 1);
  assert.deepEqual(profile.investigationKnowledge[0], {
    key: "aa11bb22cc33",
    observations: 2,
    activeTests: 1,
    completed: 1,
    passiveOnly: 0,
    cancelled: 0,
    status: "tested",
    lastReason: "active_test_complete",
    lastImpact: 42.35,
    lastOutcome: "bb22cc33dd44",
  });
  assert.equal(profile.strategy.remote_inbound.sampleN, 2);

  const batch2Path = `inventory-traces-v3/${common.gameId}/${common.placeId}/${common.runId}/0002-data.json`;
  assert.ok(Buffer.byteLength(fake.files.get(batch2Path).text) > 1024 * 1024);
});