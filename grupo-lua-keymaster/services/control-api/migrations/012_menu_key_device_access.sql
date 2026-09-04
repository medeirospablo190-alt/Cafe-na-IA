-- Ciclo de acesso dos menus + vinculo por dispositivo.
-- FREE: no maximo 24h por liberacao; depois aguarda nova liberacao ADM.
-- VIP: dias, meses ou permanente.

ALTER TABLE menu_access_keys
  DROP CONSTRAINT IF EXISTS menu_access_keys_check;

ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS access_state TEXT NOT NULL DEFAULT 'READY',
  ADD COLUMN IF NOT EXISTS duration_value INTEGER,
  ADD COLUMN IF NOT EXISTS duration_unit TEXT,
  ADD COLUMN IF NOT EXISTS access_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS access_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bound_device_hash TEXT,
  ADD COLUMN IF NOT EXISTS bound_device_hint TEXT,
  ADD COLUMN IF NOT EXISTS bound_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_access_keys_access_state_check'
  ) THEN
    ALTER TABLE menu_access_keys
      ADD CONSTRAINT menu_access_keys_access_state_check
      CHECK (access_state IN ('READY', 'ACTIVE', 'WAITING_ADMIN', 'EXPIRED'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_access_keys_duration_unit_check'
  ) THEN
    ALTER TABLE menu_access_keys
      ADD CONSTRAINT menu_access_keys_duration_unit_check
      CHECK (duration_unit IS NULL OR duration_unit IN ('HOURS', 'DAYS', 'MONTHS', 'PERMANENT'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_access_keys_duration_value_check'
  ) THEN
    ALTER TABLE menu_access_keys
      ADD CONSTRAINT menu_access_keys_duration_value_check
      CHECK (duration_value IS NULL OR duration_value > 0);
  END IF;
END $$;

ALTER TABLE menu_access_sessions
  ADD COLUMN IF NOT EXISTS device_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_menu_access_keys_access_state
  ON menu_access_keys(access_state);
CREATE INDEX IF NOT EXISTS idx_menu_access_keys_bound_device
  ON menu_access_keys(bound_device_hash);
CREATE INDEX IF NOT EXISTS idx_menu_access_sessions_device
  ON menu_access_sessions(device_hash);

-- Chaves antigas entram de forma conservadora no novo modelo.
-- FREE antiga exige nova liberacao ADM para garantir o limite de 24h.
UPDATE menu_access_keys
SET access_state = 'WAITING_ADMIN',
    duration_value = 24,
    duration_unit = 'HOURS',
    access_started_at = NULL,
    access_until = NULL,
    expires_at = NULL
WHERE kind = 'FREE'
  AND duration_unit IS NULL;

-- VIP antiga passa a ser permanente ate revogacao, mantendo compatibilidade.
UPDATE menu_access_keys
SET access_state = 'READY',
    duration_value = NULL,
    duration_unit = 'PERMANENT',
    access_started_at = NULL,
    access_until = NULL,
    expires_at = NULL
WHERE kind = 'VIP'
  AND duration_unit IS NULL;
