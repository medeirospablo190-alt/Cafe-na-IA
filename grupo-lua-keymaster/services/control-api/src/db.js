import pg from "pg";

const { Pool } = pg;

const ssl = String(process.env.DATABASE_SSL || "true").toLowerCase() === "true"
  ? { rejectUnauthorized: false }
  : false;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000
});

export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

export async function audit(client, {
  actorKind,
  actorId = null,
  action,
  targetKind = null,
  targetId = null,
  metadata = {}
}) {
  await client.query(
    `INSERT INTO audit_events
      (actor_kind, actor_id, action, target_kind, target_id, metadata)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
    [actorKind, actorId, action, targetKind, targetId, JSON.stringify(metadata)]
  );
}
