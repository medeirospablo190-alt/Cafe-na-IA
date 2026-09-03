import express from "express";
import helmet from "helmet";
import crypto from "crypto";
import { pool, withTransaction, audit } from "./db.js";
import {
  createApp1Credential,
  deriveDeviceFingerprint,
  hashSecret,
  normalizeLogin,
  privacyHash,
  randomId,
  randomToken,
  tokenHash,
  verifySecret
} from "./security.js";
import { verifyAppIntegrity } from "./integrity.js";
import { registerMenuRoutes } from "./menu-routes.js";
import { registerApp1Routes } from "./app1-routes.js";

const app = express();
const PORT = Number(process.env.PORT || 3100);
const KEYMASTER_MAX_CHARS = 16_384;
const KEYMASTER_MAX_FAILED = 3;
const KEYMASTER_LOCK_MS = 24 * 60 * 60 * 1000;
const KEYMASTER_SESSION_MS = 12 * 60 * 60 * 1000;
const APP1_SESSION_MS = 12 * 60 * 60 * 1000;
const CRITICAL_AUTH_MS = 2 * 60 * 1000;
const CRITICAL_ACTIONS = new Set([
  "APP1_RESTART",
  "APP1_MAINTENANCE_ON",
  "APP1_MAINTENANCE_OFF",
  "DELETE_APP1_ACCOUNT",
  "DELETE_MANAGED_MENU",
  "UNLOCK_APP1_ACCOUNT",
  "AUTHORIZE_APP1_DEVICE",
  "REVOKE_APP1_DEVICE"
]);

app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(express.json({ limit: "64kb" }));
app.use((_req, res, next) => {
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("Pragma", "no-cache");
  next();
});

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function ipHash(req) {
  return privacyHash(req.ip || req.socket?.remoteAddress || "unknown", "ip");
}

async function getKeymasterSession(req) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return null;
  const hash = tokenHash(token);
  const { rows } = await pool.query(
    `SELECT s.id, s.device_id, s.expires_at, d.fingerprint
       FROM keymaster_sessions s
       JOIN keymaster_devices d ON d.id = s.device_id
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > NOW()
      LIMIT 1`,
    [hash]
  );
  return rows[0] || null;
}

async function requireKeymaster(req, res, next) {
  try {
    const session = await getKeymasterSession(req);
    if (!session) return sendError(res, 401, "UNAUTHORIZED", "Sessão Keymaster inválida ou expirada.");
    req.keymasterSession = session;
    next();
  } catch (error) {
    next(error);
  }
}

function deviceInput(req) {
  const body = req.body || {};
  return {
    platform: String(body.platform || "unknown").slice(0, 20),
    nativeDeviceId: String(body.nativeDeviceId || "").slice(0, 300),
    integrityKeyId: String(body.integrityKeyId || "").slice(0, 500),
    installationId: String(body.installationId || "").slice(0, 200)
  };
}

function criticalScope(action, targetId = "") {
  const normalized = String(action || "").toUpperCase();
  if (!CRITICAL_ACTIONS.has(normalized)) return "";
  if ([
    "DELETE_APP1_ACCOUNT",
    "DELETE_MANAGED_MENU",
    "UNLOCK_APP1_ACCOUNT",
    "AUTHORIZE_APP1_DEVICE",
    "REVOKE_APP1_DEVICE"
  ].includes(normalized)) {
    const target = String(targetId || "").trim();
    return target ? `${normalized}:${target}` : "";
  }
  return normalized;
}

async function getApp1Maintenance() {
  const { rows } = await pool.query(
    `SELECT value FROM system_settings WHERE key = 'app1_maintenance' LIMIT 1`
  );
  const value = rows[0]?.value;
  return Boolean(value?.enabled);
}

