-- App 1: perfil público, Social V2, notificações e chats privados.

ALTER TABLE app1_accounts
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS status_text TEXT,
  ADD COLUMN IF NOT EXISTS avatar_style TEXT NOT NULL DEFAULT 'MOON',
  ADD COLUMN IF NOT EXISTS frame_style TEXT NOT NULL DEFAULT 'DEFAULT',
  ADD COLUMN IF NOT EXISTS presence_mode TEXT NOT NULL DEFAULT 'VISIBLE';

ALTER TABLE app1_feed_posts
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pinned_by_account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS app1_feed_posts_single_pin_idx
  ON app1_feed_posts ((1))
  WHERE pinned_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS app1_social_likes (
  post_id TEXT NOT NULL REFERENCES app1_feed_posts(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_id, account_id)
);

CREATE INDEX IF NOT EXISTS app1_social_likes_account_created_idx
  ON app1_social_likes(account_id, created_at DESC);

CREATE TABLE IF NOT EXISTS app1_social_favorites (
  post_id TEXT NOT NULL REFERENCES app1_feed_posts(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (post_id, account_id)
);

CREATE INDEX IF NOT EXISTS app1_social_favorites_account_created_idx
  ON app1_social_favorites(account_id, created_at DESC);

CREATE TABLE IF NOT EXISTS app1_social_comments (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES app1_feed_posts(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  parent_comment_id TEXT REFERENCES app1_social_comments(id) ON DELETE CASCADE,
  text_content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  edited_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS app1_social_comments_post_created_idx
  ON app1_social_comments(post_id, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS app1_social_notifications (
  id TEXT PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  actor_account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL,
  kind TEXT NOT NULL CHECK (kind IN ('LIKE', 'COMMENT', 'FAVORITE', 'ANNOUNCEMENT')),
  post_id TEXT REFERENCES app1_feed_posts(id) ON DELETE CASCADE,
  comment_id TEXT REFERENCES app1_social_comments(id) ON DELETE CASCADE,
  announcement_id TEXT,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS app1_social_notifications_account_unread_idx
  ON app1_social_notifications(account_id, read_at, created_at DESC);

CREATE INDEX IF NOT EXISTS app1_social_notifications_expiry_idx
  ON app1_social_notifications(expires_at);

CREATE TABLE IF NOT EXISTS app1_global_announcements (
  id TEXT PRIMARY KEY,
  actor_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  text_content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS app1_global_announcements_active_idx
  ON app1_global_announcements(expires_at, created_at DESC);

CREATE TABLE IF NOT EXISTS app1_conversations (
  id TEXT PRIMARY KEY,
  member_a UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  member_b UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (member_a <> member_b),
  UNIQUE (member_a, member_b)
);

CREATE INDEX IF NOT EXISTS app1_conversations_member_a_updated_idx
  ON app1_conversations(member_a, updated_at DESC);
CREATE INDEX IF NOT EXISTS app1_conversations_member_b_updated_idx
  ON app1_conversations(member_b, updated_at DESC);

CREATE TABLE IF NOT EXISTS app1_conversation_preferences (
  conversation_id TEXT NOT NULL REFERENCES app1_conversations(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  favorite BOOLEAN NOT NULL DEFAULT FALSE,
  muted BOOLEAN NOT NULL DEFAULT FALSE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (conversation_id, account_id)
);

CREATE INDEX IF NOT EXISTS app1_conversation_preferences_account_favorite_idx
  ON app1_conversation_preferences(account_id, favorite, updated_at DESC);

CREATE TABLE IF NOT EXISTS app1_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES app1_conversations(id) ON DELETE CASCADE,
  sender_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  text_content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS app1_messages_conversation_created_idx
  ON app1_messages(conversation_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS app1_messages_expiry_idx
  ON app1_messages(expires_at);

CREATE TABLE IF NOT EXISTS app1_chat_notifications (
  id TEXT PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  actor_account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL,
  conversation_id TEXT NOT NULL REFERENCES app1_conversations(id) ON DELETE CASCADE,
  message_id TEXT REFERENCES app1_messages(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS app1_chat_notifications_account_unread_idx
  ON app1_chat_notifications(account_id, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS app1_chat_notifications_expiry_idx
  ON app1_chat_notifications(expires_at);

CREATE TABLE IF NOT EXISTS app1_chat_reports (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES app1_conversations(id) ON DELETE CASCADE,
  reporter_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  reported_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS app1_chat_reports_status_created_idx
  ON app1_chat_reports(status, created_at DESC);
