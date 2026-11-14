import test from "node:test";
import assert from "node:assert/strict";
import {createOwnerMenuBridge} from "../src/owner-menu-bridge.mjs";

const GAME_ID="101",PLACE_ID="202",RUN_ID="synthetic-bridge",MISSION_ID="mission-aaaaaaaaaaaaaaaa";
const JOB_ID="11111111-1111-4111-8111-111111111111";
const SERVER_KEY="server_private_key_for_offline_ci_0123456789";
const GITHUB_TOKEN="github_private_token_test_only";
const NOW=1700000000000;
const proposal={
  schemaVersion:1,type:"cafeina_ai_menu_proposal",missionId:MISSION_ID,
  identity:{gameId:GAME_ID,placeId:PLACE_ID,runId:RUN_ID},
  manifestSha256:"b".repeat(64),toolId:"watch_state",
  params:{durationSeconds:10},
  evidenceRefs:["v3:101:202:synthetic-bridge:1:1"],
  issuedAtMs:NOW-1000,expiresAtMs:NOW+600000,
  status:"PROPOSED",approvalRequired:true,approved:false,executable:false
};
function githubFixture({missing=false,unavailable=false}={}){
  let stored=null,reads=0,writes=0;
  const request=async (url,opts={})=>{
    reads++;
    if(unavailable)throw new Error("OUTAGE");
    const method=opts.method??"GET";
    const mission=url.includes("/mission-queue/");
    const receipt=url.includes("/menu-receipts/");
    if(!mission&&!receipt)throw new Error("Unexpected URL");
    if(method==="GET"){
      if(mission&&missing)return new Response("",{status:404});
      if(receipt&&!stored)return new Response("",{status:404});
      const item=mission?proposal:stored;
      return Response.json({
        type:"file",sha:"a".repeat(40),encoding:"base64",
        content:Buffer.from(JSON.stringify(item)).toString("base64")
      });
    }
    if(method==="PUT"&&receipt){
      writes++;
      stored=JSON.parse(Buffer.from(JSON.parse(opts.body).content,"base64").toString("utf8"));
      return Response.json({content:{sha:"a".repeat(40)}});
    }
    throw new Error("Unexpected method");
  };
  return {request,get stored(){return stored;},get writes(){return writes;},
    get reads(){return reads;}};
}
function build(fixture,now=NOW){
  return createOwnerMenuBridge({
    repository:"owner/repo",githubToken:GITHUB_TOKEN,
    serverKey:SERVER_KEY,
    identity:{gameId:GAME_ID,placeId:PLACE_ID,runId:RUN_ID},
    missionId:MISSION_ID,jobId:JOB_ID,
    request:fixture.request,nowMs:()=>now,pollCooldownMs:0
  });
}
const body=(operation,overrides={})=>({
  schemaVersion:1,operation,gameId:GAME_ID,placeId:PLACE_ID,
  runId:RUN_ID,missionId:MISSION_ID,jobId:JOB_ID,...overrides
});
async function send(base,operation,overrides={},secret=SERVER_KEY){
  const res=await fetch(base+"/v1/roblox/menu",{
    method:"POST",headers:{"content-type":"application/json",
      "x-cafeina-server-key":secret},
    body:JSON.stringify(body(operation,overrides))
  });
  return {status:res.status,...await res.json()};
}
test("bridge requires scoped server-only configuration",()=>{
  assert.throws(()=>createOwnerMenuBridge(),/requires a pre-authorized/);
  const f=githubFixture();
  assert.throws(()=>createOwnerMenuBridge({
    repository:"owner/repo",githubToken:GITHUB_TOKEN,serverKey:"short",
    identity:proposal.identity,missionId:MISSION_ID,jobId:JOB_ID,
    request:f.request
  }),/requires a pre-authorized/);
});
test("a valid, allowlisted Roblox job can poll -> ack -> decline via durable GitHub receipts",async()=>{
  const f=githubFixture();
  const bridge=build(f);
  const address=await bridge.start();
  const base="http://127.0.0.1:"+address.port;
  try{
    const health=await fetch(base+"/health").then(r=>r.json());
    assert.equal(health.status,"RUNNING");
    const denied=await send(base,"POLL",{},"wrong");
    assert.equal(denied.status,401);
    assert.equal(f.reads,0);
    assert.equal((await send(base,"POLL",{runId:"different-run"})).status,403);
    assert.equal((await send(base,"POLL",{jobId:"22222222-2222-4222-8222-222222222222"})).status,403);
    assert.equal((await send(base,"ARBITRARY_COMMAND")).status,403);
    assert.equal(f.reads,0);
    const poll=await send(base,"POLL");
    assert.equal(poll.status,200);
    assert.equal(poll.hasProposal,true);
    assert.equal(poll.proposal.toolId,"watch_state");
    assert.deepEqual(Object.keys(poll.proposal).sort(),
      ["approved","durationSeconds","executable","expiresAtMs","missionId","toolId"].sort());
    assert.equal(poll.proposal.executable,false);
    assert.equal(f.stored.status,"DELIVERED");
    assert.equal(f.stored.revision,1);
    const ack=await send(base,"ACK");
    assert.equal(ack.status,200);
    assert.equal(ack.status,200);
    assert.equal(f.stored.status,"ACKNOWLEDGED");
    assert.equal(f.stored.revision,2);
    const decline=await send(base,"DECLINE");
    assert.equal(decline.status,200);
    assert.equal(decline.executed,false);
    assert.equal(decline.approved,false);
    assert.equal(f.stored.status,"CLOSED_NO_EXECUTION");
    assert.equal(f.stored.outcome,"DECLINED");
    assert.equal(f.stored.revision,3);
    const replay=await send(base,"DECLINE");
    assert.equal(replay.status,200);
    assert.equal(f.stored.revision,3);
    const closed=await send(base,"POLL");
    assert.equal(closed.status,200);
    assert.equal(closed.hasProposal,false);
    assert.equal(f.writes,3);
  }finally{await bridge.close();}
});
test("rejects premature reports and fails closed on backend outage",async()=>{
  const f=githubFixture();
  const bridge=build(f);
  const addr=await bridge.start();
  const base="http://127.0.0.1:"+addr.port;
  try{
    assert.equal((await send(base,"ACK")).status,503);
    assert.equal((await send(base,"NO_EXECUTION")).status,503);
    assert.equal(f.writes,0);
    const first=await send(base,"POLL");
    assert.equal(first.status,200);
    const wrong=await send(base,"DECLINE");
    assert.equal(wrong.status,503);
    assert.equal(f.stored.status,"DELIVERED");
  }finally{await bridge.close();}
  const outage=githubFixture({unavailable:true});
  const other=build(outage),started=await other.start();
  try{
    const answer=await send("http://127.0.0.1:"+started.port,"POLL");
    assert.equal(answer.status,503);
    assert.equal(answer.error,"BRIDGE_BACKEND_UNAVAILABLE");
  }finally{await other.close();}
});
test("missing and expired missions are never delivered",async()=>{
  const missing=githubFixture({missing:true}), m=build(missing);
  const a=await m.start();
  try{
    assert.equal((await send("http://127.0.0.1:"+a.port,"POLL")).status,404);
    assert.equal(missing.writes,0);
  }finally{await m.close();}
  const fixture=githubFixture(), expired=build(fixture,NOW+900000);
  const b=await expired.start();
  try{
    assert.equal((await send("http://127.0.0.1:"+b.port,"POLL")).status,410);
    assert.equal(fixture.writes,0);
  }finally{await expired.close();}
});
