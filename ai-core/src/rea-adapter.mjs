import {createHash} from "node:crypto";

const GAME=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const HASH=/^[a-f0-9]{64}$/;
const REF=/^v3:[1-9][0-9]*:[1-9][0-9]*:[A-Za-z0-9_-]{6,128}:[0-9]+:[0-9]+$/;
const UNKNOWNS=new Set([
  "CAUSALITY_NOT_PROVEN","GUI_TRANSITION_UNVERIFIED","BATCH_COUNT_UNREPORTED",
  "MISSING_BATCHES","NO_OBSERVATIONS"
]);

function requireReport(report){
  if(report?.schemaVersion!==1||report.type!=="cafeina_ai_session_analysis"||
     report.mode!=="DRY_RUN"||report.privacy?.rawRecordsIncluded!==false||
     report.privacy?.personalIdentifiersIncluded!==false||
     report.privacy?.remoteArgumentsIncluded!==false||
     report.coverage?.causalValidation!==false||
     report.coverage?.mechanicsReconstructed!==0){
    throw new Error("REA handoff requer relatorio V3 saneado.");
  }
  const id=report.identity??{};
  if(typeof id.gameId!=="string"||!GAME.test(id.gameId)||
     typeof id.placeId!=="string"||!GAME.test(id.placeId)||
     typeof id.runId!=="string"||!RUN.test(id.runId)||
     !HASH.test(report.sources?.manifestSha256??"")){
    throw new Error("Identidade da evidencia invalida.");
  }
  if(!Array.isArray(report.unknowns)||report.unknowns.length>10){
    throw new Error("Desconhecidos excessivos.");
  }
  return id;
}

/**
 * A handoff for REA planning, not a REA Evidence import.
 * CAFEÍNA hashes and v3 refs are NOT REA authenticated Evidence IDs.
 */
export function prepareReaHandoff(report){
  const id=requireReport(report);
  const pending=[];
  const seen=new Set();
  for(const item of report.unknowns){
    if(!UNKNOWNS.has(item?.code)||seen.has(item.code)||
       !Array.isArray(item.evidenceRefs)||item.evidenceRefs.length>3||
       item.evidenceRefs.some(ref=>typeof ref!=="string"||!REF.test(ref)||
         !ref.startsWith("v3:"+id.gameId+":"+id.placeId+":"+id.runId+":"))){
      throw new Error("REA handoff nao aceita provas nao verificadas.");
    }
    seen.add(item.code);
    pending.push({
      code:item.code,
      status:"NEEDS_AUTHENTICATED_REA_EVIDENCE",
      sourceRefs:[...item.evidenceRefs],
      verification:"EXPERIMENTAL",
      requiredAction:"MANUAL_REVIEW_OR_AUTHORIZED_COMPARATIVE_TEST"
    });
  }
  const seed=[id.gameId,id.placeId,id.runId,report.sources.manifestSha256].join(":");
  return {
    schemaVersion:1,type:"cafeina_rea_handoff",
    handoffId:"rea-handoff-"+createHash("sha256").update(seed).digest("hex").slice(0,16),
    identity:{gameId:id.gameId,placeId:id.placeId,runId:id.runId},
    inputManifestSha256:report.sources.manifestSha256,
    scope:"OBSERVATIONAL_METADATA_ONLY",
    reaEvidenceAuthenticated:false,
    reaLedgerExecuted:false,
    verifiedReconstructionClaims:0,
    comparisonAuthority:"NONE",
    pendingQuestions:pending,
    limitations:[
      "v3:* references identify CAFEINA observations, not REA-authenticated Evidence.",
      "No Roblox server-source or behavioral equivalence can be inferred.",
      "Import to REA requires legitimate Evidence producer records and comparative tests."
    ]
  };
}

/** REA's documented empty-ledger request: always unknown, never verified. */
export function reaEmptyLedgerRequest(){
  return {
    evidence_bundle:{
      artifacts:[],providers:[],environments:[],scenarios:[],
      captures:[],unknowns:[],records:[]
    },
    reviewed_obligations:[],
    manifest:{bindings:[],contradictions:[]}
  };
}
