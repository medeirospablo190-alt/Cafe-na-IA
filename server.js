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

const MODEL =
  process.env.OPENAI_MODEL ||
  "gpt-5.4";

const PUBLIC_DIR =
  path.join(__dirname, "public");

const UPLOAD_DIR =
  process.env.UPLOAD_DIR ||
  path.join(__dirname, "uploads");

const SESSION_DIR =
  path.join(UPLOAD_DIR, "_sessions");

// ============================================================
// SEGREDOS
// ============================================================

// NUNCA coloque os valores diretamente neste arquivo.

const OPENAI_API_KEY =
  String(process.env.OPENAI_API_KEY || "");

const UPLOAD_TOKEN =
  String(process.env.UPLOAD_TOKEN || "");

const ADMIN_PASSWORD =
  String(process.env.ADMIN_PASSWORD || "");

const SESSION_SECRET =
  String(process.env.SESSION_SECRET || "");

const PUBLIC_BASE_URL =
  String(process.env.PUBLIC_BASE_URL || "")
    .replace(/\/$/, "");

// ============================================================
// LIMITES
// ============================================================

const MAX_CHUNK_BYTES =
  Number(process.env.MAX_CHUNK_BYTES || 6_000_000);

const MAX_FINAL_BYTES =
  Number(process.env.MAX_FINAL_BYTES || 300_000_000);

const MAX_CHAT_CHARS =
  Number(process.env.MAX_CHAT_CHARS || 2000);

const MAX_CHAT_OUTPUT_TOKENS =
  Number(process.env.MAX_CHAT_OUTPUT_TOKENS || 800);

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

const AUTH_TTL_MS =
  Number(
    process.env.AUTH_TTL_MS ||
    12 * 60 * 60 * 1000
  );

// ============================================================
// CORS
// ============================================================

const ALLOWED_ORIGINS =
  String(process.env.ALLOWED_ORIGINS || "")
    .split(",")
    .map(v => v.trim())
    .filter(Boolean);

// ============================================================
// PASTAS
// ============================================================

fs.mkdirSync(PUBLIC_DIR, {
  recursive: true
});

fs.mkdirSync(UPLOAD_DIR, {
  recursive: true
});

fs.mkdirSync(SESSION_DIR, {
  recursive: true
});

// ============================================================
// OPENAI
// ============================================================

const openai =
  OPENAI_API_KEY
    ? new OpenAI({
        apiKey: OPENAI_API_KEY
      })
    : null;

const conversations =
  new Map();

// ============================================================
// SEGURANÇA HTTP
// ============================================================

app.disable("x-powered-by");

app.set("trust proxy", 1);

app.use((req, res, next) => {

  res.setHeader(
    "X-Content-Type-Options",
    "nosniff"
  );

  res.setHeader(
    "X-Frame-Options",
    "DENY"
  );

  res.setHeader(
    "Referrer-Policy",
    "no-referrer"
  );

  res.setHeader(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=(), payment=()"
  );

  res.setHeader(
    "Cross-Origin-Opener-Policy",
    "same-origin"
  );

  res.setHeader(
    "Cross-Origin-Resource-Policy",
    "same-origin"
  );

  res.setHeader(
    "Strict-Transport-Security",
    "max-age=31536000; includeSubDomains"
  );

  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "img-src 'self' data:",
      "style-src 'self' 'unsafe-inline'",
      "script-src 'self'",
      "connect-src 'self'",
      "object-src 'none'",
      "base-uri 'none'",
      "frame-ancestors 'none'",
      "form-action 'self'"
    ].join("; ")
  );

  res.setHeader(
    "Cache-Control",
    "no-store"
  );

  next();
});

// ============================================================
// CORS
// ============================================================

app.use((req, res, next) => {

  const origin =
    req.headers.origin;

  if (!origin) {
    return next();
  }

  if (
    ALLOWED_ORIGINS.length === 0 ||
    ALLOWED_ORIGINS.includes(origin)
  ) {

    res.setHeader(
      "Access-Control-Allow-Origin",
      origin
    );

    res.setHeader(
      "Vary",
      "Origin"
    );

    res.setHeader(
      "Access-Control-Allow-Credentials",
      "true"
    );

    res.setHeader(
      "Access-Control-Allow-Headers",
      "Content-Type, X-Upload-Token"
    );

    res.setHeader(
      "Access-Control-Allow-Methods",
      "GET,POST,DELETE,OPTIONS"
    );

    if (req.method === "OPTIONS") {
      return res.sendStatus(204);
    }

    return next();
  }

  return res
    .status(403)
    .json({
      success: false,
      message:
        "Origem não autorizada."
    });

});

