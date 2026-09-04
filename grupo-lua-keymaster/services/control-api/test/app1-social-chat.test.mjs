import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const social = fs.readFileSync(new URL("../src/app1-social-routes.js", import.meta.url), "utf8");
const chat = fs.readFileSync(new URL("../src/app1-chat-routes.js", import.meta.url), "utf8");
const auth = fs.readFileSync(new URL("../src/app1-feature-auth.js", import.meta.url), "utf8");
const registry = fs.readFileSync(new URL("../src/app1-library-routes.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../migrations/013_app1_social_chat_profile.sql", import.meta.url), "utf8");

test("Social V2 exige sessão FULL vinculada ao dispositivo", () => {
  assert.match(auth, /s\.session_kind/);
  assert.match(auth, /row\.session_kind !== "FULL"/);
  assert.match(auth, /x-app1-device-token/);
  assert.match(auth, /safeEqualText\(supplied, row\.device_token_hash\)/);
  assert.match(social, /requireApp1FullSession/);
});

test("Social implementa likes, comentários, favoritos, pin DEV e notificações separadas", () => {
  assert.match(social, /\/v1\/app1\/social\/posts\/:postId\/like/);
  assert.match(social, /\/v1\/app1\/social\/posts\/:postId\/comments/);
  assert.match(social, /\/v1\/app1\/social\/posts\/:postId\/favorite/);
  assert.match(social, /\/v1\/app1\/social\/posts\/:postId\/pin/);
  assert.match(social, /req\.app1FeatureSession\.role !== "DEV"/);
  assert.match(social, /\/v1\/app1\/social\/notifications/);
  assert.match(social, /\/v1\/app1\/social\/announcements/);
});

test("Favorito ou pin preserva post depois da janela normal", () => {
  assert.match(social, /p\.pinned_at IS NULL/);
  assert.match(social, /app1_social_favorites/);
  assert.match(migration, /app1_feed_posts_single_pin_idx/);
  assert.match(migration, /app1_social_favorites/);
});

test("Chats não expõem endpoint administrativo comum para leitura de mensagens", () => {
  assert.match(chat, /\/v1\/app1\/chats/);
  assert.match(chat, /\/v1\/app1\/chats\/:conversationId\/messages/);
  assert.match(chat, /\/v1\/app1\/chats\/:conversationId\/report/);
  assert.doesNotMatch(chat, /v1\/keymaster\/.*chat.*messages/i);
  assert.doesNotMatch(chat, /requireKeymaster/);
});

test("Chats possuem retenção, favoritos e notificações próprias", () => {
  assert.match(chat, /DELETE FROM app1_messages/);
  assert.match(chat, /app1_conversation_preferences/);
  assert.match(chat, /favorite = TRUE/);
  assert.match(chat, /app1_chat_notifications/);
  assert.match(migration, /expires_at TIMESTAMPTZ NOT NULL DEFAULT \(NOW\(\) \+ INTERVAL '24 hours'\)/);
});

test("Registro principal ativa Social e Chats antes das rotas legadas", () => {
  assert.match(registry, /registerApp1SocialRoutes\(app\)/);
  assert.match(registry, /registerApp1ChatRoutes\(app\)/);
  assert.ok(registry.indexOf("registerApp1SocialRoutes(app)") < registry.indexOf("registerApp1LibraryRoutesV2(app)"));
  assert.ok(registry.indexOf("registerApp1ChatRoutes(app)") < registry.indexOf("registerApp1LibraryRoutesV2(app)"));
});
