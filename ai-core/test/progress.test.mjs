import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { computeProgress } from "../src/progress.mjs";

const plan=JSON.parse(readFileSync(new URL("../plan/progress.json",import.meta.url),"utf8"));

test("progresso total 100 e sem conclusao prematura",()=>{
  const result=computeProgress(plan);
  assert.equal(result.overallPercent,59);
  assert.equal(result.remainingPercent,41);
  assert.equal(result.isComplete,false);
});
test("impede porcentagem inflada, etapa duplicada e soma diferente de 100",()=>{
  const phases=plan.phases.map(p=>({...p}));
  phases[0].earned=999;
  assert.throws(()=>computeProgress({...plan,phases}));
  assert.throws(()=>computeProgress({...plan,phases:[...plan.phases.slice(1),plan.phases[1]]}));
  assert.throws(()=>computeProgress({...plan,phases:plan.phases.slice(1)}));
});
