const express = require("express");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const app = express();

const PORT = process.env.PORT || 10000;

const ROOT_DIR = __dirname;
const UPLOAD_DIR = path.join(ROOT_DIR, "uploads");
const DIAGNOSTICS_FILE = path.join(ROOT_DIR, "diagnostics.json");

const MAX_UPLOAD_BYTES =
  Number(process.env.MAX_UPLOAD_BYTES || 750000);

const MAX_DIAGNOSTICS =
  Number(process.env.MAX_DIAGNOSTICS || 300);

const UPLOAD_TOKEN =
  String(process.env.UPLOAD_TOKEN || "");

const OPENAI_API_KEY =
  String(process.env.OPENAI_API_KEY || "");

// ============================================================
// PASTAS / ARQUIVOS
// ============================================================

fs.mkdirSync(UPLOAD_DIR, {
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
      MAX_UPLOAD_BYTES + 200000,
      1000000
    )
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

  next();
});

// ============================================================
// HELPERS
// ============================================================

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

function validateToken(body) {
  if (!UPLOAD_TOKEN) {
    return true;
  }

  const received =
    String(body?.token || "");

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

function buildUniqueFileName(fileName) {
  const safe =
    sanitizeFileName(fileName);

  const ext =
    path.extname(safe) || ".json";

  const base =
    path.basename(
      safe,
      ext
    );

  const stamp =
    Date.now().toString(36);

  const random =
    crypto
      .randomBytes(4)
      .toString("hex");

  return (
    `${base}_${stamp}_${random}${ext}`
  );
}

function getBaseUrl(req) {
  const protocol =
    req.headers["x-forwarded-proto"] ||
    req.protocol;

  const host =
    req.get("host");

  return `${protocol}://${host}`;
}

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
  fs.writeFileSync(
    DIAGNOSTICS_FILE,
    JSON.stringify(
      items,
      null,
      2
    ),
    "utf8"
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
      crypto.randomUUID
        ? crypto.randomUUID()
        : crypto
            .randomBytes(16)
            .toString("hex"),

    type:
      String(
        source.type ||
        "runtime"
      ).slice(0, 50),

    message:
      String(
        source.message ||
        "Erro sem mensagem."
      ).slice(0, 20000),

    trace:
      String(
        source.trace ||
        source.stack ||
        ""
      ).slice(0, 50000),

    scriptName:
      String(
        source.scriptName ||
        source.script ||
        ""
      ).slice(0, 300),

    scriptUrl:
      String(
        source.scriptUrl ||
        ""
      ).slice(0, 2000),

    version:
      String(
        source.version ||
        ""
      ).slice(0, 100),

    placeId:
      String(
        source.placeId ||
        ""
      ).slice(0, 100),

    gameId:
      String(
        source.gameId ||
        ""
      ).slice(0, 100),

    executor:
      String(
        source.executor ||
        ""
      ).slice(0, 200),

    clientTime:
      source.clientTime
        ? String(
            source.clientTime
          ).slice(0, 100)
        : null,

    receivedAt:
      new Date().toISOString()
  };
}

// ============================================================
// ARQUIVOS ESTÁTICOS DO SITE
// ============================================================

app.get(
  "/styles.css",
  (req, res) => {
    res.sendFile(
      path.join(
        ROOT_DIR,
        "styles.css"
      )
    );
  }
);

app.get(
  "/app.js",
  (req, res) => {
    res.sendFile(
      path.join(
        ROOT_DIR,
        "app.js"
      )
    );
  }
);

// ============================================================
// PÁGINA PRINCIPAL
// ============================================================

app.get("/", (req, res) => {
  res.sendFile(
    path.join(
      ROOT_DIR,
      "index.html"
    )
  );
});

// ============================================================
// HEALTH / STATUS
// ============================================================

app.get(
  "/health",
  (req, res) => {
    res.json({
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

      uptime:
        process.uptime()
    });
  }
);

// ============================================================
// STATUS PÚBLICO DA IA
// ============================================================
// IMPORTANTE:
// A chave da OpenAI nunca é enviada ao navegador.
// Só informamos se ela está configurada ou não.
// ============================================================

app.get(
  "/api/status",
  (req, res) => {
    res.json({
      ok: true,

      server: true,

      files: true,

      diagnostics: true,

      ai:
        Boolean(
          OPENAI_API_KEY
        )
    });
  }
);

// ============================================================
// UPLOAD DO EXPLORER
// ============================================================

app.post(
  "/upload",
  (req, res) => {
    try {
      if (
        !validateToken(
          req.body
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

      const content =
        String(
          req.body?.content ||
          ""
        );

      const source =
        String(
          req.body?.source ||
          "unknown"
        ).slice(0, 200);

      if (!content) {
        return res
          .status(400)
          .json({
            success: false,
            ok: false,
            error:
              "Conteúdo vazio."
          });
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

        source,

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

      const fullUrl =
        getBaseUrl(req) +
        relativeUrl;

      return res
        .status(201)
        .json({
          success: true,
          ok: true,

          filename:
            storedFileName,

          url:
            fullUrl,

          downloadUrl:
            relativeUrl,

          bytes:
            byteLength
        });

    } catch (error) {
      console.error(
        "Upload error:",
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
          (
            total,
            file
          ) =>
            total +
            Number(
              file.bytes ||
              0
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
        "List files error:",
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
// DOWNLOAD
// ============================================================

app.get(
  "/files/:filename",
  (req, res) => {
    try {
      const requested =
        path.basename(
          String(
            req.params
              .filename ||
            ""
          )
        );

      if (!requested) {
        return res
          .status(400)
          .json({
            success: false,
            ok: false,
            error:
              "Nome inválido."
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
            ok: false,

            error:
              "Arquivo não encontrado."
          });
      }

      const resolved =
        path.resolve(
          filePath
        );

      const uploadsResolved =
        path.resolve(
          UPLOAD_DIR
        ) +
        path.sep;

      if (
        !resolved.startsWith(
          uploadsResolved
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

      return res.download(
        resolved,
        requested
      );

    } catch (error) {
      console.error(
        "Download error:",
        error
      );

      return res
        .status(500)
        .json({
          success: false,
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
        "Diagnostic POST error:",
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
        "Diagnostic GET error:",
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
        "Diagnostic DELETE error:",
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
      "Server error:",
      error
    );

    if (
      res.headersSent
    ) {
      return next(error);
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
  () => {
    console.log(
      `CAFEINA online na porta ${PORT}`
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
