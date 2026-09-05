import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, "..");
const DEFAULT_APPS = ["app1", "keymaster"];
const MAX_IMAGE_BYTES = 16 * 1024 * 1024;
const MAX_DIMENSION = 16384;
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPEG_SOF_MARKERS = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);

function fail(message) {
  const error = new Error(message);
  error.name = "AssetIntegrityError";
  throw error;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export function validatePng(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 33) fail("PNG pequeno demais ou vazio.");
  if (!buffer.subarray(0, 8).equals(PNG_SIGNATURE)) fail("Assinatura PNG inválida; a extensão pode estar errada.");

  let offset = 8;
  let width = 0;
  let height = 0;
  let chunkIndex = 0;
  let sawIend = false;

  while (offset < buffer.length) {
    if (offset + 12 > buffer.length) fail("PNG truncado no cabeçalho de um chunk.");
    const length = buffer.readUInt32BE(offset);
    const typeStart = offset + 4;
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const crcOffset = dataEnd;
    const nextOffset = crcOffset + 4;
    if (nextOffset > buffer.length) fail("PNG truncado dentro de um chunk.");

    const type = buffer.toString("ascii", typeStart, dataStart);
    const expectedCrc = buffer.readUInt32BE(crcOffset);
    const actualCrc = crc32(buffer.subarray(typeStart, dataEnd));
    if (actualCrc !== expectedCrc) fail(`PNG com CRC inválido no chunk ${type || "?"}.`);

    if (chunkIndex === 0) {
      if (type !== "IHDR" || length !== 13) fail("PNG sem IHDR válido como primeiro chunk.");
      width = buffer.readUInt32BE(dataStart);
      height = buffer.readUInt32BE(dataStart + 4);
    }

    if (type === "IEND") {
      if (length !== 0) fail("PNG com IEND inválido.");
      if (nextOffset !== buffer.length) fail("PNG contém dados extras depois do IEND.");
      sawIend = true;
      offset = nextOffset;
      break;
    }

    chunkIndex += 1;
    offset = nextOffset;
  }

  if (!sawIend) fail("PNG sem chunk IEND; arquivo possivelmente truncado.");
  validateDimensions(width, height, "PNG");
  return { format: "PNG", width, height };
}

export function validateJpeg(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 16) fail("JPEG pequeno demais ou vazio.");
  if (buffer[0] !== 0xff || buffer[1] !== 0xd8) fail("Assinatura JPEG inválida; a extensão pode estar errada.");
  if (buffer[buffer.length - 2] !== 0xff || buffer[buffer.length - 1] !== 0xd9) {
    fail("JPEG sem marcador EOI; arquivo possivelmente truncado.");
  }

  let offset = 2;
  let width = 0;
  let height = 0;
  let sawScan = false;

  while (offset < buffer.length - 2) {
    if (buffer[offset] !== 0xff) fail("JPEG com estrutura inválida entre segmentos.");
    while (offset < buffer.length && buffer[offset] === 0xff) offset += 1;
    if (offset >= buffer.length) fail("JPEG truncado ao ler marcador.");

    const marker = buffer[offset];
    offset += 1;

    if (marker === 0xd9) break;
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;

    if (offset + 2 > buffer.length) fail("JPEG truncado ao ler tamanho de segmento.");
    const segmentLength = buffer.readUInt16BE(offset);
    if (segmentLength < 2) fail("JPEG com tamanho de segmento inválido.");
    const dataStart = offset + 2;
    const segmentEnd = offset + segmentLength;
    if (segmentEnd > buffer.length) fail("JPEG truncado dentro de um segmento.");

    if (JPEG_SOF_MARKERS.has(marker)) {
      if (segmentLength < 7) fail("JPEG com segmento SOF inválido.");
      height = buffer.readUInt16BE(dataStart + 1);
      width = buffer.readUInt16BE(dataStart + 3);
    }

    if (marker === 0xda) {
      sawScan = true;
      break;
    }

    offset = segmentEnd;
  }

  if (!sawScan) fail("JPEG sem segmento SOS válido.");
  validateDimensions(width, height, "JPEG");
  return { format: "JPEG", width, height };
}