async function setApp1Maintenance(client, enabled, actorSessionId) {
  const value = JSON.stringify({ enabled: Boolean(enabled), changedAt: new Date().toISOString(), changedBy: actorSessionId });
  await client.query(
    `INSERT INTO system_settings (key, value, updated_at)
     VALUES ('app1_maintenance', $1::jsonb, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [value]
  );
}

async function createCriticalAuthorization({ sessionId, action, targetId, devLogin, devCredential }) {
  const scope = criticalScope(action, targetId);
  if (!scope) return { error: "INVALID_CRITICAL_ACTION" };
  const login = normalizeLogin(devLogin);
  if (!login || !devCredential) return { error: "DEV_REAUTH_REQUIRED" };

  const dev = (await pool.query(
    `SELECT id, login, role, status, credential_hash FROM app1_accounts WHERE login = $1 LIMIT 1`,
    [login]
  )).rows[0];
  if (!dev || dev.role !== "DEV" || dev.status !== "ACTIVE" || !(await verifySecret(devCredential, dev.credential_hash))) {
    return { error: "INVALID_DEV_CREDENTIAL" };
  }

  const token = randomToken(48);
  const id = randomId();
  const expiresAt = new Date(Date.now() + CRITICAL_AUTH_MS);
  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO critical_authorizations
        (id, keymaster_session_id, dev_account_id, action, token_hash, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, sessionId, dev.id, scope, tokenHash(`critical:${token}`), expiresAt]
    );
    await audit(client, {
      actorKind: "DEV",
      actorId: dev.id,
      action: "CRITICAL_AUTHORIZATION_CREATED",
      targetKind: "CRITICAL_ACTION",
      targetId: scope,
      metadata: { keymasterSessionId: sessionId, expiresAt }
    });
  });
  return { token, expiresAt, scope, dev: { id: dev.id, login: dev.login } };
}

async function consumeCriticalAuthorization({ sessionId, token, action, targetId = "" }) {
  const scope = criticalScope(action, targetId);
  if (!scope || !token) return null;
  const hash = tokenHash(`critical:${token}`);
  return withTransaction(async (client) => {
    const row = (await client.query(
      `SELECT ca.id, ca.dev_account_id, ca.action, ca.expires_at, a.login
         FROM critical_authorizations ca
         JOIN app1_accounts a ON a.id = ca.dev_account_id
        WHERE ca.keymaster_session_id = $1
          AND ca.token_hash = $2
          AND ca.action = $3
          AND ca.used_at IS NULL
          AND ca.expires_at > NOW()
          AND a.role = 'DEV'
          AND a.status = 'ACTIVE'
        FOR UPDATE OF ca`,
      [sessionId, hash, scope]
    )).rows[0];
    if (!row) return null;
    await client.query(`UPDATE critical_authorizations SET used_at = NOW() WHERE id = $1`, [row.id]);
    return row;
  });
}

async function callRestartWebhook(actor) {
  const enabled = String(process.env.CRITICAL_ACTIONS_ENABLED || "false").toLowerCase() === "true";
  const url = String(process.env.APP1_RESTART_WEBHOOK || "").trim();
  if (!enabled || !url) return { ok: false, reason: "RESTART_NOT_CONFIGURED" };
  const token = String(process.env.APP1_CONTROL_WEBHOOK_TOKEN || "").trim();
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify({ action: "APP1_RESTART", requestedAt: new Date().toISOString(), actor }),
    signal: AbortSignal.timeout(10_000)
  });
  return { ok: response.ok, status: response.status };
}

app.get("/v1/health", async (_req, res) => {
  const db = await pool.query("SELECT NOW() AS now").then(() => true).catch(() => false);
  res.status(db ? 200 : 503).json({
    ok: db,
    service: "GRUPO_LUA_CONTROL_API",
    roles: ["ADM", "DEV"],
    keymaster: {
      maxKeyChars: KEYMASTER_MAX_CHARS,
      maxFailedAttempts: KEYMASTER_MAX_FAILED,
      lockHours: 24
    },
    app1: {
      sessionHours: 24,
      provisionalMinutes: 15,
      maxFailedAttempts: 3,
      maxActiveDevices: 2,
      deviceEnrollmentMinutes: 10
    }
  });
});

app.post("/v1/keymaster/login", async (req, res, next) => {
  try {
    const accessKey = String(req.body?.accessKey || "");
    if (!accessKey || accessKey.length > KEYMASTER_MAX_CHARS) {
      return sendError(res, 400, "INVALID_REQUEST", "Chave ausente ou acima do limite suportado.");
    }
    const device = deviceInput(req);
    if (!device.nativeDeviceId && !device.integrityKeyId && !device.installationId) {
      return sendError(res, 400, "DEVICE_ID_REQUIRED", "Identificação do dispositivo ausente.");
    }

    const requestHash = crypto.createHash("sha256")
      .update(`${device.platform}\0${device.nativeDeviceId}\0${device.integrityKeyId}\0${device.installationId}`)
      .digest("base64url");
    const integrity = await verifyAppIntegrity({
      platform: device.platform,
      integrityProof: req.body?.integrityProof || null,
      requestHash
    });
    if (!integrity.accepted) {
      return sendError(res, 403, "INTEGRITY_REQUIRED", "O dispositivo/aplicativo não passou na verificação de integridade.");
    }

    const fingerprint = deriveDeviceFingerprint(device);
    const nativeIdHash = device.nativeDeviceId ? privacyHash(device.nativeDeviceId, "native-device-id") : null;
    const configuredHash = String(process.env.KEYMASTER_ACCESS_HASH || "");
    if (!configuredHash) return sendError(res, 503, "KEYMASTER_NOT_CONFIGURED", "KEYMASTER_ACCESS_HASH não configurado no servidor.");

    const result = await withTransaction(async (client) => {
      let row = (await client.query(
        `SELECT * FROM keymaster_devices WHERE fingerprint = $1 FOR UPDATE`,
        [fingerprint]
      )).rows[0];

      if (!row) {
        row = (await client.query(
          `INSERT INTO keymaster_devices
            (fingerprint, platform, native_device_id_hash, integrity_key_id, last_ip_hash)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING *`,
          [fingerprint, device.platform, nativeIdHash, device.integrityKeyId || null, ipHash(req)]
        )).rows[0];
      }

      if (row.locked_until && new Date(row.locked_until).getTime() > Date.now()) {
        await audit(client, {
          actorKind: "DEVICE",
          actorId: String(row.id),
          action: "KEYMASTER_LOGIN_BLOCKED",
          metadata: { integrityVerified: integrity.verified }
        });
        return { locked: true, lockedUntil: row.locked_until };
      }

      if (row.locked_until && new Date(row.locked_until).getTime() <= Date.now()) {
        await client.query(
          `UPDATE keymaster_devices SET failed_attempts = 0, locked_until = NULL WHERE id = $1`,
          [row.id]
        );
        row.failed_attempts = 0;
        row.locked_until = null;
      }

      const valid = await verifySecret(accessKey, configuredHash);
      if (!valid) {
        const failures = Number(row.failed_attempts || 0) + 1;
        const shouldLock = failures >= KEYMASTER_MAX_FAILED;
        const lockedUntil = shouldLock ? new Date(Date.now() + KEYMASTER_LOCK_MS) : null;
        await client.query(
          `UPDATE keymaster_devices
              SET failed_attempts = $2,
                  locked_until = $3,
                  last_seen_at = NOW(),
                  last_ip_hash = $4
            WHERE id = $1`,
          [row.id, failures, lockedUntil, ipHash(req)]
        );
        await audit(client, {
          actorKind: "DEVICE",
          actorId: String(row.id),
          action: shouldLock ? "KEYMASTER_DEVICE_LOCKED_24H" : "KEYMASTER_LOGIN_FAILED",
          metadata: { failures: Math.min(failures, KEYMASTER_MAX_FAILED), integrityVerified: integrity.verified }
        });
        return { invalid: true, failures, lockedUntil };
      }

      await client.query(
        `UPDATE keymaster_devices
            SET failed_attempts = 0,
                locked_until = NULL,
                last_seen_at = NOW(),
                last_ip_hash = $2
          WHERE id = $1`,
        [row.id, ipHash(req)]
      );

      const token = randomToken(48);
      const sessionId = randomId();
      const expiresAt = new Date(Date.now() + KEYMASTER_SESSION_MS);
      await client.query(
        `INSERT INTO keymaster_sessions (id, device_id, token_hash, expires_at)
         VALUES ($1, $2, $3, $4)`,
        [sessionId, row.id, tokenHash(token), expiresAt]
      );
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: sessionId,
        action: "KEYMASTER_LOGIN_SUCCESS",
        metadata: { deviceId: row.id, integrityVerified: integrity.verified }
      });
      return { token, expiresAt, sessionId };
    });

    if (result.locked) {
      return sendError(res, 423, "DEVICE_LOCKED", "Este dispositivo está bloqueado por 24 horas após três tentativas inválidas.", {
        lockedUntil: result.lockedUntil,
        serverTime: new Date().toISOString()
      });
    }
    if (result.invalid) {
      const remaining = Math.max(0, KEYMASTER_MAX_FAILED - result.failures);
      if (result.lockedUntil) {
        return sendError(res, 423, "DEVICE_LOCKED", "Terceira tentativa inválida. Login bloqueado por 24 horas.", {
          attemptsRemaining: 0,
          lockedUntil: result.lockedUntil,
          serverTime: new Date().toISOString()
        });
      }
      return sendError(res, 401, "INVALID_KEYMASTER_KEY", "Chave de acesso inválida.", { attemptsRemaining: remaining });
    }

    return res.json({
      ok: true,
      token: result.token,
      expiresAt: result.expiresAt,
      serverTime: new Date().toISOString(),
      integrityVerified: integrity.verified
    });
  } catch (error) {
    next(error);
  }
});

app.post("/v1/keymaster/logout", requireKeymaster, async (req, res, next) => {
  try {
    await pool.query(`UPDATE keymaster_sessions SET revoked_at = NOW() WHERE id = $1`, [req.keymasterSession.id]);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.get("/v1/keymaster/session", requireKeymaster, async (req, res) => {
  res.json({
    ok: true,
    session: {
      id: req.keymasterSession.id,
      expiresAt: req.keymasterSession.expires_at,
      deviceId: req.keymasterSession.device_id
    }
  });
});

app.get("/v1/keymaster/system-status", requireKeymaster, async (_req, res, next) => {
  try {
    res.json({ ok: true, app1Maintenance: await getApp1Maintenance() });
  } catch (error) { next(error); }
});

app.get("/v1/keymaster/dashboard", requireKeymaster, async (_req, res, next) => {
  try {
    const [accountsResult, sessionsResult, auditResult, app1Maintenance] = await Promise.all([
      pool.query(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE status = 'ACTIVE')::int AS active,
           COUNT(*) FILTER (WHERE status = 'SUSPENDED')::int AS suspended,
           COUNT(*) FILTER (WHERE role = 'ADM')::int AS adm,
           COUNT(*) FILTER (WHERE role = 'DEV')::int AS dev
         FROM app1_accounts
         WHERE status <> 'DELETED'`
      ),
      pool.query(
        `SELECT COUNT(*)::int AS active_sessions
           FROM app1_sessions
          WHERE revoked_at IS NULL AND expires_at > NOW()`
      ),
      pool.query(
        `SELECT COUNT(*)::int AS events_24h
           FROM audit_events
          WHERE created_at >= NOW() - INTERVAL '24 hours'`
      ),
      getApp1Maintenance()
    ]);
    const accounts = accountsResult.rows[0] || {};
    res.json({
      ok: true,
      dashboard: {
        app1Maintenance,
        accounts: {
          total: Number(accounts.total || 0),
          active: Number(accounts.active || 0),
          suspended: Number(accounts.suspended || 0),
          adm: Number(accounts.adm || 0),
          dev: Number(accounts.dev || 0)
        },
        activeSessions: Number(sessionsResult.rows[0]?.active_sessions || 0),
        auditEvents24h: Number(auditResult.rows[0]?.events_24h || 0)
      }
    });
  } catch (error) { next(error); }
});

