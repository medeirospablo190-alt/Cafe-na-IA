import crypto from "crypto";
import { promisify } from "util";

const scryptAsync = promisify(crypto.scrypt);
const SCRYPT_N = 32768;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SCRYPT_BYTES = 64;
const SCRYPT_MAXMEM = 128 * SCRYPT_N * SCRYPT_R * 4;

function b64url(buffer) {
  return Buffer.from(buffer).toString("base64url");
}

export async function hashSecret(secret) {
  const salt = crypto.randomBytes(24);
  const derived = await scryptAsync(String(secret), salt, SCRYPT_BYTES, {
    N: SCRYPT_N,
    r: SCRYPT_R,
    p: SCRYPT_P,
    maxmem: SCRYPT_MAXMEM
  });
  return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${b64url(salt)}$${b64url(derived)}`;
}

export async function verifySecret(secret, encoded) {
  try {
    const [kind, n, r, p, salt64, hash64] = String(encoded || "").split("$");
    if (kind !== "scrypt") return false;
    const expected = Buffer.from(hash64, "base64url");
    const derived = await scryptAsync(String(secret), Buffer.from(salt64, "base64url"), expected.length, {
      N: Number(n),
      r: Number(r),
      p: Number(p),
      maxmem: 128 * Number(n) * Number(r) * 4
    });
    return expected.length === derived.length && crypto.timingSafeEqual(expected, derived);
  } catch {
    return false;
  }
}

export function randomToken(bytes = 48) {
  return crypto.randomBytes(bytes).toString("base64url");
}

export function randomId() {
  return crypto.randomUUID();
}

export function tokenHash(token) {
  const pepper = String(process.env.SESSION_PEPPER || "");
  if (pepper.length < 32) throw new Error("SESSION_PEPPER precisa ter pelo menos 32 caracteres.");
  return crypto.createHmac("sha256", pepper).update(String(token)).digest("base64url");
}

export function privacyHash(value, purpose = "generic") {
  const pepper = String(process.env.DEVICE_FINGERPRINT_PEPPER || "");
  if (pepper.length < 32) throw new Error("DEVICE_FINGERPRINT_PEPPER precisa ter pelo menos 32 caracteres.");
  return crypto.createHmac("sha256", pepper).update(`${purpose}\0${String(value || "")}`).digest("base64url");
}

export function deriveDeviceFingerprint({ platform, nativeDeviceId, integrityKeyId, installationId }) {
  // A instalação NÃO entra no fingerprint quando há um identificador nativo
  // mais estável. Assim, reinstalar o app não concede novas três tentativas
  // em plataformas nas quais o identificador nativo permanece igual.
  const anchor = String(nativeDeviceId || integrityKeyId || installationId || "");
  const stable = [String(platform || "unknown").toLowerCase(), anchor].join("\u001f");
  return privacyHash(stable, "keymaster-device");
}

export function normalizeLogin(input) {
  return String(input || "")
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 80);
}

const KEY_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function randomChars(count) {
  let out = "";
  const bytes = crypto.randomBytes(count * 2);
  let cursor = 0;
  while (out.length < count) {
    if (cursor >= bytes.length) return out + randomChars(count - out.length);
    const value = bytes[cursor++];
    if (value < 256 - (256 % KEY_ALPHABET.length)) out += KEY_ALPHABET[value % KEY_ALPHABET.length];
  }
  return out;
}

export function createApp1Credential(login, role) {
  if (role === "DEV") {
    const prefix = "DEV-";
    return prefix + randomChars(600 - prefix.length);
  }
  const normalized = normalizeLogin(login)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9]/g, "")
    .slice(0, 24) || "ADM";
  const prefix = `ADM1-${normalized}-`;
  return prefix + randomChars(Math.max(1, 256 - prefix.length));
}
