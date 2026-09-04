-- KEYMASTER critical completion:
-- 1) global App 1 suspension revokes every active App 1 session;
-- 2) definitive account deletion removes owned App 1 data and stale auth traces;
-- 3) legacy DELETED accounts are scrubbed once so old rows do not retain data.

CREATE OR REPLACE FUNCTION revoke_app1_sessions_on_global_suspension()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.key = 'app1_maintenance'
     AND COALESCE((NEW.value->>'enabled')::boolean, false) THEN
    UPDATE app1_sessions
       SET revoked_at = COALESCE(revoked_at, NOW())
     WHERE revoked_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_revoke_app1_sessions_on_global_suspension ON system_settings;
CREATE TRIGGER trg_revoke_app1_sessions_on_global_suspension
AFTER INSERT OR UPDATE OF value ON system_settings
FOR EACH ROW
WHEN (NEW.key = 'app1_maintenance')
EXECUTE FUNCTION revoke_app1_sessions_on_global_suspension();

-- If this migration is applied while App 1 is already suspended, immediately
-- invalidate sessions that predate the trigger.
UPDATE app1_sessions
   SET revoked_at = COALESCE(revoked_at, NOW())
 WHERE revoked_at IS NULL
   AND EXISTS (
     SELECT 1
       FROM system_settings
      WHERE key = 'app1_maintenance'
        AND COALESCE((value->>'enabled')::boolean, false)
   );

-- Extend the existing AFTER UPDATE deletion trigger. Future App 1-owned tables
-- should be added here as they are introduced (photos, videos, chats, etc.).
CREATE OR REPLACE FUNCTION purge_app1_owned_content_on_deleted_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'DELETED' AND OLD.status IS DISTINCT FROM 'DELETED' THEN
    DELETE FROM app1_feed_posts WHERE account_id = NEW.id;
    DELETE FROM app1_library_items WHERE account_id = NEW.id;
    DELETE FROM app1_login_attempts WHERE account_id = NEW.id;
    DELETE FROM critical_authorizations WHERE dev_account_id = NEW.id;
    DELETE FROM app1_device_enrollment_windows
     WHERE account_id = NEW.id OR created_by_dev_account_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

-- One-time cleanup for accounts that were already DELETED before this migration.
DELETE FROM app1_feed_posts p
USING app1_accounts a
WHERE a.status = 'DELETED' AND p.account_id = a.id;

DELETE FROM app1_library_items i
USING app1_accounts a
WHERE a.status = 'DELETED' AND i.account_id = a.id;

DELETE FROM app1_login_attempts l
USING app1_accounts a
WHERE a.status = 'DELETED' AND l.account_id = a.id;

DELETE FROM critical_authorizations c
USING app1_accounts a
WHERE a.status = 'DELETED' AND c.dev_account_id = a.id;

DELETE FROM app1_device_enrollment_windows w
USING app1_accounts a
WHERE a.status = 'DELETED'
  AND (w.account_id = a.id OR w.created_by_dev_account_id = a.id);

DELETE FROM app1_terms_acceptances t
USING app1_accounts a
WHERE a.status = 'DELETED' AND t.account_id = a.id;

DELETE FROM app1_sessions s
USING app1_accounts a
WHERE a.status = 'DELETED' AND s.account_id = a.id;

DELETE FROM app1_devices d
USING app1_accounts a
WHERE a.status = 'DELETED' AND d.account_id = a.id;

UPDATE audit_events e
   SET metadata = metadata
     - 'login'
     - 'deletedLogin'
     - 'devLogin'
     - 'privateLogin'
     - 'displayName'
 WHERE EXISTS (
   SELECT 1
     FROM app1_accounts a
    WHERE a.status = 'DELETED'
      AND (
        (e.target_kind = 'APP1_ACCOUNT' AND e.target_id = a.id::text)
        OR e.actor_id = a.id::text
      )
 );

UPDATE app1_accounts
   SET login = 'deleted_' || replace(id::text, '-', ''),
       display_name = NULL,
       credential_hash = 'deleted$' || id::text,
       credential_ciphertext = NULL,
       failed_login_attempts = 0,
       failed_device_attempts = 0,
       security_locked_at = NULL,
       security_lock_reason = NULL,
       terms_version = NULL,
       privacy_version = NULL,
       terms_accepted_at = NULL,
       public_profile_id = NULL,
       public_name = NULL,
       public_name_normalized = NULL,
       public_name_verified_at = NULL,
       onboarding_completed_at = NULL,
       updated_at = NOW()
 WHERE status = 'DELETED';
