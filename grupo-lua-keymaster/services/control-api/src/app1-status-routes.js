import express from "express";
import { pool, withTransaction, audit } from "./db.js";
import { randomId } from "./security.js";
import {
  requireApp1FullSession,
  sendApp1FeatureError
} from "./app1-feature-auth.js";

const STATUS_LIMIT = 16;
const STATUS_BYTES_MAX = 4 * 1024 * 1024;
const STATUS_TTL_HOURS = 24;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);

const imageBody = express.raw({
  type: ["image/jpeg", "image/png", "image/webp"],
  limit: `${STATUS_BYTES_MAX}b`
});

function statusAuthor(row) {
  return {
    profileId: row.public_profile_id || null,
    publicName: row.public_name || "Perfil",
    role: row.role === "DEV" ? "DEV" : "ADM",
    avatarStyle: row.avatar_style || "MOON",
    frameStyle: row.frame_style || "DEFAULT",
    statusText: row.status_text || ""
  };
}

function statusMetadata(row, viewerId) {
  if (!row.status_id) return null;
  return {
    id: row.status_id,
    createdAt: row.status_created_at,
    expiresAt: row.status_expires_at,
    mine: String(row.account_id) === String(viewerId)
  };
}

async function purgeExpiredStatuses(client = pool) {
  await client.query(
    `UPDATE app1_social_statuses
        SET deleted_at = COALESCE(deleted_at, NOW())
      WHERE deleted_at IS NULL
        AND expires_at <= NOW()`
  );
}

export function registerApp1StatusRoutes(app) {
  app.get("/v1/app1/social/statuses", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeExpiredStatuses();
      const viewerId = req.app1FeatureSession.account_id;
      const { rows } = await pool.query(
        `SELECT a.id AS account_id, a.public_profile_id, a.public_name, a.role,
                a.avatar_style, a.frame_style, a.status_text, a.presence_mode,
                s.id AS status_id, s.created_at AS status_created_at,
                s.expires_at AS status_expires_at
           FROM app1_accounts a
           LEFT JOIN LATERAL (
             SELECT st.id, st.created_at, st.expires_at
               FROM app1_social_statuses st
              WHERE st.account_id = a.id
                AND st.deleted_at IS NULL
                AND st.expires_at > NOW()
              ORDER BY st.created_at DESC
              LIMIT 1
           ) s ON TRUE
          WHERE a.status = 'ACTIVE'
            AND a.onboarding_completed_at IS NOT NULL
            AND a.public_name IS NOT NULL
            AND (a.id = $1 OR a.presence_mode = 'VISIBLE')
          ORDER BY
            (a.id = $1) DESC,
            (s.id IS NOT NULL) DESC,
            s.created_at DESC NULLS LAST,
            (a.role = 'DEV') DESC,
            a.public_name ASC
          LIMIT $2`,
        [viewerId, STATUS_LIMIT]
      );

      return res.json({
        ok: true,
        profiles: rows.map((row) => ({
          ...statusAuthor(row),
          mine: String(row.account_id) === String(viewerId),
          activeStatus: statusMetadata(row, viewerId)
        }))
      });
    } catch (error) {
      next(error);
    }
  });

  app.post(
    "/v1/app1/social/statuses",
    requireApp1FullSession,
    imageBody,
    async (req, res, next) => {
      try {
        const accountId = req.app1FeatureSession.account_id;
        const mimeType = String(req.headers["content-type"] || "").split(";")[0].trim().toLowerCase();
        if (!ALLOWED_MIME.has(mimeType)) {
          return sendApp1FeatureError(
            res,
            415,
            "STATUS_IMAGE_TYPE_UNSUPPORTED",
            "Use uma foto JPG, PNG ou WEBP."
          );
        }

        const bytes = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
        if (!bytes.length) {
          return sendApp1FeatureError(res, 400, "STATUS_IMAGE_REQUIRED", "Escolha uma foto para publicar.");
        }
        if (bytes.length > STATUS_BYTES_MAX) {
          return sendApp1FeatureError(res, 413, "STATUS_IMAGE_TOO_LARGE", "A foto do status pode ter no máximo 4 MB.");
        }

        const result = await withTransaction(async (client) => {
          await purgeExpiredStatuses(client);
          await client.query(
            `UPDATE app1_social_statuses
                SET deleted_at = NOW()
              WHERE account_id = $1
                AND deleted_at IS NULL`,
            [accountId]
          );

          const id = randomId();
          const row = (await client.query(
            `INSERT INTO app1_social_statuses
              (id, account_id, mime_type, image_bytes, image_size_bytes, expires_at)
             VALUES ($1, $2, $3, $4, $5, NOW() + ($6 * INTERVAL '1 hour'))
             RETURNING id, created_at, expires_at`,
            [id, accountId, mimeType, bytes, bytes.length, STATUS_TTL_HOURS]
          )).rows[0];

          await audit(client, {
            actorKind: "APP1_ACCOUNT",
            actorId: accountId,
            action: "APP1_SOCIAL_STATUS_CREATED",
            targetKind: "APP1_SOCIAL_STATUS",
            targetId: id,
            metadata: { mimeType, bytes: bytes.length, ttlHours: STATUS_TTL_HOURS }
          });

          return row;
        });

        return res.status(201).json({
          ok: true,
          status: {
            id: result.id,
            createdAt: result.created_at,
            expiresAt: result.expires_at,
            mine: true
          }
        });
      } catch (error) {
        next(error);
      }
    }
  );

  app.get("/v1/app1/social/statuses/:statusId/image", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeExpiredStatuses();
      const viewerId = req.app1FeatureSession.account_id;
      const statusId = String(req.params.statusId || "");
      const row = (await pool.query(
        `SELECT s.mime_type, s.image_bytes,
                a.id AS account_id, a.presence_mode
           FROM app1_social_statuses s
           JOIN app1_accounts a ON a.id = s.account_id
          WHERE s.id = $1
            AND s.deleted_at IS NULL
            AND s.expires_at > NOW()
            AND a.status = 'ACTIVE'
            AND a.onboarding_completed_at IS NOT NULL
            AND (a.id = $2 OR a.presence_mode = 'VISIBLE')
          LIMIT 1`,
        [statusId, viewerId]
      )).rows[0];

      if (!row) {
        return sendApp1FeatureError(res, 404, "STATUS_NOT_FOUND", "Este status não está mais disponível.");
      }

      res.set("Content-Type", row.mime_type);
      res.set("Content-Length", String(row.image_bytes.length));
      res.set("Cache-Control", "private, max-age=120");
      return res.send(row.image_bytes);
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/app1/social/statuses/:statusId", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const statusId = String(req.params.statusId || "");
      const result = await withTransaction(async (client) => {
        const row = (await client.query(
          `UPDATE app1_social_statuses
              SET deleted_at = NOW()
            WHERE id = $1
              AND account_id = $2
              AND deleted_at IS NULL
            RETURNING id`,
          [statusId, accountId]
        )).rows[0];
        if (!row) return null;

        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_SOCIAL_STATUS_DELETED",
          targetKind: "APP1_SOCIAL_STATUS",
          targetId: statusId,
          metadata: {}
        });
        return row;
      });

      if (!result) {
        return sendApp1FeatureError(res, 404, "STATUS_NOT_FOUND", "Este status não existe mais ou não pertence à sua conta.");
      }
      return res.json({ ok: true, deleted: true });
    } catch (error) {
      next(error);
    }
  });
}
