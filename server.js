import express from "express";
import OpenAI from "openai";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = Number(process.env.PORT || 3000);
const PUBLIC_DIR = path.join(__dirname, "public");
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");
const UPLOAD_DIR = path.join(DATA_DIR, "uploads");
const SESSION_DIR = path.join(DATA_DIR, "sessions");
const DIAG_DIR = path.join(DATA_DIR, "diagnostics");
const RUNTIME_DIAG_DIR = path.join(DIAG_DIR, "runtime");
const SOURCE_FILE = path.join(DATA_DIR, "diagnostic-sources.json");

const MAX_CHUNK_BYTES = 6 * 1024 * 1024;
const MAX_FINAL_BYTES = 300 * 1024 * 1024;
const MAX_DIAGNOSTIC_SCRIPT_BYTES = 2 * 1024 * 1024;
const SESSION_TTL_MS = 6 * 60 * 60 * 1000;
const UPLOAD_TOKEN = String(process.env.UPLOAD_TOKEN || "").trim();
const DIAGNOSTIC_TOKEN = String(process.env.DIAGNOSTIC_TOKEN || UPLOAD_TOKEN || "").trim();
const MAX_RUNTIME_DIAGNOSTIC_BYTES = 2 * 1024 * 1024;
const ALLOWED_DIAGNOSTIC_SCRIPTS = Object.freeze([
  "Scamtest.lua",
  "Menutest.lua",
  "Samme.lua",
  "CafeinaV1.lua",
  "Cafeinav2.lua",
  "Cafeinav3.lua",
  "Cafeinav4.lua",
  "Explorador de Bots V4.lua",
  "Explorador de Bots V3.lua",
  "Psico test.lua",
  "Psico scam.lua",
  "Psicov1.lua",
  "Psicov2.lua",
  "Psicov3.lua"
]);

await Promise.all([
  fsp.mkdir(UPLOAD_DIR, { recursive: true }),
  fsp.mkdir(SESSION_DIR, { recursive: true }),
  fsp.mkdir(DIAG_DIR, { recursive: true }),
  fsp.mkdir(RUNTIME_DIAG_DIR, { recursive: true })
]);

if (!fs.existsSync(SOURCE_FILE)) {
  await writeJsonAtomic(SOURCE_FILE, { sources: [] });
}

app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(express.json({ limit: "8mb" }));
app.use(express.static(PUBLIC_DIR, { extensions: ["html"] }));

