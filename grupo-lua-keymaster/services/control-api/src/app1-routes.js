import crypto from "crypto";
import { pool, withTransaction, audit } from "./db.js";
import {
  deriveDeviceFingerprint,
  normalizeLogin,
  privacyHash,
  randomId,
  randomToken,
  tokenHash,
  verifySecret
} from "./security.js";
import { verifyAppIntegrity } from "./integrity.js";

export const APP1_MAX_FAILED = 3;
export const APP1_SESSION_MS = 24 * 60 * 60 * 1000;
export const APP1_PROVISIONAL_SESSION_MS = 15 * 60 * 1000;
export const APP1_DEVICE_ENROLLMENT_MS = 10 * 60 * 1000;
export const APP1_MAX_ACTIVE_DEVICES = 2;
export const APP1_TERMS_VERSION = String(process.env.APP1_TERMS_VERSION || "1.0");
export const APP1_PRIVACY_VERSION = String(process.env.APP1_PRIVACY_VERSION || "1.0");

const PUBLIC_NAME_MIN = 3;
const PUBLIC_NAME_MAX = 30;
const INVISIBLE_RE = /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]/u;
const CREDENTIALISH_RE = /^(ADM1-|DEV-|FREE-|VIP-)/i;

function sendError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function safeEqualText(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

function secretFingerprint(value, purpose) {
  return privacyHash(String(value || ""), purpose);
}

function hashIp(req) {
  return secretFingerprint(req.ip || req.socket?.remoteAddress || "unknown", "app1-ip");
}

function maskHash(value) {
  const text = String(value || "");
  if (!text) return null;
  if (text.length <= 14) return text;
  return `${text.slice(0, 8)}…${text.slice(-4)}`;
}

function deviceInput(req) {
  const body = req.body || {};
  return {
    platform: String(body.platform || "unknown").slice(0, 20),
    nativeDeviceId: String(body.nativeDeviceId || "").slice(0, 300),
    integrityKeyId: String(body.integrityKeyId || "").slice(0, 500),
    installationId: String(body.installationId || "").slice(0, 200),
    deviceLabel: String(body.deviceLabel || "").trim().slice(0, 120),
    deviceToken: String(body.deviceToken || "").slice(0, 500)
  };
}

function hasDeviceIdentity(device) {
  return Boolean(device.nativeDeviceId || device.integrityKeyId || device.installationId);
}

function integrityRequestHash(device) {
  return crypto.createHash("sha256")
    .update(`${device.platform}\0${device.nativeDeviceId}\0${device.integrityKeyId}\0${device.installationId}`)
    .digest("base64url");
}

function deviceMetadata(device) {
  return {
    platform: device.platform,
    nativeDeviceIdHash: device.nativeDeviceId
      ? secretFingerprint(device.nativeDeviceId, "app1-native-device-id")
      : null,
    installationIdHash: device.installationId
      ? secretFingerprint(device.installationId, "app1-installation-id")
      : null
  };
}

function credentialClass(credential) {
  const value = String(credential || "");
  if (/^ADM1-/i.test(value)) return "ADM1";
  if (/^DEV-/i.test(value)) return "DEV";
  if (/^FREE-/i.test(value)) return "FREE";
  if (/^VIP-/i.test(value)) return "VIP";
  return "UNKNOWN";
}

export function normalizePublicName(value) {
  return String(value || "")
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ");
}

function canonicalIdentity(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

export function validatePublicName(value, privateLogin = "") {
  const name = normalizePublicName(value);
  const length = Array.from(name).length;
  if (length < PUBLIC_NAME_MIN || length > PUBLIC_NAME_MAX) {
    return { ok: false, code: "PUBLIC_NAME_LENGTH", name };
  }
  if (INVISIBLE_RE.test(name)) return { ok: false, code: "PUBLIC_NAME_INVALID_CHARS", name };
  if (CREDENTIALISH_RE.test(name)) return { ok: false, code: "PUBLIC_NAME_CREDENTIAL_LIKE", name };

  const publicCanonical = canonicalIdentity(name);
  const loginCanonical = canonicalIdentity(privateLogin);
  if (!publicCanonical) return { ok: false, code: "PUBLIC_NAME_INVALID_CHARS", name };
  if (loginCanonical) {
    const same = publicCanonical === loginCanonical;
    const near = publicCanonical.length >= 5 && loginCanonical.length >= 5 &&
      (publicCanonical.startsWith(loginCanonical) || loginCanonical.startsWith(publicCanonical));
    if (same || near) return { ok: false, code: "PUBLIC_NAME_TOO_CLOSE_TO_LOGIN", name };
  }
  return { ok: true, name, normalized: publicCanonical };
}

async function recordAttempt(client, {
  accountId = null,
  login,
  credential,
  deviceFingerprint = null,
  platform = "unknown",
  ipHash,
  result,
  integrityVerified = false,
  metadata = {}
}) {
  await client.query(
    `INSERT INTO app1_login_attempts
      (account_id, login_fingerprint, credential_fingerprint, device_fingerprint,
       platform, ip_hash, result, integrity_verified, metadata)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)`,
    [
      accountId,
      secretFingerprint(login, "app1-login-attempt-login"),
      secretFingerprint(credential, "app1-login-attempt-credential"),
      deviceFingerprint,
      platform,
      ipHash,
      result,
      Boolean(integrityVerified),
      JSON.stringify({
        credentialClass: credentialClass(credential),
        credentialLength: String(credential || "").length,
        ...metadata
      })
    ]
  );
}

async function lockAccount(client, accountId, reason) {
  await client.query(
    `UPDATE app1_accounts
        SET status = 'LOCKED_SECURITY',
            security_locked_at = NOW(),
            security_lock_reason = $2,
            updated_at = NOW()
      WHERE id = $1 AND status = 'ACTIVE'`,
    [accountId, reason]
  );
  await client.query(
    `UPDATE app1_sessions
        SET revoked_at = COALESCE(revoked_at, NOW())
      WHERE account_id = $1 AND revoked_at IS NULL`,
    [accountId]
  );
  await audit(client, {
    actorKind: "SYSTEM",
    actorId: "APP1_SECURITY",
    action: "APP1_ACCOUNT_LOCKED_SECURITY",
    targetKind: "APP1_ACCOUNT",
    targetId: accountId,
    metadata: { reason }
  });
}

async function makeDevice(client, {
  account,
  device,
  fingerprint,
  isPrimary,
  authorizedByDevAccountId = null,
  ipHash
}) {
  const plainDeviceToken = randomToken(48);
  const deviceId = randomId();
  const meta = deviceMetadata(device);
  const existing = (await client.query(
    `SELECT id FROM app1_devices WHERE account_id = $1 AND fingerprint = $2 FOR UPDATE`,
    [account.id, fingerprint]
  )).rows[0];

  if (existing) {
    const row = (await client.query(
      `UPDATE app1_devices
          SET device_token_hash = $2,
              platform = $3,
              native_device_id_hash = $4,
              installation_id_hash = $5,
              integrity_key_id = $6,
              device_label = $7,
              is_primary = $8,
              status = 'ACTIVE',
              authorized_by_dev_account_id = $9,
              authorized_at = NOW(),
              last_seen_at = NOW(),
              last_ip_hash = $10,
              revoked_at = NULL
        WHERE id = $1
        RETURNING *`,
      [
        existing.id,
        tokenHash(`app1-device:${plainDeviceToken}`),
        device.platform,
        meta.nativeDeviceIdHash,
        meta.installationIdHash,
        device.integrityKeyId || null,
        device.deviceLabel || null,
        Boolean(isPrimary),
        authorizedByDevAccountId,
        ipHash
      ]
    )).rows[0];
    return { row, plainDeviceToken };
  }

  const row = (await client.query(
    `INSERT INTO app1_devices
      (id, account_id, fingerprint, device_token_hash, platform,
       native_device_id_hash, installation_id_hash, integrity_key_id,
       device_label, is_primary, status, authorized_by_dev_account_id,
       last_ip_hash)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'ACTIVE', $11, $12)
     RETURNING *`,
    [
      deviceId,
      account.id,
      fingerprint,
      tokenHash(`app1-device:${plainDeviceToken}`),
      device.platform,
      meta.nativeDeviceIdHash,
      meta.installationIdHash,
      device.integrityKeyId || null,
      device.deviceLabel || null,
      Boolean(isPrimary),
      authorizedByDevAccountId,
      ipHash
    ]
  )).rows[0];
  return { row, plainDeviceToken };
}

async function createSession(client, { account, deviceId, deviceLabel }) {
  const onboardingComplete = Boolean(account.onboarding_completed_at);
  const sessionKind = onboardingComplete ? "FULL" : "PROVISIONAL";
  const lifetime = onboardingComplete ? APP1_SESSION_MS : APP1_PROVISIONAL_SESSION_MS;
  const token = randomToken(48);
  const sessionId = randomId();
  const expiresAt = new Date(Date.now() + lifetime);
  await client.query(
    `INSERT INTO app1_sessions
      (id, account_id, token_hash, device_label, expires_at, app1_device_id, session_kind)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      sessionId,
      account.id,
      tokenHash(`app1:${token}`),
      deviceLabel || null,
      expiresAt,
      deviceId,
      sessionKind
    ]
  );
  return { token, sessionId, expiresAt, sessionKind };
}

function publicAccount(row) {
  const termsCurrent = row.terms_version === APP1_TERMS_VERSION &&
    row.privacy_version === APP1_PRIVACY_VERSION && Boolean(row.terms_accepted_at);
  return {
    profileId: row.public_profile_id || null,
    publicName: row.public_name || null,
    role: row.role,
    status: row.status,
    onboarding: {
      completed: Boolean(row.onboarding_completed_at),
      termsAccepted: termsCurrent,
      publicNameVerified: Boolean(row.public_name_verified_at)
    }
  };
}

async function getApp1Session(req, { allowProvisional = true } = {}) {
  const auth = String(req.headers.authorization || "");
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const deviceToken = String(req.headers["x-app1-device-token"] || "").slice(0, 500);
  if (!token || !deviceToken) return null;

  const hash = tokenHash(`app1:${token}`);
  const { rows } = await pool.query(
    `SELECT
       s.id AS session_id,
       s.account_id,
       s.app1_device_id,
       s.session_kind,
       s.expires_at,
       a.login,
       a.role,
       a.status,
       a.terms_version,
       a.privacy_version,
       a.terms_accepted_at,
       a.public_profile_id,
       a.public_name,
       a.public_name_normalized,
       a.public_name_verified_at,
       a.onboarding_completed_at,
       d.status AS device_status,
       d.device_token_hash
     FROM app1_sessions s
     JOIN app1_accounts a ON a.id = s.account_id
     JOIN app1_devices d ON d.id = s.app1_device_id
     WHERE s.token_hash = $1
       AND s.revoked_at IS NULL
       AND s.expires_at > NOW()
     LIMIT 1`,
    [hash]
  );
  const row = rows[0];
  if (!row || row.status !== "ACTIVE" || row.device_status !== "ACTIVE") return null;
  const suppliedHash = tokenHash(`app1-device:${deviceToken}`);
  if (!safeEqualText(suppliedHash, row.device_token_hash)) return null;
  if (!allowProvisional && row.session_kind !== "FULL") return null;
  return row;
}

async function requireApp1Session(req, res, next) {
  try {
    const session = await getApp1Session(req, { allowProvisional: true });
    if (!session) return sendError(res, 401, "UNAUTHORIZED", "Sessão inválida, expirada ou incompatível com o dispositivo.");
    req.app1Session = session;
    next();
  } catch (error) {
    next(error);
  }
}

async function expireEnrollmentWindows(client, accountId) {
  await client.query(
    `UPDATE app1_device_enrollment_windows
        SET status = 'EXPIRED'
      WHERE account_id = $1
        AND status = 'PENDING'
        AND expires_at <= NOW()`,
    [accountId]
  );
}

async function findPendingEnrollment(client, accountId) {
  await expireEnrollmentWindows(client, accountId);
  return (await client.query(
    `SELECT * FROM app1_device_enrollment_windows
      WHERE account_id = $1
        AND status = 'PENDING'
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE`,
    [accountId]
  )).rows[0] || null;
}

function loginResponseMessage(code) {
  if (code === "ACCOUNT_LOCKED") return "Acesso bloqueado por segurança. Entre em contato com um DEV.";
  if (code === "ACCOUNT_SUSPENDED") return "Conta suspensa.";
  if (code === "DEVICE_NOT_AUTHORIZED") return "Este dispositivo não está autorizado para esta conta.";
  return "Login ou credencial inválidos.";
}

export function registerApp1Routes(app, {
  requireKeymaster,
  consumeCriticalAuthorization,
  getApp1Maintenance
}) {
  app.post("/v1/app1/login", async (req, res, next) => {
    try {
      const login = normalizeLogin(req.body?.login);
      const credential = String(req.body?.credential || "");
      const device = deviceInput(req);
      if (!login || !credential) return sendError(res, 400, "INVALID_REQUEST", "Login e credencial são obrigatórios.");
      if (!hasDeviceIdentity(device)) return sendError(res, 400, "DEVICE_ID_REQUIRED", "Identificação do dispositivo ausente.");
      if (await getApp1Maintenance()) return sendError(res, 503, "APP1_MAINTENANCE", "Aplicativo 1 está em manutenção.");

      const fingerprint = deriveDeviceFingerprint(device);
      const requestIpHash = hashIp(req);
      const integrity = await verifyAppIntegrity({
        platform: device.platform,
        integrityProof: req.body?.integrityProof || null,
        requestHash: integrityRequestHash(device)
      });

      if (!integrity.accepted) {
        await withTransaction(async (client) => {
          const target = (await client.query(`SELECT id FROM app1_accounts WHERE login = $1 LIMIT 1`, [login])).rows[0];
          await recordAttempt(client, {
            accountId: target?.id || null,
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: "INTEGRITY_REJECTED",
            integrityVerified: false
          });
        });
        return sendError(res, 403, "INTEGRITY_REQUIRED", "O aplicativo ou dispositivo não passou na verificação de segurança.");
      }

      const result = await withTransaction(async (client) => {
        const account = (await client.query(
          `SELECT * FROM app1_accounts WHERE login = $1 LIMIT 1 FOR UPDATE`,
          [login]
        )).rows[0];

        if (!account) {
          await recordAttempt(client, {
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: "INVALID_CREDENTIAL",
            integrityVerified: integrity.verified
          });
          return { error: "INVALID_CREDENTIAL" };
        }

        const credentialValid = await verifySecret(credential, account.credential_hash);
        if (!credentialValid) {
          const failures = account.status === "ACTIVE"
            ? Number(account.failed_login_attempts || 0) + 1
            : Number(account.failed_login_attempts || 0);
          const shouldLock = account.status === "ACTIVE" && failures >= APP1_MAX_FAILED;

          if (account.status === "ACTIVE") {
            await client.query(
              `UPDATE app1_accounts
                  SET failed_login_attempts = $2, updated_at = NOW()
                WHERE id = $1`,
              [account.id, failures]
            );
            if (shouldLock) await lockAccount(client, account.id, "INVALID_CREDENTIALS_3");
          }

          await recordAttempt(client, {
            accountId: account.id,
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: shouldLock ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIAL",
            integrityVerified: integrity.verified,
            metadata: { failureCount: Math.min(failures, APP1_MAX_FAILED) }
          });
          return { error: shouldLock ? "ACCOUNT_LOCKED" : "INVALID_CREDENTIAL" };
        }

        if (account.status === "LOCKED_SECURITY") {
          await recordAttempt(client, {
            accountId: account.id,
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: "ACCOUNT_LOCKED",
            integrityVerified: integrity.verified
          });
          return { error: "ACCOUNT_LOCKED" };
        }
        if (account.status === "SUSPENDED") {
          await recordAttempt(client, {
            accountId: account.id,
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: "ACCOUNT_SUSPENDED",
            integrityVerified: integrity.verified
          });
          return { error: "ACCOUNT_SUSPENDED" };
        }
        if (account.status === "DELETED") {
          await recordAttempt(client, {
            accountId: account.id,
            login,
            credential,
            deviceFingerprint: fingerprint,
            platform: device.platform,
            ipHash: requestIpHash,
            result: "ACCOUNT_DELETED",
            integrityVerified: integrity.verified
          });
          return { error: "INVALID_CREDENTIAL" };
        }

        await expireEnrollmentWindows(client, account.id);
        const allDevices = (await client.query(
          `SELECT * FROM app1_devices WHERE account_id = $1 ORDER BY authorized_at ASC FOR UPDATE`,
          [account.id]
        )).rows;
        const activeDevices = allDevices.filter((row) => row.status === "ACTIVE");
        let boundDevice = activeDevices.find((row) => row.fingerprint === fingerprint) || null;
        let issuedDeviceToken = null;
        let deviceEvent = "EXISTING_DEVICE";
        const suppliedDeviceTokenHash = device.deviceToken
          ? tokenHash(`app1-device:${device.deviceToken}`)
          : "";

        // O token guardado no SecureStore é uma prova mais forte de continuidade
        // da instalação do que o fingerprint nativo isolado. Em algumas atualizações,
        // Android ID/IDFV pode mudar mesmo no mesmo aparelho. Se o token do aparelho
        // continua válido, recuperamos o vínculo ao invés de acusar um "novo celular".
        if (!boundDevice && suppliedDeviceTokenHash) {
          const tokenBoundDevice = activeDevices.find((row) =>
            safeEqualText(suppliedDeviceTokenHash, row.device_token_hash)
          ) || null;
          if (tokenBoundDevice) {
            boundDevice = tokenBoundDevice;
            deviceEvent = "EXISTING_DEVICE_TOKEN_RECOVERED";
            const conflicting = allDevices.find((row) => row.id !== boundDevice.id && row.fingerprint === fingerprint);
            const meta = deviceMetadata(device);
            if (!conflicting) {
              boundDevice = (await client.query(
                `UPDATE app1_devices
                    SET fingerprint = $2,
                        platform = $3,
                        native_device_id_hash = $4,
                        installation_id_hash = $5,
                        integrity_key_id = $6,
                        device_label = COALESCE(NULLIF($7, ''), device_label),
                        last_seen_at = NOW(),
                        last_ip_hash = $8
                  WHERE id = $1
                  RETURNING *`,
                [
                  boundDevice.id,
                  fingerprint,
                  device.platform,
                  meta.nativeDeviceIdHash,
                  meta.installationIdHash,
                  device.integrityKeyId || null,
                  device.deviceLabel || "",
                  requestIpHash
                ]
              )).rows[0];
            }
            await audit(client, {
              actorKind: "APP1_ACCOUNT",
              actorId: account.id,
              action: "APP1_DEVICE_IDENTITY_RECOVERED",
              targetKind: "APP1_DEVICE",
              targetId: boundDevice.id,
              metadata: { platform: device.platform, deviceHint: maskHash(fingerprint) }
            });
          }
        }

        if (boundDevice) {
          if (!suppliedDeviceTokenHash || !safeEqualText(suppliedDeviceTokenHash, boundDevice.device_token_hash)) {
            const failures = Number(account.failed_device_attempts || 0) + 1;
            const shouldLock = failures >= APP1_MAX_FAILED;
            await client.query(
              `UPDATE app1_accounts
                  SET failed_login_attempts = 0,
                      failed_device_attempts = $2,
                      updated_at = NOW()
                WHERE id = $1`,
              [account.id, failures]
            );
            if (shouldLock) await lockAccount(client, account.id, "DEVICE_PROOF_INVALID_3");
            await recordAttempt(client, {
              accountId: account.id,
              login,
              credential,
              deviceFingerprint: fingerprint,
              platform: device.platform,
              ipHash: requestIpHash,
              result: shouldLock ? "ACCOUNT_LOCKED" : "DEVICE_PROOF_INVALID",
              integrityVerified: integrity.verified,
              metadata: { failureCount: Math.min(failures, APP1_MAX_FAILED) }
            });
            return { error: shouldLock ? "ACCOUNT_LOCKED" : "DEVICE_NOT_AUTHORIZED" };
          }
        } else if (allDevices.length === 0) {
          const created = await makeDevice(client, {
            account,
            device,
            fingerprint,
            isPrimary: true,
            ipHash: requestIpHash
          });
          boundDevice = created.row;
          issuedDeviceToken = created.plainDeviceToken;
          deviceEvent = "FIRST_DEVICE_BOUND";
          await audit(client, {
            actorKind: "APP1_ACCOUNT",
            actorId: account.id,
            action: "APP1_PRIMARY_DEVICE_BOUND",
            targetKind: "APP1_DEVICE",
            targetId: boundDevice.id,
            metadata: { platform: device.platform, deviceHint: maskHash(fingerprint) }
          });
        } else {
          const enrollment = await findPendingEnrollment(client, account.id);
          if (enrollment && activeDevices.length < APP1_MAX_ACTIVE_DEVICES) {
            const created = await makeDevice(client, {
              account,
              device,
              fingerprint,
              isPrimary: false,
              authorizedByDevAccountId: enrollment.created_by_dev_account_id,
              ipHash: requestIpHash
            });
            boundDevice = created.row;
            issuedDeviceToken = created.plainDeviceToken;
            deviceEvent = "AUTHORIZED_DEVICE_BOUND";
            await client.query(
              `UPDATE app1_device_enrollment_windows
                  SET status = 'CONSUMED',
                      consumed_at = NOW(),
                      consumed_device_id = $2
                WHERE id = $1 AND status = 'PENDING'`,
              [enrollment.id, boundDevice.id]
            );
            await client.query(
              `UPDATE app1_device_enrollment_windows
                  SET status = 'CANCELLED', cancelled_at = NOW()
                WHERE account_id = $1 AND status = 'PENDING' AND id <> $2`,
              [account.id, enrollment.id]
            );
            await audit(client, {
              actorKind: "DEV",
              actorId: enrollment.created_by_dev_account_id,
              action: "APP1_DEVICE_ENROLLMENT_CONSUMED",
              targetKind: "APP1_ACCOUNT",
              targetId: account.id,
              metadata: {
                enrollmentId: enrollment.id,
                deviceId: boundDevice.id,
                platform: device.platform,
                deviceHint: maskHash(fingerprint)
              }
            });
          } else {
            const failures = Number(account.failed_device_attempts || 0) + 1;
            const shouldLock = failures >= APP1_MAX_FAILED;
            await client.query(
              `UPDATE app1_accounts
                  SET failed_login_attempts = 0,
                      failed_device_attempts = $2,
                      updated_at = NOW()
                WHERE id = $1`,
              [account.id, failures]
            );
            if (shouldLock) await lockAccount(client, account.id, "UNAUTHORIZED_DEVICE_3");
            await recordAttempt(client, {
              accountId: account.id,
              login,
              credential,
              deviceFingerprint: fingerprint,
              platform: device.platform,
              ipHash: requestIpHash,
              result: shouldLock ? "ACCOUNT_LOCKED" : "UNAUTHORIZED_DEVICE",
              integrityVerified: integrity.verified,
              metadata: {
                failureCount: Math.min(failures, APP1_MAX_FAILED),
                enrollmentAvailable: Boolean(enrollment),
                activeDevices: activeDevices.length
              }
            });
            return { error: shouldLock ? "ACCOUNT_LOCKED" : "DEVICE_NOT_AUTHORIZED" };
          }
        }

        await client.query(
          `UPDATE app1_devices
              SET last_seen_at = NOW(), last_ip_hash = $2, device_label = COALESCE(NULLIF($3, ''), device_label)
            WHERE id = $1`,
          [boundDevice.id, requestIpHash, device.deviceLabel || ""]
        );
        await client.query(
          `UPDATE app1_accounts
              SET failed_login_attempts = 0,
                  failed_device_attempts = 0,
                  updated_at = NOW()
            WHERE id = $1`,
          [account.id]
        );

        const refreshed = (await client.query(`SELECT * FROM app1_accounts WHERE id = $1`, [account.id])).rows[0];
        const session = await createSession(client, {
          account: refreshed,
          deviceId: boundDevice.id,
          deviceLabel: device.deviceLabel
        });
        await recordAttempt(client, {
          accountId: account.id,
          login,
          credential,
          deviceFingerprint: fingerprint,
          platform: device.platform,
          ipHash: requestIpHash,
          result: "SUCCESS",
          integrityVerified: integrity.verified,
          metadata: { deviceEvent, sessionKind: session.sessionKind }
        });
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: account.id,
          action: "APP1_LOGIN_SUCCESS",
          targetKind: "APP1_SESSION",
          targetId: session.sessionId,
          metadata: {
            deviceId: boundDevice.id,
            deviceEvent,
            sessionKind: session.sessionKind,
            integrityVerified: integrity.verified
          }
        });

        return {
          account: refreshed,
          session,
          deviceToken: issuedDeviceToken,
          deviceId: boundDevice.id
        };
      });

      if (result.error) {
        const status = result.error === "ACCOUNT_LOCKED" ? 423
          : result.error === "ACCOUNT_SUSPENDED" ? 403
          : result.error === "DEVICE_NOT_AUTHORIZED" ? 403
          : 401;
        return sendError(res, status, result.error, loginResponseMessage(result.error));
      }

      return res.json({
        ok: true,
        token: result.session.token,
        expiresAt: result.session.expiresAt,
        sessionKind: result.session.sessionKind,
        deviceToken: result.deviceToken || undefined,
        account: publicAccount(result.account),
        serverTime: new Date().toISOString(),
        integrityVerified: integrity.verified
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/v1/app1/me", requireApp1Session, async (req, res) => {
    res.json({
      ok: true,
      session: {
        kind: req.app1Session.session_kind,
        expiresAt: req.app1Session.expires_at
      },
      account: publicAccount(req.app1Session)
    });
  });

  app.post("/v1/app1/onboarding/accept-terms", requireApp1Session, async (req, res, next) => {
    try {
      if (req.body?.accepted !== true) {
        return sendError(res, 400, "TERMS_ACCEPTANCE_REQUIRED", "É necessário confirmar o aceite para continuar.");
      }

      const session = req.app1Session;
      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO app1_terms_acceptances
            (account_id, app1_session_id, terms_version, privacy_version)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (account_id, terms_version, privacy_version) DO NOTHING`,
          [session.account_id, session.session_id, APP1_TERMS_VERSION, APP1_PRIVACY_VERSION]
        );
        await client.query(
          `UPDATE app1_accounts
              SET terms_version = $2,
                  privacy_version = $3,
                  terms_accepted_at = NOW(),
                  updated_at = NOW()
            WHERE id = $1`,
          [session.account_id, APP1_TERMS_VERSION, APP1_PRIVACY_VERSION]
        );
        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: session.account_id,
          action: "APP1_TERMS_ACCEPTED",
          targetKind: "APP1_ACCOUNT",
          targetId: session.account_id,
          metadata: {
            termsVersion: APP1_TERMS_VERSION,
            privacyVersion: APP1_PRIVACY_VERSION
          }
        });
      });

      res.json({
        ok: true,
        termsVersion: APP1_TERMS_VERSION,
        privacyVersion: APP1_PRIVACY_VERSION
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/app1/onboarding/public-name", requireApp1Session, async (req, res, next) => {
    try {
      const session = req.app1Session;
      const validation = validatePublicName(req.body?.publicName, session.login);
      if (!validation.ok) {
        return sendError(res, 400, "PUBLIC_NAME_REJECTED", "Este nome não pode ser utilizado. Escolha outro pseudônimo.");
      }

      const result = await withTransaction(async (client) => {
        const account = (await client.query(
          `SELECT * FROM app1_accounts WHERE id = $1 FOR UPDATE`,
          [session.account_id]
        )).rows[0];
        if (!account || account.status !== "ACTIVE") return null;

        const profileId = account.public_profile_id || `usr_${randomToken(9)}`;
        const termsCurrent = account.terms_version === APP1_TERMS_VERSION &&
          account.privacy_version === APP1_PRIVACY_VERSION && Boolean(account.terms_accepted_at);

        const updated = (await client.query(
          `UPDATE app1_accounts
              SET public_profile_id = $2,
                  public_name = $3,
                  public_name_normalized = $4,
                  public_name_verified_at = NOW(),
                  onboarding_completed_at = CASE
                    WHEN $5::boolean THEN COALESCE(onboarding_completed_at, NOW())
                    ELSE onboarding_completed_at
                  END,
                  updated_at = NOW()
            WHERE id = $1
            RETURNING *`,
          [account.id, profileId, validation.name, validation.normalized, termsCurrent]
        )).rows[0];

        let expiresAt = session.expires_at;
        let sessionKind = session.session_kind;
        if (termsCurrent && updated.onboarding_completed_at && session.session_kind !== "FULL") {
          expiresAt = new Date(Date.now() + APP1_SESSION_MS);
          sessionKind = "FULL";
          await client.query(
            `UPDATE app1_sessions
                SET session_kind = 'FULL', expires_at = $2
              WHERE id = $1`,
            [session.session_id, expiresAt]
          );
        }

        await audit(client, {
          actorKind: "APP1_ACCOUNT",
          actorId: account.id,
          action: "APP1_PUBLIC_NAME_CONFIRMED",
          targetKind: "APP1_ACCOUNT",
          targetId: account.id,
          metadata: { profileId, onboardingCompleted: Boolean(updated.onboarding_completed_at) }
        });

        return { updated, expiresAt, sessionKind };
      });

      if (!result) return sendError(res, 403, "ACCOUNT_UNAVAILABLE", "Conta indisponível.");
      res.json({
        ok: true,
        account: publicAccount(result.updated),
        session: { kind: result.sessionKind, expiresAt: result.expiresAt }
      });
    } catch (error) {
      if (error?.code === "23505") {
        return sendError(res, 409, "PUBLIC_PROFILE_ID_COLLISION", "Não foi possível concluir o perfil. Tente novamente.");
      }
      next(error);
    }
  });

  app.get("/v1/keymaster/accounts/:id/security", requireKeymaster, async (req, res, next) => {
    try {
      const accountId = String(req.params.id);
      await withTransaction(async (client) => {
        await expireEnrollmentWindows(client, accountId);
      });

      const [accountResult, devicesResult, attemptsResult, enrollmentResult] = await Promise.all([
        pool.query(
          `SELECT id,
                  COALESCE(display_name, CASE WHEN role = 'DEV' THEN 'Acesso DEV' ELSE 'Acesso ADM' END) AS name,
                  role, status, failed_login_attempts, failed_device_attempts,
                  security_locked_at, security_lock_reason, created_at, updated_at
             FROM app1_accounts
            WHERE id = $1 AND status <> 'DELETED'
            LIMIT 1`,
          [accountId]
        ),
        pool.query(
          `SELECT id, fingerprint, platform, device_label, is_primary, status,
                  authorized_at, last_seen_at, revoked_at, last_ip_hash
             FROM app1_devices
            WHERE account_id = $1
            ORDER BY authorized_at DESC`,
          [accountId]
        ),
        pool.query(
          `SELECT id::text, credential_fingerprint, device_fingerprint, platform,
                  ip_hash, result, integrity_verified, metadata, created_at
             FROM app1_login_attempts
            WHERE account_id = $1
            ORDER BY id DESC
            LIMIT 100`,
          [accountId]
        ),
        pool.query(
          `SELECT id, status, created_at, expires_at, consumed_at, cancelled_at
             FROM app1_device_enrollment_windows
            WHERE account_id = $1
            ORDER BY created_at DESC
            LIMIT 10`,
          [accountId]
        )
      ]);

      const account = accountResult.rows[0];
      if (!account) return sendError(res, 404, "NOT_FOUND", "Conta não encontrada.");

      res.json({
        ok: true,
        account,
        devices: devicesResult.rows.map((row) => ({
          id: row.id,
          platform: row.platform,
          deviceLabel: row.device_label,
          deviceHint: maskHash(row.fingerprint),
          isPrimary: row.is_primary,
          status: row.status,
          authorizedAt: row.authorized_at,
          lastSeenAt: row.last_seen_at,
          revokedAt: row.revoked_at,
          networkHint: maskHash(row.last_ip_hash)
        })),
        attempts: attemptsResult.rows.map((row) => ({
          id: row.id,
          credentialHint: maskHash(row.credential_fingerprint),
          deviceHint: maskHash(row.device_fingerprint),
          networkHint: maskHash(row.ip_hash),
          platform: row.platform,
          result: row.result,
          integrityVerified: row.integrity_verified,
          metadata: row.metadata,
          createdAt: row.created_at
        })),
        enrollments: enrollmentResult.rows
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/accounts/:id/security/unlock", requireKeymaster, async (req, res, next) => {
    try {
      const accountId = String(req.params.id);
      const auth = await consumeCriticalAuthorization({
        sessionId: req.keymasterSession.id,
        token: String(req.headers["x-critical-authorization"] || ""),
        action: "UNLOCK_APP1_ACCOUNT",
        targetId: accountId
      });
      if (!auth) return sendError(res, 403, "DEV_REAUTH_REQUIRED", "Liberar uma conta exige reautenticação DEV de uso único.");

      const unlocked = await withTransaction(async (client) => {
        const row = (await client.query(
          `UPDATE app1_accounts
              SET status = 'ACTIVE',
                  failed_login_attempts = 0,
                  failed_device_attempts = 0,
                  security_locked_at = NULL,
                  security_lock_reason = NULL,
                  updated_at = NOW()
            WHERE id = $1 AND status = 'LOCKED_SECURITY'
            RETURNING id,
                      COALESCE(display_name, CASE WHEN role = 'DEV' THEN 'Acesso DEV' ELSE 'Acesso ADM' END) AS name,
                      role, status`,
          [accountId]
        )).rows[0];
        if (!row) return null;
        await audit(client, {
          actorKind: "DEV",
          actorId: auth.dev_account_id,
          action: "APP1_SECURITY_LOCK_CLEARED",
          targetKind: "APP1_ACCOUNT",
          targetId: accountId,
          metadata: { keymasterSessionId: req.keymasterSession.id }
        });
        return row;
      });

      if (!unlocked) return sendError(res, 409, "ACCOUNT_NOT_SECURITY_LOCKED", "A conta não está bloqueada por segurança.");
      res.json({ ok: true, account: unlocked });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/accounts/:id/device-enrollment", requireKeymaster, async (req, res, next) => {
    try {
      const accountId = String(req.params.id);
      const auth = await consumeCriticalAuthorization({
        sessionId: req.keymasterSession.id,
        token: String(req.headers["x-critical-authorization"] || ""),
        action: "AUTHORIZE_APP1_DEVICE",
        targetId: accountId
      });
      if (!auth) return sendError(res, 403, "DEV_REAUTH_REQUIRED", "Autorizar um novo dispositivo exige reautenticação DEV de uso único.");

      const result = await withTransaction(async (client) => {
        const account = (await client.query(
          `SELECT id, status FROM app1_accounts WHERE id = $1 AND status <> 'DELETED' FOR UPDATE`,
          [accountId]
        )).rows[0];
        if (!account) return { error: "NOT_FOUND" };
        const activeDevices = Number((await client.query(
          `SELECT COUNT(*)::int AS count FROM app1_devices WHERE account_id = $1 AND status = 'ACTIVE'`,
          [accountId]
        )).rows[0]?.count || 0);
        if (activeDevices >= APP1_MAX_ACTIVE_DEVICES) return { error: "MAX_DEVICES" };

        await expireEnrollmentWindows(client, accountId);
        await client.query(
          `UPDATE app1_device_enrollment_windows
              SET status = 'CANCELLED', cancelled_at = NOW()
            WHERE account_id = $1 AND status = 'PENDING'`,
          [accountId]
        );

        const id = randomId();
        const expiresAt = new Date(Date.now() + APP1_DEVICE_ENROLLMENT_MS);
        const row = (await client.query(
          `INSERT INTO app1_device_enrollment_windows
            (id, account_id, created_by_dev_account_id, keymaster_session_id, expires_at)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, status, created_at, expires_at`,
          [id, accountId, auth.dev_account_id, req.keymasterSession.id, expiresAt]
        )).rows[0];
        await audit(client, {
          actorKind: "DEV",
          actorId: auth.dev_account_id,
          action: "APP1_DEVICE_ENROLLMENT_OPENED",
          targetKind: "APP1_ACCOUNT",
          targetId: accountId,
          metadata: { enrollmentId: id, expiresAt, maxMinutes: 10 }
        });
        return { row };
      });

      if (result.error === "NOT_FOUND") return sendError(res, 404, "NOT_FOUND", "Conta não encontrada.");
      if (result.error === "MAX_DEVICES") return sendError(res, 409, "MAX_DEVICES", "A conta já possui o máximo de dois dispositivos ativos.");
      res.status(201).json({ ok: true, enrollment: result.row });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/accounts/:id/device-enrollment/cancel", requireKeymaster, async (req, res, next) => {
    try {
      const accountId = String(req.params.id);
      const cancelled = await withTransaction(async (client) => {
        const rows = await client.query(
          `UPDATE app1_device_enrollment_windows
              SET status = 'CANCELLED', cancelled_at = NOW()
            WHERE account_id = $1 AND status = 'PENDING'
            RETURNING id`,
          [accountId]
        );
        if (!rows.rowCount) return 0;
        await audit(client, {
          actorKind: "KEYMASTER_SESSION",
          actorId: req.keymasterSession.id,
          action: "APP1_DEVICE_ENROLLMENT_CANCELLED",
          targetKind: "APP1_ACCOUNT",
          targetId: accountId,
          metadata: { count: rows.rowCount }
        });
        return rows.rowCount;
      });
      res.json({ ok: true, cancelledCount: cancelled });
    } catch (error) {
      next(error);
    }
  });

  app.post("/v1/keymaster/accounts/:id/devices/:deviceId/revoke", requireKeymaster, async (req, res, next) => {
    try {
      const accountId = String(req.params.id);
      const deviceId = String(req.params.deviceId);
      const auth = await consumeCriticalAuthorization({
        sessionId: req.keymasterSession.id,
        token: String(req.headers["x-critical-authorization"] || ""),
        action: "REVOKE_APP1_DEVICE",
        targetId: accountId
      });
      if (!auth) return sendError(res, 403, "DEV_REAUTH_REQUIRED", "Revogar um dispositivo exige reautenticação DEV de uso único.");

      const revoked = await withTransaction(async (client) => {
        const row = (await client.query(
          `UPDATE app1_devices
              SET status = 'REVOKED', revoked_at = NOW(), last_seen_at = NOW()
            WHERE id = $1 AND account_id = $2 AND status = 'ACTIVE'
            RETURNING id, platform, device_label`,
          [deviceId, accountId]
        )).rows[0];
        if (!row) return null;
        await client.query(
          `UPDATE app1_sessions
              SET revoked_at = COALESCE(revoked_at, NOW())
            WHERE app1_device_id = $1 AND revoked_at IS NULL`,
          [deviceId]
        );
        await audit(client, {
          actorKind: "DEV",
          actorId: auth.dev_account_id,
          action: "APP1_DEVICE_REVOKED",
          targetKind: "APP1_DEVICE",
          targetId: deviceId,
          metadata: { accountId, platform: row.platform, keymasterSessionId: req.keymasterSession.id }
        });
        return row;
      });

      if (!revoked) return sendError(res, 404, "NOT_FOUND", "Dispositivo ativo não encontrado.");
      res.json({ ok: true, device: revoked });
    } catch (error) {
      next(error);
    }
  });
}
