import { randomId, randomToken, tokenHash } from "./security.js";
import { pool, withTransaction, audit } from "./db.js";

const ACCESS_SESSION_MS = 15 * 60 * 1000;
const MAX_FREE_HOURS = 24 * 365;
const PUBLIC_ATTEMPT_WINDOW_MS = 60 * 1000;
const PUBLIC_ATTEMPT_LIMIT = 12;
const publicAttempts = new Map();

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function cleanText(value, max = 120) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, max);
}

export function validateMenuSourceUrl(value) {
  try {
    const url = new URL(String(value || "").trim());
    if (url.protocol !== "https:") return null;
    const host = url.hostname.toLowerCase();

    if (host === "github.com") {
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts.length < 5 || parts[2] !== "blob") return null;
      const raw = new URL(
        `https://raw.githubusercontent.com/${parts[0]}/${parts[1]}/${parts.slice(3).join("/")}`
      );
      if (!raw.pathname.toLowerCase().endsWith(".lua")) return null;
      return raw.toString();
    }

    if (host !== "raw.githubusercontent.com") return null;
    if (!url.pathname.toLowerCase().endsWith(".lua")) return null;
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

export function makeMenuPublicId() {
  return `menu_${randomToken(9)}`;
}

export function makeMenuKey(kind) {
  const normalized = String(kind || "").toUpperCase();
  if (normalized === "FREE") return `FREE-${randomToken(24)}`;
  if (normalized === "VIP") return `VIP-${randomToken(32)}`;
  throw new Error("INVALID_MENU_KEY_KIND");
}

export function menuKeyHint(key) {
  const value = String(key || "");
  if (value.length <= 14) return value;
  return `${value.slice(0, 9)}…${value.slice(-5)}`;
}

async function getKeymasterSession(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return null;
  const hash = tokenHash(token);
  const { rows } = await pool.query(
    `SELECT s.id, s.device_id, s.expires_at
       FROM keymaster_sessions s
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > NOW()
      LIMIT 1`,
    [hash]
  );
  return rows[0] || null;
}

async function requireKeymaster(req, res, next) {
  try {
    const session = await getKeymasterSession(req);
    if (!session) return sendError(res, 401, "UNAUTHORIZED", "Sessão Keymaster inválida ou expirada.");
    req.keymasterSession = session;
    next();
  } catch (error) {
    next(error);
  }
}

function baseUrl(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");
  if (configured) return configured;
  return `${req.protocol}://${req.get("host")}`;
}

function accessUrl(req, publicId) {
  return `${baseUrl(req)}/l/${encodeURIComponent(publicId)}`;
}

function mapMenu(row, req) {
  const url = accessUrl(req, row.public_id);
  return {
    id: row.id,
    public_id: row.public_id,
    name: row.name,
    source_url: row.source_url,
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    free_keys: Number(row.free_keys || 0),
    vip_keys: Number(row.vip_keys || 0),
    active_accesses: Number(row.active_accesses || 0),
    accesses_month: Number(row.accesses_month || 0),
    loader_url: url,
    access_url: url
  };
}

async function getManagedMenu(idOrPublicId) {
  const value = String(idOrPublicId || "").trim();
  if (!value) return null;
  return (await pool.query(
    `SELECT * FROM managed_menus
      WHERE (id::text = $1 OR public_id = $1)
        AND status <> 'DELETED'
      LIMIT 1`,
    [value]
  )).rows[0] || null;
}

function publicAttemptAllowed(req, publicId) {
  const now = Date.now();
  const id = `${String(req.ip || req.socket?.remoteAddress || "unknown")}:${publicId}`;
  const current = publicAttempts.get(id);

  if (!current || current.resetAt <= now) {
    publicAttempts.set(id, { count: 1, resetAt: now + PUBLIC_ATTEMPT_WINDOW_MS });
    return true;
  }

  current.count += 1;
  return current.count <= PUBLIC_ATTEMPT_LIMIT;
}

function publicDescriptor(req, menu) {
  const base = baseUrl(req);
  return {
    ok: true,
    menu: {
      id: menu.public_id,
      name: menu.name,
      status: menu.status
    },
    access: {
      validate: `${base}/v1/menu-access/validate`,
      manifest: `${base}/v1/menu-access/${encodeURIComponent(menu.public_id)}/manifest`,
      sessionMinutes: ACCESS_SESSION_MS / 60_000
    }
  };
}

export function registerMenuRoutes(app, { consumeCriticalAuthorization } = {}) {
  app.get("/v1/keymaster/menus", requireKeymaster, async (req, res, next) => {
    try {
      const q = cleanText(req.query?.q, 100).replace(/[%_]/g, "");
      const status = String(req.query?.status || "").toUpperCase();
      if (status && !["ACTIVE", "SUSPENDED"].includes(status)) {
        return sendError(res, 400, "INVALID_STATUS", "Filtro de status inválido.");
      }

      const params = [];
      const clauses = ["m.status <> 'DELETED'"];
      if (q) {
        params.push(q);
        clauses.push(`LOWER(m.name) LIKE '%' || LOWER($${params.length}) || '%'`);
      }
      if (status) {
        params.push(status);
        clauses.push(`m.status = $${params.length}`);
      }

      const { rows } = await pool.query(
        `SELECT
           m.*,
           COUNT(DISTINCT k.id) FILTER (
             WHERE k.kind = 'FREE'
               AND k.status = 'ACTIVE'
               AND (k.expires_at IS NULL OR k.expires_at > NOW())
           )::int AS free_keys,
           COUNT(DISTINCT k.id) FILTER (
             WHERE k.kind = 'VIP' AND k.status = 'ACTIVE'
           )::int AS vip_keys,
           COUNT(DISTINCT s.id) FILTER (
             WHERE s.revoked_at IS NULL AND s.expires_at > NOW()
           )::int AS active_accesses,
           COUNT(DISTINCT s.id) FILTER (
             WHERE s.created_at >= date_trunc('month', NOW())
           )::int AS accesses_month
         FROM managed_menus m
         LEFT JOIN menu_access_keys k ON k.menu_id = m.id
         LEFT JOIN menu_access_sessions s ON s.menu_id = m.id
         WHERE ${clauses.join(" AND ")}
         GROUP BY m.id
         ORDER BY m.updated_at DESC, m.name ASC
         LIMIT 250`,
        params
      );

      res.json({ ok: true, menus: rows.map((row) => mapMenu(row, req)) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menus", requireKeymaster, async (req, res, next) => {
    try {
      const name = cleanText(req.body?.name, 100);
      const sourceUrl = validateMenuSourceUrl(req.body?.sourceUrl);
      if (name.length < 2) return sendError(res, 400, "INVALID_NAME", "Informe um nome válido para o menu.");
      if (!sourceUrl) {
        return sendError(
          res,
          400,
          "INVALID_SOURCE_URL",
          "Use uma URL HTTPS do GitHub apontando para um arquivo .lua."
        );
      }

      const id = randomId();
      let publicId = makeMenuPublicId();
      for (let i = 0; i < 4; i += 1) {
        const exists = await pool.query(`SELECT 1 FROM managed_menus WHERE public_id = $1 LIMIT 1`, [publicId]);
        if (!exists.rowCount) break;
        publicId = makeMenuPublicId();
      }

      const row = await withTransaction(async (client) => {
        const created = (await client.query(
          `INSERT INTO managed_menus
            (id, public_id, name, source_url, status, created_by_session)
           VALUES ($1, $2, $3, $4, 'ACTIVE', $5)
           RETURNING *`,
          [id, publicId, name, sourceUrl, req.keymasterSession.id]
        )).rows[0];
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_CREATED",
          targetKind: "MENU",
          targetId: id,
          metadata: { publicId, name }
        });
        return created;
      });

      res.status(201).json({ ok: true, menu: mapMenu(row, req) });
    } catch (error) {
      if (error?.code === "23505") {
        return sendError(res, 409, "MENU_ID_COLLISION", "Não foi possível gerar um ID único para o menu.");
      }
      next(error);
    }
  });

  app.patch("/v1/keymaster/menus/:id", requireKeymaster, async (req, res, next) => {
    try {
      const current = await getManagedMenu(req.params.id);
      if (!current) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const name = req.body?.name == null ? current.name : cleanText(req.body.name, 100);
      const sourceUrl = req.body?.sourceUrl == null
        ? current.source_url
        : validateMenuSourceUrl(req.body.sourceUrl);
      if (name.length < 2) return sendError(res, 400, "INVALID_NAME", "Informe um nome válido para o menu.");
      if (!sourceUrl) {
        return sendError(
          res,
          400,
          "INVALID_SOURCE_URL",
          "Use uma URL HTTPS do GitHub apontando para um arquivo .lua."
        );
      }

      const updated = await withTransaction(async (client) => {
        const row = (await client.query(
          `UPDATE managed_menus
              SET name = $2, source_url = $3, updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [current.id, name, sourceUrl]
        )).rows[0];
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_UPDATED",
          targetKind: "MENU",
          targetId: current.id,
          metadata: { name, sourceUrlChanged: sourceUrl !== current.source_url }
        });
        return row;
      });

      res.json({ ok: true, menu: mapMenu(updated, req) });
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/keymaster/menus/:id", requireKeymaster, async (req, res, next) => {
    try {
      if (typeof consumeCriticalAuthorization !== "function") {
        return sendError(res, 503, "CRITICAL_AUTH_NOT_CONFIGURED", "Autorização crítica de menu não está configurada.");
      }

      const current = await getManagedMenu(req.params.id);
      if (!current) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const authToken = String(req.headers["x-critical-authorization"] || "");
      const auth = await consumeCriticalAuthorization({
        sessionId: req.keymasterSession.id,
        token: authToken,
        action: "DELETE_MANAGED_MENU",
        targetId: current.id
      });
      if (!auth) {
        return sendError(
          res,
          403,
          "DEV_REAUTH_REQUIRED",
          "Excluir definitivamente um menu exige reautenticação DEV de uso único."
        );
      }

      const deleted = await withTransaction(async (client) => {
        const menu = (await client.query(
          `SELECT id, public_id, name, status
             FROM managed_menus
            WHERE id = $1 AND status <> 'DELETED'
            FOR UPDATE`,
          [current.id]
        )).rows[0];
        if (!menu) return null;

        const sessions = await client.query(
          `UPDATE menu_access_sessions
              SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE menu_id = $1
              AND revoked_at IS NULL
            RETURNING id`,
          [menu.id]
        );

        const keys = await client.query(
          `UPDATE menu_access_keys
              SET status = 'REVOKED',
                  revoked_at = COALESCE(revoked_at, NOW()),
                  suspended_at = NULL,
                  updated_at = NOW()
            WHERE menu_id = $1
              AND status <> 'REVOKED'
            RETURNING id`,
          [menu.id]
        );

        await client.query(
          `UPDATE managed_menus
              SET status = 'DELETED', updated_at = NOW()
            WHERE id = $1`,
          [menu.id]
        );

        await audit(client, {
          actorKind: "DEV",
          actorId: auth.dev_account_id,
          action: "MENU_DELETED",
          targetKind: "MENU",
          targetId: menu.id,
          metadata: {
            publicId: menu.public_id,
            name: menu.name,
            revokedKeys: keys.rowCount,
            revokedSessions: sessions.rowCount,
            keymasterSessionId: req.keymasterSession.id
          }
        });

        return {
          revokedKeys: keys.rowCount,
          revokedSessions: sessions.rowCount
        };
      });

      if (!deleted) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      res.json({ ok: true, ...deleted });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menus/:id/state/:action", requireKeymaster, async (req, res, next) => {
    try {
      const action = String(req.params.action || "").toLowerCase();
      if (!["suspend", "restore"].includes(action)) {
        return sendError(res, 404, "NOT_FOUND", "Ação de menu não encontrada.");
      }

      const current = await getManagedMenu(req.params.id);
      if (!current) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");
      const nextStatus = action === "suspend" ? "SUSPENDED" : "ACTIVE";

      const updated = await withTransaction(async (client) => {
        const row = (await client.query(
          `UPDATE managed_menus SET status = $2, updated_at = NOW() WHERE id = $1 RETURNING *`,
          [current.id, nextStatus]
        )).rows[0];

        if (nextStatus === "SUSPENDED") {
          await client.query(
            `UPDATE menu_access_sessions SET revoked_at = NOW()
              WHERE menu_id = $1 AND revoked_at IS NULL`,
            [current.id]
          );
        }

        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: nextStatus === "SUSPENDED" ? "MENU_SUSPENDED" : "MENU_RESTORED",
          targetKind: "MENU",
          targetId: current.id,
          metadata: { publicId: current.public_id }
        });
        return row;
      });

      res.json({ ok: true, menu: mapMenu(updated, req) });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/keymaster/menus/:id/access-sessions", requireKeymaster, async (req, res, next) => {
    try {
      const menu = await getManagedMenu(req.params.id);
      if (!menu) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const { rows } = await pool.query(
        `SELECT
           s.id,
           s.menu_key_id,
           s.client_label,
           s.created_at,
           s.expires_at,
           s.last_seen_at,
           s.revoked_at,
           k.kind AS key_kind,
           k.key_hint,
           k.note AS key_note,
           k.expires_at AS key_expires_at,
           CASE
             WHEN s.revoked_at IS NULL
              AND s.expires_at > NOW()
              AND m.status = 'ACTIVE'
              AND k.status = 'ACTIVE'
              AND (k.kind = 'VIP' OR k.expires_at IS NULL OR k.expires_at > NOW())
             THEN true
             ELSE false
           END AS active
         FROM menu_access_sessions s
         JOIN managed_menus m ON m.id = s.menu_id
         JOIN menu_access_keys k ON k.id = s.menu_key_id
         WHERE s.menu_id = $1
         ORDER BY s.created_at DESC
         LIMIT 200`,
        [menu.id]
      );

      res.json({ ok: true, sessions: rows });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menus/:id/access-sessions/revoke-all", requireKeymaster, async (req, res, next) => {
    try {
      const menu = await getManagedMenu(req.params.id);
      if (!menu) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const revokedCount = await withTransaction(async (client) => {
        const revoked = await client.query(
          `UPDATE menu_access_sessions
              SET revoked_at = NOW()
            WHERE menu_id = $1
              AND revoked_at IS NULL
              AND expires_at > NOW()
            RETURNING id`,
          [menu.id]
        );
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_ACCESS_SESSIONS_REVOKED_ALL",
          targetKind: "MENU",
          targetId: menu.id,
          metadata: { publicId: menu.public_id, count: revoked.rowCount }
        });
        return revoked.rowCount;
      });

      res.json({ ok: true, revokedCount });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menu-access-sessions/:sessionId/revoke", requireKeymaster, async (req, res, next) => {
    try {
      const sessionId = String(req.params.sessionId || "");
      const result = await withTransaction(async (client) => {
        const current = (await client.query(
          `SELECT
             s.id,
             s.menu_id,
             s.menu_key_id,
             s.client_label,
             s.expires_at,
             s.revoked_at,
             m.public_id
           FROM menu_access_sessions s
           JOIN managed_menus m ON m.id = s.menu_id
           WHERE s.id = $1
             AND m.status <> 'DELETED'
           FOR UPDATE OF s`,
          [sessionId]
        )).rows[0];
        if (!current) return null;
        if (current.revoked_at || new Date(current.expires_at).getTime() <= Date.now()) {
          return { revoked: false };
        }

        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = NOW() WHERE id = $1`,
          [sessionId]
        );
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_ACCESS_SESSION_REVOKED",
          targetKind: "MENU_ACCESS_SESSION",
          targetId: sessionId,
          metadata: {
            menuId: current.menu_id,
            publicId: current.public_id,
            keyId: current.menu_key_id,
            clientLabel: current.client_label
          }
        });
        return { revoked: true };
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Sessão de acesso não encontrada.");
      res.json({ ok: true, revoked: result.revoked });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/keymaster/menus/:id/keys", requireKeymaster, async (req, res, next) => {
    try {
      const menu = await getManagedMenu(req.params.id);
      if (!menu) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const { rows } = await pool.query(
        `SELECT
           id,
           kind,
           status,
           key_hint,
           note,
           expires_at,
           suspended_at,
           use_count,
           last_used_at,
           created_at,
           updated_at,
           revoked_at,
           CASE
             WHEN status <> 'ACTIVE' THEN false
             WHEN kind = 'VIP' THEN true
             WHEN expires_at IS NULL THEN true
             ELSE expires_at > NOW()
           END AS usable
         FROM menu_access_keys
         WHERE menu_id = $1
         ORDER BY created_at DESC
         LIMIT 500`,
        [menu.id]
      );

      res.json({ ok: true, keys: rows });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menus/:id/keys", requireKeymaster, async (req, res, next) => {
    try {
      const menu = await getManagedMenu(req.params.id);
      if (!menu) return sendError(res, 404, "NOT_FOUND", "Menu não encontrado.");

      const kind = String(req.body?.kind || "FREE").toUpperCase();
      if (!["FREE", "VIP"].includes(kind)) {
        return sendError(res, 400, "INVALID_KEY_KIND", "Tipo de chave deve ser FREE ou VIP.");
      }

      const requestedHours = Number(req.body?.durationHours ?? 24);
      const durationHours = Number.isFinite(requestedHours)
        ? Math.min(MAX_FREE_HOURS, Math.max(1, Math.floor(requestedHours)))
        : 24;
      const note = cleanText(req.body?.note, 200) || null;
      const key = makeMenuKey(kind);
      const id = randomId();
      const expiresAt = kind === "FREE"
        ? new Date(Date.now() + durationHours * 60 * 60 * 1000)
        : null;
      const hash = tokenHash(`menu-key:${key}`);
      const now = new Date();

      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO menu_access_keys
            (id, menu_id, kind, status, key_hash, key_hint, note, expires_at, created_by_session)
           VALUES ($1, $2, $3, 'ACTIVE', $4, $5, $6, $7, $8)`,
          [id, menu.id, kind, hash, menuKeyHint(key), note, expiresAt, req.keymasterSession.id]
        );
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_KEY_CREATED",
          targetKind: "MENU_KEY",
          targetId: id,
          metadata: { menuId: menu.id, publicId: menu.public_id, kind, expiresAt }
        });
      });

      res.status(201).json({
        ok: true,
        key: {
          id,
          kind,
          status: "ACTIVE",
          value: key,
          key_hint: menuKeyHint(key),
          note,
          expires_at: expiresAt,
          suspended_at: null,
          use_count: 0,
          last_used_at: null,
          created_at: now,
          updated_at: now,
          revoked_at: null,
          usable: true,
          revealOnce: true
        }
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menu-keys/:keyId/state/:action", requireKeymaster, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId);
      const action = String(req.params.action || "").toLowerCase();
      if (!["suspend", "restore", "revoke", "permanent"].includes(action)) {
        return sendError(res, 404, "NOT_FOUND", "Ação de chave não encontrada.");
      }

      const result = await withTransaction(async (client) => {
        const current = (await client.query(
          `SELECT k.*, m.public_id, m.status AS menu_status
             FROM menu_access_keys k
             JOIN managed_menus m ON m.id = k.menu_id
            WHERE k.id = $1 AND m.status <> 'DELETED'
            FOR UPDATE OF k`,
          [keyId]
        )).rows[0];
        if (!current) return null;
        if (current.status === "REVOKED" && action !== "revoke") return { error: "REVOKED" };

        let status = current.status;
        let kind = current.kind;
        let expiresAt = current.expires_at;
        let revokedAt = current.revoked_at;
        let suspendedAt = current.suspended_at;

        if (action === "suspend") {
          status = "SUSPENDED";
          suspendedAt = new Date();
        } else if (action === "restore") {
          status = "ACTIVE";
          suspendedAt = null;
        } else if (action === "revoke") {
          status = "REVOKED";
          revokedAt = new Date();
        } else if (action === "permanent") {
          kind = "VIP";
          status = "ACTIVE";
          expiresAt = null;
          suspendedAt = null;
        }

        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET status = $2,
                  kind = $3,
                  expires_at = $4,
                  revoked_at = $5,
                  suspended_at = $6,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING
              id, kind, status, key_hint, note, expires_at, suspended_at,
              use_count, last_used_at, created_at, updated_at, revoked_at`,
          [keyId, status, kind, expiresAt, revokedAt, suspendedAt]
        )).rows[0];

        if (["suspend", "revoke"].includes(action)) {
          await client.query(
            `UPDATE menu_access_sessions SET revoked_at = NOW()
              WHERE menu_key_id = $1 AND revoked_at IS NULL`,
            [keyId]
          );
        }

        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: `MENU_KEY_${action.toUpperCase()}`,
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: { menuId: current.menu_id, publicId: current.public_id }
        });
        return { updated };
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "REVOKED") {
        return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser reativada.");
      }
      res.json({ ok: true, key: result.updated });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/menu-keys/:keyId/duration", requireKeymaster, async (req, res, next) => {
    try {
      const keyId = String(req.params.keyId);
      const hoursInput = Number(req.body?.durationHours);
      if (!Number.isFinite(hoursInput)) {
        return sendError(res, 400, "INVALID_DURATION", "Informe a duração FREE em horas.");
      }
      const durationHours = Math.min(MAX_FREE_HOURS, Math.max(1, Math.floor(hoursInput)));
      const expiresAt = new Date(Date.now() + durationHours * 60 * 60 * 1000);

      const result = await withTransaction(async (client) => {
        const current = (await client.query(
          `SELECT k.*, m.public_id
             FROM menu_access_keys k
             JOIN managed_menus m ON m.id = k.menu_id
            WHERE k.id = $1 AND m.status <> 'DELETED'
            FOR UPDATE OF k`,
          [keyId]
        )).rows[0];
        if (!current) return null;
        if (current.status === "REVOKED") return { error: "REVOKED" };
        if (current.kind !== "FREE") return { error: "NOT_FREE" };

        const updated = (await client.query(
          `UPDATE menu_access_keys
              SET expires_at = $2, updated_at = NOW()
            WHERE id = $1
            RETURNING
              id, kind, status, key_hint, note, expires_at, suspended_at,
              use_count, last_used_at, created_at, updated_at, revoked_at`,
          [keyId, expiresAt]
        )).rows[0];

        await client.query(
          `UPDATE menu_access_sessions SET revoked_at = NOW()
            WHERE menu_key_id = $1 AND revoked_at IS NULL`,
          [keyId]
        );
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "MENU_KEY_DURATION_CHANGED",
          targetKind: "MENU_KEY",
          targetId: keyId,
          metadata: { menuId: current.menu_id, publicId: current.public_id, durationHours, expiresAt }
        });
        return { updated };
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada.");
      if (result.error === "REVOKED") {
        return sendError(res, 409, "KEY_REVOKED", "Uma chave revogada não pode ser alterada.");
      }
      if (result.error === "NOT_FREE") {
        return sendError(res, 409, "KEY_NOT_FREE", "Somente chaves FREE possuem duração configurável.");
      }
      res.json({ ok: true, key: result.updated });
    } catch (error) {
      next(error);
    }
  });

  app.get("/l/:publicId", async (req, res, next) => {
    try {
      const menu = (await pool.query(
        `SELECT public_id, name, status
           FROM managed_menus
          WHERE public_id = $1 AND status <> 'DELETED'
          LIMIT 1`,
        [String(req.params.publicId)]
      )).rows[0];

      if (!menu) return sendError(res, 404, "MENU_NOT_FOUND", "Menu não encontrado.");
      if (menu.status !== "ACTIVE") {
        return sendError(res, 403, "MENU_SUSPENDED", "Este menu está suspenso.");
      }
      return res.json(publicDescriptor(req, menu));
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/menu-access/validate", async (req, res, next) => {
    try {
      const publicId = cleanText(req.body?.menuId, 80);
      const key = String(req.body?.key || "").trim();
      const clientLabel = cleanText(req.body?.clientLabel, 120) || null;
      if (!publicId || !key || key.length > 300) {
        return sendError(res, 400, "INVALID_REQUEST", "Menu e chave são obrigatórios.");
      }
      if (!publicAttemptAllowed(req, publicId)) {
        return sendError(res, 429, "TOO_MANY_ATTEMPTS", "Muitas tentativas. Aguarde um minuto.");
      }

      const menu = (await pool.query(
        `SELECT id, public_id, name, status
           FROM managed_menus
          WHERE public_id = $1 AND status <> 'DELETED'
          LIMIT 1`,
        [publicId]
      )).rows[0];
      if (!menu) return sendError(res, 404, "MENU_NOT_FOUND", "Menu não encontrado.");
      if (menu.status !== "ACTIVE") {
        return sendError(res, 403, "MENU_SUSPENDED", "Este menu está suspenso.");
      }

      const hash = tokenHash(`menu-key:${key}`);
      const menuKey = (await pool.query(
        `SELECT id, menu_id, kind, status, expires_at
           FROM menu_access_keys
          WHERE menu_id = $1 AND key_hash = $2
          LIMIT 1`,
        [menu.id, hash]
      )).rows[0];
      if (!menuKey || menuKey.status !== "ACTIVE") {
        return sendError(res, 401, "INVALID_MENU_KEY", "Chave inválida ou indisponível.");
      }

      const now = Date.now();
      if (
        menuKey.kind === "FREE" &&
        menuKey.expires_at &&
        new Date(menuKey.expires_at).getTime() <= now
      ) {
        return sendError(
          res,
          403,
          "MENU_KEY_EXPIRED",
          "Esta chave FREE expirou.",
          { expiresAt: menuKey.expires_at }
        );
      }

      let ttl = ACCESS_SESSION_MS;
      if (menuKey.kind === "FREE" && menuKey.expires_at) {
        ttl = Math.min(ttl, Math.max(1_000, new Date(menuKey.expires_at).getTime() - now));
      }

      const token = randomToken(40);
      const sessionId = randomId();
      const expiresAt = new Date(now + ttl);
      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO menu_access_sessions
            (id, menu_id, menu_key_id, token_hash, client_label, expires_at)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [sessionId, menu.id, menuKey.id, tokenHash(`menu-access:${token}`), clientLabel, expiresAt]
        );
        await client.query(
          `UPDATE menu_access_keys
              SET use_count = use_count + 1,
                  last_used_at = NOW(),
                  updated_at = NOW()
            WHERE id = $1`,
          [menuKey.id]
        );
      });

      res.json({
        ok: true,
        token,
        expiresAt,
        keyType: menuKey.kind,
        keyExpiresAt: menuKey.expires_at,
        menu: { id: menu.public_id, name: menu.name }
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/menu-access/:publicId/manifest", async (req, res, next) => {
    try {
      const auth = String(req.headers.authorization || "");
      const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
      if (!token) return sendError(res, 401, "UNAUTHORIZED", "Token de acesso ausente.");

      const hash = tokenHash(`menu-access:${token}`);
      const { rows } = await pool.query(
        `SELECT
           s.id AS session_id,
           s.expires_at AS access_expires_at,
           m.public_id,
           m.name,
           m.source_url,
           k.kind AS key_kind,
           k.expires_at AS key_expires_at
         FROM menu_access_sessions s
         JOIN managed_menus m ON m.id = s.menu_id
         JOIN menu_access_keys k ON k.id = s.menu_key_id
         WHERE s.token_hash = $1
           AND m.public_id = $2
           AND s.revoked_at IS NULL
           AND s.expires_at > NOW()
           AND m.status = 'ACTIVE'
           AND k.status = 'ACTIVE'
           AND (k.kind = 'VIP' OR k.expires_at IS NULL OR k.expires_at > NOW())
         LIMIT 1`,
        [hash, String(req.params.publicId)]
      );

      const row = rows[0];
      if (!row) {
        return sendError(res, 401, "ACCESS_INVALID", "Acesso inválido, expirado ou revogado.");
      }

      await pool.query(
        `UPDATE menu_access_sessions SET last_seen_at = NOW() WHERE id = $1`,
        [row.session_id]
      );

      res.json({
        ok: true,
        menu: {
          id: row.public_id,
          name: row.name,
          sourceUrl: row.source_url
        },
        access: {
          expiresAt: row.access_expires_at,
          keyType: row.key_kind,
          keyExpiresAt: row.key_expires_at
        }
      });
    } catch (error) {
      next(error);
    }
  });
}
