import { pool, withTransaction, audit } from "./db.js";
import { requireApp1FullSession, sendApp1FeatureError } from "./app1-feature-auth.js";
import { decryptStoredSecret, encryptStoredSecret, randomId } from "./security.js";
import { makeMenuPublicId, validateMenuSourceUrl } from "./menu-routes.js";

const MAX_INLINE_SOURCE_BYTES = 4 * 1024 * 1024;
const MAX_SUSPEND_MINUTES = 60 * 24 * 30;

function cleanText(value, max = 120) {
  return String(value || "").normalize("NFKC").trim().replace(/\s+/g, " ").slice(0, max);
}

function menuSourcePurpose(menuId) {
  return `menu-source:${String(menuId || "")}`;
}

function canManage(session, row) {
  if (!session || !row) return false;
  if (String(row.owner_account_id || "") === String(session.account_id || "")) return true;
  return !row.owner_account_id && session.role === "DEV";
}

async function requireMenuAdmin(req, res, next) {
  return requireApp1FullSession(req, res, async (error) => {
    if (error) return next(error);
    const session = req.app1FeatureSession;
    if (!session || !["ADM", "DEV"].includes(String(session.role))) {
      return sendApp1FeatureError(res, 403, "ADMIN_REQUIRED", "Esta área exige uma conta ADM ou DEV.");
    }
    req.app1MenuAdminV2 = session;
    return next();
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

function mapMenu(row) {
  return {
    id: row.id,
    public_id: row.public_id,
    name: row.name,
    status: row.status,
    source_kind: row.source_kind || "REMOTE_URL",
    suspended_until: row.suspended_until || null,
    key_count: Number(row.key_count || 0),
    free_key_count: Number(row.free_key_count || 0),
    vip_key_count: Number(row.vip_key_count || 0),
    active_access_count: Number(row.active_access_count || 0),
    legacy_unowned: !row.owner_account_id,
    created_at: row.created_at,
    updated_at: row.updated_at
  };
}

async function getManageableMenu(session, id, { lock = false, client = pool } = {}) {
  const suffix = lock ? " FOR UPDATE" : "";
  const row = (await client.query(
    `SELECT *
       FROM managed_menus
      WHERE id = $1
        AND status <> 'DELETED'
      LIMIT 1${suffix}`,
    [String(id || "")]
  )).rows[0];
  return row && canManage(session, row) ? row : null;
}

async function uniquePublicId(client) {
  let publicId = makeMenuPublicId();
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const exists = await client.query(`SELECT 1 FROM managed_menus WHERE public_id = $1 LIMIT 1`, [publicId]);
    if (!exists.rowCount) return publicId;
    publicId = makeMenuPublicId();
  }
  throw new Error("MENU_ID_COLLISION");
}

function parseInlineSource(value) {
  if (typeof value !== "string") return null;
  const source = value.replace(/^\uFEFF/, "");
  const bytes = Buffer.byteLength(source, "utf8");
  if (!source.trim()) return { error: "EMPTY" };
  if (bytes > MAX_INLINE_SOURCE_BYTES) return { error: "TOO_LARGE", bytes };
  return { source, bytes };
}

function resolveSourceInput(body, existing = null) {
  const hasCode = Object.prototype.hasOwnProperty.call(body || {}, "sourceCode");
  const hasUrl = Object.prototype.hasOwnProperty.call(body || {}, "sourceUrl");
  if (hasCode && hasUrl) return { error: "MULTIPLE" };
  if (!hasCode && !hasUrl) return existing ? { unchanged: true } : { error: "MISSING" };

  if (hasCode) {
    const parsed = parseInlineSource(body?.sourceCode);
    if (!parsed || parsed.error) return parsed || { error: "EMPTY" };
    return { kind: "INLINE_ENCRYPTED", source: parsed.source, bytes: parsed.bytes };
  }

  const sourceUrl = validateMenuSourceUrl(body?.sourceUrl);
  if (!sourceUrl) return { error: "INVALID_URL" };
  return { kind: "REMOTE_URL", sourceUrl };
}

function sourceInputError(res, parsed) {
  if (parsed?.error === "MULTIPLE") {
    return sendApp1FeatureError(res, 400, "MULTIPLE_SOURCES", "Envie código Lua ou URL, não os dois ao mesmo tempo.");
  }
  if (parsed?.error === "MISSING") {
    return sendApp1FeatureError(res, 400, "SOURCE_REQUIRED", "Cole o código Lua ou informe uma URL HTTPS do GitHub para .lua.");
  }
  if (parsed?.error === "EMPTY") {
    return sendApp1FeatureError(res, 400, "EMPTY_SOURCE", "O código Lua está vazio.");
  }
  if (parsed?.error === "TOO_LARGE") {
    return sendApp1FeatureError(res, 413, "SOURCE_TOO_LARGE", "O código Lua excede o limite de 4 MB.");
  }
  if (parsed?.error === "INVALID_URL") {
    return sendApp1FeatureError(res, 400, "INVALID_SOURCE_URL", "Use uma URL HTTPS do GitHub apontando para um arquivo .lua.");
  }
  return null;
}

export function registerApp1MenuManagementV2Routes(app) {
  app.get("/v1/app1/menu-admin/menus", requireMenuAdmin, async (req, res, next) => {
    try {
      await restoreElapsedTimedSuspensions();
      const session = req.app1MenuAdminV2;
      const q = cleanText(req.query?.q, 100).replace(/[%_]/g, "");
      const status = String(req.query?.status || "").toUpperCase();
      const order = String(req.query?.order || "RECENT").toUpperCase();
      if (status && !["ACTIVE", "SUSPENDED"].includes(status)) {
        return sendApp1FeatureError(res, 400, "INVALID_STATUS", "Filtro de status inválido.");
      }
      if (!["RECENT", "OLD"].includes(order)) {
        return sendApp1FeatureError(res, 400, "INVALID_ORDER", "Ordenação inválida.");
      }

      const params = [session.account_id, session.role];
      const clauses = [
        "m.status <> 'DELETED'",
        `(m.owner_account_id = $1 OR (m.owner_account_id IS NULL AND $2 = 'DEV'))`
      ];
      if (q) {
        params.push(q);
        clauses.push(`LOWER(m.name) LIKE '%' || LOWER($${params.length}) || '%'`);
      }
      if (status) {
        params.push(status);
        clauses.push(`m.status = $${params.length}`);
      }

      const direction = order === "OLD" ? "ASC" : "DESC";
      const { rows } = await pool.query(
        `SELECT
           m.*,
           COUNT(DISTINCT k.id) FILTER (WHERE k.deleted_at IS NULL AND k.status <> 'REVOKED')::int AS key_count,
           COUNT(DISTINCT k.id) FILTER (WHERE k.deleted_at IS NULL AND k.status <> 'REVOKED' AND k.kind = 'FREE')::int AS free_key_count,
           COUNT(DISTINCT k.id) FILTER (WHERE k.deleted_at IS NULL AND k.status <> 'REVOKED' AND k.kind = 'VIP')::int AS vip_key_count,
           COUNT(DISTINCT s.id) FILTER (WHERE s.revoked_at IS NULL AND s.expires_at > NOW())::int AS active_access_count
         FROM managed_menus m
         LEFT JOIN menu_access_keys k ON k.menu_id = m.id
         LEFT JOIN menu_access_sessions s ON s.menu_id = m.id
         WHERE ${clauses.join(" AND ")}
         GROUP BY m.id
         ORDER BY m.updated_at ${direction}, m.name ASC
         LIMIT 250`,
        params
      );
      res.set("Cache-Control", "no-store, private");
      res.json({ ok: true, menus: rows.map(mapMenu) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/menus", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      const name = cleanText(req.body?.name, 100);
      if (name.length < 2) return sendApp1FeatureError(res, 400, "INVALID_NAME", "Informe um nome com pelo menos 2 caracteres.");
      const parsed = resolveSourceInput(req.body);
      if (parsed.error) return sourceInputError(res, parsed);

      const result = await withTransaction(async (client) => {
        const id = randomId();
        const publicId = await uniquePublicId(client);
        const inline = parsed.kind === "INLINE_ENCRYPTED";
        const encrypted = inline ? encryptStoredSecret(parsed.source, menuSourcePurpose(id)) : null;
        const sourceUrl = inline ? "private://inline" : parsed.sourceUrl;
        const row = (await client.query(
          `INSERT INTO managed_menus
            (id, public_id, name, source_url, source_kind, source_ciphertext,
             status, owner_account_id, created_by_session)
           VALUES ($1, $2, $3, $4, $5, $6, 'ACTIVE', $7, NULL)
           RETURNING *`,
          [id, publicId, name, sourceUrl, parsed.kind, encrypted, session.account_id]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "MENU_CREATED_APP1",
          targetKind: "MENU",
          targetId: id,
          metadata: { publicId, name, sourceKind: parsed.kind, sourceBytes: parsed.bytes || null }
        });
        return row;
      });

      res.status(201).json({ ok: true, menu: mapMenu(result) });
    } catch (error) {
      if (error?.message === "MENU_ID_COLLISION" || error?.code === "23505") {
        return sendApp1FeatureError(res, 409, "MENU_ID_COLLISION", "Não foi possível gerar um ID único. Tente novamente.");
      }
      next(error);
    }
  });

  app.get("/v1/app1/menu-admin/menus/:id/source", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      const menu = await getManageableMenu(session, req.params.id);
      if (!menu) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      let sourceCode = null;
      let sourceUrl = null;
      if (menu.source_kind === "INLINE_ENCRYPTED") {
        sourceCode = decryptStoredSecret(menu.source_ciphertext, menuSourcePurpose(menu.id));
        if (sourceCode == null) {
          return sendApp1FeatureError(res, 500, "SOURCE_DECRYPT_FAILED", "Não foi possível recuperar o código deste menu.");
        }
      } else {
        sourceUrl = menu.source_url;
      }

      await withTransaction((client) => audit(client, {
        actorKind: "APP1_ACCOUNT",
        actorId: session.account_id,
        action: "MENU_SOURCE_VIEWED_APP1",
        targetKind: "MENU",
        targetId: menu.id,
        metadata: { sourceKind: menu.source_kind || "REMOTE_URL" }
      }));

      res.set("Cache-Control", "no-store, private");
      res.set("Pragma", "no-cache");
      res.json({ ok: true, sourceKind: menu.source_kind || "REMOTE_URL", sourceCode, sourceUrl });
    } catch (error) {
      next(error);
    }
  });

  app.patch("/v1/app1/menu-admin/menus/:id", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      const current = await getManageableMenu(session, req.params.id);
      if (!current) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const name = req.body?.name == null ? current.name : cleanText(req.body.name, 100);
      if (name.length < 2) return sendApp1FeatureError(res, 400, "INVALID_NAME", "Informe um nome com pelo menos 2 caracteres.");
      const parsed = resolveSourceInput(req.body, current);
      if (parsed.error) return sourceInputError(res, parsed);

      const updated = await withTransaction(async (client) => {
        const locked = await getManageableMenu(session, current.id, { lock: true, client });
        if (!locked) return null;
        let sourceKind = locked.source_kind || "REMOTE_URL";
        let sourceUrl = locked.source_url;
        let sourceCiphertext = locked.source_ciphertext;
        let sourceChanged = false;
        let sourceBytes = null;
        if (!parsed.unchanged) {
          sourceChanged = true;
          sourceKind = parsed.kind;
          sourceBytes = parsed.bytes || null;
          if (parsed.kind === "INLINE_ENCRYPTED") {
            sourceUrl = "private://inline";
            sourceCiphertext = encryptStoredSecret(parsed.source, menuSourcePurpose(locked.id));
          } else {
            sourceUrl = parsed.sourceUrl;
            sourceCiphertext = null;
          }
        }
        const row = (await client.query(
          `UPDATE managed_menus
              SET name = $2,
                  source_url = $3,
                  source_kind = $4,
                  source_ciphertext = $5,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [locked.id, name, sourceUrl, sourceKind, sourceCiphertext]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "MENU_UPDATED_APP1",
          targetKind: "MENU",
          targetId: locked.id,
          metadata: { name, sourceChanged, sourceKind, sourceBytes }
        });
        return row;
      });
      if (!updated) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      res.json({ ok: true, menu: mapMenu(updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/menus/:id/state/:action", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      const action = String(req.params.action || "").toLowerCase();
      if (!["suspend", "restore"].includes(action)) {
        return sendApp1FeatureError(res, 404, "NOT_FOUND", "Ação de menu desconhecida.");
      }
      const rawMinutes = req.body?.durationMinutes;
      let durationMinutes = null;
      if (action === "suspend" && rawMinutes != null && rawMinutes !== "") {
        const parsed = Math.floor(Number(rawMinutes));
        if (!Number.isFinite(parsed) || parsed < 1 || parsed > MAX_SUSPEND_MINUTES) {
          return sendApp1FeatureError(res, 400, "INVALID_SUSPEND_DURATION", "A suspensão temporária aceita de 1 minuto a 30 dias.");
        }
        durationMinutes = parsed;
      }

      const updated = await withTransaction(async (client) => {
        const current = await getManageableMenu(session, req.params.id, { lock: true, client });
        if (!current) return null;
        const nextStatus = action === "suspend" ? "SUSPENDED" : "ACTIVE";
        const until = action === "suspend" && durationMinutes
          ? new Date(Date.now() + durationMinutes * 60_000)
          : null;
        const row = (await client.query(
          `UPDATE managed_menus
              SET status = $2, suspended_until = $3, updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [current.id, nextStatus, until]
        )).rows[0];
        if (nextStatus === "SUSPENDED") {
          await client.query(
            `UPDATE menu_access_sessions
                SET revoked_at = COALESCE(revoked_at, NOW())
              WHERE menu_id = $1 AND revoked_at IS NULL`,
            [current.id]
          );
        }
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: nextStatus === "SUSPENDED" ? "MENU_SUSPENDED_APP1" : "MENU_RESTORED_APP1",
          targetKind: "MENU",
          targetId: current.id,
          metadata: { durationMinutes, suspendedUntil: until }
        });
        return row;
      });
      if (!updated) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      res.json({ ok: true, menu: mapMenu(updated) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/menu-admin/menus/:id/claim", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      if (session.role !== "DEV") {
        return sendApp1FeatureError(res, 403, "DEV_REQUIRED", "Somente DEV pode assumir um menu legado sem proprietário.");
      }
      const result = await withTransaction(async (client) => {
        const current = (await client.query(
          `SELECT * FROM managed_menus
            WHERE id = $1 AND status <> 'DELETED'
            FOR UPDATE`,
          [String(req.params.id || "")]
        )).rows[0];
        if (!current) return { error: "NOT_FOUND" };
        if (current.owner_account_id) {
          if (String(current.owner_account_id) === String(session.account_id)) return { row: current, unchanged: true };
          return { error: "ALREADY_OWNED" };
        }
        const row = (await client.query(
          `UPDATE managed_menus
              SET owner_account_id = $2, updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [current.id, session.account_id]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "LEGACY_MENU_CLAIMED_APP1",
          targetKind: "MENU",
          targetId: current.id,
          metadata: { publicId: current.public_id }
        });
        return { row };
      });
      if (result.error === "NOT_FOUND") return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      if (result.error === "ALREADY_OWNED") return sendApp1FeatureError(res, 409, "MENU_ALREADY_OWNED", "Este menu já pertence a outra conta.");
      res.json({ ok: true, menu: mapMenu(result.row), unchanged: Boolean(result.unchanged) });
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/app1/menu-admin/menus/:id", requireMenuAdmin, async (req, res, next) => {
    try {
      const session = req.app1MenuAdminV2;
      const deleted = await withTransaction(async (client) => {
        const current = await getManageableMenu(session, req.params.id, { lock: true, client });
        if (!current) return null;
        const sessions = await client.query(
          `UPDATE menu_access_sessions
              SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_id = $1 AND revoked_at IS NULL
            RETURNING id`,
          [current.id]
        );
        const keys = await client.query(
          `UPDATE menu_access_keys
              SET status = 'REVOKED',
                  revoked_at = COALESCE(revoked_at, NOW()),
                  deleted_at = COALESCE(deleted_at, NOW()),
                  suspended_at = NULL,
                  updated_at = NOW()
            WHERE menu_id = $1 AND status <> 'REVOKED'
            RETURNING id`,
          [current.id]
        );
        await client.query(
          `UPDATE managed_menus
              SET status = 'DELETED', suspended_until = NULL, updated_at = NOW()
            WHERE id = $1`,
          [current.id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "MENU_DELETED_APP1",
          targetKind: "MENU",
          targetId: current.id,
          metadata: {
            publicId: current.public_id,
            name: current.name,
            revokedKeys: keys.rowCount,
            revokedSessions: sessions.rowCount,
            legacyUnowned: !current.owner_account_id
          }
        });
        return { revokedKeys: keys.rowCount, revokedSessions: sessions.rowCount };
      });
      if (!deleted) return sendApp1FeatureError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      res.json({ ok: true, ...deleted });
    } catch (error) {
      next(error);
    }
  });
}
