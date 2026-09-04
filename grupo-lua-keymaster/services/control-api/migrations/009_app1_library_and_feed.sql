CREATE TABLE IF NOT EXISTS app1_library_items (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('CODE', 'LOADSTRING')),
  title TEXT NOT NULL,
  text_content TEXT NOT NULL,
  favorite BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app1_library_items_account_kind_updated_idx
  ON app1_library_items(account_id, kind, updated_at DESC);

CREATE INDEX IF NOT EXISTS app1_library_items_account_favorite_idx
  ON app1_library_items(account_id, favorite, updated_at DESC);

CREATE TABLE IF NOT EXISTS app1_feed_posts (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES app1_accounts(id) ON DELETE CASCADE,
  post_kind TEXT NOT NULL CHECK (post_kind IN ('CODE', 'LOADSTRING')),
  library_item_id TEXT NOT NULL REFERENCES app1_library_items(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app1_feed_posts_created_idx
  ON app1_feed_posts(created_at DESC);

CREATE INDEX IF NOT EXISTS app1_feed_posts_account_created_idx
  ON app1_feed_posts(account_id, created_at DESC);

CREATE OR REPLACE FUNCTION purge_app1_owned_content_on_deleted_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'DELETED' AND OLD.status IS DISTINCT FROM 'DELETED' THEN
    DELETE FROM app1_library_items WHERE account_id = NEW.id;
    DELETE FROM app1_feed_posts WHERE account_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app1_accounts_purge_owned_content_on_delete_status ON app1_accounts;
CREATE TRIGGER app1_accounts_purge_owned_content_on_delete_status
AFTER UPDATE OF status ON app1_accounts
FOR EACH ROW
EXECUTE FUNCTION purge_app1_owned_content_on_deleted_status();
