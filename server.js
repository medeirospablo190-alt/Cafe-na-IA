const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const app = express();

// ============================================================
// CONFIGURAÇÃO
// ============================================================

const PORT = process.env.PORT || 10000;

const ROOT_DIR = __dirname;
const PUBLIC_DIR = path.join(ROOT_DIR, "public");
const UPLOAD_DIR = path.join(ROOT_DIR, "uploads");
const DATA_DIR = path.join(ROOT_DIR, "data");

const DIAGNOSTICS_FILE = path.join(
  DATA_DIR,
  "diagnostics.json"
);

const MAX_UPLOAD_BYTES =
  Number(process.env.MAX_UPLOAD_BYTES) ||
  6000000;

const MAX_DIAGNOSTICS = Math.min(
  Number(process.env.MAX_DIAGNOSTICS) || 500,
  2000
);

const UPLOAD_TOKEN =
  String(process.env.UPLOAD_TOKEN || "");

const DIAGNOSTICS_TOKEN =
  String(process.env.DIAGNOSTICS_TOKEN || "");

const OPENAI_API_KEY =
  String(process.env.OPENAI_API_KEY || "");

// ============================================================
// CRIAR PASTAS
// ============================================================

fs.mkdirSync(UPLOAD_DIR, {
  recursive: true
});

fs.mkdirSync(DATA_DIR, {
  recursive: true
});

if (!fs.existsSync(DIAGNOSTICS_FILE)) {
  fs.writeFileSync(
    DIAGNOSTICS_FILE,
    "[]",
    "utf8"
  );
}

// ============================================================
// EXPRESS
// ============================================================

app.disable("x-powered-by");

app.use(
  express.json({
    limit: Math.max(
      MAX_UPLOAD_BYTES + 500000,
      1000000
    )
  })
);

app.use(
  express.urlencoded({
    extended: false,
    limit: "1mb"
  })
);

// ============================================================
// HEADERS DE SEGURANÇA
// ============================================================

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
    "camera=(), microphone=(), geolocation=()"
  );

  res.setHeader(
    "Cache-Control",
    "no-store"
  );

  next();
});

// ============================================================
// HELPERS
// ============================================================

function safeString(
  value,
  maxLength = 1000
) {
  return String(value ?? "")
    .slice(0, maxLength);
}

