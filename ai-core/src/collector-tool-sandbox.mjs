import {createHash} from "node:crypto";
import {validateMenuProposal} from "./menu-proposal.mjs";

const TOOL_SPECS=Object.freeze({
  watch_state:Object.freeze({
    toolId:"watch_state",observationKind:"remote_outbound",
    privilege:"OFFLINE_METADATA_ONLY",durationSeconds:10,
    maxEvidenceRefs:3,allowsActiveRemoteCalls:false
  }),
  observe_gui:Object.freeze({
    toolId:"observe_gui",observationKind:"gui_state",
    privilege:"OFFLINE_METADATA_ONLY",durationSeconds:10,
    maxEvidenceRefs:3,allowsActiveRemoteCalls:false
  })
});
const ID=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const HASH=/^[0-9a-f]{64}$/;
const REF=/^v3:[1-9][0-9]*:[1-9][0-9]*:[A-Za-z0-9_-]{6,128}:[0-9]+:[0-9]+$/;
const REQUEST=/^trial-[0-9a-f]{16}$/;
const MAX_TRIALS=2;
const MAX_SECONDS=20;
const exact=(x,fields)=>x!==null&&typeof x==="object"&&!Array.isArray(x)&&
  Object.keys(x).length===fields.length&&fields.every(k=>Object.hasOwn(x,k));
const isMs=n=>Number.isSafeInteger(n)&&n>=0;
const same=(a,b)=>a.gameId===b.gameId&&a.placeId===b.placeId&&a.runId===b.runId;
const copy=x=>JSON.parse(JSON.stringify(x));

export function collectorToolCatalog(){
  return Object.values(TOOL_SPECS).map(spec=>({...spec}));
}
export function validateCollectorSandboxSource(proposal,report){
  validateMenuProposal(proposal);
  const source=report?.sources,ident=report?.identity;
  if(report?.type!=="cafeina_ai_session_analysis"||report.mode!=="DRY_RUN"||
     !ident||typeof ident.gameId!=="string"||!ID.test(ident.gameId)||
     typeof ident.placeId!=="string"||!ID.test(ident.placeId)||
     typeof ident.runId!=="string"||!RUN.test(ident.runId)||
     !same(proposal.identity,ident)||
     !HASH.test(source?.manifestSha256??"")||
     proposal.manifestSha256!==source.manifestSha256||
     report.privacy?.rawRecordsIncluded!==false||
     report.privacy?.personalIdentifiersIncluded!==false||
     report.privacy?.remoteArgumentsIncluded!==false||
     report.coverage?.causalValidation!==false||
     report.coverage?.mechanicsReconstructed!==0||
     report.mission?.missionId!==proposal.missionId||
     report.mission?.toolId!==proposal.toolId){
    throw new Error("Fonte de observacao nao autorizada ou nao saneada.");
  }
  const spec=TOOL_SPECS[proposal.toolId];
  if(!spec||proposal.params.durationSeconds!==spec.durationSeconds||
     proposal.executable!==false||proposal.approved!==false||
     proposal.approvalRequired!==true){
    throw new Error("Ferramenta fora do catalogo seguro.");
  }
  const refs=report.observations?.evidenceRefs?.[spec.observationKind];
  const count=report.observations?.kindCounts?.[spec.observationKind];
  if(!Array.isArray(refs)||refs.length>5||
     !Number.isSafeInteger(count)||count<1||count>3120000||
     proposal.evidenceRefs.length>spec.maxEvidenceRefs||
     proposal.evidenceRefs.some(ref=>
       typeof ref!=="string"||!REF.test(ref)||!refs.includes(ref)||
       !ref.startsWith("v3:"+ident.gameId+":"+ident.placeId+":"+ident.runId+":"))){
    throw new Error("Metadados ou evidencias nao correspondem a fonte.");
  }
  return spec;
}