app.get("/v1/keymaster/audit", requireKeymaster, async (req, res, next) => {
  try {
    const requestedLimit = Number(req.query?.limit || 40);
    const limit = Number.isFinite(requestedLimit) ? Math.min(100, Math.max(1, Math.floor(requestedLimit))) : 40;
    const before = String(req.query?.before || "").trim();
    if (before && !/^\d+$/.test(before)) return sendError(res, 400, "INVALID_CURSOR", "Cursor de auditoria inválido.");

    const params = [];
    let beforeClause = "";
    if (before) {
      params.push(before);
      beforeClause = `WHERE e.id < $${params.length}::bigint`;
    }
    params.push(limit);
    const { rows } = await pool.query(
      `SELECT
         e.id::text AS id,
         e.actor_kind,
         e.actor_id,
         actor.login AS actor_login,
         e.action,
         e.target_kind,
         e.target_id,
         target.login AS target_login,
         e.metadata,
         e.created_at
       FROM audit_events e
       LEFT JOIN app1_accounts actor
         ON e.actor_kind = 'DEV' AND actor.id::text = e.actor_id
       LEFT JOIN app1_accounts target
         ON e.target_kind = 'APP1_ACCOUNT' AND target.id::text = e.target_id
       ${beforeClause}
       ORDER BY e.id DESC
       LIMIT $${params.length}`,
      params
    );
    res.json({
      ok: true,
      events: rows,
      nextBefore: rows.length === limit ? rows[rows.length - 1].id : null
    });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/critical/authorize", requireKeymaster, async (req, res, next) => {
  try {
    const devCredential = String(req.body?.devCredential || "");
    if (devCredential.length > 2_000) return sendError(res, 400, "INVALID_REQUEST", "Credencial DEV acima do limite esperado.");
    const result = await createCriticalAuthorization({
      sessionId: req.keymasterSession.id,
      action: req.body?.action,
      targetId: req.body?.targetId,
      devLogin: req.body?.devLogin,
      devCredential
    });
    if (result.error === "INVALID_CRITICAL_ACTION") return sendError(res, 400, result.error, "Ação crítica inválida.");
    if (result.error === "DEV_REAUTH_REQUIRED") return sendError(res, 400, result.error, "Login e credencial DEV são obrigatórios.");
    if (result.error === "INVALID_DEV_CREDENTIAL") return sendError(res, 403, result.error, "Reautenticação DEV inválida ou conta DEV indisponível.");
    res.json({ ok: true, authorizationToken: result.token, expiresAt: result.expiresAt, scope: result.scope, dev: result.dev });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/critical/execute", requireKeymaster, async (req, res, next) => {
  try {
    const action = String(req.body?.action || "").toUpperCase();
    if (!["APP1_MAINTENANCE_ON", "APP1_MAINTENANCE_OFF", "APP1_RESTART"].includes(action)) {
      return sendError(res, 400, "INVALID_CRITICAL_ACTION", "Ação crítica não suportada por este endpoint.");
    }
    const auth = await consumeCriticalAuthorization({
      sessionId: req.keymasterSession.id,
      token: String(req.body?.authorizationToken || ""),
      action
    });
    if (!auth) return sendError(res, 403, "CRITICAL_AUTH_INVALID", "Autorização crítica inválida, expirada ou já utilizada.");

    if (action === "APP1_RESTART") {
      const restart = await callRestartWebhook({ devAccountId: auth.dev_account_id, devLogin: auth.login });
      await withTransaction(async (client) => {
        await audit(client, {
          actorKind: "DEV", actorId: auth.dev_account_id, action: "APP1_RESTART_REQUESTED",
          targetKind: "SYSTEM", targetId: "APP1", metadata: restart
        });
      });
      if (!restart.ok) return sendError(res, 503, restart.reason || "RESTART_FAILED", "Reinício não está configurado ou o provedor recusou a solicitação.", restart);
      return res.json({ ok: true, action });
    }

    const enabled = action === "APP1_MAINTENANCE_ON";
    await withTransaction(async (client) => {
      await setApp1Maintenance(client, enabled, req.keymasterSession.id);
      await audit(client, {
        actorKind: "DEV", actorId: auth.dev_account_id, action,
        targetKind: "SYSTEM", targetId: "APP1", metadata: { enabled }
      });
    });
    return res.json({ ok: true, action, app1Maintenance: enabled });
  } catch (error) { next(error); }
});

app.get("/v1/keymaster/accounts", requireKeymaster, async (req, res, next) => {
  try {
    const q = normalizeLogin(req.query?.q).replace(/[%_]/g, "");
    const role = String(req.query?.role || "").toUpperCase();
    const status = String(req.query?.status || "").toUpperCase();
    if (role && !["ADM", "DEV"].includes(role)) return sendError(res, 400, "INVALID_ROLE", "Filtro de role inválido.");
    if (status && !["ACTIVE", "SUSPENDED", "LOCKED_SECURITY"].includes(status)) return sendError(res, 400, "INVALID_STATUS", "Filtro de status inválido.");

    const params = [];
    const clauses = ["a.status <> 'DELETED'"];
    if (q) {
      params.push(q);
      clauses.push(`LOWER(a.login) LIKE '%' || LOWER($${params.length}) || '%'`);
    }
    if (role) {
      params.push(role);
      clauses.push(`a.role = $${params.length}`);
    }
    if (status) {
      params.push(status);
      clauses.push(`a.status = $${params.length}`);
    }

    const { rows } = await pool.query(
      `SELECT
         a.id,
         a.login,
         a.role,
         a.status,
         a.created_at,
         a.updated_at,
         COUNT(s.id) FILTER (WHERE s.revoked_at IS NULL AND s.expires_at > NOW())::int AS active_sessions,
         MAX(s.created_at) FILTER (WHERE s.revoked_at IS NULL AND s.expires_at > NOW()) AS last_session_at
       FROM app1_accounts a
       LEFT JOIN app1_sessions s ON s.account_id = a.id
       WHERE ${clauses.join(" AND ")}
       GROUP BY a.id
       ORDER BY a.role DESC, a.login ASC
       LIMIT 250`,
      params
    );
    res.json({ ok: true, accounts: rows });
  } catch (error) {
    next(error);
  }
});

app.post("/v1/keymaster/accounts", requireKeymaster, async (req, res, next) => {
  try {
    const login = normalizeLogin(req.body?.login);
    const role = String(req.body?.role || "ADM").toUpperCase();
    if (!login || login.length < 2) return sendError(res, 400, "INVALID_LOGIN", "Informe um login válido.");
    if (!["ADM", "DEV"].includes(role)) return sendError(res, 400, "INVALID_ROLE", "Role deve ser ADM ou DEV.");

    const credential = createApp1Credential(login, role);
    const credentialHash = await hashSecret(credential);
    const accountId = randomId();

    await withTransaction(async (client) => {
      await client.query(
        `INSERT INTO app1_accounts
          (id, login, role, status, credential_hash, created_by_session)
         VALUES ($1, $2, $3, 'ACTIVE', $4, $5)`,
        [accountId, login, role, credentialHash, req.keymasterSession.id]
      );
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_ACCOUNT_CREATED",
        targetKind: "APP1_ACCOUNT",
        targetId: accountId,
        metadata: { role, login }
      });
    });

    res.status(201).json({
      ok: true,
      account: { id: accountId, login, role, status: "ACTIVE" },
      credential,
      credentialLength: credential.length,
      revealOnce: true
    });
  } catch (error) {
    if (error?.code === "23505") return sendError(res, 409, "LOGIN_EXISTS", "Esse login já existe.");
    next(error);
  }
});

