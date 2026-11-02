import {createServer} from "node:http";
import {validateMenuProposal} from "./menu-proposal.mjs";

function reply(res,status,data){
  res.writeHead(status,{
    "Content-Type":"application/json; charset=utf-8",
    "Cache-Control":"no-store",
    "X-Content-Type-Options":"nosniff"
  });
  res.end(JSON.stringify(data));
}
async function readSmallJson(req){
  let length=0,body="";
  for await(const chunk of req){
    length+=chunk.length;
    if(length>1024)throw new Error("TOO_LARGE");
    body+=chunk.toString("utf8");
  }
  try{return JSON.parse(body);}
  catch{throw new Error("BAD_JSON");}
}

/**
 * Loopback-only HTTP transport contract. THIS IS NOT A DEPLOYABLE GATEWAY.
 * The server-only Roblox Secret is carried exclusively in x-api-key and
 * never forwarded with the returned limited, signed proposal capability.
 */
export function createRobloxCheckinSimulator({proposal,authority}={}){
  if(process.env.NODE_ENV==="production"){
    throw new Error("Check-in simulado nao executa em producao.");
  }
  validateMenuProposal(proposal);
  if(typeof authority?.issue!=="function"||
     typeof authority?.verify!=="function"){
    throw new Error("Emissor de tokens nao configurado.");
  }
  let attempts=0,issued=0;
  const server=createServer(async(req,res)=>{
    if(req.method!=="POST"||req.url!=="/v1/server/checkin"){
      reply(res,404,{ok:false,error:"NOT_FOUND"});return;
    }
    attempts++;
    if(attempts>10){
      reply(res,429,{ok:false,error:"RATE_LIMITED"});return;
    }
    if(typeof req.headers["x-api-key"]!=="string"){
      reply(res,401,{ok:false,error:"SERVER_KEY_REQUIRED"});return;
    }
    let body;
    try{
      body=await readSmallJson(req);
    }catch(error){
      reply(res,error.message==="TOO_LARGE"?413:400,{
        ok:false,error:"INVALID_CHECKIN"
      });return;
    }
    try{
      const token=await authority.issue(proposal,{
        headers:{"x-api-key":req.headers["x-api-key"]},
        body
      },{ttlMs:60000});
      issued++;
      reply(res,200,{ok:true,mode:"PROPOSAL_READ_ONLY",
        sessionToken:token,approved:false,executable:false});
    }catch{
      reply(res,403,{ok:false,error:"UNTRUSTED_SERVER"});
    }
  });
  server.on("clientError",(_error,socket)=>{
    if(socket.writable){
      socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
    }
  });
  return Object.freeze({
    snapshot:()=>({attempts,issued,transport:"HTTP_LOOPBACK_ONLY"}),
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
  });
}
