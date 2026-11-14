import test from "node:test";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createMenuSessionAuthority} from "../src/menu-session-auth.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";
import {createExperienceServerVerifier,createInMemoryNonceStore} from "../src/roblox-server-verifier.mjs";
import {createRobloxCheckinSimulator} from "../src/roblox-checkin-sim.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000,jobId="11111111-2222-4333-8444-555555555555";
const createSystem=()=>{
  const p=createMenuProposal(report(),{nowMs:now});
  const secret=randomBytes(32).toString("base64url");
  const clock=()=>now+1000;
  const verifier=createExperienceServerVerifier({
    credentials:[{gameId:"101",placeId:"202",secret}],
    nowMs:clock,claimNonce:createInMemoryNonceStore(clock),
    resolveTrustedJob:async ({gameId,placeId,jobId:job,missionId})=>
      job===jobId?{
        verified:true,active:true,gameId,placeId,jobId:job,
        runId:p.identity.runId,missionId
      }:null
  });
  const authority=createMenuSessionAuthority({
    signingKey:randomBytes(32),nowMs:clock,
    validateTrustedServerSession:verifier.validateTrustedServerSession
  });
  const body={
    schemaVersion:1,aud:"CAFEINA_ROBLOX_SERVER_CHECKIN_V1",
    gameId:"101",placeId:"202",jobId,missionId:p.missionId,
    issuedAtMs:now+1000,nonce:"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
  };
  return {p,secret,authority,body};
};
const headers=key=>({"Content-Type":"application/json","x-api-key":key});

test("server HTTP check-in obtains scoped token then menu returns non-execution",async t=>{
  const {p,secret,authority,body}=createSystem();
  const endpoint=createRobloxCheckinSimulator({proposal:p,authority});
  t.after(()=>endpoint.close());
  const origin=await endpoint.start();
  const serverRequest=()=>fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:headers(secret),body:JSON.stringify(body)
  });
  const response=await serverRequest();
  assert.equal(response.status,200);
  const result=await response.json();
  assert.equal(result.mode,"PROPOSAL_READ_ONLY");
  assert.equal(result.approved,false);
  assert.equal(result.executable,false);
  assert.ok(result.sessionToken.startsWith("cm1."));
  const second=await serverRequest();
  assert.equal(second.status,403);
  assert.equal("sessionToken" in await second.json(),false);
  const gateway=createMenuGatewaySimulator({
    proposal:p,token:null,nowMs:()=>now+1000,
    authorizeRequest:header=>authority.verify(header,p)
  });
  t.after(()=>gateway.close());
  const base=await gateway.start();
  const session="/v1/mission/101/202/demo-run-0001";
  const auth={"Authorization":"Bearer "+result.sessionToken,"Content-Type":"application/json"};
  assert.equal((await fetch(base+session,{headers:auth})).status,200);
  assert.equal((await fetch(base+"/v1/mission/ack",{
    method:"POST",headers:auth,body:JSON.stringify(menuReceipt(p,"RECEIVED"))
  })).status,200);
  assert.equal((await fetch(base+"/v1/mission/report",{
    method:"POST",headers:auth,body:JSON.stringify(menuReceipt(p,"NOT_EXECUTED"))
  })).status,200);
  assert.equal(gateway.snapshot().status,"CLOSED_NO_EXECUTION");
  assert.equal(gateway.snapshot().executed,false);
  assert.equal(endpoint.snapshot().issued,1);
});

test("forged server and unauthorized paths get no signed capability",async t=>{
  const {p,secret,authority,body}=createSystem();
  const endpoint=createRobloxCheckinSimulator({proposal:p,authority});
  t.after(()=>endpoint.close());
  const origin=await endpoint.start();
  const badKey=await fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:headers("fake-key-000"),body:JSON.stringify(body)
  });
  assert.equal(badKey.status,403);
  assert.equal("sessionToken" in await badKey.json(),false);
  const badJob=await fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:headers(secret),
    body:JSON.stringify({...body,jobId:"88888888-9999-4aaa-8bbb-cccccccccccc"})
  });
  assert.equal(badJob.status,403);
  assert.equal((await fetch(origin+"/v1/server/checkin")).status,404);
  assert.equal((await fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)
  })).status,401);
  assert.equal(endpoint.snapshot().issued,0);
});

test("oversized checkin and unavailable nonce registry deny access",async t=>{
  const {p,secret,body}=createSystem();
  const clock=()=>now+1000;
  const verifier=createExperienceServerVerifier({
    credentials:[{gameId:"101",placeId:"202",secret}],
    nowMs:clock,resolveTrustedJob:async()=>({
      verified:true,active:true,gameId:"101",placeId:"202",jobId,
      runId:p.identity.runId,missionId:p.missionId
    }),claimNonce:async()=>false
  });
  const authority=createMenuSessionAuthority({
    signingKey:randomBytes(32),nowMs:clock,
    validateTrustedServerSession:verifier.validateTrustedServerSession
  });
  const endpoint=createRobloxCheckinSimulator({proposal:p,authority});
  t.after(()=>endpoint.close());
  const origin=await endpoint.start();
  assert.equal((await fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:headers(secret),
    body:JSON.stringify({...body,padding:"x".repeat(1200)})
  })).status,413);
  assert.equal((await fetch(origin+"/v1/server/checkin",{
    method:"POST",headers:headers(secret),body:JSON.stringify(body)
  })).status,403);
  assert.equal(endpoint.snapshot().issued,0);
});
