import test from "node:test";
import assert from "node:assert/strict";
import {
  createApp1Credential,
  decryptStoredSecret,
  encryptStoredSecret,
  hashSecret,
  verifySecret
} from "../src/security.js";
import { APP1_CREDENTIAL_POLICY } from "../../../packages/contracts/src/index.js";

process.env.SESSION_PEPPER ||= "x".repeat(64);
process.env.DEVICE_FINGERPRINT_PEPPER ||= "y".repeat(64);

test("ADMIN APP key segue o contrato compartilhado sem expor o login privado", () => {
  const key = createApp1Credential("Páblo Alves", "ADM");
  assert.equal(key.length, APP1_CREDENTIAL_POLICY.ADM_CHARS);
  assert.match(key, /^ADM1-/);
  assert.equal(key.includes("PabloAlves"), false);
  assert.equal(key.includes("Páblo Alves"), false);
});

test("DEV key segue o contrato compartilhado e mantém prefixo DEV", () => {
  const key = createApp1Credential("psycho", "DEV");
  assert.equal(key.length, APP1_CREDENTIAL_POLICY.DEV_CHARS);
  assert.match(key, /^DEV-/);
  assert.equal(key.includes("psycho"), false);
});

test("hash scrypt valida apenas a chave correta", async () => {
  const secret = "K".repeat(5000);
  const encoded = await hashSecret(secret);
  assert.equal(await verifySecret(secret, encoded), true);
  assert.equal(await verifySecret(secret + "x", encoded), false);
});

test("credencial armazenada pode ser revelada apenas com o mesmo propósito", () => {
  const secret = "ADM1-" + "Q".repeat(251);
  const encoded = encryptStoredSecret(secret, "app1-account-credential:account-123");

  assert.notEqual(encoded, secret);
  assert.equal(
    decryptStoredSecret(encoded, "app1-account-credential:account-123"),
    secret
  );
  assert.equal(
    decryptStoredSecret(encoded, "app1-account-credential:account-999"),
    null
  );
});
