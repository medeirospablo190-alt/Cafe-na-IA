import {createServer} from "node:http";
import {randomBytes} from "node:crypto";
import {validateCollectorPermissionRequest,reviewCollectorPermission}
  from "./collector-permissions.mjs";
import {createCollectorPermissionEnvelope,applyCollectorPermissionReview}
  from "./github-collector-permissions.mjs";
import {buildSyntheticCollectorPermissionView}
  from "./collector-permission-view.mjs";

const MAX_POST=512;
const HTML_ESCAPES=Object.freeze({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
});
const html=x=>String(x).replace(/[&<>"']/g,c=>HTML_ESCAPES[c]);
const text=(res,status,body,kind="text/plain; charset=utf-8")=>{
  res.writeHead(status,{
    "Content-Type":kind,"Cache-Control":"no-store",
    "X-Content-Type-Options":"nosniff","X-Frame-Options":"DENY",
    "Referrer-Policy":"no-referrer",
    "Content-Security-Policy":"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
  });
  res.end(body);
};
async function readForm(req){
  if(!req.headers["content-type"]?.startsWith("application/x-www-form-urlencoded")){
    throw new Error("BAD_CONTENT_TYPE");
  }
  let bytes=0,body="";
  for await(const chunk of req){
    bytes+=chunk.length;
    if(bytes>MAX_POST)throw new Error("TOO_LARGE");
    body+=chunk.toString("utf8");
  }
  const form=new URLSearchParams(body);
  if([...form.keys()].length!==2||!form.has("csrf")||!form.has("outcome")||
     form.getAll("csrf").length!==1||form.getAll("outcome").length!==1){
    throw new Error("BAD_FIELDS");
  }
  return {csrf:form.get("csrf"),outcome:form.get("outcome")};
}
function page(view,csrf){
  const eligible=view.status==="PENDING_REVIEW";
  const choices=eligible?view.choices.map(choice=>
    '<button type="submit" name="outcome" value="'+html(choice.code)+'"'+
    (choice.code==="DENIED"?' class="deny"':' class="allow"')+'>'+
    html(choice.label)+'</button>'
  ).join(""):"";
  return '<!doctype html><html lang="pt-BR"><head>'+
    '<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'+
    '<title>CAFEINA AI · Revisão local de teste</title>'+
    '<style>'+
    ':root{color-scheme:dark;font:16px system-ui,sans-serif;background:#0b1018;color:#e7eaf2}'+
    'body{min-height:100vh;margin:0;display:grid;place-items:center;padding:20px;box-sizing:border-box}'+
    'main{width:min(100%,580px);background:#141c29;border:1px solid #354253;border-radius:18px;padding:26px;box-sizing:border-box}'+
    'h1{font-size:1.65rem;margin:0 0 12px}h2{font-size:1.08rem}'+
    '.eyebrow{color:#93adcb;font-size:.8rem;letter-spacing:.12em;text-transform:uppercase}'+
    '.warning{border-left:3px solid #e4b25e;padding:12px;background:#222333;line-height:1.5}'+
    '.muted{color:#b4c1d4}.meta{display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:10px 0}'+
    '.meta div{border:1px solid #354253;border-radius:10px;padding:10px;min-width:0;overflow-wrap:anywhere}'+
    '.meta b{display:block;margin-bottom:5px;font-size:.85rem;color:#a8bcce}'+
    'form{display:grid;gap:12px;margin-top:18px}button{cursor:pointer;padding:14px;border:0;border-radius:12px;font-weight:700;font-size:1rem}'+
    '.deny{background:#cfe0f7;color:#0c1730}.allow{background:#a5dbc1;color:#072a20}'+
    'code{overflow-wrap:anywhere;font-size:.85rem}footer{font-size:.82rem;margin-top:22px;color:#aab7c8}'+
    '</style></head><body><main><div class="eyebrow">CAFEINA AI · demonstração offline</div>'+
    '<h1>Revisão de simulação</h1>'+
    '<p class="warning"><strong>Não é uma autorização real.</strong> Esta tela só registra '+
    'decisões locais para testar prévias de metadados. Não identifica pessoas, não '+
    'se conecta ao Roblox e não libera ferramentas de execução.</p>'+
    '<h2>'+html(view.title)+'</h2>'+
    '<p class="muted">Estado: <strong>'+html(view.status)+'</strong></p>'+
    '<section class="meta" aria-label="Limites do pedido">'+
    '<div><b>Ferramenta</b>'+html(view.toolId)+'</div>'+
    '<div><b>Escopo</b>Prévia sintética</div>'+
    '<div><b>Quantidade máxima</b>'+html(view.maxSimulations)+'</div>'+
    '<div><b>Orçamento por prévia</b>'+html(view.secondsPerSimulation)+' s</div>'+
    '</section>'+
    '<p class="muted">Motivo: '+html(view.reasonCode)+'</p>'+
    '<p class="muted">Missão: <code>'+html(view.missionId)+'</code></p>'+
    '<p class="muted">Prazo: <time>'+html(new Date(view.expiresAtMs).toISOString())+'</time></p>'+
    (eligible?
      '<form method="POST" action="/review">'+
      '<input type="hidden" name="csrf" value="'+html(csrf)+'">'+
      choices+'</form>':
      '<p role="status" class="warning">Pedido encerrado ou expirado. '+
      'Não há ações disponíveis.</p>')+
    '<footer>Servidor somente local (127.0.0.1). Nenhum token GitHub, '+
    'senha, nome de jogador ou script é transmitido.</footer>'+
    '</main></body></html>';
}

/**
 * Browser-based permission review simulator with real, local-only form actions.
 * The implicit operator is a synthetic fixture, NOT authenticated user consent.
 * Never exposes GitHub APIs, collector tool dispatch or network forwarding.
 */
export function createCollectorReviewBrowserDemo({
  proposal,request,nowMs=()=>Date.now()
}={}){
  validateCollectorPermissionRequest(request,proposal);
  if(process.env.NODE_ENV==="production"||typeof nowMs!=="function"){
    throw new Error("Interface de teste indisponivel em producao.");
  }
  let state=createCollectorPermissionEnvelope(request,proposal);
  let nonce=randomBytes(32).toString("hex");
  let locked=false,decisions=0;
  const server=createServer(async(req,res)=>{
    const authority="127.0.0.1:"+server.address().port;
    if(req.headers.host!==authority){
      text(res,403,"FORBIDDEN_HOST");return;
    }
    if(req.method==="GET"&&req.url==="/"){
      let model;
      try{model=buildSyntheticCollectorPermissionView(state,proposal,{nowMs:nowMs()});}
      catch{ text(res,503,"INVALID_STATE");return;}
      text(res,200,page(model,nonce),"text/html; charset=utf-8");
      return;
    }
    if(req.method==="GET"&&req.url==="/status"){
      try{
        const view=buildSyntheticCollectorPermissionView(state,proposal,{nowMs:nowMs()});
        // Nothing secret or personally identifying is present in this view.
        text(res,200,JSON.stringify(view),"application/json; charset=utf-8");
      }catch{text(res,503,"INVALID_STATE");}
      return;
    }
    if(req.method!=="POST"||req.url!=="/review"){
      text(res,404,"NOT_FOUND");return;
    }
    if(req.headers.origin!=="http://"+authority){
      text(res,403,"ORIGIN_REQUIRED");return;
    }
    if(locked){text(res,409,"REVIEW_BUSY");return;}
    locked=true;
    try{
      const form=await readForm(req);
      if(form.csrf!==nonce||!["DENIED","SIMULATION_ALLOWED"].includes(form.outcome)){
        text(res,403,"INVALID_SYNTHETIC_REVIEW");return;
      }
      const view=buildSyntheticCollectorPermissionView(state,proposal,{nowMs:nowMs()});
      if(view.status!=="PENDING_REVIEW"){
        text(res,409,"REVIEW_CLOSED");return;
      }
      // A local, in-process test callback. No real identity claims.
      const review=await reviewCollectorPermission(request,proposal,{
        outcome:form.outcome,nowMs:nowMs(),operatorEvidence:nonce,
        verifyTestOperator:async proof=>proof===nonce?{
          verified:true,mode:"SYNTHETIC_TEST_OPERATOR",
          requestId:request.requestId,missionId:request.missionId,
          identity:{...request.identity}
        }:null
      });
      const applied=applyCollectorPermissionReview(state,review,proposal);
      if(applied.status!=="UPDATED")throw new Error("INVALID_TRANSITION");
      state=applied.record;
      nonce=randomBytes(32).toString("hex");
      decisions++;
      res.writeHead(303,{
        Location:"/","Cache-Control":"no-store",
        "Referrer-Policy":"no-referrer"
      });
      res.end();
    }catch(error){
      text(res,error?.message==="TOO_LARGE"?413:400,"INVALID_SYNTHETIC_REVIEW");
    }finally{
      locked=false;
    }
  });
  server.requestTimeout=5000;
  server.headersTimeout=5000;
  return Object.freeze({
    getState:()=>({status:state.status,revision:state.revision,
      outcome:state.review?.outcome??null,decisions,executedInRoblox:false,
      approvedForLiveTools:false,githubPublished:false}),
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
