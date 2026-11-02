#!/usr/bin/env node
import {existsSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {analyzeDirectory} from "./session-cli.mjs";
import {syncGithubKnowledge} from "./knowledge-github.mjs";

const ID=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
export function selectedPaths(env){
  const gameId=env.CAFEINA_GAME_ID,placeId=env.CAFEINA_PLACE_ID,
    runId=env.CAFEINA_RUN_ID;
  if(typeof gameId!=="string"||!ID.test(gameId)||
     typeof placeId!=="string"||!ID.test(placeId)||
     typeof runId!=="string"||!RUN.test(runId)){
    throw new Error("IDs de sessao invalidos.");
  }
  const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../..");
  const gameRoot=path.join(root,"inventory-traces-v3",gameId,placeId);
  return {gameId,placeId,runId,
    sessionDir:path.join(gameRoot,runId),
    manifest:path.join(gameRoot,"latest.json"),
    profile:path.join(root,"inventory-traces-v3","profiles",gameId+".json")
  };
}
async function main(){
  const s=selectedPaths(process.env);
  if(!existsSync(s.sessionDir)||!existsSync(s.manifest)){
    throw new Error("Sessao V3 inexistente no checkout.");
  }
  const report=await analyzeDirectory({
    "--session-dir":s.sessionDir,
    "--manifest":s.manifest,
    ...(existsSync(s.profile)?{"--profile":s.profile}:{})
  });
  if(!report.coverage.completeBatchSequence)throw new Error("Sessao incompleta; nao publicar.");
  const publish=process.env.CAFEINA_PUBLISH==="true";
  const result=await syncGithubKnowledge({
    repository:process.env.GITHUB_REPOSITORY,report,
    token:process.env.GITHUB_TOKEN ?? "",dryRun:!publish
  });
  process.stdout.write(JSON.stringify({
    status:result.status,gameId:s.gameId,
    uniqueBatches:report.coverage.receivedUniqueDataBatches,
    knownRuns:result.totalRuns,published:result.published
  })+"\n");
}
const invoked=process.argv[1] &&
  path.resolve(process.argv[1])===fileURLToPath(import.meta.url);
if(invoked)main().catch(error=>{
  process.stderr.write("CAFEINA_KNOWLEDGE_ERROR: "+error.message+"\n");
  process.exitCode=1;
});
