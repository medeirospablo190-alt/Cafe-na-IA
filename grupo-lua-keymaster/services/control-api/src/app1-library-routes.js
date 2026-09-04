import { registerApp1LibraryRoutes as registerApp1LibraryRoutesV2 } from "./app1-library-routes-v2.js";
import { registerApp1LibraryHardeningRoutes } from "./app1-library-hardening-routes.js";

export function registerApp1LibraryRoutes(app) {
  registerApp1LibraryHardeningRoutes(app);
  registerApp1LibraryRoutesV2(app);
}
