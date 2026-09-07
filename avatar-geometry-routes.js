import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DOWNLOAD_DIR = path.resolve(process.env.DOWNLOAD_DIR || path.join(__dirname, "private-downloads"));
const GEOMETRY_DIR = path.resolve(process.env.AVATAR_GEOMETRY_DIR || path.join(DOWNLOAD_DIR, "avatar-geometry"));
const UPLOAD_DIR = path.join(GEOMETRY_DIR, "uploads");

const UPLOAD_KEY = String(process.env.AVATAR_DUMP_KEY || "").trim();
const ALLOWED_USER_IDS = new Set(
  String(process.env.AVATAR_DUMP_ALLOWED_USER_IDS || "765329164")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => /^\d{1,20}$/.test(value))
);

const MAX_PACKAGE_BYTES = 96 * 1024 * 1024;
const MAX_MESHES = 60;
const MAX_CHUNKS = 256;
const MAX_CHUNK_CHARS = 600000;
const SESSION_MAX_AGE_MS = 2 * 60 * 60 * 1000;
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_MAX_STARTS = 8;
const startsByIp = new Map();

export function installAvatarGeometryRoutes(app) {
  app.post(
    "/api/avatar-geometry/start",
    express.json({ limit: "256kb", strict: true }),
    securityHeaders,
    handleStart
  );

  app.post(
    "/api/avatar-geometry/:uploadId/chunk",
    express.json({ limit: "900kb", strict: true }),
    securityHeaders,
    handleChunk
  );

  app.post(
    "/api/avatar-geometry/:uploadId/finish",
    express.json({ limit: "1mb", strict: true }),
    securityHeaders,
    handleFinish
  );

  app.get(
    "/api/avatar-geometry/:userId/latest",
    securityHeaders,
    handleLatest
  );

  app.get(
    "/api/avatar-geometry/:userId/status",
    securityHeaders,
    handleStatus
  );

  setInterval(cleanExpiredSessions, 15 * 60 * 1000).unref();
}

async function handleStart(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!authorized(req, res)) return;
  if (!consumeStartRate(clientKey(req))) {
    return jsonError(res, 429, "Muitas sessões de geometria. Tente novamente mais tarde.");
  }

  const userId = String(req.body?.userId || "");
  if (!validAllowedUserId(userId)) {
    return jsonError(res, 403, "UserId não autorizado.");
  }

  const expectedMeshes = Number(req.body?.expectedMeshes || 0);
  if (!Number.isInteger(expectedMeshes) || expectedMeshes < 0 || expectedMeshes > MAX_MESHES) {
    return jsonError(res, 400, "expectedMeshes inválido.");
  }

  const uploadId = crypto.randomBytes(24).toString("base64url");
  const dir = sessionDir(uploadId);
  const meta = {
    schemaVersion: 1,
    uploadId,
    userId,
    username: String(req.body?.username || "").slice(0, 80),
    capturedAt: safeIsoDate(req.body?.capturedAt) || new Date().toISOString(),
    startedAt: new Date().toISOString(),
    expectedMeshes
  };

  try {
    await fs.promises.mkdir(dir, { recursive: true });
    await fs.promises.writeFile(
      path.join(dir, "meta.json"),
      JSON.stringify(meta, null, 2) + "\n",
      "utf8"
    );
  } catch (error) {
    console.error("AVATAR_GEOMETRY_START_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível iniciar a coleta de geometria.");
  }

  return res.status(201).json({
    ok: true,
    uploadId,
    maxChunkChars: MAX_CHUNK_CHARS,
    maxMeshes: MAX_MESHES,
    maxChunks: MAX_CHUNKS
  });
}

async function handleChunk(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!authorized(req, res)) return;

  const uploadId = String(req.params.uploadId || "");
  if (!validUploadId(uploadId)) return jsonError(res, 404, "Sessão inválida.");

  const body = req.body || {};
  const meshIndex = Number(body.meshIndex);
  const chunkIndex = Number(body.chunkIndex);
  const totalChunks = Number(body.totalChunks);
  const data = body.data;

  if (!Number.isInteger(meshIndex) || meshIndex < 1 || meshIndex > MAX_MESHES) {
    return jsonError(res, 400, "meshIndex inválido.");
  }
  if (!Number.isInteger(chunkIndex) || chunkIndex < 1 || chunkIndex > MAX_CHUNKS) {
    return jsonError(res, 400, "chunkIndex inválido.");
  }
  if (!Number.isInteger(totalChunks) || totalChunks < 1 || totalChunks > MAX_CHUNKS || chunkIndex > totalChunks) {
    return jsonError(res, 400, "totalChunks inválido.");
  }
  if (typeof data !== "string" || data.length === 0 || data.length > MAX_CHUNK_CHARS) {
    return jsonError(res, 400, "Chunk inválido.");
  }

  const dir = sessionDir(uploadId);
  const meta = await readSessionMeta(dir);
  if (!meta) return jsonError(res, 404, "Sessão expirada ou inexistente.");
  if (!validAllowedUserId(String(meta.userId || ""))) {
    return jsonError(res, 403, "Sessão não autorizada.");
  }

  const prefix = "mesh-" + String(meshIndex).padStart(3, "0");
  const partFile = prefix + "-" + String(chunkIndex).padStart(4, "0") + ".part";
  const infoFile = prefix + ".info.json";
  const info = {
    meshIndex,
    totalChunks,
    partName: String(body.partName || "").slice(0, 240),
    meshId: String(body.meshId || "").slice(0, 240)
  };

  try {
    await fs.promises.writeFile(path.join(dir, partFile), data, "utf8");
    await atomicWrite(path.join(dir, infoFile), JSON.stringify(info, null, 2) + "\n");
  } catch (error) {
    console.error("AVATAR_GEOMETRY_CHUNK_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível salvar o chunk.");
  }

  return res.json({ ok: true, meshIndex, chunkIndex, totalChunks });
}

