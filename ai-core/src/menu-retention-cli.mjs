#!/usr/bin/env node
import {scanSyntheticMenuRetention} from "./menu-retention.mjs";

const result=await scanSyntheticMenuRetention({
  token:process.env.GITHUB_TOKEN ?? ""
});
process.stdout.write(JSON.stringify({
  mode:result.mode,scanned:result.scanned,
  eligible:result.eligible,requiresReview:result.requiresReview,
  notYetEligible:result.notYetEligible,outOfScope:result.outOfScope,
  deleted:0
})+"\n");
