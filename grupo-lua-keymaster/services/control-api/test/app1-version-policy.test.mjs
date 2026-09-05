import test from "node:test";
import assert from "node:assert/strict";
import {
  compareAppVersions,
  evaluateApp1Version,
  parseAppVersion,
  resolveApp1VersionPolicy
} from "../src/app1-version-policy.js";

test("parseia somente versões semânticas simples", () => {
  assert.deepEqual(parseAppVersion("0.3.2"), [0, 3, 2]);
  assert.deepEqual(parseAppVersion("12.0.14"), [12, 0, 14]);
  assert.equal(parseAppVersion("0.3"), null);
  assert.equal(parseAppVersion("v0.3.2"), null);
  assert.equal(parseAppVersion(""), null);
});

test("compara versões por major, minor e patch", () => {
  assert.equal(compareAppVersions("0.3.2", "0.3.2"), 0);
  assert.equal(compareAppVersions("0.3.1", "0.3.2"), -1);
  assert.equal(compareAppVersions("0.4.0", "0.3.9"), 1);
  assert.equal(compareAppVersions("1.0.0", "0.99.99"), 1);
});

test("política separa compatível, atualização opcional e obrigatória", () => {
  const policy = {
    minSupportedVersion: "0.3.2",
    latestVersion: "0.4.0",
    headerRequired: false
  };

  assert.deepEqual(evaluateApp1Version("0.3.1", policy), {
    status: "UPDATE_REQUIRED",
    currentVersion: "0.3.1",
    updateRequired: true,
    updateAvailable: true
  });

  assert.deepEqual(evaluateApp1Version("0.3.2", policy), {
    status: "UPDATE_AVAILABLE",
    currentVersion: "0.3.2",
    updateRequired: false,
    updateAvailable: true
  });

  assert.deepEqual(evaluateApp1Version("0.4.0", policy), {
    status: "COMPATIBLE",
    currentVersion: "0.4.0",
    updateRequired: false,
    updateAvailable: false
  });
});

test("configuração inválida nunca deixa latest abaixo da mínima", () => {
  const policy = resolveApp1VersionPolicy({
    APP1_MIN_SUPPORTED_VERSION: "0.4.0",
    APP1_LATEST_VERSION: "0.3.9",
    APP1_VERSION_HEADER_REQUIRED: "true"
  });

  assert.deepEqual(policy, {
    minSupportedVersion: "0.4.0",
    latestVersion: "0.4.0",
    headerRequired: true
  });
});
