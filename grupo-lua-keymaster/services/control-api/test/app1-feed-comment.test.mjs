import test from "node:test";
import assert from "node:assert/strict";
import {
  APP1_FEED_COMMENT_MAX_CHARS,
  normalizeFeedComment,
  validateFeedComment
} from "../src/app1-feed-comment.js";

test("App1 feed comment normalization preserves readable lines", () => {
  assert.equal(normalizeFeedComment("  Olá\r\nLua  "), "Olá\nLua");
});

test("App1 feed comment is optional", () => {
  assert.deepEqual(validateFeedComment("   "), { ok: true, comment: null });
});

test("App1 feed comment accepts the exact unicode character limit", () => {
  const value = "😀".repeat(APP1_FEED_COMMENT_MAX_CHARS);
  const result = validateFeedComment(value);
  assert.equal(result.ok, true);
  assert.equal(result.comment, value);
});

test("App1 feed comment rejects values above the unicode character limit", () => {
  const result = validateFeedComment("x".repeat(APP1_FEED_COMMENT_MAX_CHARS + 1));
  assert.equal(result.ok, false);
  assert.equal(result.code, "COMMENT_TOO_LONG");
});

test("App1 feed comment rejects hidden control characters", () => {
  const result = validateFeedComment("Lua\u0000Feed");
  assert.equal(result.ok, false);
  assert.equal(result.code, "COMMENT_INVALID_CHARS");
});
