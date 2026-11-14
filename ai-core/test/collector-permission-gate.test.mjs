import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createOfflineCollectorSandbox} from "../src/collector-tool-sandbox.mjs";
import {createCollectorPermissionRequest,reviewCollectorPermission,
  createSyntheticReviewFixtureVerifier} from "../src/collector-permissions.mjs";
const read=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const now=1700000000000,clock=()=>now+3000;
const fixture=async(outcome="SIMULATION_ALLOWED")=>{
  const report=analyzeSession({batches:[read("batch.json")],manifest:read("latest.json")});
  const proposal=createMenuProposal(report,{nowMs:now});
  const request=createCollectorPermissionRequest(proposal,{nowMs:now+1000,ttlMs:60000});
  const review=await reviewCollectorPermission(request,proposal,{
    outcome,operatorEvidence:"FIXTURE_PROOF",
    verifyTestOperator:async proof=>proof==="FIXTURE_PROOF"?{
      verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
      requestId:request.requestId,missionId:request.missionId,identity:{...request.identity}
    }:null,
    nowMs:now+2000
  });
  const registry=async info=>({
    verified:true,mode:"SYNTHETIC_TEST_REVIEW_REGISTRY",
    requestId:info.requestId,reviewId:info.reviewId,
    missionId:info.missionId,scope:info.scope
  });
  return {report,proposal,request,review,registry};
};
test("simulated review requires an independently checked registry every time",async()=>{
  const {report,proposal,request,review,registry}=await fixture();
  let calls=0;
  const checker=createSyntheticReviewFixtureVerifier({
    request,proposal,review,nowMs:clock,
    verifyTrustedReview:async info=>{calls++;return registry(info);}
  });
  const sandbox=createOfflineCollectorSandbox({
    proposal,report,verifyTestFixture:checker,nowMs:clock
  });
  const output=await sandbox.simulate({requestId:"trial-"+"a".repeat(16),ticket:review});
  assert.equal(output.executedInRoblox,false);
  assert.equal(output.realToolExecutions,0);
  assert.equal(calls,1);
  await sandbox.simulate({requestId:"trial-"+"a".repeat(16),ticket:review});
  assert.equal(calls,2);
  assert.equal(sandbox.snapshot().trialCount,1);
  assert.throws(()=>sandbox.dispatchLiveTool(),/DISABLED/);
});
test("denial, expiry and invalid copied JSON cannot unlock the test sandbox",async()=>{
  const {proposal,request,review,registry}=await fixture("DENIED");
  const denied=createSyntheticReviewFixtureVerifier({
    proposal,request,review,verifyTrustedReview:registry,nowMs:clock
  });
  assert.equal(await denied(review),null);
  const approved=await fixture();
  const expired=createSyntheticReviewFixtureVerifier({
    proposal:approved.proposal,request:approved.request,
    review:approved.review,verifyTrustedReview:approved.registry,
    nowMs:()=>approved.request.expiresAtMs
  });
  assert.equal(await expired(approved.review),null);
  const active=createSyntheticReviewFixtureVerifier({
    proposal:approved.proposal,request:approved.request,
    review:approved.review,verifyTrustedReview:approved.registry,nowMs:clock
  });
  assert.equal(await active({...approved.review,authorizedLiveExecution:true}),null);
  assert.equal(await active({...approved.review,reviewId:"review-"+"f".repeat(16)}),null);
  assert.equal(await active(null),null);
  const noRegistry=createSyntheticReviewFixtureVerifier({
    proposal:approved.proposal,request:approved.request,
    review:approved.review,verifyTrustedReview:async()=>null,nowMs:clock
  });
  assert.equal(await noRegistry(approved.review),null);
});
