-- APP 1 V1 — segurança, onboarding, sessões de 24h e vínculo de dispositivos.

ALTER TABLE app1_accounts
  DROP CONSTRAINT IF EXISTS app1_accounts_status_check;

ALTER TABLE app1_accounts
  ADD CONSTRAINT app1_accounts_status_check
  CHECK (status IN ('ACTIVE', 'LOCKED_SECURITY', 'SUSPENDED', 'DELETED'));

ALTER TABLE app1_accounts
  ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_login_attempts >= 0),
  ADD COLUMN IF NOT EXISTS failed_device_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_device_attempts >= 0),
  ADD COLUMN IF NOT EXISTS security_locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS security_lock_reason TEXT,
  ADD COLUMN IF NOT EXISTS terms_version TEXT,
  ADD COLUMN IF NOT EXISTS privacy_version TEXT,
  ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS public_profile_id TEXT,
  ADD COLUMN IF NOT EXISTS public_name TEXT,
  ADD COLUMN IF NOT EXISTS public_name_normalized TEXT,
  ADD COLUMN IF NOT EXISTS public_name_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_app1_accounts_public_profile_id
  ON app1_accounts(public_profile_id)
  WHERE public_profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app1_accounts_public_name
  ON app1_accounts(public_name_normalized)
  WHERE public_name_normalized IS NOT NULL AND status <> 'DELETED';

CREATE TABLE IF NOT EXISTS app1_devices (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  device_token_hash TEXT NOT NULL,
  platform TEXT NOT NULL,
  native_device_id_hash TEXT,
  installation_id_hash TEXT,
  integrity_key_id TEXT,
  device_label TEXT,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
  authorized_by_dev_account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL,
  authorized_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_ip_hash TEXT,
  revoked_at TIMESTAMPTZ,
  UNIQUE (account_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_app1_devices_account
  ON app1_devices(account_id, status);

CREATE INDEX IF NOT EXISTS idx_app1_devices_fingerprint
  ON app1_devices(fingerprint);

ALTER TABLE app1_sessions
  ADD COLUMN IF NOT EXISTS app1_device_id UUID REFERENCES app1_devices(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS session_kind TEXT NOT NULL DEFAULT 'FULL';

ALTER TABLE app1_sessions
  DROP CONSTRAINT IF EXISTS app1_sessions_session_kind_check;

ALTER TABLE app1_sessions
  ADD CONSTRAINT app1_sessions_session_kind_check
  CHECK (session_kind IN ('PROVISIONAL', 'FULL'));

CREATE INDEX IF NOT EXISTS idx_app1_sessions_device
  ON app1_sessions(app1_device_id);

CREATE TABLE IF NOT EXISTS app1_terms_acceptances (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  app1_session_id UUID REFERENCES app1_sessions(id) ON DELETE SET NULL,
  terms_version TEXT NOT NULL,
  privacy_version TEXT NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (account_id, terms_version, privacy_version)
);

CREATE INDEX IF NOT EXISTS idx_app1_terms_acceptances_account
  ON app1_terms_acceptances(account_id, accepted_at DESC);

CREATE TABLE IF NOT EXISTS app1_device_enrollment_windows (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  created_by_dev_account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE RESTRICT,
  keymaster_session_id UUID REFERENCES keymaster_sessions(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'CONSUMED', 'EXPIRED', 'CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  consumed_device_id UUID REFERENCES app1_devices(id) ON DELETE SET NULL,
  cancelled_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_app1_device_enrollment_one_pending
  ON app1_device_enrollment_windows(account_id)
  WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_app1_device_enrollment_expiry
  ON app1_device_enrollment_windows(expires_at)
  WHERE status = 'PENDING';

CREATE TABLE IF NOT EXISTS app1_login_attempts (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL,
  login_fingerprint TEXT NOT NULL,
  credential_fingerprint TEXT NOT NULL,
  device_fingerprint TEXT,
  platform TEXT,
  ip_hash TEXT,
  result TEXT NOT NULL CHECK (result IN (
    'SUCCESS',
    'INVALID_CREDENTIAL',
    'ACCOUNT_LOCKED',
    'ACCOUNT_SUSPENDED',
    'ACCOUNT_DELETED',
    'UNAUTHORIZED_DEVICE',
    'DEVICE_PROOF_INVALID',
    'INTEGRITY_REJECTED'
  )),
  integrity_verified BOOLEAN NOT NULL DEFAULT FALSE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app1_login_attempts_account
  ON app1_login_attempts(account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app1_login_attempts_created
  ON app1_login_attempts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_app1_login_attempts_device
  ON app1_login_attempts(device_fingerprint, created_at DESC)
  WHERE device_fingerprint IS NOT NULL;

-- Quando uma conta passa definitivamente para DELETED, os dados que ainda
-- permitiriam autenticação/identificação direta são eliminados ou
-- irreversivelmente substituídos. O UUID interno continua existindo para que
-- auditoria e futuras políticas de ownership não percam integridade referencial.
CREATE OR REPLACE FUNCTION scrub_app1_account_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status <> 'DELETED' AND NEW.status = 'DELETED' THEN
    DELETE FROM app1_device_enrollment_windows WHERE account_id = OLD.id;
    DELETE FROM app1_terms_acceptances WHERE account_id = OLD.id;
    DELETE FROM app1_sessions WHERE account_id = OLD.id;
    DELETE FROM app1_devices WHERE account_id = OLD.id;

    UPDATE audit_events
       SET metadata = metadata - 'login' - 'deletedLogin' - 'devLogin'
     WHERE (target_kind = 'APP1_ACCOUNT' AND target_id = OLD.id::text)
        OR actor_id = OLD.id::text;

    NEW.login := 'deleted_' || replace(OLD.id::text, '-', '');
    NEW.credential_hash := 'deleted$' || OLD.id::text;
    NEW.failed_login_attempts := 0;
    NEW.failed_device_attempts := 0;
    NEW.security_locked_at := NULL;
    NEW.security_lock_reason := NULL;
    NEW.terms_version := NULL;
    NEW.privacy_version := NULL;
    NEW.terms_accepted_at := NULL;
    NEW.public_profile_id := NULL;
    NEW.public_name := NULL;
    NEW.public_name_normalized := NULL;
    NEW.public_name_verified_at := NULL;
    NEW.onboarding_completed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scrub_app1_account_on_delete ON app1_accounts;
CREATE TRIGGER trg_scrub_app1_account_on_delete
BEFORE UPDATE OF status ON app1_accounts
FOR EACH ROW
EXECUTE FUNCTION scrub_app1_account_on_delete();
