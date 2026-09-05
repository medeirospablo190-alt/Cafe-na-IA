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

async function jsonRequest(baseUrl, path, { method = "GET", body, appToken, appDeviceToken, menuToken, menuDeviceId } = {}) {
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

async function seedAccount(db, suffix, role = "ADM") {
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
     VALUES ($1, $2, $3, $4, 'ACTIVE', 'ci-credential',
             '1.0', '1.0', NOW(), $5, $6, $7, NOW(), NOW())`,
    [accountId, `ci_owner_${suffix}`, `Owner ${suffix}`, role, `usr_${suffix}`, `Owner${suffix}`, `owner${suffix}`]
  );
  await db.query(
    `INSERT INTO app1_devices
      (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
     VALUES ($1, $2, $3, $4, 'ci', 'CI Phone', TRUE, 'ACTIVE')`,
    [deviceId, accountId, `fp-${suffix}`, tokenHash(`app1-device:${deviceToken}`)]
  );
  await db.query(
    `INSERT INTO app1_sessions
      (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
     VALUES ($1, $2, $3, 'CI Phone', NOW() + INTERVAL '30 minutes', $4, 'FULL')`,
    [sessionId, accountId, tokenHash(`app1:${token}`), deviceId]
  );
  return { accountId, deviceId, sessionId, token, deviceToken };
}

async function publicValidate(baseUrl, menuId, key, deviceId) {
  return jsonRequest(baseUrl, "/v1/menu-access/validate", {
    method: "POST",
    body: { menuId, key, deviceId, deviceHint: "CI menu phone", clientLabel: "CI inline" }
  });
}

test("App 1 isola menus por proprietário e entrega Lua inline somente por ticket temporário", { skip: !enabled, timeout: 45_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true" ? { rejectUnauthorized: false } : false
  });
  await db.connect();
  const suffix = crypto.randomBytes(6).toString("hex");
  const owner = await seedAccount(db, `a_${suffix}`);
  const stranger = await seedAccount(db, `b_${suffix}`);
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

    const sourceCode = `-- private ${suffix}\nreturn function() return "INLINE_OK_${suffix}" end`;
    const createMenu = await jsonRequest(baseUrl, "/v1/app1/menu-admin/menus", {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: { name: `Inline Menu ${suffix}`, sourceCode }
    });
    assert.equal(createMenu.response.status, 201, JSON.stringify(createMenu.data));
    assert.equal(createMenu.data.menu.source_kind, "INLINE_ENCRYPTED");
    assert.equal(Object.hasOwn(createMenu.data.menu, "sourceCode"), false);
    assert.equal(Object.hasOwn(createMenu.data.menu, "source_ciphertext"), false);
    menuId = createMenu.data.menu.id;
    const publicId = createMenu.data.menu.public_id;

    const stored = (await db.query(
      `SELECT owner_account_id, source_url, source_kind, source_ciphertext
         FROM managed_menus WHERE id = $1`,
      [menuId]
    )).rows[0];
    assert.equal(stored.owner_account_id, owner.accountId);
    assert.equal(stored.source_url, "private://inline");
    assert.equal(stored.source_kind, "INLINE_ENCRYPTED");
    assert.ok(stored.source_ciphertext && stored.source_ciphertext !== sourceCode);
    assert.equal(String(stored.source_ciphertext).includes(sourceCode), false);

    const ownerList = await jsonRequest(baseUrl, "/v1/app1/menu-admin/menus", {
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(ownerList.response.status, 200, JSON.stringify(ownerList.data));
    assert.ok(ownerList.data.menus.some((menu) => menu.id === menuId));
    assert.equal(JSON.stringify(ownerList.data).includes(sourceCode), false);
    assert.equal(JSON.stringify(ownerList.data).includes(String(stored.source_ciphertext)), false);

    const strangerList = await jsonRequest(baseUrl, "/v1/app1/menu-admin/menus", {
      appToken: stranger.token,
      appDeviceToken: stranger.deviceToken
    });
    assert.equal(strangerList.response.status, 200, JSON.stringify(strangerList.data));
    assert.equal(strangerList.data.menus.some((menu) => menu.id === menuId), false);

    const strangerSource = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/source`, {
      appToken: stranger.token,
      appDeviceToken: stranger.deviceToken
    });
    assert.equal(strangerSource.response.status, 404, JSON.stringify(strangerSource.data));

    const ownerSource = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/source`, {
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(ownerSource.response.status, 200, JSON.stringify(ownerSource.data));
    assert.equal(ownerSource.response.headers.get("cache-control"), "no-store, private");
    assert.equal(ownerSource.data.sourceCode, sourceCode);

    const strangerKey = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken: stranger.token,
      appDeviceToken: stranger.deviceToken,
      body: { name: "Forbidden", kind: "FREE", durationValue: 1 }
    });
    assert.equal(strangerKey.response.status, 404, JSON.stringify(strangerKey.data));

    const createKey = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: { name: "Inline key", kind: "FREE", durationValue: 2 }
    });
    assert.equal(createKey.response.status, 201, JSON.stringify(createKey.data));
    const keyId = createKey.data.key.id;
    const keyValue = createKey.data.key.value;
    const menuDeviceId = `inline-device-${suffix}`;

    const validation = await publicValidate(baseUrl, publicId, keyValue, menuDeviceId);
    assert.equal(validation.response.status, 200, JSON.stringify(validation.data));
    const accessToken = validation.data.token;

    const manifest = await jsonRequest(baseUrl, `/v1/menu-access/${publicId}/manifest`, {
      menuToken: accessToken,
      menuDeviceId
    });
    assert.equal(manifest.response.status, 200, JSON.stringify(manifest.data));
    assert.ok(String(manifest.data.menu.sourceUrl).startsWith(`${baseUrl}/v1/menu-access/${publicId}/source/`));
    assert.equal(JSON.stringify(manifest.data).includes(sourceCode), false);
    assert.equal(JSON.stringify(manifest.data).includes(String(stored.source_ciphertext)), false);

    const sourceResponse = await fetch(manifest.data.menu.sourceUrl);
    assert.equal(sourceResponse.status, 200);
    assert.match(String(sourceResponse.headers.get("content-type")), /^text\/plain/);
    assert.equal(sourceResponse.headers.get("cache-control"), "no-store, private, max-age=0");
    assert.equal(await sourceResponse.text(), sourceCode);

    const suspend = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/state/suspend`, {
      method: "POST",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken,
      body: { durationMinutes: 5 }
    });
    assert.equal(suspend.response.status, 200, JSON.stringify(suspend.data));
    assert.equal(suspend.data.menu.status, "SUSPENDED");
    assert.ok(suspend.data.menu.suspended_until);

    const whileSuspended = await publicValidate(baseUrl, publicId, keyValue, menuDeviceId);
    assert.equal(whileSuspended.response.status, 403, JSON.stringify(whileSuspended.data));
    assert.equal(whileSuspended.data.code, "MENU_SUSPENDED");

    await db.query(
      `UPDATE managed_menus SET status = 'SUSPENDED', suspended_until = NOW() - INTERVAL '1 minute' WHERE id = $1`,
      [menuId]
    );
    const afterTimer = await publicValidate(baseUrl, publicId, keyValue, menuDeviceId);
    assert.equal(afterTimer.response.status, 200, JSON.stringify(afterTimer.data));
    const restored = (await db.query(`SELECT status, suspended_until FROM managed_menus WHERE id = $1`, [menuId])).rows[0];
    assert.equal(restored.status, "ACTIVE");
    assert.equal(restored.suspended_until, null);

    const manifestBeforeDelete = await jsonRequest(baseUrl, `/v1/menu-access/${publicId}/manifest`, {
      menuToken: afterTimer.data.token,
      menuDeviceId
    });
    assert.equal(manifestBeforeDelete.response.status, 200, JSON.stringify(manifestBeforeDelete.data));
    const ticketUrl = manifestBeforeDelete.data.menu.sourceUrl;

    const deleteKey = await jsonRequest(baseUrl, `/v1/app1/menu-admin/keys/${keyId}`, {
      method: "DELETE",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(deleteKey.response.status, 200, JSON.stringify(deleteKey.data));

    const keyListAfterDelete = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}/keys`, {
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(keyListAfterDelete.response.status, 200, JSON.stringify(keyListAfterDelete.data));
    assert.equal(keyListAfterDelete.data.keys.some((key) => key.id === keyId), false);

    const oldTicketAfterDelete = await fetch(ticketUrl);
    assert.equal(oldTicketAfterDelete.status, 401);

    const deletedKeyValidation = await publicValidate(baseUrl, publicId, keyValue, menuDeviceId);
    assert.equal(deletedKeyValidation.response.status, 401, JSON.stringify(deletedKeyValidation.data));

    const deleteMenu = await jsonRequest(baseUrl, `/v1/app1/menu-admin/menus/${menuId}`, {
      method: "DELETE",
      appToken: owner.token,
      appDeviceToken: owner.deviceToken
    });
    assert.equal(deleteMenu.response.status, 200, JSON.stringify(deleteMenu.data));
    const menuRow = (await db.query(`SELECT status, deleted_at FROM managed_menus WHERE id = $1`, [menuId])).rows[0];
    assert.equal(menuRow.status, "DELETED");
    assert.ok(menuRow.deleted_at);
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
    for (const account of [owner, stranger]) {
      await db.query(`DELETE FROM audit_events WHERE actor_id = $1`, [account.accountId]).catch(() => {});
      await db.query(`DELETE FROM app1_sessions WHERE id = $1`, [account.sessionId]).catch(() => {});
      await db.query(`DELETE FROM app1_devices WHERE id = $1`, [account.deviceId]).catch(() => {});
      await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [account.accountId]).catch(() => {});
    }
    await db.end();
  }
});