function validateDimensions(width, height, label) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    fail(`${label} sem dimensões válidas.`);
  }
  if (width > MAX_DIMENSION || height > MAX_DIMENSION) {
    fail(`${label} excede o limite de ${MAX_DIMENSION}px (${width}x${height}).`);
  }
}

export function validateImageFile(filePath) {
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) fail("O caminho do asset não aponta para um arquivo.");
  if (stat.size <= 0) fail("Asset vazio.");
  if (stat.size > MAX_IMAGE_BYTES) fail(`Asset maior que ${MAX_IMAGE_BYTES / 1024 / 1024} MB.`);

  const buffer = fs.readFileSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const info = ext === ".png"
    ? validatePng(buffer)
    : ext === ".jpg" || ext === ".jpeg"
      ? validateJpeg(buffer)
      : null;
  if (!info) fail(`Formato de imagem não suportado pelo guard: ${ext || "sem extensão"}.`);
  return { ...info, bytes: stat.size };
}

function collectConfiguredAssets(value, found = new Set()) {
  if (typeof value === "string") {
    if (value.startsWith("./assets/")) found.add(value);
    return found;
  }
  if (!value || typeof value !== "object") return found;
  for (const item of Array.isArray(value) ? value : Object.values(value)) {
    collectConfiguredAssets(item, found);
  }
  return found;
}

function listImageFiles(dir) {
  const result = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...listImageFiles(fullPath));
    else if (/\.(png|jpe?g)$/i.test(entry.name)) result.push(fullPath);
  }
  return result.sort();
}

export function validateAppAssets(appId, rootDir = ROOT_DIR) {
  const appDir = path.resolve(rootDir, "apps", appId);
  const configPath = path.join(appDir, "app.json");
  const assetsDir = path.join(appDir, "assets");
  if (!fs.existsSync(configPath)) fail(`${appId}: app.json não encontrado.`);
  if (!fs.existsSync(assetsDir) || !fs.statSync(assetsDir).isDirectory()) fail(`${appId}: pasta assets não encontrada.`);

  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const configuredAssets = collectConfiguredAssets(config);
  for (const ref of configuredAssets) {
    const resolved = path.resolve(appDir, ref);
    const relative = path.relative(assetsDir, resolved);
    if (relative.startsWith("..") || path.isAbsolute(relative)) fail(`${appId}: referência de asset fora da pasta assets: ${ref}`);
    if (!fs.existsSync(resolved)) fail(`${appId}: asset configurado não existe: ${ref}`);
  }

  const imageFiles = listImageFiles(assetsDir);
  if (imageFiles.length === 0) fail(`${appId}: nenhuma imagem PNG/JPEG encontrada em assets.`);

  const validated = imageFiles.map((filePath) => ({
    filePath,
    relativePath: path.relative(rootDir, filePath).replaceAll(path.sep, "/"),
    ...validateImageFile(filePath)
  }));

  for (const ref of configuredAssets) {
    const resolved = path.resolve(appDir, ref);
    if (/\.(png|jpe?g)$/i.test(resolved) && !validated.some((item) => item.filePath === resolved)) {
      fail(`${appId}: asset configurado não foi validado: ${ref}`);
    }
  }

  return validated;
}

function formatBytes(bytes) {
  return bytes < 1024 ? `${bytes} B` : `${(bytes / 1024).toFixed(1)} KB`;
}

function main() {
  const requested = process.argv.slice(2).filter(Boolean);
  const apps = requested.length ? requested : DEFAULT_APPS;
  const all = [];
  for (const appId of apps) {
    for (const item of validateAppAssets(appId)) all.push({ appId, ...item });
  }

  console.log("MOBILE_ASSETS_OK");
  for (const item of all) {
    console.log(`- ${item.appId}: ${item.relativePath} — ${item.format} ${item.width}x${item.height}, ${formatBytes(item.bytes)}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error("MOBILE_ASSETS_INVALID");
    console.error(`- ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