function validSimulatedTicket(verification,proposal){
  return exact(verification,["verified","mode","missionId","identity"])&&
    verification.verified===true&&verification.mode==="SYNTHETIC_TEST_ONLY"&&
    verification.missionId===proposal.missionId&&
    exact(verification.identity,["gameId","placeId","runId"])&&
    same(verification.identity,proposal.identity);
}

/**
 * Safe future tool protocol: this function CANNOT operate on a game.
 * No network, no Lua, no Roblox service, no captured raw arguments.
 * A fixture verifier is for tests only and is never a real user approval.
 */
export function createOfflineCollectorSandbox({
  proposal,report,verifyTestFixture,nowMs=()=>Date.now()
}={}){
  const spec=validateCollectorSandboxSource(proposal,report);
  if(typeof verifyTestFixture!=="function"||typeof nowMs!=="function"){
    throw new Error("Simulador exige fonte de autorizacao de fixture.");
  }
  const results=new Map(),events=[];
  let busy=false;
  const previewCount=Math.min(report.observations.kindCounts[spec.observationKind],1000);
  const refs=[...proposal.evidenceRefs];
  const session={...proposal.identity};
  const snapshot=()=>({
    mode:"SYNTHETIC_TEST_ONLY",maxTrials:MAX_TRIALS,
    trialCount:results.size,maxTotalDurationSeconds:MAX_SECONDS,
    simulatedDurationSeconds:results.size*spec.durationSeconds,
    realToolExecutions:0,robloxConnected:false,
    approvalForLiveTools:false,events:events.map(copy)
  });

  async function simulate({requestId,ticket}={}){
    if(!REQUEST.test(requestId??"")||!isMs(nowMs())||
       nowMs()<proposal.issuedAtMs||nowMs()>=proposal.expiresAtMs){
      throw new Error("Solicitacao de simulacao invalida ou expirada.");
    }
    if(busy)throw new Error("SIMULATOR_BUSY");
    busy=true;
    try{
      // Always verify, including idempotent requests. Never persist ticket.
      const verification=await verifyTestFixture(ticket,copy(proposal.identity));
      if(!validSimulatedTicket(verification,proposal)){
        throw new Error("Sem autorizacao de teste sintetico.");
      }
      if(results.has(requestId))return copy(results.get(requestId));
      if(results.size>=MAX_TRIALS ||
         (results.size+1)*spec.durationSeconds>MAX_SECONDS){
        throw new Error("Orcamento de simulacao esgotado.");
      }
      const ordinal=results.size+1;
      const output={
        schemaVersion:1,type:"cafeina_collector_simulation_result",
        mode:"SYNTHETIC_METADATA_PREVIEW",
        trialId:requestId,missionId:proposal.missionId,
        identity:{...session},
        toolId:spec.toolId,observationKind:spec.observationKind,
        observedRecordCountCapped:previewCount,
        countCappedAt:1000,evidenceRefs:[...refs],
        durationBudgetSeconds:spec.durationSeconds,
        simulatedTrialsUsed:ordinal,simulatedTrialsRemaining:MAX_TRIALS-ordinal,
        provenanceHash:createHash("sha256").update(
          [proposal.missionId,sourceHash(),requestId].join(":")
        ).digest("hex"),
        validation:"OBSERVATION_ONLY_CAUSALITY_NOT_PROVEN",
        approvedForRealExecution:false,executedInRoblox:false,
        realToolExecutions:0,activeRemoteCalls:0,
        untrustedPlayerContentIncluded:false
      };
      results.set(requestId,output);
      events.push({
        sequence:ordinal,kind:"SYNTHETIC_PREVIEW",
        trialId:requestId,toolId:spec.toolId,
        durationBudgetSeconds:spec.durationSeconds,
        executedInRoblox:false
      });
      return copy(output);
    }finally{
      busy=false;
    }
  }
  function sourceHash(){return report.sources.manifestSha256;}
  function dispatchLiveTool(){
    throw new Error("LIVE_COLLECTOR_EXECUTION_DISABLED");
  }
  return Object.freeze({simulate,snapshot,dispatchLiveTool});
}
