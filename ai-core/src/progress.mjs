#!/usr/bin/env node
import { readFile } from "node:fs/promises";

export function computeProgress(plan) {
  if (!plan || !Array.isArray(plan.phases) || plan.phases.length !== 9) {
    throw new Error("Plano exige nove etapas");
  }
  const ids = new Set();
  let total = 0, earned = 0;
  for (const phase of plan.phases) {
    if (typeof phase.id !== "string" || ids.has(phase.id)) throw new Error("ID duplicado");
    ids.add(phase.id);
    if (!Number.isInteger(phase.weight) || phase.weight < 1 ||
        !Number.isInteger(phase.earned) || phase.earned < 0 || phase.earned > phase.weight) {
      throw new Error("Peso ou progresso invalido");
    }
    const expected = phase.earned === 0 ? "not_started" :
      phase.earned === phase.weight ? "completed" : "in_progress";
    if (phase.status !== expected) throw new Error("Estado inconsistente: " + phase.id);
    total += phase.weight; earned += phase.earned;
  }
  if (total !== 100) throw new Error("A soma deve ser 100");
  return {
    project: plan.project,
    asOf: plan.asOf,
    completedPoints: earned,
    totalPoints: 100,
    overallPercent: earned,
    remainingPercent: 100 - earned,
    isComplete: earned === 100,
    phases: plan.phases
  };
}
async function main() {
  const p = JSON.parse(await readFile(new URL("../plan/progress.json", import.meta.url), "utf8"));
  process.stdout.write(JSON.stringify(computeProgress(p), null, 2) + "\n");
}
if (process.argv[1]?.endsWith("/progress.mjs")) {
  main().catch(e => {
    process.stderr.write("PROGRESS_ERROR: " + e.message + "\n");
    process.exitCode = 1;
  });
}
