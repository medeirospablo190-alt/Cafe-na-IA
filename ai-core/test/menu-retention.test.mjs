import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createMenuDeliveryState,applyMenuDeliveryEvent} from "../src/menu-delivery-state.mjs";
import {assessSyntheticMenuRetention,scanSyntheticMenuRetention} from "../src/menu-retention.mjs";

const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const initial=1700000000000,day=86400000;
function testData(){
  const original=report();
  const runId="synthetic-41365030921";
  const copy=JSON.parse(JSON.stringify(original));
  copy.identity.runId=runId;
  copy.mission.originatingRunId=runId;
  copy.mission.evidenceRefs=copy.mission.evidenceRefs.map(s=>s.replace("demo-run-0001",runId));
  for(const list of Object.values(copy.observations.evidenceRefs)){
    if(Array.isArray(list)){
      for(let i=0;i<list.length;i++)list[i]=list[i].replace("demo-run-0001",runId);
    }
  }
  const proposal=createMenuProposal(copy,{nowMs:initial,ttlMs:60000});
  let state=createMenuDeliveryState(proposal);
  for(const [event,time] of [
    ["DELIVERED",initial+100],["RECEIVED",initial+200],["NOT_EXECUTED",initial+300]
  ])state=applyMenuDeliveryEvent(state,proposal,event,{nowMs:time}).state;
  return {proposal,state};
}
test("only expired, fully closed synthetic records qualify for manual review",()=>{
  const {proposal,state}=testData();
  assert.equal(assessSyntheticMenuRetention(proposal,state,{
    nowMs:initial+60000+8*day
  }).status,"ELIGIBLE_FOR_MANUAL_REVIEW");
  assert.equal(assessSyntheticMenuRetention(proposal,state,{
    nowMs:initial+60000+6*day
  }).status,"NOT_YET_ELIGIBLE");
  assert.equal(assessSyntheticMenuRetention(proposal,null,{
    nowMs:initial+60000+8*day
  }).status,"REQUIRES_REVIEW");
  assert.equal(assessSyntheticMenuRetention({...proposal,
    identity:{...proposal.identity,gameId:"202"}},null,{
    nowMs:initial+60000+8*day
  }).status,"OUT_OF_SCOPE");
  assert.throws(()=>assessSyntheticMenuRetention(proposal,state,{
    nowMs:initial+60000+8*day,retentionDays:1
  }),/Limites/);
});
test("read-only Github scan does not call any write method",async()=>{
  const {proposal,state}=testData(),events=[];
  const id=proposal.missionId;
  const mock=async(url,opts)=>{
    events.push(opts.method);
    assert.equal(opts.method,"GET");
    if(url.includes("/mission-queue/101?")){
      return {status:200,json:async()=>[{name:id+".json",type:"file"}]};
    }
    const payload=url.includes("/menu-receipts/")?state:proposal;
    return {status:200,json:async()=>({
      type:"file",encoding:"base64",sha:"a".repeat(40),
      content:Buffer.from(JSON.stringify(payload)).toString("base64")
    })};
  };
  const result=await scanSyntheticMenuRetention({
    request:mock,nowMs:initial+60000+8*day,token:"TEST_READ_ONLY"
  });
  assert.equal(result.mode,"DRY_RUN");
  assert.equal(result.scanned,1);
  assert.equal(result.eligible,1);
  assert.deepEqual(result.missionIds,[id]);
  assert.ok(events.length>=3);
  assert.ok(events.every(x=>x==="GET"));
});
test("retention cannot scan other repositories or authorize deletion",async()=>{
  await assert.rejects(()=>scanSyntheticMenuRetention({
    repository:"somebody/another-repo",request:async()=>{throw Error("should not call");}
  }),/fora do escopo/);
  await assert.rejects(()=>scanSyntheticMenuRetention({
    request:async()=>({status:403})
  }),/HTTP 403/);
});
