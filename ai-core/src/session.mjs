import { normalizeBatch, normalizeManifest, assertMatchingSession, DataError } from "./schema.mjs";
import { analyzeV3 } from "./analysis.mjs";

const MAX_BATCHES = 520;
const MAX_EVIDENCE_REFS_PER_KIND = 5;
const PROFILE_STATUSES = new Set(["observed", "tested", "passive", "blocked", "cancelled", "error", "inconclusive"]);

function assertInputArray(values) {
  if (!Array.isArray(values) || values.length < 1 || values.length > MAX_BATCHES) {
    throw new DataError("Esperado 1 a 520 lotes de dados V3.");
  }
}
function sameSession(a, b) {
  assertMatchingSession(a, b);
}

export function summarizeProfile(rawProfile, gameId) {
  if (rawProfile == null) return null;
  if (!rawProfile || typeof rawProfile !== "object" || Array.isArray(rawProfile) ||
      ![1, 3].includes(rawProfile.schemaVersion) || String(rawProfile.gameId) !== gameId) {
    throw new DataError("Perfil V3 nao pertence ao gameId da sessao.");
  }
  const revision = rawProfile.revision;
  const sessions = rawProfile.sessions;
  if (!Number.isSafeInteger(revision) || revision < 0 ||
      !Number.isSafeInteger(sessions) || sessions < 0) {
    throw new DataError("Revision/sessions invalido no perfil.");
  }
  const rows = Array.isArray(rawProfile.investigationKnowledge) ?
    rawProfile.investigationKnowledge : [];
  if (rows.length > 2000) throw new DataError("Perfil de investigacao excessivo.");
  const statuses = Object.create(null);
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const key = PROFILE_STATUSES.has(row.status) ? row.status : "unknown";
    statuses[key] = (statuses[key] ?? 0) + 1;
  }
  return {
    gameId,
    revision,
    observedSessions: sessions,
    investigationCount: rows.length,
    investigationStatuses: Object.fromEntries(Object.entries(statuses).sort()),
    frontierCount: Array.isArray(rawProfile.frontier) ? rawProfile.frontier.length : 0
  };
}

