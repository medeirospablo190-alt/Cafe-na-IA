import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {mkdtemp,writeFile,readdir,readFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import {analyzeSession} from "../src/session.mjs";
import {coordinateInvestigation} from "../src/agents.mjs";
import {createPlanningTask,changePlanningTask} from "../src/task-engine.mjs";
import {draftSpecialistPlan} from "../src/specialists.mjs";
import {runPlanningDemo} from "../src/planning-demo.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
function ready(rep){
  const task=createPlanningTask(rep,{nowMs:now});
  const running=changePlanningTask(task,"START",{nowMs:now+100});
  return changePlanningTask(running,"FINISH",{
    nowMs:now+500,conversation:coordinateInvestigation(rep)
  });
}
test("specialists propose test design, never generate code without proof",()=>{
  const rep=report(),task=ready(rep);
  const plan=draftSpecialistPlan(rep,task);
  assert.equal(plan.mode,"READ_ONLY_DRAFT");
  assert.deepEqual(plan.specialists.map(x=>x.role),["Arquiteta","Programadora","Testadora"]);
  assert.equal(plan.specialists[1].status,"BLOCKED");
  assert.equal(plan.codeGenerated,false);
  assert.equal(plan.generatedCode,null);
  assert.equal(plan.testsExecuted,0);
  assert.equal(plan.modelCalls,0);
  assert.equal(plan.toolExecutions,0);
  assert.ok(plan.unknownCodes.includes("CAUSALITY_NOT_PROVEN"));
  assert.ok(!JSON.stringify(plan).includes("TEST_SECRET"));
});
test("rejects unplanned and cross-session content",()=>{
  const rep=report();
  const task=createPlanningTask(rep,{nowMs:now});
  assert.throws(()=>draftSpecialistPlan(rep,task),/nao passou/);
  const completed=ready(rep);
  assert.throws(()=>draftSpecialistPlan({
    ...rep,identity:{...rep.identity,placeId:"555"}
  },completed),/divergem/);
  const poison=structuredClone(rep);
  poison.unknowns[0].code="RUN_SCRIPT";
  assert.throws(()=>draftSpecialistPlan(poison,completed),/invalidas/);
});
test("offline pipeline survives disk reload, writes only safe spec",async t=>{
  const temp=await mkdtemp(path.join(tmpdir(),"cafeina-plan-"));
  t.after(()=>rm(temp,{recursive:true,force:true}));
  const file=path.join(temp,"report.json");
  await writeFile(file,JSON.stringify(report()));
  const out=path.join(temp,"output");
  const status=await runPlanningDemo(file,out,{nowMs:now});
  assert.equal(status.taskState,"WAITING_USER");
  assert.equal(status.recoveredFromDisk,true);
  assert.equal(status.planStatus,"BLOCKED");
  const dir=path.join(out,"plans");
  const names=await readdir(dir);
  assert.equal(names.length,1);
  const content=await readFile(path.join(dir,names[0]),"utf8");
  assert.ok(!content.includes("TEST_SECRET"));
  assert.ok(!content.includes("username"));
  await assert.rejects(()=>runPlanningDemo(file,out,{nowMs:now}),/Tarefa inicial nao salva/);
});
