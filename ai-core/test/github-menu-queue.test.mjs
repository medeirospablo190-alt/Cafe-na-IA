import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {readGithubMenuProposal,publishGithubMenuProposal} from "../src/github-menu-queue.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const proposal=()=>createMenuProposal(report(),{nowMs:1700000000000});
const repo="medeirospablo190-alt/Cafe-na-IA";
function mock(){
  let stored=null,puts=0;
  return {
    get stored(){return stored;},get puts(){return puts;},
    async request(url,opts){
      assert.ok(url.includes("/contents/ai-core/mission-queue/101/mission-"));
      if(opts.method==="GET"){
        return stored?{status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(stored)).toString("base64")
        })}:{status:404};
      }
      if(opts.method==="PUT"){
        const body=JSON.parse(opts.body);
        assert.equal(body.branch,"cafeina-ai-knowledge");
        assert.ok(opts.headers.Authorization.startsWith("Bearer MOCK"));
        stored=JSON.parse(Buffer.from(body.content,"base64").toString("utf8"));
        puts++;
        return {status:201,ok:true};
      }
      throw new Error("Unexpected API call");
    }
  };
}
test("default is read-only and no GitHub write",async()=>{
  const api=mock(),p=proposal();
  const out=await publishGithubMenuProposal({
    repository:repo,proposal:p,request:api.request
  });
  assert.equal(out.status,"DRY_RUN");
  assert.equal(api.puts,0);
});
test("published proposal is immutable, retrievable, and never executable",async()=>{
  const api=mock(),p=proposal();
  const opts={repository:repo,token:"MOCK",dryRun:false,request:api.request};
  const first=await publishGithubMenuProposal({...opts,proposal:p});
  assert.equal(first.status,"SAVED");
  assert.equal((await publishGithubMenuProposal({...opts,proposal:p})).status,"UNCHANGED");
  const read=await readGithubMenuProposal({
    repository:repo,gameId:p.identity.gameId,missionId:p.missionId,request:api.request
  });
  assert.equal(read.status,"FOUND");
  assert.equal(read.proposal.executable,false);
  assert.equal(read.proposal.approved,false);
  assert.ok(!JSON.stringify(read.proposal).includes("TEST_SECRET"));
  assert.equal(api.puts,1);
  await assert.rejects(()=>publishGithubMenuProposal({
    ...opts,proposal:{...p,issuedAtMs:p.issuedAtMs+100}
  }),/CONFLICT/);
});
test("branch restrictions and invalid proposals rejected",async()=>{
  const p=proposal(),api=mock();
  await assert.rejects(()=>publishGithubMenuProposal({
    repository:repo,proposal:p,branch:"main",request:api.request
  }),/nao autorizado/);
  await assert.rejects(()=>publishGithubMenuProposal({
    repository:repo,proposal:p,dryRun:false,request:api.request
  }),/token/);
  await assert.rejects(()=>publishGithubMenuProposal({
    repository:repo,proposal:{...p,approved:true},request:api.request
  }),/contrato/);
});
