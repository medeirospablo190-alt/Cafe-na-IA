#!/usr/bin/env node
import {readFileSync,writeFileSync} from "node:fs";
import {buildObservationWorkOrder} from "./mission-worker.mjs";

const [reportPath,proposalPath]=process.argv.slice(2);
if(!reportPath||!proposalPath||process.argv.length!==4){
  throw new Error("Usage: node mission-worker-cli.mjs report.json proposal.json");
}
const bytes=readFileSync(reportPath);
if(bytes.byteLength>1048576)throw new Error("Sanitized report too large.");
const report=JSON.parse(bytes.toString("utf8"));
const env=process.env;
const publish=env.CAFEINA_WORKER_PUBLISH==="true";
if(env.CAFEINA_WORKER_PUBLISH&&!["true","false"].includes(env.CAFEINA_WORKER_PUBLISH)){
  throw new Error("Publish must be true or false.");
}
const output=await buildObservationWorkOrder({
  report,publish,ownerApproved:env.CAFEINA_OWNER_APPROVED==="yes",
  authorizedGameId:env.CAFEINA_AUTHORIZED_GAME_ID,
  authorizedRunId:env.CAFEINA_AUTHORIZED_RUN_ID,
  repository:env.GITHUB_REPOSITORY,
  githubToken:env.GITHUB_TOKEN
});
writeFileSync(proposalPath,JSON.stringify(output.proposal,null,2)+"\n",{flag:"wx",mode:0o600});
console.log(JSON.stringify({
  mode:output.mode,published:output.published,
  missionId:output.proposal.missionId,approved:false,executable:false,
  rawPlayerDataIncluded:false
}));
