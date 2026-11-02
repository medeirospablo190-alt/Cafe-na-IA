import {createHash} from "node:crypto";
import {validateMenuProposal} from "./menu-proposal.mjs";

const HASH=/^[a-f0-9]{64}$/;
const REQUEST=/^permission-[a-f0-9]{16}$/;
const REVIEW=/^review-[a-f0-9]{16}$/;
const REQUEST_FIELDS=["schemaVersion","type","requestId","missionId","identity",
  "proposalSha256","toolId","reasonCode","scope","maxTrials","durationSeconds",
  "requestedAtMs","expiresAtMs","status","liveExecutionRequested"];
const REVIEW_FIELDS=["schemaVersion","type","reviewId","requestId","missionId",
  "identity","requestSha256","outcome","scope","reviewedAtMs",
  "authorizedLiveExecution","robloxConnected"];
const REASONS=Object.freeze({
  watch_state:"INSPECT_OBSERVED_REMOTE_METADATA",
  observe_gui:"INSPECT_OBSERVED_GUI_METADATA"
});
const outcomes=new Set(["SIMULATION_ALLOWED","DENIED"]);
const exact=(value,fields)=>value!==null&&typeof value==="object"&&!Array.isArray(value)&&
  Object.keys(value).length===fields.length&&fields.every(x=>Object.hasOwn(value,x));
const timestamp=x=>Number.isSafeInteger(x)&&x>=0;
const equalIdentity=(a,b)=>exact(a,["gameId","placeId","runId"])&&
  a.gameId===b.gameId&&a.placeId===b.placeId&&a.runId===b.runId;
const hash=x=>createHash("sha256").update(JSON.stringify(x)).digest("hex");
const id=(prefix,value)=>prefix+"-"+hash(value).slice(0,16);
const clone=x=>JSON.parse(JSON.stringify(x));

/**
 * An offline-review request, NEVER an authorization to run a live collector.
 * There is no player name, free-form prompt, raw remote arguments or script.
 */
export function createCollectorPermissionRequest(proposal,{
  nowMs=Date.now(),ttlMs=120000
}={}){
  validateMenuProposal(proposal);
  if(!timestamp(nowMs)||nowMs<proposal.issuedAtMs||
     nowMs>=proposal.expiresAtMs||
     !Number.isSafeInteger(ttlMs)||ttlMs<1000||ttlMs>300000){
    throw new Error("Prazo ou momento de revisao invalido.");
  }
  const requestId=id("permission",
    [proposal.missionId,hash(proposal),nowMs].join(":"));
  return validateCollectorPermissionRequest({
    schemaVersion:1,type:"cafeina_collector_permission_request",
    requestId,missionId:proposal.missionId,identity:{...proposal.identity},
    proposalSha256:hash(proposal),toolId:proposal.toolId,
    reasonCode:REASONS[proposal.toolId],scope:"SYNTHETIC_PREVIEW_ONLY",
    maxTrials:2,durationSeconds:proposal.params.durationSeconds,
    requestedAtMs:nowMs,
    expiresAtMs:Math.min(nowMs+ttlMs,proposal.expiresAtMs),
    status:"PENDING_REVIEW",liveExecutionRequested:false
  },proposal);
}
export function validateCollectorPermissionRequest(request,proposal){
  validateMenuProposal(proposal);
  const expectedId=id("permission",
    [proposal.missionId,hash(proposal),request?.requestedAtMs].join(":"));
  if(!exact(request,REQUEST_FIELDS)||
     request.schemaVersion!==1||
     request.type!=="cafeina_collector_permission_request"||
     !REQUEST.test(request.requestId??"")||request.requestId!==expectedId||
     request.missionId!==proposal.missionId||
     !equalIdentity(request.identity,proposal.identity)||
     !HASH.test(request.proposalSha256??"")||
     request.proposalSha256!==hash(proposal)||
     request.toolId!==proposal.toolId||
     request.reasonCode!==REASONS[proposal.toolId]||
     request.scope!=="SYNTHETIC_PREVIEW_ONLY"||
     request.maxTrials!==2||
     request.durationSeconds!==10||
     !timestamp(request.requestedAtMs)||
     request.requestedAtMs<proposal.issuedAtMs||
     !timestamp(request.expiresAtMs)||
     request.expiresAtMs<=request.requestedAtMs||
     request.expiresAtMs>proposal.expiresAtMs||
     request.expiresAtMs-request.requestedAtMs>300000||
     request.status!=="PENDING_REVIEW"||
     request.liveExecutionRequested!==false){
    throw new Error("Solicitacao de permissao fora do contrato.");
  }
  return request;
}

/**
 * The callback must be an independently trusted test operator verifier.
 * An ACK from the menu and untrusted agent text are not operator proof.
 * The resulting record is deliberately NOT a live-execution capability.
 */
