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

async function postJson(baseUrl, path, body) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function getManifest(baseUrl, publicId, token, deviceId) {
  const response = await fetch(`${baseUrl}/v1/menu-access/${encodeURIComponent(publicId)}/manifest`, {
    headers: {
      authorization: `Bearer ${token}`,
      "x-menu-device-id": deviceId
    }
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

test("FREE vincula ao primeiro aparelho, bloqueia compartilhamento e exige nova liberação após expirar", { skip: !enabled, timeout: 30_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(7).toString("hex");
  const menuId = uuid();
  const keyId = uuid();
  const publicId = `menu_ci_${suffix}`;
  const plainKey = `FREE-CI-${crypto.randomBytes(24).toString("base64url")}`;
  const deviceA = `ci-phone-a-${suffix}`;
  const deviceB = `ci-phone-b-${suffix}`;
  let child = null;

  try {
    await db.query(
      `INSERT INTO managed_menus
        (id, public_id, name, source_url, status)
       VALUES ($1, $2, $3, $4, 'ACTIVE')`,
      [menuId, publicId, `CI Menu ${suffix}`, "https://raw.githubusercontent.com/example/example/main/menu.lua"]
    );

    await db.query(
      `INSERT INTO menu_access_keys
        (id, menu_id, kind, status, key_hash, key_hint,
         access_state, duration_value, duration_unit)
       VALUES ($1, $2, 'FREE', 'ACTIVE', $3, $4,
               'READY', 1, 'HOURS')`,
      [keyId, menuId, tokenHash(`menu-key:${plainKey}`), `FREE-CI-${suffix}`]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const first = await postJson(baseUrl, "/v1/menu-access/validate", {
      menuId: publicId,
      key: plainKey,
      clientLabel: "CI A",
      deviceId: deviceA,
      deviceHint: "Phone A"
    });
    assert.equal(first.response.status, 200, JSON.stringify(first.data));
    assert.equal(first.data.ok, true);
    assert.equal(first.data.keyType, "FREE");
    assert.equal(typeof first.data.token, "string");

    const activeRow = (await db.query(
      `SELECT access_state, access_started_at, access_until, bound_device_hash, bound_device_hint
         FROM menu_access_keys WHERE id = $1`,
      [keyId]
    )).rows[0];
    assert.equal(activeRow.access_state, "ACTIVE");
    assert.ok(activeRow.access_started_at);
    assert.ok(activeRow.access_until);
    assert.ok(activeRow.bound_device_hash);
    assert.equal(activeRow.bound_device_hint, "Phone A");

    const manifestA = await getManifest(baseUrl, publicId, first.data.token, deviceA);
    assert.equal(manifestA.response.status, 200, JSON.stringify(manifestA.data));
    assert.equal(manifestA.data.ok, true);

    const manifestB = await getManifest(baseUrl, publicId, first.data.token, deviceB);
    assert.equal(manifestB.response.status, 403, JSON.stringify(manifestB.data));
    assert.equal(manifestB.data.code, "DEVICE_NOT_AUTHORIZED");

    const shared = await postJson(baseUrl, "/v1/menu-access/validate", {
      menuId: publicId,
      key: plainKey,
      clientLabel: "CI B",
      deviceId: deviceB,
      deviceHint: "Phone B"
    });
    assert.equal(shared.response.status, 403, JSON.stringify(shared.data));
    assert.equal(shared.data.code, "DEVICE_NOT_AUTHORIZED");

    await db.query(
      `UPDATE menu_access_keys
          SET access_until = NOW() - INTERVAL '1 minute'
        WHERE id = $1`,
      [keyId]
    );

    const expired = await postJson(baseUrl, "/v1/menu-access/validate", {
      menuId: publicId,
      key: plainKey,
      clientLabel: "CI A",
      deviceId: deviceA,
      deviceHint: "Phone A"
    });
    assert.equal(expired.response.status, 403, JSON.stringify(expired.data));
    assert.equal(expired.data.code, "FREE_REQUIRES_ADMIN");

    const waitingRow = (await db.query(
      `SELECT access_state FROM menu_access_keys WHERE id = $1`,
      [keyId]
    )).rows[0];
    assert.equal(waitingRow.access_state, "WAITING_ADMIN");

    // Simula a ação administrativa do App 1 sem alterar o aparelho já vinculado.
    await db.query(
      `UPDATE menu_access_keys
          SET access_state = 'READY',
              duration_value = 1,
              duration_unit = 'HOURS',
              access_started_at = NULL,
              access_until = NULL,
              expires_at = NULL,
              updated_at = NOW()
        WHERE id = $1`,
      [keyId]
    );

    const released = await postJson(baseUrl, "/v1/menu-access/validate", {
      menuId: publicId,
      key: plainKey,
      clientLabel: "CI A",
      deviceId: deviceA,
      deviceHint: "Phone A"
    });
    assert.equal(released.response.status, 200, JSON.stringify(released.data));
    assert.equal(released.data.ok, true);

    const secondCycle = (await db.query(
      `SELECT access_state, access_started_at, access_until, bound_device_hint
         FROM menu_access_keys WHERE id = $1`,
      [keyId]
    )).rows[0];
    assert.equal(secondCycle.access_state, "ACTIVE");
    assert.ok(secondCycle.access_started_at);
    assert.ok(secondCycle.access_until);
    assert.equal(secondCycle.bound_device_hint, "Phone A");
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM menu_access_sessions WHERE menu_id = $1`, [menuId]).catch(() => {});
    await db.query(`DELETE FROM menu_access_keys WHERE id = $1`, [keyId]).catch(() => {});
    await db.query(`DELETE FROM managed_menus WHERE id = $1`, [menuId]).catch(() => {});
    await db.end();
  }
});
