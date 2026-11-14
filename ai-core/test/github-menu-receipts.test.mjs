import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {syncGithubMenuDeliveryEvent,readGithubMenuDelivery} from "../src/github-menu-receipts.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
const proposal=()=>createMenuProposal(report(),{nowMs:now});
const repository="medeirospablo190-alt/Cafe-na-IA";
function mock(){
  let state=null,puts=0,conflicts=0;
  return {
    get state(){return state;},get puts(){return puts;},
    setConflicts(n){conflicts=n;},
    async request(url,opts){
      assert.ok(url.includes("/contents/ai-core/menu-receipts/101/mission-"));
      if(opts.method==="GET"){
        if(!state)return {status:404};
        return {status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(state)).toString("base64")
        })};
      }
      if(opts.method==="PUT"){
        if(conflicts>0){conflicts--;return {status:409,ok:false};}
        const body=JSON.parse(opts.body);
        assert.equal(body.branch,"cafeina-ai-knowledge");
        assert.ok(opts.headers.Authorization?.startsWith("Bearer MOCK"));
        state=JSON.parse(Buffer.from(body.content,"base64").toString("utf8"));
        puts++;
        return {ok:true,status:201};
      }
      throw new Error("Unexpected HTTP method");
    }
  };
}
test("dry-run is the default and does not mutate remote state",async()=>{
  const api=mock(),p=proposal();
  const out=await syncGithubMenuDeliveryEvent({
    repository,proposal:p,event:"DELIVERED",nowMs:now+100,request:api.request
  });
  assert.equal(out.status,"DRY_RUN");
  assert.equal(api.puts,0);
  assert.equal((await readGithubMenuDelivery({
    repository,proposal:p,request:api.request
  })).status,"MISSING");
});
test("receipt state persists across independent API calls and is idempotent",async()=>{
  const api=mock(),p=proposal();
  const opts={repository,proposal:p,token:"MOCK",dryRun:false,request:api.request};
  for(const [event,revision] of [["DELIVERED",1],["RECEIVED",2],["NOT_EXECUTED",3]]){
    const done=await syncGithubMenuDeliveryEvent({...opts,event,nowMs:now+revision*100});
    assert.equal(done.status,"SAVED");
    assert.equal(done.revision,revision);
    const reloaded=await readGithubMenuDelivery({repository,proposal:p,request:api.request});
    assert.equal(reloaded.state.revision,revision);
    assert.equal(reloaded.state.approved,false);
    assert.equal(reloaded.state.executed,false);
  }
  assert.equal(api.puts,3);
  const replay=await syncGithubMenuDeliveryEvent({
    ...opts,event:"NOT_EXECUTED",nowMs:now+1000
  });
  assert.equal(replay.status,"UNCHANGED");
  assert.equal(api.puts,3);
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    ...opts,event:"DECLINED",nowMs:now+1000
  }),/CONFLICT/);
  assert.ok(!JSON.stringify(api.state).includes("TEST_SECRET"));
});
test("retries concurrent revision conflicts and fails without token or on main",async()=>{
  const api=mock(),p=proposal();
  api.setConflicts(1);
  const out=await syncGithubMenuDeliveryEvent({
    repository,proposal:p,event:"DELIVERED",
    nowMs:now+100,request:api.request,token:"MOCK",dryRun:false
  });
  assert.equal(out.status,"SAVED");
  assert.equal(api.puts,1);
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    repository,proposal:p,event:"RECEIVED",
    nowMs:now+200,request:api.request,dryRun:false
  }),/token/);
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    repository,proposal:p,event:"RECEIVED",branch:"main",
    nowMs:now+200,request:api.request
  }),/nao permitido/);
});
test("wrong remote state, missed delivery and unrecognized event fail closed",async()=>{
  const api=mock(),p=proposal(),opts={
    repository,proposal:p,request:api.request
  };
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    ...opts,event:"RECEIVED",nowMs:now+100
  }),/ACK_REQUIRED/);
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    ...opts,event:"EXECUTE",nowMs:now+100
  }),/nao permitido/);
  await assert.rejects(()=>syncGithubMenuDeliveryEvent({
    ...opts,event:"DELIVERED",nowMs:now+600000
  }),/expirado/);
  await assert.rejects(()=>readGithubMenuDelivery({
    ...opts,request:async()=>({status:403})
  }),/HTTP 403/);
});
