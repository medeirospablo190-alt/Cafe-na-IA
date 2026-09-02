CREATE TABLE IF NOT EXISTS managed_menus (
  id UUID PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  source_url TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DELETED')),
  created_by_session UUID REFERENCES keymaster_sessions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_managed_menus_status ON managed_menus(status);
CREATE INDEX IF NOT EXISTS idx_managed_menus_public_id ON managed_menus(public_id);

CREATE TABLE IF NOT EXISTS menu_access_keys (
  id UUID PRIMARY KEY,
  menu_id UUID NOT NULL REFERENCES managed_menus(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('FREE', 'VIP')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'REVOKED')),
  key_hash TEXT NOT NULL UNIQUE,
  key_hint TEXT NOT NULL,
  note TEXT,
  expires_at TIMESTAMPTZ,
  created_by_session UUID REFERENCES keymaster_sessions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  CHECK ((kind = 'VIP' AND expires_at IS NULL) OR kind = 'FREE')
);
CREATE INDEX IF NOT EXISTS idx_menu_access_keys_menu ON menu_access_keys(menu_id);
CREATE INDEX IF NOT EXISTS idx_menu_access_keys_status ON menu_access_keys(status);
CREATE INDEX IF NOT EXISTS idx_menu_access_keys_expiry ON menu_access_keys(expires_at);

CREATE TABLE IF NOT EXISTS menu_access_sessions (
  id UUID PRIMARY KEY,
  menu_id UUID NOT NULL REFERENCES managed_menus(id) ON DELETE CASCADE,
  menu_key_id UUID NOT NULL REFERENCES menu_access_keys(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  client_label TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_menu_access_sessions_menu ON menu_access_sessions(menu_id);
CREATE INDEX IF NOT EXISTS idx_menu_access_sessions_key ON menu_access_sessions(menu_key_id);
CREATE INDEX IF NOT EXISTS idx_menu_access_sessions_expiry ON menu_access_sessions(expires_at);
