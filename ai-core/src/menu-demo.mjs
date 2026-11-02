#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {createMenuProposal,menuReceipt} from "./menu-proposal.mjs";
import {createMenuGatewaySimulator} from "./menu-gateway-sim.mjs";

const load=name=>JSON.parse(readFileSync(new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
const clock=1700000000000;
const report=analyzeSession({
  batches:[load("batch.json")],manifest:load("latest.json")
});
const proposal=createMenuProposal(report,{nowMs:clock});
const token="simulated-only-opaque-session-token";
const gateway=createMenuGatewaySimulator({
  proposal,token,nowMs:()=>clock+1000
});
try{
  const base=await gateway.start();
  const headers={"Authorization":"Bearer "+token,"Content-Type":"application/json"};
  const poll=await fetch(base+"/v1/mission/101/202/demo-run-0001",{headers});
  if(!poll.ok)throw new Error("Menu polling falhou.");
  const queued=await poll.json();
  if(queued.proposal?.executable!==false||
     queued.proposal?.approved!==false)throw new Error("Missao insegura.");
  const post=(route,kind)=>fetch(base+route,{
    method:"POST",headers,
    body:JSON.stringify(menuReceipt(proposal,kind))
  });
  const ack=await post("/v1/mission/ack","RECEIVED");
  const receipt=await post("/v1/mission/report","NOT_EXECUTED");
  if(!ack.ok||!receipt.ok)throw new Error("Confirmacao nao recebida.");
  const state=gateway.snapshot();
  if(state.status!=="CLOSED_NO_EXECUTION"||state.executed){
    throw new Error("Resposta de menu nao segura.");
  }
  process.stdout.write(JSON.stringify({
    simulationOnly:true,transport:"HTTP_LOOPBACK",missionId:proposal.missionId,
    flow:["PROPOSED","DELIVERED","ACKNOWLEDGED","CLOSED_NO_EXECUTION"],
    approved:false,executed:false,githubPublished:false,
    rawPlayerDataIncluded:false
  })+"\n");
}finally{
  await gateway.close();
}
