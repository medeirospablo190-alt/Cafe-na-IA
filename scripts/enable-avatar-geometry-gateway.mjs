import fs from "fs";

const file = "avatar-gateway.js";
let source = fs.readFileSync(file, "utf8");

if (source.includes("/api/avatar-geometry/start")) {
  console.log("Avatar geometry gateway already enabled.");
  process.exit(0);
}

const constMarker = 'const AVATAR_DUMP_DIR = path.resolve(process.env.AVATAR_DUMP_DIR || path.join(DOWNLOAD_DIR, "avatar-dumps"));\n';
const routeMarker = 'app.get("/api/avatar-dump/:userId/status", avatarSecurityHeaders, handleAvatarDumpStatus);\n';
const handlerMarker = '\nfunction proxyToPortal(req, res) {';

if (!source.includes(constMarker) || !source.includes(routeMarker) || !source.includes(handlerMarker)) {
  throw new Error("avatar-gateway.js layout changed; refusing unsafe patch");
}

source = source.replace(constMarker, constMarker + `const AVATAR_GEOMETRY_DIR = path.resolve(process.env.AVATAR_GEOMETRY_DIR || path.join(DOWNLOAD_DIR, "avatar-geometry"));
const AVATAR_GEOMETRY_UPLOAD_DIR = path.join(AVATAR_GEOMETRY_DIR, "uploads");
const AVATAR_GEOMETRY_MAX_BYTES = 96 * 1024 * 1024;
const AVATAR_GEOMETRY_MAX_MESHES = 60;
const AVATAR_GEOMETRY_MAX_CHUNKS = 256;
const AVATAR_GEOMETRY_MAX_CHUNK_CHARS = 600000;
`);

source = source.replace(routeMarker, routeMarker + `app.post("/api/avatar-geometry/start", express.json({ limit: "256kb", strict: true }), avatarSecurityHeaders, handleGeometryStart);
app.post("/api/avatar-geometry/:uploadId/chunk", express.json({ limit: "900kb", strict: true }), avatarSecurityHeaders, handleGeometryChunk);
app.post("/api/avatar-geometry/:uploadId/finish", express.json({ limit: "1mb", strict: true }), avatarSecurityHeaders, handleGeometryFinish);
app.get("/api/avatar-geometry/:userId/latest", avatarSecurityHeaders, handleLatestGeometry);
app.get("/api/avatar-geometry/:userId/status", avatarSecurityHeaders, handleGeometryStatus);
`);