async function handleFinish(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!authorized(req, res)) return;

  const uploadId = String(req.params.uploadId || "");
  if (!validUploadId(uploadId)) return jsonError(res, 404, "Sessão inválida.");

  const dir = sessionDir(uploadId);
  const meta = await readSessionMeta(dir);
  if (!meta) return jsonError(res, 404, "Sessão expirada ou inexistente.");

  const userId = String(meta.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 403, "Sessão não autorizada.");

  let names;
  try {
    names = await fs.promises.readdir(dir);
  } catch {
    return jsonError(res, 404, "Sessão não encontrada.");
  }

  const infoNames = names
    .filter((name) => /^mesh-\d{3}\.info\.json$/.test(name))
    .sort();

  const meshes = [];
  let sourceChars = 0;

  try {
    for (const infoName of infoNames) {
      const info = JSON.parse(await fs.promises.readFile(path.join(dir, infoName), "utf8"));
      if (!Number.isInteger(info.totalChunks) || info.totalChunks < 1 || info.totalChunks > MAX_CHUNKS) {
        throw new Error("invalid_chunk_count");
      }

      const prefix = infoName.slice(0, -".info.json".length);
      const pieces = [];
      for (let index = 1; index <= info.totalChunks; index++) {
        const partFile = prefix + "-" + String(index).padStart(4, "0") + ".part";
        const piece = await fs.promises.readFile(path.join(dir, partFile), "utf8");
        sourceChars += piece.length;
        if (sourceChars > MAX_PACKAGE_BYTES) throw new Error("geometry_size_limit");
        pieces.push(piece);
      }

      const mesh = JSON.parse(pieces.join(""));
      validateMesh(mesh);
      meshes.push(mesh);
    }
  } catch (error) {
    console.error("AVATAR_GEOMETRY_FINISH_READ_ERROR", error?.message || error);
    return jsonError(res, 400, "Pacote de geometria incompleto ou inválido.");
  }

  const finishedAt = new Date().toISOString();
  const failed = Array.isArray(req.body?.failed)
    ? req.body.failed.slice(0, MAX_MESHES).map(sanitizeFailure)
    : [];

  const normalized = {
    schemaVersion: 1,
    userId,
    username: String(meta.username || "").slice(0, 80),
    capturedAt: safeIsoDate(meta.capturedAt) || finishedAt,
    serverReceivedAt: finishedAt,
    uploadId,
    expectedMeshes: safeInteger(meta.expectedMeshes),
    extractedMeshes: meshes.length,
    failed,
    meshes
  };

  const text = JSON.stringify(normalized) + "\n";
  const bytes = Buffer.byteLength(text, "utf8");
  if (bytes > MAX_PACKAGE_BYTES) {
    return jsonError(res, 413, "Pacote de geometria excedeu o limite.");
  }

  const userDir = path.join(GEOMETRY_DIR, userId);
  const stamp = finishedAt.replace(/[:.]/g, "-");
  const suffix = sha256(text).slice(0, 10);
  const historyPath = path.join(userDir, stamp + "_" + suffix + ".json");
  const latestPath = path.join(userDir, "latest.json");

  try {
    await fs.promises.mkdir(userDir, { recursive: true });
    await fs.promises.writeFile(historyPath, text, { encoding: "utf8", flag: "wx" });
    await atomicWrite(latestPath, text);
    await fs.promises.rm(dir, { recursive: true, force: true });
  } catch (error) {
    console.error("AVATAR_GEOMETRY_FINISH_WRITE_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível finalizar o pacote de geometria.");
  }

  return res.status(201).json({
    ok: true,
    userId,
    extractedMeshes: meshes.length,
    failedMeshes: failed.length,
    bytes,
    latestUrl: "/api/avatar-geometry/" + encodeURIComponent(userId) + "/latest"
  });
}

