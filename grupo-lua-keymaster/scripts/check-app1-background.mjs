import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, "..");
const APP_DIR = path.join(ROOT_DIR, "apps", "app1");
const PART_DIR = path.join(APP_DIR, "backgroundData");
const EXPECTED_PART_LENGTHS = [5000, 5000, 5000, 5000, 5000, 4540];
const EXPECTED_BASE64_LENGTH = 29540;
const EXPECTED_BYTES = 22154;
const EXPECTED_SHA256 = "230f15b62e5e896eacebb3aeebd9b417363657773f4619c51f9bd1cded264922";

function fail(message) {
  throw new Error(message);
}

function readPart(index) {
  const filePath = path.join(PART_DIR, `bg${index}.ts`);
  if (!fs.existsSync(filePath)) fail(`parte bg${index}.ts não encontrada`);
  const source = fs.readFileSync(filePath, "utf8").trim();
  const match = /^export default "([A-Za-z0-9+/=]+)";?$/.exec(source);
  if (!match) fail(`bg${index}.ts não contém apenas uma parte Base64 válida`);
  const value = match[1];
  if (value.length !== EXPECTED_PART_LENGTHS[index]) {
    fail(`bg${index}.ts tem ${value.length} caracteres; esperado ${EXPECTED_PART_LENGTHS[index]}`);
  }
  return value;
}

function main() {
  const backgroundModule = fs.readFileSync(path.join(APP_DIR, "loginBackground.ts"), "utf8");
  for (let index = 0; index < EXPECTED_PART_LENGTHS.length; index += 1) {
    if (!backgroundModule.includes(`./backgroundData/bg${index}`)) {
      fail(`loginBackground.ts não importa bg${index}`);
    }
  }
  if (!backgroundModule.includes("data:image/jpeg;base64,")) {
    fail("loginBackground.ts não monta o fundo global como JPEG embutido");
  }

  const base64 = EXPECTED_PART_LENGTHS.map((_, index) => readPart(index)).join("");
  if (base64.length !== EXPECTED_BASE64_LENGTH) {
    fail(`Base64 montado tem ${base64.length} caracteres; esperado ${EXPECTED_BASE64_LENGTH}`);
  }

  const bytes = Buffer.from(base64, "base64");
  if (bytes.length !== EXPECTED_BYTES) {
    fail(`JPEG montado tem ${bytes.length} bytes; esperado ${EXPECTED_BYTES}`);
  }
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9) {
    fail("JPEG montado não possui marcadores SOI/EOI válidos");
  }

  const digest = crypto.createHash("sha256").update(bytes).digest("hex");
  if (digest !== EXPECTED_SHA256) {
    fail(`SHA-256 do fundo não confere: ${digest}`);
  }

  console.log("APP1_BACKGROUND_OK");
  console.log(`- JPEG embutido: ${bytes.length} bytes`);
  console.log(`- SHA-256: ${digest}`);
}

try {
  main();
} catch (error) {
  console.error("APP1_BACKGROUND_INVALID");
  console.error(`- ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
