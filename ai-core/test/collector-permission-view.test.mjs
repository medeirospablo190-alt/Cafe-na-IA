import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {
  createCollectorPermissionRequest,reviewCollectorPermission
} from "../src/collector-permissions.mjs";
import {
  createCollectorPermissionEnvelope,applyCollectorPermissionReview
} from "../src/github-collector-permissions.mjs";
import {buildSyntheticCollectorPermissionView} from "../src/collector-permission-view.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const t=1700000000000;
const make=()=>{
  const r=analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
  const p=createMenuProposal(r,{nowMs:t});
  const req=createCollectorPermissionRequest(p,{nowMs:t+1000,ttlMs:60000});
  return {p,req,record:createCollectorPermissionEnvelope(req,p)};
};
async function decide(p,req,record,outcome){
  const review=await reviewCollectorPermission(req,p,{
    outcome,nowMs:t+2000,operatorEvidence:"FIXTURE",
    verifyTestOperator:async()=>({
      verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
      requestId:req.requestId,missionId:req.missionId,
      identity:{...req.identity}
    })
  });
  return applyCollectorPermissionReview(record,review,p).record;
}
test("pending view lists only offline test options and zero live permissions",()=>{
  const {p,record}=make();
  const view=buildSyntheticCollectorPermissionView(record,p,{nowMs:t+3000});
  assert.equal(view.status,"PENDING_REVIEW");
  assert.deepEqual(view.choices.map(c=>c.code),["DENIED","SIMULATION_ALLOWED"]);
  assert.equal(view.canExecuteRobloxTools,false);
  assert.equal(view.canSendRemoteCommands,false);
  assert.equal(view.realApprovalAvailable,false);
  assert.equal(view.realUserIdentityVerified,false);
  assert.equal(view.displayOnly,true);
  assert.ok(!JSON.stringify(view).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(view).includes("username"));
});
test("expired, denied and simulated-allow views expose no actionable controls",async()=>{
  const {p,req,record}=make();
  const expired=buildSyntheticCollectorPermissionView(record,p,{
    nowMs:req.expiresAtMs
  });
  assert.equal(expired.status,"EXPIRED");
  assert.deepEqual(expired.choices,[]);
  const denied=buildSyntheticCollectorPermissionView(
    await decide(p,req,record,"DENIED"),p,{nowMs:t+3000});
  assert.equal(denied.status,"DENIED");
  assert.deepEqual(denied.choices,[]);
  const sim=buildSyntheticCollectorPermissionView(
    await decide(p,req,record,"SIMULATION_ALLOWED"),p,{nowMs:t+3000});
  assert.equal(sim.status,"TEST_SIMULATION_ALLOWED");
  assert.deepEqual(sim.choices,[]);
  assert.equal(sim.canExecuteRobloxTools,false);
});
test("untrusted payload cannot be presented as real permission",()=>{
  const {p,record}=make();
  assert.throws(()=>buildSyntheticCollectorPermissionView({
    ...record,extra:"X"
  },p,{nowMs:t+3000}),/invalido/);
  assert.throws(()=>buildSyntheticCollectorPermissionView({
    ...record,review:{outcome:"LIVE_EXECUTE"},revision:1,status:"REVIEWED"
  },p,{nowMs:t+3000}));
});
