import test from "node:test";
import assert from "node:assert/strict";
import {
  ACCOUNT_STATUS,
  APP1_CREDENTIAL_POLICY,
  APP1_PERMISSIONS,
  CRITICAL_ACTIONS,
  permissionsForRole,
  roleHasPermission
} from "../src/index.js";

test("credential policy matches App 1 generated credential sizes and session lifetime", () => {
  assert.equal(APP1_CREDENTIAL_POLICY.ADM_CHARS, 256);
  assert.equal(APP1_CREDENTIAL_POLICY.DEV_CHARS, 600);
  assert.equal(APP1_CREDENTIAL_POLICY.SESSION_HOURS, 24);
});

test("account status contract includes the security lock state", () => {
  assert.equal(ACCOUNT_STATUS.LOCKED_SECURITY, "LOCKED_SECURITY");
});

test("ADM receives only baseline App 1 administrative permissions", () => {
  const permissions = permissionsForRole("ADM");
  assert.ok(permissions.includes(APP1_PERMISSIONS.SESSION_USE));
  assert.ok(permissions.includes(APP1_PERMISSIONS.ADMIN_AREA));
  assert.equal(permissions.includes(APP1_PERMISSIONS.DEV_PRIVILEGED), false);
  assert.equal(permissions.includes(APP1_PERMISSIONS.SOCIAL_PIN_POST), false);
});

test("DEV receives privileged permission and reserved Social pin permission", () => {
  assert.equal(roleHasPermission("DEV", APP1_PERMISSIONS.DEV_PRIVILEGED), true);
  assert.equal(roleHasPermission("DEV", APP1_PERMISSIONS.SOCIAL_PIN_POST), true);
  assert.equal(roleHasPermission("ADM", APP1_PERMISSIONS.SOCIAL_PIN_POST), false);
});

test("critical action contract covers current target-scoped Keymaster operations", () => {
  assert.equal(CRITICAL_ACTIONS.DELETE_APP1_ACCOUNT, "DELETE_APP1_ACCOUNT");
  assert.equal(CRITICAL_ACTIONS.DELETE_MANAGED_MENU, "DELETE_MANAGED_MENU");
  assert.equal(CRITICAL_ACTIONS.UNLOCK_APP1_ACCOUNT, "UNLOCK_APP1_ACCOUNT");
  assert.equal(CRITICAL_ACTIONS.AUTHORIZE_APP1_DEVICE, "AUTHORIZE_APP1_DEVICE");
  assert.equal(CRITICAL_ACTIONS.REVOKE_APP1_DEVICE, "REVOKE_APP1_DEVICE");
  assert.equal(CRITICAL_ACTIONS.ROTATE_APP1_CREDENTIAL, "ROTATE_APP1_CREDENTIAL");
  assert.equal(CRITICAL_ACTIONS.REVEAL_APP1_CREDENTIAL, "REVEAL_APP1_CREDENTIAL");
});

test("unknown roles receive no permissions", () => {
  assert.deepEqual([...permissionsForRole("UNKNOWN")], []);
});