function safeName(input, fallback = "arquivo") {
  const base = path.basename(String(input || fallback));
  const cleaned = base
    .normalize("NFKC")
    .replace(/[\\/:*?"<>|\u0000-\u001F]/g, "_")
    .replace(/\s+/g, "_")
    .replace(/_+/g, "_")
    .slice(0, 180);
  return cleaned || fallback;
}

function safeStem(input) {
  const file = safeName(input, "script.lua");
  return file.replace(/\.(lua|luau|txt)$/i, "") || "script";
}

function randomId(prefix) {
  return `${prefix}_${Date.now().toString(36)}_${crypto.randomBytes(8).toString("hex")}`;
}

function isAuthorized(body) {
  if (!UPLOAD_TOKEN) return true;
  return String(body?.token || "") === UPLOAD_TOKEN;
}

function isDiagnosticAuthorized(req) {
  if (!DIAGNOSTIC_TOKEN) return true;
  const received = String(req.headers["x-diagnostic-token"] || req.body?.token || "");
  return received === DIAGNOSTIC_TOKEN;
}

function canonicalDiagnosticScript(input) {
  const candidate = path.basename(String(input || "")).toLowerCase();
  return ALLOWED_DIAGNOSTIC_SCRIPTS.find((name) => name.toLowerCase() === candidate) || null;
}

function diagnosticScriptDir(scriptName) {
  const stem = safeStem(scriptName);
  return path.join(RUNTIME_DIAG_DIR, stem);
}

function safeRunId(input) {
  const raw = String(input || "").trim();
  if (/^[a-zA-Z0-9_-]{6,100}$/.test(raw)) return raw;
  return randomId("run");
}

function sanitizeDiagnosticValue(value, depth = 0) {
  if (depth > 8) return "[max-depth]";
  if (value === null || value === undefined) return value ?? null;
  if (typeof value === "string") return value.slice(0, 100_000);
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.slice(0, 2000).map((item) => sanitizeDiagnosticValue(item, depth + 1));
  if (typeof value === "object") {
    const out = {};
    for (const [key, item] of Object.entries(value).slice(0, 1000)) {
      const safeKey = String(key).replace(/[\u0000-\u001F]/g, "").slice(0, 120);
      if (/token|password|secret|cookie|authorization|api.?key/i.test(safeKey)) continue;
      out[safeKey] = sanitizeDiagnosticValue(item, depth + 1);
    }
    return out;
  }
  return String(value).slice(0, 10_000);
}

function publicBase(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
  if (configured) return configured;
  return `${req.protocol}://${req.get("host")}`;
}

function jsonError(res, status, message, details) {
  return res.status(status).json({ ok: false, message, ...(details ? { details } : {}) });
}

async function readJson(file) {
  return JSON.parse(await fsp.readFile(file, "utf8"));
}

async function writeJsonAtomic(file, value) {
  const tmp = `${file}.${crypto.randomBytes(4).toString("hex")}.tmp`;
  await fsp.writeFile(tmp, JSON.stringify(value, null, 2), "utf8");
  await fsp.rename(tmp, file);
}

async function readSources() {
  try {
    const data = await readJson(SOURCE_FILE);
    return Array.isArray(data?.sources) ? data.sources : [];
  } catch {
    return [];
  }
}

async function saveSources(sources) {
  await writeJsonAtomic(SOURCE_FILE, { sources });
}

function extractHttpUrl(input) {
  const text = String(input || "").trim();
  const match = text.match(/https:\/\/[^\s"'`)]+/i);
  return match ? match[0] : "";
}

function normalizeGitHubSource(input) {
  const extracted = extractHttpUrl(input);
  if (!extracted) throw new Error("Cole um loadstring ou uma URL HTTPS do GitHub.");

  const url = new URL(extracted);
  if (url.protocol !== "https:") throw new Error("A fonte precisa usar HTTPS.");

  if (url.hostname === "raw.githubusercontent.com") {
    return url.toString();
  }

  if (url.hostname !== "github.com" && url.hostname !== "www.github.com") {
    throw new Error("Por segurança, somente fontes do GitHub são aceitas.");
  }

  const parts = url.pathname.split("/").filter(Boolean);
  if (parts.length < 5 || parts[2] !== "blob") {
    throw new Error("Use o link de um arquivo do GitHub, não apenas o repositório.");
  }

  const [owner, repo, , branch, ...fileParts] = parts;
  if (!owner || !repo || !branch || fileParts.length < 1) {
    throw new Error("Link do GitHub incompleto.");
  }

  return `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/refs/heads/${encodeURIComponent(branch)}/${fileParts.map(encodeURIComponent).join("/")}`;
}

function sourceFilename(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return safeName(decodeURIComponent(url.pathname.split("/").pop() || "script.lua"), "script.lua");
  } catch {
    return "script.lua";
  }
}

async function fetchSourceCode(rawUrl) {
  const response = await fetch(rawUrl, {
    redirect: "follow",
    signal: AbortSignal.timeout(20000),
    headers: {
      "Accept": "text/plain,*/*;q=0.8",
      "User-Agent": "CAFEINA-Diagnostic/2.1"
    }
  });

  if (!response.ok) throw new Error(`GitHub respondeu HTTP ${response.status}.`);
  const declared = Number(response.headers.get("content-length") || 0);
  if (declared > MAX_DIAGNOSTIC_SCRIPT_BYTES) throw new Error("Script remoto grande demais para diagnóstico.");

  const content = await response.text();
  if (Buffer.byteLength(content, "utf8") > MAX_DIAGNOSTIC_SCRIPT_BYTES) {
    throw new Error("Script remoto grande demais para diagnóstico.");
  }
  if (!content.trim()) throw new Error("O arquivo remoto está vazio.");
  return content;
}

async function directorySize(dir) {
  let total = 0;
  for (const entry of await fsp.readdir(dir, { withFileTypes: true }).catch(() => [])) {
    if (!entry.isFile()) continue;
    total += (await fsp.stat(path.join(dir, entry.name))).size;
  }
  return total;
}

async function cleanupOldSessions() {
  const now = Date.now();
  for (const entry of await fsp.readdir(SESSION_DIR, { withFileTypes: true }).catch(() => [])) {
    if (!entry.isDirectory()) continue;
    const dir = path.join(SESSION_DIR, entry.name);
    try {
      const stat = await fsp.stat(dir);
      if (now - stat.mtimeMs > SESSION_TTL_MS) {
        await fsp.rm(dir, { recursive: true, force: true });
      }
    } catch {}
  }
}

setInterval(() => cleanupOldSessions().catch(() => {}), 30 * 60 * 1000).unref();
cleanupOldSessions().catch(() => {});

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    service: "CAFEINA",
    scannerUpload: true,
    diagnostics: true,
    limits: {
      maxChunkBytes: MAX_CHUNK_BYTES,
      maxFinalBytes: MAX_FINAL_BYTES,
      maxDiagnosticScriptBytes: MAX_DIAGNOSTIC_SCRIPT_BYTES
    },
    storage: {
      dataDir: DATA_DIR,
      persistent: Boolean(process.env.DATA_DIR),
      note: process.env.DATA_DIR
        ? "DATA_DIR configurado."
        : "Sem DATA_DIR externo, o armazenamento pode ser efêmero em plataformas como Render."
    }
  });
});

