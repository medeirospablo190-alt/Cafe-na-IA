import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mkdtemp, readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { analyzeSession, summarizeProfile } from "../src/session.mjs";
import { persistSession } from "../src/store.mjs";
import { analyzeDirectory } from "../src/session-cli.mjs";
import { DataError } from "../src/schema.mjs";

const fixture = p => JSON.parse(readFileSync(new URL("fixtures/"+p, import.meta.url), "utf8"));
const seed = () => fixture("batch.json");
const manifest = () => fixture("latest.json");
const second = () => ({
  ...seed(), batchIndex: 2, records: [
    { kind: "remote_outbound", unix: 10, player: "DONOTCOPY_PII" },
    { kind: "workspace_added", unix: 11, payload: { secret:"DONOTCOPY_SECRET" } }
  ]
});
const profile = () => ({
  schemaVersion:3,gameId:101,revision:2,sessions:2,
  investigationKnowledge:[
    { status:"observed", key:"DONOTCOPY_PROFILE_KEY"},
    { status:"passive", key:"DONOTCOPY_PROFILE_SECRET"}
  ],
  frontier:["DONOTCOPY_FRONTIER"]
});

test("multiplos lotes, somatorios, evidencias e status de cobertura",()=>{
  const latest={...manifest(),manifest:{...manifest().manifest,dataBatches:2}};
  const report=analyzeSession({batches:[second(),seed()],manifest:latest,profile:profile()});
  assert.equal(report.observations.recordCount,6);
  assert.equal(report.observations.kindCounts.remote_outbound,2);
  assert.equal(report.coverage.expectedDataBatches,2);
  assert.deepEqual(report.coverage.missingBatchIndices,[]);
  assert.equal(report.coverage.completeBatchSequence,true);
  assert.equal(report.sources.batchChecksums["2"].length,64);
  assert.equal(report.profile.investigationStatuses.passive,1);
  assert.equal(report.profile.investigationCount,2);
  assert.equal(report.mission.status,"PROPOSED");
  assert.equal(report.mission.executable,false);
  assert.ok(!JSON.stringify(report).includes("DONOTCOPY"));
  assert.ok(!JSON.stringify(report).includes("TEST_SECRET"));
});

test("deduplica lote identico; rejeita conflito e cruzamento de jogos",()=>{
  const output=analyzeSession({batches:[seed(),seed()],manifest:manifest()});
  assert.equal(output.sources.identicalDuplicates,1);
  assert.equal(output.observations.recordCount,4);
  assert.throws(()=>analyzeSession({
    batches:[seed(), {...seed(),records:[{kind:"trajectory"}]}],
    manifest:manifest()
  }),/CONFLICT/);
  assert.throws(()=>analyzeSession({batches:[{...seed(),gameId:102}],manifest:manifest()}),DataError);
  assert.throws(()=>summarizeProfile({...profile(),gameId:102},"101"),DataError);
});

test("marca lacunas; nunca inventa causa ou reconstrucao",()=>{
  const latest={...manifest(),manifest:{...manifest().manifest,dataBatches:3}};
  const report=analyzeSession({batches:[seed(),{...second(),batchIndex:3}],manifest:latest});
  assert.deepEqual(report.coverage.missingBatchIndices,[2]);
  assert.equal(report.coverage.completeBatchSequence,false);
  assert.ok(report.unknowns.some(x=>x.code==="MISSING_BATCHES"));
  assert.equal(report.coverage.causalValidation,false);
  assert.equal(report.coverage.mechanicsReconstructed,0);
});

