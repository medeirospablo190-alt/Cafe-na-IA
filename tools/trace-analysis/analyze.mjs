#!/usr/bin/env node
/**
 * Offline analyzer for CAFÉÍNA Trace V3 batches.
 * Reads existing JSON batches; never modifies or uploads source traces.
 * Output contains aggregates and inferred field shapes, not raw records.
 */
import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const MAX_FILES = 5000;
const MAX_FILE_BYTES = 12 * 1024 * 1024;
const MAX_DEPTH = 8;
const MAX_FIELDS = 2000;
const MAX_WARNINGS = 100;

function typeOf(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (Number.isInteger(value)) return "integer";
  if (typeof value === "number") return "number";
  return typeof value;
}

function safeLabel(value, max = 180) {
  return String(value ?? "").replace(/[\r\n\t]/g, " ").slice(0, max);
}

function inferFields(value, prefix, output, depth = 0) {
  if (depth > MAX_DEPTH || value === null || typeof value !== "object") return;
  const entries = Array.isArray(value)
    ? value.slice(0, 20).map((v, i) => [`[${i}]`, v])
    : Object.entries(value);
  for (const [key, child] of entries) {
    if (output.size >= MAX_FIELDS) return;
    const name = prefix ? `${prefix}.${key}` : key;
    const type = typeOf(child);
    const item = output.get(name) || { types: new Set(), seen: 0, nonNull: 0 };
    item.types.add(type);
    item.seen += 1;
    if (child !== null) item.nonNull += 1;
    output.set(name, item);
    if (child && typeof child === "object") inferFields(child, name, output, depth + 1);
  }
}

function groupParts(row) {
  const remote = row?.remote && typeof row.remote === "object" ? row.remote : {};
  const object = row?.object && typeof row.object === "object" ? row.object : {};
  return {
    kind: safeLabel(row?.kind || row?.category || "unknown", 80),
    path: safeLabel(remote.path || object.path || row?.path || "no-path", 180),
    method: safeLabel(row?.method || row?.candidate?.method || "", 40),
  };
}

function confidence(samples) {
  if (samples >= 20) return "high";
  if (samples >= 5) return "medium";
  return "low";
}

async function collectJsonFiles(input) {
  const stat = await fs.stat(input);
  if (stat.isFile()) return input.endsWith(".json") ? [input] : [];
  if (!stat.isDirectory()) throw new Error("A entrada precisa ser um arquivo JSON ou uma pasta.");
  const found = [];
  async function walk(dir, depth = 0) {
    if (found.length >= MAX_FILES || depth > 8) return;
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (found.length >= MAX_FILES) break;
      if (entry.name.startsWith(".")) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(full, depth + 1);
      else if (entry.isFile() && entry.name.endsWith(".json")) found.push(full);
    }
  }
  await walk(input);
  return found;
}

