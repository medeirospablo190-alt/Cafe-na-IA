import crypto from "crypto";
import { pool } from "./db.js";
import { tokenHash } from "./security.js";

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

async function getKeymasterSession(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return null;
  const hash = tokenHash(token);
  const { rows } = await pool.query(
    `SELECT id, device_id, expires_at
       FROM keymaster_sessions
      WHERE token_hash = $1
        AND revoked_at IS NULL
        AND expires_at > NOW()
      LIMIT 1`,
    [hash]
  );
  return rows[0] || null;
}

async function requireKeymasterForLockdown(req, res, next) {
  try {
    const session = await getKeymasterSession(req);
    if (!session) return sendError(res, 401, "UNAUTHORIZED", "Sessão Keymaster inválida ou expirada.");
    req.keymasterMenuLockdownSession = session;
    next();
  } catch (error) {
    next(error);
  }
}

async function protectOwnedMenu(req, res, next) {
  try {
    const value = String(req.params.id || "").trim();
    if (!value) return next();
    const row = (await pool.query(
      `SELECT id, public_id, owner_account_id
         FROM managed_menus
        WHERE (id::text = $1 OR public_id = $1)
          AND status <> 'DELETED'
        LIMIT 1`,
      [value]
    )).rows[0];
    if (!row) return next();
    if (!row.owner_account_id) return next();
    return sendError(
      res,
      403,
      "APP1_MENU_MANAGED",
      "Este menu pertence a uma conta do App 1. Edição, suspensão e exclusão devem ser feitas no App 1."
    );
  } catch (error) {
    next(error);
  }
}

export function registerKeymasterMenuManagementLockdown(app) {
  // Evita criar novos menus sem proprietário. O Keymaster continua podendo
  // listar/inspecionar a infraestrutura e manter menus legados sem proprietário.
  app.post("/v1/keymaster/menus", requireKeymasterForLockdown, (_req, res) => {
    return sendError(
      res,
      403,
      "APP1_MENU_CREATION_REQUIRED",
      "Novos menus são cadastrados no App 1 para receber proprietário e fonte protegida."
    );
  });

  app.patch("/v1/keymaster/menus/:id", requireKeymasterForLockdown, protectOwnedMenu);
  app.delete("/v1/keymaster/menus/:id", requireKeymasterForLockdown, protectOwnedMenu);
  app.post("/v1/keymaster/menus/:id/state/:action", requireKeymasterForLockdown, protectOwnedMenu);
}
