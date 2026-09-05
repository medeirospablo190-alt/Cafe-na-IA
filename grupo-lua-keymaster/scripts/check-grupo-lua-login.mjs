import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const loginPath = fileURLToPath(new URL("../../GrupoLuaLogin.lua", import.meta.url));
const source = await readFile(loginPath, "utf8");

const OBFUSCATED_MARKER = "--[[ GRUPO LUA - OBFUSCATED BUILD - Prometheus Medium / LuaU ]]";
const WRAPPER_MARKER = "GRUPO LUA — LOGIN PROTECTED RUNTIME WRAPPER";

function requireSourceText(text, label) {
  if (!source.includes(text)) {
    throw new Error(`${label}: trecho obrigatório ausente: ${text}`);
  }
}

if (source.includes(WRAPPER_MARKER)) {
  const commitMatch = source.match(/local BUILD_COMMIT = "([0-9a-f]{40})"/i);
  if (!commitMatch) {
    throw new Error("GrupoLuaLogin wrapper deve fixar BUILD_COMMIT em um SHA Git completo de 40 caracteres.");
  }

  requireSourceText('"https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/" .. BUILD_COMMIT .. "/GrupoLuaLogin.lua"', "wrapper");
  requireSourceText("game:HttpGet(BUILD_URL, true)", "wrapper");
  requireSourceText("local compiled, compileError = loadstring(source)", "wrapper");
  requireSourceText("if not compiled then", "wrapper");
  requireSourceText("return compiled()", "wrapper");

  if (source.includes('/main/GrupoLuaLogin.lua') || source.includes('/refs/heads/main/')) {
    throw new Error("GrupoLuaLogin wrapper não pode carregar o build protegido a partir de main mutável.");
  }

  console.log(`GrupoLuaLogin: wrapper protegido com build imutável ${commitMatch[1]} — OK`);
  process.exit(0);
}

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
