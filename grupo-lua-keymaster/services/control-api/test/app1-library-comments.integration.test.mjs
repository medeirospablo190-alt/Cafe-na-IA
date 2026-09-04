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

async function request(baseUrl, path, { method = "GET", sessionToken, deviceToken, body } = {}) {
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

test("App1 library sharing stores optional comments and enforces the 500-character boundary", { skip: !enabled, timeout: 30_000 }, async () => {
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
  const itemId = uuid();
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
        `ci_feed_login_${suffix}`,
        `CI Feed ${suffix}`,
        `usr_${suffix}`,
        `Feed${suffix}`,
        `feed${suffix}`
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

    await db.query(
      `INSERT INTO app1_library_items (id, account_id, kind, title, text_content)
       VALUES ($1, $2, 'LOADSTRING', 'Loader CI', 'loadstring("print(1)")()')`,
      [itemId, accountId]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const shared = await request(baseUrl, `/v1/app1/library/${itemId}/share`, {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { comment: "  Teste do feed\r\nno celular  " }
    });
    assert.equal(shared.response.status, 201, JSON.stringify(shared.data));
    assert.equal(shared.data.post.comment_text, "Teste do feed\nno celular");

    const listed = await request(baseUrl, "/v1/app1/feed", { sessionToken, deviceToken });
    assert.equal(listed.response.status, 200, JSON.stringify(listed.data));
    const post = listed.data.posts.find((item) => item.id === shared.data.post.id);
    assert.ok(post);
    assert.equal(post.comment, "Teste do feed\nno celular");
    assert.equal(post.item.title, "Loader CI");

    const detail = await request(baseUrl, `/v1/app1/feed/${shared.data.post.id}`, { sessionToken, deviceToken });
    assert.equal(detail.response.status, 200, JSON.stringify(detail.data));
    assert.equal(detail.data.post.comment, "Teste do feed\nno celular");
    assert.equal(detail.data.post.item.content, 'loadstring("print(1)")()');

    const tooLong = await request(baseUrl, `/v1/app1/library/${itemId}/share`, {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { comment: "x".repeat(501) }
    });
    assert.equal(tooLong.response.status, 400);
    assert.equal(tooLong.data.code, "COMMENT_TOO_LONG");

    const hiddenControl = await request(baseUrl, `/v1/app1/library/${itemId}/share`, {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { comment: "Lua\u0000Feed" }
    });
    assert.equal(hiddenControl.response.status, 400);
    assert.equal(hiddenControl.data.code, "COMMENT_INVALID_CHARS");

    const count = Number((await db.query(
      `SELECT COUNT(*)::int AS count FROM app1_feed_posts WHERE account_id = $1`,
      [accountId]
    )).rows[0].count);
    assert.equal(count, 1);
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
