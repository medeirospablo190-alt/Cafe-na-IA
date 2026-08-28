import express from "express";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

const PORT = Number(process.env.PORT || 10000);
const PUBLIC_DIR = path.join(__dirname, "public");
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");
const UPLOAD_DIR = path.join(DATA_DIR, "uploads");
const SESSION_DIR = path.join(DATA_DIR, "sessions");

const UPLOAD_TOKEN = String(process.env.UPLOAD_TOKEN || "");
const MAX_CHUNK_BYTES = Number(process.env.MAX_CHUNK_BYTES || 6_000_000);
const MAX_FINAL_BYTES = Number(process.env.MAX_FINAL_BYTES || 300_000_000);
const SESSION_TTL_MS = Number(process.env.SESSION_TTL_MS || 6 * 60 * 60 * 1000);
const CLEANUP_INTERVAL_MS = Number(process.env.CLEANUP_INTERVAL_MS || 30 * 60 * 1000);
const PREVIEW_BYTES = Number(process.env.PREVIEW_BYTES || 300_000);

fs.mkdirSync(UPLOAD_DIR, { recursive: true });
fs.mkdirSync(SESSION_DIR, { recursive: true });

app.disable("x-powered-by");
app.set("trust proxy", true);

app.use(express.json({
  limit: Math.max(MAX_CHUNK_BYTES + 1_000_000, 8_000_000)
}));

app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  if (
    req.path === "/" ||
    req.path.endsWith(".html") ||
    req.path.endsWith(".js") ||
    req.path.endsWith(".css")
  ) {
    res.setHeader("Cache-Control", "no-store, max-age=0");
  }
  next();
});

app.use(express.static(PUBLIC_DIR, {
  index: false,
  fallthrough: true
}));

