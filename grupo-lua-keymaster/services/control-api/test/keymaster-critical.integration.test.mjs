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

async function jsonRequest(baseUrl, path, { method = "GET", keymasterToken, body, criticalToken } = {}) {
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

test("Keymaster critical DEV flow hides private logins and requires private DEV login plus credential", { skip: !enabled, timeout: 30_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const devId = uuid();
  const devLogin = `ci_private_dev_${suffix}`;
  const devLabel = `CI DEV ${suffix}`;
  const devKey = `DEV-${crypto.randomBytes(40).toString("base64url")}`;
  const keymasterSessionId = uuid();
  const keymasterToken = `ci-keymaster-${crypto.randomBytes(32).toString("base64url")}`;
  let keymasterDeviceId = null;
  let createdAccountId = null;
  let child = null;

  try {
    const devHash = await hashSecret(devKey);
    keymasterDeviceId = (await db.query(
      `INSERT INTO keymaster_devices (fingerprint, platform)
       VALUES ($1, 'ci') RETURNING id`,
      [`ci-km-device-${suffix}`]
    )).rows[0].id;

    await db.query(
      `INSERT INTO keymaster_sessions (id, device_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
      [keymasterSessionId, keymasterDeviceId, tokenHash(keymasterToken)]
    );

    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, created_by_session)
       VALUES ($1, $2, $3, 'DEV', 'ACTIVE', $4, $5)`,
      [devId, devLogin, devLabel, devHash, keymasterSessionId]
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

    const targetLogin = `ci_private_adm_${suffix}`;
    const targetLabel = `Conta CI ${suffix}`;
    const created = await jsonRequest(baseUrl, "/v1/keymaster/accounts", {
      method: "POST",
      keymasterToken,
      body: { displayName: targetLabel, login: targetLogin, role: "ADM" }
    });
    assert.equal(created.response.status, 201, JSON.stringify(created.data));
    assert.equal(created.data.account.name, targetLabel);
    assert.equal(created.data.privateLogin, targetLogin);
    assert.equal(typeof created.data.credential, "string");
    createdAccountId = created.data.account.id;
    const originalCredential = created.data.credential;

    const listed = await jsonRequest(baseUrl, `/v1/keymaster/accounts?q=${encodeURIComponent(targetLabel)}`, { keymasterToken });
    assert.equal(listed.response.status, 200, JSON.stringify(listed.data));
    const listedTarget = listed.data.accounts.find((item) => item.id === createdAccountId);
    assert.ok(listedTarget);
    assert.equal(listedTarget.name, targetLabel);
    assert.equal(Object.hasOwn(listedTarget, "login"), false);
    assert.equal(Object.hasOwn(listedTarget, "privateLogin"), false);

    const labelOnly = await jsonRequest(baseUrl, "/v1/keymaster/critical/authorize", {
      method: "POST",
      keymasterToken,
      body: {
        action: "REVEAL_APP1_CREDENTIAL",
        targetId: createdAccountId,
        devLogin: devLabel,
        devCredential: devKey
      }
    });
    assert.equal(labelOnly.response.status, 403);
    assert.equal(labelOnly.data.code, "INVALID_DEV_CREDENTIAL");

    const wrong = await jsonRequest(baseUrl, "/v1/keymaster/critical/authorize", {
      method: "POST",
      keymasterToken,
      body: {
        action: "REVEAL_APP1_CREDENTIAL",
        targetId: createdAccountId,
        devLogin,
        devCredential: `${devKey}-wrong`
      }
    });
    assert.equal(wrong.response.status, 403);
    assert.equal(wrong.data.code, "INVALID_DEV_CREDENTIAL");

    const authorized = await jsonRequest(baseUrl, "/v1/keymaster/critical/authorize", {
      method: "POST",
      keymasterToken,
      body: {
        action: "REVEAL_APP1_CREDENTIAL",
        targetId: createdAccountId,
        devLogin,
        devCredential: devKey
      }
    });
    assert.equal(authorized.response.status, 200, JSON.stringify(authorized.data));
    assert.equal(authorized.data.dev.name, devLabel);
    assert.equal(Object.hasOwn(authorized.data.dev, "login"), false);

    const revealed = await jsonRequest(baseUrl, `/v1/keymaster/accounts/${createdAccountId}/credential/reveal`, {
      method: "POST",
      keymasterToken,
      criticalToken: authorized.data.authorizationToken,
      body: {}
    });
    assert.equal(revealed.response.status, 200, JSON.stringify(revealed.data));
    assert.equal(revealed.data.privateLogin, targetLogin);
    assert.equal(revealed.data.credential, originalCredential);

    const reused = await jsonRequest(baseUrl, `/v1/keymaster/accounts/${createdAccountId}/credential/reveal`, {
      method: "POST",
      keymasterToken,
      criticalToken: authorized.data.authorizationToken,
      body: {}
    });
    assert.equal(reused.response.status, 403);

    const rotateAuth = await jsonRequest(baseUrl, "/v1/keymaster/critical/authorize", {
      method: "POST",
      keymasterToken,
      body: {
        action: "ROTATE_APP1_CREDENTIAL",
        targetId: createdAccountId,
        devLogin,
        devCredential: devKey
      }
    });
    assert.equal(rotateAuth.response.status, 200, JSON.stringify(rotateAuth.data));

    const rotated = await jsonRequest(baseUrl, `/v1/keymaster/accounts/${createdAccountId}/rotate`, {
      method: "POST",
      keymasterToken,
      criticalToken: rotateAuth.data.authorizationToken,
      body: {}
    });
    assert.equal(rotated.response.status, 200, JSON.stringify(rotated.data));
    assert.equal(rotated.data.privateLogin, targetLogin);
    assert.notEqual(rotated.data.credential, originalCredential);
    assert.match(rotated.data.credential, /^ADM1-/);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    if (createdAccountId) {
      await db.query(`DELETE FROM critical_authorizations WHERE action LIKE '%:' || $1`, [createdAccountId]).catch(() => {});
      await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [createdAccountId]).catch(() => {});
    }
    await db.query(`DELETE FROM critical_authorizations WHERE dev_account_id = $1`, [devId]).catch(() => {});
    await db.query(`DELETE FROM audit_events WHERE actor_id IN ($1, $2) OR target_id IN ($1, $2)`, [devId, createdAccountId || ""]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [devId]).catch(() => {});
    await db.query(`DELETE FROM keymaster_sessions WHERE id = $1`, [keymasterSessionId]).catch(() => {});
    if (keymasterDeviceId) await db.query(`DELETE FROM keymaster_devices WHERE id = $1`, [keymasterDeviceId]).catch(() => {});
    await db.end();
  }
});
