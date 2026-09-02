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

await client.connect();
try {
  const files = (await fs.readdir(migrationsDir))
    .filter((name) => /^\d+_.+\.sql$/i.test(name))
    .sort((a, b) => a.localeCompare(b));

  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), "utf8");
    await client.query("BEGIN");
    try {
      await client.query(sql);
      await client.query("COMMIT");
      console.log(`Migration ${file} aplicada.`);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      throw error;
    }
  }
} finally {
  await client.end();
}
