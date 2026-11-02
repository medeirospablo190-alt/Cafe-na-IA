import {Buffer} from "node:buffer";
import {validateMenuProposal} from "./menu-proposal.mjs";
import {validateMenuDeliveryState,applyMenuDeliveryEvent} from "./menu-delivery-state.mjs";

export const RECEIPT_BRANCH="cafeina-ai-knowledge";
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const SHA=/^[a-f0-9]{40}$/;
const MAX_BYTES=4096;
function urlFor(repository,branch,proposal){
  validateMenuProposal(proposal);
  if(typeof repository!=="string"||!REPO.test(repository)||branch!==RECEIPT_BRANCH){
    throw new Error("Destino de recibos GitHub nao permitido.");
  }
  return "https://api.github.com/repos/"+repository+"/contents/ai-core/menu-receipts/"+
    proposal.identity.gameId+"/"+proposal.missionId+".json";
}
function headers(token){
  return {
    Accept:"application/vnd.github+json",
    "X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"cafeina-ai-menu-receipts",
    ...(token?{Authorization:"Bearer "+token}:{})
  };
}

/** Read with no mutation; all remote metadata is validated and bound to the proposal. */
export async function readGithubMenuDelivery({
  repository,proposal,branch=RECEIPT_BRANCH,token="",request=fetch
}){
  const url=urlFor(repository,branch,proposal);
  const response=await request(url+"?ref="+encodeURIComponent(branch),{
    method:"GET",headers:headers(token)
  });
  if(response.status===404)return {status:"MISSING",state:null,sha:null};
  if(response.status!==200)throw new Error("GitHub receipt GET HTTP "+response.status);
  const data=await response.json();
  if(data?.type!=="file"||data.encoding!=="base64"||
     typeof data.sha!=="string"||!SHA.test(data.sha)||
     typeof data.content!=="string"||data.content.length>7000||
     !/^[A-Za-z0-9+/=\s]+$/.test(data.content)){
    throw new Error("GitHub receipt response invalid.");
  }
  const buffer=Buffer.from(data.content.replace(/\s+/g,""),"base64");
  if(buffer.length>MAX_BYTES)throw new Error("GitHub receipt exceeds size limit.");
  const state=validateMenuDeliveryState(JSON.parse(buffer.toString("utf8")),proposal);
  return {status:"FOUND",state,sha:data.sha};
}

/**
 * Opt-in server-side storage of events only. PUT never accepts arbitrary state.
 * A revision conflict causes bounded reload and recomputation of the event.
 */
export async function syncGithubMenuDeliveryEvent({
  repository,proposal,event,nowMs=Date.now(),
  branch=RECEIPT_BRANCH,token="",dryRun=true,request=fetch,maxAttempts=3
}){
  const url=urlFor(repository,branch,proposal);
  if(!dryRun&&(!token||typeof token!=="string")){
    throw new Error("Publicacao exige token de servidor.");
  }
  if(!Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>3){
    throw new Error("Tentativas de recibo invalidas.");
  }
  for(let attempt=0;attempt<maxAttempts;attempt++){
    const remote=await readGithubMenuDelivery({repository,proposal,branch,token,request});
    const next=applyMenuDeliveryEvent(remote.state,proposal,event,{nowMs});
    if(next.status==="UNCHANGED"){
      return {status:"UNCHANGED",published:false,revision:next.state.revision,
        deliveryStatus:next.state.status,missionId:proposal.missionId};
    }
    const serialized=JSON.stringify(next.state,null,2)+"\n";
    if(Buffer.byteLength(serialized)>MAX_BYTES){
      throw new Error("Recibo excede limite de tamanho.");
    }
    if(dryRun)return {
      status:"DRY_RUN",published:false,revision:next.state.revision,
      deliveryStatus:next.state.status,missionId:proposal.missionId
    };
    const response=await request(url,{
      method:"PUT",
      headers:{...headers(token),"Content-Type":"application/json"},
      body:JSON.stringify({
        message:"CAFEINA AI non-execution receipt "+proposal.missionId,
        content:Buffer.from(serialized).toString("base64"),
        branch,
        ...(remote.sha?{sha:remote.sha}:{})
      })
    });
    if(response.ok)return {
      status:"SAVED",published:true,revision:next.state.revision,
      deliveryStatus:next.state.status,missionId:proposal.missionId
    };
    if(response.status===409||response.status===422){
      if(attempt+1<maxAttempts)continue;
      throw new Error("CONFLICT: concurrent receipt update.");
    }
    throw new Error("GitHub receipt PUT HTTP "+response.status);
  }
  throw new Error("Recibo nao persistido.");
}
