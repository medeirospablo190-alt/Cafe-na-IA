#!/usr/bin/env node
/**
 * One-off integration check. Writes synthetic-only permission metadata into
 * cafeina-ai-knowledge. Does NOT contact Roblox, Render, players or collectors.
 * No approval for live execution is ever issued.
 */
import {fileURLToPath} from "node:url";
import path from "node:path";
import {syntheticProposal} from "./github-menu-real-smoke.mjs";
import {readGithubMenuProposal,publishGithubMenuProposal} from "./github-menu-queue.mjs";
import {
  createCollectorPermissionRequest,reviewCollectorPermission
} from "./collector-permissions.mjs";
import {
  readGithubCollectorPermission,syncGithubCollectorPermission
} from "./github-collector-permissions.mjs";

const modes=new Set(["publish","deny","verify"]);
const repo="medeirospablo190-alt/Cafe-na-IA";
const here=path.resolve(fileURLToPath(import.meta.url));
const isRun=value=>typeof value==="string"&&/^[0-9]{6,16}$/.test(value);

export async function syntheticPermissionRoundtrip(mode,env=process.env){
  if(!modes.has(mode)||env.GITHUB_REPOSITORY!==repo||
     !isRun(env.GITHUB_RUN_ID)||
     typeof env.GITHUB_TOKEN!=="string"||env.GITHUB_TOKEN.length<8){
    throw new Error("Ambiente sintetico de teste nao autorizado.");
  }
  const {GITHUB_RUN_ID:runId,GITHUB_TOKEN:token}=env;
  const probe=syntheticProposal(runId,{nowMs:1700000000000});
  const lookup={
    repository:repo,gameId:probe.identity.gameId,
    missionId:probe.missionId,token
  };
  if(mode==="publish"){
    const proposal=syntheticProposal(runId,{nowMs:Date.now()});
    if(proposal.identity.gameId!=="101"||proposal.identity.placeId!=="202"||
       proposal.identity.runId!=="synthetic-"+runId){
      throw new Error("Identidade sintetica invalida.");
    }
    const posted=await publishGithubMenuProposal({
      repository:repo,proposal,token,dryRun:false
    });
    if(!["SAVED","UNCHANGED"].includes(posted.status)){
      throw new Error("Proposta sintetica nao publicada.");
    }
    const request=createCollectorPermissionRequest(proposal,{
      nowMs:proposal.issuedAtMs+1,ttlMs:300000
    });
    const saved=await syncGithubCollectorPermission({
      repository:repo,proposal,requestRecord:request,token,dryRun:false
    });
    if(!["SAVED","UNCHANGED"].includes(saved.status)||saved.revision!==0){
      throw new Error("Pedido sintetico nao persistido.");
    }
    return {step:"PUBLISH",permissionState:"PENDING_REVIEW",
      missionId:proposal.missionId,syntheticOnly:true,executed:false};
  }
  const found=await readGithubMenuProposal(lookup);
  if(found.status!=="FOUND"||
     found.proposal.identity.runId!=="synthetic-"+runId||
     found.proposal.identity.gameId!=="101"||
     found.proposal.identity.placeId!=="202"||
     found.proposal.executable!==false||
     found.proposal.approved!==false||
     found.proposal.expiresAtMs<=Date.now()){
    throw new Error("Proposta sintetica GitHub nao encontrada ou invalida.");
  }
  const proposal=found.proposal;
  const readOptions={repository:repo,proposal,token};
  const current=await readGithubCollectorPermission(readOptions);
  if(current.status!=="FOUND"||
     current.record.request.liveExecutionRequested!==false){
    throw new Error("Pedido sintetico nao recuperado.");
  }
  if(mode==="deny"){
    if(current.record.revision!==0||current.record.status!=="PENDING_REVIEW"){
      throw new Error("Pedido nao esta pendente para recusa.");
    }
    const req=current.record.request;
    const review=await reviewCollectorPermission(req,proposal,{
      outcome:"DENIED",nowMs:Date.now(),
      operatorEvidence:"GITHUB_ACTIONS_SYNTHETIC_FIXTURE",
      // This callback is deliberately not a real user or Roblox identity.
      verifyTestOperator:async evidence=>evidence==="GITHUB_ACTIONS_SYNTHETIC_FIXTURE"?{
        verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
        requestId:req.requestId,missionId:req.missionId,
        identity:{...req.identity}
      }:null
    });
    const written=await syncGithubCollectorPermission({
      ...readOptions,review,dryRun:false
    });
    if(!["SAVED","UNCHANGED"].includes(written.status)||
       written.revision!==1||written.decision!=="DENIED"){
      throw new Error("Recusa sintetica nao salva.");
    }
    const reread=await readGithubCollectorPermission(readOptions);
    if(reread.record?.review?.outcome!=="DENIED"||
       reread.record?.revision!==1||
       reread.record?.review?.authorizedLiveExecution!==false){
      throw new Error("Recusa sintetica nao recuperada apos gravar.");
    }
    return {step:"DENY",decision:"DENIED",
      revision:1,syntheticOnly:true,executed:false};
  }
  if(current.record.revision!==1||
     current.record.status!=="REVIEWED"||
     current.record.review?.outcome!=="DENIED"||
     current.record.review?.authorizedLiveExecution!==false||
     current.record.review?.robloxConnected!==false||
     current.record.request?.scope!=="SYNTHETIC_PREVIEW_ONLY"){
    throw new Error("Recusa nao recuperada por terceiro runner.");
  }
  // Reading is not consent: third runner has contents:read only.
  return {step:"VERIFY",status:"CROSS_RUNNER_DENIAL_VERIFIED",
    revision:1,syntheticOnly:true,executed:false,
    approvedForLiveTools:false};
}
if(process.argv[1]&&path.resolve(process.argv[1])===here){
  syntheticPermissionRoundtrip(process.argv[2])
    .then(value=>process.stdout.write(JSON.stringify(value)+"\n"))
    .catch(error=>{
      // Never print tokens, response headers, raw server payload or fixtures.
      process.stderr.write("COLLECTOR_PERMISSION_SYNTHETIC_SMOKE_FAILED: "+
        String(error.message||error)+"\n");
      process.exitCode=1;
    });
}
