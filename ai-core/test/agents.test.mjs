import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {coordinateInvestigation} from "../src/agents.mjs";
const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const make=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
test("4 agentes trocam mensagens estruturadas, sem LLM ou execucao",()=>{
  const out=coordinateInvestigation(make());
  assert.equal(out.messages.length,4);
  assert.equal(out.messages.at(-1).detail.status,"WAITING_USER");
  assert.equal(out.mode,"DETERMINISTIC_REHEARSAL");
  assert.equal(out.budgets.modelCalls,0);
  assert.equal(out.budgets.toolExecutions,0);
  assert.equal(out.proposedMission.executable,false);
  assert.equal(out.codeGenerated,false);
  assert.ok(!JSON.stringify(out).includes("TEST_SECRET"));
});
test("limite de etapas, evidencias e relatorio suspeito",()=>{
  assert.equal(coordinateInvestigation(make(),{maxSteps:2}).messages.length,2);
  assert.throws(()=>coordinateInvestigation(make(),{maxSteps:100}),/Limite/);
  const x=make();x.coverage.causalValidation=true;
  assert.throws(()=>coordinateInvestigation(x),/confiavel/);
  const y=make();y.unknowns[0].code="EXECUTE_SHELL";
  assert.throws(()=>coordinateInvestigation(y),/invalidos/);
});
