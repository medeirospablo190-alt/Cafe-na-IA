import {createHash,randomBytes} from "node:crypto";
import {mkdir,readFile,writeFile,rename,unlink,open} from "node:fs/promises";
import path from "node:path";
import {validateMissionProposal} from "./analysis.mjs";

const ID=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const TASK=/^task-[0-9a-f]{16}$/;
const MISSION=/^mission-[0-9a-f]{16}$/;
const SHA=/^[0-9a-f]{64}$/;
const CONVERSATION=/^conversation-[0-9a-f]{16}$/;
const STATES=new Set(["CREATED","RUNNING","WAITING_USER","COMPLETED","FAILED","CANCELLED","EXPIRED"]);
const TERMINAL=new Set(["COMPLETED","FAILED","CANCELLED","EXPIRED"]);
function safeMs(x){return Number.isSafeInteger(x)&&x>=0;}

function expectedConversationId(task){
  return "conversation-"+createHash("sha256")
    .update([task.identity.gameId,task.identity.placeId,task.identity.runId,
      task.sourceManifestSha256].join(":")).digest("hex").slice(0,16);
}
function immutable(task){
  return JSON.stringify([task.taskId,task.identity,task.sourceManifestSha256,
    task.createdAtMs,task.expiresAtMs,task.maxAttempts,task.stepLimit,
    task.executionScope,task.proposedMissionId]);
}
export function validatePlanningTask(task){
  const allowed=["schemaVersion","type","taskId","identity","sourceManifestSha256",
    "createdAtMs","updatedAtMs","expiresAtMs","maxAttempts","attempt","stepLimit",
    "modelCallLimit","usedModelCalls","executionScope","remoteExecutionAllowed",
    "proposedMissionId","status","revision","leaseUntilMs","conversationId","decision","failure"];
  if(!task||typeof task!=="object"||Array.isArray(task)||
     Object.keys(task).length!==allowed.length ||
     Object.keys(task).some(key=>!allowed.includes(key)) ||
     task.schemaVersion!==1||task.type!=="cafeina_ai_planning_task"||
     !TASK.test(task.taskId??"")||!STATES.has(task.status)||
     task.executionScope!=="OFFLINE_METADATA_ONLY"||task.remoteExecutionAllowed!==false||
     task.modelCallLimit!==0||task.usedModelCalls!==0||
     !Number.isInteger(task.maxAttempts)||task.maxAttempts<1||task.maxAttempts>3||
     !Number.isInteger(task.attempt)||task.attempt<0||task.attempt>task.maxAttempts||
     !Number.isInteger(task.stepLimit)||task.stepLimit<1||task.stepLimit>4||
     !Number.isInteger(task.revision)||task.revision<0||
     !safeMs(task.createdAtMs)||!safeMs(task.updatedAtMs)||
     !safeMs(task.expiresAtMs)||task.expiresAtMs<=task.createdAtMs||
     task.updatedAtMs<task.createdAtMs||
     !SHA.test(task.sourceManifestSha256??"")||
     (task.proposedMissionId!==null&&!MISSION.test(task.proposedMissionId??""))){
    throw new Error("Estado da tarefa invalido.");
  }
  if(!task.identity||Object.keys(task.identity).length!==3 ||
    Object.keys(task.identity).some(key=>!["gameId","placeId","runId"].includes(key))){
    throw new Error("Identidade da tarefa nao saneada.");
  }
  const ids=task.identity??{};
  if(typeof ids.gameId!=="string"||!ID.test(ids.gameId)||
     typeof ids.placeId!=="string"||!ID.test(ids.placeId)||
     typeof ids.runId!=="string"||!RUN.test(ids.runId))throw new Error("Identidade da tarefa invalida.");
  if(task.leaseUntilMs!==null&&!safeMs(task.leaseUntilMs))throw new Error("Lease invalido.");
  if(task.conversationId!==null&&!CONVERSATION.test(task.conversationId??""))throw new Error("Conversa invalida.");
  if(task.decision!==null&&!["WAITING_USER","WAITING_EVIDENCE"].includes(task.decision)){
    throw new Error("Decisao invalida.");
  }
  if(task.failure!==null&&!["MAX_ATTEMPTS","CANCELLED_BY_USER","DEADLINE","ANALYSIS_ERROR"].includes(task.failure)){
    throw new Error("Falha invalida.");
  }
  if(task.status==="RUNNING"&&(task.leaseUntilMs===null||task.attempt===0))throw new Error("RUNNING sem lease.");
  if(task.status!=="RUNNING"&&task.leaseUntilMs!==null)throw new Error("Lease fora de RUNNING.");
  if(task.status==="WAITING_USER"&&(task.decision!=="WAITING_USER"||task.conversationId===null)){
    throw new Error("WAITING_USER sem decisao.");
  }
  if(task.status==="COMPLETED"&&(task.decision!=="WAITING_EVIDENCE"||task.conversationId===null)){
    throw new Error("COMPLETED sem decisao.");
  }
  return task;
}
function validateSafeReport(report){
  const identity=report?.identity??{}, source=report?.sources??{};
  if(report?.type!=="cafeina_ai_session_analysis"||report.mode!=="DRY_RUN"||
     report.privacy?.rawRecordsIncluded!==false||
     report.privacy?.personalIdentifiersIncluded!==false||
     report.coverage?.causalValidation!==false||
     typeof identity.gameId!=="string"||!ID.test(identity.gameId)||
     typeof identity.placeId!=="string"||!ID.test(identity.placeId)||
     typeof identity.runId!=="string"||!RUN.test(identity.runId)||
     !SHA.test(source.manifestSha256??"")){
    throw new Error("Relatorio de tarefa nao seguro.");
  }
  if(report.mission) {
    validateMissionProposal(report.mission);
    if(report.mission.gameId!==identity.gameId||
       report.mission.placeId!==identity.placeId||
       report.mission.originatingRunId!==identity.runId)throw new Error("Missao nao corresponde a sessao.");
  }
  return {identity,source,mission:report.mission??null};
}
export function createPlanningTask(report,{nowMs=Date.now(),ttlMs=900000,maxAttempts=2,stepLimit=4}={}){
  const {identity,source,mission}=validateSafeReport(report);
  if(!safeMs(nowMs)||!Number.isSafeInteger(ttlMs)||ttlMs<60000||ttlMs>86400000||
     !Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>3||
     !Number.isInteger(stepLimit)||stepLimit<4||stepLimit>4){
    throw new Error("Limites de tarefa invalidos.");
  }
  const taskId="task-"+createHash("sha256")
    .update([identity.gameId,identity.placeId,identity.runId,source.manifestSha256].join(":"))
    .digest("hex").slice(0,16);
  return validatePlanningTask({
    schemaVersion:1,type:"cafeina_ai_planning_task",taskId,
    identity:{gameId:identity.gameId,placeId:identity.placeId,runId:identity.runId},
    sourceManifestSha256:source.manifestSha256,
    createdAtMs:nowMs,updatedAtMs:nowMs,expiresAtMs:nowMs+ttlMs,
    maxAttempts,attempt:0,stepLimit,modelCallLimit:0,usedModelCalls:0,
    executionScope:"OFFLINE_METADATA_ONLY",remoteExecutionAllowed:false,
    proposedMissionId:mission?.missionId??null,
    status:"CREATED",revision:0,leaseUntilMs:null,
    conversationId:null,decision:null,failure:null
  });
}
function advance(task,patch,nowMs){
  return validatePlanningTask({...task,...patch,revision:task.revision+1,updatedAtMs:nowMs});
}
export function changePlanningTask(task,action,{nowMs=Date.now(),leaseMs=60000,conversation=null}={}){
  validatePlanningTask(task);
  if(!safeMs(nowMs)||nowMs<task.updatedAtMs)throw new Error("Relogio da tarefa invalido.");
  if(TERMINAL.has(task.status))throw new Error("Tarefa terminal imutavel.");
  if(action==="CANCEL"){
    return advance(task,{status:"CANCELLED",leaseUntilMs:null,failure:"CANCELLED_BY_USER"},nowMs);
  }
  if(nowMs>=task.expiresAtMs){
    if(action==="RECOVER")return advance(task,{
      status:"EXPIRED",leaseUntilMs:null,failure:"DEADLINE"
    },nowMs);
    throw new Error("Tarefa expirada; recupere o estado.");
  }
  if(action==="START"){
    if(task.status!=="CREATED")throw new Error("START somente em CREATED.");
    if(!Number.isInteger(leaseMs)||leaseMs<1000||leaseMs>300000){
      throw new Error("Lease fora dos limites.");
    }
    return advance(task,{status:"RUNNING",attempt:task.attempt+1,
      leaseUntilMs:Math.min(task.expiresAtMs,nowMs+leaseMs)},nowMs);
  }
  if(action==="RECOVER"){
    if(task.status!=="RUNNING")return task;
    if(nowMs<task.leaseUntilMs)return task;
    if(task.attempt>=task.maxAttempts)return advance(task,{
      status:"FAILED",leaseUntilMs:null,failure:"MAX_ATTEMPTS"
    },nowMs);
    return advance(task,{status:"CREATED",leaseUntilMs:null},nowMs);
  }
  if(action==="FAIL"){
    if(task.status!=="RUNNING"||nowMs>=task.leaseUntilMs){
      throw new Error("FAIL fora do lease.");
    }
    return advance(task,{status:"FAILED",leaseUntilMs:null,failure:"ANALYSIS_ERROR"},nowMs);
  }
  if(action==="FINISH"){
    if(task.status!=="RUNNING"||nowMs>=task.leaseUntilMs){
      throw new Error("FINISH fora do lease.");
    }
    if(!conversation||conversation.type!=="cafeina_ai_agent_conversation"||
       conversation.mode!=="DETERMINISTIC_REHEARSAL"||
       conversation.budgets?.modelCalls!==0||
       conversation.budgets?.toolExecutions!==0||
       conversation.messages?.length!==4||
       !CONVERSATION.test(conversation.conversationId??"")||
       conversation.conversationId!==expectedConversationId(task)||
       conversation.codeGenerated!==false||
       conversation.evidenceValidated!==false||
       conversation.messages.at(-1)?.role!=="Coordenadora"||
       conversation.messages.at(-1)?.kind!=="DECISION"||
       conversation.messages.at(-1)?.detail?.executionAllowed!==false||
       conversation.identity?.gameId!==task.identity.gameId||
       conversation.identity?.placeId!==task.identity.placeId||
       conversation.identity?.runId!==task.identity.runId||
       conversation.proposedMission?.missionId!== (task.proposedMissionId??undefined) &&
       !(conversation.proposedMission===null&&task.proposedMissionId===null)){
      throw new Error("Conversa nao corresponde a tarefa offline.");
    }
    const decision=conversation.messages.at(-1)?.detail?.status;
    const target=task.proposedMissionId?"WAITING_USER":"WAITING_EVIDENCE";
    if(decision!==target)throw new Error("Decisao da conversa inconsistente.");
    return advance(task,{
      status:task.proposedMissionId?"WAITING_USER":"COMPLETED",
      decision,conversationId:conversation.conversationId,
      leaseUntilMs:null
    },nowMs);
  }
  throw new Error("Transicao de tarefa desconhecida.");
}
function taskPath(root,task){
  return path.join(path.resolve(root),task.identity.gameId,task.taskId+".json");
}

