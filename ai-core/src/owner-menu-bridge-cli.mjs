#!/usr/bin/env node
import {createOwnerMenuBridge} from "./owner-menu-bridge.mjs";

if(process.env.CAFEINA_BRIDGE_ENABLE!=="true"){
  throw new Error("Bridge disabled. Explicit CAFEINA_BRIDGE_ENABLE=true required.");
}
const gateway=createOwnerMenuBridge({
  repository:process.env.GITHUB_REPOSITORY,
  githubToken:process.env.GITHUB_TOKEN,
  serverKey:process.env.CAFEINA_ROBLOX_SERVER_KEY,
  identity:{
    gameId:process.env.CAFEINA_GAME_ID,
    placeId:process.env.CAFEINA_PLACE_ID,
    runId:process.env.CAFEINA_RUN_ID
  },
  missionId:process.env.CAFEINA_MISSION_ID,
  jobId:process.env.CAFEINA_JOB_ID
});
const port=Number(process.env.PORT??3000);
const host=process.env.CAFEINA_LISTEN_HOST??"127.0.0.1";
const addr=await gateway.start({host,port});
console.log("CAFEINA bridge ready: "+addr.address+":"+addr.port+
  " (server-only, non-executing).");
for(const signal of ["SIGINT","SIGTERM"]){
  process.once(signal,()=>gateway.close().then(()=>process.exit(0)));
}