function sanitizeFileName(name) {
  let safe = String(name || "scan.json")
    .replace(/[\\/:*?"<>|]/g, "_")
    .replace(/\s+/g, "_")
    .replace(/\.\.+/g, ".")
    .replace(/^\.*/, "");

  if (!safe) safe = "scan.json";
  if (!safe.toLowerCase().endsWith(".json")) safe += ".json";

  return safe.slice(0, 140);
}

function buildUniqueFileName(fileName) {
  const safe = sanitizeFileName(fileName);
  const ext = path.extname(safe) || ".json";
  const base = path.basename(safe, ext);
  const stamp = Date.now().toString(36);
  const random = crypto.randomBytes(4).toString("hex");
  return `${base}_${stamp}_${random}${ext}`;
}

function safeUploadId(value) {
  const id = String(value || "");
  return /^[a-f0-9]{32}$/i.test(id) ? id : null;
}

function safeStoredFile(value) {
  const name = path.basename(String(value || ""));
  if (!name || name === "." || name === "..") return null;
  return name;
}

function tokenFromRequest(req) {
  return String(
    req.body?.token ??
    req.headers["x-upload-token"] ??
    ""
  );
}

function validateToken(req) {
  if (!UPLOAD_TOKEN) return true;

  const received = tokenFromRequest(req);
  if (received.length !== UPLOAD_TOKEN.length) return false;

  try {
    return crypto.timingSafeEqual(
      Buffer.from(received),
      Buffer.from(UPLOAD_TOKEN)
    );
  } catch {
    return false;
  }
}

function requireUploadToken(req, res) {
  if (validateToken(req)) return true;

  res.status(401).json({
    ok: false,
    success: false,
    message: "Token de upload inválido."
  });
  return false;
}

function publicBaseUrl(req) {
  const forwarded = req.headers["x-forwarded-proto"];
  const protocol =
    typeof forwarded === "string"
      ? forwarded.split(",")[0].trim()
      : req.protocol || "https";

  return `${protocol}://${req.get("host")}`;
}

function sessionPath(uploadId) {
  return path.join(SESSION_DIR, uploadId);
}

function manifestPath(uploadId) {
  return path.join(sessionPath(uploadId), "manifest.json");
}

function chunkPath(uploadId, index) {
  return path.join(
    sessionPath(uploadId),
    `chunk-${String(index).padStart(6, "0")}.json`
  );
}

function readManifest(uploadId) {
  const file = manifestPath(uploadId);
  if (!fs.existsSync(file)) return null;

  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function writeManifest(uploadId, manifest) {
  fs.writeFileSync(
    manifestPath(uploadId),
    JSON.stringify(manifest, null, 2),
    "utf8"
  );
}

function hashText(text) {
  return crypto
    .createHash("sha256")
    .update(text, "utf8")
    .digest("hex");
}

function removeDirectorySafe(directory) {
  try {
    fs.rmSync(directory, {
      recursive: true,
      force: true
    });
  } catch (error) {
    console.error("CLEANUP ERROR:", error);
  }
}

function cleanupExpiredSessions() {
  let entries;

  try {
    entries = fs.readdirSync(SESSION_DIR, {
      withFileTypes: true
    });
  } catch {
    return;
  }

  const now = Date.now();

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const directory = path.join(SESSION_DIR, entry.name);

    try {
      const stat = fs.statSync(directory);

      if (now - stat.mtimeMs > SESSION_TTL_MS) {
        removeDirectorySafe(directory);
      }
    } catch {}
  }
}

function validateChunkSet(uploadId, totalChunks) {
  let bytes = 0;

  for (let index = 1; index <= totalChunks; index++) {
    const file = chunkPath(uploadId, index);

    if (!fs.existsSync(file)) {
      return {
        ok: false,
        missing: index,
        bytes
      };
    }

    bytes += fs.statSync(file).size;

    if (bytes > MAX_FINAL_BYTES) {
      return {
        ok: false,
        tooLarge: true,
        bytes
      };
    }
  }

  return {
    ok: true,
    bytes
  };
}

async function writeWithBackpressure(stream, text) {
  if (stream.write(text)) return;

  await new Promise((resolve, reject) => {
    const cleanup = () => {
      stream.off("drain", onDrain);
      stream.off("error", onError);
    };

    const onDrain = () => {
      cleanup();
      resolve();
    };

    const onError = (error) => {
      cleanup();
      reject(error);
    };

    stream.once("drain", onDrain);
    stream.once("error", onError);
  });
}

async function finishStream(stream) {
  await new Promise((resolve, reject) => {
    stream.once("finish", resolve);
    stream.once("error", reject);
    stream.end();
  });
}

function getStoredFiles(req) {
  let entries;

  try {
    entries = fs.readdirSync(UPLOAD_DIR, {
      withFileTypes: true
    });
  } catch {
    return [];
  }

  return entries
    .filter((entry) =>
      entry.isFile() &&
      entry.name !== ".gitkeep" &&
      !entry.name.endsWith(".tmp")
    )
    .map((entry) => {
      try {
        const filePath = path.join(UPLOAD_DIR, entry.name);
        const stat = fs.statSync(filePath);
        const encoded = encodeURIComponent(entry.name);

        let area = null;
        let records = null;
        let source = null;
        let placeId = null;

        try {
          const fd = fs.openSync(filePath, "r");
          const buffer = Buffer.alloc(Math.min(stat.size, 64_000));
          const read = fs.readSync(fd, buffer, 0, buffer.length, 0);
          fs.closeSync(fd);

          const head = buffer.subarray(0, read).toString("utf8");

          const areaMatch = head.match(/"area"\s*:\s*"([^"]+)"/);
          const recordsMatch = head.match(/"records"\s*:\s*(\d+)/);
          const sourceMatch = head.match(/"source"\s*:\s*"([^"]+)"/);
          const placeMatch = head.match(/"placeId"\s*:\s*"?([^",}\s]+)"?/i);

          if (areaMatch) area = areaMatch[1];
          if (recordsMatch) records = Number(recordsMatch[1]);
          if (sourceMatch) source = sourceMatch[1];
          if (placeMatch) placeId = placeMatch[1];
        } catch {}

        return {
          name: entry.name,
          filename: entry.name,
          bytes: stat.size,
          size: stat.size,
          createdAt: stat.birthtime.toISOString(),
          modifiedAt: stat.mtime.toISOString(),
          area,
          records,
          source,
          placeId,
          downloadUrl: `${publicBaseUrl(req)}/files/${encoded}`,
          previewUrl: `${publicBaseUrl(req)}/api/files/${encoded}/preview`
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) =>
      new Date(b.modifiedAt) - new Date(a.modifiedAt)
    );
}