// -----------------------------------------------------------------------------
// SCANNER UPLOAD - compatível com Samme.lua V3
// -----------------------------------------------------------------------------
app.post("/upload/start", async (req, res) => {
  try {
    if (!isAuthorized(req.body)) return jsonError(res, 401, "Token de upload inválido.");

    const filename = safeName(req.body?.filename, `Cafeina_${Date.now()}.json`);
    const uploadId = randomId("upl");
    const dir = path.join(SESSION_DIR, uploadId);
    await fsp.mkdir(dir, { recursive: false });

    const meta = {
      uploadId,
      filename,
      source: String(req.body?.source || "unknown").slice(0, 100),
      metadata: req.body?.metadata ?? null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      chunks: {}
    };

    await writeJsonAtomic(path.join(dir, "meta.json"), meta);
    return res.status(201).json({ ok: true, uploadId });
  } catch (error) {
    console.error("upload/start", error);
    return jsonError(res, 500, "Não foi possível iniciar o upload.");
  }
});

app.post("/upload/chunk", async (req, res) => {
  try {
    if (!isAuthorized(req.body)) return jsonError(res, 401, "Token de upload inválido.");

    const uploadId = safeName(req.body?.uploadId, "");
    const index = Number(req.body?.index);
    const objects = req.body?.objects;

    if (!uploadId || !Number.isInteger(index) || index < 1 || !Array.isArray(objects)) {
      return jsonError(res, 400, "Chunk inválido. Envie uploadId, index e objects.");
    }

    const dir = path.join(SESSION_DIR, uploadId);
    const metaFile = path.join(dir, "meta.json");
    if (!fs.existsSync(metaFile)) return jsonError(res, 404, "Upload não encontrado ou expirado.");

    const encoded = JSON.stringify(objects);
    const bytes = Buffer.byteLength(encoded, "utf8");
    if (bytes > MAX_CHUNK_BYTES) {
      return jsonError(res, 413, "Chunk excede o limite permitido.", { maxChunkBytes: MAX_CHUNK_BYTES });
    }

    const before = await directorySize(dir);
    if (before + bytes > MAX_FINAL_BYTES + MAX_CHUNK_BYTES) {
      return jsonError(res, 413, "Upload excede o limite máximo permitido.");
    }

    const chunkFile = path.join(dir, `chunk-${String(index).padStart(6, "0")}.json`);
    await fsp.writeFile(chunkFile, encoded, "utf8");

    const meta = await readJson(metaFile);
    meta.updatedAt = new Date().toISOString();
    meta.chunks[String(index)] = { bytes, objects: objects.length };
    await writeJsonAtomic(metaFile, meta);

    return res.json({ ok: true, uploadId, index, bytes, receivedObjects: objects.length });
  } catch (error) {
    console.error("upload/chunk", error);
    return jsonError(res, 500, "Não foi possível salvar o chunk.");
  }
});

