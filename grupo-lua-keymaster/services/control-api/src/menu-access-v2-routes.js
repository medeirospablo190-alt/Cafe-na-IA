import crypto from "crypto";
import { pool, withTransaction } from "./db.js";
import { randomId, randomToken, tokenHash } from "./security.js";

const PUBLIC_ATTEMPT_WINDOW_MS = 60 * 1000;
const PUBLIC_ATTEMPT_LIMIT = 12;
const PERMANENT_SESSION_MS = 100 * 365 * 24 * 60 * 60 * 1000;
const attempts = new Map();

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function cleanText(value, max = 120) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, max);
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

function deviceHash(deviceId) {
  return tokenHash(`menu-device:${deviceId}`);
}

function deviceHint(deviceId, suppliedHint = "") {
  const hint = cleanText(suppliedHint, 80);
  if (hint) return hint;
  const value = String(deviceId || "");
  if (value.length <= 10) return value || "aparelho";
  return `…${value.slice(-8)}`;
}

function attemptAllowed(req, publicId) {
  const now = Date.now();
  const id = `${String(req.ip || req.socket?.remoteAddress || "unknown")}:${publicId}`;
  const current = attempts.get(id);
  if (!current || current.resetAt <= now) {
    attempts.set(id, { count: 1, resetAt: now + PUBLIC_ATTEMPT_WINDOW_MS });
    return true;
  }
  current.count += 1;
  return current.count <= PUBLIC_ATTEMPT_LIMIT;
}

function durationUntil(row, now = new Date()) {
  const unit = String(row.duration_unit || (row.kind === "FREE" ? "HOURS" : "PERMANENT")).toUpperCase();
  const rawValue = Number(row.duration_value || (row.kind === "FREE" ? 24 : 1));

  if (unit === "PERMANENT") return null;

  const value = Math.max(1, Math.floor(rawValue));
  const base = new Date(now);
  if (unit === "HOURS") {
    const hours = row.kind === "FREE" ? Math.min(24, value) : value;
    return new Date(base.getTime() + hours * 60 * 60 * 1000);
  }
  if (unit === "DAYS") return new Date(base.getTime() + value * 24 * 60 * 60 * 1000);
  if (unit === "MONTHS") {
    base.setUTCMonth(base.getUTCMonth() + value);
    return base;
  }
  return row.kind === "FREE"
    ? new Date(base.getTime() + 24 * 60 * 60 * 1000)
    : null;
}

function sessionExpiry(accessUntil, now = new Date()) {
  return accessUntil ? new Date(accessUntil) : new Date(now.getTime() + PERMANENT_SESSION_MS);
}

async function markEnded(client, row, now) {
  if (row.access_state !== "ACTIVE" || !row.access_until) return row;
  if (new Date(row.access_until).getTime() > now.getTime()) return row;

  const nextState = row.kind === "FREE" ? "WAITING_ADMIN" : "EXPIRED";
  await client.query(
    `UPDATE menu_access_keys
        SET access_state = $2, updated_at = NOW()
      WHERE id = $1`,
    [row.id, nextState]
  );
  await client.query(
    `UPDATE menu_access_sessions
        SET revoked_at = COALESCE(revoked_at, NOW())
      WHERE menu_key_id = $1 AND revoked_at IS NULL`,
    [row.id]
  );
  return { ...row, access_state: nextState };
}

