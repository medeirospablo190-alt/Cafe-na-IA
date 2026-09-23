import crypto from "crypto";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import pg from "pg";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const migrationsDir = path.join(__dirname, "../migrations");
const { Client } = pg;

if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL is required");
}

const client = new Client({
  connectionString: process.env.DATABASE_URL,
  ssl: String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
    ? { rejectUnauthorized: false }
    : false,
});

const LOCK_ID = 1520062401;

function checksum(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

await client.connect();
let lockHeld = false;

try {
  await client.query("SELECT pg_advisory_lock($1)", [LOCK_ID]);
  lockHeld = true;

  await client.query("CREATE SCHEMA IF NOT EXISTS cafeina_ai");
  await client.query(`
    CREATE TABLE IF NOT EXISTS cafeina_ai.schema_migrations (
      name TEXT PRIMARY KEY,
      checksum TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const files = (await fs.readdir(migrationsDir))
    .filter((name) => /^\d+_.+\.sql$/i.test(name))
    .sort((a, b) => a.localeCompare(b));

  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), "utf8");
    const digest = checksum(sql);
    const existing = (await client.query(
      "SELECT checksum FROM cafeina_ai.schema_migrations WHERE name = $1 LIMIT 1",
      [file]
    )).rows[0];

    if (existing) {
      if (existing.checksum !== digest) {
        throw new Error(`MIGRATION_CHECKSUM_MISMATCH: ${file}`);
      }
      continue;
    }

    await client.query("BEGIN");
    try {
      await client.query(sql);
      await client.query(
        "INSERT INTO cafeina_ai.schema_migrations (name, checksum) VALUES ($1, $2)",
        [file, digest]
      );
      await client.query("COMMIT");
      console.log(`Migration ${file} applied.`);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      throw error;
    }
  }
} finally {
  if (lockHeld) {
    await client.query("SELECT pg_advisory_unlock($1)", [LOCK_ID]).catch(() => {});
  }
  await client.end();
}