app.get("/", (_req, res) => {
  const indexFile = path.join(PUBLIC_DIR, "index.html");

  if (!fs.existsSync(indexFile)) {
    return res.status(503).send("public/index.html não encontrado.");
  }

  return res.sendFile(indexFile);
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    success: true,
    service: "CAFEINA",
    scannerUpload: true,
    files: true,
    chunkUpload: true,
    uploadStatus: true,
    downloads: true,
    diagnostics: false,
    ai: false,
    storage: {
      type: "local",
      persistent: Boolean(process.env.DATA_DIR),
      dataDir: DATA_DIR
    },
    limits: {
      maxChunkBytes: MAX_CHUNK_BYTES,
      maxFinalBytes: MAX_FINAL_BYTES,
      sessionTtlMs: SESSION_TTL_MS
    },
    uptime: process.uptime()
  });
});

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    success: true,
    scannerUpload: true,
    files: true,
    diagnostics: false,
    ai: false
  });
});

app.get("/api/files", (req, res) => {
  try {
    const files = getStoredFiles(req);
    const totalBytes = files.reduce(
      (sum, file) => sum + Number(file.bytes || 0),
      0
    );

    return res.json({
      ok: true,
      success: true,
      count: files.length,
      totalBytes,
      files
    });
  } catch (error) {
    console.error("FILE LIST ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao listar arquivos."
    });
  }
});

app.get("/api/scans", (req, res) => {
  try {
    const files = getStoredFiles(req);

    return res.json({
      ok: true,
      success: true,
      count: files.length,
      files
    });
  } catch (error) {
    console.error("SCAN LIST ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao listar arquivos."
    });
  }
});

app.get("/api/files/:filename/preview", async (req, res) => {
  try {
    const requested = safeStoredFile(req.params.filename);

    if (!requested) {
      return res.status(400).json({
        ok: false,
        success: false,
        message: "Nome de arquivo inválido."
      });
    }

    const filePath = path.join(UPLOAD_DIR, requested);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
        ok: false,
        success: false,
        message: "Arquivo não encontrado."
      });
    }

    const stat = await fsp.stat(filePath);
    const handle = await fsp.open(filePath, "r");

    try {
      const length = Math.min(stat.size, PREVIEW_BYTES);
      const buffer = Buffer.alloc(length);
      const result = await handle.read(buffer, 0, length, 0);
      const content = buffer
        .subarray(0, result.bytesRead)
        .toString("utf8");

      return res.json({
        ok: true,
        success: true,
        name: requested,
        bytes: stat.size,
        truncated: stat.size > result.bytesRead,
        content
      });
    } finally {
      await handle.close();
    }
  } catch (error) {
    console.error("PREVIEW ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao visualizar arquivo."
    });
  }
});

app.get("/api/scans/:filename", async (req, res) => {
  req.params.filename = req.params.filename;
  const requested = safeStoredFile(req.params.filename);

  if (!requested) {
    return res.status(400).json({
      ok: false,
      success: false,
      message: "Nome de arquivo inválido."
    });
  }

  const filePath = path.join(UPLOAD_DIR, requested);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({
      ok: false,
      success: false,
      message: "Arquivo não encontrado."
    });
  }

  try {
    const stat = await fsp.stat(filePath);
    const handle = await fsp.open(filePath, "r");

    try {
      const length = Math.min(stat.size, PREVIEW_BYTES);
      const buffer = Buffer.alloc(length);
      const result = await handle.read(buffer, 0, length, 0);

      return res.json({
        ok: true,
        success: true,
        name: requested,
        bytes: stat.size,
        truncated: stat.size > result.bytesRead,
        content: buffer
          .subarray(0, result.bytesRead)
          .toString("utf8")
      });
    } finally {
      await handle.close();
    }
  } catch (error) {
    console.error("SCAN PREVIEW ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao visualizar arquivo."
    });
  }
});

app.get("/api/scans/:filename/download", (req, res) => {
  const requested = safeStoredFile(req.params.filename);

  if (!requested) {
    return res.status(400).json({
      ok: false,
      success: false,
      message: "Nome de arquivo inválido."
    });
  }

  const filePath = path.join(UPLOAD_DIR, requested);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({
      ok: false,
      success: false,
      message: "Arquivo não encontrado."
    });
  }

  return res.download(filePath, requested);
});

