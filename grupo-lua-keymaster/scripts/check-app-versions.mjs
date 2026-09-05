import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const apps = ["app1", "keymaster"];
const semver = /^\d+\.\d+\.\d+$/;

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

for (const app of apps) {
  const appRoot = resolve(root, "apps", app);
  const packageJson = await readJson(resolve(appRoot, "package.json"));
  const appJson = await readJson(resolve(appRoot, "app.json"));

  const packageVersion = packageJson.version;
  const expoVersion = appJson?.expo?.version;
  const androidVersionCode = appJson?.expo?.android?.versionCode;

  if (!semver.test(String(packageVersion || ""))) {
    throw new Error(`${app}: package.json possui versão inválida: ${String(packageVersion)}`);
  }

  if (!semver.test(String(expoVersion || ""))) {
    throw new Error(`${app}: app.json possui versão Expo inválida: ${String(expoVersion)}`);
  }

  if (packageVersion !== expoVersion) {
    throw new Error(`${app}: package.json (${packageVersion}) e app.json (${expoVersion}) estão divergentes.`);
  }

  if (!Number.isInteger(androidVersionCode) || androidVersionCode <= 0) {
    throw new Error(`${app}: android.versionCode deve ser um inteiro positivo.`);
  }

  console.log(`${app}: versão ${expoVersion}, Android versionCode ${androidVersionCode} — OK`);
}
