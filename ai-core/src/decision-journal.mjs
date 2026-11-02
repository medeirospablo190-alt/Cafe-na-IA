import {createHash} from "node:crypto";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import path from "node:path";

const ID=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const CONVERSATION=/^conversation-[a-f0-9]{16}$/;
const UNKNOWN=new Set([
  "CAUSALITY_NOT_PROVEN","GUI_TRANSITION_UNVERIFIED","BATCH_COUNT_UNREPORTED",
  "MISSING_BATCHES","NO_OBSERVATIONS"
]);
const TOOL=new Set(["none","watch_state","observe_gui"]);
const ROLES=["Investigadora","Critica","Pesquisadora","Coordenadora"];
const KIND=["EVIDENCE_REVIEW","QUALITY_GATE","RESEARCH_PROPOSAL","DECISION","MODEL_ADVISORY"];
function validList(list,max,set){
  return Array.isArray(list)&&list.length<=max&&list.every(x=>set.has(x));
}

/**
 * Minimizes a conversation before it is persisted. Only hand-picked numeric,
 * boolean and enum fields survive. Never store LLM prose, player data or prompts.
 */
export function sanitizeConversation(conversation){
  if(!conversation||conversation.type!=="cafeina_ai_agent_conversation"||
     !["DETERMINISTIC_REHEARSAL","MODEL_ASSISTED_REHEARSAL"].includes(conversation.mode)||
     !CONVERSATION.test(conversation.conversationId??"")||
     conversation.codeGenerated!==false||conversation.evidenceValidated!==false||
     conversation.proposedMission?.executable===true||
     conversation.budgets?.toolExecutions!==0||
     !Number.isInteger(conversation.budgets.modelCalls)||
     conversation.budgets.modelCalls<0||conversation.budgets.modelCalls>1){
    throw new Error("Conversa nao confiavel.");
  }
  const id=conversation.identity??{};
  if(typeof id.gameId!=="string"||!ID.test(id.gameId)||
     typeof id.placeId!=="string"||!ID.test(id.placeId)||
     typeof id.runId!=="string"||!RUN.test(id.runId)){
    throw new Error("Identidade de conversa invalida.");
  }
  if(!Array.isArray(conversation.messages)||
     conversation.messages.length<1||conversation.messages.length>5){
    throw new Error("Mensagens excessivas ou ausentes.");
  }
  const messages=conversation.messages.map((m,i)=>{
    if(!m||m.step!==i+1||typeof m.role!=="string"||
       !ROLES.includes(m.role)||!KIND.includes(m.kind)){
      throw new Error("Mensagem de agente invalida.");
    }
    if(i<4 && (m.role!==ROLES[i]||m.kind!==KIND[i])){
      throw new Error("Ordem de agentes invalida.");
    }
    const d=m.detail??{};
    let fields;
    switch(m.kind){
      case "EVIDENCE_REVIEW":
        if(!validList(d.unknownCodes,10,UNKNOWN)||
           !Number.isSafeInteger(d.observedRecords)||d.observedRecords<0||
           d.source!=="sanitized-session-report")throw new Error("Evidencia invalida.");
        fields={unknownCodes:[...d.unknownCodes],observedRecords:d.observedRecords};
        break;
      case "QUALITY_GATE":
        if(d.causalProof!=="NOT_VERIFIED"||
           typeof d.coverageComplete!=="boolean"||
           d.action!=="REQUEST_MORE_EVIDENCE")throw new Error("Qualidade invalida.");
        fields={causalProof:"NOT_VERIFIED",coverageComplete:d.coverageComplete};
        break;
      case "RESEARCH_PROPOSAL":
        if(d.missionId!==null && !/^mission-[a-f0-9]{16}$/.test(d.missionId??"")){
          throw new Error("Missao invalida.");
        }
        if(d.toolId!==null&&!TOOL.has(d.toolId))throw new Error("Ferramenta invalida.");
        if(d.risk!=="PASSIVE_ONLY"||d.requiresUserApproval!==true){
          throw new Error("Permissao invalida.");
        }
        fields={missionId:d.missionId,toolId:d.toolId,approvalRequired:true};
        break;
      case "DECISION":
        if(!["WAITING_USER","WAITING_EVIDENCE"].includes(d.status)||
           d.executionAllowed!==false||
           !["REVIEW_PASSIVE_MISSION","COLLECT_MORE_CONTEXT"].includes(d.nextStep)){
          throw new Error("Decisao invalida.");
        }
        fields={status:d.status,executionAllowed:false,nextStep:d.nextStep};
        break;
      case "MODEL_ADVISORY":
        if(!UNKNOWN.has(d.unknownCode)||!TOOL.has(d.recommendation)||
           typeof d.accepted!=="boolean"||
           d.verification!=="EXPERIMENTAL"||d.executable!==false){
          throw new Error("Conselho do modelo invalido.");
        }
        fields={unknownCode:d.unknownCode,recommendation:d.recommendation,
          accepted:d.accepted,verification:"EXPERIMENTAL",executable:false};
        break;
    }
    return {step:m.step,role:m.role,kind:m.kind,detail:fields};
  });
  if(conversation.mode==="MODEL_ASSISTED_REHEARSAL" && 
    (messages.length!==5||messages.at(-1).kind!=="MODEL_ADVISORY"||
      conversation.budgets.modelCalls!==1)){
    throw new Error("Rodada com modelo inconsistente.");
  }
  if(conversation.mode==="DETERMINISTIC_REHEARSAL" &&
    conversation.budgets.modelCalls!==0){
    throw new Error("Contagem de modelos inconsistente.");
  }
  const record={
    schemaVersion:1,type:"cafeina_ai_decision_journal",
    conversationId:conversation.conversationId,
    mode:conversation.mode,
    identity:{gameId:id.gameId,placeId:id.placeId,runId:id.runId},
    modelCalls:conversation.budgets.modelCalls,
    toolExecutions:0,
    messages
  };
  return {...record,sha256:createHash("sha256")
    .update(JSON.stringify(record)).digest("hex")};
}

export async function saveConversation(directory,conversation){
  const record=sanitizeConversation(conversation);
  const dir=path.resolve(directory,record.identity.gameId);
  await mkdir(dir,{recursive:true,mode:0o700});
  const file=path.join(dir,record.conversationId+"-"+record.mode+".json");
  const contents=JSON.stringify(record,null,2)+"\n";
  try{
    await writeFile(file,contents,{flag:"wx",mode:0o600});
    return {status:"CREATED",file,sha256:record.sha256};
  }catch(error){
    if(error.code!=="EEXIST")throw error;
    const current=await readFile(file,"utf8");
    if(current!==contents)throw new Error("CONFLICT: diario de decisao divergente.");
    return {status:"UNCHANGED",file,sha256:record.sha256};
  }
}