app.post("/upload/start", (req, res) => {
  try {
    cleanupExpiredSessions();

    if (!requireUploadToken(req, res)) return;

    const filename = sanitizeFileName(req.body?.filename);
    const source = String(
      req.body?.source || "cafeina-area-upload"
    ).slice(0, 120);

    const metadata =
      req.body?.metadata &&
      typeof req.body.metadata === "object" &&
      !Array.isArray(req.body.metadata)
        ? req.body.metadata
        : {};

    const uploadId = crypto
      .randomBytes(16)
      .toString("hex");

    fs.mkdirSync(sessionPath(uploadId), {
      recursive: true
    });

    writeManifest(uploadId, {
      uploadId,
      filename,
      source,
      metadata,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      chunks: {},
      chunkCount: 0,
      objectCount: 0,
      receivedBytes: 0,
      finished: false
    });

    return res.status(201).json({
      ok: true,
      success: true,
      uploadId,
      filename,
      limits: {
        maxChunkBytes: MAX_CHUNK_BYTES,
        maxFinalBytes: MAX_FINAL_BYTES
      }
    });
  } catch (error) {
    console.error("UPLOAD START ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao iniciar upload."
    });
  }
});

app.get("/api/uploads/:uploadId", (req, res) => {
  const uploadId = safeUploadId(req.params.uploadId);

  if (!uploadId) {
    return res.status(400).json({
      ok: false,
      success: false,
      message: "uploadId inválido."
    });
  }

  const manifest = readManifest(uploadId);

  if (!manifest) {
    return res.status(404).json({
      ok: false,
      success: false,
      message: "Sessão não encontrada."
    });
  }

  return res.json({
    ok: true,
    success: true,
    upload: {
      uploadId: manifest.uploadId,
      filename: manifest.filename,
      source: manifest.source,
      metadata: manifest.metadata,
      createdAt: manifest.createdAt,
      updatedAt: manifest.updatedAt,
      chunkCount: manifest.chunkCount || 0,
      objectCount: manifest.objectCount || 0,
      receivedBytes: manifest.receivedBytes || 0,
      finished: Boolean(manifest.finished)
    }
  });
});

app.post("/upload/chunk", (req, res) => {
  try {
    if (!requireUploadToken(req, res)) return;

    const uploadId = safeUploadId(req.body?.uploadId);
    const index = Number(req.body?.index);
    const objects = req.body?.objects;

    if (
      !uploadId ||
      !Number.isInteger(index) ||
      index < 1 ||
      !Array.isArray(objects)
    ) {
      return res.status(400).json({
        ok: false,
        success: false,
        message: "Chunk inválido."
      });
    }

    const manifest = readManifest(uploadId);

    if (!manifest) {
      return res.status(404).json({
        ok: false,
        success: false,
        message: "Sessão de upload não encontrada."
      });
    }

    if (manifest.finished) {
      return res.status(409).json({
        ok: false,
        success: false,
        message: "Sessão já finalizada."
      });
    }

    const encoded = JSON.stringify(objects);
    const byteLength = Buffer.byteLength(encoded, "utf8");

    if (byteLength > MAX_CHUNK_BYTES) {
      return res.status(413).json({
        ok: false,
        success: false,
        message: "Chunk acima do limite.",
        maxChunkBytes: MAX_CHUNK_BYTES,
        receivedBytes: byteLength
      });
    }

    const hash = hashText(encoded);
    const existing = manifest.chunks[String(index)];

    if (existing) {
      if (
        existing.sha256 === hash &&
        existing.bytes === byteLength
      ) {
        return res.json({
          ok: true,
          success: true,
          duplicate: true,
          uploadId,
          index,
          bytes: byteLength,
          objectCount: objects.length
        });
      }

      return res.status(409).json({
        ok: false,
        success: false,
        message: `Chunk ${index} já existe com conteúdo diferente.`
      });
    }

    const projectedBytes =
      Number(manifest.receivedBytes || 0) +
      byteLength;

    if (projectedBytes > MAX_FINAL_BYTES) {
      return res.status(413).json({
        ok: false,
        success: false,
        message: "Upload ultrapassaria o limite final.",
        maxFinalBytes: MAX_FINAL_BYTES,
        projectedBytes
      });
    }

    fs.writeFileSync(
      chunkPath(uploadId, index),
      encoded,
      "utf8"
    );

    manifest.chunks[String(index)] = {
      bytes: byteLength,
      objects: objects.length,
      sha256: hash,
      receivedAt: new Date().toISOString()
    };

    manifest.chunkCount =
      Number(manifest.chunkCount || 0) + 1;

    manifest.objectCount =
      Number(manifest.objectCount || 0) +
      objects.length;

    manifest.receivedBytes = projectedBytes;
    manifest.updatedAt = new Date().toISOString();

    writeManifest(uploadId, manifest);

    return res.json({
      ok: true,
      success: true,
      uploadId,
      index,
      bytes: byteLength,
      objectCount: objects.length,
      totals: {
        chunks: manifest.chunkCount,
        objects: manifest.objectCount,
        bytes: manifest.receivedBytes
      }
    });
  } catch (error) {
    console.error("UPLOAD CHUNK ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao salvar chunk."
    });
  }
});

