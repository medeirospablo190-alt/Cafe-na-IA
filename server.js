import express from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 3000);
const PUBLIC_DIR = path.join(__dirname, "public");
const DOWNLOAD_DIR = path.resolve(process.env.DOWNLOAD_DIR || path.join(__dirname, "private-downloads"));

const MAX_PASSWORD_CHARS = 512;
const TOKEN_TTL_MS = clampInt(process.env.DOWNLOAD_TOKEN_TTL_SECONDS, 30, 600, 180) * 1000;
const ATTEMPT_WINDOW_MS = clampInt(process.env.DOWNLOAD_ATTEMPT_WINDOW_SECONDS, 60, 3600, 900) * 1000;
const ATTEMPT_BLOCK_MS = clampInt(process.env.DOWNLOAD_BLOCK_SECONDS, 60, 86_400, 1800) * 1000;
const MAX_FAILED_ATTEMPTS = clampInt(process.env.DOWNLOAD_MAX_FAILED_ATTEMPTS, 3, 20, 6);

const downloadTokens = new Map();
const failedAttempts = new Map();

const ARTIFACTS = Object.freeze({
  APP1_ANDROID: artifact({
    section: "ADM",
    product: "Aplicativo 1 — GRUPO LUA",
    platform: "Android",
    verifierEnv: "DOWNLOAD_APP1_ANDROID_HASH",
    fileEnv: "DOWNLOAD_APP1_ANDROID_FILE",
    redirectEnv: "DOWNLOAD_APP1_ANDROID_REDIRECT_URL",
    nameEnv: "DOWNLOAD_APP1_ANDROID_NAME",
    versionEnv: "DOWNLOAD_APP1_ANDROID_VERSION",
    defaultName: "GRUPO-LUA-App1.apk"
  }),
  APP1_IOS: artifact({
    section: "ADM",
    product: "Aplicativo 1 — GRUPO LUA",
    platform: "iPhone / iOS",
    verifierEnv: "DOWNLOAD_APP1_IOS_HASH",
    fileEnv: "DOWNLOAD_APP1_IOS_FILE",
    redirectEnv: "DOWNLOAD_APP1_IOS_REDIRECT_URL",
    nameEnv: "DOWNLOAD_APP1_IOS_NAME",
    versionEnv: "DOWNLOAD_APP1_IOS_VERSION",
    defaultName: "GRUPO-LUA-App1.ipa"
  }),
  KEYMASTER_ANDROID: artifact({
    section: "DEV",
    product: "Aplicativo 2 — GRUPO LUA KEYMASTER",
    platform: "Android",
    verifierEnv: "DOWNLOAD_KEYMASTER_ANDROID_HASH",
    fileEnv: "DOWNLOAD_KEYMASTER_ANDROID_FILE",
    redirectEnv: "DOWNLOAD_KEYMASTER_ANDROID_REDIRECT_URL",
    nameEnv: "DOWNLOAD_KEYMASTER_ANDROID_NAME",
    versionEnv: "DOWNLOAD_KEYMASTER_ANDROID_VERSION",
    defaultName: "GRUPO-LUA-Keymaster.apk"
  }),
  KEYMASTER_IOS: artifact({
    section: "DEV",
    product: "Aplicativo 2 — GRUPO LUA KEYMASTER",
    platform: "iPhone / iOS",
    verifierEnv: "DOWNLOAD_KEYMASTER_IOS_HASH",
    fileEnv: "DOWNLOAD_KEYMASTER_IOS_FILE",
    redirectEnv: "DOWNLOAD_KEYMASTER_IOS_REDIRECT_URL",
    nameEnv: "DOWNLOAD_KEYMASTER_IOS_NAME",
    versionEnv: "DOWNLOAD_KEYMASTER_IOS_VERSION",
    defaultName: "GRUPO-LUA-Keymaster.ipa"
  })
});

app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(express.json({ limit: "4kb", strict: true }));
app.use(securityHeaders);
app.use(express.static(PUBLIC_DIR, {
  index: false,
  dotfiles: "deny",
  extensions: ["html"],
  setHeaders(res) {
    res.setHeader("Cache-Control", "public, max-age=300");
  }
}));

app.get("/", (_req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, "index.html"));
});

app.get("/api/health", (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.json({ ok: true, service: "GRUPO_LUA_DOWNLOAD_PORTAL" });
});

app.get("/api/downloads/catalog", async (_req, res) => {
  res.setHeader("Cache-Control", "no-store");
  const items = [];
  for (const [id, item] of Object.entries(ARTIFACTS)) {
    const delivery = await resolveDelivery(item);
    items.push({
      id,
      section: item.section,
      product: item.product,
      platform: item.platform,
      version: item.version,
      available: Boolean(item.verifier && delivery),
      delivery: delivery?.type || null
    });
  }
  res.json({ ok: true, items });
});