function sanitizeFileName(name) {
  let safe =
    String(name || "export.json")
      .replace(/[\\/:*?"<>|]/g, "_")
      .replace(/\s+/g, "_")
      .replace(/\.\.+/g, ".")
      .replace(/^\.*/, "");

  if (!safe) {
    safe = "export.json";
  }

  if (
    !safe
      .toLowerCase()
      .endsWith(".json")
  ) {
    safe += ".json";
  }

  return safe.slice(0, 120);
}

function buildUniqueFileName(fileName) {
  const safe =
    sanitizeFileName(fileName);

  const ext =
    path.extname(safe) || ".json";

  const base =
    path.basename(safe, ext);

  const stamp =
    Date.now().toString(36);

  const random =
    crypto
      .randomBytes(4)
      .toString("hex");

  return `${base}_${stamp}_${random}${ext}`;
}

function getBaseUrl(req) {
  const protocol =
    req.headers["x-forwarded-proto"] ||
    req.protocol;

  const host =
    req.get("host");

  return `${protocol}://${host}`;
}

function timingSafeCompare(
  received,
  expected
) {
  const a =
    Buffer.from(
      String(received || "")
    );

  const b =
    Buffer.from(
      String(expected || "")
    );

  if (
    a.length === 0 ||
    b.length === 0 ||
    a.length !== b.length
  ) {
    return false;
  }

  try {
    return crypto.timingSafeEqual(
      a,
      b
    );
  } catch {
    return false;
  }
}

function getRequestToken(req) {
  return String(
    req.headers["x-cafeina-token"] ||
    req.body?.token ||
    ""
  );
}

function validateOptionalToken(
  req,
  expectedToken
) {
  if (!expectedToken) {
    return true;
  }

  return timingSafeCompare(
    getRequestToken(req),
    expectedToken
  );
}

// ============================================================
// DIAGNÓSTICOS
// ============================================================

function readDiagnostics() {
  try {
    if (
      !fs.existsSync(
        DIAGNOSTICS_FILE
      )
    ) {
      return [];
    }

    const raw =
      fs.readFileSync(
        DIAGNOSTICS_FILE,
        "utf8"
      );

    const parsed =
      JSON.parse(raw);

    return Array.isArray(parsed)
      ? parsed
      : [];
  } catch (error) {
    console.error(
      "Erro ao ler diagnósticos:",
      error
    );

    return [];
  }
}

function writeDiagnostics(items) {
  const tempFile =
    `${DIAGNOSTICS_FILE}.tmp`;

  fs.writeFileSync(
    tempFile,
    JSON.stringify(
      items,
      null,
      2
    ),
    "utf8"
  );

  fs.renameSync(
    tempFile,
    DIAGNOSTICS_FILE
  );
}

function normalizeDiagnostic(body) {
  const source =
    body &&
    typeof body === "object"
      ? body
      : {};

  return {
    id:
      typeof crypto.randomUUID ===
      "function"
        ? crypto.randomUUID()
        : crypto
            .randomBytes(16)
            .toString("hex"),

    receivedAt:
      new Date().toISOString(),

    type:
      safeString(
        source.type || "runtime",
        50
      ),

    scriptName:
      safeString(
        source.scriptName ||
        source.script ||
        "",
        300
      ),

    scriptUrl:
      safeString(
        source.scriptUrl || "",
        2000
      ),

    message:
      safeString(
        source.message ||
        "Erro sem mensagem.",
        20000
      ),

    trace:
      safeString(
        source.trace ||
        source.stack ||
        "",
        50000
      ),

    version:
      safeString(
        source.version || "",
        100
      ),

    placeId:
      safeString(
        source.placeId || "",
        100
      ),

    gameId:
      safeString(
        source.gameId || "",
        100
      ),

    executor:
      safeString(
        source.executor || "",
        200
      ),

    clientTime:
      source.clientTime
        ? safeString(
            source.clientTime,
            100
          )
        : null
  };
}

// ============================================================
// SITE
// ============================================================

// IMPORTANTE:
//
// Estrutura esperada:
//
// projeto/
// ├── server.js
// ├── package.json
// └── public/
//     ├── index.html
//     ├── app.js
//     └── styles.css
//

app.use(
  express.static(
    PUBLIC_DIR,
    {
      index: false,
      fallthrough: true
    }
  )
);

app.get("/", (req, res) => {
  const indexFile =
    path.join(
      PUBLIC_DIR,
      "index.html"
    );

  if (
    !fs.existsSync(
      indexFile
    )
  ) {
    return res
      .status(500)
      .send(
        "Erro: public/index.html não foi encontrado."
      );
  }

  return res.sendFile(
    indexFile
  );
});

// ============================================================
// HEALTH
// ============================================================

app.get(
  "/health",
  (req, res) => {
    return res.json({
      ok: true,

      service:
        "CAFEINA",

      web: true,

      files: true,

      diagnostics: true,

      ai:
        Boolean(
          OPENAI_API_KEY
        ),

      storage: {
        type:
          "local",

        persistent:
          false,

        note:
          "Arquivos locais podem ser apagados quando a instância do Render for recriada."
      },

      limits: {
        maxUploadBytes:
          MAX_UPLOAD_BYTES,

        maxDiagnostics:
          MAX_DIAGNOSTICS
      },

      uptime:
        process.uptime()
    });
  }
);

// ============================================================
// STATUS DA IA
// ============================================================

// A chave nunca é enviada ao navegador.
// A API retorna apenas true/false.

app.get(
  "/api/ai/status",
  (req, res) => {
    return res.json({
      ok: true,

      available:
        Boolean(
          OPENAI_API_KEY
        )
    });
  }
);

// ============================================================
// LISTAR ARQUIVOS
// ============================================================

app.get(
  "/api/files",
  (req, res) => {
    try {
      const names =
        fs.readdirSync(
          UPLOAD_DIR
        );

      const files =
        names
          .map(name => {
            try {
              const fullPath =
                path.join(
                  UPLOAD_DIR,
                  name
                );

              const stat =
                fs.statSync(
                  fullPath
                );

              if (
                !stat.isFile()
              ) {
                return null;
              }

              return {
                name,

                filename:
                  name,

                bytes:
                  stat.size,

                size:
                  stat.size,

                createdAt:
                  stat.birthtime
                    .toISOString(),

                updatedAt:
                  stat.mtime
                    .toISOString(),

                downloadUrl:
                  `/files/${encodeURIComponent(
                    name
                  )}`
              };
            } catch {
              return null;
            }
          })
          .filter(Boolean)
          .sort(
            (a, b) =>
              new Date(
                b.updatedAt
              ) -
              new Date(
                a.updatedAt
              )
          );

      const totalBytes =
        files.reduce(
          (total, file) =>
            total +
            Number(
              file.bytes || 0
            ),
          0
        );

      return res.json({
        ok: true,

        count:
          files.length,

        totalBytes,

        files
      });

    } catch (error) {
      console.error(
        "Erro ao listar arquivos:",
        error
      );

      return res
        .status(500)
        .json({
          ok: false,

          message:
            "Não foi possível listar os arquivos.",

          files: []
        });
    }
  }
);

// ============================================================
// UPLOAD
// ============================================================

app.post(
  "/upload",
  (req, res) => {
    try {
      if (
        !validateOptionalToken(
          req,
          UPLOAD_TOKEN
        )
      ) {
        return res
          .status(401)
          .json({
            success: false,
            ok: false,

            error:
              "Token inválido."
          });
      }

      const originalFileName =
        sanitizeFileName(
          req.body?.filename
        );

      let content =
        req.body?.content;

      if (
        content === undefined ||
        content === null
      ) {
        return res
          .status(400)
          .json({
            success: false,
            ok: false,

            error:
              "Conteúdo vazio."
          });
      }

      if (
        typeof content !==
        "string"
      ) {
        content =
          JSON.stringify(
            content
          );
      }

      const byteLength =
        Buffer.byteLength(
          content,
          "utf8"
        );

      if (
        byteLength >
        MAX_UPLOAD_BYTES
      ) {
        return res
          .status(413)
          .json({
            success: false,
            ok: false,

            error:
              "Arquivo acima do limite permitido.",

            maxBytes:
              MAX_UPLOAD_BYTES,

            receivedBytes:
              byteLength
          });
      }

      let parsed;

      try {
        parsed =
          JSON.parse(content);
      } catch {
        return res
          .status(400)
          .json({
            success: false,
            ok: false,

            error:
              "O conteúdo precisa ser JSON válido."
          });
      }

      const storedFileName =
        buildUniqueFileName(
          originalFileName
        );

      const filePath =
        path.join(
          UPLOAD_DIR,
          storedFileName
        );

      const wrapper = {
        uploadedAt:
          new Date()
            .toISOString(),

        source:
          safeString(
            req.body?.source ||
            "unknown",
            200
          ),

        originalFileName,

        data:
          parsed
      };

      fs.writeFileSync(
        filePath,
        JSON.stringify(
          wrapper,
          null,
          2
        ),
        "utf8"
      );

      const relativeUrl =
        `/files/${encodeURIComponent(
          storedFileName
        )}`;

      return res
        .status(201)
        .json({
          success: true,
          ok: true,

          filename:
            storedFileName,

          bytes:
            byteLength,

          downloadUrl:
            relativeUrl,

          url:
            getBaseUrl(req) +
            relativeUrl
        });

    } catch (error) {
      console.error(
        "Erro no upload:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
          ok: false,

          error:
            "Erro interno ao salvar o arquivo."
        });
    }
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
            ok: false,
            error:
              "Nome inválido."
          });
      }

      const filePath =
        path.resolve(
          UPLOAD_DIR,
          requested
        );

      const uploadsRoot =
        path.resolve(
          UPLOAD_DIR
        ) +
        path.sep;

      if (
        !filePath.startsWith(
          uploadsRoot
        )
      ) {
        return res
          .status(403)
          .json({
            ok: false,
            error:
              "Acesso negado."
          });
      }

      if (
        !fs.existsSync(
          filePath
        )
      ) {
        return res
          .status(404)
          .json({
            ok: false,
            error:
              "Arquivo não encontrado."
          });
      }

      return res.download(
        filePath,
        requested
      );

    } catch (error) {
      console.error(
        "Erro no download:",
        error
      );

      return res
        .status(500)
        .json({
          ok: false,
          error:
            "Erro interno ao baixar o arquivo."
        });
    }
  }
);

