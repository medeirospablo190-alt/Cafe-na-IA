import {Buffer} from "node:buffer";
import {validatePlanningTask,assertTaskUpdate} from "./task-engine.mjs";

export const TASK_BRANCH="cafeina-ai-knowledge";
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const GAME=/^[1-9][0-9]{0,19}$/;
const TASK=/^task-[a-f0-9]{16}$/;
const SHA=/^[a-f0-9]{40}$/;
const MAX_BYTES=8192;
function location(repository,branch,gameId,taskId){
  if(typeof repository!=="string"||!REPO.test(repository)||branch!==TASK_BRANCH||
     typeof gameId!=="string"||!GAME.test(gameId)||
     typeof taskId!=="string"||!TASK.test(taskId)){
    throw new Error("Destino GitHub de tarefa nao autorizado.");
  }
  return "https://api.github.com/repos/"+repository+
    "/contents/ai-core/tasks/"+gameId+"/"+taskId+".json";
}
function headers(token){
  return {
    Accept:"application/vnd.github+json",
    "X-GitHub-Api-Version":"2022-11-28",
    "User-Agent":"cafeina-ai-task-state",
    ...(token?{Authorization:"Bearer "+token}:{})
  };
}
export async function readGithubPlanningTask({
  repository,gameId,taskId,branch=TASK_BRANCH,token="",request=fetch
}){
  const url=location(repository,branch,gameId,taskId);
  const response=await request(url+"?ref="+encodeURIComponent(branch),{
    method:"GET",headers:headers(token)
  });
  if(response.status===404)return {status:"MISSING",task:null,sha:null};
  if(response.status!==200)throw new Error("GitHub task read HTTP "+response.status);
  const result=await response.json();
  if(result?.type!=="file"||result.encoding!=="base64"||
     typeof result.sha!=="string"||!SHA.test(result.sha)||
     typeof result.content!=="string"||result.content.length>16000||
     !/^[A-Za-z0-9+/=\s]+$/.test(result.content)){
    throw new Error("Resposta GitHub de tarefa invalida.");
  }
  const payload=Buffer.from(result.content.replace(/\s+/g,""),"base64");
  if(payload.byteLength>MAX_BYTES)throw new Error("Tarefa remota muito grande.");
  const task=validatePlanningTask(JSON.parse(payload.toString("utf8")));
  if(task.identity.gameId!==gameId||task.taskId!==taskId){
    throw new Error("Tarefa remota nao corresponde ao caminho.");
  }
  return {status:"FOUND",task,sha:result.sha};
}
export async function syncGithubPlanningTask({
  repository,task,branch=TASK_BRANCH,token="",dryRun=true,
  expectedRevision=null,request=fetch,maxAttempts=3
}){
  validatePlanningTask(task);
  const url=location(repository,branch,task.identity.gameId,task.taskId);
  if(expectedRevision!==null&&(!Number.isInteger(expectedRevision)||expectedRevision<0)){
    throw new Error("Revisao esperada invalida.");
  }
  if(!dryRun&&(!token||typeof token!=="string")){
    throw new Error("Publicacao requer token GitHub.");
  }
  if(!Number.isInteger(maxAttempts)||maxAttempts<1||maxAttempts>3){
    throw new Error("Tentativas fora do limite.");
  }
  const serialized=JSON.stringify(task,null,2)+"\n";
  if(Buffer.byteLength(serialized)>MAX_BYTES)throw new Error("Tarefa excede limite.");
  for(let attempt=0;attempt<maxAttempts;attempt++){
    const remote=await readGithubPlanningTask({
      repository,gameId:task.identity.gameId,taskId:task.taskId,branch,token,request
    });
    if(remote.task&&JSON.stringify(remote.task)===JSON.stringify(task)){
      return {status:"UNCHANGED",published:false,revision:task.revision,taskId:task.taskId};
    }
    if(remote.task&&remote.task.revision!==expectedRevision){
      throw new Error("CONFLICT: revisao remota mudou.");
    }
    if(!remote.task&&expectedRevision!==null){
      throw new Error("CONFLICT: tarefa remota nao existe.");
    }
    assertTaskUpdate(remote.task,task);
    if(dryRun)return {
      status:"DRY_RUN",published:false,revision:task.revision,taskId:task.taskId
    };
    const response=await request(url,{
      method:"PUT",
      headers:{...headers(token),"Content-Type":"application/json"},
      body:JSON.stringify({
        message:"CAFEINA AI sanitized planning task "+task.taskId,
        content:Buffer.from(serialized).toString("base64"),
        branch,
        ...(remote.sha?{sha:remote.sha}:{})
      })
    });
    if(response.ok)return {
      status:"SAVED",published:true,revision:task.revision,taskId:task.taskId
    };
    if((response.status===409||response.status===422)&&attempt+1<maxAttempts)continue;
    if(response.status===409||response.status===422){
      throw new Error("CONFLICT: API recusou gravacao.");
    }
    throw new Error("GitHub task write HTTP "+response.status);
  }
  throw new Error("Tarefa nao sincronizada.");
}
