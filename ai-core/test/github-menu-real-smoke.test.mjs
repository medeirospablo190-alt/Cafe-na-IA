import test from "node:test";
import assert from "node:assert/strict";
import {syntheticProposal,syntheticGithubMenuSmoke} from "../src/github-menu-real-smoke.mjs";

test("run-specific synthetic proposal contains no real player information",()=>{
  const p=syntheticProposal("41365500123",{nowMs:1700000000000});
  assert.equal(p.identity.gameId,"101");
  assert.equal(p.identity.placeId,"202");
  assert.equal(p.identity.runId,"synthetic-41365500123");
  assert.equal(p.approved,false);
  assert.equal(p.executable,false);
  assert.equal(p.approvalRequired,true);
  assert.equal(p.toolId,"watch_state");
  assert.ok(!JSON.stringify(p).includes("TEST_SECRET"));
  assert.deepEqual(syntheticProposal("41365500123",{nowMs:1700000000000}),p);
});
test("synthetic smoke does not accept foreign repository or unsafe run id",async()=>{
  const good={GITHUB_RUN_ID:"41365500123",GITHUB_REPOSITORY:"medeirospablo190-alt/Cafe-na-IA",GITHUB_TOKEN:"test-token-01234567"};
  await assert.rejects(()=>syntheticGithubMenuSmoke("publish",{
    ...good,GITHUB_REPOSITORY:"attacker/another-repo"
  }),/nao autorizada/);
  await assert.rejects(()=>syntheticGithubMenuSmoke("publish",{
    ...good,GITHUB_RUN_ID:"../../secret"
  }),/nao autorizada/);
  await assert.rejects(()=>syntheticGithubMenuSmoke("execute",good),/nao autorizada/);
  assert.throws(()=>syntheticProposal("../token"),/invalido/);
});