app.post("/upload/finish", async (req, res) => {
  let tempPath = null;

  try {
    if (!requireUploadToken(req, res)) return;

    const uploadId = safeUploadId(req.body?.uploadId);
    const totalChunks = Number(req.body?.totalChunks);

    const summary =
      req.body?.summary &&
      typeof req.body.summary === "object" &&
      !Array.isArray(req.body.summary)
        ? req.body.summary
        : {};

    if (
      !uploadId ||
      !Number.isInteger(totalChunks) ||
      totalChunks < 1
    ) {
      return res.status(400).json({
        ok: false,
        success: false,
        message: "Finalização inválida."
      });
    }

    const manifest = readManifest(uploadId);

    if (!manifest) {
      return res.status(404).json({
        ok: false,
        success: false,
        message: "Sessão não encontrada."
      });
    }

    if (manifest.finished) {
      return res.status(409).json({
        ok: false,
        success: false,
        message: "Sessão já finalizada."
      });
    }

    const validation = validateChunkSet(
      uploadId,
      totalChunks
    );

    if (!validation.ok) {
      if (validation.tooLarge) {
        return res.status(413).json({
          ok: false,
          success: false,
          message: "Arquivo final acima do limite.",
          maxFinalBytes: MAX_FINAL_BYTES,
          receivedBytes: validation.bytes
        });
      }

      return res.status(409).json({
        ok: false,
        success: false,
        message: `Chunk ${validation.missing} ausente.`
      });
    }

    const storedFileName = buildUniqueFileName(
      manifest.filename
    );

    const finalPath = path.join(
      UPLOAD_DIR,
      storedFileName
    );

    tempPath = `${finalPath}.tmp`;

    const stream = fs.createWriteStream(
      tempPath,
      { encoding: "utf8" }
    );

    await writeWithBackpressure(stream, "{\n");
    await writeWithBackpressure(
      stream,
      `"uploadedAt":${JSON.stringify(new Date().toISOString())},\n`
    );
    await writeWithBackpressure(
      stream,
      `"source":${JSON.stringify(manifest.source)},\n`
    );
    await writeWithBackpressure(
      stream,
      `"metadata":${JSON.stringify(manifest.metadata)},\n`
    );
    await writeWithBackpressure(
      stream,
      `"summary":${JSON.stringify(summary)},\n`
    );
    await writeWithBackpressure(stream, '"objects":[\n');

    let firstObject = true;

    for (let index = 1; index <= totalChunks; index++) {
      const raw = await fsp.readFile(
        chunkPath(uploadId, index),
        "utf8"
      );

      const objects = JSON.parse(raw);

      if (!Array.isArray(objects)) {
        throw new Error(`Chunk ${index} inválido`);
      }

      for (const object of objects) {
        if (!firstObject) {
          await writeWithBackpressure(
            stream,
            ",\n"
          );
        }

        await writeWithBackpressure(
          stream,
          JSON.stringify(object)
        );

        firstObject = false;
      }
    }

    await writeWithBackpressure(
      stream,
      "\n]\n}"
    );

    await finishStream(stream);

    const finalSize = (
      await fsp.stat(tempPath)
    ).size;

    if (finalSize > MAX_FINAL_BYTES) {
      await fsp.rm(tempPath, { force: true });
      tempPath = null;

      return res.status(413).json({
        ok: false,
        success: false,
        message: "Arquivo final excedeu o limite.",
        finalBytes: finalSize,
        maxFinalBytes: MAX_FINAL_BYTES
      });
    }

    await fsp.rename(
      tempPath,
      finalPath
    );

    tempPath = null;

    const url =
      `${publicBaseUrl(req)}/files/` +
      encodeURIComponent(storedFileName);

    removeDirectorySafe(
      sessionPath(uploadId)
    );

    console.log(
      `[UPLOAD OK] ${storedFileName} | ${finalSize} bytes | ${manifest.objectCount || 0} registros`
    );

    return res.status(201).json({
      ok: true,
      success: true,
      filename: storedFileName,
      bytes: finalSize,
      objectCount: manifest.objectCount || 0,
      chunkCount: totalChunks,
      url,
      downloadUrl: url
    });
  } catch (error) {
    console.error("UPLOAD FINISH ERROR:", error);

    if (tempPath) {
      try {
        await fsp.rm(tempPath, {
          force: true
        });
      } catch {}
    }

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao montar arquivo final."
    });
  }
});

