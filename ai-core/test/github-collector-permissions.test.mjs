import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {
  createCollectorPermissionRequest,reviewCollectorPermission
} from "../src/collector-permissions.mjs";
import {
  createCollectorPermissionEnvelope,validateCollectorPermissionEnvelope,
  readGithubCollectorPermission,syncGithubCollectorPermission,
  applyCollectorPermissionReview
} from "../src/github-collector-permissions.mjs";
const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const base=1700000000000,repository="medeirospablo190-alt/Cafe-na-IA";
const fixture=async outcome=>{
  const r=analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
  const p=createMenuProposal(r,{nowMs:base});
  const request=createCollectorPermissionRequest(p,{nowMs:base+1000});
  const review=await reviewCollectorPermission(request,p,{
    outcome,nowMs:base+2000,operatorEvidence:"SYNTHETIC_TEST_APPROVED",
    verifyTestOperator:async()=>({
      verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
      requestId:request.requestId,missionId:request.missionId,
      identity:{...request.identity}
    })
  });
  return {p,request,review};
};
function fakeGitHub(){
  let stored=null,writes=0,conflicts=0;
  return {
    get stored(){return stored;},get writes(){return writes;},
    conflictOnce(){conflicts=1;},
    async request(url,options){
      assert.ok(url.includes("/contents/ai-core/collector-permissions/101/mission-"));
      if(options.method==="GET"){
        return stored?{status:200,json:async()=>({
          type:"file",encoding:"base64",sha:"a".repeat(40),
          content:Buffer.from(JSON.stringify(stored)).toString("base64")
        })}:{status:404};
      }
      if(options.method!=="PUT")throw new Error("UNEXPECTED_METHOD");
      if(conflicts>0){conflicts--;return {ok:false,status:409};}
      assert.equal(JSON.parse(options.body).branch,"cafeina-ai-knowledge");
      assert.ok(options.headers.Authorization?.startsWith("Bearer MOCK"));
      stored=JSON.parse(Buffer.from(
        JSON.parse(options.body).content,"base64").toString("utf8"));
      writes++;
      return {ok:true,status:201};
    }
  };
}
test("request is revision zero and final review revision one",async()=>{
  const {p,request,review}=await fixture("DENIED");
  const initial=createCollectorPermissionEnvelope(request,p);
  assert.equal(initial.status,"PENDING_REVIEW");
  assert.equal(initial.revision,0);
  assert.equal(initial.review,null);
  const done=applyCollectorPermissionReview(initial,review,p);
  assert.equal(done.status,"UPDATED");
  assert.equal(done.record.status,"REVIEWED");
  assert.equal(done.record.revision,1);
  assert.equal(done.record.review.outcome,"DENIED");
  assert.equal(done.record.review.authorizedLiveExecution,false);
  assert.equal(applyCollectorPermissionReview(done.record,review,p).status,"UNCHANGED");
  assert.throws(()=>validateCollectorPermissionEnvelope({
    ...done.record,untrustedName:"TEST_SECRET"
  },p),/invalido/);
});
test("dry-run and no token cannot write",async()=>{
  const {p,request}=await fixture("DENIED");
  const api=fakeGitHub();
  assert.equal((await syncGithubCollectorPermission({
    repository,proposal:p,requestRecord:request,request:api.request
  })).status,"DRY_RUN");
  assert.equal(api.writes,0);
  await assert.rejects(()=>syncGithubCollectorPermission({
    repository,proposal:p,requestRecord:request,dryRun:false,request:api.request
  }),/token/);
  await assert.rejects(()=>syncGithubCollectorPermission({
    repository,proposal:p,requestRecord:request,branch:"main",request:api.request
  }),/nao autorizado/);
});
test("GitHub API mock supports first request and exactly one immutable decision",async()=>{
  const {p,request,review}=await fixture("SIMULATION_ALLOWED");
  const other=(await fixture("DENIED")).review;
  const api=fakeGitHub();
  const options={repository,proposal:p,token:"MOCK",dryRun:false,request:api.request};
  assert.equal((await syncGithubCollectorPermission({
    ...options,requestRecord:request
  })).revision,0);
  assert.equal((await syncGithubCollectorPermission({
    ...options,requestRecord:request
  })).status,"UNCHANGED");
  assert.equal((await readGithubCollectorPermission({
    repository,proposal:p,request:api.request
  })).record.status,"PENDING_REVIEW");
  api.conflictOnce();
  assert.equal((await syncGithubCollectorPermission({
    ...options,review
  })).revision,1);
  assert.equal((await syncGithubCollectorPermission({
    ...options,review
  })).status,"UNCHANGED");
  await assert.rejects(()=>syncGithubCollectorPermission({
    ...options,review:other
  }),/CONFLICT/);
  assert.equal((await syncGithubCollectorPermission({
    ...options,requestRecord:request
  })).revision,1);
  assert.equal(api.writes,2);
  assert.equal(api.stored.review.authorizedLiveExecution,false);
  assert.ok(!JSON.stringify(api.stored).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(api.stored).includes("username"));
});
test("forged fields and absent request refuse finalization",async()=>{
  const {p,request,review}=await fixture("DENIED");
  const api=fakeGitHub();
  const opts={repository,proposal:p,token:"MOCK",dryRun:false,request:api.request};
  await assert.rejects(()=>syncGithubCollectorPermission({...opts,review}),/CONFLICT/);
  await assert.rejects(()=>syncGithubCollectorPermission({
    ...opts,requestRecord:{...request,scope:"LIVE_EXECUTION"}
  }),/contrato/);
  await syncGithubCollectorPermission({...opts,requestRecord:request});
  await assert.rejects(()=>syncGithubCollectorPermission({
    ...opts,review:{...review,authorizedLiveExecution:true}
  }),/contrato/);
  await assert.rejects(()=>readGithubCollectorPermission({
    repository,proposal:p,request:async()=>({status:403})
  }),/HTTP 403/);
});
