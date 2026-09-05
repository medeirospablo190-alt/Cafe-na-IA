import { pool, withTransaction, audit } from "./db.js";
import { requireApp1FullSession, sendApp1FeatureError } from "./app1-feature-auth.js";
import {
  decryptStoredSecret,
  encryptStoredSecret,
  randomId,
  randomToken,
  tokenHash
} from "./security.js";

function cleanText(value, max = 120) {
  return String(value || "").normalize("NFKC").trim().replace(/\s+/g, " ").slice(0, max);
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

function canManageMenu(session, menu) {
  if (!session || !menu) return false;
  if (String(menu.owner_account_id || "") === String(session.account_id || "")) return true;
  return !menu.owner_account_id && session.role === "DEV";
}

async function requireMenuAdmin(req, res, next) {
  return requireApp1FullSession(req, res, (error) => {
    if (error) return next(error);
    const session = req.app1FeatureSession;
    if (!session || !["ADM", "DEV"].includes(String(session.role))) {
      return sendApp1FeatureError(res, 403, "ADMIN_REQUIRED", "Esta área exige uma conta ADM ou DEV.");
    }
    req.app1KeyAdminV2 = session;
    next();
  });
}

async function restoreElapsedTimedSuspensions(client = pool) {
  await client.query(
    `UPDATE managed_menus
        SET status = 'ACTIVE', suspended_until = NULL, updated_at = NOW()
      WHERE status = 'SUSPENDED'
        AND suspended_until IS NOT NULL
        AND suspended_until <= NOW()`
  );
}

function effectiveState(row) {
  if (row.status !== "ACTIVE") return row.access_state;
  if (row.access_state === "ACTIVE" && row.access_until && new Date(row.access_until).getTime() <= Date.now()) {
    return row.kind === "FREE" ? "WAITING_ADMIN" : "EXPIRED";
  }
  return row.access_state || "READY";
}

function keyName(row) {
  return cleanText(row.name, 80) || `${row.kind} ${row.key_hint}`;
}

function mapKey(row) {
  const state = effectiveState(row);
  return {
    id: row.id,
    menu_id: row.menu_id,
    name: keyName(row),
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
    usable: row.status === "ACTIVE" && !row.deleted_at && ["READY", "ACTIVE"].includes(state)
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

async function getManageableMenu(session, menuId, { client = pool, lock = false } = {}) {
  const suffix = lock ? " FOR UPDATE" : "";
  const menu = (await client.query(
    `SELECT * FROM managed_menus
      WHERE id = $1 AND status <> 'DELETED'
      LIMIT 1${suffix}`,
    [String(menuId || "")]
  )).rows[0];
  return menu && canManageMenu(session, menu) ? menu : null;
}

async function getManageableKey(session, keyId, { client = pool, lock = false, includeDeleted = false } = {}) {
  const suffix = lock ? " FOR UPDATE OF k" : "";
  const clauses = ["k.id = $1", "m.status <> 'DELETED'"];
  if (!includeDeleted) clauses.push("k.deleted_at IS NULL", "k.status <> 'REVOKED'");
  const row = (await client.query(
    `SELECT k.*, m.owner_account_id, m.public_id AS menu_public_id, m.name AS menu_name, m.status AS menu_status
       FROM menu_access_keys k
       JOIN managed_menus m ON m.id = k.menu_id
      WHERE ${clauses.join(" AND ")}
      LIMIT 1${suffix}`,
    [String(keyId || "")]
  )).rows[0];
  return row && canManageMenu(session, row) ? row : null;
}

export function registerApp1MenuKeyV2Routes(app) {
  app.get("/v1/app1/menu-admin/menus/:id/keys", requireMenuAdmin, async (req, res, next) => {
    try {
      await restoreElapsedTimedSuspensions();
      const session = req.app1KeyAdminV2;
      const menu = await getManageableMenu(session, req.params.id);
      if (!menu) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const q = cleanText(req.query?.q, 100).replace(/[%_]/g, "");
      const kind = String(req.query?.kind || "ALL").toUpperCase();
      const order = String(req.query?.order || "RECENT").toUpperCase();
      if (!["ALL", "FREE", "VIP"].includes(kind)) {
        return sendApp1FeatureError(res, 400, "INVALID_KIND", "Filtro de chave inválido.");
      }
      if (!["RECENT", "OLD"].includes(order)) {
        return sendApp1FeatureError(res, 400, "INVALID_ORDER", "Ordenação inválida.");
      }

      const params = [menu.id];
      const clauses = ["k.menu_id = $1", "k.deleted_at IS NULL", "k.status <> 'REVOKED'"];
      if (q) {
        params.push(q);
        clauses.push(`(LOWER(COALESCE(k.name, '')) LIKE '%' || LOWER($${params.length}) || '%' OR LOWER(COALESCE(k.note, '')) LIKE '%' || LOWER($${params.length}) || '%' OR LOWER(k.key_hint) LIKE '%' || LOWER($${params.length}) || '%')`);
      }
      if (kind !== "ALL") {
        params.push(kind);
        clauses.push(`k.kind = $${params.length}`);
      }
      const direction = order === "OLD" ? "ASC" : "DESC";
      const rows = (await pool.query(
        `SELECT k.*
           FROM menu_access_keys k
          WHERE ${clauses.join(" AND ")}
          ORDER BY k.created_at ${direction}
          LIMIT 500`,
        params
      )).rows;

      const synced = [];
      for (const row of rows) {
        synced.push(effectiveState(row) !== row.access_state
          ? await withTransaction((client) => syncExpiredKey(client, row))
          : row);
      }
      res.set("Cache-Control", "no-store, private");
      res.json({ ok: true, keys: synced.map(mapKey) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/menus/:id/keys", requireMenuAdmin, async (req, res, next) => {
    try {
      await restoreElapsedTimedSuspensions();
      const session = req.app1KeyAdminV2;
      const menu = await getManageableMenu(session, req.params.id);
      if (!menu) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      if (menu.status !== "ACTIVE") {
        return sendApp1FeatureError(res, 409, "MENU_SUSPENDED", "Ative o menu antes de criar uma nova chave.");
      }

      const name = cleanText(req.body?.name, 80);
      if (name.length < 2) return sendApp1FeatureError(res, 400, "INVALID_KEY_NAME", "Informe um nome para identificar a chave.");
      const kind = String(req.body?.kind || "FREE").toUpperCase();
      if (!["FREE", "VIP"].includes(kind)) {
        return sendApp1FeatureError(res, 400, "INVALID_KEY_KIND", "Escolha FREE ou VIP.");
      }

      let durationUnit;
      let durationValue;
      if (kind === "FREE") {
        durationUnit = "HOURS";
        const raw = Math.floor(Number(req.body?.durationValue || 24));
        if (!Number.isFinite(raw) || raw < 1 || raw > 24) {
          return sendApp1FeatureError(res, 400, "INVALID_FREE_DURATION", "FREE aceita de 1 a 24 horas por ciclo.");
        }
        durationValue = raw;
      } else {
        durationUnit = String(req.body?.durationUnit || "DAYS").toUpperCase();
        if (!["DAYS", "MONTHS", "PERMANENT"].includes(durationUnit)) {
          return sendApp1FeatureError(res, 400, "INVALID_DURATION_UNIT", "VIP aceita dias, meses ou permanente.");
        }
        if (durationUnit === "PERMANENT") {
          durationValue = null;
        } else {
          const raw = Math.floor(Number(req.body?.durationValue || 30));
          if (!Number.isFinite(raw) || raw < 1 || raw > 3650) {
            return sendApp1FeatureError(res, 400, "INVALID_VIP_DURATION", "Informe uma validade VIP válida.");
          }
          durationValue = raw;
        }
      }

      const note = cleanText(req.body?.note, 200) || null;
      const value = makeKey(kind);
      const id = randomId();
      const encryptedValue = encryptStoredSecret(value, keyRevealPurpose(id));
      const row = await withTransaction(async (client) => {
        const currentMenu = await getManageableMenu(session, menu.id, { client, lock: true });
        if (!currentMenu || currentMenu.status !== "ACTIVE") return null;
        const created = (await client.query(
          `INSERT INTO menu_access_keys
            (id, menu_id, name, kind, status, key_hash, key_hint, key_value_encrypted, note,
             expires_at, access_state, duration_value, duration_unit, created_by_session)
           VALUES ($1, $2, $3, $4, 'ACTIVE', $5, $6, $7, $8,
                   NULL, 'READY', $9, $10, NULL)
           RETURNING *`,
          [
            id,
            currentMenu.id,
            name,
            kind,
            tokenHash(`menu-key:${value}`),
            keyHint(value),
            encryptedValue,
            note,
            durationValue,
            durationUnit
          ]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "MENU_KEY_CREATED_APP1_V2",
          targetKind: "MENU_KEY",
          targetId: id,
          metadata: { menuId: currentMenu.id, publicId: currentMenu.public_id, name, kind, durationValue, durationUnit }
        });
        return created;
      });
      if (!row) return sendApp1FeatureError(res, 409, "MENU_SUSPENDED", "O menu não está disponível para novas chaves.");
      res.set("Cache-Control", "no-store, private");
      res.status(201).json({ ok: true, key: { ...mapKey(row), value, revealOnce: false } });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/reveal", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const result = await withTransaction(async (client) => {
        const row = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!row) return { error: "NOT_FOUND" };
        if (!row.key_value_encrypted) return { error: "NOT_RECOVERABLE" };
        const value = decryptStoredSecret(row.key_value_encrypted, keyRevealPurpose(row.id));
        if (!value) return { error: "DECRYPT_FAILED" };
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "MENU_KEY_REVEALED_APP1",
          targetKind: "MENU_KEY",
          targetId: row.id,
          metadata: { menuId: row.menu_id, kind: row.kind }
        });
        return { row, value };
      });
      if (result.error === "NOT_FOUND") return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "NOT_RECOVERABLE") {
        return sendApp1FeatureError(res, 409, "KEY_VALUE_NOT_RECOVERABLE", "Esta chave antiga possui somente hash e o valor original não pode ser reconstruído.");
      }
      if (result.error === "DECRYPT_FAILED") {
        return sendApp1FeatureError(res, 500, "KEY_VALUE_DECRYPT_FAILED", "O servidor não conseguiu recuperar esta chave com segurança.");
      }
      res.set("Cache-Control", "no-store, private");
      res.set("Pragma", "no-cache");
      res.json({ ok: true, key: { id: result.row.id, name: keyName(result.row), kind: result.row.kind, key_hint: result.row.key_hint, value: result.value } });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/release-free", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const hours = Math.floor(Number(req.body?.durationHours || 24));
      if (!Number.isFinite(hours) || hours < 1 || hours > 24) {
        return sendApp1FeatureError(res, 400, "INVALID_FREE_DURATION", "Escolha de 1 a 24 horas.");
      }
      const result = await withTransaction(async (client) => {
        const current = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!current) return { error: "NOT_FOUND" };
        if (current.kind !== "FREE") return { error: "NOT_FREE" };
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = 'ACTIVE', suspended_at = NULL,
                  access_state = 'READY', duration_value = $2, duration_unit = 'HOURS',
                  access_started_at = NULL, access_until = NULL, expires_at = NULL,
                  updated_at = NOW()
            WHERE id = $1 RETURNING *`,
          [current.id, hours]
        )).rows[0];
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [current.id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT", actorId: session.account_id,
          action: "FREE_KEY_RELEASED", targetKind: "MENU_KEY", targetId: current.id,
          metadata: { durationHours: hours }
        });
        return { updated };
      });
      if (result.error === "NOT_FOUND") return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "NOT_FREE") return sendApp1FeatureError(res, 409, "KEY_NOT_FREE", "Somente FREE usa liberação por ciclo.");
      res.json({ ok: true, key: mapKey(result.updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/configure-vip", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const durationUnit = String(req.body?.durationUnit || "DAYS").toUpperCase();
      if (!["DAYS", "MONTHS", "PERMANENT"].includes(durationUnit)) {
        return sendApp1FeatureError(res, 400, "INVALID_DURATION_UNIT", "VIP aceita dias, meses ou permanente.");
      }
      let durationValue = null;
      if (durationUnit !== "PERMANENT") {
        const raw = Math.floor(Number(req.body?.durationValue || 30));
        if (!Number.isFinite(raw) || raw < 1 || raw > 3650) {
          return sendApp1FeatureError(res, 400, "INVALID_VIP_DURATION", "Informe uma validade VIP válida.");
        }
        durationValue = raw;
      }
      const result = await withTransaction(async (client) => {
        const current = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!current) return { error: "NOT_FOUND" };
        if (current.kind !== "VIP") return { error: "NOT_VIP" };
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = 'ACTIVE', suspended_at = NULL,
                  access_state = 'READY', duration_value = $2, duration_unit = $3,
                  access_started_at = NULL, access_until = NULL, expires_at = NULL,
                  updated_at = NOW()
            WHERE id = $1 RETURNING *`,
          [current.id, durationValue, durationUnit]
        )).rows[0];
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [current.id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT", actorId: session.account_id,
          action: "VIP_KEY_CONFIGURED", targetKind: "MENU_KEY", targetId: current.id,
          metadata: { durationValue, durationUnit }
        });
        return { updated };
      });
      if (result.error === "NOT_FOUND") return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "NOT_VIP") return sendApp1FeatureError(res, 409, "KEY_NOT_VIP", "Esta chave não é VIP.");
      res.json({ ok: true, key: mapKey(result.updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/reset-device", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const result = await withTransaction(async (client) => {
        const current = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!current) return null;
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET bound_device_hash = NULL, bound_device_hint = NULL, bound_at = NULL, updated_at = NOW()
            WHERE id = $1 RETURNING *`,
          [current.id]
        )).rows[0];
        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [current.id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT", actorId: session.account_id,
          action: "MENU_KEY_DEVICE_RESET", targetKind: "MENU_KEY", targetId: current.id,
          metadata: {}
        });
        return updated;
      });
      if (!result) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      res.json({ ok: true, key: mapKey(result) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/keys/:keyId/state/:action", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const action = String(req.params.action || "").toLowerCase();
      if (!["suspend", "restore", "revoke"].includes(action)) {
        return sendApp1FeatureError(res, 404, "NOT_FOUND", "Ação de chave desconhecida.");
      }
      const result = await withTransaction(async (client) => {
        const current = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!current) return null;
        const status = action === "suspend" ? "SUSPENDED" : action === "restore" ? "ACTIVE" : "REVOKED";
        const deletedAt = action === "revoke" ? new Date() : null;
        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = $2,
                  suspended_at = CASE WHEN $2 = 'SUSPENDED' THEN NOW() ELSE NULL END,
                  revoked_at = CASE WHEN $2 = 'REVOKED' THEN COALESCE(revoked_at, NOW()) ELSE revoked_at END,
                  deleted_at = CASE WHEN $2 = 'REVOKED' THEN COALESCE(deleted_at, $3) ELSE deleted_at END,
                  updated_at = NOW()
            WHERE id = $1 RETURNING *`,
          [current.id, status, deletedAt]
        )).rows[0];
        if (status !== "ACTIVE") {
          await client.query(
            `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
              WHERE menu_key_id = $1 AND revoked_at IS NULL`,
            [current.id]
          );
        }
        await audit(client, {
          actorKind: "APP1_ACCOUNT", actorId: session.account_id,
          action: status === "REVOKED" ? "MENU_KEY_DELETED_APP1" : `MENU_KEY_${status}`,
          targetKind: "MENU_KEY", targetId: current.id,
          metadata: {}
        });
        return updated;
      });
      if (!result) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      res.json({ ok: true, key: mapKey(result) });
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/app1/menu-admin/keys/:keyId", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1KeyAdminV2;
      const result = await withTransaction(async (client) => {
        const current = await getManageableKey(session, req.params.keyId, { client, lock: true });
        if (!current) return null;
        const sessions = await client.query(
          `UPDATE menu_access_sessions SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_key_id = $1 AND revoked_at IS NULL
            RETURNING id`,
          [current.id]
        );
        await client.query(
          `UPDATE menu_access_keys
              SET status = 'REVOKED',
                  revoked_at = COALESCE(revoked_at, NOW()),
                  deleted_at = COALESCE(deleted_at, NOW()),
                  suspended_at = NULL,
                  updated_at = NOW()
            WHERE id = $1`,
          [current.id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT", actorId: session.account_id,
          action: "MENU_KEY_DELETED_APP1", targetKind: "MENU_KEY", targetId: current.id,
          metadata: { menuId: current.menu_id, revokedSessions: sessions.rowCount }
        });
        return { revokedSessions: sessions.rowCount };
      });
      if (!result) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      res.json({ ok: true, ...result });
    } catch (error) {
      next(error);
    }
  });
}