app.post("/upload/cancel", (req, res) => {
  if (!requireUploadToken(req, res)) return;

  const uploadId = safeUploadId(
    req.body?.uploadId
  );

  if (!uploadId) {
    return res.status(400).json({
      ok: false,
      success: false,
      message: "uploadId inválido."
    });
  }

  removeDirectorySafe(
    sessionPath(uploadId)
  );

  return res.json({
    ok: true,
    success: true,
    cancelled: true
  });
});

app.get("/files/:filename", (req, res) => {
  try {
    const requested = safeStoredFile(
      req.params.filename
    );

    if (!requested) {
      return res.status(400).json({
        ok: false,
        success: false,
        message: "Nome de arquivo inválido."
      });
    }

    const filePath = path.join(
      UPLOAD_DIR,
      requested
    );

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
        ok: false,
        success: false,
        message: "Arquivo não encontrado."
      });
    }

    return res.download(
      filePath,
      requested
    );
  } catch (error) {
    console.error("DOWNLOAD ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao baixar arquivo."
    });
  }
});

app.delete("/api/files/:filename", (req, res) => {
  try {
    if (!requireUploadToken(req, res)) return;

    const requested = safeStoredFile(
      req.params.filename
    );

    if (!requested) {
      return res.status(400).json({
        ok: false,
        success: false,
        message: "Nome inválido."
      });
    }

    const filePath = path.join(
      UPLOAD_DIR,
      requested
    );

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
        ok: false,
        success: false,
        message: "Arquivo não encontrado."
      });
    }

    fs.rmSync(filePath, {
      force: true
    });

    return res.json({
      ok: true,
      success: true,
      deleted: requested
    });
  } catch (error) {
    console.error("DELETE FILE ERROR:", error);

    return res.status(500).json({
      ok: false,
      success: false,
      message: "Erro ao excluir arquivo."
    });
  }
});

app.use((error, _req, res, next) => {
  if (res.headersSent) {
    return next(error);
  }

  if (error?.type === "entity.too.large") {
    return res.status(413).json({
      ok: false,
      success: false,
      message: "Requisição acima do limite permitido."
    });
  }

  console.error("UNHANDLED ERROR:", error);

  return res.status(500).json({
    ok: false,
    success: false,
    message: "Erro interno do servidor."
  });
});

app.use((_req, res) => {
  res.status(404).json({
    ok: false,
    success: false,
    message: "Rota não encontrada."
  });
});

cleanupExpiredSessions();

const cleanupTimer = setInterval(
  cleanupExpiredSessions,
  CLEANUP_INTERVAL_MS
);

cleanupTimer.unref?.();

app.listen(PORT, "0.0.0.0", () => {
  console.log("=================================");
  console.log("CAFEÍNA • SCANNER FILE RECEIVER");
  console.log(`Porta: ${PORT}`);
  console.log(`Dados: ${DATA_DIR}`);
  console.log(`Uploads: ${UPLOAD_DIR}`);
  console.log(`Chunk máximo: ${MAX_CHUNK_BYTES} bytes`);
  console.log(`Arquivo máximo: ${MAX_FINAL_BYTES} bytes`);
  console.log("Scanner: /upload/start → /upload/chunk → /upload/finish");
  console.log("Arquivos: /api/files");
  console.log("Diagnóstico: removido");
  console.log("OpenAI: removida");
  console.log("=================================");
});
