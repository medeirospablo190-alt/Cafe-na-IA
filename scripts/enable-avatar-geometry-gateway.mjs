import fs from "fs";

const file = "avatar-gateway.js";
let source = fs.readFileSync(file, "utf8");

const importLine = 'import { installAvatarGeometryRoutes } from "./avatar-geometry-routes.js";\n';
const importMarker = 'import { fileURLToPath } from "url";\n';
const installLine = 'installAvatarGeometryRoutes(app);\n';
const installMarker = 'app.set("trust proxy", 1);\n';

let changed = false;

if (!source.includes(importLine)) {
  if (!source.includes(importMarker)) {
    throw new Error("Import marker not found in avatar-gateway.js");
  }
  source = source.replace(importMarker, importMarker + importLine);
  changed = true;
}

if (!source.includes(installLine)) {
  if (!source.includes(installMarker)) {
    throw new Error("Install marker not found in avatar-gateway.js");
  }
  source = source.replace(installMarker, installMarker + "\n" + installLine);
  changed = true;
}

if (changed) {
  fs.writeFileSync(file, source, "utf8");
  console.log("Avatar geometry routes enabled in avatar-gateway.js");
} else {
  console.log("Avatar geometry gateway already enabled.");
}
