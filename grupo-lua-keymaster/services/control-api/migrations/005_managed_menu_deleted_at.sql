CREATE OR REPLACE FUNCTION set_managed_menu_deleted_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'DELETED' AND OLD.status IS DISTINCT FROM 'DELETED' THEN
    NEW.deleted_at = COALESCE(NEW.deleted_at, NOW());
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_managed_menu_deleted_at ON managed_menus;
CREATE TRIGGER trg_managed_menu_deleted_at
BEFORE UPDATE OF status ON managed_menus
FOR EACH ROW
EXECUTE FUNCTION set_managed_menu_deleted_at();

UPDATE managed_menus
SET deleted_at = COALESCE(deleted_at, updated_at, NOW())
WHERE status = 'DELETED'
  AND deleted_at IS NULL;
