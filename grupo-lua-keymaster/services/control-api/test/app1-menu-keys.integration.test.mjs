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
  for (let attempt = 0; attempt < 80; attempt += 1) {
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

async function request(baseUrl, path, {
  method = "GET",
  sessionToken,
  deviceToken,
  body
} = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(sessionToken ? { authorization: `Bearer ${sessionToken}` } : {}),
      ...(deviceToken ? { "x-app1-device-token": deviceToken } : {}),
      ...(body !== undefined ? { "content-type": "application/json" } : {})
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function seedAccount(db, suffix, label) {
  const accountId = uuid();
  const deviceId = uuid();
  const sessionId = uuid();
  const sessionToken = `ci-app1-${label}-${crypto.randomBytes(24).toString("base64url")}`;
  const deviceToken = `ci-device-${label}-${crypto.randomBytes(24).toString("base64url")}`;

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
      `ci_key_${label}_${suffix}`,
      `CI Key ${label} ${suffix}`,
      `usr_${label}_${suffix}`,
      `Key${label}${suffix}`,
      `key${label}${suffix}`
    ]
  );

  await db.query(
    `INSERT INTO app1_devices
      (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
     VALUES ($1, $2, $3, $4, 'ci', $5, TRUE, 'ACTIVE')`,
    [
      deviceId,
      accountId,
      `ci-key-device-${label}-${suffix}`,
      tokenHash(`app1-device:${deviceToken}`),
      `CI key phone ${label}`
    ]
  );

  await db.query(
    `INSERT INTO app1_sessions
      (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
     VALUES ($1, $2, $3, $4, NOW() + INTERVAL '30 minutes', $5, 'FULL')`,
    [sessionId, accountId, tokenHash(`app1:${sessionToken}`), `CI key phone ${label}`, deviceId]
  );

  return { accountId, deviceId, sessionId, sessionToken, deviceToken };
}

