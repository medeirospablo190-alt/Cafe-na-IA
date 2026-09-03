import test from "node:test";
import assert from "node:assert/strict";
import { normalizePublicName, validatePublicName } from "../src/app1-routes.js";

test("normalizePublicName normalizes unicode spacing", () => {
  assert.equal(normalizePublicName("  Lua   Fox  "), "Lua Fox");
});

test("validatePublicName accepts a normal pseudonym", () => {
  const result = validatePublicName("LuaFox", "adm_interno_7281");
  assert.equal(result.ok, true);
  assert.equal(result.name, "LuaFox");
});

test("validatePublicName rejects short and long names", () => {
  assert.equal(validatePublicName("ab", "login-secreto").ok, false);
  assert.equal(validatePublicName("x".repeat(31), "login-secreto").ok, false);
});

test("validatePublicName rejects credential-like prefixes", () => {
  for (const value of ["ADM1-Teste", "DEV-Teste", "FREE-Teste", "VIP-Teste"]) {
    const result = validatePublicName(value, "login-secreto");
    assert.equal(result.ok, false, value);
    assert.equal(result.code, "PUBLIC_NAME_CREDENTIAL_LIKE");
  }
});

test("validatePublicName rejects invisible control characters", () => {
  const result = validatePublicName("Lua\u200BDev", "login-secreto");
  assert.equal(result.ok, false);
  assert.equal(result.code, "PUBLIC_NAME_INVALID_CHARS");
});

test("validatePublicName rejects private login reuse without revealing it", () => {
  const exact = validatePublicName("PabloADM9438", "PabloADM9438");
  const close = validatePublicName("PabloADM9438Extra", "PabloADM9438");
  assert.equal(exact.ok, false);
  assert.equal(exact.code, "PUBLIC_NAME_TOO_CLOSE_TO_LOGIN");
  assert.equal(close.ok, false);
  assert.equal(close.code, "PUBLIC_NAME_TOO_CLOSE_TO_LOGIN");
});
