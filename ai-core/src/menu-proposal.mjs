import {validateMissionProposal} from "./analysis.mjs";

const gameId=/^[1-9][0-9]{0,19}$/;
const runId=/^[A-Za-z0-9_-]{6,128}$/;
const missionId=/^mission-[a-f0-9]{16}$/;
const hash=/^[a-f0-9]{64}$/;
const permittedTools=new Set(["watch_state","observe_gui"]);
const fields=["schemaVersion","type","missionId","identity","manifestSha256","toolId","params","evidenceRefs","issuedAtMs","expiresAtMs","status","approvalRequired","approved","executable"];
const keys=(value,expected)=>value&&typeof value==="object"&&!Array.isArray(value)&&
  Object.keys(value).length===expected.length&&expected.every(k=>Object.hasOwn(value,k));
const identityValid=x=>keys(x,["gameId","placeId","runId"])&&
  gameId.test(x.gameId)&&gameId.test(x.placeId)&&runId.test(x.runId);
const timeValid=n=>Number.isSafeInteger(n)&&n>=0;

export function validateMenuProposal(p){
  if(!keys(p,fields)||p.schemaVersion!==1||p.type!=="cafeina_ai_menu_proposal"||
     !missionId.test(p.missionId)||!identityValid(p.identity)||
     !hash.test(p.manifestSha256)||!permittedTools.has(p.toolId)||
     !keys(p.params,["durationSeconds"])||p.params.durationSeconds!==10||
     !Array.isArray(p.evidenceRefs)||p.evidenceRefs.length<1||p.evidenceRefs.length>3||
     p.evidenceRefs.some(ref=>typeof ref!=="string"||
       !ref.startsWith("v3:"+p.identity.gameId+":"+p.identity.placeId+":"+p.identity.runId+":")||
       !/^v3:[0-9]+:[0-9]+:[A-Za-z0-9_-]+:[0-9]+:[0-9]+$/.test(ref))||
     !timeValid(p.issuedAtMs)||!timeValid(p.expiresAtMs)||
     p.expiresAtMs<=p.issuedAtMs||p.expiresAtMs-p.issuedAtMs>86400000||
     p.status!=="PROPOSED"||p.approvalRequired!==true||
     p.approved!==false||p.executable!==false){
    throw new Error("Proposta fora do contrato.");
  }
  return p;
}

export function createMenuProposal(report,{nowMs=Date.now(),ttlMs=600000}={}){
  const id=report?.identity,mission=report?.mission;
  if(report?.type!=="cafeina_ai_session_analysis"||report.mode!=="DRY_RUN"||
     report.privacy?.rawRecordsIncluded!==false||
     report.privacy?.personalIdentifiersIncluded!==false||
     report.privacy?.remoteArgumentsIncluded!==false||
     !identityValid(id)||!hash.test(report.sources?.manifestSha256)||
     !timeValid(nowMs)||!Number.isSafeInteger(ttlMs)||ttlMs<60000||
     ttlMs>86400000||!mission){
    throw new Error("Relatorio inadequado para entrega.");
  }
  validateMissionProposal(mission);
  if(mission.gameId!==id.gameId||mission.placeId!==id.placeId||
     mission.originatingRunId!==id.runId||!missionId.test(mission.missionId)){
    throw new Error("Missao nao pertence a sessao.");
  }
  return validateMenuProposal({
    schemaVersion:1,type:"cafeina_ai_menu_proposal",
    missionId:mission.missionId,
    identity:{gameId:id.gameId,placeId:id.placeId,runId:id.runId},
    manifestSha256:report.sources.manifestSha256,
    toolId:mission.toolId,params:{durationSeconds:10},
    evidenceRefs:[...mission.evidenceRefs],issuedAtMs:nowMs,
    expiresAtMs:nowMs+ttlMs,status:"PROPOSED",
    approvalRequired:true,approved:false,executable:false
  });
}
