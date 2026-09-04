import { App1ApiError } from "./api";
import { requireApiUrl } from "./config";

export type App1MenuKeyKind = "FREE" | "VIP";
export type App1MenuKeyStatus = "ACTIVE" | "SUSPENDED" | "REVOKED" | "EXPIRED" | "MENU_SUSPENDED";

export type App1MenuKey = {
  bindingId: string;
  keyId: string;
  kind: App1MenuKeyKind;
  status: App1MenuKeyStatus;
  usable: boolean;
  keyHint: string;
  note: string | null;
  expiresAt: string | null;
  useCount: number;
  lastUsedAt: string | null;
  addedAt: string;
  lastRevealedAt: string | null;
  menu: {
    id: string;
    publicId: string;
    name: string;
    status: string;
    accessUrl: string;
  };
};

const API_TIMEOUT_MS = 45_000;

function authHeaders(sessionToken: string, deviceToken: string) {
  return {
    authorization: `Bearer ${sessionToken}`,
    "x-app1-device-token": deviceToken
  };
}

async function request<T>(path: string, sessionToken: string, deviceToken: string, init: RequestInit = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const response = await fetch(`${requireApiUrl()}${path}`, {
      ...init,
      signal: controller.signal,
      headers: {
        ...authHeaders(sessionToken, deviceToken),
        ...(init.body !== undefined ? { "content-type": "application/json" } : {}),
        ...(init.headers || {})
      }
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new App1ApiError(
        String(data?.message || `HTTP ${response.status}`),
        response.status,
        String(data?.code || "HTTP_ERROR")
      );
    }
    return data as T;
  } catch (error) {
    if (error instanceof App1ApiError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new App1ApiError("O servidor demorou demais para responder.", 0, "NETWORK_TIMEOUT");
    }
    throw new App1ApiError(
      error instanceof Error ? error.message : "Não foi possível conectar ao servidor.",
      0,
      "NETWORK_ERROR"
    );
  } finally {
    clearTimeout(timer);
  }
}

export function listApp1MenuKeys(sessionToken: string, deviceToken: string) {
  return request<{ ok: true; keys: App1MenuKey[] }>("/v1/app1/keys", sessionToken, deviceToken);
}

export function claimApp1MenuKey(
  sessionToken: string,
  deviceToken: string,
  input: { menuId: string; key: string }
) {
  return request<{ ok: true; created: boolean; key: App1MenuKey }>(
    "/v1/app1/keys/claim",
    sessionToken,
    deviceToken,
    { method: "POST", body: JSON.stringify(input) }
  );
}

export function revealApp1MenuKey(sessionToken: string, deviceToken: string, bindingId: string) {
  return request<{ ok: true; key: string; keyHint: string }>(
    `/v1/app1/keys/${encodeURIComponent(bindingId)}/reveal`,
    sessionToken,
    deviceToken,
    { method: "POST", body: "{}" }
  );
}

export function removeApp1MenuKey(sessionToken: string, deviceToken: string, bindingId: string) {
  return request<{ ok: true }>(
    `/v1/app1/keys/${encodeURIComponent(bindingId)}`,
    sessionToken,
    deviceToken,
    { method: "DELETE" }
  );
}