app.post("/v1/keymaster/accounts/:id/suspend", requireKeymaster, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE app1_accounts SET status = 'SUSPENDED', updated_at = NOW()
          WHERE id = $1 AND status <> 'DELETED' RETURNING id, login, role, status`,
        [id]
      );
      if (!result.rowCount) throw Object.assign(new Error("not found"), { statusCode: 404 });
      await client.query(`UPDATE app1_sessions SET revoked_at = NOW() WHERE account_id = $1 AND revoked_at IS NULL`, [id]);
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_ACCOUNT_SUSPENDED",
        targetKind: "APP1_ACCOUNT",
        targetId: id
      });
    });
    res.json({ ok: true });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/accounts/:id/restore", requireKeymaster, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    const restored = await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE app1_accounts SET status = 'ACTIVE', updated_at = NOW()
          WHERE id = $1 AND status = 'SUSPENDED' RETURNING id, login, role`,
        [id]
      );
      if (!result.rowCount) return null;
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_ACCOUNT_RESTORED",
        targetKind: "APP1_ACCOUNT",
        targetId: id,
        metadata: { login: result.rows[0].login, role: result.rows[0].role }
      });
      return result.rows[0];
    });
    if (!restored) return sendError(res, 404, "NOT_SUSPENDED", "Conta não encontrada ou não está suspensa.");
    res.json({ ok: true });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/accounts/:id/rotate", requireKeymaster, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    const account = (await pool.query(`SELECT id, login, role, status FROM app1_accounts WHERE id = $1`, [id])).rows[0];
    if (!account || account.status === "DELETED") return sendError(res, 404, "NOT_FOUND", "Conta não encontrada.");
    const credential = createApp1Credential(account.login, account.role);
    const credentialHash = await hashSecret(credential);
    await withTransaction(async (client) => {
      await client.query(`UPDATE app1_accounts SET credential_hash = $2, updated_at = NOW() WHERE id = $1`, [id, credentialHash]);
      await client.query(`UPDATE app1_sessions SET revoked_at = NOW() WHERE account_id = $1 AND revoked_at IS NULL`, [id]);
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_CREDENTIAL_ROTATED",
        targetKind: "APP1_ACCOUNT",
        targetId: id
      });
    });
    res.json({ ok: true, credential, credentialLength: credential.length, revealOnce: true });
  } catch (error) { next(error); }
});

