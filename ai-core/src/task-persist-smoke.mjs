#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {createPlanningTask} from "./task-engine.mjs";
import {readGithubPlanningTask,syncGithubPlanningTask} from "./github-task.mjs";

const mode=process.argv[2];
if(!["publish","read"].includes(mode))throw new Error("Modo invalido.");
const run=process.env.GITHUB_RUN_ID,repo=process.env.GITHUB_REPOSITORY;
if(typeof run!=="string"||!/^[0-9]{6,16}$/.test(run)){
  throw new Error("Execucao GitHub invalida.");
}
const f=name=>JSON.parse(readFileSync(new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
const runId="synthetic-"+run;
const report=analyzeSession({
  batches:[{...f("batch.json"),runId}],
  manifest:{...f("latest.json"),runId}
});
const task=createPlanningTask(report,{nowMs:1700000000000,ttlMs:86400000});
if(task.executionScope!=="OFFLINE_METADATA_ONLY"||
   task.remoteExecutionAllowed!==false)throw new Error("Tarefa nao segura.");
const args={repository:repo,token:process.env.GITHUB_TOKEN??""};
const result=mode==="publish"
  ?await syncGithubPlanningTask({...args,task,dryRun:false})
  :await readGithubPlanningTask({
    ...args,gameId:task.identity.gameId,taskId:task.taskId
  });
if(mode==="publish"&&!["SAVED","UNCHANGED"].includes(result.status)){
  throw new Error("Tarefa nao publicada.");
}
if(mode==="read"&&(result.status!=="FOUND"||result.task.revision!==0||
  result.task.taskId!==task.taskId||
  result.task.remoteExecutionAllowed!==false||
  result.task.executionScope!=="OFFLINE_METADATA_ONLY")){
  throw new Error("Tarefa nao recuperada em outro runner.");
}
// Only synthetic IDs and summary; no raw evidence or token.
process.stdout.write(JSON.stringify({
  mode,status:result.status,taskId:task.taskId,
  syntheticDataOnly:true,remoteExecutionAllowed:false,verified:true
})+"\n");
