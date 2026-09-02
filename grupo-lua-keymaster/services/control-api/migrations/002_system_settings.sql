CREATE TABLE IF NOT EXISTS system_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO system_settings (key, value)
VALUES ('app1_maintenance', '{"enabled": false}'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_critical_authorizations_expiry
  ON critical_authorizations(expires_at);
CREATE INDEX IF NOT EXISTS idx_critical_authorizations_session
  ON critical_authorizations(keymaster_session_id);
