import fs from "fs/promises";
import path from "path";
import crypto from "crypto";

const dumpPath = process.argv[2] || "avatar-dumps/765329164/latest.json";
const outDir = process.argv[3] || "/tmp/capuccino40-avatar-assets";

const MAX_ASSETS = 240;
const MAX_ASSET_BYTES = 32 * 1024 * 1024;
const MAX_TOTAL_BYTES = 220 * 1024 * 1024;
const CONCURRENCY = 4;
const USER_AGENT = "GrupoLua-AvatarAssetPack/3.0";

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
  const head = buffer.subarray(0, Math.min(buffer.length, 512)).toString("utf8").trimStart();
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
  const likelyText = /json|xml|text|roblox/i.test(contentType) || [".rbxmx", ".json"].includes(extFor(buffer, contentType));
  if (!likelyText || buffer.length > 5 * 1024 * 1024) return;
  const text = buffer.toString("utf8");
  addRefsFromString(text, `dependency-of:${parentId}`);
}

function findLocation(value) {
  if (!value) return null;
  if (typeof value === "string" && /^https:\/\//i.test(value)) return value;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findLocation(item);
      if (found) return found;
    }
    return null;
  }
  if (typeof value === "object") {
    for (const key of ["location", "Location", "url", "Url", "locations"]) {
      if (key in value) {
        const found = findLocation(value[key]);
        if (found) return found;
      }
    }
  }
  return null;
}

function robloxJsonError(buffer, contentType) {
  const head = buffer.subarray(0, Math.min(buffer.length, 1024)).toString("utf8").trimStart();
  if (!/json/i.test(contentType) && !head.startsWith("{") && !head.startsWith("[")) return null;
  try {
    const data = JSON.parse(buffer.toString("utf8"));
    if (Array.isArray(data?.errors) && data.errors.length) {
      return data.errors.map(e => `${e.code ?? "?"}:${e.message ?? "error"}`).join(", ");
    }
  } catch {}
  return null;
}