app.post("/api/downloads/:artifactId/authorize", async (req, res) => {
  res.setHeader("Cache-Control", "no-store");

  const artifactId = String(req.params.artifactId || "").toUpperCase();
  const item = ARTIFACTS[artifactId];
  if (!item) return jsonError(res, 404, "Download não encontrado.");

  const password = String(req.body?.password || "");
  if (!password || password.length > MAX_PASSWORD_CHARS) {
    return jsonError(res, 400, "Senha inválida.");
  }

  const rateKey = `${clientIpHash(req)}:${artifactId}`;
  const rate = attemptState(rateKey);
  if (rate.blockedUntil > Date.now()) {
    const retryAfter = Math.max(1, Math.ceil((rate.blockedUntil - Date.now()) / 1000));
    res.setHeader("Retry-After", String(retryAfter));
    return jsonError(res, 429, "Muitas tentativas. Aguarde antes de tentar novamente.", { retryAfter });
  }

  const delivery = await resolveDelivery(item);
  if (!item.verifier || !delivery) {
    return jsonError(res, 503, "Esta versão ainda não está disponível para instalação.");
  }

  const valid = verifyPassword(password, item.verifier);
  if (!valid) {
    const next = registerFailure(rateKey);
    if (next.blockedUntil > Date.now()) {
      const retryAfter = Math.max(1, Math.ceil((next.blockedUntil - Date.now()) / 1000));
      res.setHeader("Retry-After", String(retryAfter));
      return jsonError(res, 429, "Muitas tentativas. Aguarde antes de tentar novamente.", { retryAfter });
    }
    return jsonError(res, 401, "Senha inválida.");
  }

  failedAttempts.delete(rateKey);

  const rawToken = crypto.randomBytes(32).toString("base64url");
  const tokenKey = sha256(rawToken);
  const expiresAt = Date.now() + TOKEN_TTL_MS;
  downloadTokens.set(tokenKey, {
    artifactId,
    expiresAt,
    binding: clientBinding(req),
    consumed: false
  });

  res.json({
    ok: true,
    downloadUrl: `/api/downloads/t/${encodeURIComponent(rawToken)}`,
    expiresAt: new Date(expiresAt).toISOString(),
    oneTime: true
  });
});

app.get("/api/downloads/t/:token", async (req, res) => {
  res.setHeader("Cache-Control", "no-store");

  const rawToken = String(req.params.token || "");
  if (!/^[A-Za-z0-9_-]{30,120}$/.test(rawToken)) {
    return jsonError(res, 404, "Autorização de download inválida.");
  }

  const tokenKey = sha256(rawToken);
  const grant = downloadTokens.get(tokenKey);
  if (!grant) return jsonError(res, 404, "Autorização de download inválida ou já utilizada.");

  if (grant.consumed || grant.expiresAt <= Date.now()) {
    downloadTokens.delete(tokenKey);
    return jsonError(res, 410, "A autorização de download expirou ou já foi utilizada.");
  }

  if (!safeEqualText(grant.binding, clientBinding(req))) {
    return jsonError(res, 403, "Esta autorização pertence a outra sessão de navegador.");
  }

  const item = ARTIFACTS[grant.artifactId];
  const delivery = item ? await resolveDelivery(item) : null;
  if (!item || !delivery) {
    downloadTokens.delete(tokenKey);
    return jsonError(res, 503, "O arquivo não está disponível neste momento.");
  }

  // Uso único: o grant morre antes de qualquer entrega/redirecionamento.
  grant.consumed = true;
  downloadTokens.delete(tokenKey);

  if (delivery.type === "redirect") {
    return res.redirect(303, delivery.url);
  }

  res.setHeader("X-Download-Options", "noopen");
  return res.download(delivery.path, item.downloadName, {
    headers: {
      "Cache-Control": "no-store, max-age=0",
      "Pragma": "no-cache"
    }
  }, (error) => {
    if (error && !res.headersSent) {
      jsonError(res, 500, "Não foi possível iniciar o download.");
    }
  });
});

app.use((_req, res) => {
  jsonError(res, 404, "Rota não encontrada.");
});

app.use((error, _req, res, _next) => {
  if (error?.type === "entity.too.large") return jsonError(res, 413, "Requisição grande demais.");
  if (error instanceof SyntaxError) return jsonError(res, 400, "JSON inválido.");
  console.error("PORTAL_ERROR", error?.message || error);
  return jsonError(res, 500, "Erro interno do servidor.");
});

