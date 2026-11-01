import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal,validateMenuProposal,menuReceipt,validateMenuReceipt} from "../src/menu-proposal.mjs";
const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;

test("proposal contains only bounded observation metadata and requires approval",()=>{
  const p=createMenuProposal(report(),{nowMs:now});
  assert.equal(validateMenuProposal(p),p);
  assert.equal(p.approved,false);
  assert.equal(p.executable,false);
  assert.equal(p.approvalRequired,true);
  assert.equal(p.toolId,"watch_state");
  assert.equal(p.params.durationSeconds,10);
  const text=JSON.stringify(p);
  assert.ok(!text.includes("TEST_SECRET"));
  assert.ok(!text.includes("username"));
});

test("proposal rejects cross-session fields and invalid permissions",()=>{
  const p=createMenuProposal(report(),{nowMs:now});
  for(const variant of [
    {...p,executable:true},
    {...p,approved:true},
    {...p,identity:{...p.identity,gameId:"404"}},
    {...p,evidenceRefs:["v3:404:202:demo-run-0001:1:1"]},
    {...p,toolId:"other"},
    {...p,extraField:"not permitted"}
  ])assert.throws(()=>validateMenuProposal(variant),/contrato/);
  assert.throws(()=>createMenuProposal(report(),{nowMs:now,ttlMs:123}),/inadequado/);
});

test("menu can acknowledge or decline, but never grant approval or execution",()=>{
  const p=createMenuProposal(report(),{nowMs:now});
  for(const kind of ["RECEIVED","DECLINED","NOT_EXECUTED"]){
    const receipt=menuReceipt(p,kind);
    assert.equal(validateMenuReceipt(receipt,p,{nowMs:now+1000}),receipt);
  }
  const receipt=menuReceipt(p,"RECEIVED");
  assert.throws(()=>validateMenuReceipt({...receipt,executed:true},p,{nowMs:now}),/contrato/);
  assert.throws(()=>validateMenuReceipt({...receipt,kind:"UNKNOWN"},p,{nowMs:now}),/contrato/);
  assert.throws(()=>validateMenuReceipt(receipt,p,{nowMs:now+600000}),/contrato/);
});

test("mission cannot cite evidence absent from the sanitized report",()=>{
  const r=report();
  r.mission.evidenceRefs=["v3:101:202:demo-run-0001:1:599"];
  assert.throws(()=>createMenuProposal(r,{nowMs:now}),/observacoes/);
});
