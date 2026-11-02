import {createHash,timingSafeEqual} from "node:crypto";

const ID=/^[1-9][0-9]{0,19}$/;
const MISSION=/^mission-[a-f0-9]{16}$/;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const AUD="CAFEINA_ROBLOX_SERVER_CHECKIN_V1";
const CHECKIN_FIELDS=["schemaVersion","aud","gameId","placeId","jobId",
  "missionId","issuedAtMs","nonce"];
const VERIFICATION_FIELDS=["verified","gameId","placeId","jobId","runId","missionId","active"];
function exact(o,fields){
  return o!==null&&typeof o==="object"&&!Array.isArray(o)&&
    Object.keys(o).length===fields.length&&fields.every(f=>Object.hasOwn(o,f));
}
function validMs(n){return Number.isSafeInteger(n)&&n>=0;}
function sameSecret(header,secret){
  if(typeof header!=="string"||header.length<32||header.length>128)return false;
  const a=Buffer.from(header,"utf8"),b=Buffer.from(secret,"utf8");
  return a.length===b.length&&timingSafeEqual(a,b);
}
function validCheckin(body,now){
  if(!exact(body,CHECKIN_FIELDS)||body.schemaVersion!==1||body.aud!==AUD||
    typeof body.gameId!=="string"||!ID.test(body.gameId)||
    typeof body.placeId!=="string"||!ID.test(body.placeId)||
    typeof body.missionId!=="string"||!MISSION.test(body.missionId)||
    typeof body.jobId!=="string"||!UUID.test(body.jobId)||
    typeof body.nonce!=="string"||!UUID.test(body.nonce)||
    !validMs(body.issuedAtMs)||
    body.issuedAtMs<now-30000||body.issuedAtMs>now+5000){
    return false;
  }
  return true;
}

/**
 * Reference contract for a Roblox SERVER Script using HttpService:GetSecret.
 *
 * This is NOT Roblox platform attestation. Authentication proves knowledge of
 * an experience-scoped secret, and a separate trusted registration must bind
 * gameId/placeId/jobId to the previously authorized collector runId.
 * Both callbacks are mandatory; do not use client claims as a registry.
 */
export function createExperienceServerVerifier({
  credentials,resolveTrustedJob,claimNonce,nowMs=()=>Date.now()
}={}){
  if(!Array.isArray(credentials)||credentials.length<1||credentials.length>8||
    typeof resolveTrustedJob!=="function"||typeof claimNonce!=="function"||
    typeof nowMs!=="function"){
    throw new Error("Verificador exige configuracao e registros confiaveis.");
  }
  const keys=[];
  for(const item of credentials){
    if(!exact(item,["gameId","placeId","secret"])||
      typeof item.gameId!=="string"||!ID.test(item.gameId)||
      typeof item.placeId!=="string"||!ID.test(item.placeId)||
      typeof item.secret!=="string"||item.secret.length<32||
      item.secret.length>128||! /^[A-Za-z0-9_-]+$/.test(item.secret)||
      keys.some(k=>k.gameId===item.gameId&&k.placeId===item.placeId)){
      throw new Error("Credencial de experiencia invalida.");
    }
    keys.push({gameId:item.gameId,placeId:item.placeId,secret:item.secret});
  }

  async function validateTrustedServerSession(assertion){
    const now=nowMs();
    if(!validMs(now)||!assertion||!exact(assertion,["headers","body"])){
      throw new Error("Afirmacao de servidor invalida.");
    }
    const body=assertion.body,headers=assertion.headers;
    if(!validCheckin(body,now)||!headers||typeof headers!=="object"||
      Array.isArray(headers)){
      throw new Error("Check-in do servidor invalido ou expirado.");
    }
    const configured=keys.find(k=>k.gameId===body.gameId&&k.placeId===body.placeId);
    if(!configured||!sameSecret(headers["x-api-key"],configured.secret)){
      throw new Error("Servidor sem credencial de experiencia.");
    }
    // A registry populated by trusted server-side provisioning, never by client
    // data, is required to link this Roblox JobId to CAFEINA's collector runId.
    const registered=await resolveTrustedJob({
      gameId:body.gameId,placeId:body.placeId,
      jobId:body.jobId,missionId:body.missionId
    });
    if(!exact(registered,VERIFICATION_FIELDS)||registered.verified!==true||
      registered.active!==true||registered.gameId!==body.gameId||
      registered.placeId!==body.placeId||registered.jobId!==body.jobId||
      registered.missionId!==body.missionId||
      typeof registered.runId!=="string"||
      !/^[A-Za-z0-9_-]{6,128}$/.test(registered.runId)){
      throw new Error("Job Roblox nao registrado ou nao autorizado.");
    }
    const replayKey=createHash("sha256")
      .update([body.gameId,body.placeId,body.jobId,body.missionId,body.nonce].join(":"))
      .digest("hex");
    // claimNonce MUST be atomic across ALL gateway instances and durable enough
    // for 65 sec. In-memory implementation is suitable for isolated tests only.
    const firstUse=await claimNonce(replayKey,now+65000);
    if(firstUse!==true)throw new Error("Nonce repetido ou indisponivel.");
    return {
      verified:true,
      identity:{gameId:registered.gameId,placeId:registered.placeId,runId:registered.runId},
      missionId:registered.missionId
    };
  }
  return Object.freeze({validateTrustedServerSession});
}

/** Only for tests: no sharing between Render replicas, no persistence. */
export function createInMemoryNonceStore(nowMs=()=>Date.now()){
  const values=new Map();
  return async (key,expiresAtMs)=>{
    const now=nowMs();
    if(!/^[a-f0-9]{64}$/.test(key)||!validMs(expiresAtMs)||!validMs(now)||
       expiresAtMs<=now)return false;
    for(const [id,until] of values){
      if(until<=now)values.delete(id);
    }
    if(values.has(key))return false;
    if(values.size>=100)return false;
    values.set(key,expiresAtMs);
    return true;
  };
}
