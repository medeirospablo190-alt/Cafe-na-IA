import test from "node:test";
import assert from "node:assert/strict";
import express from "express";
import {
  makeMenuKey,
  makeMenuPublicId,
  menuKeyHint,
  registerMenuRoutes,
  validateMenuSourceUrl
} from "../src/menu-routes.js";

test("menu source URLs accept only HTTPS GitHub Lua files", () => {
  assert.match(
    validateMenuSourceUrl("https://github.com/user/repo/blob/main/Menu.lua"),
    /^https:\/\/raw\.githubusercontent\.com\//
  );
  assert.match(
    validateMenuSourceUrl("https://raw.githubusercontent.com/user/repo/main/Menu.lua"),
    /^https:\/\/raw\.githubusercontent\.com\//
  );
  assert.equal(validateMenuSourceUrl("http://github.com/user/repo/Menu.lua"), null);
  assert.equal(validateMenuSourceUrl("https://example.com/Menu.lua"), null);
  assert.equal(validateMenuSourceUrl("https://github.com/user/repo/readme.md"), null);
});

test("generated menu IDs and keys are high-entropy formatted values", () => {
  const idA = makeMenuPublicId();
  const idB = makeMenuPublicId();
  assert.match(idA, /^menu_[A-Za-z0-9_-]+$/);
  assert.notEqual(idA, idB);

  const free = makeMenuKey("FREE");
  const vip = makeMenuKey("VIP");
  assert.match(free, /^FREE-[A-Za-z0-9_-]+$/);
  assert.match(vip, /^VIP-[A-Za-z0-9_-]+$/);
  assert.ok(vip.length > free.length);
  assert.notEqual(free, makeMenuKey("FREE"));
});

test("key hints do not reveal full generated credentials", () => {
  const key = makeMenuKey("VIP");
  const hint = menuKeyHint(key);
  assert.ok(hint.length < key.length);
  assert.ok(hint.includes("…"));
  assert.notEqual(hint, key);
});

test("menu routes register on Express without ambiguous path syntax", () => {
  const app = express();
  assert.doesNotThrow(() => registerMenuRoutes(app));
});

test("menu routes accept the one-use critical authorization dependency", () => {
  const app = express();
  const consumeCriticalAuthorization = async () => null;
  assert.doesNotThrow(() => registerMenuRoutes(app, { consumeCriticalAuthorization }));
});
