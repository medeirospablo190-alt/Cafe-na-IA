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
    body: { action, targetId, devLogin, devCredential }
  });
}

test("last DEV can self-recover only when no active DEV exists and cannot be deleted", { skip: !enabled, timeout: 35_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const devId = uuid();
  const otherDevId = uuid();
  const kmSessionId = uuid();
  const devLogin = `ci_last_dev_${suffix}`;
  const otherDevLogin = `ci_other_dev_${suffix}`;
  const devKey = `DEV-${crypto.randomBytes(40).toString("base64url")}`;
  const otherDevKey = `DEV-${crypto.randomBytes(40).toString("base64url")}`;
  const keymasterToken = `ci-km-${crypto.randomBytes(32).toString("base64url")}`;
  let kmDeviceId = null;
  let child = null;

  try {
    kmDeviceId = (await db.query(
      `INSERT INTO keymaster_devices (fingerprint, platform)
       VALUES ($1, 'ci') RETURNING id`,
      [`ci-last-dev-km-${suffix}`]
    )).rows[0].id;

    await db.query(
      `INSERT INTO keymaster_sessions (id, device_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
      [kmSessionId, kmDeviceId, tokenHash(keymasterToken)]
    );

    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, created_by_session)
       VALUES ($1, $2, $3, 'DEV', 'SUSPENDED', $4, $5)`,
      [devId, devLogin, `CI Last DEV ${suffix}`, await hashSecret(devKey), kmSessionId]
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

    const restoreAuth = await authorize(baseUrl, keymasterToken, {
      action: "RESTORE_APP1_ACCOUNT",
      targetId: devId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(restoreAuth.response.status, 200, JSON.stringify(restoreAuth.data));
    assert.equal(restoreAuth.data.scope, `RESTORE_APP1_ACCOUNT:${devId}`);

    const restored = await request(baseUrl, `/v1/keymaster/accounts/${devId}/restore`, {
      method: "POST",
      keymasterToken,
      criticalToken: restoreAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(restored.response.status, 200, JSON.stringify(restored.data));
    assert.equal((await db.query(`SELECT status FROM app1_accounts WHERE id = $1`, [devId])).rows[0].status, "ACTIVE");

    await db.query(`UPDATE app1_accounts SET status = 'SUSPENDED', updated_at = NOW() WHERE id = $1`, [devId]);
    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, created_by_session)
       VALUES ($1, $2, $3, 'DEV', 'ACTIVE', $4, $5)`,
      [otherDevId, otherDevLogin, `CI Other DEV ${suffix}`, await hashSecret(otherDevKey), kmSessionId]
    );

    const blockedSelfRecovery = await authorize(baseUrl, keymasterToken, {
      action: "RESTORE_APP1_ACCOUNT",
      targetId: devId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(blockedSelfRecovery.response.status, 409, JSON.stringify(blockedSelfRecovery.data));
    assert.equal(blockedSelfRecovery.data.code, "DEV_RECOVERY_NOT_ALLOWED");

    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [otherDevId]);
    await db.query(
      `UPDATE app1_accounts
          SET status = 'LOCKED_SECURITY',
              security_locked_at = NOW(),
              security_lock_reason = 'ci-test',
              updated_at = NOW()
        WHERE id = $1`,
      [devId]
    );

    const unlockAuth = await authorize(baseUrl, keymasterToken, {
      action: "UNLOCK_APP1_ACCOUNT",
      targetId: devId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(unlockAuth.response.status, 200, JSON.stringify(unlockAuth.data));
    assert.equal(unlockAuth.data.scope, `UNLOCK_APP1_ACCOUNT:${devId}`);

    const unlocked = await request(baseUrl, `/v1/keymaster/accounts/${devId}/security/unlock`, {
      method: "POST",
      keymasterToken,
      criticalToken: unlockAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(unlocked.response.status, 200, JSON.stringify(unlocked.data));
    assert.equal((await db.query(`SELECT status FROM app1_accounts WHERE id = $1`, [devId])).rows[0].status, "ACTIVE");

    const deleteAuth = await authorize(baseUrl, keymasterToken, {
      action: "DELETE_APP1_ACCOUNT",
      targetId: devId,
      devLogin,
      devCredential: devKey
    });
    assert.equal(deleteAuth.response.status, 200, JSON.stringify(deleteAuth.data));

    const deleteLastDev = await request(baseUrl, `/v1/keymaster/accounts/${devId}`, {
      method: "DELETE",
      keymasterToken,
      criticalToken: deleteAuth.data.authorizationToken
    });
    assert.equal(deleteLastDev.response.status, 409, JSON.stringify(deleteLastDev.data));
    assert.equal(deleteLastDev.data.code, "LAST_DEV_REQUIRED");
    assert.equal((await db.query(`SELECT status FROM app1_accounts WHERE id = $1`, [devId])).rows[0].status, "ACTIVE");
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM critical_authorizations WHERE dev_account_id IN ($1, $2)`, [devId, otherDevId]).catch(() => {});
    await db.query(`DELETE FROM audit_events WHERE actor_id IN ($1, $2, $3) OR target_id IN ($1, $2)`, [devId, otherDevId, kmSessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id IN ($1, $2)`, [devId, otherDevId]).catch(() => {});
    await db.query(`DELETE FROM keymaster_sessions WHERE id = $1`, [kmSessionId]).catch(() => {});
    if (kmDeviceId) await db.query(`DELETE FROM keymaster_devices WHERE id = $1`, [kmDeviceId]).catch(() => {});
    await db.end();
  }
});
