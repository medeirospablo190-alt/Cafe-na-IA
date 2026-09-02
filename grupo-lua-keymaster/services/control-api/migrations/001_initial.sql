CREATE TABLE IF NOT EXISTS keymaster_devices (
  id BIGSERIAL PRIMARY KEY,
  fingerprint TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL,
  native_device_id_hash TEXT,
  integrity_key_id TEXT,
  failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until TIMESTAMPTZ,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_ip_hash TEXT
);

CREATE TABLE IF NOT EXISTS keymaster_sessions (
  id UUID PRIMARY KEY,
  device_id BIGINT NOT NULL REFERENCES keymaster_devices(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_keymaster_sessions_device ON keymaster_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_keymaster_sessions_expiry ON keymaster_sessions(expires_at);

CREATE TABLE IF NOT EXISTS app1_accounts (
  id UUID PRIMARY KEY,
  login TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('ADM', 'DEV')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DELETED')),
  credential_hash TEXT NOT NULL,
  created_by_session UUID REFERENCES keymaster_sessions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_app1_accounts_status ON app1_accounts(status);
CREATE INDEX IF NOT EXISTS idx_app1_accounts_role ON app1_accounts(role);

CREATE TABLE IF NOT EXISTS app1_sessions (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  device_label TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_app1_sessions_account ON app1_sessions(account_id);

CREATE TABLE IF NOT EXISTS critical_authorizations (
  id UUID PRIMARY KEY,
  keymaster_session_id UUID NOT NULL REFERENCES keymaster_sessions(id) ON DELETE CASCADE,
  dev_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS audit_events (
  id BIGSERIAL PRIMARY KEY,
  actor_kind TEXT NOT NULL,
  actor_id TEXT,
  action TEXT NOT NULL,
  target_kind TEXT,
  target_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_events(action);
