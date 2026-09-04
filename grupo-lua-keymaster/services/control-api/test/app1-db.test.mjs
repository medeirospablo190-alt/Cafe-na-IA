import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import pg from "pg";

const enabled = Boolean(process.env.DATABASE_URL);

function uuid() {
  return crypto.randomUUID();
}

test("App 1 migration supports LOCKED_SECURITY and scrubs definitive account deletion", { skip: !enabled }, async () => {
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await client.connect();

  const targetId = uuid();
  const devId = uuid();
  const deviceId = uuid();
  const sessionId = uuid();
  const enrollmentId = uuid();
  const targetLogin = `ci_adm_${targetId.replaceAll("-", "")}`;
  const devLogin = `ci_dev_${devId.replaceAll("-", "")}`;

  try {
    await client.query("BEGIN");

    await client.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, credential_ciphertext,
         terms_version, privacy_version, terms_accepted_at, public_profile_id,
         public_name, public_name_normalized, public_name_verified_at,
         onboarding_completed_at)
       VALUES
        ($1, $2, 'CI ADM visível', 'ADM', 'ACTIVE', 'temporary-hash', 'temporary-ciphertext',
         '1.0', '1.0', NOW(), $3, 'LuaTeste', 'luateste', NOW(), NOW()),
        ($4, $5, 'CI DEV visível', 'DEV', 'ACTIVE', 'temporary-dev-hash', 'temporary-dev-ciphertext',
         NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)`,
      [targetId, targetLogin, `usr_${targetId.slice(0, 8)}`, devId, devLogin]
    );

    await client.query(
      `UPDATE app1_accounts SET status = 'LOCKED_SECURITY' WHERE id = $1`,
      [targetId]
    );
    const locked = (await client.query(`SELECT status FROM app1_accounts WHERE id = $1`, [targetId])).rows[0];
    assert.equal(locked.status, "LOCKED_SECURITY");
    await client.query(`UPDATE app1_accounts SET status = 'ACTIVE' WHERE id = $1`, [targetId]);

    await client.query(
      `INSERT INTO app1_devices
        (id, account_id, fingerprint, device_token_hash, platform, is_primary, last_ip_hash)
       VALUES ($1, $2, 'device-fingerprint', 'device-token-hash', 'android', TRUE, 'ip-hash')`,
      [deviceId, targetId]
    );
    await client.query(
      `INSERT INTO app1_sessions
        (id, account_id, token_hash, expires_at, app1_device_id, session_kind)
       VALUES ($1, $2, 'session-token-hash', NOW() + INTERVAL '1 hour', $3, 'FULL')`,
      [sessionId, targetId, deviceId]
    );
    await client.query(
      `INSERT INTO app1_terms_acceptances
        (account_id, app1_session_id, terms_version, privacy_version)
       VALUES ($1, $2, '1.0', '1.0')`,
      [targetId, sessionId]
    );
    await client.query(
      `INSERT INTO app1_device_enrollment_windows
        (id, account_id, created_by_dev_account_id, status, expires_at)
       VALUES ($1, $2, $3, 'PENDING', NOW() + INTERVAL '10 minutes')`,
      [enrollmentId, targetId, devId]
    );
    await client.query(
      `INSERT INTO audit_events
        (actor_kind, actor_id, action, target_kind, target_id, metadata)
       VALUES ('SYSTEM', 'CI', 'CI_ACCOUNT_EVENT', 'APP1_ACCOUNT', $1, $2::jsonb)`,
      [targetId, JSON.stringify({ login: targetLogin, privateLogin: targetLogin, displayName: "CI ADM visível", keep: "audit-ok" })]
    );

    // Intentionally update only the status. The database trigger itself must
    // scrub every private/recoverable field even outside the normal API route.
    await client.query(
      `UPDATE app1_accounts
          SET status = 'DELETED', deleted_at = NOW()
        WHERE id = $1`,
      [targetId]
    );

    const account = (await client.query(
      `SELECT login, display_name, credential_hash, credential_ciphertext, status,
              public_profile_id, public_name, terms_version, terms_accepted_at,
              onboarding_completed_at
         FROM app1_accounts WHERE id = $1`,
      [targetId]
    )).rows[0];

    assert.equal(account.status, "DELETED");
    assert.match(account.login, /^deleted_[a-f0-9]+$/i);
    assert.equal(account.display_name, null);
    assert.match(account.credential_hash, /^deleted\$/);
    assert.equal(account.credential_ciphertext, null);
    assert.equal(account.public_profile_id, null);
    assert.equal(account.public_name, null);
    assert.equal(account.terms_version, null);
    assert.equal(account.terms_accepted_at, null);
    assert.equal(account.onboarding_completed_at, null);

    const counts = (await client.query(
      `SELECT
        (SELECT COUNT(*)::int FROM app1_devices WHERE account_id = $1) AS devices,
        (SELECT COUNT(*)::int FROM app1_sessions WHERE account_id = $1) AS sessions,
        (SELECT COUNT(*)::int FROM app1_terms_acceptances WHERE account_id = $1) AS terms,
        (SELECT COUNT(*)::int FROM app1_device_enrollment_windows WHERE account_id = $1) AS enrollments`,
      [targetId]
    )).rows[0];
    assert.deepEqual(counts, { devices: 0, sessions: 0, terms: 0, enrollments: 0 });

    const auditMetadata = (await client.query(
      `SELECT metadata FROM audit_events
        WHERE target_kind = 'APP1_ACCOUNT' AND target_id = $1 AND action = 'CI_ACCOUNT_EVENT'
        LIMIT 1`,
      [targetId]
    )).rows[0]?.metadata;
    assert.equal(auditMetadata.login, undefined);
    assert.equal(auditMetadata.privateLogin, undefined);
    assert.equal(auditMetadata.displayName, undefined);
    assert.equal(auditMetadata.keep, "audit-ok");

    await client.query("ROLLBACK");
  } finally {
    await client.end();
  }
});