async function handleLatest(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "Geometria não encontrada.");

  const latestPath = path.join(GEOMETRY_DIR, userId, "latest.json");
  try {
    await fs.promises.access(latestPath);
    res.type("application/json; charset=utf-8");
    return fs.createReadStream(latestPath).pipe(res);
  } catch {
    return jsonError(res, 404, "Nenhuma geometria enviada para este UserId.");
  }
}

async function handleStatus(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "UserId não disponível.");

  const latestPath = path.join(GEOMETRY_DIR, userId, "latest.json");
  try {
    const stat = await fs.promises.stat(latestPath);
    return res.json({
      ok: true,
      userId,
      available: true,
      bytes: stat.size,
      latestUrl: "/api/avatar-geometry/" + encodeURIComponent(userId) + "/latest"
    });
  } catch {
    return res.json({
      ok: true,
      userId,
      available: false,
      latestUrl: "/api/avatar-geometry/" + encodeURIComponent(userId) + "/latest"
    });
  }
}

function validateMesh(mesh) {
  if (!mesh || typeof mesh !== "object" || Array.isArray(mesh)) throw new Error("mesh_invalid");
  if (!Array.isArray(mesh.positions) || !Array.isArray(mesh.faces)) throw new Error("mesh_arrays_missing");
  if (mesh.positions.length > 120000 || mesh.faces.length > 180000) throw new Error("mesh_limit");
  if (mesh.uvs && (!Array.isArray(mesh.uvs) || mesh.uvs.length > 240000)) throw new Error("uv_limit");
  if (mesh.normals && (!Array.isArray(mesh.normals) || mesh.normals.length > 240000)) throw new Error("normal_limit");
}

function sanitizeFailure(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return { error: String(value).slice(0, 800) };
  return {
    meshIndex: safeInteger(value.meshIndex),
    partName: String(value.partName || "").slice(0, 240),
    meshId: String(value.meshId || "").slice(0, 240),
    error: String(value.error || "").slice(0, 800)
  };
}

async function readSessionMeta(dir) {
  try {
    const meta = JSON.parse(await fs.promises.readFile(path.join(dir, "meta.json"), "utf8"));
    const started = new Date(meta.startedAt).getTime();
    if (!Number.isFinite(started) || Date.now() - started > SESSION_MAX_AGE_MS) {
      await fs.promises.rm(dir, { recursive: true, force: true }).catch(() => {});
      return null;
    }
    return meta;
  } catch {
    return null;
  }
}

async function cleanExpiredSessions() {
  let entries;
  try {
    entries = await fs.promises.readdir(UPLOAD_DIR, { withFileTypes: true });
  } catch {
    return;
  }
  await Promise.all(entries.filter((entry) => entry.isDirectory()).map(async (entry) => {
    const dir = path.join(UPLOAD_DIR, entry.name);
    const meta = await readSessionMeta(dir);
    if (!meta) await fs.promises.rm(dir, { recursive: true, force: true }).catch(() => {});
  }));
}

function authorized(req, res) {
  if (!UPLOAD_KEY) return true;
  const supplied = String(req.headers["x-avatar-dump-key"] || "");
  if (safeEqualText(supplied, UPLOAD_KEY)) return true;
  jsonError(res, 401, "Chave do coletor inválida.");
  return false;
}

function validAllowedUserId(userId) {
  return /^\d{1,20}$/.test(userId) && (!ALLOWED_USER_IDS.size || ALLOWED_USER_IDS.has(userId));
}

function validUploadId(value) {
  return /^[A-Za-z0-9_-]{20,80}$/.test(String(value || ""));
}

function sessionDir(uploadId) {
  return path.join(UPLOAD_DIR, uploadId);
}

function consumeStartRate(key) {
  const now = Date.now();
  const state = startsByIp.get(key);
  if (!state || now - state.startedAt > RATE_WINDOW_MS) {
    startsByIp.set(key, { count: 1, startedAt: now });
    return true;
  }
  if (state.count >= RATE_MAX_STARTS) return false;
  state.count += 1;
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [key, state] of startsByIp) {
    if (now - state.startedAt > RATE_WINDOW_MS) startsByIp.delete(key);
  }
}, 60_000).unref();

function clientKey(req) {
  return sha256(String(req.ip || req.socket?.remoteAddress || "unknown"));
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

function jsonError(res, status, message) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(status).json({ ok: false, message });
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

async function atomicWrite(target, content) {
  const tmp = target + "." + process.pid + "." + crypto.randomBytes(4).toString("hex") + ".tmp";
  await fs.promises.writeFile(tmp, content, "utf8");
  await fs.promises.rename(tmp, target);
}
