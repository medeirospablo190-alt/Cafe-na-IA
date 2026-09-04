import { registerApp1LibraryRoutes as registerApp1LibraryRoutesV2 } from "./app1-library-routes-v2.js";
import { registerApp1LibraryHardeningRoutes } from "./app1-library-hardening-routes.js";
import { registerApp1SessionControlRoutes } from "./app1-session-control-routes.js";
import { registerApp1MenuKeyRoutes } from "./app1-menu-key-routes.js";
import { registerApp1SocialRoutes } from "./app1-social-routes.js";
import { registerApp1ChatRoutes } from "./app1-chat-routes.js";
import { registerMenuAccessV2Routes } from "./menu-access-v2-routes.js";
import { registerKeymasterMenuKeyLockdown } from "./keymaster-menu-key-lockdown.js";

export function registerApp1LibraryRoutes(app) {
  // Registrado aqui para manter o server.js pequeno sem criar rotas paralelas
  // no bootstrap principal. As rotas novas entram antes do menu-routes legado.
  registerApp1SessionControlRoutes(app);
  registerApp1SocialRoutes(app);
  registerApp1ChatRoutes(app);
  registerApp1LibraryHardeningRoutes(app);
  registerApp1LibraryRoutesV2(app);
  registerApp1MenuKeyRoutes(app);
  registerMenuAccessV2Routes(app);

  // FREE/VIP pertencem exclusivamente ao App 1. Intercepta as rotas antigas
  // do Keymaster antes de registerMenuRoutes registrar a implementação legada.
  registerKeymasterMenuKeyLockdown(app);
}