import {Buffer} from "node:buffer";
import {validateMenuProposal} from "./menu-proposal.mjs";
import {
  validateCollectorPermissionRequest,validateCollectorPermissionReview
} from "./collector-permissions.mjs";

export const COLLECTOR_PERMISSION_BRANCH="cafeina-ai-knowledge";
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const SHA=/^[a-f0-9]{40}$/;
const MAX_BYTES=8192;
const ENVELOPE_FIELDS=["schemaVersion","type","mode","missionId",
  "revision","status","request","review"];
const exact=(value,fields)=>value!==null&&typeof value==="object"&&
  !Array.isArray(value)&&Object.keys(value).length===fields.length&&
  fields.every(f=>Object.hasOwn(value,f));
function endpoint(repository,branch,proposal){
  validateMenuProposal(proposal);
  if(!REPO.test(repository??"")||branch!==COLLECTOR_PERMISSION_BRANCH){
    throw new Error("Destino de permissoes GitHub nao autorizado.");
  }
  return "https://api.github.com/repos/"+repository+
    "/contents/ai-core/collector-permissions/"+proposal.identity.gameId+
    "/"+proposal.missionId+".json";
}
function headers(token){
  return {
    Accept:"application/vnd.github+json",
    "X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"cafeina-ai-synthetic-collector-permissions",
    ...(token?{Authorization:"Bearer "+token}:{})
  };
}
function canonical(o){return JSON.stringify(o);}

/** A closed, versioned, synthetic-only record. No credentials or operator text. */
export function createCollectorPermissionEnvelope(request,proposal){
  validateCollectorPermissionRequest(request,proposal);
  return validateCollectorPermissionEnvelope({
    schemaVersion:1,type:"cafeina_collector_permission_envelope",
    mode:"SYNTHETIC_TEST_ONLY",missionId:proposal.missionId,
    revision:0,status:"PENDING_REVIEW",request,review:null
  },proposal);
}
export function validateCollectorPermissionEnvelope(record,proposal){
  validateMenuProposal(proposal);
  if(!exact(record,ENVELOPE_FIELDS)||
    record.schemaVersion!==1||
    record.type!=="cafeina_collector_permission_envelope"||
    record.mode!=="SYNTHETIC_TEST_ONLY"||
    record.missionId!==proposal.missionId||
    ![0,1].includes(record.revision)||
    !["PENDING_REVIEW","REVIEWED"].includes(record.status)){
    throw new Error("Registro de permissao invalido.");
  }
  validateCollectorPermissionRequest(record.request,proposal);
  if(record.revision===0){
    if(record.status!=="PENDING_REVIEW"||record.review!==null){
      throw new Error("Registro pendente inconsistente.");
    }
  }else{
    if(record.status!=="REVIEWED"){
      throw new Error("Estado final de permissao inconsistente.");
    }
    validateCollectorPermissionReview(record.review,record.request,proposal);
  }
  return record;
}
export function applyCollectorPermissionReview(record,review,proposal){
  validateCollectorPermissionEnvelope(record,proposal);
  validateCollectorPermissionReview(review,record.request,proposal);
  if(record.revision===1){
    if(canonical(record.review)===canonical(review)){
      return {status:"UNCHANGED",record};
    }
    throw new Error("CONFLICT: decisao de permissao ja finalizada.");
  }
  return {status:"UPDATED",record:validateCollectorPermissionEnvelope({
    ...record,revision:1,status:"REVIEWED",review
  },proposal)};
}
/** Read: no GitHub write. All returned fields are revalidated. */
export async function readGithubCollectorPermission({
  repository,proposal,branch=COLLECTOR_PERMISSION_BRANCH,
  token="",request=fetch
}={}){
  const url=endpoint(repository,branch,proposal);
  const response=await request(url+"?ref="+encodeURIComponent(branch),{
    method:"GET",headers:headers(token)
  });
  if(response.status===404)return {status:"MISSING",record:null,sha:null};
  if(response.status!==200)throw new Error("GitHub permissions GET HTTP "+response.status);
  const data=await response.json();
  if(data?.type!=="file"||data.encoding!=="base64"||
     typeof data.sha!=="string"||!SHA.test(data.sha)||
     typeof data.content!=="string"||data.content.length>15000||
     !/^[A-Za-z0-9+/=\s]+$/.test(data.content)){
    throw new Error("Resposta GitHub de permissoes invalida.");
  }
  const raw=Buffer.from(data.content.replace(/\s+/g,""),"base64");
  if(raw.byteLength>MAX_BYTES){
    throw new Error("Registro de permissoes remoto excessivo.");
  }
  const record=validateCollectorPermissionEnvelope(JSON.parse(raw.toString("utf8")),proposal);
  return {status:"FOUND",record,sha:data.sha};
}
/**
 * Opt-in and synthetic-only. Request creation is immutable; final review is a
 * one-time transition. Conflicting updates are re-read with bounded retries.
 * A stored record is NOT proof that a real person approved a Roblox action.
 */
