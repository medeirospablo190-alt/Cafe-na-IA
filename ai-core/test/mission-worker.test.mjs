import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {buildObservationWorkOrder} from "../src/mission-worker.mjs";

const read=name=>JSON.parse(readFileSync(
  new URL("./fixtures/"+name,import.meta.url),"utf8"
));
const report=analyzeSession({
  batches:[read("batch.json")],manifest:read("latest.json")
});
const NOW=1700000000000;
test("server-side worker creates strictly non-executing, sanitized mission offline",async()=>{
  let requests=0;
  const result=await buildObservationWorkOrder({
    report,nowMs:NOW,request:()=>{requests++;throw new Error("network not allowed");}
  });
  assert.equal(result.mode,"DRY_RUN");
  assert.equal(result.published,false);
  assert.equal(requests,0);
  assert.equal(result.proposal.approved,false);
  assert.equal(result.proposal.executable,false);
  assert.equal(result.proposal.approvalRequired,true);
  assert.equal(result.proposal.expiresAtMs,NOW+600000);
  assert.ok(["watch_state","observe_gui"].includes(result.proposal.toolId));
  assert.doesNotMatch(JSON.stringify(result.proposal),/username|userId|rawRecords|remoteArguments/i);
});
test("worker will not publish without owner approved scope and server-only token",async()=>{
  const opts={
    report,nowMs:NOW,publish:true,repository:"owner/repo",
    githubToken:"example_workflow_server_token",
    ownerApproved:true,
    authorizedGameId:report.identity.gameId,
    authorizedRunId:report.identity.runId
  };
  await assert.rejects(buildObservationWorkOrder({...opts,ownerApproved:false}),/Owner-approved scope/);
  await assert.rejects(buildObservationWorkOrder({...opts,authorizedGameId:"999"}),/Owner-approved scope/);
  await assert.rejects(buildObservationWorkOrder({...opts,githubToken:""}),/Owner-approved scope/);
  const writes=[];
  const request=async (_url,req)=>{
    if(req.method==="GET")return new Response("",{status:404});
    if(req.method==="PUT"){
      writes.push(JSON.parse(req.body));
      return Response.json({commit:{sha:"a".repeat(40)}},{status:201});
    }
    throw new Error("Unexpected request.");
  };
  const result=await buildObservationWorkOrder({...opts,request});
  assert.equal(result.mode,"OWNER_APPROVED_GITHUB_WRITE");
  assert.equal(result.published,true);
  assert.equal(writes.length,1);
  assert.equal(writes[0].branch,"cafeina-ai-knowledge");
  const decoded=JSON.parse(Buffer.from(writes[0].content,"base64").toString("utf8"));
  assert.equal(decoded.executable,false);
  assert.equal(decoded.approved,false);
  assert.equal(decoded.identity.gameId,report.identity.gameId);
});
