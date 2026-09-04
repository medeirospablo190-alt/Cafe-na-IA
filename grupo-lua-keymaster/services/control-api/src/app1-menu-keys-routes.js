import crypto from "node:crypto";
import { pool, withTransaction, audit } from "./db.js";
import {
  decryptStoredSecret,
  encryptStoredSecret,
  randomId,
  tokenHash
} from "./security.js";

const CLAIM_WINDOW_MS = 60_000;
const CLAIM_LIMIT = 12;
const claimAttempts = new Map();

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function safeEqualText(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function getFullSession(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const deviceToken = String(req.headers["x-app1-device-token"] || "").slice(0, 500);
  if (!token || !deviceToken) return null;

  const hash = tokenHash(`app1:${token}`);
  const { rows } = await pool.query(
    `SELECT s.id AS session_id, s.account_id, s.app1_device_id, s.session_kind,
            a.status AS account_status, d.status AS device_status, d.device_token_hash
       FROM app1_sessions s
       JOIN app1_accounts a ON a.id = s.account_id
       JOIN app1_devices d ON d.id = s.app1_device_id
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > NOW()
      LIMIT 1`,
    [hash]
  );
  const row = rows[0];
  if (!row || row.account_status !== "ACTIVE" || row.device_status !== "ACTIVE" || row.session_kind !== "FULL") {
    return null;
  }
  const supplied = tokenHash(`app1-device:${deviceToken}`);
  return safeEqualText(supplied, row.device_token_hash) ? row : null;
}

async function requireFullSession(req, res, next) {
  try {
    const session = await getFullSession(req);
    if (!session) {
      return sendError(res, 401, "UNAUTHORIZED", "Sessão FULL inválida, expirada ou incompatível com este dispositivo.");
    }
    req.app1MenuKeySession = session;
    next();
  } catch (error) {
    next(error);
  }
}

function claimAllowed(accountId) {
  const now = Date.now();
  const current = claimAttempts.get(accountId);
  if (!current || current.resetAt <= now) {
    claimAttempts.set(accountId, { count: 1, resetAt: now + CLAIM_WINDOW_MS });
    return true;
  }
  current.count += 1;
  return current.count <= CLAIM_LIMIT;
}

function normalizeMenuPublicId(value) {
  const text = String(value || "").trim().slice(0, 2_000);
  if (!text) return "";
  if (/^menu_[A-Za-z0-9_-]+$/.test(text)) return text.slice(0, 100);
  try {
    const url = new URL(text);
    const parts = url.pathname.split("/").filter(Boolean);
    const index = parts.indexOf("l");
    if (index >= 0 && parts[index + 1] && /^menu_[A-Za-z0-9_-]+$/.test(parts[index + 1])) {
      return parts[index + 1].slice(0, 100);
    }
  } catch {
    // Não é URL; o erro final será INVALID_MENU_REFERENCE.
  }
  return "";
}

function baseUrl(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");
  return configured || `${req.protocol}://${req.get("host")}`;
}

function effectiveStatus(row) {
  if (row.menu_status !== "ACTIVE") return "MENU_SUSPENDED";
  if (row.key_status === "REVOKED") return "REVOKED";
  if (row.key_status === "SUSPENDED") return "SUSPENDED";
  if (row.kind === "FREE" && row.expires_at && new Date(row.expires_at).getTime() <= Date.now()) {
    return "EXPIRED";
  }
  return "ACTIVE";
}

function mapBinding(row, req) {
  const status = effectiveStatus(row);
  return {
    bindingId: row.binding_id,
    keyId: row.key_id,
    kind: row.kind,
    status,
    usable: status === "ACTIVE",
    keyHint: row.key_hint,
    note: row.note || null,
    expiresAt: row.expires_at || null,
    useCount: Number(row.use_count || 0),
    lastUsedAt: row.last_used_at || null,
    addedAt: row.binding_created_at,
    lastRevealedAt: row.last_revealed_at || null,
    menu: {
      id: row.menu_id,
      publicId: row.public_id,
      name: row.menu_name,
      status: row.menu_status,
      accessUrl: `${baseUrl(req)}/l/${encodeURIComponent(row.public_id)}`
    }
  };
}

async function getBinding(accountId, bindingId, client = pool) {
  return (await client.query(
    `SELECT
       b.id AS binding_id,
       b.key_ciphertext,
       b.key_hint,
       b.created_at AS binding_created_at,
       b.last_revealed_at,
       k.id AS key_id,
       k.kind,
       k.status AS key_status,
       k.note,
       k.expires_at,
       k.use_count,
       k.last_used_at,
       m.id AS menu_id,
       m.public_id,
       m.name AS menu_name,
       m.status AS menu_status
     FROM app1_menu_key_bindings b
     JOIN menu_access_keys k ON k.id = b.menu_key_id
     JOIN managed_menus m ON m.id = k.menu_id
    WHERE b.id = $1
      AND b.account_id = $2
      AND m.status <> 'DELETED'
    LIMIT 1`,
    [bindingId, accountId]
  )).rows[0] || null;
}

export function registerApp1MenuKeyRoutes(app) {
  app.get("/v1/app1/keys", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1MenuKeySession.account_id;
      const { rows } = await pool.query(
        `SELECT
           b.id AS binding_id,
           b.key_hint,
           b.created_at AS binding_created_at,
           b.last_revealed_at,
           k.id AS key_id,
           k.kind,
           k.status AS key_status,
           k.note,
           k.expires_at,
           k.use_count,
           k.last_used_at,
           m.id AS menu_id,
           m.public_id,
           m.name AS menu_name,
           m.status AS menu_status
         FROM app1_menu_key_bindings b
         JOIN menu_access_keys k ON k.id = b.menu_key_id
         JOIN managed_menus m ON m.id = k.menu_id
        WHERE b.account_id = $1
          AND m.status <> 'DELETED'
        ORDER BY b.created_at DESC, b.id DESC
        LIMIT 500`,
        [accountId]
      );
      return res.json({ ok: true, keys: rows.map((row) => mapBinding(row, req)) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/keys/claim", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1MenuKeySession.account_id;
      if (!claimAllowed(accountId)) {
        return sendError(res, 429, "TOO_MANY_ATTEMPTS", "Muitas tentativas de adicionar chave. Aguarde um minuto.");
      }

      const publicId = normalizeMenuPublicId(req.body?.menuId ?? req.body?.menu);
      const key = String(req.body?.key || "").trim();
      if (!publicId) {
        return sendError(res, 400, "INVALID_MENU_REFERENCE", "Informe o ID do menu ou o link de acesso do menu.");
      }
      if (!key || key.length > 300) {
        return sendError(res, 400, "INVALID_MENU_KEY", "Informe uma chave FREE/VIP válida.");
      }

      const menu = (await pool.query(
        `SELECT id, public_id, name, status
           FROM managed_menus
          WHERE public_id = $1 AND status <> 'DELETED'
          LIMIT 1`,
        [publicId]
      )).rows[0];
      if (!menu) return sendError(res, 404, "MENU_NOT_FOUND", "Menu não encontrado.");
      if (menu.status !== "ACTIVE") return sendError(res, 403, "MENU_SUSPENDED", "Este menu está suspenso.");

      const hash = tokenHash(`menu-key:${key}`);
      const menuKey = (await pool.query(
        `SELECT id, menu_id, kind, status, key_hint, note, expires_at, use_count, last_used_at
           FROM menu_access_keys
          WHERE menu_id = $1 AND key_hash = $2
          LIMIT 1`,
        [menu.id, hash]
      )).rows[0];
      if (!menuKey || menuKey.status !== "ACTIVE") {
        return sendError(res, 401, "INVALID_MENU_KEY", "Chave inválida ou indisponível.");
      }
      if (menuKey.kind === "FREE" && menuKey.expires_at && new Date(menuKey.expires_at).getTime() <= Date.now()) {
        return sendError(res, 403, "MENU_KEY_EXPIRED", "Esta chave FREE expirou.", { expiresAt: menuKey.expires_at });
      }

      const stored = await withTransaction(async (client) => {
        const existing = (await client.query(
          `SELECT id FROM app1_menu_key_bindings
            WHERE account_id = $1 AND menu_key_id = $2
            FOR UPDATE`,
          [accountId, menuKey.id]
        )).rows[0];
        const bindingId = existing?.id || randomId();
        const keyCiphertext = encryptStoredSecret(key, `app1-menu-key-binding:${bindingId}`);

        if (existing) {
          await client.query(
            `UPDATE app1_menu_key_bindings
                SET key_ciphertext = $3,
                    key_hint = $4,
                    updated_at = NOW()
              WHERE id = $1 AND account_id = $2`,
            [bindingId, accountId, keyCiphertext, menuKey.key_hint]
          );
        } else {
          await client.query(
            `INSERT INTO app1_menu_key_bindings
              (id, account_id, menu_key_id, key_ciphertext, key_hint)
             VALUES ($1, $2, $3, $4, $5)`,
            [bindingId, accountId, menuKey.id, keyCiphertext, menuKey.key_hint]
          );
        }

        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: existing ? "APP1_MENU_KEY_REFRESHED" : "APP1_MENU_KEY_ADDED",
          targetKind: "APP1_MENU_KEY_BINDING",
          targetId: bindingId,
          metadata: {
            menuId: menu.id,
            publicId: menu.public_id,
            menuKeyId: menuKey.id,
            kind: menuKey.kind
          }
        });
        return { bindingId, created: !existing };
      });

      const row = await getBinding(accountId, stored.bindingId);
      if (!row) {
        return sendError(res, 409, "KEY_BINDING_UNAVAILABLE", "A chave foi alterada durante a operação. Atualize e tente novamente.");
      }
      return res.status(stored.created ? 201 : 200).json({
        ok: true,
        created: stored.created,
        key: mapBinding(row, req)
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/keys/:bindingId/reveal", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1MenuKeySession.account_id;
      const bindingId = String(req.params.bindingId || "");
      const result = await withTransaction(async (client) => {
        const row = await getBinding(accountId, bindingId, client);
        if (!row) return null;
        const status = effectiveStatus(row);
        if (status !== "ACTIVE") return { unavailable: true, status };
        const key = decryptStoredSecret(row.key_ciphertext, `app1-menu-key-binding:${row.binding_id}`);
        if (!key) return { decryptFailed: true };
        await client.query(
          `UPDATE app1_menu_key_bindings SET last_revealed_at = NOW(), updated_at = NOW() WHERE id = $1`,
          [row.binding_id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_MENU_KEY_REVEALED",
          targetKind: "APP1_MENU_KEY_BINDING",
          targetId: row.binding_id,
          metadata: {
            menuId: row.menu_id,
            publicId: row.public_id,
            menuKeyId: row.key_id,
            status
          }
        });
        return { key, keyHint: row.key_hint };
      });
      if (!result) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada nesta conta.");
      if (result.unavailable) {
        return sendError(res, 409, "KEY_NOT_USABLE", "Esta chave não está ativa e não pode ser revelada agora.", { status: result.status });
      }
      if (result.decryptFailed) return sendError(res, 500, "KEY_DECRYPT_FAILED", "A chave protegida não pôde ser aberta.");
      return res.json({ ok: true, key: result.key, keyHint: result.keyHint });
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/app1/keys/:bindingId", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1MenuKeySession.account_id;
      const bindingId = String(req.params.bindingId || "");
      const deleted = await withTransaction(async (client) => {
        const row = (await client.query(
          `DELETE FROM app1_menu_key_bindings
            WHERE id = $1 AND account_id = $2
            RETURNING id, menu_key_id`,
          [bindingId, accountId]
        )).rows[0];
        if (!row) return null;
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_MENU_KEY_REMOVED",
          targetKind: "APP1_MENU_KEY_BINDING",
          targetId: bindingId,
          metadata: { menuKeyId: row.menu_key_id }
        });
        return row;
      });
      if (!deleted) return sendError(res, 404, "NOT_FOUND", "Chave não encontrada nesta conta.");
      return res.json({ ok: true });
    } catch (error) {
      next(error);
    }
  });
}
