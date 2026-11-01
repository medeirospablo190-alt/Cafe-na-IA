const ROLES=new Set(["Investigadora","Critica","Pesquisadora"]);
const CODES=new Set([
  "CAUSALITY_NOT_PROVEN","GUI_TRANSITION_UNVERIFIED",
  "BATCH_COUNT_UNREPORTED","MISSING_BATCHES","NO_OBSERVATIONS"
]);
const TOOLS=new Set(["watch_state","observe_gui","none"]);
const KIND=/^[a-z][a-z0-9_]{0,63}$/;
const REF=/^v3:[1-9][0-9]*:[1-9][0-9]*:[A-Za-z0-9_-]{6,128}:[0-9]+:[0-9]+$/;

export function safeModelContext(report){
  if(report?.type!=="cafeina_ai_session_analysis"||
    report.mode!=="DRY_RUN"||report.privacy?.rawRecordsIncluded!==false||
    report.privacy?.personalIdentifiersIncluded!==false){
    throw new Error("Relatorio nao saneado.");
  }
  const kinds=report.observations?.kindCounts;
  if(!kinds||typeof kinds!=="object"||Array.isArray(kinds)){
    throw new Error("Contadores indisponiveis.");
  }
  const counts=Object.entries(kinds);
  if(counts.length>200||counts.some(([k,v])=>!KIND.test(k)||
    !Number.isSafeInteger(v)||v<0))throw new Error("Contadores invalidos.");
  const unknowns=report.unknowns;
  if(!Array.isArray(unknowns)||unknowns.length>10||
    unknowns.some(u=>!CODES.has(u.code)||!Array.isArray(u.evidenceRefs)||
      u.evidenceRefs.length>3||u.evidenceRefs.some(ref=>!REF.test(ref)))){
    throw new Error("Evidencias de modelo invalidas.");
  }
  return {
    kinds:Object.fromEntries(counts.sort(([a],[b])=>a.localeCompare(b))),
    unknowns:unknowns.map(u=>({code:u.code,evidenceRefs:u.evidenceRefs})),
    fullBatchSequence:report.coverage?.completeBatchSequence===true,
    causalValidation:false
  };
}

/**
 * Optional local Ollama-compatible inference. Never runs by default or inside CI.
 * It cannot propose arbitrary tools: all replies are reduced to controlled enums.
 */
export async function askLocalModel({
  report,role,model,server="http://127.0.0.1:11434",
  request=fetch,timeoutMs=15000
}){
  if(!ROLES.has(role))throw new Error("Papel de IA nao autorizado.");
  const endpoint=/^http:\/\/(127\.0\.0\.1|localhost):([0-9]{2,5})$/.exec(server);
  if(!endpoint||Number(endpoint[2])>65535)throw new Error("Apenas servidor local de IA e permitido.");
  if(typeof model!=="string"||!/^[A-Za-z0-9_.:/-]{1,100}$/.test(model)){
    throw new Error("Nome de modelo invalido.");
  }
  if(!Number.isInteger(timeoutMs)||timeoutMs<1000||timeoutMs>60000){
    throw new Error("Timeout fora dos limites.");
  }
  const context=safeModelContext(report);
  const allowedCodes=context.unknowns.map(u=>u.code);
  if(!allowedCodes.length)throw new Error("Nenhuma lacuna para investigar.");
  // Use schema-constrained generation. Even a small model must stay in these enums.
  const format={
    type:"object",additionalProperties:false,
    required:["unknownCode","recommendation"],
    properties:{
      unknownCode:{type:"string",enum:allowedCodes},
      recommendation:{type:"string",enum:["watch_state","observe_gui","none"]}
    }
  };
  const prompt="Voce e "+role+
    ". Responda APENAS com um objeto JSON valido conforme o schema. "+
    "unknownCode DEVE ser um item da lista. Se houver CAUSALITY_NOT_PROVEN, "+
    "use unknownCode CAUSALITY_NOT_PROVEN e recommendation watch_state. "+
    "Nao execute ferramentas, nao infira logica de servidor. "+
    "Contexto de metadados observados: "+JSON.stringify(context);
  if(prompt.length>20000)throw new Error("Contexto muito grande.");
  const response=await request(server+"/api/generate",{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({
      model,prompt,stream:false,format,
      options:{temperature:0,num_predict:128}
    }),
    signal:AbortSignal.timeout(timeoutMs)
  });
  if(!response.ok)throw new Error("Modelo local indisponivel (HTTP "+response.status+").");
  const data=await response.json();
  if(typeof data.response!=="string"||data.response.length>4096){
    throw new Error("Resposta de modelo excessiva ou invalida.");
  }
  let parsed;
  try{parsed=JSON.parse(data.response);}
  catch{throw new Error("Modelo retornou JSON invalido.");}
  if(!parsed||typeof parsed!=="object"||
    !context.unknowns.some(u=>u.code===parsed.unknownCode)||
    !TOOLS.has(parsed.recommendation)){
    throw new Error("Modelo propos resposta fora do contrato.");
  }
  const toolAllowed=report.mission?.toolId===parsed.recommendation;
  return {
    role,model,
    unknownCode:parsed.unknownCode,
    recommendation:toolAllowed?parsed.recommendation:"none",
    modelRecommendationAccepted:toolAllowed,
    verification:"EXPERIMENTAL",
    executable:false,
    requiresApproval:true
  };
}
