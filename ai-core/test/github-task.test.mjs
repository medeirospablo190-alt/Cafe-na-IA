import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {coordinateInvestigation} from "../src/agents.mjs";
import {createPlanningTask,changePlanningTask} from "../src/task-engine.mjs";
import {readGithubPlanningTask,syncGithubPlanningTask} from "../src/github-task.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
const config={repository:"medeirospablo190-alt/Cafe-na-IA"};
function mock(){
  let stored=null,puts=0;
  return {
    get stored(){return stored;},get puts(){return puts;},
    async request(u,opts){
      assert.ok(u.includes("/contents/ai-core/tasks/101/task-"));
      if(opts.method==="GET"){
        return stored?{status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(stored)).toString("base64")
        })}:{status:404};
      }
      if(opts.method==="PUT"){
        const body=JSON.parse(opts.body);
        assert.equal(body.branch,"cafeina-ai-knowledge");
        assert.ok(opts.headers.Authorization.includes("MOCK"));
        stored=JSON.parse(Buffer.from(body.content,"base64").toString("utf8"));
        puts++;
        return {ok:true,status:201};
      }
      throw Error("unexpected method");
    }
  };
}
test("default read-only dry run",async()=>{
  const api=mock(),task=createPlanningTask(report(),{nowMs:now});
  const result=await syncGithubPlanningTask({...config,task,request:api.request});
  assert.equal(result.status,"DRY_RUN");
  assert.equal(api.puts,0);
});
test("task crosses API sessions and only legal revisions persist",async()=>{
  const api=mock(),initial=createPlanningTask(report(),{nowMs:now});
  const opts={...config,token:"MOCK",dryRun:false,request:api.request};
  assert.equal((await syncGithubPlanningTask({...opts,task:initial})).status,"SAVED");
  assert.equal((await syncGithubPlanningTask({...opts,task:initial})).status,"UNCHANGED");
  const loaded=await readGithubPlanningTask({
    ...config,gameId:initial.identity.gameId,taskId:initial.taskId,request:api.request
  });
  assert.deepEqual(loaded.task,initial);
  const running=changePlanningTask(loaded.task,"START",{nowMs:now+1000});
  assert.equal((await syncGithubPlanningTask({
    ...opts,task:running,expectedRevision:0
  })).revision,1);
  const finished=changePlanningTask(running,"FINISH",{
    nowMs:now+2000,conversation:coordinateInvestigation(report())
  });
  assert.equal((await syncGithubPlanningTask({
    ...opts,task:finished,expectedRevision:1
  })).status,"SAVED");
  assert.equal(api.stored.status,"WAITING_USER");
  assert.equal(api.puts,3);
  await assert.rejects(()=>syncGithubPlanningTask({
    ...opts,task:running,expectedRevision:0
  }),/CONFLICT/);
  assert.ok(!JSON.stringify(api.stored).includes("TEST_SECRET"));
});
test("wrong branch, forged data or unauthorized write fail closed",async()=>{
  const task=createPlanningTask(report(),{nowMs:now}),api=mock();
  await assert.rejects(()=>syncGithubPlanningTask({
    ...config,task,dryRun:false
  }),/token/);
  await assert.rejects(()=>syncGithubPlanningTask({
    ...config,task,branch:"main"
  }),/nao autorizado/);
  await assert.rejects(()=>syncGithubPlanningTask({
    ...config,task:{...task,playerId:"TEST_SECRET"},request:api.request
  }),/invalido/);
  await assert.rejects(()=>syncGithubPlanningTask({
    ...config,task,request:async()=>({status:403})
  }),/HTTP 403/);
});
