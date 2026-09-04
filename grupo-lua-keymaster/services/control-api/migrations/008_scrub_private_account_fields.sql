-- Harden definitive account deletion for fields introduced after migration 006.
-- The application route already clears credential_ciphertext, but keeping the
-- database trigger authoritative prevents a direct status update from leaving
-- recoverable credentials behind.

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
       SET metadata = metadata - 'login' - 'deletedLogin' - 'devLogin' - 'privateLogin' - 'displayName'
     WHERE (target_kind = 'APP1_ACCOUNT' AND target_id = OLD.id::text)
        OR actor_id = OLD.id::text;

    NEW.login := 'deleted_' || replace(OLD.id::text, '-', '');
    NEW.display_name := NULL;
    NEW.credential_hash := 'deleted$' || OLD.id::text;
    NEW.credential_ciphertext := NULL;
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
