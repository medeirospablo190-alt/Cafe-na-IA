import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,menuReceipt} from "../src/menu-proposal.mjs";
import {publishGithubMenuProposal,readGithubMenuProposal} from "../src/github-menu-queue.mjs";
import {createMenuGatewaySimulator} from "../src/menu-gateway-sim.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const repo="medeirospablo190-alt/Cafe-na-IA";
const token="local-demo-session-token";
const now=1700000000000;

test("synthetic GitHub inbox -> gateway HTTP -> menu receipt -> closed safely",async t=>{
  let content=null,puts=0;
  const request=async(_url,options)=>{
    if(options.method==="GET")return content?{
      status:200,json:async()=>({type:"file",encoding:"base64",
        sha:"a".repeat(40),content:Buffer.from(JSON.stringify(content)).toString("base64")})
    }:{status:404};
    if(options.method==="PUT"){
      puts++;
      content=JSON.parse(Buffer.from(JSON.parse(options.body).content,"base64").toString());
      return {ok:true,status:201};
    }
    throw new Error("API call not expected");
  };
  const proposed=createMenuProposal(report(),{nowMs:now});
  const written=await publishGithubMenuProposal({
    repository:repo,proposal:proposed,token:"MOCK",dryRun:false,request
  });
  assert.equal(written.status,"SAVED");
  const fetched=await readGithubMenuProposal({
    repository:repo,gameId:proposed.identity.gameId,
    missionId:proposed.missionId,request
  });
  assert.equal(fetched.status,"FOUND");
  assert.equal(puts,1);
  assert.equal(fetched.proposal.executable,false);
  const bridge=createMenuGatewaySimulator({
    proposal:fetched.proposal,token,nowMs:()=>now+1000
  });
  t.after(()=>bridge.close());
  const origin=await bridge.start();
  const headers={"Authorization":"Bearer "+token,"Content-Type":"application/json"};
  const poll=await (await fetch(origin+"/v1/mission/101/202/demo-run-0001",{headers})).json();
  assert.equal(poll.proposal.missionId,proposed.missionId);
  assert.equal(poll.proposal.approvalRequired,true);
  const post=(route,kind)=>fetch(origin+route,{
    method:"POST",headers,body:JSON.stringify(menuReceipt(poll.proposal,kind))
  });
  assert.equal((await post("/v1/mission/ack","RECEIVED")).status,200);
  assert.equal((await post("/v1/mission/report","DECLINED")).status,200);
  assert.equal(bridge.snapshot().status,"CLOSED_NO_EXECUTION");
  assert.equal(bridge.snapshot().executed,false);
  assert.equal(bridge.snapshot().approved,false);
  assert.ok(!JSON.stringify(content).includes("TEST_SECRET"));
});
