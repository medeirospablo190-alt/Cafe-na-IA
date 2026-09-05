import { readdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const serviceRoot = fileURLToPath(new URL("..", import.meta.url));
const scanRoots = [resolve(serviceRoot, "src"), resolve(serviceRoot, "scripts")];
const supportedExtensions = new Set([".js", ".mjs"]);

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectFiles(path));
      continue;
    }

    if (entry.isFile() && supportedExtensions.has(extname(entry.name))) {
      files.push(path);
    }
  }

  return files;
}

const files = (await Promise.all(scanRoots.map(collectFiles)))
  .flat()
  .sort((a, b) => a.localeCompare(b));

if (files.length === 0) {
  console.error("Nenhum arquivo JavaScript da Control API foi encontrado para validar.");
  process.exit(1);
}

for (const file of files) {
  const displayName = relative(serviceRoot, file);
  const result = spawnSync(process.execPath, ["--check", file], {
    cwd: serviceRoot,
    stdio: "inherit"
  });

  if (result.error) {
    console.error(`Falha ao iniciar a validação de sintaxe para ${displayName}:`, result.error);
    process.exit(1);
  }

  if (result.status !== 0) {
    console.error(`Sintaxe inválida em ${displayName}.`);
    process.exit(result.status ?? 1);
  }
}

console.log(`Sintaxe validada em ${files.length} arquivo(s) da Control API.`);
