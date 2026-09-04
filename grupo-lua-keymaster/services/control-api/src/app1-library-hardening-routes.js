import crypto from "node:crypto";
import { pool, withTransaction, audit } from "./db.js";
import { randomId, tokenHash } from "./security.js";
import { validateFeedComment } from "./app1-feed-comment.js";

const LOADSTRING_MAX_CHARS = 32_768;
const BULK_MAX = 500;

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
    req.app1LibraryHardeningSession = session;
    next();
  } catch (error) {
    next(error);
  }
}

function normalizeKind(value) {
  return String(value || "").trim().toUpperCase();
}

function codePointLength(value) {
  return Array.from(String(value ?? "")).length;
}

function validateLoadstringLength(kind, content) {
  if (normalizeKind(kind) !== "LOADSTRING") return null;
  const chars = codePointLength(content);
  if (chars <= LOADSTRING_MAX_CHARS) return null;
  return {
    code: "LOADSTRING_TOO_LONG",
    message: `A loadstring ultrapassa o limite de ${LOADSTRING_MAX_CHARS.toLocaleString("pt-BR")} caracteres.`,
    maxChars: LOADSTRING_MAX_CHARS,
    chars
  };
}

function parseIds(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item || "").trim()).filter(Boolean))];
}

async function purgeExpiredFeedPosts(client) {
  await client.query(`DELETE FROM app1_feed_posts WHERE expires_at <= NOW()`);
}

export function registerApp1LibraryHardeningRoutes(app) {
  // Validação adicional executada antes das rotas V2. A autenticação é repetida pela
  // rota principal depois do next(), mantendo esta camada independente e fail-closed.
  app.post("/v1/app1/library", requireFullSession, (req, res, next) => {
    const invalid = validateLoadstringLength(req.body?.kind, req.body?.content);
    if (invalid) return sendError(res, 400, invalid.code, invalid.message, { maxChars: invalid.maxChars });
    next();
  });

  app.patch("/v1/app1/library/:id", requireFullSession, async (req, res, next) => {
    try {
      if (req.body?.content === undefined) return next();
      const accountId = req.app1LibraryHardeningSession.account_id;
      const id = String(req.params.id || "");
      const item = (await pool.query(
        `SELECT kind
           FROM app1_library_items
          WHERE id = $1 AND account_id = $2
          LIMIT 1`,
        [id, accountId]
      )).rows[0];
      if (!item) return next();
      const invalid = validateLoadstringLength(item.kind, req.body.content);
      if (invalid) return sendError(res, 400, invalid.code, invalid.message, { maxChars: invalid.maxChars });
      next();
    } catch (error) {
      next(error);
    }
  });

  // Favoritar não é uma edição de conteúdo: não altera updated_at.
  app.post("/v1/app1/library/bulk/favorite", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibraryHardeningSession.account_id;
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
              SET favorite = $3
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

  // Compartilhamento com comentário + estado de favorito é atômico. Se qualquer
  // parte falhar, nem o post nem a mudança do favorito são parcialmente aplicados.
  app.post("/v1/app1/library/:id/share/options", requireFullSession, async (req, res, next) => {
    try {
      const accountId = req.app1LibraryHardeningSession.account_id;
      const id = String(req.params.id || "");
      const checkedComment = validateFeedComment(req.body?.comment);
      if (!checkedComment.ok) {
        return sendError(res, 400, checkedComment.code, checkedComment.message);
      }
      if (req.body?.favorite !== undefined && typeof req.body.favorite !== "boolean") {
        return sendError(res, 400, "INVALID_FAVORITE", "Informe favorite como true ou false.");
      }

      const result = await withTransaction(async (client) => {
        await purgeExpiredFeedPosts(client);
        const item = (await client.query(
          `SELECT id, kind, title, text_content, favorite
             FROM app1_library_items
            WHERE id = $1 AND account_id = $2
            LIMIT 1 FOR UPDATE`,
          [id, accountId]
        )).rows[0];
        if (!item) return null;

        const desiredFavorite = typeof req.body?.favorite === "boolean"
          ? req.body.favorite
          : Boolean(item.favorite);
        const favoriteChanged = desiredFavorite !== Boolean(item.favorite);
        if (favoriteChanged) {
          await client.query(
            `UPDATE app1_library_items
                SET favorite = $3
              WHERE id = $1 AND account_id = $2`,
            [id, accountId, desiredFavorite]
          );
        }

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
            favorite: desiredFavorite,
            favoriteChanged,
            expiresAt: post.expires_at
          }
        });

        return { post, favorite: desiredFavorite };
      });

      if (!result) return sendError(res, 404, "NOT_FOUND", "Arquivo não encontrado.");
      return res.status(201).json({ ok: true, post: result.post, favorite: result.favorite });
    } catch (error) {
      next(error);
    }
  });
}

export { LOADSTRING_MAX_CHARS };