export function analyzeSession({ batches, manifest: rawManifest, profile = null }) {
  assertInputArray(batches);
  const manifest = normalizeManifest(rawManifest);
  const unique = new Map();
  let identicalDuplicates = 0;
  for (const raw of batches) {
    const batch = normalizeBatch(raw);
    if (raw.batchKind !== "data") throw new DataError("Use somente lotes 'data'.");
    sameSession(batch, manifest);
    const prior = unique.get(batch.batchIndex);
    if (prior) {
      if (prior.batch.checksum !== batch.checksum) {
        throw new DataError("CONFLICT: mesmo batchIndex com conteudo divergente " + batch.batchIndex);
      }
      identicalDuplicates += 1;
      continue;
    }
    unique.set(batch.batchIndex, { batch, raw });
  }
  const sorted = [...unique.values()].sort((a, b) => a.batch.batchIndex - b.batch.batchIndex);
  const expected = rawManifest.manifest?.dataBatches;
  const lastIndex = sorted.at(-1).batch.batchIndex;
  const hasDeclaredCount = Number.isSafeInteger(expected) && expected >= 0 && expected <= MAX_BATCHES;
  const expectedCount = hasDeclaredCount ? expected : lastIndex;
  if (expectedCount < lastIndex) {
    throw new DataError("Contagem declarada no manifesto menor que os lotes recebidos.");
  }
  const missing = [];
  const indices = new Set(sorted.map(x => x.batch.batchIndex));
  for (let i = 1; i <= expectedCount; i++) if (!indices.has(i)) missing.push(i);
  const profileSummary = summarizeProfile(profile, manifest.gameId);
  const counts = Object.create(null);
  const refs = Object.create(null);
  let total = 0;
  const batchChecksums = Object.create(null);
  const batchRecords = Object.create(null);
  for (const { batch } of sorted) {
    batchChecksums[String(batch.batchIndex)] = batch.checksum;
    batchRecords[String(batch.batchIndex)] = batch.observations.length;
    total += batch.observations.length;
    for (const record of batch.observations) {
      counts[record.kind] = (counts[record.kind] ?? 0) + 1;
      if (!refs[record.kind]) refs[record.kind] = [];
      if (refs[record.kind].length < MAX_EVIDENCE_REFS_PER_KIND) {
        refs[record.kind].push(record.evidenceRef);
      }
    }
  }
  const kinds = Object.keys(counts).sort();
  const kindCounts = Object.fromEntries(kinds.map(k => [k, counts[k]]));
  const evidenceRefs = Object.fromEntries(kinds.map(k => [k, refs[k]]));
  const unknowns = [];
  if (counts.remote_outbound) unknowns.push({
    code: "CAUSALITY_NOT_PROVEN",
    summary: "Chamadas observadas nao comprovam os efeitos ou a logica do servidor.",
    evidenceRefs: refs.remote_outbound.slice(0, 3)
  });
  if (counts.gui_state) unknowns.push({
    code: "GUI_TRANSITION_UNVERIFIED",
    summary: "Estados de interface observados sem testes causais.",
    evidenceRefs: refs.gui_state.slice(0, 3)
  });
  if (!hasDeclaredCount) unknowns.push({
    code: "BATCH_COUNT_UNREPORTED",
    summary: "Manifesto nao informa quantos lotes de dados eram esperados; cobertura desconhecida.",
    evidenceRefs: []
  });
  if (missing.length) unknowns.push({
    code: "MISSING_BATCHES",
    summary: "A cobertura da sessao esta incompleta: ha lotes faltantes.",
    evidenceRefs: []
  });
  if (!total) unknowns.push({
    code: "NO_OBSERVATIONS",
    summary: "Nao ha observacoes nos lotes recebidos.",
    evidenceRefs: []
  });
  // Reuse the tested dry-run mission builder; never execute or route to Roblox.
  // Pick an evidence-bearing batch so a single empty leading batch does not mask a proposal.
  const missionBatch = sorted.find(x => x.batch.observations.some(y => y.kind === "remote_outbound")) ??
    sorted.find(x => x.batch.observations.some(y => y.kind === "gui_state"));
  const mission = missionBatch ? analyzeV3(missionBatch.raw, rawManifest).mission : null;
  return {
    schemaVersion: 1,
    type: "cafeina_ai_session_analysis",
    mode: "DRY_RUN",
    identity: {
      gameId: manifest.gameId,
      placeId: manifest.placeId,
      runId: manifest.runId
    },
    sources: {
      manifestSha256: manifest.checksum,
      batchChecksums,
      batchRecordCounts: batchRecords,
      identicalDuplicates
    },
    observations: {
      recordCount: total,
      kindCounts,
      evidenceRefs
    },
    coverage: {
      expectedDataBatches: hasDeclaredCount ? expectedCount : null,
      batchCountDeclared: hasDeclaredCount,
      receivedUniqueDataBatches: sorted.length,
      missingBatchIndices: missing,
      completeBatchSequence: hasDeclaredCount && missing.length === 0 && sorted.length === expectedCount,
      reportedCoveragePresent: manifest.hasCoverage,
      causalValidation: false,
      mechanicsReconstructed: 0
    },
    profile: profileSummary,
    unknowns,
    mission,
    privacy: {
      rawRecordsIncluded: false,
      personalIdentifiersIncluded: false,
      remoteArgumentsIncluded: false,
      notes: "Metadados minimizados; a origem bruta continua sujeita a revisao de privacidade."
    },
    limitations: [
      "Presenca de dados ou perfis nao prova causalidade nem fidelidade de reconstrucao.",
      "Nenhuma ferramenta remota, modelo de IA ou motor REA foi executado.",
      "Apenas dados de uma sessao; a memoria entre sessoes depende de armazenamento separado."
    ]
  };
}
