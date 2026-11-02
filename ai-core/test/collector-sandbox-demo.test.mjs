import test from "node:test";
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createOfflineCollectorSandbox} from "../src/collector-tool-sandbox.mjs";

test("synthetic tool demo emits minimal JSON with both passive tools",()=>{
  const result=spawnSync(process.execPath,[
    new URL("../src/collector-sandbox-demo.mjs",import.meta.url).pathname
  ],{encoding:"utf8",timeout:10000});
  assert.equal(result.status,0,result.stderr);
  const parsed=JSON.parse(result.stdout);
  assert.deepEqual(parsed.simulations.map(x=>x.toolId),
    ["watch_state","observe_gui"]);
  assert.equal(parsed.catalogSize,2);
  assert.equal(parsed.totalRealToolExecutions,0);
  assert.equal(parsed.robloxConnected,false);
  assert.equal(parsed.permissionsGrantedForLiveTools,false);
  for(const row of parsed.simulations){
    assert.equal(row.simulatedTrialsUsed,1);
    assert.equal(row.durationBudgetSeconds,10);
    assert.equal(row.realToolExecutions,0);
    assert.equal(row.activeRemoteCalls,0);
    assert.equal(row.executedInRoblox,false);
  }
  assert.ok(!result.stdout.includes("TEST_SECRET"));
  assert.ok(!result.stdout.includes("username"));
});

test("observe_gui remains metadata only and rejects unverified fixture",async()=>{
  const b=JSON.parse(readFileSync(
    new URL("fixtures/batch.json",import.meta.url),"utf8"));
  const m=JSON.parse(readFileSync(
    new URL("fixtures/latest.json",import.meta.url),"utf8"));
  const report=analyzeSession({
    batches:[{...b,records:b.records.filter(x=>x.kind!=="remote_outbound")}],
    manifest:m
  });
  const now=1700000000000,proposal=createMenuProposal(report,{nowMs:now});
  assert.equal(proposal.toolId,"observe_gui");
  const sandbox=createOfflineCollectorSandbox({
    proposal,report,nowMs:()=>now+1000,
    verifyTestFixture:async ticket=>ticket==="FOR_TESTS_ONLY"?
      {verified:true,mode:"SYNTHETIC_TEST_ONLY",
        missionId:proposal.missionId,identity:{...proposal.identity}}:
      {verified:false,mode:"SYNTHETIC_TEST_ONLY",
        missionId:proposal.missionId,identity:{...proposal.identity}}
  });
  await assert.rejects(()=>sandbox.simulate({
    requestId:"trial-"+"a".repeat(16),ticket:"NO_APPROVAL"
  }),/autorizacao/);
  assert.equal(sandbox.snapshot().trialCount,0);
  const preview=await sandbox.simulate({
    requestId:"trial-"+"a".repeat(16),ticket:"FOR_TESTS_ONLY"
  });
  assert.equal(preview.toolId,"observe_gui");
  assert.equal(preview.observationKind,"gui_state");
  assert.equal(preview.observedRecordCountCapped,1);
  assert.equal(preview.executedInRoblox,false);
  assert.ok(!JSON.stringify(preview).includes("TEST_SECRET"));
});