export async function reviewCollectorPermission(request,proposal,{
  outcome,operatorEvidence,verifyTestOperator,nowMs=Date.now()
}={}){
  validateCollectorPermissionRequest(request,proposal);
  if(!outcomes.has(outcome)||typeof verifyTestOperator!=="function"||
     !timestamp(nowMs)||nowMs<request.requestedAtMs||
     nowMs>=request.expiresAtMs){
    throw new Error("Revisao nao permitida, vencida ou incompleta.");
  }
  const proof=await verifyTestOperator(operatorEvidence,clone({
    requestId:request.requestId,missionId:request.missionId,
    identity:request.identity,scope:request.scope
  }));
  if(!exact(proof,["verified","mode","requestId","missionId","identity"])||
     proof.verified!==true||proof.mode!=="SYNTHETIC_TEST_OPERATOR"||
     proof.requestId!==request.requestId||
     proof.missionId!==request.missionId||
     !equalIdentity(proof.identity,request.identity)){
    throw new Error("Avaliador offline nao autenticado.");
  }
  const record={
    schemaVersion:1,type:"cafeina_collector_permission_review",
    reviewId:id("review",[request.requestId,outcome,nowMs].join(":")),
    requestId:request.requestId,missionId:request.missionId,
    identity:{...request.identity},requestSha256:hash(request),
    outcome,scope:"SYNTHETIC_PREVIEW_ONLY",
    reviewedAtMs:nowMs,authorizedLiveExecution:false,
    robloxConnected:false
  };
  return validateCollectorPermissionReview(record,request,proposal);
}
export function validateCollectorPermissionReview(review,request,proposal){
  validateCollectorPermissionRequest(request,proposal);
  if(!exact(review,REVIEW_FIELDS)||review.schemaVersion!==1||
     review.type!=="cafeina_collector_permission_review"||
     !REVIEW.test(review.reviewId??"")||
     !outcomes.has(review.outcome)||
     review.reviewId!==id("review",
       [request.requestId,review.outcome,review.reviewedAtMs].join(":"))||
     review.requestId!==request.requestId||
     review.missionId!==request.missionId||
     !equalIdentity(review.identity,request.identity)||
     !HASH.test(review.requestSha256??"")||
     review.requestSha256!==hash(request)||
     !timestamp(review.reviewedAtMs)||
     review.reviewedAtMs<request.requestedAtMs||
     review.reviewedAtMs>=request.expiresAtMs||
     review.scope!=="SYNTHETIC_PREVIEW_ONLY"||
     review.authorizedLiveExecution!==false||
     review.robloxConnected!==false){
    throw new Error("Registro de revisao fora do contrato.");
  }
  return review;
}

/** Audit only. Never persists credentials, user IDs or untrusted messages. */
export function summarizeCollectorPermissionAudit(request,review,proposal){
  validateCollectorPermissionReview(review,request,proposal);
  return {
    schemaVersion:1,type:"cafeina_collector_permission_audit",
    missionId:request.missionId,requestId:request.requestId,
    reviewId:review.reviewId,toolId:request.toolId,
    outcome:review.outcome,scope:"SYNTHETIC_PREVIEW_ONLY",
    requestedAtMs:request.requestedAtMs,reviewedAtMs:review.reviewedAtMs,
    approvedForLiveTools:false,realToolExecutions:0
  };
}


/**
 * Optional adapter for the OFFLINE sandbox only. Review records are NOT bearer
 * tokens and a copied JSON review is insufficient. Every simulated call checks
 * an independently trusted test registry callback and the short-lived scope.
 * Never use this as an authorization gate for real collectors or Roblox tools.
 */
export function createSyntheticReviewFixtureVerifier({
  request,proposal,review,verifyTrustedReview,nowMs=()=>Date.now()
}={}){
  validateCollectorPermissionReview(review,request,proposal);
  if(typeof verifyTrustedReview!=="function"||typeof nowMs!=="function"){
    throw new Error("Registro de revisao confiavel de teste obrigatorio.");
  }
  const captured=clone(review);
  const req=clone(request);
  const safeIdentity={...proposal.identity};
  return async ticket=>{
    if(captured.outcome!=="SIMULATION_ALLOWED"||!timestamp(nowMs())||
       nowMs()<captured.reviewedAtMs||nowMs()>=req.expiresAtMs){
      return null;
    }
    try{
      validateCollectorPermissionReview(ticket,req,proposal);
    }catch{
      return null;
    }
    if(JSON.stringify(ticket)!==JSON.stringify(captured))return null;
    let state;
    try{
      state=await verifyTrustedReview({
        requestId:req.requestId,reviewId:captured.reviewId,
        missionId:req.missionId,scope:req.scope
      });
    }catch{
      return null;
    }
    if(!exact(state,["verified","mode","requestId","reviewId","missionId","scope"])||
       state.verified!==true||
       state.mode!=="SYNTHETIC_TEST_REVIEW_REGISTRY"||
       state.requestId!==req.requestId||
       state.reviewId!==captured.reviewId||
       state.missionId!==req.missionId||
       state.scope!=="SYNTHETIC_PREVIEW_ONLY"){
      return null;
    }
    return {
      verified:true,mode:"SYNTHETIC_TEST_ONLY",
      missionId:req.missionId,identity:{...safeIdentity}
    };
  };
}