app.post("/upload/finish", async (req, res) => {
  try {
    if (!isAuthorized(req.body)) return jsonError(res, 401, "Token de upload inválido.");

    const uploadId = safeName(req.body?.uploadId, "");
    const totalChunks = Number(req.body?.totalChunks);
    if (!uploadId || !Number.isInteger(totalChunks) || totalChunks < 1) {
      return jsonError(res, 400, "Finalização inválida.");
    }

    const dir = path.join(SESSION_DIR, uploadId);
    const metaFile = path.join(dir, "meta.json");
    if (!fs.existsSync(metaFile)) return jsonError(res, 404, "Upload não encontrado ou expirado.");

    const meta = await readJson(metaFile);
    let totalBytes = 0;
    let recordCount = 0;

    // Valida cada parte isoladamente. Assim, mesmo um scan grande não precisa
    // ficar inteiro na memória do processo.
    for (let i = 1; i <= totalChunks; i++) {
      const chunkFile = path.join(dir, `chunk-${String(i).padStart(6, "0")}.json`);
      if (!fs.existsSync(chunkFile)) {
        return jsonError(res, 409, `Chunk ${i} não foi recebido.`);
      }
      const raw = await fsp.readFile(chunkFile, "utf8");
      totalBytes += Buffer.byteLength(raw, "utf8");
      if (totalBytes > MAX_FINAL_BYTES) return jsonError(res, 413, "Arquivo final excede o limite permitido.");
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return jsonError(res, 422, `Chunk ${i} está corrompido.`);
      recordCount += parsed.length;
    }

    const finalNameBase = safeName(meta.filename, `${uploadId}.json`);
    const ext = path.extname(finalNameBase) || ".json";
    const stem = path.basename(finalNameBase, ext);
    let finalName = `${stem}${ext}`;
    let finalPath = path.join(UPLOAD_DIR, finalName);
    if (fs.existsSync(finalPath)) {
      finalName = `${stem}_${Date.now()}${ext}`;
      finalPath = path.join(UPLOAD_DIR, finalName);
    }

    const receivedAt = new Date().toISOString();
    const header = {
      uploadId,
      source: meta.source,
      metadata: meta.metadata,
      summary: req.body?.summary ?? null,
      receivedAt,
      totalChunks,
      recordCount
    };

    // Monta o JSON final por streaming, retirando apenas os colchetes externos
    // de cada array de chunk. Isso mantém o arquivo compatível e reduz o pico de memória.
    const tempFinal = `${finalPath}.tmp`;
    const out = fs.createWriteStream(tempFinal, { encoding: "utf8" });
    const write = (text) => new Promise((resolve, reject) => {
      if (out.write(text)) return resolve();
      out.once("drain", resolve);
      out.once("error", reject);
    });

    try {
      await write(`{\n  "cafeinaUpload": ${JSON.stringify(header, null, 2)},\n  "records": [`);
      let wroteAny = false;
      for (let i = 1; i <= totalChunks; i++) {
        const chunkFile = path.join(dir, `chunk-${String(i).padStart(6, "0")}.json`);
        const raw = (await fsp.readFile(chunkFile, "utf8")).trim();
        const inner = raw.length >= 2 ? raw.slice(1, -1).trim() : "";
        if (!inner) continue;
        await write(`${wroteAny ? "," : ""}\n${inner}`);
        wroteAny = true;
      }
      await write(`\n  ]\n}\n`);
      await new Promise((resolve, reject) => {
        out.end(resolve);
        out.once("error", reject);
      });
      await fsp.rename(tempFinal, finalPath);
    } catch (error) {
      out.destroy();
      await fsp.rm(tempFinal, { force: true }).catch(() => {});
      throw error;
    }

    const stat = await fsp.stat(finalPath);
    const sidecar = {
      name: finalName,
      bytes: stat.size,
      modifiedAt: stat.mtime.toISOString(),
      area: header.summary?.area || header.metadata?.area || "Desconhecida",
      records: recordCount,
      uploadId,
      receivedAt
    };
    await writeJsonAtomic(`${finalPath}.meta.json`, sidecar);
    await fsp.rm(dir, { recursive: true, force: true });

    const encodedName = encodeURIComponent(finalName);
    const url = `${publicBase(req)}/api/scans/${encodedName}/download`;
    return res.json({
      ok: true,
      uploadId,
      filename: finalName,
      bytes: stat.size,
      records: recordCount,
      downloadUrl: url,
      url
    });
  } catch (error) {
    console.error("upload/finish", error);
    return jsonError(res, 500, "Não foi possível finalizar o upload.");
  }
});

app.post("/upload/cancel", async (req, res) => {
  try {
    if (!isAuthorized(req.body)) return jsonError(res, 401, "Token de upload inválido.");
    const uploadId = safeName(req.body?.uploadId, "");
    if (!uploadId) return jsonError(res, 400, "uploadId obrigatório.");
    await fsp.rm(path.join(SESSION_DIR, uploadId), { recursive: true, force: true });
    return res.json({ ok: true, cancelled: true, uploadId });
  } catch (error) {
    console.error("upload/cancel", error);
    return jsonError(res, 500, "Não foi possível cancelar o upload.");
  }
});

// -----------------------------------------------------------------------------
// SCANS - listagem, visualização e download
// -----------------------------------------------------------------------------
app.get("/api/scans", async (_req, res) => {
  try {
    const names = (await fsp.readdir(UPLOAD_DIR)).filter((name) => name.toLowerCase().endsWith(".json"));
    const items = await Promise.all(names.map(async (name) => {
      const file = path.join(UPLOAD_DIR, name);
      const stat = await fsp.stat(file);
      let area = "Desconhecida";
      let records = null;
      let modifiedAt = stat.mtime.toISOString();
      try {
        const sidecar = await readJson(`${file}.meta.json`);
        area = sidecar.area || area;
        records = sidecar.records ?? null;
        modifiedAt = sidecar.modifiedAt || modifiedAt;
      } catch {}
      return { name, bytes: stat.size, modifiedAt, area, records };
    }));
    items.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    return res.json({ ok: true, files: items });
  } catch (error) {
    console.error("api/scans", error);
    return jsonError(res, 500, "Não foi possível listar os arquivos.");
  }
});