setInterval(() => {
  const now = Date.now();
  for (const [key, grant] of downloadTokens) {
    if (grant.consumed || grant.expiresAt <= now) downloadTokens.delete(key);
  }
  for (const [key, state] of failedAttempts) {
    if (state.blockedUntil <= now && now - state.windowStartedAt > ATTEMPT_WINDOW_MS) {
      failedAttempts.delete(key);
    }
  }
}, 60_000).unref();

app.listen(PORT, () => {
  console.log(`GRUPO LUA Download Portal em :${PORT}`);
});

function artifact(config) {
  return Object.freeze({
    ...config,
    verifier: String(process.env[config.verifierEnv] || "").trim(),
    file: String(process.env[config.fileEnv] || "").trim(),
    redirectUrl: String(process.env[config.redirectEnv] || "").trim(),
    downloadName: safeDownloadName(process.env[config.nameEnv] || config.defaultName),
    version: String(process.env[config.versionEnv] || "Em preparação").trim().slice(0, 60)
  });
}

async function resolveDelivery(item) {
  if (item.redirectUrl) {
    try {
      const url = new URL(item.redirectUrl);
      if (url.protocol === "https:") return { type: "redirect", url: url.toString() };
    } catch {}
  }

  if (!item.file) return null;
  const resolved = path.isAbsolute(item.file)
    ? path.resolve(item.file)
    : path.resolve(DOWNLOAD_DIR, item.file);

  // Caminhos relativos sempre permanecem dentro de DOWNLOAD_DIR.
  if (!path.isAbsolute(item.file) && resolved !== DOWNLOAD_DIR && !resolved.startsWith(`${DOWNLOAD_DIR}${path.sep}`)) {
    return null;
  }

  try {
    const stat = await fs.promises.stat(resolved);
    if (!stat.isFile()) return null;
    return { type: "file", path: resolved };
  } catch {
    return null;
  }
}

function verifyPassword(password, verifier) {
  try {
    const parts = String(verifier || "").split("$");
    if (parts.length !== 6 || parts[0] !== "scrypt") return false;

    const N = Number(parts[1]);
    const r = Number(parts[2]);
    const p = Number(parts[3]);
    if (!Number.isInteger(N) || !Number.isInteger(r) || !Number.isInteger(p)) return false;
    if (N < 16_384 || N > 1_048_576 || r < 1 || r > 32 || p < 1 || p > 16) return false;

    const salt = Buffer.from(parts[4], "base64url");
    const expected = Buffer.from(parts[5], "base64url");
    if (salt.length < 16 || expected.length < 32 || expected.length > 64) return false;

    const actual = crypto.scryptSync(password, salt, expected.length, {
      N,
      r,
      p,
      maxmem: Math.max(64 * 1024 * 1024, 128 * N * r + 1024 * 1024)
    });
    return crypto.timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function attemptState(key) {
  const now = Date.now();
  const current = failedAttempts.get(key);
  if (!current) return { count: 0, windowStartedAt: now, blockedUntil: 0 };
  if (current.blockedUntil > now) return current;
  if (now - current.windowStartedAt > ATTEMPT_WINDOW_MS) {
    failedAttempts.delete(key);
    return { count: 0, windowStartedAt: now, blockedUntil: 0 };
  }
  return current;
}

function registerFailure(key) {
  const now = Date.now();
  const current = attemptState(key);
  const count = current.count + 1;
  const blockedUntil = count >= MAX_FAILED_ATTEMPTS ? now + ATTEMPT_BLOCK_MS : 0;
  const next = {
    count: blockedUntil ? 0 : count,
    windowStartedAt: blockedUntil ? now : current.windowStartedAt,
    blockedUntil
  };
  failedAttempts.set(key, next);
  return next;
}

function securityHeaders(req, res, next) {
  res.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
  if (process.env.NODE_ENV === "production") {
    res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  }
  next();
}

function jsonError(res, status, message, extra = {}) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(status).json({ ok: false, message, ...extra });
}

function safeDownloadName(value) {
  const name = path.basename(String(value || "download.bin"))
    .normalize("NFKC")
    .replace(/[\\/:*?"<>|\u0000-\u001F]/g, "_")
    .slice(0, 140);
  return name || "download.bin";
}

function clientBinding(req) {
  const ua = String(req.headers["user-agent"] || "").slice(0, 500);
  return sha256(`${clientIpHash(req)}\0${ua}`);
}

function clientIpHash(req) {
  return sha256(String(req.ip || req.socket?.remoteAddress || "unknown"));
}

function safeEqualText(a, b) {
  const left = Buffer.from(String(a || ""));
  const right = Buffer.from(String(b || ""));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("base64url");
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(n)));
}