// ============================================================
// JSON BODY
// ============================================================

app.use((req, res, next) => {

  if (
    req.path === "/upload/chunk"
  ) {
    return next();
  }

  return express.json({
    limit: "1mb"
  })(req, res, next);

});

app.use(
  "/upload/chunk",
  express.json({
    limit:
      MAX_CHUNK_BYTES +
      250_000
  })
);

// ============================================================
// RATE LIMITER
// ============================================================

const rateBuckets =
  new Map();

function rateLimit({
  windowMs,
  max,
  keyPrefix
}) {

  return (
    req,
    res,
    next
  ) => {

    const now =
      Date.now();

    const ip =
      req.ip ||
      req.socket.remoteAddress ||
      "unknown";

    const key =
      `${keyPrefix}:${ip}`;

    let item =
      rateBuckets.get(key);

    if (
      !item ||
      item.resetAt <= now
    ) {

      item = {
        count: 0,
        resetAt:
          now + windowMs
      };

      rateBuckets.set(
        key,
        item
      );
    }

    item.count++;

    res.setHeader(
      "X-RateLimit-Limit",
      String(max)
    );

    res.setHeader(
      "X-RateLimit-Remaining",
      String(
        Math.max(
          0,
          max - item.count
        )
      )
    );

    if (
      item.count >
      max
    ) {

      const seconds =
        Math.max(
          1,
          Math.ceil(
            (
              item.resetAt -
              now
            ) /
            1000
          )
        );

      res.setHeader(
        "Retry-After",
        String(seconds)
      );

      return res
        .status(429)
        .json({
          success: false,
          message:
            "Muitas requisições. Tente novamente depois."
        });
    }

    next();
  };
}

const publicLimiter =
  rateLimit({
    windowMs: 60_000,
    max: 180,
    keyPrefix: "public"
  });

const authLimiter =
  rateLimit({
    windowMs:
      15 * 60_000,
    max: 10,
    keyPrefix: "auth"
  });

const chatLimiter =
  rateLimit({
    windowMs: 60_000,
    max: 10,
    keyPrefix: "chat"
  });

const uploadLimiter =
  rateLimit({
    windowMs: 60_000,
    max: 60,
    keyPrefix: "upload"
  });

// ============================================================
// HELPERS
// ============================================================

function safeEqual(a, b) {

  const aa =
    Buffer.from(
      String(a)
    );

  const bb =
    Buffer.from(
      String(b)
    );

  if (
    aa.length !==
    bb.length
  ) {
    return false;
  }

  return crypto
    .timingSafeEqual(
      aa,
      bb
    );
}

// ============================================================
// URL PÚBLICA
// ============================================================

function getBaseUrl(req) {

  if (PUBLIC_BASE_URL) {
    return PUBLIC_BASE_URL;
  }

  const proto =
    String(
      req.headers[
        "x-forwarded-proto"
      ] ||
      req.protocol ||
      "https"
    )
      .split(",")[0]
      .trim();

  return (
    `${proto}://${req.get("host")}`
  );
}

// ============================================================
// NOME SEGURO DO ARQUIVO
// ============================================================

