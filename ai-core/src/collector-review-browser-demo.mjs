#!/usr/bin/env node
// Local-only browser demo. No GitHub token, Roblox access, Render or live tools.
import {fileURLToPath} from "node:url";
import path from "node:path";
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {createMenuProposal} from "./menu-proposal.mjs";
import {createCollectorPermissionRequest} from "./collector-permissions.mjs";
import {createCollectorReviewBrowserDemo} from "./collector-review-browser.mjs";

export async function startLocalReviewBrowser({nowMs=()=>Date.now()}={}){
  const load=n=>JSON.parse(readFileSync(
    new URL("../test/fixtures/"+n,import.meta.url),"utf8"));
  const report=analyzeSession({
    batches:[load("batch.json")],manifest:load("latest.json")
  });
  const issuedAtMs=nowMs();
  const proposal=createMenuProposal(report,{nowMs:issuedAtMs});
  const request=createCollectorPermissionRequest(proposal,{
    nowMs:issuedAtMs+1,ttlMs:120000
  });
  const ui=createCollectorReviewBrowserDemo({proposal,request,nowMs});
  const origin=await ui.start();
  return {origin,ui};
}
const current=process.argv[1]?path.resolve(process.argv[1]):null;
if(current===fileURLToPath(import.meta.url)){
  startLocalReviewBrowser().then(({origin,ui})=>{
    process.stdout.write(
      "CAFEINA AI - demo local de permissao sintetica\n"+
      "Abra no navegador deste dispositivo: "+origin+"\n"+
      "Sem acesso ao GitHub, Roblox, Render ou ferramentas reais.\n"+
      "Encerre com Ctrl+C.\n"
    );
    process.once("SIGINT",()=>{ui.close().then(()=>process.exit(0));});
    process.once("SIGTERM",()=>{ui.close().then(()=>process.exit(0));});
  }).catch(error=>{
    process.stderr.write("Demo local indisponivel: "+String(error.message)+"\n");
    process.exitCode=1;
  });
}
