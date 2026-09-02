ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS use_count BIGINT NOT NULL DEFAULT 0;

ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;

ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_menu_access_keys_last_used ON menu_access_keys(last_used_at DESC);
