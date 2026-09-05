import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import net from "node:net";
import { spawn } from "node:child_process";
import pg from "pg";
import { tokenHash } from "../src/security.js";

const enabled = Boolean(process.env.DATABASE_URL);

function uuid() {
  return crypto.randomUUID();
}

async function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

async function waitForHealth(baseUrl, child) {
  let lastError = null;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Control API exited early with code ${child.exitCode}`);
    try {
      const response = await fetch(`${baseUrl}/v1/health`);
      if (response.ok) return;
      lastError = new Error(`health HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw lastError || new Error("Control API did not become ready");
}

async function jsonRequest(baseUrl, path, {
  method = "GET",
  body,
  appToken,
  appDeviceToken,
  menuToken,
  menuDeviceId
} = {}) {
  const headers = { accept: "application/json" };
  if (body !== undefined) headers["content-type"] = "application/json";
  if (appToken) headers.authorization = `Bearer ${appToken}`;
  if (appDeviceToken) headers["x-app1-device-token"] = appDeviceToken;
  if (menuToken) headers.authorization = `Bearer ${menuToken}`;
  if (menuDeviceId) headers["x-menu-device-id"] = menuDeviceId;

  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function publicValidate(baseUrl, publicId, key, deviceId, hint) {
  return jsonRequest(baseUrl, "/v1/menu-access/validate", {
    method: "POST",
    body: {
      menuId: publicId,
      key,
      clientLabel: `CI ${hint}`,
      deviceId,
      deviceHint: hint
    }
  });
}

test("App 1 administra FREE/VIP, troca aparelho e revela novas chaves sem expor valor em listagens", { skip: !enabled, timeout: 40_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const accountId = uuid();
  const appDeviceRowId = uuid();
  const appSessionId = uuid();
  const menuId = uuid();
  const publicId = `menu_admin_ci_${suffix}`;
  const appToken = `ci-app1-${crypto.randomBytes(32).toString("base64url")}`;
  const appDeviceToken = `ci-app1-device-${crypto.randomBytes(32).toString("base64url")}`;
  const deviceA = `ci-phone-a-${suffix}`;
  const deviceB = `ci-phone-b-${suffix}`;
  let child = null;

  try {
    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash,
         terms_version, privacy_version, terms_accepted_at,
         public_profile_id, public_name, public_name_normalized,
         public_name_verified_at, onboarding_completed_at)
       VALUES ($1, $2, $3, 'ADM', 'ACTIVE', 'ci-credential',
               '1.0', '1.0', NOW(), $4, $5, $6, NOW(), NOW())`,
      [
        accountId,
        `ci_key_admin_${suffix}`,
        `CI Key Admin ${suffix}`,
        `usr_key_${suffix}`,
        `KeyAdmin${suffix}`,
        `keyadmin${suffix}`
      ]
    );

    await db.query(
      `INSERT INTO app1_devices
        (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
       VALUES ($1, $2, $3, $4, 'ci', 'CI Admin Phone', TRUE, 'ACTIVE')`,
      [
        appDeviceRowId,
        accountId,
        `ci-admin-device-${suffix}`,
        tokenHash(`app1-device:${appDeviceToken}`)
      ]
    );

    await db.query(
      `INSERT INTO app1_sessions
        (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
       VALUES ($1, $2, $3, 'CI Admin Phone', NOW() + INTERVAL '30 minutes', $4, 'FULL')`,
      [appSessionId, accountId, tokenHash(`app1:${appToken}`), appDeviceRowId]
    );

    await db.query(
      `INSERT INTO managed_menus
        (id, public_id, name, source_url, status)
       VALUES ($1, $2, $3, $4, 'ACTIVE')`,
      [menuId, publicId, `CI Admin Menu ${suffix}`, "https://raw.githubusercontent.com/example/example/main/menu.lua"]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const createFree = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken,
      appDeviceToken,
      body: { kind: "FREE", durationValue: 6, note: "CI FREE" }
    });
    assert.equal(createFree.response.status, 201, JSON.stringify(createFree.data));
    assert.equal(createFree.data.key.kind, "FREE");
    assert.equal(createFree.data.key.duration_unit, "HOURS");
    assert.equal(createFree.data.key.duration_value, 6);
    assert.equal(createFree.data.key.revealOnce, false);
    assert.equal(createFree.data.key.can_reveal, true);
    assert.match(createFree.data.key.value, /^FREE-/);
    const freeId = createFree.data.key.id;
    const freeValue = createFree.data.key.value;

    const revealFree = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${freeId}/reveal`, {
      method: "POST",
      appToken,
      appDeviceToken
    });
    assert.equal(revealFree.response.status, 200, JSON.stringify(revealFree.data));
    assert.equal(revealFree.response.headers.get("cache-control"), "no-store, private");
    assert.equal(revealFree.data.key.value, freeValue);
    assert.equal(revealFree.data.key.id, freeId);

    const revealAudit = (await db.query(
      `SELECT metadata
         FROM audit_events
        WHERE actor_id = $1
          AND target_id = $2
          AND action = 'MENU_KEY_REVEALED_APP1'
        ORDER BY created_at DESC
        LIMIT 1`,
      [accountId, freeId]
    )).rows[0];
    assert.ok(revealAudit, "reveal action must be audited");
    assert.equal(JSON.stringify(revealAudit.metadata).includes(freeValue), false, "audit metadata must not contain plaintext key");

    const firstFree = await publicValidate(baseUrl, publicId, freeValue, deviceA, "Phone A");
    assert.equal(firstFree.response.status, 200, JSON.stringify(firstFree.data));
    assert.equal(firstFree.data.keyType, "FREE");
    const freeUntil = new Date(firstFree.data.keyExpiresAt).getTime();
    const freeHours = (freeUntil - Date.now()) / (60 * 60 * 1000);
    assert.ok(freeHours > 5.8 && freeHours <= 6.05, `unexpected FREE duration ${freeHours}`);

    const sharedFree = await publicValidate(baseUrl, publicId, freeValue, deviceB, "Phone B");
    assert.equal(sharedFree.response.status, 403, JSON.stringify(sharedFree.data));
    assert.equal(sharedFree.data.code, "DEVICE_NOT_AUTHORIZED");

    await db.query(
      `UPDATE menu_access_keys SET access_until = NOW() - INTERVAL '1 minute' WHERE id = $1`,
      [freeId]
    );

    const expiredFree = await publicValidate(baseUrl, publicId, freeValue, deviceA, "Phone A");
    assert.equal(expiredFree.response.status, 403, JSON.stringify(expiredFree.data));
    assert.equal(expiredFree.data.code, "FREE_REQUIRES_ADMIN");

    const releaseFree = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${freeId}/release-free`, {
      method: "POST",
      appToken,
      appDeviceToken,
      body: { durationHours: 24 }
    });
    assert.equal(releaseFree.response.status, 200, JSON.stringify(releaseFree.data));
    assert.equal(releaseFree.data.key.access_state, "READY");
    assert.equal(releaseFree.data.key.duration_value, 24);

    const secondFree = await publicValidate(baseUrl, publicId, freeValue, deviceA, "Phone A");
    assert.equal(secondFree.response.status, 200, JSON.stringify(secondFree.data));
    const secondFreeUntil = new Date(secondFree.data.keyExpiresAt).getTime();
    const secondFreeHours = (secondFreeUntil - Date.now()) / (60 * 60 * 1000);
    assert.ok(secondFreeHours > 23.8 && secondFreeHours <= 24.05, `unexpected second FREE duration ${secondFreeHours}`);

    const beforeResetRow = (await db.query(
      `SELECT access_started_at, access_until FROM menu_access_keys WHERE id = $1`,
      [freeId]
    )).rows[0];
    const beforeResetStartedAt = new Date(beforeResetRow.access_started_at).getTime();
    const beforeResetUntil = new Date(beforeResetRow.access_until).getTime();
    assert.equal(beforeResetUntil, secondFreeUntil);

    const resetFreeDevice = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${freeId}/reset-device`, {
      method: "POST",
      appToken,
      appDeviceToken,
      body: {}
    });
    assert.equal(resetFreeDevice.response.status, 200, JSON.stringify(resetFreeDevice.data));
    assert.equal(resetFreeDevice.data.key.bound_device, false);
    assert.equal(new Date(resetFreeDevice.data.key.access_started_at).getTime(), beforeResetStartedAt);
    assert.equal(new Date(resetFreeDevice.data.key.access_until).getTime(), beforeResetUntil);

    const movedFree = await publicValidate(baseUrl, publicId, freeValue, deviceB, "Phone B");
    assert.equal(movedFree.response.status, 200, JSON.stringify(movedFree.data));
    assert.equal(new Date(movedFree.data.keyExpiresAt).getTime(), beforeResetUntil);
    const movedRow = (await db.query(
      `SELECT bound_device_hint, access_started_at, access_until FROM menu_access_keys WHERE id = $1`,
      [freeId]
    )).rows[0];
    assert.equal(movedRow.bound_device_hint, "Phone B");
    assert.equal(new Date(movedRow.access_started_at).getTime(), beforeResetStartedAt);
    assert.equal(new Date(movedRow.access_until).getTime(), beforeResetUntil);

    const createVip = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken,
      appDeviceToken,
      body: { kind: "VIP", durationUnit: "MONTHS", durationValue: 2, note: "CI VIP" }
    });
    assert.equal(createVip.response.status, 201, JSON.stringify(createVip.data));
    assert.equal(createVip.data.key.kind, "VIP");
    assert.equal(createVip.data.key.duration_unit, "MONTHS");
    assert.equal(createVip.data.key.duration_value, 2);
    assert.equal(createVip.data.key.can_reveal, true);
    assert.match(createVip.data.key.value, /^VIP-/);
    const vipId = createVip.data.key.id;
    const vipValue = createVip.data.key.value;

    const firstVip = await publicValidate(baseUrl, publicId, vipValue, deviceA, "VIP Phone");
    assert.equal(firstVip.response.status, 200, JSON.stringify(firstVip.data));
    assert.equal(firstVip.data.keyType, "VIP");
    assert.ok(firstVip.data.keyExpiresAt);

    const vipShared = await publicValidate(baseUrl, publicId, vipValue, deviceB, "Other VIP Phone");
    assert.equal(vipShared.response.status, 403, JSON.stringify(vipShared.data));
    assert.equal(vipShared.data.code, "DEVICE_NOT_AUTHORIZED");

    const permanentVip = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${vipId}/configure-vip`, {
      method: "POST",
      appToken,
      appDeviceToken,
      body: { durationUnit: "PERMANENT" }
    });
    assert.equal(permanentVip.response.status, 200, JSON.stringify(permanentVip.data));
    assert.equal(permanentVip.data.key.access_state, "READY");
    assert.equal(permanentVip.data.key.duration_unit, "PERMANENT");
    assert.equal(permanentVip.data.key.duration_value, null);

    const permanentAccess = await publicValidate(baseUrl, publicId, vipValue, deviceA, "VIP Phone");
    assert.equal(permanentAccess.response.status, 200, JSON.stringify(permanentAccess.data));
    assert.equal(permanentAccess.data.keyType, "VIP");
    assert.equal(permanentAccess.data.keyExpiresAt, null);

    const listed = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      appToken,
      appDeviceToken
    });
    assert.equal(listed.response.status, 200, JSON.stringify(listed.data));
    assert.ok(Array.isArray(listed.data.keys));
    assert.ok(listed.data.keys.some((key) => key.id === freeId && key.kind === "FREE" && key.can_reveal === true));
    assert.ok(listed.data.keys.some((key) => key.id === vipId && key.kind === "VIP" && key.can_reveal === true));
    assert.equal(listed.data.keys.some((key) => Object.hasOwn(key, "value")), false);
    assert.equal(listed.data.keys.some((key) => Object.hasOwn(key, "key_value_encrypted")), false);

    await db.query(`UPDATE menu_access_keys SET key_value_encrypted = NULL WHERE id = $1`, [freeId]);
    const legacyReveal = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${freeId}/reveal`, {
      method: "POST",
      appToken,
      appDeviceToken
    });
    assert.equal(legacyReveal.response.status, 409, JSON.stringify(legacyReveal.data));
    assert.equal(legacyReveal.data.code, "KEY_VALUE_NOT_RECOVERABLE");

    const legacyListed = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      appToken,
      appDeviceToken
    });
    const legacyFree = legacyListed.data.keys.find((key) => key.id === freeId);
    assert.equal(legacyFree.can_reveal, false);
    assert.equal(Object.hasOwn(legacyFree, "value"), false);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR target_id = $2`, [accountId, menuId]).catch(() => {});
    await db.query(`DELETE FROM menu_access_sessions WHERE menu_id = $1`, [menuId]).catch(() => {});
    await db.query(`DELETE FROM menu_access_keys WHERE menu_id = $1`, [menuId]).catch(() => {});
    await db.query(`DELETE FROM managed_menus WHERE id = $1`, [menuId]).catch(() => {});
    await db.query(`DELETE FROM app1_sessions WHERE id = $1`, [appSessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_devices WHERE id = $1`, [appDeviceRowId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [accountId]).catch(() => {});
    await db.end();
  }
});
