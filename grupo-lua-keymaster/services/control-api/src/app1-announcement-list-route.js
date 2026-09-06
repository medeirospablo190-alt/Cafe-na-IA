import express from "express";
import { pool } from "./db.js";
import { getApp1FullSession, sendApp1FeatureError } from "./app1-feature-auth.js";

/**
 * Instala a listagem completa de avisos ativos da Home sem acoplar a tela ao
 * feed Social, que mantém seu próprio limite curto de destaques.
 */
export function installApp1AnnouncementListRoute() {
  const originalListen = express.application.listen;
  if (originalListen.__grupoLuaAnnouncementListHook) return;

  function listenWithAnnouncementListRoute(...args) {
    if (!this.locals.grupoLuaAnnouncementListRouteInstalled) {
      this.locals.grupoLuaAnnouncementListRouteInstalled = true;
      this.get("/v1/app1/social/announcements", async (req, res) => {
        try {
          const session = await getApp1FullSession(req);
          if (!session) {
            return sendApp1FeatureError(
              res,
              401,
              "UNAUTHORIZED",
              "Sessão FULL inválida, expirada ou incompatível com este dispositivo."
            );
          }

          const { rows } = await pool.query(
            `SELECT g.id, g.text_content, g.created_at, g.expires_at,
                    a.public_profile_id, a.public_name, a.role
               FROM app1_global_announcements g
               JOIN app1_accounts a ON a.id = g.actor_account_id
              WHERE g.expires_at > NOW()
                AND a.status = 'ACTIVE'
              ORDER BY g.created_at DESC, g.id DESC
              LIMIT 100`
          );

          return res.json({
            ok: true,
            announcements: rows.map((row) => ({
              id: row.id,
              text: row.text_content,
              createdAt: row.created_at,
              expiresAt: row.expires_at,
              author: {
                profileId: row.public_profile_id || null,
                publicName: row.public_name || "DEV",
                role: "DEV"
              }
            }))
          });
        } catch (error) {
          console.error("APP1_ANNOUNCEMENT_LIST_ERROR", error?.stack || error);
          return sendApp1FeatureError(res, 500, "INTERNAL_ERROR", "Não foi possível carregar os avisos agora.");
        }
      });
    }
    return originalListen.apply(this, args);
  }

  listenWithAnnouncementListRoute.__grupoLuaAnnouncementListHook = true;
  express.application.listen = listenWithAnnouncementListRoute;
}
