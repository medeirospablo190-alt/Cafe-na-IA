import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const TRACE_V3_DIR = path.resolve(
  process.env.INVENTORY_TRACE_V3_DIR || path.join(__dirname, "private-downloads", "inventory-traces-v3")
);
const GITHUB_TOKEN = String(process.env.AVATAR_DUMP_GITHUB_TOKEN || "").trim();
const GITHUB_REPO = String(process.env.AVATAR_DUMP_GITHUB_REPO || "medeirospablo190-alt/Cafe-na-IA").trim();
const GITHUB_BRANCH = String(process.env.AVATAR_DUMP_GITHUB_BRANCH || "main").trim();
const GITHUB_API_BASE = String(process.env.INVENTORY_TRACE_V3_GITHUB_API_BASE || "https://api.github.com")
  .trim()
  .replace(/\/+$/g, "");
const TRACE_V3_GITHUB_BASE = String(process.env.INVENTORY_TRACE_V3_GITHUB_PATH || "inventory-traces-v3")
  .trim()
  .replace(/^\/+|\/+$/g, "");

const MAX_REQUESTS_PER_WINDOW = clampInt(process.env.INVENTORY_TRACE_V3_MAX_PER_WINDOW, 30, 360, 220);
const WINDOW_MS = clampInt(process.env.INVENTORY_TRACE_V3_WINDOW_SECONDS, 60, 3600, 600) * 1000;
const MAX_RECORDS_PER_BATCH = clampInt(process.env.INVENTORY_TRACE_V3_MAX_RECORDS, 100, 12000, 6000);
const MAX_REMOTES_PER_BATCH = clampInt(process.env.INVENTORY_TRACE_V3_MAX_REMOTES, 20, 3000, 1000);
const MAX_BATCH_TOTAL = clampInt(process.env.INVENTORY_TRACE_V3_MAX_BATCHES, 20, 520, 260);
const MAX_PROFILE_LOW = clampInt(process.env.INVENTORY_TRACE_V3_PROFILE_LOW_MAX, 2000, 30000, 20000);
const MAX_PROFILE_SHAPES = clampInt(process.env.INVENTORY_TRACE_V3_PROFILE_SHAPE_MAX, 1000, 20000, 12000);
const MAX_PROFILE_SEMANTIC = clampInt(process.env.INVENTORY_TRACE_V3_PROFILE_SEMANTIC_MAX, 1000, 20000, 12000);
const MAX_PROFILE_REMOTES = clampInt(process.env.INVENTORY_TRACE_V3_PROFILE_REMOTE_MAX, 500, 8000, 4000);
const MAX_PROFILE_INVESTIGATIONS = clampInt(
  process.env.INVENTORY_TRACE_V3_PROFILE_INVESTIGATION_MAX,
  100,
  2000,
  800
);
const MAX_PROFILE_FRONTIER = clampInt(process.env.INVENTORY_TRACE_V3_PROFILE_FRONTIER_MAX, 10, 300, 100);
const BODY_LIMIT = process.env.INVENTORY_TRACE_V3_BODY_LIMIT || "3mb";
const HARD_SESSION_BYTES = 150 * 1024 * 1024;
const RECOMMENDED_BATCH_BYTES = Math.floor(1.75 * 1024 * 1024);

const attempts = new Map();
const profileLocks = new Map();

export function installCollectorV3Routes(app) {
  app.get("/api/inventory-trace-v3/health", securityHeaders, (_req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.json({
      ok: true,
      service: "CAFEINA_UNIVERSAL_TRACE_V3",
      schemaVersion: 3,
      githubMirrorConfigured: Boolean(GITHUB_TOKEN),
      maxRecordsPerBatch: MAX_RECORDS_PER_BATCH,
      maxRemotesPerBatch: MAX_REMOTES_PER_BATCH,
      maxBatches: MAX_BATCH_TOTAL,
      hardSessionBytes: HARD_SESSION_BYTES,
      recommendedBatchBytes: RECOMMENDED_BATCH_BYTES,
      profileCaps: {
        lowValueHashes: MAX_PROFILE_LOW,
        shapeHashes: MAX_PROFILE_SHAPES,
        semanticHashes: MAX_PROFILE_SEMANTIC,
        remoteHashes: MAX_PROFILE_REMOTES,
        investigationKnowledge: MAX_PROFILE_INVESTIGATIONS,
      },
    });
  });

  app.get("/api/inventory-trace-v3/profile/:gameId", securityHeaders, handleGetProfile);
  app.post(
    "/api/inventory-trace-v3/batch",
    express.json({ limit: BODY_LIMIT, strict: true }),
    securityHeaders,
    handleBatch
  );
  app.get("/api/inventory-trace-v3/:gameId/:placeId/latest", securityHeaders, handleLatestManifest);

  setInterval(() => {
    const now = Date.now();
    for (const [key, state] of attempts) {
      if (now - state.windowStartedAt > WINDOW_MS) attempts.delete(key);
    }
  }, 60_000).unref();
}

