import { registerApp1LibraryRoutes as registerApp1LibraryRoutesV2 } from "./app1-library-routes-v2.js";
import { registerApp1LibraryHardeningRoutes } from "./app1-library-hardening-routes.js";
import { registerApp1SessionControlRoutes } from "./app1-session-control-routes.js";
import { registerApp1MenuManagementV2Routes } from "./app1-menu-management-v2-routes.js";
import { registerApp1MenuKeyV2Routes } from "./app1-menu-key-v2-routes.js";
import { registerApp1MenuKeyRoutes } from "./app1-menu-key-routes.js";
import { registerApp1SocialRoutes } from "./app1-social-routes.js";
import { registerApp1ChatRoutes } from "./app1-chat-routes.js";
import { registerMenuInlineSourceRoutes } from "./menu-inline-source-routes.js";
import { registerMenuAccessV2Routes } from "./menu-access-v2-routes.js";
import { registerKeymasterMenuKeyLockdown } from "./keymaster-menu-key-lockdown.js";
import { registerKeymasterMenuManagementLockdown } from "./keymaster-menu-management-lockdown.js";

export function registerApp1LibraryRoutes(app) {
  // Registrado aqui para manter o server.js pequeno sem criar rotas paralelas
  // no bootstrap principal. As rotas novas entram antes do menu-routes legado.
  registerApp1SessionControlRoutes(app);
  registerApp1SocialRoutes(app);
  registerApp1ChatRoutes(app);
  registerApp1LibraryHardeningRoutes(app);
  registerApp1LibraryRoutesV2(app);

  // V2 é registrada antes da implementação antiga: propriedade por conta,
  // fonte Lua privada e proteção contra acesso a menu/chave de outra conta.
  registerApp1MenuManagementV2Routes(app);
  registerApp1MenuKeyV2Routes(app);

  // Compatibilidade com clientes antigos e entrega de fonte: menus INLINE usam
  // um tíquete curto; menus REMOTE_URL continuam no manifest V2 já existente.
  registerApp1MenuKeyRoutes(app);
  registerMenuInlineSourceRoutes(app);
  registerMenuAccessV2Routes(app);

  // FREE/VIP pertencem exclusivamente ao App 1. Novos menus também passam a
  // nascer no App 1; o Keymaster só mantém escrita em menus legados sem dono.
  registerKeymasterMenuKeyLockdown(app);
  registerKeymasterMenuManagementLockdown(app);
}
