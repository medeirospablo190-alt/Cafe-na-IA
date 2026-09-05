import crypto from "crypto";
import { pool, withTransaction, audit } from "./db.js";
import {
  decryptStoredSecret,
  encryptStoredSecret,
  randomId,
  randomToken,
  tokenHash
} from "./security.js";

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

function cleanText(value, max = 120) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, max);
}

function keyHint(key) {
  const value = String(key || "");
  return value.length <= 14 ? value : `${value.slice(0, 9)}…${value.slice(-5)}`;
}

function makeKey(kind) {
  return kind === "FREE" ? `FREE-${randomToken(24)}` : `VIP-${randomToken(32)}`;
}

function keyRevealPurpose(keyId) {
  return `menu-key-reveal:${String(keyId || "")}`;
}

async function getApp1Session(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const deviceToken = String(req.headers["x-app1-device-token"] || "").slice(0, 500);
  if (!token || !deviceToken) return null;

  const sessionHash = tokenHash(`app1:${token}`);
  const { rows } = await pool.query(
    `SELECT
       s.id AS session_id,
       s.account_id,
       s.session_kind,
       a.role,
       a.status,
       d.status AS device_status,
       d.device_token_hash
     FROM app1_sessions s
     JOIN app1_accounts a ON a.id = s.account_id
     JOIN app1_devices d ON d.id = s.app1_device_id
     WHERE s.token_hash = $1
       AND s.revoked_at IS NULL
       AND s.expires_at > NOW()
     LIMIT 1`,
    [sessionHash]
  );
  const row = rows[0];
  if (!row || row.status !== "ACTIVE" || row.device_status !== "ACTIVE" || row.session_kind !== "FULL") return null;
  const suppliedHash = tokenHash(`app1-device:${deviceToken}`);
  if (!safeEqual(suppliedHash, row.device_token_hash)) return null;
  return row;
}

async function requireApp1Admin(req, res, next) {
  try {
    const session = await getApp1Session(req);
    if (!session) return sendError(res, 401, "UNAUTHORIZED", "Sessão App 1 inválida ou incompatível com o dispositivo.");
    if (!["ADM", "DEV"].includes(String(session.role))) {
      return sendError(res, 403, "ADMIN_REQUIRED", "Esta área exige uma conta ADM ou DEV.");
    }
    req.app1MenuAdmin = session;
    next();
  } catch (error) {
    next(error);
  }
}

function effectiveState(row) {
  if (row.status !== "ACTIVE") return row.access_state;
  if (row.access_state === "ACTIVE" && row.access_until && new Date(row.access_until).getTime() <= Date.now()) {
    return row.kind === "FREE" ? "WAITING_ADMIN" : "EXPIRED";
  }
  return row.access_state || "READY";
}

function mapKey(row) {
  const state = effectiveState(row);
  return {
    id: row.id,
    menu_id: row.menu_id,
    kind: row.kind,
    status: row.status,
    key_hint: row.key_hint,
    note: row.note,
    access_state: state,
    duration_value: row.duration_value,
    duration_unit: row.duration_unit,
    access_started_at: row.access_started_at,
    access_until: row.access_until,
    bound_device: Boolean(row.bound_device_hash),
    bound_device_hint: row.bound_device_hint,
    use_count: Number(row.use_count || 0),
    last_used_at: row.last_used_at,
    created_at: row.created_at,
    updated_at: row.updated_at,
    revoked_at: row.revoked_at,
    can_reveal: Boolean(row.key_value_encrypted),
    usable: row.status === "ACTIVE" && ["READY", "ACTIVE"].includes(state)
  };
}

async function syncExpiredKey(client, row) {
  const state = effectiveState(row);
  if (state === row.access_state) return row;
  await client.query(
    `UPDATE menu_access_keys SET access_state = $2, updated_at = NOW() WHERE id = $1`,
    [row.id, state]
  );
  await client.query(
    `UPDATE menu_access_sessions
        SET revoked_at = COALESCE(revoked_at, NOW())
      WHERE menu_key_id = $1 AND revoked_at IS NULL`,
    [row.id]
  );
  return { ...row, access_state: state };
}

