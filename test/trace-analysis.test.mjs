import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { analyzeTracePath } from "../tools/trace-analysis/analyze.mjs";

test("analyzes V3 batches into aggregate groups without copying raw records", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "cafeina-analysis-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  await fs.writeFile(path.join(dir, "0001-data.json"), JSON.stringify({
    schemaVersion: 3,
    type: "cafeina_universal_trace_v3_batch",
    gameId: 123,
    placeId: 456,
    runId: "run-12345678",
    capturedAt: "2026-10-15T00:00:00.000Z",
    records: [
      { kind: "remote_outbound", sig: "abcdef123456", quality: 80, method: "FireServer", remote: { path: "ReplicatedStorage.Test" }, unix: 100, privateValue: "DO_NOT_COPY_RAW_VALUE" },
      { kind: "remote_outbound", sig: "abcdef123456", quality: 100, method: "FireServer", remote: { path: "ReplicatedStorage.Test" }, unix: 101 },
      { kind: "workspace_added", object: { path: "Workspace.Item" } },
    ],
    remotes: [{ kind: "remote_inbound", path: "ReplicatedStorage.Events" }],
    stats: { valueWatchers: 10 },
  }));
  await fs.writeFile(path.join(dir, "broken.json"), "{not json");
  const report = await analyzeTracePath(dir);
  assert.equal(report.inputFiles, 2);
  assert.equal(report.skippedFiles, 1);
  assert.equal(report.totalRecords, 3);
  assert.equal(report.totalRemotes, 1);
  assert.equal(Object.keys(report.sessions).length, 1);
  const group = Object.values(report.groups).find((item) => item.kind === "remote_outbound");
  assert.ok(group);
  assert.equal(group.samples, 2);
  assert.equal(group.signatures, 1);
  assert.equal(group.meanQuality, 90);
  assert.equal(group.confidence, "low");
  assert.ok(report.fields["record.remote.path"]);
  const output = JSON.stringify(report);
  assert.equal(output.includes("DO_NOT_COPY_RAW_VALUE"), false);
  assert.ok(report.fields["record.privateValue"]);
  assert.equal(report.uniqueObservedSignatures, 1);
});

test("skips oversized files and reports a bounded warning", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "cafeina-analysis-size-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const file = path.join(dir, "oversized.json");
  const handle = await fs.open(file, "w");
  try {
    await handle.write('{"schemaVersion":3,"records":["');
    await handle.write(Buffer.alloc(12 * 1024 * 1024, 65));
    await handle.write('"]}');
  } finally {
    await handle.close();
  }
  const report = await analyzeTracePath(dir);
  assert.equal(report.skippedFiles, 1);
  assert.equal(report.warnings[0].code, "file_too_large");
  assert.equal(report.totalRecords, 0);
});

test("enforces the cumulative input-byte budget", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "cafeina-analysis-total-size-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  for (let i = 0; i < 10; i += 1) {
    const handle = await fs.open(path.join(dir, `batch-${String(i).padStart(2, "0")}.json`), "w");
    try { await handle.truncate(11 * 1024 * 1024); }
    finally { await handle.close(); }
  }
  const report = await analyzeTracePath(dir);
  assert.equal(report.inputFiles, 10);
  assert.equal(report.skippedFiles, 10, "os arquivos esparsos são JSON inválido e o último também ultrapassa o orçamento");
  assert.ok(report.warnings.some((warning) => warning.code === "total_input_byte_limit_reached"));
  assert.equal(report.totalRecords, 0);
});
