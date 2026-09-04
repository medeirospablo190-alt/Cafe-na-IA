import crypto from "node:crypto";
import { pool } from "./db.js";
import { tokenHash } from "./security.js";

export function sendApp1FeatureError(res, status, code, message, extra = {}) {
  return res.status(status).json({ ok: false, code, message, ...extra });
}

function safeEqualText(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

export async function getApp1FullSession(req) {
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
       a.status AS account_status,
       a.public_profile_id,
       a.public_name,
       a.role,
       a.bio,
       a.status_text,
       a.avatar_style,
       a.frame_style,
       a.presence_mode,
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
  if (
    !row ||
    row.account_status !== "ACTIVE" ||
    row.device_status !== "ACTIVE" ||
    row.session_kind !== "FULL"
  ) return null;

  const supplied = tokenHash(`app1-device:${deviceToken}`);
  return safeEqualText(supplied, row.device_token_hash) ? row : null;
}

export async function requireApp1FullSession(req, res, next) {
  try {
    const session = await getApp1FullSession(req);
    if (!session) {
      return sendApp1FeatureError(
        res,
        401,
        "UNAUTHORIZED",
        "Sessão FULL inválida, expirada ou incompatível com este dispositivo."
      );
    }
    req.app1FeatureSession = session;
    next();
  } catch (error) {
    next(error);
  }
}

export function publicProfileFromRow(row) {
  return {
    profileId: row.public_profile_id || null,
    publicName: row.public_name || "Perfil",
    role: row.role === "DEV" ? "DEV" : "ADM",
    bio: row.bio || "",
    statusText: row.status_text || "",
    avatarStyle: row.avatar_style || "MOON",
    frameStyle: row.frame_style || "DEFAULT",
    presenceMode: row.presence_mode || "VISIBLE"
  };
}
