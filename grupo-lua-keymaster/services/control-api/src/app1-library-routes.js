import { registerApp1LibraryRoutes as registerApp1LibraryRoutesV2 } from "./app1-library-routes-v2.js";
import { registerApp1LibraryHardeningRoutes } from "./app1-library-hardening-routes.js";
import { registerApp1MenuKeyRoutes } from "./app1-menu-keys-routes.js";
import { registerApp1SessionControlRoutes } from "./app1-session-control-routes.js";

export function registerApp1LibraryRoutes(app) {
  // Registrado aqui para manter o server.js pequeno sem criar uma segunda
  // implementação de autenticação do App 1. O logout revoga a sessão atual
  // no servidor antes de o aplicativo apagar o token local.
  registerApp1SessionControlRoutes(app);
  registerApp1LibraryHardeningRoutes(app);
  registerApp1LibraryRoutesV2(app);
  registerApp1MenuKeyRoutes(app);
}
