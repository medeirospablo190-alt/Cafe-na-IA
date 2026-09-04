import test from "node:test";
import assert from "node:assert/strict";
import { durationUntil } from "../src/menu-access-v2-routes.js";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

test("FREE nunca passa de 24 horas", () => {
  const now = new Date("2026-09-04T12:00:00.000Z");
  const until = durationUntil({ kind: "FREE", duration_unit: "HOURS", duration_value: 72 }, now);
  assert.equal(until.getTime() - now.getTime(), 24 * HOUR);
});

test("FREE respeita períodos menores que 24 horas", () => {
  const now = new Date("2026-09-04T12:00:00.000Z");
  const until = durationUntil({ kind: "FREE", duration_unit: "HOURS", duration_value: 6 }, now);
  assert.equal(until.getTime() - now.getTime(), 6 * HOUR);
});

test("VIP em dias usa a quantidade configurada", () => {
  const now = new Date("2026-09-04T12:00:00.000Z");
  const until = durationUntil({ kind: "VIP", duration_unit: "DAYS", duration_value: 30 }, now);
  assert.equal(until.getTime() - now.getTime(), 30 * DAY);
});

test("VIP em meses preserva fim do mês sem pular para março", () => {
  const now = new Date("2027-01-31T10:15:00.000Z");
  const until = durationUntil({ kind: "VIP", duration_unit: "MONTHS", duration_value: 1 }, now);
  assert.equal(until.toISOString(), "2027-02-28T10:15:00.000Z");
});

test("VIP em meses trata ano bissexto", () => {
  const now = new Date("2028-01-31T10:15:00.000Z");
  const until = durationUntil({ kind: "VIP", duration_unit: "MONTHS", duration_value: 1 }, now);
  assert.equal(until.toISOString(), "2028-02-29T10:15:00.000Z");
});

test("VIP permanente não recebe data final", () => {
  const now = new Date("2026-09-04T12:00:00.000Z");
  const until = durationUntil({ kind: "VIP", duration_unit: "PERMANENT", duration_value: null }, now);
  assert.equal(until, null);
});
