import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import http from "http";
import { spawn } from "child_process";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PUBLIC_PORT = Number(process.env.PORT || 3000);
const INTERNAL_PORT = Number(process.env.COLLECTOR_GATEWAY_INTERNAL_PORT || (PUBLIC_PORT >= 65533 ? 3101 : PUBLIC_PORT + 1));
const AVATAR_INTERNAL_PORT = Number(process.env.AVATAR_GATEWAY_INTERNAL_PORT || (INTERNAL_PORT >= 65534 ? 3102 : INTERNAL_PORT + 1));

const DOWNLOAD_DIR = path.resolve(process.env.DOWNLOAD_DIR || path.join(__dirname, "private-downloads"));
const TRACE_DIR = path.resolve(process.env.INVENTORY_TRACE_DIR || path.join(DOWNLOAD_DIR, "inventory-traces"));

const GITHUB_TOKEN = String(process.env.INVENTORY_TRACE_GITHUB_TOKEN || process.env.AVATAR_DUMP_GITHUB_TOKEN || "").trim();
const GITHUB_REPO = String(process.env.INVENTORY_TRACE_GITHUB_REPO || process.env.AVATAR_DUMP_GITHUB_REPO || "medeirospablo190-alt/Cafe-na-IA").trim();
const GITHUB_BRANCH = String(process.env.INVENTORY_TRACE_GITHUB_BRANCH || process.env.AVATAR_DUMP_GITHUB_BRANCH || "main").trim();
const GITHUB_BASE_PATH = String(process.env.INVENTORY_TRACE_GITHUB_PATH || "inventory-traces").trim().replace(/^\/+|\/+$/g, "");

const MAX_RECORDS = clampInt(process.env.INVENTORY_TRACE_MAX_RECORDS, 100, 10000, 4000);
const MAX_REMOTES = clampInt(process.env.INVENTORY_TRACE_MAX_REMOTES, 20, 2000, 600);
const MAX_PER_WINDOW = clampInt(process.env.INVENTORY_TRACE_MAX_PER_WINDOW, 1, 60, 12);
const WINDOW_MS = clampInt(process.env.INVENTORY_TRACE_WINDOW_SECONDS, 60, 3600, 600) * 1000;

const attempts = new Map();
let avatarChild = null;
let publicServer = null;

app.disable("x-powered-by");
app.set("trust proxy", 1);

app.post(
  "/api/inventory-trace",
  express.json({ limit: "5mb", strict: true }),
  securityHeaders,
  handleInventoryTrace
);
app.get("/api/inventory-trace/:placeId/latest", securityHeaders, handleLatestInventoryTrace);
app.get("/api/inventory-trace/:placeId/status", securityHeaders, handleInventoryTraceStatus);

app.use(proxyToAvatarGateway);

