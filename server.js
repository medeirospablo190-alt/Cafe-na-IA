import express from "express";
import OpenAI from "openai";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const app = express();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = process.env.PORT || 10000;
const MODEL = process.env.OPENAI_MODEL || "gpt-5.4";

const UPLOAD_DIR = path.join(__dirname, "uploads");
const SESSION_DIR = path.join(UPLOAD_DIR, "_sessions");

const UPLOAD_TOKEN = String(process.env.UPLOAD_TOKEN || "");

// Limite por requisição/chunk, não do arquivo final.
const MAX_CHUNK_BYTES =
  Number(process.env.MAX_CHUNK_BYTES || 6000000);

const MAX_FINAL_BYTES =
  Number(process.env.MAX_FINAL_BYTES || 300000000);

const SESSION_TTL_MS =
  Number(process.env.SESSION_TTL_MS || 6 * 60 * 60 * 1000);

app.use(
  express.json({
    limit: Math.max(MAX_CHUNK_BYTES + 1000000, 8000000),
  })
);

fs.mkdirSync(UPLOAD_DIR, { recursive: true });
fs.mkdirSync(SESSION_DIR, { recursive: true });

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const conversations = new Map();

//==============================================================//
// HELPERS
//==============================================================//

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

function validateToken(body) {
  if (!UPLOAD_TOKEN) {
    return true;
  }

  const received = String(body?.token || "");

  if (received.length !== UPLOAD_TOKEN.length) {
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

function publicBaseUrl(req) {
  const protocol =
    req.headers["x-forwarded-proto"] ||
    req.protocol ||
    "https";

  return `${protocol}://${req.get("host")}`;
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

  if (!/^[a-f0-9]{32}$/i.test(id)) {
    return null;
  }

  return id;
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

  if (!fs.existsSync(file)) {
    return null;
  }

  try {
    return JSON.parse(
      fs.readFileSync(file, "utf8")
    );
  } catch {
    return null;
  }
}

function writeManifest(uploadId, data) {
  fs.writeFileSync(
    manifestPath(uploadId),
    JSON.stringify(data, null, 2),
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
    console.error("Cleanup error:", error);
  }
}

function cleanupExpiredSessions() {
  let entries = [];

  try {
    entries = fs.readdirSync(
      SESSION_DIR,
      { withFileTypes: true }
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
      path.join(SESSION_DIR, entry.name);

    try {
      const stat = fs.statSync(directory);

      if (
        now - stat.mtimeMs
        > SESSION_TTL_MS
      ) {
        removeDirectorySafe(directory);
      }
    } catch {
      // ignore
    }
  }
}

function totalChunkBytes(uploadId, totalChunks) {
  let total = 0;

  for (let i = 1; i <= totalChunks; i++) {
    const file = chunkPath(uploadId, i);

    if (!fs.existsSync(file)) {
      return {
        ok: false,
        missing: i,
        bytes: total,
      };
    }

    total += fs.statSync(file).size;

    if (total > MAX_FINAL_BYTES) {
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

//==============================================================//
// ROOT / HEALTH
//==============================================================//

app.get("/", (_req, res) => {
  res.json({
    ok: true,
    service: "CAFEINA AI + GAME EXPLORER",
    endpoints: {
      chat: "POST /chat",
      reset: "POST /reset",

      uploadStart: "POST /upload/start",
      uploadChunk: "POST /upload/chunk",
      uploadFinish: "POST /upload/finish",
      uploadCancel: "POST /upload/cancel",

      download: "GET /files/:filename",
      health: "GET /health",
    },
  });
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "CAFEINA",
    ai: true,
    explorerUpload: true,
    chunkUpload: true,

    limits: {
      maxChunkBytes: MAX_CHUNK_BYTES,
      maxFinalBytes: MAX_FINAL_BYTES,
    },

    uptime: process.uptime(),
  });
});

//==============================================================//
// CAFEÍNA AI
//==============================================================//

app.post("/chat", async (req, res) => {
  try {
    const { message, userId, username } = req.body ?? {};

    if (
      typeof message !== "string" ||
      !message.trim()
    ) {
      return res.status(400).json({
        message: "Mensagem inválida.",
      });
    }

    if (message.length > 2000) {
      return res.status(400).json({
        message:
          "Mensagem muito grande. Limite: 2000 caracteres.",
      });
    }

    const conversationKey =
      String(
        userId ??
        username ??
        "anonymous"
      );

    const previousResponseId =
      conversations.get(conversationKey);

    const request = {
      model: MODEL,

      instructions:
        "Você é CAFEÍNA AI, uma assistente integrada a um menu Roblox. " +
        "Responda em português do Brasil por padrão. Seja clara, objetiva e útil. " +
        "Não afirme ter acesso ao servidor Roblox, Workspace, jogadores ou dados " +
        "que não tenham sido enviados a você.",

      input: message.trim(),

      max_output_tokens: 800,
    };

    if (previousResponseId) {
      request.previous_response_id =
        previousResponseId;
    }

    const response =
      await client.responses.create(request);

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
    console.error("CHAT ERROR:", error);

    return res.status(500).json({
      message:
        "Erro ao consultar a IA.",
    });
  }
});

app.post("/reset", (req, res) => {
  const { userId, username } =
    req.body ?? {};

  const conversationKey =
    String(
      userId ??
      username ??
      "anonymous"
    );

  conversations.delete(conversationKey);

  return res.json({
    ok: true,
    message: "Conversa reiniciada.",
  });
});

//==============================================================//
// CHUNK UPLOAD • START
//==============================================================//

app.post("/upload/start", (req, res) => {
  try {
    cleanupExpiredSessions();

    if (!validateToken(req.body)) {
      return res.status(401).json({
        success: false,
        message: "Token inválido.",
      });
    }

    const filename =
      sanitizeFileName(
        req.body?.filename
      );

    const source =
      String(
        req.body?.source ||
        "cafeina-game-explorer"
      );

    const metadata =
      req.body?.metadata &&
      typeof req.body.metadata === "object"
        ? req.body.metadata
        : {};

    const uploadId =
      crypto
        .randomBytes(16)
        .toString("hex");

    const directory =
      sessionPath(uploadId);

    fs.mkdirSync(directory, {
      recursive: true,
    });

    const manifest = {
      uploadId,
      filename,
      source,
      metadata,

      createdAt:
        new Date().toISOString(),

      chunks: {},
      finished: false,
    };

    writeManifest(
      uploadId,
      manifest
    );

    return res.status(201).json({
      success: true,
      uploadId,
    });
  } catch (error) {
    console.error(
      "UPLOAD START ERROR:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Erro ao iniciar upload.",
    });
  }
});

//==============================================================//
// CHUNK UPLOAD • CHUNK
//==============================================================//

app.post("/upload/chunk", (req, res) => {
  try {
    if (!validateToken(req.body)) {
      return res.status(401).json({
        success: false,
        message: "Token inválido.",
      });
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
      !Number.isInteger(index) ||
      index < 1 ||
      !Array.isArray(objects)
    ) {
      return res.status(400).json({
        success: false,
        message:
          "Chunk inválido.",
      });
    }

    const manifest =
      readManifest(uploadId);

    if (!manifest) {
      return res.status(404).json({
        success: false,
        message:
          "Sessão de upload não encontrada.",
      });
    }

    if (manifest.finished) {
      return res.status(409).json({
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

    if (byteLength > MAX_CHUNK_BYTES) {
      return res.status(413).json({
        success: false,
        message:
          "Chunk acima do limite.",

        maxChunkBytes:
          MAX_CHUNK_BYTES,

        receivedBytes:
          byteLength,
      });
    }

    const file =
      chunkPath(
        uploadId,
        index
      );

    // Idempotente: retry do mesmo chunk sobrescreve o mesmo arquivo.
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

      receivedAt:
        new Date().toISOString(),
    };

    writeManifest(
      uploadId,
      manifest
    );

    return res.json({
      success: true,
      uploadId,
      index,
      bytes: byteLength,
      objectCount: objects.length,
    });
  } catch (error) {
    console.error(
      "UPLOAD CHUNK ERROR:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Erro ao salvar chunk.",
    });
  }
});

//==============================================================//
// CHUNK UPLOAD • FINISH
//==============================================================//

app.post("/upload/finish", (req, res) => {
  try {
    if (!validateToken(req.body)) {
      return res.status(401).json({
        success: false,
        message: "Token inválido.",
      });
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
      typeof req.body.summary === "object"
        ? req.body.summary
        : {};

    if (
      !uploadId ||
      !Number.isInteger(totalChunks) ||
      totalChunks < 1
    ) {
      return res.status(400).json({
        success: false,
        message:
          "Finalização inválida.",
      });
    }

    const manifest =
      readManifest(uploadId);

    if (!manifest) {
      return res.status(404).json({
        success: false,
        message:
          "Sessão não encontrada.",
      });
    }

    const validation =
      totalChunkBytes(
        uploadId,
        totalChunks
      );

    if (!validation.ok) {
      if (validation.tooLarge) {
        return res.status(413).json({
          success: false,
          message:
            "Arquivo final acima do limite.",

          maxFinalBytes:
            MAX_FINAL_BYTES,

          receivedBytes:
            validation.bytes,
        });
      }

      return res.status(409).json({
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

    const fd =
      fs.openSync(
        finalPath,
        "w"
      );

    try {
      const header = {
        uploadedAt:
          new Date().toISOString(),

        source:
          manifest.source,

        metadata:
          manifest.metadata,

        summary,
      };

      fs.writeSync(
        fd,
        "{\n"
      );

      fs.writeSync(
        fd,
        `"uploadedAt":${JSON.stringify(
          header.uploadedAt
        )},\n`
      );

      fs.writeSync(
        fd,
        `"source":${JSON.stringify(
          header.source
        )},\n`
      );

      fs.writeSync(
        fd,
        `"metadata":${JSON.stringify(
          header.metadata
        )},\n`
      );

      fs.writeSync(
        fd,
        `"summary":${JSON.stringify(
          summary
        )},\n`
      );

      fs.writeSync(
        fd,
        '"objects":[\n'
      );

      let firstObject = true;

      for (
        let i = 1;
        i <= totalChunks;
        i++
      ) {
        const raw =
          fs.readFileSync(
            chunkPath(
              uploadId,
              i
            ),
            "utf8"
          );

        let arr;

        try {
          arr = JSON.parse(raw);
        } catch {
          throw new Error(
            `Chunk ${i} corrompido`
          );
        }

        if (!Array.isArray(arr)) {
          throw new Error(
            `Chunk ${i} inválido`
          );
        }

        for (const object of arr) {
          if (!firstObject) {
            fs.writeSync(
              fd,
              ",\n"
            );
          }

          fs.writeSync(
            fd,
            JSON.stringify(object)
          );

          firstObject = false;
        }
      }

      fs.writeSync(
        fd,
        "\n]\n}"
      );
    } finally {
      fs.closeSync(fd);
    }

    const finalSize =
      fs.statSync(finalPath).size;

    if (finalSize > MAX_FINAL_BYTES) {
      fs.rmSync(
        finalPath,
        { force: true }
      );

      return res.status(413).json({
        success: false,
        message:
          "Arquivo final excedeu o limite após montagem.",

        finalBytes:
          finalSize,

        maxFinalBytes:
          MAX_FINAL_BYTES,
      });
    }

    manifest.finished = true;
    manifest.finishedAt =
      new Date().toISOString();

    manifest.finalFile =
      storedFileName;

    writeManifest(
      uploadId,
      manifest
    );

    const url =
      `${publicBaseUrl(req)}/files/${encodeURIComponent(
        storedFileName
      )}`;

    // Depois que o arquivo final existe, os chunks não são mais necessários.
    removeDirectorySafe(
      sessionPath(uploadId)
    );

    return res.status(201).json({
      success: true,

      filename:
        storedFileName,

      bytes:
        finalSize,

      url,
      downloadUrl:
        url,
    });
  } catch (error) {
    console.error(
      "UPLOAD FINISH ERROR:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Erro ao montar arquivo final.",
    });
  }
});

//==============================================================//
// CHUNK UPLOAD • CANCEL
//==============================================================//

app.post("/upload/cancel", (req, res) => {
  if (!validateToken(req.body)) {
    return res.status(401).json({
      success: false,
      message: "Token inválido.",
    });
  }

  const uploadId =
    safeUploadId(
      req.body?.uploadId
    );

  if (!uploadId) {
    return res.status(400).json({
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
});

//==============================================================//
// DOWNLOAD
//==============================================================//

app.get("/files/:filename", (req, res) => {
  try {
    const requested =
      path.basename(
        String(
          req.params.filename || ""
        )
      );

    if (!requested) {
      return res.status(400).json({
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

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
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

    return res.status(500).json({
      success: false,
      message:
        "Erro interno ao baixar o arquivo.",
    });
  }
});

//==============================================================//
// 404
//==============================================================//

app.use((_req, res) => {
  return res.status(404).json({
    ok: false,
    message:
      "Rota não encontrada.",
  });
});

//==============================================================//
// START
//==============================================================//

app.listen(
  PORT,
  "0.0.0.0",
  () => {
    console.log(
      `CAFEÍNA AI + Explorer Chunk Server online na porta ${PORT}`
    );
  }
);