export async function analyzeTracePath(input) {
  const files = await collectJsonFiles(input);
  const result = {
    analyzer: "cafeina-trace-v3-offline",
    analyzerVersion: 2,
    generatedAt: new Date().toISOString(),
    inputFiles: files.length,
    skippedFiles: 0,
    sessions: {},
    kinds: {},
    groups: {},
    fields: {},
    warnings: [],
  };
  const fields = new Map();
  const explicitSignatures = new Set();
  let totalRecords = 0;
  let totalRemotes = 0;

  const warn = (code, file, extra = {}) => {
    if (result.warnings.length < MAX_WARNINGS) {
      result.warnings.push({ code, file: path.basename(file), ...extra });
    }
  };

  for (const file of files) {
    let batch;
    try {
      const stat = await fs.stat(file);
      if (stat.size > MAX_FILE_BYTES) {
        result.skippedFiles += 1;
        warn("file_too_large", file, { limitBytes: MAX_FILE_BYTES });
        continue;
      }
      const raw = await fs.readFile(file, "utf8");
      batch = JSON.parse(raw);
    } catch (error) {
      result.skippedFiles += 1;
      warn(error?.code === "ENOENT" ? "file_unavailable" : "invalid_json", file);
      continue;
    }
    if (!batch || typeof batch !== "object" || Array.isArray(batch)) {
      result.skippedFiles += 1;
      warn("invalid_batch_shape", file);
      continue;
    }
    const isTrace = batch.schemaVersion === 3
      && (batch.type === "cafeina_universal_trace_v3_batch" || Array.isArray(batch.records));
    if (!isTrace) continue;

    const gameId = safeLabel(batch.gameId ?? "unknown", 40);
    const placeId = safeLabel(batch.placeId ?? "unknown", 40);
    const runId = safeLabel(batch.runId || "unknown", 120);
    const sessionKey = JSON.stringify([gameId, placeId, runId]);
    const session = result.sessions[sessionKey] || {
      gameId,
      placeId,
      runId,
      batches: 0,
      recordCount: 0,
      remoteCount: 0,
      firstCapturedAt: batch.capturedAt || null,
      lastCapturedAt: batch.capturedAt || null,
      stats: {},
    };
    session.batches += 1;
    const records = Array.isArray(batch.records) ? batch.records : [];
    const remotes = Array.isArray(batch.remotes) ? batch.remotes : [];
    session.recordCount += records.length;
    session.remoteCount += remotes.length;
    if (batch.capturedAt && (!session.firstCapturedAt || batch.capturedAt < session.firstCapturedAt)) session.firstCapturedAt = batch.capturedAt;
    if (batch.capturedAt && (!session.lastCapturedAt || batch.capturedAt > session.lastCapturedAt)) session.lastCapturedAt = batch.capturedAt;
    if (batch.stats && typeof batch.stats === "object" && !Array.isArray(batch.stats)) {
      for (const [key, value] of Object.entries(batch.stats)) {
        if (typeof value === "number" && Number.isFinite(value)) {
          session.stats[safeLabel(key, 100)] = Math.max(session.stats[safeLabel(key, 100)] || 0, value);
        }
      }
    }
    result.sessions[sessionKey] = session;

    for (const [collectionName, rows] of [["records", records], ["remotes", remotes]]) {
      for (const row of rows) {
        if (!row || typeof row !== "object" || Array.isArray(row)) continue;
        totalRecords += collectionName === "records" ? 1 : 0;
        totalRemotes += collectionName === "remotes" ? 1 : 0;
        const parts = groupParts(row);
        result.kinds[parts.kind] = (result.kinds[parts.kind] || 0) + 1;
        const groupKey = JSON.stringify([collectionName, parts.kind, parts.path, parts.method]);
        const group = result.groups[groupKey] || {
          collection: collectionName, ...parts, samples: 0,
          signatures: new Set(), qualityTotal: 0, qualityCount: 0,
          firstUnix: null, lastUnix: null,
        };
        group.samples += 1;
        const signature = row.sig || row.semanticHash || row.candidate?.semanticHash || row.shapeHash || row.candidate?.shapeHash;
        if (signature !== undefined && signature !== null && String(signature)) {
          const normalizedSignature = safeLabel(signature, 200);
          group.signatures.add(normalizedSignature);
          explicitSignatures.add(JSON.stringify([sessionKey, groupKey, normalizedSignature]));
        }
        const quality = Number(row.quality);
        if (row.quality !== null && row.quality !== undefined && row.quality !== "" && Number.isFinite(quality)) {
          group.qualityTotal += quality;
          group.qualityCount += 1;
        }
        const unix = Number(row.unix);
        if (row.unix !== null && row.unix !== undefined && row.unix !== "" && Number.isFinite(unix)) {
          group.firstUnix = group.firstUnix === null ? unix : Math.min(group.firstUnix, unix);
          group.lastUnix = group.lastUnix === null ? unix : Math.max(group.lastUnix, unix);
        }
        result.groups[groupKey] = group;
        inferFields(row, collectionName === "records" ? "record" : "remote", fields);
      }
    }
  }

  result.totalRecords = totalRecords;
  result.totalRemotes = totalRemotes;
  result.uniqueObservedSignatures = explicitSignatures.size;
  result.groups = Object.fromEntries(Object.entries(result.groups).map(([key, group]) => [key, {
    ...group,
    signatures: group.signatures.size,
    confidence: confidence(group.samples),
    meanQuality: group.qualityCount ? Math.round(group.qualityTotal / group.qualityCount * 100) / 100 : null,
    qualityCount: undefined,
    qualityTotal: undefined,
  }]));
  result.fields = Object.fromEntries([...fields.entries()].map(([name, item]) => [name, {
    types: [...item.types].sort(),
    samples: item.seen,
    nonNullSamples: item.nonNull,
    confidence: confidence(item.seen),
  }]));
  if (files.length >= MAX_FILES) result.warnings.push({ code: "file_limit_reached", limit: MAX_FILES });
  result.warnings = result.warnings.slice(0, MAX_WARNINGS);
  return result;
}

async function main() {
  const input = process.argv[2];
  const output = process.argv[3] || "trace-analysis-report.json";
  if (!input) {
    console.error("Uso: node tools/trace-analysis/analyze.mjs <arquivo-ou-pasta> [saida.json]");
    process.exitCode = 2;
    return;
  }
  const report = await analyzeTracePath(input);
  await fs.writeFile(output, JSON.stringify(report, null, 2) + "\n", "utf8");
  console.log(JSON.stringify({
    output,
    inputFiles: report.inputFiles,
    skippedFiles: report.skippedFiles,
    sessions: Object.keys(report.sessions).length,
    records: report.totalRecords,
    remotes: report.totalRemotes,
    groups: Object.keys(report.groups).length,
    fields: Object.keys(report.fields).length,
    signatures: report.uniqueObservedSignatures,
  }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error("Análise falhou:", error?.message || error);
    process.exitCode = 1;
  });
}
