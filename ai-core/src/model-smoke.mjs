#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {coordinateWithLocalModel} from "./agents.mjs";

const selectedModel=process.env.CAFEINA_MODEL ?? "qwen2.5:0.5b";
const readFixture=name=>JSON.parse(readFileSync(
  new URL("../test/fixtures/"+name,import.meta.url),"utf8"
));
const report=analyzeSession({
  batches:[readFixture("batch.json")],
  manifest:readFixture("latest.json")
});
try {
  const result=await coordinateWithLocalModel(report,{
    model:selectedModel,
    timeoutMs:60000
  });
  if(result.budgets.modelCalls!==1 ||
     result.budgets.toolExecutions!==0 ||
     result.mode!=="MODEL_ASSISTED_REHEARSAL" ||
     result.proposedMission?.executable!==false ||
     result.modelAdvice?.executable!==false ||
     result.modelAdvice?.verification!=="EXPERIMENTAL"){
    throw new Error("Resultado nao respeitou a politica de seguranca.");
  }
  // No raw response or prompt is printed or persisted to GitHub.
  process.stdout.write(JSON.stringify({
    probe:"CAFEINA_LOCAL_MODEL",
    model:selectedModel,
    result:"PASS",
    mode:result.mode,
    requestedRole:result.modelAdvice.role,
    acceptedRecommendation:result.modelAdvice.recommendation,
    modelCalls:result.budgets.modelCalls,
    toolExecutions:result.budgets.toolExecutions,
    executionPermitted:false,
    syntheticDataOnly:true
  })+"\n");
} catch(e){
  process.stderr.write("CAFEINA_MODEL_SMOKE_FAILED: "+String(e.message||e)+"\n");
  process.exitCode=1;
}
