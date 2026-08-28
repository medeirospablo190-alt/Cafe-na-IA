import express from "express";
import OpenAI from "openai";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const app = express();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================
// CONFIGURAÇÃO
// ============================================================

const PORT = Number(process.env.PORT || 10000);
const MODEL = process.env.OPENAI_MODEL || "gpt-5.4";

const PUBLIC_DIR = path.join(__dirname, "public");

const UPLOAD_DIR =
  process.env.UPLOAD_DIR ||
  path.join(__dirname, "uploads");

const SESSION_DIR =
  path.join(UPLOAD_DIR, "_sessions");

const UPLOAD_TOKEN =
  String(process.env.UPLOAD_TOKEN || "");

const MAX_CHUNK_BYTES =
  Number(process.env.MAX_CHUNK_BYTES || 6_000_000);

const MAX_FINAL_BYTES =
  Number(process.env.MAX_FINAL_BYTES || 300_000_000);

const SESSION_TTL_MS =
  Number(
    process.env.SESSION_TTL_MS ||
    6 * 60 * 60 * 1000
  );

const CLEANUP_INTERVAL_MS =
  Number(
    process.env.CLEANUP_INTERVAL_MS ||
    30 * 60 * 1000
  );

const MAX_CHAT_CHARS =
  Number(process.env.MAX_CHAT_CHARS || 2000);

const MAX_CHAT_OUTPUT_TOKENS =
  Number(process.env.MAX_CHAT_OUTPUT_TOKENS || 800);

// ============================================================
// DIRETÓRIOS
// ============================================================

fs.mkdirSync(UPLOAD_DIR, {
  recursive: true,
});

fs.mkdirSync(SESSION_DIR, {
  recursive: true,
});

// ============================================================
// EXPRESS
// ============================================================

app.disable("x-powered-by");
app.set("trust proxy", true);

app.use(
  express.json({
    limit: Math.max(
      MAX_CHUNK_BYTES + 1_000_000,
      8_000_000
    ),
  })
);

app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  if (req.path === "/" || req.path.endsWith(".html") || req.path.endsWith(".js") || req.path.endsWith(".css")) {
    res.setHeader("Cache-Control", "no-store, max-age=0");
  }
  next();
});

app.use(express.static(PUBLIC_DIR, { index: false, fallthrough: true }));

// ============================================================
// OPENAI
// ============================================================

let client = null;

if (process.env.OPENAI_API_KEY) {
  client = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
  });
}

const conversations = new Map();

// ============================================================
// DIAGNÓSTICOS
// ============================================================

const DIAGNOSTICS_DIR =
  path.join(UPLOAD_DIR, "_diagnostics");

const DIAGNOSTICS_FILE =
  path.join(DIAGNOSTICS_DIR, "diagnostics.jsonl");

const MAX_DIAGNOSTICS = 100;
const MAX_DIAGNOSTIC_MESSAGE = 6000;
const MAX_DIAGNOSTIC_TRACE = 12000;

fs.mkdirSync(DIAGNOSTICS_DIR, {
  recursive: true,
});

const diagnosticRate = new Map();

