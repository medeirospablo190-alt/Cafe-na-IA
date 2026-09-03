import crypto from "crypto";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import pg from "pg";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const migrationsDir = path.join(__dirname, "../migrations");
const { Client } = pg;
const client = new Client({
  connectionString: process.env.DATABASE_URL,
  ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true" ? { rejectUnauthorized: false } : false
});

const MIGRATION_LOCK_ID = 731928411;

function checksum(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

await client.connect();
let lockHeld = false;
try {
  await client.query("SELECT pg_advisory_lock($1)", [MIGRATION_LOCK_ID]);
  lockHeld = true;

  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name TEXT PRIMARY KEY,
      checksum TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const appliedCount = Number((await client.query("SELECT COUNT(*)::int AS count FROM schema_migrations")).rows[0]?.count || 0);
  const existingCoreTable = (await client.query("SELECT to_regclass('public.app1_accounts') AS name")).rows[0]?.name;
  if (existingCoreTable && appliedCount === 0) {
    throw new Error(
      "LEGACY_DATABASE_REQUIRES_BASELINE: o banco já possui tabelas do GRUPO LUA, mas não possui histórico schema_migrations. " +
      "Não reaplique migrations automaticamente; faça baseline/migração assistida antes de usar este banco."
    );
  }

  const files = (await fs.readdir(migrationsDir))
    .filter((name) => /^\d+_.+\.sql$/i.test(name))
    .sort((a, b) => a.localeCompare(b));

  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), "utf8");
    const fileChecksum = checksum(sql);
    const existing = (await client.query(
      "SELECT checksum FROM schema_migrations WHERE name = $1 LIMIT 1",
      [file]
    )).rows[0];

    if (existing) {
      if (existing.checksum !== fileChecksum) {
        throw new Error(`MIGRATION_CHECKSUM_MISMATCH: ${file} foi alterada depois de aplicada.`);
      }
      console.log(`Migration ${file} já aplicada; ignorando.`);
      continue;
    }

    await client.query("BEGIN");
    try {
      await client.query(sql);
      await client.query(
        "INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)",
        [file, fileChecksum]
      );
      await client.query("COMMIT");
      console.log(`Migration ${file} aplicada.`);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      throw error;
    }
  }
} finally {
  if (lockHeld) await client.query("SELECT pg_advisory_unlock($1)", [MIGRATION_LOCK_ID]).catch(() => {});
  await client.end();
}
