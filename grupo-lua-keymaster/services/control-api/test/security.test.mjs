import test from "node:test";
import assert from "node:assert/strict";
import { createApp1Credential, hashSecret, verifySecret } from "../src/security.js";
import { APP1_CREDENTIAL_POLICY } from "../../../packages/contracts/src/index.js";

process.env.SESSION_PEPPER ||= "x".repeat(64);
process.env.DEVICE_FINGERPRINT_PEPPER ||= "y".repeat(64);

test("ADMIN APP key segue o contrato compartilhado e inclui login normalizado", () => {
  const key = createApp1Credential("Páblo Alves", "ADM");
  assert.equal(key.length, APP1_CREDENTIAL_POLICY.ADM_CHARS);
  assert.match(key, /^ADM1-PabloAlves-/);
});

test("DEV key segue o contrato compartilhado e mantém prefixo DEV", () => {
  const key = createApp1Credential("psycho", "DEV");
  assert.equal(key.length, APP1_CREDENTIAL_POLICY.DEV_CHARS);
  assert.match(key, /^DEV-/);
});

test("hash scrypt valida apenas a chave correta", async () => {
  const secret = "K".repeat(5000);
  const encoded = await hashSecret(secret);
  assert.equal(await verifySecret(secret, encoded), true);
  assert.equal(await verifySecret(secret + "x", encoded), false);
});
