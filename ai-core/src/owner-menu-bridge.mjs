import {createServer} from "node:http";
import {timingSafeEqual} from "node:crypto";
import {readGithubMenuProposal} from "./github-menu-queue.mjs";
import {readGithubMenuDelivery,syncGithubMenuDeliveryEvent} from "./github-menu-receipts.mjs";

const GAME=/^[1-9][0-9]{0,19}$/;
const RUN=/^[A-Za-z0-9_-]{6,128}$/;
const MISSION=/^mission-[a-f0-9]{16}$/;
const JOB=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const REPO=/^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const OPERATIONS={POLL:"DELIVERED",ACK:"RECEIVED",DECLINE:"DECLINED",NO_EXECUTION:"NOT_EXECUTED"};
const BODY_KEYS=["schemaVersion","operation","gameId","placeId","runId","missionId","jobId"];
const own=(obj,keys)=>obj&&typeof obj==="object"&&!Array.isArray(obj)&&
  Object.keys(obj).length===keys.length&&keys.every(k=>Object.hasOwn(obj,k));

function respond(res,status,payload){
  res.writeHead(status,{"Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store","X-Content-Type-Options":"nosniff"});
  res.end(JSON.stringify(payload));
}
function keyMatches(provided,expected){
  if(typeof provided!=="string"||typeof expected!=="string")return false;
  const a=Buffer.from(provided),b=Buffer.from(expected);
  return a.length===b.length&&timingSafeEqual(a,b);
}
async function bodyJSON(req){
  let count=0;
  const chunks=[];
  for await(const chunk of req){
    count+=chunk.length;
    if(count>1024)throw new Error("TOO_LARGE");
    chunks.push(chunk);
  }
  const raw=Buffer.concat(chunks).toString("utf8");
  try{return JSON.parse(raw);}catch{throw new Error("INVALID_JSON");}
}

/**
 * Server-to-server ONLY, one explicitly provisioned job/mission. No Roblox
 * client tokens and no execution tools. HTTPS termination is the deployer's
 * responsibility; do not expose its raw HTTP port to the public internet.
 */
export function createOwnerMenuBridge({
  repository,githubToken,serverKey,identity,missionId,jobId,
  request=fetch,nowMs=()=>Date.now(),pollCooldownMs=2500
}={}){
  if(!REPO.test(repository??"")||
    typeof githubToken!=="string"||githubToken.length<8||
    typeof serverKey!=="string"||serverKey.length<32||serverKey.length>128||
    !identity||!GAME.test(identity.gameId??"")||!GAME.test(identity.placeId??"")||
    !RUN.test(identity.runId??"")||!MISSION.test(missionId??"")||
    !JOB.test(jobId??"")||typeof request!=="function"||typeof nowMs!=="function"||
    !Number.isInteger(pollCooldownMs)||pollCooldownMs<0||pollCooldownMs>60000){
    throw new Error("Bridge requires a pre-authorized job, mission and server-only secrets.");
  }
  const scope={...identity};
  let nextPollAt=0,inFlight=false;

  const httpServer=createServer(async(req,res)=>{
    const path=req.url?.split("?")[0];
    if(req.method==="GET"&&path==="/health"){
      respond(res,200,{ok:true,component:"CAFEINA_OWNER_MENU_BRIDGE",status:"RUNNING"});
      return;
    }
    if(req.method!=="POST"||path!=="/v1/roblox/menu"){
      respond(res,404,{ok:false,error:"NOT_FOUND"});
      return;
    }
    if(!keyMatches(req.headers["x-cafeina-server-key"],serverKey)){
      respond(res,401,{ok:false,error:"UNAUTHORIZED"});return;
    }
    if(inFlight){
      respond(res,429,{ok:false,error:"BRIDGE_BUSY"});return;
    }
    let body;
    try{body=await bodyJSON(req);}
    catch(error){
      respond(res,error.message==="TOO_LARGE"?413:400,
        {ok:false,error:"INVALID_REQUEST"});return;
    }
    if(!own(body,BODY_KEYS)||body.schemaVersion!==1||
      !Object.hasOwn(OPERATIONS,body.operation)||
      body.gameId!==scope.gameId||body.placeId!==scope.placeId||
      body.runId!==scope.runId||body.missionId!==missionId||body.jobId!==jobId){
      respond(res,403,{ok:false,error:"SCOPE_REJECTED"});return;
    }
    const now=nowMs();
    if(!Number.isSafeInteger(now)||now<0){
      respond(res,503,{ok:false,error:"CLOCK_UNAVAILABLE"});return;
    }
    if(body.operation==="POLL"&&now<nextPollAt){
      respond(res,429,{ok:false,error:"POLL_SLOW_DOWN"});return;
    }
    inFlight=true;
    try{
      const args={repository,gameId:scope.gameId,missionId,token:githubToken,request};
      const result=await readGithubMenuProposal(args);
      if(result.status!=="FOUND"){
        respond(res,404,{ok:false,error:"MISSION_NOT_FOUND"});return;
      }
      const proposal=result.proposal;
      if(proposal.identity.gameId!==scope.gameId||
         proposal.identity.placeId!==scope.placeId||
         proposal.identity.runId!==scope.runId||
         proposal.missionId!==missionId||
         proposal.approved!==false||proposal.executable!==false){
        respond(res,403,{ok:false,error:"PROPOSAL_SCOPE_REJECTED"});return;
      }
      if(now<proposal.issuedAtMs||now>=proposal.expiresAtMs){
        respond(res,410,{ok:false,error:"MISSION_EXPIRED"});return;
      }
      if(body.operation==="POLL"){
        nextPollAt=now+pollCooldownMs;
        const prior=await readGithubMenuDelivery({
          repository,proposal,token:githubToken,request
        });
        if(prior.state?.status==="CLOSED_NO_EXECUTION"){
          respond(res,200,{ok:true,status:"CLOSED_NO_EXECUTION",
            hasProposal:false,proposal:null,approved:false,executed:false});
          return;
        }
      }
      const event=OPERATIONS[body.operation];
      const saved=await syncGithubMenuDeliveryEvent({
        repository,proposal,event,token:githubToken,
        dryRun:false,request,nowMs:now
      });
      if(!["SAVED","UNCHANGED"].includes(saved.status)){
        throw new Error("RECEIPT_NOT_DURABLE");
      }
      const visible=body.operation==="POLL";
      respond(res,200,{
        ok:true,status:saved.deliveryStatus,
        hasProposal:visible,
        proposal:visible?{
          missionId:proposal.missionId,toolId:proposal.toolId,
          durationSeconds:proposal.params.durationSeconds,
          expiresAtMs:proposal.expiresAtMs,
          approved:false,executable:false
        }:null,
        approved:false,executed:false
      });
    }catch{
      // Never return server secrets, GitHub errors or personal data.
      respond(res,503,{ok:false,error:"BRIDGE_BACKEND_UNAVAILABLE"});
    }finally{
      inFlight=false;
    }
  });
  httpServer.on("clientError",(_error,socket)=>{
    if(socket.writable)socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
  });
  return Object.freeze({
    server:httpServer,
    async start({host="127.0.0.1",port=0}={}){
      if(!Number.isInteger(port)||port<0||port>65535)throw new Error("Invalid port.");
      await new Promise((resolve,reject)=>{
        httpServer.once("error",reject);
        httpServer.listen(port,host,resolve);
      });
      return httpServer.address();
    },
    async close(){
      if(!httpServer.listening)return;
      await new Promise((resolve,reject)=>httpServer.close(err=>err?reject(err):resolve()));
    }
  });
}
