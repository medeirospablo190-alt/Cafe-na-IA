import {Buffer} from "node:buffer";
import {validateMenuProposal} from "./menu-proposal.mjs";

export const QUEUE_BRANCH="cafeina-ai-knowledge";
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const GAME=/^[1-9][0-9]{0,19}$/;
const MISSION=/^mission-[a-f0-9]{16}$/;
const SHA=/^[a-f0-9]{40}$/;
const MAX_BYTES=7000;
function urlFor(repository,branch,gameId,missionId){
  if(typeof repository!=="string"||!REPO.test(repository)||
     branch!==QUEUE_BRANCH||typeof gameId!=="string"||!GAME.test(gameId)||
     typeof missionId!=="string"||!MISSION.test(missionId)){
    throw new Error("Destino da fila GitHub nao autorizado.");
  }
  return "https://api.github.com/repos/"+repository+
    "/contents/ai-core/mission-queue/"+gameId+"/"+missionId+".json";
}
function headers(token){
  return {
    Accept:"application/vnd.github+json",
    "X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"cafeina-ai-mission-queue",
    ...(token?{Authorization:"Bearer "+token}:{})
  };
}

export async function readGithubMenuProposal({
  repository,gameId,missionId,branch=QUEUE_BRANCH,token="",request=fetch
}){
  const url=urlFor(repository,branch,gameId,missionId);
  const response=await request(url+"?ref="+encodeURIComponent(branch),{
    method:"GET",headers:headers(token)
  });
  if(response.status===404)return {status:"MISSING",proposal:null,sha:null};
  if(response.status!==200)throw new Error("GitHub queue read HTTP "+response.status);
  const data=await response.json();
  if(data?.type!=="file"||data.encoding!=="base64"||
     typeof data.sha!=="string"||!SHA.test(data.sha)||
     typeof data.content!=="string"||data.content.length>10000||
     !/^[A-Za-z0-9+/=\s]+$/.test(data.content)){
    throw new Error("Conteudo remoto da fila invalido.");
  }
  const raw=Buffer.from(data.content.replace(/\s+/g,""),"base64");
  if(raw.length>MAX_BYTES)throw new Error("Proposta GitHub excessiva.");
  const proposal=validateMenuProposal(JSON.parse(raw.toString("utf8")));
  if(proposal.identity.gameId!==gameId||proposal.missionId!==missionId){
    throw new Error("Proposta remota de outra missao.");
  }
  return {status:"FOUND",proposal,sha:data.sha};
}

/** Default is dry-run. Publishes only immutable, unapproved observation proposals. */
export async function publishGithubMenuProposal({
  repository,proposal,branch=QUEUE_BRANCH,token="",dryRun=true,request=fetch
}){
  validateMenuProposal(proposal);
  const {gameId}=proposal.identity;
  const {missionId}=proposal;
  const url=urlFor(repository,branch,gameId,missionId);
  if(!dryRun&&(!token||typeof token!=="string")){
    throw new Error("Publicacao exige token do GitHub.");
  }
  const serialized=JSON.stringify(proposal,null,2)+"\n";
  if(Buffer.byteLength(serialized)>MAX_BYTES)throw new Error("Proposta excessiva.");
  const remote=await readGithubMenuProposal({
    repository,gameId,missionId,branch,token,request
  });
  if(remote.proposal){
    if(JSON.stringify(remote.proposal)===JSON.stringify(proposal)){
      return {status:"UNCHANGED",published:false,missionId};
    }
    throw new Error("CONFLICT: proposta ja existente e imutavel.");
  }
  if(dryRun)return {status:"DRY_RUN",published:false,missionId};
  const response=await request(url,{
    method:"PUT",
    headers:{...headers(token),"Content-Type":"application/json"},
    body:JSON.stringify({
      message:"CAFEINA AI observation proposal "+missionId,
      content:Buffer.from(serialized).toString("base64"),
      branch
    })
  });
  if(!response.ok){
    if(response.status===409||response.status===422){
      throw new Error("CONFLICT: publicacao simultanea.");
    }
    throw new Error("GitHub queue write HTTP "+response.status);
  }
  return {status:"SAVED",published:true,missionId};
}
