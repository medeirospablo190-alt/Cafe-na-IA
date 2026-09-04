import crypto from "node:crypto";
import { pool, withTransaction, audit } from "./db.js";
import { tokenHash } from "./security.js";

function sendError(res, status, code, message) {
  return res.status(status).json({ ok: false, code, message });
}

function safeEqualText(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function getBoundSession(req) {
  const auth = String(req.headers.authorization || "");
  const sessionToken = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const deviceToken = String(req.headers["x-app1-device-token"] || "").slice(0, 500);
  if (!sessionToken || !deviceToken) return null;

  const { rows } = await pool.query(
    `SELECT s.id, s.account_id, d.device_token_hash
       FROM app1_sessions s
       JOIN app1_devices d ON d.id = s.app1_device_id
       JOIN app1_accounts a ON a.id = s.account_id
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > NOW()
        AND d.status = 'ACTIVE'
        AND a.status <> 'DELETED'
      LIMIT 1`,
    [tokenHash(`app1:${sessionToken}`)]
  );

  const row = rows[0];
  if (!row) return null;
  const suppliedDeviceHash = tokenHash(`app1-device:${deviceToken}`);
  return safeEqualText(suppliedDeviceHash, row.device_token_hash) ? row : null;
}

export function registerApp1SessionControlRoutes(app) {
  app.post("/v1/app1/logout", async (req, res, next) => {
    try {
      const session = await getBoundSession(req);
      if (!session) {
        return sendError(
          res,
          401,
          "UNAUTHORIZED",
          "Sessão inválida, expirada ou incompatível com este dispositivo."
        );
      }

      const revoked = await withTransaction(async (client) => {
        const result = await client.query(
          `UPDATE app1_sessions
              SET revoked_at = NOW()
            WHERE id = $1
              AND account_id = $2
              AND revoked_at IS NULL
            RETURNING id`,
          [session.id, session.account_id]
        );
        if (!result.rowCount) return false;
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "APP1_SESSION_LOGOUT",
          targetKind: "APP1_SESSION",
          targetId: session.id,
          metadata: { revokedByOwner: true }
        });
        return true;
      });

      if (!revoked) {
        return sendError(res, 409, "SESSION_ALREADY_REVOKED", "A sessão já foi encerrada.");
      }
      return res.json({ ok: true });
    } catch (error) {
      next(error);
    }
  });
}
