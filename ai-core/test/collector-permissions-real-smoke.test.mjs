import test from "node:test";
import assert from "node:assert/strict";
import {syntheticPermissionRoundtrip} from "../src/collector-permissions-real-smoke.mjs";
test("cross-runner smoke refuses foreign repository, run and invalid mode",async()=>{
  const env={
    GITHUB_REPOSITORY:"medeirospablo190-alt/Cafe-na-IA",
    GITHUB_RUN_ID:"41385570633",GITHUB_TOKEN:"test-only-not-a-secret"
  };
  await assert.rejects(()=>syntheticPermissionRoundtrip("execute",env),/nao autorizado/);
  await assert.rejects(()=>syntheticPermissionRoundtrip("publish",{
    ...env,GITHUB_RUN_ID:"../private"
  }),/nao autorizado/);
  await assert.rejects(()=>syntheticPermissionRoundtrip("publish",{
    ...env,GITHUB_REPOSITORY:"unknown/foreign"
  }),/nao autorizado/);
});
