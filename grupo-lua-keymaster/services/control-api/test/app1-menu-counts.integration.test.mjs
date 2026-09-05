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

async function jsonRequest(baseUrl, path, { method = "GET", body, appToken, appDeviceToken } = {}) {
  const headers = { accept: "application/json" };
  if (body !== undefined) headers["content-type"] = "application/json";
  if (appToken) headers.authorization = `Bearer ${appToken}`;
  if (appDeviceToken) headers["x-app1-device-token"] = appDeviceToken;
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function seedAccount(db, suffix) {
  const accountId = uuid();
  const deviceId = uuid();
  const sessionId = uuid();
  const token = `ci-app1-${crypto.randomBytes(32).toString("base64url")}`;
  const deviceToken = `ci-device-${crypto.randomBytes(32).toString("base64url")}`;

  await db.query(
    `INSERT INTO app1_accounts
      (id, login, display_name, role, status, credential_hash,
       terms_version, privacy_version, terms_accepted_at,
       public_profile_id, public_name, public_name_normalized,
       public_name_verified_at, onboarding_completed_at)
     VALUES ($1, $2, $3, 'ADM', 'ACTIVE', 'ci-credential',
             '1.0', '1.0', NOW(), $4, $5, $6, NOW(), NOW())`,
    [accountId, `ci_counts_${suffix}`, `Counts ${suffix}`, `usr_counts_${suffix}`, `Counts${suffix}`, `counts${suffix}`]
  );

  await db.query(
    `INSERT INTO app1_devices
      (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
     VALUES ($1, $2, $3, $4, 'ci', 'CI Phone', TRUE, 'ACTIVE')`,
    [deviceId, accountId, `fp-counts-${suffix}`, tokenHash(`app1-device:${deviceToken}`)]
  );

  await db.query(
    `INSERT INTO app1_sessions
      (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
     VALUES ($1, $2, $3, 'CI Phone', NOW() + INTERVAL '30 minutes', $4, 'FULL')`,
    [sessionId, accountId, tokenHash(`app1:${token}`), deviceId]
  );

  return { accountId, deviceId, sessionId, token, deviceToken };
}

async function validateKey(baseUrl, menuPublicId, keyValue, deviceId) {
  const response = await fetch(`${baseUrl}/v1/menu-access/validate`, {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({
      menuId: menuPublicId,
      key: keyValue,
      deviceId,
      deviceHint: "CI counts phone",
      clientLabel: "CI counts"
    })
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

test("lista de menus não multiplica chaves nem acessos por causa dos JOINs", { skip: !enabled, timeout: 45_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true" ? { rejectUnauthorized: false } : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(6).toString("hex");
  const owner = await seedAccount(db, suffix);
  let child = null;
  let menuId = null;

  try {
    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const createMenu = await jsonRequest(baseUrl, "/v1/app1/menu-admin/menus", {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: {
        name: `Counts ${suffix}`,
        sourceCode: `return function() return "COUNTS_${suffix}" end`
      }
    });
    assert.equal(createMenu.response.status, 201, JSON.stringify(createMenu.data));
    menuId = createMenu.data.menu.id;
    const publicId = createMenu.data.menu.public_id;

    const freeKey = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: { name: "FREE count", kind: "FREE", durationValue: 2 }
    });
    assert.equal(freeKey.response.status, 201, JSON.stringify(freeKey.data));

    const vipKey = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: { name: "VIP count", kind: "VIP", durationUnit: "DAYS", durationValue: 7 }
    });
    assert.equal(vipKey.response.status, 201, JSON.stringify(vipKey.data));

    const freeValidation = await validateKey(baseUrl, publicId, freeKey.data.key.value, `counts-free-${suffix}`);
    assert.equal(freeValidation.response.status, 200, JSON.stringify(freeValidation.data));

    const vipValidation = await validateKey(baseUrl, publicId, vipKey.data.key.value, `counts-vip-${suffix}`);
    assert.equal(vipValidation.response.status, 200, JSON.stringify(vipValidation.data));

    const list = await jsonRequest(baseUrl, "/v1/app1/menu-admin/menus", {
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(list.response.status, 200, JSON.stringify(list.data));

    const menu = list.data.menus.find((item) => item.id === menuId);
    assert.ok(menu, JSON.stringify(list.data));
    assert.equal(menu.key_count, 2);
    assert.equal(menu.free_key_count, 1);
    assert.equal(menu.vip_key_count, 1);
    assert.equal(menu.active_access_count, 2);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    if (menuId) {
      await db.query(`DELETE FROM menu_source_tickets WHERE menu_id = $1`, [menuId]).catch(() => {});
      await db.query(`DELETE FROM menu_access_sessions WHERE menu_id = $1`, [menuId]).catch(() => {});
      await db.query(`DELETE FROM menu_access_keys WHERE menu_id = $1`, [menuId]).catch(() => {});
      await db.query(`DELETE FROM managed_menus WHERE id = $1`, [menuId]).catch(() => {});
    }

    await db.query(`DELETE FROM audit_events WHERE actor_id = $1`, [owner.accountId]).catch(() => {});
    await db.query(`DELETE FROM app1_sessions WHERE id = $1`, [owner.sessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_devices WHERE id = $1`, [owner.deviceId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [owner.accountId]).catch(() => {});
    await db.end();
  }
});
