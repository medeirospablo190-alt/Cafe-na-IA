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

async function request(baseUrl, path, token, { method = "GET", body, headers = {} } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      accept: "application/json",
      authorization: `Bearer ${token}`,
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
      ...headers
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

test("Keymaster mantém legado, mas não cria nem altera menu privado do App 1", { skip: !enabled, timeout: 35_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true" ? { rejectUnauthorized: false } : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(6).toString("hex");
  const keymasterToken = `ci-km-${crypto.randomBytes(32).toString("base64url")}`;
  const keymasterSessionId = uuid();
  const ownerId = uuid();
  const ownedMenuId = uuid();
  const legacyMenuId = uuid();
  let keymasterDeviceId = null;
  let child = null;

  try {
    keymasterDeviceId = (await db.query(
      `INSERT INTO keymaster_devices (fingerprint, platform)
       VALUES ($1, 'ci')
       RETURNING id`,
      [`ci-km-fp-${suffix}`]
    )).rows[0].id;

    await db.query(
      `INSERT INTO keymaster_sessions (id, device_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
      [keymasterSessionId, keymasterDeviceId, tokenHash(keymasterToken)]
    );

    await db.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash,
         terms_version, privacy_version, terms_accepted_at,
         public_profile_id, public_name, public_name_normalized,
         public_name_verified_at, onboarding_completed_at)
       VALUES ($1, $2, $3, 'ADM', 'ACTIVE', 'ci-credential',
               '1.0', '1.0', NOW(), $4, $5, $6, NOW(), NOW())`,
      [
        ownerId,
        `ci_km_owner_${suffix}`,
        `CI KM Owner ${suffix}`,
        `usr_km_${suffix}`,
        `KmOwner${suffix}`,
        `kmowner${suffix}`
      ]
    );

    await db.query(
      `INSERT INTO managed_menus
        (id, public_id, name, source_url, status, owner_account_id)
       VALUES
        ($1, $2, $3, $4, 'ACTIVE', $5),
        ($6, $7, $8, $9, 'ACTIVE', NULL)`,
      [
        ownedMenuId,
        `owned_${suffix}`,
        `Owned ${suffix}`,
        "https://raw.githubusercontent.com/example/example/main/owned.lua",
        ownerId,
        legacyMenuId,
        `legacy_${suffix}`,
        `Legacy ${suffix}`,
        "https://raw.githubusercontent.com/example/example/main/legacy.lua"
      ]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const list = await request(baseUrl, "/v1/keymaster/menus", keymasterToken);
    assert.equal(list.response.status, 200, JSON.stringify(list.data));
    assert.ok(list.data.menus.some((menu) => menu.id === ownedMenuId));
    assert.ok(list.data.menus.some((menu) => menu.id === legacyMenuId));

    const create = await request(baseUrl, "/v1/keymaster/menus", keymasterToken, {
      method: "POST",
      body: {
        name: "Should fail",
        sourceUrl: "https://raw.githubusercontent.com/example/example/main/new.lua"
      }
    });
    assert.equal(create.response.status, 403, JSON.stringify(create.data));
    assert.equal(create.data.code, "APP1_MENU_CREATION_REQUIRED");

    const patchOwned = await request(baseUrl, `/v1/keymaster/menus/${ownedMenuId}`, keymasterToken, {
      method: "PATCH",
      body: { name: "Should not change" }
    });
    assert.equal(patchOwned.response.status, 403, JSON.stringify(patchOwned.data));
    assert.equal(patchOwned.data.code, "APP1_MENU_MANAGED");

    const stateOwned = await request(baseUrl, `/v1/keymaster/menus/${ownedMenuId}/state/suspend`, keymasterToken, {
      method: "POST",
      body: {}
    });
    assert.equal(stateOwned.response.status, 403, JSON.stringify(stateOwned.data));
    assert.equal(stateOwned.data.code, "APP1_MENU_MANAGED");

    const deleteOwned = await request(baseUrl, `/v1/keymaster/menus/${ownedMenuId}`, keymasterToken, {
      method: "DELETE"
    });
    assert.equal(deleteOwned.response.status, 403, JSON.stringify(deleteOwned.data));
    assert.equal(deleteOwned.data.code, "APP1_MENU_MANAGED");

    const patchLegacy = await request(baseUrl, `/v1/keymaster/menus/${legacyMenuId}`, keymasterToken, {
      method: "PATCH",
      body: { name: `Legacy Updated ${suffix}` }
    });
    assert.equal(patchLegacy.response.status, 200, JSON.stringify(patchLegacy.data));
    assert.equal(patchLegacy.data.menu.name, `Legacy Updated ${suffix}`);

    const ownerRow = (await db.query(`SELECT name, status FROM managed_menus WHERE id = $1`, [ownedMenuId])).rows[0];
    assert.equal(ownerRow.name, `Owned ${suffix}`);
    assert.equal(ownerRow.status, "ACTIVE");
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }
    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR actor_id = $2 OR target_id = $3 OR target_id = $4`, [String(keymasterSessionId), String(ownerId), String(ownedMenuId), String(legacyMenuId)]).catch(() => {});
    await db.query(`DELETE FROM managed_menus WHERE id IN ($1, $2)`, [ownedMenuId, legacyMenuId]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1`, [ownerId]).catch(() => {});
    await db.query(`DELETE FROM keymaster_sessions WHERE id = $1`, [keymasterSessionId]).catch(() => {});
    if (keymasterDeviceId != null) await db.query(`DELETE FROM keymaster_devices WHERE id = $1`, [keymasterDeviceId]).catch(() => {});
    await db.end();
  }
});