app.get("/api/scans/:name", async (req, res) => {
  try {
    const name = safeName(req.params.name, "");
    const file = path.join(UPLOAD_DIR, name);
    if (!name || !fs.existsSync(file)) return jsonError(res, 404, "Arquivo não encontrado.");
    const stat = await fsp.stat(file);
    const maxPreview = 650 * 1024;
    const handle = await fsp.open(file, "r");
    const buffer = Buffer.alloc(Math.min(stat.size, maxPreview));
    await handle.read(buffer, 0, buffer.length, 0);
    await handle.close();
    return res.json({
      ok: true,
      name,
      bytes: stat.size,
      truncated: stat.size > maxPreview,
      content: buffer.toString("utf8")
    });
  } catch (error) {
    console.error("api/scans/:name", error);
    return jsonError(res, 500, "Não foi possível visualizar o arquivo.");
  }
});

app.get("/api/scans/:name/download", (req, res) => {
  const name = safeName(req.params.name, "");
  const file = path.join(UPLOAD_DIR, name);
  if (!name || !fs.existsSync(file)) return jsonError(res, 404, "Arquivo não encontrado.");
  return res.download(file, name);
});

// -----------------------------------------------------------------------------
// DIAGNÓSTICOS DE EXECUÇÃO - JSON, totalmente separados dos arquivos do Scam
// -----------------------------------------------------------------------------
app.get("/api/runtime-diagnostics/scripts", async (_req, res) => {
  return res.json({ ok: true, scripts: ALLOWED_DIAGNOSTIC_SCRIPTS });
});

app.post("/api/runtime-diagnostics", async (req, res) => {
  try {
    if (!isDiagnosticAuthorized(req)) return jsonError(res, 401, "Token de diagnóstico inválido.");

    const script = canonicalDiagnosticScript(req.body?.script || req.body?.scriptName);
    if (!script) {
      return jsonError(res, 400, "Script não autorizado para esta área.", { allowedScripts: ALLOWED_DIAGNOSTIC_SCRIPTS });
    }

    const bodyBytes = Buffer.byteLength(JSON.stringify(req.body || {}), "utf8");
    if (bodyBytes > MAX_RUNTIME_DIAGNOSTIC_BYTES) {
      return jsonError(res, 413, "Diagnóstico acima do limite permitido.", { maxBytes: MAX_RUNTIME_DIAGNOSTIC_BYTES });
    }

    const runId = safeRunId(req.body?.runId);
    const dir = diagnosticScriptDir(script);
    await fsp.mkdir(dir, { recursive: true });
    const file = path.join(dir, `${runId}.json`);

    let previous = null;
    try { previous = await readJson(file); } catch {}

    const now = new Date().toISOString();
    const incoming = sanitizeDiagnosticValue(req.body?.report && typeof req.body.report === "object" ? req.body.report : req.body);
    const report = {
      schemaVersion: 1,
      script,
      runId,
      status: String(incoming?.status || previous?.status || "running").slice(0, 40),
      phase: String(incoming?.phase || incoming?.stage || previous?.phase || "unknown").slice(0, 120),
      startedAt: incoming?.startedAt || previous?.startedAt || now,
      updatedAt: now,
      finishedAt: incoming?.finishedAt || (["success", "error", "interrupted"].includes(String(incoming?.status || "").toLowerCase()) ? now : previous?.finishedAt || null),
      receivedAt: now,
      report: incoming,
      history: [
        ...(Array.isArray(previous?.history) ? previous.history.slice(-199) : []),
        {
          at: now,
          status: String(incoming?.status || "running").slice(0, 40),
          phase: String(incoming?.phase || incoming?.stage || "unknown").slice(0, 120),
          message: String(incoming?.message || incoming?.error || "").slice(0, 2000)
        }
      ]
    };

    await writeJsonAtomic(file, report);
    const downloadUrl = `${publicBase(req)}/api/runtime-diagnostics/${encodeURIComponent(script)}/${encodeURIComponent(runId)}/download`;
    return res.status(previous ? 200 : 201).json({ ok: true, script, runId, status: report.status, updated: Boolean(previous), downloadUrl });
  } catch (error) {
    console.error("runtime-diagnostics/write", error);
    return jsonError(res, 500, "Não foi possível salvar o diagnóstico de execução.");
  }
});

