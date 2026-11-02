#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {prepareReaHandoff,reaEmptyLedgerRequest} from "./rea-adapter.mjs";
const fixture=name=>JSON.parse(readFileSync(
  new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
const report=analyzeSession({batches:[fixture("batch.json")],manifest:fixture("latest.json")});
const handoff=prepareReaHandoff(report);
const ledgerRequest=reaEmptyLedgerRequest();
process.stdout.write(JSON.stringify({
  handoff,
  reaEmptyLedgerRequest:ledgerRequest,
  note:"PREPARATION_ONLY_NO_REA_EXECUTION"
},null,2)+"\n");