async function handleGetProfile(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const gameId = safePositiveId(req.params.gameId);
  if (!gameId) return jsonError(res, 400, "gameId inválido.");

  const profile = await loadProfile(gameId);
  return res.json({
    ok: true,
    gameId,
    profile: profile || emptyProfile(gameId),
    source: profile ? "stored" : "new",
  });
}

async function handleLatestManifest(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const gameId = safePositiveId(req.params.gameId);
  const placeId = safePositiveId(req.params.placeId);
  if (!gameId || !placeId) return jsonError(res, 400, "gameId/placeId inválido.");

  const relative = `${gameId}/${placeId}/latest.json`;
  const localPath = path.join(TRACE_V3_DIR, relative);
  const local = await readLocalText(localPath);
  if (local) {
    res.type("application/json; charset=utf-8");
    return res.send(local);
  }

  try {
    const remote = await readGitHubText(`${TRACE_V3_GITHUB_BASE}/${relative}`);
    if (remote) {
      res.type("application/json; charset=utf-8");
      return res.send(remote);
    }
  } catch (error) {
    console.error("TRACE_V3_LATEST_GITHUB_READ_ERROR", error?.message || error);
  }
  return jsonError(res, 404, "Nenhum manifesto V3 encontrado.");
}

function portableHashText(text) {
  const bytes = Buffer.from(String(text || ""), "utf8");
  let h1 = 216613;
  let h2 = 131071;
  for (const b of bytes) {
    h1 = (h1 * 131 + b) % 16777213;
    h2 = (h2 * 137 + b) % 16777199;
  }
  return h1.toString(16).padStart(6, "0") + h2.toString(16).padStart(6, "0");
}

function resumeToken(row) {
  const value = row && typeof row === "object" && !Array.isArray(row) ? row : {};
  const remote = value.remote && typeof value.remote === "object" ? value.remote : {};
  const object = value.object && typeof value.object === "object" ? value.object : {};
  return [
    String(value.kind || ""),
    String(value.sig || ""),
    String(value.semanticHash || ""),
    String(value.shapeHash || ""),
    String(remote.path || object.path || value.path || ""),
  ].join("\x1f");
}

function batchResumeSummary(batch) {
  if (!batch || typeof batch !== "object" || Array.isArray(batch)) return null;
  const records = Array.isArray(batch.records) ? batch.records : [];
  const remotes = Array.isArray(batch.remotes) ? batch.remotes : [];
  return {
    batchIndex: safeInteger(batch.batchIndex),
    batchKind: String(batch.batchKind || "data"),
    payloadBytes: safeInteger(batch.payloadBytes) || 0,
    recordCount: records.length,
    remoteCount: remotes.length,
    recordsHash: portableHashText(records.map(resumeToken).join("\x1e")),
    remotesHash: portableHashText(remotes.map(resumeToken).join("\x1e")),
  };
}

