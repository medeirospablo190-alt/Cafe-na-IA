import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createMenuDeliveryState,applyMenuDeliveryEvent,validateMenuDeliveryState} from "../src/menu-delivery-state.mjs";
const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});
const now=1700000000000;
const proposal=()=>createMenuProposal(report(),{nowMs:now});

test("delivery, ack and decline can be replayed without execution",()=>{
  const p=proposal();
  const zero=createMenuDeliveryState(p);
  assert.equal(zero.revision,0);
  assert.equal(zero.status,"QUEUED");
  assert.equal(zero.executable,undefined);
  const delivered=applyMenuDeliveryEvent(zero,p,"DELIVERED",{nowMs:now+100});
  assert.equal(delivered.state.revision,1);
  assert.equal(delivered.state.status,"DELIVERED");
  assert.equal(applyMenuDeliveryEvent(delivered.state,p,"DELIVERED",{nowMs:now+150}).status,"UNCHANGED");
  const ack=applyMenuDeliveryEvent(delivered.state,p,"RECEIVED",{nowMs:now+200});
  assert.equal(ack.state.revision,2);
  const finish=applyMenuDeliveryEvent(ack.state,p,"DECLINED",{nowMs:now+300});
  assert.equal(finish.state.status,"CLOSED_NO_EXECUTION");
  assert.equal(finish.state.outcome,"DECLINED");
  assert.equal(finish.state.approved,false);
  assert.equal(finish.state.executed,false);
  assert.equal(applyMenuDeliveryEvent(finish.state,p,"DECLINED",{nowMs:now+400}).status,"UNCHANGED");
  assert.equal(applyMenuDeliveryEvent(finish.state,p,"RECEIVED",{nowMs:now+400}).status,"UNCHANGED");
  assert.throws(()=>applyMenuDeliveryEvent(finish.state,p,"NOT_EXECUTED",{nowMs:now+400}),/CONFLICT/);
  assert.ok(!JSON.stringify(finish.state).includes("TEST_SECRET"));
  assert.equal(validateMenuDeliveryState(finish.state,p),finish.state);
});

test("events must follow delivery and remain in exact session and time bounds",()=>{
  const p=proposal();
  assert.throws(()=>applyMenuDeliveryEvent(null,p,"RECEIVED",{nowMs:now+100}),/ACK_REQUIRED/);
  assert.throws(()=>applyMenuDeliveryEvent(null,p,"DECLINED",{nowMs:now+100}),/ACK_REQUIRED/);
  assert.throws(()=>applyMenuDeliveryEvent(null,p,"EXECUTE",{nowMs:now+100}),/nao permitido/);
  assert.throws(()=>applyMenuDeliveryEvent(null,p,"DELIVERED",{nowMs:now+600000}),/expirado/);
  assert.throws(()=>validateMenuDeliveryState({
    ...createMenuDeliveryState(p),username:"TEST_SECRET"
  },p),/invalido/);
  assert.throws(()=>validateMenuDeliveryState({
    ...createMenuDeliveryState(p),approved:true
  },p),/invalido/);
  assert.throws(()=>validateMenuDeliveryState({
    ...createMenuDeliveryState(p),revision:3,status:"CLOSED_NO_EXECUTION",
    outcome:"DECLINED"
  },p),/inconsistente/);
});
