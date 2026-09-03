import Constants from "expo-constants";

const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>;
const SAFE_FAILURE_URL = "https://control-api.invalid";

function safeControlApiUrl(value: unknown) {
  const raw = String(value || "").trim();
  if (!raw) return SAFE_FAILURE_URL;

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

    if (invalidHost || invalidShape) return SAFE_FAILURE_URL;
    return url.origin;
  } catch {
    return SAFE_FAILURE_URL;
  }
}

// O portal público de downloads e a Control API são serviços diferentes.
// Qualquer configuração insegura é substituída por um domínio reservado e
// não resolvível para que uma credencial Keymaster nunca seja enviada ao destino errado.
export const API_URL = safeControlApiUrl(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || extra.apiUrl || SAFE_FAILURE_URL
);

export const API_CONFIGURED = API_URL !== SAFE_FAILURE_URL;
export const KEYMASTER_MAX_CHARS = 16_384;