// ============================================================
// RECEBER DIAGNÓSTICO
// ============================================================

app.post(
  "/api/diagnostics",
  (req, res) => {
    try {
      if (
        !validateOptionalToken(
          req,
          DIAGNOSTICS_TOKEN
        )
      ) {
        return res
          .status(401)
          .json({
            ok: false,
            message:
              "Token de diagnóstico inválido."
          });
      }

      const diagnostic =
        normalizeDiagnostic(
          req.body
        );

      const diagnostics =
        readDiagnostics();

      diagnostics.push(
        diagnostic
      );

      while (
        diagnostics.length >
        MAX_DIAGNOSTICS
      ) {
        diagnostics.shift();
      }

      writeDiagnostics(
        diagnostics
      );

      return res
        .status(201)
        .json({
          ok: true,
          received: true,

          id:
            diagnostic.id
        });

    } catch (error) {
      console.error(
        "Erro ao salvar diagnóstico:",
        error
      );

      return res
        .status(500)
        .json({
          ok: false,

          message:
            "Erro ao salvar diagnóstico."
        });
    }
  }
);

// ============================================================
// CONSULTAR DIAGNÓSTICOS
// ============================================================

app.get(
  "/api/diagnostics",
  (req, res) => {
    try {
      const diagnostics =
        readDiagnostics();

      return res.json({
        ok: true,

        count:
          diagnostics.length,

        diagnostics
      });

    } catch (error) {
      console.error(
        "Erro ao consultar diagnósticos:",
        error
      );

      return res
        .status(500)
        .json({
          ok: false,

          diagnostics: [],

          message:
            "Erro ao consultar diagnósticos."
        });
    }
  }
);

