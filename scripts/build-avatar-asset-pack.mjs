import fs from "fs/promises";
import path from "path";
import crypto from "crypto";

const dumpPath = process.argv[2] || "avatar-dumps/765329164/latest.json";
const outDir = process.argv[3] || "/tmp/capuccino40-avatar-assets";

const MAX_ASSETS = 240;
const MAX_ASSET_BYTES = 32 * 1024 * 1024;
const MAX_TOTAL_BYTES = 220 * 1024 * 1024;
const CONCURRENCY = 4;
const USER_AGENT = "GrupoLua-AvatarAssetPack/1.0";

const VISUAL_NUMERIC_KEYS = new Set([
  "assetId", "Head", "LeftArm", "LeftLeg", "RightArm", "RightLeg", "Torso",
  "Face", "GraphicTShirt", "Shirt", "Pants"
]);
const VISUAL_STRING_KEYS = new Set([
  "meshId", "textureId", "texture", "colorMap", "metalnessMap", "normalMap",
  "roughnessMap", "shirtTemplate", "pantsTemplate", "graphic", "baseTextureId",
  "overlayTextureId", "referenceMeshId", "cageMeshId", "BackAccessory",
  "FaceAccessory", "FrontAccessory", "HairAccessory", "HatAccessory",
  "NeckAccessory", "ShouldersAccessory", "WaistAccessory"
]);
const ANIMATION_KEYS = /Animation$/i;

const raw = JSON.parse(await fs.readFile(dumpPath, "utf8"));
if (String(raw.userId) !== "765329164") throw new Error("Dump não pertence ao Capuccino40.");
if (!raw.avatar || typeof raw.avatar !== "object") throw new Error("Dump sem avatar.");

await fs.rm(outDir, { recursive: true, force: true });
await fs.mkdir(path.join(outDir, "assets"), { recursive: true });
await fs.copyFile(dumpPath, path.join(outDir, "avatar-dump.json"));

const queue = [];
const queued = new Set();
const reasons = new Map();
const records = [];
let totalBytes = 0;

function addId(value, reason = "unknown") {
  const id = String(value ?? "").match(/^\d{1,20}$/)?.[0];
  if (!id || id === "0" || id === "-1") return;
  if (!reasons.has(id)) reasons.set(id, new Set());
  reasons.get(id).add(reason);
  if (queued.has(id) || queue.length >= MAX_ASSETS) return;
  queued.add(id);
  queue.push(id);
}

function addRefsFromString(value, reason) {
  const text = String(value || "");
  for (const re of [
    /rbxassetid:\/\/(\d{1,20})/gi,
    /[?&]id=(\d{1,20})/gi,
    /\/asset\/?\?id=(\d{1,20})/gi,
  ]) {
    for (const match of text.matchAll(re)) addId(match[1], reason);
  }
}

function walk(value, key = "", trail = "avatar") {
  if (value == null) return;
  if (typeof value === "string") {
    if (VISUAL_STRING_KEYS.has(key) || /asset|mesh|texture|map|graphic|wrap|cage|accessory/i.test(key)) {
      addRefsFromString(value, `${trail}.${key}`);
      if (/^\d{1,20}$/.test(value) && !ANIMATION_KEYS.test(key)) addId(value, `${trail}.${key}`);
    }
    return;
  }
  if (typeof value === "number") {
    if (VISUAL_NUMERIC_KEYS.has(key) && !ANIMATION_KEYS.test(key)) addId(value, `${trail}.${key}`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((v, i) => walk(v, key, `${trail}[${i}]`));
    return;
  }
  if (typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      if (ANIMATION_KEYS.test(k)) continue;
      walk(v, k, `${trail}.${k}`);
    }
  }
}

walk(raw.avatar);
for (const ref of raw.avatar.uniqueAssetReferences || []) addRefsFromString(ref, "uniqueAssetReferences");

