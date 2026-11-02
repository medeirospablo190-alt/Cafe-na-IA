#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {createMenuProposal} from "./menu-proposal.mjs";
import {createOfflineCollectorSandbox} from "./collector-tool-sandbox.mjs";
import {
  createCollectorPermissionRequest,reviewCollectorPermission,
  createSyntheticReviewFixtureVerifier,summarizeCollectorPermissionAudit
} from "./collector-permissions.mjs";

const load=n=>JSON.parse(readFileSync(new URL("../test/fixtures/"+n,import.meta.url),"utf8"));
const t=1700000000000;
const rawBatch=load("batch.json"),manifest=load("latest.json");
const results=[];
for(const toolId of ["watch_state","observe_gui"]){
  const batch=toolId==="watch_state"?rawBatch:
    {...rawBatch,records:rawBatch.records.filter(r=>r.kind!=="remote_outbound")};
  const report=analyzeSession({batches:[batch],manifest});
  const proposal=createMenuProposal(report,{nowMs:t});
  if(proposal.toolId!==toolId)throw new Error("Tool mismatch.");
  const request=createCollectorPermissionRequest(proposal,{nowMs:t+1000,ttlMs:60000});
  const reviewer=async credential=>credential==="SYNTHETIC_OPERATOR_FIXTURE_ONLY"?{
    verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
    requestId:request.requestId,missionId:request.missionId,
    identity:{...request.identity}
  }:null;
  const decision=outcome=>reviewCollectorPermission(request,proposal,{
    outcome,operatorEvidence:"SYNTHETIC_OPERATOR_FIXTURE_ONLY",
    verifyTestOperator:reviewer,nowMs:t+2000
  });
  const approved=await decision("SIMULATION_ALLOWED");
  const denied=await decision("DENIED");
  const testGate=review=>createSyntheticReviewFixtureVerifier({
    request,proposal,review,nowMs:()=>t+3000,
    verifyTrustedReview:async query=>({
      verified:true,mode:"SYNTHETIC_TEST_REVIEW_REGISTRY",
      requestId:query.requestId,reviewId:query.reviewId,
      missionId:query.missionId,scope:query.scope
    })
  });
  if(await testGate(denied)(denied)!==null)throw new Error("Denied preview accepted.");
  const sandbox=createOfflineCollectorSandbox({
    proposal,report,verifyTestFixture:testGate(approved),nowMs:()=>t+3000
  });
  const result=await sandbox.simulate({
    requestId:"trial-"+"a".repeat(16),ticket:approved
  });
  const audit=summarizeCollectorPermissionAudit(request,approved,proposal);
  if(result.executedInRoblox!==false||result.realToolExecutions!==0||
    audit.approvedForLiveTools!==false||sandbox.snapshot().robloxConnected!==false){
    throw new Error("Review escalated privileges.");
  }
  try{
    sandbox.dispatchLiveTool();
    throw new Error("Unsafe live dispatch was possible.");
  }catch(error){
    if(error.message!=="LIVE_COLLECTOR_EXECUTION_DISABLED")throw error;
  }
  results.push({
    toolId,requestStatus:request.status,acceptedOutcome:approved.outcome,
    deniedOutcome:denied.outcome,scope:audit.scope,
    simulatedTrials:1,simulatedDurationSeconds:10,
    permissionsGrantedForLiveTools:false,robloxConnected:false,
    realToolExecutions:0,activeRemoteCalls:0
  });
}
const output={
  schemaVersion:1,type:"cafeina_collector_permission_synthetic_smoke",
  mode:"TEST_ONLY_NO_USER_AUTHORIZATION",requests:results,
  liveExecutionEnabled:false,approvedForRealCollector:false,storedPlayerData:false
};
const json=JSON.stringify(output);
if(/TEST_SECRET|username|userId|password|remoteArguments|rawRecords/i.test(json)){
  throw new Error("Sensitive data in synthetic demo.");
}
process.stdout.write(json+"\n");
