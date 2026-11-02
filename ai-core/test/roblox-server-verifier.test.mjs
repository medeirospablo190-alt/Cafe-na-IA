import test from "node:test";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createMenuSessionAuthority} from "../src/menu-session-auth.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";
import {createExperienceServerVerifier,createInMemoryNonceStore} from "../src/roblox-server-verifier.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
const JOB="11111111-2222-4333-8444-555555555555";
const SECRET=()=>randomBytes(32).toString("base64url");
const config=secret=>[{gameId:"101",placeId:"202",secret}];
const proposal=()=>createMenuProposal(report(),{nowMs:now});
const assertion=(p,secret,clock=now+1000)=>({
  headers:{"x-api-key":secret},
  body:{
    schemaVersion:1,aud:"CAFEINA_ROBLOX_SERVER_CHECKIN_V1",
    gameId:p.identity.gameId,placeId:p.identity.placeId,jobId:JOB,
    missionId:p.missionId,issuedAtMs:clock,
    nonce:"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
  }
});
function fixtureVerifier(p,{clock=()=>now+1000,secret=SECRET(),resolve,claimNonce}={}){
  const registry=resolve??(async ({gameId,placeId,jobId,missionId})=>({
    verified:true,active:true,gameId,placeId,jobId,missionId,runId:p.identity.runId
  }));
  const verifier=createExperienceServerVerifier({
    credentials:config(secret),nowMs:clock,resolveTrustedJob:registry,
    claimNonce:claimNonce??createInMemoryNonceStore(clock)
  });
  return {verifier,secret};
}

test("secret and registered JobId bind mission to a trusted CAFEINA run",async()=>{
  const p=proposal(),{verifier,secret}=fixtureVerifier(p);
  const result=await verifier.validateTrustedServerSession(assertion(p,secret));
  assert.equal(result.verified,true);
  assert.deepEqual(result.identity,p.identity);
  assert.equal(result.missionId,p.missionId);
  await assert.rejects(
    ()=>verifier.validateTrustedServerSession(assertion(p,secret)),
    /Nonce repetido/
  );
});

test("unknown key, place, job, game, clock and fields are refused",async()=>{
  const p=proposal();
  for(const alter of [
    a=>{a.headers["x-api-key"]="wrong";},
    a=>{a.body.gameId="404";},
    a=>{a.body.placeId="909";},
    a=>{a.body.jobId="88888888-9999-4aaa-8bbb-cccccccccccc";},
    a=>{a.body.issuedAtMs=now-50000;},
    a=>{a.body.issuedAtMs=now+60000;},
    a=>{a.body.approved=true;},
    a=>{a.body.nonce="../../secret";}
  ]){
    const {verifier,secret}=fixtureVerifier(p,{
      resolve:async ({gameId,placeId,jobId,missionId})=>({
        verified:true,active:true,gameId,placeId,
        jobId:JOB,missionId,runId:p.identity.runId
      })
    });
    const a=assertion(p,secret);
    alter(a);
    await assert.rejects(()=>verifier.validateTrustedServerSession(a));
  }
});
test("registered JobId mapping cannot be supplied by a Roblox client",async()=>{
  const p=proposal(),{verifier,secret}=fixtureVerifier(p,{
    resolve:async()=>null
  });
  await assert.rejects(()=>verifier.validateTrustedServerSession(
    assertion(p,secret)),/nao registrado/);
  assert.throws(()=>createExperienceServerVerifier({
    credentials:config("too-short"),resolveTrustedJob:async()=>null,claimNonce:async()=>true
  }),/invalida/);
});

test("distributed nonce store failure denies credentials, not grants",async()=>{
  const p=proposal(),{verifier,secret}=fixtureVerifier(p,{
    claimNonce:async()=>false
  });
  await assert.rejects(()=>verifier.validateTrustedServerSession(
    assertion(p,secret)),/Nonce/);
});

test("verified server check-in allows a short-lived read-only menu HTTP flow",async t=>{
  const p=proposal(),{verifier,secret}=fixtureVerifier(p);
  const authority=createMenuSessionAuthority({
    signingKey:randomBytes(32),nowMs:()=>now+1000,
    validateTrustedServerSession:verifier.validateTrustedServerSession
  });
  const cap=await authority.issue(p,assertion(p,secret),{ttlMs:60000});
  assert.equal(authority.verify("Bearer "+cap,p),true);
  const gateway=createMenuGatewaySimulator({
    proposal:p,token:null,nowMs:()=>now+1000,
    authorizeRequest:authorization=>authority.verify(authorization,p)
  });
  t.after(()=>gateway.close());
  const base=await gateway.start();
  const path="/v1/mission/101/202/demo-run-0001";
  assert.equal((await fetch(base+path,{
    headers:{Authorization:"Bearer invalid-github-token"}
  })).status,401);
  const headers={"Authorization":"Bearer "+cap,"Content-Type":"application/json"};
  const read=await fetch(base+path,{headers});
  assert.equal(read.status,200);
  assert.equal((await read.json()).proposal.executable,false);
  assert.equal((await fetch(base+"/v1/mission/ack",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"RECEIVED"))
  })).status,200);
  assert.equal((await fetch(base+"/v1/mission/report",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"NOT_EXECUTED"))
  })).status,200);
  assert.equal(gateway.snapshot().approved,false);
  assert.equal(gateway.snapshot().executed,false);
});
