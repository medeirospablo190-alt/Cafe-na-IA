import { pool, withTransaction, audit } from "./db.js";
import { randomId } from "./security.js";
import {
  publicProfileFromRow,
  requireApp1FullSession,
  sendApp1FeatureError
} from "./app1-feature-auth.js";

const MESSAGE_MAX = 2_000;
const REPORT_MAX = 500;
const PAGE_DEFAULT = 60;
const PAGE_MAX = 100;

function cleanText(value, max) {
  return String(value ?? "").normalize("NFKC").trim().slice(0, max);
}

function boundedInt(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function orderedMembers(left, right) {
  return String(left).localeCompare(String(right)) <= 0 ? [left, right] : [right, left];
}

async function purgeChats(client = pool) {
  await client.query(`DELETE FROM app1_chat_notifications WHERE expires_at <= NOW()`);
  await client.query(
    `DELETE FROM app1_messages m
      WHERE m.expires_at <= NOW()
        AND NOT EXISTS (
          SELECT 1
            FROM app1_conversation_preferences p
           WHERE p.conversation_id = m.conversation_id
             AND p.favorite = TRUE
        )`
  );
}

async function conversationForMember(client, conversationId, accountId, lock = false) {
  const suffix = lock ? " FOR UPDATE OF c" : "";
  return (await client.query(
    `SELECT c.id, c.member_a, c.member_b, c.created_at, c.updated_at,
            CASE WHEN c.member_a = $2 THEN c.member_b ELSE c.member_a END AS other_account_id
       FROM app1_conversations c
      WHERE c.id = $1
        AND ($2 = c.member_a OR $2 = c.member_b)
      LIMIT 1${suffix}`,
    [conversationId, accountId]
  )).rows[0] || null;
}

async function ensurePreference(client, conversationId, accountId) {
  await client.query(
    `INSERT INTO app1_conversation_preferences (conversation_id, account_id)
     VALUES ($1, $2)
     ON CONFLICT (conversation_id, account_id) DO NOTHING`,
    [conversationId, accountId]
  );
}

function mapConversation(row) {
  return {
    id: row.id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    favorite: Boolean(row.favorite),
    muted: Boolean(row.muted),
    unreadCount: Number(row.unread_count || 0),
    other: {
      profileId: row.public_profile_id || null,
      publicName: row.public_name || "Perfil",
      role: row.role === "DEV" ? "DEV" : "ADM",
      bio: row.bio || "",
      statusText: row.status_text || "",
      avatarStyle: row.avatar_style || "MOON",
      frameStyle: row.frame_style || "DEFAULT",
      presenceMode: row.presence_mode || "VISIBLE"
    },
    latestMessage: row.latest_message_id ? {
      id: row.latest_message_id,
      text: row.latest_text || "",
      mine: Boolean(row.latest_mine),
      createdAt: row.latest_created_at,
      expiresAt: row.latest_expires_at
    } : null
  };
}

function mapMessage(row, accountId) {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    text: row.text_content,
    mine: String(row.sender_account_id) === String(accountId),
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    sender: {
      profileId: row.public_profile_id || null,
      publicName: row.public_name || "Perfil",
      role: row.role === "DEV" ? "DEV" : "ADM",
      avatarStyle: row.avatar_style || "MOON",
      frameStyle: row.frame_style || "DEFAULT"
    }
  };
}