function sanitizeJsonFileName(name) {

  let safe =
    String(
      name ||
      "export.json"
    )
      .replace(
        /[\\/:*?"<>|\x00-\x1F]/g,
        "_"
      )
      .replace(
        /\s+/g,
        "_"
      )
      .replace(
        /\.\.+/g,
        "."
      )
      .replace(
        /^\.+/,
        ""
      )
      .slice(
        0,
        100
      );

  if (!safe) {
    safe =
      "export.json";
  }

  if (
    !safe
      .toLowerCase()
      .endsWith(
        ".json"
      )
  ) {
    safe += ".json";
  }

  return safe;
}

// ============================================================
// ARQUIVOS QUE NUNCA FICAM PÚBLICOS
// ============================================================

const BLOCKED_PUBLIC_NAMES =
  new Set([
    ".env",
    ".env.local",
    ".env.production",
    ".git",
    ".gitignore",
    "package-lock.json",
    "npm-debug.log",
    "yarn-error.log"
  ]);

const BLOCKED_PUBLIC_EXTS =
  new Set([
    ".pem",
    ".key",
    ".p12",
    ".pfx",
    ".crt",
    ".cer",
    ".der",
    ".sqlite",
    ".db",
    ".bak"
  ]);

function isPublicSafeFileName(
  name
) {

  const n =
    String(
      name || ""
    );

  const lower =
    n.toLowerCase();

  if (!n) {
    return false;
  }

  if (
    n !==
    path.basename(n)
  ) {
    return false;
  }

  if (
    n.startsWith(".")
  ) {
    return false;
  }

  if (
    n.endsWith(".tmp")
  ) {
    return false;
  }

  if (
    BLOCKED_PUBLIC_NAMES
      .has(lower)
  ) {
    return false;
  }

  if (
    BLOCKED_PUBLIC_EXTS
      .has(
        path.extname(
          lower
        )
      )
  ) {
    return false;
  }

  if (
    /secret|credential|private[_-]?key|api[_-]?key/i
      .test(lower)
  ) {
    return false;
  }

  return true;
}

// ============================================================
// RESOLVER ARQUIVO
// ============================================================

function resolvePublicUpload(
  name
) {

  const requested =
    path.basename(
      String(
        name || ""
      )
    );

  if (
    !isPublicSafeFileName(
      requested
    )
  ) {
    return null;
  }

  const full =
    path.resolve(
      UPLOAD_DIR,
      requested
    );

  const root =
    path.resolve(
      UPLOAD_DIR
    ) +
    path.sep;

  if (
    !full.startsWith(
      root
    )
  ) {
    return null;
  }

  return {
    requested,
    full
  };
}

// ============================================================
// NOME ÚNICO
// ============================================================

function buildUniqueFileName(
  fileName
) {

  const safe =
    sanitizeJsonFileName(
      fileName
    );

  const ext =
    path.extname(safe) ||
    ".json";

  const base =
    path.basename(
      safe,
      ext
    );

  return (
    `${base}_` +
    `${Date.now().toString(36)}_` +
    `${crypto.randomBytes(4).toString("hex")}` +
    ext
  );
}

// ============================================================
// UPLOAD ID
// ============================================================

function safeUploadId(
  value
) {

  const id =
    String(
      value || ""
    );

  return /^[a-f0-9]{32}$/i
    .test(id)
      ? id
      : null;
}

function sessionPath(id) {

  return path.join(
    SESSION_DIR,
    id
  );
}

function manifestPath(id) {

  return path.join(
    sessionPath(id),
    "manifest.json"
  );
}

function chunkPath(
  id,
  index
) {

  return path.join(
    sessionPath(id),
    `chunk-${String(index).padStart(6, "0")}.json`
  );
}

function hashText(text) {

  return crypto
    .createHash(
      "sha256"
    )
    .update(
      text,
      "utf8"
    )
    .digest(
      "hex"
    );
}

// ============================================================
// MANIFEST
// ============================================================

function readManifest(id) {

  try {

    return JSON.parse(
      fs.readFileSync(
        manifestPath(id),
        "utf8"
      )
    );

  } catch {

    return null;

  }
}

function writeManifest(
  id,
  data
) {

  fs.writeFileSync(
    manifestPath(id),
    JSON.stringify(
      data,
      null,
      2
    ),
    "utf8"
  );
}

function removeDirectorySafe(
  dir
) {

  try {

    fs.rmSync(
      dir,
      {
        recursive: true,
        force: true
      }
    );

  } catch {}
}

// ============================================================
// LIMPEZA DE UPLOADS INCOMPLETOS
// ============================================================

function cleanupExpiredSessions() {

  let entries = [];

  try {

    entries =
      fs.readdirSync(
        SESSION_DIR,
        {
          withFileTypes:
            true
        }
      );

  } catch {

    return;

  }

  const now =
    Date.now();

  for (
    const entry
    of entries
  ) {

    if (
      !entry.isDirectory()
    ) {
      continue;
    }

    const dir =
      path.join(
        SESSION_DIR,
        entry.name
      );

    try {

      const stat =
        fs.statSync(dir);

      if (
        now -
        stat.mtimeMs >
        SESSION_TTL_MS
      ) {

        removeDirectorySafe(
          dir
        );

      }

    } catch {}

  }
}

// ============================================================
// TOKEN DE UPLOAD
// ============================================================

function requireUploadToken(
  req,
  res,
  next
) {

  // IMPORTANTE:
  // sem token configurado,
  // upload fica DESATIVADO.

  if (
    !UPLOAD_TOKEN
  ) {

    return res
      .status(503)
      .json({
        success: false,
        message:
          "Upload desativado no servidor."
      });
  }

  const received =
    String(
      req.headers[
        "x-upload-token"
      ] ||
      req.body?.token ||
      ""
    );

  if (
    !safeEqual(
      received,
      UPLOAD_TOKEN
    )
  ) {

    return res
      .status(401)
      .json({
        success: false,
        message:
          "Não autorizado."
      });
  }

  next();
}

// ============================================================
// LOGIN ADMIN
// ============================================================

function signSession(
  expiresAt
) {

  const payload =
    `${expiresAt}`;

  const sig =
    crypto
      .createHmac(
        "sha256",
        SESSION_SECRET
      )
      .update(
        payload
      )
      .digest(
        "hex"
      );

  return (
    `${payload}.${sig}`
  );
}

function verifySession(
  token
) {

  if (
    !SESSION_SECRET ||
    !token
  ) {
    return false;
  }

  const [
    exp,
    sig
  ] =
    String(token)
      .split(".");

  if (
    !exp ||
    !sig ||
    !/^\d+$/.test(exp)
  ) {
    return false;
  }

  if (
    Number(exp) <
    Date.now()
  ) {
    return false;
  }

  const expected =
    crypto
      .createHmac(
        "sha256",
        SESSION_SECRET
      )
      .update(exp)
      .digest("hex");

  return safeEqual(
    sig,
    expected
  );
}

function parseCookies(req) {

  const out = {};

  for (
    const part
    of String(
      req.headers.cookie ||
      ""
    ).split(";")
  ) {

    const i =
      part.indexOf("=");

    if (
      i > -1
    ) {

      out[
        decodeURIComponent(
          part
            .slice(0, i)
            .trim()
        )
      ] =
        decodeURIComponent(
          part
            .slice(i + 1)
            .trim()
        );

    }
  }

  return out;
}

function requireAdminSession(
  req,
  res,
  next
) {

  if (
    !ADMIN_PASSWORD ||
    !SESSION_SECRET
  ) {

    return res
      .status(503)
      .json({
        success: false,
        message:
          "Área privada não configurada."
      });
  }

  const token =
    parseCookies(req)
      .cafeina_admin;

  if (
    !verifySession(token)
  ) {

    return res
      .status(401)
      .json({
        success: false,
        message:
          "Faça login."
      });
  }

  next();
}

// ============================================================
// STREAM HELPERS
// ============================================================

async function writeWithBackpressure(
  stream,
  text
) {

  if (
    stream.write(text)
  ) {
    return;
  }

  await new Promise(
    (
      resolve,
      reject
    ) => {

      stream.once(
        "drain",
        resolve
      );

      stream.once(
        "error",
        reject
      );

    }
  );
}

async function finishStream(
  stream
) {

  await new Promise(
    (
      resolve,
      reject
    ) => {

      stream.once(
        "finish",
        resolve
      );

      stream.once(
        "error",
        reject
      );

      stream.end();

    }
  );
}

// ============================================================
// SITE PÚBLICO
// ============================================================

app.use(
  express.static(
    PUBLIC_DIR,
    {
      index:
        "index.html",

      dotfiles:
        "deny",

      etag:
        true,

      maxAge:
        "1h"
    }
  )
);

// ============================================================
// HEALTH
// ============================================================

app.get(
  "/health",
  publicLimiter,
  (
    _req,
    res
  ) => {

    res.json({
      ok: true,
      service:
        "CAFEINA",
      ai:
        Boolean(
          openai
        ),
      files:
        true
    });

  }
);

// ============================================================
// LOGIN
// ============================================================

app.post(
  "/api/auth/login",
  authLimiter,
  (
    req,
    res
  ) => {

    if (
      !ADMIN_PASSWORD ||
      !SESSION_SECRET
    ) {

      return res
        .status(503)
        .json({
          success:
            false,
          message:
            "Login privado não configurado."
        });
    }

    const password =
      String(
        req.body?.password ||
        ""
      );

    if (
      !safeEqual(
        password,
        ADMIN_PASSWORD
      )
    ) {

      return res
        .status(401)
        .json({
          success:
            false,
          message:
            "Senha inválida."
        });
    }

    const expiresAt =
      Date.now() +
      AUTH_TTL_MS;

    const token =
      signSession(
        expiresAt
      );

    res.setHeader(
      "Set-Cookie",

      `cafeina_admin=${encodeURIComponent(token)}; ` +
      `HttpOnly; Secure; SameSite=Strict; Path=/; ` +
      `Max-Age=${Math.floor(AUTH_TTL_MS / 1000)}`
    );

    res.json({
      success:
        true,
      expiresAt
    });

  }
);

// ============================================================
// LOGOUT
// ============================================================

app.post(
  "/api/auth/logout",
  (
    _req,
    res
  ) => {

    res.setHeader(
      "Set-Cookie",
      "cafeina_admin=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0"
    );

    res.json({
      success:
        true
    });

  }
);

// ============================================================
// LISTAGEM PÚBLICA DE ARQUIVOS
// ============================================================

app.get(
  "/api/files",
  publicLimiter,
  (
    req,
    res
  ) => {

    try {

      const files =
        fs.readdirSync(
          UPLOAD_DIR,
          {
            withFileTypes:
              true
          }
        )

          .filter(
            e =>
              e.isFile() &&
              isPublicSafeFileName(
                e.name
              )
          )

          .map(e => {

            const full =
              path.join(
                UPLOAD_DIR,
                e.name
              );

            const stat =
              fs.statSync(
                full
              );

            const encoded =
              encodeURIComponent(
                e.name
              );

            return {

              name:
                e.name,

              bytes:
                stat.size,

              createdAt:
                stat.birthtime
                  .toISOString(),

              modifiedAt:
                stat.mtime
                  .toISOString(),

              infoUrl:
                `${getBaseUrl(req)}/api/files/${encoded}/info`,

              downloadUrl:
                `${getBaseUrl(req)}/files/${encoded}`
            };

          })

          .sort(
            (a, b) =>
              new Date(
                b.modifiedAt
              ) -
              new Date(
                a.modifiedAt
              )
          );

      res.json({
        success:
          true,

        count:
          files.length,

        files
      });

    } catch {

      res
        .status(500)
        .json({
          success:
            false,

          message:
            "Erro ao listar arquivos."
        });

    }

  }
);

// ============================================================
// INFO PÚBLICA
// ============================================================

app.get(
  "/api/files/:filename/info",
  publicLimiter,
  (
    req,
    res
  ) => {

    const item =
      resolvePublicUpload(
        req.params.filename
      );

    if (
      !item ||
      !fs.existsSync(
        item.full
      ) ||
      !fs.statSync(
        item.full
      ).isFile()
    ) {

      return res
        .status(404)
        .json({
          success:
            false,

          message:
            "Arquivo não encontrado."
        });
    }

    const stat =
      fs.statSync(
        item.full
      );

    res.json({

      success:
        true,

      file: {

        name:
          item.requested,

        bytes:
          stat.size,

        createdAt:
          stat.birthtime
            .toISOString(),

        modifiedAt:
          stat.mtime
            .toISOString(),

        downloadUrl:
          `${getBaseUrl(req)}/files/${encodeURIComponent(item.requested)}`

      }

    });

  }
);

// ============================================================
// DOWNLOAD PÚBLICO
// ============================================================

app.get(
  "/files/:filename",
  publicLimiter,
  (
    req,
    res
  ) => {

    const item =
      resolvePublicUpload(
        req.params.filename
      );

    if (
      !item ||
      !fs.existsSync(
        item.full
      ) ||
      !fs.statSync(
        item.full
      ).isFile()
    ) {

      return res
        .status(404)
        .json({
          success:
            false,

          message:
            "Arquivo não encontrado."
        });
    }

    res.setHeader(
      "Content-Security-Policy",
      "default-src 'none'; sandbox"
    );

    res.setHeader(
      "X-Content-Type-Options",
      "nosniff"
    );

    return res.download(
      item.full,
      item.requested
    );

  }
);

// ============================================================
// EXCLUSÃO PRIVADA
// ============================================================

app.delete(
  "/api/files/:filename",
  requireAdminSession,
  (
    req,
    res
  ) => {

    const item =
      resolvePublicUpload(
        req.params.filename
      );

    if (
      !item ||
      !fs.existsSync(
        item.full
      )
    ) {

      return res
        .status(404)
        .json({
          success:
            false,

          message:
            "Arquivo não encontrado."
        });
    }

    fs.rmSync(
      item.full,
      {
        force:
          true
      }
    );

    res.json({
      success:
        true,

      deleted:
        item.requested
    });

  }
);

// ============================================================
// CHAT PRIVADO
// ============================================================

app.post(
  "/chat",
  chatLimiter,
  requireAdminSession,
  async (
    req,
    res
  ) => {

    try {

      if (
        !openai
      ) {

        return res
          .status(503)
          .json({
            message:
              "IA indisponível."
          });

      }

      const message =
        typeof req.body?.message ===
        "string"
          ? req.body.message.trim()
          : "";

      if (
        !message
      ) {

        return res
          .status(400)
          .json({
            message:
              "Mensagem inválida."
          });

      }

      if (
        message.length >
        MAX_CHAT_CHARS
      ) {

        return res
          .status(413)
          .json({
            message:
              `Limite de ${MAX_CHAT_CHARS} caracteres.`
          });

      }

      const cookie =
        parseCookies(req)
          .cafeina_admin ||
        "session";

      const sessionKey =
        crypto
          .createHash(
            "sha256"
          )
          .update(
            String(cookie)
          )
          .digest(
            "hex"
          );

      const previousResponseId =
        conversations.get(
          sessionKey
        );

      const request = {

        model:
          MODEL,

        instructions:
          "Você é CAFEÍNA AI. Responda em português do Brasil por padrão. Seja clara, objetiva e útil.",

        input:
          message,

        max_output_tokens:
          MAX_CHAT_OUTPUT_TOKENS

      };

      if (
        previousResponseId
      ) {

        request.previous_response_id =
          previousResponseId;

      }

      const response =
        await openai
          .responses
          .create(
            request
          );

      conversations.set(
        sessionKey,
        response.id
      );

      res.json({
        message:
          response.output_text ||
          "A IA não retornou texto."
      });

    } catch (
      error
    ) {

      console.error(
        "CHAT ERROR:",
        error?.status ||
        error?.name ||
        "unknown"
      );

      res
        .status(500)
        .json({
          message:
            "Erro ao consultar a IA."
        });

    }

  }
);

// ============================================================
// RESET DO CHAT
// ============================================================

app.post(
  "/reset",
  requireAdminSession,
  (
    req,
    res
  ) => {

    const cookie =
      parseCookies(req)
        .cafeina_admin ||
      "session";

    const sessionKey =
      crypto
        .createHash(
          "sha256"
        )
        .update(
          String(cookie)
        )
        .digest(
          "hex"
        );

    conversations.delete(
      sessionKey
    );

    res.json({
      ok:
        true
    });

  }
);

// ============================================================
// INICIAR UPLOAD
// ============================================================

app.post(
  "/upload/start",
  uploadLimiter,
  requireUploadToken,
  (
    req,
    res
  ) => {

    cleanupExpiredSessions();

    const filename =
      sanitizeJsonFileName(
        req.body?.filename
      );

    const source =
      String(
        req.body?.source ||
        "cafeina-scanner"
      )
        .replace(
          /[\x00-\x1F]/g,
          ""
        )
        .slice(
          0,
          100
        );

    const metadata =
      req.body?.metadata &&
      typeof req.body.metadata ===
      "object" &&
      !Array.isArray(
        req.body.metadata
      )
        ? req.body.metadata
        : {};

    const uploadId =
      crypto
        .randomBytes(16)
        .toString("hex");

    fs.mkdirSync(
      sessionPath(
        uploadId
      ),
      {
        recursive:
          true
      }
    );

    const now =
      new Date()
        .toISOString();

    writeManifest(
      uploadId,
      {

        uploadId,

        filename,

        source,

        metadata,

        createdAt:
          now,

        updatedAt:
          now,

        chunks:
          {},

        chunkCount:
          0,

        objectCount:
          0,

        receivedBytes:
          0,

        finished:
          false

      }
    );

    res
      .status(201)
      .json({

        success:
          true,

        uploadId,

        filename,

        limits: {

          maxChunkBytes:
            MAX_CHUNK_BYTES,

          maxFinalBytes:
            MAX_FINAL_BYTES

        }

      });

  }
);

// ============================================================
// STATUS DO UPLOAD
// ============================================================

app.get(
  "/api/uploads/:uploadId",
  uploadLimiter,
  requireUploadToken,
  (
    req,
    res
  ) => {

    const uploadId =
      safeUploadId(
        req.params.uploadId
      );

    const manifest =
      uploadId
        ? readManifest(
            uploadId
          )
        : null;

    if (
      !manifest
    ) {

      return res
        .status(404)
        .json({
          success:
            false,

          message:
            "Sessão não encontrada."
        });

    }

    res.json({

      success:
        true,

      upload: {

        uploadId:
          manifest.uploadId,

        filename:
          manifest.filename,

        createdAt:
          manifest.createdAt,

        updatedAt:
          manifest.updatedAt,

        chunkCount:
          manifest.chunkCount ||
          0,

        objectCount:
          manifest.objectCount ||
          0,

        receivedBytes:
          manifest.receivedBytes ||
          0,

        finished:
          Boolean(
            manifest.finished
          )

      }

    });

  }
);

// ============================================================
// ENVIAR CHUNK
// ============================================================

app.post(
  "/upload/chunk",
  uploadLimiter,
  requireUploadToken,
  (
    req,
    res
  ) => {

    try {

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
        index > 100000 ||
        !Array.isArray(
          objects
        )
      ) {

        return res
          .status(400)
          .json({
            success:
              false,

            message:
              "Chunk inválido."
          });

      }

      const manifest =
        readManifest(
          uploadId
        );

      if (
        !manifest
      ) {

        return res
          .status(404)
          .json({
            success:
              false,

            message:
              "Sessão não encontrada."
          });

      }

      if (
        manifest.finished
      ) {

        return res
          .status(409)
          .json({
            success:
              false,

            message:
              "Sessão já finalizada."
          });

      }

      const encoded =
        JSON.stringify(
          objects
        );

      const bytes =
        Buffer.byteLength(
          encoded,
          "utf8"
        );

      if (
        bytes >
        MAX_CHUNK_BYTES
      ) {

        return res
          .status(413)
          .json({
            success:
              false,

            message:
              "Chunk acima do limite."
          });

      }

      if (
        (
          manifest.receivedBytes ||
          0
        ) +
        bytes >
        MAX_FINAL_BYTES
      ) {

        return res
          .status(413)
          .json({
            success:
              false,

            message:
              "Upload acima do limite final."
          });

      }

      const hash =
        hashText(
          encoded
        );

      const existing =
        manifest
          .chunks[
            String(index)
          ];

      if (
        existing
      ) {

        if (
          existing.sha256 ===
            hash &&
          existing.bytes ===
            bytes
        ) {

          return res.json({
            success:
              true,

            duplicate:
              true,

            uploadId,

            index
          });

        }

        return res
          .status(409)
          .json({
            success:
              false,

            message:
              "Chunk já existe com conteúdo diferente."
          });

      }

      fs.writeFileSync(
        chunkPath(
          uploadId,
          index
        ),
        encoded,
        "utf8"
      );

      manifest
        .chunks[
          String(index)
        ] = {

          bytes,

          objects:
            objects.length,

          sha256:
            hash,

          receivedAt:
            new Date()
              .toISOString()

        };

      manifest.chunkCount =
        Number(
          manifest.chunkCount ||
          0
        ) +
        1;

      manifest.objectCount =
        Number(
          manifest.objectCount ||
          0
        ) +
        objects.length;

      manifest.receivedBytes =
        Number(
          manifest.receivedBytes ||
          0
        ) +
        bytes;

      manifest.updatedAt =
        new Date()
          .toISOString();

      writeManifest(
        uploadId,
        manifest
      );

      res.json({

        success:
          true,

        uploadId,

        index,

        bytes,

        objectCount:
          objects.length,

        totals: {

          chunks:
            manifest.chunkCount,

          objects:
            manifest.objectCount,

          bytes:
            manifest.receivedBytes

        }

      });

    } catch {

      res
        .status(500)
        .json({
          success:
            false,

          message:
            "Erro ao salvar chunk."
        });

    }

  }
);

