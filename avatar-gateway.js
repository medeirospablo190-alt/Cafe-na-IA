import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import http from "http";
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { installAvatarGeometryRoutes } from "./avatar-geometry-routes.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PUBLIC_PORT = Number(process.env.PORT || 3000);
const INTERNAL_PORT = Number(process.env.AVATAR_GATEWAY_INTERNAL_PORT || (PUBLIC_PORT >= 65534 ? 3101 : PUBLIC_PORT + 1));
const DOWNLOAD_DIR = path.resolve(process.env.DOWNLOAD_DIR || path.join(__dirname, "private-downloads"));
const AVATAR_DUMP_DIR = path.resolve(process.env.AVATAR_DUMP_DIR || path.join(DOWNLOAD_DIR, "avatar-dumps"));

const AVATAR_DUMP_KEY = String(process.env.AVATAR_DUMP_KEY || "").trim();
const ALLOWED_USER_IDS = new Set(
  String(process.env.AVATAR_DUMP_ALLOWED_USER_IDS || "765329164")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => /^\d{1,20}$/.test(value))
);
const MAX_PER_WINDOW = clampInt(process.env.AVATAR_DUMP_MAX_PER_WINDOW, 1, 60, 8);
const WINDOW_MS = clampInt(process.env.AVATAR_DUMP_WINDOW_SECONDS, 60, 3600, 600) * 1000;

const GITHUB_TOKEN = String(process.env.AVATAR_DUMP_GITHUB_TOKEN || "").trim();
const GITHUB_REPO = String(process.env.AVATAR_DUMP_GITHUB_REPO || "medeirospablo190-alt/Cafe-na-IA").trim();
const GITHUB_BRANCH = String(process.env.AVATAR_DUMP_GITHUB_BRANCH || "main").trim();
const GITHUB_BASE_PATH = String(process.env.AVATAR_DUMP_GITHUB_PATH || "avatar-dumps").trim().replace(/^\/+|\/+$/g, "");

const attempts = new Map();
let portalChild = null;
let publicServer = null;

app.disable("x-powered-by");
app.set("trust proxy", 1);

installAvatarGeometryRoutes(app);

app.post("/api/avatar-dump", express.json({ limit: "4mb", strict: true }), avatarSecurityHeaders, handleAvatarDump);
app.get("/api/avatar-dump/:userId/latest", avatarSecurityHeaders, handleLatestAvatarDump);
app.get("/api/avatar-dump/:userId/status", avatarSecurityHeaders, handleAvatarDumpStatus);

// Everything that is not part of the avatar collector is streamed to the
// existing portal server, preserving current download/auth behavior.
app.use(proxyToPortal);

