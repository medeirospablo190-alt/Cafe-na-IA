import {validateMenuProposal} from "./menu-proposal.mjs";
import {validateMenuDeliveryState} from "./menu-delivery-state.mjs";
import {readGithubMenuProposal} from "./github-menu-queue.mjs";
import {readGithubMenuDelivery} from "./github-menu-receipts.mjs";

const REPOSITORY="medeirospablo190-alt/Cafe-na-IA";
const BRANCH="cafeina-ai-knowledge";
const GAME="101";
const PLACE="202";
const SYNTHETIC=/^synthetic-[0-9]{6,16}$/;
const FILE=/^mission-[a-f0-9]{16}\.json$/;
const DAY=86400000;
function validNow(n){return Number.isSafeInteger(n)&&n>=0;}

/**
 * Strictly read-only retention preview. Never delete, rewrite, or mutate.
 * Does not attempt to clean real game sessions or legacy trace history.
 */
export function assessSyntheticMenuRetention(
  proposal,receipt,{nowMs=Date.now(),retentionDays=7}={}
){
  validateMenuProposal(proposal);
  if(receipt!==null)validateMenuDeliveryState(receipt,proposal);
  if(!validNow(nowMs)||!Number.isInteger(retentionDays)||
     retentionDays<7||retentionDays>90){
    throw new Error("Limites da retencao invalidos.");
  }
  const synthetic=proposal.identity.gameId===GAME&&
    proposal.identity.placeId===PLACE&&
    SYNTHETIC.test(proposal.identity.runId);
  if(!synthetic){
    return {status:"OUT_OF_SCOPE",reviewOnly:true};
  }
  if(proposal.expiresAtMs+retentionDays*DAY>nowMs){
    return {status:"NOT_YET_ELIGIBLE",reviewOnly:true};
  }
  if(receipt===null||receipt.status!=="CLOSED_NO_EXECUTION"||
     !["DECLINED","NOT_EXECUTED"].includes(receipt.outcome)||
     receipt.executed!==false||receipt.approved!==false){
    return {status:"REQUIRES_REVIEW",reviewOnly:true};
  }
  return {status:"ELIGIBLE_FOR_MANUAL_REVIEW",reviewOnly:true};
}

export async function scanSyntheticMenuRetention({
  repository=REPOSITORY,branch=BRANCH,token="",request=fetch,
  nowMs=Date.now(),retentionDays=7
}={}){
  if(repository!==REPOSITORY||branch!==BRANCH||
     !validNow(nowMs)||!Number.isInteger(retentionDays)||
     retentionDays<7||retentionDays>90){
    throw new Error("Consulta de retencao fora do escopo.");
  }
  const url="https://api.github.com/repos/"+repository+
    "/contents/ai-core/mission-queue/"+GAME+
    "?ref="+encodeURIComponent(branch);
  const response=await request(url,{
    method:"GET",
    headers:{
      Accept:"application/vnd.github+json",
      "X-GitHub-Api-Version":"2022-11-28",
      "User-Agent":"cafeina-ai-retention-read-only",
      ...(token?{Authorization:"Bearer "+token}:{})
    }
  });
  if(response.status===404)return {
    mode:"DRY_RUN",scanned:0,eligible:0,requiresReview:0,notYetEligible:0,
    outOfScope:0,missionIds:[]
  };
  if(response.status!==200)throw new Error("GitHub retention GET HTTP "+response.status);
  const entries=await response.json();
  if(!Array.isArray(entries)||entries.length>100){
    throw new Error("Diretorio de retencao grande ou invalido.");
  }
  const ids=entries.filter(e=>e&&e.type==="file"&&typeof e.name==="string"&&
    FILE.test(e.name)).map(e=>e.name.slice(0,-5));
  if(ids.length>25){
    throw new Error("Retencao exige lotes menores, sem mutacao.");
  }
  const summary={
    mode:"DRY_RUN",scanned:0,eligible:0,requiresReview:0,
    notYetEligible:0,outOfScope:entries.length-ids.length,missionIds:[]
  };
  for(const missionId of ids){
    const item=await readGithubMenuProposal({
      repository,gameId:GAME,missionId,branch,token,request
    });
    if(item.status!=="FOUND")throw new Error("Fila alterada durante consulta.");
    let receipt=null;
    const result=await readGithubMenuDelivery({
      repository,proposal:item.proposal,branch,token,request
    });
    if(result.status==="FOUND")receipt=result.state;
    const assessment=assessSyntheticMenuRetention(item.proposal,receipt,{
      nowMs,retentionDays
    });
    summary.scanned++;
    switch(assessment.status){
      case "ELIGIBLE_FOR_MANUAL_REVIEW":
        summary.eligible++;
        summary.missionIds.push(missionId);
        break;
      case "REQUIRES_REVIEW":summary.requiresReview++;break;
      case "NOT_YET_ELIGIBLE":summary.notYetEligible++;break;
      default:summary.outOfScope++;break;
    }
  }
  // No deletion, no token, no player identifiers, and no raw fields returned.
  return summary;
}
