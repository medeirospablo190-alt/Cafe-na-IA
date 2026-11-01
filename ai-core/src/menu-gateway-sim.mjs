import {createServer} from "node:http";
import {timingSafeEqual} from "node:crypto";
import {validateMenuProposal,validateMenuReceipt} from "./menu-proposal.mjs";

function json(res,status,body){
  res.writeHead(status,{
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store",
    "X-Content-Type-Options":"nosniff"
  });
  res.end(JSON.stringify(body));
}
function equalTokens(a,b){
  if(typeof a!=="string"||!a.startsWith("Bearer "))return false;
  const x=Buffer.from(a.slice(7)),y=Buffer.from(b);
  return x.length===y.length && timingSafeEqual(x,y);
}
async function readSmallJson(req){
  let size=0,content="";
  for await(const chunk of req){
    size+=chunk.length;
    if(size>2048)throw new Error("RECEIPT_TOO_LARGE");
    content+=chunk.toString("utf8");
  }
  try{return JSON.parse(content);}
  catch{throw new Error("INVALID_JSON");}
}

/**
 * Loopback-only reference gateway. Never import this module in the production gateway.
 * This is not Roblox authentication: callers supply an opaque simulator-only token.
 * Only proposal delivery, acknowledgement and non-execution reports are supported.
 */
export function createMenuGatewaySimulator({proposal,token,nowMs=()=>Date.now()}){
  if(process.env.NODE_ENV==="production"){
    throw new Error("Simulador nao deve executar em producao.");
  }
  validateMenuProposal(proposal);
  if(typeof token!=="string"||token.length<16||token.length>128||
    typeof nowMs!=="function")throw new Error("Credencial de teste invalida.");
  const stored=JSON.parse(JSON.stringify(proposal));
  let status="QUEUED",ack=null,completion=null,polls=0;
  const server=createServer(async(req,res)=>{
    if(!equalTokens(req.headers.authorization,token)){
      json(res,401,{ok:false,error:"UNAUTHORIZED"});return;
    }
    let path;
    try{path=new URL(req.url,"http://127.0.0.1").pathname;}
    catch{json(res,400,{ok:false,error:"INVALID_PATH"});return;}
    if(!Number.isSafeInteger(nowMs())||nowMs()>=stored.expiresAtMs){
      json(res,410,{ok:false,error:"EXPIRED"});return;
    }
    const sessionPath="/v1/mission/"+stored.identity.gameId+"/"+stored.identity.placeId+
      "/"+stored.identity.runId;
    if(req.method==="GET"&&path===sessionPath){
      polls++;
      if(status==="QUEUED")status="DELIVERED";
      json(res,200,{ok:true,status,
        hasProposal:!completion,proposal:completion?null:stored});
      return;
    }
    if(req.method!=="POST"||!["/v1/mission/ack","/v1/mission/report"].includes(path)){
      json(res,404,{ok:false,error:"NOT_FOUND"});return;
    }
    let receipt;
    try{
      receipt=validateMenuReceipt(await readSmallJson(req),stored,{nowMs:nowMs()});
    }catch(error){
      json(res,error.message==="RECEIPT_TOO_LARGE"?413:400,{ok:false,error:"INVALID_RECEIPT"});
      return;
    }
    if(path==="/v1/mission/ack"){
      if(receipt.kind!=="RECEIVED"){
        json(res,422,{ok:false,error:"ACK_KIND_REQUIRED"});return;
      }
      const duplicate=!!ack;
      if(!ack){ack=receipt;status="ACKNOWLEDGED";}
      json(res,200,{ok:true,status,duplicate,approved:false,executed:false});
      return;
    }
    if(!ack){
      json(res,409,{ok:false,error:"ACK_REQUIRED"});return;
    }
    if(!["DECLINED","NOT_EXECUTED"].includes(receipt.kind)){
      json(res,422,{ok:false,error:"NON_EXECUTION_REPORT_ONLY"});return;
    }
    if(completion&&completion.kind!==receipt.kind){
      json(res,409,{ok:false,error:"RESULT_CONFLICT"});return;
    }
    const duplicate=!!completion;
    if(!completion){completion=receipt;status="CLOSED_NO_EXECUTION";}
    json(res,200,{ok:true,status,duplicate,approved:false,executed:false});
  });
  server.on("clientError",(_error,socket)=>{
    if(socket.writable)socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
  });
  return {
    server,
    snapshot:()=>({
      status,polls,acknowledged:!!ack,reported:completion?.kind??null,
      approved:false,executed:false
    }),
    // Explicit loopback restriction; no production bind-address option.
    async start(){
      await new Promise((resolve,reject)=>{
        server.once("error",reject);
        server.listen(0,"127.0.0.1",resolve);
      });
      return "http://127.0.0.1:"+server.address().port;
    },
    async close(){
      if(!server.listening)return;
      await new Promise((resolve,reject)=>server.close(err=>err?reject(err):resolve()));
    }
  };
}
