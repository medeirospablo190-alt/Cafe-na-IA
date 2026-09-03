import Constants from "expo-constants";

const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>;

function safeControlApiUrl(value: unknown) {
  const raw = String(value || "").trim();
  if (!raw) return "";

  try {
    const url = new URL(raw);
    const hostname = url.hostname.toLowerCase();
    const invalidHost = hostname === "cafe-na-ia.onrender.com" ||
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "::1" ||
      hostname.endsWith(".invalid");
    const invalidShape = url.protocol !== "https:" ||
      Boolean(url.username || url.password) ||
      Boolean((url.pathname && url.pathname !== "/") || url.search || url.hash);

    if (invalidHost || invalidShape) return "";
    return url.origin;
  } catch {
    return "";
  }
}

export const API_URL = safeControlApiUrl(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || extra.apiUrl || ""
);

export function requireApiUrl() {
  if (!API_URL) {
    throw new Error("Servidor do GRUPO LUA não foi configurado com uma Control API HTTPS válida nesta build.");
  }
  return API_URL;
}
