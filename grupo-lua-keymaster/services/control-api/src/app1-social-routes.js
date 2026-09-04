import { pool, withTransaction, audit } from "./db.js";
import { randomId } from "./security.js";
import {
  publicProfileFromRow,
  requireApp1FullSession,
  sendApp1FeatureError
} from "./app1-feature-auth.js";

const FEED_LIMIT_DEFAULT = 30;
const FEED_LIMIT_MAX = 60;
const COMMENT_LIMIT_DEFAULT = 30;
const COMMENT_LIMIT_MAX = 60;
const PROFILE_LIMIT_MAX = 30;
const PROFILE_SEARCH_WINDOW_MS = 60_000;
const PROFILE_SEARCH_LIMIT = 30;
const profileSearchWindows = new Map();
let profileSearchSweepAt = 0;

function boundedInt(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function cleanText(value, max) {
  return String(value ?? "").normalize("NFKC").trim().replace(/\s+/g, " ").slice(0, max);
}

function cleanMultiline(value, max) {
  return String(value ?? "").normalize("NFKC").trim().slice(0, max);
}

function searchAllowed(accountId) {
  const now = Date.now();
  if (now >= profileSearchSweepAt) {
    profileSearchSweepAt = now + PROFILE_SEARCH_WINDOW_MS;
    for (const [key, value] of profileSearchWindows) {
      if (value.resetAt <= now) profileSearchWindows.delete(key);
    }
  }
  const key = String(accountId);
  const current = profileSearchWindows.get(key);
  if (!current || current.resetAt <= now) {
    profileSearchWindows.set(key, { count: 1, resetAt: now + PROFILE_SEARCH_WINDOW_MS });
    return true;
  }
  current.count += 1;
  return current.count <= PROFILE_SEARCH_LIMIT;
}

async function purgeSocial(client = pool) {
  await client.query(`DELETE FROM app1_social_notifications WHERE expires_at <= NOW()`);
  await client.query(`DELETE FROM app1_global_announcements WHERE expires_at <= NOW()`);
  await client.query(
    `DELETE FROM app1_feed_posts p
      WHERE p.expires_at <= NOW()
        AND p.pinned_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
        )`
  );
}

function mapPost(row) {
  return {
    id: row.id,
    kind: row.post_kind,
    comment: row.comment_text || null,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    pinned: Boolean(row.pinned_at),
    pinnedAt: row.pinned_at || null,
    author: {
      profileId: row.public_profile_id || null,
      publicName: row.public_name || "Perfil",
      role: row.role === "DEV" ? "DEV" : "ADM",
      avatarStyle: row.avatar_style || "MOON",
      frameStyle: row.frame_style || "DEFAULT",
      statusText: row.status_text || ""
    },
    item: {
      id: row.library_item_id,
      title: row.snapshot_title,
      content: row.preview_content || row.snapshot_text_content || "",
      contentBytes: Number(row.content_bytes || Buffer.byteLength(String(row.snapshot_text_content || ""), "utf8")),
      truncated: Boolean(row.truncated)
    },
    reactions: {
      likeCount: Number(row.like_count || 0),
      commentCount: Number(row.comment_count || 0),
      favoriteCount: Number(row.favorite_count || 0),
      liked: Boolean(row.viewer_liked),
      favorited: Boolean(row.viewer_favorited)
    }
  };
}

function mapComment(row) {
  return {
    id: row.id,
    postId: row.post_id,
    parentCommentId: row.parent_comment_id || null,
    text: row.text_content,
    createdAt: row.created_at,
    editedAt: row.edited_at || null,
    mine: Boolean(row.mine),
    author: {
      profileId: row.public_profile_id || null,
      publicName: row.public_name || "Perfil",
      role: row.role === "DEV" ? "DEV" : "ADM",
      avatarStyle: row.avatar_style || "MOON",
      frameStyle: row.frame_style || "DEFAULT"
    }
  };
}

async function getPostOwner(client, postId) {
  return (await client.query(
    `SELECT p.id, p.account_id, p.snapshot_title, a.public_profile_id, a.public_name
       FROM app1_feed_posts p
       JOIN app1_accounts a ON a.id = p.account_id
      WHERE p.id = $1
      LIMIT 1`,
    [postId]
  )).rows[0] || null;
}

async function createSocialNotification(client, {
  accountId,
  actorAccountId,
  kind,
  postId = null,
  commentId = null,
  announcementId = null
}) {
  if (!accountId || String(accountId) === String(actorAccountId)) return;
  await client.query(
    `INSERT INTO app1_social_notifications
      (id, account_id, actor_account_id, kind, post_id, comment_id, announcement_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [randomId(), accountId, actorAccountId || null, kind, postId, commentId, announcementId]
  );
}

export function registerApp1SocialRoutes(app) {
  app.get("/v1/app1/profile", requireApp1FullSession, async (req, res, next) => {
    try {
      return res.json({ ok: true, profile: publicProfileFromRow(req.app1FeatureSession) });
    } catch (error) {
      next(error);
    }
  });

  app.patch("/v1/app1/profile", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const bio = cleanMultiline(req.body?.bio, 280);
      const statusText = cleanText(req.body?.statusText, 80);
      const avatarStyle = cleanText(req.body?.avatarStyle, 32).toUpperCase() || "MOON";
      const frameStyle = cleanText(req.body?.frameStyle, 32).toUpperCase() || "DEFAULT";
      const presenceMode = cleanText(req.body?.presenceMode, 20).toUpperCase() || "VISIBLE";
      const allowedPresence = new Set(["VISIBLE", "HIDDEN"]);
      if (!allowedPresence.has(presenceMode)) {
        return sendApp1FeatureError(res, 400, "INVALID_PRESENCE", "Modo de presença inválido.");
      }

      const row = await withTransaction(async (client) => {
        const updated = (await client.query(
          `UPDATE app1_accounts
              SET bio = $2,
                  status_text = $3,
                  avatar_style = $4,
                  frame_style = $5,
                  presence_mode = $6,
                  updated_at = NOW()
            WHERE id = $1 AND status = 'ACTIVE'
            RETURNING public_profile_id, public_name, role, bio, status_text,
                      avatar_style, frame_style, presence_mode`,
          [accountId, bio || null, statusText || null, avatarStyle, frameStyle, presenceMode]
        )).rows[0];
        if (!updated) return null;
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_PROFILE_UPDATED",
          targetKind: "APP1_PROFILE",
          targetId: updated.public_profile_id || String(accountId),
          metadata: { avatarStyle, frameStyle, presenceMode }
        });
        return updated;
      });
      if (!row) return sendApp1FeatureError(res, 404, "PROFILE_NOT_FOUND", "Perfil não encontrado.");
      return res.json({ ok: true, profile: publicProfileFromRow(row) });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/profiles", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      if (!searchAllowed(accountId)) {
        return sendApp1FeatureError(res, 429, "PROFILE_SEARCH_RATE_LIMIT", "Muitas buscas seguidas. Aguarde um pouco.");
      }
      const q = cleanText(req.query.q, 60);
      if (Array.from(q).length < 2) {
        return res.json({ ok: true, profiles: [], total: 0, limit: 0, offset: 0, hasMore: false });
      }
      const limit = boundedInt(req.query.limit, 20, 1, PROFILE_LIMIT_MAX);
      const offset = boundedInt(req.query.offset, 0, 0, 10_000);
      const pattern = `%${q}%`;
      const [result, countResult] = await Promise.all([
        pool.query(
          `SELECT public_profile_id, public_name, role, bio, status_text,
                  avatar_style, frame_style, presence_mode
             FROM app1_accounts
            WHERE status = 'ACTIVE'
              AND onboarding_completed_at IS NOT NULL
              AND public_name IS NOT NULL
              AND public_name ILIKE $1
            ORDER BY public_name ASC, public_profile_id ASC
            LIMIT $2 OFFSET $3`,
          [pattern, limit, offset]
        ),
        pool.query(
          `SELECT COUNT(*)::int AS total
             FROM app1_accounts
            WHERE status = 'ACTIVE'
              AND onboarding_completed_at IS NOT NULL
              AND public_name IS NOT NULL
              AND public_name ILIKE $1`,
          [pattern]
        )
      ]);
      const total = Number(countResult.rows[0]?.total || 0);
      return res.json({
        ok: true,
        profiles: result.rows.map(publicProfileFromRow),
        total,
        limit,
        offset,
        hasMore: offset + result.rows.length < total
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/profiles/:profileId", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const profileId = String(req.params.profileId || "").slice(0, 120);
      const row = (await pool.query(
        `SELECT a.public_profile_id, a.public_name, a.role, a.bio, a.status_text,
                a.avatar_style, a.frame_style, a.presence_mode,
                (SELECT COUNT(*)::int FROM app1_feed_posts p
                  WHERE p.account_id = a.id
                    AND (p.expires_at > NOW() OR p.pinned_at IS NOT NULL OR EXISTS (
                      SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
                    ))) AS post_count,
                (SELECT COUNT(*)::int FROM app1_social_favorites f WHERE f.account_id = a.id) AS favorite_count
           FROM app1_accounts a
          WHERE a.public_profile_id = $1
            AND a.status = 'ACTIVE'
            AND a.onboarding_completed_at IS NOT NULL
          LIMIT 1`,
        [profileId]
      )).rows[0];
      if (!row) return sendApp1FeatureError(res, 404, "PROFILE_NOT_FOUND", "Perfil não encontrado.");
      return res.json({
        ok: true,
        profile: publicProfileFromRow(row),
        counts: { posts: Number(row.post_count || 0), favorites: Number(row.favorite_count || 0) }
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/feed", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const viewerId = req.app1FeatureSession.account_id;
      const limit = boundedInt(req.query.limit, FEED_LIMIT_DEFAULT, 1, FEED_LIMIT_MAX);
      const offset = boundedInt(req.query.offset, 0, 0, 100_000);
      const { rows } = await pool.query(
        `SELECT p.id, p.account_id, p.post_kind, p.library_item_id,
                p.snapshot_title, p.snapshot_text_content, p.comment_text,
                p.created_at, p.expires_at, p.pinned_at,
                a.public_profile_id, a.public_name, a.role, a.avatar_style,
                a.frame_style, a.status_text,
                LEFT(p.snapshot_text_content, 4000) AS preview_content,
                OCTET_LENGTH(p.snapshot_text_content)::int AS content_bytes,
                (OCTET_LENGTH(p.snapshot_text_content) > OCTET_LENGTH(LEFT(p.snapshot_text_content, 4000))) AS truncated,
                (SELECT COUNT(*)::int FROM app1_social_likes l WHERE l.post_id = p.id) AS like_count,
                (SELECT COUNT(*)::int FROM app1_social_comments c WHERE c.post_id = p.id) AS comment_count,
                (SELECT COUNT(*)::int FROM app1_social_favorites f WHERE f.post_id = p.id) AS favorite_count,
                EXISTS(SELECT 1 FROM app1_social_likes l WHERE l.post_id = p.id AND l.account_id = $1) AS viewer_liked,
                EXISTS(SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id AND f.account_id = $1) AS viewer_favorited
           FROM app1_feed_posts p
           JOIN app1_accounts a ON a.id = p.account_id
          WHERE a.status = 'ACTIVE'
            AND (p.expires_at > NOW() OR p.pinned_at IS NOT NULL OR EXISTS (
              SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
            ))
          ORDER BY (p.pinned_at IS NOT NULL) DESC, p.pinned_at DESC NULLS LAST, p.created_at DESC, p.id DESC
          LIMIT $2 OFFSET $3`,
        [viewerId, limit, offset]
      );
      const announcements = (await pool.query(
        `SELECT g.id, g.text_content, g.created_at, g.expires_at,
                a.public_profile_id, a.public_name, a.role
           FROM app1_global_announcements g
           JOIN app1_accounts a ON a.id = g.actor_account_id
          WHERE g.expires_at > NOW()
          ORDER BY g.created_at DESC
          LIMIT 3`
      )).rows.map((row) => ({
        id: row.id,
        text: row.text_content,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
        author: {
          profileId: row.public_profile_id || null,
          publicName: row.public_name || "DEV",
          role: "DEV"
        }
      }));
      return res.json({ ok: true, posts: rows.map(mapPost), announcements, limit, offset, hasMore: rows.length === limit });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/posts/:postId", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const viewerId = req.app1FeatureSession.account_id;
      const postId = String(req.params.postId || "");
      const row = (await pool.query(
        `SELECT p.id, p.account_id, p.post_kind, p.library_item_id,
                p.snapshot_title, p.snapshot_text_content, p.comment_text,
                p.created_at, p.expires_at, p.pinned_at,
                a.public_profile_id, a.public_name, a.role, a.avatar_style,
                a.frame_style, a.status_text,
                p.snapshot_text_content AS preview_content,
                OCTET_LENGTH(p.snapshot_text_content)::int AS content_bytes,
                FALSE AS truncated,
                (SELECT COUNT(*)::int FROM app1_social_likes l WHERE l.post_id = p.id) AS like_count,
                (SELECT COUNT(*)::int FROM app1_social_comments c WHERE c.post_id = p.id) AS comment_count,
                (SELECT COUNT(*)::int FROM app1_social_favorites f WHERE f.post_id = p.id) AS favorite_count,
                EXISTS(SELECT 1 FROM app1_social_likes l WHERE l.post_id = p.id AND l.account_id = $2) AS viewer_liked,
                EXISTS(SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id AND f.account_id = $2) AS viewer_favorited
           FROM app1_feed_posts p
           JOIN app1_accounts a ON a.id = p.account_id
          WHERE p.id = $1
            AND a.status = 'ACTIVE'
            AND (p.expires_at > NOW() OR p.pinned_at IS NOT NULL OR EXISTS (
              SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
            ))
          LIMIT 1`,
        [postId, viewerId]
      )).rows[0];
      if (!row) return sendApp1FeatureError(res, 404, "POST_NOT_FOUND", "Publicação não encontrada.");
      return res.json({ ok: true, post: mapPost(row) });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/posts/:postId/like", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const postId = String(req.params.postId || "");
      const liked = req.body?.liked !== false;
      const result = await withTransaction(async (client) => {
        const owner = await getPostOwner(client, postId);
        if (!owner) return null;
        let changed = false;
        if (liked) {
          const inserted = await client.query(
            `INSERT INTO app1_social_likes (post_id, account_id)
             VALUES ($1, $2)
             ON CONFLICT DO NOTHING
             RETURNING post_id`,
            [postId, accountId]
          );
          changed = Boolean(inserted.rowCount);
          if (changed) {
            await createSocialNotification(client, {
              accountId: owner.account_id,
              actorAccountId: accountId,
              kind: "LIKE",
              postId
            });
          }
        } else {
          const deleted = await client.query(
            `DELETE FROM app1_social_likes WHERE post_id = $1 AND account_id = $2 RETURNING post_id`,
            [postId, accountId]
          );
          changed = Boolean(deleted.rowCount);
        }
        const count = Number((await client.query(
          `SELECT COUNT(*)::int AS count FROM app1_social_likes WHERE post_id = $1`,
          [postId]
        )).rows[0]?.count || 0);
        return { changed, count };
      });
      if (!result) return sendApp1FeatureError(res, 404, "POST_NOT_FOUND", "Publicação não encontrada.");
      return res.json({ ok: true, liked, likeCount: result.count, changed: result.changed });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/posts/:postId/favorite", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const postId = String(req.params.postId || "");
      const favorite = req.body?.favorite !== false;
      const result = await withTransaction(async (client) => {
        const owner = await getPostOwner(client, postId);
        if (!owner) return null;
        let changed = false;
        if (favorite) {
          const inserted = await client.query(
            `INSERT INTO app1_social_favorites (post_id, account_id)
             VALUES ($1, $2)
             ON CONFLICT DO NOTHING
             RETURNING post_id`,
            [postId, accountId]
          );
          changed = Boolean(inserted.rowCount);
          if (changed) {
            await createSocialNotification(client, {
              accountId: owner.account_id,
              actorAccountId: accountId,
              kind: "FAVORITE",
              postId
            });
          }
        } else {
          const deleted = await client.query(
            `DELETE FROM app1_social_favorites WHERE post_id = $1 AND account_id = $2 RETURNING post_id`,
            [postId, accountId]
          );
          changed = Boolean(deleted.rowCount);
        }
        const count = Number((await client.query(
          `SELECT COUNT(*)::int AS count FROM app1_social_favorites WHERE post_id = $1`,
          [postId]
        )).rows[0]?.count || 0);
        return { changed, count };
      });
      if (!result) return sendApp1FeatureError(res, 404, "POST_NOT_FOUND", "Publicação não encontrada.");
      await purgeSocial();
      return res.json({ ok: true, favorite, favoriteCount: result.count, changed: result.changed });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/posts/:postId/favorites", requireApp1FullSession, async (req, res, next) => {
    try {
      const postId = String(req.params.postId || "");
      const { rows } = await pool.query(
        `SELECT a.public_profile_id, a.public_name, a.role, a.bio, a.status_text,
                a.avatar_style, a.frame_style, a.presence_mode
           FROM app1_social_favorites f
           JOIN app1_accounts a ON a.id = f.account_id
          WHERE f.post_id = $1 AND a.status = 'ACTIVE'
          ORDER BY f.created_at DESC
          LIMIT 100`,
        [postId]
      );
      return res.json({ ok: true, profiles: rows.map(publicProfileFromRow) });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/posts/:postId/comments", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const postId = String(req.params.postId || "");
      const limit = boundedInt(req.query.limit, COMMENT_LIMIT_DEFAULT, 1, COMMENT_LIMIT_MAX);
      const offset = boundedInt(req.query.offset, 0, 0, 50_000);
      const exists = (await pool.query(`SELECT id FROM app1_feed_posts WHERE id = $1 LIMIT 1`, [postId])).rows[0];
      if (!exists) return sendApp1FeatureError(res, 404, "POST_NOT_FOUND", "Publicação não encontrada.");
      const { rows } = await pool.query(
        `SELECT c.id, c.post_id, c.parent_comment_id, c.text_content,
                c.created_at, c.edited_at,
                a.public_profile_id, a.public_name, a.role, a.avatar_style, a.frame_style,
                (c.account_id = $2) AS mine
           FROM app1_social_comments c
           JOIN app1_accounts a ON a.id = c.account_id
          WHERE c.post_id = $1 AND a.status = 'ACTIVE'
          ORDER BY c.created_at ASC, c.id ASC
          LIMIT $3 OFFSET $4`,
        [postId, accountId, limit, offset]
      );
      return res.json({ ok: true, comments: rows.map(mapComment), limit, offset, hasMore: rows.length === limit });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/posts/:postId/comments", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const postId = String(req.params.postId || "");
      const text = cleanMultiline(req.body?.text, 1000);
      const parentCommentId = cleanText(req.body?.parentCommentId, 120) || null;
      if (!text) return sendApp1FeatureError(res, 400, "COMMENT_REQUIRED", "Escreva um comentário.");
      const id = randomId();
      const result = await withTransaction(async (client) => {
        const owner = await getPostOwner(client, postId);
        if (!owner) return { error: "POST_NOT_FOUND" };
        let parent = null;
        if (parentCommentId) {
          parent = (await client.query(
            `SELECT id, account_id FROM app1_social_comments
              WHERE id = $1 AND post_id = $2 LIMIT 1`,
            [parentCommentId, postId]
          )).rows[0] || null;
          if (!parent) return { error: "PARENT_NOT_FOUND" };
        }
        const row = (await client.query(
          `INSERT INTO app1_social_comments
            (id, post_id, account_id, parent_comment_id, text_content)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, post_id, parent_comment_id, text_content, created_at, edited_at`,
          [id, postId, accountId, parentCommentId, text]
        )).rows[0];
        await createSocialNotification(client, {
          accountId: owner.account_id,
          actorAccountId: accountId,
          kind: "COMMENT",
          postId,
          commentId: id
        });
        if (parent && String(parent.account_id) !== String(owner.account_id)) {
          await createSocialNotification(client, {
            accountId: parent.account_id,
            actorAccountId: accountId,
            kind: "COMMENT",
            postId,
            commentId: id
          });
        }
        return { row };
      });
      if (result.error === "POST_NOT_FOUND") return sendApp1FeatureError(res, 404, result.error, "Publicação não encontrada.");
      if (result.error === "PARENT_NOT_FOUND") return sendApp1FeatureError(res, 400, result.error, "Comentário de resposta não encontrado.");
      const profile = publicProfileFromRow(req.app1FeatureSession);
      return res.status(201).json({
        ok: true,
        comment: {
          id: result.row.id,
          postId: result.row.post_id,
          parentCommentId: result.row.parent_comment_id,
          text: result.row.text_content,
          createdAt: result.row.created_at,
          editedAt: result.row.edited_at,
          mine: true,
          author: profile
        }
      });
    } catch (error) {
      next(error);
    }
  });

  app.delete("/v1/app1/social/comments/:commentId", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const commentId = String(req.params.commentId || "");
      const row = (await pool.query(
        `DELETE FROM app1_social_comments
          WHERE id = $1 AND account_id = $2
          RETURNING id`,
        [commentId, accountId]
      )).rows[0];
      if (!row) return sendApp1FeatureError(res, 404, "COMMENT_NOT_FOUND", "Comentário não encontrado ou não pertence a você.");
      return res.json({ ok: true, deleted: true });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/posts/:postId/pin", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      if (req.app1FeatureSession.role !== "DEV") {
        return sendApp1FeatureError(res, 403, "DEV_REQUIRED", "Somente DEV pode fixar publicação oficial.");
      }
      const postId = String(req.params.postId || "");
      const pinned = req.body?.pinned !== false;
      const result = await withTransaction(async (client) => {
        const target = (await client.query(`SELECT id FROM app1_feed_posts WHERE id = $1 FOR UPDATE`, [postId])).rows[0];
        if (!target) return null;
        let replacedPostId = null;
        if (pinned) {
          const replaced = await client.query(
            `UPDATE app1_feed_posts
                SET pinned_at = NULL, pinned_by_account_id = NULL
              WHERE pinned_at IS NOT NULL AND id <> $1
              RETURNING id`,
            [postId]
          );
          replacedPostId = replaced.rows[0]?.id || null;
          await client.query(
            `UPDATE app1_feed_posts
                SET pinned_at = NOW(), pinned_by_account_id = $2
              WHERE id = $1`,
            [postId, accountId]
          );
        } else {
          await client.query(
            `UPDATE app1_feed_posts
                SET pinned_at = NULL, pinned_by_account_id = NULL
              WHERE id = $1`,
            [postId]
          );
        }
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: pinned ? "APP1_SOCIAL_POST_PINNED" : "APP1_SOCIAL_POST_UNPINNED",
          targetKind: "APP1_FEED_POST",
          targetId: postId,
          metadata: { replacedPostId }
        });
        return { replacedPostId };
      });
      if (!result) return sendApp1FeatureError(res, 404, "POST_NOT_FOUND", "Publicação não encontrada.");
      await purgeSocial();
      return res.json({ ok: true, pinned, replacedPostId: result.replacedPostId });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/notifications", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const accountId = req.app1FeatureSession.account_id;
      const kind = cleanText(req.query.kind, 20).toUpperCase();
      const allowed = new Set(["", "LIKE", "COMMENT", "FAVORITE", "ANNOUNCEMENT"]);
      if (!allowed.has(kind)) return sendApp1FeatureError(res, 400, "INVALID_NOTIFICATION_KIND", "Categoria inválida.");
      const values = [accountId];
      let kindClause = "";
      if (kind) {
        values.push(kind);
        kindClause = `AND n.kind = $${values.length}`;
      }
      const { rows } = await pool.query(
        `SELECT n.id, n.kind, n.post_id, n.comment_id, n.announcement_id,
                n.read_at, n.created_at, n.expires_at,
                a.public_profile_id, a.public_name, a.role,
                p.snapshot_title
           FROM app1_social_notifications n
           LEFT JOIN app1_accounts a ON a.id = n.actor_account_id
           LEFT JOIN app1_feed_posts p ON p.id = n.post_id
          WHERE n.account_id = $1
            AND n.expires_at > NOW()
            ${kindClause}
          ORDER BY n.created_at DESC
          LIMIT 100`,
        values
      );
      const counts = (await pool.query(
        `SELECT kind, COUNT(*)::int AS count
           FROM app1_social_notifications
          WHERE account_id = $1 AND read_at IS NULL AND expires_at > NOW()
          GROUP BY kind`,
        [accountId]
      )).rows;
      const unread = { ALL: 0, LIKE: 0, COMMENT: 0, FAVORITE: 0, ANNOUNCEMENT: 0 };
      for (const row of counts) {
        unread[row.kind] = Number(row.count || 0);
        unread.ALL += Number(row.count || 0);
      }
      return res.json({
        ok: true,
        unread,
        notifications: rows.map((row) => ({
          id: row.id,
          kind: row.kind,
          postId: row.post_id || null,
          commentId: row.comment_id || null,
          announcementId: row.announcement_id || null,
          read: Boolean(row.read_at),
          createdAt: row.created_at,
          expiresAt: row.expires_at,
          actor: row.public_name ? {
            profileId: row.public_profile_id || null,
            publicName: row.public_name,
            role: row.role === "DEV" ? "DEV" : "ADM"
          } : null,
          postTitle: row.snapshot_title || null
        }))
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/notifications/read", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const ids = Array.isArray(req.body?.ids)
        ? [...new Set(req.body.ids.map((value) => String(value || "")).filter(Boolean))].slice(0, 200)
        : [];
      const kind = cleanText(req.body?.kind, 20).toUpperCase();
      let result;
      if (ids.length) {
        result = await pool.query(
          `UPDATE app1_social_notifications
              SET read_at = COALESCE(read_at, NOW())
            WHERE account_id = $1 AND id = ANY($2::text[])
            RETURNING id`,
          [accountId, ids]
        );
      } else if (["LIKE", "COMMENT", "FAVORITE", "ANNOUNCEMENT"].includes(kind)) {
        result = await pool.query(
          `UPDATE app1_social_notifications
              SET read_at = COALESCE(read_at, NOW())
            WHERE account_id = $1 AND kind = $2 AND read_at IS NULL AND expires_at > NOW()
            RETURNING id`,
          [accountId, kind]
        );
      } else {
        result = await pool.query(
          `UPDATE app1_social_notifications
              SET read_at = COALESCE(read_at, NOW())
            WHERE account_id = $1 AND read_at IS NULL AND expires_at > NOW()
            RETURNING id`,
          [accountId]
        );
      }
      return res.json({ ok: true, updatedCount: result.rowCount });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/social/announcements", requireApp1FullSession, async (req, res, next) => {
    try {
      const actorId = req.app1FeatureSession.account_id;
      if (req.app1FeatureSession.role !== "DEV") {
        return sendApp1FeatureError(res, 403, "DEV_REQUIRED", "Somente DEV pode publicar anúncio global.");
      }
      const text = cleanMultiline(req.body?.text, 1000);
      if (!text) return sendApp1FeatureError(res, 400, "ANNOUNCEMENT_REQUIRED", "Escreva a mensagem global.");
      const id = randomId();
      const row = await withTransaction(async (client) => {
        const created = (await client.query(
          `INSERT INTO app1_global_announcements (id, actor_account_id, text_content)
           VALUES ($1, $2, $3)
           RETURNING id, text_content, created_at, expires_at`,
          [id, actorId, text]
        )).rows[0];
        await client.query(
          `INSERT INTO app1_social_notifications
            (id, account_id, actor_account_id, kind, announcement_id)
           SELECT md5(random()::text || clock_timestamp()::text || a.id::text),
                  a.id, $1, 'ANNOUNCEMENT', $2
             FROM app1_accounts a
            WHERE a.status = 'ACTIVE'
              AND a.onboarding_completed_at IS NOT NULL
              AND a.id <> $1`,
          [actorId, id]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId,
          action: "APP1_GLOBAL_ANNOUNCEMENT_CREATED",
          targetKind: "APP1_ANNOUNCEMENT",
          targetId: id,
          metadata: { expiresAt: created.expires_at }
        });
        return created;
      });
      return res.status(201).json({
        ok: true,
        announcement: { id: row.id, text: row.text_content, createdAt: row.created_at, expiresAt: row.expires_at }
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/profiles/:profileId/posts", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const viewerId = req.app1FeatureSession.account_id;
      const profileId = String(req.params.profileId || "").slice(0, 120);
      const { rows } = await pool.query(
        `SELECT p.id, p.account_id, p.post_kind, p.library_item_id,
                p.snapshot_title, p.snapshot_text_content, p.comment_text,
                p.created_at, p.expires_at, p.pinned_at,
                a.public_profile_id, a.public_name, a.role, a.avatar_style,
                a.frame_style, a.status_text,
                LEFT(p.snapshot_text_content, 4000) AS preview_content,
                OCTET_LENGTH(p.snapshot_text_content)::int AS content_bytes,
                (OCTET_LENGTH(p.snapshot_text_content) > OCTET_LENGTH(LEFT(p.snapshot_text_content, 4000))) AS truncated,
                (SELECT COUNT(*)::int FROM app1_social_likes l WHERE l.post_id = p.id) AS like_count,
                (SELECT COUNT(*)::int FROM app1_social_comments c WHERE c.post_id = p.id) AS comment_count,
                (SELECT COUNT(*)::int FROM app1_social_favorites f WHERE f.post_id = p.id) AS favorite_count,
                EXISTS(SELECT 1 FROM app1_social_likes l WHERE l.post_id = p.id AND l.account_id = $2) AS viewer_liked,
                EXISTS(SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id AND f.account_id = $2) AS viewer_favorited
           FROM app1_feed_posts p
           JOIN app1_accounts a ON a.id = p.account_id
          WHERE a.public_profile_id = $1
            AND a.status = 'ACTIVE'
            AND (p.expires_at > NOW() OR p.pinned_at IS NOT NULL OR EXISTS (
              SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
            ))
          ORDER BY p.created_at DESC
          LIMIT 60`,
        [profileId, viewerId]
      );
      return res.json({ ok: true, posts: rows.map(mapPost) });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/social/profiles/:profileId/favorites", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeSocial();
      const viewerId = req.app1FeatureSession.account_id;
      const profileId = String(req.params.profileId || "").slice(0, 120);
      const { rows } = await pool.query(
        `SELECT p.id, p.account_id, p.post_kind, p.library_item_id,
                p.snapshot_title, p.snapshot_text_content, p.comment_text,
                p.created_at, p.expires_at, p.pinned_at,
                author.public_profile_id, author.public_name, author.role, author.avatar_style,
                author.frame_style, author.status_text,
                LEFT(p.snapshot_text_content, 4000) AS preview_content,
                OCTET_LENGTH(p.snapshot_text_content)::int AS content_bytes,
                (OCTET_LENGTH(p.snapshot_text_content) > OCTET_LENGTH(LEFT(p.snapshot_text_content, 4000))) AS truncated,
                (SELECT COUNT(*)::int FROM app1_social_likes l WHERE l.post_id = p.id) AS like_count,
                (SELECT COUNT(*)::int FROM app1_social_comments c WHERE c.post_id = p.id) AS comment_count,
                (SELECT COUNT(*)::int FROM app1_social_favorites f2 WHERE f2.post_id = p.id) AS favorite_count,
                EXISTS(SELECT 1 FROM app1_social_likes l WHERE l.post_id = p.id AND l.account_id = $2) AS viewer_liked,
                EXISTS(SELECT 1 FROM app1_social_favorites f2 WHERE f2.post_id = p.id AND f2.account_id = $2) AS viewer_favorited
           FROM app1_social_favorites fav
           JOIN app1_accounts viewer_profile ON viewer_profile.id = fav.account_id
           JOIN app1_feed_posts p ON p.id = fav.post_id
           JOIN app1_accounts author ON author.id = p.account_id
          WHERE viewer_profile.public_profile_id = $1
            AND viewer_profile.status = 'ACTIVE'
            AND author.status = 'ACTIVE'
          ORDER BY fav.created_at DESC
          LIMIT 60`,
        [profileId, viewerId]
      );
      return res.json({ ok: true, posts: rows.map(mapPost) });
    } catch (error) {
      next(error);
    }
  });
}