export function registerApp1MenuKeyRoutes(app) {
  app.get("/v1/app1/menu-admin/menus", requireApp1Admin, async (req, res, next) => {
    try {
      const { rows } = await pool.query(
        `SELECT
           m.id, m.public_id, m.name, m.source_url, m.status, m.created_at, m.updated_at,
           COUNT(k.id) FILTER (WHERE k.status <> 'REVOKED')::int AS key_count
         FROM managed_menus m
         LEFT JOIN menu_access_keys k ON k.menu_id = m.id
         WHERE m.status <> 'DELETED'
         GROUP BY m.id
         ORDER BY m.updated_at DESC, m.name ASC
         LIMIT 250`
      );
      res.json({ ok: true, menus: rows });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/menu-admin/menus/:id/keys", requireApp1Admin, async (req, res, next) => {
    try {
      const menuId = String(req.params.id || "");
      const rows = (await pool.query(
        `SELECT k.*
           FROM menu_access_keys k
           JOIN managed_menus m ON m.id = k.menu_id
          WHERE k.menu_id = $1
            AND m.status <> 'DELETED'
          ORDER BY k.created_at DESC
          LIMIT 500`,
        [menuId]
      )).rows;

      const synced = [];
      for (const row of rows) {
        if (effectiveState(row) !== row.access_state) {
          synced.push(await withTransaction((client) => syncExpiredKey(client, row)));
        } else {
          synced.push(row);
        }
      }
      res.json({ ok: true, keys: synced.map(mapKey) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/menus/:id/keys", requireApp1Admin, async (req, res, next) => {
    try {
      const menuId = String(req.params.id || "");
      const kind = String(req.body?.kind || "FREE").toUpperCase();
      if (!["FREE", "VIP"].includes(kind)) {
        return sendError(res, 400, "INVALID_KEY_KIND", "Escolha FREE ou VIP.");
      }

      const menu = (await pool.query(
        `SELECT id, public_id, name, status FROM managed_menus WHERE id = $1 AND status <> 'DELETED' LIMIT 1`,
        [menuId]
      )).rows[0];
      if (!menu) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      let durationUnit;
      let durationValue;
      if (kind === "FREE") {
        durationUnit = "HOURS";
        durationValue = Math.min(24, Math.max(1, Math.floor(Number(req.body?.durationValue || 24))));
      } else {
        durationUnit = String(req.body?.durationUnit || "DAYS").toUpperCase();
        if (!["DAYS", "MONTHS", "PERMANENT"].includes(durationUnit)) {
          return sendError(res, 400, "INVALID_DURATION_UNIT", "VIP aceita dias, meses ou permanente.");
        }
        durationValue = durationUnit === "PERMANENT"
          ? null
          : Math.max(1, Math.min(3650, Math.floor(Number(req.body?.durationValue || 30))));
      }

      const note = cleanText(req.body?.note, 200) || null;
      const value = makeKey(kind);
      const id = randomId();
      const hint = keyHint(value);
      const encryptedValue = encryptStoredSecret(value, keyRevealPurpose(id));

      const row = await withTransaction(async (client) => {
        const created = (await client.query(
          `INSERT INTO menu_access_keys
            (id, menu_id, kind, status, key_hash, key_hint, key_value_encrypted, note,
             expires_at, access_state, duration_value, duration_unit,
             created_by_session)
           VALUES ($1, $2, $3, 'ACTIVE', $4, $5, $6, $7,
                   NULL, 'READY', $8, $9, NULL)
           RETURNING *`,
          [
            id,
            menu.id,
            kind,
            tokenHash(`menu-key:${value}`),
            hint,
            encryptedValue,
            note,
            durationValue,
            durationUnit
          ]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: "MENU_KEY_CREATED_APP1",
          targetKind: "MENU_KEY",
          targetId: id,
          metadata: { menuId: menu.id, publicId: menu.public_id, kind, durationValue, durationUnit }
        });
        return created;
      });

      res.set("Cache-Control", "no-store, private");
      res.status(201).json({ ok: true, key: { ...mapKey(row), value, revealOnce: false } });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/reveal", requireApp1Admin, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId || "");
      const result = await withTransaction(async (client) => {
        const row = (await client.query(
          `SELECT id, menu_id, kind, status, key_hint, key_value_encrypted
             FROM menu_access_keys
            WHERE id = $1
            LIMIT 1`,
          [keyId]
        )).rows[0];
        if (!row) return { error: "NOT_FOUND" };
        if (row.status === "REVOKED") return { error: "REVOKED" };
        if (!row.key_value_encrypted) return { error: "NOT_RECOVERABLE" };

        const value = decryptStoredSecret(row.key_value_encrypted, keyRevealPurpose(row.id));
        if (!value) return { error: "DECRYPT_FAILED" };

        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: "MENU_KEY_REVEALED_APP1",
          targetKind: "MENU_KEY",
          targetId: row.id,
          metadata: { menuId: row.menu_id, kind: row.kind }
        });
        return { row, value };
      });

      if (result.error === "NOT_FOUND") return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "REVOKED") return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser revelada.");
      if (result.error === "NOT_RECOVERABLE") {
        return sendError(
          res,
          409,
          "KEY_VALUE_NOT_RECOVERABLE",
          "Esta chave foi criada antes da recuperação segura ser ativada e o valor original não pode ser reconstruído a partir do hash."
        );
      }
      if (result.error === "DECRYPT_FAILED") {
        return sendError(res, 500, "KEY_VALUE_DECRYPT_FAILED", "O servidor não conseguiu recuperar esta chave com segurança.");
      }

      res.set("Cache-Control", "no-store, private");
      res.set("Pragma", "no-cache");
      res.json({
        ok: true,
        key: {
          id: result.row.id,
          kind: result.row.kind,
          key_hint: result.row.key_hint,
          value: result.value
        }
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/release-free", requireApp1Admin, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId || "");
      const requested = Math.floor(Number(req.body?.durationHours || 24));
      const durationHours = Math.min(24, Math.max(1, Number.isFinite(requested) ? requested : 24));

      const result = await withTransaction(async (client) => {
        const current = (await client.query(
          `SELECT * FROM menu_access_keys WHERE id = $1 FOR UPDATE`,
          [keyId]
        )).rows[0];
        if (!current) return { error: "NOT_FOUND" };
        if (current.kind !== "FREE") return { error: "NOT_FREE" };
        if (current.status === "REVOKED") return { error: "REVOKED" };

        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = 'ACTIVE',
                  suspended_at = NULL,
                  access_state = 'READY',
                  duration_value = $2,
                  duration_unit = 'HOURS',
                  access_started_at = NULL,
                  access_until = NULL,
                  expires_at = NULL,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [keyId, durationHours]
        )).rows[0];
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [keyId]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: "FREE_KEY_RELEASED",
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: { durationHours }
        });
        return { updated };
      });

      if (result.error === "NOT_FOUND") return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "NOT_FREE") return sendError(res, 409, "KEY_NOT_FREE", "Somente FREE usa liberação por ciclo.");
      if (result.error === "REVOKED") return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser liberada.");
      res.json({ ok: true, key: mapKey(result.updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/configure-vip", requireApp1Admin, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId || "");
      const durationUnit = String(req.body?.durationUnit || "DAYS").toUpperCase();
      if (!["DAYS", "MONTHS", "PERMANENT"].includes(durationUnit)) {
        return sendError(res, 400, "INVALID_DURATION_UNIT", "VIP aceita dias, meses ou permanente.");
      }
      const raw = Math.floor(Number(req.body?.durationValue || 30));
      const durationValue = durationUnit === "PERMANENT" ? null : Math.max(1, Math.min(3650, Number.isFinite(raw) ? raw : 30));

      const result = await withTransaction(async (client) => {
        const current = (await client.query(`SELECT * FROM menu_access_keys WHERE id = $1 FOR UPDATE`, [keyId])).rows[0];
        if (!current) return { error: "NOT_FOUND" };
        if (current.kind !== "VIP") return { error: "NOT_VIP" };
        if (current.status === "REVOKED") return { error: "REVOKED" };

        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = 'ACTIVE',
                  suspended_at = NULL,
                  access_state = 'READY',
                  duration_value = $2,
                  duration_unit = $3,
                  access_started_at = NULL,
                  access_until = NULL,
                  expires_at = NULL,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [keyId, durationValue, durationUnit]
        )).rows[0];
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [keyId]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: "VIP_KEY_CONFIGURED",
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: { durationValue, durationUnit }
        });
        return { updated };
      });

      if (result.error === "NOT_FOUND") return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "NOT_VIP") return sendError(res, 409, "KEY_NOT_VIP", "Esta chave não é VIP.");
      if (result.error === "REVOKED") return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser renovada.");
      res.json({ ok: true, key: mapKey(result.updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/reset-device", requireApp1Admin, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId || "");
      const result = await withTransaction(async (client) => {
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET bound_device_hash = NULL,
                  bound_device_hint = NULL,
                  bound_at = NULL,
                  updated_at = NOW()
            WHERE id = $1 AND status <> 'REVOKED'
            RETURNING *`,
          [keyId]
        )).rows[0];
        if (!updated) return null;
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [keyId]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: "MENU_KEY_DEVICE_RESET",
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: {}
        });
        return updated;
      });
      if (!result) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada ou revogada.");
      res.json({ ok: true, key: mapKey(result) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/state/:action", requireApp1Admin, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId || "");
      const action = String(req.params.action || "").toLowerCase();
      if (!["suspend", "restore", "revoke"].includes(action)) {
        return sendError(res, 404, "NOT_FOUND", "Ação de chave desconhecida.");
      }

      const result = await withTransaction(async (client) => {
        const current = (await client.query(`SELECT * FROM menu_access_keys WHERE id = $1 FOR UPDATE`, [keyId])).rows[0];
        if (!current) return null;
        if (current.status === "REVOKED" && action !== "revoke") return { error: "REVOKED" };
        const status = action === "suspend" ? "SUSPENDED" : action === "restore" ? "ACTIVE" : "REVOKED";
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = $2,
                  suspended_at = CASE WHEN $2 = 'SUSPENDED' THEN NOW() ELSE NULL END,
                  revoked_at = CASE WHEN $2 = 'REVOKED' THEN COALESCE(revoked_at, NOW()) ELSE revoked_at END,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [keyId, status]
        )).rows[0];
        if (status !== "ACTIVE") {
          await client.query(
            `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
              WHERE menu_key_id = $1 AND revoked_at IS NULL`,
            [keyId]
          );
        }
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: req.app1MenuAdmin.account_id,
          action: `MENU_KEY_${status}`,
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: {}
        });
        return { updated };
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "REVOKED") return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser restaurada.");
      res.json({ ok: true, key: mapKey(result.updated) });
    } catch (error) {
      next(error);
    }
  });
}
