export const GRUPO_LUA_LOGIN_RAW_URL =
  "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaLogin.lua";

export function normalizePublicMenuId(value: string) {
  return String(value || "").trim();
}

export function isValidPublicMenuId(value: string) {
  return /^menu_[A-Za-z0-9_-]{6,80}$/.test(normalizePublicMenuId(value));
}

export function buildMenuLoader(menuId: string) {
  const normalized = normalizePublicMenuId(menuId);
  if (!isValidPublicMenuId(normalized)) return "";

  return [
    `getgenv().GRUPO_LUA_MENU_ID = ${JSON.stringify(normalized)}`,
    `loadstring(game:HttpGet(${JSON.stringify(GRUPO_LUA_LOGIN_RAW_URL)}))()`
  ].join("\n");
}
