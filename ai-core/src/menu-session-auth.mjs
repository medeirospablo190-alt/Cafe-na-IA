import {createHash,createHmac,randomBytes,timingSafeEqual} from "node:crypto";
import {validateMenuProposal} from "./menu-proposal.mjs";

const ALLOWED_SCOPES=["READ_PROPOSAL","SEND_NON_EXECUTION_RECEIPT"];
const FIELDS=["v","aud","jti","missionId","identity","proposalHash","iatMs","expMs","scopes"];
const HEX=/^[a-f0-9]{64}$/;
const JTI=/^[a-f0-9]{32}$/;
function exact(value,fields){
  return value&&typeof value==="object"&&!Array.isArray(value)&&
    Object.keys(value).length===fields.length&&fields.every(key=>Object.hasOwn(value,key));
}
function sameIdentity(a,b){
  return exact(a,["gameId","placeId","runId"]) &&
    a.gameId===b.gameId&&a.placeId===b.placeId&&a.runId===b.runId;
}
function time(n){return Number.isSafeInteger(n)&&n>=0;}
function proposalHash(proposal){
  return createHash("sha256").update(JSON.stringify(proposal)).digest("hex");
}
function allowedClaims(c,proposal,nowMs){
  return exact(c,FIELDS)&&c.v===1&&c.aud==="CAFEINA_MENU_PROPOSAL_V1"&&
    JTI.test(c.jti??"")&&c.missionId===proposal.missionId&&
    sameIdentity(c.identity,proposal.identity)&&
    c.proposalHash===proposalHash(proposal)&&HEX.test(c.proposalHash)&&
    time(c.iatMs)&&time(c.expMs)&&c.expMs>c.iatMs&&
    c.expMs-c.iatMs<=300000&&c.iatMs>=proposal.issuedAtMs&&
    c.expMs<=proposal.expiresAtMs&&nowMs>=c.iatMs&&nowMs<c.expMs&&
    Array.isArray(c.scopes)&&c.scopes.length===ALLOWED_SCOPES.length&&
    c.scopes.every((scope,i)=>scope===ALLOWED_SCOPES[i]);
}

/**
 * Prototype for server-issued narrow bearer capabilities.
 *
 * IMPORTANT: validateTrustedServerSession MUST independently authenticate the
 * experience server / its authorization. It cannot trust any client-provided
 * IDs, strings or headers as proof. No Roblox attestation is implemented here.
 *
 * This HMAC token never permits Roblox tools, code execution, or approval.
 */
export function createMenuSessionAuthority({
  signingKey,validateTrustedServerSession,nowMs=()=>Date.now()
}={}){
  if(!(signingKey instanceof Uint8Array)||signingKey.byteLength<32||
     signingKey.byteLength>128||
     typeof validateTrustedServerSession!=="function"||
     typeof nowMs!=="function"){
    throw new Error("Autoridade de sessao exige chave e verificador de servidor.");
  }
  const key=Buffer.from(signingKey);
  function readTime(){
    const t=nowMs();
    if(!time(t))throw new Error("Relogio de servidor invalido.");
    return t;
  }
  function mac(prefix){
    return createHmac("sha256",key).update(prefix).digest();
  }

  async function issue(proposal,serverAssertion,{ttlMs=120000}={}){
    validateMenuProposal(proposal);
    const issued=readTime();
    if(!Number.isInteger(ttlMs)||ttlMs<1000||ttlMs>300000||
       issued<proposal.issuedAtMs||issued>=proposal.expiresAtMs||
       proposal.approved!==false||proposal.executable!==false){
      throw new Error("Sessao de proposta expirada ou limite invalido.");
    }
    // Returns a server-proven identity; the data from the caller is not trusted.
    const verified=await validateTrustedServerSession(serverAssertion);
    if(!verified||!exact(verified,["verified","identity","missionId"])||
       verified.verified!==true||
       !sameIdentity(verified.identity,proposal.identity)||
       verified.missionId!==proposal.missionId){
      throw new Error("Servidor da experiencia nao autenticado.");
    }
    const claims={
      v:1,aud:"CAFEINA_MENU_PROPOSAL_V1",
      jti:randomBytes(16).toString("hex"),
      missionId:proposal.missionId,identity:{...proposal.identity},
      proposalHash:proposalHash(proposal),
      iatMs:issued,expMs:Math.min(issued+ttlMs,proposal.expiresAtMs),
      scopes:[...ALLOWED_SCOPES]
    };
    const body=Buffer.from(JSON.stringify(claims)).toString("base64url");
    const prefix="cm1."+body;
    return prefix+"."+mac(prefix).toString("hex");
  }

  function verify(authorization,proposal){
    try{
      validateMenuProposal(proposal);
      const timestamp=readTime();
      if(typeof authorization!=="string"||!authorization.startsWith("Bearer ")||
         authorization.length>1100)return false;
      const token=authorization.slice(7);
      const parts=token.split(".");
      if(parts.length!==3||parts[0]!=="cm1"||
         !/^[A-Za-z0-9_-]{100,1000}$/.test(parts[1])||
         !HEX.test(parts[2]))return false;
      const prefix=parts[0]+"."+parts[1];
      const received=Buffer.from(parts[2],"hex");
      if(received.length!==32||!timingSafeEqual(received,mac(prefix)))return false;
      const raw=Buffer.from(parts[1],"base64url");
      if(raw.length>800)return false;
      const claims=JSON.parse(raw.toString("utf8"));
      return allowedClaims(claims,proposal,timestamp)===true;
    }catch{
      return false;
    }
  }
  return Object.freeze({issue,verify});
}
