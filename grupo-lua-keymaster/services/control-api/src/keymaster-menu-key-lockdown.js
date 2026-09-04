function sendApp1Only(res) {
  return res.status(410).json({
    ok: false,
    code: "MENU_KEYS_APP1_ONLY",
    message: "FREE e VIP são administradas exclusivamente pelo App 1."
  });
}

export function registerKeymasterMenuKeyLockdown(app) {
  // Estas rotas antigas continuam existentes no módulo legado por compatibilidade
  // de código, mas são interceptadas antes dele. Assim um cliente Keymaster antigo
  // não consegue criar, renovar ou alterar FREE/VIP fora do App 1.
  app.all("/v1/keymaster/menus/:id/keys", (_req, res) => sendApp1Only(res));
  app.all("/v1/keymaster/menu-keys/:keyId/state/:action", (_req, res) => sendApp1Only(res));
  app.all("/v1/keymaster/menu-keys/:keyId/duration", (_req, res) => sendApp1Only(res));
}