async function fetchRaw(url) {
  const response = await fetch(url, {
    redirect: "follow",
    headers: { "User-Agent": USER_AGENT, Accept: "*/*" },
    signal: AbortSignal.timeout(35_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const declared = Number(response.headers.get("content-length") || 0);
  if (declared > MAX_ASSET_BYTES) throw new Error(`asset too large: ${declared}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length > MAX_ASSET_BYTES) throw new Error(`asset too large: ${buffer.length}`);
  const contentType = response.headers.get("content-type") || "application/octet-stream";
  const jsonError = robloxJsonError(buffer, contentType);
  if (jsonError) throw new Error(`Roblox API ${jsonError}`);
  return { buffer, contentType, finalUrl: response.url };
}

async function unwrapDelivery(result) {
  const head = result.buffer.subarray(0, Math.min(result.buffer.length, 1024)).toString("utf8").trimStart();
  if (/json/i.test(result.contentType) || head.startsWith("{")) {
    try {
      const data = JSON.parse(result.buffer.toString("utf8"));
      const location = findLocation(data);
      if (location) return await fetchRaw(location);
    } catch (error) {
      if (String(error?.message || error).startsWith("Roblox API")) throw error;
    }
  }
  return result;
}

async function fetchAsset(id) {
  const endpoints = [
    `https://assetdelivery.roblox.com/v2/assetId/${encodeURIComponent(id)}`,
    `https://assetdelivery.roblox.com/v2/asset/?id=${encodeURIComponent(id)}`,
    `https://assetdelivery.roblox.com/v1/assetId/${encodeURIComponent(id)}`,
    `https://assetdelivery.roblox.com/v1/asset/?id=${encodeURIComponent(id)}`,
  ];
  const errors = [];
  for (const endpoint of endpoints) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const delivered = await unwrapDelivery(await fetchRaw(endpoint));
        if (totalBytes + delivered.buffer.length > MAX_TOTAL_BYTES) throw new Error("total pack size limit reached");
        totalBytes += delivered.buffer.length;
        const ext = extFor(delivered.buffer, delivered.contentType);
        const sha256 = crypto.createHash("sha256").update(delivered.buffer).digest("hex");
        const file = `assets/${id}_${sha256.slice(0, 12)}${ext}`;
        await fs.writeFile(path.join(outDir, file), delivered.buffer);
        discoverDependencies(delivered.buffer, delivered.contentType, id);
        return {
          id, ok: true, file, bytes: delivered.buffer.length, sha256,
          contentType: delivered.contentType, endpoint, finalUrl: delivered.finalUrl,
          reasons: [...(reasons.get(id) || [])].sort(),
        };
      } catch (error) {
        errors.push(`${endpoint.replace("https://assetdelivery.roblox.com", "")}: ${String(error?.message || error)}`);
        if (attempt < 2) await new Promise(r => setTimeout(r, 450));
      }
    }
  }
  return { id, ok: false, error: errors.slice(-6).join(" | ") || "unknown", reasons: [...(reasons.get(id) || [])].sort() };
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
  schemaVersion: 3,
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

async function saveAvatar3dAttempt(useGltf) {
  const dir = path.join(outDir, "avatar3d");
  await fs.mkdir(dir, { recursive: true });
  const suffix = useGltf ? "gltf" : "obj";
  const apiUrl = `https://thumbnails.roblox.com/v1/users/avatar-3d?userId=${encodeURIComponent(raw.userId)}&useGltf=${useGltf ? "true" : "false"}`;
  const response = await fetch(apiUrl, {
    redirect: "follow",
    headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
    signal: AbortSignal.timeout(35_000),
  });
  const apiText = await response.text();
  await fs.writeFile(path.join(dir, `api-${suffix}-http-${response.status}.txt`), apiText);
  if (!response.ok) return { useGltf, status: response.status, success: false };
  let meta;
  try { meta = JSON.parse(apiText); } catch { return { useGltf, status: response.status, success: false, error: "non-json response" }; }
  const imageUrl = meta?.imageUrl || meta?.data?.[0]?.imageUrl || null;
  if (!imageUrl) return { useGltf, status: response.status, state: meta?.state || meta?.data?.[0]?.state || null, success: false };

  const payloadResponse = await fetch(imageUrl, {
    redirect: "follow",
    headers: { "User-Agent": USER_AGENT, Accept: "*/*" },
    signal: AbortSignal.timeout(35_000),
  });
  const payload = Buffer.from(await payloadResponse.arrayBuffer());
  const ext = extFor(payload, payloadResponse.headers.get("content-type") || "");
  await fs.writeFile(path.join(dir, `payload-${suffix}${ext}`), payload);

  let payloadJson = null;
  if (ext === ".json") {
    try { payloadJson = JSON.parse(payload.toString("utf8")); } catch {}
  }

  const hashes = new Set();
  const collectHashes = value => {
    if (typeof value === "string" && /^[a-f0-9]{32,128}$/i.test(value)) hashes.add(value);
    else if (Array.isArray(value)) value.forEach(collectHashes);
    else if (value && typeof value === "object") Object.values(value).forEach(collectHashes);
  };
  collectHashes(payloadJson);

  const fetched = [];
  for (const hash of hashes) {
    try {
      let shard = 31;
      for (let i = 0; i < Math.min(38, hash.length); i++) shard ^= hash.charCodeAt(i);
      const cdn = `https://t${Math.abs(shard % 8)}.rbxcdn.com/${hash}`;
      const r = await fetch(cdn, { redirect: "follow", headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(35_000) });
      if (!r.ok) continue;
      const bytes = Buffer.from(await r.arrayBuffer());
      const x = extFor(bytes, r.headers.get("content-type") || "");
      const file = `cdn-${hash}${x}`;
      await fs.writeFile(path.join(dir, file), bytes);
      fetched.push({ hash, file, bytes: bytes.length });
    } catch {}
  }
  await fs.writeFile(path.join(dir, `result-${suffix}.json`), JSON.stringify({ useGltf, success: true, apiUrl, imageUrl, payloadStatus: payloadResponse.status, payloadBytes: payload.length, fetched }, null, 2) + "\n");
  return { useGltf, success: true, payloadBytes: payload.length, fetched: fetched.length };
}

const avatar3d = [];
for (const mode of [true, false]) {
  try { avatar3d.push(await saveAvatar3dAttempt(mode)); }
  catch (error) { avatar3d.push({ useGltf: mode, success: false, error: String(error?.message || error) }); }
}
await fs.writeFile(path.join(outDir, "avatar3d-summary.json"), JSON.stringify(avatar3d, null, 2) + "\n");

console.log(`PACK_READY ${outDir} downloaded=${manifest.downloadedAssetCount} failed=${manifest.failedAssetCount} bytes=${totalBytes} avatar3d=${JSON.stringify(avatar3d)}`);
