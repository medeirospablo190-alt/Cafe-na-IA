import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";
import { installCollectorV3Routes } from "./collector-v3-routes.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 3000);

const DATA_DIR = path.resolve(
  process.env.CAFEINA_COLLECTOR_DATA_DIR
    || process.env.DOWNLOAD_DIR
    || path.join(__dirname, "private-downloads")
);
const INVENTORY_TRACE_DIR = path.resolve(
  process.env.INVENTORY_TRACE_DIR
    || path.join(DATA_DIR, "inventory-traces")
);

const TRACE_MAX_PER_WINDOW = clampInt(
  process.env.INVENTORY_TRACE_MAX_PER_WINDOW,
  1,
  120,
  30
);
const TRACE_WINDOW_MS = clampInt(
  process.env.INVENTORY_TRACE_WINDOW_SECONDS,
  60,
  3600,
  600
) * 1000;
const TRACE_MAX_RECORDS = clampInt(
  process.env.INVENTORY_TRACE_MAX_RECORDS,
  100,
  10000,
  2500
);
const TRACE_MAX_REMOTES = clampInt(
  process.env.INVENTORY_TRACE_MAX_REMOTES,
  20,
  2000,
  600
);

const GITHUB_TOKEN = String(
  process.env.CAFEINA_COLLECTOR_GITHUB_TOKEN
    || process.env.AVATAR_DUMP_GITHUB_TOKEN
    || ""
).trim();
const GITHUB_REPO = String(
  process.env.CAFEINA_COLLECTOR_GITHUB_REPO
    || process.env.AVATAR_DUMP_GITHUB_REPO
    || "medeirospablo190-alt/Cafe-na-IA"
).trim();
const GITHUB_BRANCH = String(
  process.env.CAFEINA_COLLECTOR_GITHUB_BRANCH
    || process.env.AVATAR_DUMP_GITHUB_BRANCH
    || "main"
).trim();
const TRACE_GITHUB_BASE_PATH = String(
  process.env.INVENTORY_TRACE_GITHUB_PATH || "inventory-traces"
).trim().replace(/^\/+|\/+$/g, "");

const traceAttempts = new Map();

app.disable("x-powered-by");
app.set("trust proxy", 1);

installCollectorV3Routes(app);

app.get("/api/health", securityHeaders, (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json({
    ok: true,
    service: "CAFEINA_COLLECTOR_GATEWAY",
    legacyTrace: true,
    traceV3: true,
    githubMirrorConfigured: Boolean(GITHUB_TOKEN),
  });
});

app.get("/api/inventory-trace/health", securityHeaders, (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json({
    ok: true,
    service: "CAFEINA_INVENTORY_TRACE",
    githubMirrorConfigured: Boolean(GITHUB_TOKEN),
    maxRecords: TRACE_MAX_RECORDS,
    maxRemotes: TRACE_MAX_REMOTES,
  });
});

app.post(
  "/api/inventory-trace",
  express.json({ limit: "5mb", strict: true }),
  securityHeaders,
  handleInventoryTrace
);
app.get(
  "/api/inventory-trace/:placeId/latest",
  securityHeaders,
  handleLatestInventoryTrace
);
app.get(
  "/api/inventory-trace/:placeId/status",
  securityHeaders,
  handleInventoryTraceStatus
);

app.use((_req, res) => {
  jsonError(res, 404, "Rota não encontrada.");
});

