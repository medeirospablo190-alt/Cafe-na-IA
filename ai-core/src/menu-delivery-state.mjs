import {createHash} from "node:crypto";
import {validateMenuProposal,menuReceipt,validateMenuReceipt} from "./menu-proposal.mjs";

const STATUS=new Set(["QUEUED","DELIVERED","ACKNOWLEDGED","CLOSED_NO_EXECUTION"]);
const OUTCOME=new Set(["DECLINED","NOT_EXECUTED"]);
const FIELDS=["schemaVersion","type","mode","missionId","identity","proposalSha256",
  "issuedAtMs","expiresAtMs","revision","status","deliveredAtMs","acknowledgedAtMs",
  "completedAtMs","outcome","approved","executed"];
function exact(o,fields){return o!==null&&typeof o==="object"&&!Array.isArray(o)&&
  Object.keys(o).length===fields.length&&fields.every(k=>Object.hasOwn(o,k));}
function validTime(t){return Number.isSafeInteger(t)&&t>=0;}
function sameIdentity(a,b){return a.gameId===b.gameId&&a.placeId===b.placeId&&a.runId===b.runId;}
function digest(proposal){return createHash("sha256").update(JSON.stringify(proposal)).digest("hex");}

export function createMenuDeliveryState(proposal){
  validateMenuProposal(proposal);
  return {
    schemaVersion:1,type:"cafeina_ai_menu_delivery_state",mode:"SIMULATOR_ONLY",
    missionId:proposal.missionId,identity:{...proposal.identity},
    proposalSha256:digest(proposal),issuedAtMs:proposal.issuedAtMs,
    expiresAtMs:proposal.expiresAtMs,revision:0,status:"QUEUED",
    deliveredAtMs:null,acknowledgedAtMs:null,completedAtMs:null,
    outcome:null,approved:false,executed:false
  };
}
export function validateMenuDeliveryState(state,proposal){
  validateMenuProposal(proposal);
  if(!exact(state,FIELDS)||state.schemaVersion!==1||
     state.type!=="cafeina_ai_menu_delivery_state"||state.mode!=="SIMULATOR_ONLY"||
     state.missionId!==proposal.missionId||
     !exact(state.identity,["gameId","placeId","runId"])||
     !sameIdentity(state.identity,proposal.identity)||
     state.proposalSha256!==digest(proposal)||
     state.issuedAtMs!==proposal.issuedAtMs||
     state.expiresAtMs!==proposal.expiresAtMs||
     !Number.isInteger(state.revision)||state.revision<0||state.revision>3||
     !STATUS.has(state.status)||state.approved!==false||state.executed!==false){
    throw new Error("Estado de entrega invalido.");
  }
  for(const timestamp of ["deliveredAtMs","acknowledgedAtMs","completedAtMs"]){
    const t=state[timestamp];
    if(t!==null&&(!validTime(t)||t<state.issuedAtMs||t>=state.expiresAtMs)){
      throw new Error("Timestamp de entrega invalido.");
    }
  }
  const d=state.deliveredAtMs,a=state.acknowledgedAtMs,c=state.completedAtMs;
  if((state.status==="QUEUED"&&(state.revision!==0||d!==null||a!==null||c!==null||state.outcome!==null))||
     (state.status==="DELIVERED"&&(state.revision!==1||d===null||a!==null||c!==null||state.outcome!==null))||
     (state.status==="ACKNOWLEDGED"&&(state.revision!==2||d===null||a===null||c!==null||state.outcome!==null))||
     (state.status==="CLOSED_NO_EXECUTION"&&(state.revision!==3||d===null||a===null||c===null||!OUTCOME.has(state.outcome)))||
     (a!==null&&a<d)||(c!==null&&c<a)){
    throw new Error("Historico de entrega inconsistente.");
  }
  return state;
}

/** Applies one whitelisted event. A duplicate is a no-op; a conflicting final result fails. */
export function applyMenuDeliveryEvent(previous,proposal,event,{nowMs=Date.now()}={}){
  validateMenuProposal(proposal);
  if(!["DELIVERED","RECEIVED","DECLINED","NOT_EXECUTED"].includes(event)||
     !validTime(nowMs)||nowMs<proposal.issuedAtMs||nowMs>=proposal.expiresAtMs){
    throw new Error("Evento expirado ou nao permitido.");
  }
  const state=validateMenuDeliveryState(previous??createMenuDeliveryState(proposal),proposal);
  if(event==="DELIVERED"){
    if(state.deliveredAtMs!==null)return {status:"UNCHANGED",state};
    return {status:"UPDATED",state:validateMenuDeliveryState({
      ...state,revision:1,status:"DELIVERED",deliveredAtMs:nowMs
    },proposal)};
  }
  // Client-derived messages are accepted only as non-executing receipts.
  validateMenuReceipt(menuReceipt(proposal,event),proposal,{nowMs});
  if(event==="RECEIVED"){
    if(state.acknowledgedAtMs!==null)return {status:"UNCHANGED",state};
    if(state.status!=="DELIVERED")throw new Error("ACK_REQUIRED_DELIVERY");
    return {status:"UPDATED",state:validateMenuDeliveryState({
      ...state,revision:2,status:"ACKNOWLEDGED",acknowledgedAtMs:nowMs
    },proposal)};
  }
  if(state.status==="CLOSED_NO_EXECUTION"){
    if(state.outcome===event)return {status:"UNCHANGED",state};
    throw new Error("CONFLICT: resposta final divergente.");
  }
  if(state.status!=="ACKNOWLEDGED")throw new Error("ACK_REQUIRED_BEFORE_REPORT");
  return {status:"UPDATED",state:validateMenuDeliveryState({
    ...state,revision:3,status:"CLOSED_NO_EXECUTION",
    completedAtMs:nowMs,outcome:event
  },proposal)};
}
