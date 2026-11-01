import test from "node:test";
import assert from "node:assert/strict";
import {selectedPaths} from "../src/knowledge-workflow.mjs";
test("identifica caminhos seguros de sessao",()=>{
  const p=selectedPaths({
    CAFEINA_GAME_ID:"101",CAFEINA_PLACE_ID:"202",
    CAFEINA_RUN_ID:"demo-run-0001"
  });
  assert.ok(p.sessionDir.endsWith("inventory-traces-v3/101/202/demo-run-0001"));
  assert.ok(p.manifest.endsWith("101/202/latest.json"));
});
test("rejeita entradas perigosas",()=>{
  for(const value of ["../token","0","-1","abc","101/202"]){
    assert.throws(()=>selectedPaths({
      CAFEINA_GAME_ID:value,CAFEINA_PLACE_ID:"202",CAFEINA_RUN_ID:"demo-run-0001"
    }),/invalidos/);
  }
  assert.throws(()=>selectedPaths({
    CAFEINA_GAME_ID:"101",CAFEINA_PLACE_ID:"202",CAFEINA_RUN_ID:"../../token"
  }),/invalidos/);
});
