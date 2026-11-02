import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {mkdtemp,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import {analyzeSession} from "../src/session.mjs";
import {coordinateInvestigation} from "../src/agents.mjs";
import {createPlanningTask,changePlanningTask,savePlanningTask,loadPlanningTask} from "../src/task-engine.mjs";

const fixture=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[fixture("batch.json")],manifest:fixture("latest.json")});
const clock=1700000000000;
test("tarefa segura atravessa reinicio de processo sem executar comandos",async t=>{
  const folder=await mkdtemp(path.join(tmpdir(),"cafeina-task-"));
  t.after(()=>rm(folder,{recursive:true,force:true}));
  const rep=report(),base=createPlanningTask(rep,{nowMs:clock});
  assert.equal(base.status,"CREATED");
  assert.equal(base.remoteExecutionAllowed,false);
  assert.equal(base.modelCallLimit,0);
  assert.equal((await savePlanningTask(folder,base)).status,"SAVED");
  const fromDisk=await loadPlanningTask(folder,base.identity.gameId,base.taskId);
  assert.deepEqual(fromDisk,base);
  const running=changePlanningTask(fromDisk,"START",{nowMs:clock+1000,leaseMs:3000});
  await savePlanningTask(folder,running,{expectedRevision:0});
  const recovered=changePlanningTask(await loadPlanningTask(folder,base.identity.gameId,base.taskId),
    "RECOVER",{nowMs:clock+4000});
  assert.equal(recovered.status,"CREATED");
  assert.equal(recovered.attempt,1);
  await savePlanningTask(folder,recovered,{expectedRevision:1});
  const resumed=changePlanningTask(recovered,"START",{nowMs:clock+5000,leaseMs:3000});
  assert.equal(resumed.attempt,2);
  await savePlanningTask(folder,resumed,{expectedRevision:2});
  const finish=changePlanningTask(resumed,"FINISH",{nowMs:clock+6000,
    conversation:coordinateInvestigation(rep)});
  assert.equal(finish.status,"WAITING_USER");
  assert.equal(finish.decision,"WAITING_USER");
  assert.equal(finish.remoteExecutionAllowed,false);
  await savePlanningTask(folder,finish,{expectedRevision:3});
  assert.equal((await loadPlanningTask(folder,base.identity.gameId,base.taskId)).status,"WAITING_USER");
  assert.equal((await savePlanningTask(folder,finish)).status,"UNCHANGED");
  await assert.rejects(()=>savePlanningTask(folder,{...finish,revision:5}),/CONFLICT/);
  const cancelled=changePlanningTask(finish,"CANCEL",{nowMs:clock+7000});
  await savePlanningTask(folder,cancelled,{expectedRevision:4});
  assert.equal(cancelled.status,"CANCELLED");
  assert.throws(()=>changePlanningTask(cancelled,"START",{nowMs:clock+8000}),/terminal/);
});
test("recovery apos limite de tentativas e expiracao",()=>{
  const base=createPlanningTask(report(),{nowMs:clock,maxAttempts:1,ttlMs:60000});
  const running=changePlanningTask(base,"START",{nowMs:clock+1000,leaseMs:1500});
  const failed=changePlanningTask(running,"RECOVER",{nowMs:clock+2500});
  assert.equal(failed.status,"FAILED");
  assert.equal(failed.failure,"MAX_ATTEMPTS");
  const expired=changePlanningTask(base,"RECOVER",{nowMs:clock+60000});
  assert.equal(expired.status,"EXPIRED");
  assert.equal(expired.failure,"DEADLINE");
});
test("bloqueia comandos remotos, farsa de conversa e timeout",()=>{
  const rep=report(),base=createPlanningTask(rep,{nowMs:clock});
  const running=changePlanningTask(base,"START",{nowMs:clock+1000,leaseMs:2000});
  assert.throws(()=>changePlanningTask(running,"FINISH",{nowMs:clock+3000,
    conversation:coordinateInvestigation(rep)}),/lease/);
  const fake=coordinateInvestigation(rep);
  fake.budgets.toolExecutions=1;
  assert.throws(()=>changePlanningTask(running,"FINISH",{nowMs:clock+1500,conversation:fake}),/offline/);
  assert.throws(()=>createPlanningTask({...rep,privacy:{rawRecordsIncluded:true}}, {nowMs:clock}),/seguro/);
  const changed={...base,remoteExecutionAllowed:true};
  assert.throws(()=>changePlanningTask(changed,"START",{nowMs:clock+1000}),/invalido/);
  assert.throws(()=>createPlanningTask(rep,{nowMs:clock,maxAttempts:100}),/Limites/);
});
test("tarefa sem nova missao pode encerrar sem acao de coletor",()=>{
  const rep=report();
  rep.mission=null;
  rep.unknowns=[];
  const task=createPlanningTask(rep,{nowMs:clock});
  const active=changePlanningTask(task,"START",{nowMs:clock+1});
  const convo=coordinateInvestigation(rep);
  const done=changePlanningTask(active,"FINISH",{nowMs:clock+1000,conversation:convo});
  assert.equal(done.status,"COMPLETED");
  assert.equal(done.decision,"WAITING_EVIDENCE");
});

test("rejeita injeção de campos e transição inventada no arquivo",async t=>{
  const folder=await mkdtemp(path.join(tmpdir(),"cafeina-forged-"));
  t.after(()=>rm(folder,{recursive:true,force:true}));
  const rep=report(),task=createPlanningTask(rep,{nowMs:clock});
  await savePlanningTask(folder,task);
  await assert.rejects(()=>savePlanningTask(folder,{
    ...task,revision:1,status:"WAITING_USER",
    conversationId:"conversation-"+"a".repeat(16),decision:"WAITING_USER"
  }),/CONFLICT/);
  await assert.rejects(()=>savePlanningTask(folder,{
    ...task,revision:1,username:"TEST_SECRET"
  }),/invalido/);
  const saved=await loadPlanningTask(folder,task.identity.gameId,task.taskId);
  assert.equal(saved.status,"CREATED");
});
