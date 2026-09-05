ALTER TABLE menu_access_keys
  ADD COLUMN IF NOT EXISTS key_value_encrypted TEXT;

COMMENT ON COLUMN menu_access_keys.key_value_encrypted IS
  'Valor original da chave criptografado no servidor para revelacao autenticada no App 1. Nunca enviar em listagens.';
