import Constants from "expo-constants";

const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>;

export const API_URL = String(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || extra.apiUrl || ""
).replace(/\/+$/, "");

export function requireApiUrl() {
  if (!API_URL) {
    throw new Error("Servidor do GRUPO LUA ainda não foi configurado nesta build.");
  }
  return API_URL;
}
