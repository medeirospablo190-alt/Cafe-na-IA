import { API_URL } from "./config";
import type { DeviceIdentity } from "./device";

export type AccountRole = "ADM" | "DEV";
export type AccountStatus = "ACTIVE" | "LOCKED_SECURITY" | "SUSPENDED" | "DELETED";
export type CriticalAction =
  | "APP1_RESTART"
  | "APP1_MAINTENANCE_ON"
  | "APP1_MAINTENANCE_OFF"
  | "DELETE_APP1_ACCOUNT"
  | "DELETE_MANAGED_MENU"
  | "UNLOCK_APP1_ACCOUNT"
  | "AUTHORIZE_APP1_DEVICE"
  | "REVOKE_APP1_DEVICE"
  | "ROTATE_APP1_CREDENTIAL"
  | "REVEAL_APP1_CREDENTIAL";

export type Account = {
  id: string;
  name: string;
  role: AccountRole;
  status: AccountStatus;
  credential_recoverable?: boolean;
  created_at?: string;
  updated_at?: string;
  active_sessions?: number;
  last_session_at?: string | null;
};

export type AccountSession = {
  id: string;
  device_label: string | null;
  created_at: string;
  expires_at: string;
  revoked_at: string | null;
  active: boolean;
};

export type AccountSecurityDevice = {
  id: string;
  platform: string;
  deviceLabel: string | null;
  deviceHint: string | null;
  isPrimary: boolean;
  status: "ACTIVE" | "REVOKED";
  authorizedAt: string;
  lastSeenAt: string;
  revokedAt: string | null;
  networkHint: string | null;
};

export type AccountLoginAttempt = {
  id: string;
  credentialHint: string | null;
  deviceHint: string | null;
  networkHint: string | null;
  platform: string | null;
  result: string;
  integrityVerified: boolean;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type DeviceEnrollment = {
  id: string;
  status: "PENDING" | "CONSUMED" | "EXPIRED" | "CANCELLED";
  created_at: string;
  expires_at: string;
  consumed_at: string | null;
  cancelled_at: string | null;
};

export type AccountSecurity = {
  account: {
    id: string;
    name: string;
    role: AccountRole;
    status: AccountStatus;
    failed_login_attempts: number;
    failed_device_attempts: number;
    security_locked_at: string | null;
    security_lock_reason: string | null;
    created_at: string;
    updated_at: string;
  };
  devices: AccountSecurityDevice[];
  attempts: AccountLoginAttempt[];
  enrollments: DeviceEnrollment[];
};

export type Dashboard = {
  app1Maintenance: boolean;
  accounts: {
    total: number;
    active: number;
    suspended: number;
    adm: number;
    dev: number;
  };
  activeSessions: number;
  auditEvents24h: number;
};

export type AuditEvent = {
  id: string;
  actor_kind: string;
  actor_id: string | null;
  actor_name: string | null;
  action: string;
  target_kind: string | null;
  target_id: string | null;
  target_name: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type ManagedMenuStatus = "ACTIVE" | "SUSPENDED" | "DELETED";
export type MenuKeyKind = "FREE" | "VIP";
export type MenuKeyStatus = "ACTIVE" | "SUSPENDED" | "REVOKED";

export type ManagedMenu = {
  id: string;
  public_id: string;
  name: string;
  source_url: string;
  status: ManagedMenuStatus;
  created_at: string;
  updated_at: string;
  free_keys: number;
  vip_keys: number;
  active_accesses: number;
  accesses_month: number;
  loader_url: string;
  access_url?: string;
};

export type MenuAccessKey = {
  id: string;
  kind: MenuKeyKind;
  status: MenuKeyStatus;
  key_hint: string;
  note: string | null;
  expires_at: string | null;
  suspended_at?: string | null;
  use_count?: number;
  last_used_at?: string | null;
  created_at: string;
  updated_at: string;
  revoked_at: string | null;
  usable?: boolean;
};

export type MenuAccessSession = {
  id: string;
  menu_key_id: string;
  key_kind: MenuKeyKind;
  key_hint: string;
  key_note: string | null;
  client_label: string | null;
  created_at: string;
  expires_at: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  key_expires_at: string | null;
  active: boolean;
};

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code: string,
    public details: Record<string, unknown> = {}
  ) {
    super(message);
  }
}

const API_TIMEOUT_MS = 45_000;

async function request<T>(path: string, init: RequestInit = {}, session?: string): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  let response: Response;

  try {
    response = await fetch(`${API_URL}${path}`, {
      ...init,
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        ...(session ? { authorization: `Bearer ${session}` } : {}),
        ...(init.headers || {})
      }
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new ApiError(
        "O servidor demorou demais para responder. Verifique sua conexão e tente novamente.",
        0,
        "NETWORK_TIMEOUT"
      );
    }
    throw new ApiError(
      error instanceof Error ? error.message : "Não foi possível conectar ao servidor.",
      0,
      "NETWORK_ERROR"
    );
  } finally {
    clearTimeout(timeout);
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new ApiError(
      String(data?.message || `HTTP ${response.status}`),
      response.status,
      String(data?.code || "HTTP_ERROR"),
      data
    );
  }
  return data as T;
}

