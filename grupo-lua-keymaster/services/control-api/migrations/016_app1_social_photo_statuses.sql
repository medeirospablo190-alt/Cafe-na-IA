-- APP 1 Social — status com foto, temporário e vinculado à conta.

CREATE TABLE IF NOT EXISTS app1_social_statuses (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  image_bytes BYTEA NOT NULL,
  image_size_bytes INTEGER NOT NULL CHECK (image_size_bytes > 0 AND image_size_bytes <= 4194304),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_app1_social_statuses_active
  ON app1_social_statuses(account_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_app1_social_statuses_expiry
  ON app1_social_statuses(expires_at)
  WHERE deleted_at IS NULL;