async function handleBatch(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (!GITHUB_TOKEN) return jsonError(res, 503, "Espelho GitHub não configurado.");
  if (!consumeRate(attempts, clientIpHash(req), MAX_REQUESTS_PER_WINDOW, WINDOW_MS)) {
    return jsonError(res, 429, "Muitos lotes enviados. Aguarde e tente novamente.");
  }

  const body = req.body;
  if (!body || typeof body !== "object" || Array.isArray(body)) return jsonError(res, 400, "Lote inválido.");

  const gameId = safePositiveId(body.gameId);
  const placeId = safePositiveId(body.placeId);
  const runId = safeRunId(body.runId);
  const batchIndex = safeInteger(body.batchIndex);
  const batchTotal = safeInteger(body.batchTotal);
  const batchKind = String(body.batchKind || "data");
  if (!gameId || !placeId || !runId) return jsonError(res, 400, "gameId/placeId/runId inválido.");
  if (!batchIndex || batchIndex < 1) return jsonError(res, 400, "batchIndex inválido.");
  if (batchTotal !== null && (batchTotal < batchIndex || batchTotal > MAX_BATCH_TOTAL)) {
    return jsonError(res, 400, "batchTotal inválido.");
  }
  if (!new Set(["data", "manifest"]).has(batchKind)) return jsonError(res, 400, "batchKind inválido.");

  const records = Array.isArray(body.records) ? body.records : [];
  const remotes = Array.isArray(body.remotes) ? body.remotes : [];
  if (records.length > MAX_RECORDS_PER_BATCH) return jsonError(res, 413, "Muitos registros no lote.");
  if (remotes.length > MAX_REMOTES_PER_BATCH) return jsonError(res, 413, "Muitos remotes no lote.");

  const now = new Date();
  const receivedAt = now.toISOString();
  const stablePayload = {
    schemaVersion: 3,
    collector: safeObject(body.collector),
    userId: String(body.userId || "").slice(0, 30),
    username: String(body.username || "").slice(0, 80),
    capturedAt: safeIsoDate(body.capturedAt) || null,
    gameId,
    placeId,
    placeVersion: safeInteger(body.placeVersion),
    runId,
    batchIndex,
    batchTotal,
    batchKind,
    payloadBytes: safeInteger(body.payloadBytes) || 0,
    records,
    remotes,
    manifest: batchKind === "manifest" ? safeObject(body.manifest) : undefined,
  };
  const contentChecksum = sha256(JSON.stringify(stablePayload)).slice(0, 20);
  const normalized = {
    schemaVersion: 3,
    type: "cafeina_universal_trace_v3_batch",
    ...stablePayload,
    capturedAt: stablePayload.capturedAt || receivedAt,
    serverReceivedAt: receivedAt,
    contentChecksum,
    stats: safeObject(body.stats),
  };

  const text = `${JSON.stringify(normalized, null, 2)}\n`;
  const checksum = sha256(text).slice(0, 16);
  const batchFile = `${String(batchIndex).padStart(4, "0")}-${batchKind}.json`;
  const runRelative = `${gameId}/${placeId}/${runId}/${batchFile}`;
  const localPath = path.join(TRACE_V3_DIR, runRelative);
  const githubPath = `${TRACE_V3_GITHUB_BASE}/${runRelative}`;

  try {
    await fs.promises.mkdir(path.dirname(localPath), { recursive: true });
    const existing = await readLocalText(localPath);
    if (existing) {
      let parsed = null;
      try { parsed = JSON.parse(existing); } catch {}
      if (!parsed || parsed.contentChecksum !== contentChecksum) {
        return jsonError(res, 409, "Lote já existe com conteúdo diferente.", {
          runId,
          batchIndex,
          existing: batchResumeSummary(parsed),
        });
      }
    } else {
      await fs.promises.writeFile(localPath, text, { encoding: "utf-8", flag: "wx" });
    }
  } catch (error) {
    if (error?.code !== "EEXIST") {
      console.error("TRACE_V3_LOCAL_WRITE_ERROR", error?.message || error);
      return jsonError(res, 500, "Falha ao salvar lote localmente.");
    }
  }

  try {
    const remoteText = await readGitHubText(githubPath);
    if (remoteText) {
      let remoteParsed = null;
      try { remoteParsed = JSON.parse(remoteText); } catch {}
      if (!remoteParsed || remoteParsed.contentChecksum !== contentChecksum) {
        return jsonError(res, 409, "Lote já existe no GitHub com conteúdo diferente.", {
          runId,
          batchIndex,
          existing: batchResumeSummary(remoteParsed),
        });
      }
    } else {
      await upsertGitHubText(githubPath, text, `Trace V3 ${gameId}/${placeId} ${runId} batch ${batchIndex}`);
    }
  } catch (error) {
    console.error("TRACE_V3_GITHUB_BATCH_ERROR", error?.message || error);
    return jsonError(res, 502, "Falha ao confirmar lote no GitHub.", { runId, batchIndex });
  }

  let profile = null;
  if (batchKind === "manifest") {
    const manifest = safeObject(body.manifest);
    try {
      profile = await mergeAndSaveProfile(gameId, runId, manifest?.profileDelta, manifest?.strategyDelta, manifest?.coverage);
      const latest = {
        schemaVersion: 3,
        type: "cafeina_universal_trace_v3_manifest",
        gameId,
        placeId,
        placeVersion: normalized.placeVersion,
        runId,
        capturedAt: normalized.capturedAt,
        serverReceivedAt: receivedAt,
        stats: normalized.stats,
        manifest,
        profileRevision: profile?.revision || 0,
      };
      const latestText = `${JSON.stringify(latest, null, 2)}\n`;
      const latestRelative = `${gameId}/${placeId}/latest.json`;
      await atomicWrite(path.join(TRACE_V3_DIR, latestRelative), latestText);
      await upsertGitHubText(
        `${TRACE_V3_GITHUB_BASE}/${latestRelative}`,
        latestText,
        `Trace V3 latest ${gameId}/${placeId}`
      );
    } catch (error) {
      console.error("TRACE_V3_MANIFEST_FINALIZE_ERROR", error?.message || error);
      return jsonError(res, 502, "Lote salvo, mas a finalização do perfil/manifesto falhou.", {
        runId,
        batchIndex,
      });
    }
  }

  return res.status(201).json({
    ok: true,
    runId,
    gameId,
    placeId,
    batchIndex,
    batchKind,
    checksum,
    github: { configured: true, mirrored: true, path: githubPath },
    profileRevision: profile?.revision || null,
  });
}

