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
    [id, `ci_social_${suffix}`, `CI ${publicName}`, role, profileId, publicName, publicName.toLowerCase()]
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

test("Social, perfil e chat privado funcionam com sessão FULL vinculada", { skip: !enabled, timeout: 45_000 }, async () => {
  const db = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await db.connect();

  const suffix = crypto.randomBytes(6).toString("hex");
  const a = {
    id: uuid(), suffix: `a_${suffix}`, role: "ADM", publicName: `LuaA${suffix}`,
    profileId: `usr_a_${suffix}`, deviceId: uuid(), sessionId: uuid(),
    token: `ci-a-${crypto.randomBytes(24).toString("base64url")}`,
    deviceToken: `ci-device-a-${crypto.randomBytes(24).toString("base64url")}`
  };
  const b = {
    id: uuid(), suffix: `b_${suffix}`, role: "DEV", publicName: `LuaB${suffix}`,
    profileId: `usr_b_${suffix}`, deviceId: uuid(), sessionId: uuid(),
    token: `ci-b-${crypto.randomBytes(24).toString("base64url")}`,
    deviceToken: `ci-device-b-${crypto.randomBytes(24).toString("base64url")}`
  };
  const itemId = `ci-item-${suffix}`;
  const postId = `ci-post-${suffix}`;
  let child = null;

  try {
    await insertAccount(db, a);
    await insertAccount(db, b);
    await db.query(
      `INSERT INTO app1_library_items (id, account_id, kind, title, text_content)
       VALUES ($1, $2, 'CODE', $3, $4)`,
      [itemId, a.id, `Código CI ${suffix}`, "print('social-ci')"]
    );
    await db.query(
      `INSERT INTO app1_feed_posts
        (id, account_id, post_kind, library_item_id, snapshot_title, snapshot_text_content, comment_text)
       VALUES ($1, $2, 'CODE', $3, $4, $5, $6)`,
      [postId, a.id, itemId, `Código CI ${suffix}`, "print('social-ci')", "Teste Social"]
    );

    const port = await freePort();
    const baseUrl = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath, ["src/server.js"], {
      cwd: process.cwd(),
      env: { ...process.env, PORT: String(port), PUBLIC_BASE_URL: baseUrl },
      stdio: ["ignore", "pipe", "pipe"]
    });
    await waitForHealth(baseUrl, child);

    const profile = await api(baseUrl, "/v1/app1/profile", { token: a.token, deviceToken: a.deviceToken });
    assert.equal(profile.response.status, 200, JSON.stringify(profile.data));
    assert.equal(profile.data.profile.publicName, a.publicName);

    const profileUpdate = await api(baseUrl, "/v1/app1/profile", {
      method: "PATCH",
      token: a.token,
      deviceToken: a.deviceToken,
      body: { bio: "Bio CI", statusText: "Online CI", avatarStyle: "CAT", frameStyle: "PURPLE", presenceMode: "VISIBLE" }
    });
    assert.equal(profileUpdate.response.status, 200, JSON.stringify(profileUpdate.data));
    assert.equal(profileUpdate.data.profile.avatarStyle, "CAT");
    assert.equal(profileUpdate.data.profile.frameStyle, "PURPLE");

    const search = await api(baseUrl, `/v1/app1/social/profiles?q=${encodeURIComponent(b.publicName.slice(0, 5))}`, {
      token: a.token,
      deviceToken: a.deviceToken
    });
    assert.equal(search.response.status, 200, JSON.stringify(search.data));
    assert.ok(search.data.profiles.some((entry) => entry.profileId === b.profileId));
    assert.equal(Object.hasOwn(search.data.profiles[0] || {}, "login"), false);

    const feed = await api(baseUrl, "/v1/app1/social/feed", { token: b.token, deviceToken: b.deviceToken });
    assert.equal(feed.response.status, 200, JSON.stringify(feed.data));
    assert.ok(feed.data.posts.some((entry) => entry.id === postId));

    const like = await api(baseUrl, `/v1/app1/social/posts/${postId}/like`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { liked: true }
    });
    assert.equal(like.response.status, 200, JSON.stringify(like.data));
    assert.equal(like.data.likeCount, 1);

    const favorite = await api(baseUrl, `/v1/app1/social/posts/${postId}/favorite`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { favorite: true }
    });
    assert.equal(favorite.response.status, 200, JSON.stringify(favorite.data));
    assert.equal(favorite.data.favoriteCount, 1);

    const comment = await api(baseUrl, `/v1/app1/social/posts/${postId}/comments`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { text: "Comentário CI" }
    });
    assert.equal(comment.response.status, 201, JSON.stringify(comment.data));
    assert.equal(comment.data.comment.text, "Comentário CI");

    const notifications = await api(baseUrl, "/v1/app1/social/notifications", {
      token: a.token, deviceToken: a.deviceToken
    });
    assert.equal(notifications.response.status, 200, JSON.stringify(notifications.data));
    assert.ok(notifications.data.unread.ALL >= 3);

    const pinDenied = await api(baseUrl, `/v1/app1/social/posts/${postId}/pin`, {
      method: "POST", token: a.token, deviceToken: a.deviceToken, body: { pinned: true }
    });
    assert.equal(pinDenied.response.status, 403, JSON.stringify(pinDenied.data));
    assert.equal(pinDenied.data.code, "DEV_REQUIRED");

    const pin = await api(baseUrl, `/v1/app1/social/posts/${postId}/pin`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { pinned: true }
    });
    assert.equal(pin.response.status, 200, JSON.stringify(pin.data));
    assert.equal(pin.data.pinned, true);

    const start = await api(baseUrl, "/v1/app1/chats", {
      method: "POST", token: a.token, deviceToken: a.deviceToken, body: { profileId: b.profileId }
    });
    assert.ok([200, 201].includes(start.response.status), JSON.stringify(start.data));
    const conversationId = start.data.conversation.id;
    assert.ok(conversationId);

    const send = await api(baseUrl, `/v1/app1/chats/${conversationId}/messages`, {
      method: "POST", token: a.token, deviceToken: a.deviceToken, body: { text: "Mensagem CI" }
    });
    assert.equal(send.response.status, 201, JSON.stringify(send.data));
    assert.equal(send.data.message.text, "Mensagem CI");

    const chatsB = await api(baseUrl, "/v1/app1/chats", { token: b.token, deviceToken: b.deviceToken });
    assert.equal(chatsB.response.status, 200, JSON.stringify(chatsB.data));
    const conversationB = chatsB.data.conversations.find((entry) => entry.id === conversationId);
    assert.ok(conversationB);
    assert.equal(conversationB.unreadCount, 1);

    const messagesB = await api(baseUrl, `/v1/app1/chats/${conversationId}/messages`, {
      token: b.token, deviceToken: b.deviceToken
    });
    assert.equal(messagesB.response.status, 200, JSON.stringify(messagesB.data));
    assert.equal(messagesB.data.messages.at(-1).text, "Mensagem CI");
    assert.equal(messagesB.data.messages.at(-1).mine, false);

    const favoriteChat = await api(baseUrl, `/v1/app1/chats/${conversationId}/favorite`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { favorite: true }
    });
    assert.equal(favoriteChat.response.status, 200, JSON.stringify(favoriteChat.data));
    assert.equal(favoriteChat.data.favorite, true);

    const report = await api(baseUrl, `/v1/app1/chats/${conversationId}/report`, {
      method: "POST", token: b.token, deviceToken: b.deviceToken, body: { reason: "Teste de denúncia CI" }
    });
    assert.equal(report.response.status, 201, JSON.stringify(report.data));

    const chatNotifications = await api(baseUrl, "/v1/app1/chat-notifications", {
      token: b.token, deviceToken: b.deviceToken
    });
    assert.equal(chatNotifications.response.status, 200, JSON.stringify(chatNotifications.data));
    assert.ok(chatNotifications.data.unreadCount >= 1);

    const wrongDevice = await api(baseUrl, "/v1/app1/chats", {
      token: a.token,
      deviceToken: "wrong-device-token"
    });
    assert.equal(wrongDevice.response.status, 401, JSON.stringify(wrongDevice.data));
  } finally {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 1500);
        child.once("exit", () => { clearTimeout(timer); resolve(); });
      });
      if (child.exitCode === null) child.kill("SIGKILL");
    }

    await db.query(`DELETE FROM audit_events WHERE actor_id = $1 OR actor_id = $2`, [a.id, b.id]).catch(() => {});
    await db.query(`DELETE FROM app1_accounts WHERE id = $1 OR id = $2`, [a.id, b.id]).catch(() => {});
    await db.end();
  }
});
