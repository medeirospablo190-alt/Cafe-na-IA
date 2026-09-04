import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import pg from "pg";

const enabled = Boolean(process.env.DATABASE_URL);

function uuid() {
  return crypto.randomUUID();
}

test("App 1 library survives credential/status changes and is purged only on definitive deletion", { skip: !enabled }, async () => {
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
    ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
      ? { rejectUnauthorized: false }
      : false
  });
  await client.connect();

  const accountId = uuid();
  const codeId = uuid();
  const loadstringId = uuid();
  const postId = uuid();
  const login = `ci_library_${accountId.replaceAll("-", "")}`;

  try {
    await client.query("BEGIN");

    await client.query(
      `INSERT INTO app1_accounts
        (id, login, display_name, role, status, credential_hash, credential_ciphertext,
         terms_version, privacy_version, terms_accepted_at, public_profile_id,
         public_name, public_name_normalized, public_name_verified_at,
         onboarding_completed_at)
       VALUES
        ($1, $2, 'Biblioteca CI', 'ADM', 'ACTIVE', 'credential-v1', 'cipher-v1',
         '1.0', '1.0', NOW(), $3, 'BibliotecaTeste', 'bibliotecateste', NOW(), NOW())`,
      [accountId, login, `usr_${accountId.slice(0, 8)}`]
    );

    await client.query(
      `INSERT INTO app1_library_items
        (id, account_id, kind, title, text_content, favorite)
       VALUES
        ($1, $3, 'CODE', 'Código principal', 'print("codigo")', TRUE),
        ($2, $3, 'LOADSTRING', 'Loader principal', 'loadstring(game:HttpGet("https://example.invalid"))()', FALSE)`,
      [codeId, loadstringId, accountId]
    );

    await client.query(
      `INSERT INTO app1_feed_posts (id, account_id, post_kind, library_item_id)
       VALUES ($1, $2, 'CODE', $3)`,
      [postId, accountId, codeId]
    );

    // Trocar a credencial e encerrar/recriar sessões não pode alterar a
    // biblioteca, pois os arquivos pertencem ao ID permanente da conta.
    await client.query(
      `UPDATE app1_accounts
          SET credential_hash = 'credential-v2',
              credential_ciphertext = 'cipher-v2',
              updated_at = NOW()
        WHERE id = $1`,
      [accountId]
    );

    let counts = (await client.query(
      `SELECT
        (SELECT COUNT(*)::int FROM app1_library_items WHERE account_id = $1) AS items,
        (SELECT COUNT(*)::int FROM app1_feed_posts WHERE account_id = $1) AS posts`,
      [accountId]
    )).rows[0];
    assert.deepEqual(counts, { items: 2, posts: 1 });

    // Bloqueio/suspensão também não é exclusão de dados.
    await client.query(`UPDATE app1_accounts SET status = 'SUSPENDED' WHERE id = $1`, [accountId]);
    counts = (await client.query(
      `SELECT
        (SELECT COUNT(*)::int FROM app1_library_items WHERE account_id = $1) AS items,
        (SELECT COUNT(*)::int FROM app1_feed_posts WHERE account_id = $1) AS posts`,
      [accountId]
    )).rows[0];
    assert.deepEqual(counts, { items: 2, posts: 1 });

    await client.query(`UPDATE app1_accounts SET status = 'ACTIVE' WHERE id = $1`, [accountId]);
    const favorite = (await client.query(
      `SELECT favorite FROM app1_library_items WHERE id = $1`,
      [codeId]
    )).rows[0]?.favorite;
    assert.equal(favorite, true);

    // Somente a exclusão definitiva do acesso pelo Keymaster deve disparar
    // a limpeza da biblioteca e das publicações dependentes no servidor.
    await client.query(
      `UPDATE app1_accounts SET status = 'DELETED', deleted_at = NOW() WHERE id = $1`,
      [accountId]
    );

    counts = (await client.query(
      `SELECT
        (SELECT COUNT(*)::int FROM app1_library_items WHERE account_id = $1) AS items,
        (SELECT COUNT(*)::int FROM app1_feed_posts WHERE account_id = $1) AS posts`,
      [accountId]
    )).rows[0];
    assert.deepEqual(counts, { items: 0, posts: 0 });

    await client.query("ROLLBACK");
  } finally {
    await client.end();
  }
});
