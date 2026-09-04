import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const serviceRoot = path.resolve(here, "..");
const repoWorkspace = path.resolve(serviceRoot, "../..");

function read(relativePath) {
  return fs.readFileSync(path.resolve(serviceRoot, relativePath), "utf8");
}

function readWorkspace(relativePath) {
  return fs.readFileSync(path.resolve(repoWorkspace, relativePath), "utf8");
}

test("global App 1 suspension persists and revokes active sessions", () => {
  const migration = read("migrations/010_keymaster_critical_completion.sql");
  assert.match(migration, /app1_maintenance/);
  assert.match(migration, /revoke_app1_sessions_on_global_suspension/);
  assert.match(migration, /UPDATE app1_sessions[\s\S]*revoked_at/);
});

test("definitive deleted-account cleanup covers App 1-owned data", () => {
  const migration = read("migrations/010_keymaster_critical_completion.sql");
  for (const table of [
    "app1_feed_posts",
    "app1_library_items",
    "app1_login_attempts",
    "critical_authorizations",
    "app1_device_enrollment_windows",
    "app1_terms_acceptances",
    "app1_sessions",
    "app1_devices"
  ]) {
    assert.match(migration, new RegExp(`DELETE FROM ${table}`), table);
  }
  assert.match(migration, /credential_ciphertext = NULL/);
  assert.match(migration, /display_name = NULL/);
});

test("Keymaster history can be cleared only from an authenticated Keymaster session", () => {
  const source = read("src/keymaster-audit-clear.js");
  assert.match(source, /this\.delete\("\/v1\/keymaster\/audit"/);
  assert.match(source, /getKeymasterSession\(req\)/);
  assert.match(source, /DELETE FROM app1_login_attempts/);
  assert.match(source, /DELETE FROM audit_events/);
  assert.doesNotMatch(source, /DEV_REAUTH_REQUIRED/);
});

test("critical screen uses explicit suspension and private DEV reauthentication copy", () => {
  const screen = readWorkspace("apps/keymaster/src/screens/CriticalScreen.tsx");
  assert.match(screen, /App 1: SUSPENSO/);
  assert.match(screen, /REATIVAR/);
  assert.match(screen, /SUSPENDER/);
  assert.match(screen, /LOGIN PRIVADO DEV/);
  assert.match(screen, /CHAVE DEV/);
});

test("audit screen requires an explicit yes-no confirmation before permanent clearing", () => {
  const screen = readWorkspace("apps/keymaster/src/screens/AuditScreen.tsx");
  assert.match(screen, /Limpar histórico\?/);
  assert.match(screen, /text: "Não"/);
  assert.match(screen, /text: "Sim, apagar"/);
  assert.match(screen, /clearAuditHistory/);
});

test("Keymaster bottom navigation consumes device safe-area insets", () => {
  const nav = readWorkspace("apps/keymaster/src/components/BottomNav.tsx");
  const app = readWorkspace("apps/keymaster/App.tsx");
  assert.match(nav, /useSafeAreaInsets/);
  assert.match(nav, /insets\.bottom/);
  assert.match(app, /SafeAreaProvider/);
});