startPortal();
publicServer = app.listen(PUBLIC_PORT, () => {
  console.log(`GRUPO LUA Avatar Gateway em :${PUBLIC_PORT} -> portal :${INTERNAL_PORT}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => shutdown(signal));
}

async function handleAvatarDump(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (AVATAR_DUMP_KEY) {
    const supplied = String(req.headers["x-avatar-dump-key"] || "");
    if (!safeEqualText(supplied, AVATAR_DUMP_KEY)) return jsonError(res, 401, "Chave do coletor inválida.");
  }

  if (!consumeRate(clientIpHash(req))) {
    return jsonError(res, 429, "Muitos dumps enviados. Tente novamente mais tarde.");
  }

  const body = req.body;
  if (!body || typeof body !== "object" || Array.isArray(body)) return jsonError(res, 400, "Dump inválido.");

  const userId = String(body.userId || "");
  if (!/^\d{1,20}$/.test(userId)) return jsonError(res, 400, "userId inválido.");
  if (ALLOWED_USER_IDS.size && !ALLOWED_USER_IDS.has(userId)) return jsonError(res, 403, "Este UserId não está autorizado para coleta.");
  if (!body.avatar || typeof body.avatar !== "object" || Array.isArray(body.avatar)) return jsonError(res, 400, "Campo avatar ausente.");

  const now = new Date();
  const receivedAt = now.toISOString();
  const capturedAt = safeIsoDate(body.capturedAt) || receivedAt;

  const normalized = {
    schemaVersion: Number.isInteger(body.schemaVersion) ? body.schemaVersion : 1,
    userId,
    username: String(body.username || "").slice(0, 80),
    capturedAt,
    serverReceivedAt: receivedAt,
    placeId: safeInteger(body.placeId),
    gameId: safeInteger(body.gameId),
    avatar: body.avatar
  };

  const text = `${JSON.stringify(normalized, null, 2)}\n`;
  const stamp = receivedAt.replace(/[:.]/g, "-");
  const suffix = sha256(text).slice(0, 10);
  const fileName = `${stamp}_${suffix}.json`;
  const userDir = path.join(AVATAR_DUMP_DIR, userId);
  const historyPath = path.join(userDir, fileName);
  const latestPath = path.join(userDir, "latest.json");

  try {
    await fs.promises.mkdir(userDir, { recursive: true });
    await fs.promises.writeFile(historyPath, text, { encoding: "utf-8", flag: "wx" });
    await atomicWrite(latestPath, text);
  } catch (error) {
    console.error("AVATAR_DUMP_WRITE_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível salvar o dump.");
  }

  let github = { configured: Boolean(GITHUB_TOKEN), mirrored: false };
  if (GITHUB_TOKEN) {
    try {
      const base = `${GITHUB_BASE_PATH}/${userId}`;
      await upsertGitHubText(`${base}/${fileName}`, text, `Avatar dump ${userId} ${stamp}`);
      await upsertGitHubText(`${base}/latest.json`, text, `Avatar dump latest ${userId}`);
      github = { configured: true, mirrored: true, path: `${base}/latest.json` };
    } catch (error) {
      console.error("AVATAR_DUMP_GITHUB_ERROR", error?.message || error);
      github = { configured: true, mirrored: false, error: "github_mirror_failed" };
    }
  }

  return res.status(201).json({
    ok: true,
    userId,
    capturedAt,
    receivedAt,
    file: fileName,
    latestUrl: `/api/avatar-dump/${encodeURIComponent(userId)}/latest`,
    github
  });
}

async function handleLatestAvatarDump(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "Dump não encontrado.");

  const latestPath = path.join(AVATAR_DUMP_DIR, userId, "latest.json");
  try {
    const text = await fs.promises.readFile(latestPath, "utf-8");
    res.type("application/json; charset=utf-8");
    return res.send(text);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      console.error("AVATAR_DUMP_READ_ERROR", error?.message || error);
      return jsonError(res, 500, "Não foi possível ler o dump.");
    }
  }

  // If the local Render disk was recreated but GitHub mirroring is enabled,
  // recover latest.json directly from the configured repository.
  try {
    const remote = await readGitHubText(`${GITHUB_BASE_PATH}/${userId}/latest.json`);
    if (remote) {
      res.type("application/json; charset=utf-8");
      return res.send(remote);
    }
  } catch (error) {
    console.error("AVATAR_DUMP_GITHUB_READ_ERROR", error?.message || error);
  }

  return jsonError(res, 404, "Nenhum dump encontrado para este UserId.");
}

async function handleAvatarDumpStatus(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "UserId não disponível.");

  let local = false;
  try {
    await fs.promises.access(path.join(AVATAR_DUMP_DIR, userId, "latest.json"));
    local = true;
  } catch {}

  return res.json({
    ok: true,
    userId,
    local,
    githubMirrorConfigured: Boolean(GITHUB_TOKEN),
    latestUrl: `/api/avatar-dump/${encodeURIComponent(userId)}/latest`
  });
}

function proxyToPortal(req, res) {
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
    console.error("PORTAL_PROXY_ERROR", error?.message || error);
    if (!res.headersSent) jsonError(res, 502, "Portal interno indisponível.");
    else res.end();
  });

  req.pipe(proxy);
}

function startPortal() {
  const env = { ...process.env, PORT: String(INTERNAL_PORT) };
  delete env.AVATAR_GATEWAY_INTERNAL_PORT;
  portalChild = spawn(process.execPath, [path.join(__dirname, "server.js")], {
    cwd: __dirname,
    env,
    stdio: ["ignore", "inherit", "inherit"]
  });

  portalChild.on("exit", (code, signal) => {
    console.error(`PORTAL_CHILD_EXIT code=${code} signal=${signal || ""}`);
  });
}

function shutdown(signal) {
  try { portalChild?.kill(signal); } catch {}
  publicServer?.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

function validAllowedUserId(userId) {
  return /^\d{1,20}$/.test(userId) && (!ALLOWED_USER_IDS.size || ALLOWED_USER_IDS.has(userId));
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
  const location = githubLocation(repoPath);
  const headers = githubHeaders(true);

  let sha = null;
  const current = await fetch(`${location.apiUrl}?ref=${encodeURIComponent(GITHUB_BRANCH)}`, { headers });
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

  const response = await fetch(location.apiUrl, {
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
  if (!match) throw new Error("AVATAR_DUMP_GITHUB_REPO inválido");
  const [, owner, repo] = match;
  const encodedPath = repoPath.split("/").filter(Boolean).map(encodeURIComponent).join("/");
  return { apiUrl: `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${encodedPath}` };
}

function githubHeaders(authRequired) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "grupo-lua-avatar-dump"
  };
  if (GITHUB_TOKEN) headers.Authorization = `Bearer ${GITHUB_TOKEN}`;
  else if (authRequired) throw new Error("GitHub token não configurado");
  return headers;
}

function avatarSecurityHeaders(_req, res, next) {
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

function safeEqualText(a, b) {
  const left = Buffer.from(String(a || ""));
  const right = Buffer.from(String(b || ""));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
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
