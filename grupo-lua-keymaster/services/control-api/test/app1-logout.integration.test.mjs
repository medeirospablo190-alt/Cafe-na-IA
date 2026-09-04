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

async function request(baseUrl, path, { method = "GET", sessionToken, deviceToken } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(sessionToken ? { authorization: `Bearer ${sessionToken}` } : {}),
      ...(deviceToken ? { "x-app1-device-token": deviceToken } : {}),
      ...(method !== "GET" ? { "content-type": "application/json" } : {})
    },
    ...(method !== "GET" ? { body: "{}" } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

test("App1 logout revokes only the bound session and rejects the wrong device token", { skip: !enabled, timeout: 30_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const accountId = uuid();
  const deviceId = uuid();
  const sessionId = uuid();
  const sessionToken = `ci-app1-session-${crypto.randomBytes(24).toString("base64url")}`;
  const deviceToken = `ci-app1-device-${crypto.randomBytes(24).toString("base64url")}`;
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
        `ci_logout_${suffix}`,
        `CI Logout ${suffix}`,
        `usr_${suffix}`,
        `Logout${suffix}`,
        `logout${suffix}`
      ]
    );

    await db.query(
      `INSERT INTO app1_devices
        (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
       VALUES ($1, $2, $3, $4, 'ci', 'CI phone', TRUE, 'ACTIVE')`,
      [deviceId, accountId, `ci-device-${suffix}`, tokenHash(`app1-device:${deviceToken}`)]
    );

    await db.query(
      `INSERT INTO app1_sessions
        (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
       VALUES ($1, $2, $3, 'CI phone', NOW() + INTERVAL '30 minutes', $4, 'FULL')`,
      [sessionId, accountId, tokenHash(`app1:${sessionToken}`), deviceId]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const before = await request(baseUrl, "/v1/app1/me", { sessionToken, deviceToken });
    assert.equal(before.response.status, 200, JSON.stringify(before.data));

    const wrongDevice = await request(baseUrl, "/v1/app1/logout", {
      method: "POST",
      sessionToken,
      deviceToken: `${deviceToken}-wrong`
    });
    assert.equal(wrongDevice.response.status, 401);
    assert.equal(wrongDevice.data.code, "UNAUTHORIZED");

    const stillActive = (await db.query(
      `SELECT revoked_at FROM app1_sessions WHERE id = $1`,
      [sessionId]
    )).rows[0];
    assert.equal(stillActive.revoked_at, null);

    const logout = await request(baseUrl, "/v1/app1/logout", {
      method: "POST",
      sessionToken,
      deviceToken
    });
    assert.equal(logout.response.status, 200, JSON.stringify(logout.data));
    assert.equal(logout.data.ok, true);

    const revoked = (await db.query(
      `SELECT revoked_at FROM app1_sessions WHERE id = $1`,
      [sessionId]
    )).rows[0];
    assert.ok(revoked.revoked_at);

    const after = await request(baseUrl, "/v1/app1/me", { sessionToken, deviceToken });
    assert.equal(after.response.status, 401);

    const auditRow = (await db.query(
      `SELECT action, actor_id, target_id
         FROM audit_events
        WHERE action = 'APP1_SESSION_LOGOUT' AND target_id = $1
        ORDER BY id DESC
        LIMIT 1`,
      [sessionId]
    )).rows[0];
    assert.equal(auditRow?.actor_id, accountId);
    assert.equal(auditRow?.target_id, sessionId);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR target_id = $2`, [accountId, sessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_sessions WHERE id = $1`, [sessionId]).catch(() => {});
    await db.query(`DELETE FROM app1_devices WHERE id = $1`, [deviceId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [accountId]).catch(() => {});
    await db.end();
  }
});
