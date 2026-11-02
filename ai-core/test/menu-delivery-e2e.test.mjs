import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";
import {syncGithubMenuDeliveryEvent,readGithubMenuDelivery} from "../src/github-menu-receipts.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
const repository="medeirospablo190-alt/Cafe-na-IA";
const token="test-opaque-gateway-token-12345";
function fakeGithub(){
  let state=null,puts=0,unavailable=false;
  return {
    get puts(){return puts;},
    get state(){return state;},
    makeUnavailable(value){unavailable=value;},
    async request(url,opts){
      assert.ok(url.includes("/contents/ai-core/menu-receipts/101/mission-"));
      if(unavailable)return {ok:false,status:503};
      if(opts.method==="GET"){
        return state?{status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(state)).toString("base64")
        })}:{status:404};
      }
      if(opts.method==="PUT"){
        const body=JSON.parse(opts.body);
        assert.equal(body.branch,"cafeina-ai-knowledge");
        assert.ok(opts.headers.Authorization?.includes("MOCK"));
        state=JSON.parse(Buffer.from(body.content,"base64").toString("utf8"));
        puts++;
        return {status:201,ok:true};
      }
      throw new Error("Unexpected API call");
    }
  };
}
function authHeaders(){
  return {"Authorization":"Bearer "+token,"Content-Type":"application/json"};
}
test("synthetic HTTP menu delivers and persists ACK/decline into mock GitHub state",async t=>{
  const p=createMenuProposal(report(),{nowMs:now}),api=fakeGithub();
  const store=(event,when)=>syncGithubMenuDeliveryEvent({
    repository,proposal:p,event,nowMs:when,
    token:"MOCK",dryRun:false,request:api.request
  });
  const gateway=createMenuGatewaySimulator({
    proposal:p,token,nowMs:()=>now+1000,persistEvent:store
  });
  t.after(()=>gateway.close());
  const origin=await gateway.start(),headers=authHeaders();
  const sessionPath="/v1/mission/101/202/demo-run-0001";
  const poll=await fetch(origin+sessionPath,{headers});
  assert.equal(poll.status,200);
  assert.equal((await poll.json()).status,"DELIVERED");
  assert.equal(api.state.revision,1);
  const push=(route,kind)=>fetch(origin+route,{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,kind))
  });
  const ack=await push("/v1/mission/ack","RECEIVED");
  assert.equal(ack.status,200);
  assert.equal(api.state.revision,2);
  const outcome=await push("/v1/mission/report","DECLINED");
  assert.equal(outcome.status,200);
  assert.equal(api.state.revision,3);
  assert.equal(api.state.outcome,"DECLINED");
  assert.equal(api.puts,3);
  assert.equal((await push("/v1/mission/report","DECLINED")).status,200);
  assert.equal((await push("/v1/mission/ack","RECEIVED")).status,200);
  assert.equal(api.puts,3);
  const fresh=await readGithubMenuDelivery({
    repository,proposal:p,request:api.request
  });
  assert.equal(fresh.status,"FOUND");
  assert.equal(fresh.state.status,"CLOSED_NO_EXECUTION");
  assert.equal(fresh.state.executed,false);
  assert.equal(fresh.state.approved,false);
  assert.equal(gateway.snapshot().executed,false);
  assert.ok(!JSON.stringify(fresh.state).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(fresh.state).includes("username"));
});
test("simulated gateway refuses delivery and ack until GitHub receipt writes succeed",async t=>{
  const p=createMenuProposal(report(),{nowMs:now}),api=fakeGithub();
  const store=(event,when)=>syncGithubMenuDeliveryEvent({
    repository,proposal:p,event,nowMs:when,
    token:"MOCK",dryRun:false,request:api.request
  });
  const gateway=createMenuGatewaySimulator({
    proposal:p,token,nowMs:()=>now+1000,persistEvent:store
  });
  t.after(()=>gateway.close());
  const origin=await gateway.start(),headers=authHeaders();
  const sessionPath=origin+"/v1/mission/101/202/demo-run-0001";
  api.makeUnavailable(true);
  const first=await fetch(sessionPath,{headers});
  assert.equal(first.status,503);
  assert.equal(gateway.snapshot().status,"QUEUED");
  assert.equal(api.puts,0);
  api.makeUnavailable(false);
  assert.equal((await fetch(sessionPath,{headers})).status,200);
  assert.equal(api.state.revision,1);
  api.makeUnavailable(true);
  const denied=await fetch(origin+"/v1/mission/ack",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"RECEIVED"))
  });
  assert.equal(denied.status,503);
  assert.equal(gateway.snapshot().status,"DELIVERED");
  api.makeUnavailable(false);
  assert.equal((await fetch(origin+"/v1/mission/ack",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"RECEIVED"))
  })).status,200);
  assert.equal(api.state.revision,2);
});
