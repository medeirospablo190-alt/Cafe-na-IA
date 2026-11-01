import {createHash} from "node:crypto";
import {validateMissionProposal} from "./analysis.mjs";

const UNKNOWN=new Set([
  "CAUSALITY_NOT_PROVEN","GUI_TRANSITION_UNVERIFIED",
  "BATCH_COUNT_UNREPORTED","MISSING_BATCHES","NO_OBSERVATIONS"
]);
const evidence=/^v3:[1-9][0-9]*:[1-9][0-9]*:[A-Za-z0-9_-]{6,128}:[0-9]+:[0-9]+$/;
const id=/^[1-9][0-9]{0,19}$/;
function sha(text){return createHash("sha256").update(text).digest("hex").slice(0,16);}
function check(report){
  if(report?.type!=="cafeina_ai_session_analysis"||report.mode!=="DRY_RUN"||
    report.privacy?.rawRecordsIncluded!==false||
    report.privacy?.personalIdentifiersIncluded!==false||
    report.coverage?.causalValidation!==false||
    report.coverage?.mechanicsReconstructed!==0){
    throw new Error("Relatorio nao confiavel.");
  }
  const t=report.identity??{};
  if(!id.test(t.gameId??"")||!id.test(t.placeId??"")||
    typeof t.runId!=="string"||!/^[A-Za-z0-9_-]{6,128}$/.test(t.runId)){
    throw new Error("Identidade invalida.");
  }
  if(!Array.isArray(report.unknowns)||report.unknowns.length>10||
    report.unknowns.some(x=>!UNKNOWN.has(x.code)||
      !Array.isArray(x.evidenceRefs)||x.evidenceRefs.length>3||
      x.evidenceRefs.some(ref=>!evidence.test(ref)))){
    throw new Error("Desconhecidos invalidos.");
  }
  if(report.mission)validateMissionProposal(report.mission);
}
function message(role,kind,detail,step){return {step,role,kind,detail};}
export function coordinateInvestigation(report,{maxSteps=4}={}){
  check(report);
  if(!Number.isInteger(maxSteps)||maxSteps<1||maxSteps>4){
    throw new Error("Limite de etapas invalido.");
  }
  const transcript=[];
  if(maxSteps>=1)transcript.push(message("Investigadora","EVIDENCE_REVIEW",{
    unknownCodes:report.unknowns.map(x=>x.code),
    observedRecords:report.observations.recordCount,
    source:"sanitized-session-report"
  },1));
  if(maxSteps>=2)transcript.push(message("Critica","QUALITY_GATE",{
    causalProof:"NOT_VERIFIED",
    coverageComplete:report.coverage.completeBatchSequence===true,
    action:"REQUEST_MORE_EVIDENCE"
  },2));
  if(maxSteps>=3)transcript.push(message("Pesquisadora","RESEARCH_PROPOSAL",{
    missionId:report.mission?.missionId??null,
    toolId:report.mission?.toolId??null,
    risk:"PASSIVE_ONLY",requiresUserApproval:true
  },3));
  if(maxSteps>=4)transcript.push(message("Coordenadora","DECISION",{
    status:report.mission?"WAITING_USER":"WAITING_EVIDENCE",
    executionAllowed:false,
    nextStep:report.mission?"REVIEW_PASSIVE_MISSION":"COLLECT_MORE_CONTEXT"
  },4));
  const ident=report.identity;
  return {
    schemaVersion:1,type:"cafeina_ai_agent_conversation",
    mode:"DETERMINISTIC_REHEARSAL",
    conversationId:"conversation-"+sha([ident.gameId,ident.placeId,ident.runId,
      report.sources.manifestSha256].join(":")),
    identity:{gameId:ident.gameId,placeId:ident.placeId,runId:ident.runId},
    budgets:{maxSteps,usedSteps:transcript.length,modelCalls:0,toolExecutions:0},
    agents:["Investigadora","Critica","Pesquisadora","Coordenadora"],
    messages:transcript,proposedMission:report.mission??null,
    codeGenerated:false,evidenceValidated:false,
    limitations:[
      "Agentes baseados em regras deterministicas; nenhum modelo de IA conectado.",
      "Nenhuma execucao de ferramentas ou comunicacao com Roblox.",
      "Hipoteses permanecem EXPERIMENTAL ate testes suficientes."
    ]
  };
}