app.get("/v1/keymaster/accounts/:id/sessions", requireKeymaster, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    const account = (await pool.query(
      `SELECT id FROM app1_accounts WHERE id = $1 AND status <> 'DELETED' LIMIT 1`,
      [id]
    )).rows[0];
    if (!account) return sendError(res, 404, "NOT_FOUND", "Conta não encontrada.");
    const { rows } = await pool.query(
      `SELECT
         id,
         device_label,
         created_at,
         expires_at,
         revoked_at,
         (revoked_at IS NULL AND expires_at > NOW()) AS active
       FROM app1_sessions
       WHERE account_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [id]
    );
    res.json({ ok: true, sessions: rows });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/accounts/:id/sessions/:sessionId/revoke", requireKeymaster, async (req, res, next) => {
  try {
    const accountId = String(req.params.id);
    const sessionId = String(req.params.sessionId);
    const revoked = await withTransaction(async (client) => {
      const row = (await client.query(
        `SELECT id, revoked_at FROM app1_sessions WHERE id = $1 AND account_id = $2 FOR UPDATE`,
        [sessionId, accountId]
      )).rows[0];
      if (!row) return null;
      if (row.revoked_at) return false;
      await client.query(`UPDATE app1_sessions SET revoked_at = NOW() WHERE id = $1`, [sessionId]);
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_SESSION_REVOKED",
        targetKind: "APP1_ACCOUNT",
        targetId: accountId,
        metadata: { app1SessionId: sessionId }
      });
      return true;
    });
    if (revoked === null) return sendError(res, 404, "NOT_FOUND", "Sessão não encontrada.");
    res.json({ ok: true, revoked });
  } catch (error) { next(error); }
});

app.post("/v1/keymaster/accounts/:id/sessions/revoke-all", requireKeymaster, async (req, res, next) => {
  try {
    const accountId = String(req.params.id);
    const result = await withTransaction(async (client) => {
      const account = (await client.query(
        `SELECT id FROM app1_accounts WHERE id = $1 AND status <> 'DELETED' LIMIT 1`,
        [accountId]
      )).rows[0];
      if (!account) return null;
      const revokedRows = await client.query(
        `UPDATE app1_sessions
            SET revoked_at = NOW()
          WHERE account_id = $1
            AND revoked_at IS NULL
            AND expires_at > NOW()
          RETURNING id`,
        [accountId]
      );
      await audit(client, {
        actorKind: "KEYMASTER_SESSION",
        actorId: req.keymasterSession.id,
        action: "APP1_SESSIONS_REVOKED_ALL",
        targetKind: "APP1_ACCOUNT",
        targetId: accountId,
        metadata: { count: revokedRows.rowCount }
      });
      return revokedRows.rowCount;
    });
    if (result === null) return sendError(res, 404, "NOT_FOUND", "Conta não encontrada.");
    res.json({ ok: true, revokedCount: result });
  } catch (error) { next(error); }
});

app.delete("/v1/keymaster/accounts/:id", requireKeymaster, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    const authToken = String(req.headers["x-critical-authorization"] || "");
    const auth = await consumeCriticalAuthorization({
      sessionId: req.keymasterSession.id,
      token: authToken,
      action: "DELETE_APP1_ACCOUNT",
      targetId: id
    });
    if (!auth) return sendError(res, 403, "DEV_REAUTH_REQUIRED", "Excluir uma conta exige reautenticação DEV de uso único.");

    await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE app1_accounts
            SET status = 'DELETED', deleted_at = NOW(), updated_at = NOW()
          WHERE id = $1 AND status <> 'DELETED'
          RETURNING id, login, role`,
        [id]
      );
      if (!result.rowCount) throw Object.assign(new Error("not found"), { statusCode: 404 });
      await client.query(`UPDATE app1_sessions SET revoked_at = NOW() WHERE account_id = $1 AND revoked_at IS NULL`, [id]);
      await audit(client, {
        actorKind: "DEV",
        actorId: auth.dev_account_id,
        action: "APP1_ACCOUNT_DELETED",
        targetKind: "APP1_ACCOUNT",
        targetId: id,
        metadata: { deletedLogin: result.rows[0].login, deletedRole: result.rows[0].role, keymasterSessionId: req.keymasterSession.id }
      });
    });
    res.json({ ok: true });
  } catch (error) { next(error); }
});

