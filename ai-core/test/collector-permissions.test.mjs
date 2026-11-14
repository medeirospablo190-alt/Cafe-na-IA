import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createOfflineCollectorSandbox} from "../src/collector-tool-sandbox.mjs";
import {
 createCollectorPermissionRequest,validateCollectorPermissionRequest,
 reviewCollectorPermission,validateCollectorPermissionReview,
 summarizeCollectorPermissionAudit
} from "../src/collector-permissions.mjs";

const load=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const start=1700000000000;
const report=()=>analyzeSession({batches:[load("batch.json")],manifest:load("latest.json")});
const getProposal=()=>createMenuProposal(report(),{nowMs:start});
const trustedProof=(request)=>{
 return async(data)=>{
   if(data!=="TEST_OPERATOR_APPROVED")return null;
   return {verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
     requestId:request.requestId,missionId:request.missionId,
     identity:{...request.identity}};
 };
};
const review=(r,p,outcome,operatorEvidence="TEST_OPERATOR_APPROVED")=>
  reviewCollectorPermission(r,p,{
    outcome,operatorEvidence,verifyTestOperator:trustedProof(r),nowMs:start+2000
  });

test("permission request is bounded, deterministic and cannot execute",()=>{
  const proposal=getProposal();
  const a=createCollectorPermissionRequest(proposal,{nowMs:start+1000});
  const b=createCollectorPermissionRequest(proposal,{nowMs:start+1000});
  assert.deepEqual(a,b);
  assert.equal(validateCollectorPermissionRequest(a,proposal),a);
  assert.equal(a.status,"PENDING_REVIEW");
  assert.equal(a.scope,"SYNTHETIC_PREVIEW_ONLY");
  assert.equal(a.liveExecutionRequested,false);
  assert.equal(a.maxTrials,2);
  assert.equal(a.durationSeconds,10);
  assert.equal(a.reasonCode,"INSPECT_OBSERVED_REMOTE_METADATA");
  assert.ok(!JSON.stringify(a).includes("TEST_SECRET"));
});
test("explicit offline review can approve simulation only and emits sanitized audit",async()=>{
  const p=getProposal(),r=createCollectorPermissionRequest(p,{nowMs:start+1000});
  const decision=await review(r,p,"SIMULATION_ALLOWED");
  assert.equal(validateCollectorPermissionReview(decision,r,p),decision);
  assert.equal(decision.authorizedLiveExecution,false);
  assert.equal(decision.robloxConnected,false);
  assert.equal(decision.scope,"SYNTHETIC_PREVIEW_ONLY");
  const audit=summarizeCollectorPermissionAudit(r,decision,p);
  assert.equal(audit.approvedForLiveTools,false);
  assert.equal(audit.realToolExecutions,0);
  assert.ok(!JSON.stringify(audit).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(audit).includes("username"));
  const denied=await review(r,p,"DENIED");
  assert.equal(denied.outcome,"DENIED");
  assert.notEqual(denied.reviewId,decision.reviewId);
});
test("ACK does not approve, forged operator denied, unknown outcomes denied",async()=>{
  const p=getProposal(),r=createCollectorPermissionRequest(p,{nowMs:start+1000});
  const ack=menuReceipt(p,"RECEIVED");
  await assert.rejects(()=>review(r,p,"SIMULATION_ALLOWED",ack),/nao autenticado/);
  await assert.rejects(()=>reviewCollectorPermission(r,p,{
    outcome:"EXECUTE_LUA",operatorEvidence:"TEST_OPERATOR_APPROVED",
    verifyTestOperator:trustedProof(r),nowMs:start+2000
  }),/nao permitida/);
  await assert.rejects(()=>reviewCollectorPermission(r,p,{
    outcome:"SIMULATION_ALLOWED",operatorEvidence:"TEST_OPERATOR_APPROVED",
    verifyTestOperator:async()=>({verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
      requestId:r.requestId,missionId:r.missionId,
      identity:{...r.identity,gameId:"404"}}),nowMs:start+2000
  }),/nao autenticado/);
});
test("rejects wrong mission, extra permissions, late review and tampering",async()=>{
  const p=getProposal(),r=createCollectorPermissionRequest(p,{nowMs:start+1000});
  const reviewRecord=await review(r,p,"SIMULATION_ALLOWED");
  for(const changed of [
    {...r,scope:"LIVE_COLLECTOR"},
    {...r,liveExecutionRequested:true},
    {...r,identity:{...r.identity,placeId:"999"}},
    {...r,maxTrials:99},
    {...r,extra:"TEST_SECRET"}
  ])assert.throws(()=>validateCollectorPermissionRequest(changed,p),/contrato/);
  for(const changed of [
    {...reviewRecord,authorizedLiveExecution:true},
    {...reviewRecord,identity:{...r.identity,gameId:"999"}},
    {...reviewRecord,requestSha256:"f".repeat(64)},
    {...reviewRecord,outcome:"EXECUTE_LUA"},
    {...reviewRecord,actor:"somebody"}
  ])assert.throws(()=>validateCollectorPermissionReview(changed,r,p),/contrato/);
  await assert.rejects(()=>reviewCollectorPermission(r,p,{
    outcome:"SIMULATION_ALLOWED",operatorEvidence:"TEST_OPERATOR_APPROVED",
    verifyTestOperator:trustedProof(r),nowMs:r.expiresAtMs
  }),/vencida/);
});
test("simulation reviewer never unlocks live dispatch; gated fixture only",async()=>{
  const p=getProposal(),r=createCollectorPermissionRequest(p,{nowMs:start+1000});
  const decision=await review(r,p,"SIMULATION_ALLOWED");
  const sim=createOfflineCollectorSandbox({
    proposal:p,report:report(),nowMs:()=>start+3000,
    verifyTestFixture:async incoming=>{
      if(incoming?.reviewId!==decision.reviewId)return null;
      validateCollectorPermissionReview(decision,r,p);
      return {verified:true,mode:"SYNTHETIC_TEST_ONLY",
        missionId:p.missionId,identity:{...p.identity}};
    }
  });
  const output=await sim.simulate({
    requestId:"trial-"+"a".repeat(16),ticket:decision
  });
  assert.equal(output.executedInRoblox,false);
  assert.equal(output.approvedForRealExecution,false);
  assert.throws(()=>sim.dispatchLiveTool(),/DISABLED/);
  await assert.rejects(()=>sim.simulate({
    requestId:"trial-"+"b".repeat(16),
    ticket:{...decision,reviewId:"review-"+"f".repeat(16)}
  }),/autorizacao/);
});
