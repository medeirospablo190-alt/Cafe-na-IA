import { createHash } from "node:crypto";

export class DataError extends Error {}

function asObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new DataError(field + ": objeto esperado");
  }
  return value;
}
function id(value, field) {
  const text = (typeof value === "string" || typeof value === "number") ? String(value) : "";
  if (!/^[1-9][0-9]{0,19}$/.test(text)) throw new DataError(field + ": ID invalido");
  return text;
}
function runId(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{6,128}$/.test(value)) {
    throw new DataError("runId invalido");
  }
  return value;
}
function identity(doc) {
  if (doc.schemaVersion !== 3) throw new DataError("Schema V3 obrigatorio");
  return {
    gameId: id(doc.gameId, "gameId"),
    placeId: id(doc.placeId, "placeId"),
    runId: runId(doc.runId)
  };
}
function checksum(doc) {
  return createHash("sha256").update(JSON.stringify(doc)).digest("hex");
}

export function normalizeBatch(raw) {
  const doc = asObject(raw, "batch");
  if (doc.type !== "cafeina_universal_trace_v3_batch" ||
      !["data", "manifest"].includes(doc.batchKind)) {
    throw new DataError("Batch V3 invalido");
  }
  const target = identity(doc);
  if (!Number.isSafeInteger(doc.batchIndex) || doc.batchIndex < 1 || doc.batchIndex > 520) {
    throw new DataError("batchIndex invalido");
  }
  if (!Array.isArray(doc.records) || doc.records.length > 6000) {
    throw new DataError("Quantidade de registros invalida");
  }
  const observations = doc.records.map((value, index) => {
    const record = asObject(value, "record");
    const kind = typeof record.kind === "string" &&
      /^[a-z][a-z0-9_]{0,63}$/.test(record.kind) ? record.kind : "unknown";
    return {
      evidenceRef: "v3:" + target.gameId + ":" + target.placeId + ":" + target.runId +
        ":" + doc.batchIndex + ":" + index,
      kind,
      unix: Number.isFinite(record.unix) && record.unix >= 0 ? record.unix : null
    };
  });
  return { ...target, batchIndex: doc.batchIndex, checksum: checksum(doc), observations };
}

export function normalizeManifest(raw) {
  const doc = asObject(raw, "latest");
  if (doc.type !== "cafeina_universal_trace_v3_manifest") {
    throw new DataError("Manifesto V3 invalido");
  }
  const target = identity(doc);
  const manifest = asObject(doc.manifest, "manifest");
  return {
    ...target,
    checksum: checksum(doc),
    hasCoverage: !!(manifest.coverage && typeof manifest.coverage === "object"),
    hasIntelligence: !!(manifest.intelligence && typeof manifest.intelligence === "object")
  };
}

export function assertMatchingSession(batch, manifest) {
  for (const key of ["gameId", "placeId", "runId"]) {
    if (batch[key] !== manifest[key]) throw new DataError("Sessoes divergentes: " + key);
  }
}
