import fs from "fs/promises";
import crypto from "crypto";
import { promisify } from "util";

const scryptAsync = promisify(crypto.scrypt);
const file = process.argv[2];
if (!file) {
  console.error("Uso: node scripts/hash-keymaster.mjs /caminho/KEYMASTER_ACCESS_KEY.txt");
  process.exit(1);
}

const secret = (await fs.readFile(file, "utf8")).trim();
if (secret.length < 5000 || secret.length > 16384) {
  console.error(`A chave tem ${secret.length} caracteres; esperado entre 5000 e 16384.`);
  process.exit(1);
}

const N = 32768, r = 8, p = 1;
const salt = crypto.randomBytes(24);
const derived = await scryptAsync(secret, salt, 64, { N, r, p, maxmem: 128 * N * r * 4 });
const encoded = `scrypt$${N}$${r}$${p}$${salt.toString("base64url")}$${Buffer.from(derived).toString("base64url")}`;
console.log(`KEYMASTER_ACCESS_HASH=${encoded}`);
console.error(`OK: ${secret.length} caracteres processados. A chave original não foi impressa.`);
