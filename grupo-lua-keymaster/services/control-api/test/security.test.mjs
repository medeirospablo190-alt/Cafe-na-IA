import test from "node:test";
import assert from "node:assert/strict";
import { createApp1Credential, hashSecret, verifySecret } from "../src/security.js";

process.env.SESSION_PEPPER ||= "x".repeat(64);
process.env.DEVICE_FINGERPRINT_PEPPER ||= "y".repeat(64);

test("ADMIN APP key tem 256 caracteres e inclui login normalizado", () => {
  const key = createApp1Credential("Páblo Alves", "ADM");
  assert.equal(key.length, 256);
  assert.match(key, /^ADM1-PabloAlves-/);
});

test("DEV key tem 600 caracteres e prefixo DEV", () => {
  const key = createApp1Credential("psycho", "DEV");
  assert.equal(key.length, 600);
  assert.match(key, /^DEV-/);
});

test("hash scrypt valida apenas a chave correta", async () => {
  const secret = "K".repeat(5000);
  const encoded = await hashSecret(secret);
  assert.equal(await verifySecret(secret, encoded), true);
  assert.equal(await verifySecret(secret + "x", encoded), false);
});