app.get("/api/runtime-diagnostics", async (req, res) => {
  try {
    const requested = req.query.script ? canonicalDiagnosticScript(req.query.script) : null;
    if (req.query.script && !requested) return jsonError(res, 400, "Filtro de script inválido.");
    const scripts = requested ? [requested] : ALLOWED_DIAGNOSTIC_SCRIPTS;
    const items = [];

    for (const script of scripts) {
      const dir = diagnosticScriptDir(script);
      for (const name of await fsp.readdir(dir).catch(() => [])) {
        if (!name.endsWith(".json")) continue;
        try {
          const data = await readJson(path.join(dir, name));
          items.push({
            script,
            runId: data.runId || path.basename(name, ".json"),
            status: data.status || "unknown",
            phase: data.phase || "unknown",
            startedAt: data.startedAt || null,
            updatedAt: data.updatedAt || data.receivedAt || null,
            finishedAt: data.finishedAt || null,
            message: String(data?.report?.message || data?.report?.error || "").slice(0, 1000)
          });
        } catch {}
      }
    }

    items.sort((a, b) => String(b.updatedAt || "").localeCompare(String(a.updatedAt || "")));
    return res.json({ ok: true, count: items.length, diagnostics: items.slice(0, 500) });
  } catch (error) {
    console.error("runtime-diagnostics/list", error);
    return jsonError(res, 500, "Não foi possível listar os diagnósticos.");
  }
});

app.get("/api/runtime-diagnostics/:script/:runId", async (req, res) => {
  try {
    const script = canonicalDiagnosticScript(req.params.script);
    const runId = String(req.params.runId || "");
    if (!script || !/^[a-zA-Z0-9_-]{6,100}$/.test(runId)) return jsonError(res, 400, "Diagnóstico inválido.");
    const file = path.join(diagnosticScriptDir(script), `${runId}.json`);
    if (!fs.existsSync(file)) return jsonError(res, 404, "Diagnóstico não encontrado.");
    return res.json({ ok: true, diagnostic: await readJson(file) });
  } catch (error) {
    console.error("runtime-diagnostics/read", error);
    return jsonError(res, 500, "Não foi possível abrir o diagnóstico.");
  }
});

app.get("/api/runtime-diagnostics/:script/:runId/download", async (req, res) => {
  const script = canonicalDiagnosticScript(req.params.script);
  const runId = String(req.params.runId || "");
  if (!script || !/^[a-zA-Z0-9_-]{6,100}$/.test(runId)) return jsonError(res, 400, "Diagnóstico inválido.");
  const file = path.join(diagnosticScriptDir(script), `${runId}.json`);
  if (!fs.existsSync(file)) return jsonError(res, 404, "Diagnóstico não encontrado.");
  return res.download(file, `${safeStem(script)}_${runId}.json`);
});