startAvatarGateway();
publicServer = app.listen(PUBLIC_PORT, () => {
  console.log(`GRUPO LUA Collector Gateway em :${PUBLIC_PORT} -> avatar :${INTERNAL_PORT}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => shutdown(signal));
}

async function handleInventoryTrace(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (!consumeRate(clientIpHash(req))) {
    return jsonError(res, 429, "Muitas coletas enviadas. Aguarde e tente novamente.");
  }

  const body = req.body;
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return jsonError(res, 400, "Coleta inválida.");
  }

  const placeId = safeInteger(body.placeId);
  const gameId = safeInteger(body.gameId);
  if (!placeId || placeId < 1) return jsonError(res, 400, "placeId inválido.");

  const trace = body.trace;
  if (!trace || typeof trace !== "object" || Array.isArray(trace)) {
    return jsonError(res, 400, "Campo trace ausente.");
  }

  if (!Array.isArray(trace.records)) return jsonError(res, 400, "trace.records deve ser uma lista.");
  if (!Array.isArray(trace.remotes)) return jsonError(res, 400, "trace.remotes deve ser uma lista.");
  if (trace.records.length > MAX_RECORDS) return jsonError(res, 413, `Muitos registros. Limite: ${MAX_RECORDS}.`);
  if (trace.remotes.length > MAX_REMOTES) return jsonError(res, 413, `Muitos remotes. Limite: ${MAX_REMOTES}.`);

  const now = new Date();
  const receivedAt = now.toISOString();
  const capturedAt = safeIsoDate(body.capturedAt) || receivedAt;
  const runId = String(trace.runId || body.runId || "").slice(0, 120);

  const normalized = {
    schemaVersion: Number.isInteger(body.schemaVersion) ? body.schemaVersion : 1,
    type: "inventory_remote_trace",
    userId: String(body.userId || "").slice(0, 30),
    username: String(body.username || "").slice(0, 80),
    capturedAt,
    serverReceivedAt: receivedAt,
    placeId,
    gameId,
    runId,
    trace
  };

  const text = `${JSON.stringify(normalized, null, 2)}\n`;
  const stamp = receivedAt.replace(/[:.]/g, "-");
  const suffix = sha256(text).slice(0, 12);
  const fileName = `${stamp}_${suffix}.json`;
  const placeKey = String(placeId);
  const placeDir = path.join(TRACE_DIR, placeKey);
  const historyPath = path.join(placeDir, fileName);
  const latestPath = path.join(placeDir, "latest.json");

  try {
    await fs.promises.mkdir(placeDir, { recursive: true });
    await fs.promises.writeFile(historyPath, text, { encoding: "utf-8", flag: "wx" });
    await atomicWrite(latestPath, text);
  } catch (error) {
    console.error("INVENTORY_TRACE_WRITE_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível salvar a coleta.");
  }

  let github = { configured: Boolean(GITHUB_TOKEN), mirrored: false };
  if (GITHUB_TOKEN) {
    try {
      const base = `${GITHUB_BASE_PATH}/${placeKey}`;
      await upsertGitHubText(`${base}/${fileName}`, text, `Inventory trace ${placeKey} ${stamp}`);
      await upsertGitHubText(`${base}/latest.json`, text, `Inventory trace latest ${placeKey}`);
      github = { configured: true, mirrored: true, path: `${base}/latest.json` };
    } catch (error) {
      console.error("INVENTORY_TRACE_GITHUB_ERROR", error?.message || error);
      github = { configured: true, mirrored: false, error: "github_mirror_failed" };
    }
  }

  return res.status(201).json({
    ok: true,
    traceId: suffix,
    runId,
    placeId,
    receivedAt,
    file: fileName,
    latestUrl: `/api/inventory-trace/${encodeURIComponent(placeKey)}/latest`,
    github
  });
}

async function handleLatestInventoryTrace(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const placeId = String(req.params.placeId || "");
  if (!/^\d{1,20}$/.test(placeId)) return jsonError(res, 404, "Coleta não encontrada.");

  const latestPath = path.join(TRACE_DIR, placeId, "latest.json");
  try {
    const text = await fs.promises.readFile(latestPath, "utf-8");
    res.type("application/json; charset=utf-8");
    return res.send(text);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      console.error("INVENTORY_TRACE_READ_ERROR", error?.message || error);
      return jsonError(res, 500, "Não foi possível ler a coleta.");
    }
  }

  try {
    const remote = await readGitHubText(`${GITHUB_BASE_PATH}/${placeId}/latest.json`);
    if (remote) {
      res.type("application/json; charset=utf-8");
      return res.send(remote);
    }
  } catch (error) {
    console.error("INVENTORY_TRACE_GITHUB_READ_ERROR", error?.message || error);
  }

  return jsonError(res, 404, "Nenhuma coleta encontrada para este PlaceId.");
}

async function handleInventoryTraceStatus(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const placeId = String(req.params.placeId || "");
  if (!/^\d{1,20}$/.test(placeId)) return jsonError(res, 404, "PlaceId inválido.");

  let local = false;
  try {
    await fs.promises.access(path.join(TRACE_DIR, placeId, "latest.json"));
    local = true;
  } catch {}

  return res.json({
    ok: true,
    placeId,
    local,
    githubMirrorConfigured: Boolean(GITHUB_TOKEN),
    latestUrl: `/api/inventory-trace/${encodeURIComponent(placeId)}/latest`
  });
}

function proxyToAvatarGateway(req, res) {
  const headers = { ...req.headers, host: `127.0.0.1:${INTERNAL_PORT}` };
  const proxy = http.request({
    host: "127.0.0.1",
    port: INTERNAL_PORT,
    method: req.method,
    path: req.originalUrl,
    headers
  }, (proxyRes) => {
    res.statusCode = proxyRes.statusCode || 502;
    for (const [name, value] of Object.entries(proxyRes.headers)) {
      if (value !== undefined) res.setHeader(name, value);
    }
    proxyRes.pipe(res);
  });

  proxy.on("error", (error) => {
    console.error("AVATAR_GATEWAY_PROXY_ERROR", error?.message || error);
    if (!res.headersSent) jsonError(res, 502, "Gateway interno indisponível.");
    else res.end();
  });

  req.pipe(proxy);
}

function startAvatarGateway() {
  const env = {
    ...process.env,
    PORT: String(INTERNAL_PORT),
    AVATAR_GATEWAY_INTERNAL_PORT: String(AVATAR_INTERNAL_PORT)
  };
  delete env.COLLECTOR_GATEWAY_INTERNAL_PORT;

  avatarChild = spawn(process.execPath, [path.join(__dirname, "avatar-gateway.js")], {
    cwd: __dirname,
    env,
    stdio: ["ignore", "inherit", "inherit"]
  });

  avatarChild.on("exit", (code, signal) => {
    console.error(`AVATAR_GATEWAY_CHILD_EXIT code=${code} signal=${signal || ""}`);
  });
}

function shutdown(signal) {
  try { avatarChild?.kill(signal); } catch {}
  publicServer?.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

function consumeRate(key) {
  const now = Date.now();
  const current = attempts.get(key);
  if (!current || now - current.windowStartedAt > WINDOW_MS) {
    attempts.set(key, { count: 1, windowStartedAt: now });
    return true;
  }
  if (current.count >= MAX_PER_WINDOW) return false;
  current.count += 1;
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [key, state] of attempts) {
    if (now - state.windowStartedAt > WINDOW_MS) attempts.delete(key);
  }
}, 60_000).unref();

async function atomicWrite(target, content) {
  const tmp = `${target}.${process.pid}.${crypto.randomBytes(4).toString("hex")}.tmp`;
  await fs.promises.writeFile(tmp, content, "utf-8");
  await fs.promises.rename(tmp, target);
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
    branch: GITHUB_BRANCH
  };
  if (sha) payload.sha = sha;

  const response = await fetch(apiUrl, {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) throw new Error(`GitHub PUT falhou: ${response.status}`);
}

async function readGitHubText(repoPath) {
  const { apiUrl } = githubLocation(repoPath);
  const headers = githubHeaders(false);
  const response = await fetch(`${apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`, { headers });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub read falhou: ${response.status}`);
  const data = await response.json();
  if (typeof data?.content !== "string") return null;
  return Buffer.from(data.content.replace(/\n/g, ""), "base64").toString("utf-8");
}

function githubLocation(repoPath) {
  const match = /^([^/]+)\/([^/]+)$/.exec(GITHUB_REPO);
  if (!match) throw new Error("INVENTORY_TRACE_GITHUB_REPO inválido");
  const [, owner, repo] = match;
  const encodedPath = repoPath.split("/").filter(Boolean).map(encodeURIComponent).join("/");
  return { apiUrl: `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${encodedPath}` };
}

function githubHeaders(authRequired) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "grupo-lua-inventory-trace"
  };
  if (GITHUB_TOKEN) headers.Authorization = `Bearer ${GITHUB_TOKEN}`;
  else if (authRequired) throw new Error("GitHub token não configurado");
  return headers;
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

function jsonError(res, status, message, extra = {}) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(status).json({ ok: false, message, ...extra });
}

function clientIpHash(req) {
  return sha256(String(req.ip || req.socket?.remoteAddress || "unknown"));
}

function safeIsoDate(value) {
  if (typeof value !== "string" || value.length > 60) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function safeInteger(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) ? n : null;
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("base64url");
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(n)));
}
