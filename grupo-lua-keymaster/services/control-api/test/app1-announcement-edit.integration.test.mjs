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

async function api(baseUrl, path, { method = "GET", body, token, deviceToken } = {}) {
  const headers = { accept: "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  if (deviceToken) headers["x-app1-device-token"] = deviceToken;
  if (body !== undefined) headers["content-type"] = "application/json";
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

async function insertAccount(db, {
  id,
  suffix,
  role,
  publicName,
  profileId,
  deviceId,
  sessionId,
  token,
  deviceToken
}) {
  await db.query(
    `INSERT INTO app1_accounts
      (id, login, display_name, role, status, credential_hash,
       terms_version, privacy_version, terms_accepted_at,
       public_profile_id, public_name, public_name_normalized,
       public_name_verified_at, onboarding_completed_at)
     VALUES ($1, $2, $3, $4, 'ACTIVE', 'ci-credential',
             '1.0', '1.0', NOW(), $5, $6, $7, NOW(), NOW())`,
    [id, `ci_announcement_${suffix}`, `CI ${publicName}`, role, profileId, publicName, publicName.toLowerCase()]
  );
  await db.query(
    `INSERT INTO app1_devices
      (id, account_id, fingerprint, device_token_hash, platform, device_label, is_primary, status)
     VALUES ($1, $2, $3, $4, 'ci', $5, TRUE, 'ACTIVE')`,
    [deviceId, id, `ci-fingerprint-${suffix}`, tokenHash(`app1-device:${deviceToken}`), `${publicName} Phone`]
  );
  await db.query(
    `INSERT INTO app1_sessions
      (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
     VALUES ($1, $2, $3, $4, NOW() + INTERVAL '30 minutes', $5, 'FULL')`,
    [sessionId, id, tokenHash(`app1:${token}`), `${publicName} Phone`, deviceId]
  );
}

test("DEV edita aviso, mantém prazo e a Home lista mais de três avisos ativos", { skip: !enabled, timeout: 45_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(6).toString("hex");
  const adm = {
    id: uuid(), suffix: `adm_${suffix}`, role: "ADM", publicName: `Adm${suffix}`,
    profileId: `usr_adm_${suffix}`, deviceId: uuid(), sessionId: uuid(),
    token: `ci-adm-${crypto.randomBytes(24).toString("base64url")}`,
    deviceToken: `ci-device-adm-${crypto.randomBytes(24).toString("base64url")}`
  };
  const dev = {
    id: uuid(), suffix: `dev_${suffix}`, role: "DEV", publicName: `Dev${suffix}`,
    profileId: `usr_dev_${suffix}`, deviceId: uuid(), sessionId: uuid(),
    token: `ci-dev-${crypto.randomBytes(24).toString("base64url")}`,
    deviceToken: `ci-device-dev-${crypto.randomBytes(24).toString("base64url")}`
  };

  let child = null;
  let announcementId = null;
  const extraAnnouncementIds = [];

  try {
    await insertAccount(db, adm);
    await insertAccount(db, dev);

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/bootstrap.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const created = await api(baseUrl, "/v1/app1/social/announcements", {
      method: "POST",
      token: dev.token,
      deviceToken: dev.deviceToken,
      body: { text: "Aviso original CI" }
    });
    assert.equal(created.response.status, 201, JSON.stringify(created.data));
    announcementId = created.data.announcement.id;
    assert.ok(announcementId);
    const originalExpiresAt = created.data.announcement.expiresAt;

    const admEdit = await api(baseUrl, `/v1/app1/social/announcements/${announcementId}`, {
      method: "PATCH",
      token: adm.token,
      deviceToken: adm.deviceToken,
      body: { text: "ADM não deve editar" }
    });
    assert.equal(admEdit.response.status, 403, JSON.stringify(admEdit.data));
    assert.equal(admEdit.data.code, "DEV_REQUIRED");

    const devEdit = await api(baseUrl, `/v1/app1/social/announcements/${announcementId}`, {
      method: "PATCH",
      token: dev.token,
      deviceToken: dev.deviceToken,
      body: { text: "Aviso editado CI" }
    });
    assert.equal(devEdit.response.status, 200, JSON.stringify(devEdit.data));
    assert.equal(devEdit.data.announcement.text, "Aviso editado CI");
    assert.equal(
      new Date(devEdit.data.announcement.expiresAt).getTime(),
      new Date(originalExpiresAt).getTime(),
      "editar não pode renovar o prazo de expiração"
    );

    for (let index = 0; index < 4; index += 1) {
      const id = `ci-home-announcement-${suffix}-${index}`;
      extraAnnouncementIds.push(id);
      await db.query(
        `INSERT INTO app1_global_announcements (id, actor_account_id, text_content)
         VALUES ($1, $2, $3)`,
        [id, dev.id, `Aviso extra ${index + 1}`]
      );
    }

    const homeList = await api(baseUrl, "/v1/app1/social/announcements", {
      token: adm.token,
      deviceToken: adm.deviceToken
    });
    assert.equal(homeList.response.status, 200, JSON.stringify(homeList.data));
    const expectedIds = new Set([announcementId, ...extraAnnouncementIds]);
    const returnedIds = new Set(homeList.data.announcements.map((item) => item.id));
    for (const id of expectedIds) assert.equal(returnedIds.has(id), true, `Home não retornou ${id}`);
    const editedOnHome = homeList.data.announcements.find((item) => item.id === announcementId);
    assert.equal(editedOnHome?.text, "Aviso editado CI");
    assert.equal(editedOnHome?.author?.role, "DEV");

    const feed = await api(baseUrl, "/v1/app1/social/feed", {
      token: adm.token,
      deviceToken: adm.deviceToken
    });
    assert.equal(feed.response.status, 200, JSON.stringify(feed.data));
    assert.ok(feed.data.announcements.length <= 3, "o feed Social deve manter sua lista curta de destaques");

    const auditRow = (await db.query(
      `SELECT action, actor_id, target_id
         FROM audit_events
        WHERE action = 'APP1_GLOBAL_ANNOUNCEMENT_UPDATED'
          AND target_id = $1
        ORDER BY created_at DESC
        LIMIT 1`,
      [announcementId]
    )).rows[0];
    assert.ok(auditRow);
    assert.equal(String(auditRow.actor_id), String(dev.id));
    assert.equal(auditRow.target_id, announcementId);
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    if (announcementId) {
      await db.query(`DELETE FROM app1_social_notifications WHERE announcement_id = $1`, [announcementId]).catch(() => {});
      await db.query(`DELETE FROM audit_events WHERE target_id = $1`, [announcementId]).catch(() => {});
    }
    if (announcementId || extraAnnouncementIds.length) {
      await db.query(
        `DELETE FROM app1_global_announcements WHERE id = ANY($1::text[])`,
        [[...(announcementId ? [announcementId] : []), ...extraAnnouncementIds]]
      ).catch(() => {});
    }
    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR actor_id = $2`, [adm.id, dev.id]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1 OR id = $2`, [adm.id, dev.id]).catch(() => {});
    await db.end();
  }
});
