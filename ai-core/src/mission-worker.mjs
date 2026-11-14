import {createMenuProposal} from "./menu-proposal.mjs";
import {publishGithubMenuProposal} from "./github-menu-queue.mjs";

const GAME=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;

/**
 * GitHub/server-side task builder. It only accepts an already-sanitized V3
 * analysis; generated code, raw player records and live Roblox actions
 * are NOT inputs/outputs of this worker.
 */
export async function buildObservationWorkOrder({
  report,nowMs=Date.now(),publish=false,repository=null,githubToken=null,
  ownerApproved=false,authorizedGameId=null,authorizedRunId=null,
  request=fetch
}={}){
  if(typeof publish!=="boolean"||typeof ownerApproved!=="boolean"||
     !Number.isSafeInteger(nowMs)||nowMs<0){
    throw new Error("Invalid worker configuration.");
  }
  const proposal=createMenuProposal(report,{nowMs,ttlMs:600000});
  if(!publish){
    return {mode:"DRY_RUN",published:false,proposal};
  }
  if(ownerApproved!==true||!REPO.test(repository??"")||
    typeof githubToken!=="string"||githubToken.length<8||
    !GAME.test(authorizedGameId??"")||!RUN.test(authorizedRunId??"")||
    authorizedGameId!==proposal.identity.gameId||
    authorizedRunId!==proposal.identity.runId){
    throw new Error("Owner-approved scope and server-only Github credentials required.");
  }
  const saved=await publishGithubMenuProposal({
    repository,proposal,token:githubToken,dryRun:false,request
  });
  return {
    mode:"OWNER_APPROVED_GITHUB_WRITE",
    published:saved.published,proposal
  };
}
