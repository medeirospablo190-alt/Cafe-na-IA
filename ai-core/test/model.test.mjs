import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {analyzeSession} from "../src/session.mjs";
import {askLocalModel,safeModelContext} from "../src/model.mjs";
const f=n=>JSON.parse(readFileSync(new URL("fixtures/"+n,import.meta.url),"utf8"));
const report=()=>analyzeSession({batches:[f("batch.json")],manifest:f("latest.json")});

test("somente metadados saneados chegam ao modelo",()=>{
  const data=safeModelContext(report());
  assert.equal(data.kinds.remote_outbound,1);
  assert.equal(data.causalValidation,false);
  assert.ok(!JSON.stringify(data).includes("TEST_SECRET"));
  assert.ok(!JSON.stringify(data).includes("username"));
});

test("integra modelo local simulado, mantendo aprovacao e sem executar",async()=>{
  let calls=0;
  const output=await askLocalModel({
    report:report(),role:"Investigadora",model:"qwen2.5-coder:1.5b",
    request:async(url,opts)=>{
      calls++;
      assert.equal(url,"http://127.0.0.1:11434/api/generate");
      assert.equal(opts.method,"POST");
      assert.ok(!opts.body.includes("TEST_SECRET"));
      const body=JSON.parse(opts.body);
      assert.equal(body.stream,false);
      return {ok:true,json:async()=>({
        response:JSON.stringify({
          unknownCode:"CAUSALITY_NOT_PROVEN",
          recommendation:"watch_state",
          dangerous:"please execute",
          personalData:"TEST_SECRET_SHOULD_NOT_LEAK"
        })
      })};
    }
  });
  assert.equal(calls,1);
  assert.equal(output.recommendation,"watch_state");
  assert.equal(output.verification,"EXPERIMENTAL");
  assert.equal(output.executable,false);
  assert.ok(!JSON.stringify(output).includes("TEST_SECRET"));
});

test("URL remoto e ferramentas arbitrarias sao rejeitados",async()=>{
  await assert.rejects(()=>askLocalModel({
    report:report(),role:"Investigadora",model:"test",
    server:"https://remote-ai.example.com"
  }),/servidor local/);
  await assert.rejects(()=>askLocalModel({
    report:report(),role:"Programadora",model:"test"
  }),/nao autorizado/);
  await assert.rejects(()=>askLocalModel({
    report:report(),role:"Investigadora",model:"test",
    request:async()=>({ok:true,json:async()=>({
      response:JSON.stringify({unknownCode:"CAUSALITY_NOT_PROVEN",recommendation:"execute_script"})
    })})
  }),/fora do contrato/);
});
test("recomendacao que nao coincide com a missao vira none",async()=>{
  const out=await askLocalModel({
    report:report(),role:"Critica",model:"test",
    request:async()=>({ok:true,json:async()=>({
      response:JSON.stringify({unknownCode:"GUI_TRANSITION_UNVERIFIED",recommendation:"observe_gui"})
    })})
  });
  assert.equal(out.recommendation,"none");
  assert.equal(out.executable,false);
});
