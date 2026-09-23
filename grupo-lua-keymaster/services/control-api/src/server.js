import express from "express";
import helmet from "helmet";
import { pool } from "./db.js";

const app = express();
const PORT = Number(process.env.PORT || 3100);

app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(express.json({ limit: "1mb", strict: true }));
app.use((_req, res, next) => {
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("Pragma", "no-cache");
  next();
});

app.get("/v1/health", async (_req, res) => {
  const database = await pool
    .query("SELECT NOW() AS now")
    .then((result) => ({ ok: true, serverTime: result.rows[0]?.now || null }))
    .catch(() => ({ ok: false, serverTime: null }));

  res.status(database.ok ? 200 : 503).json({
    ok: database.ok,
    service: "CAFEINA_CLOUD_API",
    database,
  });
});

app.get("/v1/system", async (_req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT key, value, updated_at
         FROM cafeina_ai.system_state
        ORDER BY key ASC`
    );
    res.json({ ok: true, state: rows });
  } catch (error) {
    next(error);
  }
});

app.use((_req, res) => {
  res.status(404).json({ ok: false, code: "NOT_FOUND", message: "Rota não encontrada." });
});

app.use((error, _req, res, _next) => {
  console.error("CAFEINA_CLOUD_API_ERROR", error?.message || error);
  res.status(500).json({ ok: false, code: "INTERNAL_ERROR", message: "Erro interno." });
});

const server = app.listen(PORT, () => {
  console.log(`CAFEINA Cloud API listening on :${PORT}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    server.close(async () => {
      await pool.end().catch(() => {});
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 5_000).unref();
  });
}
