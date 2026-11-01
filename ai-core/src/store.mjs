import { mkdir, readFile, writeFile, open, rename, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import path from "node:path";

function publicSession(report) {
  if (report?.schemaVersion !== 1 || report?.type !== "cafeina_ai_session_analysis" ||
      report.mode !== "DRY_RUN" || report.privacy?.rawRecordsIncluded !== false) {
    throw new Error("Somente relatorios de sessao saneados sao aceitos.");
  }
  const { gameId, placeId, runId } = report.identity;
  if (!/^[1-9][0-9]{0,19}$/.test(gameId) ||
      !/^[1-9][0-9]{0,19}$/.test(placeId) ||
      !/^[A-Za-z0-9_-]{6,128}$/.test(runId)) {
    throw new Error("Identificadores invalidos.");
  }
  const batchChecksums = report.sources.batchChecksums;
  if (!batchChecksums || typeof batchChecksums !== "object" || Array.isArray(batchChecksums)) {
    throw new Error("Sem fontes verificaveis.");
  }
  const entries = Object.entries(batchChecksums);
  if (entries.length > 520 || entries.some(([index, sha]) =>
    !/^[1-9][0-9]{0,2}$/.test(index) || Number(index) > 520 ||
    typeof sha !== "string" || !/^[0-9a-f]{64}$/.test(sha))) {
    throw new Error("Checksum de lote invalido.");
  }
  const checksums = Object.fromEntries(entries.sort((a,b)=>Number(a[0])-Number(b[0])));
  if (!/^[0-9a-f]{64}$/.test(report.sources.manifestSha256)) {
    throw new Error("Checksum de manifesto invalido.");
  }
  const counts = report.observations.kindCounts;
  if (!counts || typeof counts !== "object" || Object.entries(counts).some(([key,n])=>
    !/^[a-z][a-z0-9_]{0,63}$/.test(key) || !Number.isSafeInteger(n) || n<0)) {
    throw new Error("Contadores invalidos.");
  }
  const run = {
    placeId,
    runId,
    manifestSha256: report.sources.manifestSha256,
    batchChecksums: checksums,
    kindCounts: Object.fromEntries(Object.entries(counts).sort()),
    observedRecords: report.observations.recordCount,
    completeBatchSequence: report.coverage.completeBatchSequence,
    unknownCodes: report.unknowns.map(x=>x.code).filter(x=>/^[A-Z_]{2,64}$/.test(x)).slice(0,10),
    verification: "EXPERIMENTAL"
  };
  return {gameId, runId, run};
}

function buildIndex(gameId, sessions) {
  const kinds = Object.create(null);
  const hypotheses = Object.create(null);
  for (const session of Object.values(sessions)) {
    for (const [kind, count] of Object.entries(session.kindCounts)) {
      kinds[kind] = (kinds[kind] ?? 0) + count;
    }
    for (const code of session.unknownCodes) {
      hypotheses[code] ??= { status: "EXPERIMENTAL", observedRuns: 0 };
      hypotheses[code].observedRuns += 1;
    }
  }
  return {
    schemaVersion: 1,
    type: "cafeina_ai_game_knowledge",
    gameId,
    sessions: Object.fromEntries(Object.entries(sessions).sort(([a],[b])=>a.localeCompare(b))),
    totals: {
      knownRuns: Object.keys(sessions).length,
      eventKinds: Object.fromEntries(Object.entries(kinds).sort())
    },
    knowledge: Object.fromEntries(Object.entries(hypotheses).sort())
  };
}

export async function persistSession(storeDir, report) {
  const {gameId,runId,run} = publicSession(report);
  const dir = path.resolve(storeDir);
  await mkdir(dir, {recursive: true});
  const target = path.join(dir, gameId + ".json");
  // Exclusive lock: reject concurrent writers rather than lose a session.
  const lock = target + ".lock";
  const lockHandle = await open(lock, "wx");
  try {
    let previous;
    try {
      previous = JSON.parse(await readFile(target, "utf8"));
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
      previous = buildIndex(gameId, {});
    }
    if (previous.gameId !== gameId || previous.type !== "cafeina_ai_game_knowledge" ||
        !previous.sessions || typeof previous.sessions !== "object") {
      throw new Error("Memoria existente corrompida ou de outro jogo.");
    }
    const old = previous.sessions[runId];
    if (old) {
      if (old.manifestSha256 !== run.manifestSha256 || old.placeId !== run.placeId) {
        throw new Error("CONFLICT: mesmo runId com manifesto ou lugar divergente.");
      }
      for (const [index, sha] of Object.entries(old.batchChecksums)) {
        if (run.batchChecksums[index] && run.batchChecksums[index] !== sha) {
          throw new Error("CONFLICT: checksum divergente no mesmo lote.");
        }
      }
      const oldCount=Object.keys(old.batchChecksums).length;
      const newCount=Object.keys(run.batchChecksums).length;
      if (oldCount >= newCount) {
        if (oldCount === newCount && old.completeBatchSequence === false && run.completeBatchSequence) {
          // Equal membership with updated completeness is permitted if all checksums match.
        } else {
          return { status: "UNCHANGED", gameId, totalRuns: Object.keys(previous.sessions).length };
        }
      }
    }
    const next = buildIndex(gameId, {...previous.sessions, [runId]: run});
    const temp = target + "." + randomBytes(8).toString("hex") + ".tmp";
    try {
      await writeFile(temp, JSON.stringify(next,null,2)+"\n", {flag:"wx",mode:0o600});
      await rename(temp,target);
    } finally {
      await unlink(temp).catch(error=>{if(error.code!=="ENOENT")throw error;});
    }
    return {status: old ? "UPDATED" : "CREATED", gameId, totalRuns: next.totals.knownRuns};
  } finally {
    await lockHandle.close();
    await unlink(lock);
  }
}
