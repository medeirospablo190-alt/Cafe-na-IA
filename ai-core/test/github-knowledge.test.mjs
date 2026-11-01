import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {syncGithubKnowledge} from "../src/knowledge-github.mjs";
const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const make=(runId="demo-run-0001")=>analyzeSession({
  batches:[{...f("batch.json"),runId}],
  manifest:{...f("latest.json"),runId}
});
function mockApi(){
  let memory=null;
  let puts=0;
  return {
    get memory(){return memory;},get puts(){return puts;},
    async request(url,opts){
      if(opts.method==="GET"){
        if(!memory)return {status:404};
        return {status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(memory)).toString("base64")
        })};
      }
      if(opts.method==="PUT"){
        const data=JSON.parse(opts.body);
        assert.equal(data.branch,"cafeina-ai-knowledge");
        assert.ok(!JSON.stringify(data).includes("TEST_SECRET"));
        memory=JSON.parse(Buffer.from(data.content,"base64").toString("utf8"));
        puts++;
        return {ok:true,status:201};
      }
      throw new Error("Unexpected method");
    }
  };
}
test("dry run e idempotencia sem commits automaticos",async()=>{
  const mock=mockApi();
  const common={repository:"medeirospablo190-alt/Cafe-na-IA",request:mock.request};
  const dry=await syncGithubKnowledge({...common,report:make()});
  assert.equal(dry.status,"DRY_RUN");
  assert.equal(mock.puts,0);
  const first=await syncGithubKnowledge({...common,report:make(),token:"MOCK",dryRun:false});
  assert.equal(first.status,"CREATED");
  assert.equal(mock.puts,1);
  const same=await syncGithubKnowledge({...common,report:make(),token:"MOCK",dryRun:false});
  assert.equal(same.status,"UNCHANGED");
  assert.equal(mock.puts,1);
  const next=await syncGithubKnowledge({...common,report:make("demo-run-0002"),token:"MOCK",dryRun:false});
  assert.equal(next.status,"CREATED");
  assert.equal(next.totalRuns,2);
  assert.equal(mock.puts,2);
  assert.equal(mock.memory.knowledge.CAUSALITY_NOT_PROVEN.status,"EXPERIMENTAL");
  assert.ok(!JSON.stringify(mock.memory).includes("TEST_SECRET"));
});
test("branch e token obrigatorios e erros nao vazam resposta",async()=>{
  const mock=mockApi();
  const common={repository:"medeirospablo190-alt/Cafe-na-IA",report:make(),request:mock.request};
  await assert.rejects(()=>syncGithubKnowledge({...common,branch:"main"}),/invalida/);
  await assert.rejects(()=>syncGithubKnowledge({...common,dryRun:false}),/Token/);
  await assert.rejects(()=>syncGithubKnowledge({...common,request:async()=>({status:401})}),/HTTP 401/);
});
test("remote adulterado e rejeitado sem propagacao",async()=>{
  const m=mockApi();
  await syncGithubKnowledge({
    repository:"medeirospablo190-alt/Cafe-na-IA",
    report:make(),token:"MOCK",dryRun:false,request:m.request
  });
  m.memory.sessions["demo-run-0001"].rawPlayer="USER_PERSONAL_DATA";
  await assert.rejects(()=>syncGithubKnowledge({
    repository:"medeirospablo190-alt/Cafe-na-IA",report:make(),
    request:m.request
  }),/invalida/);
});