test("memoria por jogo persiste, agrega e impede conflitos entre sessoes",async t=>{
  const dir=await mkdtemp(path.join(tmpdir(),"cafeina-memory-"));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const first=analyzeSession({batches:[seed()],manifest:manifest()});
  assert.equal((await persistSession(dir,first)).status,"CREATED");
  assert.equal((await persistSession(dir,first)).status,"UNCHANGED");
  const differentRun="demo-run-0002";
  const later=analyzeSession({
    batches:[{...seed(),runId:differentRun}],
    manifest:{...manifest(),runId:differentRun}
  });
  assert.equal((await persistSession(dir,later)).totalRuns,2);
  const doc=await readFile(path.join(dir,"101.json"),"utf8");
  const stored=JSON.parse(doc);
  assert.equal(stored.totals.knownRuns,2);
  assert.equal(stored.knowledge.CAUSALITY_NOT_PROVEN.status,"EXPERIMENTAL");
  assert.equal(stored.knowledge.CAUSALITY_NOT_PROVEN.observedRuns,2);
  assert.ok(!doc.includes("TEST_SECRET"));
  const changed=analyzeSession({batches:[{...seed(),records:[{kind:"gui_state"}]}],manifest:manifest()});
  await assert.rejects(()=>persistSession(dir,changed),/CONFLICT/);
  assert.equal(JSON.parse(await readFile(path.join(dir,"101.json"),"utf8")).totals.knownRuns,2);
});

test("memoria recebe lotes tardios de mesma sessao sem dobrar contadores",async t=>{
  const dir=await mkdtemp(path.join(tmpdir(),"cafeina-later-"));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const m={...manifest(),manifest:{...manifest().manifest,dataBatches:2}};
  const partial=analyzeSession({batches:[seed()],manifest:m});
  assert.equal((await persistSession(dir,partial)).status,"CREATED");
  const full=analyzeSession({batches:[seed(),second()],manifest:m});
  assert.equal((await persistSession(dir,full)).status,"UPDATED");
  const stored=JSON.parse(await readFile(path.join(dir,"101.json"),"utf8"));
  assert.equal(stored.totals.knownRuns,1);
  assert.equal(stored.totals.eventKinds.remote_outbound,2);
});

test("CLI importa diretório de sessão realista sem expor payload",async t=>{
  const root=await mkdtemp(path.join(tmpdir(),"cafeina-cli-"));
  t.after(()=>rm(root,{recursive:true,force:true}));
  const dir=path.join(root,"session");await mkdir(dir);
  await writeFile(path.join(dir,"0001-data.json"),JSON.stringify(seed()));
  await writeFile(path.join(dir,"0002-data.json"),JSON.stringify(second()));
  const m={...manifest(),manifest:{...manifest().manifest,dataBatches:2}};
  const mf=path.join(root,"latest.json"), pf=path.join(root,"profile.json");
  await writeFile(mf,JSON.stringify(m));
  await writeFile(pf,JSON.stringify(profile()));
  const out=path.join(root,"analysis.json");
  const result=await analyzeDirectory({
    "--session-dir":dir,"--manifest":mf,"--profile":pf,
    "--store":path.join(root,"store"),"--out":out
  });
  assert.equal(result.coverage.completeBatchSequence,true);
  assert.equal(result.persistence.status,"CREATED");
  const saved=await readFile(out,"utf8");
  assert.ok(!saved.includes("DONOTCOPY"));
  assert.ok(!saved.includes("TEST_SECRET"));
  await assert.rejects(()=>analyzeDirectory({
    "--session-dir":dir,"--manifest":mf,"--out":out
  }),/EEXIST/);
  await writeFile(path.join(dir,"0002-data.json"),JSON.stringify({...second(),batchIndex:5}));
  await assert.rejects(()=>analyzeDirectory({
    "--session-dir":dir,"--manifest":mf
  }),/divergentes/);
});

test("sem contagem oficial nao declara sessao completa",()=>{
  const r=analyzeSession({batches:[seed()],manifest:manifest()});
  assert.equal(r.coverage.batchCountDeclared,false);
  assert.equal(r.coverage.completeBatchSequence,false);
  assert.ok(r.unknowns.some(x=>x.code==="BATCH_COUNT_UNREPORTED"));
});
