#!/usr/bin/env node
import {readFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {coordinateInvestigation} from "./agents.mjs";
import {saveConversation} from "./decision-journal.mjs";

export async function journalFromReport(reportPath,storeDir){
  const report=JSON.parse(await readFile(reportPath,"utf8"));
  const talk=coordinateInvestigation(report);
  if(talk.budgets.toolExecutions!==0||talk.mode!=="DETERMINISTIC_REHEARSAL"){
    throw new Error("Protocolo de agente nao seguro.");
  }
  const saved=await saveConversation(storeDir,talk);
  return {
    schemaVersion:1,
    status:saved.status,
    gameId:talk.identity.gameId,
    messages:talk.messages.length,
    modelCalls:talk.budgets.modelCalls,
    toolExecutions:talk.budgets.toolExecutions,
    decision:talk.messages.at(-1).detail.status,
    journalSha256:saved.sha256
  };
}
async function main(){
  if(process.argv.length!==4)throw new Error("Uso: node src/agent-report-cli.mjs <relatorio.json> <diretorio-privado>");
  const result=await journalFromReport(path.resolve(process.argv[2]),path.resolve(process.argv[3]));
  process.stdout.write(JSON.stringify(result)+"\n");
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(e=>{
    process.stderr.write("CAFEINA_AGENT_JOURNAL_ERROR: "+e.message+"\n");
    process.exitCode=1;
  });
}
