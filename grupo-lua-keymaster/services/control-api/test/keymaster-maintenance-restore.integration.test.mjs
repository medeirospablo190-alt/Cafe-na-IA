import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import net from "node:net";
import { spawn } from "node:child_process";
import pg from "pg";
import { hashSecret, tokenHash } from "../src/security.js";

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
  keymasterToken,
  criticalToken,
  body
} = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(keymasterToken ? { authorization: `Bearer ${keymasterToken}` } : {}),
      ...(criticalToken ? { "x-critical-authorization": criticalToken } : {}),
      ...(body !== undefined ? { "content-type": "application/json" } : {})
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function authorize(baseUrl, keymasterToken, { action, targetId, devLogin, devCredential }) {
  return request(baseUrl, "/v1/keymaster/critical/authorize", {
    method: "POST",
    keymasterToken,
    body: { action, ...(targetId ? { targetId } : {}), devLogin, devCredential }
  });
}

test("Keymaster restore needs one-time DEV auth and maintenance revokes active App1 sessions", { skip: !enabled, timeout: 35_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const devId = uuid();
  const targetId = uuid();
  const appDeviceId = uuid();
  const appSessionId = uuid();
  const kmSessionId = uuid();
  const devLogin = `ci_restore_dev_${suffix}`;
  const devKey = `DEV-${crypto.randomBytes(40).toString("base64url")}`;
  const keymasterToken = `ci-km-${crypto.randomBytes(32).toString("base64url")}`;
  const appSessionToken = `ci-app-${crypto.randomBytes(32).toString("base64url")}`;
  const appDeviceToken = `ci-device-${crypto.randomBytes(32).toString("base64url")}`;
  let kmDeviceId = null;
  let child = null;

  try {
    const devHash = await hashSecret(devKey);
    kmDeviceId = (await db.query(
      `INSERT INTO keymaster_devices (fingerprint, platform)
       VALUES ($1, 'ci') RETURNING id`,
      [`ci-km-${suffix}`]
    )).rows[0].id;

    await db.query(
      `INSERT INTO keymaster_sessions (id, device_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
      [kmSessionId, kmDeviceId, tokenHash(keymasterToken)]
    );

    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, created_by_session)
       VALUES ($1, $2, $3, 'DEV', 'ACTIVE', $4, $5)`,
      [devId, devLogin, `CI DEV ${suffix}`, devHash, kmSessionId]
    );

    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, created_by_session,
         terms_version, privacy_version, terms_accepted_at,
         public_profile_id, public_name, public_name_normalized,
         public_name_verified_at, onboarding_completed_at)
       VALUES ($1, $2, $3, 'ADM', 'SUSPENDED', 'ci-target-hash', $4,
               '1.0', '1.0', NOW(), $5, $6, $7, NOW(), NOW())`,
      [
        targetId,
        `ci_restore_target_${suffix}`,
        `CI Restore ${suffix}`,
        kmSessionId,
        `usr_${suffix}`,
        `Restore${suffix}`,
        `restore${suffix}`
      ]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        PORT: String(port),
        PUBLIC_BASE_URL: baseUrl,
        CRITICAL_ACTIONS_ENABLED: "false"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const withoutAuth = await request(baseUrl, `/v1/keymaster/accounts/${targetId}/restore`, {
      method: "POST",
      keymasterToken,
      body: {}
    });
    assert.equal(withoutAuth.response.status, 403, JSON.stringify(withoutAuth.data));
    assert.equal(withoutAuth.data.code, "DEV_REAUTH_REQUIRED");

    const restoreAuth = await authorize(baseUrl, keymasterToken, {
      action: "RESTORE_APP1_ACCOUNT",
      targetId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(restoreAuth.response.status, 200, JSON.stringify(restoreAuth.data));
    assert.equal(restoreAuth.data.scope, `RESTORE_APP1_ACCOUNT:${targetId}`);

    const restored = await request(baseUrl, `/v1/keymaster/accounts/${targetId}/restore`, {
      method: "POST",
      keymasterToken,
      criticalToken: restoreAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(restored.response.status, 200, JSON.stringify(restored.data));
    assert.equal((await db.query(`SELECT status FROM app1_accounts WHERE id = $1`, [targetId])).rows[0].status, "ACTIVE");

    const suspendedAgain = await request(baseUrl, `/v1/keymaster/accounts/${targetId}/suspend`, {
      method: "POST",
      keymasterToken,
      body: {}
    });
    assert.equal(suspendedAgain.response.status, 200, JSON.stringify(suspendedAgain.data));

    const reused = await request(baseUrl, `/v1/keymaster/accounts/${targetId}/restore`, {
      method: "POST",
      keymasterToken,
      criticalToken: restoreAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(reused.response.status, 403);
    assert.equal(reused.data.code, "DEV_REAUTH_REQUIRED");

    const secondRestoreAuth = await authorize(baseUrl, keymasterToken, {
      action: "RESTORE_APP1_ACCOUNT",
      targetId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(secondRestoreAuth.response.status, 200, JSON.stringify(secondRestoreAuth.data));
    const restoredAgain = await request(baseUrl, `/v1/keymaster/accounts/${targetId}/restore`, {
      method: "POST",
      keymasterToken,
      criticalToken: secondRestoreAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(restoredAgain.response.status, 200, JSON.stringify(restoredAgain.data));

    await db.query(
      `INSERT INTO app1_devices
        (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
       VALUES ($1, $2, $3, $4, 'ci', 'CI phone', TRUE, 'ACTIVE')`,
      [appDeviceId, targetId, `ci-app-device-${suffix}`, tokenHash(`app1-device:${appDeviceToken}`)]
    );
    await db.query(
      `INSERT INTO app1_sessions
        (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
       VALUES ($1, $2, $3, 'CI phone', NOW() + INTERVAL '30 minutes', $4, 'FULL')`,
      [appSessionId, targetId, tokenHash(`app1:${appSessionToken}`), appDeviceId]
    );

    const maintenanceAuth = await authorize(baseUrl, keymasterToken, {
      action: "APP1_MAINTENANCE_ON",
      devLogin,
      devCredential: devKey
    });
    assert.equal(maintenanceAuth.response.status, 200, JSON.stringify(maintenanceAuth.data));

    const maintenanceOn = await request(baseUrl, "/v1/keymaster/critical/execute", {
      method: "POST",
      keymasterToken,
      body: {
        action: "APP1_MAINTENANCE_ON",
        authorizationToken: maintenanceAuth.data.authorizationToken
      }
    });
    assert.equal(maintenanceOn.response.status, 200, JSON.stringify(maintenanceOn.data));
    assert.equal(maintenanceOn.data.app1Maintenance, true);
    assert.ok(Number(maintenanceOn.data.revokedSessions) >= 1);

    const revokedAt = (await db.query(
      `SELECT revoked_at FROM app1_sessions WHERE id = $1`,
      [appSessionId]
    )).rows[0].revoked_at;
    assert.ok(revokedAt);

    const setting = (await db.query(
      `SELECT value FROM system_settings WHERE key = 'app1_maintenance' LIMIT 1`
    )).rows[0]?.value;
    assert.equal(Boolean(setting?.enabled), true);

    const maintenanceOffAuth = await authorize(baseUrl, keymasterToken, {
      action: "APP1_MAINTENANCE_OFF",
      devLogin,
      devCredential: devKey
    });
    assert.equal(maintenanceOffAuth.response.status, 200, JSON.stringify(maintenanceOffAuth.data));
    const maintenanceOff = await request(baseUrl, "/v1/keymaster/critical/execute", {
      method: "POST",
      keymasterToken,
      body: {
        action: "APP1_MAINTENANCE_OFF",
        authorizationToken: maintenanceOffAuth.data.authorizationToken
      }
    });
    assert.equal(maintenanceOff.response.status, 200, JSON.stringify(maintenanceOff.data));
    assert.equal(maintenanceOff.data.app1Maintenance, false);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(
      `UPDATE system_settings
          SET value = '{"enabled":false}'::jsonb, updated_at = NOW()
        WHERE key = 'app1_maintenance'`
    ).catch(() => {});
    await db.query(`DELETE FROM critical_authorizations WHERE dev_account_id = $1 OR action LIKE '%:' || $2`, [devId, targetId]).catch(() => {});
    await db.query(`DELETE FROM audit_events WHERE actor_id IN ($1, $2) OR target_id IN ($1, $2, $3)`, [devId, targetId, appSessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_sessions WHERE id = $1`, [appSessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_devices WHERE id = $1`, [appDeviceId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id IN ($1, $2)`, [targetId, devId]).catch(() => {});
    await db.query(`DELETE FROM keymaster_sessions WHERE id = $1`, [kmSessionId]).catch(() => {});
    if (kmDeviceId) await db.query(`DELETE FROM keymaster_devices WHERE id = $1`, [kmDeviceId]).catch(() => {});
    await db.end();
  }
});
