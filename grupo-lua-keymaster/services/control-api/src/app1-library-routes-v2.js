import crypto from "node:crypto";
import { pool, withTransaction, audit } from "./db.js";
import { randomId, tokenHash } from "./security.js";
import { validateFeedComment } from "./app1-feed-comment.js";

const ALLOWED_KINDS = new Set(["CODE", "LOADSTRING"]);
const TITLE_MAX = 120;
const CONTENT_MAX_BYTES = 1_000_000;
const BULK_MAX = 500;
const LIBRARY_PAGE_DEFAULT = 60;
const LIBRARY_PAGE_MAX = 100;
const LIBRARY_OFFSET_MAX = 100_000;
const LIBRARY_PREVIEW_CHARS = 220;
const FEED_LIST_MAX = 50;
const FEED_PREVIEW_CHARS = 4_000;

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
  if (!row || row.account_status !== "ACTIVE" || row.device_status !== "ACTIVE" || row.session_kind !== "FULL") return null;
  const supplied = tokenHash(`app1-device:${deviceToken}`);
  return safeEqualText(supplied, row.device_token_hash) ? row : null;
}

async function requireFullSession(req, res, next) {
  try {
    const session = await getFullSession(req);
    if (!session) {
      return sendError(res, 401, "UNAUTHORIZED", "Sessão FULL inválida, expirada ou incompatível com este dispositivo.");
    }
    req.app1LibrarySession = session;
    next();
  } catch (error) {
    next(error);
  }
}

function normalizeKind(value) {
  const kind = String(value || "").trim().toUpperCase();
  return ALLOWED_KINDS.has(kind) ? kind : "";
}

function normalizeTitle(value) {
  return String(value || "").normalize("NFKC").trim().replace(/\s+/g, " ").slice(0, TITLE_MAX);
}

function validateContent(value) {
  const content = String(value ?? "");
  if (!content.trim()) return { ok: false, code: "CONTENT_REQUIRED", content };
  if (Buffer.byteLength(content, "utf8") > CONTENT_MAX_BYTES) {
    return { ok: false, code: "CONTENT_TOO_LARGE", content };
  }
  return { ok: true, content };
}

function parseIds(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item || "").trim()).filter(Boolean))];
}

