const raw = String(process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || "").trim();

function fail(message) {
  console.error("MOBILE_BUILD_API_NOT_READY");
  console.error(`- ${message}`);
  process.exit(1);
}

if (!raw) {
  fail("EXPO_PUBLIC_GRUPO_LUA_API_URL não foi configurada para esta build");
}

let url;
try {
  url = new URL(raw);
} catch {
  fail("EXPO_PUBLIC_GRUPO_LUA_API_URL não é uma URL válida");
}

if (url.protocol !== "https:") {
  fail("a Control API precisa usar HTTPS");
}

if (url.username || url.password) {
  fail("a URL da Control API não pode conter credenciais embutidas");
}

const hostname = url.hostname.toLowerCase();
if (hostname === "cafe-na-ia.onrender.com") {
  fail("o portal público de downloads não pode ser usado como Control API");
}

if (
  hostname === "localhost" ||
  hostname === "127.0.0.1" ||
  hostname === "::1" ||
  hostname.endsWith(".invalid")
) {
  fail("a build exige uma Control API pública real, não localhost ou domínio reservado");
}

if ((url.pathname && url.pathname !== "/") || url.search || url.hash) {
  fail("configure apenas a origem HTTPS da Control API, sem caminho, query string ou fragmento");
}

console.log("MOBILE_BUILD_API_READY");
console.log(`- api origin: ${url.origin}`);
console.log(`- eas profile: ${process.env.EAS_BUILD_PROFILE || "manual"}`);
console.log(`- platform: ${process.env.EAS_BUILD_PLATFORM || "manual"}`);