function queryString(values: Record<string, string | undefined>) {
  const parts = Object.entries(values)
    .filter(([, value]) => Boolean(value))
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
  return parts.length ? `?${parts.join("&")}` : "";
}

export async function loginKeymaster(accessKey: string, device: DeviceIdentity) {
  return request<{
    ok: true;
    token: string;
    expiresAt: string;
    integrityVerified: boolean;
  }>("/v1/keymaster/login", {
    method: "POST",
    body: JSON.stringify({ accessKey, ...device })
  });
}

export async function validateKeymasterSession(session: string) {
  return request<{
    ok: true;
    session: { id: string; expiresAt: string; deviceId: number };
  }>("/v1/keymaster/session", {}, session);
}

export async function logoutKeymaster(session: string) {
  return request<{ ok: true }>("/v1/keymaster/logout", { method: "POST", body: "{}" }, session);
}

export async function getSystemStatus(session: string) {
  return request<{ ok: true; app1Maintenance: boolean }>("/v1/keymaster/system-status", {}, session);
}

export async function getDashboard(session: string) {
  return request<{ ok: true; dashboard: Dashboard }>("/v1/keymaster/dashboard", {}, session);
}

export async function listAccounts(
  session: string,
  filters: { q?: string; role?: AccountRole; status?: Exclude<AccountStatus, "DELETED"> } = {}
) {
  const qs = queryString({ q: filters.q?.trim(), role: filters.role, status: filters.status });
  return request<{ ok: true; accounts: Account[] }>(`/v1/keymaster/accounts${qs}`, {}, session);
}

export async function createAccount(
  session: string,
  displayName: string,
  login: string,
  role: AccountRole
) {
  return request<{
    ok: true;
    account: Account;
    privateLogin: string;
    credential: string;
    credentialLength: number;
  }>("/v1/keymaster/accounts", {
    method: "POST",
    body: JSON.stringify({ displayName, login, role })
  }, session);
}

export async function setAccountState(session: string, accountId: string, action: "suspend" | "restore") {
  return request<{ ok: true }>(`/v1/keymaster/accounts/${encodeURIComponent(accountId)}/${action}`, {
    method: "POST",
    body: "{}"
  }, session);
}

export async function rotateCredential(
  session: string,
  accountId: string,
  authorizationToken: string
) {
  return request<{ ok: true; privateLogin: string; credential: string; credentialLength: number }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/rotate`,
    {
      method: "POST",
      headers: { "x-critical-authorization": authorizationToken },
      body: "{}"
    },
    session
  );
}

export async function revealAccountCredential(
  session: string,
  accountId: string,
  authorizationToken: string
) {
  return request<{ ok: true; privateLogin: string; credential: string }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/credential/reveal`,
    {
      method: "POST",
      headers: { "x-critical-authorization": authorizationToken },
      body: "{}"
    },
    session
  );
}

export async function listAccountSessions(session: string, accountId: string) {
  return request<{ ok: true; sessions: AccountSession[] }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/sessions`,
    {},
    session
  );
}

export async function revokeAccountSession(session: string, accountId: string, sessionId: string) {
  return request<{ ok: true; revoked: boolean }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/sessions/${encodeURIComponent(sessionId)}/revoke`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function revokeAllAccountSessions(session: string, accountId: string) {
  return request<{ ok: true; revokedCount: number }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/sessions/revoke-all`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function getAccountSecurity(session: string, accountId: string) {
  return request<{ ok: true } & AccountSecurity>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/security`,
    {},
    session
  );
}

export async function unlockAccountSecurity(
  session: string,
  accountId: string,
  authorizationToken: string
) {
  return request<{ ok: true; account: Account }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/security/unlock`,
    {
      method: "POST",
      headers: { "x-critical-authorization": authorizationToken },
      body: "{}"
    },
    session
  );
}

export async function openDeviceEnrollment(
  session: string,
  accountId: string,
  authorizationToken: string
) {
  return request<{ ok: true; enrollment: DeviceEnrollment }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/device-enrollment`,
    {
      method: "POST",
      headers: { "x-critical-authorization": authorizationToken },
      body: "{}"
    },
    session
  );
}

export async function cancelDeviceEnrollment(session: string, accountId: string) {
  return request<{ ok: true; cancelledCount: number }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/device-enrollment/cancel`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function revokeApp1Device(
  session: string,
  accountId: string,
  deviceId: string,
  authorizationToken: string
) {
  return request<{ ok: true; device: { id: string; platform: string; device_label: string | null } }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/devices/${encodeURIComponent(deviceId)}/revoke`,
    {
      method: "POST",
      headers: { "x-critical-authorization": authorizationToken },
      body: "{}"
    },
    session
  );
}