// ============================================================
// LIMPAR DIAGNÓSTICOS
// ============================================================

app.delete(
  "/api/diagnostics",
  (req, res) => {
    try {
      writeDiagnostics([]);

      return res.json({
        ok: true,
        cleared: true
      });

    } catch (error) {
      console.error(
        "Erro ao limpar diagnósticos:",
        error
      );

      return res
        .status(500)
        .json({
          ok: false,

          message:
            "Erro ao limpar diagnósticos."
        });
    }
  }
);

// ============================================================
// 404
// ============================================================

app.use(
  (req, res) => {
    if (
      req.path.startsWith(
        "/api/"
      )
    ) {
      return res
        .status(404)
        .json({
          ok: false,
          message:
            "Rota não encontrada."
        });
    }

    return res
      .status(404)
      .send(
        "Página não encontrada."
      );
  }
);

// ============================================================
// ERROR HANDLER
// ============================================================

app.use(
  (
    error,
    req,
    res,
    next
  ) => {
    console.error(
      "Erro interno:",
      error
    );

    if (
      res.headersSent
    ) {
      return next(error);
    }

    if (
      error?.type ===
      "entity.too.large"
    ) {
      return res
        .status(413)
        .json({
          ok: false,
          message:
            "Conteúdo acima do limite permitido."
        });
    }

    return res
      .status(500)
      .json({
        ok: false,
        message:
          "Erro interno do servidor."
      });
  }
);

// ============================================================
// START
// ============================================================

app.listen(
  PORT,
  "0.0.0.0",
  () => {
    console.log(
      `CAFEÍNA online na porta ${PORT}`
    );

    console.log(
      `Pasta pública: ${PUBLIC_DIR}`
    );

    console.log(
      `OpenAI configurada: ${
        OPENAI_API_KEY
          ? "SIM"
          : "NÃO"
      }`
    );
  }
);
