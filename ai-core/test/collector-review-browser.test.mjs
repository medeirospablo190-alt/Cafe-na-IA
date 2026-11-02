import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {createMenuProposal} from "../src/menu-proposal.mjs";
import {createCollectorPermissionRequest} from "../src/collector-permissions.mjs";
import {createCollectorReviewBrowserDemo} from "../src/collector-review-browser.mjs";
const load=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const now=1700000000000;
function make(options={}){
  const r=analyzeSession({batches:[load("batch.json")],manifest:load("latest.json")});
  const proposal=createMenuProposal(r,{nowMs:now});
  const request=createCollectorPermissionRequest(proposal,{nowMs:now+1000,ttlMs:60000});
  return createCollectorReviewBrowserDemo({proposal,request,nowMs:()=>now+2000,...options});
}
function hiddenCsrf(html){
  const csrf=html.match(/name="csrf" value="([a-f0-9]{64})"/);
  assert.ok(csrf,"Missing hidden fixture challenge");
  return csrf[1];
}
async function submit(origin,csrf,outcome,headers={}){
  return fetch(origin+"/review",{
    method:"POST",redirect:"manual",
    headers:{"Content-Type":"application/x-www-form-urlencoded",
      Origin:origin,...headers},
    body:new URLSearchParams({csrf,outcome}).toString()
  });
}
test("local browser flow explicitly denies offline test and finalizes once",async t=>{
  const app=make();t.after(()=>app.close());
  const origin=await app.start();
  const first=await fetch(origin+"/");
  assert.equal(first.status,200);
  assert.match(first.headers.get("content-security-policy"),/default-src 'none'/);
  assert.equal(first.headers.get("cache-control"),"no-store");
  const content=await first.text();
  assert.match(content,/Revisão de simulação/);
  assert.match(content,/Não é uma autorização real/);
  assert.match(content,/Recusar o teste/);
  assert.doesNotMatch(content,/TEST_SECRET|username|userId|remoteArguments/);
  assert.doesNotMatch(content,/<script\b/i);
  const csrf=hiddenCsrf(content);
  assert.equal((await submit(origin,"f".repeat(64),"DENIED")).status,403);
  assert.equal((await submit(origin,csrf,"EXECUTE_LUA")).status,403);
  assert.equal((await submit(origin,csrf,"DENIED",{Origin:"http://evil.invalid"})).status,403);
  assert.equal(app.getState().revision,0);
  const applied=await submit(origin,csrf,"DENIED");
  assert.equal(applied.status,303);
  assert.equal(app.getState().revision,1);
  assert.equal(app.getState().outcome,"DENIED");
  assert.equal((await submit(origin,csrf,"SIMULATION_ALLOWED")).status,403);
  const closed=await (await fetch(origin+"/")).text();
  assert.doesNotMatch(closed,/name="csrf"/);
  assert.match(closed,/Não há ações disponíveis/);
  assert.equal(app.getState().executedInRoblox,false);
  assert.equal(app.getState().approvedForLiveTools,false);
  assert.equal(app.getState().githubPublished,false);
});
test("offline simulation consent is NOT real Roblox consent",async t=>{
  const app=make();t.after(()=>app.close());
  const origin=await app.start();
  const csrf=hiddenCsrf(await (await fetch(origin+"/")).text());
  assert.equal((await submit(origin,csrf,"SIMULATION_ALLOWED")).status,303);
  const view=await (await fetch(origin+"/status")).json();
  assert.equal(view.status,"TEST_SIMULATION_ALLOWED");
  assert.equal(view.canExecuteRobloxTools,false);
  assert.equal(view.realApprovalAvailable,false);
  assert.equal(view.displayOnly,true);
  assert.equal(app.getState().decisions,1);
});
test("expiry, URL mismatch, form flood and invalid origin fail closed",async t=>{
  const app=make({nowMs:()=>now+70000});
  t.after(()=>app.close());
  const origin=await app.start();
  const content=await (await fetch(origin+"/")).text();
  assert.doesNotMatch(content,/name="csrf"/);
  assert.equal((await fetch(origin+"/hidden")).status,404);
  assert.equal((await fetch(origin+"/review",{method:"POST"})).status,403);
  assert.equal(app.getState().revision,0);
  const active=make();t.after(()=>active.close());
  const activeOrigin=await active.start();
  const token=hiddenCsrf(await(await fetch(activeOrigin+"/")).text());
  assert.equal((await fetch(activeOrigin+"/review",{
    method:"POST",redirect:"manual",
    headers:{Origin:activeOrigin,"Content-Type":"application/x-www-form-urlencoded"},
    body:"csrf="+token+"&outcome=DENIED&padding="+"x".repeat(700)
  })).status,413);
  assert.equal(active.getState().revision,0);
});