test("App1 menu keys stay account-scoped and never leak plaintext in lists or audit metadata", { skip: !enabled, timeout: 35_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const owner = await seedAccount(db, suffix, "owner");
  const stranger = await seedAccount(db, suffix, "stranger");
  const menuId = uuid();
  const menuKeyId = uuid();
  const publicId = `menu_${crypto.randomBytes(9).toString("base64url")}`;
  const plainKey = `FREE-${crypto.randomBytes(24).toString("base64url")}`;
  const keyHint = `${plainKey.slice(0, 9)}…${plainKey.slice(-5)}`;
  let bindingId = null;
  let child = null;

  try {
    await db.query(
      `INSERT INTO managed_menus (id, public_id, name, source_url, status)
       VALUES ($1, $2, $3, 'https://raw.githubusercontent.com/example/repo/main/menu.lua', 'ACTIVE')`,
      [menuId, publicId, `CI Menu ${suffix}`]
    );
    await db.query(
      `INSERT INTO menu_access_keys
        (id, menu_id, kind, status, key_hash, key_hint, note, expires_at)
       VALUES ($1, $2, 'FREE', 'ACTIVE', $3, $4, 'CI owner key', NOW() + INTERVAL '12 hours')`,
      [menuKeyId, menuId, tokenHash(`menu-key:${plainKey}`), keyHint]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const initial = await request(baseUrl, "/v1/app1/keys", {
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken
    });
    assert.equal(initial.response.status, 200, JSON.stringify(initial.data));
    assert.deepEqual(initial.data.keys, []);

    const claimed = await request(baseUrl, "/v1/app1/keys/claim", {
      method: "POST",
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken,
      body: { menuId: `${baseUrl}/l/${publicId}`, key: plainKey }
    });
    assert.equal(claimed.response.status, 201, JSON.stringify(claimed.data));
    assert.equal(claimed.data.key.kind, "FREE");
    assert.equal(claimed.data.key.menu.publicId, publicId);
    assert.equal(claimed.data.key.keyHint, keyHint);
    assert.equal(claimed.data.key.usable, true);
    assert.equal(JSON.stringify(claimed.data).includes(plainKey), false, "claim response leaked plaintext key");
    bindingId = claimed.data.key.bindingId;
    assert.ok(bindingId);

    const listOwner = await request(baseUrl, "/v1/app1/keys", {
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken
    });
    assert.equal(listOwner.response.status, 200, JSON.stringify(listOwner.data));
    assert.equal(listOwner.data.keys.length, 1);
    assert.equal(JSON.stringify(listOwner.data).includes(plainKey), false, "list response leaked plaintext key");

    const listStranger = await request(baseUrl, "/v1/app1/keys", {
      sessionToken: stranger.sessionToken,
      deviceToken: stranger.deviceToken
    });
    assert.equal(listStranger.response.status, 200, JSON.stringify(listStranger.data));
    assert.deepEqual(listStranger.data.keys, []);

    const strangerReveal = await request(baseUrl, `/v1/app1/keys/${bindingId}/reveal`, {
      method: "POST",
      sessionToken: stranger.sessionToken,
      deviceToken: stranger.deviceToken,
      body: {}
    });
    assert.equal(strangerReveal.response.status, 404);

    const ownerReveal = await request(baseUrl, `/v1/app1/keys/${bindingId}/reveal`, {
      method: "POST",
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken,
      body: {}
    });
    assert.equal(ownerReveal.response.status, 200, JSON.stringify(ownerReveal.data));
    assert.equal(ownerReveal.data.key, plainKey);

    const stored = (await db.query(
      `SELECT key_ciphertext FROM app1_menu_key_bindings WHERE id = $1`,
      [bindingId]
    )).rows[0];
    assert.ok(stored?.key_ciphertext);
    assert.notEqual(stored.key_ciphertext, plainKey);
    assert.equal(String(stored.key_ciphertext).includes(plainKey), false);

    const auditRows = (await db.query(
      `SELECT metadata::text AS metadata
         FROM audit_events
        WHERE actor_id = $1
          AND action IN ('APP1_MENU_KEY_ADDED', 'APP1_MENU_KEY_REFRESHED', 'APP1_MENU_KEY_REVEALED')`,
      [owner.accountId]
    )).rows;
    assert.ok(auditRows.length >= 2);
    for (const row of auditRows) {
      assert.equal(String(row.metadata || "").includes(plainKey), false, "audit metadata leaked plaintext key");
    }

    await db.query(`UPDATE menu_access_keys SET status = 'SUSPENDED', suspended_at = NOW() WHERE id = $1`, [menuKeyId]);
    const suspendedList = await request(baseUrl, "/v1/app1/keys", {
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken
    });
    assert.equal(suspendedList.response.status, 200, JSON.stringify(suspendedList.data));
    assert.equal(suspendedList.data.keys[0].status, "SUSPENDED");
    assert.equal(suspendedList.data.keys[0].usable, false);

    const removed = await request(baseUrl, `/v1/app1/keys/${bindingId}`, {
      method: "DELETE",
      sessionToken: owner.sessionToken,
      deviceToken: owner.deviceToken
    });
    assert.equal(removed.response.status, 200, JSON.stringify(removed.data));

    const underlying = (await db.query(
      `SELECT status FROM menu_access_keys WHERE id = $1`,
      [menuKeyId]
    )).rows[0];
    assert.equal(underlying?.status, "SUSPENDED", "removing App1 binding must not revoke the underlying menu key");
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    if (bindingId) await db.query(`DELETE FROM app1_menu_key_bindings WHERE id = $1`, [bindingId]).catch(() => {});
    await db.query(
      `DELETE FROM audit_events
        WHERE actor_id IN ($1, $2)
           OR target_id IN ($1, $2, $3, $4)`,
      [owner.accountId, stranger.accountId, menuId, menuKeyId]
    ).catch(() => {});
    await db.query(`DELETE FROM app1_sessions WHERE id IN ($1, $2)`, [owner.sessionId, stranger.sessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_devices WHERE id IN ($1, $2)`, [owner.deviceId, stranger.deviceId]).catch(() => {});
    await db.query(`DELETE FROM menu_access_keys WHERE id = $1`, [menuKeyId]).catch(() => {});
    await db.query(`DELETE FROM managed_menus WHERE id = $1`, [menuId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id IN ($1, $2)`, [owner.accountId, stranger.accountId]).catch(() => {});
    await db.end();
  }
});
