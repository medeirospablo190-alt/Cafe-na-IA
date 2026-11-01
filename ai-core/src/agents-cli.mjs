#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {analyzeSession} from "./session.mjs";
import {coordinateInvestigation} from "./agents.mjs";
const fixture=name=>JSON.parse(readFileSync(new URL("../test/fixtures/"+name,import.meta.url),"utf8"));
const report=analyzeSession({batches:[fixture("batch.json")],manifest:fixture("latest.json")});
process.stdout.write(JSON.stringify(coordinateInvestigation(report),null,2)+"\n");
