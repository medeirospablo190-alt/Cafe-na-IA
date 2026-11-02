#!/usr/bin/env node
/**
 * One-off GitHub Actions integration test. It never contacts Roblox, Render or
 * production services. All evidence originates from the bundled synthetic V3 fixture.
 */
import {readFileSync} from "node:fs";
import {randomBytes} from "node:crypto";
import {fileURLToPath} from "node:url";
import path from "node:path";
import {analyzeSession} from "./session.mjs";
import {createMenuProposal,menuReceipt} from "./menu-proposal.mjs";
import {createMenuGatewaySimulator} from "./menu-gateway-sim.mjs";
import {readGithubMenuProposal,publishGithubMenuProposal} from "./github-menu-queue.mjs";
import {readGithubMenuDelivery,syncGithubMenuDeliveryEvent} from "./github-menu-receipts.mjs";

const RUN=/^[0-9]{6,16}$/;
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const allowedModes=new Set(["publish","acknowledge","verify"]);
const here=path.resolve(fileURLToPath(import.meta.url));

export function syntheticProposal(runId,{nowMs=Date.now()}={}){
  if(typeof runId!=="string"||!RUN.test(runId)||
    !Number.isSafeInteger(nowMs)||nowMs<0){
    throw new Error("Ambiente de teste sintetico invalido.");
  }
  const load=name=>JSON.parse(readFileSync(new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
  const syntheticRunId="synthetic-"+runId;
  const batch={...load("batch.json"),runId:syntheticRunId};
  const manifest={...load("latest.json"),runId:syntheticRunId};
  const report=analyzeSession({batches:[batch],manifest});
  const proposal=createMenuProposal(report,{nowMs,ttlMs:86400000});
  if(proposal.approved!==false||proposal.executable!==false||
     proposal.approvalRequired!==true||proposal.toolId!=="watch_state"||
     proposal.identity.gameId!=="101"||
     proposal.identity.runId!==syntheticRunId){
    throw new Error("Proposta sintetica fora do contrato.");
  }
  const out=JSON.stringify(proposal);
  if(out.includes("TEST_SECRET")||out.includes("username")||
     out.includes('"userId"')){
    throw new Error("Proposta sintetica contem dados proibidos.");
  }
  return proposal;
}

export async function syntheticGithubMenuSmoke(mode,env=process.env){
  if(!allowedModes.has(mode)||!RUN.test(env.GITHUB_RUN_ID??"")||
    !REPO.test(env.GITHUB_REPOSITORY??"")||
    env.GITHUB_REPOSITORY!=="medeirospablo190-alt/Cafe-na-IA"||
    typeof env.GITHUB_TOKEN!=="string"||env.GITHUB_TOKEN.length<8){
    throw new Error("Execucao isolada de teste nao autorizada.");
  }
  const {GITHUB_RUN_ID:runId,GITHUB_REPOSITORY:repository,GITHUB_TOKEN:token}=env;
  const local=syntheticProposal(runId);
  const args={repository,gameId:local.identity.gameId,missionId:local.missionId,token};
  if(mode==="publish"){
    const result=await publishGithubMenuProposal({
      repository,proposal:local,token,dryRun:false
    });
    if(!["SAVED","UNCHANGED"].includes(result.status)){
      throw new Error("Fila sintetica nao publicada.");
    }
    return {
      step:"PUBLISH",status:result.status,missionId:local.missionId,
      syntheticOnly:true,approved:false,executed:false
    };
  }
  const item=await readGithubMenuProposal(args);
  if(item.status!=="FOUND"||item.proposal.approved!==false||
     item.proposal.executable!==false||
     item.proposal.approvalRequired!==true||
     item.proposal.identity.runId!==local.identity.runId||
     item.proposal.manifestSha256!==local.manifestSha256||
     item.proposal.expiresAtMs<=Date.now()){
    throw new Error("Proposta remota invalida ou expirada.");
  }
  const proposal=item.proposal;
  const receipts={repository,proposal,token};
  if(mode==="acknowledge"){
    // The token below is ephemeral and exists only within the loopback simulator.
    // The simulated menu sends NO GitHub credentials with its HTTP requests.
    const clientToken=randomBytes(24).toString("hex");
    const simulator=createMenuGatewaySimulator({
      proposal,token:clientToken,
      persistEvent:(event,nowMs)=>syncGithubMenuDeliveryEvent({
        ...receipts,event,nowMs,dryRun:false
      })
    });
    const verified=[];
    try{
      const origin=await simulator.start();
      const headers={
        Authorization:"Bearer "+clientToken,
        "Content-Type":"application/json"
      };
      const sessionPath="/v1/mission/"+proposal.identity.gameId+"/"+
        proposal.identity.placeId+"/"+proposal.identity.runId;
      const delivery=await fetch(origin+sessionPath,{headers});
      if(!delivery.ok)throw new Error("Gateway local nao entregou proposta.");
      const envelope=await delivery.json();
      if(envelope?.proposal?.missionId!==proposal.missionId||
         envelope.proposal.executable!==false||envelope.status!=="DELIVERED"){
        throw new Error("Entrega HTTP nao validada.");
      }
      verified.push("DELIVERED");
      for(const [url,kind,want] of [
        ["/v1/mission/ack","RECEIVED","ACKNOWLEDGED"],
        ["/v1/mission/report","NOT_EXECUTED","CLOSED_NO_EXECUTION"]
      ]){
        const result=await fetch(origin+url,{
          method:"POST",headers,
          body:JSON.stringify(menuReceipt(proposal,kind))
        });
        if(!result.ok)throw new Error("Gateway local nao recebeu "+kind+".");
        const payload=await result.json();
        if(payload.status!==want||payload.approved!==false||
           payload.executed!==false){
          throw new Error("Resposta HTTP inconsistente.");
        }
        verified.push(want);
      }
      if(simulator.snapshot().status!=="CLOSED_NO_EXECUTION"||
         simulator.snapshot().executed!==false){
        throw new Error("Estado local inseguro.");
      }
    }finally{
      await simulator.close();
    }
    const fresh=await readGithubMenuDelivery(receipts);
    if(fresh.status!=="FOUND"||fresh.state.status!=="CLOSED_NO_EXECUTION"||
       fresh.state.revision!==3||fresh.state.outcome!=="NOT_EXECUTED"||
       fresh.state.approved!==false||fresh.state.executed!==false){
      throw new Error("Resultado nao persistiu no GitHub.");
    }
    return {
      step:"ACKNOWLEDGE",status:"SAVED_AND_VERIFIED",
      missionId:proposal.missionId,states:verified,
      transport:"HTTP_LOOPBACK_TO_GITHUB_API",
      syntheticOnly:true,approved:false,executed:false
    };
  }
  const stored=await readGithubMenuDelivery(receipts);
  if(stored.status!=="FOUND"||
     stored.state.missionId!==proposal.missionId||
     stored.state.identity.runId!==proposal.identity.runId||
     stored.state.revision!==3||
     stored.state.status!=="CLOSED_NO_EXECUTION"||
     stored.state.outcome!=="NOT_EXECUTED"||
     stored.state.executed!==false||stored.state.approved!==false||
     stored.state.proposalSha256.length!==64){
    throw new Error("Runner independente nao recuperou o recibo final.");
  }
  return {
    step:"VERIFY",status:"CROSS_RUNNER_VERIFIED",
    missionId:proposal.missionId,revision:stored.state.revision,
    deliveryStatus:stored.state.status,
    syntheticOnly:true,approved:false,executed:false
  };
}

if(process.argv[1]&&path.resolve(process.argv[1])===here){
  syntheticGithubMenuSmoke(process.argv[2])
    .then(result=>process.stdout.write(JSON.stringify(result)+"\n"))
    .catch(error=>{
      // Never print API response bodies, tokens, raw fixture data or headers.
      process.stderr.write("CAFEINA_SYNTHETIC_MENU_SMOKE_ERROR: "+
        String(error.message||error)+"\n");
      process.exitCode=1;
    });
}
