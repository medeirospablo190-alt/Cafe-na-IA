import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import net from "node:net";
import { spawn } from "node:child_process";
import pg from "pg";
import { hashSecret } from "../src/security.js";

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
  for (let i = 0; i < 80; i += 1) {
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

async function login(baseUrl, { login, credential, nativeDeviceId, installationId, deviceToken = "" }) {
  const response = await fetch(`${baseUrl}/v1/app1/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      login,
      credential,
      platform: "android",
      nativeDeviceId,
      installationId,
      deviceLabel: "CI Android",
      ...(deviceToken ? { deviceToken } : {})
    })
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

test("same App 1 phone is recovered by its secure device token when native identity changes", { skip: !enabled, timeout: 30_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const accountId = uuid();
  const privateLogin = `ci_device_${suffix}`;
  const credential = `ADM1-${crypto.randomBytes(48).toString("base64url")}`;
  let child = null;

  try {
    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash)
       VALUES ($1, $2, $3, 'ADM', 'ACTIVE', $4)`,
      [accountId, privateLogin, `CI device ${suffix}`, await hashSecret(credential)]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        PORT: String(port),
        PUBLIC_BASE_URL: baseUrl,
        APP_INTEGRITY_MODE: "report",
        CRITICAL_ACTIONS_ENABLED: "false"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const first = await login(baseUrl, {
      login: privateLogin,
      credential,
      nativeDeviceId: `native-before-${suffix}`,
      installationId: `install-${suffix}`
    });
    assert.equal(first.response.status, 200, JSON.stringify(first.data));
    assert.equal(typeof first.data.deviceToken, "string");
    assert.ok(first.data.deviceToken.length > 20);

    const firstDevice = (await db.query(
      `SELECT id, fingerprint FROM app1_devices
        WHERE account_id = $1 AND status = 'ACTIVE'`,
      [accountId]
    )).rows;
    assert.equal(firstDevice.length, 1);
    const originalDeviceId = firstDevice[0].id;
    const originalFingerprint = firstDevice[0].fingerprint;

    // Simulates an OS/app update changing the native ID while SecureStore still
    // contains the server-issued device token. This must remain the same phone.
    const second = await login(baseUrl, {
      login: privateLogin,
      credential,
      nativeDeviceId: `native-after-${suffix}`,
      installationId: `install-${suffix}`,
      deviceToken: first.data.deviceToken
    });
    assert.equal(second.response.status, 200, JSON.stringify(second.data));
    assert.equal(second.data.deviceToken, undefined);

    const devicesAfter = (await db.query(
      `SELECT id, fingerprint FROM app1_devices
        WHERE account_id = $1 AND status = 'ACTIVE'`,
      [accountId]
    )).rows;
    assert.equal(devicesAfter.length, 1);
    assert.equal(devicesAfter[0].id, originalDeviceId);
    assert.notEqual(devicesAfter[0].fingerprint, originalFingerprint);

    const account = (await db.query(
      `SELECT failed_device_attempts, status FROM app1_accounts WHERE id = $1`,
      [accountId]
    )).rows[0];
    assert.equal(account.status, "ACTIVE");
    assert.equal(Number(account.failed_device_attempts), 0);

    const recoveredAudit = (await db.query(
      `SELECT COUNT(*)::int AS count FROM audit_events
        WHERE actor_id = $1 AND action = 'APP1_DEVICE_IDENTITY_RECOVERED'`,
      [accountId]
    )).rows[0];
    assert.equal(recoveredAudit.count, 1);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR target_id = $1`, [accountId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [accountId]).catch(() => {});
    await db.end();
  }
});