const handlers = String.raw`

function validUploadId(value) {
  return /^[A-Za-z0-9_-]{20,80}$/.test(String(value || ""));
}

function geometrySessionDir(uploadId) {
  return path.join(AVATAR_GEOMETRY_UPLOAD_DIR, uploadId);
}

function geometryAuth(req, res) {
  if (!AVATAR_DUMP_KEY) return true;
  const supplied = String(req.headers["x-avatar-dump-key"] || "");
  if (safeEqualText(supplied, AVATAR_DUMP_KEY)) return true;
  jsonError(res, 401, "Chave do coletor inválida.");
  return false;
}

async function handleGeometryStart(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!geometryAuth(req, res)) return;
  if (!consumeRate(`geometry:${clientIpHash(req)}`)) {
    return jsonError(res, 429, "Muitas sessões de geometria. Tente novamente mais tarde.");
  }

  const body = req.body;
  const userId = String(body?.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 403, "UserId não autorizado.");

  const expectedMeshes = Number(body?.expectedMeshes || 0);
  if (!Number.isInteger(expectedMeshes) || expectedMeshes < 0 || expectedMeshes > AVATAR_GEOMETRY_MAX_MESHES) {
    return jsonError(res, 400, "expectedMeshes inválido.");
  }

  const uploadId = crypto.randomBytes(24).toString("base64url");
  const dir = geometrySessionDir(uploadId);
  const meta = {
    schemaVersion: 1,
    uploadId,
    userId,
    username: String(body?.username || "").slice(0, 80),
    capturedAt: safeIsoDate(body?.capturedAt) || new Date().toISOString(),
    startedAt: new Date().toISOString(),
    expectedMeshes
  };

  try {
    await fs.promises.mkdir(dir, { recursive: true });
    await fs.promises.writeFile(path.join(dir, "meta.json"), JSON.stringify(meta, null, 2) + "\n", "utf8");
  } catch (error) {
    console.error("AVATAR_GEOMETRY_START_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível iniciar a coleta de geometria.");
  }

  return res.status(201).json({
    ok: true,
    uploadId,
    maxChunkChars: AVATAR_GEOMETRY_MAX_CHUNK_CHARS,
    maxMeshes: AVATAR_GEOMETRY_MAX_MESHES,
    maxChunks: AVATAR_GEOMETRY_MAX_CHUNKS
  });
}

async function handleGeometryChunk(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!geometryAuth(req, res)) return;

  const uploadId = String(req.params.uploadId || "");
  if (!validUploadId(uploadId)) return jsonError(res, 404, "Sessão inválida.");

  const body = req.body || {};
  const meshIndex = Number(body.meshIndex);
  const chunkIndex = Number(body.chunkIndex);
  const totalChunks = Number(body.totalChunks);
  const data = body.data;

  if (!Number.isInteger(meshIndex) || meshIndex < 1 || meshIndex > AVATAR_GEOMETRY_MAX_MESHES) {
    return jsonError(res, 400, "meshIndex inválido.");
  }
  if (!Number.isInteger(chunkIndex) || chunkIndex < 1 || chunkIndex > AVATAR_GEOMETRY_MAX_CHUNKS) {
    return jsonError(res, 400, "chunkIndex inválido.");
  }
  if (!Number.isInteger(totalChunks) || totalChunks < 1 || totalChunks > AVATAR_GEOMETRY_MAX_CHUNKS || chunkIndex > totalChunks) {
    return jsonError(res, 400, "totalChunks inválido.");
  }
  if (typeof data !== "string" || data.length === 0 || data.length > AVATAR_GEOMETRY_MAX_CHUNK_CHARS) {
    return jsonError(res, 400, "Chunk inválido.");
  }

  const dir = geometrySessionDir(uploadId);
  let meta;
  try {
    meta = JSON.parse(await fs.promises.readFile(path.join(dir, "meta.json"), "utf8"));
  } catch {
    return jsonError(res, 404, "Sessão expirada ou inexistente.");
  }
  if (!validAllowedUserId(String(meta.userId || ""))) return jsonError(res, 403, "Sessão não autorizada.");

  const prefix = `mesh-${String(meshIndex).padStart(3, "0")}`;
  const info = {
    meshIndex,
    totalChunks,
    partName: String(body.partName || "").slice(0, 240),
    meshId: String(body.meshId || "").slice(0, 240)
  };

  try {
    await fs.promises.writeFile(path.join(dir, `${prefix}-${String(chunkIndex).padStart(4, "0")}.part`), data, "utf8");
    await atomicWrite(path.join(dir, `${prefix}.info.json`), JSON.stringify(info, null, 2) + "\n");
  } catch (error) {
    console.error("AVATAR_GEOMETRY_CHUNK_ERROR", error?.message || error);
    return jsonError(res, 500, "Não foi possível salvar o chunk.");
  }

  return res.json({ ok: true, meshIndex, chunkIndex, totalChunks });
}

async function handleGeometryFinish(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (!geometryAuth(req, res)) return;

  const uploadId = String(req.params.uploadId || "");
  if (!validUploadId(uploadId)) return jsonError(res, 404, "Sessão inválida.");
  const dir = geometrySessionDir(uploadId);

  let meta;
  try {
    meta = JSON.parse(await fs.promises.readFile(path.join(dir, "meta.json"), "utf8"));
  } catch {
    return jsonError(res, 404, "Sessão expirada ou inexistente.");
  }

  const userId = String(meta.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 403, "Sessão não autorizada.");

  let names;
  try {
    names = await fs.promises.readdir(dir);
  } catch {
    return jsonError(res, 404, "Sessão não encontrada.");
  }

  const infoNames = names.filter((name) => /^mesh-\d{3}\.info\.json$/.test(name)).sort();
  const meshes = [];
  let totalBytes = 0;

  try {
    for (const infoName of infoNames) {
      const info = JSON.parse(await fs.promises.readFile(path.join(dir, infoName), "utf8"));
      const prefix = infoName.slice(0, -".info.json".length);
      const pieces = [];
      for (let index = 1; index <= info.totalChunks; index++) {
        const partPath = path.join(dir, `${prefix}-${String(index).padStart(4, "0")}.part`);
        const piece = await fs.promises.readFile(partPath, "utf8");
        totalBytes += Buffer.byteLength(piece, "utf8");
        if (totalBytes > AVATAR_GEOMETRY_MAX_BYTES) throw new Error("geometry_size_limit");
        pieces.push(piece);
      }
      const mesh = JSON.parse(pieces.join(""));
      if (!mesh || typeof mesh !== "object" || Array.isArray(mesh)) throw new Error("mesh_invalid");
      meshes.push(mesh);
    }
  } catch (error) {
    console.error("AVATAR_GEOMETRY_FINISH_READ_ERROR", error?.message || error);
    return jsonError(res, 400, "Pacote de geometria incompleto ou inválido.");
  }

  const finishedAt = new Date().toISOString();
  const normalized = {
    schemaVersion: 1,
    userId,
    username: String(meta.username || "").slice(0, 80),
    capturedAt: safeIsoDate(meta.capturedAt) || finishedAt,
    serverReceivedAt: finishedAt,
    uploadId,
    expectedMeshes: safeInteger(meta.expectedMeshes),
    extractedMeshes: meshes.length,
    failed: Array.isArray(req.body?.failed) ? req.body.failed.slice(0, AVATAR_GEOMETRY_MAX_MESHES) : [],
    meshes
  };

  const text = JSON.stringify(normalized) + "\n";
  if (Buffer.byteLength(text, "utf8") > AVATAR_GEOMETRY_MAX_BYTES) {
    return jsonError(res, 413, "Pacote de geometria excedeu o limite.");
  }

  const userDir = path.join(AVATAR_GEOMETRY_DIR, userId);
  const stamp = finishedAt.replace(/[:.]/g, "-");
  const suffix = sha256(text).slice(0, 10);
  const historyPath = path.join(userDir, `${stamp}_${suffix}.json`);
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
    failedMeshes: normalized.failed.length,
    bytes: Buffer.byteLength(text, "utf8"),
    latestUrl: `/api/avatar-geometry/${encodeURIComponent(userId)}/latest`
  });
}

async function handleLatestGeometry(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "Geometria não encontrada.");
  const latestPath = path.join(AVATAR_GEOMETRY_DIR, userId, "latest.json");
  try {
    await fs.promises.access(latestPath);
    res.type("application/json; charset=utf-8");
    return fs.createReadStream(latestPath).pipe(res);
  } catch {
    return jsonError(res, 404, "Nenhuma geometria enviada para este UserId.");
  }
}

async function handleGeometryStatus(req, res) {
  res.setHeader("Cache-Control", "no-store");
  const userId = String(req.params.userId || "");
  if (!validAllowedUserId(userId)) return jsonError(res, 404, "UserId não disponível.");
  const latestPath = path.join(AVATAR_GEOMETRY_DIR, userId, "latest.json");
  try {
    const stat = await fs.promises.stat(latestPath);
    return res.json({ ok: true, userId, available: true, bytes: stat.size, latestUrl: `/api/avatar-geometry/${encodeURIComponent(userId)}/latest` });
  } catch {
    return res.json({ ok: true, userId, available: false, latestUrl: `/api/avatar-geometry/${encodeURIComponent(userId)}/latest` });
  }
}
`;

source = source.replace(handlerMarker, handlers + handlerMarker);
fs.writeFileSync(file, source, "utf8");
console.log("Avatar geometry gateway enabled.");
