import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";
const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const time=1700000000000;
const token="local-simulator-session-credential";
function headers(auth=true){
  return {"Content-Type":"application/json",...(auth?{"Authorization":"Bearer "+token}:{})};
}

test("local HTTP gateway simulated menu poll -> ack -> non-execution result",async t=>{
  const proposal=createMenuProposal(report(),{nowMs:time});
  const gateway=createMenuGatewaySimulator({proposal,token,nowMs:()=>time+1000});
  t.after(()=>gateway.close());
  const origin=await gateway.start();
  const endpoint=origin+"/v1/mission/101/202/demo-run-0001";
  const unauth=await fetch(endpoint);
  assert.equal(unauth.status,401);
  const first=await fetch(endpoint,{headers:headers()});
  const received=await first.json();
  assert.equal(received.hasProposal,true);
  assert.equal(received.proposal.approved,false);
  assert.equal(received.proposal.executable,false);
  assert.equal(received.status,"DELIVERED");
  const repeat=await (await fetch(endpoint,{headers:headers()})).json();
  assert.equal(repeat.proposal.missionId,proposal.missionId);
  assert.equal(gateway.snapshot().polls,2);

  const post=(route,kind)=>fetch(origin+route,{
    method:"POST",headers:headers(),
    body:JSON.stringify(menuReceipt(proposal,kind))
  });
  const before=await post("/v1/mission/report","NOT_EXECUTED");
  assert.equal(before.status,409);
  const ack=await (await post("/v1/mission/ack","RECEIVED")).json();
  assert.equal(ack.status,"ACKNOWLEDGED");
  assert.equal(ack.executed,false);
  assert.equal((await post("/v1/mission/ack","RECEIVED")).status,200);
  const result=await (await post("/v1/mission/report","NOT_EXECUTED")).json();
  assert.equal(result.status,"CLOSED_NO_EXECUTION");
  assert.equal(result.approved,false);
  assert.equal(result.executed,false);
  const dupe=await (await post("/v1/mission/report","NOT_EXECUTED")).json();
  assert.equal(dupe.duplicate,true);
  const final=await (await fetch(endpoint,{headers:headers()})).json();
  assert.equal(final.hasProposal,false);
  assert.equal(gateway.snapshot().reported,"NOT_EXECUTED");
});

test("rejects cross-session acknowledgments and non-allowed result kinds",async t=>{
  const proposal=createMenuProposal(report(),{nowMs:time});
  const gateway=createMenuGatewaySimulator({proposal,token,nowMs:()=>time+1000});
  t.after(()=>gateway.close());
  const origin=await gateway.start();
  const wrong=menuReceipt(proposal,"RECEIVED");
  wrong.identity.placeId="999";
  const cross=await fetch(origin+"/v1/mission/ack",{
    method:"POST",headers:headers(),body:JSON.stringify(wrong)
  });
  assert.equal(cross.status,400);
  const wrongPath=await fetch(origin+"/v1/mission/101/404/demo-run-0001",{headers:headers()});
  assert.equal(wrongPath.status,404);
  const received=await fetch(origin+"/v1/mission/ack",{
    method:"POST",headers:headers(),body:JSON.stringify(menuReceipt(proposal,"RECEIVED"))
  });
  assert.equal(received.status,200);
  const denied=await fetch(origin+"/v1/mission/report",{
    method:"POST",headers:headers(),
    body:JSON.stringify(menuReceipt(proposal,"RECEIVED"))
  });
  assert.equal(denied.status,422);
  assert.equal(gateway.snapshot().executed,false);
});
test("expired proposals cannot be delivered or acknowledged",async t=>{
  const proposal=createMenuProposal(report(),{nowMs:time,ttlMs:60000});
  const gateway=createMenuGatewaySimulator({proposal,token,nowMs:()=>time+60000});
  t.after(()=>gateway.close());
  const origin=await gateway.start();
  const resp=await fetch(origin+"/v1/mission/101/202/demo-run-0001",{headers:headers()});
  assert.equal(resp.status,410);
  assert.equal(gateway.snapshot().status,"QUEUED");
});
