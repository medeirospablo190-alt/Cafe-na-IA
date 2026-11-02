import test from "node:test";
import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";
import {createMenuSessionAuthority} from "../src/menu-session-auth.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const originTime=1700000000000;
const proposal=()=>createMenuProposal(report(),{nowMs:originTime});
const key=()=>randomBytes(32);
function mockTrustedServer(proposal,nowMs=()=>originTime+1000){
  const authority=createMenuSessionAuthority({
    signingKey:key(),nowMs,
    validateTrustedServerSession:async assertion=>{
      if(assertion?.isTrustedServer!==true)return null;
      return {verified:true,identity:{...assertion.identity},missionId:assertion.missionId};
    }
  });
  const assertion={
    isTrustedServer:true,identity:{...proposal.identity},missionId:proposal.missionId
  };
  return {authority,assertion};
}
test("trusted-server stub issues short-lived scoped proposal token",async()=>{
  const p=proposal(),{authority,assertion}=mockTrustedServer(p);
  const token=await authority.issue(p,assertion,{ttlMs:60000});
  assert.equal(authority.verify("Bearer "+token,p),true);
  const changedLastNibble=token.at(-1)==="a"?"b":"a";
  assert.equal(authority.verify("Bearer "+token.slice(0,-1)+changedLastNibble,p),false);
  assert.equal(authority.verify("Bearer "+token.replace(".","x."),p),false);
  assert.equal(authority.verify("Bearer "+token,{...p,missionId:"mission-"+"f".repeat(16)}),false);
  assert.equal(authority.verify("Bearer "+token,{...p,identity:{...p.identity,gameId:"808"}}),false);
  assert.ok(!token.includes("TEST_SECRET"));
  assert.throws(()=>createMenuSessionAuthority({
    signingKey:Buffer.from("weak"),validateTrustedServerSession:async()=>true
  }),/chave/);
});
test("issuance fails with absent or mismatched trusted server validation",async()=>{
  const p=proposal(),{authority,assertion}=mockTrustedServer(p);
  await assert.rejects(()=>authority.issue(p,{...assertion,isTrustedServer:false}),/autenticado/);
  await assert.rejects(()=>authority.issue(p,{
    ...assertion,identity:{...p.identity,placeId:"909"}
  }),/autenticado/);
  await assert.rejects(()=>authority.issue(p,assertion,{ttlMs:3600000}),/limite/);
});
test("expired token is rejected and server callback is never bypassed",async()=>{
  const p=proposal();
  let clock=originTime+1000;
  let calls=0;
  const authority=createMenuSessionAuthority({
    signingKey:key(),nowMs:()=>clock,
    validateTrustedServerSession:async assertion=>{
      calls++;
      return assertion==="private-server-fixture"?
        {verified:true,identity:{...p.identity},missionId:p.missionId}:null;
    }
  });
  const token=await authority.issue(p,"private-server-fixture",{ttlMs:1000});
  assert.equal(calls,1);
  assert.equal(authority.verify("Bearer "+token,p),true);
  clock+=1000;
  assert.equal(authority.verify("Bearer "+token,p),false);
  assert.equal(calls,1);
});
test("HTTP loopback gateway uses scoped token, never Github credentials",async t=>{
  const p=proposal(),{authority,assertion}=mockTrustedServer(p);
  const validToken=await authority.issue(p,assertion,{ttlMs:60000});
  const gateway=createMenuGatewaySimulator({
    proposal:p,token:null,nowMs:()=>originTime+1000,
    authorizeRequest:authorization=>authority.verify(authorization,p)
  });
  t.after(()=>gateway.close());
  const base=await gateway.start();
  const path="/v1/mission/101/202/demo-run-0001";
  assert.equal((await fetch(base+path,{
    headers:{Authorization:"Bearer fake-GitHub-token"}
  })).status,401);
  const headers={Authorization:"Bearer "+validToken,"Content-Type":"application/json"};
  const response=await fetch(base+path,{headers});
  assert.equal(response.status,200);
  const delivery=await response.json();
  assert.equal(delivery.proposal.approved,false);
  assert.equal(delivery.proposal.executable,false);
  const ack=await fetch(base+"/v1/mission/ack",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"RECEIVED"))
  });
  assert.equal(ack.status,200);
  const result=await fetch(base+"/v1/mission/report",{
    method:"POST",headers,body:JSON.stringify(menuReceipt(p,"NOT_EXECUTED"))
  });
  assert.equal(result.status,200);
  assert.equal(gateway.snapshot().executed,false);
});
