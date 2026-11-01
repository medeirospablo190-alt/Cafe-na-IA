import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {prepareReaHandoff,reaEmptyLedgerRequest} from "../src/rea-adapter.mjs";

const f=name=>JSON.parse(readFileSync(new URL("fixtures/"+name,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});

test("REA handoff preserves only references, not personal data or fake proof",()=>{
  const handoff=prepareReaHandoff(report());
  assert.equal(handoff.reaEvidenceAuthenticated,false);
  assert.equal(handoff.reaLedgerExecuted,false);
  assert.equal(handoff.verifiedReconstructionClaims,0);
  assert.equal(handoff.pendingQuestions.length,2);
  assert.ok(handoff.pendingQuestions.every(x=>x.status==="NEEDS_AUTHENTICATED_REA_EVIDENCE"));
  assert.ok(handoff.pendingQuestions[0].sourceRefs[0].startsWith("v3:101:202:"));
  const serialized=JSON.stringify(handoff);
  assert.ok(!serialized.includes("TEST_SECRET"));
  assert.ok(!serialized.includes("username"));
});

test("REA never receives invented proof or cross-session evidence refs",()=>{
  const a=report();
  a.unknowns[0].evidenceRefs=["v3:666:202:demo-run-0001:1:1"];
  assert.throws(()=>prepareReaHandoff(a),/verificadas/);
  const b=report();
  b.unknowns[0].code="EXECUTE_SCRIPT";
  assert.throws(()=>prepareReaHandoff(b),/verificadas/);
  const c=report();
  c.coverage.causalValidation=true;
  assert.throws(()=>prepareReaHandoff(c),/saneado/);
});

test("REA documented empty ledger has zero evidence and obligations",()=>{
  const x=reaEmptyLedgerRequest();
  assert.deepEqual(Object.keys(x.evidence_bundle).sort(),
    ["artifacts","captures","environments","providers","records","scenarios","unknowns"]);
  assert.deepEqual(x.reviewed_obligations,[]);
  assert.deepEqual(x.manifest.bindings,[]);
  assert.deepEqual(x.manifest.contradictions,[]);
});
