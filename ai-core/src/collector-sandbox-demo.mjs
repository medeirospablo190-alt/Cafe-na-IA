#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {createMenuProposal} from "./menu-proposal.mjs";
import {createOfflineCollectorSandbox,collectorToolCatalog} from "./collector-tool-sandbox.mjs";

const load=name=>JSON.parse(readFileSync(
  new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
const time=1700000000000;
const batch=load("batch.json"),manifest=load("latest.json");
const summaries=[];
for(const toolId of ["watch_state","observe_gui"]){
  const source=toolId==="observe_gui"
    ?{...batch,records:batch.records.filter(r=>r.kind!=="remote_outbound")}
    :batch;
  const report=analyzeSession({batches:[source],manifest});
  const proposal=createMenuProposal(report,{nowMs:time});
  if(proposal.toolId!==toolId){
    throw new Error("A fixture nao gerou a ferramenta prevista.");
  }
  const sandbox=createOfflineCollectorSandbox({
    proposal,report,nowMs:()=>time+1000,
    verifyTestFixture:async ticket=>ticket==="SYNTHETIC_ONLY"?
      {verified:true,mode:"SYNTHETIC_TEST_ONLY",
        missionId:proposal.missionId,identity:{...proposal.identity}}:null
  });
  const result=await sandbox.simulate({
    requestId:"trial-"+"a".repeat(16),ticket:"SYNTHETIC_ONLY"
  });
  const audit=sandbox.snapshot();
  if(result.executedInRoblox!==false||
    result.realToolExecutions!==0||
    result.approvedForRealExecution!==false||
    audit.realToolExecutions!==0||
    audit.trialCount!==1||
    audit.robloxConnected!==false){
    throw new Error("Sandbox ultrapassou fronteira de seguranca.");
  }
  summaries.push({
    toolId,kind:result.observationKind,
    metadataCount:result.observedRecordCountCapped,
    safeEvidenceRefs:result.evidenceRefs.length,
    simulatedTrialsUsed:result.simulatedTrialsUsed,
    durationBudgetSeconds:result.durationBudgetSeconds,
    approvedForRealExecution:false,executedInRoblox:false,
    realToolExecutions:0,activeRemoteCalls:0
  });
}
const output={
  schemaVersion:1,type:"cafeina_collector_tool_synthetic_smoke",
  source:"SYNTHETIC_V3_FIXTURES_ONLY",
  mode:"OFFLINE_SIMULATION_ONLY",
  catalogSize:collectorToolCatalog().length,
  simulations:summaries,
  totalRealToolExecutions:0,robloxConnected:false,
  permissionsGrantedForLiveTools:false
};
const json=JSON.stringify(output);
if(/TEST_SECRET|username|userId|password|remoteArguments|rawRecords/i.test(json)){
  throw new Error("Dado proibido em resultado sintetico.");
}
process.stdout.write(json+"\n");
