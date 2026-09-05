import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const loginPath = fileURLToPath(new URL("../../GrupoLuaLogin.lua", import.meta.url));
const source = await readFile(loginPath, "utf8");

function section(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0 || end <= start) {
    throw new Error(`Não foi possível localizar a seção entre ${startMarker} e ${endMarker}.`);
  }
  return source.slice(start, end);
}

function requireText(block, text, label) {
  if (!block.includes(text)) {
    throw new Error(`${label}: trecho obrigatório ausente: ${text}`);
  }
}

const runtimeBlock = section(
  "local function runMenuFunction(fn)",
  "local function fetchManifest(token)"
);

requireText(runtimeBlock, "local runtimeOK, runtimeError = xpcall", "runMenuFunction");
requireText(runtimeBlock, "return false, runtimeError", "runMenuFunction");
requireText(runtimeBlock, "return true", "runMenuFunction");

const runtimeCheckPosition = runtimeBlock.indexOf("if not runtimeOK then");
const destroyPosition = runtimeBlock.indexOf("GUI:Destroy()");
if (runtimeCheckPosition < 0 || destroyPosition < 0 || destroyPosition < runtimeCheckPosition) {
  throw new Error("runMenuFunction deve destruir a UI somente depois de confirmar que não houve erro de runtime.");
}

const manifestBlock = section(
  "local function loadFromManifest(manifest)",
  "local function validate()"
);

requireText(
  manifestBlock,
  "local runtimeOK, runtimeError = runMenuFunction(fn)",
  "loadFromManifest"
);
requireText(manifestBlock, "if not runtimeOK then", "loadFromManifest");
requireText(
  manifestBlock,
  'return false, "Falha de execução", runtimeError',
  "loadFromManifest"
);

console.log("GrupoLuaLogin: proteção contra falha de runtime — OK");