async function mergeAndSaveProfile(gameId, runId, profileDelta, strategyDelta, coverage) {
  return withProfileLock(gameId, async () => {
    const current = (await loadProfile(gameId)) || emptyProfile(gameId);
    current.recentRuns = mergeBoundedStrings(current.recentRuns, [], 50, 120);
    const alreadyApplied = current.recentRuns.includes(runId);
    if (alreadyApplied) return current;

    current.revision = (safeInteger(current.revision) || 0) + 1;
    current.sessions = (safeInteger(current.sessions) || 0) + 1;
    current.updatedAt = new Date().toISOString();
    current.recentRuns = mergeBoundedStrings(current.recentRuns, [runId], 50, 120);

    const delta = safeObject(profileDelta);
    current.knownLowValueHashes = mergeBoundedHashes(
      current.knownLowValueHashes,
      delta?.knownLowValueHashes,
      MAX_PROFILE_LOW
    );
    current.knownShapeHashes = mergeBoundedHashes(
      current.knownShapeHashes,
      delta?.knownShapeHashes,
      MAX_PROFILE_SHAPES
    );
    current.knownSemanticHashes = mergeBoundedHashes(
      current.knownSemanticHashes,
      delta?.knownSemanticHashes,
      MAX_PROFILE_SEMANTIC
    );
    current.knownRemoteHashes = mergeBoundedHashes(
      current.knownRemoteHashes,
      delta?.knownRemoteHashes,
      MAX_PROFILE_REMOTES
    );
    current.investigationKnowledge = mergeInvestigationKnowledge(
      current.investigationKnowledge,
      delta?.investigationKnowledge,
      MAX_PROFILE_INVESTIGATIONS
    );
    current.frontier = mergeBoundedStrings(current.frontier, delta?.frontier, MAX_PROFILE_FRONTIER, 180);
    current.strategy = mergeStrategy(current.strategy, strategyDelta);
    current.lastCoverage = compactCoverage(coverage);

    const text = `${JSON.stringify(current, null, 2)}\n`;
    const local = profileLocalPath(gameId);
    await atomicWrite(local, text);
    await upsertGitHubText(profileGitHubPath(gameId), text, `Trace V3 profile ${gameId} rev ${current.revision}`);
    return current;
  });
}

async function withProfileLock(gameId, fn) {
  const key = String(gameId);
  const previous = profileLocks.get(key) || Promise.resolve();
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const chain = previous.catch(() => {}).then(() => gate);
  profileLocks.set(key, chain);

  await previous.catch(() => {});
  try {
    return await fn();
  } finally {
    release();
    if (profileLocks.get(key) === chain) profileLocks.delete(key);
  }
}

