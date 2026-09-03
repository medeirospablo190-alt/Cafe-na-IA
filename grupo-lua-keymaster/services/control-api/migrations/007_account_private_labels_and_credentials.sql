ALTER TABLE app1_accounts
  ADD COLUMN IF NOT EXISTS display_name TEXT;

ALTER TABLE app1_accounts
  ADD COLUMN IF NOT EXISTS credential_ciphertext TEXT;

UPDATE app1_accounts
   SET display_name = CASE
     WHEN role = 'DEV' THEN 'Acesso DEV ' || UPPER(SUBSTRING(id::text, 1, 4))
     ELSE 'Acesso ADM ' || UPPER(SUBSTRING(id::text, 1, 4))
   END
 WHERE display_name IS NULL OR BTRIM(display_name) = '';

CREATE INDEX IF NOT EXISTS idx_app1_accounts_display_name
  ON app1_accounts (LOWER(display_name));
