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

export async function listAccounts(session: string) {
  return request<{ ok: true; accounts: Account[] }>("/v1/keymaster/accounts", {}, session);
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
