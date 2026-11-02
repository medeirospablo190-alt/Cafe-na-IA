import {validateCollectorPermissionEnvelope} from "./github-collector-permissions.mjs";

const NAMES=Object.freeze({
  watch_state:"Ver metadados de chamadas observadas",
  observe_gui:"Ver metadados da interface observada"
});
function integer(n){return Number.isSafeInteger(n)&&n>=0;}
/**
 * Presentation model only: NO callbacks, code, URLs, tokens or remote actions.
 * Intended for a future user-reviewed screen. It does not authenticate users.
 */
export function buildSyntheticCollectorPermissionView(record,proposal,{
  nowMs=Date.now()
}={}){
  validateCollectorPermissionEnvelope(record,proposal);
  if(!integer(nowMs))throw new Error("Horario de tela invalido.");
  const req=record.request;
  const expired=nowMs>=req.expiresAtMs;
  const decision=record.review?.outcome??null;
  const status=decision==="DENIED"?"DENIED":
    decision==="SIMULATION_ALLOWED"?"TEST_SIMULATION_ALLOWED":
    expired?"EXPIRED":"PENDING_REVIEW";
  const options=status==="PENDING_REVIEW"?
    [
      {code:"DENIED",label:"Recusar o teste"},
      {code:"SIMULATION_ALLOWED",label:"Permitir prévia offline de teste"}
    ]:[];
  return {
    schemaVersion:1,
    type:"cafeina_collector_permission_view",
    mode:"SYNTHETIC_PREVIEW_UI_MODEL",
    missionId:req.missionId,
    requestId:req.requestId,
    toolId:req.toolId,
    title:NAMES[req.toolId],
    status,
    reasonCode:req.reasonCode,
    scope:"SYNTHETIC_PREVIEW_ONLY",
    maxSimulations:req.maxTrials,
    secondsPerSimulation:req.durationSeconds,
    expiresAtMs:req.expiresAtMs,
    choices:options,
    realUserIdentityVerified:false,
    realApprovalAvailable:false,
    canExecuteRobloxTools:false,
    canSendRemoteCommands:false,
    requiresSeparateRealConsent:true,
    displayOnly:true
  };
}
