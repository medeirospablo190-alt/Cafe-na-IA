import express from "express";
import { audit, withTransaction } from "./db.js";
import { getApp1FullSession, sendApp1FeatureError } from "./app1-feature-auth.js";

function cleanMultiline(value, max) {
  return String(value ?? "").normalize("NFKC").trim().slice(0, max);
}

/**
 * server.js keeps its Express app private. Bootstrap owns startup hooks, so
 * this installs the announcement edit route immediately before app.listen().
 * The handler is self-contained because routes installed at this stage sit
 * after the central error middleware.
 */
export function installApp1AnnouncementEditRoute() {
  const originalListen = express.application.listen;
  if (originalListen.__grupoLuaAnnouncementEditHook) return;

  function listenWithAnnouncementEditRoute(...args) {
    if (!this.locals.grupoLuaAnnouncementEditRouteInstalled) {
      this.locals.grupoLuaAnnouncementEditRouteInstalled = true;
      this.patch("/v1/app1/social/announcements/:announcementId", async (req, res) => {
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
          if (session.role !== "DEV") {
            return sendApp1FeatureError(res, 403, "DEV_REQUIRED", "Somente DEV pode editar anúncio global.");
          }

          const announcementId = String(req.params.announcementId || "").trim().slice(0, 160);
          const text = cleanMultiline(req.body?.text, 1000);
          if (!announcementId) {
            return sendApp1FeatureError(res, 400, "ANNOUNCEMENT_ID_REQUIRED", "Informe o anúncio que será editado.");
          }
          if (!text) {
            return sendApp1FeatureError(res, 400, "ANNOUNCEMENT_REQUIRED", "Escreva a mensagem global.");
          }

          const row = await withTransaction(async (client) => {
            const updated = (await client.query(
              `UPDATE app1_global_announcements
                  SET text_content = $2
                WHERE id = $1
                  AND expires_at > NOW()
                RETURNING id, text_content, created_at, expires_at`,
              [announcementId, text]
            )).rows[0] || null;
            if (!updated) return null;

            await audit(client, {
              actorKind: "APP1_ACCOUNT",
              actorId: session.account_id,
              action: "APP1_GLOBAL_ANNOUNCEMENT_UPDATED",
              targetKind: "APP1_ANNOUNCEMENT",
              targetId: announcementId,
              metadata: { expiresAt: updated.expires_at }
            });
            return updated;
          });

          if (!row) {
            return sendApp1FeatureError(res, 404, "ANNOUNCEMENT_NOT_FOUND", "Anúncio não encontrado ou já expirado.");
          }

          return res.json({
            ok: true,
            announcement: {
              id: row.id,
              text: row.text_content,
              createdAt: row.created_at,
              expiresAt: row.expires_at
            }
          });
        } catch (error) {
          console.error("APP1_ANNOUNCEMENT_EDIT_ERROR", error?.stack || error);
          return sendApp1FeatureError(res, 500, "INTERNAL_ERROR", "Não foi possível editar o anúncio agora.");
        }
      });
    }
    return originalListen.apply(this, args);
  }

  listenWithAnnouncementEditRoute.__grupoLuaAnnouncementEditHook = true;
  express.application.listen = listenWithAnnouncementEditRoute;
}