// ============================================================
// FINALIZAR UPLOAD
// ============================================================

app.post(
  "/upload/finish",
  uploadLimiter,
  requireUploadToken,
  async (
    req,
    res
  ) => {

    let tempPath =
      null;

    try {

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
        typeof req.body.summary ===
        "object" &&
        !Array.isArray(
          req.body.summary
        )
          ? req.body.summary
          : {};

      if (
        !uploadId ||
        !Number.isInteger(
          totalChunks
        ) ||
        totalChunks < 1 ||
        totalChunks > 100000
      ) {

        return res
          .status(400)
          .json({
            success:
              false,

            message:
              "Finalização inválida."
          });

      }

      const manifest =
        readManifest(
          uploadId
        );

      if (
        !manifest
      ) {

        return res
          .status(404)
          .json({
            success:
              false,

            message:
              "Sessão não encontrada."
          });

      }

      if (
        manifest.finished
      ) {

        return res
          .status(409)
          .json({
            success:
              false,

            message:
              "Sessão já finalizada."
          });

      }

      for (
        let i = 1;
        i <= totalChunks;
        i++
      ) {

        if (
          !fs.existsSync(
            chunkPath(
              uploadId,
              i
            )
          )
        ) {

          return res
            .status(409)
            .json({
              success:
                false,

              message:
                `Chunk ${i} ausente.`
            });

        }

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
            encoding:
              "utf8",

            flags:
              "wx",

            mode:
              0o600
          }
        );

      await writeWithBackpressure(
        stream,
        "{\n"
      );

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

      await writeWithBackpressure(
        stream,
        `"objects":[\n`
      );

      let first =
        true;

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

        const arr =
          JSON.parse(
            raw
          );

        if (
          !Array.isArray(
            arr
          )
        ) {
          throw new Error(
            "chunk invalid"
          );
        }

        for (
          const object
          of arr
        ) {

          if (
            !first
          ) {

            await writeWithBackpressure(
              stream,
              ",\n"
            );

          }

          await writeWithBackpressure(
            stream,
            JSON.stringify(
              object
            )
          );

          first =
            false;

        }

      }

      await writeWithBackpressure(
        stream,
        "\n]\n}"
      );

      await finishStream(
        stream
      );

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
            force:
              true
          }
        );

        tempPath =
          null;

        return res
          .status(413)
          .json({
            success:
              false,

            message:
              "Arquivo final acima do limite."
          });

      }

      await fsp.rename(
        tempPath,
        finalPath
      );

      tempPath =
        null;

      removeDirectorySafe(
        sessionPath(
          uploadId
        )
      );

      const url =
        `${getBaseUrl(req)}/files/${encodeURIComponent(storedFileName)}`;

      res
        .status(201)
        .json({

          success:
            true,

          filename:
            storedFileName,

          bytes:
            finalSize,

          objectCount:
            manifest.objectCount ||
            0,

          chunkCount:
            totalChunks,

          url,

          downloadUrl:
            url

        });

    } catch {

      if (
        tempPath
      ) {

        try {

          await fsp.rm(
            tempPath,
            {
              force:
                true
            }
          );

        } catch {}

      }

      res
        .status(500)
        .json({
          success:
            false,

          message:
            "Erro ao montar arquivo final."
        });

    }

  }
);

