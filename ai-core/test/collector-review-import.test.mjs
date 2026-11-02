import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createCollectorPermissionRequest,reviewCollectorPermission} from "../src/collector-permissions.mjs";
import {createCollectorPermissionEnvelope,applyCollectorPermissionReview} from "../src/github-collector-permissions.mjs";
import {createCollectorReviewBrowserDemo} from "../src/collector-review-browser.mjs";
const load=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const time=1700000000000;
test("browser reloads an already persisted synthetic denial without reopening options",async t=>{
  const report=analyzeSession({batches:[load("batch.json")],manifest:load("latest.json")});
  const proposal=createMenuProposal(report,{nowMs:time});
  const request=createCollectorPermissionRequest(proposal,{nowMs:time+1000});
  const review=await reviewCollectorPermission(request,proposal,{
    outcome:"DENIED",nowMs:time+2000,operatorEvidence:"fixture",
    verifyTestOperator:async()=>({
      verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
      requestId:request.requestId,missionId:request.missionId,
      identity:{...request.identity}
    })
  });
  const pending=createCollectorPermissionEnvelope(request,proposal);
  const record=applyCollectorPermissionReview(pending,review,proposal).record;
  const ui=createCollectorReviewBrowserDemo({
    proposal,request,initialRecord:record,nowMs:()=>time+3000
  });
  t.after(()=>ui.close());
  const origin=await ui.start();
  const page=await (await fetch(origin+"/")).text();
  assert.match(page,/DENIED/);
  assert.doesNotMatch(page,/name="csrf"/);
  const view=await (await fetch(origin+"/status")).json();
  assert.equal(view.status,"DENIED");
  assert.equal(ui.getState().revision,1);
  assert.equal(ui.getState().approvedForLiveTools,false);
  assert.throws(()=>createCollectorReviewBrowserDemo({
    proposal,request,initialRecord:{
      ...record,request:{...request,identity:{...request.identity,gameId:"999"}}
    }
  }));
});
