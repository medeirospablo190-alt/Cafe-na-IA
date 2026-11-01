import {mkdtemp,readFile,writeFile,mkdir,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {Buffer} from "node:buffer";
import path from "node:path";
import {persistSession} from "./store.mjs";

export const KNOWLEDGE_BRANCH="cafeina-ai-knowledge";
const ID=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const SHA=/^[0-9a-f]{64}$/;
const REPO=/^[a-zA-Z0-9_.-]{1,100}\/[a-zA-Z0-9_.-]{1,100}$/;
const KIND=/^[a-z][a-z0-9_]{0,63}$/;
const UNKNOWN=/^[A-Z_]{2,64}$/;

function object(x){return x && typeof x==="object" && !Array.isArray(x);}
function keysExactly(x,expected){
  return object(x) && Object.keys(x).every(k=>expected.includes(k)) &&
    expected.every(k=>Object.hasOwn(x,k));
}
function verifyStored(source,gameId){
  if(!keysExactly(source,["schemaVersion","type","gameId","sessions","totals","knowledge"])||
    source.schemaVersion!==1||source.type!=="cafeina_ai_game_knowledge"||
    source.gameId!==gameId||!object(source.sessions)||
    Object.keys(source.sessions).length>1000)throw new Error("Memoria GitHub invalida.");
  const out=Object.create(null),aggregated=Object.create(null),knowledge=Object.create(null);
  for(const [runId,run] of Object.entries(source.sessions)){
    if(!RUN.test(runId)||!keysExactly(run,[
      "placeId","runId","manifestSha256","batchChecksums","kindCounts",
      "observedRecords","completeBatchSequence","unknownCodes","verification"
    ])||run.runId!==runId||typeof run.placeId!=="string"||!ID.test(run.placeId)||
      typeof run.manifestSha256!=="string"||!SHA.test(run.manifestSha256)||
      !object(run.batchChecksums)||Object.keys(run.batchChecksums).length>520||
      !object(run.kindCounts)||Object.keys(run.kindCounts).length>200||
      !Array.isArray(run.unknownCodes)||run.unknownCodes.length>10||
      run.verification!=="EXPERIMENTAL"||typeof run.completeBatchSequence!=="boolean"||
      !Number.isSafeInteger(run.observedRecords)||run.observedRecords<0){
      throw new Error("Sessao remota invalida.");
    }
    const checksums=Object.entries(run.batchChecksums);
    if(checksums.some(([index,sha])=>!/^[1-9][0-9]{0,2}$/.test(index)||
      Number(index)>520||typeof sha!=="string"||!SHA.test(sha)))throw new Error("Lote remoto invalido.");
    const kindCounts=Object.entries(run.kindCounts);
    if(kindCounts.some(([kind,count])=>!KIND.test(kind)||!Number.isSafeInteger(count)||
      count<0))throw new Error("Contador remoto invalido.");
    const total=kindCounts.reduce((sum,[kind,count])=>sum+count,0);
    if(total!==run.observedRecords)throw new Error("Total remoto divergente.");
    if(run.unknownCodes.some(code=>typeof code!=="string"||!UNKNOWN.test(code))){
      throw new Error("Desconhecido remoto invalido.");
    }
    const clean={
      placeId:run.placeId,runId,manifestSha256:run.manifestSha256,
      batchChecksums:Object.fromEntries(checksums.sort(([a],[b])=>Number(a)-Number(b))),
      kindCounts:Object.fromEntries(kindCounts.sort(([a],[b])=>a.localeCompare(b))),
      observedRecords:run.observedRecords,
      completeBatchSequence:run.completeBatchSequence,
      unknownCodes:[...new Set(run.unknownCodes)].sort(),
      verification:"EXPERIMENTAL"
    };
    out[runId]=clean;
    for(const [kind,count] of kindCounts)aggregated[kind]=(aggregated[kind]??0)+count;
    for(const code of clean.unknownCodes){
      knowledge[code]??={status:"EXPERIMENTAL",observedRuns:0};
      knowledge[code].observedRuns++;
    }
  }
  return {
    schemaVersion:1,type:"cafeina_ai_game_knowledge",gameId,
    sessions:Object.fromEntries(Object.entries(out).sort(([a],[b])=>a.localeCompare(b))),
    totals:{
      knownRuns:Object.keys(out).length,
      eventKinds:Object.fromEntries(Object.entries(aggregated).sort(([a],[b])=>a.localeCompare(b)))
    },
    knowledge:Object.fromEntries(Object.entries(knowledge).sort(([a],[b])=>a.localeCompare(b)))
  };
}
function headers(token){
  return {
    Accept:"application/vnd.github+json",
    "X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"cafeina-ai-knowledge",
    ...(token?{Authorization:"Bearer "+token}:{})
  };
}
export async function syncGithubKnowledge({
  repository,report,token="",branch=KNOWLEDGE_BRANCH,dryRun=true,
  request=fetch,maxAttempts=3
}){
  const gameId=report?.identity?.gameId;
  if(!REPO.test(repository??"")||branch!==KNOWLEDGE_BRANCH||
    typeof gameId!=="string"||!ID.test(gameId)||
    !Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>3){
    throw new Error("Configuracao de memoria invalida.");
  }
  if(!dryRun&&(!token||typeof token!=="string")){
    throw new Error("Token de escrita necessario.");
  }
  const endpoint="https://api.github.com/repos/"+repository+
    "/contents/ai-core/knowledge/"+gameId+".json";
  for(let attempt=1;attempt<=maxAttempts;attempt++){
    const response=await request(endpoint+"?ref="+branch,{
      method:"GET",headers:headers(token)
    });
    let existing=null,sha;
    if(response.status===200){
      const remote=await response.json();
      if(remote.type!=="file"||remote.encoding!=="base64"||
        typeof remote.sha!=="string"||!/^[a-f0-9]{40}$/.test(remote.sha)||
        typeof remote.content!=="string"||remote.content.length>900_000||
        !/^[A-Za-z0-9+/=\s]+$/.test(remote.content)){
        throw new Error("Resposta GitHub de memoria invalida.");
      }
      const raw=Buffer.from(remote.content.replace(/\s+/g,""),"base64");
      if(raw.length>600_000)throw new Error("Arquivo de memoria excede 600 KB.");
      existing=verifyStored(JSON.parse(raw.toString("utf8")),gameId);
      sha=remote.sha;
    }else if(response.status!==404){
      throw new Error("Falha GitHub ao ler memoria (HTTP "+response.status+").");
    }
    const dir=await mkdtemp(path.join(tmpdir(),"cafeina-github-sync-"));
    let status,content,totalRuns;
    try{
      if(existing){
        await mkdir(dir,{recursive:true});
        await writeFile(path.join(dir,gameId+".json"),JSON.stringify(existing)+"\n",{mode:0o600,flag:"wx"});
      }
      const saved=await persistSession(dir,report);
      status=saved.status;totalRuns=saved.totalRuns;
      content=await readFile(path.join(dir,gameId+".json"),"utf8");
    }finally{
      await rm(dir,{recursive:true,force:true});
    }
    if(Buffer.byteLength(content)>600_000)throw new Error("Indice excede 600 KB.");
    if(status==="UNCHANGED"){
      return {status,gameId,totalRuns,published:false};
    }
    if(dryRun){
      return {status:"DRY_RUN",plannedStatus:status,gameId,totalRuns,published:false};
    }
    const put=await request(endpoint,{
      method:"PUT",
      headers:{...headers(token),"Content-Type":"application/json"},
      body:JSON.stringify({
        message:"CAFEINA AI sanitized knowledge "+gameId,
        content:Buffer.from(content).toString("base64"),
        branch,
        ...(sha?{sha}:{})
      })
    });
    if(put.ok)return {status,gameId,totalRuns,published:true};
    if(put.status===409||put.status===422){
      if(attempt<maxAttempts)continue;
      throw new Error("CONFLICT: memoria alterada durante gravacao.");
    }
    throw new Error("Falha GitHub ao salvar memoria (HTTP "+put.status+").");
  }
  throw new Error("Memoria nao sincronizada.");
}