function mergeStrategy(current, incoming) {
  const out = safeObject(current) || {};
  const inc = safeObject(incoming) || {};
  for (const [category, value] of Object.entries(inc)) {
    if (!/^[A-Za-z0-9_.-]{1,60}$/.test(category)) continue;
    const v = safeObject(value);
    if (!v) continue;
    const old = safeObject(out[category]) || {};
    out[category] = {
      observed: boundedCounter(old.observed, v.observed),
      accepted: boundedCounter(old.accepted, v.accepted),
      novel: boundedCounter(old.novel, v.novel),
      suppressed: boundedCounter(old.suppressed, v.suppressed),
      sampleN: clampInt(v.sampleN ?? old.sampleN, 1, 16, 1),
    };
  }
  return out;
}

function boundedCounter(a, b) {
  const n = Math.max(0, Number(a) || 0) + Math.max(0, Number(b) || 0);
  return Math.min(1_000_000_000, Math.floor(n));
}

function compactCoverage(value) {
  const v = safeObject(value);
  if (!v) return {};
  const out = {};
  for (const [key, item] of Object.entries(v)) {
    if (!/^[A-Za-z0-9_.-]{1,60}$/.test(key)) continue;
    if (typeof item === "number" && Number.isFinite(item)) out[key] = Math.floor(item);
    else if (typeof item === "boolean") out[key] = item;
    else if (typeof item === "string") out[key] = item.slice(0, 120);
  }
  return out;
}

async function loadProfile(gameId) {
  const local = await readLocalText(profileLocalPath(gameId));
  if (local) {
    try { return JSON.parse(local); } catch {}
  }
  try {
    const remote = await readGitHubText(profileGitHubPath(gameId));
    if (!remote) return null;
    const parsed = JSON.parse(remote);
    await atomicWrite(profileLocalPath(gameId), `${JSON.stringify(parsed, null, 2)}\n`);
    return parsed;
  } catch (error) {
    console.error("TRACE_V3_PROFILE_READ_ERROR", error?.message || error);
    return null;
  }
}

function emptyProfile(gameId) {
  return {
    schemaVersion: 1,
    gameId,
    revision: 0,
    sessions: 0,
    updatedAt: null,
    knownLowValueHashes: [],
    knownShapeHashes: [],
    knownSemanticHashes: [],
    knownRemoteHashes: [],
    investigationKnowledge: [],
    frontier: [],
    strategy: {},
    lastCoverage: {},
    recentRuns: [],
  };
}

function profileLocalPath(gameId) {
  return path.join(TRACE_V3_DIR, "profiles", `${gameId}.json`);
}

function profileGitHubPath(gameId) {
  return `${TRACE_V3_GITHUB_BASE}/profiles/${gameId}.json`;
}

function mergeBoundedHashes(current, incoming, max) {
  const set = new Set();
  const out = [];
  for (const source of [current, incoming]) {
    if (!Array.isArray(source)) continue;
    for (const value of source) {
      const s = String(value || "");
      if (!/^[a-f0-9]{8,24}$/i.test(s) || set.has(s)) continue;
      set.add(s);
      out.push(s.toLowerCase());
    }
  }
  return out.length <= max ? out : out.slice(out.length - max);
}

function mergeInvestigationKnowledge(current, incoming, max) {
  const rows = new Map();

  const apply = (source, accumulate) => {
    if (!Array.isArray(source)) return;
    for (const value of source) {
      const row = safeObject(value);
      const key = String(row?.key || "").toLowerCase();
      if (!/^[a-f0-9]{8,24}$/.test(key)) continue;

      const old = rows.get(key) || {
        key,
        observations: 0,
        activeTests: 0,
        completed: 0,
        passiveOnly: 0,
        cancelled: 0,
        status: null,
        lastReason: null,
        lastImpact: null,
        lastOutcome: null,
      };
      const next = { ...old };
      for (const field of ["observations", "activeTests", "completed", "passiveOnly", "cancelled"]) {
        const incomingValue = Math.max(0, Math.floor(Number(row[field]) || 0));
        next[field] = accumulate ? boundedCounter(old[field], incomingValue) : incomingValue;
      }

      const status = String(row.status || "").slice(0, 32);
      if (/^(observed|tested|passive|blocked|cancelled|error|inconclusive)$/.test(status)) {
        next.status = status;
      }
      if (row.lastReason !== undefined && row.lastReason !== null) {
        next.lastReason = String(row.lastReason).slice(0, 120);
      }
      const impact = Number(row.lastImpact);
      if (Number.isFinite(impact)) next.lastImpact = Math.max(0, Math.min(100, Math.round(impact * 100) / 100));

      const outcome = String(row.lastOutcome || "").toLowerCase();
      if (/^[a-f0-9]{8,24}$/.test(outcome)) next.lastOutcome = outcome;

      if (rows.has(key)) rows.delete(key);
      rows.set(key, next);
    }
  };

  apply(current, false);
  apply(incoming, true);
  const out = [...rows.values()];
  return out.length <= max ? out : out.slice(out.length - max);
}

