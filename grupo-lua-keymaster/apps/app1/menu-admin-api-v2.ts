import { App1ApiError } from "./api";
import { requireApiUrl } from "./config";

export type MenuSourceKind = "REMOTE_URL" | "INLINE_ENCRYPTED";
export type MenuStatus = "ACTIVE" | "SUSPENDED";
export type MenuOrder = "RECENT" | "OLD";
export type KeyKindFilter = "ALL" | "FREE" | "VIP";
export type MenuKeyKindV2 = "FREE" | "VIP";
export type MenuKeyDurationUnitV2 = "HOURS" | "DAYS" | "MONTHS" | "PERMANENT";
export type MenuKeyAccessStateV2 = "READY" | "ACTIVE" | "WAITING_ADMIN" | "EXPIRED";

export type ManagedMenuV2 = {
  id: string;
  public_id: string;
  name: string;
  status: MenuStatus;
  source_kind: MenuSourceKind;
  suspended_until: string | null;
  key_count: number;
  free_key_count: number;
  vip_key_count: number;
  active_access_count: number;
  legacy_unowned: boolean;
  created_at: string;
  updated_at: string;
};

export type MenuSourceV2 = {
  sourceKind: MenuSourceKind;
  sourceCode: string | null;
  sourceUrl: string | null;
};

export type MenuKeyV2 = {
  id: string;
  menu_id: string;
  name: string;
  kind: MenuKeyKindV2;
  status: "ACTIVE" | "SUSPENDED" | "REVOKED";
  key_hint: string;
  note: string | null;
  access_state: MenuKeyAccessStateV2;
  duration_value: number | null;
  duration_unit: MenuKeyDurationUnitV2 | null;
  access_started_at: string | null;
  access_until: string | null;
  bound_device: boolean;
  bound_device_hint: string | null;
  use_count: number;
  last_used_at: string | null;
  created_at: string;
  updated_at: string;
  revoked_at: string | null;
  can_reveal: boolean;
  usable: boolean;
};

const TIMEOUT_MS = 45_000;

function authHeaders(sessionToken: string, deviceToken: string) {
  return {
    authorization: `Bearer ${sessionToken}`,
    "x-app1-device-token": deviceToken
  };
}

async function request<T>(path: string, sessionToken: string, deviceToken: string, init: RequestInit = {}): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${requireApiUrl()}${path}`, {
      ...init,
      headers: {
        accept: "application/json",
        ...authHeaders(sessionToken, deviceToken),
        ...(init.headers || {})
      },
      signal: controller.signal
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
    throw new App1ApiError(error instanceof Error ? error.message : "Falha de conexão.", 0, "NETWORK_ERROR");
  } finally {
    clearTimeout(timeout);
  }
}

function jsonInit(method: string, body?: unknown): RequestInit {
  return {
    method,
    headers: { "content-type": "application/json" },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  };
}

export async function listManagedMenusV2(
  sessionToken: string,
  deviceToken: string,
  options: { q?: string; status?: MenuStatus | ""; order?: MenuOrder } = {}
) {
  const params = new URLSearchParams();
  if (options.q?.trim()) params.set("q", options.q.trim());
  if (options.status) params.set("status", options.status);
  if (options.order) params.set("order", options.order);
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return request<{ ok: true; menus: ManagedMenuV2[] }>(`/v1/app1/menu-admin/menus${suffix}`, sessionToken, deviceToken);
}

export async function createManagedMenuV2(
  sessionToken: string,
  deviceToken: string,
  input: { name: string; sourceCode?: string; sourceUrl?: string }
) {
  return request<{ ok: true; menu: ManagedMenuV2 }>(
    "/v1/app1/menu-admin/menus",
    sessionToken,
    deviceToken,
    jsonInit("POST", input)
  );
}

export async function getManagedMenuSourceV2(sessionToken: string, deviceToken: string, menuId: string) {
  return request<{ ok: true } & MenuSourceV2>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/source`,
    sessionToken,
    deviceToken
  );
}