function extFor(buffer, contentType = "") {
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) return ".png";
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return ".jpg";
  if (buffer.length >= 12 && buffer.subarray(0, 4).toString("ascii") === "RIFF" && buffer.subarray(8, 12).toString("ascii") === "WEBP") return ".webp";
  const head = buffer.subarray(0, Math.min(buffer.length, 256)).toString("utf8").trimStart();
  if (head.startsWith("<roblox") || head.startsWith("<?xml")) return ".rbxmx";
  if (head.startsWith("version ")) return ".mesh";
  if (head.startsWith("{") || head.startsWith("[")) return ".json";
  if (/image\/png/i.test(contentType)) return ".png";
  if (/image\/jpe?g/i.test(contentType)) return ".jpg";
  if (/image\/webp/i.test(contentType)) return ".webp";
  if (/xml|roblox/i.test(contentType)) return ".rbxmx";
  return ".bin";
}

function discoverDependencies(buffer, contentType, parentId) {
  const likelyText = /json|xml|text|roblox/i.test(contentType) || extFor(buffer, contentType) === ".rbxmx";
  if (!likelyText || buffer.length > 4 * 1024 * 1024) return;
  const text = buffer.toString("utf8");
  addRefsFromString(text, `dependency-of:${parentId}`);
}

async function fetchAsset(id) {
  const url = `https://assetdelivery.roblox.com/v1/asset/?id=${encodeURIComponent(id)}`;
  let lastError = null;
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: "follow",
        headers: { "User-Agent": USER_AGENT, Accept: "*/*" },
        signal: AbortSignal.timeout(45_000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const declared = Number(response.headers.get("content-length") || 0);
      if (declared > MAX_ASSET_BYTES) throw new Error(`asset too large: ${declared}`);
      const buffer = Buffer.from(await response.arrayBuffer());
      if (buffer.length > MAX_ASSET_BYTES) throw new Error(`asset too large: ${buffer.length}`);
      if (totalBytes + buffer.length > MAX_TOTAL_BYTES) throw new Error("total pack size limit reached");
      totalBytes += buffer.length;
      const contentType = response.headers.get("content-type") || "application/octet-stream";
      const ext = extFor(buffer, contentType);
      const sha256 = crypto.createHash("sha256").update(buffer).digest("hex");
      const file = `assets/${id}_${sha256.slice(0, 12)}${ext}`;
      await fs.writeFile(path.join(outDir, file), buffer);
      discoverDependencies(buffer, contentType, id);
      return {
        id,
        ok: true,
        file,
        bytes: buffer.length,
        sha256,
        contentType,
        finalUrl: response.url,
        reasons: [...(reasons.get(id) || [])].sort(),
      };
    } catch (error) {
      lastError = String(error?.message || error);
      if (attempt < 4) await new Promise(r => setTimeout(r, 650 * attempt));
    }
  }
  return { id, ok: false, error: lastError || "unknown", reasons: [...(reasons.get(id) || [])].sort() };
}

let cursor = 0;
async function worker() {
  while (cursor < queue.length && records.length < MAX_ASSETS) {
    const index = cursor++;
    const id = queue[index];
    const record = await fetchAsset(id);
    records.push(record);
    process.stdout.write(`${record.ok ? "OK" : "FAIL"} ${id}${record.ok ? ` ${record.bytes} bytes` : ` ${record.error}`}\n`);
  }
}

await Promise.all(Array.from({ length: CONCURRENCY }, () => worker()));

records.sort((a, b) => Number(a.id) - Number(b.id));
const manifest = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  userId: String(raw.userId),
  username: raw.username,
  capturedAt: raw.capturedAt,
  sourceObjectCount: raw.avatar.objectCount,
  requestedAssetCount: queued.size,
  downloadedAssetCount: records.filter(r => r.ok).length,
  failedAssetCount: records.filter(r => !r.ok).length,
  totalBytes,
  limits: { maxAssets: MAX_ASSETS, maxAssetBytes: MAX_ASSET_BYTES, maxTotalBytes: MAX_TOTAL_BYTES },
  assets: records,
};
await fs.writeFile(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`PACK_READY ${outDir} downloaded=${manifest.downloadedAssetCount} failed=${manifest.failedAssetCount} bytes=${totalBytes}`);