export function validStoredTransition(old,next){
  if(TERMINAL.has(old.status))throw new Error("CONFLICT: tarefa terminal nao pode mudar.");
  if(next.updatedAtMs<old.updatedAtMs ||
     next.revision!==old.revision+1 ||
     next.modelCallLimit!==0 ||next.usedModelCalls!==0 ||
     (next.status!=="RUNNING"&&next.attempt!==old.attempt)){
    throw new Error("CONFLICT: atualizacao nao sequencial.");
  }
  const from=old.status,to=next.status,now=next.updatedAtMs;
  const within=now<old.expiresAtMs;
  if(to==="CANCELLED"){
    if(next.failure!=="CANCELLED_BY_USER")throw new Error("CONFLICT: cancelamento invalido.");
    return;
  }
  if(to==="EXPIRED"){
    if(within || next.failure!=="DEADLINE")throw new Error("CONFLICT: expiracao invalida.");
    return;
  }
  if(from==="CREATED"&&to==="RUNNING"){
    if(!within || next.attempt!==old.attempt+1 ||
       next.leaseUntilMs<=now ||next.leaseUntilMs>old.expiresAtMs||
       next.leaseUntilMs-now>300000||
       next.conversationId!==null||next.decision!==null||next.failure!==null){
      throw new Error("CONFLICT: inicio invalido.");
    }
    return;
  }
  if(from==="RUNNING"&&to==="CREATED"){
    if(now<old.leaseUntilMs || next.attempt!==old.attempt ||
       next.conversationId!==null||next.decision!==null||next.failure!==null){
      throw new Error("CONFLICT: recuperacao invalida.");
    }
    return;
  }
  if(from==="RUNNING"&&to==="FAILED"){
    if(!(next.failure==="ANALYSIS_ERROR"&&now<old.leaseUntilMs&&within ||
         next.failure==="MAX_ATTEMPTS"&&now>=old.leaseUntilMs&&
         old.attempt>=old.maxAttempts)){
      throw new Error("CONFLICT: falha nao justificada.");
    }
    return;
  }
  if(from==="RUNNING"&&["WAITING_USER","COMPLETED"].includes(to)){
    const correct=old.proposedMissionId?"WAITING_USER":"COMPLETED";
    const correctDecision=old.proposedMissionId?"WAITING_USER":"WAITING_EVIDENCE";
    if(to!==correct||now>=old.leaseUntilMs||!within||
       !CONVERSATION.test(next.conversationId??"")||
       next.conversationId!==expectedConversationId(old)||
       next.decision!==correctDecision||next.failure!==null){
      throw new Error("CONFLICT: conclusao invalida.");
    }
    return;
  }
  throw new Error("CONFLICT: transicao de estado proibida.");
}