export async function listAudit(session: string, before?: string) {
  const qs = queryString({ limit: "40", before });
  return request<{ ok: true; events: AuditEvent[]; nextBefore: string | null }>(
    `/v1/keymaster/audit${qs}`,
    {},
    session
  );
}

export async function listManagedMenus(
  session: string,
  filters: { q?: string; status?: Exclude<ManagedMenuStatus, "DELETED"> } = {}
) {
  const qs = queryString({ q: filters.q?.trim(), status: filters.status });
  return request<{ ok: true; menus: ManagedMenu[] }>(`/v1/keymaster/menus${qs}`, {}, session);
}

export async function createManagedMenu(session: string, name: string, sourceUrl: string) {
  return request<{ ok: true; menu: ManagedMenu }>("/v1/keymaster/menus", {
    method: "POST",
    body: JSON.stringify({ name, sourceUrl })
  }, session);
}

export async function updateManagedMenu(
  session: string,
  menuId: string,
  values: { name?: string; sourceUrl?: string }
) {
  return request<{ ok: true; menu: ManagedMenu }>(`/v1/keymaster/menus/${encodeURIComponent(menuId)}`, {
    method: "PATCH",
    body: JSON.stringify(values)
  }, session);
}

export async function setManagedMenuState(session: string, menuId: string, action: "suspend" | "restore") {
  return request<{ ok: true; menu: ManagedMenu }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}/state/${action}`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function deleteManagedMenu(
  session: string,
  menuId: string,
  authorizationToken: string
) {
  return request<{ ok: true; revokedKeys: number; revokedSessions: number }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}`,
    {
      method: "DELETE",
      headers: { "x-critical-authorization": authorizationToken }
    },
    session
  );
}

export async function listMenuAccessKeys(session: string, menuId: string) {
  return request<{ ok: true; keys: MenuAccessKey[] }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}/keys`,
    {},
    session
  );
}

export async function createMenuAccessKey(
  session: string,
  menuId: string,
  values: { kind: MenuKeyKind; durationHours?: number; note?: string }
) {
  return request<{
    ok: true;
    key: MenuAccessKey & { value: string; revealOnce: true };
  }>(`/v1/keymaster/menus/${encodeURIComponent(menuId)}/keys`, {
    method: "POST",
    body: JSON.stringify(values)
  }, session);
}

export async function setMenuAccessKeyState(
  session: string,
  keyId: string,
  action: "suspend" | "restore" | "revoke" | "permanent"
) {
  return request<{ ok: true; key: MenuAccessKey }>(
    `/v1/keymaster/menu-keys/${encodeURIComponent(keyId)}/state/${action}`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function setMenuAccessKeyDuration(session: string, keyId: string, durationHours: number) {
  return request<{ ok: true; key: MenuAccessKey }>(
    `/v1/keymaster/menu-keys/${encodeURIComponent(keyId)}/duration`,
    { method: "POST", body: JSON.stringify({ durationHours }) },
    session
  );
}

export async function listMenuAccessSessions(session: string, menuId: string) {
  return request<{ ok: true; sessions: MenuAccessSession[] }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}/access-sessions`,
    {},
    session
  );
}

export async function revokeMenuAccessSession(session: string, accessSessionId: string) {
  return request<{ ok: true; revoked: boolean }>(
    `/v1/keymaster/menu-access-sessions/${encodeURIComponent(accessSessionId)}/revoke`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function revokeAllMenuAccessSessions(session: string, menuId: string) {
  return request<{ ok: true; revokedCount: number }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}/access-sessions/revoke-all`,
    { method: "POST", body: "{}" },
    session
  );
}

export async function authorizeCriticalAction(
  session: string,
  action: CriticalAction,
  devLogin: string,
  devCredential: string,
  targetId?: string
) {
  return request<{
    ok: true;
    authorizationToken: string;
    expiresAt: string;
    scope: string;
    dev: { id: string; name: string };
  }>("/v1/keymaster/critical/authorize", {
    method: "POST",
    body: JSON.stringify({ action, devLogin, devCredential, ...(targetId ? { targetId } : {}) })
  }, session);
}

type SystemCriticalAction =
  | "APP1_RESTART"
  | "APP1_MAINTENANCE_ON"
  | "APP1_MAINTENANCE_OFF";

export async function executeCriticalAction(
  session: string,
  action: SystemCriticalAction,
  authorizationToken: string
) {
  return request<{ ok: true; action: string; app1Maintenance?: boolean }>("/v1/keymaster/critical/execute", {
    method: "POST",
    body: JSON.stringify({ action, authorizationToken })
  }, session);
}

export async function deleteAccount(
  session: string,
  accountId: string,
  authorizationToken: string
) {
  return request<{ ok: true }>(`/v1/keymaster/accounts/${encodeURIComponent(accountId)}`, {
    method: "DELETE",
    headers: { "x-critical-authorization": authorizationToken }
  }, session);
}