function parseBoundedInteger(value, fallback, min, max) {
  if (value === undefined || value === null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function summaryRow(row) {
  const source = row.preview_text ?? row.text_content ?? "";
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    favorite: Boolean(row.favorite),
    preview: String(source).slice(0, LIBRARY_PREVIEW_CHARS),
    contentBytes: Number(row.content_bytes || Buffer.byteLength(String(row.text_content || ""), "utf8")),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    sharedCount: Number(row.shared_count || 0)
  };
}

function feedRow(row, fullContent = false) {
  const content = fullContent ? row.snapshot_text_content : row.preview_content;
  const contentBytes = Number(
    row.content_bytes ?? Buffer.byteLength(String(row.snapshot_text_content || ""), "utf8")
  );
  return {
    id: row.id,
    kind: row.post_kind,
    comment: row.comment_text || null,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    author: {
      profileId: row.public_profile_id,
      publicName: row.public_name || "Perfil"
    },
    item: {
      id: row.library_item_id,
      title: row.snapshot_title,
      content: content || "",
      contentBytes,
      truncated: fullContent
        ? false
        : contentBytes > Buffer.byteLength(String(content || ""), "utf8")
    }
  };
}

async function purgeExpiredFeedPosts(client = pool) {
  await client.query(
    `DELETE FROM app1_feed_posts p
      WHERE p.expires_at <= NOW()
        AND p.pinned_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id
        )`
  );
}

export function registerApp1LibraryRoutes(app) {
  app.get("/v1/app1/library", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const kind = req.query.kind ? normalizeKind(req.query.kind) : "";
      if (req.query.kind && !kind) return sendError(res, 400, "INVALID_KIND", "Tipo de arquivo inválido.");

      const favorite = String(req.query.favorite || "").toLowerCase();
      const q = String(req.query.q || "").trim().slice(0, 120);
      const limit = parseBoundedInteger(req.query.limit, LIBRARY_PAGE_DEFAULT, 1, LIBRARY_PAGE_MAX);
      const offset = parseBoundedInteger(req.query.offset, 0, 0, LIBRARY_OFFSET_MAX);
      const values = [accountId];
      const clauses = ["i.account_id = $1"];

      if (kind) {
        values.push(kind);
        clauses.push(`i.kind = $${values.length}`);
      }
      if (favorite === "true" || favorite === "false") {
        values.push(favorite === "true");
        clauses.push(`i.favorite = $${values.length}`);
      }
      if (q) {
        values.push(`%${q}%`);
        clauses.push(`i.title ILIKE $${values.length}`);
      }

      const limitPosition = values.length + 1;
      const offsetPosition = values.length + 2;
      const [listResult, countResult] = await Promise.all([
        pool.query(
          `SELECT i.id, i.kind, i.title, i.favorite,
                  LEFT(i.text_content, ${LIBRARY_PREVIEW_CHARS}) AS preview_text,
                  i.created_at, i.updated_at,
                  OCTET_LENGTH(i.text_content)::int AS content_bytes,
                  COUNT(p.id) FILTER (
                    WHERE p.expires_at > NOW()
                       OR p.pinned_at IS NOT NULL
                       OR EXISTS (SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id)
                  )::int AS shared_count
             FROM app1_library_items i
             LEFT JOIN app1_feed_posts p ON p.library_item_id = i.id
            WHERE ${clauses.join(" AND ")}
            GROUP BY i.id
            ORDER BY i.favorite DESC, i.updated_at DESC, i.id DESC
            LIMIT $${limitPosition} OFFSET $${offsetPosition}`,
          [...values, limit, offset]
        ),
        pool.query(
          `SELECT COUNT(*)::int AS total
             FROM app1_library_items i
            WHERE ${clauses.join(" AND ")}`,
          values
        )
      ]);

      const total = Number(countResult.rows[0]?.total || 0);
      const items = listResult.rows.map(summaryRow);
      const nextOffset = offset + items.length;
      return res.json({
        ok: true,
        items,
        total,
        limit,
        offset,
        hasMore: nextOffset < total,
        nextOffset: nextOffset < total ? nextOffset : null
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/library", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const kind = normalizeKind(req.body?.kind);
      const title = normalizeTitle(req.body?.title);
      const checked = validateContent(req.body?.content);
      if (!kind) return sendError(res, 400, "INVALID_KIND", "Use CODE ou LOADSTRING.");
      if (!title) return sendError(res, 400, "TITLE_REQUIRED", "Dê um nome antes de salvar.");
      if (!checked.ok) {
        return sendError(
          res,
          400,
          checked.code,
          checked.code === "CONTENT_TOO_LARGE" ? "O conteúdo ultrapassa 1 MB." : "O conteúdo não pode ficar vazio."
        );
      }

      const id = randomId();
      const row = await withTransaction(async (client) => {
        const created = (await client.query(
          `INSERT INTO app1_library_items (id, account_id, kind, title, text_content)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, kind, title, favorite, text_content, created_at, updated_at`,
          [id, accountId, kind, title, checked.content]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_LIBRARY_ITEM_CREATED",
          targetKind: "APP1_LIBRARY_ITEM",
          targetId: id,
          metadata: { kind }
        });
        return created;
      });
      return res.status(201).json({ ok: true, item: { ...summaryRow(row), content: row.text_content } });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/library/bulk/favorite", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const ids = parseIds(req.body?.ids);
      if (!ids.length) return sendError(res, 400, "IDS_REQUIRED", "Selecione pelo menos um item.");
      if (ids.length > BULK_MAX) return sendError(res, 400, "TOO_MANY_IDS", `Selecione no máximo ${BULK_MAX} itens por vez.`);
      if (typeof req.body?.favorite !== "boolean") {
        return sendError(res, 400, "INVALID_FAVORITE", "Informe favorite como true ou false.");
      }

      const favorite = req.body.favorite;
      const updatedCount = await withTransaction(async (client) => {
        const updated = await client.query(
          `UPDATE app1_library_items
              SET favorite = $3, updated_at = NOW()
            WHERE account_id = $1 AND id = ANY($2::text[])
            RETURNING id`,
          [accountId, ids, favorite]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: favorite ? "APP1_LIBRARY_ITEMS_FAVORITED" : "APP1_LIBRARY_ITEMS_UNFAVORITED",
          targetKind: "APP1_LIBRARY",
          targetId: accountId,
          metadata: { count: updated.rowCount }
        });
        return updated.rowCount;
      });
      return res.json({ ok: true, updatedCount });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/library/bulk/delete", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const ids = parseIds(req.body?.ids);
      if (!ids.length) return sendError(res, 400, "IDS_REQUIRED", "Selecione pelo menos um item.");
      if (ids.length > BULK_MAX) return sendError(res, 400, "TOO_MANY_IDS", `Selecione no máximo ${BULK_MAX} itens por vez.`);

      const deletedCount = await withTransaction(async (client) => {
        const deleted = await client.query(
          `DELETE FROM app1_library_items
            WHERE account_id = $1 AND id = ANY($2::text[])
            RETURNING id`,
          [accountId, ids]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_LIBRARY_ITEMS_DELETED",
          targetKind: "APP1_LIBRARY",
          targetId: accountId,
          metadata: { count: deleted.rowCount }
        });
        return deleted.rowCount;
      });
      return res.json({ ok: true, deletedCount });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/library/:id", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const row = (await pool.query(
        `SELECT id, kind, title, favorite, text_content, created_at, updated_at,
                OCTET_LENGTH(text_content)::int AS content_bytes
           FROM app1_library_items
          WHERE id = $1 AND account_id = $2
          LIMIT 1`,
        [String(req.params.id), accountId]
      )).rows[0];
      if (!row) return sendError(res, 404, "NOT_FOUND", "Arquivo não encontrado.");
      return res.json({ ok: true, item: { ...summaryRow(row), content: row.text_content } });
    } catch (error) {
      next(error);
    }
  });

  app.patch("/v1/app1/library/:id", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const id = String(req.params.id);
      const title = req.body?.title === undefined ? null : normalizeTitle(req.body.title);
      const checked = req.body?.content === undefined ? null : validateContent(req.body.content);
      if (title !== null && !title) return sendError(res, 400, "TITLE_REQUIRED", "O nome não pode ficar vazio.");
      if (checked && !checked.ok) {
        return sendError(
          res,
          400,
          checked.code,
          checked.code === "CONTENT_TOO_LARGE" ? "O conteúdo ultrapassa 1 MB." : "O conteúdo não pode ficar vazio."
        );
      }
      if (title === null && checked === null) return sendError(res, 400, "NO_CHANGES", "Nenhuma alteração foi enviada.");

      const row = await withTransaction(async (client) => {
        const updated = (await client.query(
          `UPDATE app1_library_items
              SET title = COALESCE($3, title),
                  text_content = COALESCE($4, text_content),
                  updated_at = NOW()
            WHERE id = $1 AND account_id = $2
            RETURNING id, kind, title, favorite, text_content, created_at, updated_at`,
          [id, accountId, title, checked?.content ?? null]
        )).rows[0];
        if (!updated) return null;
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_LIBRARY_ITEM_UPDATED",
          targetKind: "APP1_LIBRARY_ITEM",
          targetId: id,
          metadata: { renamed: title !== null, contentChanged: checked !== null }
        });
        return updated;
      });
      if (!row) return sendError(res, 404, "NOT_FOUND", "Arquivo não encontrado.");
      return res.json({ ok: true, item: { ...summaryRow(row), content: row.text_content } });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/library/:id/share", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibrarySession.account_id;
      const id = String(req.params.id);
      const checkedComment = validateFeedComment(req.body?.comment);
      if (!checkedComment.ok) {
        return sendError(res, 400, checkedComment.code, checkedComment.message);
      }

      const result = await withTransaction(async (client) => {
        await purgeExpiredFeedPosts(client);
        const item = (await client.query(
          `SELECT id, kind, title, text_content
             FROM app1_library_items
            WHERE id = $1 AND account_id = $2
            LIMIT 1 FOR UPDATE`,
          [id, accountId]
        )).rows[0];
        if (!item) return null;

        const postId = randomId();
        const post = (await client.query(
          `INSERT INTO app1_feed_posts
            (id, account_id, post_kind, library_item_id, snapshot_title, snapshot_text_content, comment_text)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id, post_kind, comment_text, created_at, expires_at`,
          [postId, accountId, item.kind, item.id, item.title, item.text_content, checkedComment.comment]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_LIBRARY_ITEM_SHARED_TO_FEED",
          targetKind: "APP1_FEED_POST",
          targetId: postId,
          metadata: {
            itemId: item.id,
            kind: item.kind,
            hasComment: Boolean(checkedComment.comment),
            expiresAt: post.expires_at
          }
        });
        return post;
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Arquivo não encontrado.");
      return res.status(201).json({ ok: true, post: result });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/feed", requireFullSession, async (_req, res, next) => {
    try {
      await purgeExpiredFeedPosts();
      const { rows } = await pool.query(
        `SELECT p.id, p.post_kind, p.comment_text, p.created_at, p.expires_at,
                p.library_item_id, p.snapshot_title,
                LEFT(p.snapshot_text_content, ${FEED_PREVIEW_CHARS}) AS preview_content,
                OCTET_LENGTH(p.snapshot_text_content)::int AS content_bytes,
                a.public_profile_id, a.public_name
           FROM app1_feed_posts p
           JOIN app1_accounts a ON a.id = p.account_id AND a.status <> 'DELETED'
          WHERE p.expires_at > NOW()
             OR p.pinned_at IS NOT NULL
             OR EXISTS (SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id)
          ORDER BY (p.pinned_at IS NOT NULL) DESC, p.pinned_at DESC NULLS LAST, p.created_at DESC
          LIMIT ${FEED_LIST_MAX}`
      );
      return res.json({ ok: true, posts: rows.map((row) => feedRow(row, false)) });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/feed/:id", requireFullSession, async (req, res, next) => {
    try {
      const row = (await pool.query(
        `SELECT p.id, p.post_kind, p.comment_text, p.created_at, p.expires_at,
                p.library_item_id, p.snapshot_title, p.snapshot_text_content,
                a.public_profile_id, a.public_name
           FROM app1_feed_posts p
           JOIN app1_accounts a ON a.id = p.account_id AND a.status <> 'DELETED'
          WHERE p.id = $1
            AND (
              p.expires_at > NOW()
              OR p.pinned_at IS NOT NULL
              OR EXISTS (SELECT 1 FROM app1_social_favorites f WHERE f.post_id = p.id)
            )
          LIMIT 1`,
        [String(req.params.id)]
      )).rows[0];
      if (!row) return sendError(res, 404, "NOT_FOUND", "Publicação não encontrada ou removida.");
      return res.json({ ok: true, post: feedRow(row, true) });
    } catch (error) {
      next(error);
    }
  });
}
