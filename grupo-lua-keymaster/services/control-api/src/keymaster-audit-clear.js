import express from "express";
import { pool, withTransaction } from "./db.js";
import { tokenHash } from "./security.js";

async function getKeymasterSession(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return null;
  const hash = tokenHash(token);
  const { rows } = await pool.query(
    `SELECT s.id
       FROM keymaster_sessions s
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > NOW()
      LIMIT 1`,
    [hash]
  );
  return rows[0] || null;
}

function sendError(res, status, code, message) {
  return res.status(status).json({ ok: false, code, message });
}

/**
 * server.js keeps its Express app private. Bootstrap already owns the startup
 * hooks, so this installs one route immediately before app.listen() starts the
 * server. The handler is self-contained because it is registered after the
 * central error middleware.
 */
export function installKeymasterAuditClearRoute() {
  const originalListen = express.application.listen;
  if (originalListen.__grupoLuaAuditHook) return;

  function listenWithAuditRoute(...args) {
    if (!this.locals.grupoLuaAuditClearRouteInstalled) {
      this.locals.grupoLuaAuditClearRouteInstalled = true;
      this.delete("/v1/keymaster/audit", async (req, res) => {
        try {
          const session = await getKeymasterSession(req);
          if (!session) {
            return sendError(res, 401, "UNAUTHORIZED", "Sessão Keymaster inválida ou expirada.");
          }

          const result = await withTransaction(async (client) => {
            // app1_login_attempts is the detailed security-attempt history that
            // is displayed from account security. audit_events is the global
            // Keymaster history. Clearing history intentionally does not write
            // a new audit event, otherwise the list would never become empty.
            const attempts = await client.query(`DELETE FROM app1_login_attempts`);
            const auditEvents = await client.query(`DELETE FROM audit_events`);
            return {
              auditDeleted: Number(auditEvents.rowCount || 0),
              loginAttemptsDeleted: Number(attempts.rowCount || 0)
            };
          });

          return res.json({ ok: true, ...result });
        } catch (error) {
          console.error("KEYMASTER_AUDIT_CLEAR_ERROR", error?.stack || error);
          return sendError(res, 500, "INTERNAL_ERROR", "Não foi possível limpar o histórico do servidor.");
        }
      });
    }
    return originalListen.apply(this, args);
  }

  listenWithAuditRoute.__grupoLuaAuditHook = true;
  express.application.listen = listenWithAuditRoute;
}
