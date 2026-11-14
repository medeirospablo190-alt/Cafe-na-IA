#!/usr/bin/env node
import { readdir, open, lstat, mkdir, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";
import { analyzeSession } from "./session.mjs";
import { persistSession } from "./store.mjs";

const MAX_FILE_BYTES = 8 * 1024 * 1024;
const MAX_SESSION_BYTES = 150 * 1024 * 1024;

async function readLimitedJson(file) {
  const stat = await lstat(file);
  if (!stat.isFile() || stat.size > MAX_FILE_BYTES) throw new Error("Arquivo nao regular ou muito grande.");
  const handle = await open(file, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
  try {
    const s = await handle.stat();
    if (!s.isFile() || s.size > MAX_FILE_BYTES) throw new Error("Arquivo invalido.");
    return JSON.parse(await handle.readFile("utf8"));
  } finally {
    await handle.close();
  }
}

function parseArgs(argv) {
  if (argv.length % 2 !== 0) throw new Error("Argumentos devem vir em pares.");
  const accepted = new Set(["--session-dir", "--manifest", "--profile", "--store", "--out"]);
  const args = Object.create(null);
  for (let i = 0; i < argv.length; i += 2) {
    if (!accepted.has(argv[i]) || !argv[i + 1] || args[argv[i]]) {
      throw new Error("Argumento incorreto ou repetido.");
    }
    args[argv[i]] = argv[i + 1];
  }
  if (!args["--session-dir"] || !args["--manifest"]) {
    throw new Error("Uso: node src/session-cli.mjs --session-dir DIR --manifest latest.json [--profile profile.json] [--store DIR] [--out relatorio.json]");
  }
  return args;
}

export async function analyzeDirectory(args) {
  const dir = path.resolve(args["--session-dir"]);
  const names = (await readdir(dir)).filter(x => /^[0-9]{4}-data\.json$/.test(x)).sort();
  if (!names.length || names.length > 520) throw new Error("Sessao deve conter 1 a 520 lotes data.");
  let bytes = 0;
  const batches = [];
  for (const name of names) {
    const file = path.join(dir, name);
    const stat = await lstat(file);
    bytes += stat.size;
    if (bytes > MAX_SESSION_BYTES) throw new Error("Limite de 150 MB excedido.");
    const raw = await readLimitedJson(file);
    const index = Number(name.slice(0, 4));
    if (raw.batchIndex !== index || raw.batchKind !== "data") {
      throw new Error("Nome do arquivo e indice do lote divergentes.");
    }
    batches.push(raw);
  }
  const manifest = await readLimitedJson(path.resolve(args["--manifest"]));
  const profile = args["--profile"] ? await readLimitedJson(path.resolve(args["--profile"])) : null;
  const report = analyzeSession({ batches, manifest, profile });
  if (args["--store"]) {
    report.persistence = await persistSession(args["--store"], report);
  }
  if (args["--out"]) {
    const target = path.resolve(args["--out"]);
    await mkdir(path.dirname(target), {recursive:true});
    // No accidental overwrites of analysis artifacts.
    await writeFile(target, JSON.stringify(report, null, 2) + "\n", {flag:"wx"});
  }
  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = await analyzeDirectory(args);
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}
if (process.argv[1] && import.meta.url === new URL("file://" + path.resolve(process.argv[1])).href) {
  main().catch(error => {
    process.stderr.write("CAFEINA_SESSION_ERROR: " + String(error.message || error) + "\n");
    process.exitCode = 1;
  });
}
