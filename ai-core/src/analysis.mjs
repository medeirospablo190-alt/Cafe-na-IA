import { createHash } from "node:crypto";
import { normalizeBatch, normalizeManifest, assertMatchingSession } from "./schema.mjs";

const tools = Object.freeze({ watch_state: 10, observe_gui: 10 });

export function analyzeV3(rawBatch, rawManifest) {
  const batch = normalizeBatch(rawBatch);
  const manifest = normalizeManifest(rawManifest);
  assertMatchingSession(batch, manifest);

  const counts = Object.create(null);
  const refs = Object.create(null);
  for (const record of batch.observations) {
    counts[record.kind] = (counts[record.kind] ?? 0) + 1;
    if (!refs[record.kind]) refs[record.kind] = [];
    if (refs[record.kind].length < 3) refs[record.kind].push(record.evidenceRef);
  }
  const kinds = Object.keys(counts).sort();
  const kindCounts = Object.fromEntries(kinds.map(k => [k, counts[k]]));
  const evidenceRefs = Object.fromEntries(kinds.map(k => [k, refs[k]]));

  const unknowns = [];
  if (counts.remote_outbound) {
    unknowns.push({
      code: "CAUSALITY_NOT_PROVEN",
      message: "Remotes observados nao provam intencao, efeito ou implementacao do servidor.",
      evidenceRefs: refs.remote_outbound
    });
  }
  if (counts.gui_state) {
    unknowns.push({
      code: "GUI_TRANSITION_UNVERIFIED",
      message: "Estados de GUI observados sem teste causal comparativo.",
      evidenceRefs: refs.gui_state
    });
  }
  if (!kinds.length) unknowns.push({
    code: "NO_OBSERVATIONS", message: "Lote vazio.", evidenceRefs: []
  });

  const unknown = unknowns.find(x => x.code === "CAUSALITY_NOT_PROVEN" ||
    x.code === "GUI_TRANSITION_UNVERIFIED");
  let mission = null;
  if (unknown) {
    const toolId = unknown.code === "CAUSALITY_NOT_PROVEN" ? "watch_state" : "observe_gui";
    mission = {
      schemaVersion: 1,
      missionId: "mission-" + createHash("sha256").update(
        [batch.gameId,batch.placeId,batch.runId,unknown.code].join(":")
      ).digest("hex").slice(0, 16),
      gameId: batch.gameId,
      placeId: batch.placeId,
      originatingRunId: batch.runId,
      status: "PROPOSED",
      toolId,
      params: { durationSeconds: tools[toolId] },
      evidenceRefs: unknown.evidenceRefs,
      requiredPermission: "READ_ONLY",
      requiresApproval: true,
      executable: false
    };
  }
  return {
    schemaVersion: 1,
    type: "cafeina_ai_analysis",
    mode: "DRY_RUN",
    identity: {gameId:batch.gameId,placeId:batch.placeId,runId:batch.runId},
    privacy: {rawRecordsIncluded:false, personalIdentifiersIncluded:false},
    evidence: {
      sourceSha256: {batch:batch.checksum,manifest:manifest.checksum},
      batchIndex:batch.batchIndex,
      observedRecords:batch.observations.length,
      kindCounts,
      evidenceRefs,
      hasReportedCoverage:manifest.hasCoverage,
      hasReportedIntelligence:manifest.hasIntelligence,
      causalValidation:false
    },
    unknowns,
    mission,
    limitations: [
      "Somente um lote V3; resultados nao provam cobertura completa.",
      "Modelo de IA, REA, gateway de missoes e Roblox ainda nao conectados.",
      "Proposta nao executavel; nenhuma acao no jogo ocorreu."
    ]
  };
}

export function validateMissionProposal(mission) {
  if (!mission || !Object.hasOwn(tools, mission.toolId)) throw new Error("Ferramenta proibida");
  if (mission.status !== "PROPOSED" || mission.executable !== false ||
      mission.requiresApproval !== true || mission.requiredPermission !== "READ_ONLY") {
    throw new Error("Missao nao pode ser executada automaticamente");
  }
  if (mission.params?.durationSeconds !== tools[mission.toolId]) {
    throw new Error("Parametros de observacao invalidos");
  }
  if (!Array.isArray(mission.evidenceRefs) || mission.evidenceRefs.length > 3) {
    throw new Error("Evidencias invalidas");
  }
  return true;
}