// ============================================================
// CANCELAR UPLOAD
// ============================================================

app.post(
  "/upload/cancel",
  uploadLimiter,
  requireUploadToken,
  (
    req,
    res
  ) => {

    const uploadId =
      safeUploadId(
        req.body?.uploadId
      );

    if (
      !uploadId
    ) {

      return res
        .status(400)
        .json({
          success:
            false,

          message:
            "uploadId inválido."
        });

    }

    removeDirectorySafe(
      sessionPath(
        uploadId
      )
    );

    res.json({
      success:
        true,

      cancelled:
        true
    });

  }
);

// ============================================================
// TRATAMENTO DE ERROS
// ============================================================

app.use(
  (
    err,
    _req,
    res,
    _next
  ) => {

    console.error(
      "SERVER ERROR:",
      err?.name ||
      "Error"
    );

    if (
      err?.type ===
      "entity.too.large"
    ) {

      return res
        .status(413)
        .json({
          success:
            false,

          message:
            "Conteúdo acima do limite."
        });

    }

    res
      .status(500)
      .json({
        success:
          false,

        message:
          "Erro interno."
      });

  }
);

// ============================================================
// 404
// ============================================================

app.use(
  (
    _req,
    res
  ) => {

    res
      .status(404)
      .json({
        ok:
          false,

        message:
          "Rota não encontrada."
      });

  }
);

// ============================================================
// LIMPEZA
// ============================================================

cleanupExpiredSessions();

const cleanupTimer =
  setInterval(
    cleanupExpiredSessions,
    CLEANUP_INTERVAL_MS
  );

cleanupTimer
  .unref?.();

// ============================================================
// INICIAR SERVIDOR
// ============================================================

app.listen(
  PORT,
  "0.0.0.0",
  () => {

    console.log(
      `CAFEÍNA online na porta ${PORT}`
    );

    console.log(
      `IA: ${
        openai
          ? "configurada"
          : "desativada"
      }`
    );

    console.log(
      `Upload: ${
        UPLOAD_TOKEN
          ? "protegido por token"
          : "DESATIVADO - UPLOAD_TOKEN ausente"
      }`
    );

    console.log(
      `Chat privado: ${
        ADMIN_PASSWORD &&
        SESSION_SECRET
          ? "ativo"
          : "desativado"
      }`
    );

  }
);