export async function updateManagedMenuV2(
  sessionToken: string,
  deviceToken: string,
  menuId: string,
  input: { name?: string; sourceCode?: string; sourceUrl?: string }
) {
  return request<{ ok: true; menu: ManagedMenuV2 }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}`,
    sessionToken,
    deviceToken,
    jsonInit("PATCH", input)
  );
}

export async function setManagedMenuStateV2(
  sessionToken: string,
  deviceToken: string,
  menuId: string,
  action: "suspend" | "restore",
  durationMinutes?: number
) {
  return request<{ ok: true; menu: ManagedMenuV2 }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/state/${action}`,
    sessionToken,
    deviceToken,
    jsonInit("POST", durationMinutes == null ? {} : { durationMinutes })
  );
}

export async function claimLegacyMenuV2(sessionToken: string, deviceToken: string, menuId: string) {
  return request<{ ok: true; menu: ManagedMenuV2; unchanged: boolean }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/claim`,
    sessionToken,
    deviceToken,
    jsonInit("POST", {})
  );
}

export async function deleteManagedMenuV2(sessionToken: string, deviceToken: string, menuId: string) {
  return request<{ ok: true; revokedKeys: number; revokedSessions: number }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}`,
    sessionToken,
    deviceToken,
    { method: "DELETE" }
  );
}

export async function listMenuKeysV2(
  sessionToken: string,
  deviceToken: string,
  menuId: string,
  options: { q?: string; kind?: KeyKindFilter; order?: MenuOrder } = {}
) {
  const params = new URLSearchParams();
  if (options.q?.trim()) params.set("q", options.q.trim());
  if (options.kind && options.kind !== "ALL") params.set("kind", options.kind);
  if (options.order) params.set("order", options.order);
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return request<{ ok: true; keys: MenuKeyV2[] }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/keys${suffix}`,
    sessionToken,
    deviceToken
  );
}

export async function createMenuKeyV2(
  sessionToken: string,
  deviceToken: string,
  menuId: string,
  input: {
    name: string;
    kind: MenuKeyKindV2;
    durationValue?: number;
    durationUnit?: "DAYS" | "MONTHS" | "PERMANENT";
    note?: string;
  }
) {
  return request<{ ok: true; key: MenuKeyV2 & { value: string; revealOnce: false } }>(
    `/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/keys`,
    sessionToken,
    deviceToken,
    jsonInit("POST", input)
  );
}

export async function revealMenuKeyV2(sessionToken: string, deviceToken: string, keyId: string) {
  return request<{ ok: true; key: { id: string; name: string; kind: MenuKeyKindV2; key_hint: string; value: string } }>(
    `/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/reveal`,
    sessionToken,
    deviceToken,
    jsonInit("POST", {})
  );
}

export async function releaseFreeKeyV2(sessionToken: string, deviceToken: string, keyId: string, durationHours: number) {
  return request<{ ok: true; key: MenuKeyV2 }>(
    `/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/release-free`,
    sessionToken,
    deviceToken,
    jsonInit("POST", { durationHours })
  );
}

export async function configureVipKeyV2(
  sessionToken: string,
  deviceToken: string,
  keyId: string,
  durationUnit: "DAYS" | "MONTHS" | "PERMANENT",
  durationValue?: number
) {
  return request<{ ok: true; key: MenuKeyV2 }>(
    `/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/configure-vip`,
    sessionToken,
    deviceToken,
    jsonInit("POST", { durationUnit, durationValue })
  );
}

export async function resetMenuKeyDeviceV2(sessionToken: string, deviceToken: string, keyId: string) {
  return request<{ ok: true; key: MenuKeyV2 }>(
    `/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/reset-device`,
    sessionToken,
    deviceToken,
    jsonInit("POST", {})
  );
}

export async function deleteMenuKeyV2(sessionToken: string, deviceToken: string, keyId: string) {
  return request<{ ok: true; revokedSessions: number }>(
    `/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}`,
    sessionToken,
    deviceToken,
    { method: "DELETE" }
  );
}
