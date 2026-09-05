-- App 1 — propriedade privada de menus, fontes Lua protegidas e exclusão limpa de chaves.
-- Mantém compatibilidade com menus antigos: owner_account_id permanece NULL para legado.

ALTER TABLE managed_menus
  ADD COLUMN IF NOT EXISTS owner_account_id UUID REFERENCES app1_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_kind TEXT NOT NULL DEFAULT 'REMOTE_URL',
  ADD COLUMN IF NOT EXISTS source_ciphertext TEXT,
  ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;

ALTER TABLE managed_menus
  DROP CONSTRAINT IF EXISTS managed_menus_source_kind_check;

ALTER TABLE managed_menus
  ADD CONSTRAINT managed_menus_source_kind_check
  CHECK (source_kind IN ('REMOTE_URL', 'INLINE_ENCRYPTED'));

CREATE INDEX IF NOT EXISTS idx_managed_menus_owner_status
  ON managed_menus(owner_account_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_managed_menus_suspended_until
  ON managed_menus(suspended_until)
  WHERE status = 'SUSPENDED' AND suspended_until IS NOT NULL;

ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS name TEXT,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_menu_access_keys_visible
  ON menu_access_keys(menu_id, created_at DESC)
  WHERE deleted_at IS NULL AND status <> 'REVOKED';

CREATE TABLE IF NOT EXISTS menu_source_tickets (
  id UUID PRIMARY KEY,
  menu_id UUID NOT NULL REFERENCES managed_menus(id) ON DELETE CASCADE,
  access_session_id UUID NOT NULL REFERENCES menu_access_sessions(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_menu_source_tickets_expiry
  ON menu_source_tickets(expires_at);

CREATE INDEX IF NOT EXISTS idx_menu_source_tickets_session
  ON menu_source_tickets(access_session_id);

-- Normaliza explicitamente o legado para o modo remoto.
UPDATE managed_menus
SET source_kind = 'REMOTE_URL'
WHERE source_kind IS NULL;