// As rotas V1 são registradas antes das rotas legadas abaixo. Isso mantém
// compatibilidade durante a migração sem permitir que a implementação antiga
// intercepte login/sessão antes das novas regras de segurança.
registerApp1Routes(app, {
  requireKeymaster,
  consumeCriticalAuthorization,
  getApp1Maintenance
});

// Rotas legadas temporárias; permanecem durante a transição e serão removidas
// quando o App 1 Probe estiver totalmente migrado para o contrato V1.
app.post("/v1/app1/login", async (req, res, next) => {
  try {
    const login = normalizeLogin(req.body?.login);
    const credential = String(req.body?.credential || "");
    if (!login || !credential) return sendError(res, 400, "INVALID_REQUEST", "Login e credencial são obrigatórios.");
    if (await getApp1Maintenance()) return sendError(res, 503, "APP1_MAINTENANCE", "Aplicativo 1 está em manutenção.");

    const account = (await pool.query(`SELECT * FROM app1_accounts WHERE login = $1 LIMIT 1`, [login])).rows[0];
    if (!account || !(await verifySecret(credential, account.credential_hash))) {
      return sendError(res, 401, "INVALID_CREDENTIAL", "Login ou credencial inválidos.");
    }
    if (account.status === "SUSPENDED") return sendError(res, 403, "ACCOUNT_SUSPENDED", "Conta suspensa.");
    if (account.status === "DELETED") return sendError(res, 403, "ACCOUNT_DELETED", "Conta removida.");

    const token = randomToken(48);
    const sessionId = randomId();
    const expiresAt = new Date(Date.now() + APP1_SESSION_MS);
    await pool.query(
      `INSERT INTO app1_sessions (id, account_id, token_hash, device_label, expires_at)
       VALUES ($1, $2, $3, $4, $5)`,
      [sessionId, account.id, tokenHash(`app1:${token}`), String(req.body?.deviceLabel || "").slice(0, 120), expiresAt]
    );
    res.json({
      ok: true,
      token,
      expiresAt,
      account: { id: account.id, login: account.login, role: account.role, status: account.status }
    });
  } catch (error) { next(error); }
});

