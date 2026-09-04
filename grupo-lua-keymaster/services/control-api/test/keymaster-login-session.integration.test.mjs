import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import net from "node:net";
import { spawn } from "node:child_process";
import pg from "pg";
import { hashSecret } from "../src/security.js";

const enabled = Boolean(process.env.DATABASE_URL);

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

test("Keymaster login creates a usable server session and logout revokes it", { skip: !enabled, timeout: 35_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const accessKey = `km-ci-${crypto.randomBytes(48).toString("base64url")}`;
  const accessHash = await hashSecret(accessKey);
  const installationId = `ci-install-${crypto.randomUUID()}`;
  const nativeDeviceId = `ci-native-${crypto.randomUUID()}`;
  let child = null;
  let sessionId = null;
  let deviceId = null;

  try {
    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        PORT: String(port),
        PUBLIC_BASE_URL: baseUrl,
        KEYMASTER_ACCESS_HASH: accessHash,
        APP_INTEGRITY_MODE: "report",
        CRITICAL_ACTIONS_ENABLED: "false"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const loginResponse = await fetch(`${baseUrl}/v1/keymaster/login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        accessKey,
        platform: "ci-login",
        nativeDeviceId,
        installationId
      })
    });
    const loginData = await loginResponse.json();
    assert.equal(loginResponse.status, 200, JSON.stringify(loginData));
    assert.equal(loginData.ok, true);
    assert.equal(typeof loginData.token, "string");
    assert.ok(loginData.token.length > 30);

    const sessionResponse = await fetch(`${baseUrl}/v1/keymaster/session`, {
      headers: { authorization: `Bearer ${loginData.token}` }
    });
    const sessionData = await sessionResponse.json();
    assert.equal(sessionResponse.status, 200, JSON.stringify(sessionData));
    assert.equal(sessionData.ok, true);
    sessionId = sessionData.session.id;
    deviceId = sessionData.session.deviceId;
    assert.ok(sessionId);
    assert.ok(deviceId);

    const logoutResponse = await fetch(`${baseUrl}/v1/keymaster/logout`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${loginData.token}`,
        "content-type": "application/json"
      },
      body: "{}"
    });
    const logoutData = await logoutResponse.json();
    assert.equal(logoutResponse.status, 200, JSON.stringify(logoutData));
    assert.equal(logoutData.ok, true);

    const afterLogout = await fetch(`${baseUrl}/v1/keymaster/session`, {
      headers: { authorization: `Bearer ${loginData.token}` }
    });
    const afterLogoutData = await afterLogout.json();
    assert.equal(afterLogout.status, 401, JSON.stringify(afterLogoutData));
    assert.equal(afterLogoutData.code, "UNAUTHORIZED");

    const revokedAt = (await db.query(
      `SELECT revoked_at FROM keymaster_sessions WHERE id = $1`,
      [sessionId]
    )).rows[0]?.revoked_at;
    assert.ok(revokedAt);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    if (sessionId) {
      await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR target_id = $1`, [sessionId]).catch(() => {});
      await db.query(`DELETE FROM keymaster_sessions WHERE id = $1`, [sessionId]).catch(() => {});
    }
    if (deviceId) {
      await db.query(`DELETE FROM audit_events WHERE actor_id = $1`, [String(deviceId)]).catch(() => {});
      await db.query(`DELETE FROM keymaster_devices WHERE id = $1`, [deviceId]).catch(() => {});
    }
    await db.end();
  }
});
