#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { analyzeV3 } from "./analysis.mjs";

async function main() {
  const [, , batchPath, manifestPath] = process.argv;
  if (!batchPath || !manifestPath || process.argv.length !== 4) {
    throw new Error("Uso: node src/cli.mjs <batch.json> <latest.json>");
  }
  const [batch, manifest] = await Promise.all([
    readFile(batchPath, "utf8").then(JSON.parse),
    readFile(manifestPath, "utf8").then(JSON.parse)
  ]);
  process.stdout.write(JSON.stringify(analyzeV3(batch, manifest), null, 2) + "\n");
}
main().catch(e => {
  process.stderr.write("CAFEINA_AI_ERROR: " + e.message + "\n");
  process.exitCode = 1;
});
