import test from "node:test";
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";

test("request-review-preview-audit synthetic demo never executes real tools",()=>{
  const cmd=new URL("../src/collector-permissions-demo.mjs",import.meta.url);
  const r=spawnSync(process.execPath,[cmd.pathname],{
    encoding:"utf8",timeout:10000
  });
  assert.equal(r.status,0,r.stderr);
  const out=JSON.parse(r.stdout);
  assert.equal(out.mode,"TEST_ONLY_NO_USER_AUTHORIZATION");
  assert.deepEqual(out.requests.map(x=>x.toolId),["watch_state","observe_gui"]);
  assert.equal(out.approvedForRealCollector,false);
  assert.equal(out.liveExecutionEnabled,false);
  assert.equal(out.storedPlayerData,false);
  for(const item of out.requests){
    assert.equal(item.requestStatus,"PENDING_REVIEW");
    assert.equal(item.acceptedOutcome,"SIMULATION_ALLOWED");
    assert.equal(item.deniedOutcome,"DENIED");
    assert.equal(item.simulatedTrials,1);
    assert.equal(item.simulatedDurationSeconds,10);
    assert.equal(item.permissionsGrantedForLiveTools,false);
    assert.equal(item.realToolExecutions,0);
    assert.equal(item.activeRemoteCalls,0);
  }
  assert.ok(!r.stdout.includes("TEST_SECRET"));
  assert.ok(!r.stdout.includes("username"));
});
