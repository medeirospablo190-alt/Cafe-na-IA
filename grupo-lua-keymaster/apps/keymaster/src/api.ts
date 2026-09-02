import { API_URL } from "./config";
import type { DeviceIdentity } from "./device";

export type AccountRole = "ADM" | "DEV";
export type AccountStatus = "ACTIVE" | "SUSPENDED" | "DELETED";
export type CriticalAction =
  | "APP1_RESTART"
  | "APP1_MAINTENANCE_ON"
  | "APP1_MAINTENANCE_OFF"
  | "DELETE_APP1_ACCOUNT";

export type Account = {
  id: string;
  login: string;
  role: AccountRole;
  status: AccountStatus;
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
  actor_login: string | null;
  action: string;
  target_kind: string | null;
  target_id: string | null;
  target_login: string | null;
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
};

export type MenuAccessKey = {
  id: string;
  kind: MenuKeyKind;
  status: MenuKeyStatus;
  key_hint: string;
  note: string | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
  revoked_at: string | null;
  usable?: boolean;
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

async function request<T>(path: string, init: RequestInit = {}, session?: string): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(session ? { authorization: `Bearer ${session}` } : {}),
      ...(init.headers || {})
    }
  });
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

export async function createAccount(session: string, login: string, role: AccountRole) {
  return request<{
    ok: true;
    account: Account;
    credential: string;
    credentialLength: number;
    revealOnce: true;
  }>("/v1/keymaster/accounts", {
    method: "POST",
    body: JSON.stringify({ login, role })
  }, session);
}

export async function setAccountState(session: string, accountId: string, action: "suspend" | "restore") {
  return request<{ ok: true }>(`/v1/keymaster/accounts/${encodeURIComponent(accountId)}/${action}`, {
    method: "POST",
    body: "{}"
  }, session);
}

export async function rotateCredential(session: string, accountId: string) {
  return request<{ ok: true; credential: string; credentialLength: number; revealOnce: true }>(
    `/v1/keymaster/accounts/${encodeURIComponent(accountId)}/rotate`,
    { method: "POST", body: "{}" },
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

export async function updateManagedMenu(session: string, menuId: string, values: { name?: string; sourceUrl?: string }) {
  return request<{ ok: true; menu: ManagedMenu }>(`/v1/keymaster/menus/${encodeURIComponent(menuId)}`, {
    method: "PATCH",
    body: JSON.stringify(values)
  }, session);
}

export async function setManagedMenuState(session: string, menuId: string, action: "suspend" | "restore") {
  return request<{ ok: true; menu: ManagedMenu }>(
    `/v1/keymaster/menus/${encodeURIComponent(menuId)}/${action}`,
    { method: "POST", body: "{}" },
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
    `/v1/keymaster/menu-keys/${encodeURIComponent(keyId)}/${action}`,
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
    dev: { id: string; login: string };
  }>("/v1/keymaster/critical/authorize", {
    method: "POST",
    body: JSON.stringify({ action, devLogin, devCredential, ...(targetId ? { targetId } : {}) })
  }, session);
}

export async function executeCriticalAction(
  session: string,
  action: Exclude<CriticalAction, "DELETE_APP1_ACCOUNT">,
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