function mergeBoundedStrings(current, incoming, max, maxLen) {
  const set = new Set();
  const out = [];
  for (const source of [current, incoming]) {
    if (!Array.isArray(source)) continue;
    for (const value of source) {
      const s = String(value || "").slice(0, maxLen);
      if (!s || set.has(s)) continue;
      set.add(s);
      out.push(s);
    }
  }
  return out.length <= max ? out : out.slice(out.length - max);
}

async function upsertGitHubText(repoPath, text, message) {
  if (!GITHUB_TOKEN) throw new Error("GitHub token não configurado");
  const { apiUrl } = githubLocation(repoPath);
  const headers = githubHeaders(true);
  let sha = null;
  const current = await fetch(`${apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`, { headers });
  if (current.ok) {
    const data = await current.json();
    sha = typeof data?.sha === "string" ? data.sha : null;
  } else if (current.status !== 404) {
    throw new Error(`GitHub GET falhou: ${current.status}`);
  }

  const payload = {
    message,
    content: Buffer.from(text, "utf-8").toString("base64"),
    branch: GITHUB_BRANCH,
  };
  if (sha) payload.sha = sha;

  const response = await fetch(apiUrl, {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(`GitHub PUT falhou: ${response.status}`);
}

async function readGitHubText(repoPath) {
  const { apiUrl } = githubLocation(repoPath);
  const response = await fetch(`${apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`, {
    headers: { ...githubHeaders(false), Accept: "application/vnd.github.raw+json" },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub read falhou: ${response.status}`);
  return response.text();
}

function githubLocation(repoPath) {
  const match = /^([^/]+)\/([^/]+)$/.exec(GITHUB_REPO);
  if (!match) throw new Error("AVATAR_DUMP_GITHUB_REPO inválido");
  const [, owner, repo] = match;
  const encodedPath = repoPath.split("/").filter(Boolean).map(encodeURIComponent).join("/");
  return {
    apiUrl: `${GITHUB_API_BASE}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${encodedPath}`,
  };
}

function githubHeaders(authRequired) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "cafeina-trace-v3",
  };
  if (GITHUB_TOKEN) headers.Authorization = `Bearer ${GITHUB_TOKEN}`;
  else if (authRequired) throw new Error("GitHub token não configurado");
  return headers;
}

async function atomicWrite(target, content) {
  await fs.promises.mkdir(path.dirname(target), { recursive: true });
  const tmp = `${target}.${process.pid}.${crypto.randomBytes(4).toString("hex")}.tmp`;
  await fs.promises.writeFile(tmp, content, "utf-8");
  await fs.promises.rename(tmp, target);
}

async function readLocalText(target) {
  try {
    return await fs.promises.readFile(target, "utf-8");
  } catch (error) {
    if (error?.code !== "ENOENT") console.error("TRACE_V3_LOCAL_READ_ERROR", error?.message || error);
    return null;
  }
}

function securityHeaders(_req, res, next) {
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  if (process.env.NODE_ENV === "production") {
    res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  }
  next();
}

function consumeRate(store, key, maxPerWindow, windowMs) {
  const now = Date.now();
  const current = store.get(key);
  if (!current || now - current.windowStartedAt > windowMs) {
    store.set(key, { count: 1, windowStartedAt: now });
    return true;
  }
  if (current.count >= maxPerWindow) return false;
  current.count += 1;
  return true;
}

function clientIpHash(req) {
  return sha256(String(req.ip || req.socket?.remoteAddress || "unknown"));
}

function safeRunId(value) {
  const s = String(value || "");
  return /^[A-Za-z0-9-]{8,120}$/.test(s) ? s : null;
}

function safePositiveId(value) {
  const n = safeInteger(value);
  return n && n > 0 ? n : null;
}

function safeInteger(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) ? n : null;
}

function safeIsoDate(value) {
  if (typeof value !== "string" || value.length > 60) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function safeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("base64url");
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(n)));
}

function jsonError(res, status, message, extra = {}) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(status).json({ ok: false, message, ...extra });
}