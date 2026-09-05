import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const loginPath = fileURLToPath(new URL("../../GrupoLuaLogin.lua", import.meta.url));
const source = await readFile(loginPath, "utf8");

const OBFUSCATED_MARKER = "--[[ GRUPO LUA - OBFUSCATED BUILD - Prometheus Medium / LuaU ]]";

if (source.startsWith(OBFUSCATED_MARKER)) {
  if (source.length < 10000) {
    throw new Error("GrupoLuaLogin ofuscado está pequeno demais para ser um build válido.");
  }
  if (!source.includes("return(function")) {
    throw new Error("GrupoLuaLogin ofuscado não possui a estrutura esperada do build Prometheus.");
  }

  const leakedClearText = [
    "local function fetchManifest(token)",
    "local function resolveDeviceId()",
    "local function runMenuFunction(fn)",
    "https://grupo-lua-control-api.onrender.com",
    "INVALID_MENU_KEY",
    "GrupoLuaAccess"
  ];

  for (const text of leakedClearText) {
    if (source.includes(text)) {
      throw new Error(`GrupoLuaLogin ofuscado ainda expõe trecho sensível em claro: ${text}`);
    }
  }

  console.log("GrupoLuaLogin: build público ofuscado detectado — estrutura básica OK");
  process.exit(0);
}

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