const server = app.listen(PORT, () => {
  console.log(`CAFEINA Collector Gateway listening on :${PORT}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}

setInterval(() => {
  const now = Date.now();
  for (const [key, state] of traceAttempts) {
    if (now - state.windowStartedAt > TRACE_WINDOW_MS) {
      traceAttempts.delete(key);
    }
  }
}, 60_000).unref();

async function handleInventoryTrace(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (!consumeRate(
    traceAttempts,
    clientIpHash(req),
    TRACE_MAX_PER_WINDOW,
    TRACE_WINDOW_MS
  )) {
    return jsonError(
      res,
      429,
      "Muitas coletas enviadas. Aguarde e tente novamente."
    );
  }

  const body = req.body;
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return jsonError(res, 400, "Coleta inválida.");
  }

  const placeId = safeInteger(body.placeId);
  const gameId = safeInteger(body.gameId);
  if (!placeId || placeId < 1) {
    return jsonError(res, 400, "placeId inválido.");
  }

  const trace = body.trace;
  if (!trace || typeof trace !== "object" || Array.isArray(trace)) {
    return jsonError(res, 400, "Campo trace ausente.");
  }
  if (!Array.isArray(trace.records)) {
    return jsonError(res, 400, "trace.records deve ser uma lista.");
  }
  if (!Array.isArray(trace.remotes)) {
    return jsonError(res, 400, "trace.remotes deve ser uma lista.");
  }
  if (trace.records.length > TRACE_MAX_RECORDS) {
    return jsonError(
      res,
      413,
      `Muitos registros. Limite: ${TRACE_MAX_RECORDS}.`
    );
  }
  if (trace.remotes.length > TRACE_MAX_REMOTES) {
    return jsonError(
      res,
      413,
      `Muitos remotes. Limite: ${TRACE_MAX_REMOTES}.`
    );
  }

  const receivedAt = new Date().toISOString();
  const capturedAt = safeIsoDate(body.capturedAt) || receivedAt;
  const runId = String(trace.runId || body.runId || "").slice(0, 120);

  const normalized = {
    schemaVersion: Number.isInteger(body.schemaVersion)
      ? body.schemaVersion
      : 1,
    type: "inventory_remote_trace",
    userId: String(body.userId || "").slice(0, 30),
    username: String(body.username || "").slice(0, 80),
    capturedAt,
    serverReceivedAt: receivedAt,
    placeId,
    gameId,
    runId,
    trace,
  };

  const text = `${JSON.stringify(normalized, null, 2)}\n`;
  const stamp = receivedAt.replace(/[:.]/g, "-");
  const suffix = sha256(text).slice(0, 12);
  const fileName = `${stamp}_${suffix}.json`;
  const placeKey = String(placeId);
  const placeDir = path.join(INVENTORY_TRACE_DIR, placeKey);
  const historyPath = path.join(placeDir, fileName);
  const latestPath = path.join(placeDir, "latest.json");

  try {
    await fs.promises.mkdir(placeDir, { recursive: true });
    await fs.promises.writeFile(
      historyPath,
      text,
      { encoding: "utf-8", flag: "wx" }
    );
    await atomicWrite(latestPath, text);
  } catch (error) {
    console.error("INVENTORY_TRACE_WRITE_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível salvar a coleta.");
  }

  const github = await mirrorText(
    `${TRACE_GITHUB_BASE_PATH}/${placeKey}`,
    fileName,
    text,
    `Inventory trace ${placeKey} ${stamp}`,
    `Inventory trace latest ${placeKey}`
  );

  return res.status(201).json({
    ok: true,
    traceId: suffix,
    runId,
    placeId,
    receivedAt,
    file: fileName,
    latestUrl: `/api/inventory-trace/${encodeURIComponent(placeKey)}/latest`,
    github,
  });
}

async function handleLatestInventoryTrace(req, res) {
  res.setHeader("Cache-Control", "no-store");

  const placeId = String(req.params.placeId || "");
  if (!/^\d{1,20}$/.test(placeId)) {
    return jsonError(res, 404, "Coleta não encontrada.");
  }

  const local = await readLocalText(
    path.join(INVENTORY_TRACE_DIR, placeId, "latest.json")
  );
  if (local) {
    res.type("application/json; charset=utf-8");
    return res.send(local);
  }

  try {
    const remote = await readGitHubText(
      `${TRACE_GITHUB_BASE_PATH}/${placeId}/latest.json`
    );
    if (remote) {
      res.type("application/json; charset=utf-8");
      return res.send(remote);
    }
  } catch (error) {
    console.error(
      "INVENTORY_TRACE_GITHUB_READ_ERROR",
      error?.message || error
    );
  }

  return jsonError(
    res,
    404,
    "Nenhuma coleta encontrada para este PlaceId."
  );
}

async function handleInventoryTraceStatus(req, res) {
  res.setHeader("Cache-Control", "no-store");

  const placeId = String(req.params.placeId || "");
  if (!/^\d{1,20}$/.test(placeId)) {
    return jsonError(res, 404, "PlaceId inválido.");
  }

  const local = await exists(
    path.join(INVENTORY_TRACE_DIR, placeId, "latest.json")
  );

  return res.json({
    ok: true,
    placeId,
    local,
    githubMirrorConfigured: Boolean(GITHUB_TOKEN),
    latestUrl: `/api/inventory-trace/${encodeURIComponent(placeId)}/latest`,
  });
}

function consumeRate(store, key, maxPerWindow, windowMs) {
  const now = Date.now();
  const current = store.get(key);

  if (!current || now - current.windowStartedAt > windowMs) {
    store.set(key, { count: 1, windowStartedAt: now });
    return true;
  }

  if (current.count >= maxPerWindow) {
    return false;
  }

  current.count += 1;
  return true;
}

async function mirrorText(
  base,
  fileName,
  text,
  historyMessage,
  latestMessage
) {
  if (!GITHUB_TOKEN) {
    return { configured: false, mirrored: false };
  }

  try {
    await upsertGitHubText(
      `${base}/${fileName}`,
      text,
      historyMessage
    );
    await upsertGitHubText(
      `${base}/latest.json`,
      text,
      latestMessage
    );

    return {
      configured: true,
      mirrored: true,
      path: `${base}/latest.json`,
    };
  } catch (error) {
    console.error("GITHUB_MIRROR_ERROR", error?.message || error);
    return {
      configured: true,
      mirrored: false,
      error: "github_mirror_failed",
    };
  }
}

async function atomicWrite(target, content) {
  const tmp =
    `${target}.${process.pid}.${crypto.randomBytes(4).toString("hex")}.tmp`;

  await fs.promises.writeFile(tmp, content, "utf-8");
  await fs.promises.rename(tmp, target);
}

async function readLocalText(target) {
  try {
    return await fs.promises.readFile(target, "utf-8");
  } catch (error) {
    if (error?.code !== "ENOENT") {
      console.error("LOCAL_READ_ERROR", error?.message || error);
    }
    return null;
  }
}

async function exists(target) {
  try {
    await fs.promises.access(target);
    return true;
  } catch {
    return false;
  }
}

async function upsertGitHubText(repoPath, text, message) {
  if (!GITHUB_TOKEN) {
    throw new Error("GitHub token não configurado");
  }

  const { apiUrl } = githubLocation(repoPath);
  const headers = githubHeaders(true);

  let sha = null;
  const current = await fetch(
    `${apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`,
    { headers }
  );

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

  if (sha) {
    payload.sha = sha;
  }

  const response = await fetch(apiUrl, {
    method: "PUT",
    headers: {
      ...headers,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`GitHub PUT falhou: ${response.status}`);
  }
}

async function readGitHubText(repoPath) {
  const { apiUrl } = githubLocation(repoPath);
  const headers = githubHeaders(false);

  const response = await fetch(
    `${apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`,
    { headers }
  );

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new Error(`GitHub read falhou: ${response.status}`);
  }

  const data = await response.json();
  if (typeof data?.content !== "string") {
    return null;
  }

  return Buffer
    .from(data.content.replace(/\n/g, ""), "base64")
    .toString("utf-8");
}

function githubLocation(repoPath) {
  const match = /^([^/]+)\/([^/]+)$/.exec(GITHUB_REPO);
  if (!match) {
    throw new Error("CAFEINA_COLLECTOR_GITHUB_REPO inválido");
  }

  const [, owner, repo] = match;
  const encodedPath = repoPath
    .split("/")
    .filter(Boolean)
    .map(encodeURIComponent)
    .join("/");

  return {
    apiUrl:
      `https://api.github.com/repos/${encodeURIComponent(owner)}/` +
      `${encodeURIComponent(repo)}/contents/${encodedPath}`,
  };
}

function githubHeaders(authRequired) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "cafeina-collector-gateway",
  };

  if (GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${GITHUB_TOKEN}`;
  } else if (authRequired) {
    throw new Error("GitHub token não configurado");
  }

  return headers;
}

function securityHeaders(_req, res, next) {
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");

  if (process.env.NODE_ENV === "production") {
    res.setHeader(
      "Strict-Transport-Security",
      "max-age=31536000; includeSubDomains"
    );
  }

  next();
}

function jsonError(res, status, message, extra = {}) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(status).json({
    ok: false,
    message,
    ...extra,
  });
}

function clientIpHash(req) {
  return sha256(
    String(req.ip || req.socket?.remoteAddress || "unknown")
  );
}

function safeIsoDate(value) {
  if (typeof value !== "string" || value.length > 60) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? null
    : date.toISOString();
}

function safeInteger(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) ? n : null;
}

function sha256(value) {
  return crypto
    .createHash("sha256")
    .update(String(value))
    .digest("base64url");
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) {
    return fallback;
  }

  return Math.min(max, Math.max(min, Math.floor(n)));
}
