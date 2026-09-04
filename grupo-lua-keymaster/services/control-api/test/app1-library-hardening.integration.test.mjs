import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import net from "node:net";
import { spawn } from "node:child_process";
import pg from "pg";
import { tokenHash } from "../src/security.js";

const enabled = Boolean(process.env.DATABASE_URL);
const LOADSTRING_MAX_CHARS = 32_768;

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

test("App1 library hardening enforces loadstring limits and atomic share favorite", { skip: !enabled, timeout: 35_000 }, async () => {
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
  const sessionToken = `ci-hardening-session-${crypto.randomBytes(24).toString("base64url")}`;
  const deviceToken = `ci-hardening-device-${crypto.randomBytes(24).toString("base64url")}`;
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
        `ci_hardening_login_${suffix}`,
        `CI Hardening ${suffix}`,
        `usr_${suffix}`,
        `Hardening${suffix}`,
        `hardening${suffix}`
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
      `INSERT INTO app1_library_items (id, account_id, kind, title, text_content, favorite)
       VALUES ($1, $2, 'LOADSTRING', 'Loader seguro', 'loadstring("print(1)")()', FALSE)`,
      [itemId, accountId]
    );

    const originalUpdatedAt = (await db.query(
      `SELECT updated_at FROM app1_library_items WHERE id = $1`,
      [itemId]
    )).rows[0].updated_at.toISOString();

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const unauthenticatedTooLong = await request(baseUrl, "/v1/app1/library", {
      method: "POST",
      body: { kind: "LOADSTRING", title: "Sem auth", content: "x".repeat(LOADSTRING_MAX_CHARS + 1) }
    });
    assert.equal(unauthenticatedTooLong.response.status, 401);
    assert.equal(unauthenticatedTooLong.data.code, "UNAUTHORIZED");

    const tooLongCreate = await request(baseUrl, "/v1/app1/library", {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { kind: "LOADSTRING", title: "Grande", content: "x".repeat(LOADSTRING_MAX_CHARS + 1) }
    });
    assert.equal(tooLongCreate.response.status, 400, JSON.stringify(tooLongCreate.data));
    assert.equal(tooLongCreate.data.code, "LOADSTRING_TOO_LONG");
    assert.equal(tooLongCreate.data.maxChars, LOADSTRING_MAX_CHARS);

    const tooLongUpdate = await request(baseUrl, `/v1/app1/library/${itemId}`, {
      method: "PATCH",
      sessionToken,
      deviceToken,
      body: { content: "y".repeat(LOADSTRING_MAX_CHARS + 1) }
    });
    assert.equal(tooLongUpdate.response.status, 400, JSON.stringify(tooLongUpdate.data));
    assert.equal(tooLongUpdate.data.code, "LOADSTRING_TOO_LONG");

    const favorite = await request(baseUrl, "/v1/app1/library/bulk/favorite", {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { ids: [itemId], favorite: true }
    });
    assert.equal(favorite.response.status, 200, JSON.stringify(favorite.data));
    assert.equal(favorite.data.updatedCount, 1);

    const afterFavorite = (await db.query(
      `SELECT favorite, updated_at FROM app1_library_items WHERE id = $1`,
      [itemId]
    )).rows[0];
    assert.equal(afterFavorite.favorite, true);
    assert.equal(afterFavorite.updated_at.toISOString(), originalUpdatedAt, "favoriting must not rewrite content edit time");

    const shared = await request(baseUrl, `/v1/app1/library/${itemId}/share/options`, {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { comment: "Publicação atômica", favorite: false }
    });
    assert.equal(shared.response.status, 201, JSON.stringify(shared.data));
    assert.equal(shared.data.favorite, false);
    assert.equal(shared.data.post.comment_text, "Publicação atômica");

    const afterShare = (await db.query(
      `SELECT favorite, updated_at FROM app1_library_items WHERE id = $1`,
      [itemId]
    )).rows[0];
    assert.equal(afterShare.favorite, false);
    assert.equal(afterShare.updated_at.toISOString(), originalUpdatedAt, "share favorite choice must not rewrite content edit time");

    const storedPost = (await db.query(
      `SELECT comment_text, library_item_id FROM app1_feed_posts WHERE id = $1`,
      [shared.data.post.id]
    )).rows[0];
    assert.equal(storedPost.comment_text, "Publicação atômica");
    assert.equal(storedPost.library_item_id, itemId);

    const invalidFavorite = await request(baseUrl, `/v1/app1/library/${itemId}/share/options`, {
      method: "POST",
      sessionToken,
      deviceToken,
      body: { comment: "", favorite: "yes" }
    });
    assert.equal(invalidFavorite.response.status, 400);
    assert.equal(invalidFavorite.data.code, "INVALID_FAVORITE");
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
