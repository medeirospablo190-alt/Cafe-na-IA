#!/usr/bin/env node
import {readFile,writeFile,mkdir} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {coordinateInvestigation} from "./agents.mjs";
import {createPlanningTask,savePlanningTask,loadPlanningTask,changePlanningTask} from "./task-engine.mjs";
import {draftSpecialistPlan} from "./specialists.mjs";
import {prepareReaHandoff} from "./rea-adapter.mjs";

export async function runPlanningDemo(reportPath,outDir,{nowMs=1700000000000}={}){
  const report=JSON.parse(await readFile(reportPath,"utf8"));
  const task=createPlanningTask(report,{nowMs,ttlMs:60000,maxAttempts:2,stepLimit:4});
  const store=path.join(outDir,"tasks");
  const first=await savePlanningTask(store,task);
  if(first.status!=="SAVED")throw new Error("Tarefa inicial nao salva.");
  const restored=await loadPlanningTask(store,task.identity.gameId,task.taskId);
  const running=changePlanningTask(restored,"START",{nowMs:nowMs+100,leaseMs:20000});
  await savePlanningTask(store,running,{expectedRevision:restored.revision});
  const conversation=coordinateInvestigation(report);
  const result=changePlanningTask(running,"FINISH",{nowMs:nowMs+200,conversation});
  await savePlanningTask(store,result,{expectedRevision:running.revision});
  const after=await loadPlanningTask(store,task.identity.gameId,task.taskId);
  const spec=draftSpecialistPlan(report,after);
  const rea=prepareReaHandoff(report);
  const specsDir=path.join(outDir,"plans");
  await mkdir(specsDir,{recursive:true,mode:0o700});
  const file=path.join(specsDir,spec.planId+".json");
  await writeFile(file,JSON.stringify(spec,null,2)+"\n",{flag:"wx",mode:0o600});
  const reaFile=path.join(specsDir,rea.handoffId+".json");
  await writeFile(reaFile,JSON.stringify(rea,null,2)+"\n",{flag:"wx",mode:0o600});
  return {
    taskId:task.taskId,taskState:after.status,attempt:after.attempt,
    recoveredFromDisk:true,gameId:after.identity.gameId,
    specialists:spec.specialists.map(x=>x.role),codeGenerated:spec.codeGenerated,
    toolExecutions:spec.toolExecutions,testsExecuted:spec.testsExecuted,
    planStatus:spec.specialists[1].status,
    source:"SANITIZED_SESSION_REPORT",
    reaHandoffPrepared:true,
    reaEvidenceAuthenticated:false,
    reaQuestions:rea.pendingQuestions.length,
    verifiedReconstructionClaims:0
  };
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  if(process.argv.length!==4){
    process.stderr.write("Uso: node src/planning-demo.mjs <safe-report.json> <private-out-dir>\n");
    process.exitCode=1;
  }else{
    runPlanningDemo(path.resolve(process.argv[2]),path.resolve(process.argv[3]))
      .then(x=>process.stdout.write(JSON.stringify(x)+"\n"))
      .catch(e=>{
        process.stderr.write("CAFEINA_PLANNING_ERROR: "+e.message+"\n");
        process.exitCode=1;
      });
  }
}