export async function syncGithubCollectorPermission({
  repository,proposal,requestRecord=null,review=null,
  token="",dryRun=true,branch=COLLECTOR_PERMISSION_BRANCH,
  request=fetch,maxAttempts=3
}={}){
  const url=endpoint(repository,branch,proposal);
  if((requestRecord===null)===(review===null)){
    throw new Error("Escolha criar pedido OU registrar revisao.");
  }
  if(!dryRun&&(!token||typeof token!=="string")){
    throw new Error("Publicacao exige token de servidor.");
  }
  if(!Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>3){
    throw new Error("Limite de tentativas de permissoes invalido.");
  }
  let initial;
  if(requestRecord!==null)initial=createCollectorPermissionEnvelope(requestRecord,proposal);
  for(let i=0;i<maxAttempts;i++){
    const remote=await readGithubCollectorPermission({
      repository,proposal,branch,token,request
    });
    let record;
    if(initial){
      if(remote.record!==null){
        if(canonical(remote.record.request)!==canonical(initial.request)){
          throw new Error("CONFLICT: outro pedido ja existe para a missao.");
        }
        // Never regress an existing final review back to PENDING.
        return {status:"UNCHANGED",published:false,
          revision:remote.record.revision,decision:remote.record.review?.outcome??null};
      }
      record=initial;
    }else{
      if(remote.record===null){
        throw new Error("CONFLICT: pedido inexistente.");
      }
      const applied=applyCollectorPermissionReview(remote.record,review,proposal);
      if(applied.status==="UNCHANGED"){
        return {status:"UNCHANGED",published:false,revision:1,
          decision:applied.record.review.outcome};
      }
      record=applied.record;
    }
    const serialized=JSON.stringify(record,null,2)+"\n";
    if(Buffer.byteLength(serialized)>MAX_BYTES)throw new Error("Registro excede limite.");
    if(dryRun){
      return {status:"DRY_RUN",published:false,revision:record.revision,
        decision:record.review?.outcome??null};
    }
    const response=await request(url,{
      method:"PUT",
      headers:{...headers(token),"Content-Type":"application/json"},
      body:JSON.stringify({
        message:"CAFEINA AI synthetic permission "+proposal.missionId,
        content:Buffer.from(serialized).toString("base64"),
        branch,...(remote.sha?{sha:remote.sha}:{})
      })
    });
    if(response.ok){
      return {status:"SAVED",published:true,revision:record.revision,
        decision:record.review?.outcome??null};
    }
    if(response.status===409||response.status===422){
      if(i+1<maxAttempts)continue;
      throw new Error("CONFLICT: atualizacao concorrente recusada.");
    }
    throw new Error("GitHub permissions PUT HTTP "+response.status);
  }
  throw new Error("Permissao sintetica nao sincronizada.");
}