function cleanDiagnosticText(value, maxLength) {
  let text = String(value ?? "");

  // Redação básica para evitar gravar segredos acidentalmente.
  text = text
    .replace(
      /(sk-[A-Za-z0-9_-]{12,})/g,
      "[REDACTED_OPENAI_KEY]"
    )
    .replace(
      /(Bearer\s+)[A-Za-z0-9._~+\/=-]{12,}/gi,
      "$1[REDACTED]"
    )
    .replace(
      /(token["']?\s*[:=]\s*["']?)[A-Za-z0-9._~+\/=-]{12,}/gi,
      "$1[REDACTED]"
    );

  return text.slice(0, maxLength);
}

function readDiagnostics() {
  if (!fs.existsSync(DIAGNOSTICS_FILE)) {
    return [];
  }

  try {
    const lines = fs
      .readFileSync(DIAGNOSTICS_FILE, "utf8")
      .split(/\r?\n/)
      .filter(Boolean);

    return lines
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean)
      .slice(-MAX_DIAGNOSTICS)
      .reverse();
  } catch {
    return [];
  }
}

function appendDiagnostic(item) {
  fs.appendFileSync(
    DIAGNOSTICS_FILE,
    JSON.stringify(item) + "\n",
    "utf8"
  );

  const all = readDiagnostics();

  if (all.length > MAX_DIAGNOSTICS) {
    const keep = all
      .slice(0, MAX_DIAGNOSTICS)
      .reverse();

    fs.writeFileSync(
      DIAGNOSTICS_FILE,
      keep
        .map((entry) => JSON.stringify(entry))
        .join("\n") + "\n",
      "utf8"
    );
  }
}

function allowDiagnosticRequest(req) {
  const ip =
    String(
      req.headers["x-forwarded-for"] ||
      req.socket?.remoteAddress ||
      "unknown"
    )
      .split(",")[0]
      .trim();

  const now = Date.now();
  const previous =
    diagnosticRate.get(ip) || [];

  const recent =
    previous.filter(
      (timestamp) =>
        now - timestamp < 60_000
    );

  // Até 30 diagnósticos por minuto por IP.
  if (recent.length >= 30) {
    diagnosticRate.set(ip, recent);
    return false;
  }

  recent.push(now);
  diagnosticRate.set(ip, recent);
  return true;
}


// ============================================================
// HELPERS
// ============================================================

function sanitizeFileName(name) {
  let safe = String(name || "export.json")
    .replace(/[\\/:*?"<>|]/g, "_")
    .replace(/\s+/g, "_")
    .replace(/\.\.+/g, ".")
    .replace(/^\.*/, "");

  if (!safe) {
    safe = "export.json";
  }

  if (!safe.toLowerCase().endsWith(".json")) {
    safe += ".json";
  }

  return safe.slice(0, 120);
}

function tokenFromRequest(req) {
  return String(
    req.body?.token ??
    req.headers["x-upload-token"] ??
    ""
  );
}

function validateToken(req) {
  if (!UPLOAD_TOKEN) {
    return true;
  }

  const received = tokenFromRequest(req);

  if (
    received.length !==
    UPLOAD_TOKEN.length
  ) {
    return false;
  }

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
  if (validateToken(req)) {
    return true;
  }

  res.status(401).json({
    success: false,
    message: "Token inválido.",
  });

  return false;
}

function publicBaseUrl(req) {
  const forwarded =
    req.headers["x-forwarded-proto"];

  const protocol =
    typeof forwarded === "string"
      ? forwarded.split(",")[0].trim()
      : req.protocol || "https";

  return `${protocol}://${req.get("host")}`;
}

function buildUniqueFileName(fileName) {
  const safe = sanitizeFileName(fileName);
  const ext = path.extname(safe) || ".json";
  const base = path.basename(safe, ext);

  const stamp =
    Date.now().toString(36);

  const random =
    crypto.randomBytes(4).toString("hex");

  return `${base}_${stamp}_${random}${ext}`;
}

function safeUploadId(value) {
  const id = String(value || "");

  if (!/^[a-f0-9]{32}$/i.test(id)) {
    return null;
  }

  return id;
}

function sessionPath(uploadId) {
  return path.join(
    SESSION_DIR,
    uploadId
  );
}

function manifestPath(uploadId) {
  return path.join(
    sessionPath(uploadId),
    "manifest.json"
  );
}

function chunkPath(uploadId, index) {
  return path.join(
    sessionPath(uploadId),
    `chunk-${String(index).padStart(
      6,
      "0"
    )}.json`
  );
}

function hashText(text) {
  return crypto
    .createHash("sha256")
    .update(text, "utf8")
    .digest("hex");
}

function readManifest(uploadId) {
  const file = manifestPath(uploadId);

  if (!fs.existsSync(file)) {
    return null;
  }

  try {
    return JSON.parse(
      fs.readFileSync(
        file,
        "utf8"
      )
    );
  } catch {
    return null;
  }
}

function writeManifest(uploadId, data) {
  fs.writeFileSync(
    manifestPath(uploadId),
    JSON.stringify(
      data,
      null,
      2
    ),
    "utf8"
  );
}

function removeDirectorySafe(directory) {
  try {
    fs.rmSync(directory, {
      recursive: true,
      force: true,
    });
  } catch (error) {
    console.error(
      "CLEANUP ERROR:",
      error
    );
  }
}

function cleanupExpiredSessions() {
  let entries = [];

  try {
    entries =
      fs.readdirSync(
        SESSION_DIR,
        {
          withFileTypes: true,
        }
      );
  } catch {
    return;
  }

  const now = Date.now();

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const directory =
      path.join(
        SESSION_DIR,
        entry.name
      );

    try {
      const stat =
        fs.statSync(directory);

      if (
        now - stat.mtimeMs >
        SESSION_TTL_MS
      ) {
        removeDirectorySafe(
          directory
        );
      }
    } catch {}
  }
}

function validateChunkSet(
  uploadId,
  totalChunks
) {
  let total = 0;

  for (
    let i = 1;
    i <= totalChunks;
    i++
  ) {
    const file =
      chunkPath(
        uploadId,
        i
      );

    if (!fs.existsSync(file)) {
      return {
        ok: false,
        missing: i,
        bytes: total,
      };
    }

    total +=
      fs.statSync(file).size;

    if (
      total >
      MAX_FINAL_BYTES
    ) {
      return {
        ok: false,
        tooLarge: true,
        bytes: total,
      };
    }
  }

  return {
    ok: true,
    bytes: total,
  };
}

function getStoredFiles(req) {
  let entries = [];

  try {
    entries =
      fs.readdirSync(
        UPLOAD_DIR,
        {
          withFileTypes: true,
        }
      );
  } catch {
    return [];
  }

  return entries
    .filter((entry) => {
      return (
        entry.isFile() &&
        entry.name !== ".gitkeep" &&
        !entry.name.endsWith(".tmp")
      );
    })
    .map((entry) => {
      try {
        const filePath =
          path.join(
            UPLOAD_DIR,
            entry.name
          );

        const stat =
          fs.statSync(filePath);

        const encoded =
          encodeURIComponent(
            entry.name
          );

        return {
          name: entry.name,
          filename: entry.name,
          bytes: stat.size,
          size: stat.size,
          createdAt:
            stat.birthtime.toISOString(),
          modifiedAt:
            stat.mtime.toISOString(),
          downloadUrl:
            `${publicBaseUrl(req)}/files/${encoded}`,
          infoUrl:
            `${publicBaseUrl(req)}/api/files/${encoded}/info`,
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => {
      return (
        new Date(b.modifiedAt) -
        new Date(a.modifiedAt)
      );
    });
}

async function writeWithBackpressure(stream, text) {
  if (stream.write(text)) {
    return;
  }

  await new Promise((resolve, reject) => {
    const onDrain = () => {
      cleanup();
      resolve();
    };

    const onError = (error) => {
      cleanup();
      reject(error);
    };

    const cleanup = () => {
      stream.off("drain", onDrain);
      stream.off("error", onError);
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

// ============================================================
// SITE
// ============================================================

app.get("/", (_req, res) => {
  const indexFile =
    path.join(
      PUBLIC_DIR,
      "index.html"
    );

  if (!fs.existsSync(indexFile)) {
    return res
      .status(503)
      .send(`
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CAFEÍNA</title>
<style>
body{
  margin:0;
  min-height:100vh;
  display:flex;
  justify-content:center;
  align-items:center;
  background:#08080a;
  color:white;
  font-family:Arial,sans-serif;
}
.box{
  text-align:center;
  padding:30px;
}
h1{
  color:#ff2638;
  letter-spacing:3px;
}
p{
  color:#aaa;
}
</style>
</head>
<body>
<div class="box">
  <h1>CAFEÍNA</h1>
  <p>public/index.html não encontrado.</p>
</div>
</body>
</html>
`);
  }

  return res.sendFile(indexFile);
});

// ============================================================
// HEALTH
// ============================================================

app.get(
  "/health",
  (_req, res) => {
    res.json({
      ok: true,
      service: "CAFEINA",

      web: true,
      files: true,
      diagnostics: true,
      ai: Boolean(client),
      scanner: true,
      explorerUpload: true,
      chunkUpload: true,
      uploadStatus: true,
      downloads: true,

      storage: {
        type: "local",
        persistent: false,
        note:
          "Armazenamento local gratuito. Pode ser apagado quando a instância do Render for recriada.",
      },

      limits: {
        maxChunkBytes:
          MAX_CHUNK_BYTES,

        maxFinalBytes:
          MAX_FINAL_BYTES,

        sessionTtlMs:
          SESSION_TTL_MS,
      },

      uptime:
        process.uptime(),
    });
  }
);

// ============================================================
// API DE ARQUIVOS
// ============================================================

app.get(
  "/api/ai/status",
  (_req, res) => {
    return res.json({
      ok: true,
      available: Boolean(client),
    });
  }
);

app.get(
  "/api/files",
  (req, res) => {
    try {
      const files =
        getStoredFiles(req);

      const totalBytes =
        files.reduce(
          (total, file) =>
            total + file.bytes,
          0
        );

      return res.json({
        success: true,

        storage: {
          type: "local",
          persistent: false,
        },

        count:
          files.length,

        totalBytes,

        files,
      });
    } catch (error) {
      console.error(
        "FILE LIST ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao listar arquivos.",
        });
    }
  }
);

app.get(
  "/api/files/:filename/info",
  (req, res) => {
    try {
      const requested =
        path.basename(
          String(
            req.params.filename ||
            ""
          )
        );

      if (!requested) {
        return res
          .status(400)
          .json({
            success: false,
            message:
              "Nome de arquivo inválido.",
          });
      }

      const filePath =
        path.join(
          UPLOAD_DIR,
          requested
        );

      if (
        !fs.existsSync(filePath)
      ) {
        return res
          .status(404)
          .json({
            success: false,
            message:
              "Arquivo não encontrado.",
          });
      }

      const stat =
        fs.statSync(filePath);

      return res.json({
        success: true,

        file: {
          name: requested,
          bytes:
            stat.size,
          createdAt:
            stat.birthtime.toISOString(),
          modifiedAt:
            stat.mtime.toISOString(),
          downloadUrl:
            `${publicBaseUrl(
              req
            )}/files/${encodeURIComponent(
              requested
            )}`,
        },
      });
    } catch (error) {
      console.error(
        "FILE INFO ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao consultar arquivo.",
        });
    }
  }
);

// ============================================================
// CAFEÍNA AI
// ============================================================

app.post(
  "/chat",
  async (req, res) => {
    try {
      if (!client) {
        return res
          .status(503)
          .json({
            message:
              "CAFEÍNA AI não configurada. OPENAI_API_KEY ausente.",
          });
      }

      const {
        message,
        userId,
        username,
      } = req.body ?? {};

      if (
        typeof message !==
          "string" ||
        !message.trim()
      ) {
        return res
          .status(400)
          .json({
            message:
              "Mensagem inválida.",
          });
      }

      if (
        message.length >
        MAX_CHAT_CHARS
      ) {
        return res
          .status(400)
          .json({
            message:
              `Mensagem muito grande. Limite: ${MAX_CHAT_CHARS} caracteres.`,
          });
      }

      const conversationKey =
        String(
          userId ??
            username ??
            "anonymous"
        );

      const previousResponseId =
        conversations.get(
          conversationKey
        );

      const request = {
        model: MODEL,

        instructions:
          "Você é CAFEÍNA AI. " +
          "Responda em português do Brasil por padrão. " +
          "Seja clara, objetiva e útil. " +
          "Não afirme ter acesso a dados que não tenham sido enviados.",

        input:
          message.trim(),

        max_output_tokens:
          MAX_CHAT_OUTPUT_TOKENS,
      };

      if (
        previousResponseId
      ) {
        request.previous_response_id =
          previousResponseId;
      }

      const response =
        await client.responses.create(
          request
        );

      conversations.set(
        conversationKey,
        response.id
      );

      return res.json({
        message:
          response.output_text ||
          "A IA não retornou texto.",

        responseId:
          response.id,
      });
    } catch (error) {
      console.error(
        "CHAT ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          message:
            "Erro ao consultar a IA.",
        });
    }
  }
);

app.post(
  "/reset",
  (req, res) => {
    const {
      userId,
      username,
    } = req.body ?? {};

    const conversationKey =
      String(
        userId ??
          username ??
          "anonymous"
      );

    conversations.delete(
      conversationKey
    );

    return res.json({
      ok: true,
      message:
        "Conversa reiniciada.",
    });
  }
);

// ============================================================
// UPLOAD START
// ============================================================

app.post(
  "/upload/start",
  (req, res) => {
    try {
      cleanupExpiredSessions();

      if (
        !requireUploadToken(
          req,
          res
        )
      ) {
        return;
      }

      const filename =
        sanitizeFileName(
          req.body?.filename
        );

      const source =
        String(
          req.body?.source ||
            "cafeina-game-explorer"
        ).slice(0, 120);

      const metadata =
        req.body?.metadata &&
        typeof req.body
          .metadata === "object" &&
        !Array.isArray(req.body.metadata)
          ? req.body.metadata
          : {};

      const uploadId =
        crypto
          .randomBytes(16)
          .toString("hex");

      const directory =
        sessionPath(uploadId);

      fs.mkdirSync(
        directory,
        {
          recursive: true,
        }
      );

      const manifest = {
        uploadId,
        filename,
        source,
        metadata,

        createdAt:
          new Date().toISOString(),

        updatedAt:
          new Date().toISOString(),

        chunks: {},

        chunkCount: 0,
        objectCount: 0,
        receivedBytes: 0,

        finished: false,
      };

      writeManifest(
        uploadId,
        manifest
      );

      return res
        .status(201)
        .json({
          success: true,
          uploadId,
          filename,

          limits: {
            maxChunkBytes:
              MAX_CHUNK_BYTES,
            maxFinalBytes:
              MAX_FINAL_BYTES,
          },
        });
    } catch (error) {
      console.error(
        "UPLOAD START ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao iniciar upload.",
        });
    }
  }
);

// ============================================================
// UPLOAD STATUS
// ============================================================

app.get(
  "/api/uploads/:uploadId",
  (req, res) => {
    const uploadId =
      safeUploadId(
        req.params.uploadId
      );

    if (!uploadId) {
      return res
        .status(400)
        .json({
          success: false,
          message:
            "uploadId inválido.",
        });
    }

    const manifest =
      readManifest(uploadId);

    if (!manifest) {
      return res
        .status(404)
        .json({
          success: false,
          message:
            "Sessão não encontrada.",
        });
    }

    return res.json({
      success: true,

      upload: {
        uploadId:
          manifest.uploadId,
        filename:
          manifest.filename,
        source:
          manifest.source,

        createdAt:
          manifest.createdAt,
        updatedAt:
          manifest.updatedAt,

        chunkCount:
          manifest.chunkCount || 0,
        objectCount:
          manifest.objectCount || 0,
        receivedBytes:
          manifest.receivedBytes || 0,

        finished:
          Boolean(
            manifest.finished
          ),
      },
    });
  }
);

// ============================================================
// UPLOAD CHUNK
// ============================================================

app.post(
  "/upload/chunk",
  (req, res) => {
    try {
      if (
        !requireUploadToken(
          req,
          res
        )
      ) {
        return;
      }

      const uploadId =
        safeUploadId(
          req.body?.uploadId
        );

      const index =
        Number(
          req.body?.index
        );

      const objects =
        req.body?.objects;

      if (
        !uploadId ||
        !Number.isInteger(
          index
        ) ||
        index < 1 ||
        !Array.isArray(
          objects
        )
      ) {
        return res
          .status(400)
          .json({
            success: false,
            message:
              "Chunk inválido.",
          });
      }

      const manifest =
        readManifest(uploadId);

      if (!manifest) {
        return res
          .status(404)
          .json({
            success: false,
            message:
              "Sessão de upload não encontrada.",
          });
      }

      if (
        manifest.finished
      ) {
        return res
          .status(409)
          .json({
            success: false,
            message:
              "Sessão já finalizada.",
          });
      }

      const encoded =
        JSON.stringify(objects);

      const byteLength =
        Buffer.byteLength(
          encoded,
          "utf8"
        );

      if (
        byteLength >
        MAX_CHUNK_BYTES
      ) {
        return res
          .status(413)
          .json({
            success: false,

            message:
              "Chunk acima do limite.",

            maxChunkBytes:
              MAX_CHUNK_BYTES,

            receivedBytes:
              byteLength,
          });
      }

      const hash =
        hashText(encoded);

      const existing =
        manifest.chunks[
          String(index)
        ];

      // Retry idempotente: se é exatamente o mesmo chunk,
      // responde sucesso sem regravar/duplicar contadores.
      if (existing) {
        if (
          existing.sha256 === hash &&
          existing.bytes === byteLength
        ) {
          return res.json({
            success: true,
            duplicate: true,
            uploadId,
            index,
            bytes:
              byteLength,
            objectCount:
              objects.length,
          });
        }

        return res
          .status(409)
          .json({
            success: false,
            message:
              `Chunk ${index} já existe com conteúdo diferente.`,
          });
      }

      const projectedBytes =
        Number(
          manifest.receivedBytes || 0
        ) + byteLength;

      if (
        projectedBytes >
        MAX_FINAL_BYTES
      ) {
        return res
          .status(413)
          .json({
            success: false,
            message:
              "Upload ultrapassaria o limite final.",
            maxFinalBytes:
              MAX_FINAL_BYTES,
            projectedBytes,
          });
      }

      const file =
        chunkPath(
          uploadId,
          index
        );

      fs.writeFileSync(
        file,
        encoded,
        "utf8"
      );

      manifest.chunks[
        String(index)
      ] = {
        bytes:
          byteLength,

        objects:
          objects.length,

        sha256:
          hash,

        receivedAt:
          new Date().toISOString(),
      };

      manifest.chunkCount =
        Number(
          manifest.chunkCount || 0
        ) + 1;

      manifest.objectCount =
        Number(
          manifest.objectCount || 0
        ) + objects.length;

      manifest.receivedBytes =
        projectedBytes;

      manifest.updatedAt =
        new Date().toISOString();

      writeManifest(
        uploadId,
        manifest
      );

      return res.json({
        success: true,
        uploadId,
        index,
        bytes:
          byteLength,
        objectCount:
          objects.length,

        totals: {
          chunks:
            manifest.chunkCount,
          objects:
            manifest.objectCount,
          bytes:
            manifest.receivedBytes,
        },
      });
    } catch (error) {
      console.error(
        "UPLOAD CHUNK ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao salvar chunk.",
        });
    }
  }
);

// ============================================================
// UPLOAD FINISH
// ============================================================

app.post(
  "/upload/finish",
  async (req, res) => {
    let tempPath = null;

    try {
      if (
        !requireUploadToken(
          req,
          res
        )
      ) {
        return;
      }

      const uploadId =
        safeUploadId(
          req.body?.uploadId
        );

      const totalChunks =
        Number(
          req.body?.totalChunks
        );

      const summary =
        req.body?.summary &&
        typeof req.body
          .summary === "object" &&
        !Array.isArray(req.body.summary)
          ? req.body.summary
          : {};

      if (
        !uploadId ||
        !Number.isInteger(
          totalChunks
        ) ||
        totalChunks < 1
      ) {
        return res
          .status(400)
          .json({
            success: false,
            message:
              "Finalização inválida.",
          });
      }

      const manifest =
        readManifest(uploadId);

      if (!manifest) {
        return res
          .status(404)
          .json({
            success: false,
            message:
              "Sessão não encontrada.",
          });
      }

      if (
        manifest.finished
      ) {
        return res
          .status(409)
          .json({
            success: false,
            message:
              "Sessão já finalizada.",
          });
      }

      const validation =
        validateChunkSet(
          uploadId,
          totalChunks
        );

      if (
        !validation.ok
      ) {
        if (
          validation.tooLarge
        ) {
          return res
            .status(413)
            .json({
              success: false,

              message:
                "Arquivo final acima do limite.",

              maxFinalBytes:
                MAX_FINAL_BYTES,

              receivedBytes:
                validation.bytes,
            });
        }

        return res
          .status(409)
          .json({
            success: false,
            message:
              `Chunk ${validation.missing} ausente.`,
          });
      }

      const storedFileName =
        buildUniqueFileName(
          manifest.filename
        );

      const finalPath =
        path.join(
          UPLOAD_DIR,
          storedFileName
        );

      tempPath =
        `${finalPath}.tmp`;

      const stream =
        fs.createWriteStream(
          tempPath,
          {
            encoding: "utf8",
          }
        );

      await writeWithBackpressure(
        stream,
        "{\n"
      );

      await writeWithBackpressure(
        stream,
        `"uploadedAt":${JSON.stringify(
          new Date().toISOString()
        )},\n`
      );

      await writeWithBackpressure(
        stream,
        `"source":${JSON.stringify(
          manifest.source
        )},\n`
      );

      await writeWithBackpressure(
        stream,
        `"metadata":${JSON.stringify(
          manifest.metadata
        )},\n`
      );

      await writeWithBackpressure(
        stream,
        `"summary":${JSON.stringify(
          summary
        )},\n`
      );

      await writeWithBackpressure(
        stream,
        '"objects":[\n'
      );

      let firstObject = true;

      for (
        let i = 1;
        i <= totalChunks;
        i++
      ) {
        const raw =
          await fsp.readFile(
            chunkPath(
              uploadId,
              i
            ),
            "utf8"
          );

        let arr;

        try {
          arr =
            JSON.parse(raw);
        } catch {
          throw new Error(
            `Chunk ${i} corrompido`
          );
        }

        if (
          !Array.isArray(arr)
        ) {
          throw new Error(
            `Chunk ${i} inválido`
          );
        }

        for (
          const object of arr
        ) {
          if (
            !firstObject
          ) {
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

      const finalSize =
        (
          await fsp.stat(
            tempPath
          )
        ).size;

      if (
        finalSize >
        MAX_FINAL_BYTES
      ) {
        await fsp.rm(
          tempPath,
          {
            force: true,
          }
        );

        tempPath = null;

        return res
          .status(413)
          .json({
            success: false,

            message:
              "Arquivo final excedeu o limite após montagem.",

            finalBytes:
              finalSize,

            maxFinalBytes:
              MAX_FINAL_BYTES,
          });
      }

      await fsp.rename(
        tempPath,
        finalPath
      );

      tempPath = null;

      manifest.finished = true;

      manifest.finishedAt =
        new Date().toISOString();

      manifest.updatedAt =
        manifest.finishedAt;

      manifest.finalFile =
        storedFileName;

      manifest.finalBytes =
        finalSize;

      writeManifest(
        uploadId,
        manifest
      );

      const url =
        `${publicBaseUrl(
          req
        )}/files/${encodeURIComponent(
          storedFileName
        )}`;

      removeDirectorySafe(
        sessionPath(uploadId)
      );

      return res
        .status(201)
        .json({
          success: true,

          filename:
            storedFileName,

          bytes:
            finalSize,

          objectCount:
            manifest.objectCount || 0,

          chunkCount:
            totalChunks,

          url,
          downloadUrl:
            url,
        });
    } catch (error) {
      console.error(
        "UPLOAD FINISH ERROR:",
        error
      );

      if (tempPath) {
        try {
          await fsp.rm(
            tempPath,
            {
              force: true,
            }
          );
        } catch {}
      }

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao montar arquivo final.",
        });
    }
  }
);

// ============================================================
// CANCELAR UPLOAD
// ============================================================

app.post(
  "/upload/cancel",
  (req, res) => {
    if (
      !requireUploadToken(
        req,
        res
      )
    ) {
      return;
    }

    const uploadId =
      safeUploadId(
        req.body?.uploadId
      );

    if (!uploadId) {
      return res
        .status(400)
        .json({
          success: false,
          message:
            "uploadId inválido.",
        });
    }

    removeDirectorySafe(
      sessionPath(uploadId)
    );

    return res.json({
      success: true,
      cancelled: true,
    });
  }
);

// ============================================================
// DOWNLOAD
// ============================================================

app.get(
  "/files/:filename",
  (req, res) => {
    try {
      const requested =
        path.basename(
          String(
            req.params.filename ||
            ""
          )
        );

      if (!requested) {
        return res
          .status(400)
          .json({
            success: false,
            message:
              "Nome de arquivo inválido.",
          });
      }

      const filePath =
        path.join(
          UPLOAD_DIR,
          requested
        );

      if (
        !fs.existsSync(
          filePath
        )
      ) {
        return res
          .status(404)
          .json({
            success: false,
            message:
              "Arquivo não encontrado.",
          });
      }

      return res.download(
        filePath,
        requested
      );
    } catch (error) {
      console.error(
        "DOWNLOAD ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro interno ao baixar arquivo.",
        });
    }
  }
);

// ============================================================
// EXCLUIR ARQUIVO
// Se UPLOAD_TOKEN estiver configurado, DELETE também exige token.
// ============================================================

app.delete(
  "/api/files/:filename",
  (req, res) => {
    try {
      if (
        !requireUploadToken(
          req,
          res
        )
      ) {
        return;
      }

      const requested =
        path.basename(
          String(
            req.params.filename ||
            ""
          )
        );

      if (!requested) {
        return res
          .status(400)
          .json({
            success: false,
            message:
              "Nome inválido.",
          });
      }

      const filePath =
        path.join(
          UPLOAD_DIR,
          requested
        );

      if (
        !fs.existsSync(
          filePath
        )
      ) {
        return res
          .status(404)
          .json({
            success: false,
            message:
              "Arquivo não encontrado.",
          });
      }

      fs.rmSync(
        filePath,
        {
          force: true,
        }
      );

      return res.json({
        success: true,
        deleted:
          requested,
      });
    } catch (error) {
      console.error(
        "DELETE FILE ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao excluir arquivo.",
        });
    }
  }
);

// ============================================================
// DIAGNÓSTICOS DE SCRIPTS
// ============================================================

// Recebe erro enviado pelo Loader.lua.
app.post(
  "/api/diagnostics",
  (req, res) => {
    try {
      if (!allowDiagnosticRequest(req)) {
        return res
          .status(429)
          .json({
            success: false,
            message:
              "Muitos diagnósticos enviados.",
          });
      }

      const body = req.body || {};

      const item = {
        id: crypto.randomUUID(),

        type:
          cleanDiagnosticText(
            body.type || "unknown",
            40
          ),

        message:
          cleanDiagnosticText(
            body.message || "Sem mensagem",
            MAX_DIAGNOSTIC_MESSAGE
          ),

        trace:
          cleanDiagnosticText(
            body.trace || "",
            MAX_DIAGNOSTIC_TRACE
          ),

        version:
          cleanDiagnosticText(
            body.version || "",
            120
          ),

        scriptUrl:
          cleanDiagnosticText(
            body.scriptUrl || "",
            500
          ),

        placeId:
          cleanDiagnosticText(
            body.placeId || "",
            40
          ),

        gameId:
          cleanDiagnosticText(
            body.gameId || "",
            40
          ),

        executor:
          cleanDiagnosticText(
            body.executor || "desconhecido",
            120
          ),

        clientTime:
          cleanDiagnosticText(
            body.clientTime || "",
            80
          ),

        receivedAt:
          new Date().toISOString(),
      };

      appendDiagnostic(item);

      console.error(
        `[CLIENT ${item.type}]`,
        item.message
      );

      return res
        .status(201)
        .json({
          success: true,
          id: item.id,
          receivedAt: item.receivedAt,
        });

    } catch (error) {
      console.error(
        "DIAGNOSTIC RECEIVE ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao salvar diagnóstico.",
        });
    }
  }
);

// A tela Arquivos consulta esta rota.
app.get(
  "/api/diagnostics",
  (_req, res) => {
    try {
      const diagnostics =
        readDiagnostics();

      return res.json({
        success: true,
        count: diagnostics.length,
        diagnostics:
          diagnostics.slice(0, 50),
      });
    } catch (error) {
      console.error(
        "DIAGNOSTIC LIST ERROR:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          message:
            "Erro ao listar diagnósticos.",
        });
    }
  }
);

app.delete(
  "/api/diagnostics",
  (_req, res) => {
    try {
      fs.writeFileSync(DIAGNOSTICS_FILE, "", "utf8");
      return res.json({ success: true, ok: true, cleared: true });
    } catch (error) {
      console.error("DIAGNOSTIC CLEAR ERROR:", error);
      return res.status(500).json({ success: false, ok: false, message: "Erro ao limpar diagnósticos." });
    }
  }
);

// ============================================================
// 404
// ============================================================

app.use(
  (_req, res) => {
    return res
      .status(404)
      .json({
        ok: false,
        message:
          "Rota não encontrada.",
      });
  }
);

// ============================================================
// LIMPEZA PERIÓDICA DE SESSÕES
// ============================================================

cleanupExpiredSessions();

const cleanupTimer =
  setInterval(
    cleanupExpiredSessions,
    CLEANUP_INTERVAL_MS
  );

cleanupTimer.unref?.();

// ============================================================
// START
// ============================================================

app.listen(
  PORT,
  "0.0.0.0",
  () => {
    console.log(
      "================================="
    );

    console.log(
      "CAFEÍNA ONLINE"
    );

    console.log(
      `Porta: ${PORT}`
    );

    console.log(
      `Uploads: ${UPLOAD_DIR}`
    );

    console.log(
      `Chunk máximo: ${MAX_CHUNK_BYTES} bytes`
    );

    console.log(
      `Arquivo máximo: ${MAX_FINAL_BYTES} bytes`
    );

    console.log(
      "Scanner: /upload/start → /upload/chunk → /upload/finish"
    );

    console.log(
      "Arquivos: /api/files"
    );

    console.log(
      "Diagnósticos: /api/diagnostics"
    );

    console.log(
      `OpenAI: ${client ? "configurada" : "não configurada"}`
    );

    console.log(
      "================================="
    );
  }
);