async function generateDiagnostic({ req, filename, content, sourceId = null, sourceUrl = null }) {
  const bytes = Buffer.byteLength(content, "utf8");
  if (bytes > MAX_DIAGNOSTIC_SCRIPT_BYTES) {
    const error = new Error("Script grande demais para diagnóstico.");
    error.status = 413;
    throw error;
  }

  if (!process.env.OPENAI_API_KEY) {
    const error = new Error("OPENAI_API_KEY não está configurada no servidor.");
    error.status = 503;
    throw error;
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const model = process.env.OPENAI_MODEL || "gpt-5.4";
  const response = await client.responses.create({
    model,
    instructions: [
      "Você é um revisor técnico de scripts Lua/Luau.",
      "Analise somente o código fornecido.",
      "Responda em português do Brasil.",
      "Priorize erros de sintaxe, erros de runtime, incompatibilidades mobile/executor, problemas HTTP, concorrência, memória, segurança do próprio código e bugs lógicos.",
      "Não invente APIs ou objetos que não estejam no código.",
      "Estruture a resposta em: Resumo, Erros críticos, Problemas prováveis, Melhorias e Verificações recomendadas.",
      "Quando possível, cite funções ou trechos pelo nome para facilitar a correção."
    ].join("\n"),
    input: `ARQUIVO: ${filename}${sourceUrl ? `\nFONTE: ${sourceUrl}` : ""}\n\nCÓDIGO:\n${content}`
  });

  const diagnostic = String(response.output_text || "Nenhum diagnóstico foi retornado.").trim();
  const outputName = `${safeStem(filename)}_diagnostico.txt`;
  const storedName = `${sourceId ? `${safeName(sourceId)}_` : ""}${Date.now()}_${outputName}`;
  await fsp.writeFile(
    path.join(DIAG_DIR, storedName),
    `Arquivo analisado: ${filename}\n${sourceUrl ? `Fonte: ${sourceUrl}\n` : ""}Data: ${new Date().toISOString()}\nModelo: ${model}\n\n${diagnostic}\n`,
    "utf8"
  );

  return {
    filename,
    diagnostic,
    downloadName: outputName,
    storedName,
    downloadUrl: `${publicBase(req)}/api/diagnostics/${encodeURIComponent(storedName)}/download`
  };
}

function extractErrorLine(text) {
  const value = String(text || "");
  const patterns = [
    /:(\d+):\s*/,
    /line\s+(\d+)/i,
    /linha\s+(\d+)/i
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (match) return Number(match[1]) || null;
  }
  return null;
}

function publicSource(source) {
  const { reportToken, ...safe } = source;
  return safe;
}

function monitoredLoaderLua(req, source) {
  const reportUrl = `${publicBase(req)}/api/diagnostic-sources/${encodeURIComponent(source.id)}/runtime-report`;
  const sourceUrl = source.rawUrl;
  const token = source.reportToken;

  return `-- CAFEINA monitored loader\nlocal HttpService = game:GetService("HttpService")\nlocal SOURCE_URL = ${JSON.stringify(sourceUrl)}\nlocal REPORT_URL = ${JSON.stringify(reportUrl)}\nlocal REPORT_TOKEN = ${JSON.stringify(token)}\n\nlocal requestFn = (typeof(request) == "function" and request) or (typeof(http_request) == "function" and http_request) or (syn and typeof(syn.request) == "function" and syn.request) or nil\n\nlocal function report(status, err, tracebackText, line, phase)\n    local payload = HttpService:JSONEncode({\n        reportToken = REPORT_TOKEN,\n        status = status,\n        phase = phase,\n        error = err and tostring(err) or nil,\n        traceback = tracebackText and tostring(tracebackText) or nil,\n        line = tonumber(line),\n        executor = identifyexecutor and tostring(select(1, identifyexecutor())) or nil,\n        placeId = game.PlaceId,\n        jobId = game.JobId\n    })\n\n    local options = {\n        Url = REPORT_URL,\n        Method = "POST",\n        Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },\n        Body = payload\n    }\n\n    if requestFn then\n        pcall(requestFn, options)\n    else\n        pcall(function() HttpService:RequestAsync(options) end)\n    end\nend\n\nlocal function parseLine(text)\n    text = tostring(text or "")\n    return tonumber(text:match(":(%d+):") or text:match("line%s+(%d+)") or text:match("linha%s+(%d+)"))\nend\n\nreport("running", nil, nil, nil, "start")\n\nlocal fetchOk, sourceOrError = pcall(function()\n    return game:HttpGet(SOURCE_URL)\nend)\n\nif not fetchOk then\n    report("error", sourceOrError, tostring(sourceOrError), parseLine(sourceOrError), "download")\n    error(sourceOrError)\nend\n\nlocal fn, compileError = loadstring(sourceOrError)\nif not fn then\n    report("error", compileError, tostring(compileError), parseLine(compileError), "compile")\n    error(compileError)\nend\n\nlocal ok, result = xpcall(fn, function(err)\n    local trace = debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)\n    return { error = tostring(err), trace = tostring(trace) }\nend)\n\nif ok then\n    report("success", nil, nil, nil, "runtime")\n    return result\nelse\n    local errText = type(result) == "table" and result.error or tostring(result)\n    local traceText = type(result) == "table" and result.trace or tostring(result)\n    local line = parseLine(traceText) or parseLine(errText)\n    report("error", errText, traceText, line, "runtime")\n    error(errText)\nend\n`;
}

// -----------------------------------------------------------------------------
// FONTES SALVAS PARA DIAGNÓSTICO
// -----------------------------------------------------------------------------
app.get("/api/diagnostic-sources", async (_req, res) => {
  try {
    const sources = await readSources();
    sources.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
    return res.json({ ok: true, sources: sources.map(publicSource) });
  } catch (error) {
    console.error("diagnostic-sources/list", error);
    return jsonError(res, 500, "Não foi possível carregar as fontes salvas.");
  }
});

app.post("/api/diagnostic-sources", async (req, res) => {
  try {
    const originalInput = String(req.body?.input || "").trim();
    const rawUrl = normalizeGitHubSource(originalInput);
    const filename = sourceFilename(rawUrl);
    const sources = await readSources();

    const existing = sources.find((item) => item.rawUrl === rawUrl);
    if (existing) return res.json({ ok: true, source: publicSource(existing), alreadyExists: true });

    // Confirma que o arquivo existe antes de salvar a fonte.
    await fetchSourceCode(rawUrl);

    const source = {
      id: randomId("src"),
      input: originalInput.slice(0, 4000),
      rawUrl,
      filename,
      createdAt: new Date().toISOString(),
      lastDiagnosticAt: null,
      lastDownloadUrl: null,
      reportToken: crypto.randomBytes(24).toString("hex"),
      runtimeStatus: "never",
      lastRuntimeAt: null,
      lastRuntimeLine: null,
      lastRuntimeError: null,
      runtimeHistory: []
    };
    sources.push(source);
    await saveSources(sources);
    return res.status(201).json({ ok: true, source: publicSource(source) });
  } catch (error) {
    return jsonError(res, 400, error?.message || "Fonte inválida.");
  }
});

app.delete("/api/diagnostic-sources/:id", async (req, res) => {
  try {
    const id = safeName(req.params.id, "");
    const sources = await readSources();
    const exists = sources.some((item) => item.id === id);
    if (!exists) return jsonError(res, 404, "Fonte não encontrada.");

    await saveSources(sources.filter((item) => item.id !== id));

    // Remove diagnósticos ligados à fonte. Isso garante que, ao remover,
    // a área realmente deixe de manter resultados desse monitoramento.
    for (const name of await fsp.readdir(DIAG_DIR).catch(() => [])) {
      if (name.startsWith(`${id}_`)) await fsp.rm(path.join(DIAG_DIR, name), { force: true }).catch(() => {});
    }

    return res.json({ ok: true, removed: id });
  } catch (error) {
    console.error("diagnostic-sources/delete", error);
    return jsonError(res, 500, "Não foi possível remover a fonte.");
  }
});

app.post("/api/diagnostic-sources/:id/diagnose", async (req, res) => {
  try {
    const id = safeName(req.params.id, "");
    const sources = await readSources();
    const source = sources.find((item) => item.id === id);
    if (!source) return jsonError(res, 404, "Fonte removida ou não encontrada.");

    const content = await fetchSourceCode(source.rawUrl);
    const result = await generateDiagnostic({
      req,
      filename: source.filename,
      content,
      sourceId: source.id,
      sourceUrl: source.rawUrl
    });

    source.lastDiagnosticAt = new Date().toISOString();
    source.lastDownloadUrl = result.downloadUrl;
    await saveSources(sources);

    return res.json({ ok: true, source: publicSource(source), ...result });
  } catch (error) {
    console.error("diagnostic-sources/diagnose", error);
    const status = Number(error?.status) >= 400 && Number(error?.status) < 600 ? Number(error.status) : 500;
    return jsonError(res, status, error?.message || "Não foi possível diagnosticar a fonte.");
  }
});

// -----------------------------------------------------------------------------
// DIAGNÓSTICO DE SCRIPT
// -----------------------------------------------------------------------------
app.post("/api/diagnose", async (req, res) => {
  try {
    const filename = safeName(req.body?.filename, "script.lua");
    const content = String(req.body?.content || "");
    if (!content.trim()) return jsonError(res, 400, "O script está vazio.");

    const result = await generateDiagnostic({ req, filename, content });
    return res.json({ ok: true, ...result });
  } catch (error) {
    console.error("api/diagnose", error);
    const message = error?.status === 401
      ? "A chave da API da OpenAI foi recusada."
      : (error?.message || "Não foi possível gerar o diagnóstico.");
    return jsonError(res, Number(error?.status) >= 400 && Number(error?.status) < 600 ? Number(error.status) : 500, message);
  }
});

app.get("/api/diagnostics/:name/download", (req, res) => {
  const name = safeName(req.params.name, "");
  const file = path.join(DIAG_DIR, name);
  if (!name || !fs.existsSync(file)) return jsonError(res, 404, "Diagnóstico não encontrado.");
  const requestedName = name
    .replace(/^.*?_\d{13}_/, "")
    .replace(/^\d{13}_/, "");
  return res.download(file, requestedName || "diagnostico.txt");
});

app.get("/", (_req, res) => res.sendFile(path.join(PUBLIC_DIR, "index.html")));
app.use((req, res) => jsonError(res, 404, "Rota não encontrada."));

app.use((error, _req, res, _next) => {
  console.error("Unhandled", error);
  if (error?.type === "entity.too.large") return jsonError(res, 413, "Requisição grande demais.");
  return jsonError(res, 500, "Erro interno do servidor.");
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`CAFEINA online na porta ${PORT}`);
  console.log(`DATA_DIR: ${DATA_DIR}`);
});