export function registerApp1ChatRoutes(app) {
  app.get("/v1/app1/chats", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeChats();
      const accountId = req.app1FeatureSession.account_id;
      const { rows } = await pool.query(
        `SELECT c.id, c.created_at, c.updated_at,
                COALESCE(pref.favorite, FALSE) AS favorite,
                COALESCE(pref.muted, FALSE) AS muted,
                other.public_profile_id, other.public_name, other.role, other.bio,
                other.status_text, other.avatar_style, other.frame_style, other.presence_mode,
                latest.id AS latest_message_id,
                latest.text_content AS latest_text,
                latest.created_at AS latest_created_at,
                latest.expires_at AS latest_expires_at,
                (latest.sender_account_id = $1) AS latest_mine,
                (SELECT COUNT(*)::int
                   FROM app1_messages unread
                  WHERE unread.conversation_id = c.id
                    AND unread.sender_account_id <> $1
                    AND unread.created_at > COALESCE(pref.last_read_at, TIMESTAMPTZ 'epoch')) AS unread_count
           FROM app1_conversations c
           JOIN app1_accounts other
             ON other.id = CASE WHEN c.member_a = $1 THEN c.member_b ELSE c.member_a END
           LEFT JOIN app1_conversation_preferences pref
             ON pref.conversation_id = c.id AND pref.account_id = $1
           LEFT JOIN LATERAL (
             SELECT m.id, m.sender_account_id, m.text_content, m.created_at, m.expires_at
               FROM app1_messages m
              WHERE m.conversation_id = c.id
              ORDER BY m.created_at DESC, m.id DESC
              LIMIT 1
           ) latest ON TRUE
          WHERE ($1 = c.member_a OR $1 = c.member_b)
            AND other.status = 'ACTIVE'
          ORDER BY COALESCE(pref.favorite, FALSE) DESC,
                   COALESCE(latest.created_at, c.updated_at) DESC,
                   c.id DESC
          LIMIT 200`,
        [accountId]
      );
      const unreadTotal = rows.reduce((sum, row) => sum + Number(row.unread_count || 0), 0);
      return res.json({ ok: true, conversations: rows.map(mapConversation), unreadTotal });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const profileId = cleanText(req.body?.profileId, 120);
      if (!profileId) return sendApp1FeatureError(res, 400, "PROFILE_REQUIRED", "Escolha um perfil para iniciar a conversa.");

      const result = await withTransaction(async (client) => {
        const target = (await client.query(
          `SELECT id, public_profile_id, public_name, role, bio, status_text,
                  avatar_style, frame_style, presence_mode
             FROM app1_accounts
            WHERE public_profile_id = $1
              AND status = 'ACTIVE'
              AND onboarding_completed_at IS NOT NULL
            LIMIT 1`,
          [profileId]
        )).rows[0] || null;
        if (!target) return { error: "PROFILE_NOT_FOUND" };
        if (String(target.id) === String(accountId)) return { error: "SELF_CHAT" };

        const [memberA, memberB] = orderedMembers(accountId, target.id);
        let conversation = (await client.query(
          `SELECT * FROM app1_conversations WHERE member_a = $1 AND member_b = $2 LIMIT 1`,
          [memberA, memberB]
        )).rows[0] || null;
        let created = false;
        if (!conversation) {
          conversation = (await client.query(
            `INSERT INTO app1_conversations (id, member_a, member_b)
             VALUES ($1, $2, $3)
             ON CONFLICT (member_a, member_b) DO UPDATE SET updated_at = app1_conversations.updated_at
             RETURNING *`,
            [randomId(), memberA, memberB]
          )).rows[0];
          created = true;
        }
        await ensurePreference(client, conversation.id, accountId);
        await ensurePreference(client, conversation.id, target.id);
        return { conversation, target, created };
      });

      if (result.error === "PROFILE_NOT_FOUND") return sendApp1FeatureError(res, 404, result.error, "Perfil não encontrado.");
      if (result.error === "SELF_CHAT") return sendApp1FeatureError(res, 400, result.error, "Não é possível iniciar um chat com o próprio perfil.");
      return res.status(result.created ? 201 : 200).json({
        ok: true,
        conversation: {
          id: result.conversation.id,
          createdAt: result.conversation.created_at,
          updatedAt: result.conversation.updated_at,
          favorite: false,
          muted: false,
          unreadCount: 0,
          other: publicProfileFromRow(result.target),
          latestMessage: null
        }
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/chats/:conversationId/messages", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeChats();
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const limit = boundedInt(req.query.limit, PAGE_DEFAULT, 1, PAGE_MAX);
      const offset = boundedInt(req.query.offset, 0, 0, 100_000);
      const conversation = await conversationForMember(pool, conversationId, accountId);
      if (!conversation) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");

      const { rows } = await pool.query(
        `SELECT m.id, m.conversation_id, m.sender_account_id, m.text_content,
                m.created_at, m.expires_at,
                a.public_profile_id, a.public_name, a.role, a.avatar_style, a.frame_style
           FROM app1_messages m
           JOIN app1_accounts a ON a.id = m.sender_account_id
          WHERE m.conversation_id = $1
          ORDER BY m.created_at DESC, m.id DESC
          LIMIT $2 OFFSET $3`,
        [conversationId, limit, offset]
      );
      const messages = rows.reverse().map((row) => mapMessage(row, accountId));
      return res.json({ ok: true, messages, limit, offset, hasMore: rows.length === limit });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats/:conversationId/messages", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const text = cleanText(req.body?.text, MESSAGE_MAX);
      if (!text) return sendApp1FeatureError(res, 400, "MESSAGE_REQUIRED", "Escreva uma mensagem.");
      const id = randomId();

      const result = await withTransaction(async (client) => {
        const conversation = await conversationForMember(client, conversationId, accountId, true);
        if (!conversation) return null;
        const otherId = conversation.other_account_id;
        const other = (await client.query(
          `SELECT id, status FROM app1_accounts WHERE id = $1 LIMIT 1`,
          [otherId]
        )).rows[0];
        if (!other || other.status !== "ACTIVE") return { error: "RECIPIENT_UNAVAILABLE" };

        await ensurePreference(client, conversationId, accountId);
        await ensurePreference(client, conversationId, otherId);
        const row = (await client.query(
          `INSERT INTO app1_messages (id, conversation_id, sender_account_id, text_content)
           VALUES ($1, $2, $3, $4)
           RETURNING id, conversation_id, sender_account_id, text_content, created_at, expires_at`,
          [id, conversationId, accountId, text]
        )).rows[0];
        await client.query(`UPDATE app1_conversations SET updated_at = NOW() WHERE id = $1`, [conversationId]);
        await client.query(
          `INSERT INTO app1_chat_notifications
            (id, account_id, actor_account_id, conversation_id, message_id)
           VALUES ($1, $2, $3, $4, $5)`,
          [randomId(), otherId, accountId, conversationId, id]
        );
        return { row };
      });

      if (!result) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");
      if (result.error === "RECIPIENT_UNAVAILABLE") {
        return sendApp1FeatureError(res, 409, result.error, "O destinatário não está disponível para receber mensagens.");
      }
      return res.status(201).json({
        ok: true,
        message: {
          id: result.row.id,
          conversationId: result.row.conversation_id,
          text: result.row.text_content,
          mine: true,
          createdAt: result.row.created_at,
          expiresAt: result.row.expires_at,
          sender: publicProfileFromRow(req.app1FeatureSession)
        }
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats/:conversationId/read", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const result = await withTransaction(async (client) => {
        const conversation = await conversationForMember(client, conversationId, accountId);
        if (!conversation) return null;
        await ensurePreference(client, conversationId, accountId);
        await client.query(
          `UPDATE app1_conversation_preferences
              SET last_read_at = NOW(), updated_at = NOW()
            WHERE conversation_id = $1 AND account_id = $2`,
          [conversationId, accountId]
        );
        const notifications = await client.query(
          `UPDATE app1_chat_notifications
              SET read_at = COALESCE(read_at, NOW())
            WHERE conversation_id = $1 AND account_id = $2 AND read_at IS NULL
            RETURNING id`,
          [conversationId, accountId]
        );
        return notifications.rowCount;
      });
      if (result === null) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");
      return res.json({ ok: true, updatedCount: result });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats/:conversationId/favorite", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const favorite = req.body?.favorite !== false;
      const result = await withTransaction(async (client) => {
        const conversation = await conversationForMember(client, conversationId, accountId);
        if (!conversation) return null;
        await ensurePreference(client, conversationId, accountId);
        await client.query(
          `UPDATE app1_conversation_preferences
              SET favorite = $3, updated_at = NOW()
            WHERE conversation_id = $1 AND account_id = $2`,
          [conversationId, accountId, favorite]
        );
        return true;
      });
      if (!result) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");
      if (!favorite) await purgeChats();
      return res.json({ ok: true, favorite });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats/:conversationId/mute", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const muted = req.body?.muted !== false;
      const result = await withTransaction(async (client) => {
        const conversation = await conversationForMember(client, conversationId, accountId);
        if (!conversation) return null;
        await ensurePreference(client, conversationId, accountId);
        await client.query(
          `UPDATE app1_conversation_preferences
              SET muted = $3, updated_at = NOW()
            WHERE conversation_id = $1 AND account_id = $2`,
          [conversationId, accountId, muted]
        );
        return true;
      });
      if (!result) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");
      return res.json({ ok: true, muted });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/chats/:conversationId/report", requireApp1FullSession, async (req, res, next) => {
    try {
      const accountId = req.app1FeatureSession.account_id;
      const conversationId = String(req.params.conversationId || "");
      const reason = cleanText(req.body?.reason, REPORT_MAX);
      if (reason.length < 5) return sendApp1FeatureError(res, 400, "REPORT_REASON_REQUIRED", "Explique o motivo da denúncia.");
      const reportId = randomId();
      const result = await withTransaction(async (client) => {
        const conversation = await conversationForMember(client, conversationId, accountId);
        if (!conversation) return null;
        const row = (await client.query(
          `INSERT INTO app1_chat_reports
            (id, conversation_id, reporter_account_id, reported_account_id, reason)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, status, created_at`,
          [reportId, conversationId, accountId, conversation.other_account_id, reason]
        )).rows[0];
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: accountId,
          action: "APP1_CHAT_REPORTED",
          targetKind: "APP1_CHAT_REPORT",
          targetId: reportId,
          metadata: { conversationId, reportedAccountId: conversation.other_account_id }
        });
        return row;
      });
      if (!result) return sendApp1FeatureError(res, 404, "CHAT_NOT_FOUND", "Conversa não encontrada.");
      return res.status(201).json({ ok: true, report: result });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/chat-notifications", requireApp1FullSession, async (req, res, next) => {
    try {
      await purgeChats();
      const accountId = req.app1FeatureSession.account_id;
      const { rows } = await pool.query(
        `SELECT n.id, n.conversation_id, n.message_id, n.read_at,
                n.created_at, n.expires_at,
                a.public_profile_id, a.public_name, a.role,
                m.text_content
           FROM app1_chat_notifications n
           LEFT JOIN app1_accounts a ON a.id = n.actor_account_id
           LEFT JOIN app1_messages m ON m.id = n.message_id
          WHERE n.account_id = $1 AND n.expires_at > NOW()
          ORDER BY n.created_at DESC
          LIMIT 100`,
        [accountId]
      );
      const unreadCount = rows.filter((row) => !row.read_at).length;
      return res.json({
        ok: true,
        unreadCount,
        notifications: rows.map((row) => ({
          id: row.id,
          conversationId: row.conversation_id,
          messageId: row.message_id || null,
          read: Boolean(row.read_at),
          createdAt: row.created_at,
          expiresAt: row.expires_at,
          preview: String(row.text_content || "").slice(0, 160),
          actor: row.public_name ? {
            profileId: row.public_profile_id || null,
            publicName: row.public_name,
            role: row.role === "DEV" ? "DEV" : "ADM"
          } : null
        }))
      });
    } catch (error) {
      next(error);
    }
  });
}