export function registerMenuAccessV2Routes(app) {
  app.post("/v1/menu-access/validate", async (req, res, next) => {
    try {
      const publicId = cleanText(req.body?.menuId, 80);
      const key = String(req.body?.key || "").trim();
      const clientLabel = cleanText(req.body?.clientLabel, 120) || null;
      const deviceId = String(req.body?.deviceId || "").trim().slice(0, 300);
      const suppliedDeviceHint = cleanText(req.body?.deviceHint, 80);

      if (!publicId || !key || key.length > 300) {
        return sendError(res, 400, "INVALID_REQUEST", "Menu e chave são obrigatórios.");
      }
      if (!deviceId) {
        return sendError(res, 400, "DEVICE_ID_REQUIRED", "Este menu exige identificação do aparelho.");
      }
      if (!attemptAllowed(req, publicId)) {
        return sendError(res, 429, "TOO_MANY_ATTEMPTS", "Muitas tentativas. Aguarde um minuto.");
      }

      const dHash = deviceHash(deviceId);
      const dHint = deviceHint(deviceId, suppliedDeviceHint);
      const keyHash = tokenHash(`menu-key:${key}`);
      const now = new Date();

      const result = await withTransaction(async (client) => {
        const row = (await client.query(
          `SELECT
             k.*,
             m.public_id,
             m.name AS menu_name,
             m.source_url,
             m.status AS menu_status
           FROM menu_access_keys k
           JOIN managed_menus m ON m.id = k.menu_id
          WHERE m.public_id = $1
            AND m.status <> 'DELETED'
            AND k.key_hash = $2
          LIMIT 1
          FOR UPDATE OF k`,
          [publicId, keyHash]
        )).rows[0];

        if (!row) return { error: "INVALID_MENU_KEY" };
        if (row.menu_status !== "ACTIVE") return { error: "MENU_SUSPENDED" };
        if (row.status !== "ACTIVE") return { error: "INVALID_MENU_KEY" };

        const normalized = await markEnded(client, row, now);
        if (normalized.access_state === "WAITING_ADMIN") {
          return { error: "FREE_REQUIRES_ADMIN", accessUntil: normalized.access_until };
        }
        if (normalized.access_state === "EXPIRED") {
          return { error: "VIP_EXPIRED", accessUntil: normalized.access_until };
        }

        if (normalized.bound_device_hash && !safeEqual(normalized.bound_device_hash, dHash)) {
          return { error: "DEVICE_NOT_AUTHORIZED", deviceHint: normalized.bound_device_hint || null };
        }

        let accessUntil = normalized.access_until ? new Date(normalized.access_until) : null;
        let accessState = normalized.access_state || "READY";

        if (accessState === "READY") {
          accessUntil = durationUntil(normalized, now);
          accessState = "ACTIVE";
          await client.query(
            `UPDATE menu_access_keys
                SET access_state = 'ACTIVE',
                    access_started_at = $2,
                    access_until = $3,
                    expires_at = $3,
                    bound_device_hash = COALESCE(bound_device_hash, $4),
                    bound_device_hint = COALESCE(bound_device_hint, $5),
                    bound_at = COALESCE(bound_at, $2),
                    use_count = use_count + 1,
                    last_used_at = NOW(),
                    updated_at = NOW()
              WHERE id = $1`,
            [normalized.id, now, accessUntil, dHash, dHint]
          );
        } else {
          await client.query(
            `UPDATE menu_access_keys
                SET use_count = use_count + 1,
                    last_used_at = NOW(),
                    updated_at = NOW()
              WHERE id = $1`,
            [normalized.id]
          );
        }

        const token = randomToken(48);
        const sessionId = randomId();
        const expiresAt = sessionExpiry(accessUntil, now);
        await client.query(
          `INSERT INTO menu_access_sessions
            (id, menu_id, menu_key_id, token_hash, client_label, device_hash, expires_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            sessionId,
            normalized.menu_id,
            normalized.id,
            tokenHash(`menu-access:${token}`),
            clientLabel,
            dHash,
            expiresAt
          ]
        );

        return {
          token,
          expiresAt,
          keyType: normalized.kind,
          keyAccessUntil: accessUntil,
          menu: { id: normalized.public_id, name: normalized.menu_name }
        };
      });

      if (result.error === "INVALID_MENU_KEY") {
        return sendError(res, 401, result.error, "Chave inválida ou indisponível.");
      }
      if (result.error === "MENU_SUSPENDED") {
        return sendError(res, 403, result.error, "Este menu está suspenso.");
      }
      if (result.error === "FREE_REQUIRES_ADMIN") {
        return sendError(
          res,
          403,
          result.error,
          "O período FREE terminou. Um ADM precisa liberar esta chave novamente.",
          { accessUntil: result.accessUntil }
        );
      }
      if (result.error === "VIP_EXPIRED") {
        return sendError(res, 403, result.error, "O acesso VIP expirou e precisa ser renovado.", { accessUntil: result.accessUntil });
      }
      if (result.error === "DEVICE_NOT_AUTHORIZED") {
        return sendError(
          res,
          403,
          result.error,
          "Esta chave já está vinculada a outro aparelho.",
          { deviceHint: result.deviceHint }
        );
      }

      return res.json({
        ok: true,
        token: result.token,
        expiresAt: result.expiresAt,
        keyType: result.keyType,
        keyExpiresAt: result.keyAccessUntil,
        menu: result.menu
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/menu-access/:publicId/manifest", async (req, res, next) => {
    try {
      const auth = String(req.headers.authorization || "");
      const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
      const deviceId = String(req.headers["x-menu-device-id"] || "").trim().slice(0, 300);
      if (!token) return sendError(res, 401, "UNAUTHORIZED", "Token de acesso ausente.");
      if (!deviceId) return sendError(res, 401, "DEVICE_ID_REQUIRED", "Identificação do aparelho ausente.");

      const hash = tokenHash(`menu-access:${token}`);
      const dHash = deviceHash(deviceId);
      const { rows } = await pool.query(
        `SELECT
           s.id AS session_id,
           s.expires_at AS access_expires_at,
           s.device_hash,
           m.public_id,
           m.name,
           m.source_url,
           k.kind AS key_kind,
           k.access_state,
           k.access_until,
           k.bound_device_hash
         FROM menu_access_sessions s
         JOIN managed_menus m ON m.id = s.menu_id
         JOIN menu_access_keys k ON k.id = s.menu_key_id
         WHERE s.token_hash = $1
           AND m.public_id = $2
           AND s.revoked_at IS NULL
           AND s.expires_at > NOW()
           AND m.status = 'ACTIVE'
           AND k.status = 'ACTIVE'
           AND k.access_state = 'ACTIVE'
           AND (k.access_until IS NULL OR k.access_until > NOW())
         LIMIT 1`,
        [hash, String(req.params.publicId)]
      );

      const row = rows[0];
      if (!row || !row.device_hash || !row.bound_device_hash) {
        return sendError(res, 401, "ACCESS_INVALID", "Acesso inválido, expirado ou revogado.");
      }
      if (!safeEqual(row.device_hash, dHash) || !safeEqual(row.bound_device_hash, dHash)) {
        return sendError(res, 403, "DEVICE_NOT_AUTHORIZED", "Este acesso pertence a outro aparelho.");
      }

      await pool.query(`UPDATE menu_access_sessions SET last_seen_at = NOW() WHERE id = $1`, [row.session_id]);

      return res.json({
        ok: true,
        menu: {
          id: row.public_id,
          name: row.name,
          sourceUrl: row.source_url
        },
        access: {
          expiresAt: row.access_expires_at,
          keyType: row.key_kind,
          keyExpiresAt: row.access_until
        }
      });
    } catch (error) {
      next(error);
    }
  });
}