app.get("/v1/app1/me", async (req, res, next) => {
  try {
    if (await getApp1Maintenance()) return sendError(res, 503, "APP1_MAINTENANCE", "Aplicativo 1 está em manutenção.");
    const auth = String(req.headers.authorization || "");
    const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
    if (!token) return sendError(res, 401, "UNAUTHORIZED", "Token ausente.");
    const hash = tokenHash(`app1:${token}`);
    const { rows } = await pool.query(
      `SELECT a.id, a.login, a.role, a.status, s.expires_at
         FROM app1_sessions s
         JOIN app1_accounts a ON a.id = s.account_id
        WHERE s.token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > NOW()
        LIMIT 1`,
      [hash]
    );
    const row = rows[0];
    if (!row) return sendError(res, 401, "UNAUTHORIZED", "Sessão inválida.");
    if (row.status !== "ACTIVE") return sendError(res, 403, "ACCOUNT_SUSPENDED", "Conta não está ativa.");
    res.json({ ok: true, account: row });
  } catch (error) { next(error); }
});

registerMenuRoutes(app, { consumeCriticalAuthorization });

app.use((error, _req, res, _next) => {
  console.error("CONTROL_API_ERROR", error?.stack || error);
  if (error?.statusCode === 404) return sendError(res, 404, "NOT_FOUND", "Registro não encontrado.");
  return sendError(res, 500, "INTERNAL_ERROR", "Erro interno do servidor.");
});

app.listen(PORT, () => {
  console.log(`GRUPO LUA Control API em :${PORT}`);
});
