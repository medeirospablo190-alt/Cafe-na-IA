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
const UPLOAD_TOKEN = String(process.env.UPLOAD_TOKEN || "");
const MAX_UPLOAD_BYTES = Number(process.env.MAX_UPLOAD_BYTES || 750000);

// O limite HTTP precisa ser maior que o upload máximo.
// O /chat continua limitado manualmente a 2000 caracteres.
app.use(
  express.json({
    limit: Math.max(MAX_UPLOAD_BYTES + 200000, 1000000),
  })
);

fs.mkdirSync(UPLOAD_DIR, {
  recursive: true,
});

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Memória simples em RAM por usuário.
// Em reinícios do Render, essa memória é perdida.
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

function buildUniqueFileName(fileName) {
  const safe = sanitizeFileName(fileName);
  const ext = path.extname(safe) || ".json";
  const base = path.basename(safe, ext);

  const stamp = Date.now().toString(36);
  const random = crypto.randomBytes(4).toString("hex");

  return `${base}_${stamp}_${random}${ext}`;
}

function validateUploadToken(body) {
  // Se UPLOAD_TOKEN não estiver configurado, uploads ficam sem token.
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
      upload: "POST /upload",
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
    uptime: process.uptime(),
  });
});

//==============================================================//
// CAFEÍNA AI
//==============================================================//

app.post("/chat", async (req, res) => {
  try {
    const { message, userId, username } = req.body ?? {};

    if (typeof message !== "string" || !message.trim()) {
      return res.status(400).json({
        message: "Mensagem inválida.",
      });
    }

    if (message.length > 2000) {
      return res.status(400).json({
        message: "Mensagem muito grande. Limite: 2000 caracteres.",
      });
    }

    const conversationKey = String(
      userId ?? username ?? "anonymous"
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
      request.previous_response_id = previousResponseId;
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
      message: "Erro ao consultar a IA.",
    });
  }
});

//==============================================================//
// RESET DA CONVERSA
//==============================================================//

app.post("/reset", (req, res) => {
  const { userId, username } = req.body ?? {};

  const conversationKey = String(
    userId ?? username ?? "anonymous"
  );

  conversations.delete(conversationKey);

  return res.json({
    ok: true,
    message: "Conversa reiniciada.",
  });
});

//==============================================================//
// GAME EXPLORER • UPLOAD
//==============================================================//

app.post("/upload", (req, res) => {
  try {
    if (!validateUploadToken(req.body)) {
      return res.status(401).json({
        success: false,
        message: "Token de upload inválido.",
      });
    }

    const requestedName =
      sanitizeFileName(
        req.body?.filename
      );

    const content =
      String(
        req.body?.content ?? ""
      );

    const source =
      String(
        req.body?.source ??
        "cafeina-game-explorer"
      );

    if (!content) {
      return res.status(400).json({
        success: false,
        message: "Conteúdo vazio.",
      });
    }

    const byteLength =
      Buffer.byteLength(
        content,
        "utf8"
      );

    if (byteLength > MAX_UPLOAD_BYTES) {
      return res.status(413).json({
        success: false,
        message:
          "Arquivo acima do limite permitido.",

        maxBytes:
          MAX_UPLOAD_BYTES,

        receivedBytes:
          byteLength,
      });
    }

    // O Explorer deve exportar JSON válido.
    let parsed;

    try {
      parsed = JSON.parse(content);
    } catch {
      return res.status(400).json({
        success: false,
        message:
          "O conteúdo enviado precisa ser JSON válido.",
      });
    }

    const storedFileName =
      buildUniqueFileName(
        requestedName
      );

    const filePath =
      path.join(
        UPLOAD_DIR,
        storedFileName
      );

    const storedDocument = {
      uploadedAt:
        new Date().toISOString(),

      source,
      originalFileName:
        requestedName,

      data:
        parsed,
    };

    fs.writeFileSync(
      filePath,
      JSON.stringify(
        storedDocument,
        null,
        2
      ),
      "utf8"
    );

    const url =
      `${publicBaseUrl(req)}/files/${encodeURIComponent(
        storedFileName
      )}`;

    return res.status(201).json({
      success: true,

      filename:
        storedFileName,

      bytes:
        byteLength,

      url,
      downloadUrl:
        url,
    });
  } catch (error) {
    console.error("UPLOAD ERROR:", error);

    return res.status(500).json({
      success: false,
      message:
        "Erro interno ao salvar o arquivo.",
    });
  }
});

//==============================================================//
// GAME EXPLORER • DOWNLOAD
//==============================================================//

app.get("/files/:filename", (req, res) => {
  try {
    // path.basename impede path traversal.
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
    console.error("DOWNLOAD ERROR:", error);

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
    message: "Rota não encontrada.",
  });
});

//==============================================================//
// START
//==============================================================//

app.listen(PORT, "0.0.0.0", () => {
  console.log(
    `CAFEÍNA AI + Explorer online na porta ${PORT}`
  );
});
