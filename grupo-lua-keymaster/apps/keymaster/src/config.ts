import Constants from "expo-constants";

const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>;

export const API_URL = String(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || extra.apiUrl || "https://cafe-na-ia.onrender.com"
).replace(/\/+$/, "");

export const KEYMASTER_MAX_CHARS = 16_384;
