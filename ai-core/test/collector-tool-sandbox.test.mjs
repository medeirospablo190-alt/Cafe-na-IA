import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {
  collectorToolCatalog,validateCollectorSandboxSource,
  createOfflineCollectorSandbox
} from "../src/collector-tool-sandbox.mjs";

const load=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const analyze=()=>analyzeSession({batches:[load("batch.json")],manifest:load("latest.json")});
const now=1700000000000;
const trialA="trial-"+"a".repeat(16),trialB="trial-"+"b".repeat(16);
function fixture(){
  const report=analyze(),proposal=createMenuProposal(report,{nowMs:now});
  const verifyTestFixture=async ticket=>{
    if(ticket!=="SYNTHETIC_FIXTURE_GRANTED")return null;
    return {verified:true,mode:"SYNTHETIC_TEST_ONLY",
      missionId:proposal.missionId,identity:{...proposal.identity}};
  };
  return {
    report,proposal,tool:createOfflineCollectorSandbox({
      proposal,report,verifyTestFixture,nowMs:()=>now+1000
    })
  };
}
test("catalog lists only passive, bounded metadata previews",()=>{
  assert.deepEqual(collectorToolCatalog().map(t=>t.toolId),["watch_state","observe_gui"]);
  for(const tool of collectorToolCatalog()){
    assert.equal(tool.privilege,"OFFLINE_METADATA_ONLY");
    assert.equal(tool.durationSeconds,10);
    assert.equal(tool.allowsActiveRemoteCalls,false);
    assert.equal(tool.maxEvidenceRefs,3);
  }
});
test("two synthetic calls, replay idempotent, budget enforced, no player data",async()=>{
  const {tool}=fixture();
  const a=await tool.simulate({requestId:trialA,ticket:"SYNTHETIC_FIXTURE_GRANTED"});
  assert.equal(a.mode,"SYNTHETIC_METADATA_PREVIEW");
  assert.equal(a.toolId,"watch_state");
  assert.equal(a.observationKind,"remote_outbound");
  assert.equal(a.observedRecordCountCapped,1);
  assert.equal(a.executedInRoblox,false);
  assert.equal(a.approvedForRealExecution,false);
  assert.equal(a.realToolExecutions,0);
  assert.equal(a.activeRemoteCalls,0);
  assert.ok(a.evidenceRefs.every(ref=>ref.startsWith("v3:101:202:demo-run-0001:")));
  assert.ok(!JSON.stringify(a).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(a).includes("username"));
  const again=await tool.simulate({requestId:trialA,ticket:"SYNTHETIC_FIXTURE_GRANTED"});
  assert.deepEqual(again,a);
  const b=await tool.simulate({requestId:trialB,ticket:"SYNTHETIC_FIXTURE_GRANTED"});
  assert.equal(b.simulatedTrialsUsed,2);
  await assert.rejects(()=>tool.simulate({
    requestId:"trial-"+"c".repeat(16),ticket:"SYNTHETIC_FIXTURE_GRANTED"
  }),/esgotado/);
  const snapshot=tool.snapshot();
  assert.equal(snapshot.trialCount,2);
  assert.equal(snapshot.simulatedDurationSeconds,20);
  assert.equal(snapshot.realToolExecutions,0);
  assert.equal(snapshot.robloxConnected,false);
  assert.deepEqual(snapshot.events.map(x=>x.kind),[
    "SYNTHETIC_PREVIEW","SYNTHETIC_PREVIEW"
  ]);
  assert.throws(()=>tool.dispatchLiveTool(),/DISABLED/);
});
test("fake approval, invalid tool, cross-game, raw data and malformed trials fail",async()=>{
  const {tool,proposal,report}=fixture();
  await assert.rejects(()=>tool.simulate({requestId:trialA,ticket:"forged"}),/autorizacao/);
  assert.equal(tool.snapshot().trialCount,0);
  await assert.rejects(()=>tool.simulate({
    requestId:"../unsafe",ticket:"SYNTHETIC_FIXTURE_GRANTED"
  }),/invalida/);
  assert.throws(()=>validateCollectorSandboxSource({
    ...proposal,toolId:"execute_lua"
  },report),/contrato/);
  assert.throws(()=>validateCollectorSandboxSource(proposal,{
    ...report,identity:{...report.identity,gameId:"404"}
  }),/saneada/);
  assert.throws(()=>validateCollectorSandboxSource(proposal,{
    ...report,privacy:{...report.privacy,rawRecordsIncluded:true}
  }),/saneada/);
  assert.throws(()=>validateCollectorSandboxSource(proposal,{
    ...report,observations:{...report.observations,
      evidenceRefs:{remote_outbound:["v3:101:202:demo-run-0001:1:999"]}}
  }),/correspondem/);
});
test("cannot produce a synthetic result after proposal expiry",async()=>{
  const {proposal,report}=fixture();
  const tool=createOfflineCollectorSandbox({
    proposal,report,nowMs:()=>now+600000,
    verifyTestFixture:async()=>({verified:true,mode:"SYNTHETIC_TEST_ONLY",
      missionId:proposal.missionId,identity:{...proposal.identity}})
  });
  await assert.rejects(()=>tool.simulate({
    requestId:trialA,ticket:"x"
  }),/expirada/);
});
test("fixture verifier concurrency is serialized; no accidental double spend",async()=>{
  const report=analyze(),proposal=createMenuProposal(report,{nowMs:now});
  let release;
  const block=new Promise(resolve=>{release=resolve;});
  let first=true;
  const sandbox=createOfflineCollectorSandbox({
    proposal,report,nowMs:()=>now+1000,
    verifyTestFixture:async()=>{
      if(first){first=false;await block;}
      return {verified:true,mode:"SYNTHETIC_TEST_ONLY",
        missionId:proposal.missionId,identity:{...proposal.identity}};
    }
  });
  const pending=sandbox.simulate({requestId:trialA,ticket:"fixture"});
  await assert.rejects(()=>sandbox.simulate({requestId:trialB,ticket:"fixture"}),/BUSY/);
  release();
  await pending;
  assert.equal(sandbox.snapshot().trialCount,1);
});
