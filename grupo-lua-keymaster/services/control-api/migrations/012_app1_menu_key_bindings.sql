-- Chaves FREE/VIP pertencem aos menus do App 1 e permanecem separadas
-- da credencial privada usada para entrar no aplicativo.
--
-- O App 1 pode registrar uma chave válida já entregue ao usuário. O servidor
-- guarda somente uma cópia cifrada ligada à conta para permitir copiar a
-- própria chave depois, sem expor o segredo em listagens/auditoria.

CREATE TABLE IF NOT EXISTS app1_menu_key_bindings (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  menu_key_id UUID NOT NULL REFERENCES menu_access_keys(id) ON DELETE CASCADE,
  key_ciphertext TEXT NOT NULL,
  key_hint TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_revealed_at TIMESTAMPTZ,
  UNIQUE (account_id, menu_key_id)
);

CREATE INDEX IF NOT EXISTS idx_app1_menu_key_bindings_account
  ON app1_menu_key_bindings(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app1_menu_key_bindings_key
  ON app1_menu_key_bindings(menu_key_id);

CREATE OR REPLACE FUNCTION purge_app1_menu_key_bindings_on_deleted_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'DELETED' AND OLD.status IS DISTINCT FROM 'DELETED' THEN
    DELETE FROM app1_menu_key_bindings WHERE account_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_purge_app1_menu_key_bindings_on_deleted_status ON app1_accounts;
CREATE TRIGGER trg_purge_app1_menu_key_bindings_on_deleted_status
AFTER UPDATE OF status ON app1_accounts
FOR EACH ROW
WHEN (NEW.status = 'DELETED' AND OLD.status IS DISTINCT FROM 'DELETED')
EXECUTE FUNCTION purge_app1_menu_key_bindings_on_deleted_status();

-- Limpa vínculos de contas que já estavam marcadas como DELETED antes da migration.
DELETE FROM app1_menu_key_bindings b
USING app1_accounts a
WHERE b.account_id = a.id AND a.status = 'DELETED';
