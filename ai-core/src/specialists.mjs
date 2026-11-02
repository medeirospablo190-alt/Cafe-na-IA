import {createHash} from "node:crypto";
import {validatePlanningTask} from "./task-engine.mjs";

const UNKNOWN=new Set([
  "CAUSALITY_NOT_PROVEN","GUI_TRANSITION_UNVERIFIED","BATCH_COUNT_UNREPORTED",
  "MISSING_BATCHES","NO_OBSERVATIONS"
]);
const REF=/^v3:[1-9][0-9]*:[1-9][0-9]*:[A-Za-z0-9_-]{6,128}:[0-9]+:[0-9]+$/;
function safeEvidence(report){
  if(report?.type!=="cafeina_ai_session_analysis"||
     report.mode!=="DRY_RUN"||
     report.privacy?.rawRecordsIncluded!==false||
     report.privacy?.personalIdentifiersIncluded!==false||
     report.privacy?.remoteArgumentsIncluded!==false||
     report.coverage?.causalValidation!==false ||
     report.coverage?.mechanicsReconstructed!==0 ||
     !Array.isArray(report.unknowns) || report.unknowns.length>10){
    throw new Error("Evidencia de especialistas nao saneada.");
  }
  const refs=[];
  const issues=[];
  for(const unknown of report.unknowns){
    if(!UNKNOWN.has(unknown?.code) ||
       !Array.isArray(unknown.evidenceRefs) ||unknown.evidenceRefs.length>3||
       unknown.evidenceRefs.some(ref=>typeof ref!=="string"||!REF.test(ref))){
      throw new Error("Referencias de especialistas invalidas.");
    }
    issues.push(unknown.code);
    for(const ref of unknown.evidenceRefs){
      if(refs.length<8 && !refs.includes(ref))refs.push(ref);
    }
  }
  return {unknownCodes:[...new Set(issues)].sort(),evidenceRefs:refs};
}
/**
 * No LLM, Roblox executor, code generator or reverse-engineering provider is used.
 * This is a deterministic safety gate preparing only typed, evidence-linked work.
 */
export function draftSpecialistPlan(report,task){
  validatePlanningTask(task);
  if(task.status!=="WAITING_USER" && task.status!=="COMPLETED"){
    throw new Error("Tarefa nao passou pela etapa de planejamento.");
  }
  const identity=report?.identity??{};
  if(identity.gameId!==task.identity.gameId ||
     identity.placeId!==task.identity.placeId ||
     identity.runId!==task.identity.runId ||
     report.sources?.manifestSha256!==task.sourceManifestSha256){
    throw new Error("Fontes da tarefa e do relatorio divergem.");
  }
  const {unknownCodes,evidenceRefs}=safeEvidence(report);
  const planId="spec-"+createHash("sha256")
    .update([task.taskId,task.conversationId].join(":"))
    .digest("hex").slice(0,16);
  const tests=[
    {check:"REPLAY_OBSERVATIONS",status:"PENDING"},
    {check:"COMPARE_BEHAVIOR",status:"PENDING"},
    {check:"VERIFY_SERVER_CAUSALITY",status:"PENDING"}
  ];
  if(report.coverage?.completeBatchSequence!==true){
    tests.unshift({check:"COMPLETE_COLLECTION",status:"PENDING"});
  }
  return {
    schemaVersion:1,type:"cafeina_ai_specialist_plan",mode:"READ_ONLY_DRAFT",
    planId,taskId:task.taskId,
    identity:{...task.identity},
    sourceManifestSha256:task.sourceManifestSha256,
    unknownCodes,evidenceRefs,
    specialists:[
      {
        role:"Arquiteta",status:"REQUIRES_VERIFIED_REQUIREMENTS",
        decision:"SPEC_NOT_YET_PROVEN"
      },{
        role:"Programadora",status:"BLOCKED",
        decision:"NO_CODE_WITHOUT_VALIDATED_SPEC"
      },{
        role:"Testadora",status:"TEST_DESIGN_ONLY",
        decision:"COMPARATIVE_TESTS_NOT_RUN"
      }
    ],
    verification:"EXPERIMENTAL",
    tests,generatedCode:null,
    codeGenerated:false,testsExecuted:0,modelCalls:0,toolExecutions:0,
    nextAction:task.status==="WAITING_USER"?
      "REQUEST_HUMAN_REVIEW_OF_PASSIVE_MISSION":"COLLECT_ADDITIONAL_EVIDENCE",
    limitations:[
      "Papéis determinísticos; não são três modelos adicionais.",
      "Sem evidência causal validada, geração de código e execução ficam bloqueadas.",
      "Somente experiências próprias ou autorizadas poderão receber testes ativos futuros."
    ]
  };
}
