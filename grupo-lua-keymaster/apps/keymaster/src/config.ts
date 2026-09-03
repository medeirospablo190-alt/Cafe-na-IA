import Constants from "expo-constants";

const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>;

// O portal público de downloads e a Control API são serviços diferentes.
// Se a URL privada não for configurada na build, usamos um domínio reservado
// não resolvível em vez de arriscar enviar credenciais ao portal errado.
export const API_URL = String(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || extra.apiUrl || "https://control-api.invalid"
).replace(/\/+$/, "");

export const KEYMASTER_MAX_CHARS = 16_384;
