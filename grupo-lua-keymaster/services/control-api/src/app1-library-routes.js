import { registerApp1LibraryRoutes as registerApp1LibraryRoutesV2 } from "./app1-library-routes-v2.js";
import { registerApp1LibraryHardeningRoutes } from "./app1-library-hardening-routes.js";
import { registerApp1SessionControlRoutes } from "./app1-session-control-routes.js";
import { registerApp1MenuKeyRoutes } from "./app1-menu-key-routes.js";
import { registerMenuAccessV2Routes } from "./menu-access-v2-routes.js";

export function registerApp1LibraryRoutes(app) {
  // Registrado aqui para manter o server.js pequeno sem criar rotas paralelas
  // no bootstrap principal. As rotas V2 de menu sao registradas antes do
  // menu-routes legado, portanto validacao e manifest usam device binding.
  registerApp1SessionControlRoutes(app);
  registerApp1LibraryHardeningRoutes(app);
  registerApp1LibraryRoutesV2(app);
  registerApp1MenuKeyRoutes(app);
  registerMenuAccessV2Routes(app);
}