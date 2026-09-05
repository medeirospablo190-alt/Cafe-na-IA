import crypto from "node:crypto";
import { pool, withTransaction } from "./db.js";
import { decryptStoredSecret, randomId, randomToken, tokenHash } from "./security.js";

const SOURCE_TICKET_MS = 90 * 1000;

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

function deviceHash(deviceId) {
  return tokenHash(`menu-device:${deviceId}`);
}

function menuSourcePurpose(menuId) {
  return `menu-source:${String(menuId || "")}`;
}

function baseUrl(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");
  return configured || `${req.protocol}://${req.get("host")}`;
}

async function restoreElapsedTimedSuspensions() {
  await pool.query(
    `UPDATE managed_menus
        SET status = 'ACTIVE', suspended_until = NULL, updated_at = NOW()
      WHERE status = 'SUSPENDED'
        AND suspended_until IS NOT NULL
        AND suspended_until <= NOW()`
  );
}

export function registerMenuInlineSourceRoutes(app) {
  // Garante que uma suspensão temporária expire sozinha, mesmo se nenhum ADM
  // abrir o App 1 antes do próximo uso do loader.
  app.use("/v1/menu-access", async (_req, _res, next) => {
    try {
      await restoreElapsedTimedSuspensions();
      next();
    } catch (error) {
      next(error);
    }
  });

  // Intercepta apenas menus com fonte privada. Para REMOTE_URL, chama next()
  // e deixa a implementação V2 já existente responder normalmente.
  app.get("/v1/menu-access/:publicId/manifest", async (req, res, next) => {
    try {
      const sourceInfo = (await pool.query(
        `SELECT id, source_kind
           FROM managed_menus
          WHERE public_id = $1 AND status <> 'DELETED'
          LIMIT 1`,
        [String(req.params.publicId || "")]
      )).rows[0];
      if (!sourceInfo || sourceInfo.source_kind !== "INLINE_ENCRYPTED") return next();

      const auth = String(req.headers.authorization || "");
      const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
      const deviceId = String(req.headers["x-menu-device-id"] || "").trim().slice(0, 300);
      if (!token) return sendError(res, 401, "UNAUTHORIZED", "Token de acesso ausente.");
      if (!deviceId) return sendError(res, 401, "DEVICE_ID_REQUIRED", "Identificação do aparelho ausente.");

      const sessionHash = tokenHash(`menu-access:${token}`);
      const dHash = deviceHash(deviceId);
      const row = (await pool.query(
        `SELECT
           s.id AS session_id,
           s.expires_at AS access_expires_at,
           s.device_hash,
           m.id AS menu_id,
           m.public_id,
           m.name,
           m.status AS menu_status,
           m.source_kind,
           k.kind AS key_kind,
           k.status AS key_status,
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
           AND k.deleted_at IS NULL
           AND k.access_state = 'ACTIVE'
           AND (k.access_until IS NULL OR k.access_until > NOW())
         LIMIT 1`,
        [sessionHash, String(req.params.publicId || "")]
      )).rows[0];

      if (!row || !row.device_hash || !row.bound_device_hash) {
        return sendError(res, 401, "ACCESS_INVALID", "Acesso inválido, expirado ou revogado.");
      }
      if (!safeEqual(row.device_hash, dHash) || !safeEqual(row.bound_device_hash, dHash)) {
        return sendError(res, 403, "DEVICE_NOT_AUTHORIZED", "Este acesso pertence a outro aparelho.");
      }

      const ticket = randomToken(48);
      const ticketId = randomId();
      const ticketExpiresAt = new Date(Date.now() + SOURCE_TICKET_MS);
      await withTransaction(async (client) => {
        await client.query(`DELETE FROM menu_source_tickets WHERE expires_at <= NOW()`);
        await client.query(
          `INSERT INTO menu_source_tickets
            (id, menu_id, access_session_id, token_hash, expires_at)
           VALUES ($1, $2, $3, $4, $5)`,
          [ticketId, row.menu_id, row.session_id, tokenHash(`menu-source-ticket:${ticket}`), ticketExpiresAt]
        );
        await client.query(`UPDATE menu_access_sessions SET last_seen_at = NOW() WHERE id = $1`, [row.session_id]);
      });

      const sourceUrl = `${baseUrl(req)}/v1/menu-access/${encodeURIComponent(row.public_id)}/source/${encodeURIComponent(ticket)}`;
      res.set("Cache-Control", "no-store, private");
      return res.json({
        ok: true,
        menu: {
          id: row.public_id,
          name: row.name,
          sourceUrl
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

  app.get("/v1/menu-access/:publicId/source/:ticket", async (req, res, next) => {
    try {
      const ticket = String(req.params.ticket || "");
      if (!ticket || ticket.length > 300) return sendError(res, 401, "SOURCE_TICKET_INVALID", "Tíquete de fonte inválido.");
      const row = await withTransaction(async (client) => {
        const found = (await client.query(
          `SELECT
             t.id AS ticket_id,
             t.expires_at AS ticket_expires_at,
             s.id AS session_id,
             s.expires_at AS access_expires_at,
             m.id AS menu_id,
             m.public_id,
             m.status AS menu_status,
             m.source_kind,
             m.source_ciphertext,
             k.status AS key_status,
             k.deleted_at AS key_deleted_at,
             k.access_state,
             k.access_until
           FROM menu_source_tickets t
           JOIN menu_access_sessions s ON s.id = t.access_session_id
           JOIN managed_menus m ON m.id = t.menu_id
           JOIN menu_access_keys k ON k.id = s.menu_key_id
          WHERE t.token_hash = $1
            AND m.public_id = $2
            AND t.expires_at > NOW()
            AND s.revoked_at IS NULL
            AND s.expires_at > NOW()
            AND m.status = 'ACTIVE'
            AND m.source_kind = 'INLINE_ENCRYPTED'
            AND k.status = 'ACTIVE'
            AND k.deleted_at IS NULL
            AND k.access_state = 'ACTIVE'
            AND (k.access_until IS NULL OR k.access_until > NOW())
          LIMIT 1
          FOR UPDATE OF t`,
          [tokenHash(`menu-source-ticket:${ticket}`), String(req.params.publicId || "")]
        )).rows[0];
        if (!found) return null;
        await client.query(
          `UPDATE menu_source_tickets SET used_at = COALESCE(used_at, NOW()) WHERE id = $1`,
          [found.ticket_id]
        );
        await client.query(`UPDATE menu_access_sessions SET last_seen_at = NOW() WHERE id = $1`, [found.session_id]);
        return found;
      });

      if (!row) return sendError(res, 401, "SOURCE_TICKET_EXPIRED", "Este link temporário de código expirou.");
      const source = decryptStoredSecret(row.source_ciphertext, menuSourcePurpose(row.menu_id));
      if (source == null) return sendError(res, 500, "SOURCE_DECRYPT_FAILED", "Não foi possível recuperar o código deste menu.");

      res.set("Cache-Control", "no-store, private, max-age=0");
      res.set("Pragma", "no-cache");
      res.type("text/plain; charset=utf-8");
      return res.send(source);
    } catch (error) {
      next(error);
    }
  });
}