export function assertTaskUpdate(previous,next){
  validatePlanningTask(next);
  if(previous===null){
    if(next.revision!==0 ||next.status!=="CREATED"){
      throw new Error("CONFLICT: primeira revisao invalida.");
    }
    return true;
  }
  validatePlanningTask(previous);
  if(immutable(previous)!==immutable(next)){
    throw new Error("CONFLICT: identidade de tarefa divergente.");
  }
  validStoredTransition(previous,next);
  return true;
}

export async function savePlanningTask(root,task,{expectedRevision=null}={}){
  validatePlanningTask(task);
  const file=taskPath(root,task);
  await mkdir(path.dirname(file),{recursive:true,mode:0o700});
  const lock=file+".lock";
  const handle=await open(lock,"wx");
  try{
    let old=null;
    try{old=JSON.parse(await readFile(file,"utf8"));}
    catch(e){if(e.code!=="ENOENT")throw e;}
    if(old){
      validatePlanningTask(old);
      if(immutable(old)!==immutable(task))throw new Error("CONFLICT: identidade da tarefa mudou.");
      if(expectedRevision!==null&&old.revision!==expectedRevision){
        throw new Error("CONFLICT: revisao desatualizada.");
      }
      if(JSON.stringify(old)===JSON.stringify(task))return {status:"UNCHANGED",file};
      validStoredTransition(old,task);
    }else if(task.revision!==0||expectedRevision!==null){
      throw new Error("CONFLICT: tarefa ainda nao existe.");
    }
    const temp=file+"."+randomBytes(8).toString("hex")+".tmp";
    try{
      await writeFile(temp,JSON.stringify(task,null,2)+"\n",{flag:"wx",mode:0o600});
      await rename(temp,file);
    }finally{
      await unlink(temp).catch(e=>{if(e.code!=="ENOENT")throw e;});
    }
    return {status:"SAVED",file};
  }finally{
    await handle.close();
    await unlink(lock);
  }
}
export async function loadPlanningTask(root,gameId,taskId){
  if(typeof gameId!=="string"||!ID.test(gameId)||
     typeof taskId!=="string"||!TASK.test(taskId))throw new Error("IDs de leitura invalidos.");
  const file=path.join(path.resolve(root),gameId,taskId+".json");
  const raw=await readFile(file,"utf8");
  if(Buffer.byteLength(raw)>8192)throw new Error("Tarefa armazenada excessiva.");
  const task=validatePlanningTask(JSON.parse(raw));
  if(task.identity.gameId!==gameId||task.taskId!==taskId)throw new Error("Tarefa nao corresponde ao caminho.");
  return task;
}
